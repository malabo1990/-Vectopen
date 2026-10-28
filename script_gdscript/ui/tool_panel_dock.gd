# =============================================================================
# VECTOPEN — DOCK DE PANELES DE HERRAMIENTA
# RUTA: res://script_gdscript/ui/tool_panel_dock.gd
#
# Acopla los paneles de herramienta (Selector, Bézier, Pincel, Polígono,
# Texto) dentro del inspector lateral en los modos Modern (DockedInspector) y
# Pro (ProStudio), en vez de dejarlos flotando sobre el lienzo como en Smart.
# Pedido del usuario: "cambiar los paneles de herramientas a inspector para
# UI modern y pro también".
#
# - Un panel acoplado pierde su marco flotante (fondo, sombra, borde) y se
#   ajusta al ancho del lateral; al soltarlo recupera todo tal cual estaba.
# - El dock solo se ve cuando hay algún panel de herramienta abierto, y
#   muestra UNO a la vez: abrir otro cierra el anterior (antes se apilaban
#   Polígonos + Pincel + Texto en el lateral).
# - El propio dock es persistente: ProStudio reconstruye su UI al cambiar de
#   tema y lo vuelve a insertar (no se pierden los paneles acoplados).
# =============================================================================
class_name ToolPanelDock
extends VBoxContainer

## Se emite cuando cambia qué paneles se ven (para reajustar el lateral).
signal content_changed()

var _slot: VBoxContainer
var _hosted: Dictionary = {}   # panel -> {estado original}

func _init(header: Control = null) -> void:
	name = "ToolPanelDock"
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visible = false
	if header:
		add_child(header)
	_slot = VBoxContainer.new()
	_slot.name = "ToolPanelSlot"
	_slot.add_theme_constant_override("separation", 6)
	_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_slot)

func _ready() -> void:
	# Los paneles repintan su marco flotante al cambiar de tema: quitarlo
	# otra vez después (diferido, para ir detrás de su propio _apply_theme).
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _reflatten.call_deferred())

## Tamaño de letra base de los paneles de herramienta (Smart, Modern y Pro).
## Sus títulos y notas ya fijan 10-13 px, pero casillas, desplegables y
## botones sin tamaño propio caían al de Godot (16 px) y se veían enormes al
## lado del resto. Solo pone el tamaño base: no toca colores ni estilos.
const BASE_FONT_SIZE := 11

## Tipos sin tamaño propio. Hace falta fijarlos uno a uno: el tema del
## lateral (Modern/Pro) define "Button/font_size" = 16 y eso gana a un simple
## default_font_size del panel ("+ Crear en el centro" salía enorme).
const _FONT_TYPES := ["Label", "Button", "CheckBox", "CheckButton", "OptionButton",
	"MenuButton", "LineEdit", "SpinBox", "PopupMenu", "TooltipLabel"]

static func normalize_fonts(panel: Control) -> void:
	if not is_instance_valid(panel):
		return
	if panel.theme == null:
		panel.theme = Theme.new()
	panel.theme.default_font_size = BASE_FONT_SIZE
	for t in _FONT_TYPES:
		panel.theme.set_font_size("font_size", t, BASE_FONT_SIZE)
	apply_theme_colors(panel)
	# Al cambiar de tema (claro / oscuro / preset) se vuelven a pintar.
	var tm := panel.get_node_or_null("/root/ThemeManager") if panel.is_inside_tree() else null
	if tm == null and Engine.get_main_loop() is SceneTree:
		tm = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("ThemeManager")
	if tm and tm.has_signal("theme_changed") and not panel.has_meta("_tpd_theme_hooked"):
		panel.set_meta("_tpd_theme_hooked", true)
		tm.theme_changed.connect(func(_m) -> void:
			if is_instance_valid(panel):
				apply_theme_colors(panel))

## Colores del TEMA ACTUAL para textos, casillas y botones sin estilo propio.
## Antes heredaban el blanco por defecto de Godot: flotando sobre su fondo
## oscuro se leía, pero acoplados en el inspector con tema claro el texto
## quedaba blanco sobre gris claro (ilegible).
static func apply_theme_colors(panel: Control) -> void:
	if not is_instance_valid(panel) or panel.theme == null:
		return
	var th := panel.theme
	var text := ProUIStyle.col("PANEL_TEXT")
	var muted := ProUIStyle.col("TEXT_SECONDARY")
	var disabled := ProUIStyle.col("TEXT_DISABLED")
	for t in ["Label", "CheckBox", "CheckButton"]:
		th.set_color("font_color", t, text)
		th.set_color("font_hover_color", t, text)
		th.set_color("font_pressed_color", t, text)
		th.set_color("font_disabled_color", t, disabled)
	th.set_color("font_color", "LineEdit", text)
	th.set_color("font_placeholder_color", "LineEdit", muted)
	for t in ["Button", "OptionButton", "MenuButton"]:
		th.set_color("font_color", t, ProUIStyle.col("BUTTON_TEXT"))
		th.set_color("font_hover_color", t, ProUIStyle.col("BUTTON_TEXT"))
		th.set_color("font_pressed_color", t, ProUIStyle.col("BUTTON_TEXT"))
		th.set_color("font_focus_color", t, ProUIStyle.col("BUTTON_TEXT"))
		th.set_color("font_disabled_color", t, disabled)
		th.set_color("icon_normal_color", t, ProUIStyle.col("ICON_PRIMARY"))
		th.set_stylebox("normal", t, ProUIStyle.flat(ProUIStyle.col("BUTTON_BG"), 5, ProUIStyle.col("BORDER"), 6, 3))
		th.set_stylebox("hover", t, ProUIStyle.flat(ProUIStyle.col("BUTTON_HOVER"), 5, ProUIStyle.col("BORDER_STRONG"), 6, 3))
		th.set_stylebox("pressed", t, ProUIStyle.flat(ProUIStyle.col("BUTTON_PRESSED"), 5, ProUIStyle.col("ACCENT"), 6, 3))
		th.set_stylebox("disabled", t, ProUIStyle.flat(ProUIStyle.col("BUTTON_BG"), 5, ProUIStyle.col("BORDER"), 6, 3))
		th.set_stylebox("focus", t, StyleBoxEmpty.new())

func is_hosting(panel: Control) -> bool:
	return _hosted.has(panel)

func hosted_panels() -> Array:
	return _hosted.keys()

## Mueve `panel` dentro del dock (idempotente).
func host(panel: Control) -> void:
	if not is_instance_valid(panel):
		return
	if _hosted.has(panel):
		_refresh()
		return
	_hosted[panel] = {
		"min": panel.custom_minimum_size,
		"anchors": [panel.anchor_left, panel.anchor_top, panel.anchor_right, panel.anchor_bottom],
		"offsets": [panel.offset_left, panel.offset_top, panel.offset_right, panel.offset_bottom],
		"hflags": panel.size_flags_horizontal,
		"z": panel.z_index,
		"had_style": panel.has_theme_stylebox_override("panel"),
		"style": panel.get_theme_stylebox("panel") if panel.has_theme_stylebox_override("panel") else null,
	}
	var old_parent := panel.get_parent()
	if is_instance_valid(old_parent):
		old_parent.remove_child(panel)
	_slot.add_child(panel)
	panel.custom_minimum_size = Vector2.ZERO
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Flotando llevan z_index 100; acoplados no deben tapar popovers del lateral.
	panel.z_index = 0
	_flatten(panel)
	# Letra y colores del tema para CUALQUIER panel acoplado (texto y
	# Selector no tienen script propio que lo haga).
	normalize_fonts(panel)
	var cb := _on_panel_visibility.bind(panel)
	_hosted[panel]["cb"] = cb
	panel.visibility_changed.connect(cb)
	_refresh()

## Devuelve todos los paneles a `target_parent` con su aspecto original.
## Quedan ocultos (como estaban en Smart antes de elegir herramienta).
func release_all(target_parent: Node) -> void:
	for key in _hosted.keys():
		var panel := key as Control
		var st: Dictionary = _hosted[key]
		if not is_instance_valid(panel):
			continue
		if panel.visibility_changed.is_connected(st["cb"]):
			panel.visibility_changed.disconnect(st["cb"])
		panel.visible = false
		if is_instance_valid(panel.get_parent()):
			panel.get_parent().remove_child(panel)
		if is_instance_valid(target_parent):
			target_parent.add_child(panel)
		panel.custom_minimum_size = st["min"]
		panel.size_flags_horizontal = st["hflags"]
		panel.z_index = st["z"]
		if st["had_style"]:
			panel.add_theme_stylebox_override("panel", st["style"])
		else:
			panel.remove_theme_stylebox_override("panel")
		var a: Array = st["anchors"]
		var o: Array = st["offsets"]
		panel.anchor_left = a[0]
		panel.anchor_top = a[1]
		panel.anchor_right = a[2]
		panel.anchor_bottom = a[3]
		panel.offset_left = o[0]
		panel.offset_top = o[1]
		panel.offset_right = o[2]
		panel.offset_bottom = o[3]
	_hosted.clear()
	_refresh()

## Sin marco de ventana flotante: dentro del lateral se ve como una sección.
static func _flatten(panel: Control) -> void:
	var flat := StyleBoxEmpty.new()
	flat.content_margin_left = 0
	flat.content_margin_right = 0
	flat.content_margin_top = 2
	flat.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", flat)

func _reflatten() -> void:
	for key in _hosted.keys():
		if is_instance_valid(key):
			_flatten(key as Control)

func _on_panel_visibility(panel: Control) -> void:
	# Un panel a la vez: el que se abre cierra a los demás.
	if is_instance_valid(panel) and panel.visible:
		for key in _hosted.keys():
			if key != panel and is_instance_valid(key) and (key as Control).visible:
				(key as Control).visible = false
	_refresh()

func _refresh() -> void:
	var any := false
	for key in _hosted.keys():
		if is_instance_valid(key) and (key as Control).visible:
			any = true
			break
	visible = any
	content_changed.emit()
