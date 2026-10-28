extends GdUnitTestSuite

## Test suite para la arquitectura del Sistema de Interfaz Adaptable (Three UI Modes)
## Modos: Smart Panel (Vectopen) | Modern Panel (Figma) | Professional Panel (Affinity/Illustrator)

const UIModeSelectorScript := preload("res://script_gdscript/ui/ui_mode_selector.gd")
const DockedInspectorScript := preload("res://script_gdscript/ui/docked_inspector.gd")
const AdaptiveUIManagerScript := preload("res://script_gdscript/ui/adaptive_ui_manager.gd")

func after_test() -> void:
	# Siempre restaurar a smart después de cada test
	if is_instance_valid(GlobalUI):
		GlobalUI.set_ui_mode(GlobalUI.MODE_SMART)

func test_default_mode_and_constants() -> void:
	assert_that(GlobalUI.MODE_SMART).is_equal("smart")
	assert_that(GlobalUI.MODE_MODERN).is_equal("modern")
	assert_that(GlobalUI.MODE_PROFESSIONAL).is_equal("professional")
	assert_that(GlobalUI.VALID_MODES).contains(["smart", "modern", "professional"])

func test_set_ui_mode_transitions_and_signals() -> void:
	var received_modes: Array[String] = []
	var on_mode_changed := func(m: String): received_modes.append(m)
	GlobalUI.ui_mode_changed.connect(on_mode_changed)

	# Cambiar a modern
	GlobalUI.set_ui_mode(GlobalUI.MODE_MODERN)
	assert_that(GlobalUI.get_ui_mode()).is_equal("modern")
	assert_that(GlobalUI.is_modern_mode()).is_true()
	assert_that(GlobalUI.is_smart_mode()).is_false()
	assert_that(GlobalUI.is_professional_mode()).is_false()

	# Cambiar a professional
	GlobalUI.set_ui_mode(GlobalUI.MODE_PROFESSIONAL)
	assert_that(GlobalUI.get_ui_mode()).is_equal("professional")
	assert_that(GlobalUI.is_professional_mode()).is_true()
	assert_that(GlobalUI.is_modern_mode()).is_false()
	assert_that(GlobalUI.is_smart_mode()).is_false()

	# Volver a smart
	GlobalUI.set_ui_mode(GlobalUI.MODE_SMART)
	assert_that(GlobalUI.get_ui_mode()).is_equal("smart")
	assert_that(GlobalUI.is_smart_mode()).is_true()

	GlobalUI.ui_mode_changed.disconnect(on_mode_changed)
	assert_that(received_modes).is_equal(["modern", "professional", "smart"])

func test_invalid_mode_rejected() -> void:
	GlobalUI.set_ui_mode(GlobalUI.MODE_SMART)
	GlobalUI.set_ui_mode("modo_inexistente_123")
	assert_that(GlobalUI.get_ui_mode()).is_equal("smart")

func test_persistence_roundtrip() -> void:
	GlobalUI._save_ui_mode(GlobalUI.MODE_MODERN)
	var loaded := GlobalUI._load_ui_mode()
	assert_that(loaded).is_equal("modern")

	# Limpiar y restaurar
	GlobalUI._save_ui_mode(GlobalUI.MODE_SMART)
	assert_that(GlobalUI._load_ui_mode()).is_equal("smart")

func test_ui_mode_selector_widget_interaction() -> void:
	var selector = auto_free(UIModeSelectorScript.new())
	add_child(selector)

	assert_object(selector.btn_smart).is_not_null()
	assert_object(selector.btn_modern).is_not_null()
	assert_object(selector.btn_pro).is_not_null()

	# Simular pulsación en botón Modern
	selector.btn_modern.emit_signal("pressed")
	assert_that(GlobalUI.get_ui_mode()).is_equal("modern")
	assert_that(selector.btn_modern.text).contains("Modern")

	# Simular pulsación en botón Pro
	selector.btn_pro.emit_signal("pressed")
	assert_that(GlobalUI.get_ui_mode()).is_equal("professional")
	assert_that(selector.btn_pro.text).contains("Pro")

	# Simular pulsación en botón Smart
	selector.btn_smart.emit_signal("pressed")
	assert_that(GlobalUI.get_ui_mode()).is_equal("smart")
	assert_that(selector.btn_smart.text).contains("Smart")

func test_docked_inspector_creation_and_components() -> void:
	var inspector = auto_free(DockedInspectorScript.new())
	add_child(inspector)

	assert_object(inspector.lbl_title).is_not_null()
	assert_object(inspector.lbl_selection).is_not_null()
	assert_object(inspector.mode_selector).is_not_null()
	assert_object(inspector.align_container).is_not_null()
	assert_object(inspector.transform_panel).is_not_null()
	assert_object(inspector.picker_fill).is_not_null()
	assert_object(inspector.spin_opacity).is_not_null()
	assert_object(inspector.picker_stroke).is_not_null()
	assert_object(inspector.spin_stroke_width).is_not_null()

func test_docked_inspector_density_modes() -> void:
	var inspector = auto_free(DockedInspectorScript.new())
	add_child(inspector)

	# Modo Modern (densidad estándar)
	inspector.set_density(false)
	assert_that(inspector.custom_minimum_size.x).is_equal(268.0)

	# Modo Professional (alta densidad)
	inspector.set_density(true)
	assert_that(inspector.custom_minimum_size.x).is_equal(286.0)

func test_docked_inspector_selection_label() -> void:
	var inspector = auto_free(DockedInspectorScript.new())
	add_child(inspector)

	inspector._on_selection_size_changed(0)
	assert_that(inspector.lbl_selection.text).is_equal(tr("No selection"))

	inspector._on_selection_size_changed(3)
	assert_that(inspector.lbl_selection.text).is_equal(tr("%d objects selected") % 3)

func test_adaptive_ui_manager_orchestration() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)

	var inspector = DockedInspectorScript.new()
	inspector.name = "DockedInspector"
	host.add_child(inspector)

	var layout := Control.new()
	layout.name = "Layout"
	layout.anchor_left = 1.0
	layout.anchor_right = 1.0
	layout.offset_left = -106.0
	layout.offset_right = 0.0
	host.add_child(layout)

	var manager = AdaptiveUIManagerScript.new()
	manager.docked_inspector = inspector
	manager.layout_node = layout
	host.add_child(manager)

	# 1. Modo Smart por defecto: Canvas First (inspector oculto, capas a la derecha)
	GlobalUI.set_ui_mode(GlobalUI.MODE_SMART)
	assert_that(inspector.visible).is_false()
	assert_that(layout.anchor_left).is_equal(1.0)

	# 2. Conmutar a Modern: Inspector First (inspector visible a la derecha, capas a la izquierda)
	GlobalUI.set_ui_mode(GlobalUI.MODE_MODERN)
	assert_that(inspector.visible).is_true()
	assert_that(inspector.custom_minimum_size.x).is_equal(268.0)
	assert_that(layout.anchor_left).is_equal(0.0)

	# 3. Conmutar a Professional: Alta densidad (ProStudio visible a la derecha, docked_inspector oculto)
	GlobalUI.set_ui_mode(GlobalUI.MODE_PROFESSIONAL)
	assert_that(inspector.visible).is_false()
	assert_object(manager.pro_studio).is_not_null()
	assert_that(manager.pro_studio.visible).is_true()
	assert_that(manager.pro_studio.custom_minimum_size.x).is_equal(AdaptiveUIManager.PRO_RIGHT_W)
	assert_that(layout.anchor_left).is_equal(0.0)

	# 4. Regresar a Smart: Restaurar Canvas First (ProStudio y docked_inspector ocultos)
	GlobalUI.set_ui_mode(GlobalUI.MODE_SMART)
	assert_that(inspector.visible).is_false()
	assert_that(manager.pro_studio.visible).is_false()
	assert_that(layout.anchor_left).is_equal(1.0)
	assert_that(layout.offset_left).is_equal(-106.0)
