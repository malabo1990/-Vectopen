# =============================================================================
# UX-08 — Modern: la sección Trazo del Inspector es el panel COMPLETO de
# Smart (color, grosor, alineación, extremos, estilo, perfil y UNIÓN), sin la
# fila compacta de antes ni controles duplicados. Con clics reales:
#   · se ve el panel completo y ningún resto de la fila antigua;
#   · hay UNA sola fila «Unión» y UN solo selector de extremos/estilo;
#   · pulsar Bisel / Redonda / Inglete cambia la unión del objeto, con deshacer;
#   · el límite de inglete solo está activo con Inglete;
#   · tema claro y oscuro: capturas en user://ux08_modern_stroke/.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/modern_stroke_panel_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://ux08_modern_stroke"
const UI_CFG := "user://vectopen_ui.cfg"
const THEME_CFG := "user://vectopen_theme.cfg"

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

func click(c: Control, what: String) -> void:
	if c == null or not c.is_visible_in_tree():
		check("se puede pulsar " + what, false, "no visible")
		return
	var inspector := _inspector()
	if inspector:
		var sc := inspector.find_children("*", "ScrollContainer", true, false)
		if sc.size() > 0:
			(sc[0] as ScrollContainer).ensure_control_visible(c)
			await frames(3)
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
	await frames(4)

func is_cls(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls

func _inspector() -> Control:
	for n in root.find_children("*", "", true, false):
		if is_cls(n, "DockedInspector") and (n as Control).is_visible_in_tree():
			return n
	return null

func visible_in(parent: Node, cls: String) -> Array:
	return parent.find_children("*", "", true, false).filter(func(n): return is_cls(n, cls) and (n as Control).is_visible_in_tree())

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var ins := _inspector()
	var img := root.get_texture().get_image()
	if ins:
		var r := Rect2i(ins.get_global_rect())
		r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if r.size.x > 0 and r.size.y > 0:
			img = img.get_region(r)
	img.save_png(OUT.path_join(name + ".png"))

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	var th_backup := FileAccess.get_file_as_string(THEME_CFG) if FileAccess.file_exists(THEME_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("modern")
	await frames(30)
	var cv = get_first_node_in_group("_vectopen_canvas")
	var ab = cv.get_node("manager_script").get_active_artboard()
	var rect: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.name = "Rect trazo"
	ab.add_child(rect)
	rect.owner = ab
	rect.size = Vector2(220, 160)
	rect.position = Vector2(320, 300)
	rect.stroke_width = 18.0
	rect.stroke_color = Color(0.1, 0.2, 0.7)
	var sm = root.get_node("SelectionManager")
	sm.set_selection([rect])
	await frames(10)
	var ins := _inspector()
	check("Inspector de Modern visible", ins != null)
	if ins == null:
		_finish(ui_backup, th_backup)
		return
	var full := ins.find_child("FullStroke", true, false) as Control
	check("la sección Trazo es el panel completo de Smart", full != null and full.is_visible_in_tree())
	var legacy_align = ins.get("opt_stroke_align")
	check("la fila compacta antigua no se ve", legacy_align == null or not (legacy_align as Control).is_visible_in_tree())
	var joins := visible_in(ins, "StrokeJoinRow")
	check("una sola fila «Unión»", joins.size() == 1, str(joins.size()))
	var details := ins.find_children("StrokeDetails", "", true, false).filter(func(n): return (n as Control).is_visible_in_tree())
	check("sin selector de extremos/estilo duplicado", details.is_empty(), str(details.size()))
	for key in ["Chip_start", "Chip_end", "Chip_style"]:
		var chip := full.find_child(key, true, false) as Control if full else null
		check("el panel trae «%s»" % key, chip != null and chip.is_visible_in_tree())
	var prow := full.find_child("RowProfile", true, false) as Control if full else null
	check("un rectángulo no ofrece «Perfil» (no tiene perfil de grosor)", prow != null and not prow.is_visible_in_tree())
	var hm = root.get_node("HistoryManager")
	if joins.size() == 1:
		var row = joins[0]
		await click(row.buttons[2], "Bisel")
		check("Bisel cambia la unión", int(rect.stroke_join) == 2, str(rect.stroke_join))
		check("con Bisel el límite de inglete está inactivo", not row.limit_field.enabled)
		await click(row.buttons[1], "Redonda")
		check("Redonda cambia la unión", int(rect.stroke_join) == 1)
		await click(row.buttons[0], "Inglete")
		check("Inglete cambia la unión", int(rect.stroke_join) == 0)
		check("con Inglete el límite está activo", row.limit_field.enabled)
		hm.undo()
		await frames(4)
		check("deshacer vuelve a Redonda", int(rect.stroke_join) == 1)
		hm.undo()
		await frames(4)
		check("deshacer vuelve a Bisel", int(rect.stroke_join) == 2)
		check("la fila refleja el objeto tras deshacer", not row.limit_field.enabled)
	var tm = root.get_node("ThemeManager")
	for theme in ["light", "dark"]:
		tm.set_mode(theme)
		await frames(12)
		sm.set_selection([rect])
		await frames(8)
		await shot("modern_stroke_" + theme)
	rect.queue_free()
	_finish(ui_backup, th_backup)

func _finish(ui_backup: String, th_backup: String) -> void:
	await frames(2)
	for pair in [[UI_CFG, ui_backup], [THEME_CFG, th_backup]]:
		if pair[1] != "":
			var f := FileAccess.open(pair[0], FileAccess.WRITE)
			f.store_string(pair[1])
			f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
