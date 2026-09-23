# =============================================================================
# VECTOPEN — PRUEBAS DE PANEL DE POLÍGONOS Y PARÁMETROS
# RUTA: res://test/ui/PolygonPanel_test.gd
# =============================================================================
extends GdUnitTestSuite

const PanelPolygonScript := preload("res://script_gdscript/ui/panel_polygon.gd")

func test_panel_polygon_initialization_and_tabs() -> void:
	var panel = auto_free(PanelPolygonScript.new())
	add_child(panel)
	await get_tree().process_frame

	assert_object(panel._header_title).is_not_null()
	assert_object(panel._shapes_grid).is_not_null()
	# 8 figuras en el catálogo: Triángulo, Rectángulo, Rombo, Círculo,
	# Polígono, Estrella 5P, Estrella 4P, Gota — WATERDROP se agregó
	# después de este test, que se quedó afirmando el conteo viejo (7).
	assert_int(panel._shape_buttons.size()).is_equal(8)

	# Probar cambio a triángulo
	panel._switch_shape_tab(panel.ShapeType.TRIANGLE)
	assert_int(panel.current_shape).is_equal(panel.ShapeType.TRIANGLE)

	# Probar cambio a estrella
	panel._switch_shape_tab(panel.ShapeType.STAR5)
	assert_int(panel.current_shape).is_equal(panel.ShapeType.STAR5)

	# Probar cambio a círculo
	panel._switch_shape_tab(panel.ShapeType.CIRCLE)
	assert_int(panel.current_shape).is_equal(panel.ShapeType.CIRCLE)

	# Probar cambio a polígono regular
	panel._switch_shape_tab(panel.ShapeType.POLYGON)
	assert_int(panel.current_shape).is_equal(panel.ShapeType.POLYGON)

func test_vector_polygon_parametric_recalculation() -> void:
	var poly = auto_free(VectorPolygon.new())
	poly.is_regular = true
	poly.sides = 6
	poly.radius = 100.0
	poly.corner_radius = 0.0

	assert_int(poly.vertices.size()).is_equal(6)
	assert_int(poly.sides).is_equal(6)
	assert_float(poly.radius).is_equal_approx(100.0, 0.01)

	# Cambiar número de lados en tiempo real
	poly.sides = 8
	assert_int(poly.vertices.size()).is_equal(8)

	# Aplicar redondeo de esquinas (cada esquina genera curva bezier con puntos interpolados)
	poly.corner_radius = 10.0
	assert_int(poly.vertices.size()).is_greater(8)

func test_panel_polygon_realtime_sync_with_selection() -> void:
	var sm = get_node_or_null("/root/SelectionManager")
	assert_object(sm).is_not_null()

	var poly = auto_free(VectorPolygon.new())
	poly.is_regular = true
	poly.sides = 5
	poly.radius = 80.0
	poly.corner_radius = 0.0
	add_child(poly)

	sm.set_selection([poly])

	var panel = auto_free(PanelPolygonScript.new())
	add_child(panel)
	await get_tree().process_frame

	# Cambiar valor en el panel y verificar que se aplica en tiempo real a la selección
	panel._param_poly_sides = 7
	panel._param_poly_radius = 12.0
	panel._apply_to_canvas_selection()

	assert_int(poly.sides).is_equal(7)
	assert_float(poly.corner_radius).is_equal_approx(12.0, 0.01)
	assert_bool(poly.is_regular).is_true()
	assert_int(poly.vertices.size()).is_greater(7)

## Regresión: aplicar el preset Triángulo/Rombo desde "Aplicar a Selección"
## escribía SOLO sobre nodes[0] y nunca pasaba por HistoryManager — con 2+
## polígonos seleccionados el segundo quedaba intacto, y el cambio no era
## deshacible con Ctrl+Z. Ver PanelPolygon._apply_polygon_preset().
func test_triangle_preset_applies_to_ALL_selected_polygons_and_is_undoable() -> void:
	var sm = get_node_or_null("/root/SelectionManager")
	assert_object(sm).is_not_null()
	HistoryManager.clear()

	var poly_a = auto_free(VectorPolygon.new())
	poly_a.is_regular = true
	poly_a.sides = 5
	poly_a.radius = 80.0
	add_child(poly_a)

	var poly_b = auto_free(VectorPolygon.new())
	poly_b.is_regular = true
	poly_b.sides = 5
	poly_b.radius = 80.0
	add_child(poly_b)

	sm.set_selection([poly_a, poly_b])

	var panel = auto_free(PanelPolygonScript.new())
	add_child(panel)
	await get_tree().process_frame

	panel.current_shape = panel.ShapeType.TRIANGLE
	panel._param_triangle_type = "equilateral"
	panel._param_triangle_radius = 5.0
	panel._apply_to_canvas_selection()

	for p in [poly_a, poly_b]:
		assert_str(p.get_meta("shape_kind", "")).override_failure_message(
			"shape_kind no se aplicó a %s" % p
		).is_equal("triangle")
		assert_int(p.sides).is_equal(3)
		assert_bool(p.is_regular).is_false()
		assert_int(p.base_vertices.size()).is_equal(3)
		assert_float(p.corner_radius).is_equal_approx(5.0, 0.01)

	assert_bool(HistoryManager.can_undo()).override_failure_message(
		"El cambio de Triángulo/Rombo tiene que quedar registrado en el historial (Ctrl+Z)"
	).is_true()

	HistoryManager.undo(); await get_tree().process_frame
	for p in [poly_a, poly_b]:
		assert_bool(p.is_regular).is_true()
		assert_int(p.sides).is_equal(5)

	HistoryManager.clear()

## Regresión: "Esquinas Independientes" solo escribía en la figura al
## CREARLA — aplicar los sliders TL/TR/BL/BR a un rectángulo YA
## seleccionado no hacía nada, y el panel tampoco leía el estado real de un
## rectángulo existente al seleccionarlo. Ver el bloque VectorRectangle de
## PanelPolygon._apply_to_canvas_selection() / _on_inspector_changed().
func test_rectangle_independent_corners_apply_to_EXISTING_selection_and_sync_back() -> void:
	var sm = get_node_or_null("/root/SelectionManager")
	assert_object(sm).is_not_null()
	HistoryManager.clear()

	var rect = auto_free(VectorRectangle.new())
	rect.size = Vector2(160, 120)
	add_child(rect)
	sm.set_selection([rect])

	var panel = auto_free(PanelPolygonScript.new())
	add_child(panel)
	await get_tree().process_frame

	# 1) Aplicar: panel -> selección existente.
	panel.current_shape = panel.ShapeType.RECTANGLE
	panel._param_rect_independent = true
	panel._param_rect_corners = Vector4(2.0, 4.0, 6.0, 8.0)  # tl, tr, br, bl
	panel._apply_to_canvas_selection()

	var applied: Vector4 = rect.get_corner_radii()
	assert_float(applied.x).is_equal_approx(2.0, 0.01)
	assert_float(applied.y).is_equal_approx(4.0, 0.01)
	assert_float(applied.z).is_equal_approx(6.0, 0.01)
	assert_float(applied.w).is_equal_approx(8.0, 0.01)
	assert_bool(HistoryManager.can_undo()).is_true()

	HistoryManager.undo(); await get_tree().process_frame
	var reverted: Vector4 = rect.get_corner_radii()
	assert_float(reverted.x).is_equal_approx(0.0, 0.01)
	HistoryManager.clear()

	# 2) Sincronizar: selección existente -> panel (al revés).
	rect.set_corner_radii(Vector4(1.0, 2.0, 3.0, 4.0))
	panel._on_inspector_changed({})

	assert_bool(panel._param_rect_independent).override_failure_message(
		"Un rectángulo con esquinas distintas entre sí tiene que activar 'Esquinas Independientes'"
	).is_true()
	assert_float(panel._param_rect_corners.x).is_equal_approx(1.0, 0.01)
	assert_float(panel._param_rect_corners.y).is_equal_approx(2.0, 0.01)
	assert_float(panel._param_rect_corners.z).is_equal_approx(3.0, 0.01)
	assert_float(panel._param_rect_corners.w).is_equal_approx(4.0, 0.01)

