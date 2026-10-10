extends EffectFxBase

@onready var _offset_x: SpinBoxValue = %OffsetX
@onready var _offset_y: SpinBoxValue = %OffsetY
@onready var _blur: SpinBoxValue = %Blur
@onready var _spread: SpinBoxValue = %Spread
@onready var _color: ColorPickerButton = %Color

func _ready() -> void:
	effect_name = "Drop Shadow"
	super._ready()
	_offset_x.value_changed.connect(func(v): _emit_param("offset_x", v))
	_offset_y.value_changed.connect(func(v): _emit_param("offset_y", v))
	_blur.value_changed.connect(func(v): _emit_param("blur", v))
	if _spread:
		_spread.value_changed.connect(func(v): _emit_param("spread", v))
	_color.color_changed.connect(func(c): _emit_param("color", c))

func set_params(dict: Dictionary) -> void:
	super.set_params(dict)
	is_updating_ui = true
	if _offset_x and dict.has("offset_x"):
		_offset_x.value = float(dict["offset_x"])
	if _offset_y and dict.has("offset_y"):
		_offset_y.value = float(dict["offset_y"])
	if _blur and dict.has("blur"):
		_blur.value = float(dict["blur"])
	if _spread and dict.has("spread"):
		_spread.value = float(dict["spread"])
	if _color and dict.has("color"):
		var c = dict["color"]
		if c is Color:
			_color.color = c
		elif c is String:
			_color.color = Color.from_string(c, Color(0, 0, 0, 0.4))
	is_updating_ui = false

func get_params() -> Dictionary:
	var d: Dictionary = super.get_params()
	d["offset_x"] = _offset_x.value if _offset_x else 4.0
	d["offset_y"] = _offset_y.value if _offset_y else 4.0
	d["blur"] = _blur.value if _blur else 6.0
	d["spread"] = _spread.value if _spread else 0.0
	d["color"] = _color.color if _color else Color(0, 0, 0, 0.4)
	return d
