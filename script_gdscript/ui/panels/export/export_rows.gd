# =============================================================================
# RUTA: res://script_gdscript/ui/panels/export/export_rows.gd
# Columna EXPORTAR del panel de archivos (diseño "smart export", mayo 2025):
#
#   · Lista de lo exportable: Artboards | Capas | Selección. Cada fila lleva su
#     formato (y escala si es imagen).
#   · SIN diálogos: arrastra la fila a una carpeta de la lista de la izquierda
#     y se exporta ahí (nunca sobrescribe: «nombre (2).svg»). Soltarla en
#     «Recientes» la guarda en la Biblioteca (VOP) para reutilizarla.
#   · Suelta archivos sobre una fila (desde el explorador o desde la lista)
#     y se CONVIERTEN al formato de la fila, junto al original.
#   · Alternativas sin arrastrar (accesibilidad): doble clic en una fila o
#     «Exportar marcados» (Ctrl+E) → carpeta de destino.
#   · Resultado en una línea: «✓ logo.svg → Descargas · Abrir · Deshacer».
# Motor: ImportExportManager.export_nodes / convert_file.
# =============================================================================
extends VBoxContainer

const FxUI = preload("res://script_gdscript/ui/panels/effects/fx_ui.gd")
const PANEL_NAME := "ExportRows"
const GROUP := "vectopen_export_rows"
const FORMATS := ["SVG", "PNG", "JPEG", "WEBP", "PDF", "EPS", "VOP", "TSCN", "SCN"]
const SCALES := [1.0, 2.0, 3.0, 4.0, 0.5]
const CFG := "user://vectopen_export.cfg"
const ICONS := {"artboard": "res://icon/UI/frame-alt.svg", "rectangle": "res://icon/UI/square.svg",
	"ellipse": "res://icon/UI/circle-spark.svg", "star": "res://icon/UI/star.svg",
	"polygon": "res://icon/UI/star-dashed.svg", "path": "res://icon/UI/design_nodoblack.svg",
	"text": "res://icon/UI/text-square.svg", "image": "res://icon/UI/media-image.svg",
	"group": "res://icon/UI/folder.svg", "model3d": "res://icon/UI/cube.svg"}

var scope := "artboards"          # artboards | layers | selection
var dest_dir := ""
var transparent := true
var text_curves := false
var quality := 92.0

var _tabs: HBoxContainer = null
var _list: VBoxContainer = null
var _hint: Label = null
var _dest_btn: Button = null
var _dest_menu: PopupMenu = null
var _chk_transp: CheckBox = null
var _chk_curves: CheckBox = null
var _status: RichTextLabel = null
var _export_btn: Button = null
var _last_written: PackedStringArray = []
var _refresh_pending := false
var _busy := false

## Monta la columna dentro del nodo ExportPanel del panel de archivos.
static func install(host: Control) -> Control:
	if host == null:
		return null
	var existing := host.find_child(PANEL_NAME, true, false)
	if existing:
		return existing
	for c in host.get_children():
		host.remove_child(c)
		c.queue_free()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	host.add_child(margin)
	var panel: Control = load("res://script_gdscript/ui/panels/export/export_rows.gd").new()
	panel.name = PANEL_NAME
	margin.add_child(panel)
	return panel

func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(330, 0)
	var head := HBoxContainer.new()
	add_child(head)
	var title := Label.new()
	title.text = "EXPORTAR"
	title.set_meta("muted", true)
	title.add_theme_font_size_override("font_size", 11)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_tabs = HBoxContainer.new()
	head.add_child(_tabs)
	for s in [["artboards", "Artboards"], ["layers", "Capas"], ["selection", "Selección"]]:
		var b := Button.new()
		b.text = s[1]
		b.name = s[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(set_scope.bind(s[0]))
		_tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)
	_hint = Label.new()
	_hint.text = "Arrastra una fila a una carpeta para exportarla · suelta archivos en una fila para convertirlos"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.set_meta("muted", true)
	add_child(_hint)
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 6)
	add_child(opts)
	_dest_btn = _button(opts, "Descargas", "Carpeta para «Exportar marcados» y el doble clic")
	_dest_btn.set_meta("icon_path", "res://icon/UI/folder.svg")
	_dest_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dest_btn.clip_text = true
	_dest_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dest_btn.pressed.connect(_show_dest_menu)
	var checks := HBoxContainer.new()
	checks.add_theme_constant_override("separation", 12)
	add_child(checks)
	_chk_transp = CheckBox.new()
	_chk_transp.text = "Sin fondo"
	_chk_transp.tooltip_text = "PNG, WEBP, SVG, PDF y EPS sin el fondo del artboard"
	_chk_transp.focus_mode = Control.FOCUS_NONE
	_chk_transp.add_theme_font_size_override("font_size", 11)
	_chk_transp.toggled.connect(func(on: bool) -> void:
		transparent = on
		_save_cfg())
	checks.add_child(_chk_transp)
	_chk_curves = CheckBox.new()
	_chk_curves.text = "Texto a curvas"
	_chk_curves.tooltip_text = "SVG: el texto como formas con tu fuente exacta (no editable como texto).\nPDF y EPS siempre llevan el texto como curvas."
	_chk_curves.focus_mode = Control.FOCUS_NONE
	_chk_curves.add_theme_font_size_override("font_size", 11)
	_chk_curves.toggled.connect(func(on: bool) -> void:
		text_curves = on
		_save_cfg())
	checks.add_child(_chk_curves)
	_export_btn = _button(self, "Exportar marcados  (Ctrl+E)", "Exporta las filas marcadas a la carpeta de destino")
	_export_btn.name = "ExportChecked"
	_export_btn.custom_minimum_size = Vector2(0, 32)
	_export_btn.remove_meta("bar_button")   # estilo propio (verde)
	_export_btn.pressed.connect(func() -> void: export_checked())
	# Línea de estado con aire: separada del botón, altura para 2 líneas.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	add_child(gap)
	_status = RichTextLabel.new()
	_status.name = "Status"
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.custom_minimum_size = Vector2(0, 34)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("normal_font_size", 12)
	_status.add_theme_constant_override("line_separation", 3)
	_status.meta_clicked.connect(_on_status_link)
	add_child(_status)
	_dest_menu = PopupMenu.new()
	_dest_menu.id_pressed.connect(_on_dest_menu)
	add_child(_dest_menu)

func _ready() -> void:
	add_to_group(GROUP)
	_load_cfg()
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge:
		for sig in ["selection_changed", "object_created", "object_deleted", "artboard_created", "artboard_deleted"]:
			if ge.has_signal(sig):
				ge.connect(sig, func(_a = null, _b = null) -> void: queue_refresh())
	var iem := get_node_or_null("/root/ImportExportManager")
	if iem and "drop_routers" in iem:
		iem.drop_routers.append(_route_os_drop)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: restyle())
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			queue_refresh())
	set_scope(scope)

func _exit_tree() -> void:
	var iem := get_node_or_null("/root/ImportExportManager")
	if iem and "drop_routers" in iem:
		iem.drop_routers.erase(_route_os_drop)

func _shortcut_input(ev: InputEvent) -> void:
	if is_visible_in_tree() and ev is InputEventKey and ev.pressed and not ev.echo \
			and ev.is_command_or_control_pressed() and ev.keycode == KEY_E:
		export_checked()
		get_viewport().set_input_as_handled()

func _api() -> VectopenAPI:
	var pm := get_node_or_null("/root/PluginManager")
	return pm.api if pm else null

# ── filas ────────────────────────────────────────────────────────────────────
func set_scope(s: String) -> void:
	scope = s
	FxUI.style_tabs(_tabs, _tabs.get_node(s) as Button)
	refresh()

func queue_refresh() -> void:
	if _refresh_pending or not is_inside_tree():
		return
	_refresh_pending = true
	(func() -> void:
		_refresh_pending = false
		if is_visible_in_tree() or not is_inside_tree():
			refresh()).call_deferred()

## Objetos de la fila: [artboard, [nodos]] — sin nodos = artboard entero.
func targets() -> Array:
	var api := _api()
	var out: Array = []
	if api == null:
		return out
	match scope:
		"artboards":
			for ab in api.artboards():
				out.append([ab, []])
		"layers":
			var ab := api.artboard()
			for n in api.shapes():
				out.append([ab, [n]])
		"selection":
			# 1.ª fila: TODA la selección en UN archivo (si hay más de un objeto
			# del mismo artboard); después, cada objeto por separado.
			var seen := {}
			for n in api.selection():
				# siempre el objeto de primer nivel del artboard
				var top: Node = n
				while top.get_parent() and not ("artboard_size" in top.get_parent()):
					top = top.get_parent()
				if top.get_parent() and not seen.has(top):
					seen[top] = true
					out.append([top.get_parent(), [top]])
			if out.size() > 1:
				var ab0: Node = out[0][0]
				var all: Array = []
				for t in out:
					if t[0] == ab0:
						all.append(t[1][0])
				if all.size() > 1:
					out.insert(0, [ab0, all])
	return out

func refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var api := _api()
	for t in targets():
		var ab: Node2D = t[0]
		var nodes: Array = t[1]
		var node: Node = ab if nodes.is_empty() else nodes[0]
		if nodes.size() > 1:
			_list.add_child(_make_row(ab, nodes, "Selección · %d objetos" % nodes.size(), "group"))
		else:
			_list.add_child(_make_row(ab, nodes, String(node.name), "artboard" if nodes.is_empty() else (api.kind_of(node) if api else "group")))
	if _list.get_child_count() == 0:
		var l := Label.new()
		l.text = {"selection": "Selecciona objetos en el lienzo", "layers": "El artboard está vacío"}.get(scope, "No hay artboards")
		l.set_meta("muted", true)
		l.add_theme_font_size_override("font_size", 11)
		_list.add_child(l)
	restyle()

func _make_row(ab: Node2D, nodes: Array, title: String, kind: String) -> Control:
	var row := ExportRow.new()
	row.owner_panel = self
	row.artboard = ab
	row.nodes = nodes
	var key: Node = ab if nodes.is_empty() else nodes[0]
	row.format = String(key.get_meta("export_format", "PNG" if kind in ["artboard", "image"] else "SVG"))
	row.export_scale = float(key.get_meta("export_scale", 1.0))
	row.build(title, kind)
	return row

func rows() -> Array:
	return _list.get_children().filter(func(c) -> bool: return c is ExportRow)

# ── exportar ─────────────────────────────────────────────────────────────────
func settings_for(row: ExportRow) -> Dictionary:
	return {"scale": row.export_scale, "quality": quality, "transparent": transparent, "text_curves": text_curves}

## Exporta una fila en `dir`. Devuelve la ruta escrita ("" si falló).
func export_row(row: ExportRow, dir: String) -> String:
	var iem := get_node_or_null("/root/ImportExportManager")
	if iem == null or not is_instance_valid(row.artboard):
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var base := String((row.artboard if row.nodes.is_empty() else row.nodes[0]).name)
	if row.nodes.size() > 1:
		base = "Selección"
	if row.format in ["PNG", "JPEG", "WEBP"] and row.export_scale != 1.0:
		base += "@%sx" % str(row.export_scale).trim_suffix(".0")
	var path: String = iem.unique_path(dir, base, iem.extension_for(row.format))
	var err: Error = await iem.export_nodes(row.artboard, row.nodes, row.format, path, settings_for(row))
	return path if err == OK else ""

## Exporta las filas indicadas (o las marcadas) en `dir` (o el destino).
func export_rows_to(list: Array, dir: String) -> PackedStringArray:
	if _busy or list.is_empty():
		return PackedStringArray()
	_busy = true
	_set_status("Exportando…", true)
	var written := PackedStringArray()
	var failed := 0
	for r in list:
		var p := await export_row(r, dir)
		if p != "":
			written.append(p)
		else:
			failed += 1
	_busy = false
	_last_written = written
	if dir != dest_dir and not dir.begins_with(ProjectSettings.globalize_path("user://")):
		dest_dir = dir
		_save_cfg()
		_update_dest()
	_report(written, failed, dir)
	return written

func export_checked() -> PackedStringArray:
	var checked := rows().filter(func(r) -> bool: return r.checked)
	if checked.is_empty():
		_set_status("Marca alguna fila (o arrástrala a una carpeta)", false)
		return PackedStringArray()
	return await export_rows_to(checked, dest_dir)

## Biblioteca: VOP reutilizables (soltar una fila en «Recientes»).
var library_override := ""   # tests

func library_dir() -> String:
	if library_override != "":
		return library_override
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	return (docs if docs != "" else OS.get_user_data_dir()).path_join("Vectopen").path_join("Biblioteca")

func save_to_library(list: Array) -> PackedStringArray:
	var saved := PackedStringArray()
	for r in list:
		var fmt: String = r.format
		r.format = "VOP"
		var p := await export_row(r, library_dir())
		r.format = fmt
		if p != "":
			saved.append(p)
			var rfm := get_node_or_null("/root/RecentFilesManager")
			if rfm and rfm.has_method("add_file"):
				rfm.add_file(p)
	_last_written = saved
	_report(saved, list.size() - saved.size(), library_dir())
	return saved

# ── convertir (soltar archivos en una fila) ──────────────────────────────────
func convert_files(files: PackedStringArray, row: ExportRow) -> PackedStringArray:
	var iem := get_node_or_null("/root/ImportExportManager")
	var done := PackedStringArray()
	var errors := PackedStringArray()
	_set_status("Convirtiendo %d archivo(s) a %s…" % [files.size(), row.format], true)
	for f in files:
		var r: Dictionary = await iem.convert_file(f, row.format, "", settings_for(row))
		if r["ok"]:
			done.append(String(r["path"]))
		else:
			errors.append("%s: %s" % [f.get_file(), r["error"]])
	_last_written = done
	_report(done, errors.size(), files[0].get_base_dir() if not files.is_empty() else "", errors)
	return done

## Archivos del explorador del sistema soltados sobre la ventana: si caen
## en una fila se convierten; si caen en este panel (fuera de filas), se
## dejan pasar (se importan).
func _route_os_drop(files: PackedStringArray, screen_pos: Vector2) -> bool:
	if not is_visible_in_tree():
		return false
	for r in rows():
		if (r as Control).get_global_rect().has_point(screen_pos):
			convert_files(files, r)
			return true
	return false

# ── estado ───────────────────────────────────────────────────────────────────
func _report(written: PackedStringArray, failed: int, dir: String, errors: PackedStringArray = []) -> void:
	if written.is_empty():
		_set_status("No se pudo exportar" + ((": " + errors[0]) if not errors.is_empty() else ""), false)
		return
	var what := written[0].get_file() if written.size() == 1 else "%d archivos" % written.size()
	var txt := "[color=#%s]✓[/color] %s → %s · [url=open]Abrir carpeta[/url] · [url=undo]Deshacer[/url]" % [
		_ok().to_html(false), what, _dir_label(dir)]
	if failed > 0:
		txt += "  [color=#%s](%d con error)[/color]" % [_err().to_html(false), failed]
	_status.text = txt

func _on_status_link(meta: Variant) -> void:
	match str(meta):
		"open":
			if not _last_written.is_empty():
				OS.shell_open(_last_written[0].get_base_dir())
		"undo":
			# Deshacer una exportación = borrar los archivos que acaba de escribir.
			for p in _last_written:
				if FileAccess.file_exists(p):
					DirAccess.remove_absolute(p)
			_set_status("Exportación deshecha (%d archivo(s) borrado(s))" % _last_written.size(), true)
			_last_written = PackedStringArray()
			var ffl := get_tree().get_first_node_in_group("vectopen_file_flow") if get_tree() else null
			if ffl and ffl.has_method("refresh_view"):
				ffl.refresh_view()

func _set_status(text: String, ok: bool) -> void:
	_status.text = "[color=#%s]%s[/color]" % [(FxUI.c("TEXT_SECONDARY") if ok else _err()).to_html(false), text]

func _ok() -> Color:
	var tm := get_node_or_null("/root/ThemeManager")
	return FxUI.c("AFFIRMATIVE") if tm and tm.Slot.has("AFFIRMATIVE") else Color(0.3, 0.75, 0.4)

func _err() -> Color:
	var tm := get_node_or_null("/root/ThemeManager")
	return FxUI.c("NEGATIVE") if tm and tm.Slot.has("NEGATIVE") else Color(0.9, 0.3, 0.3)

# ── destino ──────────────────────────────────────────────────────────────────
const QUICK := [["Descargas", OS.SYSTEM_DIR_DOWNLOADS], ["Escritorio", OS.SYSTEM_DIR_DESKTOP],
	["Documentos", OS.SYSTEM_DIR_DOCUMENTS], ["Imágenes", OS.SYSTEM_DIR_PICTURES]]

func _dir_label(dir: String) -> String:
	for q in QUICK:
		if OS.get_system_dir(q[1]) == dir:
			return q[0]
	if dir == library_dir():
		return "Biblioteca"
	return dir.get_file() if dir.get_file() != "" else dir

func _update_dest() -> void:
	_dest_btn.text = _dir_label(dest_dir)
	_dest_btn.tooltip_text = "Destino: %s\n(clic para cambiar)" % dest_dir

func _show_dest_menu() -> void:
	_dest_menu.clear()
	for i in QUICK.size():
		var d := OS.get_system_dir(QUICK[i][1])
		if d != "":
			_dest_menu.add_item(QUICK[i][0], i)
	_dest_menu.add_item("Biblioteca", 50)
	_dest_menu.add_separator()
	_dest_menu.add_item("Elegir carpeta…", 99)
	ProUIStyle.style_popup(_dest_menu)
	_dest_menu.position = Vector2i(_dest_btn.get_screen_position() + Vector2(0, _dest_btn.size.y))
	_dest_menu.popup()

func _on_dest_menu(id: int) -> void:
	if id == 99:
		var fd := FileDialog.new()
		fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.use_native_dialog = true
		fd.current_dir = dest_dir
		fd.dir_selected.connect(func(d: String) -> void:
			set_dest(d)
			fd.queue_free())
		fd.canceled.connect(fd.queue_free)
		add_child(fd)
		fd.popup_centered(Vector2i(760, 480))
		return
	set_dest(library_dir() if id == 50 else OS.get_system_dir(QUICK[id][1]))

func set_dest(dir: String) -> void:
	dest_dir = dir
	_update_dest()
	_save_cfg()

func _load_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	var def := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	dest_dir = String(cfg.get_value("export", "dest", def if def != "" else OS.get_user_data_dir()))
	# la carpeta guardada pudo borrarse o estar en un disco desmontado
	if not DirAccess.dir_exists_absolute(dest_dir):
		dest_dir = def if def != "" and DirAccess.dir_exists_absolute(def) else OS.get_user_data_dir()
	transparent = bool(cfg.get_value("export", "transparent", true))
	text_curves = bool(cfg.get_value("export", "text_curves", false))
	quality = float(cfg.get_value("export", "quality", 92.0))
	scope = String(cfg.get_value("export", "scope", "artboards"))
	_chk_transp.set_pressed_no_signal(transparent)
	_chk_curves.set_pressed_no_signal(text_curves)
	_update_dest()

func _save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("export", "dest", dest_dir)
	cfg.set_value("export", "transparent", transparent)
	cfg.set_value("export", "text_curves", text_curves)
	cfg.set_value("export", "quality", quality)
	cfg.set_value("export", "scope", scope)
	cfg.save(CFG)

# ── aspecto ──────────────────────────────────────────────────────────────────
func _button(parent: Control, text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 26)
	b.add_theme_font_size_override("font_size", 11)
	b.set_meta("bar_button", true)
	parent.add_child(b)
	return b

func restyle() -> void:
	if _tabs:
		FxUI.style_tabs(_tabs, _tabs.get_node(scope) as Button)
	for l in find_children("*", "Label", true, false):
		if l.has_meta("muted"):
			l.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
	for b in find_children("*", "Button", true, false):
		if b.has_meta("bar_button"):
			b.add_theme_stylebox_override("normal", FxUI.flat(FxUI.c("INPUT_BG"), 4, FxUI.c("INPUT_BORDER"), 8, 0))
			b.add_theme_stylebox_override("hover", FxUI.flat(FxUI.c("BUTTON_HOVER"), 4, FxUI.c("BORDER_STRONG"), 8, 0))
			b.add_theme_stylebox_override("pressed", FxUI.flat(FxUI.c("BUTTON_PRESSED"), 4, FxUI.c("ACCENT"), 8, 0))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			b.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
	FxUI.style_primary_green(_export_btn)
	_export_btn.add_theme_font_size_override("font_size", 12)
	_dest_btn.icon = ProUIStyle.icon("res://icon/UI/folder.svg", FxUI.c("ICON_PRIMARY"), 14)
	for chk in [_chk_transp, _chk_curves]:
		ProUIStyle.style_check(chk)
		chk.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
	_status.add_theme_color_override("default_color", FxUI.c("PANEL_TEXT"))
	for r in rows():
		r.restyle()

# ═════════════════════════════════ fila ══════════════════════════════════════
class ExportRow extends PanelContainer:
	var owner_panel: Node = null
	var artboard: Node2D = null
	var nodes: Array = []
	var format := "SVG"
	var export_scale := 1.0
	var checked := false
	var _chk: CheckBox
	var _fmt: OptionButton
	var _scale: OptionButton
	var _drop_hover := false

	func build(title: String, kind: String) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		tooltip_text = "Arrastra a una carpeta para exportar · doble clic = exportar al destino · suelta archivos aquí para convertirlos a este formato"
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		add_child(h)
		_chk = CheckBox.new()
		_chk.focus_mode = Control.FOCUS_NONE
		_chk.tooltip_text = "Incluir en «Exportar marcados»"
		_chk.toggled.connect(func(on: bool) -> void: checked = on)
		h.add_child(_chk)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(16, 16)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.set_meta("icon_path", ICONS.get(kind, ICONS["group"]))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(icon)
		var name_l := Label.new()
		name_l.text = title
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(name_l)
		_fmt = OptionButton.new()
		_fmt.focus_mode = Control.FOCUS_NONE
		_fmt.fit_to_longest_item = false
		_fmt.custom_minimum_size = Vector2(70, 0)
		for f in FORMATS:
			_fmt.add_item(f)
		_fmt.select(maxi(0, FORMATS.find(format)))
		_fmt.item_selected.connect(func(i: int) -> void:
			format = FORMATS[i]
			_remember()
			_sync_scale())
		h.add_child(_fmt)
		_scale = OptionButton.new()
		_scale.focus_mode = Control.FOCUS_NONE
		_scale.custom_minimum_size = Vector2(52, 0)
		for s in SCALES:
			_scale.add_item(str(s).trim_suffix(".0") + "×")
		_scale.select(maxi(0, SCALES.find(export_scale)))
		_scale.item_selected.connect(func(i: int) -> void:
			export_scale = SCALES[i]
			_remember())
		h.add_child(_scale)
		var grip := Label.new()
		grip.text = "⠿"
		grip.tooltip_text = "Arrastrar"
		grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(grip)
		_sync_scale()

	func _sync_scale() -> void:
		_scale.visible = format in ["PNG", "JPEG", "WEBP"]

	func _remember() -> void:
		var key: Node = artboard if nodes.is_empty() else nodes[0]
		if is_instance_valid(key):
			key.set_meta("export_format", format)
			key.set_meta("export_scale", export_scale)

	func label() -> String:
		var key: Node = artboard if nodes.is_empty() else nodes[0]
		return String(key.name) if is_instance_valid(key) else "?"

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
			owner_panel.export_rows_to([self], owner_panel.dest_dir)
			accept_event()

	# arrastrar la fila (a una carpeta / a la biblioteca)
	func _get_drag_data(_at: Vector2) -> Variant:
		var sel: Array = owner_panel.rows().filter(func(r) -> bool: return r.checked)
		var list: Array = sel if (checked and sel.size() > 1) else [self]
		var prev := Label.new()
		prev.text = "  ⇩ %s  (%s)" % [label() if list.size() == 1 else "%d elementos" % list.size(), format]
		var sb := StyleBoxFlat.new()
		sb.bg_color = FxUI.c("ACCENT")
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		prev.add_theme_stylebox_override("normal", sb)
		prev.add_theme_color_override("font_color", Color.WHITE)
		set_drag_preview(prev)
		var key: Node = artboard if nodes.is_empty() else nodes[0]
		return {"type": "export_element", "rows": list, "node_reference": key, "format": format}

	# soltar archivos de la lista de la izquierda = convertir
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok: bool = data is Dictionary and (String(data.get("type", "")) in ["recent_file", "external_file"]) \
			and not String(data.get("path", "")).is_empty()
		_set_hover(ok)
		return ok

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_set_hover(false)
		owner_panel.convert_files(PackedStringArray([String(data["path"])]), self)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
			_set_hover(false)

	func _set_hover(on: bool) -> void:
		if on != _drop_hover:
			_drop_hover = on
			restyle()

	func restyle() -> void:
		add_theme_stylebox_override("panel", FxUI.flat(FxUI.c("ACCENT_SOFT") if _drop_hover else FxUI.c("INPUT_BG"), 5,
			FxUI.c("ACCENT") if _drop_hover else FxUI.c("BORDER"), 8, 4))
		for l in find_children("*", "Label", true, false):
			l.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
		for t in find_children("*", "TextureRect", true, false):
			if t.has_meta("icon_path"):
				t.texture = ProUIStyle.icon(String(t.get_meta("icon_path")), FxUI.c("ICON_PRIMARY"), 16)
		for o in [_fmt, _scale]:
			ProUIStyle.style_option(o)
			o.add_theme_font_size_override("font_size", 11)
		ProUIStyle.style_check(_chk)
