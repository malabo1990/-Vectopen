# ==========================================
# RUTA: res://script_gdscript/ui/transform_panel.gd
# Panel de transformación compacto y completo (estilo profesional).
# ==========================================
extends PanelContainer
class_name TransformPanel
## Rejilla 3×3 compacta:
##   [radio TL] [  Y  ] [radio TR]
##   [   X    ] [ ROT ] [   W    ]
##   [radio BL] [  H  ] [radio BR]
## + barra de herramientas rápidas (rotar ±90°, bloqueo de proporción 🔗, enlace de esquinas 🔗)
## + botón Reset.
##
## Características completas:
##  · Arrastre interactivo (scrubbing) en TODOS los campos: X, Y, W, H, Rotación y 4 Radios.
##  · Modificadores de teclado durante el arrastre:
##      - Shift: precisión fina (0.1× paso) / en rotación: snap a 15°.
##      - Ctrl / Cmd: incremento rápido (5.0× paso).
##  · Evaluación de expresiones matemáticas en los campos numéricos (+10, -5, *2, /2, etc.).
##  · Bloqueo de aspecto / proporción proporcional (🔗 Constrain Proportions) entre W y H.
##  · Sincronización de esquinas (🔗 Corner Radius Sync) para modificar las 4 esquinas a la vez.
##  · Entrada por teclado directa en los diales con doble clic o confirmación.
##  · Previsualización en vivo en el lienzo y un solo registro de Undo por arrastre.
##  · Sincronización en dos vías con InspectorCore y adaptación dinámica a ThemeManager.

# Paleta — se rellena desde ThemeManager (tokens de diseño). Fallback si no está disponible.
var _BG_PANEL := Color(1.0, 1.0, 1.0, 1.0)
var _BG_CARD := Color(1.0, 1.0, 1.0, 1.0)
var _BG_HOVER := Color("eceef2")
var _ACCENT := Color("0a84ff")
var _TEXT := Color("1c1c1e")
var _MUTED := Color("6c6c70")
var _BORDER := Color("d1d1d6")

func _pull_theme() -> void:
	_BG_PANEL = Color.WHITE
	_BG_CARD = Color.WHITE
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null:
		return
	var S = tm.Slot
	_BG_HOVER = tm.get_color(S.BUTTON_HOVER)
	_ACCENT   = tm.get_color(S.ACCENT)
	_TEXT     = tm.get_color(S.PANEL_TEXT)
	_MUTED    = tm.get_color(S.TEXT_SECONDARY)
	_BORDER   = tm.get_color(S.BORDER)

var _fields: Dictionary = {}          # prop -> Field
var _rot: Dial = null
var _corners: Dictionary = {}         # "corner_tl".. -> Dial
var _sync_guard := false
var _has_selection := false

# Bloqueo de proporción y enlace de esquinas
var _aspect_locked := false
var _aspect_ratio: float = 1.0        # width / height
var _btn_aspect: Button = null

var _corners_linked := false
var _btn_link_corners: Button = null

var _drag_snap: Dictionary = {}       # prop -> {figura -> valor_previo}

## Evaluador de expresiones matemáticas para campos numéricos (+10, -5, *2, /2, fórmulas).
static func eval_math(text: String, current: float) -> float:
	var t := text.strip_edges()
	if t == "":
		return current
	if t.begins_with("+") or t.begins_with("-") or t.begins_with("*") or t.begins_with("/"):
		t = str(current) + t
	elif t.is_valid_float():
		return float(t)
	var expr := Expression.new()
	var err := expr.parse(t)
	if err == OK:
		var res = expr.execute()
		if not expr.has_execute_failed() and (res is float or res is int):
			return float(res)
	return current

# ─────────────────────────────────── campo numérico con arrastre (scrub)
class Field extends PanelContainer:
	signal value_changed(v: float)
	signal drag_started()
	signal drag_ended()
	signal submitted(v: float)

	var value: float = 0.0
	var step: float = 0.5             # unidades por px de arrastre base
	var min_value: float = -999999.0
	var max_value: float = 999999.0
	var decimals: int = 2
	var enabled: bool = true

	var _le: LineEdit
	var _label_node: Label
	var _dragging := false
	var _drag_active := false
	var _drag_px := 0.0
	var _editing := false

	var _card_col: Color
	var _border_col: Color
	var _accent_col: Color
	var _text_col: Color
	var _muted_col: Color

	func _init(lbl: String, text_col: Color, muted: Color, card: Color, border: Color, accent: Color = Color("0a84ff")) -> void:
		_card_col = card; _border_col = border; _accent_col = accent
		_text_col = text_col; _muted_col = muted
		custom_minimum_size = Vector2(50, 36)
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
		_apply_panel_style(false)

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)

		_label_node = Label.new()
		_label_node.text = lbl
		_label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label_node.add_theme_color_override("font_color", muted)
		_label_node.add_theme_font_size_override("font_size", 8)
		box.add_child(_label_node)

		_le = LineEdit.new()
		_le.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_le.add_theme_color_override("font_color", text_col)
		_le.add_theme_font_size_override("font_size", 11)
		_le.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		_le.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_le.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_le.text_submitted.connect(func(_t): _exit_edit(true))
		_le.focus_exited.connect(func(): _exit_edit(true))
		box.add_child(_le)
		_refresh_text()

	func _apply_panel_style(highlight: bool) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = _card_col
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(1)
		sb.border_color = _accent_col if highlight else _border_col
		sb.set_content_margin_all(3)
		add_theme_stylebox_override("panel", sb)

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
			var mb := e as InputEventMouseButton
			if mb.pressed:
				_dragging = true
				_drag_px = 0.0
				_drag_active = false
				drag_started.emit()
				_apply_panel_style(true)
			else:
				_dragging = false
				_apply_panel_style(false)
				if absf(_drag_px) < 3.0 and not _drag_active:
					_enter_edit()
				_drag_active = false
				drag_ended.emit()
		elif e is InputEventMouseMotion and _dragging:
			var mm := e as InputEventMouseMotion
			var dx: float = mm.relative.x
			_drag_px += dx
			var current_step := step
			if Input.is_key_pressed(KEY_SHIFT):
				current_step = step * 0.1
			elif Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
				current_step = step * 5.0

			if absf(_drag_px) >= 3.0:
				_drag_active = true

			if absf(dx) > 0.0:
				value = clampf(value + dx * current_step, min_value, max_value)
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
		if commit:
			var eval_res := TransformPanel.eval_math(_le.text, value)
			value = clampf(eval_res, min_value, max_value)
			submitted.emit(value)
		_refresh_text()

# ─────────────────────────────────────────────────────── dial reutilizable
class Dial extends Control:
	signal value_changed(v: float)
	signal drag_started()
	signal drag_ended()
	signal submitted(v: float)

	enum Kind { ROTATION, RADIUS }
	var kind: int = Kind.ROTATION
	var value: float = 0.0
	var max_value: float = 360.0
	var label: String = ""
	var _dragging := false
	var _drag_px := 0.0
	var _editing := false
	var _le: LineEdit = null

	var _accent := Color("0a84ff")
	var _muted := Color("6c6c70")
	var _card := Color("ffffff")
	var _border := Color("d1d1d6")
	var _text_col := Color("1c1c1e")

	func tint(accent: Color, muted: Color, card: Color, border: Color, text_c: Color = Color("1c1c1e")) -> void:
		_accent = accent; _muted = muted; _card = card; _border = border; _text_col = text_c
		queue_redraw()

	func _init(k: int, lbl: String, mx: float) -> void:
		kind = k
		label = lbl
		max_value = mx
		custom_minimum_size = Vector2(46, 38) if k == Kind.RADIUS else Vector2(50, 50)
		mouse_default_cursor_shape = Control.CURSOR_VSIZE if k == Kind.RADIUS else Control.CURSOR_MOVE

	func set_value_silent(v: float) -> void:
		value = clampf(v, 0.0 if kind == Kind.RADIUS else -99999.0, max_value if kind == Kind.RADIUS else 99999.0)
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if _editing:
			return
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := e as InputEventMouseButton
			if mb.pressed:
				if mb.double_click:
					_enter_edit()
					return
				_dragging = true
				_drag_px = 0.0
				drag_started.emit()
			else:
				_dragging = false
				drag_ended.emit()
		elif e is InputEventMouseMotion and _dragging:
			var mm := e as InputEventMouseMotion
			if kind == Kind.ROTATION:
				var c := size * 0.5
				var ang := rad_to_deg((mm.position - c).angle()) + 90.0
				ang = fposmod(ang, 360.0)
				if Input.is_key_pressed(KEY_SHIFT):
					ang = roundf(ang / 15.0) * 15.0
				value = ang
			else:
				var dy: float = mm.relative.y
				_drag_px += absf(dy)
				var step := 0.1 if Input.is_key_pressed(KEY_SHIFT) else (2.0 if (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)) else 0.5)
				value = clampf(value - dy * step, 0.0, max_value)
			queue_redraw()
			value_changed.emit(value)

	func _enter_edit() -> void:
		if _editing:
			return
		_editing = true
		_le = LineEdit.new()
		_le.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_le.text = "%d" % int(roundf(value))
		_le.custom_minimum_size = Vector2(40, 22)
		_le.size = _le.custom_minimum_size
		_le.position = (size - _le.size) * 0.5
		_le.add_theme_color_override("font_color", _text_col)
		_le.add_theme_font_size_override("font_size", 10)
		var sb := StyleBoxFlat.new()
		sb.bg_color = _card
		sb.set_border_width_all(1)
		sb.border_color = _accent
		sb.set_corner_radius_all(4)
		_le.add_theme_stylebox_override("normal", sb)
		_le.text_submitted.connect(func(_t): _exit_edit(true))
		_le.focus_exited.connect(func(): _exit_edit(true))
		add_child(_le)
		_le.grab_focus()
		_le.select_all()

	func _exit_edit(commit: bool) -> void:
		if not _editing:
			return
		_editing = false
		if is_instance_valid(_le):
			if commit:
				var eval_v := TransformPanel.eval_math(_le.text, value)
				if kind == Kind.ROTATION:
					value = fposmod(eval_v, 360.0)
				else:
					value = clampf(eval_v, 0.0, max_value)
				submitted.emit(value)
				value_changed.emit(value)
			_le.queue_free()
			_le = null
		queue_redraw()

	func _draw() -> void:
		var r_out: float = minf(size.x, size.y) * 0.5 - 2.0
		var c := size * Vector2(0.5, 0.0) + Vector2(0, r_out + 1.0)
		if kind == Kind.RADIUS:
			c = Vector2(size.x * 0.5, r_out + 1.0)
		draw_circle(c, r_out, _card)
		draw_arc(c, r_out, 0, TAU, 32, _border, 1.0, true)
		if kind == Kind.ROTATION:
			var a := deg_to_rad(value - 90.0)
			draw_line(c, c + Vector2(cos(a), sin(a)) * (r_out - 5.0), _accent, 2.0, true)
			draw_circle(c, 2.0, _accent)
			_text_center("%d°" % int(round(value)), c + Vector2(0, r_out + 9.0), _muted, 9)
		else:
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
	custom_minimum_size = Vector2(192, 220)
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
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(0)
	sb.border_color = Color.TRANSPARENT
	sb.set_content_margin_all(4)
	add_theme_stylebox_override("panel", sb)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	# Cabecera con título y herramientas rápidas
	var header_box := HBoxContainer.new()
	header_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	header_box.add_theme_constant_override("separation", 3)
	root.add_child(header_box)

	var hdr := Label.new()
	hdr.text = "TRANSFORM"
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_theme_color_override("font_color", _MUTED)
	hdr.add_theme_font_size_override("font_size", 10)
	header_box.add_child(hdr)

	# Botones rápidos: Rotar -90°, Rotar +90°, Proporción 🔗, Esquinas 🔗
	var btn_rot_ccw := _make_icon_button("↺", "Rotar -90° antihorario")
	btn_rot_ccw.pressed.connect(rotate_ccw)
	header_box.add_child(btn_rot_ccw)

	var btn_rot_cw := _make_icon_button("↻", "Rotar +90° horario")
	btn_rot_cw.pressed.connect(rotate_cw)
	header_box.add_child(btn_rot_cw)

	_btn_aspect = _make_icon_button("🔗", "Bloquear proporciones (W / H)")
	_btn_aspect.pressed.connect(_toggle_aspect_lock)
	_update_toggle_button(_btn_aspect, _aspect_locked)
	header_box.add_child(_btn_aspect)

	_btn_link_corners = _make_icon_button("⊞", "Sincronizar radios de las 4 esquinas")
	_btn_link_corners.pressed.connect(_toggle_link_corners)
	_update_toggle_button(_btn_link_corners, _corners_linked)
	header_box.add_child(_btn_link_corners)

	# Rejilla 3×3
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
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

	# Botón de Restablecer (Reset)
	var reset := Button.new()
	reset.text = "Restablecer transformación"
	reset.add_theme_color_override("font_color", _MUTED)
	reset.add_theme_font_size_override("font_size", 10)
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color.WHITE
	rsb.set_corner_radius_all(6)
	rsb.set_border_width_all(1)
	rsb.border_color = Color(0.86, 0.87, 0.90, 1.0)
	rsb.set_content_margin_all(5)
	reset.add_theme_stylebox_override("normal", rsb)
	var rsb_h := rsb.duplicate() as StyleBoxFlat
	rsb_h.bg_color = Color(0.94, 0.94, 0.96, 1.0)
	reset.add_theme_stylebox_override("hover", rsb_h)
	reset.pressed.connect(_on_reset)
	root.add_child(reset)

func _make_icon_button(txt: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(22, 22)
	b.add_theme_font_size_override("font_size", 10)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.86, 0.87, 0.90, 1.0)
	sb.set_content_margin_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(0.94, 0.94, 0.96, 1.0)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_color_override("font_color", _MUTED)
	return b

func _update_toggle_button(b: Button, active: bool) -> void:
	if b == null:
		return
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(2)
	sb.set_border_width_all(1)
	if active:
		sb.bg_color = Color(0.88, 0.90, 0.94, 1.0)
		sb.border_color = Color(0.65, 0.68, 0.75, 1.0)
		b.add_theme_color_override("font_color", Color(0.1, 0.1, 0.12, 1.0))
	else:
		sb.bg_color = Color.WHITE
		sb.border_color = Color(0.86, 0.87, 0.90, 1.0)
		b.add_theme_color_override("font_color", _MUTED)
	b.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate() as StyleBoxFlat
	if not active:
		sb_h.bg_color = Color(0.94, 0.94, 0.96, 1.0)
	b.add_theme_stylebox_override("hover", sb_h)

func _toggle_aspect_lock() -> void:
	_aspect_locked = not _aspect_locked
	if _aspect_locked:
		var w: float = float(_fields["width"].value)
		var h: float = maxf(1.0, float(_fields["height"].value))
		_aspect_ratio = w / h
	_update_toggle_button(_btn_aspect, _aspect_locked)

func _toggle_link_corners() -> void:
	_corners_linked = not _corners_linked
	_update_toggle_button(_btn_link_corners, _corners_linked)

func _make_field(prop: String, lbl: String) -> Control:
	var f := Field.new(lbl, _TEXT, _MUTED, _BG_CARD, _BORDER, _ACCENT)
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
	d.tint(_ACCENT, _MUTED, _BG_CARD, _BORDER, _TEXT)
	var prop := _prop_for_dial(kind, lbl)
	d.drag_started.connect(func(): _snap_prop(prop))
	d.value_changed.connect(func(v): _preview(prop, v))
	d.drag_ended.connect(func(): _commit_prop(prop))
	d.submitted.connect(func(v): _on_dial_submitted(v, prop))
	return d

func _prop_for_dial(kind: int, lbl: String) -> String:
	if kind == Dial.Kind.ROTATION:
		return "rotation"
	var m := {"TL": "corner_tl", "TR": "corner_tr", "BR": "corner_br", "BL": "corner_bl"}
	return String(m.get(lbl, ""))

# ────────────────────────────────────────────────────────── captura y preview
func _snap_prop(prop: String) -> void:
	_drag_snap.clear()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null or prop == "":
		return
	var props_to_snap := [prop]
	if _aspect_locked and (prop == "width" or prop == "height"):
		props_to_snap = ["width", "height"]
	elif _corners_linked and prop.begins_with("corner_"):
		props_to_snap = ["corner_tl", "corner_tr", "corner_br", "corner_bl"]

	for p in props_to_snap:
		_drag_snap[p] = {}
		for shape in ic.selection():
			_drag_snap[p][shape] = ic._read(shape, p)

func _preview(prop: String, v: float) -> void:
	if _sync_guard or not _has_selection or prop == "":
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	var shapes: Array = ic.selection()
	if shapes.is_empty():
		return

	if _aspect_locked and (prop == "width" or prop == "height"):
		var w_val := v
		var h_val := v
		if prop == "width":
			w_val = maxf(1.0, v)
			h_val = maxf(1.0, w_val / maxf(_aspect_ratio, 0.0001))
			_fields["height"].set_value_silent(h_val)
		else:
			h_val = maxf(1.0, v)
			w_val = maxf(1.0, h_val * _aspect_ratio)
			_fields["width"].set_value_silent(w_val)

		for s in shapes:
			ic._write(s, "width", w_val)
			ic._write(s, "height", h_val)
	elif _corners_linked and prop.begins_with("corner_"):
		for p in ["corner_tl", "corner_tr", "corner_br", "corner_bl"]:
			for s in shapes:
				ic._write(s, p, v)
			if _corners.has(p):
				_corners[p].set_value_silent(v)
	else:
		var p_snaps: Dictionary = _drag_snap.get(prop, {})
		var first_val: float = float(p_snaps.get(shapes[0], v)) if not p_snaps.is_empty() else v
		var delta := v - first_val
		for s in shapes:
			if p_snaps.has(s) and (p_snaps[s] is float or p_snaps[s] is int):
				var target_v := float(p_snaps[s]) + delta
				if prop == "width" or prop == "height":
					target_v = maxf(1.0, target_v)
				ic._write(s, prop, target_v)
			else:
				ic._write(s, prop, v)

	ic._post_write()

func _commit_prop(prop: String) -> void:
	if _sync_guard or prop == "" or _drag_snap.is_empty():
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		_drag_snap.clear()
		return

	if _aspect_locked and (prop == "width" or prop == "height"):
		var multi := {}
		if _drag_snap.has("width"): multi["width"] = _drag_snap["width"]
		if _drag_snap.has("height"): multi["height"] = _drag_snap["height"]
		if ic.has_method("commit_live_multi"):
			ic.commit_live_multi(multi, "Inspector · size")
		else:
			for p in multi: ic.commit_live(p, multi[p])
	elif _corners_linked and prop.begins_with("corner_"):
		var multi := {}
		for p in ["corner_tl", "corner_tr", "corner_br", "corner_bl"]:
			if _drag_snap.has(p): multi[p] = _drag_snap[p]
		if ic.has_method("commit_live_multi"):
			ic.commit_live_multi(multi, "Inspector · corners")
		else:
			for p in multi: ic.commit_live(p, multi[p])
	else:
		var snaps: Dictionary = _drag_snap.get(prop, {})
		if not snaps.is_empty():
			ic.commit_live(prop, snaps)
	_drag_snap.clear()

func _on_field_submitted(v: float, prop: String) -> void:
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return

	if _aspect_locked and (prop == "width" or prop == "height"):
		if prop == "width":
			var new_w := maxf(1.0, v)
			var new_h := maxf(1.0, new_w / maxf(_aspect_ratio, 0.0001))
			if ic.has_method("apply_multi"):
				ic.apply_multi({"width": new_w, "height": new_h}, "Inspector · size")
			else:
				ic.apply("width", new_w)
				ic.apply("height", new_h)
		else:
			var new_h := maxf(1.0, v)
			var new_w := maxf(1.0, new_h * _aspect_ratio)
			if ic.has_method("apply_multi"):
				ic.apply_multi({"width": new_w, "height": new_h}, "Inspector · size")
			else:
				ic.apply("height", new_h)
				ic.apply("width", new_w)
	else:
		ic.apply(prop, v)

func _on_dial_submitted(v: float, prop: String) -> void:
	if _sync_guard or prop == "":
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	if _corners_linked and prop.begins_with("corner_"):
		if ic.has_method("apply_multi"):
			var multi := {}
			for p in ["corner_tl", "corner_tr", "corner_br", "corner_bl"]:
				multi[p] = v
			ic.apply_multi(multi, "Inspector · corners")
		else:
			for p in ["corner_tl", "corner_tr", "corner_br", "corner_bl"]:
				ic.apply(p, v)
	else:
		ic.apply(prop, v)

# ────────────────────────────────────────────────────────── acciones rápidas
func rotate_cw() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	var props: Dictionary = ic.current_props()
	var cur: float = float(props.get("rotation", {}).get("value", 0.0))
	ic.apply("rotation", fposmod(cur + 90.0, 360.0))

func rotate_ccw() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	var props: Dictionary = ic.current_props()
	var cur: float = float(props.get("rotation", {}).get("value", 0.0))
	ic.apply("rotation", fposmod(cur - 90.0, 360.0))

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

	if props.has("width") and props.has("height") and not _aspect_locked:
		var w: float = float(props["width"].get("value", 100.0))
		var h: float = maxf(1.0, float(props["height"].get("value", 100.0)))
		_aspect_ratio = w / h

	_sync_guard = false
