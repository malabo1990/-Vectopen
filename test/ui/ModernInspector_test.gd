# =============================================================================
# VECTOPEN — PRUEBAS DE MODERN UI INSPECTOR (FIGMA UI3 / PENPOT 2026 STYLE)
# RUTA: res://test/ui/ModernInspector_test.gd
# =============================================================================
extends GdUnitTestSuite

const DockedInspectorScript := preload("res://script_gdscript/ui/docked_inspector.gd")
const ModernTopBarScript := preload("res://script_gdscript/ui/modern/modern_top_bar.gd")

func test_header_no_mode_selector_and_no_duplicate_export() -> void:
	var inspector = auto_free(DockedInspectorScript.new())
	add_child(inspector)

	# 1. mode_selector existe para API/tests pero NO es visible en el inspector
	assert_object(inspector.mode_selector).is_not_null()
	assert_bool(inspector.mode_selector.visible).is_false()

	# 2. ModernTopBar export button está disponible en la barra superior
	var top_bar = auto_free(ModernTopBarScript.new())
	add_child(top_bar)
	assert_object(top_bar.btn_export).is_not_null()
	assert_bool(top_bar.btn_export.visible).is_true()

func test_empty_selection_shows_canvas_properties_and_hides_shape_sections() -> void:
	var inspector = auto_free(DockedInspectorScript.new())
	add_child(inspector)

	# Simular sin selección (0 elementos)
	inspector._on_selection_size_changed(0)

	assert_that(inspector.lbl_title.text).is_equal("Page")
	assert_that(inspector.lbl_selection.text).is_equal("No selection")
	assert_bool(inspector.sec_canvas.visible).is_true()
	assert_bool(inspector.sec_align.visible).is_false()
	assert_bool(inspector.transform_panel.visible).is_false()
	assert_bool(inspector.sec_appearance.visible).is_false()
	assert_bool(inspector.sec_fill.visible).is_false()
	assert_bool(inspector.sec_stroke.visible).is_false()
	assert_bool(inspector.sec_effects.visible).is_false()
	assert_bool(inspector.sec_export.visible).is_false()

func test_active_selection_shows_shape_sections_and_hides_canvas_properties() -> void:
	var inspector = auto_free(DockedInspectorScript.new())
	add_child(inspector)

	# Simular selección de 1 objeto
	inspector._on_selection_size_changed(1)

	assert_that(inspector.lbl_selection.text).is_equal("1 object selected")
	assert_bool(inspector.sec_canvas.visible).is_false()
	assert_bool(inspector.sec_align.visible).is_true()
	assert_bool(inspector.transform_panel.visible).is_true()
	assert_bool(inspector.sec_appearance.visible).is_true()
	assert_bool(inspector.sec_fill.visible).is_true()
	assert_bool(inspector.sec_stroke.visible).is_true()
	assert_bool(inspector.sec_effects.visible).is_true()
	assert_bool(inspector.sec_export.visible).is_true()

func test_transform_panel_compact_figma_grid() -> void:
	var inspector = auto_free(DockedInspectorScript.new())
	add_child(inspector)
	inspector._on_selection_size_changed(1)

	var tp = inspector.transform_panel
	assert_object(tp).is_not_null()

	# 1. Campos de posición (Fila 1: X | Y)
	assert_object(tp._fields.get("pos_x")).is_not_null()
	assert_object(tp._fields.get("pos_y")).is_not_null()

	# 2. Campos de dimensión (Fila 2: W | H con candado 🔗)
	assert_object(tp._fields.get("width")).is_not_null()
	assert_object(tp._fields.get("height")).is_not_null()
	assert_object(tp._btn_aspect).is_not_null()

	# 3. Rotación y radio de esquinas (Fila 3: ∠ | ⌜ con toggle ⊞)
	assert_object(tp._rot).is_not_null()
	assert_object(tp._corners.get("corner_tl")).is_not_null()
	assert_object(tp._btn_link_corners).is_not_null()

	# 4. Esquinas expandibles independientes (TR, BR, BL)
	assert_object(tp._corners.get("corner_tr")).is_not_null()
	assert_object(tp._corners.get("corner_br")).is_not_null()
	assert_object(tp._corners.get("corner_bl")).is_not_null()

func test_property_rows_compact_structure() -> void:
	var inspector = auto_free(DockedInspectorScript.new())
	add_child(inspector)
	inspector._on_selection_size_changed(1)

	# 1. Fill: picker + hex + eye + minus
	assert_object(inspector.picker_fill).is_not_null()
	assert_object(inspector.lbl_fill_hex).is_not_null()

	# 2. Stroke: picker + width + align + eye + minus
	assert_object(inspector.picker_stroke).is_not_null()
	assert_object(inspector.spin_stroke_width).is_not_null()
	assert_object(inspector.opt_stroke_align).is_not_null()

	# 3. Effects: chip + config + eye + minus
	assert_object(inspector.btn_shadow_toggle).is_not_null()

	# 4. Export: format + export button
	assert_object(inspector.opt_export_format).is_not_null()
	assert_object(inspector.btn_export_selection).is_not_null()

func test_3d_model_inspector_section() -> void:
	var inspector = auto_free(DockedInspectorScript.new())
	add_child(inspector)

	# 1. Sin selección -> sec_3d_model oculta
	inspector._on_selection_size_changed(0)
	assert_bool(inspector.sec_3d_model.visible).is_false()

	# 2. Selección de objeto 3D
	var VectorModel3DScript = preload("res://script_gdscript/shapes/VectorModel3D.gd")
	var m: Node2D = auto_free(VectorModel3DScript.new())
	m.name = "ModelGLB"
	m.model_rotation = Vector3(12, 34, 56)
	m.camera_distance = 4.2
	m.camera_fov = 50.0

	var sm = get_node_or_null("/root/SelectionManager")
	if sm:
		sm.select(m)

	inspector._on_selection_size_changed(1)

	assert_bool(inspector.sec_3d_model.visible).is_true()
	assert_bool(inspector.sec_fill.visible).is_false()
	assert_bool(inspector.sec_stroke.visible).is_false()
	assert_object(inspector.spin_3d_rot_x).is_not_null()
	assert_object(inspector.spin_3d_rot_y).is_not_null()
	assert_object(inspector.spin_3d_rot_z).is_not_null()
	assert_object(inspector.spin_3d_distance).is_not_null()
	assert_object(inspector.spin_3d_fov).is_not_null()
	assert_object(inspector.spin_3d_light_energy).is_not_null()
	assert_object(inspector.btn_3d_reset_view).is_not_null()

	assert_float(inspector.spin_3d_rot_x.value).is_equal_approx(12.0, 0.001)
	assert_float(inspector.spin_3d_rot_y.value).is_equal_approx(34.0, 0.001)
	assert_float(inspector.spin_3d_rot_z.value).is_equal_approx(56.0, 0.001)
	assert_float(inspector.spin_3d_distance.value).is_equal_approx(4.2, 0.001)
	assert_float(inspector.spin_3d_fov.value).is_equal_approx(50.0, 0.001)

	# 3. Limpiar selección
	if sm:
		sm.clear()
	inspector._on_selection_size_changed(0)
	assert_bool(inspector.sec_3d_model.visible).is_false()


