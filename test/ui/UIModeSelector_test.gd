# =============================================================================
# VECTOPEN — PRUEBAS DEL SELECTOR SMART / MODERN / PRO
# RUTA: res://test/ui/UIModeSelector_test.gd
# Regresión: los 3 chips del switcher tenían todos sus colores hardcodeados
# (nunca leían ThemeManager) — se veían como un parche claro pegado encima
# de cualquier tema oscuro. Ver script_gdscript/ui/ui_mode_selector.gd.
# =============================================================================
extends GdUnitTestSuite

const UIModeSelectorScript := preload("res://script_gdscript/ui/ui_mode_selector.gd")

func test_active_chip_color_follows_theme_manager() -> void:
	var tm := get_node("/root/ThemeManager")
	assert_object(tm).is_not_null()
	var _modo_previo: String = tm.current_mode

	var sel = auto_free(UIModeSelectorScript.new())
	add_child(sel)
	await get_tree().process_frame

	tm.set_mode("dark")
	await get_tree().process_frame
	var dark_active_bg: Color = sel._style_active.bg_color
	assert_that(dark_active_bg.is_equal_approx(tm.get_color(tm.Slot.SURFACE_RAISED))).is_true()

	tm.set_mode("light")
	await get_tree().process_frame
	var light_active_bg: Color = sel._style_active.bg_color
	assert_that(light_active_bg.is_equal_approx(tm.get_color(tm.Slot.SURFACE_RAISED))).is_true()

	# Los dos temas tienen fondos "elevados" distintos — si esto fuera igual
	# en los dos, seguiría hardcodeado a un solo valor fijo.
	assert_that(dark_active_bg.is_equal_approx(light_active_bg)).is_false()

	tm.set_mode(_modo_previo)

func test_switching_ui_mode_updates_the_active_button() -> void:
	var sel = auto_free(UIModeSelectorScript.new())
	add_child(sel)
	await get_tree().process_frame

	sel._update_active_button("modern")
	assert_str(sel._current_mode).is_equal("modern")
	assert_object(sel.btn_modern.get_theme_stylebox("normal")).is_equal(sel._style_active)
	assert_object(sel.btn_smart.get_theme_stylebox("normal")).is_equal(sel._style_inactive)
	assert_object(sel.btn_pro.get_theme_stylebox("normal")).is_equal(sel._style_inactive)

	sel._update_active_button("professional")
	assert_str(sel._current_mode).is_equal("professional")
	assert_object(sel.btn_pro.get_theme_stylebox("normal")).is_equal(sel._style_active)
	assert_object(sel.btn_modern.get_theme_stylebox("normal")).is_equal(sel._style_inactive)

func test_theme_change_repaints_all_three_states_normal_hover_pressed() -> void:
	var tm := get_node("/root/ThemeManager")
	assert_object(tm).is_not_null()
	var _modo_previo: String = tm.current_mode

	var sel = auto_free(UIModeSelectorScript.new())
	add_child(sel)
	await get_tree().process_frame
	sel._update_active_button("smart")

	tm.set_mode("dark")
	await get_tree().process_frame
	var stylebox_after_dark: StyleBoxFlat = sel._style_active

	tm.set_mode("light")
	await get_tree().process_frame

	# El botón activo (Smart) tiene que reflejar el estilo NUEVO en los 3
	# estados — antes del fix, "hover"/"pressed" quedaban con el StyleBox
	# viejo (referencia congelada al momento de crear el botón), solo
	# "normal" se actualizaba.
	assert_object(sel.btn_smart.get_theme_stylebox("normal")).is_equal(sel._style_active)
	assert_object(sel.btn_smart.get_theme_stylebox("hover")).is_equal(sel._style_active)
	assert_object(sel.btn_smart.get_theme_stylebox("pressed")).is_equal(sel._style_active)
	assert_that(sel._style_active).is_not_equal(stylebox_after_dark)

	tm.set_mode(_modo_previo)
