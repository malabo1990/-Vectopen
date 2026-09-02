extends GdUnitTestSuite

## ARQUITECTURA MULTI-ARTBOARD. Regresión del bug "solo el primer artboard
## funciona": las figuras nuevas caían siempre en ArtboardsContainer.get_child(0)
## en vez del artboard activo / el que contiene el punto de creación.

const CANVAS := "res://scenes/canvas/canvas.tscn"

func _scene() -> Node2D:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	return s

func _mgr(s: Node) -> ArtboardManager:
	return s.get_node("manager_script") as ArtboardManager

func _nuevo_artboard(container: Node2D, pos: Vector2, size: Vector2) -> ArtboardEditor:
	var ab: ArtboardEditor = ArtboardEditor.new()
	ab.artboard_size = size
	container.add_child(ab)
	ab.global_position = pos
	auto_free(ab)
	return ab


## REGRESIÓN: la herramienta activa DEBE estar en el árbol de escena. Si no,
## get_tree() es null dentro de ella y ArtboardManager.find(get_tree()) devuelve
## null → toda la resolución multi-artboard se cae al primer artboard (por eso
## "no se podía seleccionar ni arrastrar el 2º artboard" en la app real).
func test_la_herramienta_activa_esta_en_el_arbol_y_ve_el_manager() -> void:
	var s := _scene()  # el nodo raíz de canvas.tscn ES el canvas
	await get_tree().process_frame
	assert_bool("current_tool" in s).is_true()
	var tool = s.current_tool
	assert_object(tool).is_not_null()
	assert_bool(tool is Node).is_true()
	assert_bool(tool.is_inside_tree()).is_true()          # <- el fix
	assert_object(tool.get_tree()).is_not_null()
	# y desde la herramienta se localiza el ArtboardManager
	assert_object(ArtboardManager.find(tool.get_tree())).is_not_null()


func test_manager_registra_todos_los_artboards_y_tiene_activo() -> void:
	var s := _scene()
	await get_tree().process_frame
	var mgr := _mgr(s)
	assert_object(mgr).is_not_null()
	var container: Node2D = s.get_node("ArtboardsContainer")

	# el artboard del .tscn ya está registrado y es el activo
	assert_int(mgr.all_artboards().size()).is_equal(1)
	assert_object(mgr.get_active_artboard()).is_not_null()

	var ab2 := _nuevo_artboard(container, Vector2(2000, 0), Vector2(400, 500))
	var ab3 := _nuevo_artboard(container, Vector2(4000, 0), Vector2(400, 500))
	await get_tree().process_frame
	assert_int(mgr.all_artboards().size()).is_equal(3)  # alta por child_entered_tree

	mgr.set_active_artboard(ab2)
	assert_object(mgr.get_active_artboard()).is_same(ab2)
	assert_bool(ab2.is_selected).is_true()
	assert_bool(ab3.is_selected).is_false()

	# al borrar el activo, se recalcula a otro válido
	ab2.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(mgr.all_artboards().size()).is_equal(2)
	assert_object(mgr.get_active_artboard()).is_not_null()


func test_artboard_at_point_y_fuera() -> void:
	var s := _scene()
	await get_tree().process_frame
	var mgr := _mgr(s)
	var container: Node2D = s.get_node("ArtboardsContainer")
	var ab1: ArtboardEditor = mgr.all_artboards()[0]
	ab1.global_position = Vector2(0, 0)
	ab1.artboard_size = Vector2(500, 500)
	var ab2 := _nuevo_artboard(container, Vector2(1000, 0), Vector2(500, 500))
	await get_tree().process_frame

	assert_object(mgr.artboard_at_point(Vector2(250, 250))).is_same(ab1)
	assert_object(mgr.artboard_at_point(Vector2(1250, 250))).is_same(ab2)
	# entre los dos, en tierra de nadie -> null (elemento "suelto")
	assert_object(mgr.artboard_at_point(Vector2(700, 250))).is_null()
	assert_object(mgr.artboard_at_point(Vector2(-100, -100))).is_null()


func test_figura_nueva_pertenece_al_artboard_correcto_no_al_primero() -> void:
	var s := _scene()
	await get_tree().process_frame
	var mgr := _mgr(s)
	var container: Node2D = s.get_node("ArtboardsContainer")
	var ab1: ArtboardEditor = mgr.all_artboards()[0]
	ab1.global_position = Vector2(0, 0)
	ab1.artboard_size = Vector2(500, 500)
	var ab2 := _nuevo_artboard(container, Vector2(1000, 0), Vector2(500, 500))
	await get_tree().process_frame

	# Simula lo que hacen las herramientas de figura: destino = artboard bajo
	# el punto de creación.
	var punto := Vector2(1200, 200)  # dentro de ab2
	var destino := mgr.artboard_at_point(punto)
	assert_object(destino).is_same(ab2)

	var figura := VectorRectangle.new()
	figura.name = "RectEnAB2"
	destino.add_child(figura)
	figura.global_position = punto

	# PERTENENCIA: la figura cuelga de ab2, no de ab1
	assert_object(mgr.owning_artboard(figura)).is_same(ab2)
	assert_object(figura.get_parent()).is_same(ab2)
	assert_bool(ab1.get_children().has(figura)).is_false()
	assert_bool(mgr.is_element_outside(figura)).is_false()


func test_elemento_suelto_se_reconoce_como_fuera() -> void:
	var s := _scene()
	await get_tree().process_frame
	var mgr := _mgr(s)
	var container: Node2D = s.get_node("ArtboardsContainer")

	# figura hija DIRECTA del contenedor (fuera de todo artboard)
	var suelta := VectorRectangle.new()
	suelta.name = "Suelta"
	container.add_child(suelta)
	suelta.global_position = Vector2(5000, 5000)

	assert_object(mgr.owning_artboard(suelta)).is_null()
	assert_bool(mgr.is_element_outside(suelta)).is_true()


func test_figura_arrastrada_fuera_de_su_artboard() -> void:
	var s := _scene()
	await get_tree().process_frame
	var mgr := _mgr(s)
	var ab1: ArtboardEditor = mgr.all_artboards()[0]
	ab1.global_position = Vector2(0, 0)
	ab1.artboard_size = Vector2(500, 500)

	var fig := VectorRectangle.new()
	ab1.add_child(fig)
	fig.global_position = Vector2(250, 250)  # dentro
	assert_bool(mgr.is_element_outside(fig)).is_false()

	fig.global_position = Vector2(900, 250)  # arrastrada fuera de ab1
	assert_bool(mgr.is_element_outside(fig)).is_true()
	# sigue PERTENECIENDO a ab1 (jerarquía), aunque esté geométricamente fuera
	assert_object(mgr.owning_artboard(fig)).is_same(ab1)


## Bug reportado: arrastrar una figura ENCIMA de otro artboard debe hacerla
## HIJA de ese artboard (nuevo padre), como en un editor profesional.
func _move_tool_en(s: Node2D) -> MoveTool:
	var t := MoveTool.new()
	t.canvas = s
	s.add_child(t)
	auto_free(t)
	return t

func test_arrastrar_figura_a_otro_artboard_la_reparenta() -> void:
	var s := _scene()
	await get_tree().process_frame
	var mgr := _mgr(s)
	var container: Node2D = s.get_node("ArtboardsContainer")
	var ab1: ArtboardEditor = mgr.all_artboards()[0]
	ab1.global_position = Vector2.ZERO
	ab1.artboard_size = Vector2(500, 500)
	var ab2 := _nuevo_artboard(container, Vector2(1000, 0), Vector2(500, 500))
	await get_tree().process_frame

	var fig := VectorRectangle.new()
	fig.name = "Viajera"
	ab1.add_child(fig)
	fig.global_position = Vector2(250, 250)
	await get_tree().process_frame
	HistoryManager.clear()

	var t := _move_tool_en(s)
	t.selected_shapes.assign([fig])
	t.transform_initial_states = {fig: {"gpos": Vector2(250, 250), "grot": 0.0}}
	t.is_dragging_shape = true

	fig.global_position = Vector2(1250, 250)  # soltada dentro de ab2
	t._on_release(Vector2(1250, 250))
	await get_tree().process_frame

	assert_object(fig.get_parent()).is_same(ab2)
	assert_object(mgr.owning_artboard(fig)).is_same(ab2)
	assert_vector(fig.global_position).is_equal_approx(Vector2(1250, 250), Vector2(0.5, 0.5))
	assert_bool(mgr.is_element_outside(fig)).is_false()
	assert_bool(HistoryManager.can_undo()).is_true()

	HistoryManager.undo()
	await get_tree().process_frame
	assert_object(fig.get_parent()).is_same(ab1)
	assert_vector(fig.global_position).is_equal_approx(Vector2(250, 250), Vector2(0.5, 0.5))
	HistoryManager.clear()


## REPARENT entre artboards: undo Y redo deben dejar la figura en el mismo sitio
## (padre + posición global + índice / z-order). Antes redo la re-adjuntaba SIEMPRE
## al final del artboard destino (asimetría con undo, que sí restauraba el índice).
func test_reparent_entre_artboards_undo_redo_conserva_indice_y_global() -> void:
	var s := _scene()
	await get_tree().process_frame
	var mgr := _mgr(s)
	var container: Node2D = s.get_node("ArtboardsContainer")
	var ab1: ArtboardEditor = mgr.all_artboards()[0]
	ab1.global_position = Vector2.ZERO
	ab1.artboard_size = Vector2(500, 500)
	var ab2 := _nuevo_artboard(container, Vector2(1000, 0), Vector2(500, 500))
	await get_tree().process_frame

	# ab2 ya tiene 2 figuras fijas (hermanas) → probamos el índice de verdad.
	var fijo_a := VectorRectangle.new(); auto_free(fijo_a); ab2.add_child(fijo_a); fijo_a.global_position = Vector2(1100, 100)
	var fijo_b := VectorRectangle.new(); auto_free(fijo_b); ab2.add_child(fijo_b); fijo_b.global_position = Vector2(1300, 300)

	var fig := VectorRectangle.new(); auto_free(fig); fig.name = "Viajera"
	ab1.add_child(fig)
	fig.global_position = Vector2(250, 250)
	await get_tree().process_frame
	HistoryManager.clear()
	var idx_ab1: int = fig.get_index()

	var t := _move_tool_en(s)
	t.selected_shapes.assign([fig])
	t.transform_initial_states = {fig: {"gpos": Vector2(250, 250), "grot": 0.0}}
	t.is_dragging_shape = true
	fig.global_position = Vector2(1250, 250)     # soltada dentro de ab2
	t._on_release(Vector2(1250, 250))
	await get_tree().process_frame

	assert_object(fig.get_parent()).is_same(ab2)
	var idx_ab2: int = fig.get_index()
	var g_ab2 := fig.global_position

	HistoryManager.undo(); await get_tree().process_frame
	assert_object(fig.get_parent()).is_same(ab1)
	assert_int(fig.get_index()).is_equal(idx_ab1)
	assert_vector(fig.global_position).is_equal_approx(Vector2(250, 250), Vector2(0.5, 0.5))

	HistoryManager.redo(); await get_tree().process_frame
	assert_object(fig.get_parent()).is_same(ab2)
	assert_int(fig.get_index()).is_equal(idx_ab2)          # <- el fix: z-order idéntico
	assert_vector(fig.global_position).is_equal_approx(g_ab2, Vector2(0.5, 0.5))
	HistoryManager.clear()


func test_arrastrar_figura_fuera_de_todo_la_vuelve_suelta() -> void:
	var s := _scene()
	await get_tree().process_frame
	var mgr := _mgr(s)
	var container: Node2D = s.get_node("ArtboardsContainer")
	var ab1: ArtboardEditor = mgr.all_artboards()[0]
	ab1.global_position = Vector2.ZERO
	ab1.artboard_size = Vector2(500, 500)

	var fig := VectorRectangle.new()
	ab1.add_child(fig)
	fig.global_position = Vector2(100, 100)
	await get_tree().process_frame
	HistoryManager.clear()

	var t := _move_tool_en(s)
	t.selected_shapes.assign([fig])
	t.transform_initial_states = {fig: {"gpos": Vector2(100, 100)}}
	t.is_dragging_shape = true
	fig.global_position = Vector2(3000, 3000)  # fuera de todo artboard
	t._on_release(Vector2(3000, 3000))
	await get_tree().process_frame

	assert_object(fig.get_parent()).is_same(container)  # hija directa del contenedor = suelta
	assert_object(mgr.owning_artboard(fig)).is_null()
	assert_bool(mgr.is_element_outside(fig)).is_true()
	HistoryManager.clear()


## El botón "+A" del panel de capas no tenía señal → no hacía nada. Ahora crea
## un artboard nuevo (a la derecha del último), lo activa, y es undo-able.
func test_boton_mas_A_crea_artboard_nuevo() -> void:
	var s := _scene()
	await get_tree().process_frame
	var mgr := _mgr(s)
	var container: Node2D = s.get_node("ArtboardsContainer")
	var ab1: ArtboardEditor = mgr.all_artboards()[0]
	ab1.global_position = Vector2(100, 100)
	ab1.artboard_size = Vector2(400, 500)
	HistoryManager.clear()

	var ls := LayerSystem.new()
	ls.artboard_container = container
	ls.layer_tree = auto_free(Tree.new())
	s.add_child(ls)
	auto_free(ls)
	await get_tree().process_frame

	var antes := mgr.all_artboards().size()
	ls._on_btn_add_artboard()
	await get_tree().process_frame

	assert_int(mgr.all_artboards().size()).is_equal(antes + 1)
	var nuevo: ArtboardEditor = mgr.get_active_artboard()
	assert_object(nuevo).is_not_same(ab1)
	# a la derecha de ab1, con separación
	assert_float(nuevo.global_position.x).is_greater(ab1.global_position.x + ab1.artboard_size.x)
	assert_vector(nuevo.artboard_size).is_equal(ab1.artboard_size)

	HistoryManager.undo()
	await get_tree().process_frame
	assert_int(mgr.all_artboards().size()).is_equal(antes)
	HistoryManager.clear()
