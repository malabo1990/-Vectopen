extends EffectFxBase

@onready var _depth: SpinBoxValue = %Depth
@onready var _bevel: SpinBoxValue = %Bevel
@onready var _angle: SpinBoxValue = %Angle
@onready var _highlight: SpinBoxValue = %Highlight
@onready var _shadow: SpinBoxValue = %Shadow
@onready var _contour: OptionButton = %Contour

## Casilla "Extrusión exterior": con ella desactivada el 3D es solo el
## relieve interior (bisel), sin la profundidad que sobresale por fuera.
var _extrude: CheckBox = null

func _ready() -> void:
	effect_name = "3D"
	super._ready()
	var box := find_child("VBoxContainer", true, false) as VBoxContainer
	if box:
		_extrude = CheckBox.new()
		_extrude.name = "Extrude"
		_extrude.text = tr("Extrusión exterior (profundidad)")
		_extrude.button_pressed = true
		_extrude.focus_mode = Control.FOCUS_NONE
		_extrude.add_theme_font_size_override("font_size", 11)
		_extrude.toggled.connect(func(v): _emit_param("extrude", v))
		box.add_child(_extrude)
		box.move_child(_extrude, find_child("DepthRow", true, false).get_index() if find_child("DepthRow", true, false) else box.get_child_count() - 1)
	_depth.value_changed.connect(func(v): _emit_param("depth", v))
	if _bevel:
		_bevel.value_changed.connect(func(v): _emit_param("bevel", v))
	_angle.value_changed.connect(func(v): _emit_param("angle", v))
	if _highlight:
		_highlight.value_changed.connect(func(v): _emit_param("highlight", v))
	if _shadow:
		_shadow.value_changed.connect(func(v): _emit_param("shadow", v))
	if _contour:
		_contour.item_selected.connect(func(idx): _emit_param("contour", idx))

func set_params(dict: Dictionary) -> void:
	super.set_params(dict)
	is_updating_ui = true
	if _depth and dict.has("depth"):
		_depth.value = float(dict["depth"])
	if _bevel and dict.has("bevel"):
		_bevel.value = float(dict["bevel"])
	if _angle and dict.has("angle"):
		_angle.value = float(dict["angle"])
	if _highlight and dict.has("highlight"):
		_highlight.value = float(dict["highlight"])
	if _shadow and dict.has("shadow"):
		_shadow.value = float(dict["shadow"])
	if _contour and dict.has("contour"):
		_contour.selected = clampi(int(dict["contour"]), 0, 4)
	if _extrude:
		_extrude.button_pressed = bool(dict.get("extrude", true))
	is_updating_ui = false

func get_params() -> Dictionary:
	var d: Dictionary = super.get_params()
	d["depth"] = _depth.value if _depth else 8.0
	d["bevel"] = _bevel.value if _bevel else 8.0
	d["angle"] = _angle.value if _angle else 45.0
	d["highlight"] = _highlight.value if _highlight else 70.0
	d["shadow"] = _shadow.value if _shadow else 60.0
	d["contour"] = _contour.selected if _contour else 0
	d["extrude"] = _extrude.button_pressed if _extrude else true
	return d

