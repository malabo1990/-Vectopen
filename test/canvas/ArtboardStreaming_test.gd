extends GdUnitTestSuite

## STREAMING de artboards: dormir/despertar preserva el contenido y no crea
## trabajo para las páginas lejanas.

const CANVAS := "res://scenes/canvas/canvas.tscn"
const CS = preload("res://scripts/canvas/canvas_serializer.gd")

func _scene() -> Node2D:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	auto_free(s)
	return s

func _poblar(ab: ArtboardEditor, n: int) -> void:
	for i in n:
		var c := VectorCircle.new()
		c.name = "C%d" % i
		c.size = Vector2(20, 20)
		c.fill_color = Color(float(i) / n, 0.4, 0.8, 1)
		ab.add_child(c)
		c.position = Vector2(30 + i * 5, 40)


func test_sleep_wake_preserva_contenido() -> void:
	var s := _scene()
	await get_tree().process_frame
	var mgr := s.get_node("manager_script") as ArtboardManager
	var ab: ArtboardEditor = mgr.get_active_artboard()
	_poblar(ab, 12)
	await get_tree().process_frame

	var antes := ab.get_children().filter(func(x): return x is VectorCircle).size()
	assert_int(antes).is_equal(12)

	ab.sleep()
	assert_bool(ab.is_dormant).is_true()
	assert_int(ab.get_children().filter(func(x): return x is VectorCircle).size()).is_equal(0)
	assert_int(ab.dormant_content().size()).is_equal(12)
	assert_bool(ab.has_node("ArtboardTitle")).is_true()  # el título NO se libera

	ab.wake()
	await get_tree().process_frame
	assert_bool(ab.is_dormant).is_false()
	var circs := ab.get_children().filter(func(x): return x is VectorCircle)
	assert_int(circs.size()).is_equal(12)
	# propiedades intactas (spot-check)
	var c5 = ab.get_node_or_null("C5")
	assert_object(c5).is_not_null()
	assert_vector(c5.size).is_equal(Vector2(20, 20))
	assert_vector(c5.position).is_equal(Vector2(55, 40))


func test_no_duerme_el_activo_ni_con_figura_seleccionada() -> void:
	var s := _scene()
	await get_tree().process_frame
	var mgr := s.get_node("manager_script") as ArtboardManager
	var ab: ArtboardEditor = mgr.get_active_artboard()
	_poblar(ab, 3)
	mgr.set_active_artboard(ab)
	await get_tree().process_frame

	ab.sleep()
	assert_bool(ab.is_dormant).is_false()  # es el activo → no duerme

	# ahora no-activo pero con una figura seleccionada
	var ab2 := ArtboardEditor.new()
	ab2.artboard_size = Vector2(400, 400)
	s.get_node("ArtboardsContainer").add_child(ab2)
	auto_free(ab2)
	await get_tree().process_frame
	mgr.set_active_artboard(ab2)   # ab ya no es activo

	ab.get_node("C1").set("is_selected", true)
	ab.sleep()
	assert_bool(ab.is_dormant).is_false()  # figura seleccionada → no duerme

	ab.get_node("C1").set("is_selected", false)
	ab.sleep()
	assert_bool(ab.is_dormant).is_true()


func test_carga_diferida_no_instancia_las_paginas() -> void:
	var s := _scene()
	await get_tree().process_frame
	var container: Node2D = s.get_node("ArtboardsContainer")

	# data de 3 páginas × 50 figuras
	var data := {"v": 1, "artboards": [], "loose": []}
	for p in 3:
		var elems := []
		for i in 50:
			elems.append({"kind": "circle", "name": "C%d" % i, "pos": [i, i],
				"rot": 0.0, "scale": [1, 1], "visible": true, "size": [10, 10],
				"fill": [1, 0, 0, 1], "stroke": [0, 0, 0, 1], "stroke_w": 1.0})
		data["artboards"].append({"name": "Pag%d" % p, "pos": [p * 1000, 0],
			"size": [400, 500], "elements": elems})

	# materialize_all = false → dormidas
	CS.rebuild_container(container, data, false)
	# el wake de la 1ª es amortizado (50 > WAKE_BUDGET) → varios frames
	for f in 6:
		await get_tree().process_frame

	var artboards := container.get_children().filter(func(x): return x is ArtboardEditor)
	assert_int(artboards.size()).is_equal(3)
	# la PRIMERA se materializa (suele estar a la vista); el resto, dormidas
	assert_bool(artboards[0].is_dormant).is_false()
	assert_int(artboards[0].get_children().filter(func(x): return x is VectorCircle).size()).is_equal(50)
	var dormidas_figuras := 0
	for i in [1, 2]:
		assert_bool(artboards[i].is_dormant).is_true()
		dormidas_figuras += artboards[i].get_children().filter(func(x): return x is VectorCircle).size()
	assert_int(dormidas_figuras).is_equal(0)  # las dormidas no instancian NADA

	# despertar la segunda reconstruye sus 50 (amortizado)
	artboards[1].wake()
	for f in 6:
		await get_tree().process_frame
	assert_int(artboards[1].get_children().filter(func(x): return x is VectorCircle).size()).is_equal(50)


## UNDO SEGURO: una página editada con historial de undo vivo NO debe dormir
## (sus nodos están referenciados por callables de HistoryManager).
func test_no_duerme_pagina_editada_con_undo_vivo() -> void:
	var s := _scene()
	await get_tree().process_frame
	var mgr := s.get_node("manager_script") as ArtboardManager
	var ab: ArtboardEditor = mgr.get_active_artboard()

	HistoryManager.clear()
	assert_bool(ab.is_edited()).is_false()

	# editar la página: crear una figura (marca is_edited por child_entered_tree)
	var c := VectorCircle.new()
	c.name = "Nueva"
	ab.add_child(c)
	await get_tree().process_frame
	assert_bool(ab.is_edited()).is_true()

	# sin historial de undo → puede dormir aunque esté editada
	# (creamos un 2º artboard para que ab no sea el activo)
	var ab2 := ArtboardEditor.new()
	ab2.artboard_size = Vector2(300, 300)
	s.get_node("ArtboardsContainer").add_child(ab2)
	auto_free(ab2)
	await get_tree().process_frame
	mgr.set_active_artboard(ab2)
	assert_bool(HistoryManager.can_undo()).is_false()
	ab.sleep()
	assert_bool(ab.is_dormant).is_true()  # sin undo, duerme
	ab.wake(true)
	await get_tree().process_frame

	# ahora CON historial de undo → NO debe dormir
	HistoryManager.register_action("test")
	HistoryManager.add_do(func(): pass)
	HistoryManager.add_undo(func(): pass)
	HistoryManager.commit()
	assert_bool(HistoryManager.can_undo()).is_true()
	ab.sleep()
	assert_bool(ab.is_dormant).is_false()  # protegida por el undo vivo

	HistoryManager.clear()


## INVARIANTE CRÍTICA: guardar DESPUÉS de carga perezosa no puede perder las
## páginas que nunca se materializaron.
func test_guardar_tras_carga_perezosa_no_pierde_paginas_dormidas() -> void:
	var s := _scene()
	await get_tree().process_frame
	var container: Node2D = s.get_node("ArtboardsContainer")
	var mgr := s.get_node("manager_script") as ArtboardManager

	# 1) construir un libro de 4 páginas × 20 figuras y guardarlo
	CS.rebuild_container(container, {"v": 1, "loose": [], "artboards": []})  # limpiar
	await get_tree().process_frame
	for p in 4:
		var ab := ArtboardEditor.new()
		ab.name = "Pag%d" % p
		ab.artboard_size = Vector2(400, 500)
		container.add_child(ab)
		ab.position = Vector2(p * 700, 0)
		for i in 20:
			var c := VectorCircle.new()
			c.name = "P%d_C%d" % [p, i]
			c.size = Vector2(15, 15)
			ab.add_child(c)
			c.position = Vector2(20 + i * 3, 30)
	await get_tree().process_frame

	var path_a := "user://__lazy_integridad_a.vtc"
	DataRepository.save_project(path_a)

	# 2) cargar diferido (.vtc ZIP) → páginas dormidas con fuente perezosa
	DataRepository.load_project(path_a)
	for f in 6:
		await get_tree().process_frame
	var dormidas := 0
	for ch in container.get_children():
		if ch is ArtboardEditor and ch.is_dormant:
			dormidas += 1
	assert_int(dormidas).is_greater(0)   # confirmamos que SÍ hay dormidas

	# 3) guardar OTRA VEZ (con páginas dormidas / lazy) → NO puede perder nada
	var path_b := "user://__lazy_integridad_b.vtc"
	DataRepository.save_project(path_b)

	# leer todos los chunks del .vtc b y contar las figuras
	var manifest := CS.read_vtc_manifest(path_b)
	var total := 0
	for h in manifest.get("artboards", []):
		total += CS.read_vtc_chunk(path_b, h).size()
	assert_int(total).is_equal(4 * 20)   # las 80 figuras SIGUEN en el archivo

	CS.close_reader_cache()   # soltar el handle antes de borrar
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path_a))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path_b))
