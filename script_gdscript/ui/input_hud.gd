# =============================================================================
# VECTOPEN — INPUT HUD (bottom-left chip, Smart mode)
# RUTA: res://script_gdscript/ui/input_hud.gd
# Drives the existing chip in main.tscn (keyboard/PanelContainer/...):
#   · Export button  → opens the export dialog
#   · Keyboard button → toggles the shortcuts panel (TogglePanelSetting)
#   · Live key caps  → the key being pressed, with its modifiers
#   · Mouse          → three buttons lit while used (left green, wheel yellow,
#                      right red), anywhere in the window
# Everything follows ThemeManager.
# =============================================================================
class_name InputHud
extends Node

const CHIP := "PanelContainer"
const CONTENT := "PanelContainer/MarginContainer/Contenido"
const IDLE_AFTER_MS := 1400

## Mouse drawn as a rounded body split into left / wheel / right.
class MouseIndicator extends Control:
	var left_on := false
	var middle_on := false
	var right_on := false

	func _init() -> void:
		custom_minimum_size = Vector2(16, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var outline := ProUIStyle.col("ICON_PRIMARY")
		var body := Rect2(Vector2(1, 1), size - Vector2(2, 2))
		var r := body.size.x * 0.5
		var split_y := body.position.y + body.size.y * 0.45
		var mid_x := body.get_center().x
		var green := Color("#30a46c")
		var yellow := Color("#f5a623")
		var red := Color("#e5484d")
		# Button halves (filled while pressed)
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var steps := 10
		for i in steps + 1:
			var a := PI + PI * 0.5 * float(i) / steps
			left.append(Vector2(mid_x, body.position.y + r) + Vector2(cos(a), sin(a)) * r)
		left.append(Vector2(mid_x, split_y))
		left.append(Vector2(body.position.x, split_y))
		for i in steps + 1:
			var a := PI * 1.5 + PI * 0.5 * float(i) / steps
			right.append(Vector2(mid_x, body.position.y + r) + Vector2(cos(a), sin(a)) * r)
		right.append(Vector2(body.end.x, split_y))
		right.append(Vector2(mid_x, split_y))
		if left_on:
			draw_colored_polygon(left, green)
		if right_on:
			draw_colored_polygon(right, red)
		# Body outline
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = outline
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(int(r))
		sb.anti_aliasing = true
		draw_style_box(sb, body)
		draw_line(Vector2(body.position.x + 1, split_y), Vector2(body.end.x - 1, split_y), outline, 1.0)
		draw_line(Vector2(mid_x, body.position.y + 1), Vector2(mid_x, split_y), outline, 1.0)
		# Wheel
		var wheel := Rect2(Vector2(mid_x - 1.5, body.position.y + 3), Vector2(3, 5))
		draw_rect(wheel, yellow if middle_on else outline, true)

var _chip: PanelContainer
var _btn_export: Button
var _btn_keyboard: Button
var _lbl_mods: Label
var _lbl_key: Label
var _mouse: MouseIndicator
var _last_key_ms: int = 0

func _ready() -> void:
	var host := get_parent()
	_chip = host.get_node_or_null(CHIP) as PanelContainer
	var content := host.get_node_or_null(CONTENT)
	if content == null:
		return
	_btn_export = content.get_node_or_null("Button2") as Button
	_btn_keyboard = content.get_node_or_null("Button") as Button
	_lbl_mods = content.get_node_or_null("Label2") as Label
	_lbl_key = content.get_node_or_null("Label") as Label
	if _btn_export:
		_btn_export.set_meta("hud_icon_path", "res://icon/UI/menu/export.svg")
		_btn_export.tooltip_text = tr("Exportar")
		if not _btn_export.pressed.is_connected(_on_export):
			_btn_export.pressed.connect(_on_export)
	if _btn_keyboard:
		_btn_keyboard.set_meta("hud_icon_path", "res://icon/UI/menu/keyboard.svg")
		_btn_keyboard.tooltip_text = tr("Atajos de teclado y ratón")
	# Replace the three flat ColorRects with a drawn mouse
	var old_mouse := content.get_node_or_null("Panel") as Control
	_mouse = MouseIndicator.new()
	_mouse.name = "MouseIndicator"
	if old_mouse:
		old_mouse.visible = false
		content.add_child(_mouse)
		content.move_child(_mouse, old_mouse.get_index())
	else:
		content.add_child(_mouse)
	_show_idle()
	_apply_theme()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m): _apply_theme())
	set_process(true)

func _on_export() -> void:
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("request_export_dialog"):
		ge.emit_safe("request_export_dialog")

# ── Live input (observed, never consumed) ────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		show_key_event(event)
	elif event is InputEventMouseButton:
		var on: bool = event.pressed
		match event.button_index:
			MOUSE_BUTTON_LEFT: _mouse.left_on = on
			MOUSE_BUTTON_RIGHT: _mouse.right_on = on
			MOUSE_BUTTON_MIDDLE: _mouse.middle_on = on
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				_mouse.middle_on = true
				_last_key_ms = Time.get_ticks_msec()
		if is_instance_valid(_mouse):
			_mouse.queue_redraw()

## Updates the key caps for a key event (also used by tests).
func show_key_event(event: InputEventKey) -> void:
	var mods: PackedStringArray = []
	if event.ctrl_pressed: mods.append("Ctrl")
	if event.shift_pressed: mods.append("Shift")
	if event.alt_pressed: mods.append("Alt")
	if event.meta_pressed: mods.append("Cmd")
	var key_name := OS.get_keycode_string(event.keycode)
	if event.keycode in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
		key_name = ""
	if is_instance_valid(_lbl_mods):
		_lbl_mods.text = " + ".join(mods)
		_lbl_mods.visible = not mods.is_empty()
	if is_instance_valid(_lbl_key):
		_lbl_key.text = key_name if key_name != "" else "…"
	_last_key_ms = Time.get_ticks_msec()
	_style_caps(true)

func _process(_delta: float) -> void:
	# Wheel flashes briefly; key caps dim back to idle after a moment
	if _last_key_ms > 0 and Time.get_ticks_msec() - _last_key_ms > IDLE_AFTER_MS:
		_last_key_ms = 0
		_show_idle()
		if is_instance_valid(_mouse) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_mouse.middle_on = false
			_mouse.queue_redraw()

func _show_idle() -> void:
	if is_instance_valid(_lbl_mods):
		_lbl_mods.visible = false
	if is_instance_valid(_lbl_key):
		_lbl_key.text = "⌨"
	_style_caps(false)

# ── Theme ─────────────────────────────────────────────────────────────────────
func _apply_theme() -> void:
	if is_instance_valid(_chip):
		var sb := ProUIStyle.flat(ProUIStyle.col("PANEL_SURFACE"), 12, ProUIStyle.col("BORDER"), 8, 5)
		sb.shadow_color = Color(0, 0, 0, 0.30 if ProUIStyle.is_dark() else 0.10)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 3)
		_chip.add_theme_stylebox_override("panel", sb)
	for b in [_btn_export, _btn_keyboard]:
		if not is_instance_valid(b):
			continue
		b.expand_icon = false
		b.custom_minimum_size = Vector2(28, 28)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var path: String = b.icon.resource_path if b.icon else ""
		if not b.has_meta("hud_icon_path"):
			b.set_meta("hud_icon_path", path)
		path = String(b.get_meta("hud_icon_path"))
		if path != "":
			b.icon = ProUIStyle.icon(path, ProUIStyle.col("ICON_PRIMARY"), 16)
		ProUIStyle.style_toggle(b, b.toggle_mode and b.button_pressed)
		b.remove_meta("pro_icon_path")
	_style_caps(_last_key_ms > 0)
	if is_instance_valid(_mouse):
		_mouse.queue_redraw()

## Key caps: rounded chips; bright while a key was just pressed, dim at rest.
func _style_caps(active: bool) -> void:
	for l in [_lbl_mods, _lbl_key]:
		if not is_instance_valid(l):
			continue
		var cap := ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 5,
			ProUIStyle.col("ACCENT") if active else ProUIStyle.col("BORDER"), 6, 1)
		cap.border_width_bottom = 2
		l.add_theme_stylebox_override("normal", cap)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT") if active else ProUIStyle.col("TEXT_SECONDARY"))
		l.custom_minimum_size = Vector2(24, 22)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
