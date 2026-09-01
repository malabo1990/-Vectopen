extends GdUnitTestSuite

## Prueba PROFUNDA de la jerarquía del panel de capas: elemento DENTRO de
## elemento DENTRO de elemento (no solo grupos), a cualquier profundidad,
## incluida la sincronización con el árbol, el drag-reparent y el hit-test.

class _FakeArtboard extends Node2D:
	var artboard_size := Vector2(4000, 4000)

func _sys(tree: Tree, cont: Node2D) -> LayerSystem:
	var s: LayerSystem = auto_free(LayerSystem.new())
	s.layer_tree = tree
	s.artboard_container = cont
	add_child(s)
	return s

func _rect(parent: Node, nm: String, pos: Vector2, sz := Vector2(40, 40)) -> VectorRectangle:
	var r: VectorRectangle = auto_free(VectorRectangle.new())
	r.name = nm
	parent.add_child(r)
	r.global_position = pos
	r.size = sz
	return r


## Cadena rectángulo > círculo > polígono (figuras anidadas), NO grupos.
func test_cadena_de_figuras_anidadas_aparece_entera_en_el_arbol() -> void:
	var tree: Tree = auto_free(Tree.new()); tree.columns = 3
	var cont: Node2D = auto_free(Node2D.new()); add_child(cont)
	var ab: _FakeArtboard = auto_free(_FakeArtboard.new())
	ab.name = "Artboard"; ab.global_position = Vector2.ZERO
	cont.add_child(ab)

	var r1: VectorRectangle = _rect(ab, "R1", Vector2(100, 100))
	var c1: VectorCircle = auto_free(VectorCircle.new()); c1.name = "C1"
	r1.add_child(c1); c1.global_position = Vector2(110, 110)
	var p1: VectorPolygon = auto_free(VectorPolygon.new()); p1.name = "P1"
	c1.add_child(p1); p1.global_position = Vector2(115, 115)

	var system: LayerSystem = _sys(tree, cont)
	system.sincronizar_arbol_completo()

	# Los 3 están mapeados y anidados: R1 -> C1 -> P1
	var it_r1: TreeItem = system._node_to_item_map.get(r1)
	var it_c1: TreeItem = system._node_to_item_map.get(c1)
	var it_p1: TreeItem = system._node_to_item_map.get(p1)
	assert_object(it_r1).is_not_null()
	assert_object(it_c1).is_not_null()
	assert_object(it_p1).is_not_null()
	assert_object(it_c1.get_parent()).is_same(it_r1)
	assert_object(it_p1.get_parent()).is_same(it_c1)
	# R1 y C1 aparecen como contenedores (tienen hijos-capa); P1 no.
	assert_str(str(it_r1.get_metadata(0))).is_equal("group")
	assert_str(str(it_c1.get_metadata(0))).is_equal("group")
	assert_str(str(it_p1.get_metadata(0))).is_equal("shape")


## Reparentar una figura DENTRO de otra figura (no un grupo) con un Undo.
func test_reparentar_figura_dentro_de_figura() -> void:
	var tree: LayerTree = auto_free(LayerTree.new()); add_child(tree)
	var ab: Node2D = auto_free(Node2D.new()); add_child(ab)
	var a: VectorRectangle = _rect(ab, "A", Vector2(50, 50))
	var b: VectorRectangle = _rect(ab, "B", Vector2(300, 300))
	HistoryManager.clear()

	tree.mover_capas([b], a, a.get_child_count())
	assert_object(b.get_parent()).is_same(a)
	assert_vector(b.global_position).is_equal_approx(Vector2(300, 300), Vector2(0.01, 0.01))

	HistoryManager.undo(); await get_tree().process_frame
	assert_object(b.get_parent()).is_same(ab)
	HistoryManager.clear()


## El hit-test del lienzo encuentra una figura anidada 3 niveles y devuelve
## la capa de PRIMER nivel (para clic sencillo).
func test_hit_test_figura_anidada_3_niveles() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var ab: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(ab)
	var g: Node2D = auto_free(Node2D.new()); g.set_meta("shape_type", "group")
	ab.add_child(g)
	var sub: Node2D = auto_free(Node2D.new()); sub.set_meta("shape_type", "group")
	g.add_child(sub)
	var hoja: VectorRectangle = auto_free(VectorRectangle.new())
	sub.add_child(hoja)
	hoja.global_position = Vector2(200, 200)
	hoja.size = Vector2(60, 60)   # AABB (170,170)-(230,230)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = ab

	var hit = tool._shape_at(Vector2(200, 200))
	assert_object(hit).is_same(g)   # el grupo de primer nivel, no la hoja
	# pero si la hoja está seleccionada, se arrastra la hoja
	tool.selected_shapes = [hoja]
	assert_object(tool._primer_seleccionado_en_rama(g)).is_same(hoja)


## Figura ANIDADA dentro de OTRA FIGURA (no un grupo pelado): rectángulo padre
## con rectángulo hijo. El padre debe contar como CONTENEDOR en el hit-test para
## que, con el hijo seleccionado, `_on_press` arrastre el hijo y NO lo
## deseleccione. (El fallo "hijos no se pueden arrastrar en el lienzo".)
func test_arrastrar_figura_dentro_de_figura_no_deselecciona() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var ab: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(ab)
	var padre: VectorRectangle = auto_free(VectorRectangle.new())
	ab.add_child(padre)
	padre.global_position = Vector2(300, 300)
	padre.size = Vector2(200, 200)
	var hijo: VectorRectangle = auto_free(VectorRectangle.new())
	padre.add_child(hijo)
	hijo.global_position = Vector2(420, 420)   # sobresale del padre
	hijo.size = Vector2(60, 60)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = ab

	# el padre-figura ahora es "contenedor" para el hit-test
	assert_bool(tool._es_grupo_movetool(padre)).is_true()
	# clic sobre el cuerpo del hijo (que sobresale) → devuelve el PADRE (nivel 1)
	assert_object(tool._shape_at(Vector2(420, 420))).is_same(padre)
	# clic sobre el cuerpo del PROPIO padre también lo encuentra
	assert_object(tool._shape_at(Vector2(300, 300))).is_same(padre)

	# con el hijo seleccionado, _on_press debe arrastrar el HIJO sin deseleccionar
	tool.selected_shapes = [hijo]
	tool.transform_initial_states.clear()
	tool._on_press(Vector2(420, 420))
	assert_array(tool.selected_shapes).contains_exactly([hijo])
	assert_bool(tool.is_dragging_shape).is_true()
	tool._on_motion(Vector2(420, 420) + Vector2(50, 30))
	assert_vector(hijo.global_position).is_equal_approx(Vector2(470, 450), Vector2(1, 1))


## Doble clic (estilo Affinity): cada uno DESCIENDE un nivel hacia la hoja bajo
## el cursor y la selecciona. Clic sencillo = contenedor de primer nivel.
func test_doble_click_entra_al_hijo_anidado() -> void:
	var root: Node2D = auto_free(Node2D.new()); add_child(root)
	var ab: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(ab)
	var padre: VectorRectangle = auto_free(VectorRectangle.new())
	ab.add_child(padre)
	padre.global_position = Vector2(300, 300); padre.size = Vector2(240, 240)
	var hijo: VectorRectangle = auto_free(VectorRectangle.new())
	padre.add_child(hijo)
	hijo.global_position = Vector2(300, 300); hijo.size = Vector2(120, 120)
	var nieto: VectorRectangle = auto_free(VectorRectangle.new())
	hijo.add_child(nieto)
	nieto.global_position = Vector2(300, 300); nieto.size = Vector2(50, 50)

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = ab

	# clic sencillo (simulado) → contenedor de primer nivel
	tool._on_press(Vector2(300, 300))
	assert_array(tool.selected_shapes).contains_exactly([padre])

	# 1er doble clic → baja al hijo
	tool._entrar_en_hijo(Vector2(300, 300))
	assert_array(tool.selected_shapes).contains_exactly([hijo])

	# 2º doble clic → baja al nieto
	tool._entrar_en_hijo(Vector2(300, 300))
	assert_array(tool.selected_shapes).contains_exactly([nieto])

	# 3er doble clic → ya no hay más abajo, la selección no cambia
	tool._entrar_en_hijo(Vector2(300, 300))
	assert_array(tool.selected_shapes).contains_exactly([nieto])

	# Alt+doble clic desde cero → salta DIRECTO a la hoja más profunda (nieto)
	tool.selected_shapes = [padre]
	tool._entrar_hasta_hoja(Vector2(300, 300))
	assert_array(tool.selected_shapes).contains_exactly([nieto])


## Agrupar figuras que ya están anidadas: el grupo nuevo se crea en el padre
## correcto y el árbol lo refleja.
func test_agrupar_dentro_de_una_rama_anidada() -> void:
	var sm := get_node_or_null("/root/SelectionManager")
	sm.clear()
	var tree: Tree = auto_free(Tree.new()); tree.columns = 3
	var cont: Node2D = auto_free(Node2D.new()); add_child(cont)
	var ab: _FakeArtboard = auto_free(_FakeArtboard.new())
	ab.name = "Artboard"
	cont.add_child(ab)
	var system: LayerSystem = _sys(tree, cont)

	var contenedor: VectorRectangle = _rect(ab, "Contenedor", Vector2(100, 100), Vector2(400, 400))
	var x: VectorCircle = auto_free(VectorCircle.new()); x.name = "X"
	contenedor.add_child(x); x.global_position = Vector2(150, 150)
	var y: VectorCircle = auto_free(VectorCircle.new()); y.name = "Y"
	contenedor.add_child(y); y.global_position = Vector2(200, 200)
	HistoryManager.clear()

	sm.select_many([x, y])
	system._agrupar_seleccion()
	await get_tree().process_frame
	await get_tree().process_frame

	var grupo: Node = x.get_parent()
	assert_str(str(grupo.name)).starts_with("Grupo")
	assert_object(grupo.get_parent()).is_same(contenedor)   # dentro de la rama
	assert_object(y.get_parent()).is_same(grupo)
	HistoryManager.clear()
	sm.clear()
