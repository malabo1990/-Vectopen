extends GdUnitTestSuite

## Panel de archivos «smart export»: filas por elemento con formato,
## arrastrar a una carpeta = exportar (sin sobrescribir), a Recientes =
## Biblioteca (VOP), soltar archivos en una fila = convertir, deshacer
## una exportación, y arrastrar desde la lista.

const CANVAS := "res://scenes/canvas/canvas.tscn"
var _api: VectopenAPI
var _rows: Node
var _ffl: Node
var _dir := ""
var _cfg_backup := ""

func before() -> void:
	if FileAccess.file_exists("user://vectopen_export.cfg"):
		_cfg_backup = FileAccess.get_file_as_string("user://vectopen_export.cfg")

func after() -> void:
	if _cfg_backup != "":
		var f := FileAccess.open("user://vectopen_export.cfg", FileAccess.WRITE)
		f.store_string(_cfg_backup)

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api
	for c in _api.shapes():
		c.get_parent().remove_child(c)
		c.queue_free()
	_ffl = s.find_child("FileFlowLayout", true, false)
	_rows = s.find_child("ExportRows", true, false)
	var win: Control = s.find_child("Panel_export", true, false)
	win.visible = true
	_dir = ProjectSettings.globalize_path("user://export_panel_test")
	PluginManager._remove_dir(_dir)
	DirAccess.make_dir_recursive_absolute(_dir.path_join("Sub"))
	_rows.library_override = _dir.path_join("Biblioteca")
	await get_tree().process_frame

func after_test() -> void:
	PluginManager._remove_dir(_dir)

func _files(d: String) -> PackedStringArray:
	return DirAccess.get_files_at(d)

func test_columna_instalada_con_filas_por_ambito() -> void:
	assert_object(_rows).is_not_null()
	_api.add_star(Vector2(100, 100), 40)
	_api.add_rect(Vector2(200, 100), Vector2(50, 50))
	_rows.set_scope("artboards")
	assert_int(_rows.rows().size()).is_equal(_api.artboards().size())
	_rows.set_scope("layers")
	assert_int(_rows.rows().size()).is_equal(2)
	assert_str(_rows.rows()[0].format).is_equal("SVG")
	_api.select([_api.shapes()[1]])
	_rows.set_scope("selection")
	assert_int(_rows.rows().size()).is_equal(1)
	# varios seleccionados: 1.ª fila = todos en UN archivo, luego uno por uno
	_api.select(_api.shapes())
	_rows.refresh()
	assert_int(_rows.rows().size()).is_equal(3)
	assert_int(_rows.rows()[0].nodes.size()).is_equal(2)
	var written: PackedStringArray = await _rows.export_rows_to([_rows.rows()[0]], _dir)
	assert_str(written[0].get_file()).is_equal("Selección.svg")
	var data := preload("res://script_gdscript/system/svg_import.gd").parse(FileAccess.get_file_as_string(written[0]))
	assert_int((data["items"] as Array).size()).is_equal(2)

func test_exportar_fila_sin_sobrescribir() -> void:
	_api.add_star(Vector2(100, 100), 40, 5, 0.5)
	_rows.set_scope("layers")
	var row = _rows.rows()[0]
	var a: PackedStringArray = await _rows.export_rows_to([row], _dir)
	var b: PackedStringArray = await _rows.export_rows_to([row], _dir)
	assert_str(a[0].get_file()).is_equal("Estrella.svg")
	assert_str(b[0].get_file()).is_equal("Estrella (2).svg")
	assert_str(_rows._status.get_parsed_text()).contains("Estrella (2).svg")
	# deshacer la exportación = borrar lo escrito
	_rows._on_status_link("undo")
	assert_bool(FileAccess.file_exists(b[0])).is_false()
	assert_bool(FileAccess.file_exists(a[0])).is_true()

func test_formato_y_escala_por_fila_se_recuerdan() -> void:
	var r := _api.add_rect(Vector2(100, 100), Vector2(40, 30))
	_rows.set_scope("layers")
	var row = _rows.rows()[0]
	row._fmt.select(1)          # PNG
	row._fmt.item_selected.emit(1)
	row._scale.select(1)        # 2×
	row._scale.item_selected.emit(1)
	assert_str(String(r.get_meta("export_format"))).is_equal("PNG")
	_rows.refresh()
	assert_str(_rows.rows()[0].format).is_equal("PNG")
	assert_float(_rows.rows()[0].export_scale).is_equal(2.0)

func test_soltar_fila_en_carpeta_y_en_recientes() -> void:
	_api.add_rect(Vector2(100, 100), Vector2(40, 30))
	_rows.set_scope("layers")
	var row = _rows.rows()[0]
	# sobre una carpeta de la lista
	await _ffl._drop_export([row], {"path": _dir.path_join("Sub"), "dir": true})
	assert_bool(_files(_dir.path_join("Sub")).has("Rectángulo.svg")).is_true()
	# vista Archivos sin carpeta debajo → la carpeta que se ve
	_ffl._view_mode = "files"
	_ffl._browse_dir = _dir
	await _ffl._drop_export([row], null)
	assert_bool(_files(_dir).has("Rectángulo.svg")).is_true()
	# vista Recientes → Biblioteca, como VOP
	_ffl._view_mode = "recent"
	await _ffl._drop_export([row], null)
	assert_bool(_files(_dir.path_join("Biblioteca")).has("Rectángulo.vop")).is_true()
	assert_str(row.format).is_equal("SVG")   # la fila conserva su formato

func test_soltar_archivos_en_fila_convierte() -> void:
	_api.add_rect(Vector2(100, 100), Vector2(40, 30))
	_rows.set_scope("layers")
	var row = _rows.rows()[0]
	row.format = "PDF"
	var svg := _dir.path_join("dibujo.svg")
	var f := FileAccess.open(svg, FileAccess.WRITE)
	f.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="50" height="50"><circle cx="25" cy="25" r="20" fill="red"/></svg>')
	f.close()
	var n0 := _api.shapes().size()
	# desde el explorador del sistema: el enrutador decide por la posición
	var handled: bool = _rows._route_os_drop(PackedStringArray([svg]), row.get_global_rect().get_center())
	assert_bool(handled).is_true()
	await get_tree().create_timer(0.3).timeout
	assert_bool(FileAccess.file_exists(_dir.path_join("dibujo.pdf"))).is_true()
	assert_int(_api.shapes().size()).is_equal(n0)   # convertir no toca el documento
	# fuera de las filas no se queda el archivo (se importará)
	assert_bool(_rows._route_os_drop(PackedStringArray([svg]), Vector2(-50, -50))).is_false()

func test_arrastrar_desde_la_lista() -> void:
	var f := FileAccess.open(_dir.path_join("a.svg"), FileAccess.WRITE)
	f.store_string("<svg/>")
	f.close()
	_ffl._view_mode = "files"
	_ffl._browse_dir = _dir
	_ffl.refresh_view()
	await get_tree().create_timer(0.2).timeout
	var tree: Tree = _ffl.recent_files_tree
	var item := tree.get_root().get_first_child()
	while item and not String(item.get_text(1)).ends_with("a.svg"):
		item = item.get_next()
	assert_object(item).is_not_null()
	item.select(1)
	var data = _ffl._recent_drag(Vector2.ZERO)
	assert_str(String(data["type"])).is_equal("recent_file")
	assert_str(String(data["path"]).get_file()).is_equal("a.svg")

func test_barra_lugares_y_favoritos() -> void:
	var sb = _ffl.sidebar
	assert_object(sb).is_not_null()
	assert_bool(sb.places().any(func(p) -> bool: return p[0] == "Inicio")).is_true()
	var cfg_backup := FileAccess.get_file_as_string("user://vectopen_places.cfg") if FileAccess.file_exists("user://vectopen_places.cfg") else ""
	sb.add_favorite(_dir)
	assert_bool(_dir in sb.favorites).is_true()
	# abrir un favorito = vista Archivos en esa carpeta
	sb.open(_dir)
	assert_str(String(_ffl._view_mode)).is_equal("files")
	assert_str(String(_ffl._browse_dir)).is_equal(_dir)
	# soltar una fila de exportación sobre un lugar = exportar ahí
	_api.add_rect(Vector2(100, 100), Vector2(40, 30))
	_rows.set_scope("layers")
	# La fila de ESTE favorito (no la primera): si el usuario ya tenía
	# favoritos guardados, get_child(0) era uno suyo y el test exportaba en su
	# carpeta real (dejaba «Rectángulo (N).svg» en cada ejecución).
	var place_row = null
	for c in sb._fav_box.get_children():
		if "path" in c and String(c.path) == _dir:
			place_row = c
	assert_object(place_row).is_not_null()
	var data := {"type": "export_element", "rows": [_rows.rows()[0]], "format": "SVG"}
	assert_bool(place_row._can_drop_data(Vector2.ZERO, data)).is_true()
	place_row._drop_data(Vector2.ZERO, data)
	await get_tree().create_timer(0.2).timeout
	assert_bool(FileAccess.file_exists(_dir.path_join("Rectángulo.svg"))).is_true()
	sb.remove_favorite(_dir)
	assert_bool(_dir in sb.favorites).is_false()
	if cfg_backup != "":
		var f := FileAccess.open("user://vectopen_places.cfg", FileAccess.WRITE)
		f.store_string(cfg_backup)
