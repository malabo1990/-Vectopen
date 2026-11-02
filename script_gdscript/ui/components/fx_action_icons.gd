# =============================================================================
# VECTOPEN — ICONOS SHADER · SCRIPT · VECTORIZAR · COMPLEMENTOS (UX-13)
# RUTA: res://script_gdscript/ui/components/fx_action_icons.gd
#
# Cuatro iconos junto a «Exportar», en los tres modos. Cada uno abre SU
# sección en el panel del modo (no un diálogo):
#   · Modern → Inspector derecho (secciones plegables SecShader / SecScript /
#     SecVectorize; Complementos = SecScript en la página de complementos);
#   · Pro    → barra lateral, pestaña «Efectos», la misma sección;
#   · Smart  → ventana Efectos, en su pestaña.
# Volver a pulsar el icono lo cierra. El icono activo se ve resaltado. No
# crea editores nuevos: usa las secciones que ya existen y no toca la
# selección.
# =============================================================================
extends HBoxContainer

const InspectorFxSections = preload("res://script_gdscript/ui/components/inspector_fx_sections.gd")

## [id, icono, texto de ayuda, sección del inspector, pestaña de Smart]
const ITEMS := [
	["shader", "res://icon/UI/circle-spark.svg", "Shader", InspectorFxSections.SHADER, "ButtonShader"],
	["script", "res://icon/UI/code.svg", "Script", InspectorFxSections.SCRIPT, "ButtonScript"],
	["vectorize", "res://icon/UI/magic-wand.svg", "Vectorizar", InspectorFxSections.VECTORIZE, "ButtonVectorize"],
	["plugins", "res://icon/UI/puzzle.svg", "Complementos", InspectorFxSections.SCRIPT, "ButtonScript"],
]
const SECTION_NODE := {"shader": "SecShader", "script": "SecScript", "vectorize": "SecVectorize", "plugins": "SecScript"}

var buttons := {}               # id → Button
## Fábrica de botones del sitio donde se coloca (para que se vean como sus
## vecinos). Recibe (icono, ayuda) y devuelve un Button.
var make_button: Callable
var button_size := Vector2(28, 24)
var _tick := 0

static func create(factory: Callable = Callable(), size := Vector2(28, 24)) -> Control:
	var s = load("res://script_gdscript/ui/components/fx_action_icons.gd").new()
	s.name = "FxActionIcons"
	s.make_button = factory
	s.button_size = size
	return s

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	for it in ITEMS:
		var id := String(it[0])
		var b: Button
		if make_button.is_valid():
			b = make_button.call(String(it[1]), tr(String(it[2])))
		else:
			b = Button.new()
			b.icon = load(String(it[1]))
			b.expand_icon = true
			b.tooltip_text = tr(String(it[2]))
		b.name = "Fx_" + id
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = button_size
		b.set_meta("fx_kind", id)
		b.toggled.connect(func(on: bool) -> void: _on_toggled(id, on))
		add_child(b)
		buttons[id] = b
	_refresh.call_deferred()

## El estado se recalcula a menudo (las secciones también se pliegan desde
## su cabecera o se cierra la ventana de Smart).
func _process(_d: float) -> void:
	_tick += 1
	if _tick % 12 == 0 and is_visible_in_tree():
		_refresh()

func _mode() -> String:
	var gui := get_node_or_null("/root/GlobalUI")
	return gui.get_ui_mode() if gui and gui.has_method("get_ui_mode") else "smart"

# ── abrir / cerrar ──────────────────────────────────────────────────────────
func _on_toggled(id: String, on: bool) -> void:
	if on:
		await open(id)
	else:
		close(id)
	_refresh()

## Abre la sección `id` en el panel del modo actual.
func open(id: String) -> void:
	# Script y Complementos comparten sección: solo uno activo a la vez.
	for other in buttons:
		if other != id and is_active(other) and SECTION_NODE[other] == SECTION_NODE[id]:
			(buttons[other] as Button).set_pressed_no_signal(false)
	if _mode() == "smart":
		await _open_smart(id)
		return
	var host := _host()
	if host == null:
		return
	if host.has_method("_select_tab_b"):
		host.call("_select_tab_b", 2)          # Pro: pestaña «Efectos»
	var sec := host.find_child(SECTION_NODE[id], true, false) as Control
	if sec == null:
		return
	_reveal_window(sec)
	InspectorFxSections.set_pinned(sec.kind, true)
	if not sec.is_open():
		sec._toggle()
	sec.visible = true
	await get_tree().process_frame
	_select_module(sec.get("_content"), id)
	await get_tree().process_frame
	_scroll_to(sec)
	# La sección recién abierta crea su contenido y cambia de alto: se vuelve
	# a colocar arriba cuando la disposición se ha asentado (en la ventana
	# flotante quedaba fuera de la vista).
	for _i in 3:
		await get_tree().process_frame
	if is_instance_valid(sec):
		_scroll_to(sec)

## UX-21: si la sección vive en una pestaña FLOTANTE de Pro (Window), la
## ventana se muestra, se trae al frente y se mete entera en la pantalla.
func _reveal_window(sec: Control) -> void:
	var n: Node = sec.get_parent()
	while n and not (n is Window):
		n = n.get_parent()
	var win := n as Window
	if win == null or win == get_tree().root:
		return
	if win.mode == Window.MODE_MINIMIZED:
		win.mode = Window.MODE_WINDOWED
	win.visible = true
	var vp := get_viewport().get_visible_rect()
	var sz := Vector2(win.size)
	var pos := Vector2(win.position)
	pos.x = clampf(pos.x, vp.position.x, maxf(vp.position.x, vp.end.x - sz.x))
	pos.y = clampf(pos.y, vp.position.y + 28.0, maxf(vp.position.y + 28.0, vp.end.y - sz.y))
	win.position = Vector2i(pos)
	win.move_to_foreground()
	win.grab_focus()

func close(id: String) -> void:
	if _mode() == "smart":
		var win := _smart_window()
		if win and win.visible and is_active(id):
			win.visible = false
		return
	var host := _host()
	var sec := host.find_child(SECTION_NODE[id], true, false) as Control if host else null
	if sec == null:
		return
	InspectorFxSections.set_pinned(sec.kind, false)
	if sec.is_open():
		sec._toggle()
	sec._sync_visibility()

## ¿Está abierta ahora la sección de `id`?
func is_active(id: String) -> bool:
	if _mode() == "smart":
		var win := _smart_window()
		if win == null or not win.is_visible_in_tree():
			return false
		var host := win.find_child(_smart_host(id), true, false) as Control
		if host == null or not host.is_visible_in_tree():
			return false
		return _module_matches(_smart_content(host) if id in ["script", "plugins"] else null, id)
	var h := _host()
	var sec := h.find_child(SECTION_NODE[id], true, false) as Control if h else null
	if sec == null or not sec.is_visible_in_tree() or not sec.is_open():
		return false
	return _module_matches(sec.get("_content"), id)

func _refresh() -> void:
	for id in buttons:
		var b := buttons[id] as Button
		var on := is_active(id)
		if b.button_pressed != on:
			b.set_pressed_no_signal(on)

# ── Script / Complementos: misma sección, distinta página ───────────────────
func _select_module(content: Variant, id: String) -> void:
	if content is Object and is_instance_valid(content) and (content as Object).has_method("show_module"):
		(content as Object).call("show_module", "addons" if id == "plugins" else "scripts")

func _module_matches(content: Variant, id: String) -> bool:
	if not (id in ["script", "plugins"]):
		return true
	if not (content is Node) or not is_instance_valid(content):
		return id == "script"
	var page := (content as Node).get_node_or_null("AddonsPage") as Control
	var addons_on := page != null and page.visible
	return addons_on if id == "plugins" else not addons_on

# ── dónde está cada cosa ────────────────────────────────────────────────────
## Panel del modo: el Inspector (Modern) o el estudio lateral (Pro).
func _host() -> Control:
	var want := "docked_inspector.gd" if _mode() == "modern" else "pro_studio.gd"
	for c in get_tree().root.find_children("*", "Control", true, false):
		var s = c.get_script()
		if s and String(s.resource_path).get_file() == want:
			return c
	return null

func _scroll_to(c: Control) -> void:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)
			# Que el principio de la sección quede arriba (no solo «a la vista»).
			var sc := p as ScrollContainer
			var top := c.get_global_rect().position.y - sc.get_global_rect().position.y
			sc.scroll_vertical = int(sc.scroll_vertical + top)
			return
		p = p.get_parent()

func _smart_window() -> Control:
	return get_tree().root.find_child("panel__effects", true, false) as Control

func _smart_host(id: String) -> String:
	return {"shader": "Shader", "script": "Script", "plugins": "Script", "vectorize": "Vectorizar"}[id]

func _open_smart(id: String) -> void:
	var win := _smart_window()
	if win == null or not win.visible:
		var ge := get_node_or_null("/root/GlobalEvents")
		if ge and ge.has_signal("request_floating_panel"):
			ge.emit_safe("request_floating_panel", "panel__effects")
		await get_tree().process_frame
		win = _smart_window()
	if win == null:
		return
	var tab_name := ""
	for it in ITEMS:
		if String(it[0]) == id:
			tab_name = String(it[4])
	var tab := win.find_child(tab_name, true, false) as BaseButton
	if tab:
		tab.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var host := win.find_child(_smart_host(id), true, false)
	if host and id in ["script", "plugins"]:
		_select_module(_smart_content(host), id)

## Editor de scripts dentro de la pestaña Script de la ventana de Smart.
func _smart_content(host: Node) -> Node:
	for n in host.find_children("*", "", true, false):
		if n.has_method("show_module"):
			return n
	return null
