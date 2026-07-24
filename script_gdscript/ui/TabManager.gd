extends Node

signal button_clicked(index: int)

@export var control_a: NodePath
@export var control_b: NodePath

var _signal_used: bool = false

func _ready() -> void:
	_signal_used = true

	if control_a:
		var control_a_node = get_node_or_null(control_a)
		if control_a_node:
			var num_hijos_a = control_a_node.get_child_count()
			for i in range(num_hijos_a):
				var child = control_a_node.get_child(i)
				if child is Button and child.name != "cancel":
					child.pressed.connect(_on_control_a_activated.bind(i))
				elif child is Control:
					child.gui_input.connect(_on_control_a_gui_input.bind(i))

	if control_b:
		var control_b_node = get_node_or_null(control_b)
		if control_b_node:
			var num_hijos_b = control_b_node.get_child_count()
			for i in range(num_hijos_b):
				var child = control_b_node.get_child(i)
				child.visible = (i == 0)

func _on_control_a_activated(index: int) -> void:
	if _signal_used:
		button_clicked.emit(index)
	_update_control_b_visibility(index)
	_update_tab_buttons(index)

func _on_control_a_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _signal_used:
			button_clicked.emit(index)
		_update_control_b_visibility(index)
		_update_tab_buttons(index)

func _update_tab_buttons(index: int) -> void:
	if control_a:
		var control_a_node = get_node_or_null(control_a)
		if control_a_node:
			for i in range(control_a_node.get_child_count()):
				var child = control_a_node.get_child(i)
				if child is Button:
					child.button_pressed = (i == index)

func _update_control_b_visibility(index: int) -> void:
	if control_b:
		var control_b_node = get_node_or_null(control_b)
		if control_b_node:
			var num_hijos_b = control_b_node.get_child_count()
			if index < num_hijos_b:
				for i in range(num_hijos_b):
					var child = control_b_node.get_child(i)
					child.visible = (i == index)
					if child.visible:
						child.queue_redraw()

func connect_button_clicked(target: Object, method: StringName) -> void:
	button_clicked.connect(Callable(target, method))
