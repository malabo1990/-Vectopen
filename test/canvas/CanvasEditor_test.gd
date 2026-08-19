extends GdUnitTestSuite

## Regresión del bug encontrado el 19/08/2026: mark_region_dirty() marcaba
## regiones "sucias" para redibujado parcial (cambio de herramienta, zoom,
## toolbar...) pero _draw() nunca las limpiaba después de consumirlas. En
## cuanto ocurría la primera llamada de toda la sesión, el canvas quedaba
## atascado para siempre en modo "recorte parcial" (canvas_item_set_custom_rect
## clipeado a esa región vieja), así que CUALQUIER dibujo posterior —el
## rectángulo de marquee y los contornos de multiselección de
## MoveTool.draw_preview(), o el preview de cualquier otra herramienta— dejaba
## de verse, sin importar qué ni cuántos elementos se seleccionaran.
## Ver CanvasEditor.gd::_draw().
func test_draw_clears_dirty_regions_after_processing_them() -> void:
	var canvas: CanvasEditor = auto_free(CanvasEditor.new())
	add_child(canvas)

	canvas.mark_region_dirty(Rect2(0, 0, 100, 100))
	assert_int(canvas._dirty_regions.size()).is_equal(1)

	# mark_region_dirty() ya llama a queue_redraw(); dejamos que el motor
	# ejecute el _draw() real (no lo invocamos a mano) para probar el mismo
	# camino que se dispara en juego.
	await get_tree().process_frame

	assert_int(canvas._dirty_regions.size()).is_equal(0)

## Invariante: tras un ciclo completo de "marcar sucio → dibujar", una nueva
## región marcada después debe volver a aparecer sola en la lista (no debe
## quedar ningún resto de la región anterior acumulado).
func test_dirty_regions_do_not_accumulate_across_draw_cycles() -> void:
	var canvas: CanvasEditor = auto_free(CanvasEditor.new())
	add_child(canvas)

	canvas.mark_region_dirty(Rect2(0, 0, 50, 50))
	await get_tree().process_frame

	canvas.mark_region_dirty(Rect2(200, 200, 30, 30))
	assert_int(canvas._dirty_regions.size()).is_equal(1)
	assert_vector(canvas._dirty_regions[0].position).is_equal(Vector2(200, 200))
