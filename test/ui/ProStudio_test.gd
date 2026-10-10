# =============================================================================
# VECTOPEN — PRUEBAS DE PROFESSIONAL STUDIO
# RUTA: res://test/ui/ProStudio_test.gd
# =============================================================================
extends GdUnitTestSuite

const ProStudioScript := preload("res://script_gdscript/ui/pro/pro_studio.gd")

func test_pro_studio_initialization_and_sections() -> void:
	var studio = auto_free(ProStudioScript.new())
	add_child(studio)
	await get_tree().process_frame

	assert_object(studio._sec_color).override_failure_message("Falta sección color").is_not_null()
	assert_object(studio._sec_stroke).override_failure_message("Falta sección trazo").is_not_null()
	assert_object(studio._sec_transform).override_failure_message("Falta sección transformar").is_not_null()
	assert_object(studio._sec_swatches).override_failure_message("Falta sección muestras").is_not_null()

func test_pro_studio_color_swatches_and_modes() -> void:
	var studio = auto_free(ProStudioScript.new())
	add_child(studio)
	await get_tree().process_frame

	assert_object(studio._swatch_fill).is_not_null()
	assert_object(studio._swatch_stroke).is_not_null()

	# Desde 2026-09-27 el color se edita con el selector compartido
	# (pickr_color_tool.tscn) dentro de la página, no con deslizadores RGB/HSL.
	assert_object(studio._pickr_instance).is_not_null()
	assert_bool(studio._pickr_instance.get_parent() == studio._sec_color).is_true()
	studio._set_color_target("stroke")
	assert_str(studio._active_color_target).is_equal("stroke")
	studio._set_color_target("fill")
	assert_str(studio._active_color_target).is_equal("fill")

func test_pro_studio_stroke_and_transform_controls() -> void:
	var studio = auto_free(ProStudioScript.new())
	add_child(studio)
	await get_tree().process_frame

	# Matriz de origen 3x3
	assert_int(studio._ref_points.size()).is_equal(9)
	studio._set_active_ref_point(0)
	assert_int(studio._active_ref_point).is_equal(0)

	# Estilo de trazo
	studio._set_stroke_style(1)
	assert_bool(studio._row_dash_params.visible).is_true()

	studio._set_stroke_style(0)
	assert_bool(studio._row_dash_params.visible).is_false()

func test_pro_studio_tabs_show_one_page_per_group() -> void:
	var studio = auto_free(ProStudioScript.new())
	add_child(studio)
	await get_tree().process_frame

	# Compact studio: two tabbed groups, only the active page of each is visible
	assert_bool(studio._sec_color.visible).is_true()
	assert_bool(studio._sec_stroke.visible).is_false()
	assert_bool(studio._sec_transform.visible).is_true()
	assert_bool(studio._sec_effects.visible).is_false()
	studio._select_tab_a(2)
	assert_bool(studio._sec_color.visible).is_false()
	assert_bool(studio._sec_stroke.visible).is_true()
	studio._select_tab_b(2)
	assert_bool(studio._sec_transform.visible).is_false()
	assert_bool(studio._sec_effects.visible).is_true()
	# Layers and pages live in the left dock: no duplicated sections here
	assert_bool("_sec_layers" in studio).is_false()
	assert_bool("_sec_publication" in studio).is_false()
	assert_float(studio.custom_minimum_size.x).is_equal(ProStudioScript.STUDIO_WIDTH)

func test_pro_studio_typography_and_effects() -> void:
	var studio = auto_free(ProStudioScript.new())
	add_child(studio)
	await get_tree().process_frame

	# Secciones presentes
	assert_object(studio._sec_typography).is_not_null()
	assert_object(studio._sec_effects).is_not_null()

	# Tipografía: subtabs
	assert_bool(studio._box_typo_general.visible).is_true()
	assert_bool(studio._box_typo_parrafo.visible).is_false()
	studio._switch_typography_subtab(1)
	assert_bool(studio._box_typo_general.visible).is_false()
	assert_bool(studio._box_typo_parrafo.visible).is_true()

	# Tipografía: Controles presentes y valores válidos
	assert_object(studio._opt_font_family).is_not_null()
	assert_object(studio._spin_font_size).is_not_null()
	assert_float(studio._spin_font_size.value).is_equal(16.0)

	# Efectos y Filtros
	assert_object(studio._chk_drop_shadow).is_not_null()
	assert_object(studio._slider_shadow_blur).is_not_null()
	assert_object(studio._chk_inner_shadow).is_not_null()
	assert_object(studio._chk_outline).is_not_null()
	assert_object(studio._chk_color_overlay).is_not_null()

func test_pro_studio_rotation_clock() -> void:
	var studio = auto_free(ProStudioScript.new())
	add_child(studio)
	await get_tree().process_frame

	# Reloj de rotación
	assert_object(studio._clock_rot).is_not_null()
	studio._clock_rot.angle_degrees = 45.0
	studio._clock_rot.angle_changed.emit(45.0)
	assert_float(studio._spin_rot.value).is_equal(45.0)


func test_pro_studio_adapts_to_light_theme() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm == null:
		return
	var prev_mode: String = tm.current_mode
	var studio = auto_free(ProStudioScript.new())
	add_child(studio)
	await get_tree().process_frame

	# Cambiar tema a modo claro (blanca)
	tm.set_mode("light")
	await get_tree().process_frame

	assert_str(tm.current_mode).is_equal("light")
	assert_object(studio._clock_rot).is_not_null()

	# Restaurar modo previo
	tm.set_mode(prev_mode)

func test_pro_studio_ref_point_neutral_styling() -> void:
	var studio = auto_free(ProStudioScript.new())
	add_child(studio)
	await get_tree().process_frame

	studio._set_active_ref_point(4)
	var active_btn: Button = studio._ref_points[4]
	var sb: StyleBoxFlat = active_btn.get_theme_stylebox("normal")
	assert_object(sb).is_not_null()
	var tm = get_node_or_null("/root/ThemeManager")
	if tm:
		var expected_accent: Color = tm.get_color(tm.Slot.ACCENT)
		assert_that(sb.border_color.is_equal_approx(expected_accent)).is_true()

func test_pro_studio_rebuilds_with_theme_colors() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm == null:
		return
	var prev_mode: String = tm.current_mode
	tm.set_mode("dark")
	var studio = auto_free(ProStudioScript.new())
	add_child(studio)
	await get_tree().process_frame

	# Inactive origin points used to keep the dark style after switching to light
	tm.set_mode("light")
	await get_tree().process_frame
	var idle_btn: Button = studio._ref_points[0]
	var sb: StyleBoxFlat = idle_btn.get_theme_stylebox("normal")
	assert_that(sb.bg_color.is_equal_approx(tm.get_color(tm.Slot.INPUT_BG))).is_true()
	tm.set_mode(prev_mode)

func test_pro_studio_text_align_uses_core_modes() -> void:
	var studio = auto_free(ProStudioScript.new())
	add_child(studio)
	await get_tree().process_frame
	# InspectorCore expects "left" | "center" | "right" | "fill", not indices
	assert_array(ProStudioScript.TEXT_ALIGN_MODES).is_equal(["left", "center", "right", "fill"])
	studio._set_text_alignment(1)
	assert_int(studio._text_align).is_equal(1)
