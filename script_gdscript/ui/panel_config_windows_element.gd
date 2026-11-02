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
		if is_instance_valid(_grid):
			for c in _grid.get_children():
				if c is Button and not c.is_queued_for_deletion():
					btns.append(c)
		return btns

## UX-22: cuadrícula de tarjetas (miniatura proporcional + nombre + medida),
## como el «Nuevo documento» de los editores profesionales.
const COLUMNS := 3
const PANEL_SIZE := Vector2(452, 560)
const MODULE_ICONS := {"papel": "res://icon/UI/preset_paper.svg", "dispositivos": "res://icon/UI/preset_devices.svg",
	"red_social": "res://icon/UI/preset_social.svg", "logo": "res://icon/UI/preset_logo.svg", "icono": "res://icon/UI/preset_icon.svg"}
var _grid: GridContainer = null
var _orient_glyph: Control = null

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
	var tm0 := get_node_or_null("/root/ThemeManager")
	if tm0 and tm0.has_method("adopt"):
		tm0.adopt(self)   # tema de Vectopen (no el de Godot por defecto)
	_build_layout()
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
	var sb := ProUIStyle.flat(ProUIStyle.col("PANEL_BG"), 12, ProUIStyle.col("BORDER"), 14, 14)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.32 if ProUIStyle.is_dark() else 0.14)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	add_theme_stylebox_override("panel", sb)
	if title_label:
		title_label.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
		title_label.add_theme_font_size_override("font_size", 14)
	for l in find_children("*", "Label", true, false):
		if l == title_label or (is_instance_valid(_grid) and _grid.is_ancestor_of(l)):
			continue
		(l as Label).add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
		(l as Label).add_theme_font_size_override("font_size", 11)
	var icon := find_child("Icon", true, false) as TextureRect
	if icon:
		icon.visible = false
	if btn_close:
		btn_close.text = ""
		btn_close.flat = true
		btn_close.icon = ProUIStyle.icon("res://icon/UI/close.svg", ProUIStyle.col("TEXT_SECONDARY"), 14)
		btn_close.tooltip_text = tr("Cerrar")
		btn_close.custom_minimum_size = Vector2(28, 28)
		btn_close.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "focus"]:
			btn_close.add_theme_stylebox_override(st, ProUIStyle.flat(ProUIStyle.col("BUTTON_HOVER") if st == "hover" else Color(0, 0, 0, 0), 6, Color(0, 0, 0, 0)))
	if search_edit:
		search_edit.placeholder_text = tr("Buscar tamaño (A4, Instagram, 1080…)")
		search_edit.right_icon = ProUIStyle.icon("res://icon/UI/input-search.svg", ProUIStyle.col("TEXT_SECONDARY"), 14)
		search_edit.custom_minimum_size.y = 30
		for k in ["theme_override_styles/normal", "theme_override_styles/focus"]:
			pass
		search_edit.remove_theme_stylebox_override("normal")
		search_edit.remove_theme_stylebox_override("focus")
		search_edit.remove_theme_color_override("font_color")
	for le in [custom_w_edit, custom_h_edit]:
		if le:
			le.remove_theme_stylebox_override("normal")
			le.remove_theme_stylebox_override("focus")
			le.remove_theme_color_override("font_color")
			le.custom_minimum_size = Vector2(76, 28)
			le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if target_option:
		target_option.remove_theme_stylebox_override("normal")
		target_option.remove_theme_color_override("font_color")
	if btn_apply_custom:
		btn_apply_custom.text = tr("Aplicar")
		# Botón principal con los colores del tema: borde de acento y texto
		# normal (en oscuro el acento no da 4,5:1 con texto blanco).
		var acc := ProUIStyle.col("ACCENT")
		for st in ["normal", "hover", "pressed"]:
			var bg: String = {"normal": "BUTTON_BG", "hover": "BUTTON_HOVER", "pressed": "BUTTON_PRESSED"}[st]
			var sbb := ProUIStyle.flat(ProUIStyle.col(bg), 6, acc, 14, 5)
			sbb.set_border_width_all(2)
			btn_apply_custom.add_theme_stylebox_override(st, sbb)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			btn_apply_custom.add_theme_color_override(k, ProUIStyle.col("PANEL_TEXT"))
	var sc := find_child("ScrollContainer", true, false) as Control
	if sc:
		sc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_update_orientation_button()

## Estructura: tamaño fijo, la lista ocupa el alto libre y las tarjetas van
## en una cuadrícula.
func _build_layout() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	var vb := get_node_or_null("MarginContainer/VBoxContainer") as BoxContainer
	if vb:
		vb.add_theme_constant_override("separation", 10)
	var mc := get_node_or_null("MarginContainer") as MarginContainer
	if mc:
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			mc.add_theme_constant_override(side, 2)
	var sc := find_child("ScrollContainer", true, false) as ScrollContainer
	if sc:
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if presets_container and not is_instance_valid(_grid):
		presets_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid = GridContainer.new()
		_grid.name = "PresetsGrid"
		_grid.columns = COLUMNS
		_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_theme_constant_override("h_separation", 8)
		_grid.add_theme_constant_override("v_separation", 8)
		presets_container.add_child(_grid)
	var bar := find_child("ModulesBar", true, false) as BoxContainer
	if bar:
		bar.add_theme_constant_override("separation", 4)
	var cl := find_child("CustomLabel", true, false) as Label
	if cl:
		cl.text = tr("Personalizado")
	var tl := find_child("TargetLabel", true, false) as Label
	if tl:
		tl.text = tr("Aplicar a")
	if title_label:
		title_label.text = tr("Tamaño de página o elemento")
	if btn_orientation:
		btn_orientation.flat = false
		btn_orientation.focus_mode = Control.FOCUS_NONE
		btn_orientation.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		btn_orientation.custom_minimum_size = Vector2(112, 28)
		_orient_glyph = _PageThumb.new()
		_orient_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_orient_glyph.position = Vector2(8, 5)
		_orient_glyph.size = Vector2(18, 18)
		btn_orientation.add_child(_orient_glyph)

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
	var tabs := {"papel": tab_paper, "dispositivos": tab_devices, "red_social": tab_social, "logo": tab_logo, "icono": tab_icon}
	for k in tabs:
		var btn: Button = tabs[k]
		if not btn:
			continue
		var on := String(k) == current_module
		btn.focus_mode = Control.FOCUS_NONE
		btn.expand_icon = false
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size.y = 30
		btn.add_theme_font_size_override("font_size", 11)
		btn.set_meta("pro_icon_path", MODULE_ICONS[k])
		ProUIStyle.style_toggle(btn, on)
		btn.icon = ProUIStyle.icon(MODULE_ICONS[k], ProUIStyle.col("ACCENT") if on else ProUIStyle.col("TEXT_SECONDARY"), 14)

func _toggle_orientation() -> void:
	is_landscape = !is_landscape
	_update_orientation_button()
	_populate_presets()

func _update_orientation_button() -> void:
	if not btn_orientation:
		return
	btn_orientation.text = tr("Girar 90°")
	btn_orientation.tooltip_text = tr("Girar todos los formatos 90° (vertical ↔ horizontal)")
	var on_sb := ProUIStyle.flat(ProUIStyle.col("SURFACE_RAISED"), 6, ProUIStyle.col("ACCENT"), 8, 4)
	btn_orientation.add_theme_stylebox_override("normal", on_sb if is_landscape else ProUIStyle.flat(ProUIStyle.col("BUTTON_BG"), 6, ProUIStyle.col("BORDER"), 8, 4))
	btn_orientation.add_theme_stylebox_override("hover", ProUIStyle.flat(ProUIStyle.col("BUTTON_HOVER"), 6, ProUIStyle.col("BORDER_STRONG"), 8, 4))
	btn_orientation.add_theme_stylebox_override("pressed", ProUIStyle.flat(ProUIStyle.col("BUTTON_PRESSED"), 6, ProUIStyle.col("ACCENT"), 8, 4))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn_orientation.add_theme_color_override(k, ProUIStyle.col("PANEL_TEXT"))
	btn_orientation.add_theme_font_size_override("font_size", 11)
	if is_instance_valid(_orient_glyph):
		_orient_glyph.set("kind", "papel")
		_orient_glyph.set("aspect", 1.414 if not is_landscape else 0.707)
		_orient_glyph.set("small", true)
		_orient_glyph.queue_redraw()

func _on_search_changed(text: String) -> void:
	search_query = text.strip_edges().to_lower()
	_populate_presets()

func _populate_presets() -> void:
	if not presets_container:
		return
	if not is_instance_valid(_grid):
		_build_layout()
	for c in presets_container.get_children():
		if c != _grid:
			presets_container.remove_child(c)
			c.queue_free()
	for c in _grid.get_children():
		_grid.remove_child(c)
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
		empty_lbl.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
		empty_lbl.add_theme_font_size_override("font_size", 11)
		presets_container.add_child(empty_lbl)
		return

	for item in filtered:
		var raw_w: float = float(item["w"])
		var raw_h: float = float(item["h"])
		var final_w: float = raw_w
		var final_h: float = raw_h

		# Cada formato en su orientación natural (un escritorio es apaisado,
		# un A4 vertical); «Girar 90°» los rota todos.
		var natural_land := bool(item.get("landscape", raw_w > raw_h))
		var land := natural_land != is_landscape
		final_w = maxf(raw_w, raw_h) if land else minf(raw_w, raw_h)
		final_h = minf(raw_w, raw_h) if land else maxf(raw_w, raw_h)

		var card := _create_preset_card(item["name"], item["sub"], final_w, final_h)
		_grid.add_child(card)

func _create_preset_card(title: String, subtitle: String, w: float, h: float) -> Button:
	var btn := Button.new()
	btn.name = "Preset_" + title.validate_node_name()
	btn.custom_minimum_size = Vector2(0, 128)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "%s
%s" % [title, subtitle]
	var acc := ProUIStyle.col("ACCENT")
	var normal := ProUIStyle.flat(ProUIStyle.col("PANEL_SURFACE"), 8, ProUIStyle.col("BORDER"), 6, 6)
	normal.set_border_width_all(1)
	var hover := ProUIStyle.flat(ProUIStyle.col("BUTTON_HOVER"), 8, acc, 6, 6)
	hover.set_border_width_all(2)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	vb.add_theme_constant_override("separation", 3)
	btn.add_child(vb)
	var thumb := _PageThumb.new()
	thumb.name = "Thumb"
	thumb.kind = current_module
	thumb.aspect = h / maxf(w, 1.0)
	thumb.custom_minimum_size = Vector2(0, 66)
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(thumb)
	var lt := Label.new()
	lt.text = title
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lt.add_theme_font_size_override("font_size", 11)
	lt.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
	lt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(lt)
	var ls := Label.new()
	var phys := subtitle.split("·")[0].strip_edges()
	ls.text = phys if current_module == "papel" else "%d × %d px" % [int(w), int(h)]
	ls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ls.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ls.add_theme_font_size_override("font_size", 10)
	ls.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
	ls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(ls)
	btn.pressed.connect(func(): apply_preset(w, h, title))
	return btn

## Miniatura proporcional del formato (hoja, pantalla, móvil, icono…).
class _PageThumb extends Control:
	var kind := "papel"
	var aspect := 1.414          # alto / ancho
	var small := false
	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size).grow(-2.0 if small else -4.0)
		if box.size.x <= 2.0 or box.size.y <= 2.0:
			return
		var w := box.size.x
		var h := w * aspect
		if h > box.size.y:
			h = box.size.y
			w = h / maxf(aspect, 0.001)
		var r := Rect2(box.get_center() - Vector2(w, h) * 0.5, Vector2(w, h))
		var line := ProUIStyle.col("TEXT_SECONDARY")
		var paper := ProUIStyle.col("INPUT_BG")
		var acc := ProUIStyle.col("ACCENT")
		var shadow := Color(0, 0, 0, 0.10)
		match kind:
			"dispositivos":
				var rad := minf(w, h) * (0.16 if aspect > 1.0 else 0.06)
				var sb := StyleBoxFlat.new()
				sb.bg_color = paper
				sb.border_color = line
				sb.set_border_width_all(2)
				sb.set_corner_radius_all(int(rad))
				draw_style_box(sb, r)
				if aspect < 1.0 and not small:   # pantalla con pie
					draw_line(Vector2(r.get_center().x, r.end.y), Vector2(r.get_center().x, r.end.y + 4), line, 2.0)
					draw_line(Vector2(r.get_center().x - 8, r.end.y + 4), Vector2(r.get_center().x + 8, r.end.y + 4), line, 2.0)
			"red_social":
				var sb2 := StyleBoxFlat.new()
				sb2.bg_color = paper
				sb2.border_color = line
				sb2.set_border_width_all(1)
				sb2.set_corner_radius_all(4)
				draw_style_box(sb2, r)
				var band := Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, r.size.y * 0.55))
				draw_rect(band, Color(acc, 0.35))
			"logo", "icono":
				var sb3 := StyleBoxFlat.new()
				sb3.bg_color = paper
				sb3.border_color = line
				sb3.set_border_width_all(1)
				sb3.set_corner_radius_all(int(minf(w, h) * 0.22) if kind == "icono" else 3)
				draw_style_box(sb3, r)
				draw_circle(r.get_center(), minf(w, h) * 0.22, Color(acc, 0.55))
			_:
				# Hoja con sombra y esquina doblada.
				draw_rect(Rect2(r.position + Vector2(2, 2), r.size), shadow)
				var fold := minf(w, h) * 0.2
				var pts := PackedVector2Array([r.position, Vector2(r.end.x - fold, r.position.y),
					Vector2(r.end.x, r.position.y + fold), r.end, Vector2(r.position.x, r.end.y)])
				draw_colored_polygon(pts, paper)
				pts.append(r.position)
				draw_polyline(pts, line, 1.0, true)
				draw_polyline(PackedVector2Array([Vector2(r.end.x - fold, r.position.y), Vector2(r.end.x - fold, r.position.y + fold), Vector2(r.end.x, r.position.y + fold)]), line, 1.0, true)
				if not small:
					for i in 3:
						var yy := r.position.y + h * (0.35 + i * 0.14)
						draw_line(Vector2(r.position.x + w * 0.18, yy), Vector2(r.end.x - w * 0.18, yy), Color(line, 0.35), 1.0)

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
