extends GdUnitTestSuite

## Estilos de texto con nombre (VAL-24): crear desde un texto, aplicar a
## varios, redefinir (actualiza todos y respeta retoques locales), un paso de
## deshacer por operación, borrar/renombrar, y guardar/abrir en el .vtp.

const CANVAS := "res://scenes/canvas/canvas.tscn"
const TS = preload("res://script_gdscript/text/text_styles.gd")
const CS = preload("res://scripts/canvas/canvas_serializer.gd")

var _api: VectopenAPI = null

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api
	TS.from_data(TS.container(), [])
	HistoryManager.clear()

func _fs(t: Node) -> float:
	return float(_api.get_prop(t, "font_size"))

func test_crear_aplicar_y_redefinir() -> void:
	var a := _api.add_text(Vector2(20, 20), "Título A", 40, Color.RED)
	var b := _api.add_text(Vector2(20, 100), "Título B", 18)
	var c := _api.add_text(Vector2(20, 180), "Título C", 18)
	_api.set_prop(a, "font_weight", 700)
	var id := _api.add_text_style("Título", a, [a])
	assert_str(id).is_not_empty()
	assert_int(_api.text_styles().size()).is_equal(1)
	assert_str(_api.text_style_of(a)).is_equal(id)
	# Aplicar por NOMBRE a b y c
	assert_bool(_api.apply_text_style("título", [b, c])).is_true()
	for t in [b, c]:
		assert_float(_fs(t)).is_equal(40.0)
		assert_int(int(_api.get_prop(t, "font_weight"))).is_equal(700)
		assert_bool((_api.get_prop(t, "fill_color") as Color).is_equal_approx(Color.RED)).is_true()
		assert_str(_api.text_style_of(t)).is_equal(id)
	# Retoque local en c: color azul (se conserva al redefinir el color)
	_api.set_prop(c, "fill_color", Color.BLUE)
	assert_bool(TS.is_modified(c)).is_true()
	# Redefinir: tamaño 52 y color verde → a y b cambian todo; c solo el tamaño
	var n := _api.update_text_style(id, {"font_size": 52, "fill_color": Color.GREEN})
	assert_int(n).is_equal(3)
	for t in [a, b, c]:
		assert_float(_fs(t)).is_equal(52.0)
	assert_bool((_api.get_prop(a, "fill_color") as Color).is_equal_approx(Color.GREEN)).is_true()
	assert_bool((_api.get_prop(b, "fill_color") as Color).is_equal_approx(Color.GREEN)).is_true()
	assert_bool((_api.get_prop(c, "fill_color") as Color).is_equal_approx(Color.BLUE)).is_true()
	# Deshacer la redefinición: un solo paso devuelve tamaños y colores
	_api.undo()
	for t in [a, b, c]:
		assert_float(_fs(t)).is_equal(40.0)
	assert_bool((_api.get_prop(b, "fill_color") as Color).is_equal_approx(Color.RED)).is_true()
	assert_float(float(TS.get_style(id)["props"]["font_size"])).is_equal(40.0)
	_api.redo()
	assert_float(_fs(b)).is_equal(52.0)

func test_redefinir_desde_un_texto() -> void:
	var a := _api.add_text(Vector2(20, 20), "Cuerpo 1", 14)
	var b := _api.add_text(Vector2(20, 80), "Cuerpo 2", 14)
	var id := _api.add_text_style("Cuerpo", a, [a, b])
	_api.set_prop(a, "font_size", 16)
	_api.set_prop(a, "line_spacing", 6)
	_api.update_text_style("Cuerpo", a)
	assert_float(_fs(b)).is_equal(16.0)
	assert_int(int(_api.get_prop(b, "line_spacing"))).is_equal(6)
	assert_bool(TS.is_modified(a)).is_false()
	assert_str(id).is_not_empty()

func test_renombrar_borrar_y_deshacer() -> void:
	var a := _api.add_text(Vector2(20, 20), "Pie", 10)
	var id := _api.add_text_style("Pie", a, [a])
	var id2 := _api.add_text_style("Pie", {"font_size": 9})
	assert_str(String(TS.get_style(id2)["name"])).is_equal("Pie 2")   # nombre único
	assert_bool(_api.rename_text_style(id, "Pie de foto")).is_true()
	assert_str(String(TS.get_style(id)["name"])).is_equal("Pie de foto")
	assert_bool(_api.remove_text_style("Pie de foto")).is_true()
	assert_str(_api.text_style_of(a)).is_empty()
	assert_float(_fs(a)).is_equal(10.0)   # borrar no cambia el aspecto
	_api.undo()
	assert_str(_api.text_style_of(a)).is_equal(id)

func test_un_paso_dentro_de_un_script() -> void:
	var a := _api.add_text(Vector2(20, 20), "T", 20)
	HistoryManager.clear()
	_api.begin("script")
	var id := _api.add_text_style("H1", a, [a])
	_api.update_text_style(id, {"font_size": 30})
	_api.end()
	assert_float(_fs(a)).is_equal(30.0)
	_api.undo()
	assert_int(_api.text_styles().size()).is_equal(0)
	assert_float(_fs(a)).is_equal(20.0)

func test_guardar_y_abrir() -> void:
	var a := _api.add_text(Vector2(20, 20), "Guardado", 33, Color("#336699"))
	var id := _api.add_text_style("Título", a, [a])
	var path := "user://test_text_styles.vtp"
	var c := TS.container()
	assert_bool(CS.write_vtc(path, c)).is_true()
	TS.from_data(c, [])
	assert_int(_api.text_styles().size()).is_equal(0)
	CS.rebuild_from_vtc(c, path)
	await get_tree().process_frame
	var st := TS.get_style(id)
	assert_str(String(st.get("name", ""))).is_equal("Título")
	assert_float(float(st["props"]["font_size"])).is_equal(33.0)
	assert_bool((st["props"]["fill_color"] as Color).is_equal_approx(Color("#336699"))).is_true()
	var t := _api.find("Texto")
	assert_object(t).is_not_null()
	assert_str(_api.text_style_of(t)).is_equal(id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
