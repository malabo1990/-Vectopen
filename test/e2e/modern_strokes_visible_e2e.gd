# =============================================================================
# UX-11 — «Modern: los trazos no se muestran».
# Dibuja con clics reales (pincel arrastrando y Bézier por puntos) en Modern,
# y como control en Smart y Pro. Para cada trazo comprueba: existe el nodo,
# está en el árbol, es visible y SE VE (los píxeles de la zona cambian).
# Luego cambia de modo y comprueba que sigue ahí.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/modern_strokes_visible_e2e.gd
# Capturas en user://modern_strokes/.
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const OUT := "user://modern_strokes"

var fails := 0
## Ratón real = presión 0 (Godot no inventa presión); tableta = 0..1.
var PRESSURE := float(OS.get_environment("UX11_PRESSURE")) if OS.has_environment("UX11_PRESSURE") else 0.0

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

func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func shot(name: String) -> void:
	(await grab()).save_png(OUT.path_join(name + ".png"))

func motion(at: Vector2, held: bool) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	mm.pressure = PRESSURE if held else 0.0
	Input.warp_mouse(at)
	root.push_input(mm)
	await process_frame

func button(at: Vector2, pressed: bool, dbl := false) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = at
	mb.global_position = at
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.double_click = dbl
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(mb)
	await process_frame

func key(code: Key) -> void:
	for p in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = p
		root.push_input(k)
		await process_frame

func click(c: Control, what: String) -> void:
	if c == null or not c.is_visible_in_tree():
		check("se puede pulsar " + what, false, "no visible")
		return
	var at := c.get_global_rect().get_center()
	await motion(at, false)
	var hit := root.gui_get_hovered_control()
	check("se puede pulsar " + what, hit == c or (hit != null and c.is_ancestor_of(hit)), str(hit))
	await button(at, true)
	await button(at, false)
	await frames(6)

func is_cls(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls

func canvas() -> Node:
	return get_first_node_in_group("_vectopen_canvas")

func artboard() -> Node:
	var c = canvas()
	var m = c.get_node_or_null("manager_script") if c else null
	return m.get_active_artboard() if m and m.has_method("get_active_artboard") else null

## Todas las figuras del documento (recursivo).
func shapes() -> Array:
	var ab := artboard()
	if ab == null:
		return []
	var out: Array = []
	for n in ab.find_children("*", "Node2D", true, false):
		if n.has_method("get_doc_vertices") or n.get_script() != null and String(n.get_script().resource_path).contains("/shapes/"):
			out.append(n)
	return out

## Cuántos píxeles cambian dentro de r entre dos capturas.
func diff(a: Image, b: Image, r: Rect2i) -> int:
	var n := 0
	r = r.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.15:
				n += 1
	return n

## Zona libre del lienzo (no tapada por paneles) cerca del centro.
func free_point(frac: Vector2) -> Vector2:
	var vs := root.get_visible_rect().size
	return Vector2(vs.x * frac.x, vs.y * frac.y)

func select_tool(mode: String, tool_id: String) -> void:
	if mode == "modern":
		var bar := root.find_children("*", "PanelContainer", true, false).filter(func(n): return is_cls(n, "ModernBottomToolbar"))
		var tb = bar[0] if bar.size() > 0 else null
		check("%s: barra inferior" % mode, tb != null)
		if tb:
			await click(tb._buttons[tool_id], "%s: botón %s" % [mode, tool_id])
	else:
		var main := current_scene.find_child("main", true, false)
		var bar_c := main.find_child("ToolbarContainer_button_tool", true, false)
		var b := (bar_c.get_node_or_null("Button") if tool_id == "select" else main.find_child("button_tool" + tool_id, true, false)) as Button
		await click(b, "%s: botón %s" % [mode, tool_id])
	await frames(6)

func checks_new(mode: String, what: String, before: Array, img0: Image, zone: Rect2i) -> Node:
	var now := shapes()
	var fresh := now.filter(func(n): return not before.has(n))
	check("%s: %s crea un nodo" % [mode, what], fresh.size() >= 1, "%d → %d" % [before.size(), now.size()])
	if fresh.is_empty():
		return null
	var n: Node2D = fresh[0]
	check("%s: %s está en el árbol" % [mode, what], n.is_inside_tree())
	check("%s: %s es visible" % [mode, what], n.is_visible_in_tree(), "visible=%s mod=%s" % [n.visible, n.modulate])
	await frames(4)
	var img1 := await grab()
	var d := diff(img0, img1, zone)
	check("%s: %s se ve en pantalla" % [mode, what], d > 40, "píxeles cambiados=%d" % d)
	return n

func draw_brush(mode: String) -> Node:
	await select_tool(mode, "brush")
	var a := free_point(Vector2(0.30, 0.40))
	var b := free_point(Vector2(0.50, 0.55))
	var zone := Rect2i(Vector2i(a) - Vector2i(30, 30), Vector2i(b - a) + Vector2i(60, 60))
	var before := shapes()
	var img0 := await grab()
	await motion(a, false)
	await button(a, true)
	for i in 31:
		await motion(a.lerp(b, i / 30.0) + Vector2(0, sin(i / 5.0) * 20.0), true)
		if i == 20:
			# Vista previa EN VIVO mientras se arrastra.
			var mid := await grab()
			var dm := diff(img0, mid, zone)
			check("%s: el pincel se ve mientras se dibuja" % mode, dm > 20, "píxeles=%d" % dm)
			if mode == "modern":
				mid.save_png(OUT.path_join("modern_pincel_vivo.png"))
	await button(b, false)
	await frames(10)
	var n := await checks_new(mode, "pincel", before, img0, zone)
	await shot("%s_pincel" % mode)
	return n

func draw_bezier(mode: String) -> Node:
	await select_tool(mode, "bezier")
	var pts := [free_point(Vector2(0.28, 0.70)), free_point(Vector2(0.38, 0.62)), free_point(Vector2(0.50, 0.72))]
	var zone := Rect2i(Vector2i(pts[0]) - Vector2i(30, 40), Vector2i(pts[2] - pts[0]) + Vector2i(60, 80))
	var before := shapes()
	var img0 := await grab()
	for p in pts:
		await motion(p, false)
		await button(p, true)
		await button(p, false)
		await frames(3)
	# Con dos puntos ya puestos el tramo tiene que verse antes de cerrar.
	var mid := await grab()
	var dm := diff(img0, mid, zone)
	check("%s: el bézier se ve antes de terminar" % mode, dm > 20, "píxeles=%d" % dm)
	await key(KEY_ENTER)
	await frames(10)
	var n := await checks_new(mode, "bézier", before, img0, zone)
	await shot("%s_bezier" % mode)
	return n

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var gui = root.get_node("GlobalUI")
	var kept: Array = []
	for mode in ["modern", "smart", "professional"]:
		gui.set_ui_mode(mode)
		await frames(30)
		var sm = root.get_node("SelectionManager")
		sm.set_selection([])
		await frames(4)
		var b1 := await draw_brush(mode)
		var b2 := await draw_bezier(mode)
		await select_tool(mode, "select")
		for n in [b1, b2]:
			if n:
				kept.append(n)
		# Quitar lo dibujado para que el siguiente modo parta de la misma vista.
		for n in [b1, b2]:
			if n:
				n.visible = false
	# Persisten al cambiar de modo.
	gui.set_ui_mode("modern")
	await frames(20)
	var alive := kept.filter(func(n): return is_instance_valid(n) and n.is_inside_tree())
	check("los trazos siguen en el documento tras cambiar de modo", alive.size() == kept.size(), "%d/%d" % [alive.size(), kept.size()])
	for n in alive:
		n.queue_free()
	await frames(4)
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
