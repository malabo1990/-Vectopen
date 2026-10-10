extends GdUnitTestSuite

## Panel Trazos: perfil de grosor, puntas, guardado y desplegable.

const StrokeProfile = preload("res://script_gdscript/shapes/stroke_profile.gd")
const StrokeMarkers = preload("res://script_gdscript/shapes/stroke_markers.gd")
const Ser = preload("res://scripts/canvas/canvas_serializer.gd")
const StrokeGeom = preload("res://script_gdscript/shapes/stroke_geom.gd")

func _path() -> Path2D:
	var vp := Path2D.new()
	vp.set_script(load("res://script_gdscript/shapes/VectorPath.gd"))
	var c := Curve2D.new()
	c.add_point(Vector2(0, 0))
	c.add_point(Vector2(200, 0))
	vp.curve = c
	vp.set("stroke_width", 10.0)
	return vp

func test_sample_pasa_por_los_nodos_y_no_se_sale() -> void:
	var p := StrokeProfile.preset("ideal")
	for q in p:
		assert_float(StrokeProfile.sample(p, q.x)).is_equal_approx(q.y, 0.001)
	for k in 101:
		var w := StrokeProfile.sample(p, k / 100.0)
		assert_bool(w >= 0.0 and w <= 1.0).is_true()
	assert_float(StrokeProfile.sample(PackedVector2Array(), 0.3)).is_equal(1.0)   # uniforme

func test_preset_name_reconoce_y_personalizado_no() -> void:
	assert_str(StrokeProfile.preset_name(StrokeProfile.preset("taper_end"))).is_equal("taper_end")
	assert_str(StrokeProfile.preset_name(PackedVector2Array([Vector2(0, 0.3), Vector2(1, 0.7)]))).is_equal("")

func test_outline_es_tira_de_triangulos_valida() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(50, 20), Vector2(100, 0)])
	var o := StrokeProfile.outline(pts, 10.0, StrokeProfile.preset("taper"), true, true)
	var idx: PackedInt32Array = o["indices"]
	var verts: PackedVector2Array = o["points"]
	assert_int(idx.size() % 3).is_equal(0)
	assert_bool(idx.size() >= 12).is_true()
	for i in idx:
		assert_bool(i >= 0 and i < verts.size()).is_true()

func test_trim_points_acorta_la_longitud_pedida() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	var t := StrokeMarkers.trim_points(pts, 30.0, false)
	assert_vector(t[t.size() - 1]).is_equal_approx(Vector2(70, 0), Vector2(0.01, 0.01))
	var s := StrokeMarkers.trim_points(pts, 30.0, true)
	assert_vector(s[0]).is_equal_approx(Vector2(30, 0), Vector2(0.01, 0.01))

func test_inspector_aplica_perfil_y_escala_con_deshacer() -> void:
	var vp: Path2D = auto_free(_path())
	add_child(vp)
	var sm = get_tree().root.get_node("SelectionManager")
	sm.select(vp)
	InspectorCore._sync_selection()
	HistoryManager.clear()
	InspectorCore.apply("stroke_profile", StrokeProfile.preset("ideal"))
	InspectorCore.apply("stroke_pointer_scale", 2.0)
	assert_str(StrokeProfile.preset_name(vp.get("stroke_profile"))).is_equal("ideal")
	assert_float(float(vp.get("stroke_pointer_scale"))).is_equal(2.0)
	HistoryManager.undo()
	HistoryManager.undo()
	assert_bool(StrokeProfile.is_uniform(vp.get("stroke_profile"))).is_true()
	assert_float(float(vp.get("stroke_pointer_scale"))).is_equal(1.0)
	sm.set_selection([])
	HistoryManager.clear()

func test_guardar_y_cargar_conserva_estilo_puntas_y_perfil() -> void:
	var holder: Node2D = auto_free(Node2D.new())
	add_child(holder)
	var vp := _path()
	holder.add_child(vp)
	vp.set("stroke_style", 1)
	vp.set("stroke_dash_len", 20.0)
	vp.set("stroke_pointer_end", 5)
	vp.set("stroke_cap_start", 1)
	vp.set("stroke_pointer_scale", 1.5)
	vp.set("stroke_profile", StrokeProfile.preset("swell"))
	var data: Array = Ser.serialize_elements(holder)
	vp.free()
	Ser.instantiate_elements(holder, data)
	await get_tree().process_frame
	var back: Node = null
	for c in holder.get_children():
		if c is Path2D:
			back = c
	assert_object(back).is_not_null()
	assert_int(int(back.get("stroke_style"))).is_equal(1)
	assert_float(float(back.get("stroke_dash_len"))).is_equal(20.0)
	assert_int(int(back.get("stroke_pointer_end"))).is_equal(5)
	assert_int(int(back.get("stroke_cap_start"))).is_equal(1)
	assert_float(float(back.get("stroke_pointer_scale"))).is_equal(1.5)
	assert_str(StrokeProfile.preset_name(back.get("stroke_profile"))).is_equal("swell")

func test_perfil_en_pincel_es_su_width_curve() -> void:
	var l: Line2D = auto_free(Line2D.new())
	l.points = PackedVector2Array([Vector2.ZERO, Vector2(100, 0)])
	add_child(l)
	InspectorCore._write(l, "stroke_profile", StrokeProfile.preset("taper"))
	assert_object(l.width_curve).is_not_null()
	assert_float(l.width_curve.sample(0.5)).is_greater(0.9)
	assert_float(l.width_curve.sample(0.0)).is_less(0.2)
	InspectorCore._write(l, "stroke_profile", PackedVector2Array())
	assert_object(l.width_curve).is_null()

func test_desplegable_perfil_pasa_a_solido_en_un_paso() -> void:
	var vp: Path2D = auto_free(_path())
	add_child(vp)
	vp.set("stroke_style", 1)
	var sm = get_tree().root.get_node("SelectionManager")
	sm.select(vp)
	InspectorCore._sync_selection()
	HistoryManager.clear()
	var anchor: Control = auto_free(Control.new())
	add_child(anchor)
	var Pop = load("res://script_gdscript/ui/pro/stroke_popover.gd")
	var pop = Pop.toggle(anchor, "profile", anchor)
	await get_tree().process_frame
	pop._apply_profile(StrokeProfile.preset("ideal"))
	assert_int(int(vp.get("stroke_style"))).is_equal(0)
	assert_str(StrokeProfile.preset_name(vp.get("stroke_profile"))).is_equal("ideal")
	HistoryManager.undo()
	assert_int(int(vp.get("stroke_style"))).is_equal(1)
	assert_bool(StrokeProfile.is_uniform(vp.get("stroke_profile"))).is_true()
	pop.visible = false
	sm.set_selection([])
	HistoryManager.clear()


func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r

func test_doble_con_remate_cuadrado_son_dos_lineas_no_un_bloque() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	var m := StrokeGeom.build(line, false, 4, 20.0, 2, 2, PackedVector2Array(), 12, 8)
	var dm := StrokeGeom.double_metrics(20.0)
	# Ningún vértice en el hueco central entre las dos líneas
	var hueco := dm.y - dm.x * 0.5
	for v in m["points"]:
		assert_bool(absf(v.y) >= hueco - 0.01).is_true()
	# remate cuadrado: cada línea se alarga medio grosor DE ESA LÍNEA
	var b := _bounds(m["points"])
	assert_float(b.position.x).is_equal_approx(-dm.x * 0.5, 0.01)
	assert_float(b.end.x).is_equal_approx(100.0 + dm.x * 0.5, 0.01)
	assert_float(b.size.y).is_equal_approx(20.0, 0.01)   # borde exterior = grosor total

func test_inglete_mantiene_el_grosor_en_las_esquinas() -> void:
	var l := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])
	var m := StrokeGeom.build(l, false, 0, 10.0, 0, 0, PackedVector2Array(), 12, 8)
	# esquina de 90°: el vértice exterior está a 5·√2 del punto
	var far := 0.0
	for v in m["points"]:
		var d: float = v.distance_to(Vector2(100, 0))
		if d < 20.0:   # solo los vértices de la esquina
			far = maxf(far, d)
	assert_float(far).is_equal_approx(5.0 * sqrt(2.0), 0.01)

func test_discontinuo_empieza_y_acaba_en_guion() -> void:
	var l := PackedVector2Array([Vector2(0, 0), Vector2(137, 0)])
	var d := StrokeGeom.dashes(l, false, 10.0, 6.0)
	assert_vector(d[0]["pts"][0]).is_equal_approx(Vector2(0, 0), Vector2(0.01, 0.01))
	var last: PackedVector2Array = d[d.size() - 1]["pts"]
	assert_vector(last[last.size() - 1]).is_equal_approx(Vector2(137, 0), Vector2(0.01, 0.01))

func test_puntos_en_los_dos_extremos() -> void:
	var l := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	var c := StrokeGeom.dots(l, false, 4.0, 6.0)
	assert_vector(c[0]).is_equal(Vector2(0, 0))
	assert_vector(c[c.size() - 1]).is_equal_approx(Vector2(100, 0), Vector2(0.01, 0.01))

func test_svg_exporta_curvas_exactas() -> void:
	var vp: Path2D = auto_free(_path())
	vp.curve.set_point_out(0, Vector2(30, -40))
	var svg: String = vp.to_svg()
	assert_str(svg).contains("C ")
	assert_str(svg).not_contains("L ")


## Trazado de la captura del usuario: esquinas con manejadores de 2–3 px
## (clic con temblor). Todos los estilos dan una malla válida.
func _sharp_with_tiny_handles() -> Curve2D:
	var c := Curve2D.new()
	var hs := [Vector2(2, 3), Vector2(-3, 1), Vector2(3, -2), Vector2(-2, -3), Vector2(1, 2)]
	var ps := [Vector2(320, 0), Vector2(110, 125), Vector2(85, 380), Vector2(240, 620), Vector2(310, 690)]
	for i in ps.size():
		c.add_point(ps[i], -hs[i], hs[i])
	return c

func test_los_14_estilos_dan_mallas_validas() -> void:
	var pts := StrokeGeom.curve_points(_sharp_with_tiny_handles())
	assert_int(StrokeGeom.STYLE_ORDER.size()).is_equal(14)
	for st in StrokeGeom.STYLE_ORDER:
		var m := StrokeGeom.build(pts, false, st, 25.0, 1, 2, PackedVector2Array(), 12.0, 8.0)
		var verts: PackedVector2Array = m["points"]
		var idx: PackedInt32Array = m["indices"]
		assert_bool(idx.size() > 0 and idx.size() % 3 == 0).override_failure_message("estilo %d" % st).is_true()
		for v in verts:
			assert_bool(is_finite(v.x) and is_finite(v.y)).is_true()
		for i in idx:
			assert_bool(i >= 0 and i < verts.size()).is_true()

func test_limpieza_quita_los_microbucles_de_las_esquinas() -> void:
	var raw := StrokeGeom.curve_points(_sharp_with_tiny_handles())
	var clean := StrokeGeom.clean(raw, 25.0 * 0.15, false)
	assert_bool(clean.size() < raw.size()).is_true()
	# ningún giro de casi 180° (pico) queda en la línea limpia
	for i in range(1, clean.size() - 1):
		var a := (clean[i] - clean[i - 1]).normalized()
		var b := (clean[i + 1] - clean[i]).normalized()
		assert_float(a.dot(b)).is_greater(-0.985)
	# los extremos reales se conservan
	assert_vector(clean[0]).is_equal(raw[0])
	assert_vector(clean[clean.size() - 1]).is_equal(raw[raw.size() - 1])

func test_paralela_del_doble_no_va_al_reves() -> void:
	var pts := StrokeGeom.clean(StrokeGeom.curve_points(_sharp_with_tiny_handles()), 3.75, false)
	for side in [1.0, -1.0]:
		var o := StrokeGeom.offset_line(pts, 8.75 * side, false)
		assert_int(o.size()).is_greater(1)
