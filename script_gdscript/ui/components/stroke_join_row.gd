# =============================================================================
# VECTOPEN — FILA «UNIÓN» DEL TRAZO (inglete / redonda / bisel + límite)
# RUTA: res://script_gdscript/ui/components/stroke_join_row.gd
#
# UX-08: las uniones faltaban en los tres modos. Un ÚNICO componente que se
# coloca en el panel de Trazos de Smart, en el Inspector de Modern y en la
# página Trazo de Pro: misma propiedad, mismo deshacer, mismo aspecto.
# Escribe vía InspectorCore (stroke_join / stroke_miter_limit) y se oculta si
# ningún objeto seleccionado tiene uniones (pincel, texto, imagen…).
# El límite de inglete solo se activa con la unión en inglete.
# =============================================================================
class_name StrokeJoinRow
extends HBoxContainer

const StrokeGeom = preload("res://script_gdscript/shapes/stroke_geom.gd")

var label_width := 64.0
var buttons: Array[Button] = []
var limit_field: NumericField
var _current := 0
var _guard := false
var _label: Label

func _init(p_label_width: float = 64.0) -> void:
	label_width = p_label_width
	name = "StrokeJoinRow"

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_label = Label.new()
	_label.text = tr("Unión")
	_label.custom_minimum_size = Vector2(label_width, 0)
	_label.add_theme_font_size_override("font_size", 11)
	add_child(_label)
	for j in [StrokeGeom.JOIN_MITER, StrokeGeom.JOIN_ROUND, StrokeGeom.JOIN_BEVEL]:
		var b := Button.new()
		b.name = "BtnJoin%d" % j
		b.toggle_mode = false
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(24, 22)
		b.tooltip_text = tr("Unión en %s") % tr(StrokeGeom.JOIN_LABELS[j]).to_lower()
		b.set_meta("join", j)
		var glyph := _JoinGlyph.new(j)
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(glyph)
		b.pressed.connect(_on_join.bind(j))
		add_child(b)
		buttons.append(b)
	limit_field = NumericField.new("", "×", StrokeGeom.MITER_LIMIT_MIN, StrokeGeom.MITER_LIMIT_MAX, 0.5)
	limit_field.name = "MiterLimit"
	limit_field.decimals = 1
	limit_field.value = StrokeGeom.MITER_LIMIT
	limit_field.tooltip_text = tr("Límite de inglete: por encima, la esquina se bisela")
	limit_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	limit_field.custom_minimum_size = Vector2(36, 0)
	limit_field.value_changed.connect(_on_limit_changed)
	limit_field.drag_ended.connect(func() -> void: _apply("stroke_miter_limit", limit_field.value))
	add_child(limit_field)
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and not ic.changed.is_connected(_on_props):
		ic.changed.connect(_on_props)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme):
		tm.theme_changed.connect(_on_theme)
	_restyle()
	if ic and ic.has_method("current_props"):
		_on_props(ic.current_props())

func _on_theme(_m = null) -> void:
	_restyle()

func _restyle() -> void:
	if is_instance_valid(_label):
		_label.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
	for b in buttons:
		ProUIStyle.style_toggle(b, int(b.get_meta("join")) == _current)
		for c in b.get_children():
			if c is Control:
				(c as Control).queue_redraw()
	if is_instance_valid(limit_field):
		limit_field.enabled = _current == StrokeGeom.JOIN_MITER

func _on_join(j: int) -> void:
	_current = j
	_restyle()
	_apply("stroke_join", j)

func _on_limit_changed(v: float) -> void:
	if limit_field._is_dragging:
		return
	_apply("stroke_miter_limit", v)

func _apply(prop: String, v: Variant) -> void:
	if _guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply(prop, v)

func _on_props(props: Dictionary) -> void:
	if not is_instance_valid(self):
		return
	visible = props.has("stroke_join")
	if not visible:
		return
	_guard = true
	var pj: Dictionary = props["stroke_join"]
	_current = -1 if pj.get("mixed", false) else int(pj.get("value", 0))
	if props.has("stroke_miter_limit") and not props["stroke_miter_limit"].get("mixed", false):
		limit_field.set_value_silent(float(props["stroke_miter_limit"]["value"]))
	_restyle()
	_guard = false

## Dibujo de la unión: una esquina gruesa con la unión de ese botón.
class _JoinGlyph extends Control:
	var join := 0
	func _init(j: int) -> void:
		join = j
	func _draw() -> void:
		var s := size
		var c := ProUIStyle.col("ICON_PRIMARY")
		var w := minf(s.x, s.y) * 0.32
		var pts := PackedVector2Array([Vector2(s.x * 0.22, s.y * 0.82), Vector2(s.x * 0.5, s.y * 0.22),
			Vector2(s.x * 0.78, s.y * 0.82)])
		var m := StrokeGeom.build(pts, false, 0, w, 0, 0, PackedVector2Array(), 1.0, 1.0, join, 10.0)
		if not (m["indices"] as PackedInt32Array).is_empty():
			RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), m["indices"], m["points"], PackedColorArray([c]))
