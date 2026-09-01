# ==========================================
# RUTA: res://script_gdscript/ui/transform_panel.gd
# Panel de transformación compacto (estilo profesional).
# ==========================================
extends PanelContainer
class_name TransformPanel
## Rejilla 3×3 compacta:
##   [radio TL] [  Y  ] [radio TR]
##   [   X    ] [ ROT ] [   W    ]
##   [radio BL] [  H  ] [radio BR]
## + botón Reset.
##
## Se construye a sí mismo (no depende del .tscn) y sincroniza en dos vías con
## InspectorCore: X/Y → pos_x/pos_y, W/H → width/height, ROT → rotation,
## los 4 diales de esquina → corner_tl/tr/br/bl (radios independientes).

# Paleta — se rellena desde ThemeManager (tokens de diseño). Los valores aquí
# son solo el fallback si el autoload no está.
var _BG_PANEL := Color("f8f8fa")
var _BG_CARD := Color("ffffff")
var _BG_HOVER := Color("eceef2")
var _ACCENT := Color("0a84ff")
var _TEXT := Color("1c1c1e")
var _MUTED := Color("6c6c70")
var _BORDER := Color("d1d1d6")

func _pull_theme() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null:
		return
	var S = tm.Slot
	_BG_PANEL = tm.get_color(S.PANEL_BG)
	_BG_CARD  = tm.get_color(S.WIDGET_BG)
	_BG_HOVER = tm.get_color(S.BUTTON_HOVER)
	_ACCENT   = tm.get_color(S.ACCENT)
	_TEXT     = tm.get_color(S.PANEL_TEXT)
	_MUTED    = tm.get_color(S.TEXT_SECONDARY)
	_BORDER   = tm.get_color(S.BORDER)

var _fields: Dictionary = {}       # prop -> Field
var _rot: Dial = null
var _corners: Dictionary = {}      # "corner_tl".. -> Dial
var _sync_guard := false
var _has_selection := false

# ─────────────────────────────────── campo numérico con arrastre (scrub)
## Arrastrar horizontal = cambiar el valor (como arrastre). Clic simple =
## editar a mano. Emite value_changed durante el arrastre y submitted al escribir.
class Field extends PanelContainer:
	signal value_changed(v: float)
	signal drag_started()
	signal drag_ended()
	signal submitted(v: float)

	var value: float = 0.0
	var step: float = 0.5          # unidades por px de arrastre
	var min_value: float = -999999.0
	var decimals: int = 2
	var enabled: bool = true

	var _le: LineEdit
	var _dragging := false
	var _drag_px := 0.0
	var _editing := false

	func _init(lbl: String, text_col: Color, muted: Color, card: Color, border: Color) -> void:
		custom_minimum_size = Vector2(56, 38)
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
		var sb := StyleBoxFlat.new()
		sb.bg_color = card
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(1)
		sb.border_color = border
		sb.set_content_margin_all(3)
		add_theme_stylebox_override("panel", sb)

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)

		var l := Label.new()
		l.text = lbl
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", muted)
		l.add_theme_font_size_override("font_size", 8)
		box.add_child(l)

		_le = LineEdit.new()
		_le.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_le.add_theme_color_override("font_color", text_col)
		_le.add_theme_font_size_override("font_size", 11)
		_le.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		_le.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_le.mouse_filter = Control.MOUSE_FILTER_IGNORE   # el drag lo captura el panel
		_le.text_submitted.connect(func(_t): _exit_edit(true))
		_le.focus_exited.connect(func(): _exit_edit(true))
		box.add_child(_le)
		_refresh_text()

	func set_value_silent(v: float) -> void:
		value = v
		_refresh_text()

	func set_disabled_text(t: String) -> void:
		enabled = false
		_le.text = t

	func _refresh_text() -> void:
		if _editing:
			return
		if is_equal_approx(value, roundf(value)):
			_le.text = "%d" % int(roundf(value))
		else:
			_le.text = (("%." + str(decimals) + "f") % value).rstrip("0").rstrip(".")

	## Para tests / código: simula escribir y confirmar un valor.
	func type_value(v: float) -> void:
		_editing = true
		_le.text = str(v)
		_exit_edit(true)

	func displayed_text() -> String:
		return _le.text

	func _gui_input(e: InputEvent) -> void:
		if not enabled or _editing:
			return
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if (e as InputEventMouseButton).pressed:
				_dragging = true
				_drag_px = 0.0
				drag_started.emit()
			else:
				_dragging = false
				if absf(_drag_px) < 3.0:
					_enter_edit()          # clic sin arrastre = editar
				else:
					drag_ended.emit()
		elif e is InputEventMouseMotion and _dragging:
			var dx: float = (e as InputEventMouseMotion).relative.x
			_drag_px += dx
			if absf(dx) > 0.0:
				value = maxf(min_value, value + dx * step)
				_refresh_text()
				value_changed.emit(value)

	func _enter_edit() -> void:
		_editing = true
		_le.mouse_filter = Control.MOUSE_FILTER_STOP
		_le.grab_focus()
		_le.select_all()

	func _exit_edit(commit: bool) -> void:
		if not _editing:
			return
		_editing = false
		_le.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if commit and _le.text.strip_edges().is_valid_float():
			value = float(_le.text)
			submitted.emit(value)
		_refresh_text()

# ─────────────────────────────────────────────────────── dial reutilizable
class Dial extends Control:
	signal value_changed(v: float)
	signal drag_started()
	signal drag_ended()

	enum Kind { ROTATION, RADIUS }
	var kind: int = Kind.ROTATION
	var value: float = 0.0
	var max_value: float = 360.0
	var label: String = ""
	var _dragging := false
	var _accent := Color("0a84ff")
	var _muted := Color("6c6c70")
	var _card := Color("ffffff")
	var _border := Color("d1d1d6")

	func tint(accent: Color, muted: Color, card: Color, border: Color) -> void:
		_accent = accent; _muted = muted; _card = card; _border = border
		queue_redraw()

	func _init(k: int, lbl: String, mx: float) -> void:
		kind = k
		label = lbl
		max_value = mx
		custom_minimum_size = Vector2(52, 44) if k == Kind.RADIUS else Vector2(58, 58)
		mouse_default_cursor_shape = Control.CURSOR_VSIZE if k == Kind.RADIUS else Control.CURSOR_MOVE

	func set_value_silent(v: float) -> void:
		value = clampf(v, 0.0 if kind == Kind.RADIUS else -99999.0, max_value if kind == Kind.RADIUS else 99999.0)
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_dragging = (e as InputEventMouseButton).pressed
			if _dragging:
				drag_started.emit()
			else:
				drag_ended.emit()
		elif e is InputEventMouseMotion and _dragging:
			var mm := e as InputEventMouseMotion
			if kind == Kind.ROTATION:
				var c := size * 0.5
				var ang := rad_to_deg((mm.position - c).angle()) + 90.0
				value = fposmod(ang, 360.0)
			else:
				value = clampf(value - mm.relative.y * 0.5, 0.0, max_value)
			queue_redraw()
			value_changed.emit(value)

	func _draw() -> void:
		var r_out: float = minf(size.x, size.y) * 0.5 - 2.0
		var c := size * Vector2(0.5, 0.0) + Vector2(0, r_out + 1.0)
		if kind == Kind.RADIUS:
			c = Vector2(size.x * 0.5, r_out + 1.0)
		# disco
		draw_circle(c, r_out, _card)
		draw_arc(c, r_out, 0, TAU, 32, _border, 1.0, true)
		if kind == Kind.ROTATION:
			# manecilla
			var a := deg_to_rad(value - 90.0)
			draw_line(c, c + Vector2(cos(a), sin(a)) * (r_out - 5.0), _accent, 2.0, true)
			draw_circle(c, 2.0, _accent)
			_text_center("%d°" % int(round(value)), c + Vector2(0, r_out + 9.0), _muted, 9)
		else:
			# arco de progreso del radio
			var frac := clampf(value / maxf(max_value, 0.001), 0.0, 1.0)
			if frac > 0.001:
				draw_arc(c, r_out - 3.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 24, _accent, 2.5, true)
			_text_center(("%.1f" % value) if label == "" else label, c + Vector2(0, r_out + 8.0), _muted, 8)
			_text_center("%.0f" % value, c, _accent if frac > 0.001 else _muted, 9)

	func _text_center(t: String, at: Vector2, col: Color, sz: int) -> void:
		var f := get_theme_default_font()
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		draw_string(f, at - Vector2(w * 0.5, -sz * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

# ───────────────────────────────────────────────────────────── ciclo de vida
func _ready() -> void:
	custom_minimum_size = Vector2(236, 208)
	_pull_theme()
	_build()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_on_props):
		ic.changed.connect(_on_props)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.connect(_on_theme_changed)
	_refresh()

func _on_theme_changed(_mode: String) -> void:
	_pull_theme()
	for c in get_children():
		c.queue_free()
	_build()
	_refresh()

func _build() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _BG_PANEL
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = _BORDER
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var hdr := Label.new()
	hdr.text = "TRANSFORM"
	hdr.add_theme_color_override("font_color", _MUTED)
	hdr.add_theme_font_size_override("font_size", 11)
	root.add_child(hdr)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	root.add_child(grid)

	_corners["corner_tl"] = _make_dial(Dial.Kind.RADIUS, "TL", 400.0)
	grid.add_child(_corners["corner_tl"])
	grid.add_child(_make_field("pos_y", "Y"))
	_corners["corner_tr"] = _make_dial(Dial.Kind.RADIUS, "TR", 400.0)
	grid.add_child(_corners["corner_tr"])

	grid.add_child(_make_field("pos_x", "X"))
	_rot = _make_dial(Dial.Kind.ROTATION, "", 360.0)
	grid.add_child(_rot)
	grid.add_child(_make_field("width", "W"))

	_corners["corner_bl"] = _make_dial(Dial.Kind.RADIUS, "BL", 400.0)
	grid.add_child(_corners["corner_bl"])
	grid.add_child(_make_field("height", "H"))
	_corners["corner_br"] = _make_dial(Dial.Kind.RADIUS, "BR", 400.0)
	grid.add_child(_corners["corner_br"])

	var reset := Button.new()
	reset.text = "Reset"
	reset.add_theme_color_override("font_color", _MUTED)
	reset.add_theme_font_size_override("font_size", 10)
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = _BG_CARD
	rsb.set_corner_radius_all(6)
	rsb.set_content_margin_all(6)
	reset.add_theme_stylebox_override("normal", rsb)
	reset.pressed.connect(_on_reset)
	root.add_child(reset)

func _make_field(prop: String, lbl: String) -> Control:
	var f := Field.new(lbl, _TEXT, _MUTED, _BG_CARD, _BORDER)
	if prop == "width" or prop == "height":
		f.min_value = 1.0
	f.drag_started.connect(func(): _snap_prop(prop))
	f.value_changed.connect(func(v): _preview(prop, v))
	f.drag_ended.connect(func(): _commit_prop(prop))
	f.submitted.connect(func(v): _on_field_submitted(v, prop))
	_fields[prop] = f
	return f

func _make_dial(kind: int, lbl: String, mx: float) -> Dial:
	var d := Dial.new(kind, lbl, mx)
	d.tint(_ACCENT, _MUTED, _BG_CARD, _BORDER)
	d.drag_started.connect(func(): _snap_prop(_prop_for_dial(kind, lbl)))
	d.value_changed.connect(func(v): _preview(_prop_for_dial(kind, lbl), v))
	d.drag_ended.connect(func(): _commit_prop(_prop_for_dial(kind, lbl)))
	return d

var _drag_snap: Dictionary = {}   # figura -> valor previo (para el undo)

func _snap_prop(prop: String) -> void:
	_drag_snap.clear()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null or prop == "":
		return
	for shape in ic.selection():
		_drag_snap[shape] = ic._read(shape, prop)

# ─────────────────────────────────────────────────────────────── entrada UI
func _prop_for_dial(kind: int, lbl: String) -> String:
	if kind == Dial.Kind.ROTATION:
		return "rotation"
	var m := {"TL": "corner_tl", "TR": "corner_tr", "BR": "corner_br", "BL": "corner_bl"}
	return String(m.get(lbl, ""))

func _preview(prop: String, v: float) -> void:
	# Escritura en vivo mientras se arrastra (sin llenar el undo).
	if _sync_guard or not _has_selection or prop == "":
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		for shape in ic.selection():
			ic._write(shape, prop, v)
		ic._post_write()

func _commit_prop(prop: String) -> void:
	if _sync_guard or prop == "" or _drag_snap.is_empty():
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.commit_live(prop, _drag_snap)
	_drag_snap.clear()

func _on_field_submitted(v: float, prop: String) -> void:
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply(prop, v)

func _on_reset() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	ic.apply("rotation", 0.0)
	for p in ["corner_tl", "corner_tr", "corner_br", "corner_bl"]:
		ic.apply(p, 0.0)

# ─────────────────────────────────────────────────── sincronía con selección
func _on_props(props: Dictionary) -> void:
	_refresh(props)

func _refresh(props: Dictionary = {}) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	if props.is_empty():
		props = ic.current_props()
	_has_selection = not props.is_empty()
	_sync_guard = true
	for prop in _fields:
		var f: Field = _fields[prop]
		if props.has(prop) and not props[prop]["mixed"]:
			f.enabled = true
			f.set_value_silent(float(props[prop]["value"]))
		elif props.has(prop):
			f.set_disabled_text("—")
		else:
			f.set_disabled_text("")
	if props.has("rotation") and not props["rotation"]["mixed"]:
		_rot.set_value_silent(fposmod(float(props["rotation"]["value"]), 360.0))
	for prop in _corners:
		if props.has(prop) and not props[prop]["mixed"]:
			_corners[prop].set_value_silent(float(props[prop]["value"]))
	_sync_guard = false
