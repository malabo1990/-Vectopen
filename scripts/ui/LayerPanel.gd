extends Control

@onready var layer_tree = $LayerTree
@onready var add_layer_btn = $AddLayerButton
@onready var delete_layer_btn = $DeleteLayerButton

var current_artboard_id: String = ""

func _ready():
	add_layer_btn.pressed.connect(_add_new_layer)
	delete_layer_btn.pressed.connect(_delete_selected_layer)
	
	# Asegúrate de que GlobalEvents sea un Autoload registrado
	GlobalEvents.active_artboard_changed.connect(_on_artboard_changed)
	GlobalEvents.layer_created.connect(_on_layer_created)
	GlobalEvents.layer_deleted.connect(_on_layer_deleted)

# Corregido: Type hint para evitar errores si 'Layer' no es una clase global
func update_layer_tree(layers: Array):
	layer_tree.clear()
	
	for layer in layers:
		var tree_item = layer_tree.create_item()
		tree_item.set_text(0, layer.layer_name)
		tree_item.set_metadata(0, layer.layer_id)
		tree_item.set_editable(0, true)
		
		# Icono de visibilidad (Godot 4 usa iconos de tema o texturas)
		# Nota: 'Visible' y 'Lock' son nombres de iconos del editor, 
		# si es para un juego final, usa tus propias texturas.
		tree_item.add_button(0, get_theme_icon("Visible", "EditorIcons"), 0, false, "Toggle Visibility")
		tree_item.add_button(0, get_theme_icon("Lock", "EditorIcons"), 1, false, "Toggle Lock")
		
		tree_item.set_selectable(0, true)

func _add_new_layer():
	if current_artboard_id != "":
		GlobalEvents.layer_created.emit(
			"layer_" + str(Time.get_ticks_msec()),
			"New Layer",
			current_artboard_id
		)

func _delete_selected_layer():
	var selected = layer_tree.get_selected()
	if selected:
		var layer_id = selected.get_metadata(0)
		GlobalEvents.layer_deleted.emit(layer_id)

func _on_artboard_changed(artboard_id: String):
	current_artboard_id = artboard_id
	# Al cambiar de artboard, refrescamos la lista
	update_layer_tree(_get_current_layers())

# Corregidos los avisos (Unused Parameter) usando guiones bajos
func _on_layer_created(_layer_id: String, _layer_name: String, artboard_id: String):
	if artboard_id == current_artboard_id:
		update_layer_tree(_get_current_layers())

func _on_layer_deleted(_layer_id: String):
	update_layer_tree(_get_current_layers())

# FUNCIÓN NUEVA: Esta es la que faltaba
func _get_current_layers() -> Array:
	# Aquí debes conectar con tu lógica de datos (p. ej. ArtboardManager)
	# Por ahora, devolvemos un array vacío para que no de error
	# Ejemplo de cómo se vería si tuvieras un manager:
	# return ArtboardManager.get_layers_for(current_artboard_id)
	print("Solicitando capas para: ", current_artboard_id)
	return []
