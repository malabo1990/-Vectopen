extends FlowContainer

## Paleta de muestras de color del menú contextual (inspector). Al hacer clic en
## una muestra aplica ese color de RELLENO (o trazo) a la selección vía
## ColorCore / InspectorCore (con undo).
##
## The scene ships flat ColorRects; they are replaced at runtime by rounded,
## theme-aware swatch buttons: one grey ramp plus light / mid / dark rows per hue.

@export var saturation: float = 0.8
@export var value: float = 0.9
## "fill" (por defecto) o "stroke" — qué propiedad cambia esta paleta.
@export_enum("fill", "stroke") var apply_to: String = "fill"

const SWATCH_SIZE := Vector2(20, 20)
const HUES := 8

var _swatches: Array[Button] = []

func _ready() -> void:
	await get_tree().process_frame
	_build_swatches()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.connect(_on_theme_changed)

func _on_theme_changed(_mode: String) -> void:
	_style_swatches()

## Grey ramp, then a light / mid / dark row per hue (same column = same hue).
func palette_colors() -> Array[Color]:
	var out: Array[Color] = []
	for i in HUES:
		var v := float(i) / float(HUES - 1)
		out.append(Color(v, v, v))
	var rows := [[0.35, 1.0], [saturation, value], [0.9, 0.55]]   # [saturation, value]
	for r in rows:
		for i in HUES:
			out.append(Color.from_hsv(float(i) / HUES, r[0], r[1]))
	return out

func _build_swatches() -> void:
	for hijo in get_children():
		if hijo is ColorRect:
			hijo.visible = false   # legacy scene swatches
	for b in _swatches:
		if is_instance_valid(b):
			b.queue_free()
	_swatches.clear()
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)
	for c in palette_colors():
		var b := Button.new()
		b.custom_minimum_size = SWATCH_SIZE
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = "#" + c.to_html(false).to_upper()
		b.set_meta("swatch_color", c)
		b.pressed.connect(_apply_color.bind(c))
		add_child(b)
		_swatches.append(b)
	_style_swatches()
	_style_title()

func _style_swatches() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	var ring: Color = tm.get_interactive_color() if (tm and tm.has_method("get_interactive_color")) else ProUIStyle.col("ACCENT")
	for b in _swatches:
		if not is_instance_valid(b):
			continue
		var c: Color = b.get_meta("swatch_color")
		var sb := ProUIStyle.flat(c, 5, ProUIStyle.col("BORDER"))
		var hov := ProUIStyle.flat(c, 5, ring)
		hov.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", hov)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_style_title()

## "Color Grid" title above the grid was a fixed dark grey (unreadable on dark themes).
func _style_title() -> void:
	var outer := get_parent().get_parent() if get_parent() else null
	var title := outer.get_node_or_null("Label") as Label if outer else null
	if title:
		title.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
		title.remove_theme_stylebox_override("normal")

func _apply_color(c: Color) -> void:
	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_method("set_color"):
		cc.set_color(c, apply_to)
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply("stroke_color" if apply_to == "stroke" else "fill_color", c)

## Kept for callers of the old API.
func actualizar_colores_hsl_extendido() -> void:
	_build_swatches()
