extends GdUnitTestSuite

## Menú contextual del botón derecho (tool_in_Mouse.tscn): sus botones
## Copy/Paste/Duplicate/Remove deben estar CONECTADOS a acciones reales de
## MoveTool. Antes no hacían nada.

const TOOL_IN_MOUSE := "res://scenes/ui/tool_in_mouse.tscn"
const _MENU := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/PanelContainer/VBoxContainer"

func test_botones_del_menu_contextual_estan_conectados() -> void:
	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	add_child(panel)
	await get_tree().process_frame

	for nombre in ["Paste", "Copy", "Duplicate", "Remove"]:
		var b := panel.get_node_or_null(_MENU + "/" + nombre) as Button
		assert_object(b).override_failure_message("falta botón " + nombre).is_not_null()
		# el script raíz (clickrigth_nodo.gd) conecta pressed → _on_accion
		assert_int(b.pressed.get_connections().size()) \
			.override_failure_message(nombre + " sin conexiones").is_greater(0)


func test_remove_llama_a_delete_selected_de_move_tool() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	get_tree().current_scene = s
	await get_tree().process_frame

	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	s.add_child(panel)
	await get_tree().process_frame

	var mgr := s.get_node("manager_script") as ArtboardManager
	var ab := mgr.get_active_artboard()
	var r := VectorRectangle.new()
	r.size = Vector2(40, 40)
	ab.add_child(r)
	r.global_position = Vector2(200, 200)
	await get_tree().process_frame

	var t = s.current_tool
	t.selected_shapes.assign([r])
	HistoryManager.clear()

	var remove_btn := panel.get_node(_MENU + "/Remove") as Button
	remove_btn.pressed.emit()
	await get_tree().process_frame

	assert_bool(is_instance_valid(r) and r.is_inside_tree()).is_false()
	assert_bool(HistoryManager.can_undo()).is_true()   # con undo
	assert_bool(panel.visible).is_false()              # el menú se cierra
	HistoryManager.clear()
	if is_instance_valid(r): r.free()
