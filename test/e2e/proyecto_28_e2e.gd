# =============================================================================
# FASE B · ENCARGO 28 — Script avanzado (automatización) (modo Pro)
# Foco: API de script, errores controlados.
# Un script genera un CALENDARIO 2027 en una página A3 apaisada: 12 tablas
# mensuales (add_table) en rejilla 4 × 3, días calculados, domingos en rojo
# (color global), títulos con estilo de texto, todo agrupado. Es UN paso de
# deshacer. Después: un script que falla a mitad (tras crear 60 objetos)
# se deshace entero y da la línea exacta; api.error() aborta y deshace;
# errores de sintaxis con su línea; un complemento registra una acción
# «Numerar páginas» y se ejecuta; reabrir conserva lo generado.
#   test/run_e2e.sh proyecto_28_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/28"
var Runner   # se carga tras el arranque (depende de los autoloads)
var K
var api

const CALENDAR := """extends VectopenScript
const MESES := ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]

func dias_mes(m: int, y: int) -> int:
	if m == 2:
		return 29 if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0 else 28
	return 30 if m in [4, 6, 9, 11] else 31

## 0 = lunes … 6 = domingo (Zeller)
func dia_semana(d: int, m: int, y: int) -> int:
	var t := [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	if m < 3:
		y -= 1
	var w: int = (y + y / 4 - y / 100 + y / 400 + int(t[m - 1]) + d) % 7   # 0 = domingo
	return (w + 6) % 7

func run() -> void:
	var y := 2027
	var rojo := api.add_global_color("Domingo", Color("#d62828"))
	var st := api.add_text_style("Mes", {"font_size": 26, "font_weight": 700, "fill_color": Color("#1d3557")})
	var meses: Array = []
	for m in range(1, 13):
		var col := (m - 1) % 4
		var fila := (m - 1) / 4
		var x := 60.0 + col * 390.0
		var yy := 80.0 + fila * 360.0
		var titulo := api.add_text(Vector2(x, yy), MESES[m - 1], 26, Color.BLACK)
		titulo.name = "Mes " + MESES[m - 1]
		api.apply_text_style(st, [titulo])
		var datos := [["L", "M", "X", "J", "V", "S", "D"]]
		var semana := ["", "", "", "", "", "", ""]
		var w0 := dia_semana(1, m, y)
		for d in range(1, dias_mes(m, y) + 1):
			var wd := (w0 + d - 1) % 7
			semana[wd] = str(d)
			if wd == 6 or d == dias_mes(m, y):
				datos.append(semana)
				semana = ["", "", "", "", "", "", ""]
		var t := api.add_table(Rect2(x, yy + 44, 350, 0), datos.size(), 7, datos,
			{"row_h": 36.0, "font_size": 14, "align": ["center", "center", "center", "center", "center", "center", "center"], "zebra": false})
		t.name = "Tabla " + MESES[m - 1]
		meses.append(api.group([titulo, t], MESES[m - 1]))
	api.group(meses, "Calendario " + str(y))
	print("meses: ", meses.size())
"""

func _init() -> void:
	_run.call_deferred()
	create_timer(560.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func count() -> int:
	return K.count_shapes(api.artboard())

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("professional"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	Runner = load("res://script_gdscript/api/script_runner.gd")
	var ab: Node2D = await K.artboard(Vector2(1640, 1160), "Calendario", Color.WHITE)
	K.hm.clear()
	# ── 1. El calendario por script ──────────────────────────────────────────
	K.check("el script no tiene errores de sintaxis", Runner.check(CALENDAR).is_empty(), str(Runner.check(CALENDAR)))
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = await Runner.run(CALENDAR, api, "Calendario 2027")
	K.note("calendario_ms", Time.get_ticks_msec() - t0)
	K.check("el calendario se genera sin errores", res["ok"], str(res.get("errors", [])))
	K.check("la salida del script llega (print)", "meses: 12" in str(res.get("output", "")), str(res.get("output", "")))
	var cal: Node = ab.find_child("Calendario 2027", false, false)
	K.check("un grupo con los 12 meses", cal != null and cal.get_child_count() == 12, str(cal.get_child_count()) if cal else "-")
	var feb: Node = cal.find_child("Tabla Febrero", true, false) if cal else null
	var febdata: Array = api.table_data(feb) if feb else []
	var last_feb := ""
	for row in febdata:
		for c in row:
			if String(c) != "" and String(c).is_valid_int():
				last_feb = String(c)
	K.check("febrero de 2027 tiene 28 días", last_feb == "28", last_feb)
	var ene: Node = cal.find_child("Tabla Enero", true, false) if cal else null
	K.check("el 1 de enero de 2027 cae en viernes", ene != null and String(api.table_data(ene)[1][4]) == "1", str(api.table_data(ene)[1]) if ene else "-")
	K.check("estilo «Mes» y color global «Domingo» creados", api.text_styles().any(func(s) -> bool: return s["name"] == "Mes") and api.global_colors().any(func(c) -> bool: return c["name"] == "Domingo"))
	K.check("todo el script = UN paso de deshacer", K.hm.get_undo_name() == "Calendario 2027")
	var n_cal := count()
	K.hm.undo()
	await K.frames(3)
	K.check("deshacer quita el calendario entero", ab.find_child("Calendario 2027", false, false) == null)
	K.hm.redo()
	await K.frames(3)
	K.check("rehacer lo devuelve", count() == n_cal, "%d / %d" % [count(), n_cal])
	await K.look_at(ab)
	await K.shot("01_calendario")
	# ── 2. Error a mitad: se deshace TODO y se informa la línea ──────────────
	var n0 := count()
	var bad := "extends VectopenScript\nfunc run() -> void:\n\tfor i in 60:\n\t\tapi.add_ellipse(Vector2(100 + i * 5, 900), Vector2(8, 8))\n\tvar lista: Array = []\n\tprint(lista[3])\n"
	var r2: Dictionary = await Runner.run(bad, api, "Script roto")
	K.check("el error en ejecución se detecta", not r2["ok"])
	K.check("…con su línea (6)", not (r2["errors"] as Array).is_empty() and int(r2["errors"][0]["line"]) == 6, str(r2["errors"]))
	K.check("…y los 60 objetos creados se deshacen", count() == n0, "%d vs %d" % [count(), n0])
	K.check("…sin dejar transacciones abiertas", not api.in_transaction())
	# api.error() aborta y deshace
	var r3: Dictionary = await Runner.run("extends VectopenScript\nfunc run() -> void:\n\tapi.add_rect(Vector2(50, 50), Vector2(20, 20))\n\tif api.artboard_size().x > 100:\n\t\tapi.error(\"Página demasiado grande\")\n", api, "Con error()")
	K.check("api.error() marca el script como fallido y lo deshace", not r3["ok"] and count() == n0, str(r3.get("errors", [])))
	# Sintaxis
	var errs: Array = Runner.check("for i in 3\n\tapi.add_rect(Vector2.ZERO, Vector2.ONE)\n")
	K.check("error de sintaxis con su línea (1)", not errs.is_empty() and int(errs[0]["line"]) == 1, str(errs))
	# ── 3. Complemento: una acción registrada ────────────────────────────────
	var numerar := func() -> void:
		var i := 0
		for a in api.artboards():
			i += 1
			api.set_active_artboard(a)
			var t = api.add_text(Vector2(20, 20), "Pág. %d" % i, 14, Color.GRAY)
			t.name = "Número de página"
	api.register_operator("test.numerar", "Numerar páginas", numerar, "Pone el número en cada página", "test")
	var ok_op: bool = api.run_operator("test.numerar")
	K.check("acción de complemento registrada y ejecutada", ok_op and ab.find_child("Número de página", false, false) != null)
	api.unregister_operator("test.numerar")
	await K.undo_redo(2)   # calendario (1 paso) + numerar páginas; los scripts fallidos no dejan pasos
	var abs: Array = await K.save_reload("calendario")
	for a in abs:
		if String(a.name) == "Calendario":
			var c2: Node = a.find_child("Calendario 2027", false, false)
			K.check("reabrir: el calendario con sus 12 meses", c2 != null and c2.get_child_count() == 12)
			var dic: Node = c2.find_child("Tabla Diciembre", true, false) if c2 else null
			K.check("reabrir: diciembre sigue siendo una tabla editable", dic != null and dic.has_meta("table"))
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
