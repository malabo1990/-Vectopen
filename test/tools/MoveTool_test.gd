extends GdUnitTestSuite

## Doble mínimo de ArtboardEditor para pruebas de _on_press() con is_selected.
## No se usa ArtboardEditor real aquí porque su is_selected dispara
## queue_redraw() -> _draw() -> _is_selection_tool(), que llama a
## get_tree().current_scene.find_child(...) y revienta en el runner de
## gdUnit4 (current_scene es null ahí) — un problema del propio
## ArtboardEditor ajeno a lo que estas pruebas de MoveTool verifican.
class _FakeArtboard extends Node2D:
	var artboard_size := Vector2(794, 1123)
	var is_selected := false
	func is_on_handle(_local_pos: Vector2) -> bool:
		return false

func test_resize_round_trip_preserves_subpixel_precision() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	add_child(canvas)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	canvas.add_child(shape)

	var precise: float = 100.00001234
	shape.set_doc_position(DVec2.new(200.0, 150.0))
	shape.set_doc_extent(DVec2.new(precise, precise))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = canvas
	tool.resize_handle = "br"
	tool.transform_initial_mouse = Vector2.ZERO

	# 40 ciclos de "agrandar 37px, volver a encoger 37px" por el mismo handle,
	# re-capturando el snapshot en cada paso (como ocurriría con 40 gestos de
	# resize reales, uno tras otro). Con el .size nativo (Vector2/float32) de
	# antes, cada paso releía como "exacto" un valor ya redondeado a ~7 dígitos
	# significativos, así que el error se acumulaba de forma medible tras
	# unas pocas decenas de ciclos. Con doc_extent (float de 64 bits), cada
	# paso parte siempre del valor doble exacto guardado por el paso anterior.
	for i in range(40):
		tool.selected_shapes = [shape]
		var current_extent: Vector2 = shape.get_doc_extent().to_v2()
		var current_rect: Rect2 = Rect2(shape.doc_position.to_v2() - current_extent / 2.0, current_extent)

		tool.transform_macro_rect = current_rect
		tool.transform_initial_states = {shape: tool._snapshot(shape)}
		tool._apply_resize(Vector2(37, 0))

		current_extent = shape.get_doc_extent().to_v2()
		current_rect = Rect2(shape.doc_position.to_v2() - current_extent / 2.0, current_extent)
		tool.transform_macro_rect = current_rect
		tool.transform_initial_states = {shape: tool._snapshot(shape)}
		tool._apply_resize(Vector2(-37, 0))

	assert_float(shape.get_doc_extent().x).is_equal_approx(precise, 1e-6)
	assert_float(shape.get_doc_extent().y).is_equal_approx(precise, 1e-6)

func test_snapshot_captures_doc_space_for_vector_shape() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	add_child(canvas)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	canvas.add_child(shape)
	shape.set_doc_position(DVec2.new(10.5, 20.5))
	shape.set_doc_extent(DVec2.new(30.5, 40.5))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = canvas
	var snap: Dictionary = tool._snapshot(shape)

	assert_bool(snap.has("doc_pos")).is_true()
	assert_bool(snap.has("doc_rot")).is_true()
	assert_bool(snap.has("doc_extent")).is_true()
	assert_float(snap["doc_pos"].x).is_equal(10.5)
	assert_float(snap["doc_extent"].x).is_equal(30.5)

func test_translate_syncs_doc_position() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	add_child(canvas)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	canvas.add_child(shape)
	shape.set_doc_position(DVec2.new(0.0, 0.0))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = canvas
	tool.selected_shapes = [shape]
	tool.transform_initial_mouse = Vector2.ZERO
	tool.transform_initial_states = {shape: tool._snapshot(shape)}

	# Simula el bloque de traslación directa de _on_motion() sin pasar por
	# eventos de input reales (SnapManager no está registrado en este árbol
	# de test, así que la rama de snap simplemente no se activa).
	var delta: Vector2 = Vector2(15.0, -5.0)
	for s in tool.selected_shapes:
		var snap: Dictionary = tool.transform_initial_states[s]
		var new_pos: Vector2 = snap["gpos"] + delta
		s.global_position = new_pos
		tool._sync_doc_position_from_native(s)

	assert_vector(shape.position).is_equal(Vector2(15.0, -5.0))
	assert_float(shape.doc_position.x).is_equal(15.0)
	assert_float(shape.doc_position.y).is_equal(-5.0)

# ── Marquee (arrastre de selección) ──────────────────────────────────────────

## Regresión del bug encontrado el 19/08/2026 a partir del reporte del
## usuario ("fuera de artboard funciona, dentro no"): un clic en espacio
## vacío DENTRO del artboard (sin este seleccionado) caía en la rama
## "if ab_rect.has_point(...)" de _on_press, hacía _clear_selection() y
## devolvía false SIN activar is_marquee — así que arrastrar dentro del
## artboard nunca disparaba selección múltiple, solo fuera de él.
func test_click_on_empty_space_inside_artboard_starts_marquee() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)
	artboard.is_selected = false

	# Punto bien dentro del artboard (tamaño por defecto 794x1123) y lejos de
	# cualquier figura, para caer en la rama de "espacio vacío".
	var click_point: Vector2 = artboard.to_global(Vector2(400, 400))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard

	var handled: bool = tool._on_press(click_point)

	assert_bool(handled).is_true()
	assert_bool(tool.is_marquee).is_true()
	assert_vector(tool.marquee_start).is_equal(click_point)

## Comportamiento existente que el fix de arriba no debe romper: si el
## artboard YA está seleccionado, un clic en su espacio vacío interior debe
## seguir arrastrando el artboard en vez de iniciar un marquee.
func test_click_on_empty_space_inside_selected_artboard_drags_artboard() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var artboard: _FakeArtboard = auto_free(_FakeArtboard.new())
	root.add_child(artboard)
	artboard.is_selected = true

	var click_point: Vector2 = artboard.to_global(Vector2(400, 400))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard

	var handled: bool = tool._on_press(click_point)

	assert_bool(handled).is_true()
	assert_bool(tool.is_dragging_artboard).is_true()
	assert_bool(tool.is_marquee).is_false()

## Invariante: el marquee debe seleccionar exactamente las figuras cuyo AABB
## intersecta el rectángulo arrastrado, y NINGUNA de las que quedan fuera.
func test_marquee_selects_only_shapes_intersecting_the_drag_rect() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var inside_shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(inside_shape)
	inside_shape.position = Vector2(50, 50)
	inside_shape.size = Vector2(20, 20)  # AABB: (40,40)-(60,60)

	var outside_shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(outside_shape)
	outside_shape.position = Vector2(500, 500)
	outside_shape.size = Vector2(20, 20)  # AABB: (490,490)-(510,510)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard

	tool.marquee_start = Vector2(0, 0)
	tool.marquee_end = Vector2(100, 100)
	tool._apply_marquee()

	assert_array(tool.selected_shapes).contains_exactly([inside_shape])

## Una figura DENTRO de un grupo debe poder cogerse con el ratón: el hit-test
## recorre la rama y devuelve el GRUPO de primer nivel (clic sencillo). Antes
## solo miraba hijos directos → clic en el relleno de un hijo lo deseleccionaba.
func test_hit_test_encuentra_figura_dentro_de_grupo() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var grupo: Node2D = auto_free(Node2D.new())
	grupo.set_meta("shape_type", "group")
	artboard.add_child(grupo)
	var hijo: VectorRectangle = auto_free(VectorRectangle.new())
	grupo.add_child(hijo)
	hijo.global_position = Vector2(100, 100)
	hijo.size = Vector2(40, 40)   # AABB global: (80,80)-(120,120)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard

	var hit = tool._shape_at(Vector2(100, 100))
	assert_object(hit).is_same(grupo)   # el grupo, no el hijo

	# Pero si el hijo YA está seleccionado, el clic arrastra el hijo.
	tool.selected_shapes = [hijo]
	assert_object(tool._primer_seleccionado_en_rama(grupo)).is_same(hijo)


## Regresión: Alt durante el marquee debe RESTAR de la selección actual las
## figuras que toca, no reemplazarla ni sumarlas.
func test_marquee_with_alt_subtracts_touched_shapes_from_selection() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(50, 50)
	shape.size = Vector2(20, 20)  # AABB: (40,40)-(60,60)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]

	var alt_down := InputEventKey.new()
	alt_down.keycode = KEY_ALT
	alt_down.pressed = true
	Input.parse_input_event(alt_down)
	Input.flush_buffered_events()

	tool.marquee_start = Vector2(0, 0)
	tool.marquee_end = Vector2(100, 100)
	tool._apply_marquee()

	var alt_up := InputEventKey.new()
	alt_up.keycode = KEY_ALT
	alt_up.pressed = false
	Input.parse_input_event(alt_up)
	Input.flush_buffered_events()

	assert_array(tool.selected_shapes).is_empty()

# ── Shift+clic (multiselección) ──────────────────────────────────────────────

## Regresión del bug encontrado el 19/08/2026: Shift+clic sobre una figura YA
## seleccionada no la quitaba de la selección (_on_press solo sabía sumar,
## nunca restar). Ver MoveTool.gd::_on_press.
func test_shift_click_on_already_selected_shape_deselects_it() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(50, 50)
	shape.size = Vector2(40, 40)
	shape.set_doc_position(DVec2.new(50, 50))
	shape.set_doc_extent(DVec2.new(40, 40))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]

	var shift_down := InputEventKey.new()
	shift_down.keycode = KEY_SHIFT
	shift_down.pressed = true
	Input.parse_input_event(shift_down)
	Input.flush_buffered_events()

	tool._on_press(shape.global_position)

	var shift_up := InputEventKey.new()
	shift_up.keycode = KEY_SHIFT
	shift_up.pressed = false
	Input.parse_input_event(shift_up)
	Input.flush_buffered_events()

	assert_array(tool.selected_shapes).is_empty()

## Comportamiento existente que el fix de arriba no debe romper: Shift+clic
## sobre una figura NO seleccionada debe añadirla, conservando la selección previa.
func test_shift_click_on_unselected_shape_adds_it_to_selection() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var already_selected: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(already_selected)
	already_selected.position = Vector2(50, 50)
	already_selected.size = Vector2(20, 20)
	already_selected.set_doc_position(DVec2.new(50, 50))
	already_selected.set_doc_extent(DVec2.new(20, 20))

	var new_shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(new_shape)
	new_shape.position = Vector2(300, 50)
	new_shape.size = Vector2(20, 20)
	new_shape.set_doc_position(DVec2.new(300, 50))
	new_shape.set_doc_extent(DVec2.new(20, 20))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [already_selected]

	var shift_down := InputEventKey.new()
	shift_down.keycode = KEY_SHIFT
	shift_down.pressed = true
	Input.parse_input_event(shift_down)
	Input.flush_buffered_events()

	tool._on_press(new_shape.global_position)

	var shift_up := InputEventKey.new()
	shift_up.keycode = KEY_SHIFT
	shift_up.pressed = false
	Input.parse_input_event(shift_up)
	Input.flush_buffered_events()

	assert_array(tool.selected_shapes).contains_exactly([already_selected, new_shape])

# ── Señal object_transformed ──────────────────────────────────────────────

## Regresión: _on_release() debe emitir GlobalEvents.object_transformed
## cuando de verdad hubo una transformación (arrastre de figura), para que
## LayerSystem pueda refrescar el indicador de "fuera del artboard". Antes
## esta señal existía declarada en GlobalEvents pero nada la disparaba nunca.
func test_on_release_emits_object_transformed_after_dragging_a_shape() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.is_dragging_shape = true

	var recibido: Array = [false]
	var callback := func(): recibido[0] = true
	GlobalEvents.object_transformed.connect(callback)

	tool._on_release(Vector2.ZERO)

	GlobalEvents.object_transformed.disconnect(callback)

	assert_bool(recibido[0]).is_true()

## Comportamiento existente que no debe romperse: un release sin ningún
## arrastre/transformación activa (p.ej. un simple clic) NO debe emitir la
## señal — evita refrescos innecesarios del panel de capas en cada clic.
func test_on_release_does_not_emit_object_transformed_without_a_transform() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root

	var recibido: Array = [false]
	var callback := func(): recibido[0] = true
	GlobalEvents.object_transformed.connect(callback)

	tool._on_release(Vector2.ZERO)

	GlobalEvents.object_transformed.disconnect(callback)

	assert_bool(recibido[0]).is_false()


# ── Autocuración de gesto atascado ───────────────────────────────────────────

## REGRESIÓN CRÍTICA: `bounding_box._on_drag_panel_gui_input` pone
## `is_dragging_shape = true` al pulsar el gizmo; si la SUELTA no llega (el
## panel se alejó bajo el cursor), el flag se queda atascado y `_on_motion`
## consume TODOS los eventos → el editor entero se bloquea (ni panel de capas
## ni arrastre de artboard). `_heal_stuck_gesture` lo cierra si el botón
## izquierdo NO está pulsado de verdad.
func test_heal_stuck_gesture_cierra_arrastre_sin_boton_pulsado() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root

	# Simula el estado zombi dejado por el gizmo: arrastrando pero sin botón.
	tool.is_dragging_shape = true
	tool.is_marquee = true
	tool.is_resizing = true
	tool.transform_initial_states = {root: {}}

	# Asegura que el botón izquierdo NO consta como pulsado.
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()

	tool._heal_stuck_gesture()

	assert_bool(tool.is_dragging_shape).is_false()
	assert_bool(tool.is_marquee).is_false()
	assert_bool(tool.is_resizing).is_false()
	assert_bool(tool.transform_initial_states.is_empty()).is_true()


## El gesto legítimo (botón izquierdo pulsado de verdad) NO se cancela.
func test_heal_stuck_gesture_respeta_arrastre_con_boton_pulsado() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.is_dragging_shape = true

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()

	tool._heal_stuck_gesture()
	assert_bool(tool.is_dragging_shape).is_true()   # sigue arrastrando

	# limpieza: soltar el botón para no contaminar otros tests
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
