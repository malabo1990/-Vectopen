extends EffectFxBase

@onready var _color: ColorPickerButton = %Color
@onready var _radius: SpinBoxValue = %Radius
@onready var _opacity: SpinBoxValue = %Opacity

func _ready() -> void:
	effect_name = "Inner Glow"
	super._ready()
	_color.color_changed.connect(func(c): _emit_param("color", c))
	_radius.value_changed.connect(func(v): _emit_param("radius", v))
	_opacity.value_changed.connect(func(v): _emit_param("opacity", v))

func set_params(dict: Dictionary) -> void:
	super.set_params(dict)
	is_updating_ui = true
	if _color and dict.has("color"):
		var c = dict["color"]
		if c is Color:
			_color.color = c
		elif c is String:
			_color.color = Color.from_string(c, Color.WHITE)
	if _radius and dict.has("radius"):
		_radius.value = float(dict["radius"])
	if _opacity and dict.has("opacity"):
		_opacity.value = float(dict["opacity"])
	is_updating_ui = false

func get_params() -> Dictionary:
	var d: Dictionary = super.get_params()
	d["color"] = _color.color if _color else Color.WHITE
	d["radius"] = _radius.value if _radius else 8.0
	d["opacity"] = _opacity.value if _opacity else 1.0
	return d
