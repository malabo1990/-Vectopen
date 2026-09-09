extends Node

@export var trigger_node: Node
@export var target_node: Node

func _ready() -> void:
	var me: Variant = self
	if trigger_node == null and (me is Button or me is BaseButton):
		trigger_node = self
	if target_node == null and get_parent():
		for sibling in get_parent().get_children():
			if sibling != self and (sibling is PanelContainer or (sibling is Control and (sibling.name.begins_with("Config") or sibling.name.begins_with("Panel")))):
				target_node = sibling
				break
	if trigger_node and target_node:
		if trigger_node.has_signal("pressed"):
			if not trigger_node.pressed.is_connected(_on_toggle):
				trigger_node.pressed.connect(_on_toggle)
		elif trigger_node.has_signal("input_event"):
			if not trigger_node.input_event.is_connected(_on_input_event):
				trigger_node.input_event.connect(_on_input_event)

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event.is_action_pressed("click_izquierdo") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		_on_toggle()

func _on_toggle() -> void:
	if "visible" in target_node:
		target_node.visible = not target_node.visible
