extends GdUnitTestSuite

## BUG HUNT + REGRESIÓN del sistema de selección / transformación (bounding box).
## Cada bug encontrado se añade aquí como test permanente.
##
## Invariantes que se comprueban una y otra vez:
##   I1  una transformación NO toca figuras no seleccionadas
##   I2  undo devuelve EXACTAMENTE el estado anterior
##   I3  redo reproduce EXACTAMENTE la operación deshecha
##   I4  cadenas mover→rotar→escalar→undo×N→redo×N vuelven al mismo estado
##   I5  delete + undo restaura los MISMOS nodos en su sitio

const CANVAS := "res://scenes/canvas/canvas.tscn"

func _scene() -> Node2D:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	return s

func _tool(s: Node2D) -> MoveTool:
	# la herramienta activa de canvas.tscn ya es MoveTool y ya está en el árbol
	var t = s.current_tool
	if not (t and t.get_class_name() == "MoveTool"):
		s.switch_tool("move")
		t = s.current_tool
	return t

func _rect(parent: Node, pos: Vector2, size := Vector2(80, 60)) -> VectorRectangle:
	var r := VectorRectangle.new()
	r.size = size
	parent.add_child(r)
	r.global_position = pos
	return r

func _state(s: Node2D) -> Dictionary:
	return {"pos": s.global_position, "rot": s.global_rotation, "size": s.get("size")}

func _assert_state(actual: Dictionary, expected: Dictionary, msg := "") -> void:
	assert_vector(actual["pos"]).override_failure_message("pos " + msg).is_equal_approx(expected["pos"], Vector2(0.5, 0.5))
	assert_float(actual["rot"]).override_failure_message("rot " + msg).is_equal_approx(expected["rot"], 0.001)
	assert_vector(actual["size"]).override_failure_message("size " + msg).is_equal_approx(expected["size"], Vector2(0.5, 0.5))

# ── helpers de gesto ─────────────────────────────────────────────────────────
func _begin(t: MoveTool, shapes: Array) -> void:
	t.selected_shapes.assign(shapes)
	t.transform_initial_states.clear()
	for x in shapes:
		t.transform_initial_states[x] = t._snapshot(x)
	t.transform_initial_mouse = Vector2.ZERO

func _drag(t: MoveTool, shapes: Array, delta: Vector2) -> void:
	_begin(t, shapes)
	t.is_dragging_shape = true
	for x in shapes:
		x.global_position += delta
		t._sync_doc_position_from_native(x)
	t._on_release(delta)

func _resize(t: MoveTool, shapes: Array, handle: String, delta: Vector2) -> void:
	t.selected_shapes.assign(shapes)
	t.start_handle_transform(handle)
	t.transform_initial_mouse = Vector2.ZERO
	t._on_motion(delta)
	t._on_release(delta)

func _rotate(t: MoveTool, shapes: Array, ang_rad: float) -> void:
	_begin(t, shapes)
	t.is_rotating = true
	for x in shapes:
		x.global_rotation += ang_rad
		if x is VectorShape:
			x.doc_rotation = x.global_rotation
	t._on_release(Vector2.ZERO)


func test_mover_undo_redo() -> void:
	var s := _scene(); await get_tree().process_frame
	var t := _tool(s)
	var mgr := s.get_node("manager_script") as ArtboardManager
	var ab := mgr.get_active_artboard()
	var r := _rect(ab, Vector2(200, 200))
	await get_tree().process_frame
	HistoryManager.clear()
	var s0 := _state(r)

	_drag(t, [r], Vector2(120, -40))
	assert_vector(r.global_position).is_equal_approx(Vector2(320, 160), Vector2(0.5, 0.5))
	assert_bool(HistoryManager.can_undo()).is_true()

	HistoryManager.undo(); await get_tree().process_frame
	_assert_state(_state(r), s0, "tras undo")
	HistoryManager.redo(); await get_tree().process_frame
	assert_vector(r.global_position).is_equal_approx(Vector2(320, 160), Vector2(0.5, 0.5))
	HistoryManager.clear()


func test_escalar_esquina_undo_redo() -> void:
	var s := _scene(); await get_tree().process_frame
	var t := _tool(s)
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var r := _rect(ab, Vector2(300, 300), Vector2(100, 100))
	await get_tree().process_frame
	HistoryManager.clear()
	var s0 := _state(r)

	_resize(t, [r], "br", Vector2(50, 50))   # esquina inferior-derecha, +50/+50
	assert_vector(r.get("size")).is_not_equal(s0["size"])
	var s1 := _state(r)
	assert_bool(HistoryManager.can_undo()).is_true()

	HistoryManager.undo(); await get_tree().process_frame
	_assert_state(_state(r), s0, "escalar undo")
	HistoryManager.redo(); await get_tree().process_frame
	_assert_state(_state(r), s1, "escalar redo")
	HistoryManager.clear()


func test_rotar_undo_redo() -> void:
	var s := _scene(); await get_tree().process_frame
	var t := _tool(s)
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var r := _rect(ab, Vector2(250, 250))
	await get_tree().process_frame
	HistoryManager.clear()
	var s0 := _state(r)

	_rotate(t, [r], deg_to_rad(37.0))
	assert_float(r.global_rotation).is_equal_approx(deg_to_rad(37.0), 0.001)
	assert_bool(HistoryManager.can_undo()).is_true()

	HistoryManager.undo(); await get_tree().process_frame
	_assert_state(_state(r), s0, "rotar undo")
	HistoryManager.redo(); await get_tree().process_frame
	assert_float(r.global_rotation).is_equal_approx(deg_to_rad(37.0), 0.001)
	HistoryManager.clear()


## I4 — cadena mover→rotar→escalar, deshacer 3 y rehacer 3 → mismo estado.
func test_cadena_mover_rotar_escalar_undo_redo() -> void:
	var s := _scene(); await get_tree().process_frame
	var t := _tool(s)
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var r := _rect(ab, Vector2(200, 200), Vector2(80, 80))
	await get_tree().process_frame
	HistoryManager.clear()
	var s0 := _state(r)

	_drag(t, [r], Vector2(60, 30))
	var sA := _state(r)
	_rotate(t, [r], deg_to_rad(20.0))
	var sB := _state(r)
	_resize(t, [r], "br", Vector2(30, 20))
	var sC := _state(r)

	HistoryManager.undo(); await get_tree().process_frame
	_assert_state(_state(r), sB, "undo escala")
	HistoryManager.undo(); await get_tree().process_frame
	_assert_state(_state(r), sA, "undo rota")
	HistoryManager.undo(); await get_tree().process_frame
	_assert_state(_state(r), s0, "undo mueve → estado ORIGINAL")

	HistoryManager.redo(); await get_tree().process_frame
	_assert_state(_state(r), sA, "redo mueve")
	HistoryManager.redo(); await get_tree().process_frame
	_assert_state(_state(r), sB, "redo rota")
	HistoryManager.redo(); await get_tree().process_frame
	_assert_state(_state(r), sC, "redo escala")
	HistoryManager.clear()


## I1 — transformar una figura NO debe tocar las demás.
func test_transformar_no_toca_las_no_seleccionadas() -> void:
	var s := _scene(); await get_tree().process_frame
	var t := _tool(s)
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var a := _rect(ab, Vector2(150, 150))
	var b := _rect(ab, Vector2(400, 400))
	await get_tree().process_frame
	HistoryManager.clear()
	var b0 := _state(b)

	_drag(t, [a], Vector2(90, 90))
	_rotate(t, [a], deg_to_rad(45.0))
	_resize(t, [a], "tl", Vector2(-20, -20))

	_assert_state(_state(b), b0, "b intacta")
	HistoryManager.clear()


## Multiselección: mover 3 figuras conserva sus posiciones relativas + undo.
func test_multiseleccion_mover_conserva_relativo_y_undo() -> void:
	var s := _scene(); await get_tree().process_frame
	var t := _tool(s)
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var a := _rect(ab, Vector2(100, 100))
	var b := _rect(ab, Vector2(300, 150))
	var c := _rect(ab, Vector2(200, 350))
	await get_tree().process_frame
	HistoryManager.clear()
	var rel_ab := b.global_position - a.global_position
	var rel_ac := c.global_position - a.global_position
	var a0 := a.global_position

	_drag(t, [a, b, c], Vector2(75, -25))
	assert_vector(a.global_position).is_equal_approx(a0 + Vector2(75, -25), Vector2(0.5, 0.5))
	assert_vector(b.global_position - a.global_position).is_equal_approx(rel_ab, Vector2(0.5, 0.5))
	assert_vector(c.global_position - a.global_position).is_equal_approx(rel_ac, Vector2(0.5, 0.5))

	HistoryManager.undo(); await get_tree().process_frame
	assert_vector(a.global_position).is_equal_approx(a0, Vector2(0.5, 0.5))
	HistoryManager.clear()


## I5 — delete + undo restaura los mismos nodos; redo los vuelve a quitar.
func test_delete_undo_redo_multiseleccion() -> void:
	var s := _scene(); await get_tree().process_frame
	var t := _tool(s)
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var a := _rect(ab, Vector2(120, 120)); a.name = "A"
	var b := _rect(ab, Vector2(260, 120)); b.name = "B"
	var keep := _rect(ab, Vector2(400, 120)); keep.name = "KEEP"
	await get_tree().process_frame
	HistoryManager.clear()

	t.selected_shapes.assign([a, b])
	t.delete_selected()
	assert_bool(is_instance_valid(a) and a.is_inside_tree()).is_false()
	assert_bool(is_instance_valid(b) and b.is_inside_tree()).is_false()
	assert_bool(keep.is_inside_tree()).is_true()

	HistoryManager.undo(); await get_tree().process_frame
	assert_bool(a.is_inside_tree()).is_true()
	assert_bool(b.is_inside_tree()).is_true()
	assert_object(a.get_parent()).is_same(ab)

	HistoryManager.redo(); await get_tree().process_frame
	assert_bool(a.is_inside_tree()).is_false()
	assert_bool(b.is_inside_tree()).is_false()
	HistoryManager.clear()
	if is_instance_valid(a): a.free()
	if is_instance_valid(b): b.free()


## Handles de eje: rojo = mover solo X, verde = mover solo Y. + undo.
func test_handle_eje_x_solo_horizontal() -> void:
	var s := _scene(); await get_tree().process_frame
	var t := _tool(s)
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var r := _rect(ab, Vector2(200, 200))
	await get_tree().process_frame
	HistoryManager.clear()
	var p0 := r.global_position

	t.selected_shapes.assign([r])
	t.start_handle_transform("move_x")
	t.transform_initial_mouse = Vector2.ZERO
	t._on_motion(Vector2(60, 999))    # el 999 en Y debe IGNORARSE
	t._on_release(Vector2(60, 999))
	assert_vector(r.global_position).is_equal_approx(p0 + Vector2(60, 0), Vector2(0.5, 0.5))

	HistoryManager.undo(); await get_tree().process_frame
	assert_vector(r.global_position).is_equal_approx(p0, Vector2(0.5, 0.5))
	HistoryManager.clear()


func test_handle_eje_y_solo_vertical() -> void:
	var s := _scene(); await get_tree().process_frame
	var t := _tool(s)
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var r := _rect(ab, Vector2(200, 200))
	await get_tree().process_frame
	HistoryManager.clear()
	var p0 := r.global_position

	t.selected_shapes.assign([r])
	t.start_handle_transform("move_y")
	t.transform_initial_mouse = Vector2.ZERO
	t._on_motion(Vector2(999, 45))
	t._on_release(Vector2(999, 45))
	assert_vector(r.global_position).is_equal_approx(p0 + Vector2(0, 45), Vector2(0.5, 0.5))
	HistoryManager.clear()


## Figura ROTADA: escalar desde una esquina y luego deshacer → vuelve exacto.
func test_figura_rotada_escalar_undo() -> void:
	var s := _scene(); await get_tree().process_frame
	var t := _tool(s)
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var r := _rect(ab, Vector2(300, 300), Vector2(100, 60))
	r.rotation = deg_to_rad(30.0)
	r.doc_rotation = r.rotation
	await get_tree().process_frame
	HistoryManager.clear()
	var s0 := _state(r)

	_resize(t, [r], "br", Vector2(40, 25))
	assert_bool(HistoryManager.can_undo()).is_true()
	HistoryManager.undo(); await get_tree().process_frame
	_assert_state(_state(r), s0, "rotada+escala undo")
	# la rotación NO debe haberse perdido
	assert_float(r.global_rotation).is_equal_approx(deg_to_rad(30.0), 0.001)
	HistoryManager.clear()


## Cancelar (Escape) una transformación a medias deja la figura en su sitio.
func test_cancelar_transformacion_a_medias() -> void:
	var s := _scene(); await get_tree().process_frame
	var t := _tool(s)
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var r := _rect(ab, Vector2(200, 200), Vector2(80, 80))
	await get_tree().process_frame
	var s0 := _state(r)

	t.selected_shapes.assign([r])
	t._start_blender_mode(t.BlenderMode.SCALE)
	# simula un escalado a medias
	r.set("size", Vector2(300, 300))
	r.global_position += Vector2(50, 50)
	t._cancel_blender_transform()

	_assert_state(_state(r), s0, "cancelado")
