# =============================================================================
# VECTOPEN — MODERN BOTTOM TOOLBAR (FIGMA UI3 / APPLE STYLE)
# RUTA: res://script_gdscript/ui/modern/modern_bottom_toolbar.gd
# Barra flotante centrada en la parte inferior del lienzo con herramientas y zoom
# =============================================================================
class_name ModernBottomToolbar
extends PanelContainer

signal tool_selected(tool_name: String)
signal zoom_changed(percentage: float)

var _buttons: Dictionary = {} # tool_name -> Button
var _active_tool: String = "select"
var _canvas = null
var _last_synced_zoom: float = -1.0

var btn_zoom_out: Button
var lbl_zoom: Label
var btn_zoom_in: Button

func _ready() -> void:
	_setup_styles()
	_build_ui()
	_connect_events()
	_sync_active_tool()

func _process(_delta: float) -> void:
	_sync_zoom_from_canvas()

func _setup_styles() -> void:
	custom_minimum_size = Vector2(360, 44)
	
	# Estilo elegante Apple: Gris claro sutil (Studio neutral), bordes redondeados y sombra suave
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.97, 0.98, 0.98)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.86, 0.86, 0.89, 0.95)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.08)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	add_theme_stylebox_override("panel", sb)

func _build_ui() -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(hbox)

	var tools := [
		{"name": "select", "label": "↖", "tooltip": "Seleccionar y Mover (V)", "icon": "res://icon/UI/navigation.svg"},
		{"name": "artboard", "label": "⛶", "tooltip": "Marco / Artboard (F)", "icon": "res://icon/UI/frame-alt.svg"},
		{"name": "rectangle", "label": "□", "tooltip": "Rectangulo (R)", "icon": "res://icon/UI/square.svg"},
		{"name": "ellipse", "label": "○", "tooltip": "Elipse (O)", "icon": "res://icon/UI/circle-spark.svg"},
		{"name": "pen", "label": "✎", "tooltip": "Pluma vectorial (P)", "icon": "res://icon/UI/draw.svg"},
		{"name": "text", "label": "T", "tooltip": "Texto (T)", "icon": "res://icon/UI/text-square.svg"}
	]

	for t in tools:
		var btn := _create_tool_button(t["name"], t["label"], t["tooltip"], t["icon"])
		hbox.add_child(btn)
		_buttons[t["name"]] = btn

	# Separador vertical fino y discreto
	var sep := VSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = Color(0.85, 0.85, 0.88, 1.0)
	sep_sb.border_width_left = 1
	sep_sb.border_color = Color(0.85, 0.85, 0.88, 1.0)
	sep.add_theme_stylebox_override("separator", sep_sb)
	hbox.add_child(sep)

	# ── CONTROLES DE ZOOM CON ESTILO CHIP APPLE ──
	btn_zoom_out = _create_chip_button("−", "Reducir zoom", Vector2(26, 28))
	btn_zoom_out.pressed.connect(_on_zoom_out_pressed)
	hbox.add_child(btn_zoom_out)

	lbl_zoom = Label.new()
	lbl_zoom.text = "100%"
	lbl_zoom.custom_minimum_size = Vector2(46, 28)
	lbl_zoom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_zoom.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_zoom.add_theme_font_size_override("font_size", 11)
	lbl_zoom.add_theme_color_override("font_color", Color(0.18, 0.18, 0.22, 1.0))
	lbl_zoom.tooltip_text = "Zoom actual (Clic para resetear al 100%)"
	lbl_zoom.mouse_filter = Control.MOUSE_FILTER_PASS

	var lbl_sb := StyleBoxFlat.new()
	lbl_sb.bg_color = Color(0.93, 0.93, 0.95, 0.8)
	lbl_sb.set_corner_radius_all(6)
	lbl_sb.content_margin_left = 4
	lbl_sb.content_margin_right = 4
	lbl_zoom.add_theme_stylebox_override("normal", lbl_sb)
	lbl_zoom.gui_input.connect(_on_zoom_label_gui_input)
	hbox.add_child(lbl_zoom)

	btn_zoom_in = _create_chip_button("+", "Aumentar zoom", Vector2(26, 28))
	btn_zoom_in.pressed.connect(_on_zoom_in_pressed)
	hbox.add_child(btn_zoom_in)

func _create_chip_button(btn_text: String, tooltip: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = btn_text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 13)

	var norm_sb := StyleBoxFlat.new()
	norm_sb.bg_color = Color(0.93, 0.93, 0.95, 0.8)
	norm_sb.set_corner_radius_all(6)

	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(0.88, 0.88, 0.91, 1.0)
	hover_sb.set_corner_radius_all(6)

	var press_sb := StyleBoxFlat.new()
	press_sb.bg_color = Color(0.82, 0.82, 0.86, 1.0)
	press_sb.set_corner_radius_all(6)

	btn.add_theme_stylebox_override("normal", norm_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", press_sb)
	btn.add_theme_color_override("font_color", Color(0.18, 0.18, 0.22, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.12, 1.0))
	return btn

func _create_tool_button(tool_id: String, fallback_label: String, tooltip: String, icon_path: String) -> Button:
	var btn := Button.new()
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(32, 28)
	
	if ResourceLoader.exists(icon_path):
		btn.icon = load(icon_path)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.expand_icon = true
	else:
		btn.text = fallback_label
		btn.add_theme_font_size_override("font_size", 12)
	
	btn.pressed.connect(func(): _on_tool_button_pressed(tool_id))
	return btn

func _connect_events() -> void:
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("data_tool_changed") and not ge.data_tool_changed.is_connected(_on_data_tool_changed):
		ge.data_tool_changed.connect(_on_data_tool_changed)

func _find_canvas():
	if is_instance_valid(_canvas):
		return _canvas
	if get_tree():
		_canvas = get_tree().get_first_node_in_group("_vectopen_canvas")
	return _canvas

func _on_tool_button_pressed(tool_id: String) -> void:
	_active_tool = tool_id
	_sync_active_tool()
	tool_selected.emit(tool_id)

	var c = _find_canvas()
	if is_instance_valid(c) and c.has_method("switch_tool"):
		c.switch_tool(tool_id)

func _on_data_tool_changed(tool_id: String) -> void:
	var tid = tool_id.to_lower()
	if tid == "move": tid = "select"
	_active_tool = tid
	_sync_active_tool()

func _sync_active_tool() -> void:
	var active_sb := StyleBoxFlat.new()
	active_sb.bg_color = Color(0.84, 0.84, 0.88, 1.0)
	active_sb.set_corner_radius_all(6)
	active_sb.content_margin_left = 4
	active_sb.content_margin_right = 4
	active_sb.content_margin_top = 2
	active_sb.content_margin_bottom = 2

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = Color(0, 0, 0, 0)
	normal_sb.set_corner_radius_all(6)

	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(0.91, 0.91, 0.94, 1.0)
	hover_sb.set_corner_radius_all(6)

	for tid in _buttons:
		var btn: Button = _buttons[tid]
		btn.add_theme_stylebox_override("hover", hover_sb)
		if tid == _active_tool:
			btn.add_theme_stylebox_override("normal", active_sb)
			btn.add_theme_color_override("font_color", Color(0.08, 0.08, 0.10, 1.0))
			btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			btn.add_theme_stylebox_override("normal", normal_sb)
			btn.add_theme_color_override("font_color", Color(0.38, 0.38, 0.42, 1.0))
			btn.modulate = Color(0.9, 0.9, 0.92, 1.0)

func _sync_zoom_from_canvas() -> void:
	var c = _find_canvas()
	if is_instance_valid(c) and "zoom_percentage" in c:
		var cur = round(c.zoom_percentage)
		if cur != _last_synced_zoom:
			_last_synced_zoom = cur
			if is_instance_valid(lbl_zoom):
				lbl_zoom.text = "%d%%" % int(cur)

func _on_zoom_out_pressed() -> void:
	var c = _find_canvas()
	if is_instance_valid(c):
		if c.has_method("zoom_at_point") and is_instance_valid(c.camera):
			c.zoom_at_point(0.8, c.camera.position)
		elif "zoom_percentage" in c:
			c.zoom_percentage = clamp(c.zoom_percentage - 25.0, 10.0, 5000.0)
	_sync_zoom_from_canvas()

func _on_zoom_in_pressed() -> void:
	var c = _find_canvas()
	if is_instance_valid(c):
		if c.has_method("zoom_at_point") and is_instance_valid(c.camera):
			c.zoom_at_point(1.25, c.camera.position)
		elif "zoom_percentage" in c:
			c.zoom_percentage = clamp(c.zoom_percentage + 25.0, 10.0, 5000.0)
	_sync_zoom_from_canvas()

func _on_zoom_label_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var c = _find_canvas()
		if is_instance_valid(c):
			if c.has_method("_reset_camera"):
				c._reset_camera()
			elif "zoom_percentage" in c:
				c.zoom_percentage = 100.0
		if is_instance_valid(lbl_zoom):
			lbl_zoom.text = "100%"
		_last_synced_zoom = 100.0
		zoom_changed.emit(100.0)

func set_zoom_percentage(pct: float) -> void:
	var c = _find_canvas()
	if is_instance_valid(c) and "zoom_percentage" in c:
		c.zoom_percentage = pct
	_last_synced_zoom = round(pct)
	if is_instance_valid(lbl_zoom):
		lbl_zoom.text = "%d%%" % int(round(pct))
	zoom_changed.emit(pct)
