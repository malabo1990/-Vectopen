# res://scripts/canvas/artboard_manager.gd
extends Node
class_name ArtboardManager

@export var artboards: Array[ArtboardEditor] = []
var active_artboard: ArtboardEditor = null

func _ready() -> void:
	var container = get_tree().current_scene.find_child("ArtboardsContainer", true, false)
	if container:
		for child in container.get_children():
			if child is ArtboardEditor:
				add_artboard(child)
				print("ArtboardManager: registrado dinámicamente → ", child.name)
	print("ArtboardManager: total artboards iniciales = ", artboards.size())

func add_artboard(ab: ArtboardEditor) -> void:
	if not artboards.has(ab):
		artboards.append(ab)

# El artboard individual llama a esta función al recibir un click válido
func set_active_artboard(target_ab: ArtboardEditor) -> void:
	active_artboard = target_ab
	for ab in artboards:
		if ab == target_ab:
			ab.is_selected = true
		else:
			ab.is_selected = false
