extends GdUnitTestSuite

## Test suite para Vectopen Modern UI (Figma UI3 Style — 2026)
## Cubre: Bottom Toolbar flotante, Top Bar, Navigation Rail, Command Palette y Focus Canvas

const ModernBottomToolbarScript := preload("res://script_gdscript/ui/modern/modern_bottom_toolbar.gd")
const ModernTopBarScript := preload("res://script_gdscript/ui/modern/modern_top_bar.gd")
const ModernNavRailScript := preload("res://script_gdscript/ui/modern/modern_nav_rail.gd")
const CommandPaletteScript := preload("res://script_gdscript/ui/modern/command_palette.gd")
const AdaptiveUIManagerScript := preload("res://script_gdscript/ui/adaptive_ui_manager.gd")
const DockedInspectorScript := preload("res://script_gdscript/ui/docked_inspector.gd")

func after_test() -> void:
	if is_instance_valid(GlobalUI):
		GlobalUI.set_ui_mode(GlobalUI.MODE_SMART)

func test_modern_bottom_toolbar_components_and_tools() -> void:
	var tb: Control = auto_free(ModernBottomToolbarScript.new())
	add_child(tb)

	assert_object(tb.btn_zoom_out).is_not_null()
	assert_object(tb.lbl_zoom).is_not_null()
	assert_object(tb.btn_zoom_in).is_not_null()
	assert_that(tb.lbl_zoom.text).is_equal("100%")

	# Herramientas registradas
	assert_that(tb._buttons.has("select")).is_true()
	assert_that(tb._buttons.has("artboard")).is_true()
	assert_that(tb._buttons.has("rectangle")).is_true()
	assert_that(tb._buttons.has("ellipse")).is_true()
	assert_that(tb._buttons.has("pen")).is_true()
	assert_that(tb._buttons.has("text")).is_true()

	# Selección de herramienta emite señal
	var selected_tool: Array[String] = []
	tb.tool_selected.connect(func(t: String): selected_tool.append(t))
	tb._on_tool_button_pressed("rectangle")
	assert_that(selected_tool).contains(["rectangle"])
	assert_that(tb._active_tool).is_equal("rectangle")

func test_modern_bottom_toolbar_zoom_controls() -> void:
	var tb: Control = auto_free(ModernBottomToolbarScript.new())
	add_child(tb)

	tb.set_zoom_percentage(150.0)
	assert_that(tb.lbl_zoom.text).is_equal("150%")

	tb.set_zoom_percentage(75.0)
	assert_that(tb.lbl_zoom.text).is_equal("75%")

func test_modern_top_bar_components() -> void:
	var top_bar: Control = auto_free(ModernTopBarScript.new())
	add_child(top_bar)

	assert_object(top_bar.lbl_title).is_not_null()
	assert_that(top_bar.lbl_title.text).is_equal("Vectopen")
	assert_object(top_bar.lbl_doc_name).is_not_null()
	assert_that(top_bar.lbl_doc_name.text).contains(".vectopen")
	assert_object(top_bar.lbl_status).is_not_null()
	assert_that(top_bar.lbl_status.text).contains("Guardado")
	assert_object(top_bar.btn_undo).is_not_null()
	assert_object(top_bar.btn_redo).is_not_null()
	assert_object(top_bar.btn_export).is_not_null()
	assert_object(top_bar.mode_selector).is_not_null()

func test_modern_nav_rail_sections() -> void:
	var rail: Control = auto_free(ModernNavRailScript.new())
	add_child(rail)

	assert_that(rail._buttons.has("canvas")).is_true()
	assert_that(rail._buttons.has("layers")).is_true()
	assert_that(rail._buttons.has("assets")).is_true()
	assert_that(rail._buttons.has("settings")).is_true()

	var toggled_states: Array[bool] = []
	rail.left_panel_toggled.connect(func(op: bool): toggled_states.append(op))

	# Alternar panel
	rail._on_section_pressed("layers")
	assert_that(rail.is_panel_open()).is_false()

	rail._on_section_pressed("layers")
	assert_that(rail.is_panel_open()).is_true()

	rail._on_section_pressed("assets")
	assert_that(rail.get_active_section()).is_equal("assets")
	assert_that(rail.is_panel_open()).is_true()

func test_command_palette_filtering_and_execution() -> void:
	var cp: Control = auto_free(CommandPaletteScript.new())
	add_child(cp)

	assert_that(cp.visible).is_false()

	cp.open_palette()
	assert_that(cp.visible).is_true()

	# Filtrar por "Rectangle"
	cp.search_edit.text = "rectangle"
	cp._on_search_text_changed("rectangle")
	assert_that(cp._filtered_indices.size()).is_equal(1)

	# Ejecutar comando
	var executed: Array[String] = []
	cp.command_executed.connect(func(id: String): executed.append(id))
	cp._execute_filtered(0)
	assert_that(executed).contains(["tool_rectangle"])
	assert_that(cp.visible).is_false()

func test_adaptive_ui_manager_modern_mode_activation() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)

	var inspector: Control = DockedInspectorScript.new()
	inspector.name = "DockedInspector"
	host.add_child(inspector)

	var layout: Control = Control.new()
	layout.name = "Layout"
	host.add_child(layout)

	var top_bar: Control = ModernTopBarScript.new()
	top_bar.name = "ModernTopBar"
	host.add_child(top_bar)

	var nav_rail: Control = ModernNavRailScript.new()
	nav_rail.name = "ModernNavRail"
	host.add_child(nav_rail)

	var bottom_toolbar: Control = ModernBottomToolbarScript.new()
	bottom_toolbar.name = "ModernBottomToolbar"
	host.add_child(bottom_toolbar)

	var command_pal: Control = CommandPaletteScript.new()
	command_pal.name = "CommandPalette"
	host.add_child(command_pal)

	var manager = AdaptiveUIManagerScript.new()
	manager.docked_inspector = inspector
	manager.layout_node = layout
	manager.modern_top_bar = top_bar
	manager.modern_nav_rail = nav_rail
	manager.modern_bottom_toolbar = bottom_toolbar
	manager.command_palette = command_pal
	host.add_child(manager)

	# 1. Modo Modern UI activado
	GlobalUI.set_ui_mode(GlobalUI.MODE_MODERN)
	assert_that(top_bar.visible).is_true()
	assert_that(nav_rail.visible).is_true()
	assert_that(bottom_toolbar.visible).is_true()
	assert_that(inspector.visible).is_true()

	# 2. Modo Focus Canvas con Tab: oculta todas las barras
	manager._toggle_focus_canvas()
	assert_that(manager.is_focus_canvas_active()).is_true()
	assert_that(top_bar.visible).is_false()
	assert_that(nav_rail.visible).is_false()
	assert_that(bottom_toolbar.visible).is_false()
	assert_that(inspector.visible).is_false()

	# 3. Presionar Tab de nuevo restaura la interfaz
	manager._toggle_focus_canvas()
	assert_that(manager.is_focus_canvas_active()).is_false()
	assert_that(top_bar.visible).is_true()
	assert_that(nav_rail.visible).is_true()
	assert_that(bottom_toolbar.visible).is_true()
	assert_that(inspector.visible).is_true()

	# 4. Modo Smart: oculta todo el chrome de Modern UI
	GlobalUI.set_ui_mode(GlobalUI.MODE_SMART)
	assert_that(top_bar.visible).is_false()
	assert_that(nav_rail.visible).is_false()
	assert_that(bottom_toolbar.visible).is_false()
	assert_that(inspector.visible).is_false()
