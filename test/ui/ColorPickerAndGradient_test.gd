extends GdUnitTestSuite

## Test suite para Color Picker, Editor de Gradientes y Paletas (Sección 9)

const HslPickerScript := preload("res://script_gdscript/ui/hsl_colorpickr.gd")
const ControlGradientScript := preload("res://script_gdscript/ui/control_gradient.gd")

func test_hsl_color_picker_conversions() -> void:
	var picker: Control = auto_free(HslPickerScript.new()) as Control
	picker.size = Vector2(240, 200)
	add_child(picker)

	# 1. Fijar color rojo puro
	picker.set_color(Color(1.0, 0.0, 0.0, 1.0))
	var rgb: Dictionary = picker.to_rgb_dict()
	assert_int(rgb["r"]).is_equal(255)
	assert_int(rgb["g"]).is_equal(0)
	assert_int(rgb["b"]).is_equal(0)

	var cmyk: Dictionary = picker.to_cmyk_dict()
	assert_int(cmyk["c"]).is_equal(0)
	assert_int(cmyk["m"]).is_equal(100)
	assert_int(cmyk["y"]).is_equal(100)
	assert_int(cmyk["k"]).is_equal(0)

	# 2. Fijar desde RGB
	picker.set_from_rgb(0, 255, 0)
	var rgb2: Dictionary = picker.to_rgb_dict()
	assert_int(rgb2["g"]).is_equal(255)
	assert_int(rgb2["r"]).is_equal(0)

	# 3. Fijar desde CMYK (Cyan)
	picker.set_from_cmyk(100, 0, 0, 0)
	var rgb_c: Dictionary = picker.to_rgb_dict()
	assert_int(rgb_c["r"]).is_equal(0)
	assert_int(rgb_c["g"]).is_equal(255)
	assert_int(rgb_c["b"]).is_equal(255)

func test_gradient_editor_invert_and_stops() -> void:
	var host: Control = auto_free(Control.new()) as Control
	add_child(host)

	var color_rect: ColorRect = ColorRect.new()
	color_rect.size = Vector2(200, 24)
	host.add_child(color_rect)

	var ge: Control = auto_free(ControlGradientScript.new()) as Control
	ge.color_rect = color_rect
	host.add_child(ge)
	await get_tree().process_frame

	# Al iniciar tiene 2 paradas (0.0 negro y 1.0 blanco)
	assert_int(ge.stops.size()).is_equal(2)
	assert_float(ge.stops[0].pos_ratio).is_equal_approx(0.0, 0.001)
	assert_float(ge.stops[1].pos_ratio).is_equal_approx(1.0, 0.001)

	# Invertir gradiente
	ge.invert_gradient()
	assert_float(ge.stops[0].pos_ratio).is_equal_approx(0.0, 0.001)
	assert_float(ge.stops[1].pos_ratio).is_equal_approx(1.0, 0.001)
	# Tras invertir, el color en 0.0 debe ser el que estaba en 1.0 (blanco)
	assert_float(ge.stops[0].color.r).is_equal_approx(1.0, 0.01)

	# Añadir parada y luego eliminar
	var new_stop: Control = ge._create_stop_node(0.5, Color.RED) as Control
	assert_int(ge.stops.size()).is_equal(3)
	ge._remove_stop(new_stop)
	assert_int(ge.stops.size()).is_equal(2)

func test_color_core_palette_json_and_gpl_export() -> void:
	var cc: Node = get_node_or_null("/root/ColorCore")
	if not cc:
		return

	cc.palette.clear()
	cc.add_swatch(Color(1.0, 0.0, 0.0, 1.0))
	cc.add_swatch(Color(0.0, 1.0, 0.0, 1.0))
	cc.add_swatch(Color(0.0, 0.0, 1.0, 1.0))

	var json_path := "user://test_palette.json"
	var gpl_path := "user://test_palette.gpl"

	var ok_json: bool = cc.export_palette_json(json_path)
	assert_bool(ok_json).is_true()
	assert_bool(FileAccess.file_exists(json_path)).is_true()

	var ok_gpl: bool = cc.export_palette_gpl(gpl_path, "Test Palette")
	assert_bool(ok_gpl).is_true()
	assert_bool(FileAccess.file_exists(gpl_path)).is_true()

	# Probar importación
	cc.palette.clear()
	var imported_json: bool = cc.import_palette_json(json_path)
	assert_bool(imported_json).is_true()
	assert_int(cc.palette.size()).is_equal(3)

	# Limpieza de ficheros temporales de test
	DirAccess.remove_absolute(ProjectSettings.globalize_path(json_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gpl_path))
