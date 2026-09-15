# =============================================================================
# VECTOPEN — PRUEBAS DE PROFESSIONAL STUDIO (AFFINITY & INDESIGN STYLE)
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
	assert_object(studio._sec_layers).override_failure_message("Falta sección capas").is_not_null()
	assert_object(studio._sec_publication).override_failure_message("Falta sección publicación").is_not_null()

func test_pro_studio_color_swatches_and_modes() -> void:
	var studio = auto_free(ProStudioScript.new())
	add_child(studio)
	await get_tree().process_frame

	assert_object(studio._swatch_fill).is_not_null()
	assert_object(studio._swatch_stroke).is_not_null()

	# Cambio de modo RGB a HSL
	studio._toggle_color_mode(true)
	assert_bool(studio._is_hsl_mode).is_true()
	assert_that(studio._lbl_c1.text).is_equal("H")
	assert_float(studio._slider_c1.max_value).is_equal(360.0)

	studio._toggle_color_mode(false)
	assert_bool(studio._is_hsl_mode).is_false()
	assert_that(studio._lbl_c1.text).is_equal("R")
	assert_float(studio._slider_c1.max_value).is_equal(255.0)

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

func test_pro_studio_publication_bleed_and_margins() -> void:
	var studio = auto_free(ProStudioScript.new())
	add_child(studio)
	await get_tree().process_frame

	assert_object(studio._spin_bleed_mm).is_not_null()
	assert_float(studio._spin_bleed_mm.value).is_equal(3.0)
	assert_object(studio._spin_margin_top).is_not_null()
	assert_float(studio._spin_margin_top.value).is_equal(15.0)
