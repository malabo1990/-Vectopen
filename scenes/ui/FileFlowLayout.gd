extends HBoxContainer
class_name FileFlowLayout

signal element_dropped_internally(element: Variant, position: Vector2)
signal export_requested(element: Node, format: String, destination: String)

## Drag & drop de archivos desde el escritorio: Godot entrega los drops del
## sistema operativo como {"files": PackedStringArray([...])} en can_drop_data /
## drop_data. Aquí se aceptan, se emiten por elemento y se muestran sus datos
## (nombre, fecha de modificación, tamaño) en una sección "Desktop" del árbol.

var recent_files_tree: Tree
var format_selector: OptionButton
var recent_search_bar: LineEdit
var path_line_edit: LineEdit
var btn_browse: Button
var file_dialog: FileDialog
var view_label: Label
var _icon_list: ItemList
var _thumbnail_cache: Dictionary = {}
var _thumb_mutex := Mutex.new()
var _thumb_queue: Array[String] = []
var _thumb_ready: Array = []
var _thumb_stop := false
var _thumb_task_id := -1
var _dir_cache: Dictionary = {}

const DEFAULT_EXPORT_FORMATS := ["SVG", "PNG", "PDF", "JPEG"]
const SUPPORTED_FILTERS := ["*.svg, *.png, *.jpg, *.jpeg, *.pdf ; Archivos soportados"]
const EMPTY_MSG := "No documents exist"
const FIRST_BATCH := 12
const CHUNK_SIZE := 30

var _external_files: PackedStringArray = []
var _view_mode: String = "recent"
var _browse_dir: String = ""
var _details_mode: bool = true
var _nav_history: Array[String] = []
var _nav_index: int = -1
var _btn_back: Button
var _btn_forward: Button
var _pending_tree_items: Array = []
var _pending_grid_items: Array = []
var _pending_total := 0
var _current_root: TreeItem
var _desktop_section: TreeItem
var _preview_panel: PanelContainer
var _preview_texture: TextureRect
var _big_overlay: Control
var _big_texture: TextureRect
var _selected_path := ""
var _preview_cache: Dictionary = {}

func _ready() -> void:
	recent_files_tree = get_node_or_null("FileLibraryPanel/VBoxContainer/RecentFilesTree") as Tree
	recent_search_bar = get_node_or_null("FileLibraryPanel/VBoxContainer/SearchBar") as LineEdit
	view_label = get_node_or_null("FileLibraryPanel/VBoxContainer/ViewHeader/ViewLabel") as Label
	if not view_label:
		view_label = get_node_or_null("FileLibraryPanel/VBoxContainer/ViewLabel") as Label
	_icon_list = get_node_or_null("FileLibraryPanel/VBoxContainer/RecentFilesGrid") as ItemList
	format_selector = get_node_or_null("ExportPanel/VBoxContainer/FormatSelector") as OptionButton
	path_line_edit = _get_export_node("FolderPathHBox/PathLineEdit") as LineEdit
	btn_browse = _get_export_node("FolderPathHBox/BtnBrowse") as Button
	file_dialog = get_node_or_null("FileDialog") as FileDialog

	if not recent_files_tree:
		push_warning("FileFlowLayout: RecentFilesTree no encontrado")
		return

	_setup_ui()
	_setup_drag_and_drop()
	_setup_quick_actions()
	_setup_view_toggle()
	_wire_close_button()
	_wire_export_toggle()
	_preview_panel = get_node_or_null("PreviewPanel") as PanelContainer
	if _preview_panel:
		_preview_texture = _preview_panel.get_node_or_null("MarginContainer/PreviewTexture") as TextureRect
	_build_big_overlay()
	DirAccess.make_dir_recursive_absolute(THUMB_CACHE_DIR)
	_load_recent_files()
	_refresh_translated_texts()

func _exit_tree() -> void:
	_thumb_mutex.lock()
	_thumb_stop = true
	_thumb_mutex.unlock()
	if _thumb_task_id != -1 and not WorkerThreadPool.is_group_task_completed(_thumb_task_id):
		WorkerThreadPool.wait_for_group_task_completion(_thumb_task_id)
	_thumb_task_id = -1

	if recent_search_bar:
		recent_search_bar.text_changed.connect(_on_recent_search_text_changed)
	if btn_browse:
		btn_browse.pressed.connect(_on_browse_pressed)
	if file_dialog:
		file_dialog.dir_selected.connect(_on_dir_selected)
		file_dialog.file_selected.connect(_on_file_selected)
	if format_selector:
		format_selector.item_selected.connect(_on_format_selected)

	_ensure_file_dialog()

func _get_export_node(suffix: String) -> Node:
	var node := get_node_or_null("ExportPanel/VBoxContainer/" + suffix)
	if not node:
		node = get_node_or_null("ExportPanel/MarginContainer/VBoxContainer/" + suffix)
	return node

func _setup_ui() -> void:
	if format_selector:
		for format in DEFAULT_EXPORT_FORMATS:
			format_selector.add_item(format)
		format_selector.selected = 0

	recent_files_tree.columns = 4
	recent_files_tree.set_column_title(0, "Thumbnail")
	recent_files_tree.set_column_title(1, "Name")
	recent_files_tree.set_column_title(2, "Date")
	recent_files_tree.set_column_title(3, "Size")
	recent_files_tree.set_column_expand(0, false)
	recent_files_tree.set_column_expand(1, true)
	recent_files_tree.set_column_expand(2, false)
	recent_files_tree.set_column_expand(3, false)

func _setup_drag_and_drop() -> void:
	recent_files_tree.connect("item_selected", _on_recent_file_selected)
	recent_files_tree.connect("cell_selected", _on_recent_cell_selected)
	_attach_drag_handler(recent_files_tree, "_recent")

	var export_tree := _get_export_node("ExportLayersTree") as Tree
	if export_tree:
		_attach_drag_handler(export_tree, "_export")
	if _icon_list:
		_attach_drag_handler(_icon_list, "_grid")
		_icon_list.item_selected.connect(_on_grid_item_selected)
		_icon_list.item_activated.connect(_on_grid_item_selected)

func _attach_drag_handler(node: Node, method_prefix: String) -> void:
	if not node or not ("drag_handler" in node):
		return
	node.set("drag_handler", self)
	node.set("method_prefix", method_prefix)

# ============================================================================
#                      BOTONES RÁPIDOS (acciones del panel)
# ============================================================================

func _setup_quick_actions() -> void:
	var buttons_vbox := get_node_or_null("../QuickActionMenu/MarginContainer/ButtonsVBox")
	if buttons_vbox:
		_wire_button(buttons_vbox.get_node_or_null("BtnArchivos"), _on_btn_archivos_pressed)
		_wire_button(buttons_vbox.get_node_or_null("BtnRecuperar"), _on_btn_recuperar_pressed)
		_wire_button(buttons_vbox.get_node_or_null("BtnReciente"), _on_btn_reciente_pressed)
		_wire_button(buttons_vbox.get_node_or_null("BtnNuevo"), _on_btn_nuevo_pressed)
		_wire_button(buttons_vbox.get_node_or_null("BtnSave"), _on_btn_save_pressed)
		_wire_button(buttons_vbox.get_node_or_null("BtnSaveAs"), _on_btn_save_as_pressed)
	_wire_button(_get_export_node("SaveHBox/BtnSave"), _on_btn_save_pressed)
	_wire_button(_get_export_node("SaveHBox/BtnSaveAs"), _on_btn_save_as_pressed)

func _wire_button(btn: Button, handler: Callable) -> void:
	_set_button_contrast(btn)
	_connect_button(btn, handler)

func _wire_close_button() -> void:
	var btn := get_node_or_null("../../CloseLayer/BtnClose") as Button
	if btn:
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			btn.add_theme_color_override(color_name, Color.WHITE)
		_connect_button(btn, _on_close_pressed)

func _on_close_pressed() -> void:
	var root := get_parent().get_parent()
	if root:
		root.visible = false

func _wire_export_toggle() -> void:
	var btn := get_node_or_null("../../../keyboard/PanelContainer/MarginContainer/Contenido/Button2") as Button
	if not btn:
		return
	if "target_panel" in btn and btn.get("target_panel") is Node:
		return
	_connect_button(btn, _on_export_toggle_pressed)

func _on_export_toggle_pressed() -> void:
	var root := get_parent().get_parent()
	if root:
		root.visible = not root.visible

func _set_button_contrast(btn: Button) -> void:
	if not btn:
		return
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(color_name, Color.BLACK)

func _connect_button(btn: Button, handler: Callable) -> void:
	if btn and not btn.pressed.is_connected(handler):
		btn.pressed.connect(handler)

# ============================================================================
#                 VISTA DETALLES / ICONO (estilo Explorador de Windows)
# ============================================================================

func _setup_view_toggle() -> void:
	var view_bar := get_node_or_null("FileLibraryPanel/VBoxContainer/ViewBar/HBoxContainer")
	if not view_bar:
		return
	_wire_button(view_bar.get_node_or_null("detalles"), _on_details_pressed)
	_wire_button(view_bar.get_node_or_null("icono"), _on_icon_pressed)
	_wire_button(view_bar.get_node_or_null("BtnBack"), _on_back_pressed)
	_wire_button(view_bar.get_node_or_null("BtnForward"), _on_forward_pressed)
	_wire_button(view_bar.get_node_or_null("BtnUp"), _on_up_pressed)
	_btn_back = view_bar.get_node_or_null("BtnBack") as Button
	_btn_forward = view_bar.get_node_or_null("BtnForward") as Button
	var zoom_slider := view_bar.get_node_or_null("ZoomSlider") as HSlider
	if zoom_slider:
		zoom_slider.value_changed.connect(_on_zoom_changed)
		_on_zoom_changed(zoom_slider.value)
	_update_nav_buttons()

# ============================================================================
#                  NAVEGACIÓN DE CARPETAS (atrás/adelante/subir)
# ============================================================================

func _update_nav_buttons() -> void:
	if _btn_back:
		_btn_back.disabled = _nav_index <= 0
	if _btn_forward:
		_btn_forward.disabled = _nav_index >= _nav_history.size() - 1

func _on_back_pressed() -> void:
	if _nav_index > 0:
		_nav_index -= 1
		_browse_dir = _nav_history[_nav_index]
		_rebuild_tree.call_deferred(_current_filter())
		_update_nav_buttons()

func _on_forward_pressed() -> void:
	if _nav_index < _nav_history.size() - 1:
		_nav_index += 1
		_browse_dir = _nav_history[_nav_index]
		_rebuild_tree.call_deferred(_current_filter())
		_update_nav_buttons()

func _on_up_pressed() -> void:
	var parent := _browse_dir.get_base_dir()
	if not parent.is_empty() and parent != _browse_dir:
		_navigate_dir(parent)

func _on_zoom_changed(value: float) -> void:
	var zoom := int(value)
	var text_size := clampi(int(zoom / 4.0), 8, 28)
	if _icon_list:
		_icon_list.icon_mode = ItemList.ICON_MODE_TOP
		_icon_list.fixed_icon_size = Vector2i(zoom, zoom)
		_icon_list.fixed_column_width = zoom + 56
		_icon_list.add_theme_font_size_override("font_size", text_size)
	recent_files_tree.add_theme_font_size_override("font_size", text_size)
	recent_files_tree.set_column_custom_minimum_width(0, zoom)

func _on_details_pressed() -> void:
	set_details_mode(true)

func _on_icon_pressed() -> void:
	set_details_mode(false)

func set_details_mode(details: bool) -> void:
	_details_mode = details
	if _icon_list:
		_icon_list.visible = not details
	recent_files_tree.visible = details
	if details:
		recent_files_tree.columns = 4
		recent_files_tree.set_column_title(0, "Thumbnail")
		recent_files_tree.set_column_title(1, "Name")
		recent_files_tree.set_column_title(2, "Date")
		recent_files_tree.set_column_title(3, "Size")
		recent_files_tree.set_column_expand(0, false)
		recent_files_tree.set_column_expand(1, true)
		recent_files_tree.set_column_expand(2, false)
		recent_files_tree.set_column_expand(3, false)
		recent_files_tree.set_column_custom_minimum_width(0, 0)
	else:
		recent_files_tree.columns = 2
		recent_files_tree.set_column_title(0, "")
		recent_files_tree.set_column_title(1, "Name")
		recent_files_tree.set_column_expand(0, false)
		recent_files_tree.set_column_expand(1, true)
		recent_files_tree.set_column_custom_minimum_width(0, 64)
	_rebuild_tree(_current_filter())

func _on_btn_archivos_pressed() -> void:
	set_view("files")

func _on_btn_recuperar_pressed() -> void:
	set_view("recover")

func _on_btn_reciente_pressed() -> void:
	set_view("recent")

func _on_btn_nuevo_pressed() -> void:
	if SaveManager:
		SaveManager.new_project()

func _on_btn_save_pressed() -> void:
	if SaveManager:
		SaveManager.save()

func _on_btn_save_as_pressed() -> void:
	if SaveManager:
		SaveManager.save_as()

# ============================================================================
#                               FILE DIALOG
# ============================================================================

func _on_format_selected(_index: int) -> void:
	pass

func _on_browse_pressed() -> void:
	var fd := _ensure_file_dialog()
	fd.popup_centered(Vector2i(800, 600))

func _ensure_file_dialog() -> FileDialog:
	if is_instance_valid(file_dialog):
		return file_dialog
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	fd.filters = PackedStringArray(SUPPORTED_FILTERS)
	fd.dir_selected.connect(_on_dir_selected)
	fd.file_selected.connect(_on_file_selected)
	fd.files_selected.connect(_on_files_selected)
	add_child(fd)
	file_dialog = fd
	return fd

func _on_dir_selected(dir: String) -> void:
	if path_line_edit:
		path_line_edit.text = dir

func _on_file_selected(path: String) -> void:
	emit_signal("element_dropped_internally", path, Vector2.ZERO)

func _on_files_selected(paths: PackedStringArray) -> void:
	_handle_external_files(paths, Vector2.ZERO)

# ============================================================================
#                         DRAG & DROP (interno + escritorio)
# ============================================================================

func _is_drop_data(data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY

func _recent_can_drop(_at_position: Vector2, data: Variant) -> bool:
	return _is_drop_data(data) and (data.has("files") or data["type"] in ["export_element", "external_file"])

func _export_can_drop(_at_position: Vector2, data: Variant) -> bool:
	return _is_drop_data(data) and (data.has("files") or data["type"] in ["recent_file", "external_file"])

func _recent_drop(at_position: Vector2, data: Variant) -> void:
	if data.has("files"):
		_handle_external_files(data["files"], at_position)
		return
	match data["type"]:
		"export_element":
			var file_path = FileSystemManager.save_canvas_element_to_recent(data["node_reference"], data["format"])
			_add_to_recent_files(file_path)
		"external_file":
			emit_signal("element_dropped_internally", data["path"], at_position)

func _export_drop(at_position: Vector2, data: Variant) -> void:
	if data.has("files"):
		_handle_external_files(data["files"], at_position)
		return
	emit_signal("element_dropped_internally", data["path"], at_position)

func _grid_can_drop(at_position: Vector2, data: Variant) -> bool:
	return _recent_can_drop(at_position, data)

func _grid_drop(at_position: Vector2, data: Variant) -> void:
	_recent_drop(at_position, data)

func _handle_external_files(paths: PackedStringArray, at_position: Vector2) -> void:
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		if not _external_files.has(path):
			_external_files.append(path)
		emit_signal("element_dropped_internally", path, at_position)
	if _view_mode == "files" and paths.size() > 0:
		_browse_dir = paths[0].get_base_dir()
		_dir_cache.clear()
	_rebuild_tree(_current_filter())

# ============================================================================
#                              ÁRBOL DE ARCHIVOS
# ============================================================================

func _load_recent_files() -> void:
	_rebuild_tree("")

func _add_to_recent_files(file_path: String) -> void:
	if RecentFilesManager:
		RecentFilesManager.add_file(file_path)
	_load_recent_files()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and recent_files_tree:
		_refresh_translated_texts()

func _refresh_translated_texts() -> void:
	if not recent_files_tree:
		return
	if view_label:
		match _view_mode:
			"recent": view_label.text = tr("Recent Files")
			"recover": view_label.text = tr("Recovery")
			"files": view_label.text = tr("Files")
	if recent_search_bar:
		match _view_mode:
			"recent": recent_search_bar.placeholder_text = tr("Search recent files...")
			"recover": recent_search_bar.placeholder_text = tr("Search recovery files...")
			"files": recent_search_bar.placeholder_text = tr("Search files...")
	var view_bar := get_node_or_null("FileLibraryPanel/VBoxContainer/ViewBar/HBoxContainer")
	if view_bar:
		_set_button_text(view_bar.get_node_or_null("detalles"), tr("Details"))
		_set_button_text(view_bar.get_node_or_null("icono"), tr("Icon"))
	var buttons_vbox := get_node_or_null("../QuickActionMenu/MarginContainer/ButtonsVBox")
	if buttons_vbox:
		_set_button_text(buttons_vbox.get_node_or_null("BtnNuevo"), tr("New"))
		_set_button_text(buttons_vbox.get_node_or_null("BtnReciente"), tr("Recent"))
		_set_button_text(buttons_vbox.get_node_or_null("BtnArchivos"), tr("Files"))
		_set_button_text(buttons_vbox.get_node_or_null("BtnRecuperar"), tr("Recover"))
		_set_button_text(buttons_vbox.get_node_or_null("BtnSave"), tr("Save"))
		_set_button_text(buttons_vbox.get_node_or_null("BtnSaveAs"), tr("Save As"))
	_set_button_text(_get_export_node("SaveHBox/BtnSave"), tr("Save"))
	_set_button_text(_get_export_node("SaveHBox/BtnSaveAs"), tr("Save As"))
	_rebuild_tree(_current_filter())

func _set_button_text(btn: Button, text: String) -> void:
	if btn and btn.text != text:
		btn.text = text

func set_view(mode: String) -> void:
	if mode not in ["recent", "recover", "files"]:
		return
	_view_mode = mode
	if mode == "files" and _browse_dir.is_empty():
		_browse_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
		if _browse_dir.is_empty():
			_browse_dir = OS.get_user_data_dir()
		_nav_history = [_browse_dir]
		_nav_index = 0
		_update_nav_buttons()
	_refresh_translated_texts()

func _current_filter() -> String:
	return recent_search_bar.text if recent_search_bar else ""

func _matches_filter(item_name: String, filter_text: String) -> bool:
	return filter_text.is_empty() or item_name.to_lower().find(filter_text.to_lower()) >= 0

func _rebuild_tree(filter_text: String) -> void:
	recent_files_tree.clear()
	if _icon_list:
		_icon_list.clear()
	match _view_mode:
		"recover":
			_build_recover_view(filter_text)
		"files":
			_build_files_view(filter_text)
		_:
			_build_recent_view(filter_text)

# ============================================================================
#    RENDERIZADO PROGRESIVO: primeros items al instante, resto en lotes
# ============================================================================

func _begin_view_build() -> void:
	_pending_tree_items = []
	_pending_grid_items = []
	_pending_total = 0
	_current_root = null
	_desktop_section = null

func _add_pending_item(label: String, path: String, meta: Dictionary, icon: Texture2D = null, in_desktop := false, time := -1) -> void:
	var entry := {"label": label, "path": path, "meta": meta, "icon": icon, "section": in_desktop, "time": time}
	_pending_tree_items.append(entry)
	_pending_grid_items.append(entry)
	_pending_total += 1

func _flush_view_batches() -> void:
	var first := mini(_pending_tree_items.size(), FIRST_BATCH)
	for i in first:
		_create_pending_tree_item(_pending_tree_items[i])
		_create_pending_grid_item(_pending_grid_items[i])
	_pending_tree_items = _pending_tree_items.slice(first)
	_pending_grid_items = _pending_grid_items.slice(first)
	if _pending_tree_items.is_empty():
		_start_thumbnail_gen()

func _drain_view_chunks() -> void:
	if _pending_tree_items.is_empty():
		return
	var n := mini(_pending_tree_items.size(), CHUNK_SIZE)
	for i in n:
		_create_pending_tree_item(_pending_tree_items[i])
		_create_pending_grid_item(_pending_grid_items[i])
	_pending_tree_items = _pending_tree_items.slice(n)
	_pending_grid_items = _pending_grid_items.slice(n)
	if _pending_tree_items.is_empty():
		_start_thumbnail_gen()

func _create_pending_tree_item(entry: Dictionary) -> void:
	var parent: TreeItem = _desktop_section if entry.get("section", false) else _current_root
	if not parent or not is_instance_valid(parent):
		return
	var item := recent_files_tree.create_item(parent)
	item.set_icon(0, entry.get("icon") if entry.get("icon") else _get_item_icon(entry["path"]))
	item.set_text(1, entry["label"])
	item.set_metadata(1, entry["meta"])
	item.set_tooltip_text(1, entry["path"])
	if _details_mode:
		var t: int = entry.get("time", -1)
		if t < 0:
			t = FileAccess.get_modified_time(entry["path"])
		if t > 0:
			item.set_text(2, Time.get_date_string_from_unix_time(t))
		_set_size_column(item, entry["path"])

func _create_pending_grid_item(entry: Dictionary) -> void:
	if not _icon_list:
		return
	var idx := _icon_list.add_item(entry["label"], entry.get("icon") if entry.get("icon") else _get_item_icon(entry["path"]))
	_icon_list.set_item_metadata(idx, entry["meta"])

func _add_grid_empty() -> void:
	if _icon_list:
		var idx := _icon_list.add_item(tr(EMPTY_MSG))
		_icon_list.set_item_selectable(idx, false)
		_icon_list.set_item_metadata(idx, {})

func _on_grid_item_selected(index: int) -> void:
	if _icon_list:
		_handle_item_meta(_icon_list.get_item_metadata(index))

func _build_recent_view(filter_text: String) -> void:
	_begin_view_build()
	_current_root = recent_files_tree.create_item()
	_current_root.set_text(1, tr("Recent Files"))
	_current_root.set_selectable(1, false)
	var desktop_files: PackedStringArray = []
	for path in _external_files:
		if _matches_filter(path.get_file(), filter_text):
			desktop_files.append(path)
	if desktop_files.size() > 0:
		_desktop_section = recent_files_tree.create_item(_current_root)
		_desktop_section.set_text(1, tr("Desktop (%d)") % desktop_files.size())
		_desktop_section.set_selectable(1, false)
		for path in desktop_files:
			_add_pending_item(path.get_file(), path, {"path": path, "dir": false}, null, true)
	var recent_files = RecentFilesManager.get_files() if RecentFilesManager else []
	for file in recent_files:
		if _matches_filter(file["name"], filter_text):
			_add_pending_item(file["name"], file["path"], {"path": file["path"], "dir": false}, null, false, int(file["time"]))
	if _pending_total == 0:
		_add_empty_message(_current_root)
		_add_grid_empty()
	_flush_view_batches()

func _build_recover_view(filter_text: String) -> void:
	_begin_view_build()
	_current_root = recent_files_tree.create_item()
	_current_root.set_text(1, tr("Recovery"))
	_current_root.set_selectable(1, false)
	var paths := _get_recoverable_files()
	for path in paths:
		if _matches_filter(path.get_file(), filter_text):
			_add_pending_item(path.get_file(), path, {"path": path, "dir": false})
	if _pending_total == 0:
		_add_empty_message(_current_root)
		_add_grid_empty()
	_flush_view_batches()

func _list_dir_cached(dir_path: String) -> Dictionary:
	if _dir_cache.has(dir_path):
		return _dir_cache[dir_path]
	var listing := {"dirs": PackedStringArray(), "files": PackedStringArray()}
	var dir := DirAccess.open(dir_path)
	if dir:
		listing["dirs"] = dir.get_directories()
		listing["files"] = dir.get_files()
	_dir_cache[dir_path] = listing
	return listing

func _build_files_view(filter_text: String) -> void:
	_begin_view_build()
	_current_root = recent_files_tree.create_item()
	_current_root.set_text(1, _browse_dir)
	_current_root.set_selectable(1, false)
	_current_root.set_tooltip_text(1, _browse_dir)
	var listing := _list_dir_cached(_browse_dir)
	if listing["dirs"].is_empty() and listing["files"].is_empty() and _browse_dir.get_base_dir() == _browse_dir:
		var err := recent_files_tree.create_item(_current_root)
		err.set_text(1, tr("Cannot open folder"))
		err.set_selectable(1, false)
		_add_grid_empty()
		_flush_view_batches()
		return
	if _browse_dir.get_base_dir() != _browse_dir:
		_add_pending_item("..", _browse_dir.get_base_dir(), {"path": _browse_dir.get_base_dir(), "dir": true}, _folder_icon())
	var dirs: PackedStringArray = listing["dirs"]
	dirs.sort()
	for d in dirs:
		if _matches_filter(d, filter_text):
			_add_pending_item(d, _browse_dir.path_join(d), {"path": _browse_dir.path_join(d), "dir": true}, _folder_icon())
	var files: PackedStringArray = listing["files"]
	files.sort()
	for f in files:
		if _matches_filter(f, filter_text):
			_add_pending_item(f, _browse_dir.path_join(f), {"path": _browse_dir.path_join(f), "dir": false})
	if _pending_total == 0:
		_add_empty_message(_current_root)
		_add_grid_empty()
	_flush_view_batches()

func _get_recoverable_files() -> PackedStringArray:
	var paths := PackedStringArray()
	if FileAccess.file_exists("user://autosave.vtc"):
		paths.append("user://autosave.vtc")
	for dir_path in ["user://recovery", "user://backups"]:
		var dir := DirAccess.open(dir_path)
		if not dir:
			continue
		for file in dir.get_files():
			paths.append(dir_path.path_join(file))
	return paths

func _navigate_dir(path: String) -> void:
	if path == _browse_dir:
		return
	_nav_history.resize(_nav_index + 1)
	_nav_history.append(path)
	_nav_index = _nav_history.size() - 1
	_browse_dir = path
	_rebuild_tree.call_deferred(_current_filter())
	_update_nav_buttons()

func _recover_file(path: String) -> void:
	if SaveManager and SaveManager.has_method("open"):
		SaveManager.open(path)

func _add_empty_message(root: TreeItem) -> void:
	var empty := recent_files_tree.create_item(root)
	empty.set_text(1, tr(EMPTY_MSG))
	empty.set_selectable(1, false)
	empty.set_custom_color(1, Color(0.55, 0.55, 0.55))

# ============================================================================
#   THUMBNAILS EN SEGUNDO PLANO (WorkerThreadPool nativo + caché en disco)
# ============================================================================

const THUMB_CACHE_DIR := "user://thumb_cache/"
const THUMB_WORKERS := 8

func _get_item_icon(path: String) -> Texture2D:
	if _thumbnail_cache.has(path) and _thumbnail_cache[path] is Texture2D:
		return _thumbnail_cache[path]
	return _get_icon_for_file(path)

func _start_thumbnail_gen() -> void:
	var paths := _collect_thumbnail_paths()
	var queued := 0
	for path in paths:
		if _thumbnail_cache.has(path):
			continue
		var cache_file := _thumb_cache_path(path)
		if FileAccess.file_exists(cache_file):
			var img := Image.new()
			var data := FileAccess.get_file_as_bytes(cache_file)
			if data.size() > 0 and img.load_png_from_buffer(data) == OK:
				_thumbnail_cache[path] = ImageTexture.create_from_image(img)
				_update_icons_for_path(path, _thumbnail_cache[path])
				continue
		_thumb_mutex.lock()
		if not _thumb_queue.has(path):
			_thumb_queue.push_back(path)
			queued += 1
		_thumb_mutex.unlock()
	if queued > 0:
		_ensure_thumb_workers()

func _ensure_thumb_workers() -> void:
	if _thumb_task_id != -1 and not WorkerThreadPool.is_group_task_completed(_thumb_task_id):
		return
	_thumb_mutex.lock()
	var pending := not _thumb_queue.is_empty()
	_thumb_mutex.unlock()
	if not pending:
		return
	_thumb_task_id = WorkerThreadPool.add_group_task(_thumb_worker_group, THUMB_WORKERS)

func _thumb_worker_group(_index: int) -> void:
	while true:
		var path := ""
		_thumb_mutex.lock()
		if _thumb_stop or _thumb_queue.is_empty():
			_thumb_mutex.unlock()
			return
		path = _thumb_queue.pop_front()
		_thumb_mutex.unlock()
		var image := _decode_thumbnail(path)
		if image:
			image.save_png(_thumb_cache_path(path))
		_thumb_mutex.lock()
		if image:
			_thumb_ready.append({"path": path, "image": image})
		else:
			_thumbnail_cache[path] = null
		_thumb_mutex.unlock()

func _thumb_cache_path(path: String) -> String:
	return THUMB_CACHE_DIR + path.sha256_text() + ".png"

func _decode_thumbnail(file_path: String) -> Image:
	var ext := file_path.get_extension().to_lower()
	if ext not in ["png", "jpg", "jpeg"] or not FileAccess.file_exists(file_path):
		return null
	var data := FileAccess.get_file_as_bytes(file_path)
	if data.size() < 3 or data.size() > 4 * 1024 * 1024:
		return null
	var image := Image.new()
	var err: Error = ERR_FILE_UNRECOGNIZED
	if ext == "png" and data[0] == 0x89 and data[1] == 0x50:
		err = image.load_png_from_buffer(data)
	elif data[0] == 0xFF and data[1] == 0xD8:
		err = image.load_jpg_from_buffer(data)
	if err != OK:
		return null
	image.resize(64, 64, Image.INTERPOLATE_LANCZOS)
	return image

func _process(_delta: float) -> void:
	_consume_thumbnails()
	_ensure_thumb_workers()
	_drain_view_chunks()

func _consume_thumbnails() -> void:
	var results: Array = []
	_thumb_mutex.lock()
	results = _thumb_ready
	_thumb_ready = []
	_thumb_mutex.unlock()
	if results.is_empty():
		return
	for result in results:
		var tex := ImageTexture.create_from_image(result["image"])
		_thumbnail_cache[result["path"]] = tex
		_update_icons_for_path(result["path"], tex)

func _collect_thumbnail_paths() -> Array[String]:
	var paths: Array[String] = []
	var root := recent_files_tree.get_root()
	if root:
		_collect_item_paths(root, paths)
	return paths

func _collect_item_paths(item: TreeItem, paths: Array[String]) -> void:
	if not is_instance_valid(item):
		return
	var meta: Variant = item.get_metadata(1)
	var p := ""
	if meta is String:
		p = meta
	elif meta is Dictionary:
		p = meta.get("path", "")
	if not p.is_empty() and p.get_extension().to_lower() in ["png", "jpg", "jpeg"]:
		paths.append(p)
	for i in item.get_child_count():
		_collect_item_paths(item.get_child(i), paths)

func _update_icons_for_path(path: String, tex: Texture2D) -> void:
	var root := recent_files_tree.get_root()
	if root:
		_update_tree_icons(root, path, tex)
	if _icon_list and is_instance_valid(_icon_list):
		for i in _icon_list.item_count:
			var meta: Variant = _icon_list.get_item_metadata(i)
			if meta is Dictionary and meta.get("path", "") == path:
				_icon_list.set_item_icon(i, tex)

func _update_tree_icons(item: TreeItem, path: String, tex: Texture2D) -> void:
	if not is_instance_valid(item):
		return
	var meta: Variant = item.get_metadata(1)
	if (meta is String and meta == path) or (meta is Dictionary and meta.get("path", "") == path):
		item.set_icon(0, tex)
	for i in item.get_child_count():
		_update_tree_icons(item.get_child(i), path, tex)

func _create_recent_item(parent: TreeItem, file: Dictionary) -> void:
	var item := recent_files_tree.create_item(parent)
	item.set_icon(0, _get_item_icon(file["path"]))
	item.set_text(1, file["name"])
	item.set_metadata(1, file["path"])
	item.set_tooltip_text(1, file["path"])
	if _details_mode:
		item.set_text(2, Time.get_date_string_from_unix_time(int(file["time"])))
		_set_size_column(item, file["path"])

func _create_file_item(parent: TreeItem, path: String, meta: Variant = "") -> void:
	var item := recent_files_tree.create_item(parent)
	item.set_icon(0, _get_item_icon(path))
	item.set_text(1, path.get_file())
	item.set_metadata(1, meta if meta is Dictionary else path)
	item.set_tooltip_text(1, path)
	if _details_mode:
		var modified := FileAccess.get_modified_time(path)
		if modified > 0:
			item.set_text(2, Time.get_date_string_from_unix_time(modified))
		_set_size_column(item, path)

func _set_size_column(item: TreeItem, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var file_size := file.get_length()
		file.close()
		if file_size > 0:
			item.set_text(3, _format_size(file_size))

func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	var kb := bytes / 1024.0
	if kb < 1024.0:
		return "%.2f KB" % kb
	var mb := kb / 1024.0
	if mb < 1024.0:
		return "%.2f MB" % mb
	return "%.2f GB" % (mb / 1024.0)

func _get_icon_for_file(file_path: String) -> Texture2D:
	var ext := file_path.get_extension().to_lower()
	var icon_path := ""
	match ext:
		"svg": icon_path = "res://assets/icons/file_svg.png"
		"png": icon_path = "res://assets/icons/file_png.png"
		"pdf": icon_path = "res://assets/icons/file_pdf.png"
		"jpeg", "jpg": icon_path = "res://assets/icons/file_jpg.png"
		_: icon_path = "res://assets/icons/file_generic.png"
	return _load_icon(icon_path)

func _folder_icon() -> Texture2D:
	return _load_icon("res://assets/icons/folder.png")

func _load_icon(icon_path: String) -> Texture2D:
	if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
		return null
	var tex: Texture2D = load(icon_path)
	if tex and tex.get_width() > 64:
		var img := tex.get_image()
		if img:
			img.resize(64, 64, Image.INTERPOLATE_BILINEAR)
			return ImageTexture.create_from_image(img)
	return tex

# ============================================================================
#                               SELECCIÓN
# ============================================================================

func _on_recent_search_text_changed(text: String) -> void:
	_rebuild_tree(text)

func _on_recent_file_selected() -> void:
	var selected := recent_files_tree.get_selected()
	if not selected or selected.get_parent() == null:
		return
	_handle_item_meta(selected.get_metadata(1))

func _handle_item_meta(meta: Variant) -> void:
	if meta is Dictionary:
		var path: String = meta.get("path", "")
		if path.is_empty():
			return
		if meta.get("dir", false):
			_selected_path = ""
			_hide_small_preview()
			_navigate_dir(path)
		elif _view_mode == "recover":
			_recover_file(path)
		else:
			_selected_path = path
			_update_small_preview(path)
			emit_signal("element_dropped_internally", path, Vector2.ZERO)
	elif meta is String and not (meta as String).is_empty():
		_selected_path = meta
		_update_small_preview(meta)
		emit_signal("element_dropped_internally", meta, Vector2.ZERO)

# ============================================================================
#   VISTA PREVIA (panel derecho + popup gigante centrado con Espacio)
# ============================================================================

func _update_small_preview(path: String) -> void:
	if not _preview_panel:
		return
	_preview_panel.visible = true
	if _preview_texture:
		_preview_texture.texture = _get_preview_texture(path, 256)

func _hide_small_preview() -> void:
	if _preview_panel:
		_preview_panel.visible = false

func _get_preview_texture(path: String, max_size: int) -> Texture2D:
	if _preview_cache.has(path) and _preview_cache[path] is Texture2D:
		return _preview_cache[path]
	var ext := path.get_extension().to_lower()
	var tex: Texture2D = null
	if ext in ["png", "jpg", "jpeg"] and FileAccess.file_exists(path):
		var data := FileAccess.get_file_as_bytes(path)
		var image := Image.new()
		var err: Error = ERR_FILE_UNRECOGNIZED
		if data.size() > 1:
			if ext == "png" and data[0] == 0x89:
				err = image.load_png_from_buffer(data)
			elif data[0] == 0xFF:
				err = image.load_jpg_from_buffer(data)
		if err == OK:
			if image.get_width() > max_size or image.get_height() > max_size:
				image.resize(max_size, max_size, Image.INTERPOLATE_LANCZOS)
			tex = ImageTexture.create_from_image(image)
	if not tex:
		tex = _get_item_icon(path)
	_preview_cache[path] = tex
	return tex

func _build_big_overlay() -> void:
	_big_overlay = Control.new()
	_big_overlay.name = "BigPreviewOverlay"
	_big_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_big_overlay.top_level = true
	_big_overlay.visible = false
	_big_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_big_overlay_clicked)
	_big_overlay.add_child(bg)
	_big_texture = TextureRect.new()
	_big_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_big_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_big_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_big_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_overlay.add_child(_big_texture)
	add_child(_big_overlay)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE and not _selected_path.is_empty():
			_toggle_big_preview()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _big_overlay and _big_overlay.visible:
			_toggle_big_preview(false)
			get_viewport().set_input_as_handled()

func _on_big_overlay_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_toggle_big_preview(false)

func _toggle_big_preview(make_visible: bool = true) -> void:
	if not _big_overlay:
		return
	if _big_overlay.visible:
		_big_overlay.visible = false
	elif make_visible and not _selected_path.is_empty():
		var tex := _get_preview_texture(_selected_path, 1024)
		if tex:
			_big_texture.texture = tex
		_big_overlay.visible = true

func _on_recent_cell_selected(_column: int = -1) -> void:
	if _column <= 0:
		_on_recent_file_selected()

func _recent_drag(_at_position: Vector2) -> Variant:
	var selected := recent_files_tree.get_selected()
	if not selected or not (selected.get_metadata(1) is String):
		return null
	var path: String = selected.get_metadata(1)
	if path.is_empty():
		return null
	var preview := TextureRect.new()
	var icon := selected.get_icon(0)
	if icon:
		preview.texture = icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(64, 64)
	recent_files_tree.set_drag_preview(preview)
	return {
		"type": "recent_file",
		"path": path,
		"name": selected.get_text(1),
	}
