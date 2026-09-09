extends Control
## Panel de texto (panel_tooltext.tscn) → InspectorCore + FontCore.
##
## · Los sliders que rodean la "A" controlan propiedades de la SELECCIÓN del
##   canvas (con undo), no una etiqueta local de adorno.
## · El botón de familia abre el navegador de fuentes: lista real de las
##   tipografías del SISTEMA + las empaquetadas (FontCore), con búsqueda y
##   previsualización, y al elegir una la aplica a la selección.
##
## Mapeo de sliders (según los nombres de nodo del .tscn):
##   · Panel/Label/HSlider       → font_size       [8 .. 200]
##   · Panel/Label/line_space    → line_spacing    [-20 .. 80]
##   · Panel/Label/letras_space  → letter_spacing  [-10 .. 40]  (tracking)
##
## Antes: 4 @export sin asignar + un RichTextLabel de adorno → warning en cada
## arranque y cero efecto real.

const _SLIDER_PROPS := {
	"Panel/Label/HSlider": "font_size",
	"Panel/Label/line_space": "line_spacing",
	"Panel/Label/letras_space": "letter_spacing",
}
const _SLIDER_RANGE := {
	"font_size": [8.0, 200.0, 1.0],
	"line_spacing": [-20.0, 80.0, 1.0],
	"letter_spacing": [-10.0, 40.0, 1.0],
}

# ── rutas del navegador de fuentes (relativas a este nodo) ────────────────────
const _FONT_BTN := "Panel/BoxContainer/Button_font"
const _FONT_POPUP := "Panel/BoxContainer/Button_font/Panel_font"
const _FONT_LIST := "Panel/BoxContainer/Button_font/Panel_font/MarginContainer/BoxContainer/GridContainer/ScrollContainer/BoxContainer"
const _FONT_LIST_2 := "Panel/BoxContainer/Button_font/Panel_font/MarginContainer/BoxContainer/GridContainer/ScrollContainer2"
const _FONT_SEARCH := "Panel/BoxContainer/Button_font/Panel_font/MarginContainer/BoxContainer/BoxContainer/LineEdit"
const _FONT_SEARCH_BTN := "Panel/BoxContainer/Button_font/Panel_font/MarginContainer/BoxContainer/BoxContainer/Button"
const _FONT_PREVIEW := "Panel/BoxContainer/Button_font/Panel_font/MarginContainer/BoxContainer/GridContainer/BoxContainer2/RichTextLabel"
const _MAX_ROWS := 250

# ── botones de alineación / caja / estilo (relativos a este nodo) ─────────────
const _ALIGN_BTNS := {
	"Panel/VBoxContainer/BoxContainer2/Button": "left",
	"Panel/VBoxContainer/BoxContainer2/Button4": "center",
	"Panel/VBoxContainer/BoxContainer2/Button3": "right",
	"Panel/VBoxContainer/BoxContainer2/Button2": "fill",     # justificado
}
const _VALIGN_BTNS := {
	"Panel/VBoxContainer/BoxContainer_Valign/BtnVTop": "top",
	"Panel/VBoxContainer/BoxContainer_Valign/BtnVMiddle": "middle",
	"Panel/VBoxContainer/BoxContainer_Valign/BtnVBottom": "bottom",
}
const _CASE_BTNS := {
	"Panel/VBoxContainer/BoxContainer4/Button": "upper",     # AA
	"Panel/VBoxContainer/BoxContainer4/Button4": "title",    # Aa
	"Panel/VBoxContainer/BoxContainer4/Button2": "lower",    # aa
	"Panel/VBoxContainer/BoxContainer4/Button3": "toggle",   # aA
}
const _STYLE_OPTION := "Panel/BoxContainer/OptionButton"

const _PROP_BTNS := {
	"Panel/VBoxContainer/BoxContainer5/Button": "Aaa",
	"Panel/VBoxContainer/BoxContainer5/Button4": "aAa",
	"Panel/VBoxContainer/BoxContainer5/Button2": "aaA",
	"Panel/VBoxContainer/BoxContainer5/Button3": "AaA",
}
const _PROP_PRESETS := {
	"Aaa": {"start": 1.6, "mid": 1.2, "mid2": 0.8, "end": 0.4},
	"aAa": {"start": 0.4, "mid": 1.4, "mid2": 1.4, "end": 0.4},
	"aaA": {"start": 0.4, "mid": 0.8, "mid2": 1.2, "end": 1.6},
	"AaA": {"start": 1.5, "mid": 0.5, "mid2": 0.5, "end": 1.5},
}
const _PROP_SLIDERS := {
	"start": "Panel/VBoxContainer/HBoxContainer/HSlider",
	"mid": "Panel/VBoxContainer/HBoxContainer/HSlider2",
	"mid2": "Panel/VBoxContainer/HBoxContainer/HSlider3",
	"end": "Panel/VBoxContainer/HBoxContainer/HSlider4",
}

const _CHIP_NORMAL := Color(0.95, 0.95, 0.97, 1.0)
const _CHIP_HOVER := Color(0.90, 0.91, 0.94, 1.0)
const _CHIP_ACTIVE := Color(0.85, 0.85, 0.88, 1.0)
const _CHIP_BORDER := Color(0.86, 0.87, 0.90, 1.0)
const _CHIP_BORDER_ACTIVE := Color(0.70, 0.71, 0.75, 1.0)
const _COLOR_TEXT_DARK := Color(0.12, 0.12, 0.15, 1.0)
const _COLOR_TEXT_MUTED := Color(0.44, 0.44, 0.47, 1.0)

var _current_align: String = "left"
var _current_valign: String = "top"
var _current_prop_mode: String = ""
var _sliders: Dictionary = {}      # prop -> Slider
var _prop_sliders: Dictionary = {}  # "start"|"mid"|"end" -> Slider
var _dragging: bool = false
var _sync_guard: bool = false
var _current_family: String = ""   # última familia CONFIRMADA (para restaurar tras un hover)

func _ready() -> void:
	if not is_inside_tree():
		return
	for rel in _SLIDER_PROPS:
		var s := get_node_or_null(rel) as Slider
		if s == null:
			continue   # instancia de este script fuera del panel: salida limpia
		var prop: String = _SLIDER_PROPS[rel]
		var rng: Array = _SLIDER_RANGE[prop]
		s.min_value = rng[0]
		s.max_value = rng[1]
		s.step = rng[2]
		_sliders[prop] = s
		if not s.value_changed.is_connected(_on_value_changed):
			s.value_changed.connect(_on_value_changed.bind(prop))
		if not s.drag_started.is_connected(_on_drag_started):
			s.drag_started.connect(_on_drag_started)
		if not s.drag_ended.is_connected(_on_drag_ended):
			s.drag_ended.connect(_on_drag_ended.bind(prop))

	_setup_font_browser()
	_setup_align_case_style()
	_setup_letter_proportions()

	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_sincronizar):
		ic.changed.connect(_sincronizar)

# ── alineación / caja / estilo ──────────────────────────────────────────────
func _style_chip(b: Button, active: bool) -> void:
	if b == null: return
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	if active:
		sb.bg_color = _CHIP_ACTIVE
		sb.border_color = _CHIP_BORDER_ACTIVE
		b.add_theme_color_override("font_color", _COLOR_TEXT_DARK)
		b.add_theme_color_override("icon_normal_color", _COLOR_TEXT_DARK)
		b.add_theme_color_override("icon_hover_color", _COLOR_TEXT_DARK)
		b.add_theme_color_override("icon_pressed_color", _COLOR_TEXT_DARK)
	else:
		sb.bg_color = _CHIP_NORMAL
		sb.border_color = _CHIP_BORDER
		b.add_theme_color_override("font_color", _COLOR_TEXT_MUTED)
		b.add_theme_color_override("icon_normal_color", _COLOR_TEXT_MUTED)
		b.add_theme_color_override("icon_hover_color", _COLOR_TEXT_DARK)
		b.add_theme_color_override("icon_pressed_color", _COLOR_TEXT_DARK)
	b.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate() as StyleBoxFlat
	if not active:
		sb_h.bg_color = _CHIP_HOVER
	b.add_theme_stylebox_override("hover", sb_h)
	var sb_p := sb.duplicate() as StyleBoxFlat
	b.add_theme_stylebox_override("pressed", sb_p)

func _actualizar_align_ui() -> void:
	for rel in _ALIGN_BTNS:
		var b := get_node_or_null(rel) as Button
		if b:
			_style_chip(b, _ALIGN_BTNS[rel] == _current_align)

func _actualizar_valign_ui() -> void:
	for rel in _VALIGN_BTNS:
		var b := get_node_or_null(rel) as Button
		if b:
			_style_chip(b, _VALIGN_BTNS[rel] == _current_valign)

func _setup_align_case_style() -> void:
	for rel in _ALIGN_BTNS:
		var b := get_node_or_null(rel) as Button
		if b and not b.pressed.is_connected(_on_align_pressed):
			b.pressed.connect(_on_align_pressed.bind(_ALIGN_BTNS[rel]))
	for rel in _VALIGN_BTNS:
		var b := get_node_or_null(rel) as Button
		if b and not b.pressed.is_connected(_on_valign_pressed):
			b.pressed.connect(_on_valign_pressed.bind(_VALIGN_BTNS[rel]))
	for rel in _CASE_BTNS:
		var b := get_node_or_null(rel) as Button
		if b:
			_style_chip(b, false)
			if not b.pressed.is_connected(_on_case_pressed):
				b.pressed.connect(_on_case_pressed.bind(_CASE_BTNS[rel]))
	_actualizar_align_ui()
	_actualizar_valign_ui()
	var opt := get_node_or_null(_STYLE_OPTION) as OptionButton
	if opt:
		if opt.item_count == 0:
			for st in ["Regular", "Medium", "SemiBold", "Bold", "Italic", "Bold Italic"]:
				opt.add_item(st)
		if not opt.item_selected.is_connected(_on_style_selected):
			opt.item_selected.connect(_on_style_selected)

func _on_align_pressed(mode: String) -> void:
	_current_align = mode
	_actualizar_align_ui()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic: ic.apply("text_align", mode)

func _on_valign_pressed(mode: String) -> void:
	_current_valign = mode
	_actualizar_valign_ui()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic: ic.apply("text_valign", mode)

func _on_case_pressed(mode: String) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null: return
	# aplica la transformación de caja a cada figura de texto seleccionada
	for shape in ic.selection():
		var cur = ic._read(shape, "text")
		if cur == null: continue
		var t: String = String(cur)
		match mode:
			"upper": t = t.to_upper()
			"lower": t = t.to_lower()
			"title": t = t.capitalize()
			"toggle":
				var out := ""
				for ch in t:
					out += ch.to_lower() if ch == ch.to_upper() else ch.to_upper()
				t = out
		ic.apply("text", t)   # nota: un undo por figura

func _on_style_selected(idx: int) -> void:
	var opt := get_node_or_null(_STYLE_OPTION) as OptionButton
	var fc := get_node_or_null("/root/FontCore")
	var ic := get_node_or_null("/root/InspectorCore")
	if opt == null or fc == null or ic == null: return
	var parts: Dictionary = fc.style_to_spec_parts(opt.get_item_text(idx))
	ic.apply("font_weight", int(parts.get("weight", 400)))
	ic.apply("font_italic", bool(parts.get("italic", false)))

# ── sliders ──────────────────────────────────────────────────────────────────
func _on_drag_started() -> void:
	_dragging = true

func _on_drag_ended(_value_changed: bool, prop: String) -> void:
	_dragging = false
	_aplicar(prop)

## Cambios discretos se aplican al instante con Undo; durante un arrastre
## actualizamos en vivo a 60 FPS (_aplicar_live) y creamos la acción atómica en drag_ended.
func _on_value_changed(v: float, prop: String) -> void:
	if _sync_guard:
		return
	if _dragging:
		_aplicar_live(prop, v)
	else:
		_aplicar(prop)

func _aplicar_live(prop: String, val: float) -> void:
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null: return
	for shape in ic.selection():
		shape.set_meta(prop, val)
		var dl = shape.get_node_or_null("DisplayLabel")
		if dl:
			match prop:
				"font_size":
					dl.base_font_size = int(round(val))
					dl.add_theme_font_size_override("font_size", int(round(val)))
					if dl.has_method("apply_font_from_meta"):
						dl.apply_font_from_meta()
				"letter_spacing":
					dl.set_meta("letter_spacing", int(round(val)))
					if dl.has_method("apply_font_from_meta"):
						dl.apply_font_from_meta()
				"line_spacing":
					dl.set_meta("line_spacing", int(round(val)))
					if dl.has_method("apply_font_from_meta"):
						dl.apply_font_from_meta()

func _aplicar(prop: String) -> void:
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	var s: Slider = _sliders.get(prop)
	if ic and s:
		ic.apply(prop, s.value)

# ── navegador de fuentes ─────────────────────────────────────────────────────
func _setup_font_browser() -> void:
	var list := get_node_or_null(_FONT_LIST)
	if list == null:
		return   # instancia fuera del panel
	# La segunda columna de placeholders no se usa: una sola lista.
	var col2 := get_node_or_null(_FONT_LIST_2)
	if col2 is CanvasItem:
		col2.visible = false

	var search := get_node_or_null(_FONT_SEARCH) as LineEdit
	if search and not search.text_changed.is_connected(_on_font_search):
		search.text_changed.connect(_on_font_search)
	var sbtn := get_node_or_null(_FONT_SEARCH_BTN) as Button
	if sbtn and not sbtn.pressed.is_connected(_on_font_search_btn):
		sbtn.pressed.connect(_on_font_search_btn)

	_poblar_lista_fuentes("")

func _on_font_search(query: String) -> void:
	_poblar_lista_fuentes(query)

func _on_font_search_btn() -> void:
	var search := get_node_or_null(_FONT_SEARCH) as LineEdit
	_poblar_lista_fuentes(search.text if search else "")

func _poblar_lista_fuentes(query: String) -> void:
	var list := get_node_or_null(_FONT_LIST)
	var fc := get_node_or_null("/root/FontCore")
	if list == null or fc == null:
		return
	for c in list.get_children():
		c.queue_free()
	var familias: PackedStringArray = fc.search(query)
	var n := mini(familias.size(), _MAX_ROWS)
	for i in n:
		var fam := familias[i]
		var b := Button.new()
		b.text = fam
		b.tooltip_text = fam
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_color_override("font_color", _COLOR_TEXT_DARK)
		b.add_theme_color_override("font_hover_color", Color(0.0, 0.0, 0.0, 1.0))
		b.add_theme_color_override("font_pressed_color", Color(0.0, 0.0, 0.0, 1.0))
		b.add_theme_font_size_override("font_size", 12)
		# Cada fila se ve en SU propia fuente (todos los detalles).
		var f: Font = fc.get_font(fc.make_spec(fam))
		if f:
			b.add_theme_font_override("font", f)
		b.pressed.connect(_elegir_fuente.bind(fam))
		if not b.mouse_entered.is_connected(_on_font_row_hover):
			b.mouse_entered.connect(_on_font_row_hover.bind(fam))
		if not b.mouse_exited.is_connected(_on_font_row_unhover):
			b.mouse_exited.connect(_on_font_row_unhover)
		list.add_child(b)

func _elegir_fuente(family: String) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply("font_family", family)
	_reflejar_familia(family)
	var popup := get_node_or_null(_FONT_POPUP)
	if popup is CanvasItem:
		popup.visible = false

## Editor profesional: pasar el ratón por encima de una fila de la lista
## previsualiza esa fuente en la muestra "abcdef" al lado, SIN aplicarla todavía
## (solo al hacer clic). Al salir, la muestra vuelve a la familia confirmada.
func _on_font_row_hover(family: String) -> void:
	_set_preview_font(family)

func _on_font_row_unhover() -> void:
	_set_preview_font(_current_family if not _current_family.is_empty() else "")

## Actualiza el botón de familia y la previsualización (selección confirmada).
func _reflejar_familia(family: String) -> void:
	_current_family = family
	var btn := get_node_or_null(_FONT_BTN) as Button
	if btn:
		btn.text = family
	_set_preview_font(family)

## Aplica una fuente a la etiqueta de muestra "abcdef" del navegador, sin tocar
## el botón de familia ni la selección real — usado tanto por la confirmación
## (clic) como por la previsualización en vivo (hover de la lista).
func _set_preview_font(family: String) -> void:
	var fc := get_node_or_null("/root/FontCore")
	var prev := get_node_or_null(_FONT_PREVIEW)
	if fc == null or prev == null or family.is_empty():
		return
	var f: Font = fc.get_font(fc.make_spec(family))
	if f:
		prev.add_theme_font_override("normal_font", f)
	if String(prev.get("text")).strip_edges() == "":
		prev.set("text", fc.sample_text())

# ── proporciones de tamaño de letras ─────────────────────────────────────────
func _setup_letter_proportions() -> void:
	for rel in _PROP_BTNS:
		var b := get_node_or_null(rel) as Button
		if b:
			_style_chip(b, false)
			if not b.pressed.is_connected(_on_prop_button_pressed):
				b.pressed.connect(_on_prop_button_pressed.bind(_PROP_BTNS[rel]))
	for key in _PROP_SLIDERS:
		var s := get_node_or_null(_PROP_SLIDERS[key]) as Slider
		if s:
			s.min_value = 0.2
			s.max_value = 2.0
			s.step = 0.05
			s.value = 1.0
			_prop_sliders[key] = s
			if not s.value_changed.is_connected(_on_prop_slider_changed):
				s.value_changed.connect(_on_prop_slider_changed.bind(key))
			if not s.drag_started.is_connected(_on_drag_started):
				s.drag_started.connect(_on_drag_started)
			if not s.drag_ended.is_connected(_on_prop_slider_drag_ended):
				s.drag_ended.connect(_on_prop_slider_drag_ended.bind(key))
	_actualizar_prop_ui()

func _actualizar_prop_ui() -> void:
	for rel in _PROP_BTNS:
		var b := get_node_or_null(rel) as Button
		if b:
			_style_chip(b, _PROP_BTNS[rel] == _current_prop_mode)

func _on_prop_button_pressed(mode: String) -> void:
	if _current_prop_mode == mode:
		_current_prop_mode = ""
		_sync_guard = true
		for key in _prop_sliders:
			(_prop_sliders[key] as Slider).value = 1.0
		_sync_guard = false
		_actualizar_prop_ui()
		var ic := get_node_or_null("/root/InspectorCore")
		if ic: ic.apply("letter_proportions", {})
		return

	_current_prop_mode = mode
	var preset: Dictionary = _PROP_PRESETS.get(mode, {"start": 1.0, "mid": 1.0, "mid2": 1.0, "end": 1.0})
	_sync_guard = true
	if _prop_sliders.has("start"): (_prop_sliders["start"] as Slider).value = float(preset.get("start", 1.0))
	if _prop_sliders.has("mid"): (_prop_sliders["mid"] as Slider).value = float(preset.get("mid", 1.0))
	if _prop_sliders.has("mid2"): (_prop_sliders["mid2"] as Slider).value = float(preset.get("mid2", preset.get("mid", 1.0)))
	if _prop_sliders.has("end"): (_prop_sliders["end"] as Slider).value = float(preset.get("end", 1.0))
	_sync_guard = false
	_actualizar_prop_ui()
	_aplicar_proportions()

func _on_prop_slider_changed(_v: float, _key: String) -> void:
	if _sync_guard:
		return
	if _current_prop_mode.is_empty():
		_current_prop_mode = "Aaa"
		_actualizar_prop_ui()
	if _dragging:
		_aplicar_proportions_live()
	else:
		_aplicar_proportions()

func _on_prop_slider_drag_ended(_val_changed: bool, _key: String) -> void:
	_dragging = false
	_aplicar_proportions()

func _aplicar_proportions() -> void:
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null: return
	var s_start := float(_prop_sliders["start"].value) if _prop_sliders.has("start") else 1.0
	var s_mid := float(_prop_sliders["mid"].value) if _prop_sliders.has("mid") else 1.0
	var s_mid2 := float(_prop_sliders["mid2"].value) if _prop_sliders.has("mid2") else s_mid
	var s_end := float(_prop_sliders["end"].value) if _prop_sliders.has("end") else 1.0
	var mode := _current_prop_mode if not _current_prop_mode.is_empty() else "Aaa"
	var data := {"mode": mode, "start": s_start, "mid": s_mid, "mid2": s_mid2, "end": s_end}
	ic.apply("letter_proportions", data)

func _aplicar_proportions_live() -> void:
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null: return
	var s_start := float(_prop_sliders["start"].value) if _prop_sliders.has("start") else 1.0
	var s_mid := float(_prop_sliders["mid"].value) if _prop_sliders.has("mid") else 1.0
	var s_mid2 := float(_prop_sliders["mid2"].value) if _prop_sliders.has("mid2") else s_mid
	var s_end := float(_prop_sliders["end"].value) if _prop_sliders.has("end") else 1.0
	var mode := _current_prop_mode if not _current_prop_mode.is_empty() else "Aaa"
	var data := {"mode": mode, "start": s_start, "mid": s_mid, "mid2": s_mid2, "end": s_end}
	for shape in ic.selection():
		shape.set_meta("letter_proportions", data)
		var dl = shape.get_node_or_null("DisplayLabel")
		if dl and dl.has_method("set_letter_proportions"):
			dl.set_letter_proportions(data)

# ── sincronización con la selección ──────────────────────────────────────────
func _sincronizar(props: Dictionary) -> void:
	_sync_guard = true
	for prop in _sliders:
		if props.has(prop) and not props[prop]["mixed"]:
			(_sliders[prop] as Slider).value = float(props[prop]["value"])
	if props.has("font_family") and not props["font_family"]["mixed"]:
		_reflejar_familia(String(props["font_family"]["value"]))
	if props.has("text_align") and not props["text_align"]["mixed"]:
		_current_align = String(props["text_align"]["value"])
		_actualizar_align_ui()
	if props.has("text_valign") and not props["text_valign"]["mixed"]:
		_current_valign = String(props["text_valign"]["value"])
		_actualizar_valign_ui()
	if props.has("letter_proportions") and not props["letter_proportions"]["mixed"]:
		var lp = props["letter_proportions"]["value"]
		if lp is Dictionary and not lp.is_empty() and lp.has("mode"):
			_current_prop_mode = String(lp.get("mode", ""))
			if _prop_sliders.has("start"): (_prop_sliders["start"] as Slider).value = float(lp.get("start", 1.0))
			if _prop_sliders.has("mid"): (_prop_sliders["mid"] as Slider).value = float(lp.get("mid", 1.0))
			if _prop_sliders.has("mid2"): (_prop_sliders["mid2"] as Slider).value = float(lp.get("mid2", lp.get("mid", 1.0)))
			if _prop_sliders.has("end"): (_prop_sliders["end"] as Slider).value = float(lp.get("end", 1.0))
		else:
			_current_prop_mode = ""
		_actualizar_prop_ui()
	_sync_guard = false
