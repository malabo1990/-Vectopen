extends GdUnitTestSuite

const TM := preload("res://script_gdscript/system/ThemeManager.gd")

func test_theme_manager_aplica_tokens() -> void:
	var tm := get_node("/root/ThemeManager")
	assert_object(tm).is_not_null()
	# No dejar el modo del usuario tocado: `set_mode` escribe user://vectopen_theme.cfg.
	var _modo_previo: String = tm.current_mode
	tm.reset_all_custom_colors()

	tm.set_mode("dark")
	var theme := tm.get_tree().root.theme
	assert_object(theme).is_not_null()
	assert_object(theme.get_stylebox("normal", "AffirmativeButton")).is_not_null()
	assert_object(theme.get_stylebox("normal", "NegativeButton")).is_not_null()
	assert_that(tm.get_color(TM.Slot.AFFIRMATIVE).is_equal_approx(Color(0.188, 0.82, 0.345))).is_true()
	assert_that(tm.get_color(TM.Slot.NEGATIVE).is_equal_approx(Color(1.0, 0.271, 0.227))).is_true()

	tm.set_mode("light")
	assert_that(tm.get_color(TM.Slot.AFFIRMATIVE).is_equal_approx(Color(0.204, 0.78, 0.349))).is_true()
	assert_that(tm.get_color(TM.Slot.PANEL_TEXT).is_equal_approx(Color(0.11, 0.11, 0.118))).is_true()

	# restaurar el modo que tenía el usuario antes del test
	tm.set_mode(_modo_previo)

func test_all_five_theme_presets() -> void:
	var tm := get_node("/root/ThemeManager")
	assert_object(tm).is_not_null()
	var _modo_previo: String = tm.current_mode

	var expected_themes = ["light", "godot_blue", "blender_gray", "dark", "dark_contrast"]
	var available = tm.get_available_themes()
	for t in expected_themes:
		assert_bool(available.has(t)).override_failure_message("Falta registrar el tema " + t).is_true()
		tm.set_mode(t)
		assert_str(tm.current_mode).is_equal(t)
		var accent: Color = tm.get_color(TM.Slot.ACCENT)
		assert_that(accent != Color.MAGENTA).override_failure_message("Color accent inválido para " + t).is_true()
		var bg: Color = tm.get_color(TM.Slot.PANEL_BG)
		assert_that(bg != Color.MAGENTA).override_failure_message("Color panel_bg inválido para " + t).is_true()

	# Probar alias "blanco"
	tm.set_mode("blanco")
	assert_str(tm.current_mode).is_equal("light")

	tm.set_mode(_modo_previo)

func test_neutral_accent_tokens() -> void:
	var tm := get_node("/root/ThemeManager")
	assert_object(tm).is_not_null()
	var _modo_previo: String = tm.current_mode

	tm.set_mode("dark")
	var dark_accent: Color = tm.get_color(TM.Slot.ACCENT)
	# Verificar que el acento oscuro no sea azul primario saturado (#6EA8FF) sino neutro
	assert_bool(dark_accent.b <= 0.70).is_true()
	assert_bool(dark_accent.s <= 0.60).is_true()

	tm.set_mode("light")
	var light_accent: Color = tm.get_color(TM.Slot.ACCENT)
	# Verificar que el acento claro no sea el antiguo #007AFF chillón
	assert_bool(light_accent.b <= 0.70).is_true()
	assert_bool(light_accent.s <= 0.75).is_true()

	tm.set_mode(_modo_previo)

func test_make_white_icon() -> void:
	var tm := get_node("/root/ThemeManager")
	assert_object(tm).is_not_null()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var tex := ImageTexture.create_from_image(img)
	var white_tex = tm.make_white_icon(tex)
	assert_object(white_tex).is_not_null()
	var white_img = white_tex.get_image()
	assert_object(white_img).is_not_null()
	assert_that(white_img.get_pixel(0, 0).r).is_equal(1.0)
	assert_that(white_img.get_pixel(0, 0).g).is_equal(1.0)
	assert_that(white_img.get_pixel(0, 0).b).is_equal(1.0)
	assert_that(white_img.get_pixel(0, 0).a).is_equal(1.0)
