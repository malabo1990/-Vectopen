# =============================================================================
# PRUEBA DE INTERFAZ REAL: UNA sola caja de selección al arrastrar.
# Antes, al volver a Mover tras dibujar con otra herramienta, ToolManager creaba
# un SEGUNDO MoveTool con su propia caja del pool: al arrastrar se veían dos
# (una quieta en el sitio viejo y otra moviéndose con la figura).
#   flatpak run --command=godot org.godotengine.Godot --path . \
#       -s res://test/e2e/bounding_box_e2e.gd
# =============================================================================
extends SceneTree
func _send(ev: InputEvent) -> void:
	if ev is InputEventMouse: Input.warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev); Input.flush_buffered_events()
func _btn(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; e.position = at; e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(e); await process_frame
func _mv(at: Vector2, prev: Vector2, down: bool) -> void:
	var e := InputEventMouseMotion.new(); e.position = at; e.global_position = at; e.relative = at - prev; e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(e); await process_frame
func _key(k: int) -> void:
	for p in [true, false]:
		var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = p
		_send(e); await process_frame
func bbs(canvas) -> Array:
	var out := []
	for n in canvas.get_children():
		if String(n.name).begins_with("Boundingbox") or n.get_script() and String(n.get_script().resource_path).ends_with("bounding_box.gd"):
			if (n as CanvasItem).visible: out.append(String(n.name))
	return out
func _init() -> void:
	_run.call_deferred()
var fails := 0
func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

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
	for i in 20: await process_frame
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var y := 300.0
	for tool in ["ellipse", "rectangle", "star5", "pentagon"]:
		canvas.switch_tool(tool)
		for i in 3: await process_frame
		var p0 := Vector2(760, y); var p1 := Vector2(830, y + 60)
		y += 110.0
		await _mv(p0, p0, false); await _btn(p0, true)
		var prev := p0
		for i in 10:
			var p := p0.lerp(p1, (i + 1) / 10.0); await _mv(p, prev, true); prev = p
		await _btn(p1, false)
		for i in 4: await process_frame
		canvas.switch_tool("move")
		for i in 3: await process_frame
		var c := (p0 + p1) / 2.0
		await _mv(c, c, false); await _btn(c, true)
		prev = c
		for i in 10:
			var p := c + Vector2(12 * (i + 1), 0); await _mv(p, prev, true); prev = p
		for i in 3: await process_frame
		var vis := bbs(canvas)
		check("%s → Mover: una sola caja al arrastrar" % tool, vis.size() == 1, str(vis))
		await _btn(prev, false)
		for i in 3: await process_frame
	var tm = root.get_node("ToolManager")
	check("ToolManager no crea un Mover propio", tm.get_current_tool() == null, str(tm.get_current_tool()))
	print("RESULT %s (%d fallos)" % ["OK" if fails == 0 else "FALLOS", fails])
	quit(1 if fails > 0 else 0)
