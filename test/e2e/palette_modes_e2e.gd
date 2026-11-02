# =============================================================================
# UX-04 — «Modern y Pro no muestran el panel de paleta».
# En Smart, Modern y Pro abre el selector de color (como el usuario), pulsa el
# botón de PALETA (debajo de la rueda) y comprueba que el panel de paleta:
#   · se ve (visible, dentro de la ventana y no recortado por su contenedor),
#   · se puede usar (un clic en él le llega),
#   · hay UNA sola instancia visible,
#   · conserva su estado (abierto/cerrado) al cambiar de modo.
# También que la fila de colores guardados («+») se ve en los tres modos.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/palette_modes_e2e.gd
# Capturas en user://palette_modes/.
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const OUT := "user://palette_modes"

var fails := 0

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

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

func motion(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.warp_mouse(at)
	root.push_input(mm)
	await process_frame

func button(at: Vector2, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = at
	mb.global_position = at
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(mb)
	await process_frame

func click(c: Control, what: String) -> bool:
	if c == null or not c.is_visible_in_tree():
		check("se puede pulsar " + what, false, "no visible")
		return false
	var at := c.get_global_rect().get_center()
	await motion(at)
	var hit := root.gui_get_hovered_control()
	var ok := hit == c or (hit != null and c.is_ancestor_of(hit))
	check("se puede pulsar " + what, ok, str(hit))
	await button(at, true)
	await button(at, false)
	await frames(6)
	return ok

func is_cls(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls

func artboard() -> Node:
	var c = get_first_node_in_group("_vectopen_canvas")
	var m = c.get_node_or_null("manager_script") if c else null
	return m.get_active_artboard() if m and m.has_method("get_active_artboard") else null

func visible_picker() -> Control:
	for n in root.find_children("*", "", true, false):
		if is_cls(n, "GestorColor") and (n as Control).is_visible_in_tree():
			return n
	return null

## Paneles de paleta visibles ahora mismo (en todos los selectores).
func visible_palettes() -> Array:
	var out: Array = []
	for n in root.find_children("Panel_ multicolor", "Control", true, false):
		if (n as Control).is_visible_in_tree():
			out.append(n)
	return out

## Parte del rectángulo que de verdad se ve: dentro de la ventana y de todos
## los antepasados que recortan su contenido.
func visible_area(c: Control) -> float:
	var r := c.get_global_rect().intersection(root.get_visible_rect())
	# Un antepasado «top_level» flota: lo que hay por encima ya no lo recorta.
	var p: Node = c if c.top_level else c.get_parent()
	while p:
		if p != c and p is Control and (p as Control).clip_contents:
			r = r.intersection((p as Control).get_global_rect())
		if p is CanvasItem and (p as CanvasItem).top_level:
			break
		p = p.get_parent()
	return r.get_area() / maxf(1.0, c.get_global_rect().get_area())

func open_picker(mode: String) -> Control:
	if mode == "smart":
		var pcw := current_scene.find_child("pickr_color_windows", true, false) as Control
		if pcw:
			pcw.visible = true
			await frames(6)
	elif mode == "modern":
		var di := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "DockedInspector"))
		if di.size() > 0:
			await click(di[0].picker_fill, "modern: muestra de relleno")
	else:
		var ps := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "ProStudio"))
		if ps.size() > 0 and "_swatch_fill" in ps[0]:
			await click(ps[0]._swatch_fill, "pro: muestra de relleno")
	await frames(6)
	return visible_picker()

func probe(mode: String) -> void:
	var pk := await open_picker(mode)
	check("%s: selector de color visible" % mode, pk != null)
	if pk == null:
		return
	var grid := pk.find_child("GridContainer_palette_Color", true, false) as Control
	check("%s: colores guardados visibles" % mode, grid != null and grid.is_visible_in_tree() and visible_area(grid) > 0.9,
		"área visible %.0f %%" % (visible_area(grid) * 100.0 if grid else 0.0))
	var btn := pk.find_child("Button_palleteColor", true, false) as Button
	var before := visible_palettes().size()
	if visible_palettes().size() > 0:
		await click(btn, "%s: cerrar paleta abierta" % mode)
	await click(btn, "%s: botón paleta" % mode)
	var pals := visible_palettes()
	check("%s: el botón abre la paleta" % mode, pals.size() >= 1, "antes %d" % before)
	check("%s: una sola paleta visible" % mode, pals.size() <= 1, str(pals.size()))
	if pals.size() >= 1:
		var pal: Control = pals[0]
		var a := visible_area(pal)
		check("%s: la paleta se ve entera (no recortada ni fuera de la ventana)" % mode, a > 0.95, "%.0f %% visible, rect=%s" % [a * 100.0, pal.get_global_rect()])
		# Un clic dentro de la paleta le llega a ella (no a lo que tenga detrás).
		var inner := pal.get_global_rect().grow(-20).intersection(root.get_visible_rect())
		if inner.has_area():
			await motion(inner.get_center())
			var hit := root.gui_get_hovered_control()
			check("%s: la paleta recibe el ratón" % mode, hit == pal or (hit != null and pal.is_ancestor_of(hit)), str(hit))
	await shot("%s_paleta" % mode)

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
	var ab := artboard()
	var rect: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.name = "Rect paleta"
	ab.add_child(rect)
	rect.owner = ab
	rect.size = Vector2(200, 140)
	rect.position = Vector2(300, 300)
	# Primera vuelta: cada modo crea su selector la primera vez que se abre.
	for mode in ["smart", "modern", "professional"]:
		gui.set_ui_mode(mode)
		await frames(30)
		root.get_node("SelectionManager").set_selection([rect])
		await frames(8)
		await open_picker(mode)
	var pickers_before := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "GestorColor")).size()
	for mode in ["smart", "modern", "professional"]:
		gui.set_ui_mode(mode)
		await frames(30)
		root.get_node("SelectionManager").set_selection([rect])
		await frames(8)
		await probe(mode)
	# Conserva el estado: abierta en Pro → al volver a Modern sigue abierta.
	var open_now := visible_palettes().size()
	gui.set_ui_mode("modern")
	await frames(30)
	root.get_node("SelectionManager").set_selection([rect])
	await frames(8)
	var pk := await open_picker("modern")
	check("la paleta abierta sigue abierta al cambiar de modo", open_now == 0 or visible_palettes().size() == 1,
		"antes %d, ahora %d" % [open_now, visible_palettes().size()])
	var pickers_after := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "GestorColor")).size()
	check("cambiar de modo no duplica selectores", pickers_after == pickers_before, "%d → %d" % [pickers_before, pickers_after])
	rect.queue_free()
	await frames(4)
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
