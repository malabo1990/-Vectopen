# =============================================================================
# FASE B · ENCARGO 13 — Ilustración con pinceles (modo Smart)
# Foco: 300+ trazos, fluidez y memoria.
# Paisaje 1600 × 1000: cielo con trazos de rotulador, sol con aerógrafo,
# montañas caligráficas, hierba (200 trazos de lápiz), flores con pincel de
# figuras… 12 trazos dibujados DE VERDAD con la herramienta Pincel (ratón con
# presión) y el resto creados por script. Mide el coste por trazo, los
# fotogramas con todo a la vista y al hacer zoom, y la memoria; cambiar el
# grosor de 300 trazos a la vez; exportar SVG/PNG, deshacer 20, reabrir.
#   test/run_e2e.sh proyecto_13_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/13"
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(560.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		Input.warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func move(at: Vector2, held: bool, p: float) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.pressure = p if held else 0.0
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_send(mm)
	await process_frame

func btn(at: Vector2, down: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = at
	mb.global_position = at
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = down
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(mb)
	await process_frame

## Trazo real con la herramienta (coordenadas de PÁGINA → pantalla).
func tool_stroke(ab: Node2D, pts: PackedVector2Array) -> void:
	var xf: Transform2D = K.canvas.get_viewport().get_canvas_transform()
	var s: Array = []
	for p in pts:
		s.append(xf * (ab.global_position + p))
	await move(s[0], false, 0.0)
	await btn(s[0], true)
	if OS.has_environment("DBG13"):
		var hc := root.gui_get_hovered_control()
		print("DBG press at %s drawing=%s hovered=%s path=%s" % [s[0], K.canvas.current_tool.is_drawing, hc, hc.get_path() if hc else ""])
	for i in s.size():
		var t := float(i) / maxf(1.0, s.size() - 1)
		await move(s[i], true, clampf(0.2 + 0.8 * sin(t * PI), 0.05, 0.98))
	await btn(s[-1], false)
	await K.frames(3)

func lines_in(ab: Node2D) -> Array:
	return ab.get_children().filter(func(c) -> bool: return c is Line2D)

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("smart"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(1600, 1000), "Paisaje", Color("#fdf6e3"))
	var mem0: float = K.memory_mb()
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var t0 := Time.get_ticks_msec()
	# Cielo: 40 trazos de rotulador horizontales
	for i in 40:
		var y := 40.0 + i * 9.0
		K.brush(K.scribble(Vector2(20, y), Vector2(1580, y + rng.randf_range(-6, 6)), 4.0, 40, i), 10.0, "marker",
			Color("#8ecae6").lerp(Color("#ffd6a5"), i / 40.0), true, "Cielo %d" % i)
	# Sol: aerógrafo
	for i in 6:
		K.brush(K.arc_points(Vector2(1250, 180), 30.0 + i * 14.0, 0.0, TAU, 40), 18.0, "airbrush", Color("#ffb703", 0.6), false, "Sol %d" % i)
	# Montañas: caligráfico
	for i in 14:
		var x := 60.0 + i * 110.0
		var pts := PackedVector2Array([Vector2(x - 90, 640), Vector2(x, 400 + rng.randf_range(-60, 40)), Vector2(x + 90, 640)])
		K.brush(pts, 12.0, "calligraphy", Color("#577590").darkened(i * 0.02), true, "Montaña %d" % i)
	# Hierba: 200 trazos cortos de lápiz
	for i in 200:
		var bx := 20.0 + rng.randf() * 1560.0
		var by := 700.0 + rng.randf() * 280.0
		var tip := Vector2(bx + rng.randf_range(-14, 14), by - rng.randf_range(30, 70))
		var mid := Vector2(bx, by).lerp(tip, 0.5) + Vector2(rng.randf_range(-6, 6), 0)
		K.brush(PackedVector2Array([Vector2(bx, by), mid, tip]), rng.randf_range(2.0, 4.0), "pencil", Color("#2d6a4f").lerp(Color("#95d5b2"), rng.randf()), true, "Hierba %d" % i)
	# Flores: pincel de figuras con una estrella
	var petal = api.add_star(Vector2(1500, 950), 10, 5, 0.5, "Pétalo")
	api.set_props(petal, {"fill_color": Color("#e5989b"), "stroke_width": 0.0})
	for i in 30:
		var c := Vector2(60 + rng.randf() * 1480, 760 + rng.randf() * 200)
		K.object_brush([petal], K.arc_points(c, 10.0, 0.0, TAU, 12), 14.0, {"spacing": 1.4, "seed": i}, "Flores %d" % i)
	api.delete(petal)
	var script_ms := Time.get_ticks_msec() - t0
	var n_script := lines_in(ab).size()
	K.note("trazos_script", n_script)
	K.note("ms_por_trazo_script", snappedf(float(script_ms) / maxf(1, n_script), 0.01))
	# 12 trazos REALES con la herramienta Pincel (lápiz, con presión)
	await K.look_at(ab)
	K.canvas.switch_tool("brush")
	await K.frames(4)
	var bt = K.canvas.current_tool
	if bt.has_method("apply_brush_style"):
		bt.apply_brush_style("pencil")
	bt.brush_width = 5.0
	var before_tool := lines_in(ab).size()
	# VAL-42: la página queda SELECCIONADA (tiradores): el pincel debe dibujar
	# igualmente dentro de ella (antes el clic arrastraba la página).
	K.check("la página está seleccionada antes de dibujar", ab.is_selected)
	var t1 := Time.get_ticks_msec()
	for i in 12:
		var a := Vector2(200 + i * 100, 560)
		var pts := PackedVector2Array()
		for k in 30:
			pts.append(a + Vector2(k * 2.0, -k * 3.0 + sin(k * 0.4) * 8.0))
		await tool_stroke(ab, pts)
	var tool_ms := Time.get_ticks_msec() - t1
	var n_tool := lines_in(ab).size() - before_tool
	K.check("12 trazos dibujados con la herramienta Pincel", n_tool == 12, str(n_tool))
	K.note("ms_por_trazo_herramienta", int(tool_ms / 12.0))
	K.canvas.switch_tool("move")
	await K.frames(4)
	var total := lines_in(ab).size()
	K.check("más de 300 trazos en la ilustración", total >= 300, str(total))
	# Fluidez
	await K.look_at(ab)
	var ms_all: float = await K.frame_ms("todo_visible")
	K.check("todo a la vista a ≥ 30 fps", ms_all <= 34.0, "%.1f ms" % ms_all)
	await K.look_at(ab, 4.0)
	var ms_zoom: float = await K.frame_ms("zoom_400")
	K.check("zoom 400 % a ≥ 30 fps", ms_zoom <= 34.0, "%.1f ms" % ms_zoom)
	var mem: float = K.memory_mb() - mem0
	K.note("memoria_mb", mem)
	K.check("memoria de 300+ trazos < 400 MB", mem < 400.0, "%.0f MB" % mem)
	await K.look_at(ab)
	await K.shot("01_paisaje")
	# Cambiar el grosor de toda la hierba en una acción
	var grass: Array = lines_in(ab).filter(func(l) -> bool: return String(l.name).begins_with("Hierba"))
	K.sm.set_selection(grass)
	await K.frames(2)
	var t2 := Time.get_ticks_msec()
	K.ic.apply("stroke_width", 6.0)
	var w_ms := Time.get_ticks_msec() - t2
	await K.frames(2)
	K.check("grosor de 200 trazos de hierba a la vez", grass.all(func(l) -> bool: return is_equal_approx(l.width, 6.0)), "%d ms" % w_ms)
	K.check("y en menos de 1,5 s", w_ms < 1500, "%d ms" % w_ms)
	K.hm.undo()
	await K.frames(2)
	K.check("deshacer el grosor de la hierba", not grass.all(func(l) -> bool: return is_equal_approx(l.width, 6.0)))
	K.sm.clear()
	# Exportar y reabrir
	var p_svg := ProjectSettings.globalize_path(OUT.path_join("paisaje.svg"))
	var ok_svg: bool = await api.export(p_svg, ab)
	var svg := FileAccess.get_file_as_string(p_svg) if ok_svg else ""
	K.check("SVG con todos los trazos (≥ 300 formas)", svg.count("<path") >= 300, "%d paths · %d KB" % [svg.count("<path"), svg.length() / 1024])
	var p_png := ProjectSettings.globalize_path(OUT.path_join("paisaje.png"))
	var t3 := Time.get_ticks_msec()
	var ok_png: bool = await api.export(p_png, ab)
	K.check("PNG del paisaje en < 10 s", ok_png and Time.get_ticks_msec() - t3 < 10000, "%d ms" % (Time.get_ticks_msec() - t3))
	await K.frames(30)
	await K.undo_redo(20)
	var abs: Array = await K.save_reload("paisaje")
	for a2 in abs:
		if String(a2.name) == "Paisaje":
			K.check("reabrir: los mismos trazos", lines_in(a2).size() == total, "%d / %d" % [lines_in(a2).size(), total])
			await K.look_at(a2)
			var ms_re: float = await K.frame_ms("reabierto")
			K.check("reabierto también a ≥ 30 fps", ms_re <= 34.0, "%.1f ms" % ms_re)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
