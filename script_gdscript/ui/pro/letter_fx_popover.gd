# =============================================================================
# VECTOPEN — PANEL "LETRAS AVANZADAS"
# RUTA: res://script_gdscript/ui/pro/letter_fx_popover.gd
# Se abre con el botón "Letras avanzadas" del panel Tipografía. Efectos por
# letra paramétricos (ver script_gdscript/text/letter_fx.gd):
#   · Proporciones: preajustes (Aaa, aaA, aAa, AaA) + curva de 4 puntos
#     editable arrastrando sus puntos o escribiendo los valores;
#   · Onda / arco: desplazamiento vertical por letra;
#   · Interletra progresiva: el espaciado va de "inicio" a "fin".
# Todo pasa por InspectorCore: en vivo al arrastrar y UN paso de deshacer.
# =============================================================================
extends PanelContainer

const LetterFx = preload("res://script_gdscript/text/letter_fx.gd")
const NumField = preload("res://script_gdscript/ui/pro/pro_num_field.gd")
const _ICONS := "res://icon/UI/"
const W := 268

static var _shared: PanelContainer = null

var _anchor: Control = null
var _syncing := false
var _live_before: Dictionary = {}     # prop -> {figura: valor previo}
var _title: Label = null
var _labels: Array[Label] = []
var _seps: Array[ColorRect] = []
var _toggles: Array[Button] = []
var _actions: Array[Button] = []

var _prop_btns: Dictionary = {}       # "" | "Aaa" | … -> Button
var _curve: Control = null
var _p_fields: Dictionary = {}        # start|mid|mid2|end -> ProNumField
var _wave_btns: Dictionary = {}       # "" | "wave" | "arc" -> Button
var _w_amount: Control = null
var _w_cycles: Control = null
var _w_phase: Control = null
var _r_start: Control = null
var _r_end: Control = null

# Estado editado (refleja la selección)
var _prop: Dictionary = {}
var _wave: Dictionary = {}
var _ramp: Dictionary = {}

## Abre / cierra el panel junto a `anchor` (el panel Tipografía).
static func toggle_from(anchor: Control) -> PanelContainer:
	if not is_instance_valid(_shared):
		var layer := CanvasLayer.new()
		layer.name = "LetterFxLayer"
		layer.layer = 118
		anchor.get_tree().root.add_child(layer)
		_shared = load("res://script_gdscript/ui/pro/letter_fx_popover.gd").new()
		layer.add_child(_shared)
	if _shared.visible and _shared._anchor == anchor:
		_shared.visible = false
	else:
		_shared.open_at(anchor)
	return _shared

static func shared() -> PanelContainer:
	return _shared if is_instance_valid(_shared) else null

func _init() -> void:
	name = "LetterFxPopover"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(W, 0)

func _ready() -> void:
	_build()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed"):
		ic.changed.connect(func(_p) -> void: if visible: _sync())
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _apply_theme())
	_apply_theme()

func open_at(anchor: Control) -> void:
	_anchor = anchor
	_sync()
	visible = true
	reset_size()
	await get_tree().process_frame
	_place()

func _place() -> void:
	if not is_instance_valid(_anchor):
		return
	var vp := get_viewport_rect().size
	var r := _anchor.get_global_rect()
	var s := get_combined_minimum_size()
	var x := r.position.x - s.x - 10.0
	if x < 8.0:
		x = r.end.x + 10.0
	var y := clampf(r.position.y, 8.0, maxf(8.0, vp.y - s.y - 8.0))
	global_position = Vector2(clampf(x, 8.0, maxf(8.0, vp.x - s.x - 8.0)), y)

# ── construcción ────────────────────────────────────────────────────────────
func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var ico := TextureRect.new()
	ico.name = "Icon"
	ico.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ico.custom_minimum_size = Vector2(18, 18)
	header.add_child(ico)
	_title = Label.new()
	_title.text = tr("Letras avanzadas")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE + 2)
	header.add_child(_title)
	var close := _icon_btn("txt_none", "Cerrar", false)
	close.text = "✕"
	close.set_meta("icon_path", "")
	close.pressed.connect(func() -> void: visible = false)
	header.add_child(close)

	# Proporciones
	_section(box, "Proporciones")
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 3)
	box.add_child(prow)
	for key in ["", "Aaa", "aaA", "aAa", "AaA"]:
		var b := _icon_btn("txt_none" if key == "" else "", "Sin proporciones" if key == "" else tr("Preajuste ") + key, true)
		if key != "":
			b.text = key
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_prop_preset.bind(key))
		prow.add_child(b)
		_prop_btns[key] = b
	_curve = Control.new()
	_curve.name = "Curve"
	_curve.custom_minimum_size = Vector2(0, 74)
	_curve.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	_curve.tooltip_text = tr("Arrastra los puntos: tamaño de las letras al inicio, en medio y al final")
	_curve.draw.connect(_draw_curve)
	_curve.gui_input.connect(_on_curve_input)
	box.add_child(_curve)
	var pf := HBoxContainer.new()
	pf.add_theme_constant_override("separation", 3)
	box.add_child(pf)
	var names := {"start": "1", "mid": "2", "mid2": "3", "end": "4"}
	var tips := {"start": "Escala de la primera letra", "mid": "Escala a 1/3 del texto", "mid2": "Escala a 2/3 del texto", "end": "Escala de la última letra"}
	for k in ["start", "mid", "mid2", "end"]:
		var f := _field(pf, "", names[k], tips[k], 0.2, 3.0, 0.05, "")
		f.value_changed.connect(_on_prop_field.bind(k))
		f.scrub_changed.connect(_on_prop_field_live.bind(k))
		_p_fields[k] = f

	# Onda / arco
	_section(box, "Onda / arco")
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 3)
	box.add_child(wrow)
	for spec in [["", "txt_none", "Sin onda"], ["wave", "txt_wave", "Onda"], ["arc", "txt_arc", "Arco"]]:
		var b := _icon_btn(String(spec[1]), String(spec[2]), true)
		b.text = tr(String(spec[2]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_wave_mode.bind(String(spec[0])))
		wrow.add_child(b)
		_wave_btns[spec[0]] = b
	var wf := HBoxContainer.new()
	wf.add_theme_constant_override("separation", 3)
	box.add_child(wf)
	_w_amount = _field(wf, "", "↕", "Altura de la onda / arco (px, negativo = hacia abajo)", -400.0, 400.0, 1.0, "px")
	_w_cycles = _field(wf, "", "∿", "Número de ondas a lo largo del texto", 0.1, 12.0, 0.1, "")
	_w_phase = _field(wf, "", "φ", "Desfase de la onda (grados)", -360.0, 360.0, 5.0, "°")
	for pair in [[_w_amount, "amount"], [_w_cycles, "cycles"], [_w_phase, "phase"]]:
		pair[0].value_changed.connect(_on_wave_field.bind(String(pair[1])))
		pair[0].scrub_changed.connect(_on_wave_field_live.bind(String(pair[1])))

	# Interletra progresiva
	_section(box, "Interletra progresiva")
	var rf := HBoxContainer.new()
	rf.add_theme_constant_override("separation", 3)
	box.add_child(rf)
	_r_start = _field(rf, "txt_tracking", "", "Interletra al inicio (px)", -50.0, 300.0, 0.5, "px")
	var arrow := Label.new()
	arrow.text = "→"
	arrow.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE)
	_labels.append(arrow)
	rf.add_child(arrow)
	_r_end = _field(rf, "txt_tracking", "", "Interletra al final (px)", -50.0, 300.0, 0.5, "px")
	for pair in [[_r_start, "start"], [_r_end, "end"]]:
		pair[0].value_changed.connect(_on_ramp_field.bind(String(pair[1])))
		pair[0].scrub_changed.connect(_on_ramp_field_live.bind(String(pair[1])))

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	_seps.append(sep)
	box.add_child(sep)
	var reset := Button.new()
	reset.text = tr("Restablecer todo")
	reset.focus_mode = Control.FOCUS_NONE
	reset.custom_minimum_size = Vector2(0, 26)
	reset.set_meta("icon_path", _ICONS + "txt_reset.svg")
	reset.pressed.connect(_on_reset_all)
	_actions.append(reset)
	box.add_child(reset)

func _section(parent: Control, title: String) -> void:
	var l := Label.new()
	l.text = tr(title)
	l.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE)
	_labels.append(l)
	parent.add_child(l)

func _icon_btn(icon: String, tip: String, toggle: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tr(tip)
	b.custom_minimum_size = Vector2(26, 24)
	b.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE)
	b.set_meta("icon_path", (_ICONS + icon + ".svg") if icon != "" else "")
	_toggles.append(b)
	return b

func _field(parent: Control, icon: String, glyph: String, tip: String, lo: float, hi: float, st: float, suf: String) -> Control:
	var f: Control = NumField.new((_ICONS + icon + ".svg") if icon != "" else "", glyph, tr(tip))
	f.min_value = lo
	f.max_value = hi
	f.step = st
	f.suffix = suf
	f.custom_minimum_size = Vector2(40, 24)
	parent.add_child(f)
	return f

# ── tema ────────────────────────────────────────────────────────────────────
func _apply_theme() -> void:
	var sb := ProUIStyle.flat(ProUIStyle.col("PANEL_SURFACE"), 8, ProUIStyle.col("BORDER_STRONG"), 10, 10)
	sb.shadow_color = Color(0, 0, 0, 0.3 if ProUIStyle.is_dark() else 0.14)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", sb)
	if is_instance_valid(_title):
		_title.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
		var ico := _title.get_parent().get_node_or_null("Icon") as TextureRect
		if ico:
			ico.texture = ProUIStyle.icon(_ICONS + "txt_fx.svg", ProUIStyle.col("ACCENT"), 16)
	for l in _labels:
		l.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
	for s in _seps:
		s.color = ProUIStyle.col("BORDER")
	for b in _toggles:
		_style_toggle(b, b.button_pressed)
	for b in _actions:
		b.add_theme_stylebox_override("normal", ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 4, ProUIStyle.col("INPUT_BORDER"), 6, 0))
		b.add_theme_stylebox_override("hover", ProUIStyle.flat(ProUIStyle.col("BUTTON_HOVER"), 4, ProUIStyle.col("BORDER_STRONG"), 6, 0))
		b.add_theme_stylebox_override("pressed", ProUIStyle.flat(ProUIStyle.col("BUTTON_PRESSED"), 4, ProUIStyle.col("ACCENT"), 6, 0))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
		b.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE)
		b.icon = ProUIStyle.icon(String(b.get_meta("icon_path")), ProUIStyle.col("TEXT_SECONDARY"), 16)
	for f in _all_fields():
		f.apply_theme()
	if is_instance_valid(_curve):
		_curve.queue_redraw()

func _style_toggle(b: Button, on: bool) -> void:
	var accent := ProUIStyle.col("ACCENT")
	var n := ProUIStyle.flat(Color(accent, 0.28) if on else ProUIStyle.col("INPUT_BG"), 4,
		Color(accent, 0.7) if on else ProUIStyle.col("INPUT_BORDER"), 4, 0)
	var h := ProUIStyle.flat(Color(accent, 0.36) if on else ProUIStyle.col("BUTTON_HOVER"), 4,
		Color(accent, 0.7) if on else ProUIStyle.col("BORDER_STRONG"), 4, 0)
	for k in ["normal", "pressed"]:
		b.add_theme_stylebox_override(k, n)
	for k in ["hover", "hover_pressed"]:
		b.add_theme_stylebox_override(k, h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fg := ProUIStyle.col("PANEL_TEXT")
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, fg)
	var path := String(b.get_meta("icon_path", ""))
	if path != "":
		b.icon = ProUIStyle.icon(path, fg if on else ProUIStyle.col("ICON_PRIMARY"), 16)

func _all_fields() -> Array:
	var out: Array = _p_fields.values()
	for f in [_w_amount, _w_cycles, _w_phase, _r_start, _r_end]:
		if is_instance_valid(f):
			out.append(f)
	return out

# ── curva de proporciones ───────────────────────────────────────────────────
const _CURVE_MAX := 3.0
const _KEYS := ["start", "mid", "mid2", "end"]

func _curve_pt(i: int, v: float) -> Vector2:
	var r := Rect2(Vector2(10, 8), _curve.size - Vector2(20, 16))
	return Vector2(r.position.x + r.size.x * float(i) / 3.0, r.end.y - r.size.y * clampf(v, 0.0, _CURVE_MAX) / _CURVE_MAX)

func _draw_curve() -> void:
	var c := _curve
	c.draw_style_box(ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 4, ProUIStyle.col("INPUT_BORDER")), Rect2(Vector2.ZERO, c.size))
	var y1 := _curve_pt(0, 1.0).y
	c.draw_dashed_line(Vector2(6, y1), Vector2(c.size.x - 6, y1), ProUIStyle.col("BORDER_STRONG"), 1.0, 3.0)
	var p := _prop if not _prop.is_empty() else {"start": 1.0, "mid": 1.0, "mid2": 1.0, "end": 1.0}
	var pts := PackedVector2Array()
	for i in 4:
		pts.append(_curve_pt(i, float(p.get(_KEYS[i], 1.0))))
	var acc := ProUIStyle.col("ACCENT") if not _prop.is_empty() else ProUIStyle.col("TEXT_SECONDARY")
	# Letras de muestra con la escala de la curva
	var font := c.get_theme_default_font()
	for i in 7:
		var t := float(i) / 6.0
		var s := LetterFx.scale_at(p, t)
		var fs := int(clampf(10.0 * s, 5.0, 30.0))
		var x := 10.0 + (c.size.x - 30.0) * t
		c.draw_string(font, Vector2(x, c.size.y - 6), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ProUIStyle.col("TEXT_SECONDARY"), 0.45))
	c.draw_polyline(pts, acc, 2.0, true)
	for i in 4:
		c.draw_circle(pts[i], 5.0, ProUIStyle.col("PANEL_SURFACE"))
		c.draw_arc(pts[i], 5.0, 0.0, TAU, 20, acc, 1.5, true)

var _drag_pt := -1

func _on_curve_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var p := _prop if not _prop.is_empty() else {"mode": "custom", "start": 1.0, "mid": 1.0, "mid2": 1.0, "end": 1.0}
			var best := -1
			var bd := 1e9
			for i in 4:
				var d := absf(_curve_pt(i, float(p.get(_KEYS[i], 1.0))).x - ev.position.x)
				if d < bd:
					bd = d
					best = i
			_drag_pt = best
			_prop = p.duplicate()
			_curve_set(ev.position.y, true)
		elif _drag_pt >= 0:
			_drag_pt = -1
			_commit("letter_proportions", _prop)
		_curve.accept_event()
	elif ev is InputEventMouseMotion and _drag_pt >= 0:
		_curve_set(ev.position.y, true)
		_curve.accept_event()

func _curve_set(y: float, live: bool) -> void:
	var r := Rect2(Vector2(10, 8), _curve.size - Vector2(20, 16))
	var v := snappedf(clampf((r.end.y - y) / r.size.y * _CURVE_MAX, 0.2, _CURVE_MAX), 0.05)
	_prop[_KEYS[_drag_pt]] = v
	_prop["mode"] = "custom"
	_refresh_prop_ui()
	if live:
		_live("letter_proportions", _prop)

# ── acciones ────────────────────────────────────────────────────────────────
func _on_prop_preset(key: String) -> void:
	if key == "":
		_prop = {}
	else:
		_prop = (LetterFx.PRESETS[key] as Dictionary).duplicate()
		_prop["mode"] = key
	_refresh_prop_ui()
	_apply("letter_proportions", _prop)

func _on_prop_field(v: float, k: String) -> void:
	if _syncing:
		return
	if _commit_if_live("letter_proportions"):
		return
	_ensure_prop()
	_prop[k] = v
	_prop["mode"] = "custom"
	_refresh_prop_ui()
	_apply("letter_proportions", _prop)

func _on_prop_field_live(v: float, k: String) -> void:
	_ensure_prop()
	_prop[k] = v
	_prop["mode"] = "custom"
	_refresh_prop_ui()
	_live("letter_proportions", _prop)

func _ensure_prop() -> void:
	if _prop.is_empty():
		_prop = {"mode": "custom", "start": 1.0, "mid": 1.0, "mid2": 1.0, "end": 1.0}

func _on_wave_mode(mode: String) -> void:
	if mode == "":
		_wave = {}
	else:
		var base := _wave.duplicate() if not _wave.is_empty() else {"amount": 20.0, "cycles": 1.0, "phase": 0.0}
		base["mode"] = mode
		if absf(float(base.get("amount", 0.0))) < 0.001:
			base["amount"] = 20.0
		_wave = base
	_refresh_wave_ui()
	_apply("letter_wave", _wave)

func _on_wave_field(v: float, k: String) -> void:
	if _syncing:
		return
	if _commit_if_live("letter_wave"):
		return
	_ensure_wave()
	_wave[k] = v
	_refresh_wave_ui()
	_apply("letter_wave", _wave)

func _on_wave_field_live(v: float, k: String) -> void:
	_ensure_wave()
	_wave[k] = v
	_refresh_wave_ui()
	_live("letter_wave", _wave)

func _ensure_wave() -> void:
	if _wave.is_empty():
		_wave = {"mode": "wave", "amount": 20.0, "cycles": 1.0, "phase": 0.0}

func _on_ramp_field(v: float, k: String) -> void:
	if _syncing:
		return
	if _commit_if_live("letter_tracking_ramp"):
		return
	_ramp[k] = v
	_apply("letter_tracking_ramp", _ramp)

func _on_ramp_field_live(v: float, k: String) -> void:
	_ramp[k] = v
	_live("letter_tracking_ramp", _ramp)

func _on_reset_all() -> void:
	_prop = {}
	_wave = {}
	_ramp = {}
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply_multi({"letter_proportions": {}, "letter_wave": {}, "letter_tracking_ramp": {}}, "Texto · quitar efectos de letras")
	_sync()

# ── InspectorCore: aplicar con undo / en vivo ───────────────────────────────
func _apply(prop: String, value: Dictionary) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply(prop, value.duplicate())

func _live(prop: String, value: Dictionary) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	if not _live_before.has(prop):
		var before := {}
		for s in ic.selection():
			var b = ic._read(s, prop)
			if b != null:
				before[s] = b
		_live_before[prop] = before
	for s in (_live_before[prop] as Dictionary):
		if is_instance_valid(s):
			ic._write(s, prop, value.duplicate())
	ic._post_write()

## Fin de arrastre ya escrito en vivo → UN paso de deshacer.
func _commit_if_live(prop: String) -> bool:
	if not _live_before.has(prop):
		return false
	var before: Dictionary = _live_before[prop]
	_live_before.erase(prop)
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.commit_live(prop, before)
	return true

func _commit(prop: String, value: Dictionary) -> void:
	if not _commit_if_live(prop):
		_apply(prop, value)

# ── sincronización con la selección ─────────────────────────────────────────
func _sync() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	var props: Dictionary = ic.current_props()
	_prop = _prop_of(props, "letter_proportions")
	_wave = _prop_of(props, "letter_wave")
	_ramp = _prop_of(props, "letter_tracking_ramp")
	_refresh_prop_ui()
	_refresh_wave_ui()
	_syncing = true
	var has_text := props.has("letter_wave")
	for pair in [[_r_start, "start"], [_r_end, "end"]]:
		if has_text:
			pair[0].set_value_no_signal(float(_ramp.get(pair[1], 0.0)))
		else:
			pair[0].set_mixed(true, "—")
	_syncing = false

func _prop_of(props: Dictionary, key: String) -> Dictionary:
	if not props.has(key) or bool(props[key].get("mixed", false)):
		return {}
	var v = props[key].get("value")
	return (v as Dictionary).duplicate() if v is Dictionary else {}

func _refresh_prop_ui() -> void:
	_syncing = true
	var mode := String(_prop.get("mode", ""))
	for k in _prop_btns:
		var on: bool = (k == mode) or (k == "" and _prop.is_empty())
		_prop_btns[k].set_pressed_no_signal(on)
		_style_toggle(_prop_btns[k], on)
	for k in _p_fields:
		_p_fields[k].set_value_no_signal(float(_prop.get(k, 1.0)))
	_syncing = false
	if is_instance_valid(_curve):
		_curve.queue_redraw()

func _refresh_wave_ui() -> void:
	_syncing = true
	var mode := String(_wave.get("mode", ""))
	for k in _wave_btns:
		var on: bool = k == mode
		_wave_btns[k].set_pressed_no_signal(on)
		_style_toggle(_wave_btns[k], on)
	_w_amount.set_value_no_signal(float(_wave.get("amount", 0.0)))
	_w_cycles.set_value_no_signal(float(_wave.get("cycles", 1.0)))
	_w_phase.set_value_no_signal(float(_wave.get("phase", 0.0)))
	# Ciclos y fase solo tienen sentido en la onda
	_w_cycles.modulate.a = 1.0 if mode != "arc" else 0.4
	_w_phase.modulate.a = 1.0 if mode != "arc" else 0.4
	_syncing = false

## Clic fuera (salvo sobre el botón que lo abre) o Esc → cerrar.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mp: Vector2 = event.global_position
		if get_global_rect().has_point(mp):
			return
		var btn := _anchor.get_meta("letter_fx_button", null) as Control if is_instance_valid(_anchor) else null
		if btn and btn.get_global_rect().has_point(mp):
			return
		# El selector de color u otros popovers propios no cierran este panel
		var pop := get_tree().root.find_child("TextColorPopover", true, false) as Control
		if pop and pop.visible and pop.get_global_rect().has_point(mp):
			return
		visible = false
