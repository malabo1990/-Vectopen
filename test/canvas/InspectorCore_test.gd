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

	# pos = doc-space (relativo al artboard, como Figma) → == get_doc_position
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
