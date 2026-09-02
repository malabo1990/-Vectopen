extends BoxContainer

@export var grid_check: CheckButton
@export var grid_size_spin: Node
@export var object_check: CheckButton
@export var guide_check: CheckButton

func _ready() -> void:
	var sm: Node = get_node_or_null("/root/SnapManager")
	if not sm:
		return
	if grid_check:
		grid_check.button_pressed = sm.grid_enabled
		grid_check.toggled.connect(_on_grid_toggled)
	if grid_size_spin:
		grid_size_spin.value = sm.grid_size
		grid_size_spin.value_changed.connect(_on_grid_size_changed)
	if object_check:
		object_check.button_pressed = sm.snap_to_objects
		object_check.toggled.connect(_on_object_toggled)
	if guide_check:
		guide_check.button_pressed = sm.snap_to_guides
		guide_check.toggled.connect(_on_guide_toggled)

func _get_sm() -> Node:
	return get_node_or_null("/root/SnapManager")

func _on_grid_toggled(enabled: bool) -> void:
	var sm := _get_sm()
	if sm and sm.has_method("set_grid_enabled"):
		sm.set_grid_enabled(enabled)

func _on_grid_size_changed(p_size: float) -> void:
	var sm := _get_sm()
	if sm and sm.has_method("set_grid_size"):
		sm.set_grid_size(p_size)

func _on_object_toggled(enabled: bool) -> void:
	var sm := _get_sm()
	if sm and sm.has_method("set_snap_to_objects"):
		sm.set_snap_to_objects(enabled)

func _on_guide_toggled(enabled: bool) -> void:
	var sm := _get_sm()
	if sm and sm.has_method("set_snap_to_guides"):
		sm.set_snap_to_guides(enabled)
