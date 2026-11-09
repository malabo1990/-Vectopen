extends GdUnitTestSuite
## La malla nativa del trazo (VectopenIO.stroke_halves) es la misma que la
## del GDScript de respaldo (StrokeGeom._halves_gd), en trazos rectos,
## curvas, giros más cerrados que el grosor y con cada remate.

const SG = preload("res://script_gdscript/shapes/stroke_geom.gd")

func _cases() -> Array:
	var out := []
	var a := PackedVector2Array()
	for i in 60:
		a.append(Vector2(i * 2.0, sin(i * 0.2) * 15.0))
	out.append(a)
	var z := PackedVector2Array()
	for k in 8:
		for q in 6:
			z.append(Vector2((k + q / 6.0) * 10.0, (q * 3.0) if k % 2 == 0 else 18.0 - q * 3.0))
	out.append(z)
	var s := PackedVector2Array()
	for i in 200:
		var t := i / 199.0
		s.append(Vector2(t * 80.0 + cos(t * 40.0) * 3.0, sin(t * 40.0) * 4.0))
	out.append(s)
	return out

func test_nativo_igual_que_gdscript() -> void:
	var io: Object = SG._native_geom()
	if io == null:
		push_warning("vectopen_io no cargado: se omite la comparación")
		return
	for pts in _cases():
		var half := PackedFloat32Array()
		for i in pts.size():
			half.append(2.0 + 1.5 * sin(i * 0.1))
		for caps in [[0, 0], [1, 1], [2, 2], [1, 0]]:
			var g := {"points": PackedVector2Array(), "indices": PackedInt32Array(), "v": PackedFloat32Array()}
			SG._halves_gd(g, pts, half, caps[0], caps[1])
			var r: Dictionary = io.stroke_halves(pts, half, caps[0], caps[1])
			var gp: PackedVector2Array = g["points"]
			var rp: PackedVector2Array = r["points"]
			assert_int(rp.size()).is_equal(gp.size())
			assert_array(Array(r["indices"])).is_equal(Array(g["indices"]))
			assert_array(Array(r["k"])).is_equal(Array(g["k"]))
			var worst := 0.0
			for i in mini(rp.size(), gp.size()):
				worst = maxf(worst, rp[i].distance_to(gp[i]))
			assert_float(worst).is_less(0.01)
			assert_int((r["v"] as PackedFloat32Array).size()).is_equal((g["v"] as PackedFloat32Array).size())
			assert_int((r["beyond"] as PackedFloat32Array).size()).is_equal((g["beyond"] as PackedFloat32Array).size())

## Sellos del aerógrafo: el nativo (VectopenIO.stroke_stamps) da la misma
## malla y opacidades que el GDScript de respaldo (stamps_gd).
func test_sellos_nativo_igual_que_gdscript() -> void:
	var io: Object = SG._native_geom()
	if io == null or not io.has_method("stroke_stamps"):
		push_warning("vectopen_io sin stroke_stamps: se omite")
		return
	for pts in _cases():
		var half := PackedFloat32Array()
		var flow := PackedFloat32Array()
		for i in pts.size():
			half.append(3.0 + 2.0 * sin(i * 0.1))
			flow.append(0.5 + 0.4 * cos(i * 0.07))
		var g: Dictionary = SG.stamps_gd(pts, half, flow)
		var r: Dictionary = io.stroke_stamps(pts, half, flow)
		assert_int((r["points"] as PackedVector2Array).size()).is_equal((g["points"] as PackedVector2Array).size())
		assert_array(Array(r["indices"])).is_equal(Array(g["indices"]))
		var worst := 0.0
		var gp: PackedVector2Array = g["points"]
		var rp: PackedVector2Array = r["points"]
		for i in gp.size():
			worst = maxf(worst, gp[i].distance_to(rp[i]))
		assert_float(worst).is_less(0.01)
		var wa := 0.0
		for i in (g["a"] as PackedFloat32Array).size():
			wa = maxf(wa, absf(float(g["a"][i]) - float(r["a"][i])))
		assert_float(wa).is_less(0.001)
