extends EffectFxBase

## Desenfoque con TIPOS (como Photoshop / Affinity): gaussiano, de movimiento
## (con ángulo), radial (zoom desde el centro) y giratorio. Los controles de
## tipo y ángulo se crean aquí (el .tscn solo tiene radio y "conservar alfa").

const TYPES := ["gaussian", "motion", "radial", "spin"]
const TYPE_NAMES := ["Gaussiano", "Movimiento", "Radial (zoom)", "Giratorio"]

@onready var _radius: SpinBoxValue = %Radius
@onready var _preserve_alpha: CheckBox = %PreserveAlpha
var _type: OptionButton = null
var _angle: Control = null
var _angle_row: Control = null

func _ready() -> void:
	effect_name = "Blur"
	super._ready()
	_radius.value_changed.connect(func(v): _emit_param("radius", v))
	_preserve_alpha.toggled.connect(func(v): _emit_param("preserve_alpha", v))
	var box := find_child("VBoxContainer", true, false) as VBoxContainer
	if box == null:
		return
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = tr("Tipo")
	lab.custom_minimum_size.x = 70
	lab.add_theme_font_size_override("font_size", 11)
	row.add_child(lab)
	_type = OptionButton.new()
	_type.focus_mode = Control.FOCUS_NONE
	_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n in TYPE_NAMES:
		_type.add_item(tr(n))
	_type.item_selected.connect(func(i):
		_update_angle_row()
		_emit_param("blur_type", TYPES[i]))
	row.add_child(_type)
	box.add_child(row)
	box.move_child(row, 1)
	_angle_row = HBoxContainer.new()
	var lab2 := Label.new()
	lab2.text = tr("Ángulo")
	lab2.custom_minimum_size.x = 70
	lab2.add_theme_font_size_override("font_size", 11)
	_angle_row.add_child(lab2)
	_angle = preload("res://scenes/ui/spin_box.tscn").instantiate()
	_angle.min_value = -360.0
	_angle.max_value = 360.0
	_angle.step = 1.0
	_angle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_angle.value_changed.connect(func(v): _emit_param("angle", v))
	_angle_row.add_child(_angle)
	box.add_child(_angle_row)
	box.move_child(_angle_row, 2)
	_update_angle_row()

func _update_angle_row() -> void:
	if _angle_row and _type:
		_angle_row.visible = TYPES[maxi(0, _type.selected)] == "motion"

func set_params(dict: Dictionary) -> void:
	super.set_params(dict)
	is_updating_ui = true
	if _radius and dict.has("radius"):
		_radius.value = float(dict["radius"])
	if _preserve_alpha and dict.has("preserve_alpha"):
		_preserve_alpha.button_pressed = bool(dict["preserve_alpha"])
	if _type:
		_type.select(maxi(0, TYPES.find(String(dict.get("blur_type", "gaussian")))))
	if _angle:
		_angle.value = float(dict.get("angle", 0.0))
	_update_angle_row()
	is_updating_ui = false

func get_params() -> Dictionary:
	var d: Dictionary = super.get_params()
	d["radius"] = _radius.value if _radius else 5.0
	d["preserve_alpha"] = _preserve_alpha.button_pressed if _preserve_alpha else false
	d["blur_type"] = TYPES[maxi(0, _type.selected)] if _type else "gaussian"
	d["angle"] = float(_angle.value) if _angle else 0.0
	return d
