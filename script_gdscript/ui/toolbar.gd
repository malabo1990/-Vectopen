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
	elif current_tool != null and current_tool.has_method("get_class_name"):
		if String(current_tool.get_class_name()) == "MoveTool" and _tool_activa != "move":
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
	_refrescar_estado()

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
	for b in _botones():
		var activo := _es_activo(b)
		b.add_theme_stylebox_override("normal", _chip(activa_bg) if activo else _transparente())
		b.add_theme_stylebox_override("hover", _chip(activa_bg) if activo else _chip(hov))
		b.add_theme_stylebox_override("pressed", _chip(prs))
		b.add_theme_stylebox_override("focus", _transparente())
		var col: Color = _ICONO_ON if activo else _ICONO_OFF
		b.add_theme_color_override("icon_normal_color", col)
		b.add_theme_color_override("icon_pressed_color", _ICONO_ON)
		b.add_theme_color_override("icon_hover_color", _ICONO_ON if activo else _ICONO_HOVER)
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
