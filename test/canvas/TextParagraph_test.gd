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
	# Estas medidas comparan tamaños de Control sin escalar: valen al 100 %
	# (la app abre al 70 %; la etiqueta se escala con el zoom).
	if scene.has_method("_reset_camera"):
		scene._reset_camera(1.0)
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

func test_para_click_afuera_sale_a_movetool_muestra_bb_y_permite_drag() -> void:
	var scene := await _canvas_real()
	var artboard: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _tool(PARA_TOOL, scene, artboard)

	var shape: Node2D = tool._create_new_paragraph_at(Vector2(200, 200))
	await get_tree().process_frame

	# 1. Entrar a modo edición
	tool.target_artboard = artboard
	tool._check_and_trigger_edit_at(Vector2(250, 250), shape)
	await get_tree().process_frame

	assert_that(tool.is_editing).is_true()
	assert_that(SelectionManager.has_active_text_edit()).is_true()

	# 2. Clic fuera del área del párrafo (en lienzo vacío, p.ej. 700, 700)
	var ev_outside := InputEventMouseButton.new()
	ev_outside.button_index = MOUSE_BUTTON_LEFT
	ev_outside.pressed = true
	ev_outside.position = Vector2(700, 700)
	ev_outside.global_position = Vector2(700, 700)
	var consumed: bool = tool.handle_input(ev_outside)
	assert_that(consumed).is_true()
	await get_tree().process_frame

	# 3. Verificar que salió de edición, pasó a MoveTool, y el BB está activo y visible
	assert_that(tool.is_editing).is_false()
	assert_that(SelectionManager.has_active_text_edit()).is_false()
	assert_that(SelectionManager.get_selected()).contains_exactly([shape])

	var cur_tool = scene.current_tool
	assert_object(cur_tool).is_not_null()
	assert_that(cur_tool.get_class_name()).is_equal("MoveTool")
	assert_that(cur_tool.selected_shapes).contains_exactly([shape])
	assert_object(cur_tool._bounding_box).is_not_null()
	assert_that(cur_tool._bounding_box.visible).is_true()

	# 4. Verificar arrastre con MoveTool para mover el párrafo
	var init_pos: Vector2 = shape.global_position
	# Los eventos llevan coordenadas de PANTALLA: la cámara centra el
	# artboard, así que el punto del mundo se pasa por la transformación.
	var click_pt: Vector2 = scene.get_canvas_transform() * (init_pos + Vector2(50, 30))

	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.position = click_pt
	ev_press.global_position = click_pt
	cur_tool.handle_input(ev_press)

	var ev_motion := InputEventMouseMotion.new()
	ev_motion.position = click_pt + Vector2(100, 50)
	ev_motion.global_position = click_pt + Vector2(100, 50)
	ev_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	cur_tool.handle_input(ev_motion)

	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	ev_release.position = click_pt + Vector2(100, 50)
	ev_release.global_position = click_pt + Vector2(100, 50)
	cur_tool.handle_input(ev_release)
	await get_tree().process_frame

	assert_that(shape.global_position).is_not_equal(init_pos)
	assert_that(cur_tool._bounding_box.visible).is_true()

	scene.queue_free()

func _find_shape(artboard: Node2D, name_cont: String) -> Node2D:
	for child in artboard.get_children():
		if child.name == name_cont:
			return child
	return null
