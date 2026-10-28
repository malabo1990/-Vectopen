# =============================================================================
# VECTOPEN — SECCIONES «FILTROS» Y «VECTORIZAR» DEL INSPECTOR (Modern y Pro)
# RUTA: res://script_gdscript/ui/components/inspector_fx_sections.gd
#
# Pedido del usuario: los filtros y el vectorizado tienen que estar en el
# inspector (como el texto, los efectos y el trazo), no en botones de la
# barra. Reutiliza los MISMOS paneles que la ventana de Efectos de Smart
# (filters_panel.gd y vectorize_panel.gd): una sola implementación.
#
# - Plegables (el inspector no se hace eterno); el estado se recuerda.
# - FILTROS se ve con algo seleccionado; VECTORIZAR solo con una imagen.
# =============================================================================
extends VBoxContainer

const FILTERS := "filters"
const VECTORIZE := "vectorize"

## Plegado / desplegado por sección (compartido entre Modern y Pro).
static var _open := {FILTERS: false, VECTORIZE: true}

var kind := FILTERS
var _btn: Button
var _body: Control
var _content: Control = null

static func create(section_kind: String, node_name: String) -> Control:
	var s = load("res://script_gdscript/ui/components/inspector_fx_sections.gd").new()
	s.kind = section_kind
	s.name = node_name
	return s

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn = Button.new()
	_btn.name = "Header"
	_btn.flat = true
	_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 10)
	_btn.pressed.connect(_toggle)
	add_child(_btn)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)
	_apply_theme()
	_refresh_header()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed"):
		ic.changed.connect(func(_p) -> void: _sync_visibility())
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _apply_theme())
	var lm := get_node_or_null("/root/LanguageManager")
	if lm and lm.has_signal("language_changed"):
		lm.language_changed.connect(func(_l) -> void: _refresh_header())
	_sync_visibility()

func title() -> String:
	return tr("FILTERS_SECTION") if kind == FILTERS else tr("VECTORIZE_SECTION")

func is_open() -> bool:
	return bool(_open.get(kind, false))

func _toggle() -> void:
	_open[kind] = not is_open()
	_refresh_header()

func _refresh_header() -> void:
	if not is_instance_valid(_btn):
		return
	_btn.text = ("▾  " if is_open() else "▸  ") + title()
	_btn.tooltip_text = tr("Mostrar / ocultar")
	if is_open():
		_ensure_content()
	_body.visible = is_open()

## El panel se crea al abrir la sección la primera vez (arranque ligero).
func _ensure_content() -> void:
	if is_instance_valid(_content):
		return
	var path := "res://script_gdscript/ui/panels/effects/%s.gd" % ("filters_panel" if kind == FILTERS else "vectorize_panel")
	_content = load(path).new()
	_content.name = "FiltersContent" if kind == FILTERS else "VectorizeContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_content)
	# Su título («Filtros») sobra: la cabecera plegable ya lo dice.
	var t = _content.get("_title")
	if t is CanvasItem:
		(t as CanvasItem).visible = false

## FILTROS: hay selección. VECTORIZAR: la selección tiene una imagen.
func _sync_visibility() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	var sel: Array = ic.selection() if ic and ic.has_method("selection") else []
	if kind == FILTERS:
		visible = not sel.is_empty()
	else:
		var has_img := false
		for n in sel:
			if is_instance_valid(n) and (n is Sprite2D or (n is Node and n.has_meta("image_path"))):
				has_img = true
				break
		visible = has_img

func _apply_theme() -> void:
	if not is_instance_valid(_btn):
		return
	var tm := get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var muted: Color = tm.get_color(S.TEXT_SECONDARY) if (tm and S) else Color(0.6, 0.6, 0.65)
	var text: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color(0.9, 0.9, 0.9)
	_btn.add_theme_color_override("font_color", muted)
	_btn.add_theme_color_override("font_hover_color", text)
	_btn.add_theme_color_override("font_pressed_color", text)
