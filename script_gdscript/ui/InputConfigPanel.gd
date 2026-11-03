# =============================================================================
# RUTA: res://script_gdscript/ui/InputConfigPanel.gd
# Panel «Teclado y ratón» (botón del teclado, abajo a la izquierda en Smart).
#
#   · ATAJOS   — acciones configurables agrupadas por categoría, con nombre
#                claro y traducible; reasignar (clic en la tecla), quitar (×),
#                añadir (+) y restablecer. Avisa si dos acciones comparten tecla.
#   · TECLADO  — teclado simulado: con el modificador elegido (ninguno, Ctrl,
#                Mayús, Alt…) cada tecla se pinta como configurable, fija o
#                libre; al pasar el ratón dice qué hace. Clic en una tecla
#                ocupada → la busca en Atajos.
#   · RATÓN    — gestos del ratón y del lápiz.
# Mismo lenguaje visual que el panel de Capas (ProUIStyle), claro y oscuro.
# La captura/guardado de teclas es la de siempre (user://vectopen_inputmap.cfg).
# =============================================================================
@tool
extends PanelContainer

@export var action_container: VBoxContainer
@export var filter_line_edit: LineEdit

var _capture_action: String = ""
var _capture_index: int = -1
var _capture_label: Label
var _current_filter: String = ""

const CONFIG_PATH := "user://vectopen_inputmap.cfg"
const PANEL_SIZE := Vector2(820, 540)

## Categorías del panel (orden de lectura) → acciones de VectopenInput.DEFAULTS.
const CATEGORIES := [
	["Herramientas", ["tool_select", "tool_rectangle", "tool_ellipse", "tool_star", "tool_bezier", "tool_brush", "tool_text", "tool_paragraph", "tool_artboard", "tool_hand"]],
	["Vista", ["canvas_zoom_in", "canvas_zoom_out", "canvas_reset_zoom"]],
	["Archivo", ["save", "new_project"]],
	["Edición", ["undo", "redo", "copy", "paste", "cut", "select_all", "duplicate", "delete"]],
	["Objeto", ["group", "ungroup", "text_to_curves"]],
]
## Nombre visible de cada acción (texto fuente en español; se traduce con tr()).
const NAMES := {
	"tool_select": "Seleccionar / mover", "tool_rectangle": "Rectángulo", "tool_ellipse": "Elipse",
	"tool_star": "Estrella", "tool_bezier": "Bézier", "tool_brush": "Pincel", "tool_text": "Texto artístico",
	"tool_paragraph": "Texto de párrafo", "tool_artboard": "Mesa de trabajo", "tool_hand": "Mano (desplazar la vista)",
	"canvas_zoom_in": "Acercar", "canvas_zoom_out": "Alejar", "canvas_reset_zoom": "Restablecer el zoom",
	"save": "Guardar", "new_project": "Documento nuevo",
	"undo": "Deshacer", "redo": "Rehacer", "copy": "Copiar", "paste": "Pegar", "cut": "Cortar",
	"select_all": "Seleccionar todo", "duplicate": "Duplicar", "delete": "Borrar",
	"group": "Agrupar", "ungroup": "Desagrupar", "text_to_curves": "Convertir a curvas / contorno",
}
## Atajos FIJOS (no se reasignan aquí): combinación → descripción.
## Clave: "<mods>|<keycode>", mods en orden ctrl+shift+alt.
static func _fixed() -> Dictionary:
	var d := {}
	for i in 10:
		d["|%d" % (KEY_0 + i)] = "Opacidad de la selección|%d" % (100 if i == 0 else i * 10)
	for k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		d["|%d" % k] = "Mover la selección 1 px"
		d["shift|%d" % k] = "Mover la selección 10 px"
	d["|%d" % KEY_SPACE] = "Mantener: desplazar la vista con el ratón"
	d["|%d" % KEY_ESCAPE] = "Cancelar · devolver el teclado al lienzo"
	d["|%d" % KEY_G] = "Modo degradado"
	d["shift|%d" % KEY_G] = "Mover con el teclado"
	d["shift|%d" % KEY_R] = "Rotar con el teclado"
	d["shift|%d" % KEY_S] = "Escalar con el teclado"
	d["ctrl|%d" % KEY_Y] = "Rehacer"
	d["ctrl+alt|%d" % KEY_PERIOD] = "Fuente más gruesa"
	d["ctrl+alt|%d" % KEY_COMMA] = "Fuente más fina"
	d["|%d" % KEY_F10] = "Consola de diagnóstico: informe"
	return d

## Teclado: filas de [keycode, etiqueta, ancho en unidades]. keycode 0 = hueco.
const ROWS := [
	[[KEY_ESCAPE, "Esc", 1.0], [0, "", 0.5], [KEY_F1, "F1", 1.0], [KEY_F2, "F2", 1.0], [KEY_F3, "F3", 1.0], [KEY_F4, "F4", 1.0], [0, "", 0.5],
		[KEY_F5, "F5", 1.0], [KEY_F6, "F6", 1.0], [KEY_F7, "F7", 1.0], [KEY_F8, "F8", 1.0], [0, "", 0.5], [KEY_F9, "F9", 1.0], [KEY_F10, "F10", 1.0], [KEY_F11, "F11", 1.0], [KEY_F12, "F12", 1.0]],
	[[KEY_QUOTELEFT, "º", 1.0], [KEY_1, "1", 1.0], [KEY_2, "2", 1.0], [KEY_3, "3", 1.0], [KEY_4, "4", 1.0], [KEY_5, "5", 1.0], [KEY_6, "6", 1.0],
		[KEY_7, "7", 1.0], [KEY_8, "8", 1.0], [KEY_9, "9", 1.0], [KEY_0, "0", 1.0], [KEY_MINUS, "-", 1.0], [KEY_EQUAL, "=", 1.0], [KEY_BACKSPACE, "⌫", 2.0]],
	[[KEY_TAB, "Tab", 1.5], [KEY_Q, "Q", 1.0], [KEY_W, "W", 1.0], [KEY_E, "E", 1.0], [KEY_R, "R", 1.0], [KEY_T, "T", 1.0], [KEY_Y, "Y", 1.0],
		[KEY_U, "U", 1.0], [KEY_I, "I", 1.0], [KEY_O, "O", 1.0], [KEY_P, "P", 1.0], [KEY_BRACKETLEFT, "[", 1.0], [KEY_BRACKETRIGHT, "]", 1.0], [KEY_BACKSLASH, "\\", 1.5]],
	[[KEY_CAPSLOCK, "Bloq", 1.75], [KEY_A, "A", 1.0], [KEY_S, "S", 1.0], [KEY_D, "D", 1.0], [KEY_F, "F", 1.0], [KEY_G, "G", 1.0], [KEY_H, "H", 1.0],
		[KEY_J, "J", 1.0], [KEY_K, "K", 1.0], [KEY_L, "L", 1.0], [KEY_SEMICOLON, "Ñ", 1.0], [KEY_APOSTROPHE, "´", 1.0], [KEY_ENTER, "Intro", 2.25]],
	[[KEY_SHIFT, "Mayús", 2.25], [KEY_Z, "Z", 1.0], [KEY_X, "X", 1.0], [KEY_C, "C", 1.0], [KEY_V, "V", 1.0], [KEY_B, "B", 1.0], [KEY_N, "N", 1.0],
		[KEY_M, "M", 1.0], [KEY_COMMA, ",", 1.0], [KEY_PERIOD, ".", 1.0], [KEY_SLASH, "-", 1.0], [KEY_SHIFT, "Mayús", 2.75]],
	[[KEY_CTRL, "Ctrl", 1.5], [KEY_META, "❖", 1.25], [KEY_ALT, "Alt", 1.25], [KEY_SPACE, "Espacio", 6.25], [KEY_ALT, "AltGr", 1.25], [KEY_CTRL, "Ctrl", 1.5]],
]
## Bloque de la derecha: [keycode, etiqueta, columna, fila].
const SIDE := [
	[KEY_DELETE, "Supr", 0, 1], [KEY_HOME, "Inicio", 1, 1], [KEY_END, "Fin", 2, 1],
	[KEY_UP, "↑", 1, 4], [KEY_LEFT, "←", 0, 5], [KEY_DOWN, "↓", 1, 5], [KEY_RIGHT, "→", 2, 5],
]
const MODS := [["", "Sin modificador"], ["ctrl", "Ctrl"], ["shift", "Mayús"], ["alt", "Alt"], ["ctrl+shift", "Ctrl + Mayús"], ["ctrl+alt", "Ctrl + Alt"]]
## Gestos del ratón / lápiz: [gesto, descripción].
const MOUSE := [
	["Clic", "Seleccionar"],
	["Doble clic en un texto", "Editar el texto"],
	["Clic derecho", "Menú contextual"],
	["Arrastrar", "Mover la selección"],
	["Alt + arrastrar", "Duplicar y mover (un solo paso de deshacer)"],
	["Ctrl + arrastrar", "Mover solo en horizontal o vertical (y ajustar a la rejilla)"],
	["Mayús + arrastrar la caja", "Cambiar el grosor del trazo"],
	["Rueda", "Zoom en el punto del ratón"],
	["Ctrl + rueda", "Zoom más rápido"],
	["Botón central + arrastrar", "Desplazar la vista"],
	["Espacio + arrastrar", "Desplazar la vista"],
	["Pincel · Mayús + arrastrar", "Cambiar el grosor del pincel"],
	["Pincel · Ctrl", "Trazo en línea recta"],
	["Pincel · Alt", "Continuar desde el último trazo"],
]

var _tabs: Dictionary = {}          # id → Button
var _pages: Dictionary = {}         # id → Control
var _tab := "list"
var _mod := ""
var _kb_host: Control
var _kb_keys: Array = []            # [PanelContainer, keycode]
var _info: Label
var _legend: HBoxContainer
var _mod_buttons: Array = []        # [Button, mods]
var _title: Label
var _ui_built := false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if filter_line_edit:
		filter_line_edit.text_changed.connect(_on_filter_changed)
		filter_line_edit.placeholder_text = tr("Buscar atajo…")
	_build_ui()
	_build_action_list()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _restyle())

# ══════════════════════════════ ESTRUCTURA ═══════════════════════════════════
## Monta pestañas, teclado y ratón alrededor de la lista que trae la escena.
func _build_ui() -> void:
	var box := get_node_or_null("MarginContainer/BoxContainer") as Control
	if box == null or _ui_built or action_container == null:
		return   # p. ej. en las pruebas unitarias: solo la lista
	_ui_built = true
	custom_minimum_size = PANEL_SIZE
	offset_top = -PANEL_SIZE.y - 8.0
	offset_bottom = -8.0
	offset_right = PANEL_SIZE.x
	_title = box.get_node_or_null("Label") as Label
	if _title:
		_title.text = tr("Teclado y ratón")
	var scroll: Node = action_container.get_parent()
	while scroll and not (scroll is ScrollContainer):
		scroll = scroll.get_parent()
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	box.move_child(tabs, (_title.get_index() + 1) if _title else 0)
	for t in [["list", "Atajos"], ["keys", "Teclado"], ["mouse", "Ratón"]]:
		var b := Button.new()
		b.name = "Tab_" + String(t[0])
		b.text = tr(String(t[1]))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 28)
		var id := String(t[0])
		b.pressed.connect(func() -> void: show_tab(id))
		tabs.add_child(b)
		_tabs[id] = b
	var list_page := VBoxContainer.new()
	list_page.name = "PageList"
	list_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_page.add_theme_constant_override("separation", 6)
	box.add_child(list_page)
	if filter_line_edit and filter_line_edit.get_parent():
		filter_line_edit.reparent(list_page)
	if scroll:
		scroll.reparent(list_page)
		(scroll as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages["list"] = list_page
	_pages["keys"] = _build_keyboard_page(box)
	_pages["mouse"] = _build_mouse_page(box)
	show_tab("list")

func show_tab(id: String) -> void:
	_tab = id
	for k in _pages:
		(_pages[k] as Control).visible = k == id
	for k in _tabs:
		(_tabs[k] as Button).set_pressed_no_signal(k == id)
	if id == "keys":
		_refresh_keyboard()
	_restyle()

func _build_keyboard_page(box: Control) -> Control:
	var page := VBoxContainer.new()
	page.name = "PageKeys"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	box.add_child(page)
	var mods := HBoxContainer.new()
	mods.add_theme_constant_override("separation", 4)
	page.add_child(mods)
	for m in MODS:
		var b := Button.new()
		b.name = "Mod_" + (String(m[0]) if m[0] != "" else "none")
		b.text = tr(String(m[1]))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 26)
		var mid := String(m[0])
		b.pressed.connect(func() -> void: set_modifier(mid))
		mods.add_child(b)
		_mod_buttons.append([b, mid])
	_kb_host = Control.new()
	_kb_host.name = "Keyboard"
	_kb_host.custom_minimum_size = Vector2(0, 6 * 42 + 6)
	page.add_child(_kb_host)
	var u := 40.0
	for r in ROWS.size():
		var x := 0.0
		for k in ROWS[r]:
			var w: float = float(k[2]) * u
			if int(k[0]) != 0:
				_add_key(int(k[0]), String(k[1]), Vector2(x, r * 42.0 + (0.0 if r == 0 else 6.0)), Vector2(w - 4.0, 38.0))
			x += w
	var sx := 15.4 * u + 14.0
	for k in SIDE:
		_add_key(int(k[0]), String(k[1]), Vector2(sx + int(k[2]) * u, int(k[3]) * 42.0 + 6.0), Vector2(u - 4.0, 38.0))
	_legend = HBoxContainer.new()
	_legend.name = "Legend"
	_legend.add_theme_constant_override("separation", 14)
	page.add_child(_legend)
	for l in [["assigned", "Configurable"], ["fixed", "Fijo"], ["conflict", "Repetido"], ["free", "Libre"]]:
		var sw := HBoxContainer.new()
		sw.add_theme_constant_override("separation", 5)
		var dot := Panel.new()
		dot.name = "Dot_" + String(l[0])
		dot.custom_minimum_size = Vector2(14, 14)
		sw.add_child(dot)
		var lb := Label.new()
		lb.text = tr(String(l[1]))
		lb.add_theme_font_size_override("font_size", 11)
		sw.add_child(lb)
		_legend.add_child(sw)
	_info = Label.new()
	_info.name = "KeyInfo"
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 12)
	_info.text = tr("Pasa el ratón por una tecla para ver qué hace. Clic en una tecla ocupada: la busca en Atajos.")
	page.add_child(_info)
	return page

func _add_key(code: int, label: String, pos: Vector2, sz: Vector2) -> void:
	var key := PanelContainer.new()
	key.name = "Key_%d_%d" % [code, int(pos.x)]
	key.position = pos
	key.size = sz
	key.custom_minimum_size = sz
	key.mouse_filter = Control.MOUSE_FILTER_STOP
	key.set_meta("code", code)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.add_child(v)
	var cap := Label.new()
	cap.name = "Cap"
	cap.text = label
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 12 if label.length() <= 3 else 10)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cap)
	var act := Label.new()
	act.name = "Act"
	act.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	act.clip_text = true
	act.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	act.add_theme_font_size_override("font_size", 8)
	act.custom_minimum_size = Vector2(sz.x - 6.0, 0)
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(act)
	key.mouse_entered.connect(func() -> void:
		if _info:
			_info.text = describe(code, label))
	key.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			open_key(code))
	_kb_host.add_child(key)
	_kb_keys.append([key, code])

## Clic en una tecla del teclado simulado: si está ocupada, la busca en Atajos.
func open_key(code: int) -> void:
	var acts: Array = _combo_actions().get(_combo(_mod, code), [])
	if acts.is_empty():
		return
	if filter_line_edit:
		filter_line_edit.text = tr(String(NAMES.get(acts[0], acts[0])))
	_build_action_list(filter_line_edit.text if filter_line_edit else "")
	show_tab("list")

func set_modifier(mods: String) -> void:
	_mod = mods
	_refresh_keyboard()

func _build_mouse_page(box: Control) -> Control:
	var page := ScrollContainer.new()
	page.name = "PageMouse"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(page)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	page.add_child(list)
	for m in MOUSE:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 30)
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		var g := Label.new()
		g.text = tr(String(m[0]))
		g.custom_minimum_size = Vector2(240, 0)
		g.set_meta("chip", true)
		g.add_theme_font_size_override("font_size", 12)
		row.add_child(g)
		var d := Label.new()
		d.text = tr(String(m[1]))
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.add_theme_font_size_override("font_size", 12)
		row.add_child(d)
	return page

# ══════════════════════════════ DATOS ════════════════════════════════════════
static func _combo(mods: String, code: int) -> String:
	return "%s|%d" % [mods, code]

static func _event_combo(e: InputEventKey) -> String:
	var m: Array = []
	if e.ctrl_pressed or e.meta_pressed:
		m.append("ctrl")
	if e.shift_pressed:
		m.append("shift")
	if e.alt_pressed:
		m.append("alt")
	return _combo("+".join(m), e.keycode if e.keycode != 0 else e.physical_keycode)

## combinación → [acciones configurables que la usan]
func _combo_actions() -> Dictionary:
	var d := {}
	for a in _get_relevant_actions():
		if not InputMap.has_action(a):
			continue
		for e in InputMap.action_get_events(a):
			if e is InputEventKey:
				var c := _event_combo(e)
				if not d.has(c):
					d[c] = []
				d[c].append(a)
	return d

static func _same_meaning(acts: Array, fixed_desc: String) -> bool:
	return (acts == ["redo"] and fixed_desc == "Rehacer") or _contextual(acts, fixed_desc)

## Compartida a propósito: la cifra cambia la opacidad SOLO con selección;
## sin selección hace la acción configurable (5 = restablecer el zoom).
static func _contextual(acts: Array, fixed_desc: String) -> bool:
	return acts.size() == 1 and fixed_desc.begins_with("Opacidad")

## Acciones que comparten tecla con otra (configurable o fija): acción → combinación.
func conflicts() -> Dictionary:
	var out := {}
	var fixed := _fixed()
	var ca := _combo_actions()
	for c in ca:
		var acts: Array = ca[c]
		if acts.size() > 1 or (fixed.has(c) and not _same_meaning(acts, fixed[c])):
			for a in acts:
				out[a] = c
	return out

func describe(code: int, label: String) -> String:
	var c := _combo(_mod, code)
	var keys := ((_mod_label() + " + ") if _mod != "" else "") + label
	var acts: Array = _combo_actions().get(c, [])
	var fixed: Dictionary = _fixed()
	var parts: Array = []
	for a in acts:
		parts.append(tr(String(NAMES.get(a, a))))
	if fixed.has(c) and _contextual(acts, fixed[c]):
		parts.append(tr("con selección") + ": " + _fixed_text(fixed[c]))
	elif fixed.has(c) and not _same_meaning(acts, fixed[c]):
		parts.append(_fixed_text(fixed[c]) + " · " + tr("fijo"))
	if parts.is_empty():
		return keys + " — " + tr("libre")
	return keys + " — " + " / ".join(parts)

## Texto visible de un atajo fijo («Opacidad de la selección|50» → «… (50 %)»).
static func _fixed_text(desc: String) -> String:
	var p := desc.split("|")
	return TranslationServer.translate(p[0]) + (" (%s %%)" % p[1] if p.size() > 1 else "")

func _mod_label() -> String:
	for m in MODS:
		if m[0] == _mod:
			return tr(String(m[1]))
	return _mod

## Estado de una tecla con los modificadores dados: assigned | fixed | conflict | free.
func key_state(code: int, mods: String = _mod) -> String:
	var c := _combo(mods, code)
	var acts: Array = _combo_actions().get(c, [])
	var fixed := _fixed()
	if acts.size() > 1 or (not acts.is_empty() and fixed.has(c) and not _same_meaning(acts, fixed[c])):
		return "conflict"
	if not acts.is_empty():
		return "assigned"
	if fixed.has(c):
		return "fixed"
	return "free"

func _refresh_keyboard() -> void:
	if _kb_host == null:
		return
	for mb in _mod_buttons:
		(mb[0] as Button).set_pressed_no_signal(mb[1] == _mod)
	var ca := _combo_actions()
	var fixed := _fixed()
	for kk in _kb_keys:
		var key: PanelContainer = kk[0]
		var code: int = kk[1]
		var c := _combo(_mod, code)
		key.set_meta("state", key_state(code))
		var act := key.find_child("Act", true, false) as Label
		var acts: Array = ca.get(c, [])
		if not acts.is_empty():
			act.text = tr(String(NAMES.get(acts[0], acts[0])))
		elif fixed.has(c):
			act.text = _fixed_text(fixed[c])
		else:
			act.text = ""
		key.tooltip_text = describe(code, (key.find_child("Cap", true, false) as Label).text)
	_restyle()

# ══════════════════════════════ LISTA ════════════════════════════════════════
func _get_relevant_actions() -> Array:
	var vi := get_node_or_null("/root/VectopenInput")
	if vi and vi.has_method("get_action_names"):
		return vi.get_action_names()
	return []

func _action_display_name(action: String) -> String:
	if NAMES.has(action):
		return tr(String(NAMES[action]))
	var vi := get_node_or_null("/root/VectopenInput")
	if vi and vi.has_method("get_action_display"):
		return vi.get_action_display(action)
	return action

func _get_action_events_text(action: String) -> String:
	var vi := get_node_or_null("/root/VectopenInput")
	if vi and vi.has_method("get_action_text"):
		return vi.get_action_text(action)
	return "..."

func _build_action_list(filter: String = "") -> void:
	if not action_container:
		return
	_current_filter = filter
	for c in action_container.get_children():
		action_container.remove_child(c)
		c.queue_free()
	_capture_label = null
	var known := _get_relevant_actions()
	var bad := conflicts() if _ui_built else {}
	var f := filter.strip_edges().to_lower()
	var groups: Array = []
	var placed := {}
	for cat in CATEGORIES:
		var acts: Array = (cat[1] as Array).filter(func(a): return a in known)
		for a in acts:
			placed[a] = true
		groups.append([cat[0], acts])
	var rest: Array = known.filter(func(a): return not placed.has(a))
	if not rest.is_empty():
		groups.append(["Otros", rest])
	for g in groups:
		var shown: Array = (g[1] as Array).filter(func(a):
			return f == "" or String(a).contains(f) or _action_display_name(a).to_lower().contains(f))
		if shown.is_empty():
			continue
		if _ui_built:
			var head := Label.new()
			head.text = tr(String(g[0])).to_upper()
			head.set_meta("section", true)
			head.add_theme_font_size_override("font_size", 10)
			action_container.add_child(head)
		for action in shown:
			_add_action_row(action, bad.get(action, ""))
	_restyle()

func _add_action_row(action: String, conflict_combo: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 30)
	row.add_theme_constant_override("separation", 8)
	row.set_meta("action", action)
	action_container.add_child(row)
	var label := Label.new()
	label.text = _action_display_name(action)
	label.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	label.mouse_filter = MOUSE_FILTER_STOP
	label.theme_type_variation = "BindRowLabel"
	if conflict_combo != "":
		label.text += "  ⚠"
		label.tooltip_text = tr("Esta tecla también la usa otra acción.")
		label.set_meta("conflict", true)
	row.add_child(label)
	var binds := HBoxContainer.new()
	binds.add_theme_constant_override("separation", 4)
	var events: Array = []
	if InputMap.has_action(action):
		events = InputMap.action_get_events(action)
	for i in events.size():
		binds.add_child(_make_bind_chip(action, i, events[i] as InputEvent))
	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.custom_minimum_size = Vector2(26, 26)
	add_btn.tooltip_text = tr("Añadir atajo")
	add_btn.theme_type_variation = "BindChip"
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.set_meta("chip", true)
	add_btn.pressed.connect(_start_capture.bind(action, -1))
	binds.add_child(add_btn)
	row.add_child(binds)
	var reset_btn := Button.new()
	reset_btn.text = "↺"
	reset_btn.tooltip_text = tr("Restablecer")
	reset_btn.custom_minimum_size = Vector2(26, 26)
	reset_btn.theme_type_variation = "ResetLink"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.set_meta("chip", true)
	reset_btn.pressed.connect(_reset_action.bind(action))
	row.add_child(reset_btn)

func _make_bind_chip(action: String, index: int, event: InputEvent) -> HBoxContainer:
	var vi := get_node_or_null("/root/VectopenInput")
	var text := "..."
	if vi:
		text = pretty(vi.event_text(event))
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var chip := Button.new()
	chip.text = text
	chip.custom_minimum_size = Vector2(0, 26)
	chip.theme_type_variation = "BindChip"
	chip.focus_mode = Control.FOCUS_NONE
	chip.tooltip_text = tr("Clic para cambiar la tecla")
	chip.set_meta("chip", true)
	chip.set_meta("key_chip", true)
	chip.pressed.connect(_start_capture.bind(action, index))
	box.add_child(chip)
	var x_btn := Button.new()
	x_btn.text = "×"
	x_btn.custom_minimum_size = Vector2(22, 26)
	x_btn.tooltip_text = tr("Quitar atajo")
	x_btn.theme_type_variation = "BindChip"
	x_btn.focus_mode = Control.FOCUS_NONE
	x_btn.set_meta("chip", true)
	x_btn.pressed.connect(_remove_bind.bind(action, index))
	box.add_child(x_btn)
	return box

## «Ctrl+Equal» → «Ctrl + =», «Shift» → «Mayús», «Delete» → «Supr»…
func pretty(t: String) -> String:
	var rep := {"Equal": "=", "Minus": "-", "Shift": tr("Mayús"), "Delete": tr("Supr"), "Backspace": "⌫",
		"Mouse Left": tr("Clic izquierdo"), "Mouse Right": tr("Clic derecho"), "Mouse Middle": tr("Botón central"),
		"Wheel Up": tr("Rueda arriba"), "Wheel Down": tr("Rueda abajo")}
	var parts := t.split("+")
	for i in parts.size():
		parts[i] = rep.get(parts[i], parts[i])
	return " + ".join(parts)

# ══════════════════════════ CAPTURA DE TECLAS ════════════════════════════════
func _start_capture(action: String, index: int) -> void:
	if not _capture_action.is_empty():
		_cancel_capture()
	_capture_action = action
	_capture_index = index
	if not _capture_label:
		_capture_label = Label.new()
		_capture_label.name = "CaptureHint"
		_capture_label.theme_type_variation = "CaptureHint"
		_capture_label.custom_minimum_size = Vector2(0, 24)
		action_container.add_child(_capture_label)
		action_container.move_child(_capture_label, 0)
	_capture_label.text = tr("Pulsa la tecla o el botón del ratón para «%s»… (Esc cancela)") % _action_display_name(action)
	_capture_label.visible = true
	_restyle()

func _cancel_capture() -> void:
	_capture_action = ""
	_capture_index = -1
	if _capture_label:
		_capture_label.visible = false

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if _capture_action.is_empty():
		return
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
				return   # esperar a la tecla que va con el modificador
			if event.keycode == KEY_ESCAPE:
				_cancel_capture()
				_build_action_list(_current_filter)
				get_viewport().set_input_as_handled()
				return
			_apply_bind(_capture_action, _capture_index, _get_vi().event_to_dict(event))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_apply_bind(_capture_action, _capture_index, _get_vi().event_to_dict(event))
		get_viewport().set_input_as_handled()

func _get_vi() -> Node:
	return get_node_or_null("/root/VectopenInput")

func _apply_bind(action: String, index: int, bind_dict: Dictionary) -> void:
	if not InputMap.has_action(action):
		return
	var events := InputMap.action_get_events(action)
	var new_event: InputEvent = _get_vi().dict_to_event(bind_dict)
	if index >= 0 and index < events.size():
		events[index] = new_event
	else:
		events.append(new_event)
	InputMap.action_erase_events(action)
	for e in events:
		InputMap.action_add_event(action, e)
	_save_rebinding(action, events)
	_cancel_capture()
	_build_action_list(_current_filter)
	_refresh_keyboard()

func _remove_bind(action: String, index: int) -> void:
	if not InputMap.has_action(action):
		return
	var events := InputMap.action_get_events(action)
	if index >= 0 and index < events.size():
		events.remove_at(index)
		InputMap.action_erase_events(action)
		for e in events:
			InputMap.action_add_event(action, e)
		_save_rebinding(action, events)
		_build_action_list(_current_filter)
		_refresh_keyboard()

func _reset_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var vi := _get_vi()
	InputMap.action_erase_events(action)
	for entry in vi.get_default_binds(action):
		InputMap.action_add_event(action, vi.dict_to_event(entry))
	_save_rebinding(action, InputMap.action_get_events(action))
	_build_action_list(_current_filter)
	_refresh_keyboard()

func _save_rebinding(action: String, events: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	var dicts: Array = []
	for e in events:
		dicts.append(_get_vi().event_to_dict(e))
	cfg.set_value("rebinds", action, dicts)
	cfg.save(CONFIG_PATH)

func _on_filter_changed(new_text: String) -> void:
	_build_action_list(new_text)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_build_action_list(_current_filter)
		_refresh_keyboard()
		_keep_on_screen.call_deferred()

## Que nunca quede debajo o fuera de la pantalla.
func _keep_on_screen() -> void:
	if not is_inside_tree() or not _ui_built:
		return
	var vp := get_viewport_rect().size
	var r := get_global_rect()
	var dx := 0.0
	var dy := 0.0
	if r.end.x > vp.x - 8.0:
		dx = vp.x - 8.0 - r.end.x
	if r.position.x + dx < 8.0:
		dx = 8.0 - r.position.x
	if r.position.y < 8.0:
		dy = 8.0 - r.position.y
	if r.end.y + dy > vp.y - 8.0:
		dy = vp.y - 8.0 - r.end.y
	if dx != 0.0 or dy != 0.0:
		global_position += Vector2(dx, dy)

# ══════════════════════════════ ESTILO ═══════════════════════════════════════
func _restyle() -> void:
	if not _ui_built or Engine.is_editor_hint():
		return
	var bg := ProUIStyle.col("PANEL_BG")
	var surface := ProUIStyle.col("PANEL_SURFACE")
	var text := ProUIStyle.col("PANEL_TEXT")
	var sec := ProUIStyle.col("TEXT_SECONDARY")
	var border := ProUIStyle.col("BORDER")
	var accent := ProUIStyle.col("ACCENT")
	var bad := Color("#e5484d")
	var sb := ProUIStyle.flat(bg, 12, border, 0, 0)
	sb.shadow_color = Color(0, 0, 0, 0.3 if ProUIStyle.is_dark() else 0.12)
	sb.shadow_size = 14
	add_theme_stylebox_override("panel", sb)
	if _title:
		_title.add_theme_color_override("font_color", text)
		_title.add_theme_font_size_override("font_size", 14)
	var hover := surface.lerp(text, 0.08)
	for k in _tabs:
		var b: Button = _tabs[k]
		var on := b.button_pressed
		_style_btn(b, accent.lerp(bg, 0.82) if on else surface, hover, accent if on else border, text)
	for mb in _mod_buttons:
		var b: Button = mb[0]
		var on: bool = mb[1] == _mod
		_style_btn(b, accent.lerp(bg, 0.82) if on else surface, hover, accent if on else border, text)
	if filter_line_edit:
		filter_line_edit.add_theme_stylebox_override("normal", ProUIStyle.flat(surface, 8, border, 10, 4))
		filter_line_edit.add_theme_stylebox_override("focus", ProUIStyle.flat(surface, 8, accent, 10, 4))
		filter_line_edit.add_theme_color_override("font_color", text)
		filter_line_edit.add_theme_color_override("font_placeholder_color", sec)
	if action_container:
		for n in action_container.find_children("*", "", true, false):
			if n is Label:
				var l := n as Label
				if l.has_meta("section"):
					l.add_theme_color_override("font_color", sec)
				elif l.name == "CaptureHint":
					l.add_theme_color_override("font_color", accent)
				else:
					l.add_theme_color_override("font_color", bad if l.has_meta("conflict") else text)
			elif n is Button and n.has_meta("chip"):
				_style_btn(n, surface if n.has_meta("key_chip") else bg, hover, border, text)
	if _pages.has("mouse"):
		for n in (_pages["mouse"] as Control).find_children("*", "Label", true, false):
			var l := n as Label
			l.add_theme_color_override("font_color", text if l.has_meta("chip") else sec)
			if l.has_meta("chip"):
				l.add_theme_stylebox_override("normal", ProUIStyle.flat(surface, 6, border, 8, 3))
	if _info:
		_info.add_theme_color_override("font_color", sec)
	var cols := {"assigned": accent.lerp(bg, 0.72), "fixed": surface.lerp(text, 0.14), "conflict": bad.lerp(bg, 0.7), "free": bg}
	var edges := {"assigned": accent, "fixed": sec, "conflict": bad, "free": border}
	for kk in _kb_keys:
		var key: PanelContainer = kk[0]
		var st := String(key.get_meta("state", "free"))
		var code: int = kk[1]
		var mod_on := (code == KEY_CTRL and _mod.contains("ctrl")) or (code == KEY_SHIFT and _mod.contains("shift")) or (code == KEY_ALT and _mod.contains("alt"))
		var ksb := ProUIStyle.flat(accent if mod_on else cols.get(st, bg), 6, accent if mod_on else edges.get(st, border), 2, 2)
		ksb.border_width_bottom = 2
		key.add_theme_stylebox_override("panel", ksb)
		for l in key.find_children("*", "Label", true, false):
			(l as Label).add_theme_color_override("font_color", Color.WHITE if mod_on else (text if l.name == "Cap" else sec))
	if _legend:
		for sw in _legend.get_children():
			var dot := sw.get_child(0) as Panel
			var st := String(dot.name).trim_prefix("Dot_")
			dot.add_theme_stylebox_override("panel", ProUIStyle.flat(cols[st], 4, edges[st], 0, 0))
			(sw.get_child(1) as Label).add_theme_color_override("font_color", sec)

func _style_btn(b: Button, bg: Color, hover: Color, border: Color, fg: Color) -> void:
	b.add_theme_stylebox_override("normal", ProUIStyle.flat(bg, 7, border, 9, 3))
	b.add_theme_stylebox_override("hover", ProUIStyle.flat(hover, 7, border, 9, 3))
	b.add_theme_stylebox_override("pressed", ProUIStyle.flat(bg, 7, border, 9, 3))
	b.add_theme_stylebox_override("hover_pressed", ProUIStyle.flat(hover, 7, border, 9, 3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, fg)
	b.add_theme_font_size_override("font_size", 12)
