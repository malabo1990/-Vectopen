# =============================================================================
# RUTA: res://script_gdscript/ui/panels/layers_settings.gd
# AJUSTES DEL PANEL DE CAPAS (botón ⚙ arriba a la izquierda del panel).
# Antes era una maqueta en inglés sin ningún código detrás. Ahora:
#   · Texto de la lista de capas (tamaño) y altura de filas (densidad).
#   · Opacidad del panel.
#   · Pestaña al abrir: Capas, Páginas, Recursos o la última usada.
#   · Tamaño de las miniaturas de Recursos.
# Se guarda en user://vectopen_layers_ui.cfg y se aplica al arrancar.
# Los colores los pone el tema (modo claro/oscuro), no se tocan aquí.
# =============================================================================
extends RefCounted

const FxUI = preload("res://script_gdscript/ui/panels/effects/fx_ui.gd")
const CFG := "user://vectopen_layers_ui.cfg"
const DEFAULTS := {"font_size": 12, "density": 1, "opacity": 1.0, "start_tab": "last", "thumb": 56}
const DENSITY := [["Compacto", 0], ["Normal", 4], ["Amplio", 9]]
const TABS := [["Última usada", "last"], ["Capas", "capas"], ["Páginas", "paginas"], ["Recursos", "recursos"]]

static func load_settings() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	var out := DEFAULTS.duplicate()
	for k in DEFAULTS:
		out[k] = cfg.get_value("panel", k, DEFAULTS[k])
	out["last_tab"] = cfg.get_value("panel", "last_tab", "capas")
	return out

static func save_value(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("panel", key, value)
	cfg.save(CFG)

## Aplica los ajustes al panel (`layers`: el nodo LayersSystem).
static func apply(layers: Node, s: Dictionary = {}) -> void:
	if s.is_empty():
		s = load_settings()
	var tree: Tree = layers.get("layer_tree")
	if is_instance_valid(tree):
		tree.add_theme_font_size_override("font_size", int(s["font_size"]))
		tree.add_theme_constant_override("v_separation", int(DENSITY[clampi(int(s["density"]), 0, 2)][1]))
	var panel := _panel_root(layers)
	if panel:
		panel.modulate.a = clampf(float(s["opacity"]), 0.4, 1.0)
	var rec := layers.find_child("RecursosPanel", true, false)
	if rec and rec.has_method("set_thumb_size"):
		rec.set_thumb_size(int(s["thumb"]))

static func _panel_root(layers: Node) -> CanvasItem:
	var n: Node = layers
	while n and not (n.get_parent() and n.get_parent().name == "Layout"):
		n = n.get_parent()
	return n as CanvasItem

## Pestaña con la que se abre el panel.
static func start_tab() -> String:
	var s := load_settings()
	return String(s["last_tab"]) if String(s["start_tab"]) == "last" else String(s["start_tab"])

## Monta el botón ⚙ y el contenido real en el panel «Configuracion de Capas».
static func install(button: Button, host: Control, layers: Node) -> void:
	if button == null or host == null or host.has_meta("vectopen_settings"):
		return
	host.set_meta("vectopen_settings", true)
	button.icon = null
	button.text = "⚙"
	button.tooltip_text = "Ajustes del panel de capas"
	button.custom_minimum_size = Vector2(22, 22)
	button.offset_left = 9
	button.offset_top = 9
	button.offset_right = 31
	button.offset_bottom = 31
	button.focus_mode = Control.FOCUS_NONE
	for c in host.get_children():
		host.remove_child(c)
		c.queue_free()
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	host.add_child(m)
	var v := VBoxContainer.new()
	v.name = "Settings"
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(250, 0)
	m.add_child(v)
	var s := load_settings()
	var title := Label.new()
	title.text = "Ajustes del panel"
	title.add_theme_font_size_override("font_size", 13)
	v.add_child(title)
	var font_sl := _slider_row(v, "Texto de las capas", 10, 18, 1, float(s["font_size"]), "%d px")
	font_sl.name = "FontSize"
	font_sl.value_changed.connect(func(x: float) -> void:
		save_value("font_size", int(x))
		apply(layers))
	var dens := _option_row(v, "Altura de filas", DENSITY.map(func(d) -> String: return d[0]), int(s["density"]))
	dens.name = "Density"
	dens.item_selected.connect(func(i: int) -> void:
		save_value("density", i)
		apply(layers))
	var op := _slider_row(v, "Opacidad del panel", 40, 100, 5, float(s["opacity"]) * 100.0, "%d %%")
	op.name = "Opacity"
	op.value_changed.connect(func(x: float) -> void:
		save_value("opacity", x / 100.0)
		apply(layers))
	var tab_i := 0
	for i in TABS.size():
		if TABS[i][1] == String(s["start_tab"]):
			tab_i = i
	var tab := _option_row(v, "Pestaña al abrir", TABS.map(func(t) -> String: return t[0]), tab_i)
	tab.name = "StartTab"
	tab.item_selected.connect(func(i: int) -> void: save_value("start_tab", TABS[i][1]))
	var th := _slider_row(v, "Miniaturas de Recursos", 32, 128, 4, float(s["thumb"]), "%d px")
	th.name = "Thumb"
	th.value_changed.connect(func(x: float) -> void:
		save_value("thumb", int(x))
		apply(layers))
	var reset := Button.new()
	reset.name = "Reset"
	reset.text = "Restablecer"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void:
		for k in DEFAULTS:
			save_value(k, DEFAULTS[k])
		font_sl.set_value_no_signal(DEFAULTS["font_size"])
		dens.select(int(DEFAULTS["density"]))
		op.set_value_no_signal(100)
		tab.select(0)
		th.set_value_no_signal(DEFAULTS["thumb"])
		for sl in [font_sl, op, th]:
			sl.value_changed.emit(sl.value)
		apply(layers))
	v.add_child(reset)
	restyle(button, host)
	var tm := host.get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		# función estática: la conexión NO se suelta sola al borrar el panel;
		# se desconecta al salir de la escena (si no, repintaba nodos borrados)
		var cb := func(_m) -> void:
			if is_instance_valid(button) and is_instance_valid(host):
				restyle(button, host)
		tm.theme_changed.connect(cb)
		host.tree_exiting.connect(func() -> void:
			if tm.theme_changed.is_connected(cb):
				tm.theme_changed.disconnect(cb), CONNECT_ONE_SHOT)

static func _slider_row(parent: Control, label: String, lo: float, hi: float, step: float, value: float, fmt: String) -> HSlider:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)
	var head := HBoxContainer.new()
	row.add_child(head)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	var val := Label.new()
	val.text = fmt % int(value)
	val.set_meta("value_label", true)
	head.add_child(val)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.value_changed.connect(func(x: float) -> void: val.text = fmt % int(x))
	row.add_child(sl)
	return sl

static func _option_row(parent: Control, label: String, items: Array, selected: int) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for it in items:
		o.add_item(String(it))
	o.select(selected)
	row.add_child(o)
	return o

static func restyle(button: Button, host: Control) -> void:
	button.add_theme_font_size_override("font_size", 14)
	for k in ["font_color", "font_focus_color"]:
		button.add_theme_color_override(k, FxUI.c("TEXT_SECONDARY"))
	button.add_theme_color_override("font_hover_color", FxUI.c("PANEL_TEXT"))
	button.add_theme_color_override("font_pressed_color", FxUI.c("ACCENT"))
	button.add_theme_stylebox_override("normal", FxUI.flat(Color(0, 0, 0, 0), 5, Color(0, 0, 0, 0), 0, 0))
	button.add_theme_stylebox_override("hover", FxUI.flat(FxUI.c("BUTTON_HOVER"), 5, Color(0, 0, 0, 0), 0, 0))
	button.add_theme_stylebox_override("pressed", FxUI.flat(FxUI.c("BUTTON_PRESSED"), 5, Color(0, 0, 0, 0), 0, 0))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	host.add_theme_stylebox_override("panel", FxUI.flat(FxUI.c("PANEL_BG"), 10, FxUI.c("BORDER_STRONG"), 0, 0))
	for l in host.find_children("*", "Label", true, false):
		l.add_theme_font_size_override("font_size", 13 if l.get_parent().name == "Settings" else 11)
		l.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY") if l.has_meta("value_label") else FxUI.c("PANEL_TEXT"))
	for sl in host.find_children("*", "HSlider", true, false):
		ProUIStyle.style_slider(sl)
	for o in host.find_children("*", "OptionButton", true, false):
		ProUIStyle.style_option(o)
		o.add_theme_font_size_override("font_size", 11)
	for b in host.find_children("*", "Button", true, false):
		if not (b is OptionButton):
			b.add_theme_font_size_override("font_size", 11)
			b.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
			b.add_theme_stylebox_override("normal", FxUI.flat(FxUI.c("INPUT_BG"), 5, FxUI.c("INPUT_BORDER"), 8, 3))
			b.add_theme_stylebox_override("hover", FxUI.flat(FxUI.c("BUTTON_HOVER"), 5, FxUI.c("BORDER_STRONG"), 8, 3))
