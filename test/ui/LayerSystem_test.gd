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
