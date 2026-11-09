# =============================================================================
# CONFIGURACIÓN — ventana de ajustes (⚙): sus pestañas cambian de página y
# el tamaño de la interfaz se puede cambiar SIN teclado (tableta): botones
# grandes − / + y la lista, en la primera pestaña.
#   test/run_e2e.sh settings_ui_e2e
# =============================================================================
extends SceneTree

const OUT := "user://settings_ui"
var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
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
	root.get_texture().get_image().save_png(OUT.path_join(name))

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
	var gui = root.get_node("GlobalUI")
	gui.set_ui_mode("modern")
	await frames(30)
	root.get_node("GlobalEvents").emit_safe("request_settings_dialog")
	await frames(20)
	var win: Control = null
	for n in root.find_children("*", "ManagerWindowsRegla", true, false):
		win = n
	if win == null:
		for n in root.find_children("MANAGER WINDWS_REGLA", "", true, false):
			win = n
	check("se abre la ventana de configuración", win != null and win.is_visible_in_tree())
	if win == null:
		quit(1)
		return
	await shot("0_abierta.png")
	var tabs := win.find_child("tab", true, false) as Container
	var i := 0
	for b in tabs.get_children():
		if not (b is Button):
			continue
		(b as Button).pressed.emit()
		await frames(8)
		await shot("tab_%d_%s.png" % [i, b.name])
		var shown := []
		var cont := win.find_child("Container", true, false)
		for page in cont.get_children():
			if page is CanvasItem and (page as CanvasItem).visible:
				shown.append(String(page.name))
		print("TAB ", b.name, " → ", shown)
		i += 1
	# Pestaña Ventana: tamaño de la interfaz SIN teclado
	(tabs.get_child(0) as Button).pressed.emit()
	await frames(8)
	var svc = root.get_node_or_null("UIScaleService")
	var plus := win.find_child("UIScalePlus", true, false) as Button
	var minus := win.find_child("UIScaleMinus", true, false) as Button
	var auto := win.find_child("UIScaleAuto", true, false) as Button
	var lst := win.find_child("UIScaleList", true, false) as OptionButton
	check("botones − / + / Auto y la lista de tamaños a la vista", plus != null and minus != null and auto != null and lst != null and plus.is_visible_in_tree())
	check("botones grandes para tocar (≥ 30 px)", plus != null and plus.size.y >= 30.0, str(plus.size if plus else Vector2.ZERO))
	for k in ["Mode_windowed", "Mode_fullscreen", "Mode_borderless", "Size_0", "Size_3", "MaximizeOnStart"]:
		check("hay control «%s»" % k, win.find_child(k, true, false) != null)
	await shot("ventana_nueva.png")
	if svc and plus:
		var s0: float = svc.current_scale()
		plus.pressed.emit()
		await frames(6)
		var s1: float = svc.current_scale()
		check("+ agranda la interfaz", s1 > s0 + 0.01, "%.2f → %.2f" % [s0, s1])
		check("la lista muestra el tamaño elegido", lst.get_item_text(lst.selected) == "%d %%" % int(round(s1 * 100.0)), lst.get_item_text(lst.selected))
		await shot("ventana_mas_grande.png")
		minus.pressed.emit()
		minus.pressed.emit()
		await frames(6)
		check("− achica la interfaz", svc.current_scale() < s1 - 0.01, "%.2f" % svc.current_scale())
		lst.select(3)
		lst.item_selected.emit(3)
		await frames(4)
		check("elegir de la lista (100 %)", absf(svc.current_scale() - 1.0) < 0.01, "%.2f" % svc.current_scale())
		auto.pressed.emit()
		await frames(6)
		check("Auto vuelve al tamaño automático", svc.is_auto() and lst.selected == 0)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
