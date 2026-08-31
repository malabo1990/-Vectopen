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

	var overlay := ffl.get_node("BigPreviewOverlay") as Control
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
#                     CONFIGURACIÓN CONTEXTUAL POR FORMATO
# ============================================================================

func test_formato_png_muestra_resolucion_y_color() -> void:
	var panel := _panel()
	var cfg := _format_panel(panel)
	cfg._apply_format("PNG")
	assert_that(cfg.get_node("MarginContainer/VBoxContainer/FormatoHBox/LabelFormato").text).is_equal("Color")
	var option: OptionButton = cfg.get_node("MarginContainer/VBoxContainer/FormatoHBox/OptionFormat")
	assert_int(option.item_count).is_equal(2)
	assert_that(option.get_item_text(0)).is_equal("RGBA")
	assert_that(option.get_item_text(1)).is_equal("RGB")
	var res_row: HBoxContainer = cfg.get_node("MarginContainer/VBoxContainer/ResolucionHBox")
	assert_that(res_row.visible).is_true()

func test_formato_svg_oculta_resolucion() -> void:
	var panel := _panel()
	var cfg := _format_panel(panel)
	cfg._apply_format("SVG")
	assert_that(cfg.get_node("MarginContainer/VBoxContainer/FormatoHBox/LabelFormato").text).is_equal("Estilo")
	var option: OptionButton = cfg.get_node("MarginContainer/VBoxContainer/FormatoHBox/OptionFormat")
	assert_int(option.item_count).is_equal(2)
	assert_that(option.get_item_text(0)).is_equal("Optimizado")
	var res_row: HBoxContainer = cfg.get_node("MarginContainer/VBoxContainer/ResolucionHBox")
	assert_that(res_row.visible).is_false()

func test_formato_pdf_opciones_pagina() -> void:
	var panel := _panel()
	var cfg := _format_panel(panel)
	cfg._apply_format("PDF")
	assert_that(cfg.get_node("MarginContainer/VBoxContainer/FormatoHBox/LabelFormato").text).is_equal("Página")
	var option: OptionButton = cfg.get_node("MarginContainer/VBoxContainer/FormatoHBox/OptionFormat")
	assert_that(option.get_item_text(0)).is_equal("A4")
	var res_row: HBoxContainer = cfg.get_node("MarginContainer/VBoxContainer/ResolucionHBox")
	assert_that(res_row.visible).is_false()

func test_get_config_devuelve_formato_y_opcion() -> void:
	var panel := _panel()
	var cfg := _format_panel(panel)
	cfg._apply_format("JPEG")
	var config: Dictionary = cfg.get_config()
	assert_that(config["format"]).is_equal("JPEG")
	assert_that(config["option"]).is_equal("Alta")
	assert_that(config.has("quantity")).is_true()
	assert_that(config.has("resolution")).is_true()
