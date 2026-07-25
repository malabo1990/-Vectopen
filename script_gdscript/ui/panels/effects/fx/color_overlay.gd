extends EffectFxBase

@onready var _color: ColorPickerButton = %Color
@onready var _opacity: SpinBox = %Opacity

func _ready() -> void:
	effect_name = "Color Overlay"
	super._ready()
	_color.color_changed.connect(func(c): _emit_param("color", c))
	_opacity.value_changed.connect(func(v): _emit_param("opacity", v))
