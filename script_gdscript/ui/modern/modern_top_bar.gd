# =============================================================================
# VECTOPEN — MODERN TOP BAR (FIGMA UI3 STYLE)
# RUTA: res://script_gdscript/ui/modern/modern_top_bar.gd
# Barra superior compacta con identidad, estado del documento, Undo/Redo y selector
# =============================================================================
class_name ModernTopBar
extends PanelContainer

signal export_requested()

var logo_rect: TextureRect
var lbl_title: Label
var lbl_doc_name: Label
var lbl_status: Label
var btn_undo: Button
var btn_redo: Button
var btn_export: Button
var mode_selector: Control

func _ready() -> void:
	_setup_styles()
	_build_ui()

func _setup_styles() -> void:
	custom_minimum_size = Vector2(0, 36)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.98, 0.99, 1.0)
	sb.border_width_bottom = 1
	sb.border_color = Color(0.88, 0.88, 0.90, 1.0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

func _build_ui() -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	# ── LADO IZQUIERDO: LOGO OFICIAL VECTOPEN, MARCA, DOCUMENTO, ESTADO ──
	var left_box := HBoxContainer.new()
	left_box.add_theme_constant_override("separation", 8)
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_box)

	logo_rect = TextureRect.new()
	logo_rect.custom_minimum_size = Vector2(20, 20)
	logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists("res://icon/logo/logo_vectopen.png"):
		logo_rect.texture = load("res://icon/logo/logo_vectopen.png")
	left_box.add_child(logo_rect)

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

	# ── LADO DERECHO: UNDO, REDO, EXPORT, SELECTOR DE MODO ──
	var right_box := HBoxContainer.new()
	right_box.add_theme_constant_override("separation", 6)
	right_box.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_child(right_box)

	btn_undo = _create_chip_button("↶", "Deshacer (Ctrl+Z)", Vector2(28, 24))
	btn_undo.pressed.connect(_on_undo_pressed)
	right_box.add_child(btn_undo)

	btn_redo = _create_chip_button("↷", "Rehacer (Ctrl+Y / Ctrl+Shift+Z)", Vector2(28, 24))
	btn_redo.pressed.connect(_on_redo_pressed)
	right_box.add_child(btn_redo)

	btn_export = _create_chip_button("Export", "Exportar diseno (SVG, PNG, JPG)", Vector2(56, 24))
	btn_export.visible = false
	btn_export.pressed.connect(_on_export_pressed)
	# Export is consolidated in the DockedInspector Export section (Figma/Penpot style)

	var sep_mode := VSeparator.new()
	sep_mode.add_theme_constant_override("separation", 8)
	right_box.add_child(sep_mode)

	var selector_script = preload("res://script_gdscript/ui/ui_mode_selector.gd")
	mode_selector = selector_script.new()
	mode_selector.compact = true
	right_box.add_child(mode_selector)

func _create_chip_button(btn_text: String, tooltip: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = btn_text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 11)

	var norm_sb := StyleBoxFlat.new()
	norm_sb.bg_color = Color(0.94, 0.94, 0.96, 0.8)
	norm_sb.set_corner_radius_all(6)
	norm_sb.content_margin_left = 6
	norm_sb.content_margin_right = 6
	norm_sb.content_margin_top = 2
	norm_sb.content_margin_bottom = 2

	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(0.88, 0.88, 0.92, 1.0)
	hover_sb.set_corner_radius_all(6)
	hover_sb.content_margin_left = 6
	hover_sb.content_margin_right = 6
	hover_sb.content_margin_top = 2
	hover_sb.content_margin_bottom = 2

	var press_sb := StyleBoxFlat.new()
	press_sb.bg_color = Color(0.82, 0.82, 0.86, 1.0)
	press_sb.set_corner_radius_all(6)
	press_sb.content_margin_left = 6
	press_sb.content_margin_right = 6
	press_sb.content_margin_top = 2
	press_sb.content_margin_bottom = 2

	btn.add_theme_stylebox_override("normal", norm_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", press_sb)
	btn.add_theme_color_override("font_color", Color(0.2, 0.2, 0.24, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.12, 1.0))
	return btn

func _on_undo_pressed() -> void:
	var hm = get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("undo"):
		hm.undo()

func _on_redo_pressed() -> void:
	var hm = get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("redo"):
		hm.redo()

func _on_export_pressed() -> void:
	export_requested.emit()
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("request_export_dialog"):
		ge.emit_safe("request_export_dialog")
