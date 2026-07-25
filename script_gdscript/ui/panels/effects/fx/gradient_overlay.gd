extends EffectFxBase

@onready var _angle: SpinBox = %Angle

# GradientEditor emits GlobalEvents.gradient_changed itself; only one
# Gradient Overlay can be active at a time so that signal is unambiguous.
func _ready() -> void:
	effect_name = "Gradient Overlay"
	super._ready()
	_angle.value_changed.connect(func(v): _emit_param("angle", v))
