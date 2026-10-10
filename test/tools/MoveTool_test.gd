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
## BUG REAL reportado en vivo ("shift y drag... de repente ha desaparecido
## boundingbox"): _on_press deselecciónaba INMEDIATAMENTE, así que el simple
## gesto de apretar Shift y empezar a arrastrar una figura ya seleccionada la
## quitaba de la selección antes de que el arrastre llegara a moverla. Ahora
## el press solo marca el candidato (_pending_shift_deselect) y el release
## decide: sin arrastre real (este test, misma posición) = deselecciona,
## igual que antes de punta a punta del gesto completo.
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
	# Todavía seleccionada justo tras el press — el bounding box no debe
	# desaparecer solo por pulsar Shift y apoyar el botón.
	assert_array(tool.selected_shapes).contains([shape])

	tool._on_release(shape.global_position)  # mismo punto = sin arrastre real

	var shift_up := InputEventKey.new()
	shift_up.keycode = KEY_SHIFT
	shift_up.pressed = false
	Input.parse_input_event(shift_up)
	Input.flush_buffered_events()

	assert_array(tool.selected_shapes).is_empty()

## El mismo gesto pero CON arrastre real de por medio no debe deseleccionar
## — la figura sigue seleccionada (y con el eje de Shift ya aplicado), tal
## como se espera al mover con Shift una figura que ya estaba seleccionada.
func test_shift_drag_sobre_figura_ya_seleccionada_no_la_deselecciona() -> void:
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
	assert_bool(tool.is_dragging_shape).is_true()

	# Arrastre real: se mueve claramente más de los 3px de umbral.
	tool._on_motion(shape.global_position + Vector2(40, 2), {"shift": true, "alt": false, "ctrl": false})
	tool._on_release(shape.global_position + Vector2(40, 2))

	var shift_up := InputEventKey.new()
	shift_up.keycode = KEY_SHIFT
	shift_up.pressed = false
	Input.parse_input_event(shift_up)
	Input.flush_buffered_events()

	assert_array(tool.selected_shapes).contains([shape])

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

func test_shape_at_finds_rotated_rectangle_accurately() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(200, 200)
	shape.size = Vector2(100, 100)
	shape.rotation = deg_to_rad(45.0)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard

	# Punto dentro del rombo (en el eje local Y a 40px del centro): dentro
	var pt_inside: Vector2 = shape.to_global(Vector2(0, 40))
	assert_object(tool._shape_at(pt_inside)).is_same(shape)

	# Punto en la esquina AABB no rotada (45, 45) relativo al centro: fuera del rombo
	var pt_outside: Vector2 = shape.position + Vector2(45, 45)
	assert_object(tool._shape_at(pt_outside)).is_null()

## Estilo Figma/Affinity (ver comentario grande en _perform_alt_drag_duplication):
## el nodo que se está arrastrando (`shape`) NUNCA se toca — sigue siendo el
## mismo, en su posición YA ARRASTRADA, seleccionado, con su
## transform_initial_states/transform_initial_mouse intactos. Lo único nuevo
## es el clon, que nace INMÓVIL en el snapshot inicial (antes de arrastrar) y
## no participa más en este gesto. La versión anterior restauraba `shape` a
## su posición inicial y reasignaba la selección al clon — ese swap a mitad
## de gesto era la causa real del salto reportado en vivo ("se nota salta
## rápido... quiero igual a Affinity y Figma").
func test_alt_drag_duplication_creates_duplicate_leaving_original() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)
	shape.set_doc_position(DVec2.new(100, 100))
	shape.set_doc_extent(DVec2.new(50, 50))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]
	tool.transform_initial_states[shape] = tool._snapshot(shape)
	tool.transform_initial_mouse = Vector2(100, 100)

	# El gesto ya venía arrastrando `shape` antes de que se detectara Alt
	# (igual que hace _on_motion en el bloque is_dragging_shape antes de
	# llamar a _perform_alt_drag_duplication).
	shape.global_position = Vector2(150, 150)

	var count_before: int = artboard.get_child_count()
	tool._perform_alt_drag_duplication(Vector2(150, 150))

	assert_int(artboard.get_child_count()).is_equal(count_before + 1)

	# La selección y el estado de arrastre siguen intactos sobre `shape` —
	# nada se reasigna a mitad de gesto.
	assert_int(tool.selected_shapes.size()).is_equal(1)
	assert_object(tool.selected_shapes[0]).is_same(shape)
	assert_vector(tool.transform_initial_mouse).is_equal(Vector2(100, 100))
	assert_object(tool.transform_initial_states.keys()[0]).is_same(shape)

	# El original SIGUE en su posición ya arrastrada — sin salto.
	assert_vector(shape.global_position).is_equal(Vector2(150, 150))

	# El clon queda quieto en la posición ANTERIOR al arrastre.
	var clone: Node2D = null
	for c in artboard.get_children():
		if c != shape and c is VectorRectangle:
			clone = c
	assert_object(clone).is_not_null()
	assert_object(clone).is_not_same(shape)
	assert_vector(clone.global_position).is_equal(Vector2(100, 100))

func test_shift_drag_edge_adjusts_stroke_width() -> void:
	# Rectangles: Shift+edge handle changes only that side (per-side stroke)
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)
	shape.set("stroke_width", 2.0)
	shape.set_doc_position(DVec2.new(100, 100))
	shape.set_doc_extent(DVec2.new(50, 50))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]
	tool.resize_handle = "rc"
	tool.transform_initial_mouse = Vector2(100, 100)
	tool.transform_macro_rect = Rect2(75, 75, 50, 50)

	tool.transform_initial_states = {shape: tool._snapshot(shape)}
	tool.is_resizing = true

	var shift_down := InputEventKey.new()
	shift_down.keycode = KEY_SHIFT
	shift_down.pressed = true
	Input.parse_input_event(shift_down)
	Input.flush_buffered_events()

	tool._apply_resize(Vector2(120, 100))
	assert_float(shape.get_side_widths().y).is_equal_approx(5.0, 0.01)

	# Verificar que múltiples frames con el mismo mouse no acumulan el delta
	tool._apply_resize(Vector2(120, 100))
	assert_float(shape.get_side_widths().y).is_equal_approx(5.0, 0.01)

	var shift_up := InputEventKey.new()
	shift_up.keycode = KEY_SHIFT
	shift_up.pressed = false
	Input.parse_input_event(shift_up)
	Input.flush_buffered_events()

	# Release para consolidar en HistoryManager
	tool._on_release(Vector2(120, 100))
	assert_float(shape.get_side_widths().y).is_equal_approx(5.0, 0.01)

	# Undo debe restaurar exactamente a 2.0
	HistoryManager.undo()
	assert_float(shape.get_side_widths().y).is_equal_approx(2.0, 0.01)

	# Redo debe volver a 5.0
	HistoryManager.redo()
	assert_float(shape.get_side_widths().y).is_equal_approx(5.0, 0.01)

## BUG REAL reportado por el usuario ("shift con drag para grosor no funciona
## bien"): el handle "lc" (borde izquierdo) usaba el mismo signo que "rc"
## para stroke_delta, así que arrastrar hacia afuera (más a la izquierda,
## delta.x negativo) ADELGAZABA el trazo en vez de engrosarlo — al revés de
## "rc"/"bc" y al revés de como ya se comporta sx/sy para lc/tc unas líneas
## más arriba en la misma función (resta en vez de suma). Mismo caso con
## "tc" contra "bc". Fix: invertir el signo para lc/tc igual que sx/sy.
func test_shift_drag_edge_izquierdo_engruesa_al_arrastrar_hacia_afuera() -> void:
	# Rectangles: Shift+edge handle changes only that side (per-side stroke)
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)
	shape.set("stroke_width", 2.0)
	shape.set_doc_position(DVec2.new(100, 100))
	shape.set_doc_extent(DVec2.new(50, 50))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]
	tool.resize_handle = "lc"
	tool.transform_initial_mouse = Vector2(100, 100)
	tool.transform_macro_rect = Rect2(75, 75, 50, 50)
	tool.transform_initial_states = {shape: tool._snapshot(shape)}
	tool.is_resizing = true

	# Arrastrar el handle izquierdo HACIA AFUERA (más a la izquierda) debe
	# engrosar el trazo, igual que arrastrar "rc" hacia afuera (a la derecha).
	tool._on_motion(Vector2(80, 100), {"shift": true, "alt": false, "ctrl": false})
	assert_float(shape.get_side_widths().w).is_equal_approx(5.0, 0.01)

	# Arrastrar hacia ADENTRO (a la derecha, invadiendo la figura) adelgaza.
	tool.transform_initial_states = {shape: tool._snapshot(shape)}
	tool.transform_initial_mouse = Vector2(100, 100)
	tool._on_motion(Vector2(110, 100), {"shift": true, "alt": false, "ctrl": false})
	assert_float(shape.get_side_widths().w).is_less(5.0)

## Mismo bug, cara Line2D: los trazos de pincel reales (BrushTool) son un
## Line2D crudo sin propiedad "stroke_width" (usan ".width"), y no pasan por
## VectorRectangle. Verifica el camino completo _get/_set_shape_stroke_width
## -> Line2D.width con el handle "tc" (borde superior), que también necesita
## el signo invertido.
func test_shift_drag_edge_superior_engruesa_trazo_line2d() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var stroke: Line2D = auto_free(Line2D.new())
	artboard.add_child(stroke)
	stroke.points = PackedVector2Array([Vector2(80, 100), Vector2(150, 100)])
	stroke.width = 4.0

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [stroke]
	tool.resize_handle = "tc"
	tool.transform_initial_mouse = Vector2(100, 100)
	tool.transform_macro_rect = tool._global_rect(stroke)
	tool.transform_initial_states = {stroke: tool._snapshot(stroke)}
	tool.is_resizing = true

	# Arrastrar el handle superior HACIA ARRIBA (afuera) debe engrosar.
	tool._on_motion(Vector2(100, 70), {"shift": true, "alt": false, "ctrl": false})
	assert_float(stroke.width).is_greater(4.0)

## _apply_resize/_apply_rotation leían Input.is_key_pressed() (estado global
## sondeado en un stream aparte de keydown/keyup) en vez del InputEventMouseMotion
## real — mismo bug que IHTML documentó y corrigió en
## js/workspace/bounding-box.js _onHandleDown (desincroniza si el modificador
## cambia a mitad del arrastre, porque keydown/keyup y mousemove llegan en
## cuadros distintos; "estilo Affinity: apretar Shift a mitad del arrastre
## engancha la proporción en el acto, sin race"). Ahora handle_input arma un
## dict `mods` desde InputEventMouseMotion.shift_pressed/alt_pressed/ctrl_pressed
## y lo pasa a _on_motion -> _apply_resize/_apply_rotation, con fallback a
## Input.is_key_pressed() solo cuando no hay dict (InputEventScreenDrag, que no
## trae esos campos). Este test NO toca el teclado global (Input.parse_input_event)
## — si _apply_resize volviera a leer solo el estado global, fallaría porque
## Shift no está realmente pulsado ahí.
func test_resize_lee_shift_del_dict_mods_no_del_input_global() -> void:
	# Rectangles: Shift+edge handle changes only that side (per-side stroke)
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)
	shape.set("stroke_width", 2.0)
	shape.set_doc_position(DVec2.new(100, 100))
	shape.set_doc_extent(DVec2.new(50, 50))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]
	tool.resize_handle = "rc"
	tool.transform_initial_mouse = Vector2(100, 100)
	tool.transform_macro_rect = Rect2(75, 75, 50, 50)
	tool.transform_initial_states = {shape: tool._snapshot(shape)}
	tool.is_resizing = true

	tool._on_motion(Vector2(120, 100), {"shift": true, "alt": false, "ctrl": false})

	assert_bool(tool._is_stroke_adjusting).is_true()
	assert_float(shape.get_side_widths().y).is_equal_approx(5.0, 0.01)

## Mismo mecanismo de "leer del dict mods, no del Input global" aplicado al
## bloque is_dragging_shape (Alt = duplicar al vuelo, Shift = restringir a un
## eje) — mismo bug class que el resize, ver el comentario grande en
## handle_input. Prueba el camino real completo vía _on_motion, no llamando
## _perform_alt_drag_duplication() directo (eso no ejercita la lectura de
## mods en sí).
func test_drag_lee_alt_del_dict_mods_y_duplica_sin_tocar_input_global() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)
	shape.set_doc_position(DVec2.new(100, 100))
	shape.set_doc_extent(DVec2.new(50, 50))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]
	tool.transform_initial_states[shape] = tool._snapshot(shape)
	tool.transform_initial_mouse = Vector2(100, 100)
	tool.is_dragging_shape = true

	var count_before: int = artboard.get_child_count()
	# Movimiento > 3px del umbral de duplicación, con alt=true SOLO en el
	# dict — el teclado global se queda sin Alt realmente pulsado.
	tool._on_motion(Vector2(110, 100), {"shift": false, "alt": true, "ctrl": false})

	assert_int(artboard.get_child_count()).is_equal(count_before + 1)
	assert_bool(tool._alt_drag_duplicated).is_true()

## BUG REAL reportado en vivo ("shift y drag en area de BB... sigue con
## fallos"): el eje de Shift+arrastrar (cuerpo de la figura, no un handle) se
## recalculaba CADA frame contra el delta acumulado desde el inicio del
## gesto — si el mouse pasaba cerca de la diagonal, el eje "bloqueado" podía
## cambiar a mitad de arrastre. Debe decidirse una sola vez y quedar fijo
## hasta soltar Shift (estilo Figma/Affinity).
func test_shift_drag_eje_se_decide_una_vez_y_no_cambia_a_mitad_de_gesto() -> void:
	# Axis lock moved from Shift to Ctrl (Shift+drag on the body = stroke width)
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)
	shape.set_doc_position(DVec2.new(100, 100))
	shape.set_doc_extent(DVec2.new(50, 50))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]
	tool.transform_initial_states[shape] = tool._snapshot(shape)
	tool.transform_initial_mouse = Vector2(100, 100)
	tool.is_dragging_shape = true

	# Primer movimiento: más horizontal que vertical -> fija el eje X.
	tool._on_motion(Vector2(110, 103), {"shift": false, "alt": false, "ctrl": true})
	assert_str(tool._shift_drag_axis).is_equal("x")
	assert_float(shape.global_position.y).is_equal_approx(100.0, 0.01)

	# Segundo movimiento: ahora predominantemente vertical (cruza la
	# diagonal) — el eje YA FIJADO no debe cambiar a "y".
	tool._on_motion(Vector2(101, 140), {"shift": false, "alt": false, "ctrl": true})
	assert_str(tool._shift_drag_axis).is_equal("x")
	assert_float(shape.global_position.y).is_equal_approx(100.0, 0.01)
	# Ctrl also keeps its grid pull, only along the locked axis
	var gs: float = float(SnapManager.grid_size) if SnapManager.grid_size > 0 else 1.0
	assert_float(shape.global_position.x).is_equal_approx(roundf(101.0 / gs) * gs, 0.01)

	# Soltar Shift libera el eje; volver a pulsarlo lo vuelve a decidir.
	tool._on_motion(Vector2(101, 150), {"shift": false, "alt": false, "ctrl": false})
	assert_str(tool._shift_drag_axis).is_equal("")

## Ctrl+arrastrar debe FORZAR el snap a grilla aunque el toggle permanente
## (SnapManager.grid_enabled, Ajustes) esté apagado — igual que IHTML
## (js/workspace/drag.js: "const snapToGrid = e.ctrlKey || settings.grid.snap").
## Antes Ctrl no hacía nada en el bloque de arrastre (pedido explícito del
## usuario tras probarlo en vivo: "con ctrl y drag para mover vertical o
## horizontal" — resultó ser snap a grilla, no eje, ver SnapManager.snap_position).
func test_drag_ctrl_fuerza_snap_a_grilla_aunque_el_toggle_este_apagado() -> void:
	var prev_grid_enabled: bool = SnapManager.grid_enabled
	var prev_grid_size: float = SnapManager.grid_size
	SnapManager.grid_enabled = false
	SnapManager.grid_size = 20.0

	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)
	shape.set_doc_position(DVec2.new(100, 100))
	shape.set_doc_extent(DVec2.new(50, 50))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]
	tool.transform_initial_states[shape] = tool._snapshot(shape)
	tool.transform_initial_mouse = Vector2(100, 100)
	tool.is_dragging_shape = true

	# Mover a (107,111): sin grilla quedaría ahí; a grilla de 20 redondea a
	# (100,120). El teclado global NO tiene Ctrl pulsado — solo el dict mods.
	tool._on_motion(Vector2(107, 111), {"shift": false, "alt": false, "ctrl": true})

	assert_vector(shape.global_position).is_equal_approx(Vector2(100, 120), Vector2(0.01, 0.01))

	SnapManager.grid_enabled = prev_grid_enabled
	SnapManager.grid_size = prev_grid_size

## Mismo mecanismo para Alt (redimensionar desde el centro) — comprobado por
## separado porque _apply_resize lee "alt" y "shift" del mismo dict con
## ramas de código distintas.
func test_resize_lee_alt_del_dict_mods_no_del_input_global() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)
	shape.set_doc_position(DVec2.new(100, 100))
	shape.set_doc_extent(DVec2.new(50, 50))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]
	tool.resize_handle = "rc"
	tool.transform_initial_mouse = Vector2(100, 100)
	tool.transform_macro_rect = Rect2(75, 75, 50, 50)
	tool.transform_initial_states = {shape: tool._snapshot(shape)}
	tool.is_resizing = true

	# rc + alt: crece simétrico desde el centro en X (sx cambia, sy queda 1.0).
	tool._on_motion(Vector2(120, 100), {"shift": false, "alt": true, "ctrl": false})

	assert_bool(tool._is_stroke_adjusting).is_false()
	assert_float(tool.live_scale.x).is_greater(1.0)
	assert_float(tool.live_pivot.x).is_equal_approx(100.0, 0.01) # centro del rect 75..125

## Ctrl+rotar = redondeo a grado entero (sin Shift) — Vectopen solo tenía el
## snap de Shift a 15°; se agrega el segundo modificador de rotación que ya
## trae IHTML (bounding-box.js _onRotationStart: shift=15°, ctrl=1°) para
## igualar el mismo "método completo" de acceso rápido por teclado. También
## prueba que "ctrl" se lee del dict mods, no de Input.is_key_pressed(KEY_CTRL).
func test_rotate_ctrl_redondea_a_grado_entero_via_dict_mods() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)
	shape.set_doc_position(DVec2.new(100, 100))
	shape.set_doc_extent(DVec2.new(50, 50))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]
	tool.transform_initial_states = {shape: tool._snapshot(shape)}
	tool.is_rotating = true
	tool.initial_macro_center = Vector2(125, 125) # centro del rect 100,100..150,150
	tool.transform_initial_mouse = Vector2(175, 125) # 0° de partida (a la derecha del centro)

	# Ángulo que cae lejos de un múltiplo de 15° pero cerca de uno entero,
	# para distinguir claramente "redondeo a 1°" de "snap a 15°": 100,225
	# respecto al centro (125,125) da un ángulo de ~48.65...°.
	tool._on_motion(Vector2(100.0, 225.0), {"shift": false, "alt": false, "ctrl": true})

	assert_float(rad_to_deg(tool.live_rot_angle)).is_equal_approx(round(rad_to_deg(tool.live_rot_angle)), 0.001)
	# Y NO cayó en el snap de 15° (48.65 no redondea a un múltiplo de 15):
	assert_bool(is_equal_approx(fmod(rad_to_deg(tool.live_rot_angle), 15.0), 0.0)).is_false()

## New keyboard transform bindings (user request): bare G/R/S are freed for
## single-letter tool switching (see canvas.gd TOOL_SWITCH_KEYS); the move/
## rotate/scale key-modes now require Shift so they don't collide with tool
## switching. G was left as-is for gradient toggle (bare, no shift) since
## that's a real, already-shipped feature.
func test_shift_g_starts_translate_key_mode() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]

	var handled: bool = tool._handle_key_shortcuts(KEY_G, true)

	assert_bool(handled).is_true()
	assert_int(tool.current_key_mode).is_equal(MoveTool.KeyMode.TRANSLATE)
	# Bare G (no shift) must still toggle gradient mode, untouched.
	assert_bool(tool.is_gradient_mode).is_false()

func test_shift_r_starts_rotate_key_mode() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]

	assert_bool(tool._handle_key_shortcuts(KEY_R, true)).is_true()
	assert_int(tool.current_key_mode).is_equal(MoveTool.KeyMode.ROTATE)

func test_shift_s_starts_scale_key_mode() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]

	assert_bool(tool._handle_key_shortcuts(KEY_S, true)).is_true()
	assert_int(tool.current_key_mode).is_equal(MoveTool.KeyMode.SCALE)

## Bare R/S (no shift) must NOT start a key-transform mode anymore — they're
## freed up for canvas.gd's single-letter tool switching. Real regression
## guard: before this session's change, bare R/S unconditionally called
## _start_key_mode.
func test_bare_r_and_s_do_not_start_key_mode() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]

	assert_bool(tool._handle_key_shortcuts(KEY_R, false)).is_false()
	assert_int(tool.current_key_mode).is_equal(MoveTool.KeyMode.NONE)
	assert_bool(tool._handle_key_shortcuts(KEY_S, false)).is_false()
	assert_int(tool.current_key_mode).is_equal(MoveTool.KeyMode.NONE)

## X with a selection and no active key-transform now deletes the selection
## (Blender-style: X deletes when idle, locks the X axis mid-transform).
func test_bare_x_deletes_selection_when_idle() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]

	assert_bool(tool._handle_key_shortcuts(KEY_X, false)).is_true()
	# delete_selected() removes the node from the tree but keeps it alive
	# (undo support) — it doesn't free() it, so check tree membership instead.
	assert_bool(shape.is_inside_tree()).is_false()
	assert_array(tool.selected_shapes).is_empty()

## Delete / Supr / Backspace with a selection when idle also deletes the selection.
func test_delete_and_backspace_delete_selection_when_idle() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape1: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape1)
	shape1.position = Vector2(100, 100)
	shape1.size = Vector2(50, 50)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape1]

	assert_bool(tool._handle_key_shortcuts(KEY_DELETE, false)).is_true()
	assert_bool(shape1.is_inside_tree()).is_false()
	assert_array(tool.selected_shapes).is_empty()

	var shape2: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape2)
	tool.selected_shapes = [shape2]

	assert_bool(tool._handle_key_shortcuts(KEY_BACKSPACE, false)).is_true()
	assert_bool(shape2.is_inside_tree()).is_false()
	assert_array(tool.selected_shapes).is_empty()

## X during an ACTIVE key-transform must still lock the X axis, not delete —
## the pre-existing Blender-style behavior must survive the new idle-X=delete
## addition.
func test_x_during_active_transform_still_locks_axis_not_delete() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(50, 50)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool.selected_shapes = [shape]
	tool.current_key_mode = MoveTool.KeyMode.TRANSLATE

	assert_bool(tool._handle_key_shortcuts(KEY_X, false)).is_true()
	assert_int(tool.current_axis).is_equal(MoveTool.AxisLock.X)
	assert_bool(shape.is_inside_tree()).is_true()

func test_image_sprite_bounding_box_and_resize() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	add_child(canvas)

	# Crear un Sprite2D con una imagen real
	var img := Image.create(200, 100, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	var sprite: Sprite2D = auto_free(Sprite2D.new())
	sprite.texture = tex
	sprite.centered = false
	sprite.position = Vector2(50, 50)
	canvas.add_child(sprite)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = canvas
	tool.selected_shapes = [sprite]

	# 1. El rect global debe medir exactamente 200x100
	var gr: Rect2 = tool._global_rect(sprite)
	assert_float(gr.size.x).is_equal_approx(200.0, 0.1)
	assert_float(gr.size.y).is_equal_approx(100.0, 0.1)

	# 2. _snapshot debe capturar la escala del Sprite2D
	var snap := tool._snapshot(sprite)
	assert_bool(snap.has("scale")).is_true()
	assert_vector(snap["scale"]).is_equal(Vector2.ONE)

	# 3. _apply_resize debe escalar el Sprite2D
	tool.resize_handle = "br"
	tool.transform_macro_rect = gr
	tool.transform_initial_states = {sprite: snap}
	tool.transform_initial_mouse = gr.end

	# 3a. Sin Control: escala uniforme EXACTA sin estirar nada la imagen (proporcional)
	# Aunque el ratón se mueva 200px en X (factor 2.0) y solo 50px en Y (factor 1.5)
	tool._apply_resize(gr.end + Vector2(200, 50), {"ctrl": false})
	assert_float(sprite.scale.x).is_equal_approx(2.0, 0.05)
	assert_float(sprite.scale.y).is_equal_approx(2.0, 0.05)

	# 3b. Con Control: permite estirar libremente en anchura y altura
	tool._restore_transform(sprite, snap)
	tool._apply_resize(gr.end + Vector2(200, 50), {"ctrl": true})
	assert_float(sprite.scale.x).is_equal_approx(2.0, 0.05)
	assert_float(sprite.scale.y).is_equal_approx(1.5, 0.05)

	# 4. _restore_transform debe restaurar la escala original (Undo)
	tool._restore_transform(sprite, snap)
	assert_vector(sprite.scale).is_equal(Vector2.ONE)

