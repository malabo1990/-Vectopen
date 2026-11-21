extends GdUnitTestSuite

## Colores globales del documento (encargo 25): vincular relleno y trazo,
## cambiar la muestra cambia todo, un color a mano desvincula, deshacer,
## guardar y abrir.

const CANVAS := "res://scenes/canvas/canvas.tscn"
const GC = preload("res://script_gdscript/shapes/global_colors.gd")
const CS = preload("res://scripts/canvas/canvas_serializer.gd")
var _api: VectopenAPI = null

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api
	GC.from_data(GC.container(), [])
	HistoryManager.clear()

func test_vincular_y_cambiar() -> void:
	var a := _api.add_rect(Vector2(50, 50), Vector2(40, 40))
	var b := _api.add_ellipse(Vector2(150, 50), Vector2(40, 40))
	var t := _api.add_text(Vector2(20, 120), "Marca", 30)
	var id := _api.add_global_color("Azul marca", Color("#1d3557"))
	assert_bool(_api.apply_global_color("azul marca", [a, b, t])).is_true()
	assert_bool(_api.apply_global_color(id, [b], "stroke")).is_true()
	assert_int(_api.set_global_color(id, Color("#e63946"))).is_equal(4)   # 3 rellenos + 1 trazo
	for n in [a, b, t]:
		assert_bool((_api.get_prop(n, "fill_color") as Color).is_equal_approx(Color("#e63946"))).is_true()
	assert_bool((b.stroke_color as Color).is_equal_approx(Color("#e63946"))).is_true()
	_api.undo()
	assert_bool((a.fill_color as Color).is_equal_approx(Color("#1d3557"))).is_true()
	# Un color puesto a mano desvincula ese canal
	_api.redo()
	_api.set_fill(a, Color.GREEN)
	assert_bool(a.has_meta("fill_global")).is_false()
	_api.set_global_color(id, Color.BLACK)
	assert_bool((a.fill_color as Color).is_equal_approx(Color.GREEN)).is_true()
	assert_bool((b.fill_color as Color).is_equal_approx(Color.BLACK)).is_true()

func test_guardar_y_abrir() -> void:
	var a := _api.add_rect(Vector2(50, 50), Vector2(40, 40))
	a.name = "Logo"
	var id := _api.add_global_color("Arena", Color("#e9c46a"))
	_api.apply_global_color(id, [a])
	var c := GC.container()
	var path := "user://test_gc.vtp"
	assert_bool(CS.write_vtc(path, c)).is_true()
	GC.from_data(c, [])
	CS.rebuild_from_vtc(c, path)
	await get_tree().process_frame
	assert_str(String(_api.global_colors()[0]["name"])).is_equal("Arena")
	var a2 := _api.find("Logo")
	assert_str(String(a2.get_meta("fill_global", ""))).is_equal(id)
	assert_int(_api.set_global_color("Arena", Color.WHITE)).is_equal(1)
	assert_bool((a2.fill_color as Color).is_equal_approx(Color.WHITE)).is_true()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
