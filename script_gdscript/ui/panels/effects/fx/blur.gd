extends EffectFxBase

@onready var _radius: SpinBox = %Radius
@onready var _preserve_alpha: CheckBox = %PreserveAlpha

func _ready() -> void:
	effect_name = "Blur"
	super._ready()
	_radius.value_changed.connect(func(v): _emit_param("radius", v))
	_preserve_alpha.toggled.connect(func(v): _emit_param("preserve_alpha", v))
