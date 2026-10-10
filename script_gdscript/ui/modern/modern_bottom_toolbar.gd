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
var _text_popup: PopupMenu = null

func _ready() -> void:
	_setup_styles()
	_build_ui()
	_connect_events()
	_sync_active_tool()
	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_mode):
			_setup_styles()
			_sync_active_tool()
		)

func _process(_delta: float) -> void:
	_sync_zoom_from_canvas()

func _setup_styles() -> void:
	custom_minimum_size = Vector2(400, 44)
	
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var bg_col: Color = tm.get_color(S.PANEL_SURFACE) if (tm and S) else Color(0.97, 0.97, 0.98, 0.98)
	var border_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color(0.86, 0.86, 0.89, 0.95)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.set_border_width_all(1)
	sb.border_color = border_col
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.28) if bg_col.get_luminance() < 0.5 else Color(0, 0, 0, 0.08)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	add_theme_stylebox_override("panel", sb)

	if is_instance_valid(lbl_zoom):
		var text_col: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color(0.18, 0.18, 0.22, 1.0)
		var chip_bg: Color = tm.get_color(S.INPUT_BG) if (tm and S) else Color(0.93, 0.93, 0.95, 0.8)
		lbl_zoom.add_theme_color_override("font_color", text_col)
		var lsb := StyleBoxFlat.new()
		lsb.bg_color = chip_bg
		lsb.set_corner_radius_all(6)
		lsb.content_margin_left = 4
		lsb.content_margin_right = 4
		lbl_zoom.add_theme_stylebox_override("normal", lsb)

	if is_instance_valid(btn_zoom_out):
		_style_zoom_btn(btn_zoom_out)
	if is_instance_valid(btn_zoom_in):
		_style_zoom_btn(btn_zoom_in)

func _build_ui() -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(hbox)

	var tools := [
		{"name": "select", "label": "↖", "tooltip": "Select and Move (V)", "icon": "res://icon/UI/navigation.svg"},
		{"name": "artboard", "label": "⛶", "tooltip": "Frame / Artboard (F)", "icon": "res://icon/UI/frame-alt.svg"},
		{"name": "rectangle", "label": "□", "tooltip": "Rectangle (R)", "icon": "res://icon/UI/square.svg"},
		{"name": "ellipse", "label": "○", "tooltip": "Ellipse (O)", "icon": "res://icon/UI/circle-spark.svg"},
		{"name": "star", "label": "★", "tooltip": "Star (S)", "icon": "res://icon/UI/star.svg"},
		{"name": "bezier", "label": "∿", "tooltip": "Bézier Curve (D)", "icon": "res://icon/UI/design_nodoblack.svg"},
		{"name": "brush", "label": "🖌", "tooltip": "Brush (B)", "icon": "res://icon/UI/draw.svg"},
		{"name": "text", "label": "T", "tooltip": "Text (T)", "icon": "res://icon/UI/text-square.svg"},
		{"name": "model3d", "label": "3D", "tooltip": "Import 3D Model (.glb / .gltf)", "icon": "res://icon/UI/cube.svg"}
	]

	for t in tools:
		var btn := _create_tool_button(t["name"], t["label"], t["tooltip"], t["icon"])
		hbox.add_child(btn)
		_buttons[t["name"]] = btn

	# Plain gap between tools and zoom: a hard divider line is visual noise
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(gap)

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
	lbl_zoom.tooltip_text = tr("Arrastra para hacer zoom · Doble clic: 100%")
	lbl_zoom.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl_zoom.mouse_default_cursor_shape = Control.CURSOR_HSIZE

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
	btn.tooltip_text = tr(tooltip)
	btn.set_meta("tooltip_key", tooltip)
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 13)
	_style_zoom_btn(btn)
	return btn

func _style_zoom_btn(btn: Button) -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var text_col: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color(0.18, 0.18, 0.22, 1.0)
	var chip_bg: Color = tm.get_color(S.INPUT_BG) if (tm and S) else Color(0.93, 0.93, 0.95, 0.8)
	var hov_bg: Color = tm.get_color(S.BUTTON_HOVER) if (tm and S) else Color(0.88, 0.88, 0.91, 1.0)
	var prs_bg: Color = tm.get_color(S.BUTTON_PRESSED) if (tm and S) else Color(0.82, 0.82, 0.86, 1.0)

	var norm_sb := StyleBoxFlat.new()
	norm_sb.bg_color = chip_bg
	norm_sb.set_corner_radius_all(6)

	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = hov_bg
	hover_sb.set_corner_radius_all(6)

	var press_sb := StyleBoxFlat.new()
	press_sb.bg_color = prs_bg
	press_sb.set_corner_radius_all(6)

	btn.add_theme_stylebox_override("normal", norm_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", press_sb)
	btn.add_theme_color_override("font_color", text_col)
	btn.add_theme_color_override("font_hover_color", text_col)

func _create_tool_button(tool_id: String, fallback_label: String, tooltip: String, icon_path: String) -> Button:
	var btn := Button.new()
	btn.tooltip_text = tr(tooltip)
	btn.set_meta("tooltip_key", tooltip)
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(32, 28)

	if ResourceLoader.exists(icon_path):
		btn.icon = _icon_blanco(icon_path)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.expand_icon = false
	else:
		btn.text = fallback_label
		btn.add_theme_font_size_override("font_size", 12)

	btn.pressed.connect(func(): _on_tool_button_pressed(tool_id))
	if tool_id == "text":
		btn.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				_show_text_options_menu(btn)
		)
	return btn

func _show_text_options_menu(anchor_btn: Button) -> void:
	if not is_instance_valid(_text_popup):
		_text_popup = PopupMenu.new()
		_text_popup.add_icon_item(_icon_blanco("res://icon/UI/text-square.svg"), tr("Texto artístico (T)"), 0)
		_text_popup.add_icon_item(_icon_blanco("res://icon/UI/TEXTO-PARRAFO.svg"), tr("Texto de párrafo"), 1)
		_text_popup.id_pressed.connect(func(id: int):
			if id == 0:
				_select_text_subtool("text")
			elif id == 1:
				_select_text_subtool("paragraph")
		)
		add_child(_text_popup)
	var pos: Vector2 = anchor_btn.global_position + Vector2(0, -65)
	_text_popup.position = Vector2i(int(pos.x), int(pos.y))
	_text_popup.popup()

func _select_text_subtool(sub_id: String) -> void:
	_update_text_tool_button(sub_id)
	_active_tool = sub_id
	_sync_active_tool()
	tool_selected.emit(sub_id)
	var c = _find_canvas()
	if is_instance_valid(c) and c.has_method("switch_tool"):
		c.switch_tool(sub_id)

func _update_text_tool_button(sub_id: String) -> void:
	if not _buttons.has("text"):
		return
	var btn: Button = _buttons["text"]
	if sub_id == "paragraph":
		btn.icon = _icon_blanco("res://icon/UI/TEXTO-PARRAFO.svg")
		btn.tooltip_text = tr("Texto de párrafo (clic para conmutar a texto artístico)")
	else:
		btn.icon = _icon_blanco("res://icon/UI/text-square.svg")
		btn.tooltip_text = tr("Texto artístico (T) (clic para conmutar a texto de párrafo)")

## _sync_active_tool tiñe cada botón con `btn.modulate` (icon_primary /
## icon_muted según el tema) — esos SVG traen stroke #000000 fijo, y negro ×
## cualquier color de modulate sigue dando negro, así que el icono no se
## puede aclarar en ningún preset. Mismo bug y mismo arreglo que
## layers_system.gd::_icon_blanco: forzar cada píxel opaco a blanco antes de
## crear la textura, para que el modulate sí pueda teñirlo.
static var _icon_cache: Dictionary = {}
static func _icon_blanco(path: String) -> Texture2D:
	if _icon_cache.has(path):
		return _icon_cache[path]
	var src: Texture2D = load(path)
	var tex: Texture2D = src
	if src:
		var img := src.get_image()
		if img:
			img = img.duplicate()
			img.resize(18, 18, Image.INTERPOLATE_LANCZOS)
			img.convert(Image.FORMAT_RGBA8)
			for y in img.get_height():
				for x in img.get_width():
					var a := img.get_pixel(x, y).a
					if a > 0.0:
						img.set_pixel(x, y, Color(1, 1, 1, a))
			tex = ImageTexture.create_from_image(img)
	_icon_cache[path] = tex
	return tex

func _connect_events() -> void:
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("data_tool_changed") and not ge.data_tool_changed.is_connected(_on_data_tool_changed):
		ge.data_tool_changed.connect(_on_data_tool_changed)

	var lm = get_node_or_null("/root/LanguageManager")
	if lm and lm.has_signal("language_changed"):
		lm.language_changed.connect(_on_language_changed)

func _on_language_changed(_locale: String) -> void:
	for b in find_children("", "Button", true, false):
		if b.has_meta("tooltip_key"):
			b.tooltip_text = tr(String(b.get_meta("tooltip_key")))

func _find_canvas():
	if is_instance_valid(_canvas):
		return _canvas
	if get_tree():
		_canvas = get_tree().get_first_node_in_group("_vectopen_canvas")
	return _canvas

func _on_tool_button_pressed(tool_id: String) -> void:
	if tool_id == "model3d":
		var im = get_node_or_null("/root/ImportExportManager")
		if is_instance_valid(im) and im.has_method("import_3d_model"):
			im.import_3d_model()
		return

	if tool_id == "text":
		if _active_tool == "text":
			tool_id = "paragraph"
		elif _active_tool == "paragraph":
			tool_id = "text"
		_update_text_tool_button(tool_id)

	if tool_id == "bezier":
		var ge = get_node_or_null("/root/GlobalEvents")
		if is_instance_valid(ge) and ge.has_method("emit_safe"):
			ge.emit_safe("request_bezier_panel")
	elif tool_id == "brush":
		var ge = get_node_or_null("/root/GlobalEvents")
		if is_instance_valid(ge) and ge.has_method("emit_safe"):
			ge.emit_safe("request_brush_panel")

	_active_tool = tool_id
	_sync_active_tool()
	tool_selected.emit(tool_id)

	var c = _find_canvas()
	if is_instance_valid(c) and c.has_method("switch_tool"):
		c.switch_tool(tool_id)

func _on_data_tool_changed(tool_id: String) -> void:
	var tid = tool_id.to_lower()
	if tid == "move": tid = "select"
	if tid == "text" or tid == "paragraph":
		_update_text_tool_button(tid)
	_active_tool = tid
	_sync_active_tool()

func _sync_active_tool() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var active_bg: Color = tm.get_color(S.SURFACE_RAISED) if (tm and S) else Color(0.84, 0.84, 0.88, 1.0)
	var hov_bg: Color = tm.get_color(S.BUTTON_HOVER) if (tm and S) else Color(0.91, 0.91, 0.94, 1.0)
	var active_text: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color(0.08, 0.08, 0.10, 1.0)
	var _inactive_text: Color = tm.get_color(S.TEXT_SECONDARY) if (tm and S) else Color(0.38, 0.38, 0.42, 1.0)
	var icon_primary: Color = tm.get_color(S.ICON_PRIMARY) if (tm and S) else Color.WHITE
	var _icon_muted: Color = tm.get_color(S.ICON_MUTED) if (tm and S) else Color(0.7, 0.7, 0.7)
	var border_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color(0.8, 0.8, 0.8)

	var active_sb := StyleBoxFlat.new()
	active_sb.bg_color = active_bg
	active_sb.border_color = border_col
	active_sb.set_border_width_all(1)
	active_sb.set_corner_radius_all(6)
	active_sb.content_margin_left = 4
	active_sb.content_margin_right = 4
	active_sb.content_margin_top = 2
	active_sb.content_margin_bottom = 2

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = Color(0, 0, 0, 0)
	normal_sb.set_corner_radius_all(6)

	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = hov_bg
	hover_sb.set_corner_radius_all(6)

	for tid in _buttons:
		var btn: Button = _buttons[tid]
		btn.add_theme_stylebox_override("hover", hover_sb)
		btn.modulate = Color.WHITE
		var is_active: bool = (tid == _active_tool) or (tid == "text" and (_active_tool == "text" or _active_tool == "paragraph"))
		if is_active:
			btn.add_theme_stylebox_override("normal", active_sb)
			btn.add_theme_color_override("font_color", active_text)
			btn.add_theme_color_override("icon_normal_color", active_text)
			btn.add_theme_color_override("icon_hover_color", active_text)
			btn.add_theme_color_override("icon_pressed_color", active_text)
			btn.add_theme_color_override("icon_focus_color", icon_primary)
		else:
			btn.add_theme_stylebox_override("normal", normal_sb)
			# Inactive tools keep full icon contrast (low-vision friendly);
			# the active one is told apart by its raised chip instead.
			btn.add_theme_color_override("font_color", active_text)
			btn.add_theme_color_override("icon_normal_color", icon_primary)
			btn.add_theme_color_override("icon_hover_color", active_text)
			btn.add_theme_color_override("icon_pressed_color", active_text)
			btn.add_theme_color_override("icon_focus_color", icon_primary)

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

const ZOOM_DRAG_SENSITIVITY := 0.006  # zoom factor per pixel dragged (exponential)
var _zoom_dragging: bool = false

## Single clicks do nothing (too easy to trigger by accident): double-click
## resets to 100%, and dragging left/right zooms smoothly around the view center.
func _on_zoom_label_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			_zoom_dragging = false
			_reset_zoom()
			accept_event()
			return
		_zoom_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _zoom_dragging:
		if absf(event.relative.x) > 0.0:
			_zoom_by_factor(exp(event.relative.x * ZOOM_DRAG_SENSITIVITY))
		accept_event()

func _zoom_by_factor(factor: float) -> void:
	var c = _find_canvas()
	if not is_instance_valid(c):
		return
	if c.has_method("zoom_at_point") and "camera" in c and is_instance_valid(c.camera):
		c.zoom_at_point(factor, c.camera.position)
	elif "zoom_percentage" in c:
		c.zoom_percentage = clampf(c.zoom_percentage * factor, 10.0, 5000.0)
	_sync_zoom_from_canvas()

func _reset_zoom() -> void:
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
