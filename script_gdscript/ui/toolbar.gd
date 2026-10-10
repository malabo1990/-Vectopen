extends Control

## Barra vertical de herramientas (izquierda del lienzo).
##
## Mismo lenguaje visual que el panel de capas: superficie blanca sin marco ni
## sombra, esquinas redondeadas y chips de botón que sólo se ven al pasar el
## ratón. La herramienta ACTIVA se marca con un chip gris claro y el icono en
## NEGRO; las inactivas van en gris medio. Sin azul. Los iconos SVG del proyecto
## son negros, así que se reconvierten a blanco (`_blanco`) para poder teñirlos
## claros u oscuros con `icon_*_color` (el modulate MULTIPLICA: un negro no se
## puede aclarar).

const _ICON_PX := 20
const _ICONO_OFF := Color(0.44, 0.44, 0.47, 1.0)   # inactiva: gris medio, legible
const _ICONO_HOVER := Color(0.10, 0.10, 0.11, 1.0) # al pasar el ratón: negro
const _ICONO_ON := Color(0.10, 0.10, 0.11, 1.0)    # activa: negro

static var _blanco_cache: Dictionary = {}

var _tool_activa: String = "select"

func _ready() -> void:
	call_deferred("_init_toolbar")

func _init_toolbar() -> void:
	_preparar_iconos()
	_conectar_botones()
	_aplicar_tema()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.connect(_on_theme_changed)
	# Atajos de teclado (V/M/B/T…) cambian de herramienta sin pasar por el botón;
	# ToolManager emite `data_tool_changed` para las que gestiona.
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("data_tool_changed") and not ge.data_tool_changed.is_connected(_on_data_tool_changed):
		ge.data_tool_changed.connect(_on_data_tool_changed)

func _on_theme_changed(_mode: String) -> void:
	_aplicar_tema()

func _on_data_tool_changed(tool_name: String) -> void:
	marcar_activa(tool_name)

# ── API (compatible con canvas.gd::_sincronizar_ui_toolbar) ──────────────────
func actualizar_botones_visuales(current_tool) -> void:
	if current_tool is String and String(current_tool) != "":
		_tool_activa = String(current_tool)
	elif current_tool != null:
		var cname := ""
		if current_tool.has_method("get_class_name"):
			cname = String(current_tool.get_class_name())
		elif current_tool is NodeSelectionTool:
			cname = "NodeSelectionTool"
		if cname == "NodeSelectionTool":
			_tool_activa = "nodeselection"
		elif cname == "MoveTool" and _tool_activa != "move":
			_tool_activa = "select"
	_refrescar_estado()

## Fija la herramienta resaltada por nombre (lo usan los propios botones).
func marcar_activa(nombre: String) -> void:
	if nombre == "":
		return
	_tool_activa = nombre
	_refrescar_estado()

# ── Botones ─────────────────────────────────────────────────────────────────
func _botones() -> Array:
	var out: Array = []
	for c in get_children():
		if c is Button:
			out.append(c)
	return out

func _conectar_botones() -> void:
	for b in _botones():
		if not b.pressed.is_connected(_on_boton_pulsado):
			b.pressed.connect(_on_boton_pulsado.bind(b))

func _on_boton_pulsado(b: Button) -> void:
	if "tool_name" in b and String(b.tool_name) != "":
		_tool_activa = String(b.tool_name)
	# Los botones-panel (btn_toggle) cambian la visibilidad de su panel en el
	# mismo frame; se relee de forma diferida.
	call_deferred("_refrescar_estado")

func _es_activo(b: Button) -> bool:
	if "tool_name" in b and String(b.tool_name) != "":
		return String(b.tool_name) == _tool_activa
	if "target_node" in b:
		var t = b.target_node
		return is_instance_valid(t) and "visible" in t and t.visible
	return false

# ── Tema ────────────────────────────────────────────────────────────────────
func _preparar_iconos() -> void:
	for b in _botones():
		b.focus_mode = Control.FOCUS_NONE
		b.expand_icon = false
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		if b.icon and not b.has_meta("_icono_blanco"):
			b.icon = _blanco(b.icon)
			b.set_meta("_icono_blanco", true)

func _panel_container() -> PanelContainer:
	var n := get_parent()
	while n:
		if n is PanelContainer:
			return n
		n = n.get_parent()
	return null

func _aplicar_tema() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null:
		return
	var S = tm.Slot
	var pc := _panel_container()
	if pc:
		var sb := StyleBoxFlat.new()
		sb.bg_color = tm.get_color(S.PANEL_SURFACE)
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(0)
		sb.shadow_size = 0
		pc.add_theme_stylebox_override("panel", sb)
	add_theme_constant_override("separation", 6)
	_theme_subpanels()
	_refrescar_estado()

func _theme_subpanels() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null: return
	var S = tm.Slot
	var surface_c: Color = tm.get_color(S.PANEL_SURFACE)
	var border_c: Color = tm.get_color(S.BORDER)
	var text_c: Color = tm.get_color(S.PANEL_TEXT)

	var parent_tools = get_parent()
	while parent_tools and parent_tools.name != "Herramientas":
		parent_tools = parent_tools.get_parent()
	if not parent_tools: return

	var sub_hov := StyleBoxFlat.new()
	sub_hov.bg_color = tm.get_color(S.BUTTON_HOVER)
	sub_hov.set_corner_radius_all(6)
	var sub_prs := StyleBoxFlat.new()
	sub_prs.bg_color = tm.get_color(S.BUTTON_PRESSED)
	sub_prs.set_corner_radius_all(6)

	for sub_name in ["polygon", "text", "Selector"]:
		var p = parent_tools.get_node_or_null(sub_name) as PanelContainer
		# Paneles con tema propio (p.ej. Polígonos: pestañas con icono y
		# estado activo): el estilo genérico de abajo les borraba el fondo.
		if is_instance_valid(p) and p.has_method("_apply_theme"):
			p._apply_theme()
			continue
		if is_instance_valid(p):
			var sb := StyleBoxFlat.new()
			sb.bg_color = surface_c
			sb.border_color = border_c
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(10)
			sb.shadow_color = Color(0, 0, 0, 0.3) if surface_c.get_luminance() < 0.5 else Color(0, 0, 0, 0.1)
			sb.shadow_size = 10
			p.add_theme_stylebox_override("panel", sb)
			for lbl in p.find_children("", "Label", true, false):
				(lbl as Label).add_theme_color_override("font_color", text_c)
			for btn in p.find_children("", "Button", true, false):
				var b := btn as Button
				if b.icon and tm.has_method("make_white_icon"):
					b.icon = tm.make_white_icon(b.icon, 20)
				b.modulate = Color.WHITE
				b.add_theme_color_override("icon_normal_color", tm.get_color(S.ICON_PRIMARY))
				b.add_theme_color_override("icon_hover_color", tm.get_color(S.PANEL_TEXT))
				b.add_theme_color_override("icon_pressed_color", tm.get_color(S.ACCENT))
				b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
				b.add_theme_stylebox_override("hover", sub_hov)
				b.add_theme_stylebox_override("pressed", sub_prs)
				b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _chip(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(9)
	s.set_content_margin_all(5)
	return s

func _transparente() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.set_content_margin_all(5)
	return s

func _refrescar_estado() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null:
		return
	var S = tm.Slot
	var hov: Color = tm.get_color(S.BUTTON_HOVER)
	var prs: Color = tm.get_color(S.BUTTON_PRESSED)
	var activa_bg: Color = tm.get_color(S.SURFACE_RAISED)
	var icon_on: Color = tm.get_color(S.ICON_PRIMARY)
	var icon_off: Color = tm.get_color(S.ICON_MUTED)
	var icon_hover: Color = tm.get_color(S.ICON_PRIMARY)
	for b in _botones():
		var activo := _es_activo(b)
		b.add_theme_stylebox_override("normal", _chip(activa_bg) if activo else _transparente())
		b.add_theme_stylebox_override("hover", _chip(activa_bg) if activo else _chip(hov))
		b.add_theme_stylebox_override("pressed", _chip(prs))
		b.add_theme_stylebox_override("focus", _transparente())
		var col: Color = icon_on if activo else icon_off
		b.add_theme_color_override("icon_normal_color", col)
		b.add_theme_color_override("icon_pressed_color", icon_on)
		b.add_theme_color_override("icon_hover_color", icon_hover)
		b.add_theme_color_override("icon_focus_color", col)

## Copia del icono con todos los píxeles a blanco (mismo alfa), a `_ICON_PX`.
func _blanco(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var clave := str(tex.get_rid())
	if _blanco_cache.has(clave):
		return _blanco_cache[clave]
	var img := tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != _ICON_PX or img.get_height() != _ICON_PX:
		img.resize(_ICON_PX, _ICON_PX, Image.INTERPOLATE_LANCZOS)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	var out: Texture2D = ImageTexture.create_from_image(img)
	_blanco_cache[clave] = out
	return out
