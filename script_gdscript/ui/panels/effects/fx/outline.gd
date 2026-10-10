extends EffectFxBase

@onready var _width: SpinBoxValue = %Width
@onready var _color: ColorPickerButton = %Color

func _ready() -> void:
	effect_name = "Outline"
	super._ready()
	_width.value_changed.connect(func(v): _emit_param("width", v))
	_color.color_changed.connect(func(c): _emit_param("color", c))

func set_params(dict: Dictionary) -> void:
	super.set_params(dict)
	is_updating_ui = true
	if _width and dict.has("width"):
		_width.value = float(dict["width"])
	if _color and dict.has("color"):
		var c = dict["color"]
		if c is Color:
			_color.color = c
		elif c is String:
			_color.color = Color.from_string(c, Color.BLACK)
	is_updating_ui = false

func get_params() -> Dictionary:
	var d: Dictionary = super.get_params()
	d["width"] = _width.value if _width else 2.0
	d["color"] = _color.color if _color else Color(0, 0, 0, 1.0)
	return d
