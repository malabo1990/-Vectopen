extends GdUnitTestSuite

## Efectos de letras paramétricos (panel "Letras avanzadas"): se materializan
## en runs por letra solo para dibujar; los runs del usuario no se tocan.

const LetterFx := preload("res://script_gdscript/text/letter_fx.gd")

func _shape(text: String, fs := 40) -> Node2D:
	var s: Node2D = auto_free(Node2D.new())
	s.set_meta("text", text)
	s.set_meta("font_size", fs)
	return s

func test_sin_efectos_devuelve_los_mismos_runs() -> void:
	var s := _shape("Hola")
	var runs := [{"length": 4, "color": Color.RED}]
	assert_bool(LetterFx.has_fx(s)).is_false()
	assert_array(LetterFx.derive_runs(s, runs, "Hola")).is_equal(runs)

func test_proporciones_aaa_primera_grande_ultima_pequena() -> void:
	var s := _shape("ABCDEFG")
	s.set_meta("letter_proportions", {"mode": "Aaa", "start": 1.6, "mid": 1.2, "mid2": 0.8, "end": 0.4})
	var out := LetterFx.derive_runs(s, [], "ABCDEFG")
	assert_int(out.size()).is_equal(7)
	assert_float(float(out[0]["size"])).is_equal(64.0)   # 40 × 1.6
	assert_float(float(out[6]["size"])).is_equal(16.0)   # 40 × 0.4
	for i in 6:
		assert_bool(float(out[i]["size"]) > float(out[i + 1]["size"])).is_true()

func test_conserva_el_formato_del_usuario_y_su_tamano() -> void:
	var s := _shape("abcd")
	s.set_meta("letter_proportions", {"mode": "custom", "start": 2.0, "mid": 2.0, "mid2": 2.0, "end": 2.0})
	var out := LetterFx.derive_runs(s, [{"length": 2, "color": Color.RED, "size": 10.0}, {"length": 2, "bold": true}], "abcd")
	assert_int(out.size()).is_equal(2)                    # fusiona letras iguales
	assert_object(out[0]["color"]).is_equal(Color.RED)
	assert_float(float(out[0]["size"])).is_equal(20.0)    # su propio tamaño × 2
	assert_bool(bool(out[1]["bold"])).is_true()
	assert_float(float(out[1]["size"])).is_equal(80.0)    # base 40 × 2

func test_arco_baja_entero_y_el_centro_queda_mas_alto() -> void:
	var s := _shape("ABCDEFGHI")
	s.set_meta("letter_wave", {"mode": "arc", "amount": 30.0})
	var out := LetterFx.derive_runs(s, [], "ABCDEFGHI")
	var shifts: Array = []
	for r in out:
		for k in int(r["length"]):
			shifts.append(float(r.get("baseline_shift", 0.0)))
	assert_int(shifts.size()).is_equal(9)
	for v in shifts:
		assert_bool(v <= 0.001).is_true()                 # nunca sube por encima de la caja
	assert_float(shifts[4]).is_equal_approx(0.0, 0.01)    # el centro, en la línea base
	assert_float(shifts[0]).is_equal_approx(-30.0, 0.01)  # los extremos, 30 px más abajo
	assert_float(LetterFx.wave_extent(s, 9)).is_equal_approx(30.0, 0.01)

func test_onda_y_rango() -> void:
	var w := {"mode": "wave", "amount": 10.0, "cycles": 1.0, "phase": 0.0}
	var rng := LetterFx.wave_range(w, 33)
	assert_float(rng.x).is_equal_approx(-10.0, 0.2)
	assert_float(rng.y).is_equal_approx(10.0, 0.2)

func test_interletra_progresiva() -> void:
	var s := _shape("ABCDE")
	s.set_meta("letter_tracking_ramp", {"start": 0.0, "end": 20.0})
	var out := LetterFx.derive_runs(s, [], "ABCDE")
	assert_float(float(out[0]["letter_spacing"])).is_equal(0.0)
	assert_float(float(out[out.size() - 1]["letter_spacing"])).is_equal(20.0)

func test_efectos_vacios_no_cuentan() -> void:
	var s := _shape("x")
	s.set_meta("letter_wave", {"mode": "wave", "amount": 0.0})
	s.set_meta("letter_tracking_ramp", {"start": 0.0, "end": 0.0})
	s.set_meta("letter_proportions", {})
	assert_bool(LetterFx.has_fx(s)).is_false()
