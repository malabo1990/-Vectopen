# =============================================================================
# FASE B · ENCARGO 16 — Diagrama técnico (modo Modern)
# Foco: trazos con puntas, guiones, etiquetas.
# Diagrama de flujo 1400 × 900: 6 cajas (componente vinculado «Nodo»),
# rombo de decisión, conectores (rectos y Bézier) con puntas de flecha de
# varios tipos, línea de retorno discontinua, etiquetas «sí / no» y un pie con
# leyenda. Cambiar la punta de todos los conectores a la vez (un deshacer),
# escalar las puntas, exportar SVG / PDF / EPS con las puntas (VAL-20) y los
# guiones, reabrir.
#   test/run_e2e.sh proyecto_16_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/16"
const INK := Color("#2b2d42")
const BLUE := Color("#4361ee")
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func connector(a: Vector2, b: Vector2, name: String, bend: float = 0.0) -> Node2D:
	var n
	if bend == 0.0:
		n = api.add_path(PackedVector2Array([a, b]), false, name)
	else:
		var c := Curve2D.new()
		var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * bend
		c.add_point(a, Vector2.ZERO, (mid - a) * 0.6)
		c.add_point(b, (mid - b) * 0.6, Vector2.ZERO)
		n = api.add_curve(c, false, name)
	api.set_props(n, {"stroke_color": INK, "stroke_width": 2.0, "stroke_pointer_end": 2})
	return n

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("modern"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(1400, 900), "Diagrama", Color.WHITE)
	# Nodo como componente: caja + texto
	var box = api.add_rect(Vector2(200, 150), Vector2(220, 90), 12.0, "Caja")
	api.set_props(box, {"fill_color": Color("#edf2fb"), "stroke_color": BLUE, "stroke_width": 2.0})
	var lbl = api.add_text(Vector2(130, 135), "Proceso", 22, INK)
	lbl.name = "Etiqueta"
	var node = api.make_symbol([box, lbl], "Nodo")
	var positions := [Vector2(200, 150), Vector2(560, 150), Vector2(920, 150), Vector2(920, 470), Vector2(560, 470), Vector2(200, 470)]
	var nodes: Array = [node]
	for i in range(1, positions.size()):
		nodes.append(api.place_symbol(api.symbol_of(node), positions[i]))
	await K.frames(3)
	api.set_symbol_sync(false)
	var names := ["Inicio", "Leer datos", "Validar", "Guardar", "Notificar", "Fin"]
	for i in nodes.size():
		api.set_prop(nodes[i].find_child("Etiqueta*", true, false), "text", names[i])
	api.sync_symbols()
	api.set_symbol_sync(true)
	K.check("6 nodos con su propio texto (retoque local del componente)",
		nodes.map(func(n) -> String: return String(api.get_prop(n.find_child("Etiqueta*", true, false), "text"))) == names)
	# Decisión: rombo
	var diamond = api.add_polygon(Vector2(1240, 310), 70, 4, 0.0, "Decisión")
	api.set_props(diamond, {"fill_color": Color("#fff3b0"), "stroke_color": INK, "stroke_width": 2.0})
	# Conectores
	var conns: Array = []
	conns.append(connector(Vector2(310, 150), Vector2(450, 150), "C1"))
	conns.append(connector(Vector2(670, 150), Vector2(810, 150), "C2"))
	conns.append(connector(Vector2(1030, 150), Vector2(1200, 260), "C3", -40.0))
	conns.append(connector(Vector2(1240, 380), Vector2(1030, 470), "C4", 40.0))
	conns.append(connector(Vector2(810, 470), Vector2(670, 470), "C5"))
	conns.append(connector(Vector2(450, 470), Vector2(310, 470), "C6"))
	var back = connector(Vector2(1300, 260), Vector2(670, 110), "Retorno", -160.0)
	api.set_props(back, {"stroke_style": 1, "stroke_dash_len": 8.0, "stroke_dash_gap": 6.0, "stroke_color": Color("#d62828"), "stroke_pointer_end": 5})
	var yes = api.add_text(Vector2(1180, 410), "sí", 18, Color("#2a9d8f"))
	yes.name = "sí"
	var no = api.add_text(Vector2(1280, 170), "no", 18, Color("#d62828"))
	no.name = "no"
	K.check("conectores con punta de flecha al final", conns.all(func(c) -> bool: return int(api.get_prop(c, "stroke_pointer_end")) == 2))
	# Cambiar la punta de todos los conectores en una acción
	K.sm.set_selection(conns)
	await K.frames(2)
	K.ic.apply_multi({"stroke_pointer_end": 5, "stroke_pointer_start": 3, "stroke_pointer_scale": 1.5}, "Puntas")
	await K.frames(2)
	K.check("puntas cambiadas en los 6 conectores a la vez",
		conns.all(func(c) -> bool: return int(api.get_prop(c, "stroke_pointer_end")) == 5 and int(api.get_prop(c, "stroke_pointer_start")) == 3))
	K.hm.undo()
	await K.frames(2)
	K.check("deshacer: un paso devuelve las puntas originales",
		conns.all(func(c) -> bool: return int(api.get_prop(c, "stroke_pointer_end")) == 2 and int(api.get_prop(c, "stroke_pointer_start")) == 0))
	K.hm.redo()
	K.sm.clear()
	# Leyenda
	var leg_line = api.add_path(PackedVector2Array([Vector2(160, 780), Vector2(260, 780)]), false, "Leyenda flujo")
	api.set_props(leg_line, {"stroke_color": INK, "stroke_width": 2.0, "stroke_pointer_end": 2})
	var leg_dash = api.add_path(PackedVector2Array([Vector2(420, 780), Vector2(520, 780)]), false, "Leyenda retorno")
	api.set_props(leg_dash, {"stroke_color": Color("#d62828"), "stroke_width": 2.0, "stroke_style": 1, "stroke_dash_len": 8.0, "stroke_dash_gap": 6.0, "stroke_pointer_end": 5})
	var t1 = api.add_text(Vector2(275, 768), "flujo principal", 16, INK)
	var t2 = api.add_text(Vector2(535, 768), "reintento", 16, INK)
	api.align([leg_line, leg_dash, t1, t2], "middle")
	await K.look_at(ab)
	await K.shot("01_diagrama")
	await K.undo_redo(20)
	# Exportar
	var ex: Dictionary = await K.export_all(ab, "diagrama")
	if ex.has("svg"):
		var svg := FileAccess.get_file_as_string(ex["svg"])
		# Cada conector: su línea + 2 puntas (inicio círculo, fin flecha afilada)
		K.check("SVG: el retorno discontinuo", svg.contains("stroke-dasharray"))
		K.check("SVG: las puntas salen como formas (≥ 6 conectores × 2)", svg.count("<path") + svg.count("<circle") + svg.count("<polygon") >= 30, "%d" % (svg.count("<path") + svg.count("<circle")))
	if ex.has("pdf"):
		var pdf := FileAccess.get_file_as_bytes(ex["pdf"]).get_string_from_ascii()
		K.check("PDF con guiones (operador d)", pdf.contains("] 0 d") or pdf.contains("] 0.0 d") or RegEx.create_from_string("\\[[0-9. ]+\\] [0-9.]+ d").search(pdf) != null)
	var abs: Array = await K.save_reload("diagrama")
	for a in abs:
		if String(a.name) == "Diagrama":
			var c1: Node = a.find_child("C1", true, false)
			K.check("reabrir: puntas de los conectores", c1 != null and int(api.get_prop(c1, "stroke_pointer_end")) == 5 and int(api.get_prop(c1, "stroke_pointer_start")) == 3)
			K.check("reabrir: escala de las puntas", c1 != null and is_equal_approx(float(api.get_prop(c1, "stroke_pointer_scale")), 1.5))
			var labels := 0
			for n in a.get_children():
				if api.symbol_of(n) != "":
					labels += 1
			K.check("reabrir: 6 nodos vinculados", labels == 6, str(labels))
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
