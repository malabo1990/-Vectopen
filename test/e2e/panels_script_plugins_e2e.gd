# =============================================================================
# UX-05: Script y Complementos (plugins) en Modern y Pro. Se usan con clics:
# abrir la sección, escribir y ejecutar un script, ver la lista de
# complementos y activar uno. Al cambiar de modo el script abierto y los
# complementos activos se conservan; Smart sigue teniendo su pestaña Script.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/panels_script_plugins_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const OUT := "user://panels_script_plugins"
const MARK := "# ux05-e2e"
var fails := 0
var _addon_id := ""
var _addon_was := false

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

func send(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		Input.warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await process_frame

func click_at(at: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = at
	mv.global_position = at
	await send(mv)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = at
		ev.global_position = at
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		await send(ev)
	await frames(4)

## Clic real en el centro del control; falla si no se ve o algo lo tapa.
func click(c: Control, what: String) -> bool:
	if c == null or not c.is_visible_in_tree():
		check("se puede pulsar " + what, false, "no visible")
		return false
	var sc := _scroll_of(c)
	if sc:
		sc.ensure_control_visible(c)
		await frames(3)
	var at := c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = at
	mv.global_position = at
	await send(mv)
	var hit := root.gui_get_hovered_control()
	var reach := hit == c or (hit != null and c.is_ancestor_of(hit))
	check("se puede pulsar " + what, reach, str(hit))
	await click_at(at)
	return reach

func _scroll_of(c: Node) -> ScrollContainer:
	var n := c.get_parent()
	while n:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null

func visible_named(name: String) -> Control:
	for c in root.find_children(name, "Control", true, false):
		if (c as Control).is_visible_in_tree():
			return c
	return null

func any_named(name: String) -> Control:
	var l := root.find_children(name, "Control", true, false)
	return l[0] if l.size() > 0 else null

## Hace visible la sección Script del inspector del modo (en Pro está en la
## pestaña «Efectos» del estudio).
func reach_section(mode: String) -> Control:
	var sec := visible_named("SecScript")
	if sec == null and mode == "professional":
		for b in root.find_children("*", "Button", true, false):
			if (b as Button).text.strip_edges() == "Efectos" and (b as Button).is_visible_in_tree():
				await click(b, "pestaña Efectos (Pro)")
				break
		sec = visible_named("SecScript")
	return sec

func test_mode(mode: String, first: bool) -> void:
	var gui = root.get_node("GlobalUI")
	gui.set_ui_mode(mode)
	await frames(40)
	var sec := await reach_section(mode)
	check(mode + ": sección Script visible sin selección", sec != null)
	if sec == null:
		await shot(mode + "_sin_script")
		return
	if not sec.is_open():
		await click(sec.get_node("Header"), mode + ": cabecera SCRIPT")
	await frames(6)
	var panel := sec.find_child("ScriptContent", true, false) as Control
	check(mode + ": panel de scripts montado", panel != null and panel.is_visible_in_tree())
	if panel == null:
		return
	var code: CodeEdit = panel.get("_code")
	if first:
		code.text = MARK + "\nprint(\"hola ux05\")\n"
		code.text_changed.emit()
	else:
		check(mode + ": conserva el script abierto en el otro modo", code.text.begins_with(MARK), code.text.left(40))
	await frames(2)
	await click(panel._btn_run, mode + ": ▶ Ejecutar")
	for _i in 60:
		if not panel._running:
			break
		await process_frame
	check(mode + ": el script se ejecuta (sale en la consola)", panel._console.get_parsed_text().contains("hola ux05"), panel._console.get_parsed_text().right(80))
	await shot(mode + "_script")

	await click(panel._tab_addons, mode + ": pestaña Complementos")
	var cards: Array = panel._addon_list.get_children().filter(func(c): return c.has_meta("addon_card"))
	check(mode + ": lista de complementos", cards.size() > 0, str(cards.size()))
	var pm: Node = root.get_node("PluginManager")
	if cards.size() > 0:
		var card: Control = cards[0]
		var id := String(card.name).trim_prefix("Addon_")
		var chk: CheckBox = card.find_child("Enabled", true, false)
		if first:
			_addon_id = id
			_addon_was = pm.is_enabled(id)
			await click(chk, mode + ": activar/desactivar «%s»" % id)
			check(mode + ": el complemento cambia de estado", pm.is_enabled(id) != _addon_was)
		else:
			var c2 = panel._addon_list.find_child("Addon_" + _addon_id, true, false)
			var chk2: CheckBox = c2.find_child("Enabled", true, false) if c2 else null
			check(mode + ": el estado del complemento se conserva", chk2 != null and chk2.button_pressed == pm.is_enabled(_addon_id) and pm.is_enabled(_addon_id) != _addon_was)
	await shot(mode + "_complementos")
	await click(panel._tab_scripts, mode + ": volver a Scripts")

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

	await test_mode("modern", true)
	await test_mode("professional", false)
	await test_mode("modern", false)

	# Smart: la ventana de Efectos sigue teniendo su pestaña Script.
	root.get_node("GlobalUI").set_ui_mode("smart")
	await frames(40)
	var host := any_named("panel__effects")
	var script_host: Node = host.find_child("Script", true, false) if host else null
	check("smart: la ventana de Efectos conserva la pestaña Script", script_host != null)

	var pm: Node = root.get_node("PluginManager")
	if _addon_id != "" and pm.is_enabled(_addon_id) != _addon_was:
		if _addon_was:
			pm.enable(_addon_id)
		else:
			pm.disable(_addon_id)
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		if f:
			f.store_string(ui_backup)
	print("RESULT: %s (%d fallos)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
