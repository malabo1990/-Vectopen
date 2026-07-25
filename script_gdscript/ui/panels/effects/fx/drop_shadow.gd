extends EffectFxBase

@onready var _offset_x: SpinBox = %OffsetX
@onready var _offset_y: SpinBox = %OffsetY
@onready var _blur: SpinBox = %Blur
@onready var _color: ColorPickerButton = %Color

func _ready() -> void:
	effect_name = "Drop Shadow"
	super._ready()
	_offset_x.value_changed.connect(func(v): _emit_param("offset_x", v))
	_offset_y.value_changed.connect(func(v): _emit_param("offset_y", v))
	_blur.value_changed.connect(func(v): _emit_param("blur", v))
	_color.color_changed.connect(func(c): _emit_param("color", c))
