# =============================================================================
# UX-05 — «En Pro falta el panel de…»: el panel PÁGINA (sin selección).
# Pro no lo tenía y en Modern no funcionaba (el color emitía una señal que
# nadie escuchaba; el tamaño era un texto fijo «1920 × 1080 px»).
# En Modern y Pro, sin selección y con clics reales:
#   · se ve el panel Página con el color y el tamaño REALES de la página;
#   · el color (selector de Vectopen) cambia el fondo de la página, con deshacer;
#   · escribir el ancho cambia la página, con deshacer;
#   · «girar» intercambia ancho y alto;
#   · «Tamaños…» abre el panel de formatos dentro de la pantalla;
#   · en Pro, con algo seleccionado, el panel Página se oculta.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/page_section_e2e.gd
# =============================================================================
extends SceneTree

var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(220.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func click(c: Control, what: String) -> void:
	if c == null or not c.is_visible_in_tree():
		check("se puede pulsar " + what, false, "no visible")
		return
	var at := c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	root.push_input(mm)
	await process_frame
	var hit := root.gui_get_hovered_control()
	check("se puede pulsar " + what, hit == c or (hit != null and c.is_ancestor_of(hit)), str(hit))
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.position = at
		mb.global_position = at
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(mb)
		await process_frame
	await frames(6)

func page_section() -> Control:
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == "PageSection" and (n as Control).is_visible_in_tree():
			return n
	return null

func _run() -> void:
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
	var hm = root.get_node("HistoryManager")
	var cv = get_first_node_in_group("_vectopen_canvas")
	var ab = cv.get_node("manager_script").get_active_artboard()
	var vp := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	for mode in ["modern", "professional"]:
		gui.set_ui_mode(mode)
		await frames(30)
		sm.set_selection([])
		await frames(30)
		var ps := page_section()
		check("%s: se ve el panel Página sin selección" % mode, ps != null)
		if ps == null:
			continue
		var real: Vector2 = ab.artboard_size
		check("%s: tamaño REAL de la página" % mode, Vector2(ps.field_w.value, ps.field_h.value).is_equal_approx(real), "%s vs %s" % [Vector2(ps.field_w.value, ps.field_h.value), real])
		# Color con el selector de Vectopen.
		var before_col: Color = ab.fill_color
		await click(ps.swatch, "%s: color de la página" % mode)
		var pop: Control = null
		for n in root.find_children("TextColorPopover", "", true, false):
			if (n as Control).visible:
				pop = n
		check("%s: abre el selector de Vectopen" % mode, pop != null)
		var want := Color(0.93, 0.89, 0.80)
		if pop:
			pop._pickr.establecer_color(want, true)
			await frames(4)
			pop.hide_popover()
		check("%s: el color cambia el fondo de la página" % mode, (ab.fill_color as Color).is_equal_approx(want), str(ab.fill_color))
		hm.undo()
		await frames(4)
		check("%s: deshacer vuelve al color anterior" % mode, (ab.fill_color as Color).is_equal_approx(before_col))
		# Ancho escrito.
		ps.field_w.value = 1000.0
		ps.field_w.value_changed.emit(1000.0)
		await frames(4)
		check("%s: escribir el ancho cambia la página" % mode, is_equal_approx(ab.artboard_size.x, 1000.0), str(ab.artboard_size))
		hm.undo()
		await frames(4)
		check("%s: deshacer vuelve al ancho anterior" % mode, ab.artboard_size.is_equal_approx(real))
		# Girar.
		await click(ps.btn_rotate, "%s: girar página" % mode)
		check("%s: girar intercambia ancho y alto" % mode, ab.artboard_size.is_equal_approx(Vector2(real.y, real.x)), str(ab.artboard_size))
		hm.undo()
		await frames(4)
		# Tamaños…
		await click(ps.btn_sizes, "%s: Tamaños…" % mode)
		var win: Control = ps.get("_presets")
		check("%s: «Tamaños…» abre el panel de formatos" % mode, win != null and win.visible)
		if win:
			check("%s: el panel de formatos cabe en la pantalla" % mode, vp.grow(1.0).encloses(win.get_global_rect()), str(win.get_global_rect()))
			win.visible = false
		if mode == "professional":
			var r: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
			ab.add_child(r)
			r.owner = ab
			sm.set_selection([r])
			await frames(30)
			check("pro: con selección el panel Página se oculta", page_section() == null)
			sm.set_selection([])
			r.queue_free()
			await frames(30)
			check("pro: sin selección vuelve a verse", page_section() != null)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
