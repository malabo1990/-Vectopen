# =============================================================================
# VECTOPEN — Test Suite para Panel Bézier, Herramientas de Nodos y Atajos
# RUTA: res://test/ui/BezierPanelAndNodeTools_test.gd
# =============================================================================
extends GdUnitTestSuite

func test_panel_bezier_scene_structure() -> void:
	var scene: PackedScene = load("res://scenes/ui/panels/panel_bezier.tscn")
	assert_object(scene).is_not_null()

	var panel = auto_free(scene.instantiate())
	assert_object(panel).is_not_null()
	add_child(panel)
	await get_tree().process_frame

	# Verificar controles de acciones
	assert_object(panel._btn_delete).is_not_null()
	assert_object(panel._btn_join).is_not_null()
	assert_object(panel._btn_split).is_not_null()

	# Verificar botones de modos (Affinity / Illustrator)
	assert_object(panel._btn_mode_sharp).is_not_null()
	assert_object(panel._btn_mode_smooth).is_not_null()
	assert_object(panel._btn_mode_symmetric).is_not_null()
	assert_object(panel._btn_mode_retract).is_not_null()

	# Verificar controles de tiradores
	assert_object(panel._btn_handle_small).is_not_null()
	assert_object(panel._btn_handle_medium).is_not_null()
	assert_object(panel._btn_handle_large).is_not_null()
	assert_object(panel._chk_all_handles).is_not_null()

	# Verificar controles de trazo
	assert_object(panel._chk_closed).is_not_null()
	assert_object(panel._spin_stroke_width).is_not_null()

func test_tool_scene_has_bezier_panel_and_target() -> void:
	var tool_scene: PackedScene = load("res://scenes/ui/tool.tscn")
	assert_object(tool_scene).is_not_null()

	var instance: Node = auto_free(tool_scene.instantiate())
	assert_object(instance).is_not_null()

	var btn_bezier: Button = instance.find_child("button_toolbezier", true, false) as Button
	assert_object(btn_bezier).is_not_null()
	assert_str(String(btn_bezier.get("tool_name"))).is_equal("bezier")

	# Verificar que tiene target_node apuntando a panel bezier
	var target = btn_bezier.get("target_node")
	assert_object(target).is_not_null()
	assert_str(target.name).is_equal("bezier")

func test_node_selection_tool_modes() -> void:
	var node_tool: NodeSelectionTool = auto_free(NodeSelectionTool.new())
	var path: Path2D = auto_free(Path2D.new())
	var curve: Curve2D = Curve2D.new()

	# Crear un trazado de 3 puntos
	curve.add_point(Vector2(0, 0), Vector2(-10, 0), Vector2(10, 0))
	curve.add_point(Vector2(100, 100), Vector2(-20, 10), Vector2(30, -5))
	curve.add_point(Vector2(200, 0), Vector2(-10, 0), Vector2(10, 0))
	path.curve = curve
	node_tool.edit_path = path

	# Seleccionar el punto intermedio (índice 1)
	node_tool.selected_nodes = [1]

	# 1. Probar modo Simétrico
	node_tool.set_selected_nodes_mode("symmetric")
	var h_in := curve.get_point_in(1)
	var h_out := curve.get_point_out(1)
	assert_float(h_in.length()).is_equal_approx(h_out.length(), 0.01)
	# Deben ser colineales y opuestos: h_in.normalized() == -h_out.normalized()
	assert_float(h_in.normalized().dot(h_out.normalized())).is_equal_approx(-1.0, 0.01)

	# 2. Probar modo Suave (Smooth)
	curve.set_point_in(1, Vector2(-10, 0))
	curve.set_point_out(1, Vector2(30, 0))
	node_tool.set_selected_nodes_mode("smooth")
	h_in = curve.get_point_in(1)
	h_out = curve.get_point_out(1)
	assert_float(h_in.normalized().dot(h_out.normalized())).is_equal_approx(-1.0, 0.01)
	# Conservan longitudes individuales
	assert_float(h_in.length()).is_equal_approx(10.0, 0.01)
	assert_float(h_out.length()).is_equal_approx(30.0, 0.01)

	# 3. Probar modo Recto / Retract
	node_tool.set_selected_nodes_mode("retract")
	assert_that(curve.get_point_in(1).is_equal_approx(Vector2.ZERO)).is_true()
	assert_that(curve.get_point_out(1).is_equal_approx(Vector2.ZERO)).is_true()

func test_node_selection_tool_delete_nodes() -> void:
	var node_tool: NodeSelectionTool = auto_free(NodeSelectionTool.new())
	var path: Path2D = auto_free(Path2D.new())
	var curve: Curve2D = Curve2D.new()

	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(50, 50))
	curve.add_point(Vector2(100, 100))
	curve.add_point(Vector2(150, 50))
	path.curve = curve
	node_tool.edit_path = path

	assert_int(curve.point_count).is_equal(4)

	# Seleccionar puntos 1 y 2
	node_tool.selected_nodes = [1, 2]
	node_tool.delete_selected_nodes()

	# Deben quedar 2 puntos: el original (0,0) y el original (150,50)
	assert_int(curve.point_count).is_equal(2)
	assert_that(curve.get_point_position(0).is_equal_approx(Vector2(0, 0))).is_true()
	assert_that(curve.get_point_position(1).is_equal_approx(Vector2(150, 50))).is_true()
	assert_int(node_tool.selected_nodes.size()).is_equal(0)

func test_node_selection_tool_keyboard_delete_x() -> void:
	var node_tool: NodeSelectionTool = auto_free(NodeSelectionTool.new())
	var path: Path2D = auto_free(Path2D.new())
	var curve: Curve2D = Curve2D.new()

	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(50, 50))
	curve.add_point(Vector2(100, 100))
	path.curve = curve
	node_tool.edit_path = path
	node_tool.selected_nodes = [1]

	var key_event := InputEventKey.new()
	key_event.pressed = true
	key_event.keycode = KEY_X

	var handled := node_tool.handle_input(key_event)
	assert_bool(handled).is_true()
	assert_int(curve.point_count).is_equal(2)

func test_bezier_tool_keyboard_delete_x() -> void:
	var BezierToolScript = load("res://script_gdscript/tools/beziertool.gd")
	var b_tool = auto_free(BezierToolScript.new())
	var path: Path2D = auto_free(Path2D.new())
	var curve: Curve2D = Curve2D.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(50, 50))
	path.curve = curve
	b_tool.current_path = path
	b_tool.is_creating = true

	var key_event := InputEventKey.new()
	key_event.pressed = true
	key_event.keycode = KEY_X

	var handled: bool = b_tool.handle_input(key_event)
	assert_bool(handled).is_true()
	assert_int(curve.point_count).is_equal(1)

func test_panel_bezier_visual_render() -> void:
	var subvp := SubViewport.new()
	subvp.size = Vector2i(600, 500)
	subvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(subvp)

	var bg := ColorRect.new()
	bg.size = Vector2(600, 500)
	bg.color = Color(0.12, 0.12, 0.14, 1.0)
	subvp.add_child(bg)

	var scene: PackedScene = load("res://scenes/ui/panels/panel_bezier.tscn")
	var panel = scene.instantiate() as Control
	panel.visible = true
	panel.position = Vector2(120, 30)
	subvp.add_child(panel)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var img: Image = subvp.get_texture().get_image() if subvp.get_texture() else null
	if img:
		img.save_png("C:/Users/User/.gemini/antigravity/brain/e2cde967-7b74-4b4e-b620-1a51af2310f4/panel_bezier_verification.png")

	subvp.queue_free()

func test_node_selection_visual_red_and_click_outside() -> void:
	# 1. Color rojo vivo para nodos seleccionados
	assert_that(NodeSelectionTool.COLOR_NODE_SELECTED).is_equal(Color(0.95, 0.20, 0.20, 1.0))
	assert_that(NodeSelectionTool.COLOR_NODE_FILL).is_equal(Color(1.0, 1.0, 1.0, 1.0))

	# 2. Doble clic en MoveTool no selecciona todos los nodos
	var node_tool: NodeSelectionTool = auto_free(NodeSelectionTool.new())
	var path: Path2D = auto_free(Path2D.new())
	var curve: Curve2D = Curve2D.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(50, 50))
	curve.add_point(Vector2(100, 100))
	path.curve = curve
	node_tool.edit_path = path
	node_tool.activate()
	# Al activar, no selecciona todos los nodos
	assert_int(node_tool.selected_nodes.size()).is_equal(0)

func test_global_signals_and_bezier_panel_trigger() -> void:
	var ge = get_node_or_null("/root/GlobalEvents")
	assert_object(ge).is_not_null()
	assert_bool(ge.has_signal("request_export_dialog")).is_true()
	assert_bool(ge.has_signal("request_bezier_panel")).is_true()

	var scene: PackedScene = load("res://scenes/ui/panels/panel_bezier.tscn")
	var panel = auto_free(scene.instantiate()) as Control
	add_child(panel)
	panel.visible = false
	ge.emit_safe("request_bezier_panel")
	assert_bool(panel.visible).is_true()

func test_svg_text_export_and_import() -> void:
	var artboard_script = load("res://scripts/canvas/artboard.gd")
	var ab1: Node2D = auto_free(Node2D.new())
	ab1.set_script(artboard_script)
	ab1.set("artboard_size", Vector2(800, 600))
	add_child(ab1)

	var text_node := Node2D.new()
	text_node.name = "TextoPrueba"
	text_node.position = Vector2(100, 150)
	text_node.set_meta("shape_type", "text_title")
	text_node.set_meta("text", "Hola Vectopen SVG")
	text_node.set_meta("font_size", 32)
	text_node.set_meta("font_family", "Inter")
	text_node.set_meta("text_color", Color.RED)
	ab1.add_child(text_node)

	var tmp_svg := "user://test_svg_text_roundtrip.svg"
	var svg_content: String = ab1.call("export_to_svg", ProjectSettings.globalize_path(tmp_svg))
	assert_str(svg_content).contains("<text")
	assert_str(svg_content).contains("Hola Vectopen SVG")
	assert_str(svg_content).contains('font-size="32"')

	# Importar en nuevo artboard
	var ab2: Node2D = auto_free(Node2D.new())
	ab2.set_script(artboard_script)
	ab2.set("artboard_size", Vector2(800, 600))
	add_child(ab2)
	ab2.call("import_svg", ProjectSettings.globalize_path(tmp_svg))

	var imported_text: Node2D = null
	for child in ab2.get_children():
		if child.has_meta("shape_type") and child.get_meta("shape_type") == "text_title":
			imported_text = child
			break

	assert_object(imported_text).is_not_null()
	assert_str(String(imported_text.get_meta("text"))).is_equal("Hola Vectopen SVG")
	assert_int(int(imported_text.get_meta("font_size"))).is_equal(32)

	if FileAccess.file_exists(tmp_svg):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_svg))

func test_first_and_last_node_curvature_open_curve() -> void:
	var node_tool: NodeSelectionTool = auto_free(NodeSelectionTool.new())
	var path: Path2D = auto_free(Path2D.new())
	var curve: Curve2D = Curve2D.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(100, 0))
	path.curve = curve
	node_tool.edit_path = path

	# Probar nodo inicial (0) en curva abierta: antes daba 0 handles
	node_tool.selected_nodes = [0]
	node_tool.set_selected_nodes_mode("smooth")
	assert_that(curve.get_point_out(0)).is_not_equal(Vector2.ZERO)
	assert_that(curve.get_point_in(0)).is_not_equal(Vector2.ZERO)

	# Probar nodo final (1) en curva abierta: antes daba 0 handles
	node_tool.selected_nodes = [1]
	node_tool.set_selected_nodes_mode("smooth")
	assert_that(curve.get_point_in(1)).is_not_equal(Vector2.ZERO)
	assert_that(curve.get_point_out(1)).is_not_equal(Vector2.ZERO)

func test_segment_hover_and_tick_mark() -> void:
	var node_tool: NodeSelectionTool = auto_free(NodeSelectionTool.new())
	var path: Path2D = auto_free(Path2D.new())
	var curve: Curve2D = Curve2D.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(100, 0))
	path.curve = curve
	node_tool.edit_path = path

	var seg_idx = node_tool._find_segment_index_by_point(Vector2(50, 1))
	assert_int(seg_idx).is_equal(0)

	node_tool._update_segment_hover(Vector2(50, 1))
	assert_int(node_tool.hovered_segment_idx).is_equal(0)
	assert_float(node_tool.hovered_segment_point.distance_to(Vector2(50, 0))).is_less(1.0)
	# Normal debe ser perpendicular a la línea horizontal (x aprox 0)
	assert_float(absf(node_tool.hovered_segment_normal.x)).is_less(0.01)

func test_tool_scene_has_brush_panel_and_target() -> void:
	var scene: PackedScene = load("res://scenes/ui/tool.tscn")
	var tool_root = auto_free(scene.instantiate()) as Control
	add_child(tool_root)

	var btn_brush: Button = tool_root.find_child("button_toolbrush", true, false)
	assert_object(btn_brush).is_not_null()

	var brush_panel: Control = tool_root.find_child("brush", true, false)
	assert_object(brush_panel).is_not_null()
	assert_that(btn_brush.get("target_node")).is_equal(brush_panel)

func test_text_ctrl_resize_scales_font_size() -> void:
	var move_tool: MoveTool = auto_free(MoveTool.new())
	var text_shape: Node2D = auto_free(Node2D.new())
	text_shape.set_meta("shape_type", "text_paragraph")
	text_shape.set_meta("width", 200.0)
	text_shape.set_meta("height", 100.0)
	text_shape.set_meta("font_size", 16)

	var snap: Dictionary = move_tool._snapshot(text_shape)
	assert_int(snap.get("font_size", 0)).is_equal(16)

	move_tool.selected_shapes = [text_shape]
	move_tool.transform_initial_states[text_shape] = snap
	move_tool.transform_macro_rect = Rect2(Vector2(0, 0), Vector2(200, 100))
	move_tool.transform_initial_mouse = Vector2(200, 100)
	move_tool.resize_handle = "br"

	# Resize con Ctrl: duplicar tamaño (de 200x100 a 400x200) -> sx=2.0, sy=2.0
	move_tool._apply_resize(Vector2(400, 200), {"ctrl": true})
	assert_int(int(text_shape.get_meta("font_size"))).is_equal(32)



