# =============================================================================
# VECTOPEN — PANEL DESPLEGABLE DEL PANEL TRAZOS
# RUTA: res://script_gdscript/ui/pro/stroke_popover.gd
# Se abre con el "+" de Inicio / Fin / Estilo / Perfil del panel Trazos, al
# lado del panel (mismo aspecto que "Letras avanzadas"):
#   · start / end : lista de puntas (iconos dibujados con el mismo código que
#                   el lienzo), remate (plano / redondo / cuadrado), tamaño
#                   de las puntas e intercambiar inicio ↔ fin;
#   · style       : sólido / discontinuo / punteado / doble + guion y hueco;
#   · profile     : preajustes de grosor (Ideal, Afilado…) + editor de perfil.
# Todo pasa por InspectorCore (con deshacer); el perfil y el tamaño se ven en
# vivo al arrastrar y quedan en UN paso de deshacer.
# =============================================================================
extends PanelContainer
const StrokeProfile = preload("res://script_gdscript/shapes/stroke_profile.gd")
const StrokeMarkers = preload("res://script_gdscript/shapes/stroke_markers.gd")

const NumField = preload("res://script_gdscript/ui/pro/pro_num_field.gd")
const Swatch = preload("res://script_gdscript/ui/pro/stroke_swatch.gd")
const ProfileEditor = preload("res://script_gdscript/ui/pro/stroke_profile_editor.gd")
const StrokeGeom = preload("res://script_gdscript/shapes/stroke_geom.gd")
const W := 252

const STYLE_ITEMS := [[0, "Sólido"], [1, "Discontinuo"], [2, "Punteado"], [4, "Doble"]]
const CAP_ITEMS := [[0, "Plano"], [1, "Redondo"], [2, "Cuadrado"]]

static var _shared: PanelContainer = null

var mode := ""
var _anchor: Control = null
var _from: Control = null
var _box: VBoxContainer = null
var _title: Label = null
var _labels: Array[Label] = []
var _items: Array[Button] = []
var _fields: Array = []
var _live_before: Dictionary = {}
var _editor: Control = null

## Abre (o cierra si ya estaba abierto en el mismo modo) junto a `anchor`.
static func toggle(anchor: Control, m: String, from_btn: Control) -> PanelContainer:
	if not is_instance_valid(_shared):
		var layer := CanvasLayer.new()
		layer.name = "StrokePopoverLayer"
		layer.layer = 118
		anchor.get_tree().root.add_child(layer)
		_shared = load("res://script_gdscript/ui/pro/stroke_popover.gd").new()
		layer.add_child(_shared)
	if _shared.visible and _shared.mode == m and _shared._anchor == anchor:
		_shared.visible = false
	else:
		_shared.open_at(anchor, m, from_btn)
	return _shared

static func shared() -> PanelContainer:
	return _shared if is_instance_valid(_shared) else null

func _init() -> void:
	name = "StrokePopover"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(W, 0)

func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE + 2)
	header.add_child(_title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = tr("Cerrar")
	close.pressed.connect(func() -> void: visible = false)
	header.add_child(close)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	root.add_child(_box)
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed"):
		ic.changed.connect(func(_p) -> void:
			if visible and _live_before.is_empty():
				_refresh_states())
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _apply_theme())
	visibility_changed.connect(func() -> void:
		if not visible:
			_end_live())

func open_at(anchor: Control, m: String, from_btn: Control) -> void:
	_end_live()
	_anchor = anchor
	_from = from_btn
	mode = m
	_build()
	_apply_theme()
	visible = true
	reset_size()
	await get_tree().process_frame
	_place()

## A la izquierda del panel (o a la derecha si no cabe), a la altura del
## botón que lo abrió, siempre dentro de la pantalla.
func _place() -> void:
	if not is_instance_valid(_anchor):
		return
	var vp := get_viewport_rect().size
	var r := _anchor.get_global_rect()
	var s := get_combined_minimum_size()
	var x := r.position.x - s.x - 10.0
	if x < 8.0:
		x = r.end.x + 10.0
	var y0: float = _from.get_global_rect().position.y - 12.0 if is_instance_valid(_from) else r.position.y
	var y := clampf(y0, 8.0, maxf(8.0, vp.y - s.y - 8.0))
	global_position = Vector2(clampf(x, 8.0, maxf(8.0, vp.x - s.x - 8.0)), y)

# ── valores de la selección ──────────────────────────────────────────────────
func _ic() -> Node:
	return get_node_or_null("/root/InspectorCore")

func _prop(name: String, def: Variant) -> Variant:
	var ic := _ic()
	if ic == null or not ic.has_method("current_props"):
		return def
	var props: Dictionary = ic.current_props()
	if props.has(name) and not bool(props[name].get("mixed", false)):
		return props[name].get("value", def)
	return def

func _apply(prop: String, v: Variant) -> void:
	var ic := _ic()
	if ic:
		ic.apply(prop, v)
	_refresh_states()

# ── construcción ─────────────────────────────────────────────────────────────
func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_labels.clear()
	_items.clear()
	_fields.clear()
	_editor = null

func _build() -> void:
	_clear()
	match mode:
		"start", "end":
			var at_start := mode == "start"
			_title.text = tr("Inicio del trazo") if at_start else tr("Fin del trazo")
			_section(tr("Punta"))
			var grid := GridContainer.new()
			grid.columns = 5
			grid.add_theme_constant_override("h_separation", 4)
			grid.add_theme_constant_override("v_separation", 4)
			_box.add_child(grid)
			var prop := "stroke_pointer_start" if at_start else "stroke_pointer_end"
			for t in StrokeMarkers.TYPES.size():
				grid.add_child(_item("marker", t, at_start, tr(StrokeMarkers.LABELS[StrokeMarkers.TYPES[t]]), prop, Vector2(44, 30)))
			_section(tr("Remate"))
			var caps := HBoxContainer.new()
			caps.add_theme_constant_override("separation", 4)
			_box.add_child(caps)
			var cprop := "stroke_cap_start" if at_start else "stroke_cap_end"
			for c in CAP_ITEMS:
				var b := _item("cap", c[0], at_start, tr(c[1]), cprop, Vector2(0, 28))
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				caps.add_child(b)
			_section(tr("Tamaño de la punta"))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			_box.add_child(row)
			var f: Control = NumField.new("", "↕", tr("Tamaño de las puntas (inicio y fin)"))
			f.min_value = 25
			f.max_value = 500
			f.step = 5
			f.suffix = "%"
			f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			f.set_value_no_signal(float(_prop("stroke_pointer_scale", 1.0)) * 100.0)
			f.set_meta("prop", "stroke_pointer_scale")
			f.scrub_changed.connect(func(v: float) -> void: _live("stroke_pointer_scale", v / 100.0))
			f.scrub_ended.connect(func(_v: float) -> void: _commit_live("stroke_pointer_scale"))
			f.value_changed.connect(func(v: float) -> void:
				if _live_before.is_empty():
					_apply("stroke_pointer_scale", v / 100.0))
			row.add_child(f)
			_fields.append(f)
			var swap := Button.new()
			swap.text = "⇄  " + tr("Intercambiar")
			swap.tooltip_text = tr("Intercambiar inicio y fin")
			swap.focus_mode = Control.FOCUS_NONE
			swap.set_meta("action", true)
			swap.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE)
			swap.pressed.connect(_swap_ends)
			row.add_child(swap)
			_items.append(swap)
		"style":
			_title.text = tr("Estilo del trazo")
			# 14 estilos en dos columnas: muestra arriba, nombre abajo.
			var sgrid := GridContainer.new()
			sgrid.columns = 2
			sgrid.add_theme_constant_override("h_separation", 4)
			sgrid.add_theme_constant_override("v_separation", 4)
			_box.add_child(sgrid)
			for st in StrokeGeom.STYLE_ORDER:
				var label: String = tr(StrokeGeom.STYLE_LABELS[st])
				var b := _item("style", st, false, label, "stroke_style", Vector2(114, 40))
				var sw := b.get_child(0) as Control
				sw.offset_top = 2
				sw.offset_bottom = -15   # muestra arriba, nombre abajo
				var name_l := Label.new()
				name_l.name = "Name"
				name_l.text = label
				name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
				name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				name_l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
				name_l.offset_top = -16
				name_l.offset_bottom = -2
				name_l.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE_SMALL)
				b.add_child(name_l)
				sgrid.add_child(b)
			var row := HBoxContainer.new()
			row.name = "DashRow"
			row.add_theme_constant_override("separation", 6)
			_box.add_child(row)
			for d in [["stroke_dash_len", "Guion", 12.0], ["stroke_dash_gap", "Hueco", 8.0]]:
				var f: Control = NumField.new("", String(d[1]).substr(0, 1), tr(d[1]))
				f.min_value = 1
				f.max_value = 500
				f.step = 1
				f.suffix = "px"
				f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				f.set_value_no_signal(float(_prop(d[0], d[2])))
				f.set_meta("prop", d[0])
				var p: String = d[0]
				f.value_changed.connect(func(v: float) -> void: _apply(p, v))
				row.add_child(f)
				_fields.append(f)
		"profile":
			_title.text = tr("Perfil de grosor")
			var grid := GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 4)
			grid.add_theme_constant_override("v_separation", 4)
			_box.add_child(grid)
			for k in StrokeProfile.PRESETS:
				var b := _item("profile", StrokeProfile.preset(k), false, tr(StrokeProfile.PRESET_LABELS[k]), "stroke_profile", Vector2(54, 30))
				b.set_meta("preset", k)
				grid.add_child(b)
			_section(tr("Personalizado · arrastra los nodos, clic añade, doble clic quita"))
			_editor = ProfileEditor.new()
			_editor.changed_live.connect(func(p: PackedVector2Array) -> void: _live("stroke_profile", p))
			_editor.committed.connect(func(_p: PackedVector2Array) -> void: _commit_live("stroke_profile"))
			_box.add_child(_editor)
	_refresh_states()

func _section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE)
	_labels.append(l)
	_box.add_child(l)

## Botón con su muestra dibujada; al pulsarlo aplica `value` a `prop`.
func _item(kind: String, value: Variant, at_start: bool, tip: String, prop: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE)
	b.set_meta("prop", prop)
	b.set_meta("value", value)
	var sw: Control = Swatch.new(kind, value, at_start)
	sw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sw.offset_left = 6
	sw.offset_right = -6
	b.add_child(sw)
	b.pressed.connect(_on_item.bind(b))
	_items.append(b)
	return b

func _on_item(b: Button) -> void:
	var prop := String(b.get_meta("prop"))
	var v: Variant = b.get_meta("value")
	if prop == "stroke_profile":
		_apply_profile(v)
		return
	_apply(prop, v)

## Un perfil se ve con el trazo sólido: si estaba discontinuo / punteado /
## doble (o el "cónico" antiguo), pasa a sólido en el MISMO paso de deshacer.
func _apply_profile(p: PackedVector2Array) -> void:
	var ic := _ic()
	if ic == null:
		return
	var st := int(_prop("stroke_style", 0))
	if not StrokeProfile.is_uniform(p) and st != 0 and ic.has_method("apply_multi"):
		ic.apply_multi({"stroke_profile": p, "stroke_style": 0}, "Trazo · perfil")
	elif st == 3 and ic.has_method("apply_multi"):
		ic.apply_multi({"stroke_profile": p, "stroke_style": 0}, "Trazo · perfil")
	else:
		ic.apply("stroke_profile", p)
	if is_instance_valid(_editor):
		_editor.set_profile(p)
	_refresh_states()

func _swap_ends() -> void:
	var ic := _ic()
	if ic == null or not ic.has_method("apply_multi"):
		return
	ic.apply_multi({
		"stroke_pointer_start": int(_prop("stroke_pointer_end", 0)),
		"stroke_pointer_end": int(_prop("stroke_pointer_start", 0)),
		"stroke_cap_start": int(_prop("stroke_cap_end", 0)),
		"stroke_cap_end": int(_prop("stroke_cap_start", 0)),
	}, "Trazo · intercambiar extremos")
	_refresh_states()

# ── en vivo (arrastre) → un paso de deshacer al soltar ────────────────────────
func _live(prop: String, v: Variant) -> void:
	var ic := _ic()
	if ic == null or not ic.has_method("_write"):
		return
	if not _live_before.has(prop):
		var before := {}
		for s in ic.selection():
			var b = ic._read(s, prop)
			if b != null:
				before[s] = b
		_live_before[prop] = before
		# Perfil sobre un trazo discontinuo: pasa a sólido para verse.
		if prop == "stroke_profile" and int(_prop("stroke_style", 0)) != 0:
			_live_before["stroke_style"] = {}
			for s in before:
				_live_before["stroke_style"][s] = ic._read(s, "stroke_style")
				ic._write(s, "stroke_style", 0)
	for s in (_live_before[prop] as Dictionary):
		if is_instance_valid(s):
			ic._write(s, prop, v)
	ic.post_write_live()

func _commit_live(prop: String) -> void:
	var ic := _ic()
	if ic == null or not _live_before.has(prop):
		return
	if _live_before.has("stroke_style") and ic.has_method("commit_live_multi"):
		ic.commit_live_multi({prop: _live_before[prop], "stroke_style": _live_before["stroke_style"]}, "Trazo · perfil")
	else:
		ic.commit_live(prop, _live_before[prop])
	_live_before.clear()
	_refresh_states()

func _end_live() -> void:
	for p in _live_before.keys():
		if p != "stroke_style":
			_commit_live(p)
			break
	_live_before.clear()

# ── estado ───────────────────────────────────────────────────────────────────
func _refresh_states() -> void:
	var cur_prof := StrokeProfile.normalize(_prop("stroke_profile", PackedVector2Array()))
	var st := int(_prop("stroke_style", 0))
	if st == 3 and StrokeProfile.is_uniform(cur_prof):
		cur_prof = StrokeProfile.preset("taper")   # cónico antiguo = Afilado
	for b in _items:
		if not is_instance_valid(b) or b.has_meta("action"):
			continue
		var prop := String(b.get_meta("prop"))
		var on := false
		if prop == "stroke_profile":
			on = StrokeProfile.preset_name(cur_prof) == String(b.get_meta("preset", "?"))
		else:
			on = int(_prop(prop, 0)) == int(b.get_meta("value"))
		_style_item(b, on)
	for f in _fields:
		if is_instance_valid(f):
			var p := String(f.get_meta("prop"))
			var v := float(_prop(p, f.value if p != "stroke_pointer_scale" else 1.0))
			f.set_value_no_signal(v * 100.0 if p == "stroke_pointer_scale" else v)
	var dash := _box.get_node_or_null("DashRow") as Control
	if dash:
		dash.visible = st in StrokeGeom.PATTERNED
	if is_instance_valid(_editor):
		_editor.set_profile(cur_prof)
	if visible:
		reset_size()

# ── tema (igual que "Letras avanzadas") ──────────────────────────────────────
func _apply_theme() -> void:
	var sb := ProUIStyle.flat(ProUIStyle.col("PANEL_SURFACE"), 8, ProUIStyle.col("BORDER_STRONG"), 10, 10)
	sb.shadow_color = Color(0, 0, 0, 0.3 if ProUIStyle.is_dark() else 0.14)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", sb)
	if is_instance_valid(_title):
		_title.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
		var close := _title.get_parent().get_child(1) as Button
		close.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
		close.add_theme_color_override("font_hover_color", ProUIStyle.col("PANEL_TEXT"))
	for l in _labels:
		l.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
	for b in _items:
		if is_instance_valid(b) and b.has_meta("action"):
			b.add_theme_stylebox_override("normal", ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 4, ProUIStyle.col("INPUT_BORDER"), 6, 0))
			b.add_theme_stylebox_override("hover", ProUIStyle.flat(ProUIStyle.col("BUTTON_HOVER"), 4, ProUIStyle.col("BORDER_STRONG"), 6, 0))
			b.add_theme_stylebox_override("pressed", ProUIStyle.flat(ProUIStyle.col("BUTTON_PRESSED"), 4, ProUIStyle.col("ACCENT"), 6, 0))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			b.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
	for f in _fields:
		if is_instance_valid(f) and f.has_method("apply_theme"):
			f.apply_theme()
	_refresh_states()

func _style_item(b: Button, on: bool) -> void:
	var accent := ProUIStyle.col("ACCENT")
	var n := ProUIStyle.flat(Color(accent, 0.28) if on else ProUIStyle.col("INPUT_BG"), 4,
		Color(accent, 0.7) if on else ProUIStyle.col("INPUT_BORDER"), 6, 0)
	var h := ProUIStyle.flat(Color(accent, 0.36) if on else ProUIStyle.col("BUTTON_HOVER"), 4,
		Color(accent, 0.7) if on else ProUIStyle.col("BORDER_STRONG"), 6, 0)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("pressed", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, ProUIStyle.col("PANEL_TEXT") if on else ProUIStyle.col("TEXT_SECONDARY"))
	var nl := b.get_node_or_null("Name") as Label
	if nl:
		nl.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT") if on else ProUIStyle.col("TEXT_SECONDARY"))
	for c in b.get_children():
		if c is Control and c.has_method("set_value"):
			c.color_override = ProUIStyle.col("PANEL_TEXT") if on else ProUIStyle.col("TEXT_SECONDARY")
			c.queue_redraw()

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
		if is_instance_valid(_from) and _from.get_global_rect().has_point(mp):
			return
		visible = false
