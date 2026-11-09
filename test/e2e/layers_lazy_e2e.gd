# =============================================================================
# Panel de Capas con documentos grandes: grupos con muchas capas empiezan
# cerrados y sus filas se crean al abrirlos; contenedores con muchísimas
# capas van por tandas («Mostrar N más…»); los grupos pequeños, como siempre.
#   test/run_e2e.sh layers_lazy_e2e
# =============================================================================
extends SceneTree

var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func rows(item: TreeItem) -> int:
	var n := 0
	var c := item.get_first_child()
	while c:
		n += 1
		c = c.get_next()
	return n

func _run() -> void:
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("smart")
	await frames(10)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").api
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var ls := root.find_child("LayersSystem", true, false)
	# grupo grande (30), grupo pequeño (3) y contenedor enorme (450)
	var big: Array = []
	for i in 30:
		big.append(api.add_rect(Vector2(20 + i * 5, 20), Vector2(4, 4)))
	var g_big = api.group(big, "Grande")
	var small: Array = []
	for i in 3:
		small.append(api.add_ellipse(Vector2(20 + i * 10, 80), Vector2(6, 6)))
	var g_small = api.group(small, "Pequeño")
	var huge := Node2D.new()
	huge.name = "Enorme"
	huge.set_meta("shape_type", "group")
	ab.add_child(huge)
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	var one = api.add_rect(Vector2(300, 300), Vector2(4, 4))
	var data: Array = Ser.serialize_elements_list([one]) if Ser.has_method("serialize_elements_list") else []
	one.reparent(huge)
	for i in 449:
		var d = one.duplicate()
		d.position += Vector2(i % 30, i / 30) * 6.0
		huge.add_child(d)
	await frames(10)
	ls.sincronizar_arbol_completo()
	await frames(6)
	var map: Dictionary = ls._node_to_item_map
	var it_big: TreeItem = map.get(g_big)
	var it_small: TreeItem = map.get(g_small)
	var it_huge: TreeItem = map.get(huge)
	check("los tres grupos están en Capas", it_big != null and it_small != null and it_huge != null)
	if it_big == null or it_small == null or it_huge == null:
		quit(1)
		return
	check("grupo grande: cerrado y sin crear sus 30 filas", it_big.collapsed and rows(it_big) == 1 and ls._es_perezoso(it_big))
	check("grupo pequeño: abierto con sus 3 filas (como siempre)", not it_small.collapsed and rows(it_small) == 3)
	it_big.collapsed = false
	await frames(4)
	check("al abrir el grupo grande aparecen sus 30 filas", rows(it_big) == 30 and not ls._es_perezoso(it_big), str(rows(it_big)))
	it_huge.collapsed = false
	await frames(4)
	var last := it_huge.get_child(rows(it_huge) - 1)
	check("contenedor de 450: 200 filas y «Mostrar 250 capas más…»", rows(it_huge) == 201 and str(last.get_metadata(0)) == "more", "%d filas" % rows(it_huge))
	ls._mostrar_mas(last)
	await frames(4)
	check("«Mostrar más» añade la siguiente tanda de 200 (400 + «Mostrar 50 más…»)", rows(it_huge) == 401, str(rows(it_huge)))
	ls._mostrar_mas(it_huge.get_child(rows(it_huge) - 1))
	await frames(4)
	check("y la última tanda completa las 450", rows(it_huge) == 450, str(rows(it_huge)))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
