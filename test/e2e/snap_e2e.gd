# =============================================================================
# PRUEBA DE INTERFAZ REAL del IMÁN inteligente (estilo Figma / Affinity), con
# arrastres de ratón simulados sobre la app:
#   · engancha a 4 px de pantalla, no a 9 (umbral 6 px);
#   · histéresis: enganchado se mantiene a 8 px y se suelta a 14;
#   · la guía va SOLO entre los dos objetos (antes cruzaba la pantalla);
#   · Ctrl desactiva el imán;
#   · con 120 imágenes fuera de la vista el arrastre sigue fluido.
#   flatpak run --command=godot org.godotengine.Godot --path . \
#       -s res://test/e2e/snap_e2e.gd
# =============================================================================
extends SceneTree

var fails := 0
var api
var canvas
var mt

func _init() -> void:
	_run.call_deferred()

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

## También mueve el cursor REAL: MoveTool lee get_global_mouse_position(),
## que es la posición del sistema, no la del evento simulado.
func _send(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		Input.warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _btn(at: Vector2, down: bool, ctrl := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	e.global_position = at
	e.ctrl_pressed = ctrl
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(e)
	await process_frame

func _mv(at: Vector2, prev: Vector2, ctrl := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = at - prev
	e.ctrl_pressed = ctrl
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(e)
	await process_frame

func screen_rect(n: Node2D) -> Rect2:
	var xf: Transform2D = canvas.get_viewport().get_canvas_transform()
	var gr: Rect2 = mt._global_rect(n)
	return Rect2(xf * gr.position, gr.size * xf.get_scale())

## Arrastra `n` desde su centro hasta que su borde izquierdo quede a `target_x`
## (pantalla), en pasos de 4 px. Devuelve el borde izquierdo final (pantalla).
func drag_left_to(n: Node2D, target_x: float, ctrl := false, release := true) -> float:
	var r := screen_rect(n)
	var start := r.get_center()
	var dx := target_x - r.position.x
	var steps := maxi(1, int(absf(dx) / 4.0))
	await _mv(start, start)
	await _btn(start, true, ctrl)
	var prev := start
	for i in range(1, steps + 1):
		var p := start + Vector2(dx * float(i) / steps, 0.0)
		await _mv(p, prev, ctrl)
		prev = p
	await frames(2)
	var left := screen_rect(n).position.x
	if release:
		await _btn(prev, false, ctrl)
		await frames(2)
	return left

func _run() -> void:
	Input.use_accumulated_input = false
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)  # pantalla Huion completa
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await frames(20)
	api = root.get_node("PluginManager").api
	canvas = get_first_node_in_group("_vectopen_canvas")
	mt = canvas.current_tool
	var sm = root.get_node("SnapManager")
	sm.snap_to_objects = true
	sm.grid_enabled = false
	for c in api.shapes():
		c.get_parent().remove_child(c)
		c.queue_free()
	var cam: Camera2D = canvas.get_node("Camera2D")
	cam.zoom = Vector2.ONE
	var cen: Vector2 = api.artboard_size() / 2.0
	cam.global_position = canvas.get_node("manager_script").get_active_artboard().global_position + cen
	await frames(4)
	var a: Node2D = api.add_rect(cen + Vector2(-150, -120), Vector2(140, 100))
	var b: Node2D = api.add_rect(cen + Vector2(60, 120), Vector2(140, 90))   # mismo ancho que A: bordes y centro alinean a la vez
	api.set_fill(a, Color(0.2, 0.5, 0.9))
	api.set_fill(b, Color(0.9, 0.4, 0.2))
	await frames(4)
	var ax := screen_rect(a).position.x
	var left := 0.0

	# 1-3. Lógica del imán (directa: el arrastre simulado no fija el píxel exacto
	#      porque MoveTool lee el cursor del sistema).
	var ra: Rect2 = mt._global_rect(a)
	var rb: Rect2 = mt._global_rect(b)
	var cands: Array = [ra]
	var at := func(left: float) -> Rect2: return Rect2(Vector2(left, rb.position.y), rb.size)
	sm.begin_snap_session()   # como al empezar a arrastrar
	var r1: Dictionary = sm.smart_snap(at.call(ra.position.x + 4.0), cands, 1.0)
	check("a 4 px engancha al borde izquierdo", is_equal_approx(float(r1["offset"].x), -4.0), str(r1["offset"]))
	var g1: Array = r1["guides"]
	check("una sola guía vertical", g1.size() == 1 and String(g1[0]["axis"]) == "x")
	if g1.size() == 1:
		var lo := minf(ra.position.y, rb.position.y)
		var hi := maxf(ra.end.y, rb.end.y)
		check("la guía va solo entre los dos objetos", float(g1[0]["a"]) >= lo - 0.5 and float(g1[0]["b"]) <= hi + 0.5,
			"%.0f..%.0f dentro de %.0f..%.0f" % [g1[0]["a"], g1[0]["b"], lo, hi])
	var r2: Dictionary = sm.smart_snap(at.call(ra.position.x + 8.0), cands, 1.0)
	check("histéresis: enganchado, a 8 px sigue", is_equal_approx(float(r2["offset"].x), -8.0), str(r2["offset"]))
	var r3: Dictionary = sm.smart_snap(at.call(ra.position.x + 14.0), cands, 1.0)
	check("a 14 px se suelta", is_equal_approx(float(r3["offset"].x), 0.0), str(r3["offset"]))
	sm.begin_snap_session()
	var r4: Dictionary = sm.smart_snap(at.call(ra.position.x + 9.0), cands, 1.0)
	check("a 9 px (sin enganche previo) NO engancha: umbral 6 px", is_equal_approx(float(r4["offset"].x), 0.0), str(r4["offset"]))
	sm.begin_snap_session()
	var r5: Dictionary = sm.smart_snap(at.call(ra.position.x + 6.0), cands, 2.0)
	check("a zoom 2 el umbral es en pantalla (6 px = 3 de mundo)", is_equal_approx(float(r5["offset"].x), 0.0), str(r5["offset"]))
	sm.end_snap_session()
	# Con el ratón real: al acercarse se dibuja UNA guía corta (no la pantalla entera)
	await drag_left_to(b, screen_rect(a).position.x + 2.0, false, false)
	var gl: Array = mt._snap_guides
	var short := true
	for gg in gl:
		var span: float = absf(float(gg["b"]) - float(gg["a"]))
		short = short and span < 700.0
	check("arrastrando: guía corta, como mucho una por eje", gl.size() <= 2 and short, "%d guías" % gl.size())
	await _btn(screen_rect(b).get_center(), false)
	await frames(10)

	# 4. Ctrl desactiva el imán
	await frames(10)
	await drag_left_to(b, ax + 3.0, true, false)
	check("con Ctrl no se dibuja ninguna guía (imán apagado)", mt._snap_guides.is_empty())
	await _btn(screen_rect(b).get_center(), false)
	await frames(4)

	# 5. 120 imágenes FUERA de la vista: el arrastre sigue fluido
	for i in 120:
		var im := Image.create(40, 40, false, Image.FORMAT_RGBA8)
		im.fill(Color(randf(), randf(), randf()))
		api.add_image(im, cen + Vector2(3000 + (i % 12) * 60, (i / 12) * 60))
	await frames(5)
	var t0 := Time.get_ticks_usec()
	await drag_left_to(b, ax + 200.0)
	var per_step := (Time.get_ticks_usec() - t0) / 1000.0 / 50.0
	check("con 120 imágenes fuera de la vista no las usa como imán", mt._snap_candidates().size() <= 8, "%d candidatos" % mt._snap_candidates().size())
	check("arrastre fluido con muchas capas", per_step < 40.0, "%.1f ms por paso" % per_step)

	print("RESULT %s (%d fallos)" % ["OK" if fails == 0 else "FALLOS", fails])
	quit(1 if fails > 0 else 0)
