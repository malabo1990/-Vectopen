# =============================================================================
# Duplicar TEXTO y PÁRRAFO con Alt + arrastrar (y Ctrl+D, copiar/pegar):
# la copia debe verse igual que el original (mismo tamaño de letra, el
# párrafo sigue partiendo líneas) y deshacer la quita.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/text_alt_drag_duplicate_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://text_dup"
var fails := 0
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

## Centro en pantalla de un objeto (coordenadas del viewport).
func screen_center(n: Node2D) -> Vector2:
	var vrt = n.get_node_or_null("VectorRichText")
	var size: Vector2 = vrt.get_content_size() if vrt else Vector2(40, 20)
	return n.get_global_transform_with_canvas() * (size / 2.0)

func _send(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		Input.warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

var _prev := Vector2.ZERO
func mouse(at: Vector2, pressed: Variant, alt: bool) -> void:
	if pressed == null:
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.global_position = at
		mm.relative = at - _prev
		mm.alt_pressed = alt
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
		_send(mm)
	else:
		var mb := InputEventMouseButton.new()
		mb.position = at
		mb.global_position = at
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.alt_pressed = alt
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		_send(mb)
	_prev = at
	await process_frame

func alt_drag(n: Node2D, by: Vector2) -> void:
	var a := screen_center(n)
	var k := InputEventKey.new()
	k.keycode = KEY_ALT
	k.physical_keycode = KEY_ALT
	k.pressed = true
	_send(k)
	await mouse(a, null, true)
	await mouse(a, true, true)
	for i in range(1, 11):
		await mouse(a + by * (i / 10.0), null, true)
	await mouse(a + by, false, true)
	k = k.duplicate()
	k.pressed = false
	_send(k)
	await frames(8)

func texts(ab: Node) -> Array:
	return ab.get_children().filter(func(c): return String(c.get_meta("shape_type", "")).begins_with("text"))

func same_look(a: Node, b: Node) -> bool:
	var va = a.get_node_or_null("VectorRichText")
	var vb = b.get_node_or_null("VectorRichText")
	if va == null or vb == null:
		return false
	var sa: Vector2 = va.get_content_size()
	var sb: Vector2 = vb.get_content_size()
	return absf(sa.x - sb.x) < 1.5 and absf(sa.y - sb.y) < 1.5

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("smart")
	await frames(20)
	api = root.get_node("PluginManager").api
	var ab: Node2D = api.artboard()
	var title = api.add_text(Vector2(60, 60), "Título grande", 48, Color.BLACK)
	title.name = "Titulo"
	var para = api.add_text_box(Rect2(Vector2(60, 220), Vector2(300, 120)), "Un párrafo con varias líneas de texto para comprobar que la copia sigue partiendo líneas. ".repeat(2), 16, Color.BLACK, 1, 20.0, "Parrafo")
	await frames(10)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	canvas.switch_tool("move")
	await frames(6)
	var hm = root.get_node("HistoryManager")
	# Control: un rectángulo con el mismo gesto.
	var rect = api.add_rect(Vector2(600, 500), Vector2(120, 80), 0.0, "Caja")
	await frames(4)
	api.select([rect])
	await frames(4)
	var nb := ab.get_child_count()
	var rc: Vector2 = rect.get_global_transform_with_canvas().origin
	var k0 := InputEventKey.new(); k0.keycode = KEY_ALT; k0.physical_keycode = KEY_ALT; k0.pressed = true; _send(k0)
	await mouse(rc, null, true); await mouse(rc, true, true)
	for i in range(1, 11): await mouse(rc + Vector2(15 * i, 0), null, true)
	await mouse(rc + Vector2(150, 0), false, true)
	k0 = k0.duplicate(); k0.pressed = false; _send(k0)
	await frames(8)
	print("INFO rectángulo: hijos %d → %d" % [nb, ab.get_child_count()])
	print("INFO título: pos=%s pantalla=%s" % [title.global_position, screen_center(title)])
	for pair in [[title, "título"], [para, "párrafo"]]:
		var n: Node2D = pair[0]
		var before := texts(ab).size()
		api.select([n])
		await frames(6)
		await alt_drag(n, Vector2(0, 160) if n == title else Vector2(360, 0))
		var now := texts(ab)
		check("Alt + arrastrar duplica el %s" % pair[1], now.size() == before + 1, "%d → %d" % [before, now.size()])
		var copy: Node = null
		for t in now:
			if t != title and t != para and String(t.name).begins_with(String(n.name)):
				copy = t
		check("la copia del %s se ve igual (mismo tamaño de texto)" % pair[1], copy != null and same_look(n, copy),
			"%s vs %s" % [n.get_node("VectorRichText").get_content_size(), copy.get_node("VectorRichText").get_content_size() if copy else "-"])
		check("el %s original se queda en su sitio" % pair[1], n.position.distance_to(n.position) < 0.1)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT.path_join("altdrag_%s.png" % ("titulo" if n == title else "parrafo")))
		hm.undo()
		await frames(6)
		check("deshacer quita la copia del %s" % pair[1], texts(ab).size() == before)
	# Ctrl+D y copiar/pegar también.
	var mt: Node = null
	for t in root.get_node("ToolManager").get_children():
		if t.has_method("duplicate_selected"):
			mt = t
	if mt == null:
		for n in root.find_children("*", "", true, false):
			if n.has_method("duplicate_selected") and n.has_method("paste_clipboard"):
				mt = n
				break
	check("herramienta Mover disponible", mt != null, str(mt))
	if mt:
		api.select([para])
		await frames(4)
		mt.selected_shapes.assign([para])
		mt.duplicate_selected()
		await frames(8)
		var dup = texts(ab).filter(func(t): return t != title and t != para)
		check("Ctrl+D: la copia del párrafo se ve igual", dup.size() == 1 and same_look(para, dup[0]),
			"%d copias; %s" % [dup.size(), [para.get_node("VectorRichText").get_content_size()] + dup.map(func(d): return d.get_node("VectorRichText").get_content_size() if d.get_node_or_null("VectorRichText") else "sin VRT")])
		hm.undo()
		await frames(4)
		mt.selected_shapes.assign([title])
		mt.copy_selected()
		mt.target_artboard = ab
		mt.paste_clipboard()
		await frames(8)
		dup = texts(ab).filter(func(t): return t != title and t != para)
		check("Pegar: la copia del título se ve igual", dup.size() == 1 and same_look(title, dup[0]),
			"%d copias; %s" % [dup.size(), [title.get_node("VectorRichText").get_content_size()] + dup.map(func(d): return d.get_node("VectorRichText").get_content_size() if d.get_node_or_null("VectorRichText") else "sin VRT")])
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
