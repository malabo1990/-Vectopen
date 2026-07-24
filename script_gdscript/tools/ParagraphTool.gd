# =============================================================================
# RUTA: res://script_gdscript/ParagraphTool.gd
# Vectopen — Herramienta de Párrafos (MultiLineEdit) con Texto en Color Negro
# =============================================================================
extends Tool

var is_editing: bool = false
var current_editing_shape: Node2D = null
var target_artboard: Node2D = null

func _init(p_canvas: Node2D) -> void:
	super(p_canvas)

func activate() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_IBEAM)
	_refresh_artboard()

func deactivate() -> void:
	if is_editing:
		_finish_editing_and_save()

func handle_input(event: InputEvent) -> bool:
	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false

	_refresh_artboard()
	if not target_artboard:
		return false

	var gm: Vector2 = canvas.get_global_mouse_position()

	# 1. DETECCIÓN DE DOBLE CLIC: Para editar un párrafo
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		var hit: Node2D = _shape_at(gm)
		if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_paragraph":
			var local_pos = target_artboard.to_local(gm)
			_check_and_trigger_edit_at(local_pos)
			return true

	# 2. GESTIÓN DE CLIC SIMPLE
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		
		# CASO A: Si ya estamos editando y hacemos clic FUERA del bloque de texto
		if is_editing and is_instance_valid(current_editing_shape):
			var local_pos: Vector2 = current_editing_shape.to_local(gm)
			var w: float = current_editing_shape.get_meta("width") if current_editing_shape.has_meta("width") else 350.0
			var h: float = current_editing_shape.get_meta("height") if current_editing_shape.has_meta("height") else 100.0
			var rect: Rect2 = Rect2(Vector2.ZERO, Vector2(w, h))

			if not rect.has_point(local_pos):
				var saved_shape = current_editing_shape
				_finish_editing_and_save()
				_switch_to_move_tool(saved_shape)
				return true

			return false

		# CASO B: Clic en lienzo vacío -> Crea párrafo estático negro y cambia a MoveTool
		var hit: Node2D = _shape_at(gm)
		if not hit:
			_create_new_paragraph_at(target_artboard.to_local(gm))
			return true

	return false

func _check_and_trigger_edit_at(local_pos: Vector2) -> void:
	var gm = target_artboard.to_global(local_pos)
	var hit: Node2D = _shape_at(gm)
	
	if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_paragraph":
		is_editing = true
		current_editing_shape = hit
		
		var display_label: Label = hit.get_node_or_null("DisplayLabel")
		var multi_edit: TextEdit = hit.get_node_or_null("MultiLineEdit")
		
		if display_label: display_label.visible = false
		if multi_edit:
			multi_edit.visible = true
			multi_edit.text = hit.get_meta("text") if hit.has_meta("text") else ""
			multi_edit.grab_focus()

func _finish_editing_and_save() -> void:
	if not is_instance_valid(current_editing_shape):
		_reset_state()
		return
		
	var display_label: Label = current_editing_shape.get_node_or_null("DisplayLabel")
	var multi_edit: TextEdit = current_editing_shape.get_node_or_null("MultiLineEdit")
	
	if multi_edit:
		var final_text = multi_edit.text.strip_edges()
		if final_text == "": final_text = "Texto de párrafo vacío."
		
		current_editing_shape.set_meta("text", final_text)
		if display_label:
			display_label.text = final_text
			display_label.visible = true
		
		multi_edit.release_focus()
		multi_edit.visible = false

	_reset_state()

func _create_new_paragraph_at(local_pos: Vector2) -> void:
	var new_para = Node2D.new()
	new_para.name = "TextParagraph_Container"
	new_para.set_meta("shape_type", "text_paragraph")
	new_para.set_meta("width", 350.0)
	new_para.set_meta("height", 100.0)
	new_para.set_meta("text", "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam nec diam interdum, laoreet lacus id, aliquet magna.")
	
	var label = Label.new()
	label.name = "DisplayLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(350, 100)
	label.size = Vector2(350, 100)
	label.text = new_para.get_meta("text")
	# Forzar color de fuente a negro
	label.add_theme_color_override("font_color", Color.BLACK)
	
	var edit = TextEdit.new()
	edit.name = "MultiLineEdit"
	edit.visible = false
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.custom_minimum_size = Vector2(350, 100)
	edit.size = Vector2(350, 100)
	# Forzar color de fuente a negro en el editor
	edit.add_theme_color_override("font_color", Color.BLACK)
	
	new_para.add_child(label)
	new_para.add_child(edit)
	
	target_artboard.add_child(new_para)
	new_para.position = local_pos
	
	_switch_to_move_tool(new_para)

func _switch_to_move_tool(shape: Node2D) -> void:
	if is_instance_valid(canvas) and canvas.has_method("change_tool"):
		var move_tool_script = load("res://script_gdscript/tools/MoveTool.gd")
		if move_tool_script:
			var move_tool = move_tool_script.new(canvas)
			move_tool.target_artboard = target_artboard
			
			if "selected_shapes" in move_tool:
				if move_tool.selected_shapes is Array:
					move_tool.selected_shapes.clear()
					move_tool.selected_shapes.append(shape)
				else:
					move_tool.selected_shapes = shape
			elif "selection" in move_tool:
				if move_tool.selection is Array:
					move_tool.selection.clear()
					move_tool.selection.append(shape)
				else:
					move_tool.selection = shape
			elif "selected_shape" in move_tool:
				move_tool.selected_shape = shape
				
			canvas.change_tool(move_tool)

func _reset_state() -> void:
	is_editing = false
	current_editing_shape = null

func _refresh_artboard() -> void:
	var container = canvas.get_node_or_null("ArtboardsContainer")
	if container and container.get_child_count() > 0:
		target_artboard = container.get_child(0)

func _shape_at(gpos: Vector2) -> Node2D:
	if not target_artboard: return null
	for child in target_artboard.get_children():
		if child is Node2D and child.has_meta("shape_type"):
			var w = child.get_meta("width") if child.has_meta("width") else 350.0
			var h = child.get_meta("height") if child.has_meta("height") else 100.0
			var r = Rect2(child.global_position, Vector2(w, h))
			if r.has_point(gpos):
				return child
	return null
