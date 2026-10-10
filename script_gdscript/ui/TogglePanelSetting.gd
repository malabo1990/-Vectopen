extends Button

@export var target_panel: Control:
	set(value):
		if is_instance_valid(target_panel) and target_panel.visibility_changed.is_connected(_on_target_visibility_changed):
			target_panel.visibility_changed.disconnect(_on_target_visibility_changed)
		target_panel = value
		if is_instance_valid(target_panel):
			if not target_panel.visibility_changed.is_connected(_on_target_visibility_changed):
				target_panel.visibility_changed.connect(_on_target_visibility_changed)
			_sync_state()

func _ready() -> void:
	if not target_panel:
		target_panel = get_node_or_null("Panel_keyboard") as Control
		if not target_panel:
			for child in get_children():
				if child is Control and child != self:
					target_panel = child
					break

	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

	if is_instance_valid(target_panel):
		if not target_panel.visibility_changed.is_connected(_on_target_visibility_changed):
			target_panel.visibility_changed.connect(_on_target_visibility_changed)
		_sync_state()

func _sync_state() -> void:
	if toggle_mode and is_instance_valid(target_panel):
		set_pressed_no_signal(target_panel.visible)

func _on_target_visibility_changed() -> void:
	_sync_state()

func _on_pressed() -> void:
	if is_instance_valid(target_panel):
		target_panel.visible = not target_panel.visible

		if target_panel.visible:
			target_panel.move_to_front()
			var p: Node = get_parent()
			while is_instance_valid(p) and p.get_parent() != target_panel.get_parent():
				p = p.get_parent()
			if is_instance_valid(p) and p is CanvasItem:
				(p as CanvasItem).move_to_front()

		_sync_state()
