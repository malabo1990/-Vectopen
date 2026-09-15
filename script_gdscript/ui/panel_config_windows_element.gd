# =============================================================================
# RUTA: res://script_gdscript/ui/panel_config_windows_element.gd
# Panel de Configuración de Tamaño de Página y Elementos (Presets Profesionales).
# Módulos: Papel, Dispositivos, Red Social, Logo, Icono.
# =============================================================================
extends PanelContainer
class_name PanelConfigWindowsElement

signal size_applied(w: float, h: float, preset_name: String)
signal closed()

@export var title_label: Label
@export var btn_close: Button
@export var btn_orientation: Button
@export var target_option: OptionButton
@export var tab_paper: Button
@export var tab_devices: Button
@export var tab_social: Button
@export var tab_logo: Button
@export var tab_icon: Button
@export var search_edit: LineEdit
@export var presets_container: VBoxContainer
@export var custom_w_edit: LineEdit
@export var custom_h_edit: LineEdit
@export var btn_apply_custom: Button

var current_module: String = "papel"
var is_landscape: bool = false
var is_horizontal: bool:
	get: return is_landscape
	set(v): is_landscape = v

var preset_buttons: Array[Button]:
	get:
		var btns: Array[Button] = []
		if presets_container:
			for c in presets_container.get_children():
				if c is Button and not c.is_queued_for_deletion():
					btns.append(c)
		return btns

var target_mode: int = 0 # 0 = Auto, 1 = Solo Elemento, 2 = Solo Página/Artboard
var search_query: String = ""

func switch_module(mod_name: String) -> void:
	_select_module(mod_name)

func toggle_orientation() -> void:
	_toggle_orientation()


const PRESETS := {
	"papel": [
		{"name": "A4", "sub": "210 × 297 mm · Impresión estándar", "w": 794, "h": 1123, "landscape": false},
		{"name": "A3", "sub": "297 × 420 mm · Formato grande", "w": 1123, "h": 1587, "landscape": false},
		{"name": "A5", "sub": "148 × 210 mm · Cuaderno / Folleto", "w": 559, "h": 794, "landscape": false},
		{"name": "Carta (Letter)", "sub": "8.5 × 11 in · Estándar USA", "w": 816, "h": 1056, "landscape": false},
		{"name": "Legal (Oficio)", "sub": "8.5 × 14 in · Documento legal", "w": 816, "h": 1344, "landscape": false},
		{"name": "Tabloide (Tabloid)", "sub": "11 × 17 in · Póster / Plano", "w": 1056, "h": 1632, "landscape": false},
		{"name": "B5", "sub": "176 × 250 mm · Editorial / Libro", "w": 665, "h": 945, "landscape": false},
		{"name": "Tarjeta de Visita", "sub": "85 × 50 mm · Business Card", "w": 321, "h": 189, "landscape": true},
	],
	"dispositivos": [
		{"name": "Desktop Full HD", "sub": "1920 × 1080 px · 16:9 Estándar", "w": 1920, "h": 1080, "landscape": true},
		{"name": "Desktop 4K UHD", "sub": "3840 × 2160 px · 16:9 Ultra HD", "w": 3840, "h": 2160, "landscape": true},
		{"name": "MacBook Pro 16\"", "sub": "1728 × 1117 px · Retina Display", "w": 1728, "h": 1117, "landscape": true},
		{"name": "MacBook Air 13\"", "sub": "1280 × 832 px · Retina Display", "w": 1280, "h": 832, "landscape": true},
		{"name": "iPhone 16 / 15 Pro", "sub": "393 × 852 px · Super Retina XDR", "w": 393, "h": 852, "landscape": false},
		{"name": "iPhone 16 Pro Max", "sub": "430 × 932 px · Dynamic Island", "w": 430, "h": 932, "landscape": false},
		{"name": "iPhone SE", "sub": "375 × 667 px · Pantalla compacta", "w": 375, "h": 667, "landscape": false},
		{"name": "iPad Pro 12.9\"", "sub": "1024 × 1366 px · Liquid Retina", "w": 1024, "h": 1366, "landscape": false},
		{"name": "iPad Air / Mini", "sub": "820 × 1180 px · Tablet estándar", "w": 820, "h": 1180, "landscape": false},
		{"name": "Android FHD+", "sub": "1080 × 2400 px · 20:9 Pantalla móvil", "w": 1080, "h": 2400, "landscape": false},
		{"name": "Apple Watch 45mm", "sub": "396 × 484 px · Smartwatch OLED", "w": 396, "h": 484, "landscape": false},
	],
	"red_social": [
		{"name": "Instagram Post Cuadrado", "sub": "1080 × 1080 px · 1:1 Feed", "w": 1080, "h": 1080, "landscape": false},
		{"name": "Instagram Story / Reel", "sub": "1080 × 1920 px · 9:16 Vertical", "w": 1080, "h": 1920, "landscape": false},
		{"name": "Instagram Post Retrato", "sub": "1080 × 1350 px · 4:5 Feed", "w": 1080, "h": 1350, "landscape": false},
		{"name": "Twitter / X Post", "sub": "1200 × 675 px · 16:9 Feed Media", "w": 1200, "h": 675, "landscape": true},
		{"name": "Twitter / X Banner", "sub": "1500 × 500 px · 3:1 Cabecera", "w": 1500, "h": 500, "landscape": true},
		{"name": "YouTube Miniatura", "sub": "1280 × 720 px · 16:9 Thumbnail", "w": 1280, "h": 720, "landscape": true},
		{"name": "YouTube Banner", "sub": "2560 × 1440 px · Cabecera Canal", "w": 2560, "h": 1440, "landscape": true},
		{"name": "Facebook Post", "sub": "1200 × 630 px · 1.91:1 Feed", "w": 1200, "h": 630, "landscape": true},
		{"name": "Facebook Portada", "sub": "820 × 312 px · Banner Fanpage", "w": 820, "h": 312, "landscape": true},
		{"name": "TikTok Video", "sub": "1080 × 1920 px · 9:16 Pantalla completa", "w": 1080, "h": 1920, "landscape": false},
		{"name": "LinkedIn Banner", "sub": "1584 × 396 px · 4:1 Portada Empresa", "w": 1584, "h": 396, "landscape": true},
	],
	"logo": [
		{"name": "Logo Cuadrado", "sub": "500 × 500 px · 1:1 Isotipo / Avatar", "w": 500, "h": 500, "landscape": false},
		{"name": "Logo Estándar", "sub": "800 × 400 px · 2:1 Imagotipo", "w": 800, "h": 400, "landscape": true},
		{"name": "Logo Horizontal", "sub": "800 × 200 px · 4:1 Header Web", "w": 800, "h": 200, "landscape": true},
		{"name": "Logo Banner", "sub": "1200 × 400 px · 3:1 Patrocinio", "w": 1200, "h": 400, "landscape": true},
		{"name": "App Icon iOS", "sub": "1024 × 1024 px · App Store Master", "w": 1024, "h": 1024, "landscape": false},
		{"name": "App Icon Android", "sub": "512 × 512 px · Google Play Store", "w": 512, "h": 512, "landscape": false},
		{"name": "Favicon Web HD", "sub": "512 × 512 px · PWA & Navegador", "w": 512, "h": 512, "landscape": false},
		{"name": "Avatar Perfil", "sub": "400 × 400 px · Foto de Cuenta", "w": 400, "h": 400, "landscape": false},
	],
	"icono": [
		{"name": "Icono 16 px", "sub": "16 × 16 px · Micro Favicon", "w": 16, "h": 16, "landscape": false},
		{"name": "Icono 24 px", "sub": "24 × 24 px · Barra de herramientas", "w": 24, "h": 24, "landscape": false},
		{"name": "Icono 32 px", "sub": "32 × 32 px · Botón de interfaz", "w": 32, "h": 32, "landscape": false},
		{"name": "Icono 48 px", "sub": "48 × 48 px · Botón táctil grande", "w": 48, "h": 48, "landscape": false},
		{"name": "Icono 64 px", "sub": "64 × 64 px · Dock / App desktop", "w": 64, "h": 64, "landscape": false},
		{"name": "Icono 128 px", "sub": "128 × 128 px · Diálogo / Alerta", "w": 128, "h": 128, "landscape": false},
		{"name": "Icono 256 px", "sub": "256 × 256 px · Retina HD", "w": 256, "h": 256, "landscape": false},
		{"name": "Icono Master 512 px", "sub": "512 × 512 px · Vectorial Master", "w": 512, "h": 512, "landscape": false},
	]
}

func _ready() -> void:
	_conectar_senales()
	_configurar_target_dropdown()
	_update_orientation_button()
	_update_tab_styles()
	_populate_presets()

	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.connect(_on_theme_changed)
	_apply_theme_colors()

func _on_theme_changed(_mode: String) -> void:
	_apply_theme_colors()
	_update_tab_styles()
	_populate_presets()

func _apply_theme_colors() -> void:
	var bg_col := Color(0.14, 0.15, 0.18, 0.98)
	var border_col := Color(0.28, 0.3, 0.36, 1.0)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm:
		var S = tm.Slot
		bg_col = tm.get_color(S.PANEL_BG)
		border_col = tm.get_color(S.BORDER)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", sb)

func _conectar_senales() -> void:
	if btn_close and not btn_close.pressed.is_connected(close):
		btn_close.pressed.connect(close)
	if btn_orientation and not btn_orientation.pressed.is_connected(_toggle_orientation):
		btn_orientation.pressed.connect(_toggle_orientation)
	if target_option and not target_option.item_selected.is_connected(_on_target_changed):
		target_option.item_selected.connect(_on_target_changed)

	if tab_paper and not tab_paper.pressed.is_connected(_select_module.bind("papel")):
		tab_paper.pressed.connect(_select_module.bind("papel"))
	if tab_devices and not tab_devices.pressed.is_connected(_select_module.bind("dispositivos")):
		tab_devices.pressed.connect(_select_module.bind("dispositivos"))
	if tab_social and not tab_social.pressed.is_connected(_select_module.bind("red_social")):
		tab_social.pressed.connect(_select_module.bind("red_social"))
	if tab_logo and not tab_logo.pressed.is_connected(_select_module.bind("logo")):
		tab_logo.pressed.connect(_select_module.bind("logo"))
	if tab_icon and not tab_icon.pressed.is_connected(_select_module.bind("icono")):
		tab_icon.pressed.connect(_select_module.bind("icono"))

	if search_edit and not search_edit.text_changed.is_connected(_on_search_changed):
		search_edit.text_changed.connect(_on_search_changed)

	if btn_apply_custom and not btn_apply_custom.pressed.is_connected(_apply_custom_size):
		btn_apply_custom.pressed.connect(_apply_custom_size)
	if custom_w_edit and not custom_w_edit.text_submitted.is_connected(func(_t): _apply_custom_size()):
		custom_w_edit.text_submitted.connect(func(_t): _apply_custom_size())
	if custom_h_edit and not custom_h_edit.text_submitted.is_connected(func(_t): _apply_custom_size()):
		custom_h_edit.text_submitted.connect(func(_t): _apply_custom_size())

func _configurar_target_dropdown() -> void:
	if not target_option:
		return
	target_option.clear()
	target_option.add_item("Auto (Selección / Página)", 0)
	target_option.add_item("Solo Elemento(s)", 1)
	target_option.add_item("Solo Página / Artboard", 2)
	target_option.select(target_mode)

func _on_target_changed(idx: int) -> void:
	target_mode = idx

func _select_module(mod_name: String) -> void:
	current_module = mod_name
	_update_tab_styles()
	_populate_presets()

func _update_tab_styles() -> void:
	var tabs := {
		"papel": tab_paper,
		"dispositivos": tab_devices,
		"red_social": tab_social,
		"logo": tab_logo,
		"icono": tab_icon,
	}

	var active_col := Color("0a84ff")
	var tm := get_node_or_null("/root/ThemeManager")
	if tm:
		active_col = tm.get_color(tm.Slot.ACCENT)

	for k in tabs:
		var btn: Button = tabs[k]
		if not btn:
			continue
		var is_active: bool = (String(k) == current_module)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(5)
		if is_active:
			sb.bg_color = active_col
			sb.border_color = active_col.lightened(0.2)
			sb.set_border_width_all(1)
			btn.add_theme_color_override("font_color", Color.WHITE)
			btn.add_theme_color_override("icon_normal_color", Color.WHITE)
		else:
			sb.bg_color = Color(1.0, 1.0, 1.0, 0.08)
			sb.border_color = Color(1.0, 1.0, 1.0, 0.12)
			sb.set_border_width_all(1)
			btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1.0))
			btn.add_theme_color_override("icon_normal_color", Color(0.85, 0.85, 0.88, 1.0))
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)

func _toggle_orientation() -> void:
	is_landscape = !is_landscape
	_update_orientation_button()
	_populate_presets()

func _update_orientation_button() -> void:
	if not btn_orientation:
		return
	if is_landscape:
		btn_orientation.text = "↔ Horizontal"
		btn_orientation.tooltip_text = "Orientación horizontal activa (Ancho > Alto)"
	else:
		btn_orientation.text = "↕ Vertical"
		btn_orientation.tooltip_text = "Orientación vertical activa (Alto > Ancho)"

func _on_search_changed(text: String) -> void:
	search_query = text.strip_edges().to_lower()
	_populate_presets()

func _populate_presets() -> void:
	if not presets_container:
		return

	for c in presets_container.get_children():
		presets_container.remove_child(c)
		c.queue_free()

	var list: Array = PRESETS.get(current_module, [])
	var filtered: Array = []
	for p in list:
		if search_query == "":
			filtered.append(p)
		else:
			var n: String = String(p.get("name", "")).to_lower()
			var s: String = String(p.get("sub", "")).to_lower()
			if search_query in n or search_query in s:
				filtered.append(p)

	if filtered.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No se encontraron medidas coincidentes."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65, 1.0))
		empty_lbl.add_theme_font_size_override("font_size", 11)
		presets_container.add_child(empty_lbl)
		return

	for item in filtered:
		var raw_w: float = float(item["w"])
		var raw_h: float = float(item["h"])
		var final_w: float = raw_w
		var final_h: float = raw_h

		if is_landscape:
			final_w = maxf(raw_w, raw_h)
			final_h = minf(raw_w, raw_h)
		else:
			final_w = minf(raw_w, raw_h)
			final_h = maxf(raw_w, raw_h)

		var card := _create_preset_card(item["name"], item["sub"], final_w, final_h)
		presets_container.add_child(card)

func _create_preset_card(title: String, subtitle: String, w: float, h: float) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 44)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	sb_n.border_color = Color(1.0, 1.0, 1.0, 0.1)
	sb_n.set_border_width_all(1)
	sb_n.set_corner_radius_all(6)
	sb_n.set_content_margin_all(6)

	var sb_h := StyleBoxFlat.new()
	sb_h.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	sb_h.border_color = Color("0a84ff")
	sb_h.set_border_width_all(1)
	sb_h.set_corner_radius_all(6)
	sb_h.set_content_margin_all(6)

	btn.add_theme_stylebox_override("normal", sb_n)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_h)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 6)
	btn.add_child(hbox)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 1)
	hbox.add_child(vbox)

	var lbl_title := Label.new()
	lbl_title.text = title
	lbl_title.add_theme_font_size_override("font_size", 11)
	lbl_title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(lbl_title)

	var lbl_sub := Label.new()
	lbl_sub.text = subtitle
	lbl_sub.add_theme_font_size_override("font_size", 9)
	lbl_sub.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78, 1.0))
	vbox.add_child(lbl_sub)

	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_sb := StyleBoxFlat.new()
	pill_sb.bg_color = Color(0, 0, 0, 0.25)
	pill_sb.set_corner_radius_all(4)
	pill_sb.content_margin_left = 6
	pill_sb.content_margin_right = 6
	pill_sb.content_margin_top = 2
	pill_sb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", pill_sb)

	var lbl_dim := Label.new()
	lbl_dim.text = "%d × %d" % [int(w), int(h)]
	lbl_dim.add_theme_font_size_override("font_size", 10)
	lbl_dim.add_theme_color_override("font_color", Color("0a84ff"))
	pill.add_child(lbl_dim)
	hbox.add_child(pill)

	btn.pressed.connect(func(): apply_preset(w, h, title))
	return btn

func apply_preset(w: float, h: float, preset_name: String) -> void:
	var final_w := w
	var final_h := h

	var ic := get_node_or_null("/root/InspectorCore")
	var has_shape_sel := false
	if ic:
		if ic.has_method("selection"):
			has_shape_sel = not ic.selection().is_empty()
		elif ic.has_method("get_selection"):
			has_shape_sel = not ic.get_selection().is_empty()

	var apply_to_shape := false
	var apply_to_artboard := false

	if target_mode == 1: # Solo Elemento(s)
		apply_to_shape = true
	elif target_mode == 2: # Solo Página / Artboard
		apply_to_artboard = true
	else: # Auto
		if has_shape_sel:
			apply_to_shape = true
		else:
			apply_to_artboard = true

	if apply_to_shape and has_shape_sel and ic:
		ic.apply_multi({"width": final_w, "height": final_h}, "Preset de tamaño · " + preset_name)
	elif apply_to_artboard:
		_apply_to_active_artboard(final_w, final_h, preset_name)
	elif has_shape_sel and ic:
		ic.apply_multi({"width": final_w, "height": final_h}, "Preset de tamaño · " + preset_name)
	else:
		_apply_to_active_artboard(final_w, final_h, preset_name)

	# Actualizar campos de tamaño personalizado
	if custom_w_edit: custom_w_edit.text = str(int(final_w))
	if custom_h_edit: custom_h_edit.text = str(int(final_h))

	size_applied.emit(final_w, final_h, preset_name)

func _apply_to_active_artboard(w: float, h: float, preset_name: String) -> void:
	if not is_inside_tree() or not get_tree():
		return
	var ab_list := get_tree().get_nodes_in_group("artboards")
	if ab_list.is_empty():
		return
	var target_ab: Node2D = null
	for ab in ab_list:
		if ab is Node2D and bool(ab.get("is_selected")):
			target_ab = ab
			break
	if target_ab == null and ab_list.size() > 0:
		target_ab = ab_list[0] as Node2D

	if target_ab and "artboard_size" in target_ab:
		var prev_size: Vector2 = target_ab.get("artboard_size")
		var new_size := Vector2(w, h)
		var hm := get_node_or_null("/root/HistoryManager")
		if hm and hm.has_method("register_action"):
			hm.register_action("Tamaño Artboard · " + preset_name)
			hm.add_do(func(): target_ab.set("artboard_size", new_size))
			hm.add_undo(func(): target_ab.set("artboard_size", prev_size))
			hm.commit()
		target_ab.set("artboard_size", new_size)

func _apply_custom_size() -> void:
	if not custom_w_edit or not custom_h_edit:
		return
	var w := float(custom_w_edit.text)
	var h := float(custom_h_edit.text)
	if w > 0.0 and h > 0.0:
		apply_preset(w, h, "Personalizado")

func close() -> void:
	visible = false
	closed.emit()
