# =============================================================================
# RUTA: res://script_gdscript/ui/panels/assets/assets_panel.gd
# Pestaña RECURSOS (junto a Capas y Páginas): biblioteca de logos, iconos,
# botones… para reutilizar sin buscar en carpetas. Como Assets de Affinity:
#
#   · Categoría (selector) → SUBCATEGORÍAS (secciones plegables).
#   · ARRASTRAR PARA ORGANIZAR: un recurso dentro de su sección (orden), a
#     otra sección (mover) o al artboard (usar); una sección por su cabecera
#     (orden de secciones).
#   · «+ Selección» guarda lo seleccionado en la sección activa; cada
#     sección tiene su menú ⋯ (añadir aquí, renombrar, mover, borrar).
#   · Doble clic = colocar en el centro. Clic derecho en un recurso: colocar,
#     renombrar, borrar. Suelta archivos o filas de Exportar en una sección.
#   · Paquetes .vopassets (exportar / importar) en el menú ⋯ de categoría.
# Motor: asset_library.gd.
# =============================================================================
extends VBoxContainer

const Lib = preload("res://script_gdscript/system/asset_library.gd")
const FxUI = preload("res://script_gdscript/ui/panels/effects/fx_ui.gd")
const GROUP := "vectopen_assets_panel"

var current_cat := ""
var current_sub := ""
var _cat: OptionButton
var _menu_btn: Button
var _cat_menu: PopupMenu
var _item_menu: PopupMenu
var _sub_menu: PopupMenu
var _move_cat_menu: PopupMenu
var _search: LineEdit
var _sections: VBoxContainer
var _add_btn: Button
var _status: Label
var _menu_item_id := ""
var _menu_sub_id := ""
var _last_mouse := Vector2.ZERO
var thumb_size := 56
var _zoom: HSlider
const CFG := "user://vectopen_assets_ui.cfg"

func _init() -> void:
	name = "RecursosPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	add_child(head)
	_cat = OptionButton.new()
	_cat.name = "Category"
	_cat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cat.focus_mode = Control.FOCUS_NONE
	_cat.tooltip_text = "Categoría"
	_cat.item_selected.connect(func(i: int) -> void:
		current_cat = String(_cat.get_item_metadata(i))
		current_sub = ""
		refresh_items())
	head.add_child(_cat)
	_menu_btn = _small_button(head, "⋯", "Categorías, subcategorías y paquetes .vopassets")
	_menu_btn.pressed.connect(func() -> void: _popup_at(_cat_menu, _menu_btn))
	_search = LineEdit.new()
	_search.placeholder_text = "Buscar recursos…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: refresh_items())
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	add_child(srow)
	srow.add_child(_search)
	# zoom de las miniaturas
	_zoom = HSlider.new()
	_zoom.name = "Zoom"
	_zoom.min_value = 32
	_zoom.max_value = 128
	_zoom.step = 4
	_zoom.custom_minimum_size = Vector2(80, 0)
	_zoom.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_zoom.tooltip_text = "Tamaño de las miniaturas"
	_zoom.value_changed.connect(func(v: float) -> void: set_thumb_size(int(v)))
	srow.add_child(_zoom)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 160)
	add_child(scroll)
	_sections = VBoxContainer.new()
	_sections.name = "Sections"
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", 4)
	scroll.add_child(_sections)
	_add_btn = Button.new()
	_add_btn.name = "AddSelection"
	_add_btn.text = "+ Selección como recurso"
	_add_btn.tooltip_text = "Guarda lo seleccionado en la sección activa"
	_add_btn.focus_mode = Control.FOCUS_NONE
	_add_btn.custom_minimum_size = Vector2(0, 28)
	_add_btn.pressed.connect(func() -> void: add_selection())
	add_child(_add_btn)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 11)
	_status.custom_minimum_size = Vector2(0, 18)
	add_child(_status)
	_cat_menu = PopupMenu.new()
	_cat_menu.add_item("Nueva subcategoría…", 6)
	_cat_menu.add_separator()
	_cat_menu.add_item("Nueva categoría…", 0)
	_cat_menu.add_item("Renombrar categoría…", 1)
	_cat_menu.add_item("Borrar categoría", 2)
	_cat_menu.add_separator()
	_cat_menu.add_item("Exportar esta categoría (.vopassets)…", 3)
	_cat_menu.add_item("Exportar todas (.vopassets)…", 4)
	_cat_menu.add_item("Importar paquete .vopassets…", 5)
	_cat_menu.id_pressed.connect(_on_cat_menu)
	add_child(_cat_menu)
	_item_menu = PopupMenu.new()
	_item_menu.add_item("Colocar en el artboard", 0)
	_item_menu.add_item("Renombrar…", 1)
	_item_menu.add_separator()
	_item_menu.add_item("Borrar", 3)
	_item_menu.id_pressed.connect(_on_item_menu)
	add_child(_item_menu)
	_move_cat_menu = PopupMenu.new()
	_move_cat_menu.index_pressed.connect(_on_move_sub_to_cat)
	add_child(_move_cat_menu)
	_sub_menu = PopupMenu.new()
	_sub_menu.add_item("Añadir la selección aquí", 0)
	_sub_menu.add_item("Renombrar sección…", 1)
	_sub_menu.add_item("Mover a otra categoría…", 2)
	_sub_menu.add_separator()
	_sub_menu.add_item("Borrar sección", 3)
	_sub_menu.id_pressed.connect(_on_sub_menu)
	add_child(_sub_menu)

func _ready() -> void:
	add_to_group(GROUP)
	add_to_group("vectopen_drop_exclude")   # la capa de soltar archivos no lo tapa
	var iem := get_node_or_null("/root/ImportExportManager")
	if iem and "drop_routers" in iem:
		iem.drop_routers.append(_route_os_drop)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: restyle())
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	thumb_size = int(cfg.get_value("ui", "thumb_size", 56))
	_zoom.set_value_no_signal(thumb_size)
	refresh()

func _exit_tree() -> void:
	var iem := get_node_or_null("/root/ImportExportManager")
	if iem and "drop_routers" in iem:
		iem.drop_routers.erase(_route_os_drop)

## Posición real del ratón para soltar (la que da Godot dentro de un
## CanvasLayer no siempre es local al control).
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_last_mouse = (event as InputEventMouse).global_position

func _api() -> VectopenAPI:
	var pm := get_node_or_null("/root/PluginManager")
	return pm.api if pm else null

# ── construir ────────────────────────────────────────────────────────────────
## Tamaño de las miniaturas (deslizador de zoom); se recuerda.
func set_thumb_size(px: int) -> void:
	thumb_size = clampi(px, 32, 128)
	for g in find_children("*", "ItemList", true, false):
		g.fixed_icon_size = Vector2i(thumb_size, thumb_size)
		g.fixed_column_width = thumb_size + 28
	if _zoom and int(_zoom.value) != thumb_size:
		_zoom.set_value_no_signal(thumb_size)
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("ui", "thumb_size", thumb_size)
	cfg.save(CFG)

func refresh() -> void:
	var cats := Lib.categories()
	_cat.clear()
	var sel := 0
	for i in cats.size():
		_cat.add_item("%s  (%d)" % [cats[i]["name"], Lib.category_items(cats[i]["id"]).size()])
		_cat.set_item_metadata(i, cats[i]["id"])
		if cats[i]["id"] == current_cat:
			sel = i
	if not cats.is_empty():
		_cat.select(sel)
		current_cat = cats[sel]["id"]
	refresh_items()

func refresh_items() -> void:
	for c in _sections.get_children():
		_sections.remove_child(c)
		c.queue_free()
	var cat := Lib.category(current_cat)
	var q := _search.text.strip_edges().to_lower()
	var subs: Array = cat.get("subs", [])
	if current_sub == "" or not subs.any(func(s) -> bool: return s["id"] == current_sub):
		current_sub = subs[0]["id"] if not subs.is_empty() else ""
	var total := 0
	for s in subs:
		var items: Array = (s["items"] as Array).filter(func(it) -> bool: return q == "" or q in String(it["name"]).to_lower())
		if q != "" and items.is_empty():
			continue
		total += items.size()
		_sections.add_child(_make_section(s, items, q != ""))
	_status.text = "" if total > 0 or q != "" else "Vacío: selecciona algo y pulsa «+ Selección», o arrastra aquí archivos."
	restyle()

func _make_section(s: Dictionary, items: Array, searching: bool) -> Control:
	var box := VBoxContainer.new()
	box.name = "Sec_" + String(s["id"])
	box.add_theme_constant_override("separation", 2)
	var head := SectionHeader.new()
	head.panel = self
	head.sub_id = s["id"]
	head.name = "Header"
	head.text = ("▸ " if bool(s.get("collapsed", false)) and not searching else "▾ ") + "%s  (%d)" % [s["name"], (s["items"] as Array).size()]
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.focus_mode = Control.FOCUS_NONE
	head.custom_minimum_size = Vector2(0, 24)
	head.tooltip_text = "Clic: plegar/desplegar · arrastra para reordenar · suelta recursos aquí para moverlos"
	head.set_meta("active", s["id"] == current_sub)
	head.pressed.connect(func() -> void:
		current_sub = s["id"]
		Lib.set_collapsed(s["id"], not bool(Lib.subcategory(s["id"]).get("collapsed", false)))
		refresh_items())
	var row := HBoxContainer.new()
	row.add_child(head)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var more := _small_button(row, "⋯", "Sección: añadir aquí, renombrar, mover, borrar")
	more.pressed.connect(func() -> void:
		_menu_sub_id = s["id"]
		current_sub = s["id"]
		_popup_at(_sub_menu, more))
	box.add_child(row)
	var grid := AssetGrid.new()
	grid.panel = self
	grid.sub_id = s["id"]
	grid.name = "Grid"
	grid.icon_mode = ItemList.ICON_MODE_TOP
	grid.max_columns = 0
	grid.same_column_width = true
	grid.fixed_column_width = thumb_size + 28
	grid.fixed_icon_size = Vector2i(thumb_size, thumb_size)
	grid.max_text_lines = 2
	grid.auto_height = true
	grid.select_mode = ItemList.SELECT_SINGLE
	grid.visible = searching or not bool(s.get("collapsed", false))
	for it in items:
		var tex: Texture2D = null
		var img := Image.load_from_file(Lib.thumb_path(it)) if FileAccess.file_exists(Lib.thumb_path(it)) else null
		if img:
			tex = ImageTexture.create_from_image(img)
		var idx := grid.add_item(String(it["name"]), tex)
		grid.set_item_metadata(idx, it)
		grid.set_item_tooltip(idx, "%s\nArrastra al artboard o a otra sección · doble clic: colocar" % it["name"])
	if items.is_empty():
		var idx2 := grid.add_item("Suelta aquí")
		grid.set_item_selectable(idx2, false)
		grid.set_item_disabled(idx2, true)
		grid.set_item_metadata(idx2, {})
	grid.item_activated.connect(func(i: int) -> void: place_item(grid.get_item_metadata(i)))
	grid.item_clicked.connect(func(i: int, at: Vector2, b: int) -> void: _on_item_clicked(grid, i, at, b))
	box.add_child(grid)
	return box

## Sección de una subcategoría (para tests y menús).
func section(sub_id: String) -> Control:
	return _sections.get_node_or_null("Sec_" + sub_id)

func grid_of(sub_id: String) -> ItemList:
	var s := section(sub_id)
	return s.get_node("Grid") if s else null

func header_of(sub_id: String) -> Control:
	var s := section(sub_id)
	return s.find_child("Header", true, false) if s else null

# ── acciones ─────────────────────────────────────────────────────────────────
## Guarda la selección actual como recurso en `sub_id` (o la sección activa).
func add_selection(name: String = "", sub_id: String = "") -> Dictionary:
	var api := _api()
	if api == null or api.selection().is_empty():
		_status.text = "Selecciona primero lo que quieras guardar."
		return {}
	var tops: Array = []
	var ab: Node = null
	for n in api.selection():
		var top: Node = n
		while top.get_parent() and not ("artboard_size" in top.get_parent()):
			top = top.get_parent()
		if top.get_parent() and not (top in tops):
			if ab == null:
				ab = top.get_parent()
			if top.get_parent() == ab:
				tops.append(top)
	var it := Lib.add_from_nodes(current_cat, ab, tops, name, sub_id if sub_id != "" else current_sub)
	refresh()
	_status.text = ("✓ «%s» guardado en Recursos" % it["name"]) if not it.is_empty() else "No se pudo guardar"
	return it

func place_item(it: Dictionary, at: Vector2 = Vector2.INF) -> bool:
	var api := _api()
	if api == null or it.is_empty():
		return false
	return bool(Lib.place(it, api.artboard(), at).get("ok", false))

## Archivos soltados en una sección → nuevos recursos ahí.
func add_files(paths: PackedStringArray, sub_id: String = "") -> int:
	var n := 0
	for p in paths:
		var it: Dictionary = await Lib.add_from_file(current_cat, p, sub_id if sub_id != "" else current_sub)
		if not it.is_empty():
			n += 1
	refresh()
	_status.text = "✓ %d recurso(s) añadido(s)" % n if n > 0 else "Esos archivos no se pueden usar como recurso"
	return n

## Filas de Exportar soltadas en una sección → recursos.
func add_rows(rows: Array, sub_id: String) -> void:
	for r in rows:
		var nodes: Array = r.nodes if not r.nodes.is_empty() else r.artboard.get_children().filter(func(c) -> bool: return VectopenAPI.is_shape(c))
		Lib.add_from_nodes(current_cat, r.artboard, nodes, "", sub_id)
	refresh()

## Reordenar / mover un recurso (arrastrar para organizar).
func move_item(asset_id: String, to_sub: String, index: int = -1) -> void:
	Lib.move_asset(asset_id, to_sub, index)
	current_sub = to_sub
	refresh()

## Reordenar secciones: `sub_id` pasa a la posición de `before_sub`.
func move_section(sub_id: String, before_sub: String) -> void:
	if sub_id == before_sub:
		return
	var subs: Array = Lib.category(current_cat).get("subs", [])
	var idx := -1
	for i in subs.size():
		if subs[i]["id"] == before_sub:
			idx = i
	Lib.move_subcategory(sub_id, current_cat, idx)
	refresh()

func _route_os_drop(files: PackedStringArray, screen_pos: Vector2) -> bool:
	if not (is_visible_in_tree() and get_global_rect().has_point(screen_pos)):
		return false
	# otro panel ENCIMA en ese punto (p. ej. Exportar, abajo a todo el ancho)
	for n in get_tree().get_nodes_in_group("vectopen_overlay_panel"):
		if n is Control and (n as Control).is_visible_in_tree() and (n as Control).get_global_rect().has_point(screen_pos):
			return false
	var target := current_sub
	for s in _sections.get_children():
		if (s as Control).get_global_rect().has_point(screen_pos):
			target = String(s.name).trim_prefix("Sec_")
	add_files(files, target)
	return true

# ── menús ────────────────────────────────────────────────────────────────────
func _on_cat_menu(id: int) -> void:
	match id:
		6:
			_ask("Nueva subcategoría", "Sección", func(t: String) -> void:
				current_sub = Lib.add_subcategory(current_cat, t)
				refresh())
		0:
			_ask("Nueva categoría", "Logos", func(t: String) -> void:
				current_cat = Lib.add_category(t)
				current_sub = ""
				refresh())
		1:
			_ask("Renombrar categoría", String(Lib.category(current_cat).get("name", "")), func(t: String) -> void:
				Lib.rename_category(current_cat, t)
				refresh())
		2:
			_confirm("¿Borrar la categoría «%s» y todos sus recursos?" % Lib.category(current_cat).get("name", ""), func() -> void:
				Lib.remove_category(current_cat)
				current_cat = ""
				refresh())
		3, 4:
			var only: Array = [current_cat] if id == 3 else []
			var nm := String(Lib.category(current_cat).get("name", "Recursos")) if id == 3 else "Recursos Vectopen"
			_pick_file(FileDialog.FILE_MODE_SAVE_FILE, nm + ".vopassets", func(p: String) -> void:
				var path := p if p.get_extension() == "vopassets" else p + ".vopassets"
				var err := Lib.export_package(path, only)
				_status.text = ("✓ Paquete guardado: " + path.get_file()) if err == OK else "No se pudo guardar el paquete")
		5:
			_pick_file(FileDialog.FILE_MODE_OPEN_FILE, "", func(p: String) -> void: import_package(p))

func import_package(path: String) -> Dictionary:
	var r := Lib.import_package(path)
	refresh()
	_status.text = ("✓ %d recurso(s) importado(s)" % int(r["items"])) if r["ok"] else String(r["error"])
	return r

func _on_sub_menu(id: int) -> void:
	var s := Lib.subcategory(_menu_sub_id)
	if s.is_empty():
		return
	match id:
		0:
			add_selection("", _menu_sub_id)
		1:
			_ask("Renombrar sección", String(s["name"]), func(t: String) -> void:
				Lib.rename_subcategory(_menu_sub_id, t)
				refresh())
		2:
			_move_cat_menu.clear()
			for c in Lib.categories():
				if c["id"] != current_cat:
					_move_cat_menu.add_item(String(c["name"]))
					_move_cat_menu.set_item_metadata(_move_cat_menu.item_count - 1, c["id"])
			if _move_cat_menu.item_count == 0:
				_status.text = "Crea otra categoría primero (menú ⋯ de arriba)."
				return
			ProUIStyle.style_popup(_move_cat_menu)
			_move_cat_menu.position = _sub_menu.position
			_move_cat_menu.popup()
		3:
			_confirm("¿Borrar la sección «%s» y sus %d recursos?" % [s["name"], (s["items"] as Array).size()], func() -> void:
				Lib.remove_subcategory(_menu_sub_id)
				refresh())

func _on_move_sub_to_cat(i: int) -> void:
	Lib.move_subcategory(_menu_sub_id, String(_move_cat_menu.get_item_metadata(i)))
	refresh()

func _on_item_clicked(grid: ItemList, index: int, at: Vector2, button: int) -> void:
	var meta: Dictionary = grid.get_item_metadata(index)
	if meta.is_empty():
		return
	current_sub = grid.get("sub_id")
	if button != MOUSE_BUTTON_RIGHT:
		return
	_menu_item_id = String(meta["id"])
	grid.select(index)
	_item_menu.position = Vector2i(grid.get_screen_position() + at)
	ProUIStyle.style_popup(_item_menu)
	_item_menu.popup()

func _on_item_menu(id: int) -> void:
	var it := Lib.find_asset(_menu_item_id)
	if it.is_empty():
		return
	match id:
		0:
			place_item(it)
		1:
			_ask("Renombrar recurso", String(it["name"]), func(t: String) -> void:
				Lib.rename_asset(_menu_item_id, t)
				refresh())
		3:
			_confirm("¿Borrar «%s»?" % it["name"], func() -> void:
				Lib.remove_asset(_menu_item_id)
				refresh())

func _popup_at(menu: PopupMenu, anchor: Control) -> void:
	ProUIStyle.style_popup(menu)
	menu.position = Vector2i(anchor.get_screen_position() + Vector2(0, anchor.size.y))
	menu.popup()

func _ask(title: String, value: String, done: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = title
	var le := LineEdit.new()
	le.text = value
	le.custom_minimum_size = Vector2(240, 0)
	dlg.add_child(le)
	dlg.register_text_enter(le)
	dlg.confirmed.connect(func() -> void:
		if le.text.strip_edges() != "":
			done.call(le.text.strip_edges())
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
	le.select_all()
	le.grab_focus.call_deferred()

func _confirm(text: String, done: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = text
	dlg.confirmed.connect(func() -> void:
		dlg.queue_free()
		done.call())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

func _pick_file(mode: int, file_name: String, done: Callable) -> void:
	var fd := FileDialog.new()
	fd.file_mode = mode
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.filters = PackedStringArray(["*.vopassets ; Paquete de recursos de Vectopen"])
	fd.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if file_name != "":
		fd.current_file = file_name
	fd.file_selected.connect(func(p: String) -> void:
		done.call(p)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(760, 480))

# ── aspecto ──────────────────────────────────────────────────────────────────
func _small_button(parent: Control, text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(28, 0)
	b.set_meta("small", true)
	parent.add_child(b)
	return b

func restyle() -> void:
	ProUIStyle.style_option(_cat)
	ProUIStyle.style_line_edit(_search)
	ProUIStyle.style_slider(_zoom)
	for b in find_children("*", "Button", true, false):
		if b == _add_btn or b.has_meta("small"):
			b.add_theme_font_size_override("font_size", 11)
			b.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
			b.add_theme_stylebox_override("normal", FxUI.flat(FxUI.c("INPUT_BG"), 5, FxUI.c("INPUT_BORDER"), 8, 2))
			b.add_theme_stylebox_override("hover", FxUI.flat(FxUI.c("BUTTON_HOVER"), 5, FxUI.c("BORDER_STRONG"), 8, 2))
			b.add_theme_stylebox_override("pressed", FxUI.flat(FxUI.c("BUTTON_PRESSED"), 5, FxUI.c("ACCENT"), 8, 2))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		elif b is SectionHeader:
			var active: bool = b.get_meta("active", false)
			b.add_theme_font_size_override("font_size", 11)
			b.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT") if active else FxUI.c("TEXT_SECONDARY"))
			b.add_theme_color_override("font_hover_color", FxUI.c("PANEL_TEXT"))
			var bg := FxUI.c("ACCENT_SOFT") if b.get_meta("drop_hover", false) else (FxUI.c("SURFACE_RAISED") if active else Color(0, 0, 0, 0))
			b.add_theme_stylebox_override("normal", FxUI.flat(bg, 4, FxUI.c("ACCENT") if b.get_meta("drop_hover", false) else Color(0, 0, 0, 0), 6, 1))
			b.add_theme_stylebox_override("hover", FxUI.flat(FxUI.c("BUTTON_HOVER"), 4, Color(0, 0, 0, 0), 6, 1))
			b.add_theme_stylebox_override("pressed", FxUI.flat(FxUI.c("BUTTON_PRESSED"), 4, Color(0, 0, 0, 0), 6, 1))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for g in find_children("*", "ItemList", true, false):
		var hov: bool = g.get_meta("drop_hover", false)
		g.add_theme_stylebox_override("panel", FxUI.flat(FxUI.c("ACCENT_SOFT") if hov else FxUI.c("INPUT_BG"), 6, FxUI.c("ACCENT") if hov else FxUI.c("BORDER"), 4, 4))
		g.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		g.add_theme_stylebox_override("selected", FxUI.flat(FxUI.c("ACCENT_SOFT"), 6))
		g.add_theme_stylebox_override("selected_focus", FxUI.flat(FxUI.c("ACCENT_SOFT"), 6))
		g.add_theme_stylebox_override("hovered", FxUI.flat(FxUI.c("BUTTON_HOVER"), 6))
		g.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
		g.add_theme_color_override("font_selected_color", FxUI.c("PANEL_TEXT"))
		g.add_theme_color_override("font_disabled_color", FxUI.c("TEXT_SECONDARY"))
		g.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
	for m in [_cat_menu, _item_menu, _sub_menu, _move_cat_menu]:
		ProUIStyle.style_popup(m)

func _set_drop_hover(c: Control, on: bool) -> void:
	if bool(c.get_meta("drop_hover", false)) != on:
		c.set_meta("drop_hover", on)
		restyle()

## Datos de arrastre que entiende el panel.
static func _kind(data: Variant) -> String:
	if not (data is Dictionary):
		return ""
	if String(data.get("type", "")) == "asset_section":
		return "section"
	if bool(data.get("asset", false)):
		return "asset"
	if String(data.get("type", "")) in ["recent_file", "external_file"]:
		return "file"
	if String(data.get("type", "")) == "export_element":
		return "rows"
	return ""

# ═══════════════════════════════ cuadrícula ══════════════════════════════════
class AssetGrid extends ItemList:
	var panel: Node
	var sub_id := ""
	func _get_drag_data(at: Vector2) -> Variant:
		var i := get_item_at_position(at, true)
		if i < 0 or (get_item_metadata(i) as Dictionary).is_empty():
			return null
		var it: Dictionary = get_item_metadata(i)
		var prev := TextureRect.new()
		prev.texture = get_item_icon(i)
		prev.custom_minimum_size = Vector2(56, 56)
		prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		set_drag_preview(prev)
		# tipo recent_file: soltado sobre el artboard se importa (capa de soltar)
		return {"type": "recent_file", "path": Lib.vop_path(it), "name": it["name"], "asset": true, "asset_id": it["id"]}
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok: bool = panel._kind(data) in ["asset", "file", "rows"]
		panel._set_drop_hover(self, ok)
		return ok
	func _drop_data(_at: Vector2, data: Variant) -> void:
		panel._set_drop_hover(self, false)
		match panel._kind(data):
			"asset":
				# posición de inserción: el recurso bajo el ratón (o al final)
				var local: Vector2 = get_global_transform().affine_inverse() * panel._last_mouse
				var i := get_item_at_position(local, true)
				var idx := i if i >= 0 and not (get_item_metadata(i) as Dictionary).is_empty() else -1
				panel.move_item(String(data["asset_id"]), sub_id, idx)
			"file":
				panel.add_files(PackedStringArray([String(data["path"])]), sub_id)
			"rows":
				panel.add_rows(data.get("rows", []), sub_id)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
			if panel:
				panel._set_drop_hover(self, false)

# ═══════════════════════════ cabecera de sección ═════════════════════════════
class SectionHeader extends Button:
	var panel: Node
	var sub_id := ""
	func _get_drag_data(_at: Vector2) -> Variant:
		var l := Label.new()
		l.text = "  " + text
		set_drag_preview(l)
		return {"type": "asset_section", "sub_id": sub_id}
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var k: String = panel._kind(data)
		var ok: bool = (k == "section" and String(data["sub_id"]) != sub_id) or k in ["asset", "file", "rows"]
		panel._set_drop_hover(self, ok)
		return ok
	func _drop_data(_at: Vector2, data: Variant) -> void:
		panel._set_drop_hover(self, false)
		match panel._kind(data):
			"section": panel.move_section(String(data["sub_id"]), sub_id)
			"asset": panel.move_item(String(data["asset_id"]), sub_id, -1)
			"file": panel.add_files(PackedStringArray([String(data["path"])]), sub_id)
			"rows": panel.add_rows(data.get("rows", []), sub_id)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
			if panel:
				panel._set_drop_hover(self, false)
