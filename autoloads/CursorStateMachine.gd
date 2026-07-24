# =============================================================================
# VECTOPEN CORE — CURSOR STATE MACHINE
# RUTA: res://autoloads/CursorStateMachine.gd
# =============================================================================
extends RefCounted
class_name CursorStateMachine

## Máquina de estados para el cursor.
## Gestiona la relación estado → forma/color/animación sin atarse al lifecycle de Godot.


# ==========================================
# ENUMERACIONES
# ==========================================

enum CursorShape {
	ROUNDED_TRIANGLE,
	CIRCLE,
	CROSSHAIR,
	HAND,
	I_BEAM,
	CUSTOM
}

enum CursorAnimation {
	NONE,
	PULSE,
	COLOR_TRANSITION,
	HALO,
	ROTATION
}

enum CursorState {
	NEUTRAL,
	ACTIVE,
	CREATIVE,
	CONFIRM,
	WARNING,
	DISABLED,
	TEXT_EDIT,
	DRAGGING,
	PRECISION
}


# ==========================================
# CONSTANTES
# ==========================================

const STATE_COLORS := {
	CursorState.NEUTRAL: Color.BLACK,
	CursorState.ACTIVE: Color(0.05, 0.55, 0.91, 1.0),
	CursorState.CREATIVE: Color(1.0, 0.0, 1.0, 1.0),
	CursorState.CONFIRM: Color(0.13, 0.69, 0.3, 1.0),
	CursorState.WARNING: Color(0.91, 0.3, 0.24, 1.0),
	CursorState.DISABLED: Color(0.5, 0.5, 0.5, 1.0),
	CursorState.TEXT_EDIT: Color(0.2, 0.2, 0.2, 1.0),
	CursorState.DRAGGING: Color(0.05, 0.55, 0.91, 1.0),
	CursorState.PRECISION: Color(0.1, 0.1, 0.1, 1.0)
}

const CURSOR_BASE_SIZE: float = 24.0
const CURSOR_MIN_SIZE: float = 16.0
const CURSOR_MAX_SIZE: float = 48.0
const CURSOR_PULSE_SPEED: float = 1.5
const CURSOR_COLOR_TRANSITION_SPEED: float = 0.2
const CURSOR_HALO_SIZE: float = 1.5
const CURSOR_ROTATION_SPEED: float = 0.5


# ==========================================
# ESTADO ACTUAL
# ==========================================

var current_state: CursorState = CursorState.NEUTRAL
var current_shape: CursorShape = CursorShape.ROUNDED_TRIANGLE
var current_animation: CursorAnimation = CursorAnimation.NONE
var current_color: Color = STATE_COLORS[CursorState.NEUTRAL]
var target_color: Color = STATE_COLORS[CursorState.NEUTRAL]
var current_size: float = CURSOR_BASE_SIZE
var target_size: float = CURSOR_BASE_SIZE
var animation_progress: float = 0.0
var rotation_angle: float = 0.0
var pulse_factor: float = 1.0
var halo_factor: float = 0.0
var interactive_element: bool = false


# ==========================================
# API — CAMBIO DE ESTADO
# ==========================================

func set_state(new_state: CursorState) -> void:
	if current_state == new_state:
		return

	current_state = new_state
	target_color = STATE_COLORS.get(new_state, Color.BLACK)

	match new_state:
		CursorState.NEUTRAL:
			current_shape = CursorShape.ROUNDED_TRIANGLE
			current_animation = CursorAnimation.NONE
		CursorState.ACTIVE:
			current_shape = CursorShape.ROUNDED_TRIANGLE
			current_animation = CursorAnimation.PULSE
		CursorState.CREATIVE:
			current_shape = CursorShape.ROUNDED_TRIANGLE
			current_animation = CursorAnimation.COLOR_TRANSITION
		CursorState.CONFIRM:
			current_shape = CursorShape.ROUNDED_TRIANGLE
			current_animation = CursorAnimation.PULSE
		CursorState.WARNING:
			current_shape = CursorShape.ROUNDED_TRIANGLE
			current_animation = CursorAnimation.PULSE
		CursorState.DISABLED:
			current_shape = CursorShape.ROUNDED_TRIANGLE
			current_animation = CursorAnimation.NONE
		CursorState.TEXT_EDIT:
			current_shape = CursorShape.I_BEAM
			current_animation = CursorAnimation.NONE
		CursorState.DRAGGING:
			current_shape = CursorShape.HAND
			current_animation = CursorAnimation.NONE
		CursorState.PRECISION:
			current_shape = CursorShape.CROSSHAIR
			current_animation = CursorAnimation.NONE


func set_interactive_element(interactive: bool) -> void:
	if interactive_element == interactive:
		return
	interactive_element = interactive

	if interactive:
		current_animation = CursorAnimation.HALO
	elif current_state in [CursorState.ACTIVE, CursorState.CREATIVE, CursorState.CONFIRM, CursorState.WARNING]:
		current_animation = CursorAnimation.PULSE
	else:
		current_animation = CursorAnimation.NONE


func set_size(size: float) -> void:
	target_size = clampf(size, CURSOR_MIN_SIZE, CURSOR_MAX_SIZE)


func animation_to_cursor_shape() -> int:
	match current_shape:
		CursorShape.CROSSHAIR:
			return Input.CURSOR_CROSS
		CursorShape.HAND:
			return Input.CURSOR_DRAG
		CursorShape.I_BEAM:
			return Input.CURSOR_IBEAM
		_:
			return Input.CURSOR_ARROW


# ==========================================
# ANIMACIONES
# ==========================================

func update(delta: float) -> void:
	# Transición de color
	if current_color != target_color:
		current_color = current_color.lerp(target_color, CURSOR_COLOR_TRANSITION_SPEED * delta * 60.0)
		if absf(current_color.r - target_color.r) + absf(current_color.g - target_color.g) + absf(current_color.b - target_color.b) < 0.01:
			current_color = target_color

	# Transición de tamaño
	if not is_equal_approx(current_size, target_size):
		current_size = lerpf(current_size, target_size, 0.1)
		if absf(current_size - target_size) < 0.1:
			current_size = target_size

	# Pulso
	if current_animation == CursorAnimation.PULSE:
		animation_progress += delta * CURSOR_PULSE_SPEED
		pulse_factor = 1.0 + sin(animation_progress) * 0.1
	else:
		pulse_factor = 1.0

	# Halo
	if current_animation == CursorAnimation.HALO:
		animation_progress += delta * 2.0
		halo_factor = absf(sin(animation_progress))
	else:
		halo_factor = 0.0

	# Rotación
	if current_animation == CursorAnimation.ROTATION:
		rotation_angle += delta * CURSOR_ROTATION_SPEED
		if rotation_angle > PI * 2:
			rotation_angle -= PI * 2
	else:
		rotation_angle = 0.0
