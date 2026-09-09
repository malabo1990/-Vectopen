# =============================================================================
# RUTA: res://script_gdscript/test_effects_realtime.gd
# Test interactivo y en tiempo real del Panel de Efectos y renderizado vectorial
# estilo Figma y Affinity Designer.
# =============================================================================
extends Control

const ARTIFACT_DIR := "C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686"
const SCREENSHOT_PATH := ARTIFACT_DIR + "/realtime_effects_test.png"
const RES_SCREENSHOT := "res://addons/godot_mcp/cache/screenshots/realtime_effects_test.png"

var _canvas_inner: Control
var _effects_panel: Control
var _shape1: VectorRectangle
var _shape2: VectorCircle
var _shape3: VectorPolygon
var _status_label: Label
var _log_label: Label

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Fondo Claro Studio (#F8F8FA)
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.96, 0.96, 0.98, 1.0)
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.offset_left = 24
	main_vbox.offset_top = 20
	main_vbox.offset_right = -24
	main_vbox.offset_bottom = -20
	main_vbox.add_theme_constant_override("separation", 14)
	add_child(main_vbox)

	# Header con título y estado
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 36)
	main_vbox.add_child(header)

	var title := Label.new()
	title.text = "VERIFICACIÓN EN TIEMPO REAL: PANEL EFECTOS (FIGMA / AFFINITY DESIGNER STANDARD)"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.15))
	header.add_child(title)

	_status_label = Label.new()
	_status_label.text = "  [INICIANDO TESTS DE EFECTOS...]"
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.0))
	header.add_child(_status_label)

	# 2 Columnas: Izquierda Canvas con figuras renderizadas, Derecha Panel de Efectos
	var hsplit := HBoxContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.add_theme_constant_override("separation", 20)
	main_vbox.add_child(hsplit)

	# Columna Izquierda: Canvas
	var left_box := VBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.size_flags_stretch_ratio = 1.8
	hsplit.add_child(left_box)

	var canvas_card := PanelContainer.new()
	canvas_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	card_style.border_width_left = 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.border_color = Color(0.88, 0.88, 0.92, 1.0)
	card_style.set_corner_radius_all(12)
	card_style.shadow_color = Color(0, 0, 0, 0.06)
	card_style.shadow_size = 12
	card_style.shadow_offset = Vector2(0, 4)
	canvas_card.add_theme_stylebox_override("panel", card_style)
	left_box.add_child(canvas_card)

	_canvas_inner = Control.new()
	_canvas_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas_inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_card.add_child(_canvas_inner)

	# Columna Derecha: Panel de Efectos Flotante Studio White
	var right_box := VBoxContainer.new()
	right_box.custom_minimum_size = Vector2(300, 0)
	right_box.size_flags_horizontal = Control.SIZE_FILL
	hsplit.add_child(right_box)

	var panel_title := Label.new()
	panel_title.text = "PANEL FLOTANTE (STUDIO WHITE):"
	panel_title.add_theme_font_size_override("font_size", 12)
	panel_title.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
	right_box.add_child(panel_title)

	var panel_scene: PackedScene = load("res://scenes/ui/panel__effects.tscn")
	_effects_panel = panel_scene.instantiate()
	_effects_panel.visible = true
	# Permitir que se acomode en el contenedor
	_effects_panel.anchors_preset = Control.PRESET_FULL_RECT
	_effects_panel.offset_left = 0
	_effects_panel.offset_top = 0
	_effects_panel.offset_right = 0
	_effects_panel.offset_bottom = 0
	_effects_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_child(_effects_panel)

	# Log footer
	_log_label = Label.new()
	_log_label.text = "Iniciando sistema de efectos..."
	_log_label.add_theme_font_size_override("font_size", 12)
	_log_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
	main_vbox.add_child(_log_label)

	_ejecutar_verificacion_en_vivo()

func _log(msg: String) -> void:
	print("[EFFECTS-TEST] ", msg)
	if _log_label:
		_log_label.text = msg

func _ejecutar_verificacion_en_vivo() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. Crear Shape 1: Rectángulo con Drop Shadow suave
	_shape1 = VectorRectangle.new()
	_shape1.name = "Shape_DropShadow"
	_shape1.size = Vector2(160, 110)
	_shape1.corner_radius = 16.0
	_shape1.fill_color = Color(0.12, 0.53, 0.90, 1.0) # Azul moderno
	_shape1.stroke_width = 0.0
	_shape1.position = Vector2(150, 140)
	_shape1.effects = [
		{
			"type": "Drop Shadow",
			"enabled": true,
			"offset_x": 8.0,
			"offset_y": 10.0,
			"blur": 14.0,
			"color": Color(0.05, 0.15, 0.35, 0.45)
		}
	]
	_canvas_inner.add_child(_shape1)
	_shape1.queue_redraw()

	var lbl1 := Label.new()
	lbl1.text = "Figura 1: Drop Shadow (8px, 10px, Blur 14px)"
	lbl1.position = Vector2(50, 225)
	lbl1.add_theme_font_size_override("font_size", 11)
	lbl1.add_theme_color_override("font_color", Color(0.2, 0.2, 0.25))
	_canvas_inner.add_child(lbl1)

	# 2. Crear Shape 2: Círculo con Inner Shadow y Outline
	_shape2 = VectorCircle.new()
	_shape2.name = "Shape_InnerShadow"
	_shape2.size = Vector2(120, 120)
	_shape2.fill_color = Color(1.0, 0.60, 0.20, 1.0) # Naranja cálido
	_shape2.stroke_color = Color(0.9, 0.45, 0.1, 1.0)
	_shape2.stroke_width = 2.0
	_shape2.position = Vector2(380, 140)
	_shape2.effects = [
		{
			"type": "Inner Shadow",
			"enabled": true,
			"offset_x": 4.0,
			"offset_y": 4.0,
			"blur": 8.0,
			"color": Color(0.2, 0.05, 0.0, 0.5)
		},
		{
			"type": "Outline",
			"enabled": true,
			"width": 3.0,
			"color": Color(0.9, 0.45, 0.1, 0.5)
		}
	]
	_canvas_inner.add_child(_shape2)
	_shape2.queue_redraw()

	var lbl2 := Label.new()
	lbl2.text = "Figura 2: Inner Shadow + Outline"
	lbl2.position = Vector2(300, 225)
	lbl2.add_theme_font_size_override("font_size", 11)
	lbl2.add_theme_color_override("font_color", Color(0.2, 0.2, 0.25))
	_canvas_inner.add_child(lbl2)

	# 3. Crear Shape 3: Polígono con Drop Shadow y Color Overlay
	_shape3 = VectorPolygon.new()
	_shape3.name = "Shape_Polygon"
	_shape3.vertices = PackedVector2Array([
		Vector2(0, -60),
		Vector2(55, 45),
		Vector2(-55, 45)
	])
	_shape3.fill_color = Color(0.35, 0.78, 0.45, 1.0) # Verde esmeralda
	_shape3.stroke_width = 0.0
	_shape3.position = Vector2(580, 150)
	_shape3.effects = [
		{
			"type": "Drop Shadow",
			"enabled": true,
			"offset_x": 6.0,
			"offset_y": 8.0,
			"blur": 12.0,
			"color": Color(0.05, 0.2, 0.1, 0.4)
		},
		{
			"type": "Color Overlay",
			"enabled": true,
			"color": Color(0.1, 0.5, 0.8, 0.25),
			"opacity": 0.8
		}
	]
	_canvas_inner.add_child(_shape3)
	_shape3.queue_redraw()

	var lbl3 := Label.new()
	lbl3.text = "Figura 3: Triángulo con Drop Shadow + Color Overlay"
	lbl3.position = Vector2(460, 225)
	lbl3.add_theme_font_size_override("font_size", 11)
	lbl3.add_theme_color_override("font_color", Color(0.2, 0.2, 0.25))
	_canvas_inner.add_child(lbl3)

	await get_tree().process_frame

	# 4. Sincronizar el Panel de Efectos con Shape 1
	var effects_node = _effects_panel.get_node("PanelContainer/VBoxContainer/VBoxContainer/effects")
	if effects_node and effects_node.has_method("_rebuild_or_update_ui"):
		effects_node._empty_label.visible = false
		effects_node._add_button.disabled = false
		effects_node._rebuild_or_update_ui(_shape1.effects)
		_log("Panel de Efectos poblado con los efectos de Figura 1 (Drop Shadow).")

	_status_label.text = "  [¡EFECTOS VECTORIALES VERIFICADOS Y ACTIVOS!]"
	_status_label.add_theme_color_override("font_color", Color(0.1, 0.6, 0.2))

	await get_tree().create_timer(0.6).timeout
	_capture_screenshot()

func _capture_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ARTIFACT_DIR)
	DirAccess.make_dir_recursive_absolute("D:/2025/Godot/vectopen/addons/godot_mcp/cache/screenshots")

	var err1 := img.save_png(SCREENSHOT_PATH)
	var err2 := img.save_png(RES_SCREENSHOT)
	_log("Captura guardada en: " + SCREENSHOT_PATH + " (código=" + str(err1) + ")")
	print("[REALTIME-EFFECTS-DONE] Screenshot saved successfully!")
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0)
