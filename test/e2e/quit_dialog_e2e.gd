# =============================================================================
# Diálogo «Cambios sin guardar» (estilo de la app): en tema claro y oscuro
# se abre con la tarjeta y los tres botones con color con significado
# (Guardar verde, Cancelar amarillo, No guardar rojo), con contraste de
# texto suficiente (WCAG AA ≥ 4,5); Esc lo cierra sin salir. Capturas en
# user://quit_dialog.
#   test/run_e2e.sh quit_dialog_e2e
# =============================================================================
extends SceneTree

const OUT := "user://quit_dialog"
var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(120.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

func contrast(a: Color, b: Color) -> float:
	var la := lum(a)
	var lb := lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

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
	var sm = root.get_node("SaveManager")
	var tm = root.get_node("ThemeManager")
	var before_mode = tm.get("current_mode")
	sm.is_modified = true
	for theme in ["light", "dark"]:
		tm.set_mode(theme)
		await frames(10)
		sm._show_quit_dialog()
		await frames(6)
		var d = sm._quit_dialog
		check("%s: el diálogo se abre" % theme, d != null and d.visible)
		var card := d.find_child("Card", true, false) as Control
		check("%s: tarjeta con el estilo de la app (no ventana del sistema)" % theme, card != null and card.is_visible_in_tree() and not (d is Window))
		var card_bg: Color = (card.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
		# Guardar: verde sólido; Cancelar: borde ámbar; No guardar: rojo en borde y texto
		var bs := d.find_child("BtnSave", true, false) as Button
		var sbs := bs.get_theme_stylebox("normal") as StyleBoxFlat
		check("%s: Guardar verde sólido con texto legible (%.1f)" % [theme, contrast(sbs.bg_color, bs.get_theme_color("font_color"))],
			sbs.bg_color.is_equal_approx(Color("1e7d45")) and contrast(sbs.bg_color, bs.get_theme_color("font_color")) >= 4.5)
		var bc := d.find_child("BtnCancel", true, false) as Button
		var sbc := bc.get_theme_stylebox("normal") as StyleBoxFlat
		check("%s: Cancelar con borde ámbar y texto legible (%.1f)" % [theme, contrast(card_bg, bc.get_theme_color("font_color"))],
			sbc.border_color.is_equal_approx(Color("d99a00")) and contrast(card_bg, bc.get_theme_color("font_color")) >= 4.5)
		var bd := d.find_child("BtnDiscard", true, false) as Button
		var sbd := bd.get_theme_stylebox("normal") as StyleBoxFlat
		var red_txt: Color = bd.get_theme_color("font_color")
		check("%s: No guardar en rojo (borde y texto) legible (%.1f)" % [theme, contrast(card_bg, red_txt)],
			red_txt.r > red_txt.g * 1.5 and sbd.border_color == red_txt and contrast(card_bg, red_txt) >= 4.5)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT.path_join("%s.png" % theme))
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = true
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await frames(4)
		var up := ev.duplicate()
		up.pressed = false
		Input.parse_input_event(up)
		await frames(4)
		check("%s: Esc cierra el diálogo (Cancelar)" % theme, not d.visible)
	sm.is_modified = false
	if before_mode != null:
		tm.set_mode(before_mode)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
