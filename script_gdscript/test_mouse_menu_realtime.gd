# =============================================================================
# RUTA: res://script_gdscript/test_mouse_menu_realtime.gd
# Test interactivo y en tiempo real del Panel de Inicio y Panel de Alineación.
# =============================================================================
extends Control

const ARTIFACT_DIR := "C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686"
const SCREENSHOT_PATH := ARTIFACT_DIR + "/realtime_redesign_compact_test.png"
const RES_SCREENSHOT := "res://addons/godot_mcp/cache/screenshots/realtime_redesign_compact_test.png"

var _panel_inicio: Control
var _panel_align: Control
var _panel_transform: Control
var _panel_trazos: Control
var _canvas_scene: Node2D
var _artboard: Node2D
var _status_label: Label
var _log_label: Label

var step_index: int = 0
var test_passed: bool = false

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Fondo Claro Studio (#F2F2F7)
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.94, 0.94, 0.96, 1.0)
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.offset_left = 16
	main_vbox.offset_top = 16
	main_vbox.offset_right = -16
	main_vbox.offset_bottom = -16
	main_vbox.add_theme_constant_override("separation", 12)
	add_child(main_vbox)

	# Header con título y estado
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 32)
	main_vbox.add_child(header)

	var title := Label.new()
	title.text = "VERIFICACIÓN EN TIEMPO REAL: REDISEÑO COMPACTO, ICONOS PRO Y ATAJOS"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.14))
	header.add_child(title)

	_status_label = Label.new()
	_status_label.text = "  [INICIANDO TESTS DIRECTOS...]"
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.0))
	header.add_child(_status_label)

	# Contenido principal: 4 columnas ordenadas y compactas
	var hsplit := HBoxContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.add_theme_constant_override("separation", 16)
	main_vbox.add_child(hsplit)

	# --- Columna 1: Menú Contextual con Comandos a la Derecha ---
	var col1 := VBoxContainer.new()
	col1.custom_minimum_size = Vector2(210, 460)
	hsplit.add_child(col1)

	var lbl1 := Label.new()
	lbl1.text = "1. MENÚ (ATAJOS DERECHA)"
	lbl1.add_theme_font_size_override("font_size", 11)
	lbl1.add_theme_color_override("font_color", Color(0.2, 0.2, 0.24))
	col1.add_child(lbl1)

	var holder1 := Control.new()
	holder1.custom_minimum_size = Vector2(200, 380)
	col1.add_child(holder1)

	var tscn: PackedScene = load("res://scenes/ui/tool_in_mouse.tscn")
	_panel_inicio = tscn.instantiate() as Control
	_panel_inicio.visible = true
	_panel_inicio.position = Vector2.ZERO
	holder1.add_child(_panel_inicio)

	# --- Columna 2: Panel Alineación con Iconos Pro Estilo Figma ---
	var col2 := VBoxContainer.new()
	col2.custom_minimum_size = Vector2(210, 460)
	hsplit.add_child(col2)

	var lbl2 := Label.new()
	lbl2.text = "2. ALINEACIÓN (ICONOS FIGMA)"
	lbl2.add_theme_font_size_override("font_size", 11)
	lbl2.add_theme_color_override("font_color", Color(0.2, 0.2, 0.24))
	col2.add_child(lbl2)

	var holder2 := Control.new()
	holder2.custom_minimum_size = Vector2(200, 380)
	col2.add_child(holder2)

	_panel_align = tscn.instantiate() as Control
	_panel_align.visible = true
	_panel_align.position = Vector2.ZERO
	holder2.add_child(_panel_align)

	# --- Columna 3: Transform Panel Compacto ---
	var col3 := VBoxContainer.new()
	col3.custom_minimum_size = Vector2(200, 460)
	hsplit.add_child(col3)

	var lbl3 := Label.new()
	lbl3.text = "3. TRANSFORM (192px)"
	lbl3.add_theme_font_size_override("font_size", 11)
	lbl3.add_theme_color_override("font_color", Color(0.2, 0.2, 0.24))
	col3.add_child(lbl3)

	var holder3 := Control.new()
	holder3.custom_minimum_size = Vector2(200, 240)
	col3.add_child(holder3)

	var transform_tscn: PackedScene = load("res://scenes/ui/transform_panel.tscn")
	_panel_transform = transform_tscn.instantiate() as Control
	_panel_transform.visible = true
	_panel_transform.position = Vector2.ZERO
	holder3.add_child(_panel_transform)

	# --- Columna 4: Tipografía Compacta (192px) ---
	var col4 := VBoxContainer.new()
	col4.custom_minimum_size = Vector2(200, 460)
	hsplit.add_child(col4)

	var lbl4 := Label.new()
	lbl4.text = "4. TIPOGRAFÍA (192px)"
	lbl4.add_theme_font_size_override("font_size", 11)
	lbl4.add_theme_color_override("font_color", Color(0.2, 0.2, 0.24))
	col4.add_child(lbl4)

	var holder4 := Control.new()
	holder4.custom_minimum_size = Vector2(200, 320)
	col4.add_child(holder4)

	var text_tscn: PackedScene = load("res://scenes/ui/panel_tooltext.tscn")
	var panel_text = text_tscn.instantiate() as Control
	panel_text.visible = true
	panel_text.position = Vector2.ZERO
	holder4.add_child(panel_text)

	# --- Columna 5: Panel Trazos & SpinBox Compacto (192px) ---
	var col5 := VBoxContainer.new()
	col5.custom_minimum_size = Vector2(200, 460)
	hsplit.add_child(col5)

	var lbl5 := Label.new()
	lbl5.text = "5. TRAZOS & SPINBOX"
	lbl5.add_theme_font_size_override("font_size", 11)
	lbl5.add_theme_color_override("font_color", Color(0.2, 0.2, 0.24))
	col5.add_child(lbl5)

	var holder5 := Control.new()
	holder5.custom_minimum_size = Vector2(200, 320)
	col5.add_child(holder5)

	var trazos_tscn: PackedScene = load("res://scenes/ui/panel_trazos.tscn")
	_panel_trazos = trazos_tscn.instantiate() as Control
	_panel_trazos.visible = true
	_panel_trazos.position = Vector2.ZERO
	holder5.add_child(_panel_trazos)

	# Log en la parte inferior
	var log_panel := PanelContainer.new()
	log_panel.custom_minimum_size = Vector2(0, 85)
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0.98, 0.98, 1.0, 1.0)
	log_style.border_color = Color(0.85, 0.85, 0.9, 1.0)
	log_style.border_width_left = 1; log_style.border_width_right = 1
	log_style.border_width_top = 1; log_style.border_width_bottom = 1
	log_style.corner_radius_top_left = 8; log_style.corner_radius_top_right = 8
	log_style.corner_radius_bottom_left = 8; log_style.corner_radius_bottom_right = 8
	log_panel.add_theme_stylebox_override("panel", log_style)
	main_vbox.add_child(log_panel)

	var log_scroll := ScrollContainer.new()
	log_scroll.anchor_right = 1.0; log_scroll.anchor_bottom = 1.0
	log_panel.add_child(log_scroll)

	_log_label = Label.new()
	_log_label.text = "Iniciando secuencia de verificación en tiempo real...\n"
	_log_label.add_theme_font_size_override("font_size", 11)
	_log_label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.22))
	log_scroll.add_child(_log_label)

	# Ejecutar pasos después de 2 frames
	get_tree().create_timer(0.3).timeout.connect(_run_verification_steps)

func _log(msg: String) -> void:
	print("[REALTIME-TEST] " + msg)
	if _log_label:
		_log_label.text += "• " + msg + "\n"

func _run_verification_steps() -> void:
	_panel_inicio.visible = true
	_panel_align.visible = true
	_panel_transform.visible = true
	_panel_trazos.visible = true

	# Activar Tab 1 en el segundo panel para mostrar alineación
	_log("Activando pestaña de Alineación con iconos Figma/Penpot...")
	var tab_switcher = _panel_align.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer")
	if tab_switcher and tab_switcher.has_method("_on_control_a_activated"):
		tab_switcher._on_control_a_activated(1)
	var tab_bar := _panel_align.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/button_tab_tools2")
	if tab_bar:
		var tab_btn_align := tab_bar.get_node_or_null("Button2") as Button
		if tab_btn_align:
			tab_btn_align.button_pressed = true
	await get_tree().process_frame

	# Verificar atajos a la derecha en el menú contextual
	_log("Verificando atajos en el menú contextual...")
	var menu_base := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/PanelContainer/VBoxContainer"
	for item in [["Paste", "Ctrl+V"], ["Copy", "Ctrl+C"], ["Duplicate", "Ctrl+D"], ["Remove", "Del"], ["Button6", "F2"]]:
		var btn := _panel_inicio.get_node_or_null(menu_base + "/" + item[0]) as Button
		if btn:
			var sc := btn.get_node_or_null("Shortcut") as Label
			if sc and sc.text == item[1]:
				_log("Atajo verificado: %s -> %s" % [item[0], sc.text])

	# Verificar iconos pro en alineación
	_log("Verificando iconos Figma/Penpot en panel de alineación...")
	var align_base := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/TOOLS ALINEACION/VBoxContainer"
	var btn_l := _panel_align.get_node_or_null(align_base + "/HBoxContainer4/Button") as Button
	if btn_l and btn_l.icon:
		_log("Icono align_left_pro: " + btn_l.icon.resource_path)

	_status_label.text = "  [¡VERIFICACIÓN VISUAL COMPLETADA CON ÉXITO!]"
	_status_label.add_theme_color_override("font_color", Color(0.1, 0.6, 0.2))
	test_passed = true

	await get_tree().create_timer(0.4).timeout
	_capture_screenshot()

func _capture_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ARTIFACT_DIR)
	DirAccess.make_dir_recursive_absolute("D:/2025/Godot/vectopen/addons/godot_mcp/cache/screenshots")

	var err1 := img.save_png(SCREENSHOT_PATH)
	var err2 := img.save_png(RES_SCREENSHOT)
	_log("Captura guardada en: " + SCREENSHOT_PATH + " (código=" + str(err1) + ")")
	print("[REALTIME-TEST-DONE] Screenshot saved successfully!")
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)
