# =============================================================================
# RUTA: res://script_gdscript/ui/panel_light.gd
# PANEL «ILUMINACIÓN» (herramienta Luz ☀ de la barra): tipo de luz (botones
# del registro VectorLight.TYPE_INFO: puntual, foco, direccional, ambiente…
# los tipos futuros salen solos) y todos sus parámetros, y la SOMBRA.
#   · Con una luz seleccionada: edita ESA luz (InspectorCore: en vivo y con
#     deshacer).
#   · Sin luz seleccionada: ajusta la PRÓXIMA luz (LightTool.settings).
# Las filas que no aplican al tipo (alcance en «ambiente», apertura fuera del
# foco…) se ocultan.
# =============================================================================
extends PanelContainer

const TPS = preload("res://script_gdscript/ui/components/tool_panel_style.gd")
const LightScript = preload("res://script_gdscript/shapes/vector_light.gd")
const LightToolScript = preload("res://script_gdscript/tools/LightTool.gd")
const NF = preload("res://script_gdscript/ui/components/numeric_field.gd")

## clave → [etiqueta, tipo, min, max, paso, sufijo, escala, condición de tipo]
const ROWS := [
	["color", "Color", "color"],
	["energy", "Intensidad", "num", 0, 1600, 5, "%", 100.0],
	["radius", "Alcance", "num", 4, 20000, 5, " px", 1.0, "radius"],
	["angle", "Dirección", "num", -180, 180, 1, "°", 1.0, "angle"],
	["cone", "Apertura", "num", 5, 170, 1, "°", 1.0, "cone"],
	["falloff", "Borde duro", "num", 0, 100, 1, "%", 100.0, "radius"],
	["mode", "Mezcla", "option", [["add", "Sumar (aclara)"], ["mix", "Mezclar"], ["sub", "Restar (oscurece)"]]],
]
const SHADOW_ROWS := [
	["shadows", "Proyectar sombras", "check"],
	["shadow_color", "Color de sombra", "color"],
	["shadow_soft", "Suavidad", "num", 0, 100, 1, "%", 100.0],
]

var _title: Label
var _hint: Label
var _type_buttons := {}
var _ctrls := {}
var _rows := {}           # clave → fila (para ocultar)
var _labels: Array = []
var _sections: Array = []
var _shadow_box: VBoxContainer
var _syncing := false

func _ready() -> void:
	name = "light"
	custom_minimum_size = Vector2(290, 0)
	_build()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.changed.connect(func(_p) -> void:
			# al SELECCIONAR una luz, su panel se abre (también en Smart)
			if selected_light() != null and not visible:
				var ge := get_node_or_null("/root/GlobalEvents")
				if ge and ge.has_method("emit_safe"):
					ge.emit_safe("request_tool_panel", "light")
				if not visible:
					visible = true
			sync())
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _apply_theme())
	visibility_changed.connect(func() -> void:
		if visible:
			sync())
	_apply_theme()
	sync()

func _build() -> void:
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 10)
	add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	m.add_child(vb)
	_title = Label.new()
	_title.text = tr("Iluminación")
	vb.add_child(_title)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_hint)
	# tipos
	var types := HFlowContainer.new()
	types.name = "Types"
	types.add_theme_constant_override("h_separation", 4)
	types.add_theme_constant_override("v_separation", 4)
	vb.add_child(types)
	for t in LightScript.TYPES:
		var b := Button.new()
		b.name = "Type_" + t
		b.text = tr(String(LightScript.TYPE_INFO[t]["label"]))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: _put("type", t))
		types.add_child(b)
		_type_buttons[t] = b
	# parámetros
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for spec in ROWS:
		_add_row(grid, spec)
	# sombra
	var sl := Label.new()
	sl.text = tr("Sombra")
	vb.add_child(sl)
	_sections.append(sl)
	var sg := GridContainer.new()
	sg.name = "Shadow"
	sg.columns = 2
	sg.add_theme_constant_override("h_separation", 8)
	sg.add_theme_constant_override("v_separation", 6)
	vb.add_child(sg)
	for spec in SHADOW_ROWS:
		_add_row(sg, spec)
	_rows["__shadow_title"] = [sl]

func _add_row(grid: GridContainer, spec: Array) -> void:
	var key: String = spec[0]
	var l := Label.new()
	l.text = tr(String(spec[1]))
	l.add_theme_font_size_override("font_size", 11)
	grid.add_child(l)
	_labels.append(l)
	var c: Control
	match String(spec[2]):
		"num":
			var nf := NF.new("", String(spec[6]), float(spec[3]), float(spec[4]), float(spec[5]))
			nf.decimals = 0
			nf.custom_minimum_size = Vector2(90, 24)
			var k_scale: float = spec[7]
			nf.value_changed.connect(func(v: float) -> void: _put(key, v / k_scale))
			c = nf
		"color":
			var cp := ColorPickerButton.new()
			cp.custom_minimum_size = Vector2(90, 24)
			cp.edit_alpha = key == "shadow_color"
			cp.color_changed.connect(func(col: Color) -> void: _put(key, col))
			c = cp
		"check":
			var cb := CheckButton.new()
			cb.focus_mode = Control.FOCUS_NONE
			cb.toggled.connect(func(on: bool) -> void: _put(key, on))
			c = cb
		"option":
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			for it in spec[3]:
				ob.add_item(tr(String(it[1])))
				ob.set_item_metadata(ob.item_count - 1, it[0])
			ob.item_selected.connect(func(i: int) -> void: _put(key, ob.get_item_metadata(i)))
			c = ob
	c.name = "Light_" + key
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(c)
	_ctrls[key] = c
	_rows[key] = [l, c]

## Luz seleccionada (una sola) o null.
func selected_light() -> Node:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return null
	var sel: Array = ic.selection()
	if sel.size() == 1 and is_instance_valid(sel[0]) and String(sel[0].get_meta("shape_type", "")) == "light":
		return sel[0]
	return null

func _put(key: String, value) -> void:
	if _syncing:
		return
	var l := selected_light()
	if l:
		var ic := get_node_or_null("/root/InspectorCore")
		ic.apply("lamp_" + key, value)
	else:
		LightToolScript.settings[key] = value
	if key == "type":
		_sync_from(_current())

## Valores mostrados: los de la luz elegida o los de la próxima luz.
func _current() -> Dictionary:
	var l := selected_light()
	return l.params() if l else LightToolScript.settings.duplicate()

func sync() -> void:
	if not is_inside_tree():
		return
	_sync_from(_current())

func _sync_from(p: Dictionary) -> void:
	_syncing = true
	var l := selected_light()
	_hint.text = tr("Editando la luz seleccionada.") if l else tr("Clic en el lienzo para colocar una luz; arrastra para darle alcance y dirección.")
	var t := String(p.get("type", "point"))
	for k in _type_buttons:
		(_type_buttons[k] as Button).set_pressed_no_signal(k == t)
	var info: Dictionary = LightScript.TYPE_INFO.get(t, {})
	for spec in ROWS + SHADOW_ROWS:
		var key: String = spec[0]
		var c: Control = _ctrls[key]
		var v = p.get(key)
		match String(spec[2]):
			"num":
				if v != null:
					(c as NF).set_value_silent(float(v) * float(spec[7]))
			"color":
				if v is Color:
					(c as ColorPickerButton).color = v
			"check":
				(c as CheckButton).set_pressed_no_signal(bool(v))
			"option":
				var ob := c as OptionButton
				for i in ob.item_count:
					if String(ob.get_item_metadata(i)) == String(v):
						ob.select(i)
		# filas que no aplican al tipo
		var cond: String = String(spec[8]) if spec.size() > 8 else ""
		var show := cond == "" or bool(info.get(cond, false))
		for n in _rows[key]:
			(n as Control).visible = show
	var sh := bool(info.get("shadows", false))
	for key in ["shadows", "shadow_color", "shadow_soft"]:
		for n in _rows[key]:
			(n as Control).visible = sh
	for n in _rows["__shadow_title"]:
		(n as Control).visible = sh
	_syncing = false
	_apply_theme()

func _apply_theme() -> void:
	TPS.apply_frame(self)
	TPS.style_title(_title)
	TPS.style_muted(_hint)
	for l in _labels:
		TPS.style_text(l)
	for l in _sections:
		TPS.style_section_label(l)
	for k in _type_buttons:
		TPS.style_toggle(_type_buttons[k], (_type_buttons[k] as Button).button_pressed)
