extends EffectFxBase

@onready var _radius: SpinBox = %Radius
@onready var _preserve_alpha: CheckBox = %PreserveAlpha

func _ready() -> void:
	effect_name = "Blur"
	super._ready()
	_radius.value_changed.connect(func(v): _emit_param("radius", v))
	_preserve_alpha.toggled.connect(func(v): _emit_param("preserve_alpha", v))

func set_params(dict: Dictionary) -> void:
	super.set_params(dict)
	is_updating_ui = true
	if _radius and dict.has("radius"):
		_radius.value = float(dict["radius"])
	if _preserve_alpha and dict.has("preserve_alpha"):
		_preserve_alpha.button_pressed = bool(dict["preserve_alpha"])
	is_updating_ui = false

func get_params() -> Dictionary:
	var d: Dictionary = super.get_params()
	d["radius"] = _radius.value if _radius else 5.0
	d["preserve_alpha"] = _preserve_alpha.button_pressed if _preserve_alpha else false
	return d
