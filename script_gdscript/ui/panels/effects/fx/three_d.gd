extends EffectFxBase

@onready var _depth: SpinBox = %Depth
@onready var _angle: SpinBox = %Angle

func _ready() -> void:
	effect_name = "3D"
	super._ready()
	_depth.value_changed.connect(func(v): _emit_param("depth", v))
	_angle.value_changed.connect(func(v): _emit_param("angle", v))
