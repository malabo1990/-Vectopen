# =============================================================================
# VECTOPEN — PRUEBAS DEL PANEL DE POLÍGONOS Y ESTRELLAS
# RUTA: res://test/ui/PolygonPanel_test.gd
# =============================================================================
extends GdUnitTestSuite

const PanelPolygonScript := preload("res://script_gdscript/ui/panel_polygon.gd")
const Serializer := preload("res://scripts/canvas/canvas_serializer.gd")

var _sm: Node

func before_test() -> void:
	_sm = get_node_or_null("/root/SelectionManager")
	HistoryManager.clear()

func after_test() -> void:
	if _sm:
		_sm.set_selection([])
	HistoryManager.clear()

func _poly(sides: int = 5) -> VectorPolygon:
	var p: VectorPolygon = auto_free(VectorPolygon.new())
	p.radius = 80.0
	p.is_regular = true
	p.sides = sides
	add_child(p)
	return p

func _panel() -> PanelPolygon:
	var panel: PanelPolygon = auto_free(PanelPolygonScript.new())
	add_child(panel)
	await get_tree().process_frame
	return panel

## Cinco figuras, sin duplicados: estrella y polígono regular son UNA pestaña.
func test_tabs_are_unique_kinds() -> void:
	var panel := await _panel()
	assert_int(panel._tabs.size()).is_equal(5)
	panel.set_kind(PanelPolygon.Kind.STAR)
	assert_bool(panel._fields.has("points_count")).is_true()
	assert_bool(panel._fields.has("inner_corner_radius")).is_true()
	panel.set_kind(PanelPolygon.Kind.POLYGON)
	assert_bool(panel._fields.has("sides")).is_true()
	assert_bool(panel._fields.has("points_count")).is_false()

## Preajuste (Cuadrado) a TODOS los polígonos seleccionados con UN deshacer.
func test_preset_applies_to_all_selected_with_one_undo() -> void:
	var a := _poly(5)
	var b := _poly(7)
	_sm.set_selection([a, b])
	var panel := await _panel()
	assert_int(panel.kind).is_equal(PanelPolygon.Kind.POLYGON)
	panel._apply_values({"sides": 4, "poly_angle": 45.0, "poly_aspect": 1.0})
	for p in [a, b]:
		assert_int(p.sides).is_equal(4)
		assert_float(p.poly_angle).is_equal_approx(45.0, 0.01)
		assert_int(p.vertices.size()).is_equal(4)
	HistoryManager.undo()
	assert_int(a.sides).is_equal(5)
	assert_int(b.sides).is_equal(7)
	assert_bool(HistoryManager.can_undo()).is_false()

## Arrastre en vivo: muchos pasos → la figura cambia al momento → un deshacer.
func test_live_drag_one_undo_and_no_rebuild() -> void:
	var a := _poly(5)
	_sm.set_selection([a])
	var panel := await _panel()
	var field = panel._fields["sides"]
	for v in [6, 7, 8, 9]:
		panel._live("sides", float(v))
		assert_int(a.sides).is_equal(v)
	# El control sigue siendo el mismo (no se reconstruyó el panel).
	assert_object(panel._fields["sides"]).is_same(field)
	panel._commit_live()
	assert_object(panel._fields["sides"]).is_same(field)
	assert_bool(HistoryManager.can_undo()).is_true()
	HistoryManager.undo()
	assert_int(a.sides).is_equal(5)
	assert_bool(HistoryManager.can_undo()).is_false()

## Seleccionar una estrella cambia a la pestaña Estrella y lee sus valores.
func test_sync_from_star_selection() -> void:
	var st: VectorStar = auto_free(VectorStar.new())
	st.size = Vector2(140, 140)
	st.points_count = 7
	st.inner_radius_ratio = 0.6
	add_child(st)
	_sm.set_selection([st])
	var panel := await _panel()
	panel._on_inspector_changed({})
	assert_int(panel.kind).is_equal(PanelPolygon.Kind.STAR)
	assert_int(int(panel.values["points_count"])).is_equal(7)
	assert_float(float(panel.values["inner_radius_ratio"])).is_equal_approx(0.6, 0.001)
	# Redondeo de valles distinto del de puntas.
	panel._apply_values({"star_radius": 6.0, "inner_corner_radius": 0.0})
	assert_float(st.corner_radius).is_equal_approx(6.0, 0.01)
	assert_float(st.inner_corner_radius).is_equal_approx(0.0, 0.01)

## Esquinas independientes del rectángulo: aplicar, deshacer y leer de vuelta.
func test_rectangle_independent_corners() -> void:
	var rect: VectorRectangle = auto_free(VectorRectangle.new())
	rect.size = Vector2(160, 120)
	add_child(rect)
	_sm.set_selection([rect])
	var panel := await _panel()
	panel._on_inspector_changed({})
	assert_int(panel.kind).is_equal(PanelPolygon.Kind.RECTANGLE)
	panel._apply_values({"corner_tl": 2.0, "corner_tr": 4.0, "corner_br": 6.0, "corner_bl": 8.0})
	var c: Vector4 = rect.get_corner_radii()
	assert_vector(c).is_equal_approx(Vector4(2, 4, 6, 8), Vector4.ONE * 0.01)
	HistoryManager.undo()
	assert_float(rect.get_corner_radii().x).is_equal_approx(0.0, 0.01)
	rect.set_corner_radii(Vector4(1, 2, 3, 4))
	panel._on_inspector_changed({})
	assert_bool(bool(panel.values["independent"])).is_true()
	assert_float(float(panel.values["corner_bl"])).is_equal_approx(4.0, 0.01)

## La curvatura de la gota regenera su contorno.
func test_drop_curvature_changes_shape() -> void:
	var d: VectorPolygon = auto_free(VectorPolygon.new())
	d.set_meta("shape_kind", "drop")
	d.set_meta("drop_radius", 50.0)
	d.set_meta("drop_curvature", 0.5)
	d.set_doc_vertices(DVec2.array_from_v2(WaterDropTool.drop_points(50.0, 0.0, 0.5)))
	add_child(d)
	_sm.set_selection([d])
	var panel := await _panel()
	panel._on_inspector_changed({})
	assert_int(panel.kind).is_equal(PanelPolygon.Kind.DROP)
	var before: PackedVector2Array = d.vertices.duplicate()
	panel._apply_values({"drop_curvature": 1.0})
	assert_float(float(d.get_meta("drop_curvature"))).is_equal_approx(1.0, 0.001)
	assert_bool(d.vertices == before).is_false()
	HistoryManager.undo()
	assert_bool(d.vertices == before).is_true()

## Polígono regular: redondeo adaptativo y parámetros que sobreviven a
## guardar/cargar.
func test_polygon_params_roundtrip_and_smooth_corners() -> void:
	var p := _poly(6)
	p.poly_angle = 30.0
	p.poly_aspect = 0.5
	p.corner_radius = 30.0
	assert_int(p.vertices.size()).is_greater(6 * 3)
	var bb := Rect2(p.vertices[0], Vector2.ZERO)
	for v in p.vertices:
		bb = bb.expand(v)
	assert_float(bb.size.x).is_less(bb.size.y)   # proporción 50 % → más estrecho
	var data: Dictionary = Serializer._serialize_element(p)
	var q = auto_free(Serializer._element_from(data))
	assert_int(q.sides).is_equal(6)
	assert_float(q.poly_angle).is_equal_approx(30.0, 0.01)
	assert_float(q.poly_aspect).is_equal_approx(0.5, 0.01)
	assert_float(q.corner_radius).is_equal_approx(30.0, 0.01)

## Rendimiento: arrastrar "lados" hasta 200 con redondeo no debe atascar.
func test_live_drag_performance() -> void:
	var p := _poly(5)
	p.corner_radius = 10.0
	_sm.set_selection([p])
	var panel := await _panel()
	var t0 := Time.get_ticks_usec()
	for v in range(3, 200):
		panel._live("sides", float(v))
	panel._commit_live()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_int(p.sides).is_equal(199)
	assert_float(ms).override_failure_message("197 pasos de arrastre: %.1f ms" % ms).is_less(1500.0)

## Dibujar con la herramienta usa los valores del panel y se puede deshacer.
func test_drawing_tools_use_panel_settings_and_undo() -> void:
	var panel := await _panel()
	panel.values["sides"] = 8
	panel.values["corner_radius"] = 5.0
	panel.values["points_count"] = 9
	panel.values["drop_curvature"] = 0.9
	var ab: Node2D = auto_free(Node2D.new())
	add_child(ab)
	var pt: PentagonTool = auto_free(PentagonTool.new())
	pt.artboard = ab
	pt._spawn_shape(Vector2(100, 100), 50.0, 0.0)
	var poly: VectorPolygon = ab.get_child(ab.get_child_count() - 1)
	assert_bool(poly.is_regular).is_true()
	assert_int(poly.sides).is_equal(8)
	assert_float(poly.corner_radius).is_equal_approx(5.0, 0.01)
	assert_int(PanelPolygon.kind_of(poly)).is_equal(PanelPolygon.Kind.POLYGON)
	var st: StarTool = auto_free(StarTool.new())
	st.artboard = ab
	st._spawn_shape(Vector2(200, 100), 50.0, 0.0)
	var star: VectorStar = ab.get_child(ab.get_child_count() - 1)
	assert_int(star.points_count).is_equal(9)
	var wd: WaterDropTool = auto_free(WaterDropTool.new())
	wd.artboard = ab
	add_child(wd)
	wd._spawn_shape(Vector2(300, 100), 40.0, 0.0)
	var drop: VectorPolygon = ab.get_child(ab.get_child_count() - 1)
	assert_float(float(drop.get_meta("drop_curvature"))).is_equal_approx(0.9, 0.001)
	var n := ab.get_child_count()
	HistoryManager.undo()
	assert_int(ab.get_child_count()).is_equal(n - 1)
	HistoryManager.undo()
	HistoryManager.undo()
	assert_int(ab.get_child_count()).is_equal(n - 3)
	HistoryManager.redo()
	assert_object(poly.get_parent()).is_same(ab)
	for s in [poly, star, drop]:
		if s.get_parent() == null:
			s.free()
