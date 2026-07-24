@tool
class_name VectopenProject
extends Resource

@export var project_name: String = "Untitled"
@export var file_path: String = ""
@export var created_at: int = 0

var artboards: Dictionary = {}
var layers: Dictionary = {}

func _init():
	created_at = Time.get_unix_time_from_system()

func get_artboard(id: String) -> VectopenArtboard:
	return artboards.get(id) as VectopenArtboard

func get_layer(id: String) -> VectopenLayer:
	return layers.get(id) as VectopenLayer

func list_artboard_ids() -> Array[String]:
	return artboards.keys() as Array[String]

func list_layer_ids() -> Array[String]:
	return layers.keys() as Array[String]

func add_artboard(ab: VectopenArtboard):
	artboards[ab.id] = ab

func remove_artboard(id: String):
	artboards.erase(id)

func add_layer(layer: VectopenLayer):
	layers[layer.id] = layer

func remove_layer(id: String):
	layers.erase(id)

func get_safe_name() -> String:
	if project_name.is_empty():
		return "untitled"
	return project_name.replace(" ", "_").replace("/", "_").replace("\\", "_")
