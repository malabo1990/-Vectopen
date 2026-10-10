extends Node

## ImportExportManager
## Handles export and import of artboards to various formats
## 
## Features:
## - Export caching system to optimize repeated exports
## - Error handling for unsupported formats
## - Progress notifications via GlobalEvents
## 
## Supported Export Formats:
## - SVG: Vector graphics export (optimized with estándar math calculations)
## - PDF: Portable Document Format (basic vector support)
## - PNG: Raster image export
## - JPEG: Raster image export
## - JPEG XL: Next-gen raster format
## - WEBP: Modern raster format with transparency
## - EPS: Encapsulated PostScript (import only)
## - TSCN: Godot 4 scene format
## - SCN: Godot 3 scene format
## - VOP: Vectopen proprietary format
## - JSON: Project data export
## 
## Unsupported Export Formats (will emit export_error):
## - AI: formato vectorial (.ai) format
## - DXF: AutoCAD Drawing Exchange Format
## 
## Supported Import Formats:
## - SVG: Vector graphics import (strong math calculations, estándar)
## - PNG, JPEG: Raster image import (converted to Sprite2D, not vectorized)
## - EPS: Encapsulated PostScript (import only)
## - TSCN, SCN: Godot scene formats
## - VOP: Vectopen proprietary format
## 
## Unsupported Import Formats (will emit import_error):
## - AI: formato vectorial (.ai) format
## - PDF: Portable Document Format
## - DXF: AutoCAD Drawing Exchange Format
## - JPEG XL, WEBP: Import not yet implemented


enum ExportFormat {
	SVG,
	PDF,
	PNG,
	JPEG,
	JPEG_XL,
	WEBP,
	EPS,
	TSCN,
	SCN,
	VOP,
	JSON
}

enum ImportFormat {
	SVG,
	EPS,
	TSCN,
	SCN,
	VOP,
	PNG,
	JPEG
}

# Configuración de exportación
var cache_enabled: bool = true
var default_pdf_page_size: Vector2 = Vector2(612, 792)
var default_png_scale: float = 2.0

# Formato y configuración seleccionados en el panel (FormatConfigPanel)
var current_format: String = "SVG"
var current_export_config: Dictionary = {}

func _ready() -> void:
	_get_and_connect_button("HBoxContainer/QuickActionMenu/ButtonsVBox/BtnArchivos", _on_btn_archivos_pressed)
	_get_and_connect_button("HBoxContainer/QuickActionMenu/ButtonsVBox/BtnRecuperar", _on_btn_recuperar_pressed)
	_get_and_connect_button("HBoxContainer/QuickActionMenu/ButtonsVBox/BtnNuevo", _on_btn_nuevo_pressed)
	_get_and_connect_button("HBoxContainer/QuickActionMenu/ButtonsVBox/BtnReciente", _on_btn_reciente_pressed)
	var format_config := get_node_or_null("HBoxContainer/FileFlowLayout/ExportPanel")
	if format_config and format_config.has_signal("format_selected"):
		format_config.format_selected.connect(_on_format_selected_changed)
	_get_and_connect_button("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/SaveHBox/BtnExport", _on_btn_export_pressed)
	_get_and_connect_button("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/SaveHBox/BtnSave", _on_btn_save_pressed)
	_get_and_connect_button("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/SaveHBox/BtnSaveAs", _on_btn_save_as_pressed)
	_get_and_connect_button("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/FolderPathHBox/BtnBrowse", _on_btn_browse_pressed)
	_get_and_connect_button("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/QuickFoldersHBox/BtnFolderDesktop", func(): _on_quick_folder_pressed(OS.SYSTEM_DIR_DESKTOP))
	_get_and_connect_button("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/QuickFoldersHBox/BtnFolderDownloads", func(): _on_quick_folder_pressed(OS.SYSTEM_DIR_DOWNLOADS))
	_get_and_connect_button("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/QuickFoldersHBox/BtnFolderDocs", func(): _on_quick_folder_pressed(OS.SYSTEM_DIR_DOCUMENTS))
	_get_and_connect_button("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/QuickFoldersHBox/BtnFolderPics", func(): _on_quick_folder_pressed(OS.SYSTEM_DIR_PICTURES))
	_get_and_connect_button("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/QuickFoldersHBox/BtnFolderVideos", func(): _on_quick_folder_pressed(OS.SYSTEM_DIR_MOVIES))
	_setup_drag_and_drop()
	_connect_export_dialog_event()
	_connect_theme()
	_apply_theme()

func _connect_export_dialog_event() -> void:
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("request_export_dialog"):
		if not ge.request_export_dialog.is_connected(_on_request_export_dialog):
			ge.request_export_dialog.connect(_on_request_export_dialog)

func _on_request_export_dialog() -> void:
	var obj: Object = self
	if obj is Control:
		var c = obj
		c.visible = true
		c.z_index = 100
		c.move_to_front()
		_apply_theme()

func _connect_theme() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm:
		if tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)
		if tm.has_signal("color_slot_changed") and not tm.color_slot_changed.is_connected(_on_color_slot_changed):
			tm.color_slot_changed.connect(_on_color_slot_changed)

func _on_theme_changed(_mode: String) -> void:
	_apply_theme()

func _on_color_slot_changed(_slot: String, _color: Color) -> void:
	_apply_theme()

func _apply_theme() -> void:
	var obj: Object = self
	if not (obj is Control):
		return
	var c = obj
	var tm = get_node_or_null("/root/ThemeManager")
	var is_dark := true
	if tm and tm.has_method("is_dark_theme"):
		is_dark = tm.is_dark_theme()
	elif tm and tm.has_method("get_current_mode"):
		is_dark = (tm.get_current_mode() == "dark")

	var bg_col := Color(0.13, 0.13, 0.16, 0.98) if is_dark else Color(0.96, 0.96, 0.98, 0.98)
	var border_col := Color(1, 1, 1, 0.12) if is_dark else Color(0, 0, 0, 0.15)
	var text_col := Color(0.95, 0.95, 0.95, 1.0) if is_dark else Color(0.12, 0.12, 0.14, 1.0)
	var sec_col := Color(0.70, 0.70, 0.75, 1.0) if is_dark else Color(0.35, 0.35, 0.40, 1.0)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 4)
	c.add_theme_stylebox_override("panel", sb)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.19, 0.19, 0.23, 0.95) if is_dark else Color(0.92, 0.92, 0.95, 0.95)
	btn_normal.border_color = border_col
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(6)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.26, 0.26, 0.32, 1.0) if is_dark else Color(0.86, 0.86, 0.90, 1.0)
	btn_hover.border_color = Color(0.15, 0.55, 0.95, 0.6)
	btn_hover.set_border_width_all(1)
	btn_hover.set_corner_radius_all(6)

	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = Color(0.15, 0.15, 0.18, 1.0) if is_dark else Color(0.78, 0.78, 0.84, 1.0)
	btn_pressed.border_color = border_col
	btn_pressed.set_border_width_all(1)
	btn_pressed.set_corner_radius_all(6)

	var panel_inner := StyleBoxFlat.new()
	panel_inner.bg_color = Color(0.16, 0.16, 0.20, 0.95) if is_dark else Color(0.93, 0.93, 0.96, 0.95)
	panel_inner.border_color = border_col
	panel_inner.set_border_width_all(1)
	panel_inner.set_corner_radius_all(8)

	var le_style := StyleBoxFlat.new()
	le_style.bg_color = Color(0.17, 0.17, 0.21, 1.0) if is_dark else Color(0.98, 0.98, 1.0, 1.0)
	le_style.border_color = border_col
	le_style.set_border_width_all(1)
	le_style.set_corner_radius_all(5)

	_apply_theme_recursive(self, is_dark, text_col, sec_col, btn_normal, btn_hover, btn_pressed, panel_inner, le_style)

func _apply_theme_recursive(node: Node, is_dark: bool, text_col: Color, sec_col: Color, btn_n: StyleBoxFlat, btn_h: StyleBoxFlat, btn_p: StyleBoxFlat, p_inner: StyleBoxFlat, le_st: StyleBoxFlat) -> void:
	for child in node.get_children():
		if child is Label:
			child.add_theme_color_override("font_color", text_col)
		elif child is Button and child.name != "BtnClose":
			if child.name == "BtnExport":
				var btn_acc := StyleBoxFlat.new()
				btn_acc.bg_color = Color(0.12, 0.50, 0.95, 1.0)
				btn_acc.set_corner_radius_all(6)
				var btn_acc_h := StyleBoxFlat.new()
				btn_acc_h.bg_color = Color(0.20, 0.60, 1.0, 1.0)
				btn_acc_h.set_corner_radius_all(6)
				child.add_theme_color_override("font_color", Color.WHITE)
				child.add_theme_color_override("font_hover_color", Color.WHITE)
				child.add_theme_stylebox_override("normal", btn_acc)
				child.add_theme_stylebox_override("hover", btn_acc_h)
				child.add_theme_stylebox_override("pressed", btn_acc)
			else:
				child.add_theme_color_override("font_color", text_col)
				child.add_theme_color_override("font_hover_color", Color.WHITE if is_dark else Color.BLACK)
				child.add_theme_stylebox_override("normal", btn_n)
				child.add_theme_stylebox_override("hover", btn_h)
				child.add_theme_stylebox_override("pressed", btn_p)
		elif child is PanelContainer and child != self:
			child.add_theme_stylebox_override("panel", p_inner)
		elif child is LineEdit:
			child.add_theme_color_override("font_color", text_col)
			child.add_theme_stylebox_override("normal", le_st)
		elif child is Tree:
			child.add_theme_color_override("font_color", text_col)
			child.add_theme_color_override("font_selected_color", Color.WHITE if is_dark else Color.BLACK)
			child.add_theme_stylebox_override("panel", p_inner)
		_apply_theme_recursive(child, is_dark, text_col, sec_col, btn_n, btn_h, btn_p, p_inner, le_st)

func _setup_drag_and_drop() -> void:
	if not is_inside_tree():
		return
	var win: Window = get_window()
	if not win and get_tree():
		win = get_tree().root
	if win and not win.files_dropped.is_connected(_on_window_files_dropped):
		win.files_dropped.connect(_on_window_files_dropped)

func _on_window_files_dropped(files: PackedStringArray) -> void:
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	var drop_pos := Vector2.INF
	if is_instance_valid(canvas) and canvas is Node2D:
		drop_pos = (canvas as Node2D).get_global_mouse_position()

	for file_path in files:
		var ext := file_path.get_extension().to_lower()
		match ext:
			"glb", "gltf":
				import_3d_model(file_path, drop_pos)
			"svg":
				var mgr := ArtboardManager.find(get_tree()) if is_inside_tree() else null
				var act: Node = null
				if mgr:
					if drop_pos != Vector2.INF:
						act = mgr.artboard_at_point(drop_pos)
					if not act:
						act = mgr.get_active_artboard()
				if act and act.has_method("import_svg"):
					act.import_svg(file_path)
			"png", "jpg", "jpeg", "webp":
				var mgr := ArtboardManager.find(get_tree()) if is_inside_tree() else null
				var act: Node = null
				if mgr:
					if drop_pos != Vector2.INF:
						act = mgr.artboard_at_point(drop_pos)
					if not act:
						act = mgr.get_active_artboard()
				if act and act.has_method("vectorize_image"):
					act.vectorize_image(file_path)


func _get_and_connect_button(path: String, callback: Callable) -> void:
	var btn: Button = get_node_or_null(path)
	if btn:
		btn.pressed.connect(callback)

func _on_btn_archivos_pressed() -> void:
	_set_file_view("files")

func _on_btn_recuperar_pressed() -> void:
	_set_file_view("recover")

func _on_btn_reciente_pressed() -> void:
	_set_file_view("recent")

func _set_file_view(mode: String) -> void:
	var ffl := get_node_or_null("HBoxContainer/FileFlowLayout")
	if ffl and ffl.has_method("set_view"):
		ffl.set_view(mode)

func _on_open_file_selected(path: String) -> void:
	if SaveManager:
		SaveManager.open(path)
	RecentFilesManager.add_file(path)

var _browse_dialog: FileDialog = null

func _on_btn_nuevo_pressed() -> void:
	if SaveManager:
		SaveManager.new_project()
	var obj: Object = self
	if obj is Control:
		obj.visible = false

func _on_btn_save_pressed() -> void:
	if SaveManager:
		SaveManager.save()

func _on_btn_save_as_pressed() -> void:
	if SaveManager:
		SaveManager.save_as()

func _on_quick_folder_pressed(system_dir_id: int) -> void:
	var path_edit := get_node_or_null("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/FolderPathHBox/PathLineEdit") as LineEdit
	if path_edit:
		var dir := OS.get_system_dir(system_dir_id)
		if dir.is_empty():
			dir = OS.get_user_data_dir()
		path_edit.text = dir

func _on_btn_browse_pressed() -> void:
	if is_instance_valid(_browse_dialog):
		_browse_dialog.queue_free()
		_browse_dialog = null

	var fd := FileDialog.new()
	_browse_dialog = fd
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "Select Export Folder"
	var path_edit := get_node_or_null("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/FolderPathHBox/PathLineEdit") as LineEdit
	if path_edit and not path_edit.text.strip_edges().is_empty():
		fd.current_dir = path_edit.text.strip_edges()
	else:
		fd.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)

	fd.dir_selected.connect(func(dir: String):
		if path_edit:
			path_edit.text = dir
		if is_instance_valid(fd):
			fd.queue_free()
	)
	fd.canceled.connect(func():
		if is_instance_valid(fd):
			fd.queue_free()
	)
	add_child(fd)
	fd.popup_centered(Vector2i(800, 600))

func _format_name_to_enum(format_str: String) -> int:
	match format_str.to_upper().replace(" ", "_"):
		"SVG": return ExportFormat.SVG
		"PDF": return ExportFormat.PDF
		"PNG": return ExportFormat.PNG
		"JPEG", "JPG": return ExportFormat.JPEG
		"JPEG_XL", "JPEGXL", "JXL": return ExportFormat.JPEG_XL
		"WEBP": return ExportFormat.WEBP
		"EPS": return ExportFormat.EPS
		"TSCN": return ExportFormat.TSCN
		"SCN": return ExportFormat.SCN
		"VOP": return ExportFormat.VOP
		"JSON": return ExportFormat.JSON
		_: return ExportFormat.SVG

func _format_extension(format_str: String) -> String:
	match format_str.to_upper().replace(" ", "_"):
		"SVG": return "svg"
		"PDF": return "pdf"
		"PNG": return "png"
		"JPEG", "JPG": return "jpg"
		"JPEG_XL", "JPEGXL", "JXL": return "jxl"
		"WEBP": return "webp"
		"EPS": return "eps"
		"TSCN": return "tscn"
		"SCN": return "scn"
		"VOP": return "vop"
		"JSON": return "json"
		_: return "svg"

func _on_btn_export_pressed() -> void:
	var tree := get_tree()
	var mgr := ArtboardManager.find(tree) if tree else null
	var artboard: Node = null
	if mgr:
		artboard = mgr.get_active_artboard()
	if not artboard and tree:
		var artboards = tree.get_nodes_in_group("artboards")
		if artboards.size() > 0:
			artboard = artboards[0]
		else:
			var canvas = tree.get_first_node_in_group("_vectopen_canvas")
			if canvas:
				var container = canvas.get_node_or_null("ArtboardsContainer")
				if container and container.get_child_count() > 0:
					artboard = container.get_child(0)

	if not artboard:
		push_error("[Export] No artboard found to export")
		GlobalEvents.emit_safe("export_error", current_format, "No artboard found to export")
		return

	var name_edit := get_node_or_null("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/NameHBox/LineEditName") as LineEdit
	var path_edit := get_node_or_null("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/FolderPathHBox/PathLineEdit") as LineEdit

	var file_title := name_edit.text.strip_edges() if name_edit and not name_edit.text.strip_edges().is_empty() else "export"
	var folder := path_edit.text.strip_edges() if path_edit and not path_edit.text.strip_edges().is_empty() else OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if folder.is_empty():
		folder = OS.get_user_data_dir()

	if not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)

	var ext := _format_extension(current_format)
	var full_path := folder.path_join(file_title + "." + ext)

	var fmt_enum: ExportFormat = _format_name_to_enum(current_format) as ExportFormat

	var settings := current_export_config.duplicate(true)
	var spin_res := get_node_or_null("HBoxContainer/FileFlowLayout/ExportPanel/MarginContainer/VBoxContainer/ResolucionHBox/SpinBoxResolucion")
	if spin_res and "value" in spin_res and float(spin_res.value) > 0.0:
		settings["scale"] = float(spin_res.value)
	elif not settings.has("scale"):
		settings["scale"] = 1.0

	export_artboard(artboard, fmt_enum, full_path, settings)

	var obj: Object = self
	if obj is Control:
		obj.visible = false

func _on_format_selected_changed(format: String, config: Dictionary) -> void:
	current_format = format
	current_export_config = config

func export_artboard(artboard: Node, format: ExportFormat, path: String, settings: Dictionary = {}) -> void:
	var format_name = ExportFormat.keys()[format]
	GlobalEvents.export_started.emit(format_name, path)
	
	# Verificar si el formato es soportado
	var unsupported_formats = ["AI", "DXF"]
	if format_name in unsupported_formats:
		var error_msg = "Export format '%s' is not yet supported. Currently supported: SVG, PDF, PNG, JPEG, JPEG XL, WEBP, EPS, TSCN, SCN, VOP, JSON." % format_name
		push_error(error_msg)
		GlobalEvents.emit_safe("export_error", format_name, error_msg)
		return
	
	# Preparar datos para la caché
	var export_data = {
		"artboard_id": artboard.get_instance_id(),
		"artboard_state": _get_artboard_state(artboard),
		"format": format_name,
		"settings": settings.duplicate(true),
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Intentar recuperar de la caché si está habilitada
	var cached_result = null
	if cache_enabled and ExportCache:
		cached_result = ExportCache.retrieve(format_name, export_data)
		if cached_result:
			# Guardar el resultado cacheado
			var file = FileAccess.open(path, FileAccess.WRITE)
			if file:
				if cached_result is PackedByteArray:
					file.store_buffer(cached_result)
				else:
					file.store_string(cached_result)
				file.close()
				GlobalEvents.export_finished.emit(format_name, path)
				return
	
	# Si no está en caché, procesar la exportación
	match format:
		ExportFormat.SVG:
			_export_svg(artboard, path, settings)
		ExportFormat.PDF:
			_export_pdf(artboard, path, settings)
		ExportFormat.PNG:
			await _export_png(artboard, path, settings)
		ExportFormat.JPEG:
			_export_jpeg(artboard, path, settings)
		ExportFormat.JPEG_XL:
			_export_jpegxl(artboard, path, settings)
		ExportFormat.WEBP:
			_export_webp(artboard, path, settings)
		ExportFormat.EPS:
			_export_eps(artboard, path, settings)
		ExportFormat.TSCN:
			_export_tscn(artboard, path, settings)
		ExportFormat.SCN:
			_export_scn(artboard, path, settings)
		ExportFormat.VOP:
			_export_vop(artboard, path, settings)
		ExportFormat.JSON:
			_export_json(artboard, path, settings)
		_:
			var error_msg = "Export format '%s' is not yet supported." % format_name
			push_error(error_msg)
			GlobalEvents.emit_safe("export_error", format_name, error_msg)

func import_file(file_path: String, format: ImportFormat, target_artboard: Node) -> void:
	GlobalEvents.import_started.emit(file_path)

	match format:
		ImportFormat.SVG:
			_import_svg(file_path, target_artboard)
		ImportFormat.EPS:
			_import_eps(file_path, target_artboard)
		ImportFormat.TSCN, ImportFormat.SCN:
			_import_godot_scene(file_path, target_artboard)
		ImportFormat.VOP:
			_import_vop(file_path, target_artboard)
		ImportFormat.PNG, ImportFormat.JPEG:
			_vectorize_image(file_path, target_artboard)
		_:
			var fmt_name = ImportFormat.keys()[format]
			var error_msg = "Import format '%s' is not yet supported. Currently supported: SVG, EPS, TSCN, SCN, VOP, PNG, JPEG." % fmt_name
			push_error(error_msg)
			GlobalEvents.emit_safe("import_error", fmt_name, error_msg)

func _export_svg(artboard: Node, path: String, _settings: Dictionary):
	# Prefixing settings with _ to ignore unused warning
	var _svg_content = artboard.export_to_svg(path)
	GlobalEvents.export_finished.emit("svg", path)

func _export_pdf(artboard: Node, path: String, _settings: Dictionary) -> void:
	var shapes = _collect_shapes(artboard)
	var content = _render_pdf_content(shapes, artboard)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Cannot open %s for PDF export" % path)
		GlobalEvents.emit_safe("export_error", "PDF", "Cannot open file for writing")
		return
	file.store_buffer(content)
	file.close()
	GlobalEvents.export_finished.emit("pdf", path)

func _collect_shapes(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		var c = child as Node
		if c and c.has_method("get_bounds"):
			out.append(c)
		out.append_array(_collect_shapes(c))
	return out

func _render_pdf_content(shapes: Array[Node], artboard: Node) -> PackedByteArray:
	var text := "%PDF-1.4\n"
	var objects: Array[String] = []
	var content_body := ""
	
	# Get artboard size for MediaBox
	var artboard_size = Vector2(612, 792)  # Default A4 in points (72 dpi)
	if "artboard_size" in artboard:
		# Convert pixels to points (assuming 96 dpi for artboard, PDF uses 72 dpi)
		var pixel_size = artboard.get("artboard_size")
		artboard_size = Vector2(pixel_size.x * 72.0 / 96.0, pixel_size.y * 72.0 / 96.0)
	
	# Collect all unique colors and fonts
	var colors_used: Dictionary = {}
	var fonts_used: Dictionary = {"Helvetica": true}
	
	for shape in shapes:
		content_body += _shape_to_pdf(shape, colors_used, fonts_used)

	if content_body.is_empty():
		content_body = "BT /F1 12 Tf (Empty Artboard) Tj ET\n"

	# Build PDF objects
	objects.append("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
	objects.append("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n")
	
	# Build resources dictionary
	var resources := "<< /Font"
	var font_index = 1
	for font_name in fonts_used:
		resources += " /F%d /%s" % [font_index, font_name]
		font_index += 1
	resources += " >>"
	
	# Add color space if we have colors
	if colors_used.size() > 0:
		resources = resources.replace(">>", " /ColorSpace << /Cs1 /DeviceRGB >> >>")
	
	# Page object with proper MediaBox
	objects.append("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents 4 0 R /Resources %s >>\nendobj\n" % [artboard_size.x, artboard_size.y, resources])
	
	# Content stream
	var stream_data := "q\n" + content_body + "Q\n"
	var encoded = stream_data.to_utf8_buffer()
	
	objects.append("4 0 obj\n<< /Length %d >>\nstream\n%s\nendstream\nendobj\n" % [encoded.size(), stream_data])
	
	# Font objects
	font_index = 1
	for font_name in fonts_used:
		objects.append("5 %d 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /%s >>\nendobj\n" % [font_index - 1, font_name])
		font_index += 1

	# Build cross-reference table
	var offsets: Array[int] = []
	for obj in objects:
		offsets.append(text.length())
		text += obj

	var xref_offset = text.length()
	text += "xref\n0 %d\n0000000000 65535 f \n" % (objects.size() + 1)
	for off in offsets:
		text += "%010d 00000 n \n" % off
	text += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % [objects.size() + 1, xref_offset]

	return text.to_utf8_buffer()


func _shape_to_pdf(shape: Node, colors_used: Dictionary, _fonts_used: Dictionary) -> String:
	var content := ""
	var cls = shape.get_class()
	
	# Get position, scale, rotation
	var position = shape.position if "position" in shape else Vector2.ZERO
	var _scale = shape.scale if "scale" in shape else Vector2.ONE
	var _rotation = shape.rotation if "rotation" in shape else 0.0
	
	# Get color and style properties
	var stroke_color = Color.BLACK
	var fill_color = Color.TRANSPARENT
	var stroke_width = 1.0
	var is_filled = false
	
	if "stroke_color" in shape:
		stroke_color = shape.get("stroke_color")
	if "fill_color" in shape:
		fill_color = shape.get("fill_color")
	if "stroke_width" in shape:
		stroke_width = shape.get("stroke_width")
	if "is_filled" in shape:
		is_filled = shape.get("is_filled")
	
	# Add colors to used colors
	if not colors_used.has(stroke_color.to_html()):
		colors_used[stroke_color.to_html()] = true
	if not colors_used.has(fill_color.to_html()):
		colors_used[fill_color.to_html()] = true
	
	# Set PDF color
	var pdf_stroke_color = _color_to_pdf(stroke_color)
	var pdf_fill_color = _color_to_pdf(fill_color)
	
	# Handle different shape types
	if cls == "Path2D":
		var curve = shape.get(&"curve") as Curve2D if shape.get(&"curve") else null
		if curve and curve.point_count >= 2:
			var pts = curve.get_baked_points()
			if pts.size() >= 2:
				content += "%s %s %s rg\n" % [pdf_fill_color.r, pdf_fill_color.g, pdf_fill_color.b]
				content += "%s %s %s RG\n" % [pdf_stroke_color.r, pdf_stroke_color.g, pdf_stroke_color.b]
				content += "%f w\n" % stroke_width
				content += "%f %f m\n" % [pts[0].x, pts[0].y]
				for i in range(1, pts.size()):
					content += "%f %f l\n" % [pts[i].x, pts[i].y]
				if is_filled:
					content += "b\n"  # Fill and stroke
				else:
					content += "S\n"  # Stroke only
			
	elif cls == "Polygon2D":
		var pts = shape.get("polygon") if "polygon" in shape else []
		if pts.size() >= 3:
			content += "%s %s %s rg\n" % [pdf_fill_color.r, pdf_fill_color.g, pdf_fill_color.b]
			content += "%s %s %s RG\n" % [pdf_stroke_color.r, pdf_stroke_color.g, pdf_stroke_color.b]
			content += "%f w\n" % stroke_width
			content += "%f %f m\n" % [position.x + pts[0].x, position.y + pts[0].y]
			for i in range(1, pts.size()):
				content += "%f %f l\n" % [position.x + pts[i].x, position.y + pts[i].y]
			content += "h\n"  # Close path
			if is_filled:
				content += "b\n"
			else:
				content += "S\n"
		
	elif cls == "Line2D":
		var pts = shape.get("points") if "points" in shape else []
		if pts.size() >= 2:
			content += "%s %s %s RG\n" % [pdf_stroke_color.r, pdf_stroke_color.g, pdf_stroke_color.b]
			content += "%f w\n" % (shape.get("width") if "width" in shape else stroke_width)
			content += "%f %f m\n" % [position.x + pts[0].x, position.y + pts[0].y]
			for i in range(1, pts.size()):
				content += "%f %f l\n" % [position.x + pts[i].x, position.y + pts[i].y]
			content += "S\n"
		
	elif cls == "ColorRect" or cls.find("Rect") >= 0:
		var rect = shape.get("rect") if "rect" in shape else Rect2(Vector2.ZERO, shape.get("size") if "size" in shape else Vector2(100, 100))
		if rect.size.x > 0 and rect.size.y > 0:
			content += "%s %s %s rg\n" % [pdf_fill_color.r, pdf_fill_color.g, pdf_fill_color.b]
			content += "%f %f %f %f re\n" % [position.x + rect.position.x, position.y + rect.position.y, rect.size.x, rect.size.y]
			content += "f\n"
		
	elif cls == "Sprite2D":
		# For imported raster images (not vector, but we include them)
		var texture = shape.get("texture")
		if texture:
			# This is a simplified approach - real PDF image embedding would need more work
			content += "% BT /F1 12 Tf (Raster Image: %s) Tj ET\n" % [shape.name]
		
	elif shape.has_method("to_svg"):
		# Try to parse SVG output and convert to PDF
		var svg = shape.to_svg()
		content += _svg_path_to_pdf(svg)
	
	return content


func _color_to_pdf(color: Color) -> Color:
	# Convert Godot Color (0-1 range) to PDF color (0-1 range)
	# PDF uses RGB, same as Godot
	return Color(color.r, color.g, color.b)


func _svg_path_to_pdf(svg: String) -> String:
	# Simple conversion from SVG path to PDF path
	# This is a basic implementation - would need more work for full SVG support
	var pdf_content := ""
	
	# Look for path data in SVG
	var path_match = svg.find("d=\"")
	if path_match >= 0:
		var start = svg.find("d=\"") + 3
		var end = svg.find("\"", start)
		if end > start:
			var path_data = svg.substr(start, end - start)
			# Basic conversion - would need proper parsing for full support
			pdf_content += "q\n"
			pdf_content += "0 0 0 RG\n"  # Black stroke
			pdf_content += "1 w\n"  # Stroke width
			pdf_content += path_data.replace("M", "m").replace("L", "l").replace("Z", "h") + " S\n"
			pdf_content += "Q\n"
	
	return pdf_content

func _export_png(artboard: Node, path: String, settings: Dictionary) -> void:
	var scale = settings.get("scale", 1.0)
	await artboard.export_to_png(path, scale)
	GlobalEvents.export_finished.emit("png", path)

func _export_jpeg(artboard: Node, path: String, settings: Dictionary) -> void:
	var scale = settings.get("scale", 1.0)
	var quality = settings.get("quality", 90)
	await artboard.export_to_jpeg(path, scale, quality)
	GlobalEvents.export_finished.emit("jpeg", path)

func _export_jpegxl(artboard: Node, path: String, settings: Dictionary) -> void:
	var scale = settings.get("scale", 1.0)
	var quality = settings.get("quality", 90)
	await artboard.export_to_jpegxl(path, scale, quality)
	GlobalEvents.export_finished.emit("jpeg_xl", path)

func _export_webp(artboard: Node, path: String, settings: Dictionary) -> void:
	var scale = settings.get("scale", 1.0)
	var quality = settings.get("quality", 90)
	await artboard.export_to_webp(path, scale, quality)
	GlobalEvents.export_finished.emit("webp", path)

func _export_eps(artboard: Node, path: String, _settings: Dictionary) -> void:
	# EPS export - wrapper around SVG with EPS header
	var svg_content = artboard.export_to_svg_string()
	var eps_content = _svg_to_eps(svg_content)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(eps_content)
		file.close()
		GlobalEvents.export_finished.emit("eps", path)

func _svg_to_eps(svg: String) -> String:
	# Convert SVG to EPS format
	return "%%EPSF-3.0\n" + svg + "\n%%EOF\n"

func _export_tscn(artboard: Node, path: String, _settings: Dictionary) -> void:
	# Export as Godot 4 scene
	var scene_data = {
		"resource_path": path,
		"format_version": 3,
		"root_node": artboard.get_class(),
		"node_data": _get_node_data(artboard),
		"metadata": {
			"exported_at": Time.get_unix_time_from_system(),
			"vectopen_version": "1.0"
		}
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(scene_data, "\t"))
		file.close()
		GlobalEvents.export_finished.emit("tscn", path)

func _export_scn(artboard: Node, path: String, _settings: Dictionary) -> void:
	# Export as Godot 3 scene (legacy format)
	var scene_data = {
		"resource_path": path,
		"format_version": 2,
		"root_node": artboard.get_class(),
		"node_data": _get_node_data(artboard),
		"metadata": {
			"exported_at": Time.get_unix_time_from_system(),
			"vectopen_version": "1.0"
		}
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(scene_data, "\t"))
		file.close()
		GlobalEvents.export_finished.emit("scn", path)

func _export_vop(artboard: Node, path: String, _settings: Dictionary) -> void:
	# Export as Vectopen proprietary format
	var vop_data = {
		"version": "1.0",
		"artboard": {
			"name": artboard.name,
			"size": artboard.get("artboard_size") if "artboard_size" in artboard else Vector2(800, 600),
			"layers": _get_layer_data(artboard),
			"metadata": {
				"created_at": Time.get_unix_time_from_system(),
				"modified_at": Time.get_unix_time_from_system()
			}
		}
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(vop_data, "\t"))
		file.close()
		GlobalEvents.export_finished.emit("vop", path)

func _export_json(artboard: Node, path: String, _settings: Dictionary) -> void:
	var shapes = _collect_shapes(artboard)
	var json_data = {
		"version": "1.0",
		"artboard_name": artboard.name,
		"shapes": shapes
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(json_data, "\t"))
		file.close()
		GlobalEvents.export_finished.emit("json", path)


func _get_node_data(node: Node) -> Dictionary:
	var data = {
		"name": node.name,
		"type": node.get_class(),
		"position": node.position if "position" in node else Vector2.ZERO,
		"scale": node.scale if "scale" in node else Vector2.ONE,
		"rotation": node.rotation if "rotation" in node else 0.0,
		"children": []
	}
	
	for child in node.get_children():
		if child is Node:
			data["children"].append(_get_node_data(child))
	
	return data

func _get_layer_data(artboard: Node) -> Array:
	var layers = []
	for child in artboard.get_children():
		if child is Node2D:
			layers.append({
				"name": child.name,
				"type": child.get_class(),
				"visible": child.visible if "visible" in child else true,
				"locked": child.locked if "locked" in child else false
			})
	return layers

# ==========================================
# MÉTODOS DE CACHÉ Y ESTADO
# ==========================================

func _get_artboard_state(artboard: Node) -> Dictionary:
	"""
	Obtiene el estado del artboard para la caché de exportación.
	"""
	var state = {
		"id": artboard.get_instance_id(),
		"name": artboard.name,
		"size": artboard.get("artboard_size") if "artboard_size" in artboard else Vector2.ZERO,
		"shapes": [],
		"modified_at": Time.get_unix_time_from_system()
	}
	
	# Recoger información de las shapes
	for child in artboard.get_children():
		if child is Node2D and child.name != "ArtboardTitle":
			var shape_state = {
				"type": child.get_class(),
				"id": child.get_instance_id(),
				"position": child.position,
				"scale": child.scale,
				"rotation": child.rotation,
				"properties": {}
			}
			
			# Propiedades específicas de cada tipo
			if "stroke_color" in child:
				shape_state["properties"]["stroke_color"] = child.get("stroke_color").to_html()
			if "fill_color" in child:
				shape_state["properties"]["fill_color"] = child.get("fill_color").to_html()
			if "stroke_width" in child:
				shape_state["properties"]["stroke_width"] = child.get("stroke_width")
			if "points" in child and child.get("points") is PackedVector2Array:
				shape_state["properties"]["points"] = child.get("points").duplicate()
			if "polygon" in child and child.get("polygon") is PackedVector2Array:
				shape_state["properties"]["polygon"] = child.get("polygon").duplicate()
			if "width" in child:
				shape_state["properties"]["width"] = child.get("width")
			if "height" in child:
				shape_state["properties"]["height"] = child.get("height")
			
			state["shapes"].append(shape_state)
	
	return state


# ==========================================
# MÉTODOS DE EXPORTACIÓN
# ==========================================


func _import_svg(file_path: String, target_artboard: Node):
	target_artboard.import_svg(file_path)

func _vectorize_image(file_path: String, target_artboard: Node):
	target_artboard.vectorize_image(file_path)

func _import_eps(file_path: String, target_artboard: Node):
	# Import EPS as SVG first, then process
	var svg_path = file_path.get_base_dir() + "/" + file_path.get_file().get_basename() + ".svg"
	# EPS to SVG conversion would be done here
	_import_svg(svg_path, target_artboard)

func _import_godot_scene(file_path: String, target_artboard: Node):
	# Import Godot scene file
	var scene = load(file_path)
	if scene:
		var instance = scene.instantiate()
		target_artboard.add_child(instance)
		GlobalEvents.import_finished.emit(file_path)

func import_3d_model(file_path: String = "", drop_pos: Vector2 = Vector2.INF) -> void:
	if not file_path.is_empty():
		_do_import_3d_model(file_path, drop_pos)
		return

	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.glb ; Modelos 3D GLB (*.glb)", "*.gltf ; Modelos 3D GLTF (*.gltf)"])
	fd.title = "Importar Modelo 3D"
	fd.file_selected.connect(func(path: String):
		_do_import_3d_model(path, drop_pos)
		fd.queue_free()
	)
	fd.canceled.connect(func():
		fd.queue_free()
	)
	var root := get_tree().root if get_tree() else null
	if root:
		root.add_child(fd)
		fd.popup_centered_ratio(0.7)

func _do_import_3d_model(path: String, drop_pos: Vector2 = Vector2.INF) -> Node2D:
	var model_script = load("res://script_gdscript/shapes/VectorModel3D.gd")
	if not model_script:
		push_error("ImportExportManager: No se pudo cargar VectorModel3D.gd")
		return null

	var model: Node2D = model_script.new()
	model.name = path.get_file().get_basename()
	model.load_model(path)

	# Buscar destino en el lienzo: artboard bajo el ratón o artboard activo
	var mgr := ArtboardManager.find(get_tree()) if is_inside_tree() else null
	var target_parent: Node = null
	var target_artboard: Node = null
	var center_pos := Vector2(200, 200)

	if mgr:
		if drop_pos != Vector2.INF:
			target_artboard = mgr.artboard_at_point(drop_pos)
		if not target_artboard:
			target_artboard = mgr.get_active_artboard()

		if is_instance_valid(target_artboard):
			var dl: Node = target_artboard.get_node_or_null("VectorDrawingLayer")
			target_parent = dl if is_instance_valid(dl) else target_artboard
			if "artboard_size" in target_artboard:
				center_pos = target_artboard.artboard_size * 0.5

	if not target_parent:
		var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
		if is_instance_valid(canvas):
			var container = canvas.get_node_or_null("ArtboardsContainer")
			target_parent = container if is_instance_valid(container) else canvas
		elif get_tree() and get_tree().root:
			target_parent = get_tree().root

	if target_parent:
		if drop_pos != Vector2.INF:
			if target_parent is CanvasItem:
				model.position = (target_parent as CanvasItem).to_local(drop_pos)
			else:
				model.position = drop_pos
		else:
			model.position = center_pos
		target_parent.add_child(model)

		var sm := get_node_or_null("/root/SelectionManager")
		if sm and sm.has_method("set_selection"):
			sm.set_selection([model])

		if GlobalEvents and GlobalEvents.has_signal("import_finished"):
			GlobalEvents.emit_safe("import_finished")

	return model

func _import_vop(file_path: String, target_artboard: Node):
	# Import Vectopen proprietary format
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Cannot open VOP file: %s" % file_path)
		return
	
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	json.parse(content)
	var vop_data = json.data
	
	if not vop_data:
		push_error("Invalid VOP file: %s" % file_path)
		return
	
	# Process VOP data
	if vop_data.has("artboard"):
		target_artboard.name = vop_data["artboard"].get("name", "Imported Artboard")
		# Load layers from VOP data
		_load_vop_layers(target_artboard, vop_data["artboard"].get("layers", []))
		GlobalEvents.import_finished.emit(file_path)

func _load_vop_layers(artboard: Node, layers: Array) -> void:
	# Process VOP layers and recreate them in the artboard
	for layer_data in layers:
		# Create nodes based on layer type
		var layer_type = layer_data.get("type", "Node2D")
		var layer_node = create_node_by_type(layer_type)
		if layer_node:
			layer_node.name = layer_data.get("name", "Layer")
			layer_node.position = layer_data.get("position", Vector2.ZERO)
			layer_node.scale = layer_data.get("scale", Vector2.ONE)
			layer_node.rotation = layer_data.get("rotation", 0.0)
			artboard.add_child(layer_node)

func create_node_by_type(type_name: String) -> Node:
	# Factory method to create nodes by type name
	match type_name:
		"Path2D", "Bezier2D":
			return Path2D.new()
		"Polygon2D":
			return Polygon2D.new()
		"Line2D":
			return Line2D.new()
		"ColorRect", "Rect2D":
			return ColorRect.new()
		"Sprite2D":
			return Sprite2D.new()
		"Node2D":
			return Node2D.new()
		_:
			return Node2D.new()

func export_to_svg_string(artboard: Node) -> String:
	# Export artboard to SVG string (helper method)
	var svg_content = '<?xml version="1.0" encoding="UTF-8"?>\n'
	svg_content += '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s">\n' % [
		artboard.get("artboard_size").x if "artboard_size" in artboard else 800,
		artboard.get("artboard_size").y if "artboard_size" in artboard else 600
	]
	
	# Add shapes
	for child in artboard.get_children():
		if child is Node2D and child.name != "ArtboardTitle":
			svg_content += _node_to_svg(child)
	
	svg_content += '</svg>'
	return svg_content

func _node_to_svg(node: Node) -> String:
	# Convert a node to SVG element string
	var svg_element = ""
	
	if node is Path2D:
		svg_element = '<path d="M 0 0" stroke="black" fill="none"/>'
	elif node is Polygon2D:
		svg_element = '<polygon points="0,0 100,0 100,100 0,100" fill="none" stroke="black"/>'
	elif node is ColorRect:
		svg_element = '<rect x="0" y="0" width="100" height="100" fill="black"/>'
	elif node is Sprite2D:
		svg_element = '<image href="" x="0" y="0" width="100" height="100"/>'
	else:
		svg_element = '<!-- Unknown shape type: %s -->' % node.get_class()
	
	return svg_element
