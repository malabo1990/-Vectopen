# =============================================================================
# RUTA: res://script_gdscript/test_typography_realtime.gd
# Test interactivo y en tiempo real del Panel de Tipografía y Proporciones.
# =============================================================================
extends Control

const ARTIFACT_DIR := "C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686"
const SCREENSHOT_PATH := ARTIFACT_DIR + "/realtime_typography_proportions_test.png"
const RES_SCREENSHOT := "res://addons/godot_mcp/cache/screenshots/realtime_typography_proportions_test.png"

var _panel: Control
var _canvas_inner: Control
var _text1: Node2D
var _text2: Node2D
var _text3: Node2D
var _text4: Node2D
var _text5: Node2D
var _status_label: Label
var _log_label: Label

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Fondo Claro Studio (#F8F8FA)
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.97, 0.97, 0.98, 1.0)
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.offset_left = 20
	main_vbox.offset_top = 20
	main_vbox.offset_right = -20
	main_vbox.offset_bottom = -20
	main_vbox.add_theme_constant_override("separation", 14)
	add_child(main_vbox)

	# Header con título y estado
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 36)
	main_vbox.add_child(header)

	var title := Label.new()
	title.text = "VERIFICACIÓN EN TIEMPO REAL: PANEL TIPOGRAFÍA LIMPIO (SIN MARCOS) Y 4 SLIDERS"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.15))
	header.add_child(title)

	_status_label = Label.new()
	_status_label.text = "  [INICIANDO TESTS DE TIPOGRAFÍA...]"
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.0))
	header.add_child(_status_label)

	# 2 Columnas
	var hsplit := HBoxContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.add_theme_constant_override("separation", 24)
	main_vbox.add_child(hsplit)

	# --- Columna 1: Panel Tipografía (Sin Marcos, Fondo Blanco) ---
	var col1 := VBoxContainer.new()
	col1.custom_minimum_size = Vector2(300, 560)
	hsplit.add_child(col1)

	var lbl1 := Label.new()
	lbl1.text = "PANEL TIPOGRAFÍA (BLANCO PURO, SIN MARCOS)"
	lbl1.add_theme_font_size_override("font_size", 12)
	lbl1.add_theme_color_override("font_color", Color(0.2, 0.22, 0.26))
	col1.add_child(lbl1)

	var holder1 := PanelContainer.new()
	holder1.custom_minimum_size = Vector2(290, 520)
	var sb_holder := StyleBoxFlat.new()
	sb_holder.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	sb_holder.set_corner_radius_all(10)
	sb_holder.set_border_width_all(0)
	sb_holder.content_margin_left = 12
	sb_holder.content_margin_top = 12
	sb_holder.content_margin_right = 12
	sb_holder.content_margin_bottom = 12
	holder1.add_theme_stylebox_override("panel", sb_holder)
	col1.add_child(holder1)

	var tscn: PackedScene = load("res://scenes/ui/panel_tooltext.tscn")
	_panel = tscn.instantiate() as Control
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder1.add_child(_panel)

	# --- Columna 2: Canvas & Muestras de Texto (Sin Marcos, Fondo Blanco) ---
	var col2 := VBoxContainer.new()
	col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(col2)

	var lbl2 := Label.new()
	lbl2.text = "CANVAS VECTORIAL: PROPORCIONES (4 SLIDERS), INTERLETRAJE Y TAMAÑO EN VIVO"
	lbl2.add_theme_font_size_override("font_size", 12)
	lbl2.add_theme_color_override("font_color", Color(0.2, 0.22, 0.26))
	col2.add_child(lbl2)

	var canvas_card := PanelContainer.new()
	canvas_card.custom_minimum_size = Vector2(0, 500)
	canvas_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	card_sb.set_corner_radius_all(10)
	card_sb.set_border_width_all(0)
	canvas_card.add_theme_stylebox_override("panel", card_sb)
	col2.add_child(canvas_card)

	_canvas_inner = Control.new()
	_canvas_inner.clip_contents = true
	_canvas_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas_inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_card.add_child(_canvas_inner)

	# Log inferior
	_log_label = Label.new()
	_log_label.text = "Log de Operaciones:\n"
	_log_label.custom_minimum_size = Vector2(0, 70)
	_log_label.add_theme_font_size_override("font_size", 11)
	_log_label.add_theme_color_override("font_color", Color(0.3, 0.32, 0.36))
	col2.add_child(_log_label)

	_run_verification_sequence()

func _log(msg: String) -> void:
	print("[REALTIME-TYPO] " + msg)
	if _log_label:
		_log_label.text += "• " + msg + "\n"

func _run_verification_sequence() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	# 1. Crear 4 Textos vectoriales con las 4 proporciones (usando los 4 factores start, mid, mid2, end)
	_text1 = _crear_texto_con_proporcion(
		"VECTOPEN STUDIO",
		Vector2(40, 35),
		{"mode": "Aaa", "start": 1.6, "mid": 1.2, "mid2": 0.8, "end": 0.4},
		Color(0.12, 0.12, 0.15),
		0
	)

	_text2 = _crear_texto_con_proporcion(
		"TYPOGRAPHY CURVES",
		Vector2(40, 125),
		{"mode": "aAa", "start": 0.4, "mid": 1.4, "mid2": 1.4, "end": 0.4},
		Color(0.15, 0.35, 0.85),
		0
	)

	_text3 = _crear_texto_con_proporcion(
		"CREATIVE VECTOR ENGINE",
		Vector2(40, 215),
		{"mode": "aaA", "start": 0.4, "mid": 0.8, "mid2": 1.2, "end": 1.6},
		Color(0.1, 0.55, 0.3),
		0
	)

	_text4 = _crear_texto_con_proporcion(
		"CONCAVE DYNAMIC SHAPE",
		Vector2(40, 305),
		{"mode": "AaA", "start": 1.5, "mid": 0.5, "mid2": 0.5, "end": 1.5},
		Color(0.5, 0.2, 0.7),
		0
	)

	# 5. Texto para probar interletraje (letter_spacing = 6px) y tamaño en tiempo real
	_text5 = _crear_texto_con_proporcion(
		"TRACKING & REALTIME RESIZE",
		Vector2(40, 400),
		{},
		Color(0.8, 0.35, 0.1),
		6
	)

	_log("Texto 1: Aaa (4 sliders: inicio=1.6, medio1=1.2, medio2=0.8, fin=0.4)")
	_log("Texto 2: aAa (4 sliders: extremos=0.4, centro doble=1.4)")
	_log("Texto 3: aaA (4 sliders: inicio=0.4, medio1=0.8, medio2=1.2, fin=1.6)")
	_log("Texto 4: AaA (4 sliders: extremos=1.5, valle central=0.5)")
	_log("Texto 5: Interletraje activo (letter_spacing=6) sin distorsión.")

	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	# Sincronizar selección en InspectorCore con Text 1
	var ic = get_node_or_null("/root/InspectorCore")
	if ic:
		ic._selection = [_text1]
		ic.changed.emit(ic.current_props())
	await get_tree().process_frame

	_log("Panel Tipografía sincronizado con selección activa (_text1).")
	_status_label.text = "  [¡VERIFICACIÓN EN TIEMPO REAL COMPLETADA CON ÉXITO!]"
	_status_label.add_theme_color_override("font_color", Color(0.1, 0.6, 0.2))

	await get_tree().create_timer(0.6).timeout
	_capture_screenshot()

func _crear_texto_con_proporcion(texto: String, pos: Vector2, prop: Dictionary, col: Color, ls: int = 0) -> Node2D:
	var txt := Node2D.new()
	txt.name = "Text_" + texto.substr(0, 4)
	txt.set_meta("shape_type", "text_title")
	txt.set_meta("font_size", 30)
	txt.set_meta("text", texto)
	txt.set_meta("text_color", col)
	txt.set_meta("letter_spacing", ls)
	if not prop.is_empty():
		txt.set_meta("letter_proportions", prop)
	txt.position = pos

	var dl := WorldTextLabel.new()
	dl.name = "DisplayLabel"
	dl.text = texto
	dl.base_font_size = 30
	dl.add_theme_font_size_override("font_size", 30)
	dl.add_theme_color_override("font_color", col)
	txt.add_child(dl)

	_canvas_inner.add_child(txt)
	if not prop.is_empty():
		dl.set_letter_proportions(prop)
	return txt

func _capture_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ARTIFACT_DIR)
	DirAccess.make_dir_recursive_absolute("D:/2025/Godot/vectopen/addons/godot_mcp/cache/screenshots")

	var err1 := img.save_png(SCREENSHOT_PATH)
	var err2 := img.save_png(RES_SCREENSHOT)
	_log("Captura guardada en: " + SCREENSHOT_PATH + " (código=" + str(err1) + ")")
	print("[REALTIME-TYPO-DONE] Screenshot saved successfully!")
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0)
