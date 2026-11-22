# =============================================================================
# RUTA: res://script_gdscript/ui/panel_layout.gd
# PANEL «CONTENEDOR» (Auto Layout: flex y grid). Se abre solo al seleccionar
# un contenedor y edita el seleccionado: tipo (fila, columna, rejilla, fila
# con salto de línea), separación, margen interior, columnas, ancho de línea,
# alineación principal y cruzada, tamaño automático y «Quitar contenedor».
# Compacto como los paneles de Iluminación y Fusión; los números se arrastran
# con vista previa en vivo y UN paso de deshacer. Pedido del usuario: «su
# panel dónde está para configuración».
# =============================================================================
extends PanelContainer

const TPS = preload("res://script_gdscript/ui/components/tool_panel_style.gd")
const NF = preload("res://script_gdscript/ui/components/numeric_field.gd")
const AL = preload("res://script_gdscript/shapes/auto_layout.gd")

const MODE_ITEMS := [["row", "→", "Fila", "Elementos en fila (como flex en horizontal)"],
	["column", "↓", "Columna", "Elementos en columna (como flex en vertical)"],
	["grid", "▦", "Rejilla", "Rejilla de filas y columnas (como grid)"],
	["wrap", "↩", "Salto", "Fila que salta de línea al llegar al ancho (como flex-wrap)"]]
const ALIGN_ITEMS := [["start", "⇤", "Al inicio"], ["center", "⇹", "Centrado"],
	["end", "⇥", "Al final"], ["space-between", "↔", "Repartir el espacio"]]
const CROSS_ITEMS := [["start", "⤒", "Arriba / izquierda"], ["center", "⊝", "Centro"],
	["end", "⤓", "Abajo / derecha"]]

var _title: Label
var _info: Label
var _labels: Array = []
var _sections: Array = []
var _cards: Array = []
var _toggles := {}      # prop → {valor: Button}
var _nums := {}         # prop → NF
var _rows := {}         # prop → [controles]
var _auto: CheckButton
var _release: Button
var _syncing := false
var _live_orig := {}
var _auto_opened := false

func _ready() -> void:
	name = "layout"
	custom_minimum_size = Vector2(290, 0)
	_build()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.changed.connect(func(_p) -> void:
			var g := container()
			if g != null and not visible:
				var ge := get_node_or_null("/root/GlobalEvents")
				if ge and ge.has_method("emit_safe"):
					ge.emit_safe("request_tool_panel", "layout")
				if not visible:
					visible = true
				_auto_opened = true
			elif g == null and visible and _auto_opened:
				visible = false
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

## El contenedor seleccionado, o null.
func container() -> Node2D:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return null
	var sel: Array = ic.selection()
	if sel.size() == 1 and is_instance_valid(sel[0]) and AL.is_layout(sel[0]):
		return sel[0]
	return null

func _build() -> void:
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 8)
	add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	m.add_child(vb)
	_title = Label.new()
	_title.text = tr("Contenedor")
	vb.add_child(_title)
	_info = Label.new()
	_info.name = "Info"
	_info.add_theme_font_size_override("font_size", 10)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_info)
	# Tipo
	var tbox := _card(vb, tr("TIPO"))
	tbox.add_child(_toggle_row("layout_mode", MODE_ITEMS, true))
	# Espaciado
	var sbox := _card(vb, tr("ESPACIADO"))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 4)
	sbox.add_child(g)
	_num(g, "layout_gap", "Separación", 0, 2000, 1, " px")
	_num(g, "layout_padding", "Margen interior", 0, 2000, 1, " px")
	_num(g, "layout_columns", "Columnas", 1, 64, 1, "")
	_num(g, "layout_wrap_width", "Ancho de línea", 10, 20000, 5, " px")
	# Alineación
	var abox := _card(vb, tr("ALINEACIÓN"))
	var la := Label.new()
	la.text = tr("Principal")
	la.add_theme_font_size_override("font_size", 11)
	abox.add_child(la)
	_labels.append(la)
	abox.add_child(_toggle_row("layout_align", ALIGN_ITEMS, false))
	var lc := Label.new()
	lc.text = tr("Cruzada")
	lc.add_theme_font_size_override("font_size", 11)
	abox.add_child(lc)
	_labels.append(lc)
	abox.add_child(_toggle_row("layout_cross", CROSS_ITEMS, false))
	# Tamaño y acciones
	var obox := _card(vb, tr("OPCIONES"))
	var row := HBoxContainer.new()
	obox.add_child(row)
	var al := Label.new()
	al.text = tr("Tamaño automático")
	al.tooltip_text = tr("El contenedor crece o encoge con su contenido")
	al.add_theme_font_size_override("font_size", 11)
	al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(al)
	_labels.append(al)
	_auto = CheckButton.new()
	_auto.name = "Layout_auto"
	_auto.focus_mode = Control.FOCUS_NONE
	_auto.toggled.connect(func(on: bool) -> void: _commit("layout_auto", on))
	row.add_child(_auto)
	_release = Button.new()
	_release.name = "Release"
	_release.text = "⊟ " + tr("Quitar contenedor")
	_release.tooltip_text = tr("Deja los elementos sueltos, donde están")
	_release.focus_mode = Control.FOCUS_NONE
	_release.custom_minimum_size = Vector2(0, 24)
	_release.add_theme_font_size_override("font_size", 11)
	_release.pressed.connect(_on_release)
	obox.add_child(_release)

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

## Fila de botones excluyentes (glifo + nombre si `with_text`).
func _toggle_row(prop: String, items: Array, with_text: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row_" + prop
	row.add_theme_constant_override("separation", 4)
	var bmap := {}
	for it in items:
		var b := Button.new()
		var val := String(it[0])
		b.name = "%s_%s" % [prop.trim_prefix("layout_"), val]
		b.text = ("%s %s" % [it[1], tr(String(it[2]))]) if with_text else String(it[1])
		b.tooltip_text = tr(String(it[3] if it.size() > 3 else it[2]))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11 if with_text else 13)
		b.pressed.connect(func() -> void: _commit(prop, val))
		row.add_child(b)
		bmap[val] = b
	_toggles[prop] = bmap
	return row

func _num(grid: GridContainer, prop: String, text: String, lo: float, hi: float, step: float, suffix: String) -> void:
	var l := Label.new()
	l.text = tr(text)
	l.add_theme_font_size_override("font_size", 11)
	grid.add_child(l)
	_labels.append(l)
	var nf := NF.new("", suffix, lo, hi, step)
	nf.name = "Layout_" + prop.trim_prefix("layout_")
	nf.decimals = 0
	nf.custom_minimum_size = Vector2(90, 22)
	nf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nf.value_changed.connect(func(v: float) -> void:
		if nf.get("_is_dragging"):
			_preview(prop, v)
		else:
			_commit(prop, v))
	nf.drag_ended.connect(func() -> void: _commit(prop, nf.value))
	nf.live_typing = true
	nf.live_value.connect(func(v: float) -> void: _preview(prop, v))
	grid.add_child(nf)
	_nums[prop] = nf
	_rows[prop] = [l, nf]

func _preview(prop: String, value) -> void:
	var g := container()
	if g == null or _syncing:
		return
	if not _live_orig.has(prop):
		_live_orig[prop] = AL.read_prop(g, prop)
	AL.write_prop(g, prop, value)   # sin historial: se recoloca al momento

func _commit(prop: String, value) -> void:
	if _syncing:
		return
	var g := container()
	if g == null:
		return
	if _live_orig.has(prop):
		AL.write_prop(g, prop, _live_orig[prop])   # el deshacer parte de aquí
		_live_orig.erase(prop)
	var cur = AL.read_prop(g, prop)
	if cur == value or (cur is float and value is float and is_equal_approx(cur, value)):
		AL.apply(g)
		sync()
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply(prop, value)
	sync()

func _on_release() -> void:
	var g := container()
	var pm := get_node_or_null("/root/PluginManager")
	if g == null or pm == null or pm.api == null:
		return
	var kids: Array = AL.items(g)
	pm.api.release_layout(g)
	pm.api.select(kids.filter(func(k) -> bool: return is_instance_valid(k)))
	sync()

func sync() -> void:
	if not is_inside_tree():
		return
	var g := container()
	_syncing = true
	_release.disabled = g == null
	if g == null:
		_info.text = tr("Selecciona un contenedor (clic derecho ▸ «Convertir en contenedor» con varios objetos).")
		_syncing = false
		_apply_theme()
		return
	for prop in _toggles:
		var cur := String(AL.read_prop(g, prop))
		for v in _toggles[prop]:
			(_toggles[prop][v] as Button).set_pressed_no_signal(v == cur)
	for prop in _nums:
		(_nums[prop] as NF).set_value_silent(float(AL.read_prop(g, prop)))
	_auto.set_pressed_no_signal(bool(AL.read_prop(g, "layout_auto")))
	var mode := String(AL.read_prop(g, "layout_mode"))
	for n in _rows["layout_columns"]:
		(n as Control).visible = mode == "grid"
	for n in _rows["layout_wrap_width"]:
		(n as Control).visible = mode == "wrap"
	var names := {"row": tr("Fila"), "column": tr("Columna"), "grid": tr("Rejilla"), "wrap": tr("Fila con salto")}
	_info.text = tr("%d elementos · %s") % [AL.items(g).size(), names.get(mode, mode)]
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
	for prop in _toggles:
		for v in _toggles[prop]:
			TPS.style_toggle(_toggles[prop][v], (_toggles[prop][v] as Button).button_pressed)
	for pc in _cards:
		TPS.style_card(pc)
	if _release:
		TPS.style_action(_release)
