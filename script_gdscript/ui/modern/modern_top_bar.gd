# =============================================================================
# VECTOPEN — MODERN TOP BAR
# RUTA: res://script_gdscript/ui/modern/modern_top_bar.gd
# Compact top bar: identity and document status on the left, undo/redo and
# settings on the right. Tool and object parameters live only in the docked
# inspector, so the bar carries no duplicated quick controls.
# =============================================================================
class_name ModernTopBar
extends PanelContainer

signal export_requested()

var logo_rect: TextureRect
var lbl_title: Label
var lbl_doc_name: Label
var lbl_status: Label
var context_container: HBoxContainer
var btn_undo: Button
var btn_redo: Button
var btn_export: Button
var btn_settings: Button
## Mostrar / ocultar el panel Capas · Páginas · Recursos. En Modern ya no hay
## columna de herramientas a la izquierda (donde estaba ese botón).
var btn_layers: Button

## [panel, icono, tooltip, nombre del botón]
## Efectos, filtros, vectorizar y tipografía viven en el INSPECTOR (como
## pidió el usuario: "no tiene sentido en la barra, el inspector ya los
## tiene"). Aquí solo lo que no es una propiedad del objeto.
const FLOATING_BUTTONS := [
	["Panel_PREVIEW", "res://icon/UI/eye.svg", "Vista previa", "BtnPreview"],
]
var mode_selector: Control

var _active_tool_id: String = "select"

func _ready() -> void:
	_setup_styles()
	_build_ui()
	_connect_events()

func _connect_events() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		if not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)

	var ge = get_node_or_null("/root/GlobalEvents")
	if ge:
		if ge.has_signal("data_tool_changed") and not ge.data_tool_changed.is_connected(_on_tool_changed):
			ge.data_tool_changed.connect(_on_tool_changed)
		if ge.has_signal("tool_changed") and not ge.tool_changed.is_connected(_on_tool_changed):
			ge.tool_changed.connect(_on_tool_changed)

func _exit_tree() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.disconnect(_on_theme_changed)

	var ge = get_node_or_null("/root/GlobalEvents")
	if ge:
		if ge.has_signal("data_tool_changed") and ge.data_tool_changed.is_connected(_on_tool_changed):
			ge.data_tool_changed.disconnect(_on_tool_changed)
		if ge.has_signal("tool_changed") and ge.tool_changed.is_connected(_on_tool_changed):
			ge.tool_changed.disconnect(_on_tool_changed)

func _on_theme_changed(_mode: String) -> void:
	_setup_styles()

func _setup_styles() -> void:
	custom_minimum_size = Vector2(0, 36)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var bg_col: Color = tm.get_color(S.PANEL_SURFACE) if (tm and S) else Color(0.98, 0.98, 0.99, 1.0)
	var border_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color(0.88, 0.88, 0.90, 1.0)
	var text_col: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color(0.12, 0.12, 0.14, 1.0)
	var muted_col: Color = tm.get_color(S.TEXT_SECONDARY) if (tm and S) else Color(0.45, 0.45, 0.50, 1.0)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_width_bottom = 1
	sb.border_color = border_col
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

	if is_instance_valid(lbl_title):
		lbl_title.add_theme_color_override("font_color", text_col)
	if is_instance_valid(lbl_doc_name):
		lbl_doc_name.add_theme_color_override("font_color", muted_col)
	if is_instance_valid(btn_undo):
		_style_chip_button(btn_undo)
	if is_instance_valid(btn_redo):
		_style_chip_button(btn_redo)
	if is_instance_valid(btn_export):
		_style_chip_button(btn_export)
	if is_instance_valid(btn_settings):
		_style_chip_button(btn_settings)
		# White stencil: style_button tints it through icon_*_color per theme
		btn_settings.icon = ProUIStyle.icon("res://icon/UI/settings.svg", Color.WHITE, 16)

func _build_ui() -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	# ── LADO IZQUIERDO: LOGO OFICIAL VECTOPEN, MARCA, DOCUMENTO, ESTADO ──
	var left_box := HBoxContainer.new()
	left_box.add_theme_constant_override("separation", 8)
	hbox.add_child(left_box)

	logo_rect = TextureRect.new()
	logo_rect.custom_minimum_size = Vector2(20, 20)
	logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists("res://icon/logo/logo_vectopen.png"):
		logo_rect.texture = load("res://icon/logo/logo_vectopen.png")
	left_box.add_child(logo_rect)

	btn_layers = _create_chip_button("", "Mostrar / ocultar el panel Capas · Páginas · Recursos", Vector2(28, 24))
	btn_layers.name = "BtnLayersToggle"
	if ResourceLoader.exists("res://icon/UI/folder-tree.svg"):
		btn_layers.icon = load("res://icon/UI/folder-tree.svg")
		btn_layers.expand_icon = true
	else:
		btn_layers.text = "☰"
	btn_layers.pressed.connect(_on_layers_toggle_pressed)
	left_box.add_child(btn_layers)

	lbl_title = Label.new()
	lbl_title.text = "Vectopen"
	lbl_title.add_theme_font_size_override("font_size", 12)
	lbl_title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.14, 1.0))
	left_box.add_child(lbl_title)

	var sep_left := VSeparator.new()
	sep_left.add_theme_constant_override("separation", 8)
	left_box.add_child(sep_left)

	lbl_doc_name = Label.new()
	lbl_doc_name.text = "Documento.vectopen"
	lbl_doc_name.add_theme_font_size_override("font_size", 11)
	lbl_doc_name.add_theme_color_override("font_color", Color(0.35, 0.35, 0.38, 1.0))
	left_box.add_child(lbl_doc_name)

	lbl_status = Label.new()
	lbl_status.text = "● Guardado"
	lbl_status.add_theme_font_size_override("font_size", 10)
	lbl_status.add_theme_color_override("font_color", Color(0.2, 0.65, 0.3, 1.0))
	left_box.add_child(lbl_status)

	# Flexible gap (kept as a container for layout compatibility; intentionally empty)
	context_container = HBoxContainer.new()
	context_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(context_container)

	# ── LADO DERECHO: UNDO, REDO ──
	var right_box := HBoxContainer.new()
	right_box.add_theme_constant_override("separation", 6)
	right_box.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_child(right_box)

	# Vista previa (de Smart; no es una propiedad del objeto).
	for spec in FLOATING_BUTTONS:
		var fb := _create_chip_button("", String(spec[2]), Vector2(28, 24))
		fb.name = String(spec[3])
		fb.icon = ModernBottomToolbar._icon_blanco(String(spec[1]))
		fb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fb.set_meta("tooltip_key", String(spec[2]))
		var pname := String(spec[0])
		fb.pressed.connect(func() -> void:
			var ge := get_node_or_null("/root/GlobalEvents")
			if ge and ge.has_signal("request_floating_panel"):
				ge.emit_safe("request_floating_panel", pname))
		right_box.add_child(fb)
	var sep_fl := VSeparator.new()
	right_box.add_child(sep_fl)

	btn_undo = _create_chip_button("↶", "Deshacer (Ctrl+Z)", Vector2(28, 24))
	btn_undo.pressed.connect(_on_undo_pressed)
	right_box.add_child(btn_undo)

	btn_redo = _create_chip_button("↷", "Rehacer (Ctrl+Y / Ctrl+Shift+Z)", Vector2(28, 24))
	btn_redo.pressed.connect(_on_redo_pressed)
	right_box.add_child(btn_redo)

	btn_export = _create_chip_button(tr("Export"), "Exportar diseño (SVG, PNG, JPG)", Vector2(56, 24))
	btn_export.visible = true
	btn_export.pressed.connect(_on_export_pressed)
	right_box.add_child(btn_export)

	# Single entry point to settings in Modern mode (the ruler corner and
	# side-rail buttons were duplicates)
	btn_settings = _create_chip_button("", "Configuración", Vector2(28, 24))
	btn_settings.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn_settings.pressed.connect(_on_settings_pressed)
	right_box.add_child(btn_settings)
	_setup_styles()

	var selector_script = preload("res://script_gdscript/ui/ui_mode_selector.gd")
	mode_selector = selector_script.new()
	mode_selector.visible = false
	add_child(mode_selector)


# ── ACTIVE TOOL TRACKING ──────────────────────────────────────────────────────

func _on_tool_changed(tool_id: String) -> void:
	set_active_tool(tool_id)

func set_active_tool(tool_id: String) -> void:
	var tid: String = tool_id.to_lower()
	if tid == "move":
		tid = "select"
	_active_tool_id = tid

func get_active_tool() -> String:
	return _active_tool_id

func _style_chip_button(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var bg_col: Color = tm.get_color(S.BUTTON_BG) if (tm and S) else Color(0.94, 0.94, 0.96, 0.8)
	var hover_col: Color = tm.get_color(S.BUTTON_HOVER) if (tm and S) else Color(0.90, 0.90, 0.92, 1.0)
	var pressed_col: Color = tm.get_color(S.BUTTON_PRESSED) if (tm and S) else Color(0.85, 0.85, 0.88, 1.0)
	var text_col: Color = tm.get_color(S.BUTTON_TEXT) if (tm and S) else Color(0.2, 0.2, 0.24, 1.0)
	var border_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color(0.85, 0.85, 0.88, 0.5)

	var norm_sb := StyleBoxFlat.new()
	norm_sb.bg_color = bg_col
	norm_sb.border_color = border_col
	norm_sb.set_border_width_all(1)
	norm_sb.set_corner_radius_all(6)
	norm_sb.content_margin_left = 6
	norm_sb.content_margin_right = 6
	norm_sb.content_margin_top = 2
	norm_sb.content_margin_bottom = 2
	btn.add_theme_stylebox_override("normal", norm_sb)

	var hover_sb := norm_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = hover_col
	btn.add_theme_stylebox_override("hover", hover_sb)

	var pressed_sb := norm_sb.duplicate() as StyleBoxFlat
	pressed_sb.bg_color = pressed_col
	btn.add_theme_stylebox_override("pressed", pressed_sb)

	btn.add_theme_color_override("font_color", text_col)
	btn.add_theme_color_override("font_hover_color", text_col)
	btn.add_theme_color_override("font_pressed_color", text_col)
	btn.add_theme_color_override("icon_normal_color", text_col)
	btn.add_theme_color_override("icon_hover_color", text_col)
	btn.add_theme_color_override("icon_pressed_color", text_col)

func _create_chip_button(btn_text: String, tooltip: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = btn_text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 11)
	_style_chip_button(btn)
	return btn

## Hace lo mismo que el botón carpeta de Smart/Pro (button_capas): ese botón
## ya sabe ocultar el panel y encoger el lateral y las reglas.
func _on_layers_toggle_pressed() -> void:
	var b := get_tree().root.find_child("button_capas", true, false) as BaseButton
	if b:
		b.pressed.emit()

func _on_undo_pressed() -> void:
	var hm = get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("undo"):
		hm.undo()

func _on_redo_pressed() -> void:
	var hm = get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("redo"):
		hm.redo()

func _on_settings_pressed() -> void:
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("request_settings_dialog"):
		ge.emit_safe("request_settings_dialog")

func _on_export_pressed() -> void:
	export_requested.emit()
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("request_export_dialog"):
		ge.emit_safe("request_export_dialog")
