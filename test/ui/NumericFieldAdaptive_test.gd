extends GdUnitTestSuite
## Campos de grosor con paso adaptativo: llegan a 0,005 sin escribir y
## muestran los decimales que hacen falta.

const NF = preload("res://script_gdscript/ui/components/numeric_field.gd")
const PNF = preload("res://script_gdscript/ui/pro/pro_num_field.gd")

func test_paso_redondo_cerca_del_diez_por_ciento() -> void:
	assert_float(NF.adapt_step(2.0)).is_equal_approx(0.2, 0.0001)
	assert_float(NF.adapt_step(0.05)).is_equal_approx(0.005, 0.00001)
	assert_float(NF.adapt_step(0.5)).is_equal_approx(0.05, 0.0001)
	assert_float(NF.adapt_step(0.0)).is_equal_approx(NF.ADAPT_MIN, 0.000001)

func test_decimales_segun_el_valor() -> void:
	assert_int(NF.adapt_decimals(0.005)).is_greater_equal(3)
	assert_int(NF.adapt_decimals(2.5)).is_equal(2)

func test_rueda_baja_hasta_0005() -> void:
	var f: NumericField = auto_free(NF.new("", " px", 0.0, 100.0, 0.5))
	f.adaptive_step = true
	add_child(f)
	f.value = 2.0
	for i in 200:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = true
		f._gui_input(ev)
		if f.value <= 0.005:
			break
	assert_float(f.value).is_less_equal(0.0051)
	f._refresh_display()
	assert_str(f._line_edit.text).is_not_equal("0")

func test_pro_field_no_redondea_a_medio_pixel() -> void:
	var f = auto_free(PNF.new("", "", ""))
	f.step = 0.5
	f.adaptive_step = true
	assert_float(f._clamp(0.005)).is_equal_approx(0.005, 0.00001)
	assert_str(f._fmt(0.005)).is_equal("0.005")
