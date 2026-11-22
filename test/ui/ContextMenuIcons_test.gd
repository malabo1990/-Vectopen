extends GdUnitTestSuite
## Cada acción de los menús contextuales (Modern, Smart y Pro) tiene su icono
## propio en icon/UI/menu/ (antes: huecos en Modern y la misma curva para
## todas las opciones nuevas de Smart).

const DIR := "res://icon/UI/menu/"

func _ids(path: String, pattern: String) -> Array:
	var src := FileAccess.get_file_as_string(path)
	var re := RegEx.new()
	re.compile(pattern)
	var out: Array = []
	for m in re.search_all(src):
		var id := m.get_string(1)
		if not out.has(id):
			out.append(id)
	return out

func _missing(ids: Array, aliases: Dictionary = {}) -> Array:
	var miss: Array = []
	for id in ids:
		var f: String = DIR + String(aliases.get(id, id)) + ".svg"
		if not ResourceLoader.exists(f):
			miss.append(id)
	return miss

func test_modern_todas_las_opciones_con_icono() -> void:
	var ids := _ids("res://script_gdscript/ui/modern/modern_context_menu.gd", '_add_menu_item\\("([a-z_0-9]+)"')
	assert_int(ids.size()).is_greater(20)
	assert_array(_missing(ids, {"ungroup_all": "ungroup"})).is_empty()

func test_smart_extras_con_icono_propio() -> void:
	var ids := _ids("res://script_gdscript/ui/smart_menu_extras.gd", '\\["[A-Z][A-Za-z]+", "([a-z_0-9]+)", "')
	assert_int(ids.size()).is_greater(10)
	assert_array(_missing(ids)).is_empty()

func test_pro_todas_las_opciones_con_icono() -> void:
	var ids := _ids("res://script_gdscript/ui/pro/pro_context_menu.gd", '_add\\([a-z_]+, "([a-z_0-9]+)", "')
	assert_int(ids.size()).is_greater(20)
	assert_array(_missing(ids)).is_empty()
