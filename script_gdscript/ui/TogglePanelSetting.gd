extends Button

@export var target_panel: Control

func _ready() -> void:
	if not target_panel:
		target_panel = get_node_or_null("Panel_keyboard") as Control
		if not target_panel:
			for child in get_children():
				if child is Control and child != self:
					target_panel = child
					break
		if not target_panel and get_parent():
			for sibling in get_parent().get_children():
				if sibling != self and sibling is Control:
					target_panel = sibling
					break
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if target_panel:
		target_panel.visible = not target_panel.visible
