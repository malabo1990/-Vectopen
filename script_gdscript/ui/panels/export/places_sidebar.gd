# =============================================================================
# RUTA: res://script_gdscript/ui/panels/export/places_sidebar.gd
# Barra lateral del panel de archivos, como en un gestor de archivos:
#   · LUGARES: Inicio, Escritorio, Documentos, Descargas, Imágenes, Vídeos,
#     Biblioteca de Vectopen y discos montados.
#   · FAVORITOS: carpetas (y archivos) para volver rápido. Se añaden con «★»
#     (carpeta actual) o arrastrando una carpeta/archivo de la lista encima;
#     clic derecho → quitar. Se guardan en user://vectopen_places.cfg.
# Clic en un lugar = abrirlo en la vista Archivos. Soltar una fila de
# exportación sobre un lugar/favorito = exportar ahí.
# =============================================================================
extends VBoxContainer

const FxUI = preload("res://script_gdscript/ui/panels/effects/fx_ui.gd")
const CFG := "user://vectopen_places.cfg"
const ICON_DIR := "res://icon/UI/folder.svg"
const ICON_FAV := "res://icon/UI/star-solid.svg"
const ICON_FILE := "res://icon/UI/agregar-documento.svg"

signal place_selected(path: String)

var file_flow: Node = null        # FileFlowLayout (navegar / exportar)
var favorites: PackedStringArray = []
var _places_box: VBoxContainer
var _fav_box: VBoxContainer
var _menu: PopupMenu
var _menu_path := ""

func _init() -> void:
	name = "PlacesSidebar"
	custom_minimum_size = Vector2(150, 0)
	add_theme_constant_override("separation", 2)
	add_child(_title("LUGARES"))
	_places_box = VBoxContainer.new()
	_places_box.add_theme_constant_override("separation", 1)
	add_child(_places_box)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	add_child(gap)
	var head := HBoxContainer.new()
	add_child(head)
	var t := _title("FAVORITOS")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var add := Button.new()
	add.name = "AddFavorite"
	add.text = "★"
	add.tooltip_text = "Añadir la carpeta que estás viendo a Favoritos"
	add.focus_mode = Control.FOCUS_NONE
	add.flat = true
	add.pressed.connect(func() -> void:
		if file_flow and String(file_flow.get("_browse_dir")) != "":
			add_favorite(String(file_flow.get("_browse_dir"))))
	head.add_child(add)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_fav_box = FavDrop.new()
	_fav_box.sidebar = self
	_fav_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fav_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fav_box.add_theme_constant_override("separation", 1)
	scroll.add_child(_fav_box)
	_menu = PopupMenu.new()
	_menu.add_item("Abrir", 0)
	_menu.add_item("Abrir en el gestor de archivos", 1)
	_menu.add_separator()
	_menu.add_item("Quitar de Favoritos", 2)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)

func _ready() -> void:
	_load()
	rebuild()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: rebuild())

## Lugares del sistema que existen en este equipo.
func places() -> Array:
	var out: Array = []
	var home := OS.get_environment("HOME")
	if home == "":
		home = OS.get_environment("USERPROFILE")
	if home != "":
		out.append(["Inicio", home])
	for p in [["Escritorio", OS.SYSTEM_DIR_DESKTOP], ["Documentos", OS.SYSTEM_DIR_DOCUMENTS],
			["Descargas", OS.SYSTEM_DIR_DOWNLOADS], ["Imágenes", OS.SYSTEM_DIR_PICTURES],
			["Vídeos", OS.SYSTEM_DIR_MOVIES]]:
		var d := OS.get_system_dir(p[1])
		if d != "" and DirAccess.dir_exists_absolute(d) and d != home:
			out.append([p[0], d])
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var lib := (docs if docs != "" else OS.get_user_data_dir()).path_join("Vectopen").path_join("Biblioteca")
	out.append(["Biblioteca", lib])
	# discos montados (Linux) y unidades (Windows)
	if OS.get_name() == "Windows":
		for i in DirAccess.get_drive_count():
			out.append([DirAccess.get_drive_name(i), DirAccess.get_drive_name(i) + "/"])
	else:
		var user := OS.get_environment("USER")
		for base in ["/run/media/" + user, "/media/" + user, "/mnt"]:
			if DirAccess.dir_exists_absolute(base):
				for d in DirAccess.get_directories_at(base):
					out.append([d, base.path_join(d)])
	return out

func rebuild() -> void:
	for box in [_places_box, _fav_box]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	for p in places():
		_places_box.add_child(_row(p[0], p[1], ICON_DIR, false))
	for f in favorites:
		var is_dir := DirAccess.dir_exists_absolute(f)
		_fav_box.add_child(_row(f.get_file() if f.get_file() != "" else f, f, ICON_DIR if is_dir else ICON_FILE, true))
	if favorites.is_empty():
		var l := Label.new()
		l.text = "Arrastra aquí carpetas o archivos, o pulsa ★"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fav_box.add_child(l)
	for t in find_children("*", "Label", true, false):
		if t.has_meta("title"):
			t.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
	var add := find_child("AddFavorite", true, false) as Button
	if add:
		add.add_theme_color_override("font_color", FxUI.c("ACCENT"))
	ProUIStyle.style_popup(_menu)

func _row(label: String, path: String, icon_path: String, fav: bool) -> Control:
	var b := PlaceRow.new()
	b.sidebar = self
	b.path = path
	b.is_favorite = fav
	b.text = label
	b.tooltip_text = path
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 24)
	b.icon = ProUIStyle.icon(icon_path, FxUI.c("ICON_PRIMARY"), 14)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
	b.add_theme_stylebox_override("normal", FxUI.flat(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0), 6, 0))
	b.add_theme_stylebox_override("hover", FxUI.flat(FxUI.c("BUTTON_HOVER"), 4, Color(0, 0, 0, 0), 6, 0))
	b.add_theme_stylebox_override("pressed", FxUI.flat(FxUI.c("ACCENT_SOFT"), 4, Color(0, 0, 0, 0), 6, 0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

func open(path: String) -> void:
	place_selected.emit(path)
	if file_flow == null:
		return
	if DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
		file_flow.set_view("files")
		file_flow._navigate_dir(path)
	elif FileAccess.file_exists(path):
		file_flow.set_view("files")
		file_flow._navigate_dir(path.get_base_dir())

func add_favorite(path: String) -> void:
	var p := path.trim_suffix("/") if path.length() > 1 else path
	if p == "" or p in favorites:
		return
	favorites.append(p)
	_save()
	rebuild()

func remove_favorite(path: String) -> void:
	var i := favorites.find(path)
	if i >= 0:
		favorites.remove_at(i)
		_save()
		rebuild()

func show_menu(path: String, fav: bool, at: Vector2) -> void:
	_menu_path = path
	_menu.set_item_disabled(_menu.get_item_index(2), not fav)
	_menu.position = Vector2i(at)
	_menu.popup()

func _on_menu(id: int) -> void:
	match id:
		0: open(_menu_path)
		1: OS.shell_open(_menu_path if DirAccess.dir_exists_absolute(_menu_path) else _menu_path.get_base_dir())
		2: remove_favorite(_menu_path)

func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.set_meta("title", true)
	l.add_theme_font_size_override("font_size", 10)
	return l

func _load() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	favorites = PackedStringArray(cfg.get_value("places", "favorites", PackedStringArray()))

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("places", "favorites", favorites)
	cfg.save(CFG)

## Lo que se puede soltar en la barra: archivos/carpetas de la lista
## (→ favoritos) y filas de exportación (→ exportar en ese lugar).
static func _data_path(data: Variant) -> String:
	if data is Dictionary and String(data.get("type", "")) in ["recent_file", "external_file", "folder"]:
		return String(data.get("path", ""))
	return ""

static func _is_export(data: Variant) -> bool:
	return data is Dictionary and String(data.get("type", "")) == "export_element"

class PlaceRow extends Button:
	var sidebar: Node
	var path := ""
	var is_favorite := false
	func _pressed() -> void:
		sidebar.open(path)
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			sidebar.show_menu(path, is_favorite, get_screen_position() + ev.position)
			accept_event()
	func _get_drag_data(_at: Vector2) -> Variant:
		var l := Label.new()
		l.text = "  " + text
		set_drag_preview(l)
		return {"type": "folder" if DirAccess.dir_exists_absolute(path) else "recent_file", "path": path}
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return (sidebar._is_export(data) and DirAccess.dir_exists_absolute(path)) or (is_favorite and sidebar._data_path(data) != "")
	func _drop_data(_at: Vector2, data: Variant) -> void:
		if sidebar._is_export(data) and sidebar.file_flow:
			sidebar.file_flow._drop_export(data.get("rows", []), {"path": path, "dir": true})
		else:
			sidebar.add_favorite(sidebar._data_path(data))

class FavDrop extends VBoxContainer:
	var sidebar: Node
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return sidebar._data_path(data) != ""
	func _drop_data(_at: Vector2, data: Variant) -> void:
		sidebar.add_favorite(sidebar._data_path(data))
