# =============================================================================
# RUTA: res://script_gdscript/ui/panel_blend.gd
# PANEL «FUSIÓN» (Blend). Se abre solo al seleccionar una fusión y edita la
# seleccionada: modo (pasos fijos / por distancia), nº de pasos o distancia,
# orientar con la guía, invertir orden, expandir y soltar. Compacto, como el
# de Iluminación; los números se pueden ARRASTRAR (vista previa en vivo y un
# solo paso de deshacer al soltar). Pedido del usuario: «falta panel de blend
# para poder cambiar la configuración».
# =============================================================================
extends PanelContainer

const TPS = preload("res://script_gdscript/ui/components/tool_panel_style.gd")
const NF = preload("res://script_gdscript/ui/components/numeric_field.gd")
const BlendScript = preload("res://script_gdscript/shapes/blend.gd")

var _title: Label
var _info: Label
var _labels: Array = []
var _sections: Array = []
var _cards: Array = []
var _mode_buttons := {}
var _steps: NF
var _spacing: NF
var _orient: CheckButton
var _rows := {}
var _actions: Array = []
var _syncing := false
var _live_orig := {}   # prop → valor antes del arrastre
var _auto_opened := false

func _ready() -> void:
	name = "blend"
	custom_minimum_size = Vector2(290, 0)
	_build()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.changed.connect(func(_p) -> void:
			var g := blend()
			if g != null and not visible:
				var ge := get_node_or_null("/root/GlobalEvents")
				if ge and ge.has_method("emit_safe"):
					ge.emit_safe("request_tool_panel", "blend")
				if not visible:
					visible = true
				_auto_opened = true
			elif g == null and visible and _auto_opened:
				visible = false   # se abrió por la selección: se cierra con ella
				_auto_opened = false
			sync())
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _apply_theme())
	visibility_changed.connect(func() -> void:
		if visible:
			sync())
	_apply_theme()
	sync()

## La fusión seleccionada (o la que contiene lo seleccionado), o null.
func blend() -> Node2D:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return null
	var sel: Array = ic.selection()
	if sel.size() != 1 or not is_instance_valid(sel[0]):
		return null
	return BlendScript.blend_of(sel[0])

func _build() -> void:
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 8)
	add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	m.add_child(vb)
	_title = Label.new()
	_title.text = tr("Fusión")
	vb.add_child(_title)
	_info = Label.new()
	_info.name = "Info"
	_info.add_theme_font_size_override("font_size", 10)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_info)
	# Pasos
	var sbox := _card(vb, tr("PASOS"))
	var modes := HBoxContainer.new()
	modes.name = "Modes"
	modes.add_theme_constant_override("separation", 4)
	sbox.add_child(modes)
	for it in [["steps", "Pasos fijos", "Un número fijo de pasos entre cada par de objetos"],
			["distance", "Por distancia", "Un paso cada cierta distancia"]]:
		var b := Button.new()
		b.name = "Mode_" + String(it[0])
		b.text = tr(String(it[1]))
		b.tooltip_text = tr(String(it[2]))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		var mode_id := String(it[0])
		b.pressed.connect(func() -> void: _commit("blend_mode", mode_id))
		modes.add_child(b)
		_mode_buttons[mode_id] = b
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	sbox.add_child(grid)
	_steps = _num(grid, "blend_steps", "Pasos", 0, 500, 1, "")
	_spacing = _num(grid, "blend_spacing", "Distancia", 0.5, 5000, 1, " px")
	var ol := Label.new()
	ol.text = tr("Orientar con la guía")
	ol.add_theme_font_size_override("font_size", 11)
	grid.add_child(ol)
	_labels.append(ol)
	_orient = CheckButton.new()
	_orient.name = "Blend_orient"
	_orient.focus_mode = Control.FOCUS_NONE
	_orient.tooltip_text = tr("Con una guía: cada paso gira siguiendo la dirección del trazado")
	_orient.toggled.connect(func(on: bool) -> void: _commit("blend_orient", on))
	grid.add_child(_orient)
	_rows["blend_orient"] = [ol, _orient]
	# Acciones
	var abox := _card(vb, tr("ACCIONES"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	abox.add_child(row)
	for it in [["Reverse", "⇄ " + tr("Invertir"), "Invertir el orden de la cadena (C → B → A)"],
			["Expand", "⊞ " + tr("Expandir"), "Convertir los pasos en figuras normales"],
			["Release", "⊟ " + tr("Soltar"), "Quitar la fusión: deja los objetos sueltos"]]:
		var b := Button.new()
		b.name = String(it[0])
		b.text = String(it[1])
		b.tooltip_text = tr(String(it[2]))
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 24)
		b.add_theme_font_size_override("font_size", 11)
		var id := String(it[0])
		b.pressed.connect(func() -> void: _action(id))
		row.add_child(b)
		_actions.append(b)

func _card(parent: Control, title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.name = "Card_" + title
	parent.add_child(pc)
	_cards.append(pc)
	var inner := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inner.add_theme_constant_override(k, 6)
	pc.add_child(inner)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	inner.add_child(v)
	var l := Label.new()
	l.text = title
	v.add_child(l)
	_sections.append(l)
	return v

func _num(grid: GridContainer, prop: String, text: String, lo: float, hi: float, step: float, suffix: String) -> NF:
	var l := Label.new()
	l.text = tr(text)
	l.add_theme_font_size_override("font_size", 11)
	grid.add_child(l)
	_labels.append(l)
	var nf := NF.new("", suffix, lo, hi, step)
	nf.name = "Blend_" + prop.trim_prefix("blend_")
	nf.decimals = 0
	nf.custom_minimum_size = Vector2(90, 22)
	nf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# arrastrar = vista previa en vivo; al soltar, un paso de deshacer
	nf.value_changed.connect(func(v: float) -> void:
		if nf.get("_is_dragging"):
			_preview(prop, v)
		else:
			_commit(prop, v))
	nf.drag_ended.connect(func() -> void: _commit(prop, nf.value))
	nf.live_typing = true
	nf.live_value.connect(func(v: float) -> void: _preview(prop, v))
	grid.add_child(nf)
	_rows[prop] = [l, nf]
	return nf

func _preview(prop: String, value) -> void:
	var g := blend()
	if g == null or _syncing:
		return
	if not _live_orig.has(prop):
		_live_orig[prop] = BlendScript.read_prop(g, prop)
	BlendScript.write_prop(g, prop, value)   # sin historial (se rehace al momento)
	_info.text = _summary(g)

func _commit(prop: String, value) -> void:
	if _syncing:
		return
	var g := blend()
	if g == null:
		return
	if _live_orig.has(prop):
		BlendScript.write_prop(g, prop, _live_orig[prop])   # el deshacer parte de aquí
		_live_orig.erase(prop)
	if BlendScript.read_prop(g, prop) == value or (value is float and is_equal_approx(float(BlendScript.read_prop(g, prop)), value)):
		BlendScript.rebuild(g)
		sync()
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply(prop, value)
	sync()

func _action(id: String) -> void:
	var g := blend()
	var pm := get_node_or_null("/root/PluginManager")
	if g == null or pm == null or pm.api == null:
		return
	match id:
		"Reverse":
			pm.api.reverse_blend(g)
		"Expand":
			pm.api.expand_blend(g)
			pm.api.select([g])   # ya es un grupo normal: el panel se cierra
		"Release":
			var loose: Array = BlendScript.keys(g)
			pm.api.release_blend(g)
			pm.api.select(loose)   # quedan seleccionados los objetos sueltos
	sync()

func _summary(g: Node2D) -> String:
	var k: Array = BlendScript.keys(g)
	var n := 0
	for c in g.get_children():
		if c.has_meta(BlendScript.STEP_META):
			n += 1
	var guide := tr(" · con guía") if BlendScript.spine_of(g) != null else ""
	return tr("%d objetos · %d pasos%s") % [k.size(), n, guide]

func sync() -> void:
	if not is_inside_tree():
		return
	var g := blend()
	_syncing = true
	for b in _actions:
		(b as Button).disabled = g == null
	if g == null:
		_info.text = tr("Selecciona una fusión (clic derecho ▸ «Crear fusión» con dos o más figuras).")
		_syncing = false
		_apply_theme()
		return
	var mode := String(BlendScript.read_prop(g, "blend_mode"))
	for k in _mode_buttons:
		(_mode_buttons[k] as Button).set_pressed_no_signal(k == mode)
	_steps.set_value_silent(float(BlendScript.read_prop(g, "blend_steps")))
	_spacing.set_value_silent(float(BlendScript.read_prop(g, "blend_spacing")))
	_orient.set_pressed_no_signal(bool(BlendScript.read_prop(g, "blend_orient")))
	for n in _rows["blend_steps"]:
		(n as Control).visible = mode == "steps"
	for n in _rows["blend_spacing"]:
		(n as Control).visible = mode == "distance"
	for n in _rows["blend_orient"]:
		(n as Control).visible = BlendScript.spine_of(g) != null
	_info.text = _summary(g)
	_syncing = false
	_apply_theme()

func _apply_theme() -> void:
	TPS.apply_frame(self)
	TPS.style_title(_title)
	TPS.style_muted(_info)
	for l in _labels:
		TPS.style_text(l)
	for l in _sections:
		TPS.style_section_label(l)
	for k in _mode_buttons:
		TPS.style_toggle(_mode_buttons[k], (_mode_buttons[k] as Button).button_pressed)
	for pc in _cards:
		TPS.style_card(pc)
	for b in _actions:
		TPS.style_action(b)
