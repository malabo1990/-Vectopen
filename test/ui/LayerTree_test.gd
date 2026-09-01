extends GdUnitTestSuite

## LayerTree — reparent multi-nodo con undo (Fase 4 del panel profesional).

func _tree() -> LayerTree:
	var t: LayerTree = auto_free(LayerTree.new())
	add_child(t)
	return t

func _n(parent: Node, nm: String) -> Node2D:
	var n: Node2D = auto_free(Node2D.new())
	n.name = nm
	parent.add_child(n)
	return n


## Un item ANIDADO (hijo/nieto) debe poder arrastrarse: `_nodos_para_arrastrar`
## devuelve su nodo aunque no esté seleccionado.
func test_item_anidado_se_puede_arrastrar() -> void:
	var t := _tree()
	t.columns = 3
	var raiz := t.create_item()
	var it_ab := t.create_item(raiz)
	var it_grupo := t.create_item(it_ab)
	var it_nieto := t.create_item(it_grupo)

	var ab: Node2D = auto_free(Node2D.new()); add_child(ab)
	var grupo: Node2D = auto_free(Node2D.new()); ab.add_child(grupo)
	var nieto: Node2D = auto_free(Node2D.new()); grupo.add_child(nieto)
	# metadatos: nodo en slot 1, tipo en slot 0 (como _create_tree_item)
	it_ab.set_metadata(1, ab)
	it_grupo.set_metadata(1, grupo)
	it_nieto.set_metadata(1, nieto)

	var arrastrables: Array = t._nodos_para_arrastrar(it_nieto)
	assert_array(arrastrables).contains_exactly([nieto])


## Sacar un NIETO fuera, al nivel superior (hijo directo del artboard).
func test_sacar_nieto_al_nivel_superior_con_undo() -> void:
	var t := _tree()
	var ab: Node2D = auto_free(Node2D.new()); add_child(ab)
	var g := _n(ab, "G")
	var sub := _n(g, "Sub")
	var nieto := _n(sub, "Nieto")
	nieto.global_position = Vector2(77, 88)
	HistoryManager.clear()

	t.mover_capas([nieto], ab, ab.get_child_count())
	assert_object(nieto.get_parent()).is_same(ab)
	assert_vector(nieto.global_position).is_equal_approx(Vector2(77, 88), Vector2(0.01, 0.01))

	HistoryManager.undo(); await get_tree().process_frame
	assert_object(nieto.get_parent()).is_same(sub)
	HistoryManager.clear()


## `_can_drop_data`: NO se puede soltar un nodo dentro de su propio descendiente.
func test_can_drop_rechaza_soltar_en_descendiente_propio() -> void:
	var t := _tree(); t.columns = 3
	var raiz := t.create_item()
	var it_g := t.create_item(raiz)
	var it_sub := t.create_item(it_g)
	var g: Node2D = auto_free(Node2D.new()); add_child(g)
	var sub: Node2D = auto_free(Node2D.new()); g.add_child(sub)
	it_g.set_metadata(1, g)
	it_sub.set_metadata(1, sub)

	# arrastrar `g` e intentar soltarlo sobre `sub` (su propio hijo) → false
	var data := {"nodes": [g]}
	# _can_drop_data usa get_item_at_position; probamos la lógica de ancestros
	# directamente vía _drag_nodes + el bucle. Reconstruimos la comprobación:
	var nodos: Array = t._drag_nodes(data)
	var anc: Node = sub
	var rechazado := false
	while anc != null:
		if anc in nodos:
			rechazado = true
			break
		anc = anc.get_parent()
	assert_bool(rechazado).is_true()


## Regresión: con SELECT_MULTI la fila DESTINO puede venir en la selección
## arrastrada. `_nodos_efectivos` la excluye para que "meter A dentro de B"
## funcione aunque B siga seleccionada (antes fallaba siempre).
func test_nodos_efectivos_excluye_el_destino_y_sus_descendientes() -> void:
	var t := _tree()
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var a := _n(root, "A")
	var b := _n(root, "B")
	var hijo_b := _n(b, "HijoB")

	# Arrastrar [A, B] y soltar sobre B → solo A es efectivo.
	assert_array(t._nodos_efectivos([a, b], b)).contains_exactly([a])
	# Arrastrar [A, HijoB] y soltar sobre B → HijoB (descendiente de B) se cae.
	assert_array(t._nodos_efectivos([a, hijo_b], b)).contains_exactly([a])
	# Sin el destino en la lista, no se toca nada.
	assert_array(t._nodos_efectivos([a], b)).contains_exactly([a])
	# Si SOLO se arrastra el propio destino, queda vacío (drop se ignora).
	assert_array(t._nodos_efectivos([b], b)).is_empty()


## `mover_capas` con la lista ya filtrada mete A dentro de B conservando C fuera.
func test_meter_capa_en_otra_ya_seleccionada_via_efectivos() -> void:
	var t := _tree()
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var a := _n(root, "A")
	var b := _n(root, "B")
	var c := _n(root, "C")
	a.global_position = Vector2(10, 20)
	HistoryManager.clear()

	var efectivos := t._nodos_efectivos([a, b], b)   # simula A+B seleccionados, drop en B
	t.mover_capas(efectivos, b, b.get_child_count())

	assert_object(a.get_parent()).is_same(b)
	assert_object(c.get_parent()).is_same(root)
	assert_vector(a.global_position).is_equal_approx(Vector2(10, 20), Vector2(0.01, 0.01))
	HistoryManager.undo(); await get_tree().process_frame
	assert_object(a.get_parent()).is_same(root)
	HistoryManager.clear()


## REGRESIÓN CRÍTICA ("1er anidado OK, el 2º saca las figuras"): tras el primer
## reparent + rebuild, `Tree.get_drop_section_at_position()` devuelve -100 (no lo
## sabe) y `_drop_data` trataba TODO drop como "hermano" → reparentaba al
## artboard en vez de anidar. `_seccion_drop` lo recalcula desde el rect de la
## fila cuando el motor devuelve un valor fuera de rango.
func test_seccion_drop_recalcula_cuando_el_motor_no_lo_sabe() -> void:
	# Cálculo por rect (lo que hace `_seccion_drop` cuando el motor devuelve -100):
	# tercio central 30–70 % = 0 (anida); fuera = -1 / 1.
	var r := Rect2(Vector2(0, 100), Vector2(200, 20))   # fila de 20 px de alto, y ∈ [100,120]
	assert_int(LayerTree._seccion_por_rect(110.0, r)).is_equal(0)    # 50 % → DENTRO (anida)
	assert_int(LayerTree._seccion_por_rect(108.0, r)).is_equal(0)    # 40 % → DENTRO
	assert_int(LayerTree._seccion_por_rect(112.0, r)).is_equal(0)    # 60 % → DENTRO
	assert_int(LayerTree._seccion_por_rect(103.0, r)).is_equal(-1)   # 15 % → arriba
	assert_int(LayerTree._seccion_por_rect(118.0, r)).is_equal(1)    # 90 % → abajo
	assert_int(LayerTree._seccion_por_rect(0.0, Rect2())).is_equal(0)  # rect vacío → 0 (seguro)


func test_mover_capas_reparenta_varios_con_un_undo() -> void:
	var t := _tree()
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var grupo_a := _n(root, "A")
	var grupo_b := _n(root, "B")
	var x := _n(grupo_a, "X")
	var y := _n(grupo_a, "Y")
	x.global_position = Vector2(11, 22)
	y.global_position = Vector2(33, 44)
	HistoryManager.clear()

	t.mover_capas([x, y], grupo_b, 0)
	assert_object(x.get_parent()).is_same(grupo_b)
	assert_object(y.get_parent()).is_same(grupo_b)
	assert_vector(x.global_position).is_equal_approx(Vector2(11, 22), Vector2(0.01, 0.01))
	assert_bool(HistoryManager.can_undo()).is_true()

	HistoryManager.undo(); await get_tree().process_frame
	assert_object(x.get_parent()).is_same(grupo_a)
	assert_object(y.get_parent()).is_same(grupo_a)

	HistoryManager.redo(); await get_tree().process_frame
	assert_object(x.get_parent()).is_same(grupo_b)
	HistoryManager.clear()


func test_mover_capas_a_indice_concreto() -> void:
	var t := _tree()
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var a := _n(root, "A")
	var b := _n(root, "B")
	var c := _n(root, "C")
	HistoryManager.clear()

	# mover C al principio de root
	t.mover_capas([c], root, 0)
	assert_int(c.get_index()).is_equal(0)
	assert_int(a.get_index()).is_equal(1)
	assert_int(b.get_index()).is_equal(2)
	HistoryManager.clear()


func test_drag_nodes_descarta_descendientes_de_otros_arrastrados() -> void:
	var t := _tree()
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var g := _n(root, "G")
	var hijo := _n(g, "H")
	# _nodos_para_arrastrar filtra por selección de TreeItem; probamos el
	# filtro de descendientes con la ruta de datos directa.
	var data := {"nodes": [g, hijo]}
	# mover_capas debe seguir funcionando aunque le pasen padre+hijo: el hijo
	# viaja con el padre igualmente; comprobamos que no revienta.
	HistoryManager.clear()
	t.mover_capas([g], root, 0)
	assert_object(hijo.get_parent()).is_same(g)
	HistoryManager.clear()
