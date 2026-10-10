extends Control
const TextRuns = preload("res://script_gdscript/text/text_runs.gd")
const TextCore = preload("res://script_gdscript/text/text_core.gd")
const _NumField = preload("res://script_gdscript/ui/pro/pro_num_field.gd")
const _ColorPopover = preload("res://script_gdscript/ui/pro/text_color_popover.gd")
const TextFormat = preload("res://script_gdscript/text/text_format.gd")
const _LetterFxPopover = preload("res://script_gdscript/ui/pro/letter_fx_popover.gd")
const _LetterFx = preload("res://script_gdscript/text/letter_fx.gd")

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
	# Alineación y sangrías son de PÁRRAFO: viven solo en el panel de la
	# herramienta Texto (antes estaban repetidas en los dos paneles).
	for rel in ["Panel/VBoxContainer/BoxContainer2", "Panel/VBoxContainer/BoxContainer_Valign"]:
		var row := get_node_or_null(rel) as CanvasItem
		if row:
			row.visible = false
	_setup_font_color()
	_setup_format_row()
	_setup_metric_rows()
	_setup_prop_values()
	_setup_advanced_button()
	_fit_panel_height.call_deferred()

	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_sincronizar):
		ic.changed.connect(_sincronizar)
	if not visibility_changed.is_connected(_on_visibility_sync):
		visibility_changed.connect(_on_visibility_sync)

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
	_theme_format_row()
	for prop in _metric_fields:
		if is_instance_valid(_metric_fields[prop]):
			_metric_fields[prop].apply_theme()
	if is_instance_valid(_btn_advanced):
		_theme_advanced_button(bool(_btn_advanced.get_meta("fx_active", false)))
	_refresh_prop_values()

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
	var popup := get_node_or_null(_FONT_POPUP) as Control
	if popup:
		# Igual que el panel de Capas: PANEL_SURFACE, radio 14 (0 en Modern),
		# sin marco ni sombra.
		var gui := get_node_or_null("/root/GlobalUI")
		var modern: bool = gui != null and gui.has_method("is_modern_mode") and gui.is_modern_mode()
		var pop_sb := StyleBoxFlat.new()
		pop_sb.bg_color = ProUIStyle.col("PANEL_SURFACE")
		pop_sb.set_corner_radius_all(0 if modern else 14)
		pop_sb.set_border_width_all(0)
		popup.add_theme_stylebox_override("panel", pop_sb)

	var search := get_node_or_null(_FONT_SEARCH) as LineEdit
	if search:
		var ssb := StyleBoxFlat.new()
		ssb.bg_color = tc["input_bg"]
		ssb.border_color = tc["input_border"]
		ssb.set_border_width_all(1)
		ssb.set_corner_radius_all(6)
		ssb.set_content_margin_all(6)
		search.add_theme_stylebox_override("normal", ssb)
		var sfocus := ssb.duplicate() as StyleBoxFlat
		var tmi = get_node_or_null("/root/ThemeManager")
		sfocus.border_color = tmi.get_interactive_color() if tmi and tmi.has_method("get_interactive_color") else tc["accent"]
		search.add_theme_stylebox_override("focus", sfocus)
		search.add_theme_color_override("font_color", tc["text"])
		search.add_theme_color_override("caret_color", tc["text"])
	_theme_font_browser(tc)

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
## Arrastre: se escribe EN VIVO a través de InspectorCore (así el panel de la
## herramienta Texto y el resto lo siguen en tiempo real) y al soltar se
## registra UNA acción de undo con los valores del inicio. Antes se escribía
## el meta a mano: nadie se enteraba y, al soltar, apply() veía "sin cambio"
## y no creaba deshacer.
var _drag_before: Dictionary = {}     # prop -> {figura: valor previo}
var _drag_text_before: Dictionary = {} # foto del texto en edición (tamaño por letras)

func _on_drag_started() -> void:
	_dragging = true
	# Diccionarios NUEVOS (no .clear()): el undo ya registrado guarda una
	# referencia a la foto anterior y vaciarla le hacía restaurar "nada".
	_drag_before = {}
	_drag_text_before = {}

func _on_drag_ended(_value_changed: bool, prop: String) -> void:
	_dragging = false
	if not _drag_text_before.is_empty():
		var shp: Node2D = _drag_text_before.get("_shape")
		if is_instance_valid(shp):
			TextCore.register_text_undo(shp, _drag_text_before, "Texto · tamaño (selección)")
		_drag_text_before = {}
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if _drag_before.has(prop) and ic and ic.has_method("commit_live"):
		ic.commit_live(prop, _drag_before[prop])
		_drag_before.erase(prop)
	else:
		_aplicar(prop)

func _on_value_changed(v: float, prop: String) -> void:
	if _sync_guard:
		return
	if _dragging:
		_aplicar_live(prop, v)
	else:
		_aplicar(prop)

## Editando con letras seleccionadas, el tamaño va a ESAS letras.
func _editing_size(val: float, live: bool) -> bool:
	var st := TextCore.selection_style(get_tree())
	if st.is_empty():
		return false
	var shape: Node2D = st["shape"]
	var before := TextCore.capture_text_state(shape)
	if live and _drag_text_before.is_empty():
		_drag_text_before = before
		_drag_text_before["_shape"] = shape
	TextCore.apply_selection_size(get_tree(), val)
	if not live:
		TextCore.register_text_undo(shape, before, "Texto · tamaño (selección)")
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic._sync_selection()
		ic.changed.emit(ic.current_props())
	return true

func _aplicar_live(prop: String, val: float) -> void:
	if _sync_guard:
		return
	if prop == "font_size" and _editing_size(val, true):
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null or not ic.has_method("_write"):
		return
	if not _drag_before.has(prop):
		var before := {}
		for s in ic.selection():
			var b = ic._read(s, prop)
			if b != null:
				before[s] = b
		_drag_before[prop] = before
	for s in (_drag_before[prop] as Dictionary):
		if is_instance_valid(s):
			ic._write(s, prop, val)
	ic.post_write_live()

func _aplicar(prop: String) -> void:
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	var s: Slider = _sliders.get(prop)
	if ic and s:
		if prop == "font_size" and _editing_size(s.value, false):
			return
		ic.apply(prop, s.value)

# ── navegador de fuentes ─────────────────────────────────────────────────────
## Popup rediseñado (se construye en código sobre los nodos del .tscn, cuyas
## rutas siguen siendo las mismas): cabecera con contador y cerrar, buscador,
## filtros (Todas / Sistema / Incluidas / Recientes), filas a dos líneas
## (nombre legible en la fuente de la UI + muestra en SU fuente: las de
## símbolos ya no salen ilegibles), tarjeta de vista previa con el tema,
## teclado (↑ ↓ Intro Esc), se coloca dentro de la pantalla junto al menú y
## se cierra al hacer clic fuera.
const _FONT_W := 380
const _FONT_H := 500
const _RECENTS_PATH := "user://font_recents.cfg"
const _MAX_RECENTS := 8
const _FILTERS := ["all", "system", "google", "bundled", "recent"]
const _FILTER_LABELS := {"all": "Todas", "system": "Sistema", "google": "Google", "bundled": "Incluidas", "recent": "Recientes"}

var _font_filter := "all"
var _font_rows: Array[Button] = []
var _font_hl := -1                     # fila resaltada con el teclado
var _font_count_lbl: Label = null
var _font_preview_caption: Label = null
var _font_filter_btns: Dictionary = {}  # filtro -> Button
var _font_close_btn: Button = null
var _font_ui_built := false

func _setup_font_browser() -> void:
	var list := get_node_or_null(_FONT_LIST)
	if list == null:
		return   # instancia fuera del panel
	# La segunda columna de placeholders no se usa: una sola lista.
	var col2 := get_node_or_null(_FONT_LIST_2)
	if col2 is CanvasItem:
		col2.visible = false
	_build_font_browser_ui()

	var search := get_node_or_null(_FONT_SEARCH) as LineEdit
	if search:
		if not search.text_changed.is_connected(_on_font_search):
			search.text_changed.connect(_on_font_search)
		if not search.gui_input.is_connected(_on_font_search_key):
			search.gui_input.connect(_on_font_search_key)
		if not search.text_submitted.is_connected(_on_font_search_submit):
			search.text_submitted.connect(_on_font_search_submit)
	var sbtn := get_node_or_null(_FONT_SEARCH_BTN) as Button
	if sbtn and not sbtn.pressed.is_connected(_on_font_search_btn):
		sbtn.pressed.connect(_on_font_search_btn)

	var popup := get_node_or_null(_FONT_POPUP) as CanvasItem
	if popup and not popup.visibility_changed.is_connected(_on_font_popup_visibility_changed):
		popup.visibility_changed.connect(_on_font_popup_visibility_changed)
	var fc := get_node_or_null("/root/FontCore")
	if fc and fc.has_signal("font_installed") and not fc.font_installed.is_connected(_on_font_installed):
		fc.font_installed.connect(_on_font_installed)

## Reorganiza el contenido del popup (una sola vez).
func _build_font_browser_ui() -> void:
	if _font_ui_built:
		return
	var popup := get_node_or_null(_FONT_POPUP) as Control
	var search := get_node_or_null(_FONT_SEARCH) as LineEdit
	var list := get_node_or_null(_FONT_LIST) as Control
	if popup == null or search == null or list == null:
		return
	_font_ui_built = true
	popup.custom_minimum_size = Vector2(_FONT_W, _FONT_H)
	popup.size = Vector2(_FONT_W, _FONT_H)
	popup.z_index = 50
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := popup.get_node_or_null("MarginContainer") as MarginContainer
	if margin:
		# Mismos márgenes que el panel de Capas (16 / 14).
		for side in ["left", "right"]:
			margin.add_theme_constant_override("margin_" + side, 16)
		for side in ["top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 14)
	var root_box := search.get_parent().get_parent() as BoxContainer   # MarginContainer/BoxContainer
	if root_box:
		root_box.vertical = true
		root_box.add_theme_constant_override("separation", 10)

	# Cabecera: título + nº de familias + cerrar
	var header := HBoxContainer.new()
	header.name = "FontHeader"
	header.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.name = "Title"
	# Título como el de Capas: mayúsculas, 12 px, color secundario.
	title.text = tr("TIPOGRAFÍAS")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	header.add_child(title)
	_font_count_lbl = Label.new()
	_font_count_lbl.name = "Count"
	_font_count_lbl.add_theme_font_size_override("font_size", 11)
	_font_close_btn = Button.new()
	_font_close_btn.name = "Close"
	_font_close_btn.tooltip_text = tr("Cerrar (Esc)")
	_font_close_btn.focus_mode = Control.FOCUS_NONE
	_font_close_btn.custom_minimum_size = Vector2(28, 28)
	_font_close_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font_close_btn.pressed.connect(_close_font_popup)
	header.add_child(_font_close_btn)
	if root_box:
		root_box.add_child(header)
		root_box.move_child(header, 0)

	# Buscador: sin la etiqueta "FONT" ni el botón "SEARCH" (filtra al escribir)
	var search_row := search.get_parent() as Control
	for c in search_row.get_children():
		if c != search and c is CanvasItem:
			(c as CanvasItem).visible = false
	search.placeholder_text = tr("Buscar fuente…")
	search.clear_button_enabled = true
	search.custom_minimum_size.y = 28

	# Filtros
	var chips := HBoxContainer.new()
	chips.name = "FontFilters"
	chips.add_theme_constant_override("separation", 4)
	for f in _FILTERS:
		var b := Button.new()
		b.text = tr(_FILTER_LABELS[f])
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # pestañas iguales, como Capas / Páginas
		b.custom_minimum_size = Vector2(0, 26)
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_on_font_filter.bind(f))
		chips.add_child(b)
		_font_filter_btns[f] = b
	if root_box:
		root_box.add_child(chips)
		root_box.move_child(chips, search_row.get_index() + 1)

	# Lista arriba (ocupa el alto libre), vista previa abajo
	var grid := list.get_parent().get_parent() as GridContainer
	if grid:
		grid.columns = 1
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := list.get_parent() as ScrollContainer
	if scroll:
		scroll.custom_minimum_size = Vector2(0, 0)
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.custom_minimum_size = Vector2(0, 0)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if list is BoxContainer:
		(list as BoxContainer).vertical = true
	var prev := get_node_or_null(_FONT_PREVIEW) as RichTextLabel
	if prev:
		# La tarjeta es un PanelContainer del .tscn: el pie "Familia · Estilo"
		# va justo encima, como otra fila de la rejilla.
		var card := prev.get_parent() as Control
		card.custom_minimum_size = Vector2(0, 0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_SHRINK_END
		_font_preview_caption = Label.new()
		_font_preview_caption.name = "Caption"
		_font_preview_caption.add_theme_font_size_override("font_size", 10)
		if grid:
			grid.add_child(_font_preview_caption)
			grid.move_child(_font_preview_caption, card.get_index())
		prev.custom_minimum_size = Vector2(0, 46)
		prev.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		prev.fit_content = false
		prev.scroll_active = false
		prev.autowrap_mode = TextServer.AUTOWRAP_OFF
		prev.clip_contents = true
		prev.text = ""
	# Contador abajo a la izquierda, como "0 capas".
	if root_box and is_instance_valid(_font_count_lbl):
		root_box.add_child(_font_count_lbl)

func _on_font_popup_visibility_changed() -> void:
	var popup := get_node_or_null(_FONT_POPUP) as Control
	if popup == null:
		return
	if popup.visible:
		if not _font_list_populated:
			_poblar_lista_fuentes(_font_query)
		_place_font_popup.call_deferred()
		var search := get_node_or_null(_FONT_SEARCH) as LineEdit
		if search and search.is_inside_tree():
			search.grab_focus.call_deferred()
		_scroll_to_current.call_deferred()
	else:
		_font_hl = -1
		_font_hover_fam = ""
		_font_live_revert()   # cerrado sin elegir: el texto vuelve a su fuente
		_set_preview_font(_current_family)

## Junto al menú (a la izquierda o a la derecha, donde quepa) y siempre
## dentro de la pantalla. Antes se abría a 650 px a la izquierda del botón:
## con el menú pegado al borde izquierdo quedaba fuera de la vista.
func _place_font_popup() -> void:
	var popup := get_node_or_null(_FONT_POPUP) as Control
	if popup == null or not popup.visible:
		return
	popup.size = Vector2(_FONT_W, _FONT_H)
	var vp := popup.get_viewport_rect().size
	var anchor := _menu_anchor().get_global_rect()
	var btn := get_node_or_null(_FONT_BTN) as Control
	var x := anchor.position.x - _FONT_W - 8.0
	if x < 8.0:
		x = anchor.end.x + 8.0
	if x + _FONT_W > vp.x - 8.0:
		x = maxf(8.0, vp.x - _FONT_W - 8.0)
	var y := (btn.get_global_rect().position.y if btn else anchor.position.y) - 40.0
	y = clampf(y, 8.0, maxf(8.0, vp.y - _FONT_H - 8.0))
	popup.global_position = Vector2(x, y)

func _close_font_popup() -> void:
	var popup := get_node_or_null(_FONT_POPUP) as CanvasItem
	if popup:
		popup.visible = false

## Clic fuera del popup (y fuera del botón que lo abre) → se cierra.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var popup := get_node_or_null(_FONT_POPUP) as Control
	if popup == null or not popup.is_visible_in_tree():
		return
	var mp: Vector2 = popup.get_global_mouse_position()
	var btn := get_node_or_null(_FONT_BTN) as Control
	if popup.get_global_rect().has_point(mp) or (btn and btn.get_global_rect().has_point(mp)):
		return
	popup.visible = false

func _on_font_search(query: String) -> void:
	_poblar_lista_fuentes(query)

func _on_font_search_btn() -> void:
	var search := get_node_or_null(_FONT_SEARCH) as LineEdit
	_poblar_lista_fuentes(search.text if search else "")

func _on_font_search_submit(_t: String) -> void:
	var i := _font_hl if _font_hl >= 0 else (0 if _font_rows.size() == 1 else -1)
	if i >= 0 and i < _font_rows.size():
		_font_rows[i].pressed.emit()

func _on_font_search_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match (event as InputEventKey).keycode:
		KEY_DOWN:
			_move_font_hl(1)
		KEY_UP:
			_move_font_hl(-1)
		KEY_ESCAPE:
			_close_font_popup()
		_:
			return
	get_viewport().set_input_as_handled()

func _move_font_hl(d: int) -> void:
	if _font_rows.is_empty():
		return
	_font_hl = clampi(_font_hl + d, 0, _font_rows.size() - 1)
	for i in _font_rows.size():
		_style_font_row(_font_rows[i], _font_rows[i].get_meta("family") == _current_family, i == _font_hl)
	var row := _font_rows[_font_hl]
	_set_preview_font(String(row.get_meta("family")))
	_font_live_preview(String(row.get_meta("family")))
	var scroll := get_node_or_null(_FONT_LIST).get_parent() as ScrollContainer
	if scroll:
		scroll.ensure_control_visible(row)

func _scroll_to_current() -> void:
	# Esperar a que las filas tengan posición (si no, el scroll se queda corto).
	await get_tree().process_frame
	await get_tree().process_frame
	var list := get_node_or_null(_FONT_LIST) as Control
	if list == null:
		return
	var scroll := list.get_parent() as ScrollContainer
	for r in _font_rows:
		if is_instance_valid(r) and r.get_meta("family") == _current_family and scroll:
			# La actual queda arriba del todo (no pegada al borde inferior).
			scroll.scroll_vertical = int(r.position.y)
			return

func _on_font_filter(f: String) -> void:
	_font_filter = f
	_poblar_lista_fuentes(_font_query)

# ── recientes (por usuario, comodidad local) ──────────────────────────────────
func _font_recents() -> PackedStringArray:
	var cfg := ConfigFile.new()
	if cfg.load(_RECENTS_PATH) != OK:
		return PackedStringArray()
	return PackedStringArray(cfg.get_value("fonts", "recent", PackedStringArray()))

func _push_font_recent(family: String) -> void:
	var rec := _font_recents()
	var idx := rec.find(family)
	if idx >= 0:
		rec.remove_at(idx)
	rec.insert(0, family)
	if rec.size() > _MAX_RECENTS:
		rec.resize(_MAX_RECENTS)
	var cfg := ConfigFile.new()
	cfg.set_value("fonts", "recent", rec)
	cfg.save(_RECENTS_PATH)

# ── lista ─────────────────────────────────────────────────────────────────────
## Texto de muestra de cada fila: el de la selección (si es corto) o uno fijo.
func _font_row_sample() -> String:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("current_props"):
		var props: Dictionary = ic.current_props()
		if props.has("text") and not bool(props["text"].get("mixed", false)):
			var t := String(props["text"].get("value", "")).strip_edges().replace("\n", " ")
			if t.length() >= 2:
				return t.substr(0, 28)
	return "Aa Bb Cc 0123"

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
	_font_rows.clear()
	_font_hl = -1
	if list is BoxContainer:
		list.add_theme_constant_override("separation", 2)
	var tc := _get_theme_colors()
	_rows_theme_key = "%s|%s" % [tc["surface"].to_html(), tc["accent"].to_html()]

	var familias: PackedStringArray = fc.search(query)
	var total := familias.size()
	var recents := _font_recents()
	var q := query.strip_edges().to_lower()
	match _font_filter:
		"system":
			familias = PackedStringArray(Array(familias).filter(func(f): return not fc.is_bundled(f) and not _is_google(fc, f)))
		"google":
			familias = PackedStringArray(Array(familias).filter(func(f): return _is_google(fc, f)))
		"bundled":
			familias = PackedStringArray(Array(familias).filter(func(f): return fc.is_bundled(f)))
		"recent":
			familias = PackedStringArray(Array(recents).filter(func(f): return q.is_empty() or String(f).to_lower().contains(q)))
	_style_font_filters()
	if is_instance_valid(_font_count_lbl):
		_font_count_lbl.text = (tr("%d fuentes") % familias.size()) if familias.size() == total \
			else (tr("%d de %d fuentes") % [familias.size(), total])

	if familias.is_empty():
		var empty := Label.new()
		empty.name = "Empty"
		empty.text = tr("Sin recientes todavía") if _font_filter == "recent" and q.is_empty() else tr("Ninguna fuente coincide")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 60)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", tc["text_secondary"])
		empty.add_theme_font_size_override("font_size", 12)
		list.add_child(empty)
		return

	var sample := _font_row_sample()
	var n := mini(familias.size(), _MAX_ROWS)
	for i in n:
		var fam := familias[i]
		var b := Button.new()
		b.text = fam                      # (los tests y la búsqueda leen .text)
		b.tooltip_text = fam
		b.set_meta("family", fam)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 50)
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 11)
		# Muestra en la propia fuente, debajo del nombre.
		var lbl := Label.new()
		lbl.name = "Sample"
		lbl.text = sample
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.clip_text = true
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		lbl.offset_left = 10
		lbl.offset_right = -28
		lbl.offset_top = -30
		lbl.offset_bottom = -4
		lbl.add_theme_font_size_override("font_size", 16)
		# Google sin descargar: NO se pide la fuente (get_font la descargaría;
		# abrir la lista bajaría las 30). Se ofrece descargarla al elegirla.
		var gstate: String = fc.google_state(fam) if fc.has_method("google_state") else ""
		b.set_meta("google_state", gstate)
		if gstate == "remote" or gstate == "downloading":
			lbl.text = tr("Descargando…") if gstate == "downloading" else tr("Google Fonts · clic para descargar")
			lbl.add_theme_font_size_override("font_size", 12)
		else:
			var f: Font = fc.get_font(fc.make_spec(fam))
			if f:
				lbl.add_theme_font_override("font", f)
		b.add_child(lbl)
		_style_font_row(b, fam == _current_family, false)
		b.pressed.connect(_elegir_fuente.bind(fam))
		b.mouse_entered.connect(_on_font_row_hover.bind(fam))
		b.mouse_exited.connect(_on_font_row_unhover)
		list.add_child(b)
		_font_rows.append(b)
	if familias.size() > n:
		var more := Label.new()
		more.name = "More"
		more.text = tr("…y %d más: escribe para filtrar") % (familias.size() - n)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.add_theme_color_override("font_color", tc["text_secondary"])
		more.add_theme_font_size_override("font_size", 10)
		list.add_child(more)

## Fila: nombre arriba (fuente de la UI, legible) y muestra abajo. Mismo
## lenguaje que las filas de Capas: hover gris de radio 5 y la actual con el
## relleno de selección (ACCENT_SOFT), sin barras ni insignias.
func _style_font_row(b: Button, current: bool, highlighted: bool) -> void:
	var tc := _get_theme_colors()
	var sel := ProUIStyle.col("ACCENT_SOFT")
	var row := StyleBoxFlat.new()
	row.set_corner_radius_all(5)
	row.content_margin_left = 8
	row.content_margin_right = 8
	row.content_margin_top = 4
	row.content_margin_bottom = 26     # el nombre queda arriba; la muestra, abajo
	row.bg_color = sel if current else (tc["btn_hover"] if highlighted else Color(0, 0, 0, 0))
	var hov := row.duplicate() as StyleBoxFlat
	hov.bg_color = sel if current else tc["btn_hover"]
	b.add_theme_stylebox_override("normal", row)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var name_col: Color = tc["text"] if current else tc["text_secondary"]
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(key, name_col)
	var gstate := String(b.get_meta("google_state", ""))
	var remote := gstate == "remote" or gstate == "downloading"
	b.icon = ProUIStyle.icon("res://icon/UI/cloud-download.svg", tc["icon_muted"], 14) if remote else null
	b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var lbl := b.get_node_or_null("Sample") as Label
	if lbl:
		lbl.offset_left = 8
		lbl.offset_top = -26
		lbl.add_theme_color_override("font_color", tc["text_secondary"] if remote else tc["text"])

## Pestañas como Capas / Páginas (layers_system._style_tabs_fusion).
func _style_font_filters() -> void:
	var tc := _get_theme_colors()
	var tm = get_node_or_null("/root/ThemeManager")
	var act_border: Color = tm.get_interactive_color() if tm and tm.has_method("get_interactive_color") else tc["accent"]
	for f in _font_filter_btns:
		var b: Button = _font_filter_btns[f]
		if not is_instance_valid(b):
			continue
		var on: bool = f == _font_filter
		var sb := StyleBoxFlat.new()
		sb.bg_color = tc["surface_raised"] if on else tc["btn_bg"]
		sb.set_corner_radius_all(5)
		sb.set_border_width_all(1)
		sb.border_color = act_border if on else tc["border"]
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var fcol: Color = tc["text"] if on else tc["text_secondary"]
		for key in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(key, fcol)

## Colores de cabecera / vista previa / cerrar según el tema (mismos tokens
## y medidas que el panel de Capas).
func _theme_font_browser(tc: Dictionary) -> void:
	var popup := get_node_or_null(_FONT_POPUP) as Control
	if popup == null:
		return
	var title := popup.find_child("Title", true, false) as Label
	if title:
		title.add_theme_color_override("font_color", tc["text_secondary"])
	if is_instance_valid(_font_count_lbl):
		_font_count_lbl.add_theme_color_override("font_color", tc["text_secondary"])
	if is_instance_valid(_font_close_btn):
		# Chip de icono como los de la barra de Capas (28 px, radio 7, sin borde).
		_font_close_btn.icon = ProUIStyle.icon("res://icon/UI/x.svg", tc["icon_primary"], 14)
		for st in ["normal", "hover", "pressed"]:
			var cb := StyleBoxFlat.new()
			cb.bg_color = {"normal": tc["input_bg"], "hover": tc["btn_hover"], "pressed": tc["btn_pressed"]}[st]
			cb.set_corner_radius_all(7)
			cb.content_margin_left = 5
			cb.content_margin_right = 5
			cb.content_margin_top = 4
			cb.content_margin_bottom = 4
			_font_close_btn.add_theme_stylebox_override(st, cb)
		_font_close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var search := get_node_or_null(_FONT_SEARCH) as LineEdit
	if search:
		search.right_icon = null
		search.add_theme_color_override("font_placeholder_color", ProUIStyle.col("TEXT_DISABLED"))
		search.add_theme_font_size_override("font_size", 12)
	var prev := get_node_or_null(_FONT_PREVIEW) as RichTextLabel
	if prev:
		# Tarjeta = un campo de entrada (INPUT_BG, radio 6, borde suave).
		var psb := StyleBoxFlat.new()
		psb.bg_color = tc["input_bg"]
		psb.border_color = tc["input_border"]
		psb.set_border_width_all(1)
		psb.set_corner_radius_all(6)
		psb.content_margin_left = 10
		psb.content_margin_right = 10
		psb.content_margin_top = 6
		psb.content_margin_bottom = 6
		var card := prev.get_parent() as Control
		if card is PanelContainer:
			card.add_theme_stylebox_override("panel", psb)
		prev.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		prev.add_theme_color_override("default_color", tc["text"])
	var scroll := get_node_or_null(_FONT_LIST).get_parent() as ScrollContainer if get_node_or_null(_FONT_LIST) else null
	if scroll:
		var bar := scroll.get_v_scroll_bar()
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color(tc["text_secondary"], 0.45)
		grab.set_corner_radius_all(3)
		grab.content_margin_left = 3
		grab.content_margin_right = 3
		grab.content_margin_top = 14     # largo mínimo: con 150+ fuentes era un punto
		grab.content_margin_bottom = 14
		var grab_h := grab.duplicate() as StyleBoxFlat
		grab_h.bg_color = Color(tc["text_secondary"], 0.7)
		bar.add_theme_stylebox_override("grabber", grab)
		bar.add_theme_stylebox_override("grabber_highlight", grab_h)
		bar.add_theme_stylebox_override("grabber_pressed", grab_h)
		bar.add_theme_stylebox_override("scroll", StyleBoxEmpty.new())
		bar.custom_minimum_size.x = 6
	if is_instance_valid(_font_preview_caption):
		_font_preview_caption.add_theme_color_override("font_color", tc["text_secondary"])
		_font_preview_caption.add_theme_font_size_override("font_size", 11)
	_style_font_filters()

func _is_google(fc: Node, family: String) -> bool:
	return fc.has_method("is_google") and fc.is_google(family)

## Terminó una descarga de Google: la lista y la muestra pasan a la fuente real.
func _on_font_installed(family: String) -> void:
	var popup := get_node_or_null(_FONT_POPUP) as CanvasItem
	if popup and popup.visible:
		_poblar_lista_fuentes(_font_query)
	else:
		_font_list_populated = false
	if family == _current_family:
		_set_preview_font(family)

func _elegir_fuente(family: String) -> void:
	var fc := get_node_or_null("/root/FontCore")
	if fc and _is_google(fc, family):
		fc.download_google(family)   # si ya está en caché no hace nada
	# Primero se deshace la vista previa: así el paso de deshacer guarda la
	# fuente ORIGINAL (no la última que se previsualizó).
	_font_live_revert()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply("font_family", family)
	_push_font_recent(family)
	_reflejar_familia(family)
	var popup := get_node_or_null(_FONT_POPUP)
	if popup is CanvasItem:
		popup.visible = false

## Editor profesional: pasar el ratón por encima de una fila de la lista
## previsualiza esa fuente en la tarjeta de abajo, SIN aplicarla todavía
## (solo al hacer clic). Al salir, la muestra vuelve a la familia confirmada.
func _on_font_row_hover(family: String) -> void:
	_font_hover_fam = family
	_set_preview_font(family)
	_font_live_preview(family)

func _on_font_row_unhover() -> void:
	_font_hover_fam = ""
	_set_preview_font(_current_family if not _current_family.is_empty() else "")
	_font_revert_if_idle()

# ── vista previa EN VIVO sobre el lienzo (como Affinity) ──────────────────────
## Pasar el ratón por una fila (o moverse con ↑ ↓) cambia la fuente de los
## textos / párrafos seleccionados SIN tocar el historial. Clic = se aplica
## de verdad (un solo paso de deshacer, desde la fuente original). Salir de
## la lista, cerrar o hacer clic fuera = vuelven a su fuente original.
var _font_live_before: Dictionary = {}   # figura -> familia original
var _font_hover_fam := ""

func _font_live_preview(family: String) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	var fc := get_node_or_null("/root/FontCore")
	if ic == null or not ic.has_method("_write"):
		return
	# Una de Google sin descargar no se previsualiza (pasar el ratón no
	# debe descargar nada): se deja la original a la vista.
	var gstate: String = fc.google_state(family) if fc and fc.has_method("google_state") else ""
	if gstate == "remote" or gstate == "downloading":
		_font_live_revert()
		return
	if _font_live_before.is_empty():
		for sh in ic.selection():
			var b = ic._read(sh, "font_family")
			if b != null:
				_font_live_before[sh] = b
	if _font_live_before.is_empty():
		return
	for sh in _font_live_before:
		if is_instance_valid(sh):
			ic._write(sh, "font_family", family)
	ic.post_write_live()

func _font_live_revert() -> void:
	if _font_live_before.is_empty():
		return
	var ic := get_node_or_null("/root/InspectorCore")
	var before := _font_live_before
	_font_live_before = {}
	if ic == null:
		return
	for sh in before:
		if is_instance_valid(sh):
			ic._write(sh, "font_family", before[sh])
	ic.post_write_live()

## Entre dos filas hay un instante sin fila bajo el ratón: se espera un par
## de frames antes de restaurar (si no, el texto parpadearía al recorrer).
func _font_revert_if_idle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _font_hover_fam.is_empty() and _font_hl < 0:
		_font_live_revert()

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
	var gstate: String = fc.google_state(family) if fc.has_method("google_state") else ""
	if gstate == "remote" or gstate == "downloading":
		# Pasar el ratón no descarga nada: se avisa en el pie de la tarjeta.
		if is_instance_valid(_font_preview_caption):
			_font_preview_caption.text = "%s · %s" % [family, tr("Descargando…") if gstate == "downloading" else tr("se descarga al elegirla")]
		return
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
	if _font_ui_built:
		fs = clampi(fs, 18, 34)   # cabe en la tarjeta de una línea
	prev.add_theme_font_size_override("normal_font_size", fs)
	prev.add_theme_font_size_override("bold_font_size", fs)
	# Tarjeta de vista previa: una línea con el texto de la selección (o una
	# muestra) y, encima, "Familia · Estilo".
	prev.set("text", _font_row_sample() if _font_ui_built else fc.sample_text())
	if is_instance_valid(_font_preview_caption):
		_font_preview_caption.text = fc.describe(spec) if fc.has_method("describe") else family

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
		_btn_prop_reset = ProUIStyle.action_button("", "res://icon/UI/txt_reset.svg", tr("Restablecer proporciones"))
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
	var ic := get_node_or_null("/root/InspectorCore")
	if _drag_before.has("letter_proportions") and ic and ic.has_method("commit_live"):
		ic.commit_live("letter_proportions", _drag_before["letter_proportions"])
		_drag_before.erase("letter_proportions")
	else:
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
	# En vivo vía InspectorCore (los demás paneles lo ven); undo al soltar.
	if not _drag_before.has("letter_proportions"):
		var before := {}
		for shape in ic.selection():
			var bv = ic._read(shape, "letter_proportions")
			if bv != null:
				before[shape] = (bv as Dictionary).duplicate() if bv is Dictionary else bv
		_drag_before["letter_proportions"] = before
	for shape in (_drag_before["letter_proportions"] as Dictionary):
		if is_instance_valid(shape):
			ic._write(shape, "letter_proportions", data)
	ic.post_write_live()

# ── fila de sangrías Publisher (creada por código: el .tscn no tiene nodos) ──
var _indent_spins: Dictionary = {}  # prop -> SpinBox/SpinBoxValue

func _setup_indent_row() -> void:
	var box := get_node_or_null("Panel/VBoxContainer") as VBoxContainer
	if box == null or box.has_node("RowIndents"):
		return  # fuera del panel o ya construida
	# Compacto: 3 campos con icono en una fila de 192px.
	var row := HBoxContainer.new()
	row.name = "RowIndents"
	row.add_theme_constant_override("separation", 3)
	box.add_child(row)
	for spec in [
		["indent_left", "txt_indent_left", 0.0, 500.0, "Sangría izquierda"],
		["indent_right", "txt_indent_right", 0.0, 500.0, "Sangría derecha"],
		["indent_first", "txt_indent_first", -500.0, 500.0, "Primera línea (negativa = francesa)"],
	]:
		var prop: String = spec[0]
		var sp: Control = _NumField.new("res://icon/UI/%s.svg" % spec[1], "", tr(String(spec[4])))
		sp.min_value = float(spec[2])
		sp.max_value = float(spec[3])
		sp.step = 1.0
		sp.custom_minimum_size = Vector2(40, 24)
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
		elif sp.has_method("apply_theme"):
			sp.apply_theme()

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
	cp.custom_minimum_size = Vector2(24, 24)
	# Familia + estilo + color caben en 192 px (antes el color se salía).
	var fb := row.get_node_or_null("Button_font") as Control
	if fb:
		fb.custom_minimum_size.x = 68
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var opt := row.get_node_or_null("OptionButton") as Control
	if opt is OptionButton:
		opt.custom_minimum_size.x = 80
		(opt as OptionButton).fit_to_longest_item = false   # "Bold Italic" ensanchaba la fila
		(opt as OptionButton).clip_text = true
	if fb is Button:
		(fb as Button).clip_text = true
		(fb as Button).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cp.tooltip_text = tr("Color del texto")
	cp.focus_mode = Control.FOCUS_NONE
	cp.color_changed.connect(_on_font_color_changed)
	row.add_child(cp)
	_ColorPopover.attach(cp, "Color del texto")   # selector de color de la app
	_font_color_btn = cp
	_theme_font_color()

# ── fila de formato de carácter: B / I / U + trazo (antes solo en el panel
#    de la herramienta; ahora el formato de letra vive aquí, sin repetirse) ──
var _fmt_btns: Dictionary = {}          # "bold"|"italic"|"underline" -> Button
var _stroke_btn: ColorPickerButton = null
var _stroke_field: Control = null
var _stroke_before: Dictionary = {}

func _setup_format_row() -> void:
	var box := get_node_or_null("Panel/VBoxContainer") as VBoxContainer
	if box == null or box.has_node("RowFormat"):
		return
	var row := HBoxContainer.new()
	row.name = "RowFormat"
	row.add_theme_constant_override("separation", 2)
	box.add_child(row)
	box.move_child(row, 0)
	for spec in [["bold", "txt_bold", "Negrita (Ctrl+B)"], ["italic", "txt_italic", "Cursiva (Ctrl+I)"], ["underline", "txt_underline", "Subrayado (Ctrl+U)"]]:
		var b := Button.new()
		b.name = "Btn_" + String(spec[0])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = tr(String(spec[2]))
		b.custom_minimum_size = Vector2(26, 24)
		b.icon = load("res://icon/UI/%s.svg" % spec[1])
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(_on_fmt_toggle.bind(String(spec[0])))
		row.add_child(b)
		_fmt_btns[String(spec[0])] = b
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(6, 0)
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	_stroke_btn = ColorPickerButton.new()
	_stroke_btn.name = "StrokeColorPicker"
	_stroke_btn.color = Color.BLACK
	_stroke_btn.custom_minimum_size = Vector2(24, 24)
	_stroke_btn.tooltip_text = tr("Color del trazo / contorno")
	_stroke_btn.focus_mode = Control.FOCUS_NONE
	_stroke_btn.color_changed.connect(func(c: Color) -> void:
		if not _sync_guard:
			TextFormat.set_prop(get_tree(), "stroke_color", c))
	var hole := Panel.new()   # trazo = anillo, como en Illustrator
	hole.name = "Hole"
	hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hole.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hole.offset_left = 6; hole.offset_top = 6; hole.offset_right = -6; hole.offset_bottom = -6
	_stroke_btn.add_child(hole)
	row.add_child(_stroke_btn)
	_ColorPopover.attach(_stroke_btn, "Color del trazo")
	_stroke_field = _NumField.new("res://icon/UI/txt_stroke_width.svg", "", tr("Grosor del trazo (0 = sin trazo)"))
	_stroke_field.min_value = 0.0
	_stroke_field.max_value = 50.0
	_stroke_field.step = 0.5
	_stroke_field.custom_minimum_size = Vector2(58, 24)
	_stroke_field.size_flags_horizontal = Control.SIZE_FILL
	_stroke_field.scrub_changed.connect(_on_stroke_scrub)
	_stroke_field.value_changed.connect(_on_stroke_width)
	row.add_child(_stroke_field)
	_theme_format_row()

# ── tamaño / interlineado / interletra: icono + número + slider ─────────────
## Antes eran tres sliders sueltos alrededor de una "A" grande, sin número
## visible. Ahora cada uno es una fila: campo con icono (editable, arrastrable,
## acepta "12*2") + slider, como el resto de controles de la app.
var _metric_fields: Dictionary = {}   # prop -> ProNumField
var _field_scrubbed: Dictionary = {}  # prop -> true mientras se arrastra el campo

const _METRICS := [
	["font_size", "txt_size", "Tamaño de letra", 4.0, 400.0, 1.0, "pt"],
	["line_spacing", "txt_leading", "Interlineado", -100.0, 400.0, 1.0, "px"],
	["letter_spacing", "txt_tracking", "Espaciado entre letras", -50.0, 200.0, 0.5, "px"],
]

func _setup_metric_rows() -> void:
	var vb := get_node_or_null("Panel/VBoxContainer") as VBoxContainer
	if vb == null or vb.has_node("RowMetrics") or _sliders.is_empty():
		return
	var box := VBoxContainer.new()
	box.name = "RowMetrics"
	box.add_theme_constant_override("separation", 4)
	vb.add_child(box)
	vb.move_child(box, 0)
	for m in _METRICS:
		var prop: String = m[0]
		var sl: Slider = _sliders.get(prop)
		if sl == null:
			continue
		var row := HBoxContainer.new()
		row.name = "Row_" + prop
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var f: Control = _NumField.new("res://icon/UI/%s.svg" % m[1], "", tr(String(m[2])))
		f.min_value = float(m[3])
		f.max_value = float(m[4])
		f.step = float(m[5])
		f.suffix = String(m[6])
		f.custom_minimum_size = Vector2(80, 24)
		f.size_flags_horizontal = Control.SIZE_FILL
		f.set_value_no_signal(sl.value)
		row.add_child(f)
		_metric_fields[prop] = f
		if sl is VSlider:
			# El interlineado era vertical (al lado de la "A"): uno horizontal.
			var hs := HSlider.new()
			hs.name = sl.name
			hs.min_value = sl.min_value
			hs.max_value = sl.max_value
			hs.step = sl.step
			hs.value = sl.value
			hs.tooltip_text = sl.tooltip_text
			hs.value_changed.connect(_on_value_changed.bind(prop))
			hs.drag_started.connect(_on_drag_started)
			hs.drag_ended.connect(_on_drag_ended.bind(prop))
			sl = hs
			_sliders[prop] = hs
		else:
			sl.get_parent().remove_child(sl)
		sl.layout_mode = 2
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.custom_minimum_size = Vector2(40, 20)
		# Lo escrito en el campo puede salir del recorrido del slider.
		sl.allow_greater = true
		sl.allow_lesser = true
		row.add_child(sl)
		sl.value_changed.connect(func(v: float) -> void: f.set_value_no_signal(v))
		f.value_changed.connect(_on_metric_field.bind(prop))
		f.scrub_changed.connect(_on_metric_scrub.bind(prop))
		f.scrub_ended.connect(func(_v: float) -> void: _on_drag_ended(true, prop))
	# Sin la "A" grande: familia arriba y las filas debajo.
	var big_a := get_node_or_null("Panel/Label") as CanvasItem
	if big_a:
		big_a.visible = false
	var font_row := get_node_or_null("Panel/BoxContainer") as Control
	for c in [font_row, vb]:
		if c:
			c.anchor_left = 0.0
			c.anchor_right = 1.0
			c.offset_left = 5.0    # filas de 188 px en un panel de 198
			c.offset_right = -5.0
	if font_row:
		font_row.offset_top = 8.0
		font_row.offset_bottom = 36.0
	vb.offset_top = 44.0

func _on_metric_field(v: float, prop: String) -> void:
	if _field_scrubbed.get(prop, false):
		_field_scrubbed.erase(prop)   # el arrastre ya se aplicó y registró
		return
	var sl: Slider = _sliders.get(prop)
	if sl:
		sl.value = v   # → _on_value_changed → aplica con undo

func _on_metric_scrub(v: float, prop: String) -> void:
	if not _field_scrubbed.get(prop, false):
		_field_scrubbed[prop] = true
		_on_drag_started()
	var sl: Slider = _sliders.get(prop)
	if sl:
		sl.value = v   # en vivo (arrastrando)

# ── proporciones: el valor de cada slider, visible ──────────────────────────
var _prop_value_labels: Dictionary = {}   # key -> Label

func _setup_prop_values() -> void:
	var vb := get_node_or_null("Panel/VBoxContainer") as VBoxContainer
	var srow := get_node_or_null("Panel/VBoxContainer/HBoxContainer") as Control
	if vb == null or srow == null or vb.has_node("RowPropValues"):
		return
	var row := HBoxContainer.new()
	row.name = "RowPropValues"
	row.add_theme_constant_override("separation", srow.get_theme_constant("separation"))
	vb.add_child(row)
	vb.move_child(row, srow.get_index() + 1)
	for key in ["start", "mid", "mid2", "end"]:
		var sl: Slider = _prop_sliders.get(key)
		if sl == null:
			continue
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = sl.custom_minimum_size.x
		l.add_theme_font_size_override("font_size", 10)
		l.tooltip_text = sl.tooltip_text
		row.add_child(l)
		_prop_value_labels[key] = l
		sl.value_changed.connect(func(_v: float) -> void: _refresh_prop_values())
	if is_instance_valid(_btn_prop_reset):
		var pad := Control.new()
		pad.custom_minimum_size.x = _btn_prop_reset.custom_minimum_size.x
		row.add_child(pad)
	_refresh_prop_values()

func _refresh_prop_values() -> void:
	var tc := _get_theme_colors()
	for key in _prop_value_labels:
		var l: Label = _prop_value_labels[key]
		var sl: Slider = _prop_sliders.get(key)
		if is_instance_valid(l) and sl:
			l.text = "%.2f×" % sl.value
			l.add_theme_color_override("font_color", tc["text"] if not is_equal_approx(sl.value, 1.0) else tc["text_secondary"])

# ── botón "Letras avanzadas": las proporciones y demás efectos por letra
#    viven en su propio panel (letter_fx_popover.gd) ──────────────────────
var _btn_advanced: Button = null

func _setup_advanced_button() -> void:
	var vb := get_node_or_null("Panel/VBoxContainer") as VBoxContainer
	if vb == null or vb.has_node("RowAdvanced"):
		return
	# Las proporciones se mudan al panel avanzado (aquí no se repiten).
	for rel in ["BoxContainer5", "HBoxContainer", "RowPropValues"]:
		var r := vb.get_node_or_null(rel) as CanvasItem
		if r:
			r.visible = false
	_btn_advanced = Button.new()
	_btn_advanced.name = "RowAdvanced"
	_btn_advanced.text = tr("Letras avanzadas")
	_btn_advanced.tooltip_text = tr("Efectos por letra: proporciones, onda / arco e interletra progresiva")
	_btn_advanced.focus_mode = Control.FOCUS_NONE
	_btn_advanced.custom_minimum_size = Vector2(0, 26)
	_btn_advanced.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_btn_advanced.pressed.connect(_on_advanced_pressed)
	vb.add_child(_btn_advanced)
	_theme_advanced_button(false)

## Contenedor visible más externo del menú (para abrir el panel a su lado).
func _menu_anchor() -> Control:
	var vp := get_viewport_rect().size
	var a: Control = self
	var n: Node = get_parent()
	while n is Control:
		var cr := (n as Control).get_global_rect()
		if cr.size.x > vp.x * 0.5 or cr.size.y > vp.y * 0.95 or not cr.grow(1.0).encloses(get_global_rect()):
			break
		a = n
		n = n.get_parent()
	return a

func _on_advanced_pressed() -> void:
	var anchor := _menu_anchor()
	anchor.set_meta("letter_fx_button", _btn_advanced)
	_LetterFxPopover.toggle_from(anchor)

func _theme_advanced_button(active: bool) -> void:
	if not is_instance_valid(_btn_advanced):
		return
	var accent := ProUIStyle.col("ACCENT")
	_btn_advanced.add_theme_stylebox_override("normal", ProUIStyle.flat(Color(accent, 0.22) if active else ProUIStyle.col("INPUT_BG"), 5, accent if active else ProUIStyle.col("INPUT_BORDER"), 8, 0))
	_btn_advanced.add_theme_stylebox_override("hover", ProUIStyle.flat(Color(accent, 0.32) if active else ProUIStyle.col("BUTTON_HOVER"), 5, accent if active else ProUIStyle.col("BORDER_STRONG"), 8, 0))
	_btn_advanced.add_theme_stylebox_override("pressed", ProUIStyle.flat(ProUIStyle.col("BUTTON_PRESSED"), 5, accent, 8, 0))
	_btn_advanced.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_btn_advanced.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		_btn_advanced.add_theme_color_override(k, ProUIStyle.col("PANEL_TEXT"))
	_btn_advanced.icon = ProUIStyle.icon("res://icon/UI/txt_fx.svg", accent if active else ProUIStyle.col("TEXT_SECONDARY"), 16)
	_btn_advanced.set_meta("fx_active", active)

## El .tscn fija 280 px de alto; sin las filas de párrafo sobraba hueco.
func _fit_panel_height() -> void:
	var panel := get_node_or_null("Panel") as Control
	var vb := get_node_or_null("Panel/VBoxContainer") as Control
	if panel == null or vb == null:
		return
	var h := vb.position.y + vb.get_combined_minimum_size().y + 10.0
	panel.custom_minimum_size.y = h
	custom_minimum_size.y = 0.0
	var root_pc := get_parent() as Control
	if root_pc:
		root_pc.reset_size()

func _on_fmt_toggle(key: String) -> void:
	var on := TextFormat.toggle(get_tree(), key)
	var b: Button = _fmt_btns.get(key)
	if b:
		b.set_pressed_no_signal(on)
		_style_chip(b, on)

## Arrastre del grosor: en vivo (letras seleccionadas o el objeto) y UN undo.
func _on_stroke_scrub(v: float) -> void:
	if _sync_guard:
		return
	if TextFormat.live(get_tree(), "stroke_width", v):
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	if _stroke_before.is_empty():
		for s in ic.selection():
			var b = ic._read(s, "stroke_width")
			if b != null:
				_stroke_before[s] = b
	for s in _stroke_before:
		if is_instance_valid(s):
			ic._write(s, "stroke_width", v)
	ic.post_write_live()

func _on_stroke_width(v: float) -> void:
	if _sync_guard:
		return
	if TextFormat.commit_live("stroke_width"):
		return
	if not _stroke_before.is_empty():
		var ic := get_node_or_null("/root/InspectorCore")
		var before := _stroke_before
		_stroke_before = {}
		if ic:
			ic.commit_live("stroke_width", before)
		return
	TextFormat.set_prop(get_tree(), "stroke_width", v)

func _theme_format_row() -> void:
	for k in _fmt_btns:
		var b: Button = _fmt_btns[k]
		if is_instance_valid(b):
			_style_chip(b, b.button_pressed)
	if is_instance_valid(_stroke_btn):
		var tc := _get_theme_colors()
		var hole := _stroke_btn.get_node_or_null("Hole") as Panel
		if hole:
			var sb := StyleBoxFlat.new()
			sb.bg_color = tc["input_bg"]
			sb.border_color = tc["input_border"]
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(2)
			hole.add_theme_stylebox_override("panel", sb)
	if is_instance_valid(_stroke_field) and _stroke_field.has_method("apply_theme"):
		_stroke_field.apply_theme()

func _on_font_color_changed(c: Color) -> void:
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		TextFormat.set_prop(get_tree(), "fill_color", c)   # letras seleccionadas o todo

func _theme_font_color() -> void:
	if not is_instance_valid(_font_color_btn):
		return
	var tc := _get_theme_colors()
	_font_color_btn.add_theme_color_override("font_color", tc["text"])

# ── sincronización con la selección ──────────────────────────────────────────
## Oculto (menú contextual cerrado) no se sincroniza en cada selección:
## con 300 figuras costaba ~1,9 ms por clic. Se pone al día al mostrarse.
var _sync_dirty := false

func _on_visibility_sync() -> void:
	if _sync_dirty and is_visible_in_tree():
		_sync_dirty = false
		var ic := get_node_or_null("/root/InspectorCore")
		if ic and ic.has_method("current_props"):
			_sincronizar(ic.current_props())

func _sincronizar(props: Dictionary) -> void:
	if is_inside_tree() and not is_visible_in_tree():
		_sync_dirty = true
		return
	_sync_guard = true
	for prop in _sliders:
		if props.has(prop) and not props[prop]["mixed"]:
			(_sliders[prop] as Slider).value = float(props[prop]["value"])
	if is_instance_valid(_btn_advanced):
		var fx_on := false
		for fk in ["letter_proportions", "letter_wave", "letter_tracking_ramp"]:
			if props.has(fk) and not props[fk]["mixed"] and props[fk]["value"] is Dictionary:
				var probe := Node.new()
				probe.set_meta(fk, props[fk]["value"])
				fx_on = fx_on or _LetterFx.has_fx(probe)
				probe.free()
		_theme_advanced_button(fx_on)
	for mprop in _metric_fields:
		var mf = _metric_fields[mprop]
		if not props.has(mprop):
			mf.set_mixed(true, "—")
		elif props[mprop]["mixed"]:
			mf.set_mixed(true)
		else:
			mf.set_value_no_signal(float(props[mprop]["value"]))
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
		# (sin tocar _sync_guard: ponerlo a false aquí dejaba los sliders de
		# proporción de abajo sin guarda → acciones de undo fantasma)
		_font_color_btn.color = props["fill_color"]["value"]
	if props.has("font_family") and not props["font_family"]["mixed"]:
		# Durante la vista previa en vivo la selección "tiene" la fuente bajo el
		# ratón: no es la elegida (si no, la lista se rehacía bajo el cursor).
		if _font_live_before.is_empty():
			_reflejar_familia(String(props["font_family"]["value"]))
	if not _fmt_btns.is_empty():
		var states := {
			"bold": props.has("font_weight") and not props["font_weight"]["mixed"] and int(props["font_weight"]["value"]) >= 700,
			"italic": props.has("font_italic") and not props["font_italic"]["mixed"] and bool(props["font_italic"]["value"]),
			"underline": not props.is_empty() and TextFormat.is_on(get_tree(), "underline"),
		}
		for k in _fmt_btns:
			var fb: Button = _fmt_btns[k]
			fb.set_pressed_no_signal(bool(states[k]))
			_style_chip(fb, bool(states[k]))
	if is_instance_valid(_stroke_btn) and props.has("stroke_color") and not props["stroke_color"]["mixed"]:
		_stroke_btn.color = props["stroke_color"]["value"]
	if is_instance_valid(_stroke_field):
		if not props.has("stroke_width"):
			_stroke_field.set_mixed(true, "—")
		elif props["stroke_width"]["mixed"]:
			_stroke_field.set_mixed(true)
		else:
			_stroke_field.set_value_no_signal(float(props["stroke_width"]["value"]))
	var opt := get_node_or_null(_STYLE_OPTION) as OptionButton
	if opt and props.has("font_weight") and not props["font_weight"]["mixed"]:
		var w := int(props["font_weight"]["value"])
		var it: bool = props.has("font_italic") and not props["font_italic"]["mixed"] and bool(props["font_italic"]["value"])
		var want := "Regular"
		if it:
			want = "Bold Italic" if w >= 600 else "Italic"
		elif w >= 700:
			want = "Bold"
		elif w >= 600:
			want = "SemiBold"
		elif w >= 500:
			want = "Medium"
		for i in opt.item_count:
			if opt.get_item_text(i) == want:
				opt.select(i)
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
