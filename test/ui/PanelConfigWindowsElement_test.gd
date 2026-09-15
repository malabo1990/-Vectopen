extends GdUnitTestSuite

## Pruebas para Panel_config_windows_element:
## Validación de módulos (papel, dispositivos, red social, logo, icono),
## alternancia de orientación (vertical/horizontal), búsqueda y aplicación de tamaños con Undo/Redo.

const CANVAS := "res://scenes/canvas/canvas.tscn"
const PANEL := "res://scenes/ui/transform_panel.tscn"
const PRESET_WINDOW := "res://scenes/ui/panel_config_windows_element.tscn"

func _scene() -> Node2D:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s); get_tree().current_scene = s; auto_free(s)
	return s

func _tool(s: Node2D):
	var t = s.current_tool
	if not (t and t.get_class_name() == "MoveTool"):
		s.switch_tool("move"); t = s.current_tool
	return t

func _rect(parent: Node) -> VectorRectangle:
	var r := VectorRectangle.new()
	r.size = Vector2(80, 60)
	parent.add_child(r)
	r.set_doc_position(DVec2.new(120, 90))
	r.set_doc_extent(DVec2.from_v2(r.size))
	return r

func _ab(s: Node2D) -> ArtboardEditor:
	return (s.get_node("manager_script") as ArtboardManager).get_active_artboard()


func test_preset_window_instantiation_and_modules() -> void:
	var win: PanelConfigWindowsElement = auto_free(load(PRESET_WINDOW).instantiate())
	add_child(win)
	await get_tree().process_frame

	assert_object(win).is_not_null()
	assert_str(win.name).is_equal("Panel_config_windows_element")

	# Comprobar 5 módulos
	var expected_modules: Array[String] = ["papel", "dispositivos", "red_social", "logo", "icono"]
	for mod in expected_modules:
		win.switch_module(mod)
		assert_str(win.current_module).is_equal(mod)
		assert_bool(win.preset_buttons.size() > 0).is_true()


func test_preset_window_orientation_toggle() -> void:
	var win: PanelConfigWindowsElement = auto_free(load(PRESET_WINDOW).instantiate())
	add_child(win)
	await get_tree().process_frame

	assert_bool(win.is_horizontal).is_false()
	win.toggle_orientation()
	assert_bool(win.is_horizontal).is_true()
	win.toggle_orientation()
	assert_bool(win.is_horizontal).is_false()


func test_preset_window_filter_search() -> void:
	var win: PanelConfigWindowsElement = auto_free(load(PRESET_WINDOW).instantiate())
	add_child(win)
	await get_tree().process_frame

	win.switch_module("papel")
	var initial_count: int = win.preset_buttons.size()
	assert_bool(initial_count >= 5).is_true()

	win.search_edit.text = "A4"
	win._on_search_changed("A4")
	assert_int(win.preset_buttons.size()).is_equal(1)

	win.search_edit.text = ""
	win._on_search_changed("")
	assert_int(win.preset_buttons.size()).is_equal(initial_count)


func test_transform_panel_toggle_presets_window() -> void:
	var s := _scene(); await get_tree().process_frame
	var panel = auto_free(load(PANEL).instantiate())
	add_child(panel)
	await get_tree().process_frame

	assert_object(panel._btn_presets).is_not_null()
	assert_object(panel._config_window).is_not_null()
	assert_bool(panel._config_window.visible).is_false()

	# Abrir ventana de presets mediante el botón de la barra de transformación
	panel._btn_presets.pressed.emit()
	await get_tree().process_frame
	assert_bool(panel._config_window.visible).is_true()

	# Volver a pulsar para cerrar
	panel._btn_presets.pressed.emit()
	await get_tree().process_frame
	assert_bool(panel._config_window.visible).is_false()


func test_apply_preset_to_shape_with_undo() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var r := _rect(_ab(s))
	await get_tree().process_frame

	var panel = auto_free(load(PANEL).instantiate())
	add_child(panel)
	await get_tree().process_frame

	t.selected_shapes.assign([r]); InspectorCore._sync_selection()
	InspectorCore.changed.emit(InspectorCore.current_props())
	HistoryManager.clear()

	# Aplicar un tamaño concreto (p.ej. Logo Cuadrado 500x500)
	panel._config_window.apply_preset(500.0, 500.0, "Logo Cuadrado")
	await get_tree().process_frame

	assert_float(r.size.x).is_equal_approx(500.0, 0.01)
	assert_float(r.size.y).is_equal_approx(500.0, 0.01)

	# Undo debe restaurar el tamaño original (80x60)
	HistoryManager.undo()
	await get_tree().process_frame
	assert_float(r.size.x).is_equal_approx(80.0, 0.01)
	assert_float(r.size.y).is_equal_approx(60.0, 0.01)
	HistoryManager.clear()
