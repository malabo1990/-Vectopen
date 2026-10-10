extends EffectFxBase

@onready var _color: ColorPickerButton = %Color
@onready var _opacity: SpinBoxValue = %Opacity

func _ready() -> void:
	effect_name = "Color Overlay"
	super._ready()
	_color.color_changed.connect(func(c): _emit_param("color", c))
	_opacity.value_changed.connect(func(v): _emit_param("opacity", v))

func set_params(dict: Dictionary) -> void:
	super.set_params(dict)
	is_updating_ui = true
	if _color and dict.has("color"):
		var c = dict["color"]
		if c is Color:
			_color.color = c
		elif c is String:
			_color.color = Color.from_string(c, Color(1, 0, 0, 1))
	if _opacity and dict.has("opacity"):
		_opacity.value = float(dict["opacity"])
	is_updating_ui = false

func get_params() -> Dictionary:
	var d: Dictionary = super.get_params()
	d["color"] = _color.color if _color else Color(1, 0, 0, 1)
	d["opacity"] = _opacity.value if _opacity else 1.0
	return d
