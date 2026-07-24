extends HBoxContainer
class_name FileFlowLayout

signal element_dropped_internally(element: Node, position: Vector2)
signal export_requested(element: Node, format: String, destination: String)

@onready var recent_files_tree: Tree = $FileLibraryPanel/VBoxContainer/RecentFilesTree
@onready var format_selector: OptionButton = $ExportPanel/VBoxContainer/FormatSelector
@onready var recent_search_bar: LineEdit = $FileLibraryPanel/VBoxContainer/SearchBar
@onready var path_line_edit: LineEdit = $ExportPanel/VBoxContainer/FolderPathHBox/PathLineEdit
@onready var btn_browse: Button = $ExportPanel/VBoxContainer/FolderPathHBox/BtnBrowse
@onready var file_dialog: FileDialog = $FileDialog

const DEFAULT_EXPORT_FORMATS := ["SVG", "PNG", "PDF", "JPEG"]

func _ready() -> void:
	_setup_ui()
	_setup_drag_and_drop()
	_load_recent_files()

	if recent_search_bar:
		recent_search_bar.text_changed.connect(_on_recent_search_text_changed)
	if btn_browse:
		btn_browse.pressed.connect(_on_browse_pressed)
	if file_dialog:
		file_dialog.dir_selected.connect(_on_dir_selected)
		file_dialog.file_selected.connect(_on_file_selected)
	if format_selector:
		format_selector.item_selected.connect(_on_format_selected)

func _setup_ui() -> void:
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
	recent_files_tree.connect("drag_data", _get_drag_data_recent)
	recent_files_tree.connect("can_drop_data", _can_drop_data_recent)
	recent_files_tree.connect("drop_data", _drop_data_recent)

func _on_format_selected(index: int) -> void:
	pass

func _on_browse_pressed() -> void:
	if file_dialog:
		file_dialog.popup_centered(Vector2i(800, 600))

func _on_dir_selected(dir: String) -> void:
	if path_line_edit:
		path_line_edit.text = dir

func _on_file_selected(path: String) -> void:
	emit_signal("element_dropped_internally", path, Vector2.ZERO)

func _get_drag_data_recent(position: Vector2) -> Variant:
	var selected = recent_files_tree.get_selected()
	if not selected:
		return null
	var preview = TextureRect.new()
	preview.texture = selected.get_icon(0)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(64, 64)
	set_drag_preview(preview)
	var drag_data = {
		"type": "recent_file",
		"path": selected.get_metadata(0),
		"name": selected.get_text(0)
	}
	return drag_data

func _can_drop_data_recent(position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] in ["export_element", "external_file"]

func _can_drop_data_export(position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] in ["recent_file", "external_file"]

func _drop_data_recent(position: Vector2, data: Variant) -> void:
	if data["type"] == "export_element":
		var file_path = FileSystemManager.save_canvas_element_to_recent(data["node_reference"], data["format"])
		_add_to_recent_files(file_path)
	elif data["type"] == "external_file":
		emit_signal("element_dropped_internally", data["path"], position)

func _drop_data_export(position: Vector2, data: Variant) -> void:
	if data["type"] == "recent_file":
		emit_signal("element_dropped_internally", data["path"], position)
	elif data["type"] == "external_file":
		emit_signal("element_dropped_internally", data["path"], position)

func _load_recent_files() -> void:
	recent_files_tree.clear()
	var root = recent_files_tree.create_item()
	root.set_text(1, "Recent Files")
	root.set_selectable(1, false)
	var recent_files = RecentFilesManager.get_files() if RecentFilesManager else []
	for file in recent_files:
		var item = recent_files_tree.create_item(root)
		var thumbnail = _generate_thumbnail(file["path"])
		if thumbnail:
			item.set_icon(0, thumbnail)
		else:
			item.set_icon(0, _get_icon_for_file(file["path"]))
		item.set_text(1, file["name"])
		item.set_metadata(1, file["path"])
		item.set_text(2, Time.get_datetime_dict_from_unix(file["time"]).format("%Y-%m-%d"))
		var file_size = FileAccess.get_file_size(file["path"])
		if file_size > 0:
			item.set_text(3, "%.2f KB" % (file_size / 1024.0))

func _add_to_recent_files(file_path: String) -> void:
	if RecentFilesManager:
		RecentFilesManager.add_file(file_path)
	_load_recent_files()

func _get_icon_for_file(file_path: String) -> Texture2D:
	var ext = file_path.get_extension().to_lower()
	match ext:
		"svg": return load("res://assets/icons/file_svg.svg")
		"png": return load("res://assets/icons/file_png.svg")
		"pdf": return load("res://assets/icons/file_pdf.svg")
		"jpeg", "jpg": return load("res://assets/icons/file_jpg.svg")
		_: return load("res://assets/icons/file_generic.svg")

func _generate_thumbnail(file_path: String) -> Texture2D:
	var ext = file_path.get_extension().to_lower()
	if ext in ["png", "jpg", "jpeg"]:
		if FileAccess.file_exists(file_path):
			var image = Image.load_from_file(file_path)
			if image:
				image.resize(64, 64, Image.INTERPOLATE_LANCZOS)
				var texture = ImageTexture.create_from_image(image)
				return texture
	elif ext == "svg":
		return load("res://assets/icons/file_svg.svg")
	return load("res://assets/icons/file_generic.svg")

func _on_recent_search_text_changed(text: String) -> void:
	recent_files_tree.clear()
	var root = recent_files_tree.create_item()
	root.set_text(1, "Recent Files")
	root.set_selectable(1, false)
	var recent_files = RecentFilesManager.get_files() if RecentFilesManager else []
	for file in recent_files:
		if file["name"].to_lower().find(text.to_lower()) >= 0:
			var item = recent_files_tree.create_item(root)
			var thumbnail = _generate_thumbnail(file["path"])
			if thumbnail:
				item.set_icon(0, thumbnail)
			else:
				item.set_icon(0, _get_icon_for_file(file["path"]))
			item.set_text(1, file["name"])
			item.set_metadata(1, file["path"])
			item.set_text(2, Time.get_datetime_dict_from_unix(file["time"]).format("%Y-%m-%d"))
			var file_size = FileAccess.get_file_size(file["path"])
			if file_size > 0:
				item.set_text(3, "%.2f KB" % (file_size / 1024.0))

func _on_recent_file_selected() -> void:
	var selected = recent_files_tree.get_selected()
	if selected and selected.get_parent() != null:
		var path = selected.get_metadata(1)
		if path:
			emit_signal("element_dropped_internally", path, Vector2.ZERO)

func _on_recent_cell_selected(row: int, column: int) -> void:
	if column == 0:
		_on_recent_file_selected()
