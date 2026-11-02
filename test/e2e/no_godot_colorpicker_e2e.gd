# =============================================================================
# UX-17 — «El color del trazo (también en textos) abre el ColorPicker original
# de Godot: quiero el selector de Vectopen.» En Smart, Modern y Pro, con un
# texto y un rectángulo seleccionados, pulsa con clics reales TODAS las
# muestras de color (ColorPickerButton) visibles de la interfaz:
#   · nunca se abre el ColorPicker de Godot (su ventana emergente);
#   · se abre el selector de Vectopen (TextColorPopover);
#   · el selector queda ENTERO dentro de la ventana (nada por debajo de la
#     pantalla).
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/no_godot_colorpicker_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func press_at(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	root.push_input(mm)
	await process_frame
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.position = at
		mb.global_position = at
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(mb)
		await process_frame
	await frames(4)

## UX-24: el menú del clic derecho, entero en la ventana y por debajo de la
## regla superior / a la derecha de la lateral (se dibujan por encima).
func menu_inside(tag: String, tabs: Control) -> void:
	var menu := tabs.owner as Control
	var pc := menu.get_node_or_null("PanelContainer") as Control if menu else null
	if pc == null:
		return
	var r := pc.get_global_rect()
	var vp := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var top := 0.0
	var left := 0.0
	for n in root.find_children("regla horizontal", "Control", true, false):
		if (n as Control).is_visible_in_tree():
			top = maxf(top, (n as Control).get_global_rect().end.y)
	for n in root.find_children("regla vertical", "Control", true, false):
		if (n as Control).is_visible_in_tree():
			left = maxf(left, (n as Control).get_global_rect().end.x)
	check("%s: el menú cabe en la pantalla" % tag, vp.grow(1.0).encloses(r), "%s en %s" % [r, vp.size])
	check("%s: el menú no queda bajo las reglas" % tag, r.position.y >= top - 1.0 and r.position.x >= left - 1.0, "%s · regla h hasta %.0f, v hasta %.0f" % [r.position, top, left])

## El selector de Vectopen abierto: la ventana sencilla (TextColorPopover) o
## la completa del Inspector de Modern (color del trazo con degradados, REG-01).
func popover() -> Control:
	for n in root.find_children("TextColorPopover", "", true, false):
		if (n as Control).visible:
			return n
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == "DockedInspector":
			var cp = n.get("_color_popover")
			if cp is Control and (cp as Control).visible:
				return cp
	for n in root.find_children("TextColorPopover", "", true, false):
		return n
	return null

func close_popovers() -> void:
	var pop := popover()
	if pop and pop.visible and pop.has_method("hide_popover"):
		pop.hide_popover()
	elif pop and pop.visible:
		pop.visible = false
	await frames(2)

func swatches() -> Array:
	var out: Array = []
	for n in root.find_children("*", "ColorPickerButton", true, false):
		var cp := n as ColorPickerButton
		if not cp.is_visible_in_tree():
			continue
		var r := cp.get_global_rect()
		if r.size.x < 4.0 or not Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(r):
			continue
		out.append(cp)
	return out

func probe(tag: String) -> void:
	var list := swatches()
	print("INFO %s: %d muestras de color visibles" % [tag, list.size()])
	var vp := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	for cp in list:
		if not is_instance_valid(cp) or not cp.is_visible_in_tree():
			continue
		var label := "%s «%s»" % [tag, String(cp.get_path()).get_file()]
		await close_popovers()
		var at: Vector2 = (cp as Control).get_global_rect().get_center()
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.global_position = at
		root.push_input(mm)
		await process_frame
		var hit := root.gui_get_hovered_control()
		if hit != cp:
			# UX-24: algo de la propia interfaz (la regla…) la tapa.
			check("%s: la muestra no está tapada" % label, false, "tapada por %s" % hit)
			continue
		await press_at(at)
		var godot_open := (cp as ColorPickerButton).get_popup().visible
		check("%s: no abre el ColorPicker de Godot" % label, not godot_open)
		if godot_open:
			(cp as ColorPickerButton).get_popup().hide()
		var pop := popover()
		check("%s: abre el selector de Vectopen" % label, pop != null and pop.visible)
		if pop and pop.visible:
			await frames(3)
			var r := pop.get_global_rect()
			check("%s: el selector cabe en la pantalla" % label, vp.grow(1.0).encloses(r), "%s en %s" % [r, vp.size])
	await close_popovers()

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var gui = root.get_node("GlobalUI")
	var sm = root.get_node("SelectionManager")
	var cv = get_first_node_in_group("_vectopen_canvas")
	var ab = cv.get_node("manager_script").get_active_artboard()
	var rect: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.name = "Rect"
	ab.add_child(rect)
	rect.owner = ab
	rect.size = Vector2(200, 140)
	rect.position = Vector2(300, 300)
	var api = root.get_node("PluginManager").api
	var txt = api.add_text(Vector2(400, 600), "Texto")
	# Pegado al borde superior del lienzo: el clic derecho sale junto a la regla.
	var top_rect: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	top_rect.name = "Arriba"
	ab.add_child(top_rect)
	top_rect.owner = ab
	top_rect.size = Vector2(200, 60)
	await frames(2)
	# Su punto (100, 30) cae en la pantalla a 36 px del borde superior.
	top_rect.position = (ab as CanvasItem).get_global_transform_with_canvas().affine_inverse() * Vector2(800, 36) - Vector2(100, 30)
	var total := 0
	for mode in ["smart", "modern", "professional"]:
		gui.set_ui_mode(mode)
		await frames(30)
		for o in ([txt, rect, top_rect] if mode == "smart" else [txt, rect]):
			sm.set_selection([o])
			await frames(12)
			if mode == "smart":
				# Smart: clic derecho sobre el objeto y cada pestaña del menú
				# (Trazos, Color, Tipografía…), como el usuario.
				var local: Vector2 = Vector2(100, 70) if o == rect else (Vector2(100, 30) if o == top_rect else Vector2(20, 10))
				var at: Vector2 = (o as CanvasItem).get_global_transform_with_canvas() * local
				var mm := InputEventMouseMotion.new()
				mm.position = at
				mm.global_position = at
				root.push_input(mm)
				await process_frame
				for pressed in [true, false]:
					var mb := InputEventMouseButton.new()
					mb.position = at
					mb.global_position = at
					mb.button_index = MOUSE_BUTTON_RIGHT
					mb.pressed = pressed
					mb.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
					root.push_input(mb)
					await process_frame
				await frames(8)
				var tabs := root.find_child("button_tab_tools2", true, false) as Control
				check("smart/%s: el menú del clic derecho se abre" % o.name, tabs != null and tabs.is_visible_in_tree())
				if tabs and tabs.is_visible_in_tree():
					for b in tabs.get_children():
						if b is Button and (b as Button).is_visible_in_tree():
							await press_at((b as Button).get_global_rect().get_center())
							await frames(4)
							menu_inside("smart/%s/%s" % [o.name, b.name], tabs)
							total += swatches().size()
							await probe("smart/%s/%s" % [o.name, b.name])
				# Cerrar el menú antes del siguiente objeto (Esc, como el usuario).
				var esc := InputEventKey.new()
				esc.keycode = KEY_ESCAPE
				esc.pressed = true
				root.push_input(esc)
				await frames(2)
				if tabs and tabs.owner and (tabs.owner as CanvasItem).visible:
					(tabs.owner as CanvasItem).visible = false
				sm.set_selection([o])
				await frames(4)
			elif mode == "professional":
				var pro := root.find_children("*", "", true, false).filter(func(n): return n.get_script() and n.get_script().get_global_name() == "ProStudio" and (n as Control).is_visible_in_tree())
				if pro.size() > 0:
					for ta in 3:
						for tb in 3:
							pro[0]._select_tab_a(ta)
							pro[0]._select_tab_b(tb)
							await frames(6)
							total += swatches().size()
							await probe("pro/%s/a%d-b%d" % [o.name, ta, tb])
			else:
				total += swatches().size()
				await probe("%s/%s" % [mode, o.name])
				if o == rect:
					# El color elegido en el selector de Vectopen llega al trazo.
					var full := root.find_child("FullStroke", true, false) as Control
					var cp := full.find_children("*", "ColorPickerButton", true, false)[0] as ColorPickerButton if full else null
					if cp and cp.is_visible_in_tree():
						rect.stroke_width = 4.0
						await press_at(cp.get_global_rect().get_center())
						var pop := popover()
						var red := Color(0.9, 0.1, 0.1)
						if pop and pop.visible:
							var g = pop.get("_pickr")
							if g == null:
								for n in pop.find_children("*", "", true, false):
									if n.get_script() and n.get_script().get_global_name() == "GestorColor":
										g = n
										break
							if g and g.has_method("establecer_color"):
								g.establecer_color(red, true)
							await frames(4)
						check("modern: el color elegido se aplica al trazo", rect.stroke_color.is_equal_approx(red), str(rect.stroke_color))
						root.get_node("HistoryManager").undo()
						await frames(4)
						check("modern: deshacer devuelve el color del trazo", not rect.stroke_color.is_equal_approx(red))
						await close_popovers()
	check("se han probado muestras de color", total > 0, str(total))
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
