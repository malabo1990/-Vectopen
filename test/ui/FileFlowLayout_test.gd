extends GdUnitTestSuite

const PANEL_SCENE := "res://scenes/ui/panel_export.tscn"
const EMPTY_MSG := "No documents exist"

func _panel() -> Node:
	var panel: Node = auto_free(load(PANEL_SCENE).instantiate())
	add_child(panel)
	return panel

func _ffl(panel: Node) -> Node:
	return panel.get_node("HBoxContainer/FileFlowLayout")

func _tree(panel: Node) -> Tree:
	return panel.get_node("HBoxContainer/FileFlowLayout/FileLibraryPanel/VBoxContainer/RecentFilesTree")

func _label(panel: Node) -> Label:
	return panel.get_node("HBoxContainer/FileFlowLayout/FileLibraryPanel/VBoxContainer/ViewHeader/ViewLabel")

func _format_panel(panel: Node) -> Node:
	return panel.get_node("HBoxContainer/FileFlowLayout/ExportPanel")

func test_preview_al_seleccionar_archivo() -> void:
	var panel := _panel()
	var ffl := _ffl(panel)
	var test_path := "user://test_preview.png"
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	img.save_png(test_path)

	ffl._handle_item_meta({"path": test_path, "dir": false})

	var preview: PanelContainer = panel.get_node("HBoxContainer/FileFlowLayout/PreviewPanel")
	assert_that(preview.visible).is_true()
	var tex: TextureRect = preview.get_node("MarginContainer/PreviewTexture")
	assert_object(tex.texture).is_not_null()
	DirAccess.remove_absolute(test_path)

func test_preview_espacio_muestra_overlay_centrado() -> void:
	var panel := _panel()
	var ffl := _ffl(panel)
	var test_path := "user://test_preview.png"
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLUE)
	img.save_png(test_path)
	ffl._handle_item_meta({"path": test_path, "dir": false})

	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	ffl._input(ev)

	# en su propia capa, por encima del panel de exportar y de todo lo demás
	var layer := ffl.get_node("BigPreviewLayer") as CanvasLayer
	assert_int(layer.layer).is_greater(50)
	var overlay := layer.get_node("BigPreviewOverlay") as Control
	assert_that(overlay.visible).is_true()
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_SPACE
	ev2.pressed = true
	ffl._input(ev2)
	assert_that(overlay.visible).is_false()
	DirAccess.remove_absolute(test_path)

func test_navegacion_historial() -> void:
	var panel := _panel()
	var ffl := _ffl(panel)
	ffl.set_view("files")
	var raiz: String = ffl._browse_dir
	assert_that(raiz).is_not_empty()
	ffl._navigate_dir(raiz.get_base_dir())
	assert_that(ffl._browse_dir).is_equal(raiz.get_base_dir())
	ffl._on_back_pressed()
	assert_that(ffl._browse_dir).is_equal(raiz)
	ffl._on_forward_pressed()
	assert_that(ffl._browse_dir).is_equal(raiz.get_base_dir())
	ffl._on_up_pressed()
	assert_that(ffl._browse_dir).is_equal(raiz.get_base_dir().get_base_dir())

func test_grid_iconos_no_nulos() -> void:
	var panel := _panel()
	var ffl := _ffl(panel)
	ffl.set_view("files")
	ffl.set_details_mode(false)
	var grid: ItemList = panel.get_node("HBoxContainer/FileFlowLayout/FileLibraryPanel/VBoxContainer/RecentFilesGrid")
	assert_that(grid.visible).is_true()
	assert_int(grid.item_count).is_greater_equal(1)
	var with_icon := 0
	for i in grid.item_count:
		if grid.get_item_icon(i):
			with_icon += 1
	assert_int(with_icon).is_greater_equal(1)

# ============================================================================
#                           VISTAS DEL PANEL DE ARCHIVOS
# ============================================================================

func test_ready_muestra_titulo_recent() -> void:
	var panel := _panel()
	assert_that(_label(panel).text).is_equal(tr("Recent Files"))
	var root := _tree(panel).get_root()
	assert_object(root).is_not_null()
	assert_that(root.get_text(1)).is_equal(tr("Recent Files"))

func test_set_view_recent_actualiza_titulo() -> void:
	var panel := _panel()
	_ffl(panel).set_view("recent")
	assert_that(_label(panel).text).is_equal(tr("Recent Files"))

func test_set_view_files_actualiza_titulo_y_lista() -> void:
	var panel := _panel()
	_ffl(panel).set_view("files")
	assert_that(_label(panel).text).is_equal(tr("Files"))
	var root := _tree(panel).get_root()
	assert_object(root).is_not_null()
	assert_that(root.get_text(1)).is_not_empty()
	# Siempre hay al menos 1 item: la carpeta tiene contenido o el mensaje de vacio
	assert_int(root.get_child_count()).is_greater_equal(1)

func test_set_view_recover_actualiza_titulo() -> void:
	var panel := _panel()
	_ffl(panel).set_view("recover")
	assert_that(_label(panel).text).is_equal(tr("Recovery"))
	var root := _tree(panel).get_root()
	assert_object(root).is_not_null()
	assert_that(root.get_text(1)).is_equal(tr("Recovery"))
	assert_int(root.get_child_count()).is_greater_equal(1)

func test_set_view_recover_sin_archivos_muestra_mensaje() -> void:
	var panel := _panel()
	var paths: PackedStringArray = _ffl(panel)._get_recoverable_files()
	_ffl(panel).set_view("recover")
	var root := _tree(panel).get_root()
	if paths.is_empty():
		assert_int(root.get_child_count()).is_equal(1)
		assert_that(root.get_child(0).get_text(1)).is_equal(tr(EMPTY_MSG))
	else:
		assert_int(root.get_child_count()).is_greater_equal(1)

func test_set_view_recent_sin_archivos_muestra_mensaje() -> void:
	var panel := _panel()
	var files = RecentFilesManager.get_files() if RecentFilesManager else []
	_ffl(panel).set_view("recent")
	var root := _tree(panel).get_root()
	if files.is_empty():
		assert_int(root.get_child_count()).is_equal(1)
		assert_that(root.get_child(0).get_text(1)).is_equal(tr(EMPTY_MSG))
	else:
		assert_int(root.get_child_count()).is_greater_equal(1)

func test_modo_invalido_no_cambia_vista() -> void:
	var panel := _panel()
	_ffl(panel).set_view("otra_cosa")
	assert_that(_label(panel).text).is_equal(tr("Recent Files"))

# ============================================================================
#                        ARCHIVOS EXTERNOS (ESCRITORIO)
# ============================================================================

func test_archivo_externo_se_agrega_a_seccion_desktop() -> void:
	var panel := _panel()
	var ffl := _ffl(panel)
	var test_path := "user://test_external.svg"
	var f := FileAccess.open(test_path, FileAccess.WRITE)
	f.store_string("<svg/>")
	f.close()

	ffl._handle_external_files(PackedStringArray([test_path]), Vector2.ZERO)

	assert_that(ffl._external_files.has(test_path)).is_true()
	var root := _tree(panel).get_root()
	var has_desktop := false
	for child in root.get_children():
		if child.get_text(1) == tr("Desktop (%d)") % 1:
			has_desktop = true
	assert_that(has_desktop).is_true()
	DirAccess.remove_absolute(test_path)

# ============================================================================
#        COLUMNA EXPORTAR (filas por elemento, diseño «smart export»)
# ============================================================================
# Sustituye a la antigua columna de formato (Estilo/Resolución/Página), que
# no llegaba al exportador.

func _rows(panel: Node) -> Node:
	return _format_panel(panel).find_child("ExportRows", true, false)

func test_columna_exportar_sustituye_al_formulario() -> void:
	var panel := _panel()
	var rows := _rows(panel)
	assert_object(rows).is_not_null()
	assert_object(_format_panel(panel).find_child("BtnExport", true, false)).is_null()
	assert_object(rows.find_child("ExportChecked", true, false)).is_not_null()

func test_formatos_sin_jpeg_xl_y_escala_solo_en_imagen() -> void:
	var panel := _panel()
	var rows := _rows(panel)
	assert_bool("JPEG XL" in rows.FORMATS).is_false()
	for f in ["SVG", "PNG", "JPEG", "WEBP", "PDF", "EPS", "VOP", "TSCN", "SCN"]:
		assert_bool(f in rows.FORMATS).override_failure_message(f).is_true()
	var row = rows.ExportRow.new()
	row.owner_panel = rows
	row.build("x", "rectangle")
	auto_free(row)
	for f in ["PNG", "JPEG", "WEBP"]:
		row.format = f
		row._sync_scale()
		assert_bool(row._scale.visible).override_failure_message(f).is_true()
	for f in ["SVG", "PDF", "EPS", "VOP"]:
		row.format = f
		row._sync_scale()
		assert_bool(row._scale.visible).override_failure_message(f).is_false()

func test_destino_por_defecto_no_es_de_windows() -> void:
	var panel := _panel()
	var rows := _rows(panel)
	assert_bool(String(rows.dest_dir).begins_with("C:")).is_false()
	assert_bool(DirAccess.dir_exists_absolute(rows.dest_dir)).is_true()
