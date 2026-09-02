extends GdUnitTestSuite

## NodeState: contrato de captura / restauración del estado NO-geométrico
## (visibilidad, bloqueo, recorte / máscara, z-order).

func _nodo() -> Node2D:
	var n := Node2D.new()
	auto_free(n)
	add_child(n)
	return n


func test_captura_solo_claves_soportadas() -> void:
	var n := _nodo()
	var s := NodeState.capture(n)
	assert_bool(s.has("visible")).is_true()
	assert_bool(s.has("z_index")).is_true()
	assert_bool(s.has("clip_children")).is_true()   # Node2D es CanvasItem
	assert_bool(s.has("locked")).is_true()
	assert_bool(s["locked"]).is_false()
	assert_bool(s.has("clip_mask")).is_false()      # sin meta → no aparece


func test_round_trip_visibilidad_bloqueo_recorte_zorder() -> void:
	var n := _nodo()
	n.visible = true
	n.z_index = 3
	n.clip_children = 0
	var s0 := NodeState.capture(n)

	# muta TODO
	n.visible = false
	n.z_index = 99
	n.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	n.set_meta("locked", true)

	NodeState.restore(n, s0)
	assert_bool(n.visible).is_true()
	assert_int(n.z_index).is_equal(3)
	assert_int(int(n.clip_children)).is_equal(0)
	assert_bool(n.get_meta("locked", false)).is_false()
	assert_bool(n.has_meta("locked")).is_false()   # quitado, no dejado en false


func test_round_trip_meta_de_mascara() -> void:
	var n := _nodo()
	n.set_meta("clip_mask", true)
	n.set_meta("clip_mask_target", "DisplayLabel")
	var s_on := NodeState.capture(n)

	n.set_meta("clip_mask", false)
	n.remove_meta("clip_mask_target")
	NodeState.restore(n, s_on)
	assert_bool(n.get_meta("clip_mask", false)).is_true()
	assert_str(String(n.get_meta("clip_mask_target", ""))).is_equal("DisplayLabel")

	# y al revés: capturar "sin máscara" y restaurar sobre uno enmascarado la quita
	var limpio := _nodo()
	var s_off := NodeState.capture(limpio)
	n.set_meta("clip_mask", true)
	n.set_meta("clip_mask_target", "X")
	# s_off no tiene clave clip_mask → restore no toca esas metas (captura parcial segura)
	NodeState.restore(n, s_off)
	assert_bool(n.get_meta("clip_mask", false)).is_true()   # intacto: s_off no la conocía


func test_equal_detecta_cambios() -> void:
	var n := _nodo()
	var a := NodeState.capture(n)
	var b := NodeState.capture(n)
	assert_bool(NodeState.equal(a, b)).is_true()

	n.visible = false
	var c := NodeState.capture(n)
	assert_bool(NodeState.equal(a, c)).is_false()


func test_nodo_invalido_no_revienta() -> void:
	assert_dict(NodeState.capture(null)).is_empty()
	NodeState.restore(null, {"visible": false})   # no debe lanzar
	assert_bool(NodeState.equal({}, {})).is_true()
