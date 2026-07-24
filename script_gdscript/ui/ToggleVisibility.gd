extends Node

@export var target_node_path: NodePath
@export var button_toggle_path: NodePath

var _target_node: Node
var _button_toggle: Node
var _is_initialized: bool = false

func _ready() -> void:
	_update_target_node()
	_update_button_node()
	_setup_signal_connection()

func _update_target_node() -> void:
	if not is_inside_tree():
		return
	_target_node = get_node_or_null(target_node_path)
	if not _target_node:
		push_error("Error: 'target_node_path' (%s) does not point to a valid node." % target_node_path)
		return
	if not "visible" in _target_node:
		push_error("Error: Target node does not have a 'visible' property.")
		_target_node = null

func _update_button_node() -> void:
	if not is_inside_tree():
		return
	_button_toggle = get_node_or_null(button_toggle_path)
	if not _button_toggle:
		push_error("Error: 'button_toggle_path' (%s) does not point to a valid node." % button_toggle_path)

func _setup_signal_connection() -> void:
	if _is_initialized or not _button_toggle or not _target_node:
		return
	if not _button_toggle.has_signal("pressed"):
		push_error("Toggle node does not have 'pressed' signal.")
		return
	if not _button_toggle.pressed.is_connected(_on_toggle_activated):
		_button_toggle.pressed.connect(_on_toggle_activated)
	_is_initialized = true

func _on_toggle_activated() -> void:
	if _target_node:
		_target_node.visible = not _target_node.visible

func _exit_tree() -> void:
	if _button_toggle and _button_toggle.pressed.is_connected(_on_toggle_activated):
		_button_toggle.pressed.disconnect(_on_toggle_activated)
	_is_initialized = false
