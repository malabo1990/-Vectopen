# =============================================================================
# VECTOPEN — PRUEBAS DE GEOMETRÍA PARAMÉTRICA Y TOOLBAR CONTEXTUAL (FASE 6)
# RUTA: res://test/ui/ParametricGeometryAndToolbar_test.gd
# =============================================================================
extends GdUnitTestSuite

const VectorCircleScript := preload("res://script_gdscript/shapes/VectorCircle.gd")
const VectorStarScript := preload("res://script_gdscript/shapes/VectorStar.gd")
const VectorRectangleScript := preload("res://script_gdscript/shapes/VectorRectangle.gd")
const CircleToolScript := preload("res://script_gdscript/tools/CircleTool.gd")
const StarToolScript := preload("res://script_gdscript/tools/StarTool.gd")
const ModernTopBarScript := preload("res://script_gdscript/ui/modern/modern_top_bar.gd")
const DockedInspectorScript := preload("res://script_gdscript/ui/docked_inspector.gd")
const CanvasSerializerScript := preload("res://scripts/canvas/canvas_serializer.gd")

func test_parametric_vector_circle_modes() -> void:
	var circle: VectorCircle = auto_free(VectorCircleScript.new()) as VectorCircle
	circle.size = Vector2(200, 200)

	# Modo por defecto: Círculo completo (whole)
	assert_str(circle.shape_mode).is_equal("whole")
	var verts_whole: PackedVector2Array = circle.get_effect_points()
	assert_int(verts_whole.size()).is_equal(128)

	# Modo Arco (arc): abierto
	circle.shape_mode = "arc"
	circle.start_angle_deg = 0.0
	circle.end_angle_deg = 180.0
	var verts_arc: PackedVector2Array = circle.get_effect_points()
	assert_bool(verts_arc.size() > 0).is_true()
	assert_bool(verts_arc.size() <= 128).is_true()

	# Modo Sector / Pie: contiene el centro (0, 0)
	circle.shape_mode = "pie"
	var verts_pie: PackedVector2Array = circle.get_effect_points()
	assert_that(verts_pie[0]).is_equal(Vector2.ZERO)

	# Modo Cuerda (chord)
	circle.shape_mode = "chord"
	var verts_chord: PackedVector2Array = circle.get_effect_points()
	assert_bool(verts_chord.size() > 0).is_true()

	# Modo Anillo / Donut
	circle.shape_mode = "donut"
	circle.inner_radius_ratio = 0.5
	var verts_donut: PackedVector2Array = circle.get_effect_points()
	assert_bool(verts_donut.size() > 128).is_true()

	# Serialización y estado
	var state: Dictionary = circle.get_state()
	assert_str(state.get("shape_mode", "")).is_equal("donut")
	assert_float(state.get("inner_radius_ratio", 0.0)).is_equal(0.5)

func test_parametric_vector_star() -> void:
	var star: VectorShape = auto_free(VectorStarScript.new()) as VectorShape
	star.size = Vector2(100, 100)
	star.points_count = 5
	star.inner_radius_ratio = 0.382

	var verts: PackedVector2Array = star.get_effect_points()
	# 5 puntas = 10 vértices en estrella no redondeada
	assert_int(verts.size()).is_equal(10)

	# Con redondeo de esquinas
	star.corner_radius = 5.0
	var verts_rounded: PackedVector2Array = star.get_effect_points()
	assert_bool(verts_rounded.size() > 10).is_true()

	# Serialización
	var state: Dictionary = star.get_state()
	assert_str(state.get("type", "")).is_equal("star")
	assert_int(state.get("points_count", 0)).is_equal(5)
	assert_float(state.get("inner_radius_ratio", 0.0)).is_equal(0.382)
	assert_float(state.get("corner_radius", 0.0)).is_equal(5.0)

func test_star_and_circle_tool_creation() -> void:
	var circle_tool: ToolBase = auto_free(CircleToolScript.new()) as ToolBase
	assert_str(circle_tool.shape_mode).is_equal("whole")
	assert_float(circle_tool.start_angle_deg).is_equal(0.0)
	assert_float(circle_tool.end_angle_deg).is_equal(360.0)

	var star_tool: ToolBase = auto_free(StarToolScript.new()) as ToolBase
	assert_int(star_tool.points_count).is_equal(5)
	assert_float(star_tool.inner_radius_ratio).is_equal(0.382)

func test_modern_top_bar_has_no_duplicated_quick_controls() -> void:
	var top_bar: ModernTopBar = auto_free(ModernTopBarScript.new()) as ModernTopBar
	add_child(top_bar)
	await get_tree().process_frame

	# Tool/object parameters live in the docked inspector only: the top bar
	# tracks the active tool but never shows duplicated quick controls.
	for tool_id in ["rectangle", "ellipse", "star", "text", "select"]:
		top_bar.set_active_tool(tool_id)
		await get_tree().process_frame
		assert_str(top_bar.get_active_tool()).is_equal(tool_id)
		assert_int(top_bar.context_container.get_child_count()).is_equal(0)
	assert_object(top_bar.btn_settings).is_not_null()

func test_docked_inspector_parametric_sections() -> void:
	var inspector: DockedInspector = auto_free(DockedInspectorScript.new()) as DockedInspector
	add_child(inspector)
	await get_tree().process_frame

	assert_object(inspector.sec_parametric_circle).is_not_null()
	assert_object(inspector.sec_parametric_star).is_not_null()
	assert_object(inspector.sec_parametric_rect).is_not_null()

	# Sin selección: deben estar ocultas
	inspector._on_selection_size_changed(0)
	assert_bool(inspector.sec_parametric_circle.visible).is_false()
	assert_bool(inspector.sec_parametric_star.visible).is_false()
	assert_bool(inspector.sec_parametric_rect.visible).is_false()

func test_parametric_undo_redo_via_inspector_core() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var circle: VectorCircle = auto_free(VectorCircleScript.new()) as VectorCircle
	circle.size = Vector2(100, 100)
	circle.shape_mode = "whole"
	circle.start_angle_deg = 0.0
	root.add_child(circle)

	# Mock selection in SelectionManager
	var sm = get_node_or_null("/root/SelectionManager")
	if sm and sm.has_method("set_selection"):
		sm.set_selection([circle])

	var ic = get_node_or_null("/root/InspectorCore")
	assert_object(ic).is_not_null()

	# Modificar modo de círculo vía InspectorCore.apply
	ic.apply("shape_mode", "arc")
	assert_str(circle.shape_mode).is_equal("arc")

	# Modificar ángulo inicial
	ic.apply("start_angle_deg", 45.0)
	assert_float(circle.start_angle_deg).is_equal(45.0)

	# Deshacer ángulo inicial
	HistoryManager.undo()
	assert_float(circle.start_angle_deg).is_equal(0.0)

	# Deshacer modo
	HistoryManager.undo()
	assert_str(circle.shape_mode).is_equal("whole")

	# Rehacer modo
	HistoryManager.redo()
	assert_str(circle.shape_mode).is_equal("arc")

	# Probar estrella paramétrica
	var star: VectorShape = auto_free(VectorStarScript.new()) as VectorShape
	star.size = Vector2(100, 100)
	star.points_count = 5
	root.add_child(star)

	if sm and sm.has_method("set_selection"):
		sm.set_selection([star])

	ic.apply("points_count", 8)
	assert_int(star.points_count).is_equal(8)

	HistoryManager.undo()
	assert_int(star.points_count).is_equal(5)

	# Probar mediante setter de DockedInspector
	var inspector: DockedInspector = auto_free(DockedInspectorScript.new()) as DockedInspector
	add_child(inspector)
	inspector._set_star_param("points_count", 12)
	assert_int(star.points_count).is_equal(12)

	HistoryManager.undo()
	assert_int(star.points_count).is_equal(5)
