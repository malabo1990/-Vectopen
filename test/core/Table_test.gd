extends GdUnitTestSuite

## Tablas (encargo 23): crear, celdas, filas/columnas, deshacer, editar el
## texto de una celda a mano y guardar/abrir.

const CANVAS := "res://scenes/canvas/canvas.tscn"
const CS = preload("res://scripts/canvas/canvas_serializer.gd")
var _api: VectopenAPI = null

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api
	HistoryManager.clear()

func _cells(t: Node) -> int:
	return t.get_children().filter(func(c) -> bool: return c.has_meta("table_cell")).size()

func test_crear_y_editar() -> void:
	var t := _api.add_table(Rect2(20, 20, 600, 0), 3, 3, [["A", "B", "C"], ["1", "2", "3"], ["x", "y", "z"]])
	assert_object(t).is_not_null()
	assert_int(_cells(t)).is_equal(9)
	_api.table_set_cell(t, 1, 1, "dos")
	assert_str(String(_api.table_data(t)[1][1])).is_equal("dos")
	_api.table_insert_row(t)
	assert_int(int(t.get_meta("table")["rows"])).is_equal(4)
	_api.table_insert_col(t, 1, 80.0)
	assert_int(int(t.get_meta("table")["cols"])).is_equal(4)
	assert_str(String(_api.table_data(t)[0][2])).is_equal("B")
	_api.undo()
	assert_int(int(t.get_meta("table")["cols"])).is_equal(3)
	_api.table_delete_row(t, 0)
	assert_str(String(_api.table_data(t)[0][0])).is_equal("1")

func test_texto_editado_a_mano_se_conserva() -> void:
	var t := _api.add_table(Rect2(20, 20, 400, 0), 2, 2, [["a", "b"], ["c", "d"]])
	var cell: Node = null
	for c in t.get_children():
		if c.has_meta("table_cell") and c.get_meta("table_cell") == [1, 0]:
			cell = c
	assert_object(cell).is_not_null()
	_api.set_prop(cell, "text", "editado")
	_api.table_insert_row(t)   # rehace la tabla: no puede perder el texto
	assert_str(String(_api.table_data(t)[1][0])).is_equal("editado")

func test_guardar_y_abrir() -> void:
	var t := _api.add_table(Rect2(20, 20, 400, 0), 2, 2, [["Plan", "Precio"], ["Pro", "9 €"]])
	t.name = "Precios"
	var path := "user://test_table.vtp"
	var c := t.get_parent().get_parent()
	assert_bool(CS.write_vtc(path, c)).is_true()
	CS.rebuild_from_vtc(c, path)
	await get_tree().process_frame
	var t2 := _api.find("Precios")
	assert_object(t2).is_not_null()
	assert_str(String(_api.table_data(t2)[1][1])).is_equal("9 €")
	assert_int(_cells(t2)).is_equal(4)
	_api.table_insert_col(t2)
	assert_int(int(t2.get_meta("table")["cols"])).is_equal(3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
