extends GdUnitTestSuite

## Test Suite para creación de texto interactivo estilo Affinity
## y encadenamiento de marcos de párrafo (Text Threading estilo InDesign/Affinity Publisher)

const TEXT_TOOL := "res://script_gdscript/tools/TextTool.gd"
const PARA_TOOL := "res://script_gdscript/tools/ParagraphTool.gd"
const ParagraphThreading := preload("res://script_gdscript/tools/ParagraphThreading.gd")

func _canvas_real() -> Node2D:
	var scene: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	return scene

func _tool(path: String, scene: Node2D, artboard: Node2D) -> Node:
	var tool: Node = auto_free((load(path) as GDScript).new())
	add_child(tool)
	tool.set("target_artboard", artboard)
	tool.set("canvas", scene)
	return tool

func _find_shape(artboard: Node2D, prefix: String) -> Node2D:
	for child in artboard.get_children():
		if child.name.begins_with(prefix):
			return child
	return null

# ── 1. AFFINITY-STYLE DRAG EN TEXT TOOL ───────────────────────────────────────

func test_text_tool_drag_creation_and_font_size() -> void:
	var scene := await _canvas_real()
	var artboard: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _tool(TEXT_TOOL, scene, artboard)

	# Simular inicio de arrastre en vacío
	var start_pos := Vector2(150, 150)
	tool._start_drag_creation(start_pos)
	assert_bool(tool.is_drag_creating).is_true()
	assert_int(tool.drag_font_size).is_equal(24)

	# Simular arrastre hacia abajo para aumentar tamaño a ~54 pt
	var drag_pos := Vector2(150, 204)
	tool._process_drag_creation(drag_pos)
	assert_int(tool.drag_font_size).is_equal(54)

	# Simular soltado de ratón para confirmar
	tool._finish_drag_creation(drag_pos)
	assert_bool(tool.is_drag_creating).is_false()

	await get_tree().process_frame

	var title := _find_shape(artboard, "Texto")
	assert_object(title).is_not_null()
	assert_int(title.get_meta("font_size")).is_equal(54)

	var label := title.get_node_or_null("DisplayLabel") as WorldTextLabel
	assert_object(label).is_not_null()
	assert_int(label.base_font_size).is_equal(54)

# ── 2. MOTOR DE TEXT THREADING (DIVISIÓN Y FLUJO) ─────────────────────────────

func test_paragraph_threading_split_text_to_fit() -> void:
	var font = ThemeDB.fallback_font
	var story := "El rápido zorro marrón salta sobre el perezoso perro dormido en una hermosa tarde de verano en el parque municipal con amigos y alegría."
	
	# Un marco pequeño (180x40) con fuente 20: solo caben 1 o 2 líneas
	var res: Dictionary = ParagraphThreading.split_text_to_fit(story, font, 20, 180.0, 40.0)
	
	assert_str(res["fits"]).is_not_empty()
	assert_str(res["overflow"]).is_not_empty()
	
	# El texto que cupo (reemplazando saltos de línea por espacio) debe coincidir con el inicio de la historia
	var fits_normalized: String = res["fits"].replace("\n", " ").strip_edges()
	assert_bool(story.begins_with(fits_normalized)).is_true()
	# Y el desbordamiento debe continuar hasta el final de la historia
	assert_bool(story.ends_with(res["overflow"].strip_edges())).is_true()

func test_paragraph_threading_link_and_reflow() -> void:
	var scene := await _canvas_real()
	var artboard: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _tool(PARA_TOOL, scene, artboard)

	# Crear Párrafo 1
	var p1: Node2D = tool._create_new_paragraph_at(Vector2(50, 50))
	p1.set_meta("width", 200.0)
	p1.set_meta("height", 50.0)
	var story := "Capítulo Uno: En un lugar de la Mancha, de cuyo nombre no quiero acordarme, no ha mucho tiempo que vivía un hidalgo de los de lanza en astillero, adarga antigua, rocín flaco y galgo corredor."
	p1.set_meta("text", story)

	# Crear Párrafo 2
	var p2: Node2D = tool._create_new_paragraph_at(Vector2(300, 50))
	p2.set_meta("width", 200.0)
	p2.set_meta("height", 120.0)
	p2.set_meta("text", "")

	# Enlazar p1 -> p2
	var ok: bool = ParagraphThreading.link(p1, p2)
	assert_bool(ok).is_true()
	assert_str(str(p1.get_meta("next_paragraph"))).is_equal(str(p2.get_path()))
	assert_str(str(p2.get_meta("prev_paragraph"))).is_equal(str(p1.get_path()))

	# Verificar que el texto fluyó de p1 a p2
	var label1 := p1.get_node("DisplayLabel") as WorldTextLabel
	var label2 := p2.get_node("DisplayLabel") as WorldTextLabel

	assert_str(label1.text).is_not_empty()
	assert_str(label2.text).is_not_empty()
	# La suma de ambos textos debe contener la historia completa
	assert_bool(label1.text.length() < story.length()).is_true()
	var label2_norm: String = label2.text.replace("\n", " ").strip_edges()
	assert_bool(story.contains(label2_norm.substr(0, 20))).is_true()

	# ── 3. REDIMENSIONADO Y REFLUJO EN TIEMPO REAL ────────────────────────────
	# Si agrandamos p1 a 800 de alto, toda la historia cabe en p1 y p2 queda vacío
	# (a 200 px de ancho y fuente 24 la historia ocupa ~13 líneas: 400 no bastaba).
	p1.set_meta("height", 800.0)
	ParagraphThreading.reflow_chain(p1)

	var label1_norm: String = label1.text.replace("\n", " ").strip_edges()
	assert_str(label1_norm).is_equal(story)
	assert_str(label2.text).is_empty()
	assert_bool(p1.get_meta("is_overflowing")).is_false()

func test_paragraph_tool_out_port_detection() -> void:
	var scene := await _canvas_real()
	var artboard: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _tool(PARA_TOOL, scene, artboard)

	var p1: Node2D = tool._create_new_paragraph_at(Vector2(100, 100))
	p1.set_meta("width", 300.0)
	p1.set_meta("height", 100.0)

	var port_rect: Rect2 = ParagraphThreading.get_out_port_rect(p1)
	assert_bool(port_rect.size.x > 0.0).is_true()

	# Punto dentro del puerto
	var inside_pt: Vector2 = port_rect.position + Vector2(4, 4)
	assert_bool(ParagraphThreading.is_point_in_out_port(p1, inside_pt)).is_true()

	# Punto fuera del puerto
	var outside_pt: Vector2 = p1.global_position + Vector2(20, 20)
	assert_bool(ParagraphThreading.is_point_in_out_port(p1, outside_pt)).is_false()

	# Detección por tool
	var found: Node2D = tool._find_out_port_at(inside_pt)
	assert_object(found).is_equal(p1)
