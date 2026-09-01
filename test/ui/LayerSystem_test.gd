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


## Máscara de recorte sobre una FIGURA con geometría propia: pone
## `clip_children` directamente en la figura (recorta a su forma), con undo.
func test_boton_de_mascara_en_figura_alterna_clip_children_con_undo() -> void:
	var tree: Tree = auto_free(Tree.new())
	tree.columns = 3
	var system: LayerSystem = _make_system(tree, auto_free(Node2D.new()))
	var raiz := tree.create_item()
	var item := tree.create_item(raiz)

	var fig: VectorRectangle = auto_free(VectorRectangle.new())
	item.set_metadata(1, fig)

	assert_int(int(fig.clip_children)).is_equal(0)
	HistoryManager.clear()

	system._on_tree_button_clicked(item, 1, LayerSystem._BTN_CLIP, MOUSE_BUTTON_LEFT)
	assert_int(int(fig.clip_children)).is_equal(2)   # CLIP_CHILDREN_AND_DRAW
	assert_bool(HistoryManager.can_undo()).is_true()

	HistoryManager.undo(); await get_tree().process_frame
	assert_int(int(fig.clip_children)).is_equal(0)
	HistoryManager.redo(); await get_tree().process_frame
	assert_int(int(fig.clip_children)).is_equal(2)
	HistoryManager.clear()


## Máscara STENCIL sobre un GRUPO: la figura de arriba recorta al resto — el
## contenido se mueve DENTRO de ella y ELLA lleva `clip_children`. Con undo.
func test_mascara_stencil_de_grupo_mueve_contenido_bajo_la_figura_de_arriba() -> void:
	_sm().clear()
	var tree: LayerTree = auto_free(LayerTree.new()); add_child(tree)
	var cont: Node2D = auto_free(Node2D.new()); add_child(cont)
	var ab: _FakeArtboard = auto_free(_FakeArtboard.new()); ab.name = "Artboard"
	cont.add_child(ab)
	var system: LayerSystem = _make_system(tree, cont)

	var grupo: Node2D = auto_free(Node2D.new()); grupo.name = "Grupo"
	grupo.set_meta("shape_type", "group"); ab.add_child(grupo)
	var fondo: VectorCircle = auto_free(VectorCircle.new()); fondo.name = "Fondo"
	grupo.add_child(fondo); fondo.global_position = Vector2(100, 100)
	var mascara: VectorRectangle = auto_free(VectorRectangle.new()); mascara.name = "Mascara"
	grupo.add_child(mascara); mascara.global_position = Vector2(120, 120)  # último = "arriba"
	system.sincronizar_arbol_completo()
	await get_tree().process_frame
	HistoryManager.clear()

	var it := func() -> TreeItem: return system._node_to_item_map.get(grupo)

	system._on_tree_button_clicked(it.call(), 1, LayerSystem._BTN_CLIP, MOUSE_BUTTON_LEFT)
	await get_tree().process_frame
	assert_object(fondo.get_parent()).is_same(mascara)          # el contenido va DENTRO
	assert_int(int(mascara.clip_children)).is_equal(1)          # CLIP_CHILDREN_ONLY
	assert_bool(grupo.get_meta("clip_mask", false)).is_true()
	assert_str(String(grupo.get_meta("clip_mask_target", ""))).is_equal("Mascara")

	HistoryManager.undo(); await get_tree().process_frame
	assert_object(fondo.get_parent()).is_same(grupo)            # vuelve al grupo
	assert_int(int(mascara.clip_children)).is_equal(0)
	assert_bool(grupo.has_meta("clip_mask")).is_false()

	# quitar la máscara con un 2º clic (tras rehacer)
	HistoryManager.redo(); await get_tree().process_frame
	HistoryManager.clear()
	system._on_tree_button_clicked(it.call(), 1, LayerSystem._BTN_CLIP, MOUSE_BUTTON_LEFT)
	await get_tree().process_frame
	assert_object(fondo.get_parent()).is_same(grupo)
	assert_int(int(mascara.clip_children)).is_equal(0)
	HistoryManager.clear()
	_sm().clear()


## TODA fila (hoja o grupo) lleva los MISMOS 3 botones en el MISMO orden:
## ojo · candado · máscara. Así las columnas quedan alineadas.
func test_todas_las_filas_tienen_los_tres_botones() -> void:
	_sm().clear()
	var tree: LayerTree = auto_free(LayerTree.new()); add_child(tree)
	var cont: Node2D = auto_free(Node2D.new()); add_child(cont)
	var ab: _FakeArtboard = auto_free(_FakeArtboard.new()); ab.name = "Artboard"
	cont.add_child(ab)
	var system: LayerSystem = _make_system(tree, cont)

	var hoja: VectorRectangle = auto_free(VectorRectangle.new()); hoja.name = "Hoja"
	ab.add_child(hoja); hoja.global_position = Vector2(100, 100)
	var padre: VectorRectangle = auto_free(VectorRectangle.new()); padre.name = "Padre"
	ab.add_child(padre); padre.global_position = Vector2(300, 300)
	var hijo: VectorCircle = auto_free(VectorCircle.new()); hijo.name = "Hijo"
	padre.add_child(hijo); hijo.global_position = Vector2(300, 300)
	system.sincronizar_arbol_completo()
	await get_tree().process_frame

	for n in [hoja, padre, hijo]:
		var it: TreeItem = system._node_to_item_map[n]
		assert_int(it.get_button_count(2)).override_failure_message(
			"fila %s" % n.name).is_equal(3)
		assert_int(it.get_button_id(2, 0)).is_equal(LayerSystem._BTN_VIS)
		assert_int(it.get_button_id(2, 1)).is_equal(LayerSystem._BTN_LOCK)
		assert_int(it.get_button_id(2, 2)).is_equal(LayerSystem._BTN_CLIP)
	_sm().clear()


## Los botones de ojo y candado de la fila alternan el estado real con undo.
func test_botones_ojo_y_candado_con_undo() -> void:
	var tree: Tree = auto_free(Tree.new())
	tree.columns = 3
	var system: LayerSystem = _make_system(tree, auto_free(Node2D.new()))
	var raiz := tree.create_item()
	var item := tree.create_item(raiz)
	var fig: Node2D = auto_free(Node2D.new())
	item.set_metadata(1, fig)
	item.set_metadata(0, "shape")
	HistoryManager.clear()

	system._on_tree_button_clicked(item, 0, LayerSystem._BTN_VIS, MOUSE_BUTTON_LEFT)
	assert_bool(fig.visible).is_false()
	HistoryManager.undo(); await get_tree().process_frame
	assert_bool(fig.visible).is_true()

	system._on_tree_button_clicked(item, 2, LayerSystem._BTN_LOCK, MOUSE_BUTTON_LEFT)
	assert_bool(bool(fig.get_meta("locked", false))).is_true()
	HistoryManager.undo(); await get_tree().process_frame
	assert_bool(bool(fig.get_meta("locked", false))).is_false()
	HistoryManager.clear()


## El panel de capas aplica el tema (tokens de diseño), no el blanco fijo del .tscn.
func test_panel_usa_los_tokens_del_tema() -> void:
	var panel_scene = auto_free(load("res://scenes/ui/layers_system.tscn").instantiate())
	add_child(panel_scene)
	await get_tree().process_frame

	var panel := panel_scene.get_node_or_null("Panel") as Panel
	assert_object(panel).is_not_null()
	var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_object(sb).is_not_null()
	# el token panel_bg NO es blanco puro (era Color(1,1,1,1) fijo en el .tscn)
	assert_bool(sb.bg_color.is_equal_approx(Color(1, 1, 1, 1))).is_false()


## Una figura HOJA con nodos internos de render (Contorno_Stroke, Render_Visual)
## NO debe generar sub-ítems → sin flecha ">" en el panel.
func test_figura_hoja_no_tiene_hijos_en_el_arbol() -> void:
	var tree: Tree = auto_free(Tree.new())
	tree.columns = 3
	var artboard: _FakeArtboard = auto_free(_FakeArtboard.new())
	artboard.global_position = Vector2(0, 0)
	artboard.artboard_size = Vector2(800, 600)
	var cont: Node2D = auto_free(Node2D.new())
	add_child(cont)
	cont.add_child(artboard)

	var rect := VectorRectangle.new()
	rect.name = "R"
	rect.size = Vector2(40, 40)
	artboard.add_child(rect)
	rect.global_position = Vector2(100, 100)
	# hijos internos de render (NO son capas)
	var stroke := Line2D.new(); stroke.name = "Contorno_Stroke"; rect.add_child(stroke)
	var rv := Node2D.new(); rv.name = "Render_Visual"; rect.add_child(rv)
	await get_tree().process_frame

	var system: LayerSystem = _make_system(tree, cont)
	system.sincronizar_arbol_completo()

	var item: TreeItem = system._node_to_item_map.get(rect)
	assert_object(item).is_not_null()
	assert_int(item.get_child_count()).is_equal(0)   # sin sub-ítems → sin flecha
	assert_str(str(item.get_metadata(0))).is_equal("shape")   # no "group"


# ── Fase 2/3: selección jerárquica + agrupar/desagrupar/orden Z ─────────────

func _sm() -> Node:
	return get_node_or_null("/root/SelectionManager")

func test_menu_seleccionar_descendientes_via_selectionmanager() -> void:
	_sm().clear()
	var tree: Tree = auto_free(Tree.new())
	tree.columns = 3
	var system: LayerSystem = _make_system(tree, auto_free(Node2D.new()))

	var grupo: Node2D = auto_free(Node2D.new())
	add_child(grupo)
	grupo.set_meta("shape_type", "group")
	var c1: Node2D = auto_free(Node2D.new()); grupo.add_child(c1)
	var c2: Node2D = auto_free(Node2D.new()); grupo.add_child(c2)

	var raiz := tree.create_item()
	var item := tree.create_item(raiz)
	item.set_metadata(1, grupo)
	item.set_metadata(0, "group")
	system._ctx_item = item

	system._on_ctx_menu_id(system._Ctx.SEL_DESC)
	assert_array(_sm().get_selected()).contains_exactly([c1, c2])
	_sm().clear()


func test_agrupar_seleccion_con_undo() -> void:
	_sm().clear()
	var tree: Tree = auto_free(Tree.new())
	var system: LayerSystem = _make_system(tree, auto_free(Node2D.new()))

	var padre: Node2D = auto_free(Node2D.new()); add_child(padre)
	var a: Node2D = auto_free(Node2D.new()); a.name = "A"; padre.add_child(a)
	var b: Node2D = auto_free(Node2D.new()); b.name = "B"; padre.add_child(b)
	a.global_position = Vector2(10, 20)
	b.global_position = Vector2(30, 40)
	_sm().select_many([a, b])
	HistoryManager.clear()

	system._agrupar_seleccion()
	assert_object(a.get_parent()).is_not_same(padre)
	assert_str(str(a.get_parent().name)).starts_with("Grupo")
	assert_object(a.get_parent()).is_same(b.get_parent())
	assert_vector(a.global_position).is_equal_approx(Vector2(10, 20), Vector2(0.01, 0.01))

	HistoryManager.undo(); await get_tree().process_frame
	assert_object(a.get_parent()).is_same(padre)
	assert_object(b.get_parent()).is_same(padre)
	HistoryManager.clear()
	_sm().clear()


func test_orden_z_traer_al_frente_con_undo() -> void:
	_sm().clear()
	var tree: Tree = auto_free(Tree.new())
	var system: LayerSystem = _make_system(tree, auto_free(Node2D.new()))

	var padre: Node2D = auto_free(Node2D.new()); add_child(padre)
	var a: Node2D = auto_free(Node2D.new()); padre.add_child(a)
	var b: Node2D = auto_free(Node2D.new()); padre.add_child(b)
	var c: Node2D = auto_free(Node2D.new()); padre.add_child(c)
	_sm().select(a)   # a está en índice 0
	HistoryManager.clear()

	system._cambiar_orden_z(system._Ctx.AL_FRENTE)
	assert_int(a.get_index()).is_equal(2)   # al frente = último

	HistoryManager.undo(); await get_tree().process_frame
	assert_int(a.get_index()).is_equal(0)
	HistoryManager.clear()
	_sm().clear()


func test_ctrl_g_global_agrupa_la_seleccion() -> void:
	_sm().clear()
	var tree: Tree = auto_free(Tree.new())
	var system: LayerSystem = _make_system(tree, auto_free(Node2D.new()))
	var padre: Node2D = auto_free(Node2D.new()); add_child(padre)
	var a: VectorRectangle = auto_free(VectorRectangle.new()); padre.add_child(a)
	var b: VectorRectangle = auto_free(VectorRectangle.new()); padre.add_child(b)
	_sm().select_many([a, b])
	HistoryManager.clear()

	var ev := InputEventKey.new()
	ev.keycode = KEY_G
	ev.ctrl_pressed = true
	ev.pressed = true
	system._unhandled_key_input(ev)

	assert_str(str(a.get_parent().name)).starts_with("Grupo")
	assert_object(a.get_parent()).is_same(b.get_parent())
	HistoryManager.clear()
	_sm().clear()


## El buscador de capas (LineEdit SearchLayers → `_on_buscar_capas`) filtra el
## árbol: las filas que no casan quedan `visible == false`; al vaciar el texto,
## todo vuelve.
func test_buscar_capas_filtra_el_arbol() -> void:
	_sm().clear()
	var tree: LayerTree = auto_free(LayerTree.new())
	add_child(tree)
	var cont: Node2D = auto_free(Node2D.new()); add_child(cont)
	var ab: _FakeArtboard = auto_free(_FakeArtboard.new())
	ab.name = "Artboard"; ab.artboard_size = Vector2(3000, 3000)
	cont.add_child(ab)
	var system: LayerSystem = _make_system(tree, cont)

	var uno: VectorRectangle = auto_free(VectorRectangle.new()); uno.name = "Alfa"
	ab.add_child(uno); uno.global_position = Vector2(100, 100)
	var dos: VectorRectangle = auto_free(VectorRectangle.new()); dos.name = "Beta"
	ab.add_child(dos); dos.global_position = Vector2(200, 200)
	system.sincronizar_arbol_completo()
	await get_tree().process_frame

	system._on_buscar_capas("beta")
	assert_bool(system._node_to_item_map[dos].is_visible()).is_true()
	assert_bool(system._node_to_item_map[uno].is_visible()).is_false()

	system._on_buscar_capas("")
	assert_bool(system._node_to_item_map[uno].is_visible()).is_true()
	assert_bool(system._node_to_item_map[dos].is_visible()).is_true()
	_sm().clear()


func test_agrupar_refleja_la_jerarquia_en_el_arbol() -> void:
	_sm().clear()
	var tree: Tree = auto_free(Tree.new())
	tree.columns = 3
	var cont: Node2D = auto_free(Node2D.new()); add_child(cont)
	var artboard: _FakeArtboard = auto_free(_FakeArtboard.new())
	artboard.name = "Artboard"; artboard.global_position = Vector2(0, 0)
	artboard.artboard_size = Vector2(2000, 2000)
	cont.add_child(artboard)
	var system: LayerSystem = _make_system(tree, cont)

	var a: VectorRectangle = auto_free(VectorRectangle.new()); artboard.add_child(a)
	var b: VectorRectangle = auto_free(VectorRectangle.new()); artboard.add_child(b)
	a.global_position = Vector2(50, 50)
	b.global_position = Vector2(80, 80)
	_sm().select_many([a, b])
	HistoryManager.clear()

	system._agrupar_seleccion()
	await get_tree().process_frame            # _marcar_arbol_sucio es diferido
	await get_tree().process_frame

	# El grupo nuevo es padre de a y b en la escena…
	var grupo: Node = a.get_parent()
	assert_str(str(grupo.name)).starts_with("Grupo")
	# …y el árbol lo refleja: item de tipo "group" con 2 sub-items.
	var item_grupo: TreeItem = system._node_to_item_map.get(grupo)
	assert_object(item_grupo).is_not_null()
	assert_str(str(item_grupo.get_metadata(0))).is_equal("group")
	assert_int(item_grupo.get_child_count()).is_equal(2)
	HistoryManager.clear()
	_sm().clear()


func test_duplicar_seleccion_clona_en_el_mismo_padre_con_undo() -> void:
	_sm().clear()
	var tree: Tree = auto_free(Tree.new())
	var system: LayerSystem = _make_system(tree, auto_free(Node2D.new()))
	var padre: Node2D = auto_free(Node2D.new()); add_child(padre)
	var r: VectorRectangle = auto_free(VectorRectangle.new()); r.name = "Rectángulo"
	padre.add_child(r)
	r.position = Vector2(10, 10)
	_sm().select(r)
	HistoryManager.clear()

	system._duplicar_seleccion()
	assert_int(padre.get_child_count()).is_equal(2)
	var clon: Node2D = padre.get_child(1)
	assert_str(str(clon.name)).is_equal("Rectángulo 2")
	assert_vector(clon.position).is_equal_approx(Vector2(26, 26), Vector2(0.01, 0.01))

	HistoryManager.undo(); await get_tree().process_frame
	assert_int(padre.get_child_count()).is_equal(1)
	HistoryManager.clear()
	_sm().clear()


func test_eliminar_seleccion_quita_del_arbol_con_undo() -> void:
	_sm().clear()
	var tree: Tree = auto_free(Tree.new())
	var system: LayerSystem = _make_system(tree, auto_free(Node2D.new()))
	var padre: Node2D = auto_free(Node2D.new()); add_child(padre)
	var a: Node2D = auto_free(Node2D.new()); padre.add_child(a)
	var b: Node2D = auto_free(Node2D.new()); padre.add_child(b)
	_sm().select(b)
	HistoryManager.clear()

	system._eliminar_seleccion()
	assert_bool(b.get_parent() == null).is_true()
	assert_int(padre.get_child_count()).is_equal(1)

	HistoryManager.undo(); await get_tree().process_frame
	assert_object(b.get_parent()).is_same(padre)
	HistoryManager.clear()
	_sm().clear()


func test_seleccionar_similares_elige_mismo_tipo_en_el_artboard() -> void:
	_sm().clear()
	var tree: Tree = auto_free(Tree.new())
	var cont: Node2D = auto_free(Node2D.new()); add_child(cont)
	var artboard: _FakeArtboard = auto_free(_FakeArtboard.new())
	artboard.name = "Artboard"
	cont.add_child(artboard)
	var system: LayerSystem = _make_system(tree, cont)

	var r1: VectorRectangle = auto_free(VectorRectangle.new()); artboard.add_child(r1)
	var r2: VectorRectangle = auto_free(VectorRectangle.new()); artboard.add_child(r2)
	var c1: VectorCircle = auto_free(VectorCircle.new()); artboard.add_child(c1)

	system._seleccionar_similares(r1)
	var sel: Array = _sm().get_selected()
	assert_array(sel).contains([r1, r2])
	assert_bool(_sm().is_selected(c1)).is_false()
	_sm().clear()


func test_desagrupar_via_menu_saca_hijos_con_undo() -> void:
	_sm().clear()
	var tree: Tree = auto_free(Tree.new())
	var system: LayerSystem = _make_system(tree, auto_free(Node2D.new()))

	var padre: Node2D = auto_free(Node2D.new()); add_child(padre)
	var grupo: Node2D = auto_free(Node2D.new()); grupo.name = "G"
	grupo.set_meta("shape_type", "group")
	padre.add_child(grupo)
	var c1: VectorRectangle = auto_free(VectorRectangle.new()); grupo.add_child(c1)
	var c2: VectorRectangle = auto_free(VectorRectangle.new()); grupo.add_child(c2)
	HistoryManager.clear()

	system._desagrupar(grupo)
	assert_object(c1.get_parent()).is_same(padre)
	assert_object(c2.get_parent()).is_same(padre)
	assert_bool(is_instance_valid(grupo) and grupo.get_parent() != null).is_false()

	HistoryManager.undo(); await get_tree().process_frame
	assert_object(c1.get_parent()).is_same(grupo)
	HistoryManager.clear()
	_sm().clear()


## REGRESIÓN CRÍTICA: tras el PRIMER anidado por drag en el panel, TODO se
## bloqueaba — no se podía anidar más ni el panel volvía a sincronizarse.
## Sospecha: `_bloquear_sincronizacion` se queda en `true` o la ruta
## incremental (`child_exiting_tree` → `_process_pending_changes`) borra la
## fila reparentada y nunca la vuelve a poner. Este test hace DOS anidados
## seguidos por la ruta real (`LayerTree.mover_capas` → `hierarchy_changed_by_user`).
func test_dos_anidados_seguidos_por_drag_no_bloquean_el_panel() -> void:
	_sm().clear()
	var tree: LayerTree = auto_free(LayerTree.new())
	add_child(tree)
	var cont: Node2D = auto_free(Node2D.new()); add_child(cont)
	var artboard: _FakeArtboard = auto_free(_FakeArtboard.new())
	artboard.name = "Artboard"; artboard.global_position = Vector2.ZERO
	artboard.artboard_size = Vector2(3000, 3000)
	cont.add_child(artboard)
	var system: LayerSystem = _make_system(tree, cont)

	var a: VectorRectangle = auto_free(VectorRectangle.new()); a.name = "A"; artboard.add_child(a)
	var b: VectorRectangle = auto_free(VectorRectangle.new()); b.name = "B"; artboard.add_child(b)
	var c: VectorCircle = auto_free(VectorCircle.new()); c.name = "C"; artboard.add_child(c)
	a.global_position = Vector2(100, 100)
	b.global_position = Vector2(200, 200)
	c.global_position = Vector2(300, 300)
	HistoryManager.clear()

	system.sincronizar_arbol_completo()
	await get_tree().process_frame

	# ── PRIMER anidado: B dentro de A (como un drop "encima") ──
	tree.mover_capas([b], a, a.get_child_count())
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout   # deja pasar la ventana de batch
	await get_tree().process_frame
	await get_tree().process_frame

	assert_object(b.get_parent()).is_same(a)
	assert_bool(system._bloquear_sincronizacion).is_false()   # ← no debe quedarse trabado
	var it_a: TreeItem = system._node_to_item_map.get(a)
	var it_b: TreeItem = system._node_to_item_map.get(b)
	assert_object(it_a).is_not_null()
	assert_object(it_b).is_not_null()
	assert_object(it_b.get_parent()).is_same(it_a)          # el panel refleja B bajo A

	# ── SEGUNDO anidado: C dentro de A (esto es lo que "se bloqueaba") ──
	tree.mover_capas([c], a, a.get_child_count())
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	await get_tree().process_frame
	await get_tree().process_frame

	assert_object(c.get_parent()).is_same(a)
	assert_bool(system._bloquear_sincronizacion).is_false()
	var it_c: TreeItem = system._node_to_item_map.get(c)
	assert_object(it_c).is_not_null()
	assert_object(it_c.get_parent()).is_same(system._node_to_item_map.get(a))

	# ── TERCERO: sacar C de nuevo al artboard (debe seguir pudiéndose) ──
	tree.mover_capas([c], artboard, artboard.get_child_count())
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	await get_tree().process_frame
	await get_tree().process_frame

	assert_object(c.get_parent()).is_same(artboard)
	assert_bool(system._bloquear_sincronizacion).is_false()
	assert_object(system._node_to_item_map.get(c)).is_not_null()
	HistoryManager.clear()
	_sm().clear()
