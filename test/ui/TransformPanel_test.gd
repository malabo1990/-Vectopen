extends GdUnitTestSuite

## Panel de transformación compacto: campos X/Y/W/H + dial de rotación + 4 diales
## de radio de esquina, sincronizados en dos vías con InspectorCore (con undo).

const CANVAS := "res://scenes/canvas/canvas.tscn"
const PANEL := "res://scenes/ui/transform_panel.tscn"

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


func test_panel_refleja_la_seleccion() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var r := _rect(_ab(s))
	await get_tree().process_frame

	var panel = auto_free(load(PANEL).instantiate())
	add_child(panel)
	await get_tree().process_frame

	t.selected_shapes.assign([r]); InspectorCore._sync_selection()
	InspectorCore.changed.emit(InspectorCore.current_props())
	await get_tree().process_frame

	assert_str(panel._fields["pos_x"].displayed_text()).is_equal("120")
	assert_str(panel._fields["pos_y"].displayed_text()).is_equal("90")
	assert_str(panel._fields["width"].displayed_text()).is_equal("80")


func test_editar_campo_x_mueve_la_figura_con_undo() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var r := _rect(_ab(s))
	await get_tree().process_frame
	var panel = auto_free(load(PANEL).instantiate())
	add_child(panel)
	await get_tree().process_frame
	t.selected_shapes.assign([r]); InspectorCore._sync_selection()
	InspectorCore.changed.emit(InspectorCore.current_props())
	await get_tree().process_frame
	HistoryManager.clear()

	panel._fields["pos_x"].type_value(300.0)
	assert_float(r.get_doc_position().x).is_equal_approx(300.0, 0.5)
	assert_bool(HistoryManager.can_undo()).is_true()
	HistoryManager.undo(); await get_tree().process_frame
	assert_float(r.get_doc_position().x).is_equal_approx(120.0, 0.5)
	HistoryManager.clear()


## Arrastrar el campo Y (scrub) mueve la figura en vivo y deja UNA acción de undo.
func test_arrastrar_campo_y_scrub_con_undo() -> void:
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

	var f = panel._fields["pos_y"]
	f.drag_started.emit()
	f.value = 90.0
	f.value_changed.emit(140.0)   # simula el arrastre: +50
	f.value = 140.0
	f.drag_ended.emit()
	await get_tree().process_frame

	assert_float(r.get_doc_position().y).is_equal_approx(140.0, 0.5)
	assert_bool(HistoryManager.can_undo()).is_true()
	HistoryManager.undo(); await get_tree().process_frame
	assert_float(r.get_doc_position().y).is_equal_approx(90.0, 0.5)
	HistoryManager.clear()


func test_dial_de_rotacion_aplica_una_accion_de_undo() -> void:
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

	# simula: pulsar (snapshot) → arrastrar (preview) → soltar (commit)
	panel._rot.drag_started.emit()
	panel._rot.value = 45.0
	panel._rot.value_changed.emit(45.0)
	panel._rot.drag_ended.emit()
	await get_tree().process_frame

	assert_float(rad_to_deg(r.get_doc_rotation())).is_equal_approx(45.0, 0.5)
	assert_bool(HistoryManager.can_undo()).is_true()
	HistoryManager.undo(); await get_tree().process_frame
	assert_float(rad_to_deg(r.get_doc_rotation())).is_equal_approx(0.0, 0.5)
	HistoryManager.clear()


func test_dial_de_esquina_pone_radio_independiente() -> void:
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

	var d = panel._corners["corner_tl"]
	d.drag_started.emit()
	d.value = 12.0
	d.value_changed.emit(12.0)
	d.drag_ended.emit()
	await get_tree().process_frame

	assert_float(r.corner_tl).is_equal_approx(12.0, 0.01)
	assert_float(r.corner_tr).is_equal_approx(0.0, 0.01)   # solo la esquina TL
	HistoryManager.undo(); await get_tree().process_frame
	assert_float(r.corner_tl).is_equal_approx(0.0, 0.01)
	HistoryManager.clear()
