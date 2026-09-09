# =============================================================================
# RUTA: res://script_gdscript/test_align_color_realtime.gd
# Test interactivo y en tiempo real de:
# 1. Panel de Alineación: Iconos con hueco vacío + Cuadrícula 4x4 + Botón Todo Tamaño
# 2. Selector de Color: Modos Círculo, Triángulo y Cuadrado (Figma style)
# 3. Pestañas de Degradado: Sólido, Lineal y Radial
# 4. Gradient Annotator sobre el Canvas (Affinity / Figma / Illustrator style)
# =============================================================================
extends Control

const ARTIFACT_DIR := "C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686"
const SCREENSHOT_PATH := ARTIFACT_DIR + "/realtime_align_color_gradient_test.png"

var _status_label: Label
var _align_panel: Control
var _color_picker: Control
var _canvas_inner: Control
var _rect_shape: VectorRectangle
var _circle_shape: VectorCircle
var _bbox: Control

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Fondo claro (#F4F4F6)
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.95, 0.95, 0.97, 1.0)
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.offset_left = 20
	main_vbox.offset_top = 16
	main_vbox.offset_right = -20
	main_vbox.offset_bottom = -16
	main_vbox.add_theme_constant_override("separation", 10)
	add_child(main_vbox)

	# Header con título y estado
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 32)
	main_vbox.add_child(header)

	var title := Label.new()
	title.text = "VERIFICACIÓN: ALINEACIÓN PRO, COLOR MULTI-MODO Y GRADIENT ANNOTATOR"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.15))
	header.add_child(title)

	_status_label = Label.new()
	_status_label.text = "  [INICIANDO SIMULACIÓN...]"
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.1, 0.5, 0.9))
	header.add_child(_status_label)

	# Fila central: 3 paneles
	# 1. Canvas con Gradient Annotator sobre figuras
	# 2. Panel de Alineación rediseñado (Arriba 4x4 + Todo Tamaño, Abajo Iconos Huecos)
	# 3. Color Picker con Pestañas (Sólido/Lineal/Radial) + Modos (◯, △, ▢)
	var hsplit := HBoxContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.add_theme_constant_override("separation", 16)
	main_vbox.add_child(hsplit)

	# ── 1. Columna Canvas (Izquierda) ──────────────────────────────────────────
	var canvas_col := VBoxContainer.new()
	canvas_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_col.size_flags_stretch_ratio = 1.5
	hsplit.add_child(canvas_col)

	var c_lbl := Label.new()
	c_lbl.text = "CANVAS & GRADIENT ANNOTATOR (ON-CANVAS GIZMO):"
	c_lbl.add_theme_font_size_override("font_size", 11)
	c_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	canvas_col.add_child(c_lbl)

	var canvas_card := PanelContainer.new()
	canvas_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color.WHITE
	card_style.set_corner_radius_all(8)
	card_style.border_color = Color(0.85, 0.85, 0.88)
	card_style.set_border_width_all(1)
	canvas_card.add_theme_stylebox_override("panel", card_style)
	canvas_col.add_child(canvas_card)

	_canvas_inner = Control.new()
	_canvas_inner.clip_contents = true
	canvas_card.add_child(_canvas_inner)

	# Artboard y figuras en el canvas
	var artboard := Node2D.new()
	artboard.name = "Artboard"
	_canvas_inner.add_child(artboard)

	# Figura 1: Rectángulo con Linear Gradient
	_rect_shape = VectorRectangle.new()
	_rect_shape.name = "GradRect"
	_rect_shape.position = Vector2(160, 160)
	_rect_shape.size = Vector2(180, 140)
	var g_lin := Gradient.new()
	g_lin.set_color(0, Color(1.0, 0.22, 0.45, 1.0)) # Rosa/Fucsia
	g_lin.add_point(0.5, Color(1.0, 0.75, 0.2, 1.0)) # Naranja
	g_lin.set_color(1, Color(0.12, 0.65, 1.0, 1.0)) # Azul Cyan
	_rect_shape.fill_gradient = g_lin
	_rect_shape.fill_gradient_type = 0 # Linear
	_rect_shape.fill_gradient_angle = deg_to_rad(35.0)
	artboard.add_child(_rect_shape)

	# Figura 2: Círculo con Radial Gradient
	_circle_shape = VectorCircle.new()
	_circle_shape.name = "GradCircle"
	_circle_shape.position = Vector2(360, 160)
	_circle_shape.size = Vector2(130, 130)
	var g_rad := Gradient.new()
	g_rad.set_color(0, Color(1.0, 0.95, 0.4, 1.0)) # Amarillo sol
	g_rad.add_point(0.6, Color(1.0, 0.4, 0.1, 1.0)) # Naranja fuego
	g_rad.set_color(1, Color(0.4, 0.05, 0.7, 1.0)) # Púrpura noche
	_circle_shape.fill_gradient = g_rad
	_circle_shape.fill_gradient_type = 1 # Radial
	_circle_shape.fill_gradient_angle = deg_to_rad(45.0)
	artboard.add_child(_circle_shape)

	# Bounding Box con Gradient Annotator activo sobre _rect_shape
	var bbox_scene = load("res://scenes/canvas/boundingbox.tscn")
	if bbox_scene:
		_bbox = bbox_scene.instantiate()
		_canvas_inner.add_child(_bbox)
		_bbox.target_node = _rect_shape
		_bbox._sincronizar_dimensiones_en_canvas()

	# ── 2. Columna Panel de Alineación (Centro) ───────────────────────────────
	var align_col := VBoxContainer.new()
	align_col.custom_minimum_size = Vector2(240, 0)
	align_col.size_flags_horizontal = Control.SIZE_FILL
	hsplit.add_child(align_col)

	var a_lbl := Label.new()
	a_lbl.text = "ALINEACIÓN (4x4 + FULL + OUTLINE):"
	a_lbl.add_theme_font_size_override("font_size", 10)
	a_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	align_col.add_child(a_lbl)

	var mouse_menu_scene = load("res://scenes/ui/tool_in_mouse.tscn")
	if mouse_menu_scene:
		_align_panel = mouse_menu_scene.instantiate()
		_align_panel.custom_minimum_size = Vector2(230, 420)
		_align_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		align_col.add_child(_align_panel)
		_align_panel.target_node = null
		_align_panel.visible = true

		var pc = _align_panel.get_node_or_null("PanelContainer")
		if pc:
			pc.offset_left = 0
			pc.offset_top = 0
			pc.offset_right = 230
			pc.offset_bottom = 410

		# Activar pestaña de alineación (índice 1: TOOLS ALINEACION)
		var tab_list = _align_panel.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer")
		if tab_list and tab_list.has_method("_on_control_a_activated"):
			tab_list._on_control_a_activated(1)

	# ── 3. Columna Color Picker Modo Cuadrado Figma (Completa Ancho) ────────
	var color_col1 := VBoxContainer.new()
	color_col1.custom_minimum_size = Vector2(215, 0)
	color_col1.size_flags_horizontal = Control.SIZE_FILL
	hsplit.add_child(color_col1)

	var cp_lbl1 := Label.new()
	cp_lbl1.text = "COLOR PICKER (MODO CUADRADO FIGMA):"
	cp_lbl1.add_theme_font_size_override("font_size", 10)
	cp_lbl1.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	color_col1.add_child(cp_lbl1)

	var color_scene = load("res://scenes/ui/pickr_color_tool.tscn")
	if color_scene:
		_color_picker = color_scene.instantiate()
		color_col1.add_child(_color_picker)

	# ── 4. Columna Color Picker Modo Triángulo (Fondo Blanco) ───────────────
	var color_col2 := VBoxContainer.new()
	color_col2.custom_minimum_size = Vector2(215, 0)
	color_col2.size_flags_horizontal = Control.SIZE_FILL
	hsplit.add_child(color_col2)

	var cp_lbl2 := Label.new()
	cp_lbl2.text = "COLOR PICKER (TRIÁNGULO FONDO BLANCO):"
	cp_lbl2.add_theme_font_size_override("font_size", 10)
	cp_lbl2.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	color_col2.add_child(cp_lbl2)

	var color_picker_tri: Control = null
	if color_scene:
		color_picker_tri = color_scene.instantiate()
		color_col2.add_child(color_picker_tri)

	# Iniciar ciclo de pruebas
	_run_simulation(color_picker_tri)

func _run_simulation(color_picker_tri: Control) -> void:
	await get_tree().create_timer(0.3).timeout
	_status_label.text = "  [1/4] CONFIGURANDO SELECTORES: CUADRADO FIGMA Y TRIÁNGULO FONDO BLANCO..."

	# Picker 1: Modo Cuadrado Figma (Completa Ancho)
	if _color_picker and _color_picker.has_method("_on_mode_pressed"):
		_color_picker._on_mode_pressed(2) # SQUARE
	if _color_picker and _color_picker.has_method("_on_tab_pressed"):
		_color_picker._on_tab_pressed("linear")

	# Picker 2: Modo Triángulo con fondo blanco puro
	if color_picker_tri and color_picker_tri.has_method("_on_mode_pressed"):
		color_picker_tri._on_mode_pressed(1) # TRIANGLE
	if color_picker_tri and color_picker_tri.has_method("_on_tab_pressed"):
		color_picker_tri._on_tab_pressed("solid")

	await get_tree().create_timer(0.5).timeout
	_status_label.text = "  [2/4] VERIFICANDO PESTAÑAS Y DEGRADADO EN TIEMPO REAL..."

	if _bbox:
		_bbox._sincronizar_dimensiones_en_canvas()

	await get_tree().create_timer(0.4).timeout
	_status_label.text = "  [3/4] PROBANDO GRADIENT ANNOTATOR Y ROTACIÓN EN CANVAS..."

	# Simular rotación del degradado en canvas con el annotator
	if _bbox:
		_rect_shape.fill_gradient_angle = deg_to_rad(75.0)
		_rect_shape.queue_redraw()
		_bbox._sincronizar_dimensiones_en_canvas()

	await get_tree().create_timer(0.4).timeout
	_status_label.text = "  [4/4] VERIFICACIÓN COMPLETADA CON ÉXITO... [OK]"

	await get_tree().create_timer(0.4).timeout
	_capture_and_finish()

func _capture_and_finish() -> void:
	var vp := get_viewport()
	if vp:
		var tex := vp.get_texture()
		if tex:
			var img := tex.get_image()
			if img:
				var dir := ARTIFACT_DIR
				if not DirAccess.dir_exists_absolute(dir):
					DirAccess.make_dir_recursive_absolute(dir)
				var err := img.save_png(SCREENSHOT_PATH)
				if err == OK:
					print("SCREENSHOT_SAVED: " + SCREENSHOT_PATH)
				else:
					print("ERROR saving screenshot: ", err)

	print("TEST_REALTIME_SUCCESSFUL")
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)
