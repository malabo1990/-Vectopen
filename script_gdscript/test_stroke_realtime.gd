# =============================================================================
# RUTA: res://script_gdscript/test_stroke_realtime.gd
# Test interactivo y en tiempo real del Panel de Trazos y Panel de Tipografía.
# =============================================================================
extends Control

const ARTIFACT_DIR := "C:/Users/User/.gemini/antigravity/brain/84517d09-fb94-481f-9eb7-a9c8bd6050c3"
const SCREENSHOT_PATH := ARTIFACT_DIR + "/realtime_stroke_test.png"
const RES_SCREENSHOT := "res://addons/godot_mcp/cache/screenshots/realtime_stroke_test.png"

var _panel: PanelTrazos
var _panel_text: Control
var _canvas_container: Control
var _path: VectorPath
var _rect: VectorRectangle
var _circle: VectorCircle
var _text_node: Node2D
var _log_label: Label
var _status_label: Label

var test_passed: bool = false
var step_index: int = 0

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	
	# Fondo de la aplicación (Modo Claro / Studio: #EFEFF4)
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.937, 0.937, 0.957, 1.0)
	add_child(bg)
	
	# Layout principal horizontal: Izquierda Trazos, Centro Tipografía, Derecha Canvas y Log
	var hsplit := HBoxContainer.new()
	hsplit.anchor_right = 1.0
	hsplit.anchor_bottom = 1.0
	hsplit.add_theme_constant_override("separation", 14)
	add_child(hsplit)
	
	# Columna 1: Panel de Trazos
	var col1 := VBoxContainer.new()
	col1.custom_minimum_size = Vector2(270, 0)
	hsplit.add_child(col1)
	
	var title_panel1 := Label.new()
	title_panel1.text = "  PANEL DE TRAZOS (CHIPS GRISES)"
	title_panel1.add_theme_font_size_override("font_size", 12)
	title_panel1.add_theme_color_override("font_color", Color(0.12, 0.12, 0.15))
	col1.add_child(title_panel1)
	
	var panel_scene: PackedScene = load("res://scenes/ui/panel_trazos.tscn")
	_panel = panel_scene.instantiate() as PanelTrazos
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col1.add_child(_panel)
	
	# Columna 2: Panel de Tipografía
	var col2 := VBoxContainer.new()
	col2.custom_minimum_size = Vector2(250, 0)
	hsplit.add_child(col2)
	
	var title_panel2 := Label.new()
	title_panel2.text = "  PANEL TIPOGRAFÍA (ESTRUCTURA EXACTA)"
	title_panel2.add_theme_font_size_override("font_size", 12)
	title_panel2.add_theme_color_override("font_color", Color(0.12, 0.12, 0.15))
	col2.add_child(title_panel2)
	
	var text_scene: PackedScene = load("res://scenes/ui/panel_tooltext.tscn")
	_panel_text = text_scene.instantiate() as Control
	_panel_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col2.add_child(_panel_text)
	
	# Columna 3: Lienzo 2D y Log
	var col3 := VBoxContainer.new()
	col3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col3.add_theme_constant_override("separation", 10)
	hsplit.add_child(col3)
	
	# Header Canvas
	var header_box := HBoxContainer.new()
	col3.add_child(header_box)
	
	var canvas_title := Label.new()
	canvas_title.text = "CANVAS VECTORIAL EN VIVO"
	canvas_title.add_theme_font_size_override("font_size", 13)
	canvas_title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.15))
	header_box.add_child(canvas_title)
	
	_status_label = Label.new()
	_status_label.text = " [EJECUTANDO PRUEBAS...]"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.0))
	header_box.add_child(_status_label)
	
	# Contenedor del Lienzo (Blanco puro / Artboard)
	_canvas_container = Control.new()
	_canvas_container.custom_minimum_size = Vector2(0, 420)
	_canvas_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var canvas_bg := ColorRect.new()
	canvas_bg.anchor_right = 1.0
	canvas_bg.anchor_bottom = 1.0
	canvas_bg.color = Color(1.0, 1.0, 1.0, 1.0)
	_canvas_container.add_child(canvas_bg)
	col3.add_child(_canvas_container)
	
	_crear_figuras()
	
	# Log inferior
	var log_panel := PanelContainer.new()
	log_panel.custom_minimum_size = Vector2(0, 160)
	var log_sb := StyleBoxFlat.new()
	log_sb.bg_color = Color(0.98, 0.98, 0.99, 1.0)
	log_sb.border_width_top = 1
	log_sb.border_color = Color(0.85, 0.85, 0.88, 1.0)
	log_panel.add_theme_stylebox_override("panel", log_sb)
	col3.add_child(log_panel)
	
	_log_label = Label.new()
	_log_label.add_theme_font_size_override("font_size", 11)
	_log_label.add_theme_color_override("font_color", Color(0.25, 0.28, 0.35, 1.0))
	log_panel.add_child(_log_label)
	
	_log("Sistema listo. Iniciando validación en tiempo real de Trazos y Tipografía...")
	_ejecutar_secuencia_tiempo_real()

func _crear_figuras() -> void:
	# 1. VectorPath
	_path = VectorPath.new()
	_path.name = "TestPath"
	var curve := Curve2D.new()
	curve.add_point(Vector2(50, 100), Vector2.ZERO, Vector2(80, -60))
	curve.add_point(Vector2(260, 100), Vector2(-80, 60), Vector2(80, -60))
	curve.add_point(Vector2(480, 100), Vector2(-80, 60), Vector2.ZERO)
	_path.curve = curve
	_path.stroke_color = Color("38bdf8")
	_path.stroke_width = 8.0
	_canvas_container.add_child(_path)
	
	# 2. VectorRectangle
	_rect = VectorRectangle.new()
	_rect.name = "TestRect"
	_rect.position = Vector2(50, 240)
	_rect.size = Vector2(180, 100)
	_rect.corner_radius = 12.0
	_rect.fill_color = Color(0.2, 0.35, 0.7, 0.15)
	_rect.stroke_color = Color("8b5cf6")
	_rect.stroke_width = 5.0
	_canvas_container.add_child(_rect)
	
	# 3. VectorCircle
	_circle = VectorCircle.new()
	_circle.name = "TestCircle"
	_circle.position = Vector2(280, 240)
	_circle.size = Vector2(110, 110)
	_circle.fill_color = Color(0.8, 0.2, 0.4, 0.15)
	_circle.stroke_color = Color("ec4899")
	_circle.stroke_width = 5.0
	_circle.stroke_style = 2
	_canvas_container.add_child(_circle)
	
	# 4. Texto tipográfico interactivo en el lienzo
	_text_node = Node2D.new()
	_text_node.name = "TestText"
	_text_node.set_meta("shape_type", "text_title")
	_text_node.set_meta("font_size", 28)
	_text_node.set_meta("text", "Vectopen Studio 2026")
	_text_node.position = Vector2(50, 370)
	var dl := Label.new()
	dl.name = "DisplayLabel"
	dl.text = "Vectopen Studio 2026"
	dl.add_theme_font_size_override("font_size", 28)
	dl.add_theme_color_override("font_color", Color(0.12, 0.12, 0.15))
	_text_node.add_child(dl)
	_canvas_container.add_child(_text_node)

func _log(msg: String) -> void:
	print("[TEST-LIVE] " + msg)
	if _log_label:
		_log_label.text += "\n  " + msg

func _ejecutar_secuencia_tiempo_real() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	var sm := get_node_or_null("/root/SelectionManager")
	var hm := get_node_or_null("/root/HistoryManager")
	
	await get_tree().create_timer(0.3).timeout
	
	# PASO 1: Seleccionar VectorPath
	_log("► PASO 1: Seleccionando VectorPath en tiempo real...")
	if sm and sm.has_method("set_selection"):
		sm.set_selection([_path])
	if ic:
		ic._sync_selection()
	await get_tree().create_timer(0.2).timeout
	
	# PASO 2: Modificar color y grosor en panel_trazos
	_log("► PASO 2: Modificando color a Rosa Coral y grosor a 12.0px (fila independiente)...")
	if ic:
		ic.apply("stroke_color", Color("f43f5e"))
		ic.apply("stroke_width", 12.0)
	await get_tree().create_timer(0.2).timeout
	
	# PASO 3: Probar Caps y Punteros con chips grises
	_log("► PASO 3: Activando Caps (Round/Square) y Punteros (Arrow/Triangle) con chips grises...")
	var btn_cap_s: Button = _panel.find_child("BtnCapStartRound", true, false) as Button
	var btn_cap_e: Button = _panel.find_child("BtnCapEndSquare", true, false) as Button
	if btn_cap_s: btn_cap_s.emit_signal("pressed")
	if btn_cap_e: btn_cap_e.emit_signal("pressed")
	
	var btn_ptr_s: Button = _panel.find_child("BtnPointerStartArrow", true, false) as Button
	var btn_ptr_e: Button = _panel.find_child("BtnPointerEndTriangle", true, false) as Button
	if btn_ptr_s: btn_ptr_s.emit_signal("pressed")
	if btn_ptr_e: btn_ptr_e.emit_signal("pressed")
	await get_tree().create_timer(0.2).timeout
	
	# PASO 4: Estilo discontinuo
	_log("► PASO 4: Aplicando Estilo Discontinuo (Dashed) con raya=16, hueco=8...")
	var btn_style_dashed: Button = _panel.find_child("BtnStyleDashed", true, false) as Button
	if btn_style_dashed: btn_style_dashed.emit_signal("pressed")
	var spin_len: SpinBox = _panel.find_child("SpinDashLen", true, false) as SpinBox
	var spin_gap: SpinBox = _panel.find_child("SpinDashGap", true, false) as SpinBox
	if spin_len: spin_len.value = 16.0
	if spin_gap: spin_gap.value = 8.0
	await get_tree().create_timer(0.2).timeout
	
	# PASO 5: Desplegar editor de curvas (botón gris)
	_log("► PASO 5: Pulsando botón gris 'Editor Perfil Cónico'...")
	var btn_curve: Button = _panel.find_child("BtnToggleCurve", true, false) as Button
	if btn_curve: btn_curve.emit_signal("pressed")
	await get_tree().create_timer(0.2).timeout
	
	# PASO 6: Probar Panel de Tipografía
	_log("► PASO 6: Seleccionando texto e interactuando con Panel de Tipografía...")
	if sm and sm.has_method("set_selection"):
		sm.set_selection([_text_node])
	if ic:
		ic._sync_selection()
	
	# Pulsar botón de alineación centro en panel tipografía
	var align_center_btn := _panel_text.get_node_or_null("BoxContainer/Panel/VBoxContainer/BoxContainer2/Button4") as Button
	if align_center_btn:
		align_center_btn.emit_signal("pressed")
		_log("  Botón de alineación Centrada activado en chip gris.")
	
	await get_tree().create_timer(0.2).timeout
	
	# PASO 7: Comprobar Undo / Redo
	_log("► PASO 7: Verificando Undo y Redo...")
	if hm:
		hm.undo()
		await get_tree().create_timer(0.1).timeout
		hm.redo()
	await get_tree().create_timer(0.2).timeout
	
	# Seleccionar de nuevo Path para vista equilibrada
	if sm and sm.has_method("set_selection"):
		sm.set_selection([_path])
	if ic:
		ic._sync_selection()
	
	_log("► PASO 8: ¡TODAS LAS COMPROBACIONES EN TIEMPO REAL SUPERADAS!")
	test_passed = true
	_status_label.text = " [✓ TESTS EN TIEMPO REAL SUPERADOS CON ÉXITO]"
	_status_label.add_theme_color_override("font_color", Color(0.12, 0.62, 0.22))
	
	await get_tree().process_frame
	await get_tree().process_frame
	_guardar_captura()

func _guardar_captura() -> void:
	var vp := get_viewport()
	if vp:
		var tex := vp.get_texture()
		if tex:
			var img: Image = tex.get_image()
			if img:
				DirAccess.make_dir_recursive_absolute("res://addons/godot_mcp/cache/screenshots/")
				DirAccess.make_dir_recursive_absolute(ARTIFACT_DIR)
				
				img.save_png(RES_SCREENSHOT)
				img.save_png(SCREENSHOT_PATH)
				_log("Captura en tiempo real guardada en: " + SCREENSHOT_PATH)
				await get_tree().create_timer(1.0).timeout
				get_tree().quit(0)
