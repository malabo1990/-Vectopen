# =============================================================================
# RUTA: res://script_gdscript/ui/components/shader_params_box.gd
# PARÁMETROS DEL SHADER en el inspector (encargo 27). Lee los `uniform` del
# shader del objeto seleccionado y crea un control por cada uno:
#   float / int (con hint_range: deslizador + número) · bool · color
#   (vec3/vec4 con source_color) · vec2.
# Escribe en custom_shader.params (lo que FilterFx pasa al material). Cada
# cambio es UN paso de deshacer; durante un arrastre se ve en vivo.
# =============================================================================
extends VBoxContainer

var _node: Node = null
var _sig := ""
var _live_before = null   # custom_shader antes de un arrastre (para deshacer)

func _init() -> void:
	name = "ShaderParams"
	add_theme_constant_override("separation", 4)

func _ready() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed"):
		ic.changed.connect(func(_p = null) -> void:
			if is_visible_in_tree(): refresh())
	refresh()

func _api():
	var pm := get_node_or_null("/root/PluginManager")
	return pm.api if pm else null

func _target() -> Node:
	var ic := get_node_or_null("/root/InspectorCore")
	var sel: Array = ic.selection() if ic and ic.has_method("selection") else []
	for n in sel:
		if is_instance_valid(n) and n.has_meta("custom_shader") and not (n.get_meta("custom_shader", {}) as Dictionary).is_empty():
			return n
	return null

## Uniforms del código: [{name, type, hint, hint_string}] (de Godot).
static func uniforms_of(code: String) -> Array:
	var sh := Shader.new()
	sh.code = code
	var out := []
	for u in sh.get_shader_uniform_list():
		var nm := String(u.get("name", ""))
		if nm == "":
			continue
		out.append(u)
	return out

func refresh() -> void:
	var t := _target()
	var cs: Dictionary = t.get_meta("custom_shader", {}) if t else {}
	var sig := str(t.get_instance_id() if t else 0) + "|" + String(cs.get("code", "")).md5_text()
	if sig == _sig and t == _node:
		_sync_values(cs)
		return
	_sig = sig
	_node = t
	for c in get_children():
		c.queue_free()
	visible = t != null
	if t == null:
		return
	var params: Dictionary = cs.get("params", {})
	var mat_defaults := _defaults(String(cs.get("code", "")))
	for u in uniforms_of(String(cs.get("code", ""))):
		var nm := String(u["name"])
		var cur = params.get(nm, mat_defaults.get(nm, null))
		var row := HBoxContainer.new()
		row.name = "Param_" + nm
		row.add_theme_constant_override("separation", 6)
		add_child(row)
		var lbl := Label.new()
		lbl.text = nm.capitalize()
		lbl.custom_minimum_size = Vector2(90, 0)
		lbl.clip_text = true
		lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(lbl)
		match int(u["type"]):
			TYPE_FLOAT, TYPE_INT:
				var hs := String(u.get("hint_string", ""))
				var parts := hs.split(",")
				var sl := HSlider.new()
				sl.name = "Slider"
				sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sl.min_value = float(parts[0]) if parts.size() >= 2 else 0.0
				sl.max_value = float(parts[1]) if parts.size() >= 2 else maxf(10.0, absf(float(cur if cur != null else 1.0)) * 4.0)
				sl.step = float(parts[2]) if parts.size() >= 3 else (1.0 if int(u["type"]) == TYPE_INT else 0.01)
				sl.value = float(cur if cur != null else sl.min_value)
				sl.custom_minimum_size = Vector2(80, 18)
				row.add_child(sl)
				var sp := SpinBox.new()
				sp.name = "Value"
				sp.min_value = sl.min_value
				sp.max_value = sl.max_value
				sp.step = sl.step
				sp.value = sl.value
				sp.custom_minimum_size = Vector2(70, 0)
				row.add_child(sp)
				var is_int := int(u["type"]) == TYPE_INT
				sl.value_changed.connect(func(v: float) -> void:
					sp.set_value_no_signal(v)
					_live(nm, int(v) if is_int else v))
				sl.drag_ended.connect(func(_c: bool) -> void: set_param(nm, int(sl.value) if is_int else sl.value))
				sp.value_changed.connect(func(v: float) -> void:
					sl.set_value_no_signal(v)
					set_param(nm, int(v) if is_int else v))
			TYPE_BOOL:
				var cb := CheckBox.new()
				cb.name = "Value"
				cb.button_pressed = bool(cur) if cur != null else false
				cb.toggled.connect(func(v: bool) -> void: set_param(nm, v))
				row.add_child(cb)
			TYPE_COLOR, TYPE_VECTOR4, TYPE_VECTOR3:
				var cp := ColorPickerButton.new()
				cp.name = "Value"
				cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				cp.custom_minimum_size = Vector2(0, 22)
				cp.color = _to_color(cur)
				cp.edit_alpha = int(u["type"]) != TYPE_VECTOR3
				var vec3 := int(u["type"]) == TYPE_VECTOR3
				var vec4 := int(u["type"]) == TYPE_VECTOR4
				cp.color_changed.connect(func(c: Color) -> void: _live(nm, _from_color(c, vec3, vec4)))
				cp.popup_closed.connect(func() -> void: set_param(nm, _from_color(cp.color, vec3, vec4)))
				row.add_child(cp)
			TYPE_VECTOR2:
				var v2: Vector2 = cur if cur is Vector2 else Vector2.ZERO
				for axis in 2:
					var sp2 := SpinBox.new()
					sp2.name = "Value%d" % axis
					sp2.min_value = -10000.0
					sp2.max_value = 10000.0
					sp2.step = 0.01
					sp2.value = v2.x if axis == 0 else v2.y
					sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					var ax := axis
					sp2.value_changed.connect(func(v: float) -> void:
						var base: Vector2 = _param(nm) if _param(nm) is Vector2 else Vector2.ZERO
						if ax == 0: base.x = v
						else: base.y = v
						set_param(nm, base))
					row.add_child(sp2)
			_:
				var na := Label.new()
				na.text = tr("(no editable)")
				na.modulate.a = 0.6
				row.add_child(na)

func _sync_values(cs: Dictionary) -> void:
	var params: Dictionary = cs.get("params", {})
	for nm in params:
		var row := get_node_or_null("Param_" + String(nm))
		if row == null:
			continue
		var sl := row.get_node_or_null("Slider") as HSlider
		var sp := row.get_node_or_null("Value")
		if sl:
			sl.set_value_no_signal(float(params[nm]))
		if sp is SpinBox:
			(sp as SpinBox).set_value_no_signal(float(params[nm]))

static func _to_color(v) -> Color:
	if v is Color:
		return v
	if v is Vector4:
		return Color(v.x, v.y, v.z, v.w)
	if v is Vector3:
		return Color(v.x, v.y, v.z)
	return Color.WHITE

static func _from_color(c: Color, vec3: bool, vec4: bool) -> Variant:
	if vec3:
		return Vector3(c.r, c.g, c.b)
	if vec4:
		return Vector4(c.r, c.g, c.b, c.a)
	return c

## Valores por defecto de los uniforms (lo que dice el código).
static func _defaults(code: String) -> Dictionary:
	var out := {}
	if code == "":
		return out
	var sh := Shader.new()
	sh.code = code
	for u in sh.get_shader_uniform_list():
		var nm := String(u.get("name", ""))
		var d = RenderingServer.shader_get_parameter_default(sh.get_rid(), nm)
		if d != null:
			out[nm] = d
	return out

func _param(nm: String) -> Variant:
	if _node == null:
		return null
	return ((_node.get_meta("custom_shader", {}) as Dictionary).get("params", {}) as Dictionary).get(nm, null)

## Vista previa mientras se arrastra (sin paso de deshacer).
func _live(nm: String, v: Variant) -> void:
	if not is_instance_valid(_node):
		return
	if _live_before == null:
		_live_before = (_node.get_meta("custom_shader", {}) as Dictionary).duplicate(true)
	var cs: Dictionary = (_node.get_meta("custom_shader", {}) as Dictionary).duplicate(true)
	var p: Dictionary = (cs.get("params", {}) as Dictionary).duplicate()
	p[nm] = v
	cs["params"] = p
	_node.set_meta("custom_shader", cs)
	preload("res://script_gdscript/shapes/filter_fx.gd").sync(_node)

## Fija un parámetro (UN paso de deshacer). Público para las pruebas.
func set_param(nm: String, v: Variant) -> void:
	if not is_instance_valid(_node):
		return
	var api = _api()
	if _live_before != null:
		_node.set_meta("custom_shader", _live_before)   # el paso de deshacer parte de antes del arrastre
		_live_before = null
	var cs: Dictionary = (_node.get_meta("custom_shader", {}) as Dictionary).duplicate(true)
	var p: Dictionary = (cs.get("params", {}) as Dictionary).duplicate()
	p[nm] = v
	cs["params"] = p
	if api:
		api.set_prop(_node, "custom_shader", cs)
	else:
		_node.set_meta("custom_shader", cs)
