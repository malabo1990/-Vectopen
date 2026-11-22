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
	["shadow_length", "Longitud", "num", 0, 5000, 5, " px", 1.0],
	["shadow_soft", "Difuminado", "num", 0, 100, 1, "%", 100.0],
	["shadow_fade", "Desvanecer", "num", 0, 100, 1, "%", 100.0],
]
## Glifo de cada tipo en su botón.
const TYPE_GLYPH := {"point": "●", "spot": "◣", "directional": "➚", "ambient": "◌"}

var _title: Label
var _hint: Label
var _type_buttons := {}
var _ctrls := {}
var _rows := {}           # clave → fila (para ocultar)
var _labels: Array = []
var _sections: Array = []
var _shadow_box: VBoxContainer
var _syncing := false
var _cards: Array = []
var _reset: Button

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
	vb.add_theme_constant_override("separation", 8)
	m.add_child(vb)
	# cabecera: título + Restablecer
	var head := HBoxContainer.new()
	vb.add_child(head)
	_title = Label.new()
	_title.text = tr("Iluminación")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_reset = Button.new()
	_reset.name = "Reset"
	_reset.text = "↺  " + tr("Restablecer")
	_reset.tooltip_text = tr("Vuelve a los valores de fábrica (luz seleccionada o próxima luz)")
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.add_theme_font_size_override("font_size", 11)
	_reset.pressed.connect(reset_to_defaults)
	head.add_child(_reset)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 10)
	vb.add_child(_hint)
	# tarjeta Tipo
	var tbox := _card(vb, tr("TIPO DE LUZ"))
	var types := GridContainer.new()
	types.name = "Types"
	types.columns = 2
	types.add_theme_constant_override("h_separation", 6)
	types.add_theme_constant_override("v_separation", 6)
	tbox.add_child(types)
	for t in LightScript.TYPES:
		var b := Button.new()
		b.name = "Type_" + t
		b.text = "%s  %s" % [TYPE_GLYPH.get(t, "•"), tr(String(LightScript.TYPE_INFO[t]["label"]))]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func() -> void: _put("type", t))
		types.add_child(b)
		_type_buttons[t] = b
	# tarjeta Luz
	var lbox := _card(vb, tr("LUZ"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	lbox.add_child(grid)
	for spec in ROWS:
		_add_row(grid, spec)
	# tarjeta Sombra
	var sbox := _card(vb, tr("SOMBRA"))
	var sg := GridContainer.new()
	sg.name = "Shadow"
	sg.columns = 2
	sg.add_theme_constant_override("h_separation", 8)
	sg.add_theme_constant_override("v_separation", 6)
	sbox.add_child(sg)
	for spec in SHADOW_ROWS:
		_add_row(sg, spec)
	_rows["__shadow_title"] = [sbox.get_parent().get_parent()]

## Tarjeta con título (devuelve su caja interior).
func _card(parent: Control, title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.name = "Card_" + title.replace(" ", "_")
	parent.add_child(pc)
	_cards.append(pc)
	var inner := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inner.add_theme_constant_override(k, 6)
	pc.add_child(inner)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	inner.add_child(v)
	var l := Label.new()
	l.text = title
	v.add_child(l)
	_sections.append(l)
	return v

## «Restablecer»: valores de fábrica (manteniendo el tipo).
func reset_to_defaults() -> void:
	var l := selected_light()
	var d: Dictionary = LightScript.DEFAULTS
	if l:
		var ic := get_node_or_null("/root/InspectorCore")
		var hm := get_node_or_null("/root/HistoryManager")
		var before: Dictionary = l.params()
		var after := before.duplicate()
		after.merge(d, true)
		var apply_p := func(p: Dictionary) -> void:
			if is_instance_valid(l):
				l.set_params(p)
		if hm:
			hm.register_action("Luz · restablecer")
			hm.add_do(apply_p.bind(after))
			hm.add_undo(apply_p.bind(before))
			hm.commit()
		apply_p.call(after)
		if ic and ic.has_method("_sync_selection"):
			ic.call_deferred("_sync_selection")
	else:
		var t := String(LightToolScript.settings.get("type", "point"))
		LightToolScript.settings = d.duplicate()
		LightToolScript.settings["type"] = t
	sync()

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
			# tiempo real mientras se escribe (la sombra y la luz siguen al número)
			nf.live_typing = true
			nf.live_value.connect(func(v: float) -> void: _preview(key, v / k_scale))
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

## Vista previa sin historial (se escribe un número): se guarda el valor de
## antes para que el paso de deshacer vaya desde él.
var _live_orig := {}

func _preview(key: String, value) -> void:
	var l := selected_light()
	if l == null or _syncing:
		return
	var prop := "lamp_" + key
	if not _live_orig.has(key) or _live_orig[key][0] != l.get_instance_id():
		_live_orig[key] = [l.get_instance_id(), l.get(prop)]
	l.set(prop, value)

func _put(key: String, value) -> void:
	if _syncing:
		return
	var l := selected_light()
	if l and _live_orig.has(key):
		if _live_orig[key][0] == l.get_instance_id():
			l.set("lamp_" + key, _live_orig[key][1])   # el historial parte de aquí
		_live_orig.erase(key)
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
	for key in ["shadows", "shadow_color", "shadow_length", "shadow_soft", "shadow_fade"]:
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
	for pc in _cards:
		TPS.style_card(pc)
	if _reset:
		TPS.style_action(_reset)
