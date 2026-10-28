# =============================================================================
# VECTOPEN — PROFESSIONAL UI STYLE HELPERS
# RUTA: res://script_gdscript/ui/pro/pro_ui_style.gd
# Shared, theme-driven styling for the compact Professional mode widgets
# (ProStudio, ProTopBar, ProContextMenu). Every color comes from ThemeManager
# so all five themes render consistently.
# =============================================================================
class_name ProUIStyle
extends RefCounted

const FONT_SIZE := 11
const FONT_SIZE_SMALL := 10
const ROW_H := 20
const ICON_SIZE := 14

static var _icon_cache: Dictionary = {}

static func tm() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("/root/ThemeManager")

## Theme color for a ThemeManager slot name, with a dark fallback.
static func col(slot_name: String) -> Color:
	var t := tm()
	if t:
		return t.get_color(t.Slot[slot_name])
	match slot_name:
		"PANEL_BG": return Color(0.125, 0.125, 0.125)
		"PANEL_SURFACE": return Color(0.145, 0.145, 0.145)
		"PANEL_TEXT", "ICON_PRIMARY": return Color(0.9, 0.9, 0.9)
		"TOOLBAR_BG", "INPUT_BG": return Color(0.094, 0.094, 0.094)
		"BORDER": return Color(0.22, 0.22, 0.22)
		"ACCENT": return Color(0.35, 0.5, 0.68)
	return Color(0.5, 0.5, 0.5)

static func is_dark() -> bool:
	var t := tm()
	return t.is_dark() if t else true

## Loads an SVG icon and recolors every opaque pixel to `color`, keeping alpha.
## Cached per (path, color, size) so theme switches stay cheap.
static func icon(path: String, color: Color, size: int = ICON_SIZE) -> Texture2D:
	var key := "%s|%s|%d" % [path, color.to_html(), size]
	if _icon_cache.has(key):
		return _icon_cache[key]
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != size or img.get_height() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if a > 0.0:
				img.set_pixel(x, y, Color(color.r, color.g, color.b, a * color.a))
	var out := ImageTexture.create_from_image(img)
	_icon_cache[key] = out
	return out

static func flat(bg: Color, radius: int = 0, border: Color = Color(0, 0, 0, 0), margin_h: int = 0, margin_v: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb

static func label(text: String, muted: bool = true, size: int = FONT_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col("TEXT_SECONDARY") if muted else col("PANEL_TEXT"))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

## Flat toggle button: icon (tinted) or short text. Active state = raised chip
## with accent outline, the same language as the rest of the Pro panels.
static func toggle_button(text: String, icon_path: String = "", tooltip: String = "") -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(ROW_H + 2, ROW_H)
	b.tooltip_text = tooltip
	b.set_meta("pro_icon_path", icon_path)
	if icon_path != "":
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.expand_icon = false
	else:
		b.text = text
	b.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	style_toggle(b, false)
	return b

static func style_toggle(b: Button, active: bool) -> void:
	if not is_instance_valid(b):
		return
	b.set_meta("pro_active", active)
	var normal := flat(col("SURFACE_RAISED") if active else Color(0, 0, 0, 0), 3,
		col("ACCENT") if active else Color(0, 0, 0, 0), 4, 1)
	var hover := flat(col("BUTTON_HOVER"), 3, col("ACCENT") if active else Color(0, 0, 0, 0), 4, 1)
	var pressed := flat(col("BUTTON_PRESSED"), 3, Color(0, 0, 0, 0), 4, 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", flat(Color(0, 0, 0, 0), 3, Color(0, 0, 0, 0), 4, 1))
	b.add_theme_color_override("font_disabled_color", col("TEXT_DISABLED"))
	var text_col := col("PANEL_TEXT") if active else col("TEXT_SECONDARY")
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(key, text_col if key == "font_color" else col("PANEL_TEXT"))
	var path := String(b.get_meta("pro_icon_path", ""))
	if path != "":
		b.icon = icon(path, col("ICON_PRIMARY") if active else col("TEXT_SECONDARY"))

## Plain icon/text action button (no persistent active state).
static func action_button(text: String, icon_path: String = "", tooltip: String = "") -> Button:
	var b := toggle_button(text, icon_path, tooltip)
	b.set_meta("pro_action", true)
	return b

static func style_line_edit(le: LineEdit) -> void:
	le.add_theme_stylebox_override("normal", flat(col("INPUT_BG"), 3, col("INPUT_BORDER"), 5, 1))
	le.add_theme_stylebox_override("focus", flat(col("INPUT_BG"), 3, col("ACCENT"), 5, 1))
	le.add_theme_stylebox_override("read_only", flat(col("INPUT_BG"), 3, col("INPUT_BORDER"), 5, 1))
	le.add_theme_color_override("font_color", col("PANEL_TEXT"))
	le.add_theme_color_override("caret_color", col("PANEL_TEXT"))
	# Texto de ayuda («Ir a…»): sin esto salía casi blanco en el tema claro.
	le.add_theme_color_override("font_placeholder_color", col("TEXT_SECONDARY"))
	le.add_theme_font_size_override("font_size", FONT_SIZE)
	le.custom_minimum_size.y = ROW_H

static func style_option(opt: OptionButton) -> void:
	opt.focus_mode = Control.FOCUS_NONE
	opt.custom_minimum_size.y = ROW_H
	opt.add_theme_font_size_override("font_size", FONT_SIZE)
	opt.add_theme_stylebox_override("normal", flat(col("INPUT_BG"), 3, col("INPUT_BORDER"), 6, 0))
	opt.add_theme_stylebox_override("hover", flat(col("INPUT_HOVER"), 3, col("INPUT_BORDER"), 6, 0))
	opt.add_theme_stylebox_override("pressed", flat(col("INPUT_HOVER"), 3, col("ACCENT"), 6, 0))
	opt.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		opt.add_theme_color_override(key, col("PANEL_TEXT"))
	opt.add_theme_icon_override("arrow", icon("res://icon/UI/nav-arrow-down.svg", col("TEXT_SECONDARY"), 10))
	style_popup(opt.get_popup())

## Compact desktop-style popup menu, used by dropdowns and the Pro context menu.
static func style_popup(pop: PopupMenu) -> void:
	if not is_instance_valid(pop):
		return
	var panel := flat(col("PANEL_SURFACE"), 4, col("BORDER_STRONG"), 4, 4)
	panel.shadow_color = Color(0, 0, 0, 0.35 if is_dark() else 0.15)
	panel.shadow_size = 6
	panel.shadow_offset = Vector2(0, 2)
	pop.add_theme_stylebox_override("panel", panel)
	pop.add_theme_stylebox_override("hover", flat(col("ACCENT"), 3))
	var sep := StyleBoxLine.new()
	sep.color = col("BORDER")
	sep.thickness = 1
	pop.add_theme_stylebox_override("separator", sep)
	pop.add_theme_font_size_override("font_size", FONT_SIZE + 1)
	pop.add_theme_constant_override("v_separation", 6)
	pop.add_theme_constant_override("h_separation", 8)
	pop.add_theme_constant_override("item_start_padding", 8)
	pop.add_theme_constant_override("item_end_padding", 10)
	pop.add_theme_color_override("font_color", col("PANEL_TEXT"))
	pop.add_theme_color_override("font_hover_color", Color.WHITE)
	pop.add_theme_color_override("font_accelerator_color", col("TEXT_MUTED"))
	pop.add_theme_color_override("font_disabled_color", col("TEXT_DISABLED"))
	pop.add_theme_color_override("font_separator_color", col("TEXT_MUTED"))
	var arrow := icon("res://icon/UI/nav-arrow-right.svg", col("TEXT_SECONDARY"), 10)
	pop.add_theme_icon_override("submenu", arrow)
	pop.add_theme_icon_override("submenu_mirrored", icon("res://icon/UI/nav-arrow-left.svg", col("TEXT_SECONDARY"), 10))
	var check := icon("res://icon/UI/badge-check.svg", col("PANEL_TEXT"), 12)
	if check:
		pop.add_theme_icon_override("checked", check)
		pop.add_theme_icon_override("radio_checked", check)

## HSlider with a thin theme-colored track: the engine default is a dark bar
## that looks broken on light themes.
static func style_slider(s: Slider) -> void:
	s.focus_mode = Control.FOCUS_NONE
	var vertical := s is VSlider
	if vertical:
		s.custom_minimum_size.x = maxf(s.custom_minimum_size.x, ROW_H)
	else:
		s.custom_minimum_size.y = ROW_H
	# The track thickness comes from the margins across the slider axis
	var track := flat(col("INPUT_BG"), 2, col("INPUT_BORDER"))
	var fill := flat(col("ACCENT"), 2)
	for sb in [track, fill]:
		if vertical:
			sb.content_margin_left = 1
			sb.content_margin_right = 1
		else:
			sb.content_margin_top = 1
			sb.content_margin_bottom = 1
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob_texture(col("PANEL_TEXT") if is_dark() else Color.WHITE, col("BORDER_STRONG"))
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	s.add_theme_icon_override("grabber_disabled", knob)
	s.add_theme_constant_override("center_grabber", 0)

static func _knob_texture(fill_col: Color, ring: Color) -> Texture2D:
	var key := "knob|%s|%s" % [fill_col.to_html(), ring.to_html()]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var n := 12
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n / 2.0 - 0.5, n / 2.0 - 0.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(c)
			if d <= 4.6:
				img.set_pixel(x, y, fill_col)
			elif d <= 5.6:
				img.set_pixel(x, y, ring)
	var tex := ImageTexture.create_from_image(img)
	_icon_cache[key] = tex
	return tex

static func style_check(cb: CheckBox) -> void:
	cb.focus_mode = Control.FOCUS_NONE
	cb.add_theme_font_size_override("font_size", FONT_SIZE)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		cb.add_theme_color_override(key, col("PANEL_TEXT"))
	cb.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	cb.add_theme_icon_override("checked", _check_texture(true))
	cb.add_theme_icon_override("unchecked", _check_texture(false))

static func _check_texture(on: bool) -> Texture2D:
	var box_bg := col("ACCENT") if on else col("INPUT_BG")
	var border := col("ACCENT") if on else col("BORDER_STRONG")
	var key := "check|%s|%s|%s" % [on, box_bg.to_html(), border.to_html()]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var n := 12
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var edge := x == 0 or y == 0 or x == n - 1 or y == n - 1
			img.set_pixel(x, y, border if edge else box_bg)
	if on:
		# Check mark polyline: (3,6) -> (5,8) -> (9,3)
		for p in [Vector2i(3, 6), Vector2i(4, 7), Vector2i(5, 8), Vector2i(6, 7), Vector2i(7, 6), Vector2i(8, 5), Vector2i(9, 4)]:
			img.set_pixel(p.x, p.y, Color.WHITE)
			img.set_pixel(p.x, p.y - 1, Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	_icon_cache[key] = tex
	return tex

static func vsep() -> Control:
	var s := ColorRect.new()
	s.color = col("BORDER")
	s.custom_minimum_size = Vector2(1, 16)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

static func hline() -> Control:
	var s := ColorRect.new()
	s.color = col("BORDER")
	s.custom_minimum_size = Vector2(0, 1)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s
