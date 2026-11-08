extends GdUnitTestSuite
## Pincel de objeto (VGSE fase 2): estampas repartidas por longitud de arco,
## tamaño con la presión, giro con el trazo, multiobjeto y semilla.

const OB = preload("res://script_gdscript/shapes/object_brush.gd")

func _line(n: int, step: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		p.append(Vector2(i * step, 0.0))
	return p

func _const(n: int, v: float) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	for i in n:
		h.append(v)
	return h

func test_estampas_repartidas_por_longitud() -> void:
	# eje de 100 unidades con puntos MUY desiguales: el reparto no depende
	# de los puntos sino de la longitud
	var p := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(100, 0)])
	var m: Dictionary = OB.build(p, _const(4, 5.0), OB.preset("dot"), {"spacing": 1.0})
	# tamaño 10, separación 1 → una cada 10: 0,10,…,100 = 11
	assert_int(int(m["stamps"])).is_equal(11)
	assert_bool((m["indices"] as PackedInt32Array).size() % 3 == 0).is_true()
	assert_int((m["colors"] as PackedColorArray).size()).is_equal((m["points"] as PackedVector2Array).size())

func test_el_tamano_sigue_a_la_presion() -> void:
	var p := _line(2, 200.0)
	var small: Dictionary = OB.build(p, _const(2, 2.0), OB.preset("dot"))
	var big: Dictionary = OB.build(p, _const(2, 8.0), OB.preset("dot"))
	var r_small := _extent(small["points"]).size.y
	var r_big := _extent(big["points"]).size.y
	assert_float(r_small).is_equal_approx(4.0, 0.1)
	assert_float(r_big).is_equal_approx(16.0, 0.2)
	assert_int(int(big["stamps"])).is_less(int(small["stamps"]))

func test_gira_con_el_trazo() -> void:
	# hoja (alargada en x) a lo largo de un trazo VERTICAL: girada, queda
	# alargada en y
	var p := PackedVector2Array([Vector2(0, 0), Vector2(0, 30)])
	var m: Dictionary = OB.build(p, _const(2, 5.0), OB.preset("leaf"), {"spacing": 5.0})
	var e := _extent(m["points"])
	assert_float(e.size.y).is_greater(e.size.x)
	var m2: Dictionary = OB.build(p, _const(2, 5.0), OB.preset("leaf"), {"spacing": 5.0, "rotate": false})
	var e2 := _extent(m2["points"])
	assert_float(e2.size.x).is_greater(e2.size.y * 0.9)

func test_multiobjeto_alterna_y_la_semilla_repite() -> void:
	var src: Array = OB.preset("dot") + OB.preset("star")
	var p := _line(2, 100.0)
	var a: Dictionary = OB.build(p, _const(2, 3.0), src, {"multi": "sequence"})
	var cols: PackedColorArray = a["colors"]
	var seen := {}
	for c in cols:
		seen[c.to_html()] = true
	assert_int(seen.size()).is_equal(2)
	var r1: Dictionary = OB.build(p, _const(2, 3.0), src, {"multi": "random", "scatter": 0.5, "seed": 7})
	var r2: Dictionary = OB.build(p, _const(2, 3.0), src, {"multi": "random", "scatter": 0.5, "seed": 7})
	assert_array(Array(r1["points"])).is_equal(Array(r2["points"]))

func test_datos_guardables_ida_y_vuelta() -> void:
	var src: Array = OB.preset("star")
	var back: Array = OB.from_data(JSON.parse_string(JSON.stringify(OB.to_data(src))))
	assert_int(back.size()).is_equal(1)
	assert_int((back[0][0]["pts"] as PackedVector2Array).size()).is_equal(10)
	assert_str((back[0][0]["col"] as Color).to_html()).is_equal((src[0][0]["col"] as Color).to_html())

func test_fuente_desde_figuras_normalizada() -> void:
	var a := Polygon2D.new()
	a.polygon = PackedVector2Array([Vector2(0, 0), Vector2(40, 0), Vector2(40, 20), Vector2(0, 20)])
	a.position = Vector2(100, 100)
	a.color = Color.RED
	var b := Polygon2D.new()
	b.polygon = PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	b.position = Vector2(150, 100)
	add_child(a)
	add_child(b)
	auto_free(a)
	auto_free(b)
	var one: Array = OB.from_shapes([a, b], true)
	assert_int(one.size()).is_equal(1)
	assert_int(one[0].size()).is_equal(2)
	var e := Rect2()
	var first := true
	for pc in one[0]:
		for q in pc["pts"]:
			if first:
				e = Rect2(q, Vector2.ZERO)
				first = false
			else:
				e = e.expand(q)
	assert_float(maxf(e.size.x, e.size.y)).is_equal_approx(1.0, 0.001)
	assert_float(e.get_center().length()).is_less(0.001)
	var many: Array = OB.from_shapes([a, b], false)
	assert_int(many.size()).is_equal(2)

func _extent(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(q)
	return r

# ── Pincel de patrón ─────────────────────────────────────────────────────────
## Rectángulo 2:1 a lo largo de un trazo recto: teselas que encajan justas
## de principio a fin y del grosor del trazo.
func test_patron_en_recta_encaja_de_extremo_a_extremo() -> void:
	var src := [[{"pts": PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 1), Vector2(0, 1)]), "col": Color.RED}]]
	var p := _line(2, 100.0)   # 100 de largo
	var m: Dictionary = OB.build(p, _const(2, 5.0), OB._normalize_all(src), {"mode": "pattern", "spacing": 1.0})
	# grosor 10 → tesela de 20 → 5 teselas
	assert_int(int(m["stamps"])).is_equal(5)
	var e := _extent(m["points"])
	assert_float(e.position.x).is_equal_approx(0.0, 0.01)
	assert_float(e.end.x).is_equal_approx(100.0, 0.01)
	assert_float(e.size.y).is_equal_approx(10.0, 0.01)

## En un arco de circunferencia la figura se DOBLA: sus puntos quedan entre
## los radios r ± grosor/2 (no en cuerdas rectas que se salen).
func test_patron_se_dobla_con_la_curva() -> void:
	var p := PackedVector2Array()
	for i in 91:
		var a := deg_to_rad(float(i))
		p.append(Vector2(cos(a), sin(a)) * 100.0)
	var src := [[{"pts": PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 1), Vector2(0, 1)]), "col": Color.RED}]]
	var m: Dictionary = OB.build(p, _const(91, 4.0), OB._normalize_all(src), {"mode": "pattern", "spacing": 1.0})
	var lo := INF
	var hi := 0.0
	for q in m["points"]:
		lo = minf(lo, q.length())
		hi = maxf(hi, q.length())
	assert_float(lo).is_greater(95.9)
	assert_float(hi).is_less(104.1)
	# las franjas tienen puntos en medio de cada tesela (no solo en sus extremos)
	assert_int((m["points"] as PackedVector2Array).size()).is_greater(int(m["stamps"]) * 40)

## Contornos para «convertir en figuras»: uno por estampa y pieza; en
## patrón, doblados con la curva (dentro del grosor).
func test_contornos_por_estampa_y_doblados_en_patron() -> void:
	var src: Array = OB.preset("star")
	var p := _line(2, 100.0)
	var m: Dictionary = OB.build(p, _const(2, 5.0), src, {"spacing": 1.0})
	var rings: Array = OB.outlines(p, _const(2, 5.0), src, {"spacing": 1.0})
	assert_int(rings.size()).is_equal(int(m["stamps"]))
	var arc := PackedVector2Array()
	for i in 91:
		var a := deg_to_rad(float(i))
		arc.append(Vector2(cos(a), sin(a)) * 100.0)
	var rect := [[{"pts": PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 1), Vector2(0, 1)]), "col": Color.RED}]]
	var pr := {"mode": "pattern", "spacing": 1.0}
	var pr_rings: Array = OB.outlines(arc, _const(91, 4.0), OB._normalize_all(rect), pr)
	assert_int(pr_rings.size()).is_equal(int(OB.build(arc, _const(91, 4.0), OB._normalize_all(rect), pr)["stamps"]))
	for r in pr_rings:
		for q in r["pts"]:
			assert_float(q.length()).is_between(95.9, 104.1)
