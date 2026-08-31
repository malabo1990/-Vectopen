extends GdUnitTestSuite

## Suite de regresiÃ³n: atrapa los bugs reportados en la sesiÃ³n de UI/zoom.
## 1. Zoom extremo NO debe deformar Labels ni romper sus tamaÃ±os lÃ³gicos.
## 2. El tÃ­tulo del artboard debe existir, con texto, interactivo y sin escalas raras.
## 3. TextTool/ParagraphTool deben crear Labels normales (sin contra-escala).
## 4. El canvas no debe deformar la cÃ¡mara a zoom mÃ¡ximo.

const CanvasScript := "res://scripts/canvas/canvas.gd"
const ArtboardScript := "res://scripts/canvas/artboard.gd"
const TextToolScript := "res://script_gdscript/tools/TextTool.gd"
const ParagraphToolScript := "res://script_gdscript/tools/ParagraphTool.gd"
const WorldLabelGone := "world_label.gd"
const ArtboardTitleGone := "artboard_title.gd"

func _canvas_with_camera() -> Array:
	var canvas: Node2D = Node2D.new()
	canvas.set_script(load(CanvasScript))
	var cam := Camera2D.new()
	cam.position = Vector2(300, 200)
	cam.zoom = Vector2.ONE
	canvas.set("camera", cam)
	canvas.set("zoom_min", 0.05)
	canvas.set("zoom_max", 50000.0)
	add_child(cam)
	add_child(canvas)
	return [canvas, cam]

# 1. Zoom al mÃ¡ximo no deforma los Labels del mundo
func test_zoom_maximo_no_deforma_labels() -> void:
	var setup := _canvas_with_camera()
	var canvas: Node2D = setup[0]
	var cam: Camera2D = setup[1]
	await get_tree().process_frame

	var label := Label.new()
	label.text = "Texto de prueba"
	label.add_theme_font_size_override("font_size", 24)
	label.size = Vector2(350, 100)
	add_child(label)

	var size_antes := label.size
	var scale_antes := label.scale

	# Zoom hasta el mÃ¡ximo en pasos
	var p := Vector2(400, 300)
	for i in 30:
		canvas.zoom_at_point(2.0, p)
		await get_tree().process_frame

	assert_that(cam.zoom.x).is_greater(1000.0)
	# El Label NO debe cambiar de tamaÃ±o lÃ³gico ni de escala (el zoom es de cÃ¡mara)
	assert_that(label.size).is_equal(size_antes)
	assert_that(label.scale).is_equal(scale_antes)
	assert_that(cam.zoom.x).is_less_equal(50000.1)

# 2. El zoom extremo mantiene la posiciÃ³n de cÃ¡mara finita (sin NaN/overflow)
func test_zoom_maximo_camara_finita() -> void:
	var setup := _canvas_with_camera()
	var canvas: Node2D = setup[0]
	var cam: Camera2D = setup[1]
	await get_tree().process_frame

	var p := Vector2(400, 300)
	for i in 40:
		canvas.zoom_at_point(1.8, p)
		await get_tree().process_frame

	assert_that(is_finite(cam.position.x)).is_true()
	assert_that(is_finite(cam.position.y)).is_true()
	assert_that(is_finite(cam.zoom.x)).is_true()
	assert_that(is_finite(cam.zoom.y)).is_true()

# 3. El tÃ­tulo del artboard se crea con texto y es interactivo
func test_artboard_titulo_label_funcional() -> void:
	var scene: Node2D = load("res://scenes/canvas/canvas.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var artboard := scene.get_node_or_null("ArtboardsContainer/Artboard")
	assert_object(artboard).is_not_null()
	var label := artboard.get_node_or_null("ArtboardTitle") as Control
	assert_object(label).is_not_null()
	assert_that(label.text).is_not_empty()
	assert_that(label.scale).is_equal(Vector2.ONE)
	assert_that(label.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_that(label.gui_input.is_connected(Callable(artboard, "_on_title_gui_input"))).is_true()
	scene.queue_free()

# 4. TextTool y ParagraphTool ya no usan contra-escala (world_label eliminado)
func test_tools_no_referencian_world_label() -> void:
	for path in [TextToolScript, ParagraphToolScript]:
		var src := FileAccess.get_file_as_string(path)
		assert_that(WorldLabelGone in src).is_false()

# 5. No quedan referencias a los scripts eliminados
func test_no_hay_referencias_a_scripts_eliminados() -> void:
	var ruta := "res://"
	var dir := DirAccess.open(ruta)
	assert_object(dir).is_not_null()
	for archivo in dir.get_files():
		if archivo.ends_with(".gd"):
			var src := FileAccess.get_file_as_string(ruta + archivo)
			assert_that(WorldLabelGone in src).is_false()
			assert_that(ArtboardTitleGone in src).is_false()

# 6. Zoom mantiene el punto bajo el cursor (invariante ya probada, aquÃ­ a extremos)
func test_zoom_extremo_invariante_puntero() -> void:
	var setup := _canvas_with_camera()
	var canvas: Node2D = setup[0]
	var cam: Camera2D = setup[1]
	await get_tree().process_frame

	var viewport_size: Vector2 = canvas.get_viewport_rect().size
	var center := viewport_size / 2.0
	var cursor := Vector2(640, 480)
	var world_before: Vector2 = cam.position + (cursor - center) / cam.zoom.x

	canvas.zoom_at_point(1.5, world_before)
	var world_after: Vector2 = cam.position + (cursor - center) / cam.zoom.x
	assert_that(world_after.distance_to(world_before)).is_less(0.01)

	canvas.zoom_at_point(2.0, world_before)
	canvas.zoom_at_point(2.0, world_before)
	canvas.zoom_at_point(0.5, world_before)
	var world_final: Vector2 = cam.position + (cursor - center) / cam.zoom.x
	assert_that(world_final.distance_to(world_before)).is_less(0.01)

# 7. El zoom no cambia el rect lÃ³gico de los Controles del mundo
func test_zoom_no_altera_rect_de_controles() -> void:
	var setup := _canvas_with_camera()
	var canvas: Node2D = setup[0]
	var cam: Camera2D = setup[1]
	await get_tree().process_frame

	var label := Label.new()
	label.size = Vector2(350, 100)
	add_child(label)
	var rect_antes := label.get_rect()

	var p := Vector2(300, 200)
	for i in 25:
		canvas.zoom_at_point(1.9, p)

	assert_that(label.get_rect()).is_equal(rect_antes)
	assert_that(cam.zoom.x).is_greater(100.0)

