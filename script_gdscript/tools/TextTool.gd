 # =============================================================================
# RUTA: res://script_gdscript/TextTool.gd
# Vectopen — Herramienta de Títulos Avanzada (Edición Síncrona Reparada)
# Soporta: Saltos de línea, Color Negro, Doble Clic Robusto para editar.
# CONTROL INTELIGENTE: CMD (o CTRL) + Arrastre Vertical para escalar fuente.
# =============================================================================
extends ToolBase

# ── Estados Internos de Edición ──────────────────────────────────────────────
var is_editing: bool = false
var current_editing_shape: Node2D = null
var target_artboard: Node2D = null

# ── Estados Internos para el Redimensionado Inteligente (CMD+Drag) ────────────
var is_cmd_scaling: bool = false
var scaling_shape: Node2D = null
var scaling_start_mouse_y: float = 0.0
var scaling_start_font_size: int = 24

# Configuración del redimensionado
const MIN_FONT_SIZE: int = 8
const MAX_FONT_SIZE: int = 300
const SCALING_SENSITIVITY: float = 0.5 

func activate() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_IBEAM)
	_refresh_artboard()

func deactivate() -> void:
	if is_editing:
		_finish_editing_and_save()
	_reset_scaling_state()

func handle_input(event: InputEvent) -> bool:
	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false

	_refresh_artboard()
	if not target_artboard:
		return false

	var gm: Vector2 = canvas.get_global_mouse_position()

	# 1. DETECCIÓN DE DOBLE CLIC (Restaurado el comportamiento original directo)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		if is_cmd_scaling: return true 
		var hit: Node2D = _shape_at(gm)
		if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_title":
			var local_pos = target_artboard.to_local(gm)
			_check_and_trigger_edit_at(local_pos)
			return true

	# 2. GESTIÓN DE CLIC DE RATÓN
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# --- NUEVA LÓGICA CON CMD / CTRL + DRAG ---
			if Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_CTRL):
				var hit: Node2D = _shape_at(gm)
				if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_title":
					_start_cmd_scaling(hit, gm.y)
					return true

			# Clic Fuera al Editar para guardar cambios
			if is_editing and is_instance_valid(current_editing_shape):
				var local_pos: Vector2 = current_editing_shape.to_local(gm)
				var size = _get_current_shape_size(current_editing_shape)
				var rect: Rect2 = Rect2(Vector2.ZERO, size)

				if not rect.has_point(local_pos):
					var saved_shape = current_editing_shape
					_finish_editing_and_save()
					_switch_to_move_tool(saved_shape)
					return true 

				return false

			# Clic en vacío -> Crear nuevo Título
			if not (Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_CTRL)):
				var hit: Node2D = _shape_at(gm)
				if not hit:
					var t := _artboard_for_point(gm)
					if is_instance_valid(t):
						target_artboard = t
					_create_new_title_at(target_artboard.to_local(gm))
					return true
		
		else: # Botón Soltado
			if is_cmd_scaling:
				_confirm_cmd_scaling()
				return true

	# 3. MOVIMIENTO DE RATÓN (Procesado del arrastre vertical)
	if event is InputEventMouseMotion and is_cmd_scaling:
		_process_cmd_scaling(gm.y)
		return true

	return false

# ── Métodos para Edición y Creación ──────────────────────────────────────────

func _check_and_trigger_edit_at(local_pos: Vector2) -> void:
	var gm = target_artboard.to_global(local_pos)
	var hit: Node2D = _shape_at(gm)
	
	if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_title":
		if is_editing: _finish_editing_and_save()
		
		is_editing = true
		current_editing_shape = hit
		
		var display_label: Control = hit.get_node_or_null("DisplayLabel")
		var title_edit: TextEdit = hit.get_node_or_null("TitleEdit")
		
		if display_label: display_label.visible = false
		if title_edit:
			title_edit.visible = true
			title_edit.text = hit.get_meta("text") if hit.has_meta("text") else ""
			
			var fs = hit.get_meta("font_size") if hit.has_meta("font_size") else 24
			title_edit.add_theme_font_size_override("font_size", fs)
			
			_update_shape_meta_size(hit)
			title_edit.grab_focus()
			title_edit.select_all()

func _finish_editing_and_save() -> void:
	if not is_instance_valid(current_editing_shape):
		_reset_state()
		return
		
	var display_label: Control = current_editing_shape.get_node_or_null("DisplayLabel")
	var title_edit: TextEdit = current_editing_shape.get_node_or_null("TitleEdit")
	
	if title_edit:
		var final_text = title_edit.text.strip_edges()
		if final_text == "": final_text = "Título Nuevo"
		
		current_editing_shape.set_meta("text", final_text)
		if display_label:
			display_label.text = final_text
			display_label.visible = true
			
		# Sincronización instantánea de las cajas de colisión y límites visuales
		_update_shape_meta_size(current_editing_shape)
		
		title_edit.release_focus()
		title_edit.visible = false

	_reset_state()

func _create_new_title_at(local_pos: Vector2) -> void:
	var new_title = Node2D.new()
	new_title.name = "TextTitle_Container"
	new_title.set_meta("shape_type", "text_title")
	new_title.set_meta("text", "Título Corporativo")
	new_title.set_meta("font_size", 24)
	
	var label := WorldTextLabel.new()
	label.name = "DisplayLabel"
	label.base_font_size = 24
	label.text = new_title.get_meta("text")
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_font_size_override("font_size", 24)
	
	var edit = TextEdit.new()
	edit.name = "TitleEdit"
	edit.visible = false
	edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE 
	edit.add_theme_color_override("font_color", Color.BLACK)
	edit.add_theme_font_size_override("font_size", 24)
	
	new_title.add_child(label)
	new_title.add_child(edit)
	
	target_artboard.add_child(new_title)
	new_title.position = local_pos
	
	# Actualización limpia sin retrasos de frames
	_update_shape_meta_size(new_title)
	_switch_to_move_tool(new_title)

# ── Métodos para Escalado Inteligente (CMD + Arrastre) ────────────────────────

func _start_cmd_scaling(shape: Node2D, mouse_y: float) -> void:
	is_cmd_scaling = true
	scaling_shape = shape
	scaling_start_mouse_y = mouse_y
	scaling_start_font_size = shape.get_meta("font_size") if shape.has_meta("font_size") else 24
	Input.set_default_cursor_shape(Input.CURSOR_VSIZE)

func _process_cmd_scaling(current_mouse_y: float) -> void:
	if not is_instance_valid(scaling_shape): 
		_reset_scaling_state()
		return
		
	var delta_y = scaling_start_mouse_y - current_mouse_y
	var font_size_delta = int(delta_y * SCALING_SENSITIVITY)
	var new_font_size = clamp(scaling_start_font_size + font_size_delta, MIN_FONT_SIZE, MAX_FONT_SIZE)
	
	var display_label: Control = scaling_shape.get_node_or_null("DisplayLabel")
	var title_edit: TextEdit = scaling_shape.get_node_or_null("TitleEdit")
	
	if display_label:
		var font_changed: bool = display_label.world_font_size != new_font_size if display_label is WorldTextLabel else display_label.get_theme_font_size("font_size") != new_font_size
		if font_changed:
			if display_label is WorldTextLabel:
				display_label.world_font_size = new_font_size
			else:
				display_label.add_theme_font_size_override("font_size", new_font_size)
			if title_edit: title_edit.add_theme_font_size_override("font_size", new_font_size)
			_update_shape_meta_size(scaling_shape)

func _confirm_cmd_scaling() -> void:
	if is_instance_valid(scaling_shape):
		var display_label: Control = scaling_shape.get_node_or_null("DisplayLabel")
		if display_label:
			var final_fs = display_label.world_font_size if display_label is WorldTextLabel else display_label.get_theme_font_size("font_size")
			scaling_shape.set_meta("font_size", final_fs)
			_update_shape_meta_size(scaling_shape)
	_reset_scaling_state()

func _reset_scaling_state() -> void:
	is_cmd_scaling = false
	scaling_shape = null
	Input.set_default_cursor_shape(Input.CURSOR_IBEAM)

# ── Utilidades de Cálculo Inmediato ───────────────────────────────────────────

func _update_shape_meta_size(shape: Node2D) -> void:
	var display_label: Control = shape.get_node_or_null("DisplayLabel")
	var title_edit: TextEdit = shape.get_node_or_null("TitleEdit")
	
	if display_label:
		# get_combined_minimum_size() devuelve el tamaño requerido de forma síncrona inmediata.
		# Si es un WorldTextLabel, el re-rasterizado de zoom infla el mínimo local:
		# pedimos el mínimo EN UNIDADES DE MUNDO (el de diseño).
		var real_size: Vector2 = display_label.get_world_minimum_size() if display_label is WorldTextLabel else display_label.get_combined_minimum_size()
		var safe_size = Vector2(max(real_size.x, 200.0), max(real_size.y, 40.0))
		
		shape.set_meta("width", safe_size.x)
		shape.set_meta("height", safe_size.y)
		
		if display_label is WorldTextLabel:
			display_label.set_world_size(safe_size)
		else:
			display_label.size = safe_size
		if title_edit: title_edit.size = safe_size

func _get_current_shape_size(shape: Node2D) -> Vector2:
	var w: float = shape.get_meta("width") if shape.has_meta("width") else 250.0
	var h: float = shape.get_meta("height") if shape.has_meta("height") else 40.0
	return Vector2(w, h)

func _switch_to_move_tool(shape: Node2D) -> void:
	if is_instance_valid(canvas) and canvas.has_method("change_tool"):
		var move_tool_script = load("res://script_gdscript/tools/MoveTool.gd")
		if move_tool_script:
			var move_tool = canvas._new_tool(move_tool_script)
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
	var mgr := ArtboardManager.find(get_tree()) if get_tree() else null
	if mgr:
		var act := mgr.get_active_artboard()
		if is_instance_valid(act):
			target_artboard = act
			return
	var container = canvas.get_node_or_null("ArtboardsContainer")
	if container and container.get_child_count() > 0:
		target_artboard = container.get_child(0)

func _shape_at(gpos: Vector2) -> Node2D:
	if not target_artboard: return null
	for child in target_artboard.get_children():
		if child is Node2D and child.has_meta("shape_type"):
			var size = _get_current_shape_size(child)
			var r = Rect2(child.global_position, size)
			if r.has_point(gpos):
				return child
	return null
