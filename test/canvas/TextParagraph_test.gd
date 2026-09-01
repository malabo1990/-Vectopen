extends GdUnitTestSuite

## REGRESIÓN — Bug reportado: al editar texto/párrafo, el bounding box y el
## LineEdit quedan desincronizados: las líneas del texto se salen del bbox.
##
## Aquí validamos la invariante real: tras crear (y tras editar), el rect
## de la selección (meta width/height) ENVUELVE el contenido del Label, y el
## LineEdit/TitleEdit coincide con el DisplayLabel.

const TEXT_TOOL := "res://script_gdscript/tools/TextTool.gd"
const PARA_TOOL := "res://script_gdscript/tools/ParagraphTool.gd"

func _canvas_real() -> Node2D:
	var scene: Node2D = load("res://scenes/canvas/canvas.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	return scene

func _tool(path: String, scene: Node2D, artboard: Node2D) -> Node:
	var tool: Node = (load(path) as GDScript).new()
	add_child(tool)
	tool.set("target_artboard", artboard)
	tool.set("canvas", scene)
	return tool

# ------------------------------------------------------------------ TEXTO
func test_text_tool_label_y_edit_iguales() -> void:
	var scene := await _canvas_real()
	var artboard: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _tool(TEXT_TOOL, scene, artboard)

	tool._create_new_title_at(Vector2(200, 200))
	await get_tree().process_frame

	var shape := _find_shape(artboard, "Texto")
	assert_object(shape).is_not_null()
	var label := shape.get_node_or_null("DisplayLabel") as Control
	var edit := shape.get_node_or_null("TitleEdit") as Control
	assert_object(label).is_not_null()
	assert_object(edit).is_not_null()

	var meta_w: float = shape.get_meta("width") if shape.has_meta("width") else 0.0
	var meta_h: float = shape.get_meta("height") if shape.has_meta("height") else 0.0
	assert_that(meta_w).is_greater(0.0)
	assert_that(meta_h).is_greater(0.0)
	# El LineEdit debe cubrir exactamente el rect del label (regla del bug)
	assert_that(edit.size).is_equal(label.size)
	# El bbox meta envuelve el contenido del label
	assert_that(label.size.x).is_less_equal(meta_w + 0.5)
	assert_that(label.size.y).is_less_equal(meta_h + 0.5)
	# El label es WorldTextLabel (re-render nítido) y su font base es 24
	assert_that(label is WorldTextLabel).is_true()
	assert_that((label as WorldTextLabel).base_font_size).is_equal(24)
	scene.queue_free()

# ------------------------------------------------------------------ PÁRRAFO
func test_para_tool_label_wrap_dentro_bbox() -> void:
	var scene := await _canvas_real()
	var artboard: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _tool(PARA_TOOL, scene, artboard)

	tool._create_new_paragraph_at(Vector2(200, 200))
	await get_tree().process_frame

	var shape := _find_shape(artboard, "Párrafo")
	assert_object(shape).is_not_null()
	var label := shape.get_node_or_null("DisplayLabel") as Control
	var edit := shape.get_node_or_null("MultiLineEdit") as Control
	assert_object(label).is_not_null()
	assert_object(edit).is_not_null()

	var meta_w: float = shape.get_meta("width") if shape.has_meta("width") else 0.0
	var meta_h: float = shape.get_meta("height") if shape.has_meta("height") else 0.0
	assert_that(meta_w).is_greater(0.0)
	assert_that(meta_h).is_greater(0.0)
	assert_that(edit.size).is_equal(label.size)
	assert_that(label.size.x).is_less_equal(meta_w + 0.5)
	assert_that(label.size.y).is_less_equal(meta_h + 0.5)
	scene.queue_free()

# EL BUG: tras editar guardando un texto LARGO, el bbox debe re-sincronizarse
func test_para_tras_editar_texto_largo_bbox_eso_contiene() -> void:
	var scene := await _canvas_real()
	var artboard: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _tool(PARA_TOOL, scene, artboard)

	tool._create_new_paragraph_at(Vector2(200, 200))
	await get_tree().process_frame
	var shape := _find_shape(artboard, "Párrafo")

	var label := shape.get_node_or_null("DisplayLabel") as Control
	var multi_edit := shape.get_node_or_null("MultiLineEdit") as TextEdit

	# Simulamos edición: texto MUCHO más largo y guardar
	var texto_largo := "Este es un texto de prueba con LÍNEAS SUPER LARGAS. Este es un texto de prueba con LÍNEAS SUPER LARGAS. Este es un texto de prueba con LÍNEAS SUPER LARGAS. Este es un texto de prueba con LÍNEAS SUPER LARGAS. FIN."
	tool.is_editing = true
	tool.current_editing_shape = shape
	multi_edit.text = texto_largo
	tool._finish_editing_and_save()
	await get_tree().process_frame

	assert_that(shape.get_meta("text")).is_equal(texto_largo)
	assert_that(label.text).is_equal(texto_largo)
	assert_that(label.visible).is_true()

	# REGLA: el meta con el contenido debe re-escancarse o al menos el rect
	# final debe contener el texto renderizado.
	var meta_w: float = shape.get_meta("width") if shape.has_meta("width") else 0.0
	var meta_h: float = shape.get_meta("height") if shape.has_meta("height") else 0.0
	var min_world: Vector2 = label.get_world_minimum_size()
	var texto_dentro: bool = min_world.x <= meta_w + 1.0 and min_world.y <= meta_h + 1.0
	# Si no re-escanea: min_world será mayor que el meta → bug confirmado.
	assert_that(texto_dentro).is_true()
	scene.queue_free()

func _find_shape(artboard: Node2D, name_cont: String) -> Node2D:
	for child in artboard.get_children():
		if child.name == name_cont:
			return child
	return null
