extends EffectFxBase

@onready var _width: SpinBox = %Width
@onready var _color: ColorPickerButton = %Color

func _ready() -> void:
	effect_name = "Outline"
	super._ready()
	_width.value_changed.connect(func(v): _emit_param("width", v))
	_color.color_changed.connect(func(c): _emit_param("color", c))
