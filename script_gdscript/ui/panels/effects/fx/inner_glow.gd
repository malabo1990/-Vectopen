extends EffectFxBase

@onready var _color: ColorPickerButton = %Color
@onready var _radius: SpinBox = %Radius
@onready var _opacity: SpinBox = %Opacity

func _ready() -> void:
	effect_name = "Inner Glow"
	super._ready()
	_color.color_changed.connect(func(c): _emit_param("color", c))
	_radius.value_changed.connect(func(v): _emit_param("radius", v))
	_opacity.value_changed.connect(func(v): _emit_param("opacity", v))
