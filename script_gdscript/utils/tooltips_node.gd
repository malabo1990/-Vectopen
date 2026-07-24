extends Control

# Propiedades exportadas con @export
@export var button_to_track: Button
@export var tooltip_node: Node

func _ready():
	if button_to_track:
		tooltip_node.visible = false
		button_to_track.mouse_entered.connect(_on_button_entered)
		button_to_track.mouse_exited.connect(_on_button_exited)

func _on_button_entered():
	tooltip_node.visible = true

func _on_button_exited():
	tooltip_node.visible = false
