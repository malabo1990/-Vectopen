extends GdUnitTestSuite

## SISTEMA CORE del Inspector: lectura/escritura de propiedades de la selección
## con undo, multiselección (mixed), y alineación / distribución.

const CANVAS := "res://scenes/canvas/canvas.tscn"

func _scene() -> Node2D:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	return s

func _tool(s: Node2D):
	var t = s.current_tool
	if not (t and t.get_class_name() == "MoveTool"):
		s.switch_tool("move"); t = s.current_tool
	return t

func _rect(parent: Node, pos: Vector2, size := Vector2(80, 60)) -> VectorRectangle:
	var r := VectorRectangle.new()
	r.size = size
	r.fill_color = Color(0.2, 0.4, 0.9)
	parent.add_child(r)
	r.global_position = pos
	r.set_doc_position(DVec2.from_v2(r.position))   # doc-space = pos local (como las herramientas)
	r.set_doc_extent(DVec2.from_v2(size))
	return r

func _ab(s: Node2D) -> ArtboardEditor:
	return (s.get_node("manager_script") as ArtboardManager).get_active_artboard()


func test_lee_propiedades_de_una_figura() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var r := _rect(_ab(s), Vector2(150, 200), Vector2(120, 80))
	r.set_doc_rotation(deg_to_rad(30.0))
	r.stroke_width = 4.0
	await get_tree().process_frame

	t.selected_shapes.assign([r])
	InspectorCore._sync_selection()
	var p := InspectorCore.current_props()

	# pos = doc-space (relativo al artboard, como un editor profesional) → == get_doc_position
	assert_float(p["pos_x"]["value"]).is_equal_approx(r.get_doc_position().x, 0.01)
	assert_float(p["pos_y"]["value"]).is_equal_approx(r.get_doc_position().y, 0.01)
	assert_float(p["width"]["value"]).is_equal_approx(120.0, 0.5)
	assert_float(p["height"]["value"]).is_equal_approx(80.0, 0.5)
	assert_float(p["rotation"]["value"]).is_equal_approx(30.0, 0.1)
	assert_float(p["stroke_width"]["value"]).is_equal_approx(4.0, 0.01)
	assert_that(p["fill_color"]["value"]).is_equal(Color(0.2, 0.4, 0.9))
	assert_bool(p["pos_x"]["mixed"]).is_false()


func test_escribir_pos_x_mueve_y_es_undo_able() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var r := _rect(_ab(s), Vector2(100, 100))
	await get_tree().process_frame
	t.selected_shapes.assign([r])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	var y0 := r.get_doc_position().y
	InspectorCore.apply("pos_x", 333.0)
	assert_float(r.get_doc_position().x).is_equal_approx(333.0, 0.01)
	assert_float(r.get_doc_position().y).is_equal_approx(y0, 0.01)   # Y intacta
	assert_bool(HistoryManager.can_undo()).is_true()

	HistoryManager.undo(); await get_tree().process_frame
	assert_float(r.get_doc_position().x).is_equal_approx(0.0, 0.5)   # local ≈ 0 (artboard en 100,100)
	HistoryManager.redo(); await get_tree().process_frame
	assert_float(r.get_doc_position().x).is_equal_approx(333.0, 0.01)
	HistoryManager.clear()


func test_escribir_width_y_rotation_y_color() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var r := _rect(_ab(s), Vector2(200, 200), Vector2(50, 50))
	await get_tree().process_frame
	t.selected_shapes.assign([r])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	InspectorCore.apply("width", 140.0)
	assert_float((r.get("size") as Vector2).x).is_equal_approx(140.0, 0.5)
	InspectorCore.apply("rotation", 45.0)
	assert_float(r.global_rotation).is_equal_approx(deg_to_rad(45.0), 0.001)
	InspectorCore.apply("fill_color", Color.RED)
	assert_that(r.fill_color).is_equal(Color.RED)

	# 3 acciones → 3 undos
	HistoryManager.undo(); await get_tree().process_frame
	assert_that(r.fill_color).is_equal(Color(0.2, 0.4, 0.9))
	HistoryManager.undo(); await get_tree().process_frame
	assert_float(r.global_rotation).is_equal_approx(0.0, 0.001)
	HistoryManager.undo(); await get_tree().process_frame
	assert_float((r.get("size") as Vector2).x).is_equal_approx(50.0, 0.5)
	HistoryManager.clear()


func test_multiseleccion_valores_comunes_y_mixed() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var a := _rect(_ab(s), Vector2(100, 100), Vector2(60, 60)); a.fill_color = Color.RED
	var b := _rect(_ab(s), Vector2(300, 100), Vector2(60, 60)); b.fill_color = Color.RED
	var c := _rect(_ab(s), Vector2(500, 100), Vector2(60, 60)); c.fill_color = Color.BLUE
	await get_tree().process_frame
	t.selected_shapes.assign([a, b, c])
	InspectorCore._sync_selection()
	var p := InspectorCore.current_props()

	assert_bool(p["pos_y"]["mixed"]).is_false()      # todas en y=100
	assert_bool(p["width"]["mixed"]).is_false()       # todas 60
	assert_bool(p["fill_color"]["mixed"]).is_true()   # red/red/blue → mixto
	assert_bool(p.has("name")).is_false()             # nombre no aplica en multi

	# escribir fill en multi → todas iguales, UNA acción de undo
	HistoryManager.clear()
	InspectorCore.apply("fill_color", Color.GREEN)
	assert_that(a.fill_color).is_equal(Color.GREEN)
	assert_that(c.fill_color).is_equal(Color.GREEN)
	HistoryManager.undo(); await get_tree().process_frame
	assert_that(a.fill_color).is_equal(Color.RED)
	assert_that(c.fill_color).is_equal(Color.BLUE)
	HistoryManager.clear()


func test_alinear_izquierda_a_los_bordes_de_la_seleccion() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	# _global_rect usa el ORIGEN como esquina sup-izq para VectorRectangle
	var a := _rect(_ab(s), Vector2(100, 100), Vector2(40, 40))
	var b := _rect(_ab(s), Vector2(250, 200), Vector2(40, 40))
	var c := _rect(_ab(s), Vector2(400, 300), Vector2(40, 40))
	await get_tree().process_frame
	t.selected_shapes.assign([a, b, c])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	InspectorCore.align("left")
	# todas comparten el borde izquierdo (el mínimo x = 100)
	assert_float(a.global_position.x).is_equal_approx(100.0, 0.5)
	assert_float(b.global_position.x).is_equal_approx(100.0, 0.5)
	assert_float(c.global_position.x).is_equal_approx(100.0, 0.5)
	# Y no se toca
	assert_float(b.global_position.y).is_equal_approx(200.0, 0.5)

	HistoryManager.undo(); await get_tree().process_frame
	assert_float(b.global_position.x).is_equal_approx(250.0, 0.5)
	HistoryManager.clear()


func test_distribuir_horizontal_espaciado_uniforme() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var a := _rect(_ab(s), Vector2(0, 100), Vector2(20, 20))
	var b := _rect(_ab(s), Vector2(35, 100), Vector2(20, 20))   # desordenada
	var d := _rect(_ab(s), Vector2(300, 100), Vector2(20, 20))
	await get_tree().process_frame
	t.selected_shapes.assign([a, b, d])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	InspectorCore.distribute("h")
	# primera y última no se mueven; la del medio queda a espaciado uniforme
	var gap_ab := b.global_position.x - (a.global_position.x + 20)
	var gap_bd := d.global_position.x - (b.global_position.x + 20)
	assert_float(gap_ab).is_equal_approx(gap_bd, 0.5)
	assert_float(a.global_position.x).is_equal_approx(0.0, 0.5)
	assert_float(d.global_position.x).is_equal_approx(300.0, 0.5)
	HistoryManager.clear()


## Alinear en los DOS ejes a la vez (["left","top"]) en una sola acción de undo.
func test_alinear_combo_dos_ejes_una_accion() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var a := _rect(_ab(s), Vector2(100, 100), Vector2(40, 40))
	var b := _rect(_ab(s), Vector2(300, 250), Vector2(40, 40))
	await get_tree().process_frame
	t.selected_shapes.assign([a, b])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	InspectorCore.align(["left", "top"])
	# ambas comparten esquina sup-izq (min x=100, min y=100)
	assert_vector(a.global_position).is_equal_approx(Vector2(100, 100), Vector2(0.5, 0.5))
	assert_vector(b.global_position).is_equal_approx(Vector2(100, 100), Vector2(0.5, 0.5))

	# UNA sola acción → un undo lo revierte todo
	HistoryManager.undo(); await get_tree().process_frame
	assert_vector(b.global_position).is_equal_approx(Vector2(300, 250), Vector2(0.5, 0.5))
	assert_bool(HistoryManager.can_undo()).is_false()
	HistoryManager.clear()


## Muestra de color del menú contextual → aplica fill a la selección (con undo).
func test_swatch_de_color_aplica_fill() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var r := _rect(_ab(s), Vector2(200, 200))
	r.fill_color = Color.WHITE
	await get_tree().process_frame
	t.selected_shapes.assign([r])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	# ListaColor.gd sobre una FlowContainer con muestras (como en tool_in_mouse.tscn)
	var fc: FlowContainer = auto_free(FlowContainer.new())
	fc.set_script(load("res://script_gdscript/ui/ListaColor.gd"))
	for i in 5:
		var cr := ColorRect.new()
		cr.color = Color(0.1 * i, 0.2, 0.3)
		fc.add_child(cr)
	add_child(fc)
	await get_tree().process_frame
	await get_tree().process_frame   # _ready hace await 1 frame

	var swatch: ColorRect = fc.get_child(2) as ColorRect
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	swatch.gui_input.emit(ev)
	await get_tree().process_frame

	assert_that(r.fill_color).is_equal(swatch.color)
	assert_bool(HistoryManager.can_undo()).is_true()
	HistoryManager.undo(); await get_tree().process_frame
	assert_that(r.fill_color).is_equal(Color.WHITE)
	HistoryManager.clear()


## Tamaño de fuente de una figura de texto: meta + etiqueta de display, con undo.
func test_escribir_font_size_en_texto_con_undo() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)

	var txt := Node2D.new()
	txt.set_meta("shape_type", "text_title")
	txt.set_meta("font_size", 24)
	var dl := Label.new()
	dl.name = "DisplayLabel"
	txt.add_child(dl)
	_ab(s).add_child(txt)
	await get_tree().process_frame

	t.selected_shapes.assign([txt])
	InspectorCore._sync_selection()
	var p := InspectorCore.current_props()
	assert_float(p["font_size"]["value"]).is_equal_approx(24.0, 0.01)

	HistoryManager.clear()
	InspectorCore.apply("font_size", 48.0)
	assert_int(int(txt.get_meta("font_size"))).is_equal(48)
	assert_int(dl.get_theme_font_size("font_size")).is_equal(48)
	assert_bool(HistoryManager.can_undo()).is_true()

	HistoryManager.undo(); await get_tree().process_frame
	assert_int(int(txt.get_meta("font_size"))).is_equal(24)
	HistoryManager.clear()


## El inspector opera sobre un POLÍGONO: color de relleno/trazo y grosor
## directos; ancho/alto escalando los vértices sobre el centro. Todo con undo.
func test_inspector_con_poligono_estilo_y_tamano() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)

	var poly := VectorPolygon.new()
	poly.vertices = PackedVector2Array([Vector2(-40, -30), Vector2(40, -30), Vector2(40, 30), Vector2(-40, 30)])
	poly.closed = true
	poly.fill_color = Color.WHITE
	poly.stroke_width = 1.0
	_ab(s).add_child(poly)
	poly.global_position = Vector2(200, 200)
	poly.set_doc_position(DVec2.from_v2(poly.position))
	poly.set_doc_vertices(DVec2.array_from_v2(poly.vertices))
	await get_tree().process_frame

	t.selected_shapes.assign([poly])
	InspectorCore._sync_selection()
	var p := InspectorCore.current_props()
	assert_float(p["width"]["value"]).is_equal_approx(80.0, 1.0)
	assert_float(p["height"]["value"]).is_equal_approx(60.0, 1.0)

	HistoryManager.clear()
	InspectorCore.apply("fill_color", Color.RED)
	InspectorCore.apply("stroke_width", 6.0)
	assert_that(poly.fill_color).is_equal(Color.RED)
	assert_float(poly.stroke_width).is_equal_approx(6.0, 0.01)

	InspectorCore.apply("width", 160.0)   # x2
	var b := _pv2_bounds(poly.vertices)
	assert_float(b.size.x).is_equal_approx(160.0, 1.0)
	assert_float(b.size.y).is_equal_approx(60.0, 1.0)   # alto intacto

	HistoryManager.undo(); await get_tree().process_frame   # deshace width
	assert_float(_pv2_bounds(poly.vertices).size.x).is_equal_approx(80.0, 1.5)
	HistoryManager.clear()


## El inspector estiliza un TRAZO BÉZIER (Path2D + VectorPath.gd) igual que
## cualquier figura: fill/stroke/grosor, con undo.
func test_inspector_con_trazo_bezier() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)

	var vp := Path2D.new()
	vp.set_script(load("res://script_gdscript/shapes/VectorPath.gd"))
	var cu := Curve2D.new()
	cu.add_point(Vector2(0, 0))
	cu.add_point(Vector2(100, 0))
	cu.add_point(Vector2(100, 80))
	vp.curve = cu
	vp.set("closed", true)
	_ab(s).add_child(vp)
	vp.global_position = Vector2(150, 150)
	await get_tree().process_frame

	t.selected_shapes.assign([vp])
	InspectorCore._sync_selection()
	var p := InspectorCore.current_props()
	assert_bool(p.has("stroke_color")).is_true()
	assert_bool(p.has("fill_color")).is_true()

	HistoryManager.clear()
	InspectorCore.apply("stroke_color", Color.BLUE)
	InspectorCore.apply("stroke_width", 5.0)
	InspectorCore.apply("fill_color", Color(0, 1, 0, 0.5))
	assert_that(vp.get("stroke_color")).is_equal(Color.BLUE)
	assert_float(vp.get("stroke_width")).is_equal_approx(5.0, 0.01)

	HistoryManager.undo(); await get_tree().process_frame   # deshace fill
	HistoryManager.undo(); await get_tree().process_frame   # deshace grosor
	assert_float(vp.get("stroke_width")).is_equal_approx(2.0, 0.01)
	HistoryManager.clear()


## Line2D: color/grosor por default_color/width y ancho escalando los puntos.
func test_inspector_con_line2d() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)

	var ln := Line2D.new()
	ln.points = PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 50)])
	ln.width = 3.0
	ln.default_color = Color.BLACK
	_ab(s).add_child(ln)
	ln.global_position = Vector2(120, 120)
	await get_tree().process_frame

	t.selected_shapes.assign([ln])
	InspectorCore._sync_selection()
	var p := InspectorCore.current_props()
	assert_float(p["stroke_width"]["value"]).is_equal_approx(3.0, 0.01)

	HistoryManager.clear()
	InspectorCore.apply("stroke_color", Color.RED)
	assert_that(ln.default_color).is_equal(Color.RED)
	InspectorCore.apply("width", 200.0)   # x2
	assert_float(_pv2_bounds(ln.points).size.x).is_equal_approx(200.0, 1.0)
	HistoryManager.clear()


## Familia tipográfica de un texto: meta + fuente (FontCore) en el DisplayLabel,
## con undo. WorldTextLabel resuelve la familia desde la meta del contenedor.
func test_inspector_font_family_en_texto() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)

	var txt := Node2D.new()
	txt.set_meta("shape_type", "text_title")
	txt.set_meta("font_size", 24)
	var dl := WorldTextLabel.new()
	dl.name = "DisplayLabel"
	dl.text = "Aa"
	txt.add_child(dl)
	_ab(s).add_child(txt)
	await get_tree().process_frame

	t.selected_shapes.assign([txt])
	InspectorCore._sync_selection()
	assert_str(InspectorCore.current_props()["font_family"]["value"]).is_equal("Inter")

	HistoryManager.clear()
	InspectorCore.apply("font_family", "Inter")   # no-op (igual) → sin undo
	assert_bool(HistoryManager.can_undo()).is_false()

	# elegimos una familia real del sistema si la hay, si no un peso variado
	InspectorCore.apply("font_weight", 700)
	assert_int(int(txt.get_meta("font_weight"))).is_equal(700)
	var applied: Font = dl.get_theme_font("font")
	assert_object(applied).is_same(FontCore.get_font(FontCore.spec_from_node(txt)))

	HistoryManager.undo(); await get_tree().process_frame
	assert_int(int(txt.get_meta("font_weight"))).is_equal(400)
	HistoryManager.clear()


## Texto: color de relleno / contorno / grosor de contorno / alineación /
## contenido — todo vía InspectorCore, con undo, aplicado al DisplayLabel.
func test_inspector_texto_color_alineacion_y_contenido() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)

	var txt := Node2D.new()
	txt.set_meta("shape_type", "text_title")
	txt.set_meta("text", "hola mundo")
	txt.set_meta("font_size", 24)
	var dl := Label.new(); dl.name = "DisplayLabel"; dl.text = "hola mundo"
	txt.add_child(dl)
	_ab(s).add_child(txt)
	await get_tree().process_frame

	t.selected_shapes.assign([txt]); InspectorCore._sync_selection()
	HistoryManager.clear()

	# color de relleno del texto
	InspectorCore.apply("fill_color", Color.RED)
	assert_that(dl.get_theme_color("font_color")).is_equal(Color.RED)
	assert_that(txt.get_meta("text_color")).is_equal(Color.RED)

	# contorno
	InspectorCore.apply("stroke_color", Color.BLUE)
	InspectorCore.apply("stroke_width", 3.0)
	assert_that(dl.get_theme_color("font_outline_color")).is_equal(Color.BLUE)
	assert_int(dl.get_theme_constant("outline_size")).is_equal(3)

	# alineación
	InspectorCore.apply("text_align", "center")
	assert_int(dl.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	assert_str(InspectorCore.current_props()["text_align"]["value"]).is_equal("center")

	# contenido (transformación de caja)
	InspectorCore.apply("text", "HOLA MUNDO")
	assert_str(String(txt.get_meta("text"))).is_equal("HOLA MUNDO")
	assert_str(dl.text).is_equal("HOLA MUNDO")

	HistoryManager.undo(); await get_tree().process_frame
	assert_str(dl.text).is_equal("hola mundo")
	HistoryManager.clear()


## Relleno con degradado en un rectángulo: fill_paint lee/escribe, con undo, y
## el color plano lo revierte. Serialización cubierta en CanvasSerializer_test.
func test_fill_paint_degradado_lineal() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var r := _rect(_ab(s), Vector2(200, 200), Vector2(80, 80))
	await get_tree().process_frame
	t.selected_shapes.assign([r]); InspectorCore._sync_selection()

	# lectura inicial = sólido
	assert_str(InspectorCore.current_props()["fill_paint"]["value"]["type"]).is_equal("solid")

	HistoryManager.clear()
	InspectorCore.apply("fill_paint", {
		"type": "linear", "angle": deg_to_rad(45),
		"stops": [[0.0, Color.RED], [1.0, Color.BLUE]]})
	assert_bool(r.has_gradient_fill()).is_true()
	assert_int(int(r.fill_gradient_type)).is_equal(0)
	assert_float(r.fill_gradient_angle).is_equal_approx(deg_to_rad(45), 0.001)

	var p := InspectorCore.current_props()
	assert_str(p["fill_paint"]["value"]["type"]).is_equal("linear")

	HistoryManager.undo(); await get_tree().process_frame
	assert_bool(r.has_gradient_fill()).is_false()
	HistoryManager.clear()


## Sprite2D (imagen): ancho/alto redimensionan escalando el nodo, con undo.
func test_inspector_redimensiona_sprite2d_por_escala() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)

	var img := Image.create(100, 50, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.6, 0.9, 1))
	var sp := Sprite2D.new()
	sp.texture = ImageTexture.create_from_image(img)
	_ab(s).add_child(sp)
	sp.global_position = Vector2(300, 300)
	await get_tree().process_frame

	t.selected_shapes.assign([sp])
	InspectorCore._sync_selection()
	var p := InspectorCore.current_props()
	assert_float(p["width"]["value"]).is_equal_approx(100.0, 1.0)
	assert_float(p["height"]["value"]).is_equal_approx(50.0, 1.0)

	HistoryManager.clear()
	InspectorCore.apply("width", 250.0)   # x2.5
	assert_float(sp.scale.x).is_equal_approx(2.5, 0.02)
	assert_float(sp.scale.y).is_equal_approx(1.0, 0.02)   # alto intacto
	assert_float(InspectorCore.current_props()["width"]["value"]).is_equal_approx(250.0, 1.0)

	HistoryManager.undo(); await get_tree().process_frame
	assert_float(sp.scale.x).is_equal_approx(1.0, 0.02)
	HistoryManager.clear()


## Interlineado de un texto: meta + constante de tema en el DisplayLabel, undo.
func test_inspector_line_spacing_en_texto() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)

	var txt := Node2D.new()
	txt.set_meta("shape_type", "text_paragraph")
	txt.set_meta("font_size", 24)
	var dl := Label.new()
	dl.name = "DisplayLabel"
	txt.add_child(dl)
	_ab(s).add_child(txt)
	await get_tree().process_frame

	t.selected_shapes.assign([txt])
	InspectorCore._sync_selection()
	assert_float(InspectorCore.current_props()["line_spacing"]["value"]).is_equal_approx(0.0, 0.01)

	HistoryManager.clear()
	InspectorCore.apply("line_spacing", 18.0)
	assert_int(int(txt.get_meta("line_spacing"))).is_equal(18)
	assert_int(dl.get_theme_constant("line_spacing")).is_equal(18)

	HistoryManager.undo(); await get_tree().process_frame
	assert_int(int(txt.get_meta("line_spacing"))).is_equal(0)
	HistoryManager.clear()

	# tracking (interletra): FontVariation con spacing sobre el DisplayLabel
	InspectorCore.apply("letter_spacing", 6.0)
	assert_int(int(txt.get_meta("letter_spacing"))).is_equal(6)


func _pv2_bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for i in range(1, pts.size()):
		r = r.expand(pts[i])
	return r


## Invariante I6: el Inspector y el bounding box muestran el mismo valor.
func test_inspector_y_bounding_box_coinciden_en_pos() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var r := _rect(_ab(s), Vector2(123, 45))
	r.set_doc_position(DVec2.new(123.0, 45.0))
	await get_tree().process_frame

	var bb := preload("res://scenes/canvas/boundingbox.tscn").instantiate()
	_ab(s).add_child(bb); auto_free(bb)
	bb.move_tool_reference = t
	t.selected_shapes.assign([r])
	bb._sincronizar_dimensiones_en_canvas()
	InspectorCore._sync_selection()
	var p := InspectorCore.current_props()

	assert_float(p["pos_x"]["value"]).is_equal_approx(bb._field_x.value, 0.01)
	assert_float(p["pos_y"]["value"]).is_equal_approx(bb._field_y.value, 0.01)
