extends Node2D
class_name Layer

@export var layer_id: String = ""
@export var layer_name: String = "Layer"
@export var parent_artboard_id: String = "" # Cambiado nombre para evitar confusión
@export var is_layer_visible: bool = true   # Cambiado para evitar Shadowing
@export var is_locked: bool = false
@export var opacity: float = 1.0
@export var blend_mode: int = 0  

var objects: Array[String] = []  
# Si 'Effect' es otra clase, asegúrate de que no tenga errores de indentación
var effects: Array = [] 

func _ready():
	visible = is_layer_visible
	modulate.a = opacity

func add_object(object_id: String):
	if not objects.has(object_id):
		objects.append(object_id)

func remove_object(object_id: String):
	objects.erase(object_id)

func set_layer_visibility(p_visible: bool): # 'p_visible' evita conflicto con 'visible'
	is_layer_visible = p_visible
	visible = p_visible
	GlobalEvents.layer_visibility_toggled.emit(layer_id, p_visible)

func set_locked(p_locked: bool):
	is_locked = p_locked
	GlobalEvents.layer_locked_toggled.emit(layer_id, p_locked)

func set_opacity(value: float):
	opacity = clamp(value, 0.0, 1.0)
	modulate.a = opacity

func apply_effect(effect):
	effects.append(effect)
	if effect.has_method("apply_to_layer"):
		effect.apply_to_layer(self)

func to_svg() -> String:
	var svg = '<g id="%s" opacity="%f">' % [layer_id, opacity]
	for object_id in objects:
		var obj = get_node_or_null(object_id)
		if obj and obj.has_method("to_svg"):
			svg += obj.to_svg()
	svg += "</g>"
	return svg

func get_state() -> Dictionary:
	return {
		"id": layer_id,
		"name": layer_name,
		"visible": is_layer_visible,
		"locked": is_locked,
		"opacity": opacity,
		"objects": objects.duplicate()
	}

# Usamos un tipo genérico 'Node' si Artboard sigue dando error de carga
func copy_to(target_artboard: Node):
	if target_artboard.has_method("create_layer"):
		var new_layer = target_artboard.create_layer(layer_name + " (copy)")
		for object_id in objects:
			var obj = get_node_or_null(object_id)
			if obj and obj.has_method("copy_to_layer"):
				obj.copy_to_layer(new_layer)
