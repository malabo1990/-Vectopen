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
	"Panel/VBoxContainer/BoxContainer2/Button2": "fill",     # justificado
	"Panel/VBoxContainer/BoxContainer2/Button3": "right",
}
const _CASE_BTNS := {
	"Panel/VBoxContainer/BoxContainer4/Button": "upper",     # AA
	"Panel/VBoxContainer/BoxContainer4/Button4": "title",    # Aa
	"Panel/VBoxContainer/BoxContainer4/Button2": "lower",    # aa
	"Panel/VBoxContainer/BoxContainer4/Button3": "toggle",   # aA
}
const _STYLE_OPTION := "Panel/BoxContainer/OptionButton"

var _sliders: Dictionary = {}      # prop -> Slider
var _dragging: bool = false
var _sync_guard: bool = false

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

	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_sincronizar):
		ic.changed.connect(_sincronizar)

# ── alineación / caja / estilo ──────────────────────────────────────────────
func _setup_align_case_style() -> void:
	for rel in _ALIGN_BTNS:
		var b := get_node_or_null(rel) as Button
		if b and not b.pressed.is_connected(_on_align_pressed):
			b.pressed.connect(_on_align_pressed.bind(_ALIGN_BTNS[rel]))
	for rel in _CASE_BTNS:
		var b := get_node_or_null(rel) as Button
		if b and not b.pressed.is_connected(_on_case_pressed):
			b.pressed.connect(_on_case_pressed.bind(_CASE_BTNS[rel]))
	var opt := get_node_or_null(_STYLE_OPTION) as OptionButton
	if opt:
		if opt.item_count == 0:
			for st in ["Regular", "Medium", "SemiBold", "Bold", "Italic", "Bold Italic"]:
				opt.add_item(st)
		if not opt.item_selected.is_connected(_on_style_selected):
			opt.item_selected.connect(_on_style_selected)

func _on_align_pressed(mode: String) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic: ic.apply("text_align", mode)

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

## Cambios discretos (teclado, clic en la barra) se aplican al instante; durante
## un arrastre esperamos a drag_ended para no llenar el historial de undo.
func _on_value_changed(_v: float, prop: String) -> void:
	if _sync_guard or _dragging:
		return
	_aplicar(prop)

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
		# Cada fila se ve en SU propia fuente (todos los detalles).
		var f: Font = fc.get_font(fc.make_spec(fam))
		if f:
			b.add_theme_font_override("font", f)
		b.pressed.connect(_elegir_fuente.bind(fam))
		list.add_child(b)

func _elegir_fuente(family: String) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply("font_family", family)
	_reflejar_familia(family)
	var popup := get_node_or_null(_FONT_POPUP)
	if popup is CanvasItem:
		popup.visible = false

## Actualiza el botón de familia y la previsualización.
func _reflejar_familia(family: String) -> void:
	var btn := get_node_or_null(_FONT_BTN) as Button
	if btn:
		btn.text = family
	var fc := get_node_or_null("/root/FontCore")
	var prev := get_node_or_null(_FONT_PREVIEW)
	if fc and prev:
		var f: Font = fc.get_font(fc.make_spec(family))
		if f:
			prev.add_theme_font_override("normal_font", f)
		if String(prev.get("text")).strip_edges() == "":
			prev.set("text", fc.sample_text())

# ── sincronización con la selección ──────────────────────────────────────────
func _sincronizar(props: Dictionary) -> void:
	_sync_guard = true
	for prop in _sliders:
		if props.has(prop) and not props[prop]["mixed"]:
			(_sliders[prop] as Slider).value = float(props[prop]["value"])
	if props.has("font_family") and not props["font_family"]["mixed"]:
		_reflejar_familia(String(props["font_family"]["value"]))
	_sync_guard = false
