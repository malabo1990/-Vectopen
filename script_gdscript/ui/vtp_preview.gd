# =============================================================================
# RUTA: res://script_gdscript/ui/vtp_preview.gd
# VTP PREVIEW — fase 1 (§0 nonies): visor de documentos .vtp de SOLO LECTURA
# en su propia ventana, sin entrar en el editor ni tocar el documento abierto.
#   · mismo núcleo de lectura que el editor (canvas_serializer, carga por
#     páginas) en un SubViewport propio (no comparte mundo con el lienzo);
#   · modo seguro: no compila shaders del archivo ni carga rutas externas;
#   · zoom (rueda, + / −), desplazar (arrastrar), ajustar página / todo,
#     página anterior / siguiente, fondo claro / oscuro / cuadros;
#   · panel de información (ocultable): nombre, fecha, tamaño, páginas,
#     dimensiones de la página actual y nº de elementos.
# Abrir: VtpPreview.open(árbol, ruta) o desde Archivo ▸ «Vista previa…».
# =============================================================================
extends Window

const CS = preload("res://scripts/canvas/canvas_serializer.gd")
const BGS := [["Claro", Color(0.93, 0.93, 0.94)], ["Oscuro", Color(0.16, 0.16, 0.18)], ["Cuadros", Color(0, 0, 0, 0)]]

var path := ""
var pages: Array = []          # ArtboardEditor del visor
var page_i := 0
var _svc: SubViewportContainer
var _vp: SubViewport
var _doc: Node2D
var _cam: Camera2D
var _bg: ColorRect
var _checker: TextureRect
var _info: Label
var _info_panel: PanelContainer
var _lbl_page: Label
var _lbl_zoom: Label
var _bg_i := 0
var _dragging := false
# Explorador (fase 2): carpeta, lista de documentos con metadatos, filtro.
var folder := ""
var docs: Array = []          # [{path, name, mtime, size}]
var _list: ItemList
var _filter: LineEdit
var _lbl_folder: Label
var _explorer: VBoxContainer
const PREFS_PATH := "user://vectopen_files.cfg"
# Miniaturas (fase 3): PNG en caché por ruta + fecha + tamaño.
const THUMB_DIR := "user://thumbnails"
const THUMB_PX := 160
var thumbs := {}               # ruta → Texture2D
var _thumb_queue: Array = []
var _thumb_busy := false
var thumbs_made := 0           # cuántas se renderizaron (no venían de caché)

## Abre el visor (una ventana nueva) con `p`. Devuelve la ventana.
static func open(tree: SceneTree, p: String = "") -> Window:
	var w: Window = load("res://script_gdscript/ui/vtp_preview.gd").new()
	tree.root.add_child(w)
	# El tema de Vectopen (claro / oscuro) también en esta ventana.
	var tm := tree.root.get_node_or_null("ThemeManager")
	if tm and tm.has_method("adopt"):
		tm.adopt(w.get_node("UiRoot"))
	w.popup_centered(Vector2i(1100, 720))
	if p != "":
		w.set_folder(p.get_base_dir())
		w.load_file(p)
	else:
		w.set_folder(w._last_folder())
	return w

func _init() -> void:
	title = tr("Vista previa de documento")
	name = "VtpPreview"
	wrap_controls = false
	transient = false
	close_requested.connect(queue_free)
	var bgp := PanelContainer.new()   # fondo del tema detrás de barra y panel
	bgp.name = "UiRoot"
	bgp.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bgp)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	bgp.add_child(root)
	# ── barra ──
	var bar := HBoxContainer.new()
	bar.name = "Bar"
	bar.add_theme_constant_override("separation", 4)
	root.add_child(bar)
	_btn(bar, "Open", tr("Abrir…"), ask_file)
	_btn(bar, "Prev", "◀", func() -> void: go_page(page_i - 1))
	_lbl_page = Label.new()
	_lbl_page.name = "PageLabel"
	bar.add_child(_lbl_page)
	_btn(bar, "Next", "▶", func() -> void: go_page(page_i + 1))
	_btn(bar, "FitPage", tr("Ajustar página"), fit_page)
	_btn(bar, "FitAll", tr("Ajustar todo"), fit_all)
	_btn(bar, "ZoomOut", "−", func() -> void: zoom_by(1.0 / 1.25))
	_lbl_zoom = Label.new()
	_lbl_zoom.name = "ZoomLabel"
	_lbl_zoom.custom_minimum_size = Vector2(52, 0)
	_lbl_zoom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_lbl_zoom)
	_btn(bar, "ZoomIn", "+", func() -> void: zoom_by(1.25))
	_btn(bar, "Background", tr("Fondo"), cycle_background)
	_btn(bar, "Info", tr("Información"), func() -> void: _info_panel.visible = not _info_panel.visible)
	_btn(bar, "Explorer", tr("Explorador"), func() -> void: _explorer.visible = not _explorer.visible)
	# ── zona central + panel ──
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)
	# ── explorador (izquierda) ──
	_explorer = VBoxContainer.new()
	_explorer.name = "Explorer"
	_explorer.custom_minimum_size = Vector2(250, 0)
	body.add_child(_explorer)
	var frow := HBoxContainer.new()
	_explorer.add_child(frow)
	_btn(frow, "Folder", tr("Carpeta…"), ask_folder)
	_lbl_folder = Label.new()
	_lbl_folder.name = "FolderLabel"
	_lbl_folder.clip_text = true
	_lbl_folder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(_lbl_folder)
	_filter = LineEdit.new()
	_filter.name = "Filter"
	_filter.placeholder_text = tr("Buscar documento…")
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_t: String) -> void: _fill_list())
	_explorer.add_child(_filter)
	_list = ItemList.new()
	_list.name = "Docs"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.max_columns = 1
	_list.item_selected.connect(func(i: int) -> void:
		var p := String(_list.get_item_metadata(i))
		if p != path:
			load_file(p))
	_explorer.add_child(_list)
	var stage := Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	body.add_child(stage)
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_bg)
	_checker = TextureRect.new()
	_checker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_checker.stretch_mode = TextureRect.STRETCH_TILE
	_checker.texture = _checker_tex()
	_checker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_checker)
	_svc = SubViewportContainer.new()
	_svc.name = "Stage"
	_svc.stretch = true
	_svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_svc.gui_input.connect(_on_stage_input)
	stage.add_child(_svc)
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_2d = Viewport.MSAA_4X
	_vp.handle_input_locally = false
	_svc.add_child(_vp)
	_doc = Node2D.new()
	_doc.name = "PreviewDocument"
	_vp.add_child(_doc)
	_cam = Camera2D.new()
	_vp.add_child(_cam)
	_cam.make_current()
	_info_panel = PanelContainer.new()
	_info_panel.name = "InfoPanel"
	_info_panel.custom_minimum_size = Vector2(240, 0)
	body.add_child(_info_panel)
	_info = Label.new()
	_info.name = "Info"
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_panel.add_child(_info)
	_apply_background()
	_update_labels()

func _btn(bar: Control, nm: String, txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	bar.add_child(b)
	return b

static func _checker_tex() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			img.set_pixel(x, y, Color(0.8, 0.8, 0.8) if (x / 8 + y / 8) % 2 == 0 else Color(0.95, 0.95, 0.95))
	return ImageTexture.create_from_image(img)

# ── explorador ───────────────────────────────────────────────────────────────
func ask_folder() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fd.access = FileDialog.ACCESS_FILESYSTEM
	if folder != "":
		fd.current_dir = folder
	add_child(fd)
	fd.dir_selected.connect(func(d: String) -> void:
		set_folder(d)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered(Vector2i(800, 520))

## Lista los documentos de `d` (no recursivo), del más reciente al más antiguo.
func set_folder(d: String) -> void:
	folder = d
	docs.clear()
	var da := DirAccess.open(d)
	if da:
		for f in da.get_files():
			var ext := f.get_extension().to_lower()
			if ext in ["vtp", "vtc"]:
				var fp := d.path_join(f)
				var fa := FileAccess.open(fp, FileAccess.READ)
				var sz := fa.get_length() if fa else 0
				docs.append({"path": fp, "name": f, "mtime": FileAccess.get_modified_time(fp), "size": sz})
	docs.sort_custom(func(a, b) -> bool: return int(a["mtime"]) > int(b["mtime"]))
	_list.fixed_icon_size = Vector2i(THUMB_PX / 2, THUMB_PX / 2)
	_thumb_queue = docs.map(func(x): return x)
	_next_thumb.call_deferred()
	_lbl_folder.text = d.get_file() if d.get_file() != "" else d
	_lbl_folder.tooltip_text = d
	var cfg := ConfigFile.new()
	cfg.load(PREFS_PATH)
	cfg.set_value("preview", "folder", d)
	cfg.save(PREFS_PATH)
	_fill_list()

func _fill_list() -> void:
	_list.clear()
	var q := _filter.text.strip_edges().to_lower()
	for d in docs:
		if q != "" and not String(d["name"]).to_lower().contains(q):
			continue
		var when := Time.get_datetime_string_from_unix_time(int(d["mtime"]), true).substr(0, 16)
		var i := _list.add_item("%s  ·  %s  ·  %.0f KB" % [d["name"], when, float(d["size"]) / 1024.0])
		_list.set_item_metadata(i, d["path"])
		_list.set_item_tooltip(i, String(d["path"]))
		if thumbs.has(d["path"]):
			_list.set_item_icon(i, thumbs[d["path"]])
		if String(d["path"]) == path:
			_list.select(i)

# ── miniaturas ───────────────────────────────────────────────────────────────
## Clave de caché: cambia si el documento cambia (fecha o tamaño) → la
## miniatura antigua deja de usarse sola.
static func thumb_key(d: Dictionary) -> String:
	return "%s_%d_%d" % [String(d["path"]).md5_text().substr(0, 16), int(d["mtime"]), int(d["size"])]

static func thumb_path(d: Dictionary) -> String:
	return THUMB_DIR.path_join(thumb_key(d) + ".png")

## Una miniatura cada vez (sin bloquear la ventana): de la caché o renderizada.
func _next_thumb() -> void:
	if _thumb_busy or _thumb_queue.is_empty() or not is_inside_tree():
		return
	_thumb_busy = true
	var d: Dictionary = _thumb_queue.pop_front()
	var tp := thumb_path(d)
	var tex: Texture2D = null
	if FileAccess.file_exists(tp):
		var img := Image.load_from_file(ProjectSettings.globalize_path(tp))
		if img and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		tex = await _render_thumb(String(d["path"]))
		if tex:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(THUMB_DIR))
			tex.get_image().save_png(ProjectSettings.globalize_path(tp))
			thumbs_made += 1
	if tex and is_inside_tree():
		thumbs[d["path"]] = tex
		for i in _list.item_count:
			if String(_list.get_item_metadata(i)) == String(d["path"]):
				_list.set_item_icon(i, tex)
	_thumb_busy = false
	if is_inside_tree():
		_next_thumb.call_deferred()

## Primera página del documento en un SubViewport propio (modo seguro).
func _render_thumb(p: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(THUMB_PX, THUMB_PX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var holder := Node2D.new()
	vp.add_child(holder)
	CS.safe_mode = true
	var manifest: Dictionary = CS.rebuild_from_vtc(holder, p)
	var first: Node2D = null
	for c in holder.get_children():
		if c is ArtboardEditor:
			if c.is_in_group("artboards"):
				c.remove_from_group("artboards")
			if first == null:
				first = c
				if c.is_dormant:
					if c.has_method("wake_now"):
						c.wake_now()
					else:
						c.wake()
			else:
				c.visible = false
	CS.safe_mode = false
	if manifest.is_empty() or first == null:
		vp.queue_free()
		return null
	var cam := Camera2D.new()
	vp.add_child(cam)
	cam.make_current()
	var sz: Vector2 = first.artboard_size
	var z := minf(THUMB_PX / maxf(sz.x, 1.0), THUMB_PX / maxf(sz.y, 1.0)) * 0.94
	cam.zoom = Vector2(z, z)
	cam.position = first.position + sz / 2.0
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return ImageTexture.create_from_image(img) if img else null

func _last_folder() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) == OK:
		var f := String(cfg.get_value("preview", "folder", ""))
		if f != "" and DirAccess.dir_exists_absolute(f):
			return f
	return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)

# ── archivo ──────────────────────────────────────────────────────────────────
func ask_file() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.vtp, *.vtc ; Vectopen"])
	add_child(fd)
	fd.file_selected.connect(func(p: String) -> void:
		load_file(p)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered(Vector2i(800, 520))

## Carga `p` en el visor (solo lectura). false si no es un documento válido.
func load_file(p: String) -> bool:
	for c in _doc.get_children():
		_doc.remove_child(c)
		c.queue_free()
	pages.clear()
	path = p
	CS.safe_mode = true
	var manifest: Dictionary = CS.rebuild_from_vtc(_doc, p)
	CS.safe_mode = false
	if manifest.is_empty():
		_info.text = "%s\n\n%s" % [p.get_file(), tr("No se pudo leer: archivo dañado o de otra versión.")]
		_update_labels()
		return false
	for c in _doc.get_children():
		if c is ArtboardEditor:
			# Fuera del grupo global: el editor no debe ver estas páginas.
			if c.is_in_group("artboards"):
				c.remove_from_group("artboards")
			if c.is_dormant:
				# todo de golpe (wake() va por tandas en varios fotogramas y
				# el modo seguro debe cubrir toda la carga)
				CS.safe_mode = true
				if c.has_method("wake_now"):
					c.wake_now()
				else:
					c.wake()
				CS.safe_mode = false
			pages.append(c)
	title = "%s — %s" % [tr("Vista previa"), p.get_file()]
	page_i = 0
	_fill_info(manifest)
	fit_page.call_deferred()
	if _list and folder == p.get_base_dir():
		_fill_list()
	return true

func _fill_info(manifest: Dictionary) -> void:
	var t := "%s\n\n" % path.get_file()
	if FileAccess.file_exists(path):
		var mt := FileAccess.get_modified_time(path)
		t += "%s: %s\n" % [tr("Modificado"), Time.get_datetime_string_from_unix_time(mt, true)]
		t += "%s: %.1f KB\n" % [tr("Tamaño"), FileAccess.get_file_as_bytes(path).size() / 1024.0]
	t += "%s: %d\n" % [tr("Páginas"), pages.size()]
	var n := 0
	for pg in pages:
		n += pg.get_child_count()
	t += "%s: %d\n" % [tr("Elementos (1.er nivel)"), n]
	if manifest.has("version"):
		t += "%s: %s\n" % [tr("Versión del formato"), str(manifest["version"])]
	t += "\n%s" % tr("Solo lectura: el visor no modifica el documento ni ejecuta su código.")
	_info.text = t

# ── navegación ───────────────────────────────────────────────────────────────
func current_page() -> Node2D:
	return pages[page_i] if page_i >= 0 and page_i < pages.size() else null

func go_page(i: int) -> void:
	if pages.is_empty():
		return
	page_i = clampi(i, 0, pages.size() - 1)
	fit_page()

func _rect_of(pg: Node2D) -> Rect2:
	return Rect2(pg.position, pg.artboard_size)

func _fit(r: Rect2) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var vs := Vector2(_vp.size)
	if vs.x < 8.0:
		vs = Vector2(size) - Vector2(260, 40)
	var z := minf(vs.x / r.size.x, vs.y / r.size.y) * 0.92
	_cam.zoom = Vector2(z, z)
	_cam.position = r.get_center()
	_update_labels()

func fit_page() -> void:
	var pg := current_page()
	if pg:
		_fit(_rect_of(pg))

func fit_all() -> void:
	if pages.is_empty():
		return
	var r := _rect_of(pages[0])
	for pg in pages:
		r = r.merge(_rect_of(pg))
	_fit(r)

func zoom_by(k: float, at_screen: Vector2 = Vector2.INF) -> void:
	var old := _cam.zoom.x
	var z := clampf(old * k, 0.02, 64.0)
	if at_screen != Vector2.INF:
		var vs := Vector2(_vp.size)
		var world_before := _cam.position + (at_screen - vs / 2.0) / old
		_cam.zoom = Vector2(z, z)
		_cam.position = world_before - (at_screen - vs / 2.0) / z
	else:
		_cam.zoom = Vector2(z, z)
	_update_labels()

func cycle_background() -> void:
	_bg_i = (_bg_i + 1) % BGS.size()
	_apply_background()

func _apply_background() -> void:
	_bg.color = BGS[_bg_i][1]
	_checker.visible = String(BGS[_bg_i][0]) == "Cuadros"

func _update_labels() -> void:
	if _lbl_page:
		var pg := current_page()
		_lbl_page.text = ("%d / %d  %s  %d × %d px" % [page_i + 1, pages.size(), String(pg.name), int(pg.artboard_size.x), int(pg.artboard_size.y)]) if pg else tr("Sin documento")
	if _lbl_zoom and _cam:
		_lbl_zoom.text = "%d %%" % int(round(_cam.zoom.x * 100.0))

func _on_stage_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.15, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.15, mb.position)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mb.pressed
	elif ev is InputEventMouseMotion and _dragging:
		_cam.position -= (ev as InputEventMouseMotion).relative / _cam.zoom.x

func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed:
		return
	match (ev as InputEventKey).keycode:
		KEY_PAGEDOWN, KEY_RIGHT:
			go_page(page_i + 1)
		KEY_PAGEUP, KEY_LEFT:
			go_page(page_i - 1)
		KEY_0:
			fit_page()
		KEY_1:
			fit_all()
		KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
			zoom_by(1.25)
		KEY_MINUS, KEY_KP_SUBTRACT:
			zoom_by(1.0 / 1.25)
		KEY_ESCAPE:
			queue_free()
