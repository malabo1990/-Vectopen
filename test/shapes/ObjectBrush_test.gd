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

## Texto en trazado: UNA copia a su tamaño natural (no se estira), alineada
## al centro y al otro lado de la curva con «flip».
func test_patron_una_copia_alineada() -> void:
	var src := [[{"pts": PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 1), Vector2(0, 1)]), "col": Color.RED}]]
	var p := _line(2, 100.0)
	var pr := {"mode": "pattern", "repeat": false, "align": 0.5}
	var m: Dictionary = OB.build(p, _const(2, 2.5), OB._normalize_all(src), pr)
	assert_int(int(m["stamps"])).is_equal(1)
	var e := _extent(m["points"])
	# alto 5 → largo natural 20, centrado en 100 → de 40 a 60
	assert_float(e.position.x).is_equal_approx(40.0, 0.05)
	assert_float(e.end.x).is_equal_approx(60.0, 0.05)
	pr["align"] = 0.0
	pr["offset"] = 0.1
	var m2: Dictionary = OB.build(p, _const(2, 2.5), OB._normalize_all(src), pr)
	assert_float(_extent(m2["points"]).position.x).is_equal_approx(10.0, 0.05)
	# flip: la parte de «arriba» de la figura pasa al otro lado
	var top := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 0.2), Vector2(0, 0.2)])
	var bot := PackedVector2Array([Vector2(0, 0.8), Vector2(4, 0.8), Vector2(4, 1), Vector2(0, 1)])
	var two: Array = OB._normalize_all([[{"pts": top, "col": Color.RED}, {"pts": bot, "col": Color.BLUE}]])
	var a: Dictionary = OB.build(p, _const(2, 2.5), two, {"mode": "pattern", "repeat": false})
	var b: Dictionary = OB.build(p, _const(2, 2.5), two, {"mode": "pattern", "repeat": false, "flip": true})
	var ya := 0.0
	var yb := 0.0
	var cols_a: PackedColorArray = a["colors"]
	var cols_b: PackedColorArray = b["colors"]
	for i in cols_a.size():
		if cols_a[i] == Color.RED:
			ya = (a["points"] as PackedVector2Array)[i].y
	for i in cols_b.size():
		if cols_b[i] == Color.RED:
			yb = (b["points"] as PackedVector2Array)[i].y
	assert_float(signf(ya)).is_equal(-signf(yb))

## Texto en trazado: cada letra se coloca RÍGIDA (sin doblarse) y girada con
## la curva; en un valle no se aprietan ni se pierde el espacio entre letras.
func test_texto_en_trazado_letras_rigidas() -> void:
	var a := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var b := PackedVector2Array([Vector2(1.5, 0), Vector2(2.5, 0), Vector2(2.5, 1), Vector2(1.5, 1)])
	var src: Array = OB._normalize_all([[{"pts": a, "col": Color.RED, "g": 0}, {"pts": b, "col": Color.BLUE, "g": 1}]])
	# valle cerrado (arco de radio 12): las letras van por dentro de la curva
	var p := PackedVector2Array()
	for i in 61:
		var t := PI * 0.25 + PI * 0.5 * float(i) / 60.0
		p.append(Vector2(cos(t), sin(t)) * -12.0 + Vector2(0, 12))
	var m: Dictionary = OB.build(p, _const(p.size(), 2.0), src, {"mode": "pattern", "repeat": false, "align": 0.5, "baseline": true})
	var pts: PackedVector2Array = m["points"]
	var cols: PackedColorArray = m["colors"]
	for col in [Color.RED, Color.BLUE]:
		var q := PackedVector2Array()
		for i in pts.size():
			if cols[i] == col and not q.has(pts[i]):
				q.append(pts[i])
		assert_int(q.size()).is_equal(4)
		# cuadrado de lado 4 (alto 4 px): lados y diagonales sin deformar
		var d := PackedFloat32Array()
		for i in 4:
			for j in range(i + 1, 4):
				d.append(q[i].distance_to(q[j]))
		d.sort()
		for k in 4:
			assert_float(d[k]).is_equal_approx(4.0, 0.05)
		assert_float(d[4]).is_equal_approx(4.0 * sqrt(2.0), 0.05)
	# hueco entre letras conservado: ningún punto azul a menos de 1 px de uno rojo
	var gap := INF
	for i in pts.size():
		for j in pts.size():
			if cols[i] == Color.RED and cols[j] == Color.BLUE:
				gap = minf(gap, pts[i].distance_to(pts[j]))
	assert_float(gap).is_greater(1.0)

func test_datos_conservan_la_letra() -> void:
	var src := [[{"pts": PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]), "col": Color.RED, "g": 3}]]
	var back: Array = OB.from_data(JSON.parse_string(JSON.stringify(OB.to_data(src))))
	assert_int(int(back[0][0]["g"])).is_equal(3)

## Línea base: una letra con descendente (la «p») no levanta el resto del
## texto; las letras se apoyan en el trazo por su base, no por el pie.
func test_texto_en_trazado_linea_base_real() -> void:
	var a := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var b := PackedVector2Array([Vector2(1.2, 0), Vector2(2.2, 0), Vector2(2.2, 1), Vector2(1.2, 1)])
	var p := PackedVector2Array([Vector2(2.4, 0.3), Vector2(3.4, 0.3), Vector2(3.4, 1.4), Vector2(2.4, 1.4)])  # baja
	var src: Array = OB._normalize_all([[{"pts": a, "col": Color.RED, "g": 0}, {"pts": b, "col": Color.GREEN, "g": 1}, {"pts": p, "col": Color.BLUE, "g": 2}]])
	var m: Dictionary = OB.build(_line(2, 100.0), _const(2, 7.0), src, {"mode": "pattern", "repeat": false, "baseline": true})
	var pts: PackedVector2Array = m["points"]
	var cols: PackedColorArray = m["colors"]
	var red_bottom := -INF
	var blue_bottom := -INF
	for i in pts.size():
		if cols[i] == Color.RED:
			red_bottom = maxf(red_bottom, pts[i].y)
		elif cols[i] == Color.BLUE:
			blue_bottom = maxf(blue_bottom, pts[i].y)
	# y hacia abajo y texto encima del eje (y = 0): la base toca el eje y la «p» baja de él
	assert_float(absf(red_bottom)).is_less(0.01)
	assert_float(blue_bottom).is_greater(0.5)

func test_texto_en_trazado_espaciado_y_tramo() -> void:
	var a := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var b := PackedVector2Array([Vector2(2, 0), Vector2(3, 0), Vector2(3, 1), Vector2(2, 1)])
	var src: Array = OB._normalize_all([[{"pts": a, "col": Color.RED, "g": 0}, {"pts": b, "col": Color.BLUE, "g": 1}]])
	var line := _line(2, 200.0)
	var half := _const(2, 5.0)   # alto 10 → texto de 30 de largo
	var base := {"mode": "pattern", "repeat": false, "baseline": true}
	var s0: Dictionary = OB.text_span(line, half, src, base)
	assert_float(s0["text"].x).is_equal_approx(0.0, 0.01)
	assert_float(s0["text"].y).is_equal_approx(30.0, 0.05)
	# espaciado 0,5 alto → +5 entre las dos letras
	var tr := base.duplicate()
	tr["tracking"] = 0.5
	assert_float(OB.text_span(line, half, src, tr)["text"].y).is_equal_approx(35.0, 0.05)
	# tramo 25 %..75 % (50..150) centrado → empieza en 100 - 15 = 85
	var rg := base.duplicate()
	rg["start_at"] = 0.25
	rg["end_at"] = 0.75
	rg["align"] = 0.5
	assert_float(OB.text_span(line, half, src, rg)["text"].x).is_equal_approx(85.0, 0.05)
	# con espaciado, el centrado tiene en cuenta el largo nuevo (35) → 82,5
	rg["tracking"] = 0.5
	assert_float(OB.text_span(line, half, src, rg)["text"].x).is_equal_approx(82.5, 0.05)

## Área con signo de las piezas de un color (el signo dice si está reflejada).
func _signed_area(m: Dictionary, col: Color) -> float:
	var pts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var cols: PackedColorArray = m["colors"]
	var a := 0.0
	for t in range(0, idx.size(), 3):
		if cols[idx[t]] != col:
			continue
		var p0 := pts[idx[t]]
		var p1 := pts[idx[t + 1]]
		var p2 := pts[idx[t + 2]]
		a += (p1 - p0).cross(p2 - p0) * 0.5
	return a

func _center(m: Dictionary, col: Color) -> Vector2:
	var acc := Vector2.ZERO
	var n := 0
	for i in (m["points"] as PackedVector2Array).size():
		if (m["colors"] as PackedColorArray)[i] == col:
			acc += (m["points"] as PackedVector2Array)[i]
			n += 1
	return acc / maxf(n, 1)

## Debajo del trazo, invertir dirección y espejo.
func test_texto_en_trazado_debajo_invertir_espejo() -> void:
	var a := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var b := PackedVector2Array([Vector2(2, 0), Vector2(3, 0), Vector2(3, 1), Vector2(2, 1)])
	var src: Array = OB._normalize_all([[{"pts": a, "col": Color.RED, "g": 0}, {"pts": b, "col": Color.BLUE, "g": 1}]])
	var line := _line(2, 100.0)
	var half := _const(2, 5.0)
	var base := {"mode": "pattern", "repeat": false, "baseline": true}
	var m0: Dictionary = OB.build(line, half, src, base)
	var area0 := _signed_area(m0, Color.RED)
	assert_float(_center(m0, Color.RED).y).is_less(0.0)              # encima
	assert_float(_center(m0, Color.RED).x).is_less(_center(m0, Color.BLUE).x)
	# debajo: cuelga del trazo, se lee igual
	var pt := base.duplicate()
	pt["valign"] = "top"
	var mt: Dictionary = OB.build(line, half, src, pt)
	for q in (mt["points"] as PackedVector2Array):
		assert_float(q.y).is_greater_equal(-0.01)
	assert_float(_center(mt, Color.RED).x).is_less(_center(mt, Color.BLUE).x)
	assert_float(signf(_signed_area(mt, Color.RED))).is_equal(signf(area0))
	# invertir: al otro lado, de derecha a izquierda, letras NO reflejadas
	var pr := base.duplicate()
	pr["reverse"] = true
	var mr: Dictionary = OB.build(line, half, src, pr)
	assert_float(_center(mr, Color.RED).y).is_greater(0.0)
	assert_float(_center(mr, Color.RED).x).is_greater(_center(mr, Color.BLUE).x)
	assert_float(signf(_signed_area(mr, Color.RED))).is_equal(signf(area0))
	# al invertir, el texto se queda en el mismo tramo del trazado (0..30)
	var sp: Vector2 = OB.text_span(line, half, src, pr)["text"]
	assert_float(sp.x).is_equal_approx(0.0, 0.05)
	assert_float(sp.y).is_equal_approx(30.0, 0.05)
	# espejo: letras reflejadas
	var pf := base.duplicate()
	pf["flip"] = true
	var mf: Dictionary = OB.build(line, half, src, pf)
	assert_float(signf(_signed_area(mf, Color.RED))).is_equal(-signf(area0))
