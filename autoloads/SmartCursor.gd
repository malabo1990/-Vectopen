# =============================================================================
# VECTOPEN CORE — SMART MOUSE SYSTEM
# RUTA: res://autoloads/SmartCursor.gd
# =============================================================================
extends Node

## Sistema de cursor inteligente para Vectopen
## Delega la máquina de estados a CursorStateMachine (RefCounted).

signal cursor_changed(shape: int, color: Color, animation: int, size: float)

var _fsm: CursorStateMachine = null
var _accessibility_mode: bool = false

# ==========================================
# CICLO DE VIDA
# ==========================================

func _ready() -> void:
	_fsm = CursorStateMachine.new()
	_update_cursor()

	if GlobalEvents:
		if GlobalEvents.has_signal("data_tool_changed"):
			GlobalEvents.data_tool_changed.connect(_on_tool_changed)
		if GlobalEvents.has_signal("data_selection_changed"):
			GlobalEvents.data_selection_changed.connect(_on_selection_changed)
		if GlobalEvents.has_signal("performance_warning"):
			GlobalEvents.performance_warning.connect(_on_error_occurred)


func _process(delta: float) -> void:
	_fsm.update(delta)
	_update_cursor()


# ==========================================
# API PÚBLICA
# ==========================================

func set_state(state: int) -> void:
	if _fsm.current_state == state:
		return
	_fsm.set_state(state)
	cursor_changed.emit(_fsm.current_shape, _fsm.current_color, _fsm.current_animation, _fsm.current_size * _fsm.pulse_factor)


func set_interactive_element(interactive: bool) -> void:
	_fsm.set_interactive_element(interactive)
	cursor_changed.emit(_fsm.current_shape, _fsm.current_color, _fsm.current_animation, _fsm.current_size * _fsm.pulse_factor)


func set_size(size: float) -> void:
	_fsm.set_size(size)


func get_current_state() -> int:
	return _fsm.current_state


func get_current_color() -> Color:
	return _fsm.current_color


func get_current_size() -> float:
	return _fsm.current_size


func get_current_shape() -> int:
	return _fsm.current_shape


func get_pulse_factor() -> float:
	return _fsm.pulse_factor


func get_halo_factor() -> float:
	return _fsm.halo_factor


func get_rotation_angle() -> float:
	return _fsm.rotation_angle


func set_accessibility_mode(enabled: bool) -> void:
	_accessibility_mode = enabled


# ==========================================
# MANEJO DE SEÑALES
# ==========================================

func _on_tool_changed(tool_name: String) -> void:
	match tool_name:
		"MoveTool", "SelectTool":
			set_state(CursorStateMachine.CursorState.ACTIVE)
		"BrushTool", "PenTool", "RectangleTool", "CircleTool":
			set_state(CursorStateMachine.CursorState.CREATIVE)
		"TextTool", "ParagraphTool":
			set_state(CursorStateMachine.CursorState.TEXT_EDIT)
		"EraserTool":
			set_state(CursorStateMachine.CursorState.WARNING)
		_:
			set_state(CursorStateMachine.CursorState.NEUTRAL)


func _on_selection_changed() -> void:
	if DataRepository and DataRepository.get_selected_count() > 0:
		set_state(CursorStateMachine.CursorState.ACTIVE)
	else:
		set_state(CursorStateMachine.CursorState.NEUTRAL)


func _on_error_occurred(_error_msg: String) -> void:
	set_state(CursorStateMachine.CursorState.WARNING)
	get_tree().create_timer(2.0).timeout.connect(_restore_state)



func _restore_state() -> void:
	if DataRepository and DataRepository.get_selected_count() > 0:
		set_state(CursorStateMachine.CursorState.ACTIVE)
	elif ToolManager and ToolManager.get_current_tool_name():
		_on_tool_changed(ToolManager.get_current_tool_name())
	else:
		set_state(CursorStateMachine.CursorState.NEUTRAL)


func _update_cursor() -> void:
	var final_size = _fsm.current_size * _fsm.pulse_factor
	Input.set_default_cursor_shape(_fsm.animation_to_cursor_shape())
	cursor_changed.emit(_fsm.current_shape, _fsm.current_color, _fsm.current_animation, final_size)
