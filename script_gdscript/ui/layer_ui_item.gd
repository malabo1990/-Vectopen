# res://scripts/layer_ui_item.gd
class_name LayerUIItem
extends PanelContainer

signal layer_reparented(item: LayerUIItem, target_parent: LayerUIItem, index: int)

var data: LayerItem
var is_selected: bool = false

# Elementos de la UI alineados horizontalmente
var visibility_check: CheckBox
var mask_check: CheckBox
var thumbnail: TextureRect
var name_label: Label
var name_edit: LineEdit

func _init() -> void:
	# Configuración del contenedor de la fila (Estilo Mac compacto)
	custom_minimum_size.y = 30
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_corporate_style()
	
	# Contenedor Horizontal Base
	var hbox = HBoxContainer.new()
	add_child(hbox)
	
	# 1. Checkbox para Visibilidad (Ojo / Check)
	visibility_check = CheckBox.new()
	visibility_check.flat = true
	visibility_check.toggled.connect(_on_visibility_toggled)
	hbox.add_child(visibility_check)
	
	# 2. Checkbox para Máscara de Recorte
	mask_check = CheckBox.new()
	mask_check.flat = true
	mask_check.text = "M"
	mask_check.toggled.connect(_on_mask_toggled)
	hbox.add_child(mask_check)
	
	# 3. TextureRect para la miniatura del Lienzo/Viewport
	thumbnail = TextureRect.new()
	thumbnail.custom_minimum_size = Vector2(22, 22)
	thumbnail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumbnail.modulate = Color(0.8, 0.8, 0.8) 
	hbox.add_child(thumbnail)
	
	# Space intermedio sutil
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(4, 0)
	hbox.add_child(spacer)
	
	# 4. Contenedor del Nombre (Label y LineEdit superpuestos)
	var name_container = MarginContainer.new()
	name_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_container)
	
	name_label = Label.new()
	name_label.clip_text = true
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_container.add_child(name_label)
	
	name_edit = LineEdit.new()
	name_edit.visible = false
	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.focus_exited.connect(_on_name_focus_exited)
	name_edit.add_theme_font_size_override("font_size", 12)
	name_container.add_child(name_edit)

func setup(layer_data: LayerItem) -> void:
	data = layer_data
	name_label.text = data.name
	name_edit.text = data.name
	visibility_check.button_pressed = data.visible
	mask_check.button_pressed = data.is_clipping_mask

# --- DETECCIÓN DE DOBLE CLIC ---
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			_start_editing_name()

func _start_editing_name() -> void:
	name_label.visible = false
	name_edit.visible = true
	name_edit.grab_focus()
	name_edit.select_all()

func _on_name_submitted(new_text: String) -> void:
	if new_text.strip_edges() != "":
		data.name = new_text
		name_label.text = new_text
	_stop_editing_name()

func _on_name_focus_exited() -> void:
	_on_name_submitted(name_edit.text)

func _stop_editing_name() -> void:
	name_edit.visible = false
	name_label.visible = true

func _on_visibility_toggled(is_visible: bool) -> void:
	data.visible = is_visible

func _on_mask_toggled(is_mask: bool) -> void:
	data.is_clipping_mask = is_mask

# --- GESTIÓN NATIVA DE DRAG & DROP (ARRASTRAR Y SOLTAR) ---
func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview = PanelContainer.new()
	var preview_style = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	preview_style.bg_color = Color(0.22, 0.22, 0.22, 0.8)
	preview.add_theme_stylebox_override("panel", preview_style)
	
	var preview_label = Label.new()
	preview_label.text = " Mover: " + data.name + " "
	preview_label.add_theme_font_size_override("font_size", 13)
	preview.add_child(preview_label)
	
	set_drag_preview(preview)
	return self 

func _can_drop_data(_at_position: Vector2, data_dropped: Variant) -> bool:
	return data_dropped is LayerUIItem and data_dropped != self

func _drop_data(_at_position: Vector2, data_dropped: Variant) -> void:
	var dropped_item = data_dropped as LayerUIItem
	var my_index = get_index()
	
	# Si se suelta en la mitad inferior de la celda, se inserta debajo
	if _at_position.y > size.y / 2:
		my_index += 1
		
	layer_reparented.emit(dropped_item, self, my_index)

func _apply_corporate_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.14, 0.14) 
	style.border_width_bottom = 1
	style.border_color = Color(0.2, 0.2, 0.2) 
	style.content_margin_left = 6
	style.content_margin_right = 6
	add_theme_stylebox_override("panel", style)
