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
