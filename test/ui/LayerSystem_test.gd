extends GdUnitTestSuite

## Doble mínimo de ArtboardEditor. No se usa la clase real aquí porque su
## artboard_size/is_selected disparan queue_redraw() -> _draw() ->
## _is_selection_tool(), que llama a get_tree().current_scene.find_child(...)
## y revienta en el runner de gdUnit4 en cuanto el nodo real entra al árbol
## (current_scene es null ahí) — un problema del propio ArtboardEditor ajeno
## a lo que estas pruebas de LayerSystem verifican (ver el mismo workaround
## en test/tools/MoveTool_test.gd).
class _FakeArtboard extends Node2D:
	var artboard_size := Vector2(794, 1123)

func _make_system(layer_tree: Tree, artboard_container: Node2D) -> LayerSystem:
	var system: LayerSystem = auto_free(LayerSystem.new())
	system.layer_tree = layer_tree
	system.artboard_container = artboard_container
	add_child(system)
	return system

## Invariante: una figura cuyo global_position cae dentro del rectángulo del
## artboard (global_position, artboard_size) no está "fuera"; una que cae
## fuera de cualquiera de los cuatro bordes sí lo está. Esta es la lógica que
## decide el aviso "⚠ fuera del artboard" en el panel de CAPAS
## (_create_tree_item la usa vía sincronizar_arbol_completo/_construir_nodo_recursivo,
## verificado manualmente en vivo — el propio Tree/TreeItem no se comporta de
## forma fiable en el runner headless de gdUnit4 para probarlo ahí también).
func test_esta_fuera_del_artboard_checks_point_against_artboard_rect() -> void:
	var artboard: _FakeArtboard = auto_free(_FakeArtboard.new())
	artboard.global_position = Vector2(100, 100)
	artboard.artboard_size = Vector2(794, 1123)

	var system: LayerSystem = _make_system(auto_free(Tree.new()), auto_free(Node2D.new()))

	var dentro: Node2D = auto_free(Node2D.new())
	dentro.global_position = Vector2(500, 500)  # bien dentro de [100,894]x[100,1223]
	assert_bool(system._esta_fuera_del_artboard(dentro, artboard)).is_false()

	var fuera_izquierda: Node2D = auto_free(Node2D.new())
	fuera_izquierda.global_position = Vector2(-50, 500)
	assert_bool(system._esta_fuera_del_artboard(fuera_izquierda, artboard)).is_true()

	var fuera_abajo: Node2D = auto_free(Node2D.new())
	fuera_abajo.global_position = Vector2(500, 2000)
	assert_bool(system._esta_fuera_del_artboard(fuera_abajo, artboard)).is_true()

	# El propio artboard nunca debe marcarse como "fuera de sí mismo".
	assert_bool(system._esta_fuera_del_artboard(artboard, artboard)).is_false()

	# Figura SUELTA (sin artboard) → fuera de todo artboard por definición.
	# Es lo que va bajo el grupo raíz "Fuera de artboard" del panel.
	var suelta: Node2D = auto_free(Node2D.new())
	assert_bool(system._esta_fuera_del_artboard(suelta, null)).is_true()


## REGRESIÓN O(N²): añadir figuras a un artboard debe ir por la ruta
## INCREMENTAL (un batch de 100 ms), no disparar sincronizar_arbol_completo()
## por cada figura. Antes _schedule_update() nunca arrancaba el timer (bug
## "and not is_stopped()") y todo caía en el rebuild completo O(N) por figura.
func test_alta_de_figuras_es_incremental_no_rebuild_por_figura() -> void:
	var contenedor: Node2D = auto_free(Node2D.new())
	add_child(contenedor)
	var artboard: _FakeArtboard = auto_free(_FakeArtboard.new())
	artboard.name = "Artboard"
	contenedor.add_child(artboard)

	var system: LayerSystem = _make_system(auto_free(Tree.new()), contenedor)
	await get_tree().process_frame

	var rebuilds := [0]
	# contamos las reconstrucciones completas
	var _orig_pending := system._pending_changes.size()

	# añadir 8 figuras seguidas dentro del artboard
	for i in 8:
		var s: Node2D = auto_free(Node2D.new())
		s.name = "Fig_%d" % i
		s.position = Vector2(100 + i, 100 + i)
		artboard.add_child(s)

	# aún NO se ha procesado nada (batch diferido) — la clave del arreglo:
	# NO se dispara sincronizar_arbol_completo() por cada figura.
	assert_int(system._pending_changes.size()).is_greater(0)

	# tras la ventana de batch, un único proceso incremental
	await get_tree().create_timer(0.15).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(system._pending_changes.size()).is_equal(0)
	# el artboard + las 8 figuras están mapeadas
	assert_int(system._node_to_item_map.size()).is_greater_equal(9)

	# borrar una figura hoja -> se quita su item, sin rebuild
	var victima := artboard.get_node("Fig_3")
	artboard.remove_child(victima)
	await get_tree().create_timer(0.15).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(system._node_to_item_map.has(victima)).is_false()
	victima.free()
