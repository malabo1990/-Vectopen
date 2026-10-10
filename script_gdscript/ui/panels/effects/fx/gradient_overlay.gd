extends EffectFxBase

## Superposición de degradado: degradado PROPIO del efecto (colores,
## posiciones y ángulo). El editor embebido es local (emit_global = false):
## antes cada cambio iba al bus global y ColorCore lo aplicaba al RELLENO de
## la figura seleccionada en vez de al efecto.

@onready var _angle: SpinBoxValue = %Angle
var _editor: Control = null
var _colors: Array = [Color(0.95, 0.3, 0.2), Color(0.25, 0.3, 0.95)]
var _offsets: Array = [0.0, 1.0]
var _opacity := 1.0

func _ready() -> void:
	effect_name = "Gradient Overlay"
	super._ready()
	_angle.value_changed.connect(func(v): _emit_param("angle", v))
	_editor = find_child("GradientEditor", true, false)
	if _editor:
		if "emit_global" in _editor:
			_editor.emit_global = false
		if _editor.has_signal("gradient_edited"):
			_editor.gradient_edited.connect(_on_gradient_edited)

func _on_gradient_edited(g: Gradient) -> void:
	if is_updating_ui or g == null:
		return
	_colors = Array(g.colors)
	_offsets = Array(g.offsets)
	_emit_param("colors", _colors)

func set_params(dict: Dictionary) -> void:
	super.set_params(dict)
	is_updating_ui = true
	if _angle and dict.has("angle"):
		_angle.value = float(dict["angle"])
	if dict.get("colors") is Array and (dict["colors"] as Array).size() >= 2:
		_colors = (dict["colors"] as Array).duplicate()
		_offsets = (dict["offsets"] as Array).duplicate() if dict.get("offsets") is Array and (dict["offsets"] as Array).size() == _colors.size() else [0.0, 1.0]
	_opacity = float(dict.get("opacity", 1.0))
	if _editor and _editor.has_method("set_gradient_resource"):
		var g := Gradient.new()
		g.colors = PackedColorArray(_colors)
		g.offsets = PackedFloat32Array(_offsets)
		_editor.set_gradient_resource(g, 0, float(dict.get("angle", 0.0)))
	is_updating_ui = false

func get_params() -> Dictionary:
	var d: Dictionary = super.get_params()
	d["angle"] = _angle.value if _angle else 0.0
	d["colors"] = _colors.duplicate()
	d["offsets"] = _offsets.duplicate()
	d["opacity"] = _opacity
	return d
