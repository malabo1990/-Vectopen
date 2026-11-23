# =============================================================================
# RUTA: res://script_gdscript/ui/panel_table.gd
# PANEL «TABLA»: se abre al seleccionar una tabla y la maneja como una tabla
# de verdad (pedido del usuario: «arreglar bien la tabla y su panel de
# configuración»).
#   · ESTRUCTURA: nº de filas y columnas; insertar fila arriba / abajo y
#     columna a la izquierda / derecha de la CELDA ACTIVA; borrar su fila /
#     columna. La celda activa es la última editada con doble clic.
#   · TAMAÑO: alto de fila, ancho de la columna activa, igualar columnas.
#   · ESTILO: cabecera, filas alternas, letra, borde, alineación y colores.
# Cada cambio es UN paso de deshacer (Table.edit / InspectorCore).
# =============================================================================
extends PanelContainer

const TPS = preload("res://script_gdscript/ui/components/tool_panel_style.gd")
const NF = preload("res://script_gdscript/ui/components/numeric_field.gd")
const Table = preload("res://script_gdscript/shapes/table.gd")

var _title: Label
var _info: Label
var _labels: Array = []
var _sections: Array = []
var _cards: Array = []
var _buttons: Array = []
var _nums := {}
var _checks := {}
var _colors := {}
var _align := {}
var _syncing := false
var _auto_opened := false
var _last_table: Node2D = null

func _ready() -> void:
	name = "table"
	custom_minimum_size = Vector2(290, 0)
	_build()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.changed.connect(func(_p) -> void:
			var t := table()
			if t != null and (not visible or t != _last_table or _others_visible()):
				# al seleccionar una tabla su panel es EL panel (oculta los demás:
				# antes podía quedar «Bézier y nodos» encima)
				var ge := get_node_or_null("/root/GlobalEvents")
				if ge and ge.has_method("emit_safe"):
					ge.emit_safe("request_tool_panel", "table")
				if not visible:
					visible = true
				_auto_opened = true
			elif t == null and visible and _auto_opened:
				visible = false
				_auto_opened = false
			_last_table = t
			_sync_soon())
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _apply_theme())
	visibility_changed.connect(func() -> void:
		if visible:
			sync())
	_apply_theme()
	sync()

## ¿Hay otro panel de herramienta abierto a la vez (p. ej. «Bézier y nodos»)?
func _others_visible() -> bool:
	var host := get_parent()
	if host == null:
		return false
	for c in host.get_children():
		if c != self and c is Control and (c as Control).visible and c.name in ["polygon", "text", "Selector", "bezier", "brush", "light", "blend", "layout"]:
			return true
	return false

func table() -> Node2D:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return null
	var sel: Array = ic.selection()
	if sel.size() == 1 and is_instance_valid(sel[0]):
		return Table.table_of(sel[0])
	return null

func _api():
	var pm := get_node_or_null("/root/PluginManager")
	return pm.api if pm else null

## Celda activa [fila, columna] (la última editada; si no, la última celda).
func active_cell(t: Node2D) -> Array:
	var s: Dictionary = t.get_meta(Table.META)
	var rc: Array = t.get_meta("_active_cell", []) if t.has_meta("_active_cell") else []
	if rc.size() != 2:
		return [int(s["rows"]) - 1, int(s["cols"]) - 1]
	return [clampi(int(rc[0]), 0, int(s["rows"]) - 1), clampi(int(rc[1]), 0, int(s["cols"]) - 1)]

# ── construcción ─────────────────────────────────────────────────────────────
func _build() -> void:
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 8)
	add_child(m)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	m.add_child(outer)
	_title = Label.new()
	_title.text = tr("Tabla")
	outer.add_child(_title)
	_info = Label.new()
	_info.name = "Info"
	_info.add_theme_font_size_override("font_size", 10)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_info)
	# contenido con DESPLAZAMIENTO y altura limitada: nunca llega al borde
	# inferior de la ventana (botón central también desplaza)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	_scroll.add_child(vb)
	_content = vb
	vb.minimum_size_changed.connect(func() -> void: _fit.call_deferred())
	visibility_changed.connect(func() -> void:
		if visible:
			_fit.call_deferred())
	# Estructura
	var sbox := _card(vb, tr("ESTRUCTURA"))
	var g := _grid(sbox)
	_num(g, "rows", "Filas", 1, 200, 1, "")
	_num(g, "cols", "Columnas", 1, 50, 1, "")
	var r1 := _row(sbox)
	_btn(r1, "RowAbove", "↑ " + tr("Fila arriba"), "Insertar una fila encima de la celda activa", func() -> void: _insert_row(0))
	_btn(r1, "RowBelow", "↓ " + tr("Fila abajo"), "Insertar una fila debajo de la celda activa", func() -> void: _insert_row(1))
	var r2 := _row(sbox)
	_btn(r2, "ColLeft", "← " + tr("Col. izquierda"), "Insertar una columna a la izquierda de la celda activa", func() -> void: _insert_col(0))
	_btn(r2, "ColRight", "→ " + tr("Col. derecha"), "Insertar una columna a la derecha de la celda activa", func() -> void: _insert_col(1))
	var r3 := _row(sbox)
	_btn(r3, "DelRow", "✕ " + tr("Borrar fila"), "Borrar la fila de la celda activa", _delete_row)
	_btn(r3, "DelCol", "✕ " + tr("Borrar columna"), "Borrar la columna de la celda activa", _delete_col)
	# Tamaño
	var zbox := _card(vb, tr("TAMAÑO"))
	var gz := _grid(zbox)
	_num(gz, "row_h", "Alto de fila", 8, 2000, 1, " px")
	_num(gz, "col_w", "Ancho de columna", 8, 4000, 1, " px")
	var r4 := _row(zbox)
	_btn(r4, "EqualCols", "⇔ " + tr("Igualar columnas"), "Todas las columnas con el mismo ancho", _equalize)
	# Estilo
	var ebox := _card(vb, tr("ESTILO"))
	var ge := _grid(ebox)
	_check(ge, "table_header", "Cabecera")
	_check(ge, "table_zebra", "Filas alternas")
	_num(ge, "table_font_size", "Tamaño de letra", 4, 400, 1, " px")
	_num(ge, "table_border", "Borde", 0, 50, 1, " px")
	var la := Label.new()
	la.text = tr("Alineación")
	la.add_theme_font_size_override("font_size", 11)
	ebox.add_child(la)
	_labels.append(la)
	var ar := _row(ebox)
	for it in [["left", "⇤", "Izquierda"], ["center", "⇹", "Centro"], ["right", "⇥", "Derecha"]]:
		var b := Button.new()
		b.name = "Align_" + String(it[0])
		b.text = String(it[1])
		b.tooltip_text = tr(String(it[2]))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 24)
		var v := String(it[0])
		b.pressed.connect(func() -> void: _apply("table_align", v))
		ar.add_child(b)
		_align[v] = b
	var gc := _grid(ebox)
	for it in [["table_header_bg", "Fondo cabecera"], ["table_header_fg", "Texto cabecera"],
			["table_cell_bg", "Fondo celdas"], ["table_zebra_bg", "Fondo alterno"],
			["table_text_color", "Texto"], ["table_border_color", "Color bordes"]]:
		var l := Label.new()
		l.text = tr(String(it[1]))
		l.add_theme_font_size_override("font_size", 11)
		gc.add_child(l)
		_labels.append(l)
		var cp := ColorPickerButton.new()
		cp.name = "Color_" + String(it[0]).trim_prefix("table_")
		cp.custom_minimum_size = Vector2(90, 22)
		cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key := String(it[0])
		cp.popup_closed.connect(func() -> void: _apply(key, cp.color))
		gc.add_child(cp)
		_colors[key] = cp

const BOTTOM_GAP := 16.0
var _scroll: ScrollContainer
var _content: VBoxContainer

func _fit() -> void:
	if not is_inside_tree() or _scroll == null or _content == null:
		return
	var want := _content.get_combined_minimum_size().y
	var head_h := _scroll.global_position.y - global_position.y
	var avail := get_viewport_rect().size.y - global_position.y - head_h - BOTTOM_GAP - 8.0
	_scroll.custom_minimum_size.y = clampf(want, 80.0, maxf(avail, 80.0))
	reset_size()

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

func _grid(parent: Control) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 4)
	parent.add_child(g)
	return g

func _row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 4)
	parent.add_child(r)
	return r

func _btn(row: Control, nm: String, text: String, tip: String, cb: Callable) -> void:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.tooltip_text = tr(tip)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 24)
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	row.add_child(b)
	_buttons.append(b)

func _num(grid: GridContainer, key: String, text: String, lo: float, hi: float, step: float, suffix: String) -> void:
	var l := Label.new()
	l.text = tr(text)
	l.add_theme_font_size_override("font_size", 11)
	grid.add_child(l)
	_labels.append(l)
	var nf := NF.new("", suffix, lo, hi, step)
	nf.name = "Table_" + key.trim_prefix("table_")
	nf.decimals = 0
	nf.custom_minimum_size = Vector2(90, 22)
	nf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nf.value_changed.connect(func(v: float) -> void:
		if not nf.get("_is_dragging"):
			_on_num(key, v))
	nf.drag_ended.connect(func() -> void: _on_num(key, nf.value))
	grid.add_child(nf)
	_nums[key] = nf

func _check(grid: GridContainer, key: String, text: String) -> void:
	var l := Label.new()
	l.text = tr(text)
	l.add_theme_font_size_override("font_size", 11)
	grid.add_child(l)
	_labels.append(l)
	var cb := CheckButton.new()
	cb.name = "Table_" + key.trim_prefix("table_")
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(on: bool) -> void: _apply(key, on))
	grid.add_child(cb)
	_checks[key] = cb

# ── acciones ─────────────────────────────────────────────────────────────────
func _apply(prop: String, value) -> void:
	if _syncing or table() == null:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply(prop, value)
	sync()

func _on_num(key: String, v: float) -> void:
	if _syncing:
		return
	var t := table()
	if t == null:
		return
	match key:
		"rows": _set_count(t, "rows", int(v))
		"cols": _set_count(t, "cols", int(v))
		"row_h": _apply("table_row_h", v)
		"col_w":
			var c := int(active_cell(t)[1])
			Table.edit(t, "Tabla · ancho de columna", func(s: Dictionary) -> void:
				(s["col_w"] as Array)[c] = maxf(8.0, v))
		_: _apply(key, v)
	sync()

## Cambia el nº de filas / columnas (añade o quita al final), un paso.
func _set_count(t: Node2D, what: String, n: int) -> void:
	var s: Dictionary = t.get_meta(Table.META)
	var cur := int(s[what])
	n = maxi(1, n)
	if n == cur:
		return
	Table.edit(t, "Tabla · filas" if what == "rows" else "Tabla · columnas", func(sp: Dictionary) -> void:
		while int(sp[what]) < n:
			if what == "rows":
				Table.op_insert_row(sp, int(sp["rows"]))
			else:
				Table.op_insert_col(sp, int(sp["cols"]), float((sp["col_w"] as Array)[-1]))
		while int(sp[what]) > n:
			if what == "rows":
				Table.op_delete_row(sp, int(sp["rows"]) - 1)
			else:
				Table.op_delete_col(sp, int(sp["cols"]) - 1))

func _insert_row(after: int) -> void:
	var t := table()
	var api = _api()
	if t == null or api == null:
		return
	var r := int(active_cell(t)[0]) + after
	api.table_insert_row(t, r)
	t.set_meta("_active_cell", [r, int(active_cell(t)[1])])
	sync()

func _insert_col(after: int) -> void:
	var t := table()
	var api = _api()
	if t == null or api == null:
		return
	var c := int(active_cell(t)[1]) + after
	var s: Dictionary = t.get_meta(Table.META)
	api.table_insert_col(t, c, float((s["col_w"] as Array)[int(active_cell(t)[1])]))
	t.set_meta("_active_cell", [int(active_cell(t)[0]), c])
	sync()

func _delete_row() -> void:
	var t := table()
	var api = _api()
	if t == null or api == null:
		return
	api.table_delete_row(t, int(active_cell(t)[0]))
	sync()

func _delete_col() -> void:
	var t := table()
	var api = _api()
	if t == null or api == null:
		return
	api.table_delete_col(t, int(active_cell(t)[1]))
	sync()

func _equalize() -> void:
	var t := table()
	if t == null:
		return
	Table.edit(t, "Tabla · igualar columnas", func(s: Dictionary) -> void:
		var total := 0.0
		for w in s["col_w"]:
			total += float(w)
		var each := total / float(int(s["cols"]))
		var cw: Array = []
		for c in int(s["cols"]):
			cw.append(each)
		s["col_w"] = cw)
	sync()

# ── sincronizar ──────────────────────────────────────────────────────────────
## Rendimiento (clic / soltar sobre figuras): sincronizar SOLO si el panel se
## ve, y como mucho UNA vez por fotograma. Antes cada cambio de selección
## reconstruía los cuatro paneles nuevos aunque estuvieran ocultos (~170 ms
## por clic). Oculto, se sincroniza al mostrarse (visibility_changed).
var _sync_pending := false

func _sync_soon() -> void:
	if _sync_pending or not is_visible_in_tree():
		return
	_sync_pending = true
	(func() -> void:
		_sync_pending = false
		if is_inside_tree() and is_visible_in_tree():
			sync()).call_deferred()

func sync() -> void:
	if not is_inside_tree():
		return
	var t := table()
	_syncing = true
	for b in _buttons:
		(b as Button).disabled = t == null
	if t == null:
		_info.text = tr("Selecciona una tabla (clic derecho ▸ «Insertar tabla»). Doble clic en una celda para escribir.")
		_syncing = false
		_apply_theme()
		return
	var s: Dictionary = t.get_meta(Table.META)
	var rc := active_cell(t)
	_info.text = tr("%d filas × %d columnas · celda activa %d, %d · doble clic en una celda para escribir") % [int(s["rows"]), int(s["cols"]), int(rc[0]) + 1, int(rc[1]) + 1]
	(_nums["rows"] as NF).set_value_silent(float(s["rows"]))
	(_nums["cols"] as NF).set_value_silent(float(s["cols"]))
	(_nums["row_h"] as NF).set_value_silent(float(s["row_h"]))
	(_nums["col_w"] as NF).set_value_silent(float((s["col_w"] as Array)[int(rc[1])]))
	(_nums["table_font_size"] as NF).set_value_silent(float(s.get("font_size", 16)))
	(_nums["table_border"] as NF).set_value_silent(float(s.get("border", 1.0)))
	(_checks["table_header"] as CheckButton).set_pressed_no_signal(bool(s.get("header", true)))
	(_checks["table_zebra"] as CheckButton).set_pressed_no_signal(bool(s.get("zebra", true)))
	var al: Array = s.get("align", [])
	var cur_al := String(al[int(rc[1])]) if int(rc[1]) < al.size() else "left"
	for v in _align:
		(_align[v] as Button).set_pressed_no_signal(v == cur_al)
	for key in _colors:
		var ck: String = {"table_header_bg": "header_bg", "table_header_fg": "header_fg", "table_cell_bg": "cell_bg",
			"table_zebra_bg": "zebra_bg", "table_text_color": "text", "table_border_color": "border"}[key]
		(_colors[key] as ColorPickerButton).color = Table._col(s, ck)
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
	for v in _align:
		TPS.style_toggle(_align[v], (_align[v] as Button).button_pressed)
	for pc in _cards:
		TPS.style_card(pc)
	for b in _buttons:
		TPS.style_action(b)
