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

## El selector compartido de la ventana de color (uno para toda la app) no
## cuenta como selector de un modo.
func _in_text_popover(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if String(p.name) == "TextColorPopover":
			return true
		p = p.get_parent()
	return false

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
	if pk:
		# Las pestañas de degradado muestran su degradado EN COLOR (sin teñir).
		var tinted := []
		for t in ["tab_linear", "tab_radial", "tab_conic", "tab_diamond"]:
			var tb = pk.get(t)
			if tb is Button and (tb as Button).icon and not (tb as Button).get_theme_color("icon_normal_color").is_equal_approx(Color.WHITE):
				tinted.append(t)
		check("%s: los iconos de degradado se ven en color" % mode, tinted.is_empty(), ", ".join(tinted))
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
		await use_palette(mode, pal, pk)
	await shot("%s_paleta" % mode)

## UX-20: la paleta se USA: el deslizador cambia el número de colores y una
## muestra pulsada va al objeto (lo que edita el selector) y al selector.
func use_palette(mode: String, pal: Control, pk: Control) -> void:
	var slider := pal.find_child("HSlider", true, false) as HSlider
	var flow := pal.find_child("FlowContainer", true, false) as Container
	check("%s: deslizador de la paleta visible" % mode, slider != null and slider.is_visible_in_tree())
	if slider == null or flow == null:
		return
	var r := slider.get_global_rect()
	var from := r.position + Vector2(4.0, r.size.y * 0.5)
	var to := r.position + Vector2(r.size.x - 4.0, r.size.y * 0.5)
	await motion(from)
	var hit := root.gui_get_hovered_control()
	check("%s: el deslizador recibe el ratón" % mode, hit == slider, str(hit))
	# Arrastre real: pulsar a la izquierda y llevarlo al extremo derecho.
	await button(from, true)
	for k in 8:
		var mm := InputEventMouseMotion.new()
		mm.position = from.lerp(to, float(k + 1) / 8.0)
		mm.global_position = mm.position
		mm.relative = (to - from) / 8.0
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mm)
		await process_frame
	await button(to, false)
	await frames(6)
	var n := flow.get_children().filter(func(c): return not c.is_queued_for_deletion()).size()
	check("%s: arrastrar el deslizador da más colores" % mode, int(slider.value) == int(slider.max_value) and n == int(slider.max_value), "valor %d, %d muestras" % [int(slider.value), n])
	var cells := flow.get_children().filter(func(c): return not c.is_queued_for_deletion())
	if cells.size() < 3:
		return
	var cell: Control = cells[1]
	var want: Color = (cell.get_child(0) as ColorRect).color
	var cc := cell.get_global_rect().get_center()
	await motion(cc)
	await button(cc, true)
	await button(cc, false)
	await frames(6)
	var rect = root.get_node("SelectionManager").get_selection()[0] if root.get_node("SelectionManager").has_method("get_selection") else null
	if rect == null:
		rect = get_first_node_in_group("_vectopen_canvas").get_node("manager_script").get_active_artboard().get_node_or_null("Rect paleta")
	check("%s: la muestra pulsada va al relleno del objeto" % mode, rect != null and (rect.fill_color as Color).is_equal_approx(want), "%s ≠ %s" % [rect.fill_color if rect else "-", want])
	var shown: Color = pk.nodo_color_rect.color if "nodo_color_rect" in pk and pk.nodo_color_rect else Color.MAGENTA
	check("%s: el selector muestra ese color" % mode, shown.is_equal_approx(want), str(shown))
	check("%s: pulsar la paleta no deselecciona el objeto" % mode, root.get_node("InspectorCore").selection().size() == 1)
	if mode == "modern" and rect:
		# Con el selector del TRAZO, la muestra va al trazo (no al relleno).
		var di := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "DockedInspector"))
		rect.stroke_width = 4.0
		var fill_before: Color = rect.fill_color
		var full := di[0].find_child("FullStroke", true, false) as Control
		var vis_cp := full.find_children("*", "ColorPickerButton", true, false).filter(func(n): return (n as Control).is_visible_in_tree())
		var scp := (vis_cp[0] if vis_cp.size() > 0 else full.find_children("*", "ColorPickerButton", true, false)[0]) as Control
		var sc := scp.get_parent()
		while sc and not (sc is ScrollContainer):
			sc = sc.get_parent()
		if sc:
			(sc as ScrollContainer).ensure_control_visible(scp)
			await frames(4)
		await click(scp, "modern: muestra de trazo")
		await frames(6)
		var pop: Control = di[0].get("_color_popover")   # REG-01: el completo del Inspector
		check("modern: el trazo abre el selector de Vectopen", pop != null and pop.visible)
		var pals := visible_palettes()
		if pals.is_empty() and pop:
			var b2 := pop.find_child("Button_palleteColor", true, false) as Button
			await click(b2, "modern: abrir paleta del trazo")
			pals = visible_palettes()
		check("modern: paleta abierta con el selector del trazo", pals.size() == 1)
		if pals.size() == 1:
			var cells2 := (pals[0] as Control).find_child("FlowContainer", true, false).get_children().filter(func(c): return not c.is_queued_for_deletion())
			var c2: Control = cells2[cells2.size() - 2]
			var want2: Color = (c2.get_child(0) as ColorRect).color
			var at2 := c2.get_global_rect().get_center()
			await motion(at2)
			await button(at2, true)
			await button(at2, false)
			await frames(6)
			check("modern: la muestra va al TRAZO", (rect.stroke_color as Color).is_equal_approx(want2), "%s ≠ %s" % [rect.stroke_color, want2])
			check("modern: el relleno no cambia", (rect.fill_color as Color).is_equal_approx(fill_before))

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
	var pickers_before := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "GestorColor") and not _in_text_popover(n)).size()
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
	var pickers_after := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "GestorColor") and not _in_text_popover(n)).size()
	check("cambiar de modo no duplica selectores", pickers_after == pickers_before, "%d → %d" % [pickers_before, pickers_after])
	rect.queue_free()
	await frames(4)
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
