extends GdUnitTestSuite

## Imán inteligente (SnapManager.smart_snap): ajuste por bordes y centros,
## umbral constante en pantalla y segmentos de guía.

var _prev_obj: bool
var _prev_center: bool
var _prev_grid: bool

func before_test() -> void:
	_prev_obj = SnapManager.snap_to_objects
	_prev_center = SnapManager.snap_to_center
	_prev_grid = SnapManager.grid_enabled
	SnapManager.snap_to_objects = true
	SnapManager.snap_to_center = true
	SnapManager.grid_enabled = false

func after_test() -> void:
	SnapManager.snap_to_objects = _prev_obj
	SnapManager.snap_to_center = _prev_center
	SnapManager.grid_enabled = _prev_grid

func test_sin_candidatos_no_ajusta() -> void:
	var r := SnapManager.smart_snap(Rect2(0, 0, 50, 50), [], 1.0)
	assert_vector(r["offset"]).is_equal(Vector2.ZERO)
	assert_int((r["guides"] as Array).size()).is_equal(0)

func test_desactivado_no_ajusta() -> void:
	SnapManager.snap_to_objects = false
	var moving := Rect2(103, 0, 50, 50)
	var cand := [Rect2(100, 0, 50, 50)]
	var r := SnapManager.smart_snap(moving, cand, 1.0)
	assert_vector(r["offset"]).is_equal(Vector2.ZERO)

func test_ajusta_borde_izquierdo_dentro_del_umbral() -> void:
	# moving.left = 103, candidato.left = 100 → dx = -3 (<= 7 px)
	var moving := Rect2(103, 300, 50, 50)
	var cand := [Rect2(100, 0, 50, 50)]
	var r := SnapManager.smart_snap(moving, cand, 1.0)
	assert_float(r["offset"].x).is_equal_approx(-3.0, 0.001)
	assert_float(r["offset"].y).is_equal_approx(0.0, 0.001)
	assert_int((r["guides"] as Array).size()).is_equal(1)
	assert_str(r["guides"][0]["axis"]).is_equal("x")
	assert_float(r["guides"][0]["coord"]).is_equal_approx(100.0, 0.001)

func test_fuera_del_umbral_no_ajusta() -> void:
	# dx = -12, umbral 7 px a zoom 1 → nada
	var moving := Rect2(112, 300, 50, 50)
	var cand := [Rect2(100, 0, 50, 50)]
	var r := SnapManager.smart_snap(moving, cand, 1.0)
	assert_vector(r["offset"]).is_equal(Vector2.ZERO)

func test_umbral_escala_con_el_zoom() -> void:
	# dx = -12 en mundo; a zoom 0.5 el umbral efectivo es 14 px de mundo → ajusta
	var moving := Rect2(112, 300, 50, 50)
	var cand := [Rect2(100, 0, 50, 50)]
	var r := SnapManager.smart_snap(moving, cand, 0.5)
	assert_float(r["offset"].x).is_equal_approx(-12.0, 0.001)

func test_ajusta_en_ambos_ejes_a_la_vez() -> void:
	# moving left 103 / top 300 ; candidato left 100 / top 303 → offset (-3, +3)
	var moving := Rect2(103, 300, 50, 50)
	var cand := [Rect2(100, 303, 50, 50)]
	var r := SnapManager.smart_snap(moving, cand, 1.0)
	assert_float(r["offset"].x).is_equal_approx(-3.0, 0.001)
	assert_float(r["offset"].y).is_equal_approx(3.0, 0.001)
	assert_int((r["guides"] as Array).size()).is_equal(2)

func test_snap_to_center_off_ignora_los_centros() -> void:
	SnapManager.snap_to_center = false
	# El ÚNICO par dentro de umbral es centro-vs-centro → con center off, nada.
	var moving := Rect2(102, 300, 50, 50)   # left 102, center 127, right 152
	var cand := [Rect2(77, 900, 50, 50)]    # left 77,  center 102, right 127
	# left(102) vs right(127) = 25 (fuera); center(127) vs center(102) = 25 (fuera);
	# left(102) vs center(102) = 0 pero involucra un centro → ignorado con center off
	var r := SnapManager.smart_snap(moving, cand, 1.0)
	assert_vector(r["offset"]).is_equal(Vector2.ZERO)
