# =============================================================================
# RUTA: res://script_gdscript/ui/panels/effects/script_panel.gd
# Pestaña "Script" del panel Efectos, con DOS módulos:
#
#   · SCRIPTS: área de código GDScript (como la pestaña Shader) que maneja
#     Vectopen con la API (VectopenAPI): ejecutar (Ctrl+Intro / F5), consola
#     con print() y errores por línea, comprobación al escribir,
#     autocompletado de `api.`, ayuda de la API, biblioteca de scripts
#     guardados (user://scripts/) y plantillas. Cada ejecución es UN paso de
#     deshacer; si falla, se deshace sola.
#   · COMPLEMENTOS: gestor estilo Blender. Instalar (.zip, carpeta o .gd),
#     activar/desactivar, recargar, desinstalar; cada complemento activo
#     muestra sus operadores (botones) y su panel de ajustes.
#
# Motor: script_runner.gd, script_library.gd, PluginManager (autoload).
# Se construye por código dentro del nodo "Script" que ya tenía la ventana.
# =============================================================================
extends VBoxContainer

const Lib = preload("res://script_gdscript/api/script_library.gd")
const Runner = preload("res://script_gdscript/api/script_runner.gd")
const FxUI = preload("res://script_gdscript/ui/panels/effects/fx_ui.gd")
const PANEL_NAME := "ScriptPanel"

# módulos
var _tab_scripts: Button = null
var _tab_addons: Button = null
var _tabs: HBoxContainer = null
var _page_scripts: Control = null
var _page_addons: Control = null

# scripts
var _name: LineEdit = null
var _code: CodeEdit = null
var _status: Label = null
var _console: RichTextLabel = null
var _list: VBoxContainer = null
var _templates: VBoxContainer = null
var _btn_run: Button = null
var _row_menu: PopupMenu = null
var _menu_path := ""
var _errors: Array = []
var _check_timer: Timer = null
var _running := false
var _syncing := false
var _api_popup: PopupPanel = null

# complementos
var _addon_list: VBoxContainer = null
var _addon_filter: LineEdit = null
var _addon_menu: PopupMenu = null
var _addon_menu_id := ""
var _file_dialog: FileDialog = null

var _titles: Array[Label] = []

## Monta la pestaña dentro del nodo "Script" existente de la ventana.
static func install(effects_panel: Control) -> Control:
	if effects_panel == null:
		return null
	var content := effects_panel.get_parent()
	var host := content.get_node_or_null("Script") as Control if content else null
	if host == null:
		return null
	var existing := host.find_child(PANEL_NAME, true, false)
	if existing:
		return existing
	for c in host.get_children():
		host.remove_child(c)
		c.queue_free()
	var panel: Control = load("res://script_gdscript/ui/panels/effects/script_panel.gd").new()
	panel.name = PANEL_NAME
	# Márgenes como la pestaña Vectorizar: el contenido no toca los bordes.
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 12)
	host.add_child(margin)
	margin.add_child(panel)
	return panel

func _init() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_tabs = HBoxContainer.new()
	_tabs.name = "Modules"
	add_child(_tabs)
	_tab_scripts = _tab_button("Scripts", "Escribir y ejecutar scripts GDScript")
	_tab_addons = _tab_button("Complementos", "Instalar y activar complementos (como en Blender)")
	_tab_scripts.pressed.connect(show_module.bind("scripts"))
	_tab_addons.pressed.connect(show_module.bind("addons"))
	_page_scripts = _build_scripts()
	_page_scripts.name = "ScriptsPage"
	add_child(_page_scripts)
	_page_addons = _build_addons()
	_page_addons.name = "AddonsPage"
	add_child(_page_addons)
	show_module("scripts")

func _ready() -> void:
	_check_timer = Timer.new()
	_check_timer.one_shot = true
	_check_timer.wait_time = 0.4
	_check_timer.timeout.connect(_check_now)
	add_child(_check_timer)
	_code.syntax_highlighter = _make_highlighter()
	var pm := _pm()
	if pm:
		pm.addons_changed.connect(_queue_addons_refresh)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: restyle())
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_fit_window.call_deferred())
	refresh_list()
	refresh_addons()
	_load_template("Nuevo script")
	restyle()

func _pm() -> Node:
	return get_node_or_null("/root/PluginManager")

func _api() -> VectopenAPI:
	var pm := _pm()
	return pm.api if pm else null

## "scripts" | "addons"
func show_module(which: String) -> void:
	_page_scripts.visible = which == "scripts"
	_page_addons.visible = which == "addons"
	_tabs.set_meta("active", _tab_addons if which == "addons" else _tab_scripts)
	FxUI.style_tabs(_tabs, _tabs.get_meta("active"))

# ═════════════════════════════════ SCRIPTS ═══════════════════════════════════
func _build_scripts() -> Control:
	var page := VBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 6)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	page.add_child(bar)
	_name = LineEdit.new()
	_name.placeholder_text = "Nombre del script"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.custom_minimum_size = Vector2(120, 26)
	bar.add_child(_name)
	_button(bar, "Guardar", "Guardar en la biblioteca (Ctrl+S)").pressed.connect(_on_save)
	_btn_run = _button(bar, "▶ Ejecutar", "Ejecutar (Ctrl+Intro o F5). Ctrl+Z deshace todo el script")
	_btn_run.name = "RunButton"
	_btn_run.pressed.connect(run_current)
	_button(bar, "API", "Referencia de la API de Vectopen").pressed.connect(_show_api_help)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(split)
	var left := VSplitContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	var code_box := VBoxContainer.new()
	code_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code_box.add_theme_constant_override("separation", 4)
	left.add_child(code_box)
	_code = CodeEdit.new()
	_code.name = "ScriptCode"
	_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code.custom_minimum_size = Vector2(320, 200)
	_code.gutters_draw_line_numbers = true
	_code.indent_automatic = true
	_code.indent_size = 4
	_code.indent_use_spaces = false
	_code.indent_automatic_prefixes = [":"]
	_code.auto_brace_completion_enabled = true
	_code.highlight_current_line = true
	_code.draw_tabs = true
	_code.minimap_draw = false
	_code.scroll_past_end_of_file = true
	_code.code_completion_enabled = true
	_code.code_completion_prefixes = ["."]
	_code.add_comment_delimiter("#", "", true)
	_code.add_string_delimiter("\"", "\"", false)
	_code.add_string_delimiter("'", "'", false)
	_code.text_changed.connect(_on_code_changed)
	_code.gui_input.connect(_on_code_key)
	_code.code_completion_requested.connect(_on_completion)
	code_box.add_child(_code)
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 11)
	code_box.add_child(_status)

	var cons_box := VBoxContainer.new()
	cons_box.add_theme_constant_override("separation", 2)
	left.add_child(cons_box)
	var cons_head := HBoxContainer.new()
	cons_box.add_child(cons_head)
	cons_head.add_child(_title_label("CONSOLA"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cons_head.add_child(sp)
	_button(cons_head, "Limpiar", "Vaciar la consola").pressed.connect(func() -> void: _console.clear())
	_console = RichTextLabel.new()
	_console.name = "Console"
	_console.custom_minimum_size = Vector2(0, 90)
	_console.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_console.scroll_following = true
	_console.selection_enabled = true
	_console.bbcode_enabled = true
	_console.meta_clicked.connect(func(meta) -> void: _goto_line(int(str(meta))))
	cons_box.add_child(_console)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(190, 0)
	right.add_theme_constant_override("separation", 4)
	split.add_child(right)
	var lib_head := HBoxContainer.new()
	right.add_child(lib_head)
	lib_head.add_child(_title_label("MIS SCRIPTS"))
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lib_head.add_child(sp2)
	_button(lib_head, "+ Nuevo", "Empezar un script nuevo").pressed.connect(func() -> void: _load_template("Nuevo script"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 2)
	scroll.add_child(inner)
	_list = VBoxContainer.new()
	_list.name = "ScriptList"
	_list.add_theme_constant_override("separation", 2)
	inner.add_child(_list)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	inner.add_child(gap)
	inner.add_child(_title_label("PLANTILLAS"))
	_templates = VBoxContainer.new()
	_templates.name = "Templates"
	_templates.add_theme_constant_override("separation", 2)
	inner.add_child(_templates)
	for tname in Lib.TEMPLATES:
		var b := _row_button(_templates, tname)
		b.tooltip_text = "Cargar la plantilla en el editor"
		b.pressed.connect(_load_template.bind(tname))

	_row_menu = PopupMenu.new()
	_row_menu.add_item("Cargar", 0)
	_row_menu.add_item("Ejecutar", 4)
	_row_menu.add_item("Renombrar…", 1)
	_row_menu.add_item("Duplicar", 2)
	_row_menu.add_separator()
	_row_menu.add_item("Eliminar", 3)
	_row_menu.id_pressed.connect(_on_row_menu)
	page.add_child(_row_menu)
	return page

# ── editor ───────────────────────────────────────────────────────────────────
func set_code(nm: String, code: String) -> void:
	_syncing = true
	_name.text = nm
	_code.text = code
	_code.clear_undo_history()
	_syncing = false
	_check_now()

func get_code() -> String:
	return _code.text

func _load_template(tname: String) -> void:
	set_code(Lib.unique_name(tname if tname != "Nuevo script" else "Mi script"), Lib.template_code(tname))

func _on_code_changed() -> void:
	if not _syncing and _check_timer:
		_check_timer.start()

func _on_code_key(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed):
		return
	if ev.keycode == KEY_F5 or (ev.is_command_or_control_pressed() and (ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER)):
		run_current()
		_code.accept_event()
	elif ev.is_command_or_control_pressed() and ev.keycode == KEY_S:
		_on_save()
		_code.accept_event()

## Comprueba la sintaxis y marca las líneas con error.
func _check_now() -> void:
	_clear_marks()
	var errs := Runner.check(_code.text)
	if errs.is_empty():
		_set_status("✓ Sin errores de sintaxis", true)
		return
	_mark(errs)
	var first: Dictionary = errs[0]
	_set_status("Línea %d: %s" % [int(first["line"]), String(first["msg"])], false)

func _clear_marks() -> void:
	for l in _errors:
		if l >= 0 and l < _code.get_line_count():
			_code.set_line_background_color(l, Color(0, 0, 0, 0))
	_errors.clear()

func _mark(errs: Array) -> void:
	for e in errs:
		var ln := int(e["line"]) - 1
		if ln >= 0 and ln < _code.get_line_count():
			_code.set_line_background_color(ln, Color(0.9, 0.2, 0.2, 0.22))
			_errors.append(ln)

func _set_status(text: String, ok: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", _ok_col() if ok else _err_col())

func _ok_col() -> Color:
	return FxUI.c("AFFIRMATIVE") if _has_slot("AFFIRMATIVE") else Color(0.3, 0.75, 0.4)

func _err_col() -> Color:
	return FxUI.c("NEGATIVE") if _has_slot("NEGATIVE") else Color(0.9, 0.3, 0.3)

func _has_slot(slot: String) -> bool:
	var tm := get_node_or_null("/root/ThemeManager")
	return tm != null and tm.Slot.has(slot)

func _goto_line(line: int) -> void:
	if line >= 1 and line <= _code.get_line_count():
		_code.set_caret_line(line - 1)
		_code.set_caret_column(_code.get_line(line - 1).length())
		_code.center_viewport_to_caret()
		_code.grab_focus()

# ── ejecutar ─────────────────────────────────────────────────────────────────
## Ejecuta el código del editor. Devuelve el resultado de ScriptRunner.run.
func run_current() -> Dictionary:
	if _running:
		return {}
	var api := _api()
	if api == null:
		_log("[color=#%s]Vectopen no está listo (sin PluginManager)[/color]" % _err_col().to_html(false))
		return {}
	_running = true
	_btn_run.disabled = true
	_btn_run.text = "… Ejecutando"
	_clear_marks()
	var nm := _name.text.strip_edges()
	_log("[color=#%s]▶ %s[/color]" % [FxUI.c("TEXT_SECONDARY").to_html(false), nm if nm != "" else "Script"])
	var res: Dictionary = await Runner.run(_code.text, api, "Script: %s" % (nm if nm != "" else "sin nombre"))
	for l in res.get("output", PackedStringArray()):
		_log(_escape(String(l)))
	if res.get("ok", false):
		_log("[color=#%s]✓ Hecho en %.1f ms · Ctrl+Z lo deshace entero[/color]" % [_ok_col().to_html(false), float(res.get("ms", 0.0))])
		_set_status("✓ Ejecutado", true)
	else:
		var errs: Array = res.get("errors", [])
		_mark(errs)
		for e in errs:
			_log("[color=#%s][url=%d]Línea %d[/url]: %s[/color]" % [_err_col().to_html(false), int(e["line"]), int(e["line"]), _escape(String(e["msg"]))])
		if not errs.is_empty():
			_set_status("Error en la línea %d — no se ha cambiado nada" % int(errs[0]["line"]), false)
			_goto_line(int(errs[0]["line"]))
	_running = false
	_btn_run.disabled = false
	_btn_run.text = "▶ Ejecutar"
	return res

func _log(bb: String) -> void:
	_console.append_text(bb + "\n")

static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")

# ── autocompletado y ayuda ───────────────────────────────────────────────────
func _on_completion() -> void:
	var line := _code.get_line(_code.get_caret_line()).substr(0, _code.get_caret_column())
	var re := RegEx.new()
	re.compile("\\bapi\\.(\\w*)$")
	var m := re.search(line)
	if m == null:
		return
	var typed := m.get_string(1)
	for e in VectopenAPI.REFERENCE:
		var meth := VectopenAPI.reference_method(e)
		if typed == "" or meth.begins_with(typed):
			_code.add_code_completion_option(CodeEdit.KIND_FUNCTION, String(e[1]), meth + "(")
	_code.update_code_completion_options(true)

func _show_api_help() -> void:
	if _api_popup == null:
		_api_popup = PopupPanel.new()
		_api_popup.name = "ApiHelp"
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(560, 420)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_api_popup.add_child(scroll)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.selection_enabled = true
		rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(rt)
		var txt := "[b]API de Vectopen %s[/b] — en los scripts y complementos se usa como [code]api.metodo()[/code].\n" % VectopenAPI.API_VERSION
		txt += "Coordenadas del artboard; las figuras se colocan por su centro.\n"
		var group := ""
		for e in VectopenAPI.REFERENCE:
			if e[0] != group:
				group = e[0]
				txt += "\n[b]%s[/b]\n" % group
			txt += "  [code]%s[/code]  —  %s\n" % [_escape(String(e[1])), _escape(String(e[2]))]
		txt += "\n[b]Propiedades[/b] (get_prop / set_prop): [code]%s[/code]\n" % ", ".join(PackedStringArray(_api().props() if _api() else []))
		rt.text = txt
		add_child(_api_popup)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm:
		_api_popup.add_theme_stylebox_override("panel", FxUI.flat(FxUI.c("PANEL_BG"), 6, FxUI.c("BORDER_STRONG"), 12, 10))
	_api_popup.popup_centered()

# ── biblioteca ───────────────────────────────────────────────────────────────
func _on_save() -> void:
	var nm := _name.text.strip_edges()
	if nm.is_empty():
		nm = Lib.unique_name("Mi script")
		_name.text = nm
	Lib.save(nm, _code.text)
	refresh_list()
	_set_status("Guardado «%s»" % nm, true)

func refresh_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var items := Lib.list()
	if items.is_empty():
		var empty := Label.new()
		empty.name = "Empty"
		empty.text = "Aún no hay scripts guardados.\nEscribe uno y pulsa Guardar."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
		_list.add_child(empty)
		return
	for it in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		_list.add_child(row)
		var b := _row_button(row, String(it["name"]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("path", it["path"])
		b.tooltip_text = "Cargar en el editor"
		b.pressed.connect(_load_saved.bind(String(it["path"])))
		var run := _button(row, "▶", "Ejecutar sin abrirlo")
		run.custom_minimum_size = Vector2(26, 24)
		run.pressed.connect(func() -> void:
			_load_saved(String(it["path"]))
			run_current())
		var more := _button(row, "⋯", "Renombrar, duplicar, eliminar")
		more.custom_minimum_size = Vector2(26, 24)
		more.pressed.connect(func() -> void:
			_menu_path = String(it["path"])
			_row_menu.position = Vector2i(more.get_screen_position() + Vector2(0, more.size.y))
			_row_menu.popup())
	restyle()

func _load_saved(path: String) -> void:
	for it in Lib.list():
		if it["path"] == path:
			set_code(String(it["name"]), Lib.load_code(path))
			return

func _on_row_menu(id: int) -> void:
	var path := _menu_path
	match id:
		0:
			_load_saved(path)
		4:
			_load_saved(path)
			run_current()
		1:
			_ask_name("Renombrar script", _name_of(path), func(nm: String) -> void:
				Lib.rename(path, nm)
				refresh_list())
		2:
			Lib.save(Lib.unique_name(_name_of(path)), Lib.load_code(path))
			refresh_list()
		3:
			_confirm("¿Eliminar «%s» de la biblioteca?" % _name_of(path), "Eliminar", func() -> void:
				Lib.remove(path)
				refresh_list())

func _name_of(path: String) -> String:
	for it in Lib.list():
		if it["path"] == path:
			return String(it["name"])
	return path.get_file().get_basename()

# ═══════════════════════════════ COMPLEMENTOS ════════════════════════════════
func _build_addons() -> Control:
	var page := VBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 6)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	page.add_child(bar)
	_addon_filter = LineEdit.new()
	_addon_filter.placeholder_text = "Buscar complementos"
	_addon_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_addon_filter.custom_minimum_size = Vector2(120, 26)
	_addon_filter.clear_button_enabled = true
	_addon_filter.text_changed.connect(func(_t: String) -> void: refresh_addons())
	bar.add_child(_addon_filter)
	_button(bar, "Instalar…", "Instalar un complemento desde un .zip, una carpeta o un .gd").pressed.connect(_on_install_pressed)
	_button(bar, "Recargar", "Volver a leer las carpetas de complementos").pressed.connect(func() -> void:
		var pm := _pm()
		if pm:
			pm.refresh())
	_button(bar, "Carpeta", "Abrir la carpeta de complementos del usuario").pressed.connect(func() -> void:
		var pm := _pm()
		if pm:
			OS.shell_open(pm.user_dir()))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_addon_list = VBoxContainer.new()
	_addon_list.name = "AddonList"
	_addon_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_addon_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_addon_list)
	_addon_menu = PopupMenu.new()
	_addon_menu.add_item("Recargar código", 0)
	_addon_menu.add_item("Abrir carpeta", 1)
	_addon_menu.add_separator()
	_addon_menu.add_item("Desinstalar…", 2)
	_addon_menu.id_pressed.connect(_on_addon_menu)
	page.add_child(_addon_menu)
	return page

var _addons_pending := false
func _queue_addons_refresh() -> void:
	if _addons_pending:
		return
	_addons_pending = true
	(func() -> void:
		_addons_pending = false
		refresh_addons()).call_deferred()

func refresh_addons() -> void:
	var pm := _pm()
	if _addon_list == null or pm == null:
		return
	_detach_addon_panels()
	for c in _addon_list.get_children():
		_addon_list.remove_child(c)
		c.queue_free()
	var q := _addon_filter.text.strip_edges().to_lower() if _addon_filter else ""
	var shown := 0
	for a in pm.list_addons():
		var hay := ("%s %s %s %s" % [a["name"], a["description"], a["category"], a["author"]]).to_lower()
		if q != "" and not (q in hay):
			continue
		_addon_list.add_child(_addon_card(a))
		shown += 1
	if shown == 0:
		var l := Label.new()
		l.text = "No hay complementos." if q == "" else "Ningún complemento coincide."
		l.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
		_addon_list.add_child(l)
	restyle()

## Los paneles de los complementos son SUYOS: se sacan antes de borrar las
## fichas (o esta pestaña), si no se liberarían con ellas.
func _detach_addon_panels() -> void:
	if _addon_list == null:
		return
	for host in _addon_list.find_children("AddonPanelHost", "", true, false):
		for p in host.get_children():
			host.remove_child(p)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_detach_addon_panels()

func _addon_card(a: Dictionary) -> Control:
	var id := String(a["id"])
	var card := PanelContainer.new()
	card.name = "Addon_" + id
	card.set_meta("addon_card", true)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	var chk := CheckBox.new()
	chk.name = "Enabled"
	chk.focus_mode = Control.FOCUS_NONE
	chk.button_pressed = bool(a["enabled"])
	chk.tooltip_text = "Activar / desactivar"
	chk.toggled.connect(func(on: bool) -> void: set_addon_enabled(id, on))
	head.add_child(chk)
	var title := Label.new()
	title.text = String(a["name"])
	title.add_theme_font_size_override("font_size", 13)
	title.set_meta("card_title", true)
	head.add_child(title)
	var meta := Label.new()
	meta.text = ("v" + String(a["version"]) if String(a["version"]) != "" else "") + \
		("  ·  " + String(a["category"])) + ("  ·  incluido" if bool(a["builtin"]) else "")
	meta.add_theme_font_size_override("font_size", 10)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.set_meta("muted", true)
	head.add_child(meta)
	var more := _button(head, "⋯", "Recargar, abrir carpeta, desinstalar")
	more.custom_minimum_size = Vector2(26, 24)
	more.pressed.connect(func() -> void:
		_addon_menu_id = id
		_addon_menu.set_item_disabled(_addon_menu.get_item_index(2), bool(a["builtin"]))
		_addon_menu.position = Vector2i(more.get_screen_position() + Vector2(0, more.size.y))
		_addon_menu.popup())
	if String(a["description"]) != "" or String(a["author"]) != "":
		var desc := Label.new()
		desc.text = String(a["description"]) + (("  — " + String(a["author"])) if String(a["author"]) != "" else "")
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 11)
		desc.set_meta("muted", true)
		v.add_child(desc)
	if String(a["error"]) != "":
		var err := Label.new()
		err.name = "Error"
		err.text = "⚠ " + String(a["error"])
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err.add_theme_font_size_override("font_size", 11)
		err.add_theme_color_override("font_color", _err_col())
		v.add_child(err)
	if bool(a["enabled"]):
		var api := _api()
		var ops: Array = api.operators(id) if api else []
		if not ops.is_empty():
			var flow := HFlowContainer.new()
			flow.name = "Operators"
			flow.add_theme_constant_override("h_separation", 4)
			flow.add_theme_constant_override("v_separation", 4)
			v.add_child(flow)
			for op in ops:
				var b := _button(flow, String(op["label"]), String(op["tooltip"]))
				b.set_meta("operator", op["id"])
				b.pressed.connect(func() -> void: run_operator(String(op["id"])))
		var addon = _pm().get_addon(id)
		if addon is VectopenAddon and not addon.get_panels().is_empty():
			var host := VBoxContainer.new()
			host.name = "AddonPanelHost"
			v.add_child(host)
			for p in addon.get_panels():
				if is_instance_valid(p):
					if p.get_parent():
						p.get_parent().remove_child(p)
					host.add_child(p)
	return card

func set_addon_enabled(id: String, on: bool) -> void:
	var pm := _pm()
	if pm == null:
		return
	if on:
		var err: String = pm.enable(id)
		if err != "":
			_log("[color=#%s]%s: %s[/color]" % [_err_col().to_html(false), id, _escape(err)])
	else:
		pm.disable(id)

func run_operator(op_id: String) -> bool:
	var api := _api()
	if api == null:
		return false
	return api.run_operator(op_id)

func _on_addon_menu(item: int) -> void:
	var pm := _pm()
	var id := _addon_menu_id
	if pm == null or id == "":
		return
	match item:
		0:
			var err: String = pm.reload(id)
			if err != "":
				_log("[color=#%s]%s: %s[/color]" % [_err_col().to_html(false), id, _escape(err)])
		1:
			var info: Dictionary = pm.get_info(id)
			if not info.is_empty():
				OS.shell_open(ProjectSettings.globalize_path(String(info["dir"])))
		2:
			_confirm("¿Desinstalar «%s»? Se borrará su carpeta." % String(pm.get_info(id).get("name", id)), "Desinstalar",
				func() -> void: pm.uninstall(id))

func _on_install_pressed() -> void:
	_confirm("Los complementos ejecutan código con los mismos permisos que Vectopen.\nInstala solo complementos de fuentes de confianza.",
		"Elegir archivo…", _open_install_dialog)

func _open_install_dialog() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
		_file_dialog.filters = PackedStringArray(["*.zip ; Complemento comprimido", "*.gd ; Script de complemento"])
		_file_dialog.use_native_dialog = true
		_file_dialog.title = "Instalar complemento"
		_file_dialog.file_selected.connect(install_from)
		_file_dialog.dir_selected.connect(install_from)
		add_child(_file_dialog)
	_file_dialog.popup_centered(Vector2i(760, 480))

## Instala y activa. Devuelve el resultado de PluginManager.install.
func install_from(path: String) -> Dictionary:
	var pm := _pm()
	if pm == null:
		return {}
	var res: Dictionary = pm.install(path)
	if not res["ok"]:
		_log("[color=#%s]No se pudo instalar: %s[/color]" % [_err_col().to_html(false), _escape(String(res["error"]))])
		return res
	var err: String = pm.enable(String(res["id"]))
	_log(("Instalado y activado «%s»" % res["id"]) if err == "" else ("Instalado «%s», pero falla al activarse: %s" % [res["id"], _escape(err)]))
	show_module("addons")
	return res

# ═══════════════════════════════ comunes ═════════════════════════════════════
func _ask_name(title: String, current: String, done: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = title
	var le := LineEdit.new()
	le.text = current
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

func _confirm(text: String, ok_text: String, done: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = text
	dlg.ok_button_text = ok_text
	dlg.confirmed.connect(func() -> void:
		dlg.queue_free()
		done.call())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

func _tab_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	_tabs.add_child(b)
	return b

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

func _row_button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size = Vector2(0, 24)
	b.add_theme_font_size_override("font_size", 11)
	b.set_meta("row_button", true)
	parent.add_child(b)
	return b

func _title_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	_titles.append(l)
	return l

func restyle() -> void:
	if _tabs.has_meta("active"):
		FxUI.style_tabs(_tabs, _tabs.get_meta("active"))
	for l in _titles:
		l.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
	ProUIStyle.style_line_edit(_name)
	ProUIStyle.style_line_edit(_addon_filter)
	_name.add_theme_font_size_override("font_size", 12)
	for b in find_children("*", "Button", true, false):
		if b.has_meta("bar_button"):
			b.add_theme_stylebox_override("normal", FxUI.flat(FxUI.c("INPUT_BG"), 4, FxUI.c("INPUT_BORDER"), 8, 0))
			b.add_theme_stylebox_override("hover", FxUI.flat(FxUI.c("BUTTON_HOVER"), 4, FxUI.c("BORDER_STRONG"), 8, 0))
			b.add_theme_stylebox_override("pressed", FxUI.flat(FxUI.c("BUTTON_PRESSED"), 4, FxUI.c("ACCENT"), 8, 0))
			b.add_theme_stylebox_override("disabled", FxUI.flat(FxUI.c("INPUT_BG"), 4, FxUI.c("BORDER"), 8, 0))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			b.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
		elif b.has_meta("row_button"):
			b.add_theme_stylebox_override("normal", FxUI.flat(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0), 6, 0))
			b.add_theme_stylebox_override("hover", FxUI.flat(FxUI.c("BUTTON_HOVER"), 4, Color(0, 0, 0, 0), 6, 0))
			b.add_theme_stylebox_override("pressed", FxUI.flat(FxUI.c("ACCENT_SOFT"), 4, Color(0, 0, 0, 0), 6, 0))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			b.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
	for cb in find_children("*", "CheckBox", true, false):
		ProUIStyle.style_check(cb)
	for card in _addon_list.get_children():
		if card.has_meta("addon_card"):
			card.add_theme_stylebox_override("panel", FxUI.flat(FxUI.c("SURFACE_RAISED") if _has_slot("SURFACE_RAISED") else FxUI.c("INPUT_BG"), 6, FxUI.c("BORDER"), 10, 8))
			for l in card.find_children("*", "Label", true, false):
				if l.has_meta("card_title"):
					l.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
				elif l.has_meta("muted"):
					l.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
			# Paneles de los complementos: mismo aspecto que el resto de la ventana.
			for host in card.find_children("AddonPanelHost", "", true, false):
				for l in host.find_children("*", "Label", true, false):
					l.add_theme_font_size_override("font_size", 11)
					l.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
				for sb in host.find_children("*", "SpinBox", true, false):
					sb.add_theme_font_size_override("font_size", 11)
					ProUIStyle.style_line_edit(sb.get_line_edit())
					sb.get_line_edit().add_theme_font_size_override("font_size", 11)
				for le in host.find_children("*", "LineEdit", true, false):
					if not (le.get_parent() is SpinBox):
						ProUIStyle.style_line_edit(le)
		elif card is Label:
			card.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
	ProUIStyle.style_popup(_row_menu)
	ProUIStyle.style_popup(_addon_menu)
	# Código y consola: oscuros en cualquier tema, como un editor.
	var dark := ProUIStyle.is_dark()
	var bg := Color(0.09, 0.09, 0.11) if dark else Color(0.12, 0.13, 0.16)
	_code.add_theme_stylebox_override("normal", FxUI.flat(bg, 6, FxUI.c("INPUT_BORDER"), 8, 6))
	_code.add_theme_stylebox_override("focus", FxUI.flat(bg, 6, FxUI.c("ACCENT"), 8, 6))
	_code.add_theme_color_override("font_color", Color(0.86, 0.87, 0.9))
	_code.add_theme_color_override("line_number_color", Color(0.45, 0.47, 0.52))
	_code.add_theme_color_override("current_line_color", Color(1, 1, 1, 0.05))
	_code.add_theme_color_override("caret_color", Color(0.9, 0.9, 0.95))
	_code.add_theme_color_override("selection_color", Color(0.3, 0.45, 0.8, 0.45))
	_code.add_theme_font_size_override("font_size", 13)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["JetBrains Mono", "Fira Code", "DejaVu Sans Mono", "Monospace"])
	_code.add_theme_font_override("font", mono)
	_console.add_theme_stylebox_override("normal", FxUI.flat(bg, 6, FxUI.c("INPUT_BORDER"), 8, 6))
	_console.add_theme_color_override("default_color", Color(0.8, 0.82, 0.86))
	_console.add_theme_font_override("normal_font", mono)
	_console.add_theme_font_size_override("normal_font_size", 12)

## Resaltado de GDScript (los colores del editor de Godot).
func _make_highlighter() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = Color(0.71, 0.84, 0.66)
	h.symbol_color = Color(0.67, 0.75, 0.87)
	h.function_color = Color(0.4, 0.85, 0.95)
	h.member_variable_color = Color(0.86, 0.87, 0.9)
	var kw := Color(1.0, 0.44, 0.52)
	for w in ["extends", "class_name", "func", "var", "const", "signal", "enum", "static", "class",
			"if", "elif", "else", "for", "while", "match", "break", "continue", "pass", "return",
			"in", "is", "as", "not", "and", "or", "await", "self", "super", "preload", "load",
			"true", "false", "null", "PI", "TAU", "INF", "NAN"]:
		h.add_keyword_color(w, kw)
	var ty := Color(0.55, 0.85, 1.0)
	for w in ["void", "bool", "int", "float", "String", "StringName", "Vector2", "Vector2i", "Vector3",
			"Color", "Rect2", "Transform2D", "Array", "Dictionary", "PackedVector2Array", "PackedFloat32Array",
			"PackedStringArray", "Curve2D", "Node", "Node2D", "Callable", "Variant", "VectopenScript",
			"VectopenAddon", "VectopenAPI", "Control", "Label", "Button", "SpinBox", "HBoxContainer", "VBoxContainer"]:
		h.add_keyword_color(w, ty)
	h.add_member_keyword_color("api", Color(1.0, 0.78, 0.45))
	h.add_keyword_color("api", Color(1.0, 0.78, 0.45))
	h.add_color_region("#", "", Color(0.5, 0.55, 0.6), true)
	h.add_color_region("\"", "\"", Color(1.0, 0.93, 0.63), false)
	h.add_color_region("'", "'", Color(1.0, 0.93, 0.63), false)
	return h

## Código + consola + lista necesitan sitio: la ventana crece (como Shader).
func _fit_window() -> void:
	var n: Node = self
	while n and not (n is Control and (n as Control).name == "panel__effects"):
		n = n.get_parent()
	var win := n as Control
	if win == null:
		return
	var vp := win.get_viewport_rect().size
	var want_w := minf(800.0, vp.x - 40.0)
	var want_h := minf(600.0, vp.y - win.offset_top - 40.0)
	if win.size.x < want_w:
		win.offset_left -= ceilf(want_w - win.size.x)
	if win.size.y < want_h:
		win.offset_bottom = win.offset_top + want_h
