extends Control
const TextRuns = preload("res://script_gdscript/text/text_runs.gd")
const TextCore = preload("res://script_gdscript/text/text_core.gd")

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

func _get_theme_colors() -> Dictionary:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm:
		var S = tm.Slot
		return {
			"surface": tm.get_color(S.PANEL_SURFACE),
			"surface_raised": tm.get_color(S.SURFACE_RAISED),
			"border": tm.get_color(S.BORDER),
			"text": tm.get_color(S.PANEL_TEXT),
			"text_secondary": tm.get_color(S.TEXT_SECONDARY),
			"btn_bg": tm.get_color(S.BUTTON_BG),
			"btn_hover": tm.get_color(S.BUTTON_HOVER),
			"btn_pressed": tm.get_color(S.BUTTON_PRESSED),
			"accent": tm.get_color(S.ACCENT),
			"input_bg": tm.get_color(S.INPUT_BG),
			"input_border": tm.get_color(S.INPUT_BORDER),
			"icon_primary": tm.get_color(S.ICON_PRIMARY),
			"icon_muted": tm.get_color(S.ICON_MUTED),
			"is_dark": tm.is_dark(),
		}
	return {
		"surface": Color(0.14, 0.14, 0.16, 1.0),
		"surface_raised": Color(0.20, 0.20, 0.23, 1.0),
		"border": Color(0.24, 0.24, 0.26, 1.0),
		"text": Color(0.94, 0.94, 0.96, 1.0),
		"text_secondary": Color(0.60, 0.60, 0.64, 1.0),
		"btn_bg": Color(0.18, 0.18, 0.21, 1.0),
		"btn_hover": Color(0.24, 0.24, 0.28, 1.0),
		"btn_pressed": Color(0.28, 0.28, 0.33, 1.0),
		"accent": Color(0.24, 0.52, 0.95, 1.0),
		"input_bg": Color(0.11, 0.11, 0.13, 1.0),
		"input_border": Color(0.24, 0.24, 0.27, 1.0),
		"icon_primary": Color(0.90, 0.90, 0.92, 1.0),
		"icon_muted": Color(0.55, 0.55, 0.60, 1.0),
		"is_dark": true,
	}

var _current_align: String = "left"
var _current_valign: String = "top"
var _current_prop_mode: String = ""
var _sliders: Dictionary = {}      # prop -> Slider
var _prop_sliders: Dictionary = {}  # "start"|"mid"|"end" -> Slider
var _indent_labels: Array[Label] = []
var _dragging: bool = false
var _sync_guard: bool = false
var _current_family: String = ""   # última familia CONFIRMADA (para restaurar tras un hover)
var _btn_prop_reset: Button = null
var _font_query: String = ""
var _rows_theme_key: String = ""
var _font_list_populated: bool = false

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
		s.tooltip_text = tr({"font_size": "Tamaño de letra", "line_spacing": "Interlineado", "letter_spacing": "Espaciado entre letras"}.get(prop, prop))
		if not s.value_changed.is_connected(_on_value_changed):
			s.value_changed.connect(_on_value_changed.bind(prop))
		if not s.drag_started.is_connected(_on_drag_started):
			s.drag_started.connect(_on_drag_started)
		if not s.drag_ended.is_connected(_on_drag_ended):
			s.drag_ended.connect(_on_drag_ended.bind(prop))

	_setup_font_browser()
	_setup_align_case_style()
	_setup_letter_proportions()
	_setup_indent_row()
	_setup_font_color()

	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_sincronizar):
		ic.changed.connect(_sincronizar)

	var tm = get_node_or_null("/root/ThemeManager")
	if tm:
		if tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)
		if tm.has_signal("color_slot_changed") and not tm.color_slot_changed.is_connected(_on_color_slot_changed):
			tm.color_slot_changed.connect(_on_color_slot_changed)

	_aplicar_tema()

func _on_theme_changed(_mode: String) -> void:
	_aplicar_tema()
	_restyle_chips()

## Los chips se pintan una vez en _ready: sin esto quedaban con los colores
## del tema anterior al cambiar claro/oscuro (blancos fijos en modo oscuro).
func _restyle_chips() -> void:
	_actualizar_align_ui()
	_actualizar_valign_ui()
	_actualizar_prop_ui()
	for rel in _CASE_BTNS:
		var b := get_node_or_null(rel) as Button
		if b:
			_style_chip(b, false)
	_theme_indent_row()
	_theme_font_color()

func _on_color_slot_changed(_slot: String, _col: Color) -> void:
	_aplicar_tema()

func _aplicar_tema() -> void:
	var tc := _get_theme_colors()

	# 1. Label de título "TIPOGRAFÍA / TEXT"
	var header_lbl := get_node_or_null("Label") as Label
	if header_lbl:
		header_lbl.add_theme_color_override("font_color", tc["text_secondary"])

	# 2. Panel contenedor que rodea los controles (reemplaza el fondo blanco fijo)
	var main_panel := get_node_or_null("Panel") as Panel
	if main_panel:
		var psb := StyleBoxFlat.new()
		psb.bg_color = tc["surface_raised"]
		psb.border_color = tc["border"]
		psb.set_border_width_all(1)
		psb.set_corner_radius_all(8)
		main_panel.add_theme_stylebox_override("panel", psb)

	# 3. Letras A
	var big_a := get_node_or_null("Panel/Label") as Label
	if big_a:
		big_a.add_theme_color_override("font_color", tc["text"])
	var ghost_a1 := get_node_or_null("Panel/Control/Label2") as Label
	if ghost_a1:
		ghost_a1.add_theme_color_override("font_color", Color(tc["text_secondary"].r, tc["text_secondary"].g, tc["text_secondary"].b, 0.35))
	var ghost_a2 := get_node_or_null("Panel/Control/Label3") as Label
	if ghost_a2:
		ghost_a2.add_theme_color_override("font_color", Color(tc["text_secondary"].r, tc["text_secondary"].g, tc["text_secondary"].b, 0.35))

	# 4. Botón de familia tipográfica y selector de peso
	var btn_font := get_node_or_null(_FONT_BTN) as Button
	if btn_font:
		var b_sb := StyleBoxFlat.new()
		b_sb.bg_color = tc["btn_bg"]
		b_sb.border_color = tc["border"]
		b_sb.set_border_width_all(1)
		b_sb.set_corner_radius_all(6)
		b_sb.content_margin_left = 8
		b_sb.content_margin_right = 8
		b_sb.content_margin_top = 4
		b_sb.content_margin_bottom = 4
		btn_font.add_theme_stylebox_override("normal", b_sb)
		var b_h := b_sb.duplicate() as StyleBoxFlat
		b_h.bg_color = tc["btn_hover"]
		btn_font.add_theme_stylebox_override("hover", b_h)
		btn_font.add_theme_color_override("font_color", tc["text"])
		btn_font.add_theme_color_override("font_hover_color", tc["text"])

	var opt := get_node_or_null(_STYLE_OPTION) as OptionButton
	if opt:
		var opt_sb := StyleBoxFlat.new()
		opt_sb.bg_color = tc["btn_bg"]
		opt_sb.border_color = tc["border"]
		opt_sb.set_border_width_all(1)
		opt_sb.set_corner_radius_all(6)
		opt_sb.content_margin_left = 8
		opt_sb.content_margin_right = 8
		opt_sb.content_margin_top = 4
		opt_sb.content_margin_bottom = 4
		opt.add_theme_stylebox_override("normal", opt_sb)
		var opt_h := opt_sb.duplicate() as StyleBoxFlat
		opt_h.bg_color = tc["btn_hover"]
		opt.add_theme_stylebox_override("hover", opt_h)
		opt.add_theme_color_override("font_color", tc["text"])
		opt.add_theme_color_override("font_hover_color", tc["text"])


	# 6. Popup del navegador de fuentes
	var popup := get_node_or_null(_FONT_POPUP) as Panel
	if popup:
		var pop_sb := StyleBoxFlat.new()
		pop_sb.bg_color = tc["surface"]
		pop_sb.border_color = tc["border"]
		pop_sb.set_border_width_all(1)
		pop_sb.set_corner_radius_all(10)
		pop_sb.shadow_size = 8
		pop_sb.shadow_color = Color(0, 0, 0, 0.25 if tc["is_dark"] else 0.08)
		popup.add_theme_stylebox_override("panel", pop_sb)

	var search := get_node_or_null(_FONT_SEARCH) as LineEdit
	if search:
		var ssb := StyleBoxFlat.new()
		ssb.bg_color = tc["input_bg"]
		ssb.border_color = tc["input_border"]
		ssb.set_border_width_all(1)
		ssb.set_corner_radius_all(6)
		ssb.content_margin_left = 6
		ssb.content_margin_right = 6
		search.add_theme_stylebox_override("normal", ssb)
		search.add_theme_stylebox_override("focus", ssb)
		search.add_theme_color_override("font_color", tc["text"])

	# 7. Theme-colored sliders (the engine default is a dark bar on light themes)
	for s in _sliders.values():
		if is_instance_valid(s) and s is Slider:
			ProUIStyle.style_slider(s)
	for s in _prop_sliders.values():
		if is_instance_valid(s) and s is HSlider:
			ProUIStyle.style_slider(s)
	if is_instance_valid(_btn_prop_reset):
		ProUIStyle.style_toggle(_btn_prop_reset, false)
	# Font rows carry per-theme colors: rebuild them, but only when the theme
	# really changed (this runs on every right-click open of the panel)
	var theme_key := "%s|%s" % [tc["surface"].to_html(), tc["accent"].to_html()]
	if theme_key != _rows_theme_key and get_node_or_null(_FONT_LIST) != null:
		if popup and popup.visible:
			_poblar_lista_fuentes(_font_query)
		else:
			_font_list_populated = false

	# 8. Actualizar chips (alineación, mayúsculas/minúsculas, proporciones)
	_actualizar_align_ui()
	_actualizar_valign_ui()
	_actualizar_prop_ui()

# ── alineación / caja / estilo ──────────────────────────────────────────────
func _style_chip(b: Button, active: bool) -> void:
	if b == null: return
	var tc := _get_theme_colors()
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	if active:
		sb.bg_color = tc["btn_pressed"]
		sb.border_color = tc["accent"]
		b.add_theme_color_override("font_color", tc["accent"])
		b.add_theme_color_override("icon_normal_color", tc["accent"])
		b.add_theme_color_override("icon_hover_color", tc["accent"])
		b.add_theme_color_override("icon_pressed_color", tc["accent"])
	else:
		sb.bg_color = tc["btn_bg"]
		sb.border_color = tc["border"]
		b.add_theme_color_override("font_color", tc["text_secondary"])
		b.add_theme_color_override("icon_normal_color", tc["icon_muted"])
		b.add_theme_color_override("icon_hover_color", tc["text"])
		b.add_theme_color_override("icon_pressed_color", tc["accent"])
	b.add_theme_stylebox_override("normal", sb)
	# Colored SVGs (the vertical-align ones are blue) ignore the icon tint:
	# turn them into a white stencil so icon_*_color follows the theme.
	var tm = get_node_or_null("/root/ThemeManager")
	if b.icon and tm and tm.has_method("make_white_icon") and not b.has_meta("icon_stencil"):
		b.icon = tm.make_white_icon(b.icon, 16)
		b.set_meta("icon_stencil", true)

	var sb_h := sb.duplicate() as StyleBoxFlat
	if not active:
		sb_h.bg_color = tc["btn_hover"]
	b.add_theme_stylebox_override("hover", sb_h)

	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = tc["btn_pressed"]
	sb_p.border_color = tc["accent"]
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

## [shape, editor, start, end] del texto EN EDICIÓN con selección no vacía.
func _editing_range() -> Array:
	return TextCore.editing_range(get_tree())

## Offset plano → [línea, columna] en el TextEdit.
func _flat_to_line_col(ed: TextEdit, off: int) -> Array:
	var rest := maxi(0, off)
	for l in ed.get_line_count():
		var ln := ed.get_line(l).length() + 1
		if rest < ln or l == ed.get_line_count() - 1:
			return [l, mini(rest, ed.get_line(l).length())]
		rest -= ln
	return [0, 0]

func _case_of(t: String, mode: String) -> String:
	match mode:
		"upper": return t.to_upper()
		"lower": return t.to_lower()
		"title": return t.capitalize()
		"toggle":
			var out := ""
			for ch in t:
				out += ch.to_lower() if ch == ch.to_upper() else ch.to_upper()
			return out
	return t

func _on_case_pressed(mode: String) -> void:
	# Con palabra seleccionada en el editor: solo el rango (con undo).
	var ctx := _editing_range()
	if not ctx.is_empty():
		_apply_case_to_range(ctx[0], ctx[1], int(ctx[2]), int(ctx[3]), mode)
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null: return
	# aplica la transformación de caja a cada figura de texto seleccionada
	for shape in ic.selection():
		var cur = ic._read(shape, "text")
		if cur == null: continue
		ic.apply("text", _case_of(String(cur), mode))   # nota: un undo por figura

## Mayúsculas/minúsculas solo en [start, end): reescribe texto + reajusta
## runs en una sola acción de undo (si no, el BBCode se desincronizaba).
func _apply_case_to_range(shape: Node2D, ed: TextEdit, start: int, end: int, mode: String) -> void:
	var old_text := ed.text
	var new_sub := _case_of(old_text.substr(start, end - start), mode)
	if new_sub == old_text.substr(start, end - start):
		return
	var new_text := old_text.substr(0, start) + new_sub + old_text.substr(end)
	var old_runs: Array = (shape.get_meta("runs", []) as Array).duplicate(true)
	var do_fn := func() -> void:
		shape.set_meta("text", new_text)
		ed.text = new_text
		var a := _flat_to_line_col(ed, mini(start, new_text.length()))
		var b := _flat_to_line_col(ed, mini(end, new_text.length()))
		ed.select(a[0], a[1], b[0], b[1])
		# Runs por posición desde los ORIGINALES (ß→SS cambia la longitud).
		var er := TextRuns.edit_runs(old_runs, old_text, new_text)
		if er.is_empty():
			TextRuns.resize_runs(shape, new_text.length())
		else:
			shape.set_meta("runs", er)
		var dl := shape.get_node_or_null("DisplayLabel")
		if dl:
			dl.text = new_text
			if dl.has_method("set_rich_runs"):
				dl.set_rich_runs(shape.get_meta("runs", []))
			if dl.has_method("queue_redraw"):
				dl.queue_redraw()
	var undo_fn := func() -> void:
		shape.set_meta("text", old_text)
		shape.set_meta("runs", old_runs)
		ed.text = old_text
		var dl := shape.get_node_or_null("DisplayLabel")
		if dl:
			dl.text = old_text
			if dl.has_method("set_rich_runs"):
				dl.set_rich_runs(old_runs)
			if dl.has_method("queue_redraw"):
				dl.queue_redraw()
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Texto · caja (selección)")
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()

func _on_style_selected(idx: int) -> void:
	var opt := get_node_or_null(_STYLE_OPTION) as OptionButton
	var fc := get_node_or_null("/root/FontCore")
	var ic := get_node_or_null("/root/InspectorCore")
	if opt == null or fc == null or ic == null: return
	var parts: Dictionary = fc.style_to_spec_parts(opt.get_item_text(idx))
	ic.apply("font_weight", int(parts.get("weight", 400)))
	ic.apply("font_italic", bool(parts.get("italic", false)))
	_set_preview_font(_current_family)

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
		var vrt = shape.get_node_or_null("VectorRichText")
		if vrt:
			match prop:
				"font_size":
					vrt.set_font_size(val)
				"line_spacing":
					vrt.set_paragraph_line_spacing(val)
			vrt.queue_redraw()
		if ic.has_method("_refit_text_shape"):
			ic._refit_text_shape(shape)

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

	var popup := get_node_or_null(_FONT_POPUP) as CanvasItem
	if popup and not popup.visibility_changed.is_connected(_on_font_popup_visibility_changed):
		popup.visibility_changed.connect(_on_font_popup_visibility_changed)

func _on_font_popup_visibility_changed() -> void:
	var popup := get_node_or_null(_FONT_POPUP) as CanvasItem
	if popup and popup.visible and not _font_list_populated:
		_poblar_lista_fuentes(_font_query)

func _on_font_search(query: String) -> void:
	_poblar_lista_fuentes(query)

func _on_font_search_btn() -> void:
	var search := get_node_or_null(_FONT_SEARCH) as LineEdit
	_poblar_lista_fuentes(search.text if search else "")

func _poblar_lista_fuentes(query: String) -> void:
	_font_list_populated = true
	_font_query = query
	var list := get_node_or_null(_FONT_LIST)
	var fc := get_node_or_null("/root/FontCore")
	if list == null or fc == null:
		return
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	if list is BoxContainer:
		list.add_theme_constant_override("separation", 1)
	var tc := _get_theme_colors()
	_rows_theme_key = "%s|%s" % [tc["surface"].to_html(), tc["accent"].to_html()]
	var familias: PackedStringArray = fc.search(query)
	var n := mini(familias.size(), _MAX_ROWS)
	for i in n:
		var fam := familias[i]
		var current := fam == _current_family
		var b := Button.new()
		b.text = fam
		b.tooltip_text = fam
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 28)
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.clip_text = true
		# Rounded rows: soft hover, current family marked with a raised chip
		var row := StyleBoxFlat.new()
		row.set_corner_radius_all(5)
		row.content_margin_left = 8
		row.content_margin_right = 8
		row.bg_color = tc["surface_raised"] if current else Color(0, 0, 0, 0)
		if current:
			row.border_color = tc["accent"]
			row.border_width_left = 2
		var hov := row.duplicate() as StyleBoxFlat
		hov.bg_color = tc["btn_hover"]
		b.add_theme_stylebox_override("normal", row)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", hov)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", tc["text"])
		b.add_theme_color_override("font_hover_color", tc["text"])
		b.add_theme_color_override("font_pressed_color", tc["text"])
		b.add_theme_font_size_override("font_size", 13)
		# Cada fila se ve en SU propia fuente (todos los detalles).
		var f: Font = fc.get_font(fc.make_spec(fam))
		if f:
			b.add_theme_font_override("font", f)
		b.pressed.connect(_elegir_fuente.bind(fam))
		b.mouse_entered.connect(_on_font_row_hover.bind(fam))
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
	var changed := family != _current_family
	_current_family = family
	if changed and get_node_or_null(_FONT_LIST) != null:
		var popup := get_node_or_null(_FONT_POPUP) as CanvasItem
		if popup and popup.visible:
			_poblar_lista_fuentes(_font_query)
		else:
			_font_list_populated = false
	var btn := get_node_or_null(_FONT_BTN) as Button
	if btn:
		btn.text = family
	_set_preview_font(family)

## Muestra del navegador: familia (hover o confirmada) + estilo elegido +
## tamaño de la selección. Sin esto solo cambiaba la familia (regular 16).
func _set_preview_font(family: String) -> void:
	var fc := get_node_or_null("/root/FontCore")
	var prev := get_node_or_null(_FONT_PREVIEW)
	if fc == null or prev == null or family.is_empty():
		return
	var weight := 400
	var italic := false
	var opt := get_node_or_null(_STYLE_OPTION) as OptionButton
	if opt and opt.selected >= 0 and fc.has_method("style_to_spec_parts"):
		var parts: Dictionary = fc.style_to_spec_parts(opt.get_item_text(opt.selected))
		weight = int(parts.get("weight", 400))
		italic = bool(parts.get("italic", false))
	var spec: Dictionary = fc.make_spec(family)
	spec["weight"] = weight
	spec["italic"] = italic
	var f: Font = fc.get_font(spec)
	if f:
		for slot in ["normal_font", "bold_font", "italic_font", "bold_italics_font"]:
			prev.add_theme_font_override(slot, f)
	var fs := 20
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("current_props"):
		var props: Dictionary = ic.current_props()
		if props.has("font_size") and not bool(props["font_size"].get("mixed", false)):
			fs = clampi(int(props["font_size"].get("value", 20)), 12, 48)
	prev.add_theme_font_size_override("normal_font_size", fs)
	prev.add_theme_font_size_override("bold_font_size", fs)
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
	# Reset: back to uniform letter size
	var row := get_node_or_null("Panel/VBoxContainer/HBoxContainer") as Container
	if row and not is_instance_valid(_btn_prop_reset):
		_btn_prop_reset = ProUIStyle.action_button("", "res://icon/UI/system-restart.svg", tr("Restablecer proporciones"))
		_btn_prop_reset.name = "BtnResetProportions"
		_btn_prop_reset.custom_minimum_size = Vector2(22, 20)
		_btn_prop_reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_btn_prop_reset.pressed.connect(reset_letter_proportions)
		row.add_child(_btn_prop_reset)
		# Make room for the reset button without widening the panel
		for sl in _prop_sliders.values():
			(sl as Control).custom_minimum_size.x = 36
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

## Uniform letter size again (sliders back to 1.0, proportions cleared).
func reset_letter_proportions() -> void:
	_current_prop_mode = ""
	_sync_guard = true
	for key in _prop_sliders:
		(_prop_sliders[key] as Slider).value = 1.0
	_sync_guard = false
	_actualizar_prop_ui()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply("letter_proportions", {})

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

# ── fila de sangrías Publisher (creada por código: el .tscn no tiene nodos) ──
var _indent_spins: Dictionary = {}  # prop -> SpinBox/SpinBoxValue

func _setup_indent_row() -> void:
	var box := get_node_or_null("Panel/VBoxContainer") as VBoxContainer
	if box == null or box.has_node("RowIndents"):
		return  # fuera del panel o ya construida
	# Compacto: 3 campos en una fila de 192px (sin título largo).
	var row := HBoxContainer.new()
	row.name = "RowIndents"
	row.add_theme_constant_override("separation", 2)
	box.add_child(row)
	for spec in [
		["indent_left", "Iz", 0.0, 500.0, "Sangría izquierda"],
		["indent_right", "De", 0.0, 500.0, "Sangría derecha"],
		["indent_first", "1ª", -500.0, 500.0, "Primera línea (negativa = francesa)"],
	]:
		var prop: String = spec[0]
		var lab := Label.new()
		lab.text = String(spec[1])
		lab.add_theme_font_size_override("font_size", 11)
		_indent_labels.append(lab)
		row.add_child(lab)
		var sp: Control = preload("res://scenes/ui/spin_box.tscn").instantiate()
		sp.min_value = float(spec[2])
		sp.max_value = float(spec[3])
		sp.step = 1.0
		sp.custom_minimum_size = Vector2(40, 22)
		sp.tooltip_text = tr(String(spec[4]))
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if sp.has_method("set_compact"):
			sp.set_compact(true)
		sp.value_changed.connect(_on_indent_changed.bind(prop))
		row.add_child(sp)
		_indent_spins[prop] = sp
	_theme_indent_row()

## Colores de la fila de sangrías según tema (claro/oscuro).
func _theme_indent_row() -> void:
	var tc := _get_theme_colors()
	for l in _indent_labels:
		if is_instance_valid(l):
			l.add_theme_color_override("font_color", tc["text_secondary"])
	for prop in _indent_spins:
		var sp = _indent_spins[prop]
		if not is_instance_valid(sp):
			continue
		if sp is SpinBox:
			var sb := StyleBoxFlat.new()
			sb.bg_color = tc["input_bg"]
			sb.border_color = tc["input_border"]
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(4)
			var sp_box := sp as SpinBox
			var le := sp_box.get_line_edit()
			if le:
				le.add_theme_color_override("font_color", tc["text"])
				le.add_theme_stylebox_override("normal", sb)
				le.add_theme_stylebox_override("focus", sb)
				le.add_theme_stylebox_override("read_only", sb)
		elif sp.has_method("_aplicar_tema"):
			sp._aplicar_tema()

func _on_indent_changed(v: float, prop: String) -> void:
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply(prop, v)

## Color de fuente junto a la familia (el panel no tenía cómo teñir texto).
var _font_color_btn: ColorPickerButton = null

func _setup_font_color() -> void:
	var row := get_node_or_null("Panel/BoxContainer") as BoxContainer
	if row == null or row.has_node("FontColorPicker"):
		return
	var cp := ColorPickerButton.new()
	cp.name = "FontColorPicker"
	cp.color = Color.BLACK
	cp.custom_minimum_size = Vector2(30, 22)
	cp.tooltip_text = tr("Color del texto")
	cp.focus_mode = Control.FOCUS_NONE
	cp.color_changed.connect(_on_font_color_changed)
	row.add_child(cp)
	_font_color_btn = cp
	_theme_font_color()

func _on_font_color_changed(c: Color) -> void:
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("fill_color", c)

func _theme_font_color() -> void:
	if not is_instance_valid(_font_color_btn):
		return
	var tc := _get_theme_colors()
	_font_color_btn.add_theme_color_override("font_color", tc["text"])

# ── sincronización con la selección ──────────────────────────────────────────
func _sincronizar(props: Dictionary) -> void:
	_sync_guard = true
	for prop in _sliders:
		if props.has(prop) and not props[prop]["mixed"]:
			(_sliders[prop] as Slider).value = float(props[prop]["value"])
	for iprop in _indent_spins:
		if props.has(iprop) and not props[iprop]["mixed"]:
			var sp = _indent_spins[iprop]
			if is_instance_valid(sp):
				if sp.has_method("set_value_no_signal"):
					sp.set_value_no_signal(float(props[iprop]["value"]))
				elif sp.has_method("set_value"):
					sp.set_value(float(props[iprop]["value"]))
				elif "value" in sp:
					sp.value = float(props[iprop]["value"])
	if props.has("fill_color") and not props["fill_color"]["mixed"] and is_instance_valid(_font_color_btn):
		_sync_guard = true
		_font_color_btn.color = props["fill_color"]["value"]
		_sync_guard = false
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
