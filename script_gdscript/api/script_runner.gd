# =============================================================================
# RUTA: res://script_gdscript/api/script_runner.gd
# Compila y ejecuta los scripts GDScript de la pestaña Script.
#
#   · check(code)  → [{line, msg}] errores de sintaxis (vacío = correcto).
#   · run(code, api, name) (await) → {ok, errors, output, result}
#     Toda la ejecución es UN paso de deshacer; si el script FALLA a mitad,
#     lo que llegó a hacer se deshace (atómico) y se informa la línea.
#
# Modo rápido: sin `extends` se añade `extends VectopenScript`; sin ninguna
# función, todo el código se envuelve en `func run()`. Los números de línea
# de los errores se refieren SIEMPRE al texto que escribió el usuario.
# Los errores y print() se capturan con un Logger mientras corre.
# =============================================================================
extends RefCounted

const SCRIPT_PREFIX := "gdscript://"

class _Capture extends Logger:
	var errors: Array = []
	var output: PackedStringArray = []
	var offset := 0
	var _mutex := Mutex.new()

	func _log_message(msg: String, _is_error: bool) -> void:
		_mutex.lock()
		output.append(msg.trim_suffix("\n"))
		_mutex.unlock()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, backtraces: Array[ScriptBacktrace]) -> void:
		# Solo los errores del script del usuario (o que pasan por él).
		var ln := -1
		if file.begins_with(SCRIPT_PREFIX):
			ln = line
		else:
			for bt in backtraces:
				for i in bt.get_frame_count():
					if bt.get_frame_file(i).begins_with(SCRIPT_PREFIX):
						ln = bt.get_frame_line(i)
						break
				if ln >= 0:
					break
		if ln < 0:
			return
		var msg := (rationale if rationale != "" else code).trim_prefix("Parse Error: ")
		_mutex.lock()
		if error_type == Logger.ERROR_TYPE_WARNING:
			output.append("⚠ Línea %d: %s" % [maxi(1, ln - offset), msg])
		else:
			errors.append({"line": maxi(1, ln - offset), "msg": msg})
		_mutex.unlock()

## Código listo para compilar + líneas añadidas delante.
static func prepare(code: String) -> Dictionary:
	var has_extends := false
	var has_func := false
	for raw in code.split("\n"):
		var l := raw.strip_edges(false, true)
		if l.begins_with("extends ") or l.begins_with("class_name "):
			has_extends = true
		if l.begins_with("func ") or l.begins_with("static func "):
			has_func = true
	if has_extends:
		return {"code": code, "offset": 0}
	if has_func:
		return {"code": "extends VectopenScript\n" + code, "offset": 1}
	var body := PackedStringArray()
	for raw in code.split("\n"):
		body.append("\t" + raw)
	return {"code": "extends VectopenScript\nfunc run():\n" + "\n".join(body) + "\n\tpass\n", "offset": 2}

## Compila; devuelve {script, errors}.
static func compile(code: String) -> Dictionary:
	var prep := prepare(code)
	var cap := _Capture.new()
	cap.offset = int(prep["offset"])
	OS.add_logger(cap)
	var g := GDScript.new()
	g.source_code = String(prep["code"])
	var err := g.reload()
	OS.remove_logger(cap)
	var errors := cap.errors
	if err != OK and errors.is_empty():
		errors = [{"line": 1, "msg": "No compila (%s)" % error_string(err)}]
	return {"script": g if err == OK else null, "errors": errors}

## Errores de sintaxis de `code` (vacío = correcto).
static func check(code: String) -> Array:
	return compile(code)["errors"]

## Ejecuta `code` con `api`. Usar con await.
static func run(code: String, api: VectopenAPI, action_name: String = "Script") -> Dictionary:
	var res := {"ok": false, "errors": [], "output": PackedStringArray(), "result": null}
	var comp := compile(code)
	if comp["script"] == null:
		res["errors"] = comp["errors"]
		return res
	var g: GDScript = comp["script"]
	var inst: Object = g.new()
	if inst == null or not inst.has_method("run"):
		res["errors"] = [{"line": 1, "msg": "El script necesita una función run()"}]
		return res
	if "api" in inst:
		inst.set("api", api)
	var cap := _Capture.new()
	cap.offset = int(prepare(code)["offset"])
	var on_msg := func(text: String, _level: String) -> void: cap.output.append(text)
	api.message.connect(on_msg)
	OS.add_logger(cap)
	api.begin(action_name)
	var t0 := Time.get_ticks_usec()
	var result: Variant = await inst.call("run")
	var elapsed := (Time.get_ticks_usec() - t0) / 1000.0
	OS.remove_logger(cap)
	api.message.disconnect(on_msg)
	# Los print() del propio script y los de api.info() salen duplicados en el
	# Logger (api.info también hace print): se quita el eco "[Vectopen] …".
	var out := PackedStringArray()
	for l in cap.output:
		if not l.begins_with("[Vectopen] "):
			out.append(l)
	res["output"] = out
	res["errors"] = cap.errors
	res["result"] = result
	res["ms"] = elapsed
	if cap.errors.is_empty():
		api.end()
		res["ok"] = true
	else:
		api.rollback()
	return res
