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
## La caché devolvía exportaciones viejas (su clave no veía tamaños, radios,
## efectos, textos ni grupos). Exportar es una acción puntual: sin caché.
var cache_enabled: bool = false
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
	# ARRANQUE RÁPIDO: el panel empieza oculto; recorrer y estilizar todos sus
	# nodos al abrir Vectopen costaba ~100 ms. Se estiliza al mostrarse.
	_queue_theme()

## Aplica el tema ya si el panel se ve; si no, al mostrarse (LazyTheme).
func _queue_theme() -> void:
	var obj: Object = self
	if obj is CanvasItem:
		LazyTheme.apply(obj as CanvasItem, _apply_theme)
	else:
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
	_queue_theme()

func _on_color_slot_changed(_slot: String, _color: Color) -> void:
	_queue_theme()

## Tema del panel de archivos con los colores del tema activo (ThemeManager),
## letra uniforme y márgenes interiores. La columna de exportar se estiliza
## sola (ExportRows.restyle) y aquí no se toca.
func _apply_theme() -> void:
	var obj: Object = self
	if not (obj is Control):
		return
	var c = obj
	c.add_theme_stylebox_override("panel", FxUI.flat(FxUI.c("PANEL_BG"), 10, FxUI.c("BORDER"), 6, 6))
	_theme_node(self)
	var rows := get_tree().get_first_node_in_group("vectopen_export_rows") if is_inside_tree() else null
	if rows and rows.has_method("restyle"):
		rows.restyle()

func _theme_node(node: Node) -> void:
	for child in node.get_children():
		if child.is_in_group("vectopen_export_rows"):
			continue
		if child.name == "PlacesSidebar":
			child.call("rebuild")   # se estiliza sola (filas planas)
			continue
		if child is Button and child.name == "BtnClose":
			child.text = "✕"
			child.tooltip_text = "Cerrar"
			child.add_theme_font_size_override("font_size", 13)
			child.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
			child.add_theme_color_override("font_hover_color", FxUI.c("PANEL_TEXT"))
			child.add_theme_stylebox_override("normal", FxUI.flat(Color(0, 0, 0, 0), 6, Color(0, 0, 0, 0), 6, 2))
			child.add_theme_stylebox_override("hover", FxUI.flat(FxUI.c("BUTTON_HOVER"), 6, Color(0, 0, 0, 0), 6, 2))
			child.add_theme_stylebox_override("pressed", FxUI.flat(FxUI.c("BUTTON_PRESSED"), 6, Color(0, 0, 0, 0), 6, 2))
		elif child is Button:
			child.add_theme_font_size_override("font_size", 12)
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
				child.add_theme_color_override(k, FxUI.c("PANEL_TEXT"))
			child.add_theme_color_override("font_disabled_color", FxUI.c("TEXT_SECONDARY"))
			child.add_theme_stylebox_override("normal", FxUI.flat(FxUI.c("INPUT_BG"), 6, FxUI.c("INPUT_BORDER"), 10, 3))
			child.add_theme_stylebox_override("hover", FxUI.flat(FxUI.c("BUTTON_HOVER"), 6, FxUI.c("BORDER_STRONG"), 10, 3))
			child.add_theme_stylebox_override("pressed", FxUI.flat(FxUI.c("BUTTON_PRESSED"), 6, FxUI.c("ACCENT"), 10, 3))
			child.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		elif child is Label:
			child.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
			child.add_theme_font_size_override("font_size", 12)
		elif child is LineEdit:
			ProUIStyle.style_line_edit(child)
			child.add_theme_font_size_override("font_size", 12)
		elif child is HSlider:
			ProUIStyle.style_slider(child)
		elif child is Tree or child is ItemList:
			child.add_theme_font_size_override("font_size", 12)
			child.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
			child.add_theme_color_override("font_selected_color", FxUI.c("PANEL_TEXT"))
			child.add_theme_color_override("title_button_color", FxUI.c("TEXT_SECONDARY"))
			child.add_theme_color_override("guide_color", Color(0, 0, 0, 0))
			child.add_theme_stylebox_override("panel", FxUI.flat(FxUI.c("INPUT_BG"), 6, FxUI.c("BORDER"), 6, 6))
			child.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			child.add_theme_stylebox_override("selected", FxUI.flat(FxUI.c("ACCENT_SOFT"), 4))
			child.add_theme_stylebox_override("selected_focus", FxUI.flat(FxUI.c("ACCENT_SOFT"), 4))
			if child is Tree:
				child.add_theme_stylebox_override("title_button_normal", FxUI.flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 4, 2))
		elif child is PanelContainer and child != self:
			child.add_theme_stylebox_override("panel", FxUI.flat(FxUI.c("SURFACE_RAISED") if _slot("SURFACE_RAISED") else FxUI.c("INPUT_BG"), 8, FxUI.c("BORDER"), 8, 8))
		elif child is BoxContainer:
			child.add_theme_constant_override("separation", 6)
		_theme_node(child)

func _slot(name: String) -> bool:
	var tm := get_node_or_null("/root/ThemeManager")
	return tm != null and tm.Slot.has(name)

const FxUI = preload("res://script_gdscript/ui/panels/effects/fx_ui.gd")

func _setup_drag_and_drop() -> void:
	if not is_inside_tree():
		return
	var win: Window = get_window()
	if not win and get_tree():
		win = get_tree().root
	if win and not win.files_dropped.is_connected(_on_window_files_dropped):
		win.files_dropped.connect(_on_window_files_dropped)

## Quien quiera recibir antes los archivos soltados (el panel de archivos:
## soltar en una fila = convertir, en la biblioteca = añadir) registra aquí
## un Callable(files: PackedStringArray, screen_pos: Vector2) -> bool.
var drop_routers: Array[Callable] = []

## Archivos arrastrados desde el sistema (explorador, escritorio…). En Linux
## SOLO llegan por esta señal de la ventana, no a los controles.
## Última posición del ratón vista en los eventos de la ventana: al soltar
## archivos del sistema es la referencia (el cursor del SO puede ir desfasado).
var last_mouse := Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		last_mouse = (event as InputEventMouse).global_position

func _on_window_files_dropped(files: PackedStringArray) -> void:
	var screen_pos := last_mouse
	for r in drop_routers.duplicate():
		if r.is_valid() and bool(r.call(files, screen_pos)):
			return
	if get_parent() != get_tree().root:
		return   # la copia de la escena del panel no importa: solo el autoload
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	var mgr := ArtboardManager.find(get_tree())
	var drop_pos := Vector2.INF
	if is_instance_valid(canvas) and canvas is Node2D:
		drop_pos = (canvas as Node2D).get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var ab: Node2D = null
	if mgr:
		ab = mgr.artboard_at_point(drop_pos) if drop_pos != Vector2.INF else null
		if ab == null:
			ab = mgr.get_active_artboard()
	var at := ab.to_local(drop_pos) if ab and drop_pos != Vector2.INF else Vector2.INF
	for f in files:
		var res := import_any(f, ab, at)
		if not res["ok"]:
			push_warning(String(res["error"]))
			GlobalEvents.emit_safe("import_error", f.get_extension(), String(res["error"]))
		elif at != Vector2.INF:
			at += Vector2(24, 24)   # varios archivos: en cascada

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

## Exporta `artboard` a `path`. settings: scale (raster), quality 1-100
## (JPEG/WEBP), transparent (PNG/WEBP/SVG/PDF/EPS sin fondo). Devuelve OK o
## el error; emite export_finished / export_error. Usar con await.
func export_artboard(artboard: Node, format: ExportFormat, path: String, settings: Dictionary = {}) -> Error:
	var format_name: String = ExportFormat.keys()[format]
	GlobalEvents.export_started.emit(format_name, path)
	var scale := float(settings.get("scale", 1.0))
	var quality := float(settings.get("quality", 90.0))
	var transparent := bool(settings.get("transparent", false))
	var err: Error = OK
	match format:
		ExportFormat.SVG:
			var sd := VectorExport.collect(artboard, transparent)
			if bool(settings.get("text_curves", false)):
				sd = VectorExport.texts_to_curves(sd)
			err = _write_text(path, VectorExport.to_svg(sd))
		ExportFormat.PDF:
			err = _write_bytes(path, VectorExport.to_pdf(VectorExport.collect(artboard, transparent)))
		ExportFormat.EPS:
			err = _write_text(path, VectorExport.to_eps(VectorExport.collect(artboard, transparent)))
		ExportFormat.PNG:
			err = await artboard.export_to_png(path, scale, transparent)
		ExportFormat.JPEG:
			err = await artboard.export_to_jpeg(path, scale, quality)
		ExportFormat.WEBP:
			err = await artboard.export_to_webp(path, scale, quality, transparent)
		ExportFormat.TSCN, ExportFormat.SCN:
			err = _save_scene(VectorExport.to_godot_scene(VectorExport.collect(artboard, transparent), String(artboard.name)), path)
		ExportFormat.VOP, ExportFormat.JSON:
			err = _write_text(path, JSON.stringify(vop_data(artboard), "\t"))
		_:
			err = ERR_UNAVAILABLE
	if err == OK:
		GlobalEvents.export_finished.emit(format_name, path)
	else:
		var msg := "No se pudo exportar %s (%s)" % [format_name, "formato no soportado" if err == ERR_UNAVAILABLE else error_string(err)]
		push_error(msg)
		GlobalEvents.emit_safe("export_error", format_name, msg)
	return err

# ── exportar elementos sueltos, importar, convertir ─────────────────────────
## Formatos que el panel ofrece (JPEG XL no: Godot no sabe escribirlo).
const EXPORT_FORMATS := ["SVG", "PDF", "EPS", "PNG", "JPEG", "WEBP", "VOP", "TSCN", "SCN"]
const RASTER_FORMATS := ["PNG", "JPEG", "WEBP"]
const IMPORT_EXTS := ["svg", "png", "jpg", "jpeg", "webp", "vop", "tscn", "scn", "glb", "gltf", "vectopen"]

## Exporta solo `nodes` (hijos directos de `artboard`), recortado a su caja.
## Sin nodos = el artboard entero. Usar con await.
func export_nodes(artboard: Node, nodes: Array, format: String, path: String, settings: Dictionary = {}) -> Error:
	var fmt := format.to_upper()
	if not (fmt in EXPORT_FORMATS):
		return ERR_UNAVAILABLE
	if nodes.is_empty():
		return await export_artboard(artboard, ExportFormat[fmt], path, settings)
	GlobalEvents.export_started.emit(fmt, path)
	var transparent := bool(settings.get("transparent", true))
	var data := VectorExport.collect(artboard, true, nodes)
	var box := VectorExport.bounds(data)
	if not box.has_area():
		return ERR_INVALID_DATA
	var err: Error = OK
	match fmt:
		"SVG", "PDF", "EPS":
			var d := VectorExport.offset(data, -box.position, box.size)
			if not transparent and "fill_color" in artboard:
				d["bg"] = artboard.fill_color
			match fmt:
				"SVG": err = _write_text(path, VectorExport.to_svg(VectorExport.texts_to_curves(d) if bool(settings.get("text_curves", false)) else d))
				"PDF": err = _write_bytes(path, VectorExport.to_pdf(d))
				"EPS": err = _write_text(path, VectorExport.to_eps(d))
		"PNG", "JPEG", "WEBP":
			var img: Image = await artboard.render_to_image(float(settings.get("scale", 1.0)), transparent and fmt != "JPEG", nodes, box)
			if img == null:
				err = FAILED
			else:
				var q := clampf(float(settings.get("quality", 90.0)) / 100.0, 0.1, 1.0)
				match fmt:
					"PNG": err = img.save_png(path)
					"JPEG": err = img.save_jpg(path, q)
					"WEBP": err = img.save_webp(path, q < 1.0, q)
		"VOP":
			err = _write_text(path, JSON.stringify(vop_data(artboard, nodes), "\t"))
		"TSCN", "SCN":
			var d2 := VectorExport.offset(data, -box.position, box.size)
			err = _save_scene(VectorExport.to_godot_scene(d2, path.get_file().get_basename()), path)
	if err == OK:
		GlobalEvents.export_finished.emit(fmt, path)
	else:
		GlobalEvents.emit_safe("export_error", fmt, error_string(err))
	return err

## Ruta libre: "nombre.ext", "nombre (2).ext"… (nunca sobrescribe).
static func unique_path(dir: String, base_name: String, ext: String) -> String:
	var b := base_name.strip_edges().validate_filename()
	if b == "":
		b = "export"
	var p := dir.path_join(b + "." + ext)
	var i := 2
	while FileAccess.file_exists(p):
		p = dir.path_join("%s (%d).%s" % [b, i, ext])
		i += 1
	return p

static func extension_for(format: String) -> String:
	return {"JPEG": "jpg"}.get(format.to_upper(), format.to_lower())

## Importa un archivo en `artboard` (UN paso de deshacer). `at`: posición
## en el artboard donde centrarlo (INF = centro). Devuelve {ok, error, node}.
func import_any(path: String, artboard: Node2D, at: Vector2 = Vector2.INF) -> Dictionary:
	var ext := path.get_extension().to_lower()
	var api: VectopenAPI = get_node("/root/PluginManager").api if has_node("/root/PluginManager") else null
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "No existe: " + path}
	if ext == "vectopen" or ext == "vtc":
		if SaveManager:
			SaveManager.open(path)
		return {"ok": true, "error": ""}
	if ext in ["glb", "gltf"]:
		import_3d_model(path, artboard.to_global(at) if at != Vector2.INF else Vector2.INF)
		return {"ok": true, "error": ""}
	if artboard == null or api == null:
		return {"ok": false, "error": "No hay artboard activo"}
	var center: Vector2 = at if at != Vector2.INF else artboard.artboard_size / 2.0
	var node: Node2D = null
	match ext:
		"svg":
			var data := SvgImport.parse(FileAccess.get_file_as_string(path))
			if (data["items"] as Array).is_empty():
				return {"ok": false, "error": "El SVG no tiene nada que importar"}
			node = SvgImport.build(data, path.get_file().get_basename())
			node.position = center - Vector2(data["size"]) / 2.0
			node = api.add(node, artboard)
		"png", "jpg", "jpeg", "webp":
			node = api.add_image(path, center)
		"vop":
			var json = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not (json is Dictionary) or String(json.get("format", "")) != "vop" or not json.has("elements"):
				return {"ok": false, "error": "No es un VOP válido"}
			var g := Node2D.new()
			g.name = path.get_file().get_basename()
			g.set_meta("shape_type", "group")
			CanvasSerializer.instantiate_elements(g, json["elements"])
			# Caja del VOP: `anchor` (esquina) + `size`. Se coloca centrada en
			# el punto de destino; un VOP de artboard entero sin destino va a
			# su sitio original.
			var vsz: Array = json.get("size", [0, 0])
			var anc: Array = json.get("anchor", [0, 0])
			var box_size := Vector2(float(vsz[0]), float(vsz[1]))
			var anchor := Vector2(float(anc[0]), float(anc[1]))
			if at != Vector2.INF or anchor != Vector2.ZERO:
				g.position = center - box_size / 2.0 - anchor
			node = api.add(g, artboard)
		"tscn", "scn":
			var ps := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			if ps == null:
				return {"ok": false, "error": "No se pudo leer la escena"}
			var inst := ps.instantiate()
			var g2 := Node2D.new()
			g2.name = path.get_file().get_basename()
			g2.set_meta("shape_type", "group")
			for c in inst.get_children():
				if c is Node2D and not (String(c.name) in ["ArtboardTitle", "TitleEdit", "Contorno_Stroke"]):
					inst.remove_child(c)
					g2.add_child(c)
			inst.free()
			if g2.get_child_count() == 0:
				g2.free()
				return {"ok": false, "error": "La escena no tiene objetos 2D"}
			if at != Vector2.INF:
				g2.position = at
			node = api.add(g2, artboard)
		_:
			return {"ok": false, "error": "Formato no soportado para importar: .%s" % ext}
	if node == null:
		return {"ok": false, "error": "No se pudo importar " + path.get_file()}
	api.select([node])
	GlobalEvents.import_finished.emit(path)
	return {"ok": true, "error": "", "node": node}

## Convierte un archivo a `format` sin tocar el documento: lo carga en un
## artboard temporal invisible y lo exporta junto al original (o en
## `out_dir`). Una imagen a formato vectorial se VECTORIZA. Usar con await.
## Devuelve {ok, path, error}.
func convert_file(src: String, format: String, out_dir: String = "", settings: Dictionary = {}) -> Dictionary:
	var fmt := format.to_upper()
	var ext := src.get_extension().to_lower()
	var dir := out_dir if out_dir != "" else src.get_base_dir()
	if not (fmt in EXPORT_FORMATS):
		return {"ok": false, "path": "", "error": "Formato de salida no soportado"}
	var tmp: Node2D = Node2D.new()
	tmp.set_script(load("res://scripts/canvas/artboard.gd"))
	tmp.name = "_ConvertTmp"
	tmp.visible = false
	tmp.position = Vector2(-1e6, -1e6)
	add_child(tmp)
	tmp.remove_from_group("artboards")
	var error := ""
	match ext:
		"svg":
			var data := SvgImport.parse(FileAccess.get_file_as_string(src))
			tmp.artboard_size = data["size"]
			tmp.fill_color = Color(1, 1, 1, 0)
			var g := SvgImport.build(data)
			for c in g.get_children():
				g.remove_child(c)
				tmp.add_child(c)
			g.free()
		"png", "jpg", "jpeg", "webp":
			var img := Image.load_from_file(src)
			if img == null:
				error = "No se pudo leer la imagen"
			else:
				tmp.artboard_size = Vector2(img.get_size())
				tmp.fill_color = Color(1, 1, 1, 0)
				var sp := Sprite2D.new()
				sp.texture = ImageTexture.create_from_image(img)
				sp.centered = false
				tmp.add_child(sp)
				if not (fmt in RASTER_FORMATS):
					var g2: Node2D = await _vectorize_sprite(sp, String(settings.get("preset", "Ilustración")))
					if g2 == null:
						error = "No se pudo vectorizar la imagen"
					else:
						tmp.remove_child(sp)
						sp.free()
						tmp.add_child(g2)
		"vop":
			var json = JSON.parse_string(FileAccess.get_file_as_string(src))
			if json is Dictionary and json.has("elements"):
				var sz: Array = json.get("size", [800, 600])
				var anc2: Array = json.get("anchor", [0, 0])
				tmp.artboard_size = Vector2(float(sz[0]), float(sz[1]))
				var holder := Node2D.new()
				holder.position = -Vector2(float(anc2[0]), float(anc2[1]))
				tmp.add_child(holder)
				CanvasSerializer.instantiate_elements(holder, json["elements"])
			else:
				error = "No es un VOP válido"
		_:
			error = "No se puede convertir .%s" % ext
	var out := ""
	if error == "":
		out = unique_path(dir, src.get_file().get_basename(), extension_for(fmt))
		var err: Error = await export_artboard(tmp, ExportFormat[fmt], out, settings)
		if err != OK:
			error = error_string(err)
	tmp.queue_free()
	return {"ok": error == "", "path": out if error == "" else "", "error": error}

## Vectoriza un Sprite2D sin pasar por el historial (conversión de archivos).
func _vectorize_sprite(sp: Sprite2D, preset: String) -> Node2D:
	if not ClassDB.class_exists("VectorizerJob"):
		return null
	var VecPanel = load("res://script_gdscript/ui/panels/effects/vectorize_panel.gd")
	var opts: Dictionary = (VecPanel.PRESETS.get(preset, VecPanel.PRESETS["Ilustración"]) as Dictionary).duplicate()
	opts["hierarchical"] = "stacked"
	opts["path_precision"] = 3
	var src: String = VecPanel._tmp_path("conv_in.png")
	var out: String = VecPanel._tmp_path("conv_out.svg")
	sp.texture.get_image().save_png(src)
	var j = ClassDB.instantiate("VectorizerJob")
	j.start_vectorize(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(out), opts,
		false, false, ProjectSettings.globalize_path("user://"))
	while not j.is_done():
		await get_tree().process_frame
	var svg := FileAccess.get_file_as_string(out)
	VecPanel._cleanup([src, out])
	return VecPanel.build_group(sp, svg) if svg != "" else null

## Objetos que solo se ven al rasterizar (shaders, filtros, efectos): para
## avisar al exportar en SVG/PDF/EPS.
func vector_warnings(artboard: Node) -> PackedStringArray:
	return VectorExport.collect(artboard)["warnings"]

static func _write_text(path: String, text: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK

static func _write_bytes(path: String, data: PackedByteArray) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(data)
	f.close()
	return OK

## Escena de Godot PORTABLE (.tscn texto / .scn binario): solo nodos nativos
## (Polygon2D, Line2D, Label, Sprite2D), sin scripts de Vectopen, así se ve
## en cualquier proyecto de Godot. Para editar con todo, VOP.
static func _save_scene(root: Node2D, path: String) -> Error:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	return err if err != OK else ResourceSaver.save(packed, path)

static func _own_all(root: Node, n: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own_all(root, c)

## VOP: formato VECTORIAL propio, sin pérdidas (figuras paramétricas,
## efectos, filtros, shaders, texto enriquecido). JSON legible versionado.
## Mismo serializador que el archivo .vectopen.
## Con `nodes` (selección): `size` es el de la SELECCIÓN y `anchor` dónde
## estaba su esquina en el artboard; la capa render va relativa a esa caja.
## Así al importar ocupa exactamente lo mismo, con la selección como eje.
func vop_data(artboard: Node, nodes: Array = []) -> Dictionary:
	var elements: Array = []
	if nodes.is_empty():
		elements = CanvasSerializer.serialize_elements(artboard)
	else:
		for n in nodes:
			var e := CanvasSerializer._serialize_element(n)
			if not e.is_empty():
				elements.append(e)
	var size: Vector2 = artboard.get("artboard_size") if "artboard_size" in artboard else Vector2(800, 600)
	var anchor := Vector2.ZERO
	var render_data := VectorExport.collect(artboard, not nodes.is_empty(), nodes)
	if not nodes.is_empty():
		var box := VectorExport.bounds(render_data)
		if box.has_area():
			anchor = box.position
			size = box.size
			render_data = VectorExport.offset(render_data, -anchor, size)
	return {"format": "vop", "version": 2, "generator": "Vectopen %s" % ProjectSettings.get_setting("application/config/version", ""),
		"name": String(artboard.name if nodes.is_empty() else nodes[0].name), "size": [size.x, size.y],
		# esquina de la caja en coordenadas de `elements` (0,0 = artboard entero)
		"anchor": [anchor.x, anchor.y],
		# Vista resuelta para cualquier lector (ver docs/*/reference/VOP_FORMAT.md)
		# texto como curvas: otros programas lo ven con la fuente exacta
		"render": VectorExport.to_render_json(VectorExport.texts_to_curves(render_data)),
		# Datos nativos sin pérdidas (los lee Vectopen)
		"elements": elements}

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
	
	# VOP v2: elementos completos (mismo serializador que .vectopen).
	if vop_data is Dictionary and int(vop_data.get("version", 1)) >= 2 and vop_data.has("elements"):
		var before := target_artboard.get_child_count()
		CanvasSerializer.instantiate_elements(target_artboard, vop_data["elements"])
		var added: Array = target_artboard.get_children().slice(before)
		var hm := get_node_or_null("/root/HistoryManager")
		if hm and not added.is_empty():
			hm.register_action("Importar VOP")
			hm.add_do(func() -> void:
				for n in added:
					if is_instance_valid(n) and n.get_parent() == null:
						target_artboard.add_child(n))
			hm.add_undo(func() -> void:
				for n in added:
					if is_instance_valid(n) and n.get_parent() == target_artboard:
						target_artboard.remove_child(n))
			hm.commit()
		GlobalEvents.import_finished.emit(file_path)
		return
	# VOP v1 (antiguo: solo nombres de capas)
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
	return VectorExport.to_svg(VectorExport.collect(artboard))

const VectorExport = preload("res://script_gdscript/system/vector_export.gd")
const SvgImport = preload("res://script_gdscript/system/svg_import.gd")
const CanvasSerializer = preload("res://scripts/canvas/canvas_serializer.gd")
