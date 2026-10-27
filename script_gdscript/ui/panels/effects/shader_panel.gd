# =============================================================================
# RUTA: res://script_gdscript/ui/panels/effects/shader_panel.gd
# Pestaña "Shader" del panel Efectos (antes vacía): ÁREA DE CÓDIGO para
# escribir un shader y aplicarlo al objeto seleccionado + LISTA de los
# shaders guardados (biblioteca en user://shaders/) y plantillas.
#
#   · Editor: números de línea, resaltado del lenguaje de shaders de Godot,
#     compilación al escribir con el error y su línea marcados.
#   · Aplicar: un paso de deshacer. "En vivo": el objeto cambia mientras se
#     escribe (sin llenar el historial; se consolida en un paso al aplicar,
#     cambiar de selección o salir de la pestaña).
#   · Biblioteca: guardar / cargar (clic) / renombrar / duplicar / eliminar.
# Motor: filter_fx.gd (capa "shader del usuario"); datos: shader_library.gd.
# Se construye por código dentro del nodo "Shader" que ya tenía la ventana.
# =============================================================================
extends VBoxContainer

const Lib = preload("res://script_gdscript/shapes/shader_library.gd")
const FxUI = preload("res://script_gdscript/ui/panels/effects/fx_ui.gd")
const PANEL_NAME := "ShaderPanel"

var _name: LineEdit = null
var _code: CodeEdit = null
var _status: Label = null
var _target: Label = null
var _list: VBoxContainer = null
var _templates: VBoxContainer = null
var _btn_save: Button = null
var _btn_apply: Button = null
var _btn_remove: Button = null
var _chk_live: CheckBox = null
var _row_menu: PopupMenu = null
var _menu_path := ""
var _titles: Array[Label] = []
var _errors: Array = []
var _validate_timer: Timer = null
var _live_before: Dictionary = {}   # figura -> custom_shader anterior (en vivo)
var _loaded_for: Array = []          # selección cuyo shader está en el editor
var _syncing := false

## Monta la pestaña dentro del nodo "Shader" existente de la ventana.
static func install(effects_panel: Control) -> Control:
	if effects_panel == null:
		return null
	var content := effects_panel.get_parent()
	var host := content.get_node_or_null("Shader") as Control if content else null
	if host == null:
		return null
	var existing := host.find_child(PANEL_NAME, true, false)
	if existing:
		return existing
	for c in host.get_children():
		host.remove_child(c)
		c.queue_free()
	var panel: Control = load("res://script_gdscript/ui/panels/effects/shader_panel.gd").new()
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
	var margin_box := self

	# ── barra: nombre + acciones ──
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	margin_box.add_child(bar)
	_name = LineEdit.new()
	_name.placeholder_text = "Nombre del shader"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.custom_minimum_size = Vector2(120, 26)
	bar.add_child(_name)
	_btn_save = _button(bar, "Guardar", "Guardar en la biblioteca (Ctrl+S)")
	_btn_save.pressed.connect(_on_save)
	_btn_apply = _button(bar, "Aplicar", "Aplicar al objeto seleccionado (Ctrl+Intro)")
	_btn_apply.pressed.connect(_on_apply)
	_btn_remove = _button(bar, "Quitar", "Quitar el shader del objeto seleccionado")
	_btn_remove.pressed.connect(_on_remove)
	_chk_live = CheckBox.new()
	_chk_live.text = "En vivo"
	_chk_live.tooltip_text = "Ver el resultado en el objeto mientras escribes"
	_chk_live.focus_mode = Control.FOCUS_NONE
	_chk_live.toggled.connect(func(on: bool) -> void:
		if on:
			_schedule_validate()
		else:
			_commit_live())
	bar.add_child(_chk_live)

	# ── cuerpo: código | biblioteca ──
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = -10
	margin_box.add_child(split)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	split.add_child(left)
	_code = CodeEdit.new()
	_code.name = "ShaderCode"
	_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code.custom_minimum_size = Vector2(320, 260)
	_code.gutters_draw_line_numbers = true
	_code.indent_automatic = true
	_code.indent_size = 4
	_code.indent_use_spaces = false
	_code.auto_brace_completion_enabled = true
	_code.highlight_current_line = true
	_code.draw_tabs = true
	_code.minimap_draw = false
	_code.scroll_past_end_of_file = true
	_code.add_comment_delimiter("//", "", true)
	_code.add_comment_delimiter("/*", "*/", false)
	_code.text_changed.connect(_on_code_changed)
	_code.gui_input.connect(_on_code_key)
	left.add_child(_code)
	var foot := HBoxContainer.new()
	left.add_child(foot)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 11)
	foot.add_child(_status)
	_target = Label.new()
	_target.add_theme_font_size_override("font_size", 11)
	foot.add_child(_target)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(200, 0)
	right.add_theme_constant_override("separation", 4)
	split.add_child(right)
	var lib_head := HBoxContainer.new()
	right.add_child(lib_head)
	lib_head.add_child(_title_label("MIS SHADERS"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lib_head.add_child(sp)
	var new_btn := _button(lib_head, "+ Nuevo", "Empezar un shader nuevo")
	new_btn.pressed.connect(func() -> void: _load_template("Nuevo shader"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 2)
	scroll.add_child(inner)
	_list = VBoxContainer.new()
	_list.name = "ShaderList"
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
	_row_menu.add_item("Renombrar…", 1)
	_row_menu.add_item("Duplicar", 2)
	_row_menu.add_separator()
	_row_menu.add_item("Eliminar", 3)
	_row_menu.id_pressed.connect(_on_row_menu)
	add_child(_row_menu)

func _ready() -> void:
	_validate_timer = Timer.new()
	_validate_timer.one_shot = true
	_validate_timer.wait_time = 0.35
	_validate_timer.timeout.connect(_validate_now)
	add_child(_validate_timer)
	_code.syntax_highlighter = _make_highlighter()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed"):
		ic.changed.connect(func(_p) -> void: _on_selection_maybe_changed())
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: restyle())
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_fit_window.call_deferred()
			_on_selection_maybe_changed()
		else:
			_commit_live())
	refresh_list()
	_load_template("Nuevo shader")
	restyle()
	_on_selection_maybe_changed()

# ── selección ────────────────────────────────────────────────────────────────
func _selection() -> Array:
	var ic := get_node_or_null("/root/InspectorCore")
	return ic.selection() if ic and ic.has_method("selection") else []

## Al cambiar la selección: se consolida lo "en vivo" y, si el objeto ya
## tiene shader, se carga en el editor.
func _on_selection_maybe_changed() -> void:
	if _syncing:
		return
	var sel := _selection()
	if sel == _loaded_for:
		_update_target(sel)
		return
	_commit_live()
	_loaded_for = sel.duplicate()
	_update_target(sel)
	if sel.size() == 1 and is_instance_valid(sel[0]) and sel[0].has_meta("custom_shader"):
		var cs = sel[0].get_meta("custom_shader")
		if cs is Dictionary and String(cs.get("code", "")) != "":
			_set_editor(String(cs.get("name", "Shader")), String(cs["code"]))

func _update_target(sel: Array) -> void:
	if sel.is_empty():
		_target.text = "Sin selección"
	else:
		var with_sh := 0
		for s in sel:
			if is_instance_valid(s) and s.has_meta("custom_shader"):
				with_sh += 1
		_target.text = ("%d objeto" % sel.size()) + ("s" if sel.size() != 1 else "") \
			+ ((" · %d con shader" % with_sh) if with_sh > 0 else "")
	_btn_apply.disabled = sel.is_empty()
	_btn_remove.disabled = sel.is_empty()

# ── editor ───────────────────────────────────────────────────────────────────
func _set_editor(nm: String, code: String) -> void:
	_syncing = true
	_name.text = nm
	_code.text = code
	_code.clear_undo_history()
	_syncing = false
	_validate_now()

func _load_template(tname: String) -> void:
	_set_editor(Lib.unique_name(tname if tname != "Nuevo shader" else "Mi shader"), Lib.template_code(tname))

func _on_code_changed() -> void:
	if _syncing:
		return
	_schedule_validate()

func _schedule_validate() -> void:
	if _validate_timer:
		_validate_timer.start()

func _on_code_key(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.is_command_or_control_pressed():
		if ev.keycode == KEY_S:
			_on_save()
			_code.accept_event()
		elif ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER:
			_on_apply()
			_code.accept_event()

## Compila y marca los errores; en vivo, aplica si compila.
func _validate_now() -> void:
	for l in _errors:
		if l >= 0 and l < _code.get_line_count():
			_code.set_line_background_color(l, Color(0, 0, 0, 0))
	_errors.clear()
	var errs := Lib.validate(_code.text)
	if errs.is_empty():
		_status.text = "✓ Compila"
		_status.add_theme_color_override("font_color", FxUI.c("AFFIRMATIVE") if _has_slot("AFFIRMATIVE") else Color(0.3, 0.75, 0.4))
		if _chk_live.button_pressed:
			_apply_live()
		return
	var first: Dictionary = errs[0]
	_status.text = "Línea %d: %s" % [int(first["line"]), String(first["msg"])] \
		+ (("  (+%d)" % (errs.size() - 1)) if errs.size() > 1 else "")
	_status.add_theme_color_override("font_color", FxUI.c("NEGATIVE") if _has_slot("NEGATIVE") else Color(0.9, 0.3, 0.3))
	for e in errs:
		var ln := int(e["line"]) - 1
		if ln >= 0 and ln < _code.get_line_count():
			_code.set_line_background_color(ln, Color(0.9, 0.2, 0.2, 0.22))
			_errors.append(ln)

func _has_slot(slot: String) -> bool:
	var tm := get_node_or_null("/root/ThemeManager")
	return tm != null and tm.Slot.has(slot)

func is_valid_code() -> bool:
	return Lib.validate(_code.text).is_empty()

func _shader_value() -> Dictionary:
	return {"name": _name.text.strip_edges(), "code": _code.text,
		"margin": Lib.margin_of(_code.text), "params": {}, "enabled": true}

# ── aplicar ──────────────────────────────────────────────────────────────────
func _on_apply() -> void:
	if _selection().is_empty():
		return
	if not is_valid_code():
		_validate_now()
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	# Lo "en vivo" se deshace primero: el paso de deshacer guarda el ORIGINAL.
	_revert_live()
	_syncing = true
	ic.apply("custom_shader", _shader_value())
	_syncing = false
	_update_target(_selection())

func _on_remove() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	_revert_live()
	_syncing = true
	ic.apply("custom_shader", {})
	_syncing = false
	_update_target(_selection())

func _apply_live() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null or not ic.has_method("_write"):
		return
	if _live_before.is_empty():
		for s in _selection():
			var b = ic._read(s, "custom_shader")
			if b != null:
				_live_before[s] = b
	_syncing = true
	for s in _live_before:
		if is_instance_valid(s):
			ic._write(s, "custom_shader", _shader_value())
	ic.post_write_live()
	_syncing = false

## Consolida lo aplicado en vivo en UN paso de deshacer.
func _commit_live() -> void:
	if _live_before.is_empty():
		return
	var ic := get_node_or_null("/root/InspectorCore")
	var before := _live_before
	_live_before = {}
	if ic and ic.has_method("commit_live"):
		_syncing = true
		ic.commit_live("custom_shader", before)
		_syncing = false

func _revert_live() -> void:
	if _live_before.is_empty():
		return
	var ic := get_node_or_null("/root/InspectorCore")
	var before := _live_before
	_live_before = {}
	if ic == null:
		return
	_syncing = true
	for s in before:
		if is_instance_valid(s):
			ic._write(s, "custom_shader", before[s])
	ic.post_write_live()
	_syncing = false

# ── biblioteca ───────────────────────────────────────────────────────────────
func _on_save() -> void:
	var nm := _name.text.strip_edges()
	if nm.is_empty():
		nm = Lib.unique_name("Mi shader")
		_name.text = nm
	Lib.save(nm, _code.text)
	refresh_list()
	_status.text = "Guardado «%s»" % nm

func refresh_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var items := Lib.list()
	if items.is_empty():
		var empty := Label.new()
		empty.name = "Empty"
		empty.text = "Aún no hay shaders guardados.\nEscribe uno y pulsa Guardar."
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
		var more := _button(row, "⋯", "Renombrar, duplicar, eliminar")
		more.custom_minimum_size = Vector2(26, 24)
		more.pressed.connect(func() -> void:
			_menu_path = String(it["path"])
			_row_menu.position = Vector2i(more.get_screen_position() + Vector2(0, more.size.y))
			_row_menu.popup())

func _load_saved(path: String) -> void:
	_commit_live()
	for it in Lib.list():
		if it["path"] == path:
			_set_editor(String(it["name"]), Lib.load_code(path))
			return

func _on_row_menu(id: int) -> void:
	var path := _menu_path
	match id:
		0:
			_load_saved(path)
		1:
			_ask_name("Renombrar shader", _name_of(path), func(nm: String) -> void:
				Lib.rename(path, nm)
				refresh_list())
		2:
			var nm2 := Lib.unique_name(_name_of(path))
			Lib.save(nm2, Lib.load_code(path))
			refresh_list()
		3:
			var dlg := ConfirmationDialog.new()
			dlg.dialog_text = "¿Eliminar «%s» de la biblioteca?" % _name_of(path)
			dlg.ok_button_text = "Eliminar"
			dlg.confirmed.connect(func() -> void:
				Lib.remove(path)
				refresh_list()
				dlg.queue_free())
			dlg.canceled.connect(dlg.queue_free)
			add_child(dlg)
			dlg.popup_centered()

func _name_of(path: String) -> String:
	for it in Lib.list():
		if it["path"] == path:
			return String(it["name"])
	return path.get_file().get_basename()

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
	for l in _titles:
		l.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
	_target.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY"))
	ProUIStyle.style_line_edit(_name)
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
	_chk_live.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
	_chk_live.add_theme_font_size_override("font_size", 11)
	ProUIStyle.style_popup(_row_menu)
	# Área de código: oscura en cualquier tema, como un editor.
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

## Resaltado del lenguaje de shaders de Godot.
func _make_highlighter() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = Color(0.71, 0.84, 0.66)
	h.symbol_color = Color(0.67, 0.75, 0.87)
	h.function_color = Color(0.4, 0.85, 0.95)
	h.member_variable_color = Color(0.86, 0.87, 0.9)
	var kw := Color(1.0, 0.44, 0.52)
	for w in ["shader_type", "render_mode", "uniform", "varying", "const", "in", "out", "inout",
			"if", "else", "for", "while", "do", "return", "break", "continue", "discard", "switch", "case", "default",
			"struct", "global", "instance", "group_uniforms"]:
		h.add_keyword_color(w, kw)
	var ty := Color(0.55, 0.85, 1.0)
	for w in ["void", "bool", "int", "uint", "float", "vec2", "vec3", "vec4", "ivec2", "ivec3", "ivec4",
			"bvec2", "bvec3", "bvec4", "mat2", "mat3", "mat4", "sampler2D", "isampler2D", "usampler2D",
			"samplerCube", "canvas_item", "spatial", "particles", "unshaded", "blend_mix", "blend_add",
			"blend_sub", "blend_mul", "blend_premul_alpha"]:
		h.add_keyword_color(w, ty)
	var hint := Color(0.78, 0.66, 1.0)
	for w in ["source_color", "hint_range", "hint_screen_texture", "filter_linear", "filter_nearest",
			"filter_linear_mipmap", "filter_nearest_mipmap", "repeat_enable", "repeat_disable",
			"hint_normal", "hint_default_white", "hint_default_black"]:
		h.add_keyword_color(w, hint)
	var bi := Color(1.0, 0.78, 0.45)
	for w in ["COLOR", "UV", "SCREEN_UV", "SCREEN_PIXEL_SIZE", "TIME", "VERTEX", "TEXTURE", "TEXTURE_PIXEL_SIZE",
			"FRAGCOORD", "MODEL_MATRIX", "CANVAS_MATRIX", "SCREEN_MATRIX", "POINT_COORD", "NORMAL", "PI", "TAU",
			"true", "false"]:
		h.add_keyword_color(w, bi)
	h.add_color_region("//", "", Color(0.5, 0.55, 0.6), true)
	h.add_color_region("/*", "*/", Color(0.5, 0.55, 0.6), false)
	return h

## La pestaña necesita sitio para código + lista: la ventana crece hacia la
## izquierda y hacia abajo (como al añadir la pestaña Filtros).
func _fit_window() -> void:
	# El tamaño por pestaña lo pone el panel de Efectos (effects.gd,
	# _apply_tab_size): aquí solo se ensanchaba y nunca volvía a encoger.
	return

