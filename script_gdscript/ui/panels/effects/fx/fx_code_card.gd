# =============================================================================
# RUTA: res://script_gdscript/ui/panels/effects/fx/fx_code_card.gd
# Tarjeta de efecto construida POR CÓDIGO (sin .tscn) a partir de una lista
# de filas: "3D" (iluminación, como Affinity), "Bevel Emboss" (Bisel y
# relieve, como Photoshop) y "Extrusion". Mismo contrato que las demás
# tarjetas (EffectFxBase: get_params / set_params / param_changed).
# =============================================================================
extends EffectFxBase

const NumField = preload("res://script_gdscript/ui/pro/pro_num_field.gd")
const FxLight = preload("res://script_gdscript/shapes/fx_light.gd")
const FxUI = preload("res://script_gdscript/ui/panels/effects/fx_ui.gd")

## [clave, etiqueta, mín, máx, paso, sufijo] · [clave, etiqueta, "color"] ·
## [clave, etiqueta, "bool"] · [clave, etiqueta, "option", [opciones]] ·
## ["dial"] (dirección de la luz: acimut + elevación)
const SPECS := {
	"3D": [
		["radius", "Radius", 0, 200, 1, "px"], ["relief", "Depth", 0, 200, 1, "px"],
		["link", "Link radius and depth", "bool"], ["soften", "Soften", 0, 50, 0.5, "px"],
		["opacity", "Opacity", 0, 100, 1, "%"],
		["profile", "Profile", "option", ["Smooth", "Chisel", "Rounded"]], ["sunken", "Sunken", "bool"],
		["diffuse", "Diffuse", 0, 100, 1, "%"], ["specular", "Specular", 0, 100, 1, "%"],
		["shininess", "Shininess", 0, 100, 1, "%"], ["specular_color", "Specular color", "color"],
		["ambient", "Ambient", 0, 100, 1, "%"], ["ambient_color", "Ambient color", "color"],
		["dial"], ["azimuth", "Azimuth", 0, 360, 1, "°"], ["elevation", "Elevation", 0, 90, 1, "°"],
		["light_color", "Light color", "color"],
	],
	"Bevel Emboss": [
		["style", "Style", "option", ["Inner bevel", "Outer bevel", "Emboss", "Pillow emboss"]],
		["technique", "Technique", "option", ["Smooth", "Chisel hard", "Chisel soft"]],
		["up", "Direction", "option", ["Up", "Down"]],
		["size", "Size", 0, 200, 1, "px"], ["depth", "Depth", 1, 1000, 1, "%"], ["soften", "Soften", 0, 50, 0.5, "px"],
		["dial"], ["azimuth", "Angle", 0, 360, 1, "°"], ["elevation", "Altitude", 0, 90, 1, "°"],
		["highlight_color", "Highlight", "color"], ["highlight_opacity", "Highlight opacity", 0, 100, 1, "%"],
		["shadow_color", "Shadow", "color"], ["shadow_opacity", "Shadow opacity", 0, 100, 1, "%"],
	],
	"Extrusion": [
		["depth", "Depth", 0, 200, 1, "px"], ["angle", "Angle", 0, 360, 1, "°"],
		["highlight", "Highlight", 0, 100, 1, "%"], ["shadow", "Shadow", 0, 100, 1, "%"],
	],
}

const KIND := {"3D": "3d", "Bevel Emboss": "bevel_emboss", "Extrusion": "extrusion"}

var _controls: Dictionary = {}   # clave -> control
var _dial: Control = null
var _values: Dictionary = {}

func _init(kind: String = "3D") -> void:
	effect_name = kind
	_values = FxLight.defaults(KIND.get(kind, "3d"))
	var sb := StyleBoxFlat.new()
	add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	add_child(margin)
	var v := VBoxContainer.new()
	v.name = "VBoxContainer"
	margin.add_child(v)
	var head := HBoxContainer.new()
	head.name = "Header"
	v.add_child(head)
	var en := CheckBox.new()
	en.name = "Enabled"
	en.text = kind
	en.button_pressed = true
	head.add_child(en)
	en.owner = self
	en.unique_name_in_owner = true
	var sp := Control.new()
	sp.name = "Spacer"
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var rm := Button.new()
	rm.name = "Remove"
	rm.text = "✕"
	head.add_child(rm)
	rm.owner = self
	rm.unique_name_in_owner = true
	for spec in SPECS.get(kind, []):
		v.add_child(_make_row(spec))

func _make_row(spec: Array) -> Control:
	var key: String = spec[0]
	if key == "dial":
		var holder := HBoxContainer.new()
		holder.name = "Row_dial"
		var lb := Label.new()
		lb.text = FxUI.t("Direction")
		holder.add_child(lb)
		_dial = LightDial.new()
		_dial.size_flags_horizontal = Control.SIZE_SHRINK_END
		_dial.changed.connect(_on_dial)
		holder.add_child(_dial)
		return holder
	var row := HBoxContainer.new()
	row.name = "Row_" + key
	var lb := Label.new()
	lb.text = FxUI.t(String(spec[1]))
	row.add_child(lb)
	var c: Control
	if spec.size() >= 3 and spec[2] is String and spec[2] == "color":
		var cp := ColorPickerButton.new()
		cp.name = "Value"
		cp.color_changed.connect(func(col: Color) -> void: _set_val(key, col))
		c = cp
	elif spec.size() >= 3 and spec[2] is String and spec[2] == "bool":
		var cb := CheckBox.new()
		cb.name = "Value"
		cb.toggled.connect(func(on: bool) -> void: _set_val(key, on))
		c = cb
	elif spec.size() >= 4 and spec[2] is String and spec[2] == "option":
		var ob := OptionButton.new()
		ob.name = "Value"
		for it in spec[3]:
			ob.add_item(FxUI.t(String(it)))
		ob.item_selected.connect(func(i: int) -> void: _set_val(key, (i == 0) if key == "up" else i))
		c = ob
	else:
		var nf: Control = NumField.new("", "", FxUI.t(String(spec[1])))
		nf.name = "Value"
		nf.min_value = float(spec[2])
		nf.max_value = float(spec[3])
		nf.step = float(spec[4])
		nf.suffix = String(spec[5])
		nf.scrub_changed.connect(func(val: float) -> void: _set_val(key, val))
		nf.value_changed.connect(func(val: float) -> void: _set_val(key, val))
		c = nf
	row.add_child(c)
	_controls[key] = c
	return row

func _set_val(key: String, val: Variant) -> void:
	if is_updating_ui:
		return
	_values[key] = val
	if key == "radius" and bool(_values.get("link", false)):
		_values["relief"] = val
		_show(["relief"])
	if key in ["azimuth", "elevation"] and _dial:
		_dial.set_angles(float(_values.get("azimuth", 0.0)), float(_values.get("elevation", 45.0)))
	_update_enabled()
	_emit_param(key, val)

func _on_dial(az: float, el: float) -> void:
	if is_updating_ui:
		return
	_values["azimuth"] = roundf(az)
	_values["elevation"] = roundf(el)
	_show(["azimuth", "elevation"])
	_emit_param("azimuth", _values["azimuth"])
	_emit_param("elevation", _values["elevation"])

## "Vincular radio y profundidad": la profundidad sigue al radio.
func _update_enabled() -> void:
	var rel = _controls.get("relief")
	if rel:
		rel.modulate.a = 0.45 if bool(_values.get("link", false)) else 1.0

func _show(keys: Array) -> void:
	var was := is_updating_ui
	is_updating_ui = true
	for key in keys:
		var c = _controls.get(key)
		if c == null or not _values.has(key):
			continue
		var val = _values[key]
		if c is ColorPickerButton:
			(c as ColorPickerButton).color = FxLight._col(val, Color.WHITE)
		elif c is CheckBox:
			(c as CheckBox).button_pressed = bool(val)
		elif c is OptionButton:
			(c as OptionButton).selected = (0 if bool(val) else 1) if key == "up" else int(val)
		elif c.has_method("set_value_no_signal"):
			c.set_value_no_signal(float(val))
	if _dial:
		_dial.set_angles(float(_values.get("azimuth", 0.0)), float(_values.get("elevation", 45.0)))
	is_updating_ui = was

func set_params(dict: Dictionary) -> void:
	super.set_params(dict)
	for k in dict:
		if k != "type" and k != "enabled":
			_values[k] = dict[k]
	_show(_controls.keys())
	_update_enabled()

func get_params() -> Dictionary:
	var d: Dictionary = super.get_params()
	for k in _values:
		d[k] = _values[k]
	return d


## Control circular de la dirección de la luz (como Affinity): el ángulo del
## punto es el acimut y la distancia al centro la elevación (centro = 90°).
class LightDial extends Control:
	signal changed(azimuth: float, elevation: float)
	var az := 135.0
	var el := 45.0
	var _drag := false

	func _init() -> void:
		custom_minimum_size = Vector2(46, 46)
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		tooltip_text = "Direction of the light: drag the point (center = straight above)"

	func set_angles(a: float, e: float) -> void:
		az = a
		el = e
		queue_redraw()

	func _point() -> Vector2:
		var r := minf(size.x, size.y) * 0.5 - 4.0
		var k := (90.0 - clampf(el, 0.0, 90.0)) / 90.0
		var a := deg_to_rad(az)
		return size * 0.5 + Vector2(cos(a), -sin(a)) * r * k

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var bg := ProUIStyle.col("INPUT_BG")
		var br := ProUIStyle.col("INPUT_BORDER")
		draw_circle(c, r, bg)
		draw_arc(c, r, 0.0, TAU, 48, br, 1.0, true)
		draw_arc(c, r * 0.5, 0.0, TAU, 32, Color(br, 0.5), 1.0, true)
		draw_line(c, _point(), Color(ProUIStyle.col("ACCENT"), 0.5), 1.0, true)
		draw_circle(_point(), 4.0, ProUIStyle.col("ACCENT"))

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = ev.pressed
			if ev.pressed:
				_from(ev.position)
			accept_event()
		elif ev is InputEventMouseMotion and _drag:
			_from(ev.position)
			accept_event()

	func _from(pos: Vector2) -> void:
		var r := minf(size.x, size.y) * 0.5 - 4.0
		var d := pos - size * 0.5
		az = fposmod(rad_to_deg(atan2(-d.y, d.x)), 360.0)
		el = clampf(90.0 * (1.0 - d.length() / maxf(r, 1.0)), 0.0, 90.0)
		queue_redraw()
		changed.emit(az, el)
