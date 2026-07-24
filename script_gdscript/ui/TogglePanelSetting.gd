extends Button

@export var target_panel: PanelContainer

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if target_panel:
		target_panel.visible = not target_panel.visible
