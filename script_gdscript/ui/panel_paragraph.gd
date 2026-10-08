# =============================================================================
# VECTOPEN - PANEL DE PÁRRAFO (configuración bajo los botones Texto/Párrafo)
# RUTA: res://script_gdscript/ui/panel_paragraph.gd
# Se monta por código dentro del popup `text` de tool.tscn (sin tocar el .tscn),
# mismo patrón de construcción que PanelPolygon: secciones + InspectorCore.
# =============================================================================
class_name PanelParagraph
extends VBoxContainer
const TextRuns = preload("res://script_gdscript/text/text_runs.gd")
const TextCore = preload("res://script_gdscript/text/text_core.gd")


## Relleno largo para previsualizar marcos (estilo InDesign).
const LOREM := "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.\nDuis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

const SpinBoxScene := preload("res://scenes/ui/spin_box.tscn")

var _syncing := false
var _fields: Dictionary = {}
var _cards: Array[PanelContainer] = []
var _card_titles: Array[Label] = []
var _labels: Array[Label] = []
var _buttons: Array[Button] = []
var _align_btns: Array[Button] = []
var _valign_btns: Array[Button] = []

var _btn_bold: Button = null
var _btn_italic: Button = null
var _btn_underline: Button = null
var _spin_size: Control = null
var _cp_fill: ColorPickerButton = null
var _cp_stroke: ColorPickerButton = null
var _spin_stroke: Control = null

const _ALIGNS := ["left", "center", "right", "fill"]
const _ALIGN_TXT := ["⫷ Izq", "⫸ Cen", "⫹ Der", "≣ Jus"]
const _VALIGNS := ["top", "middle", "bottom"]
const _VALIGN_TXT := ["⤓ Arr", "⇕ Cen", "⤒ Aba"]

## Busca la sección ya montada (preload-safe: no usa el class_name global,
## que el caché del editor aún no conoce para este archivo nuevo).
static func find_in(text_panel: Node) -> Node:
	if text_panel == null:
		return null
	return text_panel.find_child("ParagraphConfig", true, false)

var _popup: Control = null

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build_ui()
	# El popup vive con offsets fijos del .tscn: si cae bajo la pantalla se
	# corta. Al mostrarse se recoloca para que quepa entero.
	var p := get_parent()
	while p:
		if p is PanelContainer and p.name == "text":
			break
		p = p.get_parent()
	if p is Control:
		_popup = p
		if not _popup.visibility_changed.is_connected(_keep_on_screen):
			_popup.visibility_changed.connect(_keep_on_screen)
		var btn_close := _popup.get_node_or_null("MarginContainer/BoxContainer/Header/BtnClose") as Button
		if btn_close and not btn_close.pressed.is_connected(_on_close_popup):
			btn_close.pressed.connect(_on_close_popup)
		call_deferred("_keep_on_screen")
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_sync):
		ic.changed.connect(_sync)
	if ic and ic.has_signal("selection_size_changed") and not ic.selection_size_changed.is_connected(_on_selection_size_changed):
		ic.selection_size_changed.connect(_on_selection_size_changed)
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("data_tool_changed") and not ge.data_tool_changed.is_connected(_on_tool_changed):
		ge.data_tool_changed.connect(_on_tool_changed)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_apply_theme):
		tm.theme_changed.connect(_apply_theme)
	_apply_theme()
	_sync({})

func _on_close_popup() -> void:
	if is_instance_valid(_popup):
		_popup.visible = false

func _on_selection_size_changed(_count: int) -> void:
	_sync({})

## Estilo profesional adaptado al ThemeManager de Vectopen
func _apply_theme(_mode: String = "") -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var card_bg: Color = tm.get_color(S.SURFACE_RAISED) if tm else Color(1, 1, 1, 0.7)
	var card_bd: Color = tm.get_color(S.BORDER) if tm else Color(0.85, 0.85, 0.88, 1.0)
	var text_col: Color = tm.get_color(S.PANEL_TEXT) if tm else Color(0.12, 0.12, 0.14, 1.0)
	var title_col: Color = tm.get_color(S.TEXT_MUTED) if (tm and "TEXT_MUTED" in S) else Color(0.35, 0.35, 0.4, 1.0)
	var input_bg: Color = tm.get_color(S.INPUT_BG) if tm else Color(1, 1, 1, 1)
	var input_bd: Color = tm.get_color(S.INPUT_BORDER) if tm else Color(0.8, 0.8, 0.85, 1.0)

	for c in _cards:
		if is_instance_valid(c):
			var sb := StyleBoxFlat.new()
			sb.bg_color = card_bg
			sb.border_color = card_bd
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(8)
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			sb.content_margin_top = 8
			sb.content_margin_bottom = 8
			c.add_theme_stylebox_override("panel", sb)

	for tl in _card_titles:
		if is_instance_valid(tl):
			tl.add_theme_color_override("font_color", title_col)

	for l in _labels:
		if is_instance_valid(l):
			l.add_theme_color_override("font_color", text_col)

	for prop in _fields:
		var sp = _fields[prop]
		if is_instance_valid(sp):
			if sp is SpinBox:
				_style_spinbox(sp, input_bg, input_bd, text_col)
			elif sp.has_method("_aplicar_tema"):
				sp._aplicar_tema()

	for sp in [_spin_size, _spin_stroke]:
		if is_instance_valid(sp):
			if sp is SpinBox:
				_style_spinbox(sp, input_bg, input_bd, text_col)
			elif sp.has_method("_aplicar_tema"):
				sp._aplicar_tema()

	for b in _buttons:
		if is_instance_valid(b):
			_style_button(b, b.button_pressed)

func _style_button(btn: Button, pressed: bool = false) -> void:
	if not is_instance_valid(btn):
		return
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var accent: Color = tm.get_color(S.ACCENT) if tm else Color(0.2, 0.5, 1.0)
	var text_col: Color = tm.get_color(S.PANEL_TEXT) if tm else Color(0.15, 0.15, 0.18)
	var input_bg: Color = tm.get_color(S.INPUT_BG) if tm else Color(1, 1, 1, 1)
	var input_bd: Color = tm.get_color(S.INPUT_BORDER) if tm else Color(0.8, 0.8, 0.85)

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3

	if pressed:
		sb.bg_color = Color(accent.r, accent.g, accent.b, 0.18)
		sb.border_color = accent
		btn.add_theme_color_override("font_color", accent)
		btn.add_theme_color_override("font_pressed_color", accent)
	else:
		sb.bg_color = input_bg
		sb.border_color = input_bd
		btn.add_theme_color_override("font_color", text_col)
		btn.add_theme_color_override("font_pressed_color", text_col)

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)

func _style_spinbox(sp: SpinBox, input_bg: Color, input_bd: Color, text_col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = input_bg
	sb.border_color = input_bd
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	var le := sp.get_line_edit()
	if le:
		le.add_theme_color_override("font_color", text_col)
		le.add_theme_stylebox_override("normal", sb)
		le.add_theme_stylebox_override("focus", sb)
		le.add_theme_stylebox_override("read_only", sb)
	else:
		sp.add_theme_color_override("font_color", text_col)
		sp.add_theme_stylebox_override("normal", sb)
		sp.add_theme_stylebox_override("focus", sb)

func _on_tool_changed(_tool_name: String) -> void:
	pass

## Recoloca el popup para que nunca salga por abajo de la pantalla.
func _keep_on_screen() -> void:
	if not is_instance_valid(_popup) or not _popup.visible:
		return
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(_popup) or not _popup.visible:
		return
	var vp: Vector2 = _popup.get_viewport_rect().size
	if vp.x <= 0.0:
		return
	var r := _popup.get_global_rect()
	var over := r.end.y - vp.y
	if over > 0.0:
		_popup.position.y -= over + 8.0
		if _popup.position.y < 0.0:
			_popup.position.y = 8.0

# ── construcción ────────────────────────────────────────────────────────────

func _create_card(title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	var gsb := StyleBoxFlat.new()
	gsb.set_corner_radius_all(8)
	gsb.set_border_width_all(1)
	gsb.content_margin_left = 10
	gsb.content_margin_right = 10
	gsb.content_margin_top = 8
	gsb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", gsb)
	_cards.append(pc)
	add_child(pc)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	pc.add_child(vbox)
	
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 11)
	_card_titles.append(lbl)
	vbox.add_child(lbl)
	return vbox

func _mini_num_col(parent: Control, label_txt: String, min_v: float, max_v: float, tip: String, prop: String = "", step_v: float = 1.0, suffix_txt: String = "px", compact: bool = true) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)

	var l := Label.new()
	l.text = label_txt
	l.add_theme_font_size_override("font_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	l.tooltip_text = "Arrastrar horizontalmente para ajustar: " + tip
	_labels.append(l)
	col.add_child(l)

	var sp: SpinBoxValue = SpinBoxScene.instantiate() as SpinBoxValue
	sp.min_value = min_v
	sp.max_value = max_v
	sp.step = step_v
	sp.suffix = suffix_txt
	sp.tooltip_text = tip
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.custom_minimum_size = Vector2(0, 24)
	if sp.has_method("set_compact"):
		sp.set_compact(compact)
	if not prop.is_empty():
		sp.value_changed.connect(_on_field.bind(prop))
		_fields[prop] = sp
	col.add_child(sp)

	var drag_info := {"active": false, "start_x": 0.0, "start_val": 0.0}
	l.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				drag_info["active"] = true
				drag_info["start_x"] = ev.global_position.x
				drag_info["start_val"] = sp.value
			else:
				drag_info["active"] = false
		elif ev is InputEventMouseMotion and drag_info["active"]:
			var dx: float = ev.global_position.x - drag_info["start_x"]
			var current_step := step_v
			if Input.is_key_pressed(KEY_SHIFT):
				current_step *= 0.1
			elif Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
				current_step *= 5.0
			var delta_val := (dx * 0.4) * current_step
			sp.value = clampf(drag_info["start_val"] + delta_val, min_v, max_v)
	)

	return sp

func _build_ui() -> void:
	# 1. Tarjeta: Carácter y Tipografía
	var card_char := _create_card("Carácter y Tipografía")
	
	var row_fmt := HBoxContainer.new()
	row_fmt.add_theme_constant_override("separation", 6)
	card_char.add_child(row_fmt)
	
	_btn_bold = _mini_btn("B")
	_btn_bold.toggle_mode = true
	_btn_bold.tooltip_text = "Negrita (Ctrl+B)"
	_btn_bold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_bold.pressed.connect(func(): _fmt_toggle("bold"))
	row_fmt.add_child(_btn_bold)

	_btn_italic = _mini_btn("I")
	_btn_italic.toggle_mode = true
	_btn_italic.tooltip_text = "Cursiva (Ctrl+I)"
	_btn_italic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_italic.pressed.connect(func(): _fmt_toggle("italic"))
	row_fmt.add_child(_btn_italic)

	_btn_underline = _mini_btn("U")
	_btn_underline.toggle_mode = true
	_btn_underline.tooltip_text = "Subrayado (Ctrl+U)"
	_btn_underline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_underline.pressed.connect(func(): _fmt_toggle("underline"))
	row_fmt.add_child(_btn_underline)

	var vsep := VSeparator.new()
	row_fmt.add_child(vsep)

	_cp_fill = ColorPickerButton.new()
	_cp_fill.tooltip_text = "Color de relleno de texto"
	_cp_fill.color = Color.BLACK
	_cp_fill.custom_minimum_size = Vector2(28, 24)
	_cp_fill.focus_mode = Control.FOCUS_NONE
	_cp_fill.color_changed.connect(_fmt_color)
	row_fmt.add_child(_cp_fill)

	# Fila 2 de Carácter: Tamaño, Interlineado, Tracking en 3 columnas
	var row_metrics := HBoxContainer.new()
	row_metrics.add_theme_constant_override("separation", 6)
	card_char.add_child(row_metrics)
	
	_spin_size = _mini_num_col(row_metrics, "Tamaño", 4.0, 400.0, "Tamaño de fuente en pt/px", "", 1.0, "pt", true)
	_spin_size.value_changed.connect(_fmt_size)
	_fields["font_size"] = _spin_size
	
	_mini_num_col(row_metrics, "Interl.", -20.0, 300.0, "Interlineado", "line_spacing", 1.0, "px", true)
	_mini_num_col(row_metrics, "Track.", -10.0, 100.0, "Espaciado entre letras", "letter_spacing", 0.5, "px", true)

	# 2. Tarjeta: Trazo y Contorno
	var card_stroke := _create_card("Trazo y Contorno")
	var row_strk := HBoxContainer.new()
	row_strk.add_theme_constant_override("separation", 6)
	card_stroke.add_child(row_strk)
	
	var strk_lab := Label.new()
	strk_lab.text = "Color:"
	strk_lab.add_theme_font_size_override("font_size", 11)
	_labels.append(strk_lab)
	row_strk.add_child(strk_lab)

	_cp_stroke = ColorPickerButton.new()
	_cp_stroke.tooltip_text = "Color de trazo / contorno"
	_cp_stroke.color = Color.BLACK
	_cp_stroke.custom_minimum_size = Vector2(28, 24)
	_cp_stroke.focus_mode = Control.FOCUS_NONE
	_cp_stroke.color_changed.connect(_fmt_stroke_color)
	row_strk.add_child(_cp_stroke)

	var w_lab := Label.new()
	w_lab.text = "Grosor:"
	w_lab.add_theme_font_size_override("font_size", 11)
	_labels.append(w_lab)
	row_strk.add_child(w_lab)

	_spin_stroke = SpinBoxScene.instantiate() as SpinBoxValue
	_spin_stroke.min_value = 0.0
	_spin_stroke.max_value = 50.0
	_spin_stroke.step = 0.5
	_spin_stroke.suffix = "px"
	_spin_stroke.tooltip_text = "Grosor de trazo (0 = sin trazo)"
	_spin_stroke.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_stroke.custom_minimum_size = Vector2(0, 24)
	if _spin_stroke.has_method("set_compact"):
		_spin_stroke.set_compact(true)
	_spin_stroke.value_changed.connect(_fmt_stroke_width)
	row_strk.add_child(_spin_stroke)

	# 3. Tarjeta: Párrafo y Alineación
	var card_par := _create_card("Párrafo y Sangrías")
	
	_align_btns = _btn_row(card_par, _ALIGN_TXT, _on_align)
	_valign_btns = _btn_row(card_par, _VALIGN_TXT, _on_valign)

	var row_indents := HBoxContainer.new()
	row_indents.add_theme_constant_override("separation", 6)
	card_par.add_child(row_indents)
	
	_mini_num_col(row_indents, "Izq", 0.0, 500.0, "Sangría izquierda", "indent_left", 1.0, "px", true)
	_mini_num_col(row_indents, "Der", 0.0, 500.0, "Sangría derecha", "indent_right", 1.0, "px", true)
	_mini_num_col(row_indents, "1ª Lín", -500.0, 500.0, "Primera línea (negativa = francesa)", "indent_first", 1.0, "px", true)

	# 4. Tarjeta: Marco y Flujo de Texto
	var card_frame := _create_card("Marco y Flujo")
	
	var row_dims := HBoxContainer.new()
	row_dims.add_theme_constant_override("separation", 6)
	card_frame.add_child(row_dims)
	
	_mini_num_col(row_dims, "Ancho", 40.0, 4000.0, "Ancho del marco", "width", 1.0, "px", false)
	_mini_num_col(row_dims, "Alto", 20.0, 4000.0, "Alto del marco", "height", 1.0, "px", false)

	var row_cols := HBoxContainer.new()
	row_cols.add_theme_constant_override("separation", 6)
	card_frame.add_child(row_cols)

	_mini_num_col(row_cols, "Cols", 1.0, 16.0, "Número de columnas", "columns", 1.0, "", false)
	_mini_num_col(row_cols, "Medianil", 0.0, 200.0, "Espacio entre columnas (medianil)", "column_gap", 1.0, "px", false)

	var row_actions := HBoxContainer.new()
	row_actions.add_theme_constant_override("separation", 4)
	card_frame.add_child(row_actions)

	var b_unlink := _mini_btn("Desvincular")
	b_unlink.tooltip_text = "Romper enlace con el marco siguiente"
	b_unlink.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_unlink.pressed.connect(_on_unlink)
	row_actions.add_child(b_unlink)

	var b_reflow := _mini_btn("Reorganizar")
	b_reflow.tooltip_text = "Recalcular flujo del texto encadenado"
	b_reflow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_reflow.pressed.connect(_on_reflow)
	row_actions.add_child(b_reflow)

	var b_lorem := _mini_btn("¶ Lorem")
	b_lorem.tooltip_text = "Insertar texto falso largo en el párrafo seleccionado"
	b_lorem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_lorem.pressed.connect(_on_lorem)
	row_actions.add_child(b_lorem)

func _btn_row(parent: Control, texts: Array, cb: Callable) -> Array[Button]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var out: Array[Button] = []
	for t in texts:
		var b := _mini_btn(String(t))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(cb.bind(out.size()))
		row.add_child(b)
		out.append(b)
	return out

func _mini_btn(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	_buttons.append(b)
	return b

# ── acciones ────────────────────────────────────────────────────────────────

func _on_field(v: float, prop: String) -> void:
	if _syncing:
		return
	_ic_apply(prop, v)

func _ic_apply(prop: String, v: Variant) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply(prop, v)

func _on_align(idx: int) -> void:
	_mark(_align_btns, idx)
	_ic_apply("text_align", _ALIGNS[idx])

func _on_valign(idx: int) -> void:
	_mark(_valign_btns, idx)
	_ic_apply("text_valign", _VALIGNS[idx])

func _mark(btns: Array[Button], idx: int) -> void:
	for i in btns.size():
		btns[i].button_pressed = (i == idx)

func _thread_targets() -> Array:
	var sm := get_node_or_null("/root/SelectionManager")
	if sm and sm.has_method("get_selected"):
		return sm.get_selected()
	return []

func _on_unlink() -> void:
	for n in _thread_targets():
		ParagraphThreading.unlink_next(n)

func _on_reflow() -> void:
	var heads: Array = []
	for n in _thread_targets():
		var h := ParagraphThreading.get_chain_head(n)
		if is_instance_valid(h) and h not in heads:
			heads.append(h)
	for h in heads:
		ParagraphThreading.reflow_chain(h)

func _on_lorem() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null or not ic.has_method("selection"):
		return
	var ok := false
	for shape in ic.selection():
		if is_instance_valid(shape) and shape.has_meta("shape_type") and str(shape.get_meta("shape_type")) == "text_paragraph":
			_ic_apply("text", LOREM)
			ok = true
			break
	if not ok:
		var sm := get_node_or_null("/root/SelectionManager")
		if sm and sm.has_method("count") and sm.count() == 0:
			pass  # sin párrafo seleccionado: el botón no crea marcos

# ── motor de runs (BBCode avanzado, editor-agnóstico) ───────────────────────
## [shape, editor] del texto EN EDICIÓN (título o párrafo). Vacío si no hay.
func _editing() -> Array:
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if canvas == null or not ("current_tool" in canvas):
		return []
	var t = canvas.current_tool
	# OJO: bool(null) no existe como constructor: null-check explícito.
	var _ed_flag = t.get("is_editing") if t != null else null
	if t == null or _ed_flag == null or not bool(_ed_flag):
		return []
	var shape: Node2D = t.get("current_editing_shape")
	if not is_instance_valid(shape):
		return []
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt and vrt.has_method("is_editing") and vrt.is_editing():
		return [shape, vrt]
	var ed: TextEdit = shape.get_node_or_null("TitleEdit")
	if ed == null:
		ed = shape.get_node_or_null("MultiLineEdit")
	if ed == null or not ed.visible:
		return []
	return [shape, ed]

func _sel_range(ed: TextEdit) -> Variant:
	return TextCore.sel_range(ed)

func _runs_of(shape: Node2D, text_len: int) -> Array:
	return TextRuns.runs_of(shape, text_len)

func _apply_to_range(shape: Node2D, ed: TextEdit, start: int, end: int, mutator: Callable) -> void:
	var dl := shape.get_node_or_null("DisplayLabel")
	TextRuns.apply_range(shape, dl, ed.text.length(), start, end, mutator)
	if dl and dl.has_method("apply_stroke_meta"):
		dl.apply_stroke_meta()
	if is_instance_valid(ed) and ed.syntax_highlighter:
		ed.syntax_highlighter.clear_highlighting_cache()
	if is_instance_valid(ed):
		ed.queue_redraw()
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	var t = canvas.current_tool if canvas and ("current_tool" in canvas) else null
	if t and t.has_method("_fit_height_to_text"):
		t._fit_height_to_text(shape, ed.text)

func _apply_with_undo(shape: Node2D, ed: TextEdit, start: int, end: int, action_name: String, mutator: Callable) -> void:
	var before: Array = (shape.get_meta("runs", []) as Array).duplicate(true)
	var dl := shape.get_node_or_null("DisplayLabel")
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	var t = canvas.current_tool if canvas and ("current_tool" in canvas) else null
	var do_fn := func() -> void:
		TextRuns.apply_range(shape, dl, ed.text.length(), start, end, mutator)
		if dl and dl.has_method("apply_stroke_meta"):
			dl.apply_stroke_meta()
		if is_instance_valid(ed) and ed.syntax_highlighter:
			ed.syntax_highlighter.clear_highlighting_cache()
		if is_instance_valid(ed):
			ed.queue_redraw()
		if t and t.has_method("_fit_height_to_text"):
			t._fit_height_to_text(shape, ed.text)
	var undo_fn := func() -> void:
		shape.set_meta("runs", before)
		if dl and dl.has_method("set_rich_runs"):
			dl.set_rich_runs(before)
		if dl and dl.has_method("apply_stroke_meta"):
			dl.apply_stroke_meta()
		if is_instance_valid(ed) and ed.syntax_highlighter:
			ed.syntax_highlighter.clear_highlighting_cache()
		if is_instance_valid(ed):
			ed.queue_redraw()
		if t and t.has_method("_fit_height_to_text"):
			t._fit_height_to_text(shape, ed.text)
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action(action_name)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()

func _update_toggle_btn(key: String, v: bool) -> void:
	match key:
		"bold":
			if is_instance_valid(_btn_bold): _btn_bold.button_pressed = v
		"italic":
			if is_instance_valid(_btn_italic): _btn_italic.button_pressed = v
		"underline":
			if is_instance_valid(_btn_underline): _btn_underline.button_pressed = v

func _fmt_toggle(key: String) -> void:
	var ctx := _editing()
	if not ctx.is_empty():
		var shape: Node2D = ctx[0]
		var ed = ctx[1]
		if ed.has_method("is_editing"):
			match key:
				"bold":
					var cur: bool = _btn_bold.button_pressed if is_instance_valid(_btn_bold) else false
					ed.apply_bold_to_selection(cur)
				"italic":
					var cur: bool = _btn_italic.button_pressed if is_instance_valid(_btn_italic) else false
					ed.apply_italic_to_selection(cur)
				"underline":
					var cur: bool = _btn_underline.button_pressed if is_instance_valid(_btn_underline) else false
					ed.apply_underline_to_selection(cur)
			shape.set_meta("runs", ed.get_runs_meta())
			ed.queue_redraw()
			return
		var ed_te: TextEdit = ed as TextEdit
		var sel = _sel_range(ed_te)
		var start: int = 0
		var end: int = ed_te.text.length()
		if sel != null and int(sel["end"]) > int(sel["start"]):
			start = int(sel["start"])
			end = int(sel["end"])
		if start < end:
			var runs := _runs_of(shape, ed_te.text.length())
			var all := true
			var pos := 0
			for r in runs:
				var len_: int = int(r.get("length", 0))
				if pos < end and pos + len_ > start and not bool(r.get(key, false)):
					all = false
				pos += len_
			var v := not all
			_apply_with_undo(shape, ed_te, start, end, "Párrafo · %s (selección)" % key, func(r: Dictionary) -> Dictionary:
				r[key] = v
				return r)
			_update_toggle_btn(key, v)
			return

	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	if key == "bold":
		var cur_w := 400
		var p = ic.current_props() if ic.has_method("current_props") else {}
		if p.has("font_weight") and not bool(p["font_weight"].get("mixed", false)):
			cur_w = int(p["font_weight"].get("value", 400))
		var new_w := 400 if cur_w >= 700 else 700
		_ic_apply("font_weight", new_w)
		if is_instance_valid(_btn_bold):
			_btn_bold.button_pressed = (new_w >= 700)
	elif key == "italic":
		var cur_it := false
		var p = ic.current_props() if ic.has_method("current_props") else {}
		if p.has("font_italic") and not bool(p["font_italic"].get("mixed", false)):
			cur_it = bool(p["font_italic"].get("value", false))
		var new_it := not cur_it
		_ic_apply("font_italic", new_it)
		if is_instance_valid(_btn_italic):
			_btn_italic.button_pressed = new_it
	elif key == "underline":
		if ic.has_method("selection"):
			var shapes: Array = ic.selection()
			for s in shapes:
				if is_instance_valid(s) and s.has_meta("shape_type") and str(s.get_meta("shape_type")).begins_with("text_"):
					var dl = s.get_node_or_null("DisplayLabel")
					var tlen := 0
					if dl and "text" in dl:
						tlen = String(dl.text).length()
					elif s.has_meta("text"):
						tlen = String(s.get_meta("text")).length()
					var before := TextCore.capture_text_state(s)
					# Copia profunda: runs_of devuelve el array del meta y
					# mutarlo en sitio dejaba el undo sin estado "antes".
					var runs := _runs_of(s, tlen).duplicate(true)
					var all := true
					for r in runs:
						if not bool(r.get("underline", false)):
							all = false
							break
					var new_u := not all
					for r in runs:
						r["underline"] = new_u
					s.set_meta("runs", runs)
					if dl and dl.has_method("set_rich_runs"):
						dl.set_rich_runs(runs)
					if dl and dl.has_method("apply_stroke_meta"):
						dl.apply_stroke_meta()
					var vrt = s.get_node_or_null("VectorRichText")
					if vrt:
						vrt.apply_underline_to_selection(new_u)
						vrt.queue_redraw()
					TextCore.register_text_undo(s, before, "Párrafo · subrayado")
					if is_instance_valid(_btn_underline):
						_btn_underline.button_pressed = new_u

func _fmt_color(color: Color) -> void:
	if _syncing:
		return
	var ctx := _editing()
	if not ctx.is_empty():
		var shape: Node2D = ctx[0]
		var ed = ctx[1]
		if ed.has_method("is_editing"):
			ed.apply_color_to_selection(color)
			shape.set_meta("runs", ed.get_runs_meta())
			shape.set_meta("text_color", color)
			ed.queue_redraw()
			var dl = shape.get_node_or_null("DisplayLabel")
			if dl and dl.has_method("set_rich_runs"):
				dl.set_rich_runs(ed.get_runs_meta())
				dl.queue_redraw()
			return
		var ed_te: TextEdit = ed as TextEdit
		var sel = _sel_range(ed_te)
		if sel != null and int(sel["end"]) > int(sel["start"]):
			var start: int = int(sel["start"])
			var end: int = int(sel["end"])
			_apply_with_undo(shape, ed_te, start, end, "Párrafo · color (selección)", func(r: Dictionary) -> Dictionary:
				r["color"] = color
				return r)
			return
		else:
			_apply_with_undo(shape, ed_te, 0, ed_te.text.length(), "Párrafo · color", func(r: Dictionary) -> Dictionary:
				r["color"] = color
				return r)
			shape.set_meta("text_color", color)
			ed_te.add_theme_color_override("font_color", color)
			if ed_te.syntax_highlighter:
				ed_te.syntax_highlighter.clear_highlighting_cache()
			ed_te.queue_redraw()
			var dl = shape.get_node_or_null("DisplayLabel")
			if dl:
				dl.add_theme_color_override("font_color", color)
				if dl.has_method("queue_redraw"):
					dl.queue_redraw()
			return
	_ic_apply("fill_color", color)

func _fmt_size(v: float) -> void:
	if _syncing:
		return
	var sz := clampf(v, 4.0, 400.0)
	var ctx := _editing()
	if not ctx.is_empty():
		var shape: Node2D = ctx[0]
		var ed = ctx[1]
		if ed.has_method("is_editing"):
			ed.apply_font_size_to_selection(sz)
			shape.set_meta("runs", ed.get_runs_meta())
			shape.set_meta("font_size", int(sz))
			ed.queue_redraw()
			var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
			var t = canvas.current_tool if canvas and ("current_tool" in canvas) else null
			if t and t.has_method("_fit_height_to_text"):
				t._fit_height_to_text(shape, ed.get_text())
			return
		var ed_te: TextEdit = ed as TextEdit
		var sel = _sel_range(ed_te)
		if sel != null and int(sel["end"]) > int(sel["start"]):
			var start: int = int(sel["start"])
			var end: int = int(sel["end"])
			_apply_with_undo(shape, ed_te, start, end, "Párrafo · tamaño (selección)", func(r: Dictionary) -> Dictionary:
				r["size"] = sz
				return r)
			return
		else:
			shape.set_meta("font_size", int(sz))
			ed_te.add_theme_font_size_override("font_size", int(sz))
			var dl = shape.get_node_or_null("DisplayLabel")
			if dl:
				if "world_font_size" in dl:
					dl.world_font_size = int(sz)
				else:
					dl.add_theme_font_size_override("font_size", int(sz))
				dl.queue_redraw()
			var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
			var t = canvas.current_tool if canvas and ("current_tool" in canvas) else null
			if t and t.has_method("_fit_height_to_text"):
				t._fit_height_to_text(shape, ed_te.text)
			return
	_ic_apply("font_size", sz)

func _fmt_stroke_color(color: Color) -> void:
	if _syncing:
		return
	var ctx := _editing()
	if not ctx.is_empty():
		var shape: Node2D = ctx[0]
		var ed = ctx[1]
		if ed.has_method("is_editing"):
			var sw: float = float(ed.get_stroke_width())
			ed.apply_stroke_to_selection(color, sw)
			shape.set_meta("runs", ed.get_runs_meta())
			shape.set_meta("stroke_color", color)
			shape.set_meta("text_outline_color", color)
			ed.queue_redraw()
			return
		var ed_te: TextEdit = ed as TextEdit
		var sel = _sel_range(ed_te)
		if sel != null and int(sel["end"]) > int(sel["start"]):
			var start: int = int(sel["start"])
			var end: int = int(sel["end"])
			_apply_with_undo(shape, ed_te, start, end, "Párrafo · color de trazo (selección)", func(r: Dictionary) -> Dictionary:
				r["stroke_color"] = color
				return r)
			return
		else:
			_apply_with_undo(shape, ed_te, 0, ed_te.text.length(), "Párrafo · color de trazo", func(r: Dictionary) -> Dictionary:
				r["stroke_color"] = color
				return r)
			shape.set_meta("stroke_color", color)
			shape.set_meta("text_outline_color", color)
			var dl = shape.get_node_or_null("DisplayLabel")
			if dl and dl.has_method("apply_stroke_meta"):
				dl.apply_stroke_meta()
			return
	_ic_apply("stroke_color", color)

func _fmt_stroke_width(v: float) -> void:
	if _syncing:
		return
	var w := maxf(0.0, v)
	var ctx := _editing()
	if not ctx.is_empty():
		var shape: Node2D = ctx[0]
		var ed = ctx[1]
		if ed.has_method("is_editing"):
			var sc: Color = ed.get_stroke_color()
			ed.apply_stroke_to_selection(sc, w)
			shape.set_meta("runs", ed.get_runs_meta())
			shape.set_meta("stroke_width", w)
			shape.set_meta("text_outline", int(w))
			ed.queue_redraw()
			return
		var ed_te: TextEdit = ed as TextEdit
		var sel = _sel_range(ed_te)
		if sel != null and int(sel["end"]) > int(sel["start"]):
			var start: int = int(sel["start"])
			var end: int = int(sel["end"])
			_apply_with_undo(shape, ed_te, start, end, "Párrafo · grosor de trazo (selección)", func(r: Dictionary) -> Dictionary:
				r["stroke_width"] = w
				return r)
			return
		else:
			_apply_with_undo(shape, ed_te, 0, ed_te.text.length(), "Párrafo · grosor de trazo", func(r: Dictionary) -> Dictionary:
				r["stroke_width"] = w
				return r)
			shape.set_meta("stroke_width", w)
			shape.set_meta("text_outline", int(w))
			var dl = shape.get_node_or_null("DisplayLabel")
			if dl and dl.has_method("apply_stroke_meta"):
				dl.apply_stroke_meta()
			return
	_ic_apply("stroke_width", w)

# ── sync ────────────────────────────────────────────────────────────────────

func _sync(props: Dictionary = {}) -> void:
	_syncing = true
	if props.is_empty():
		var ic := get_node_or_null("/root/InspectorCore")
		if ic and ic.has_method("current_props"):
			props = ic.current_props()

	for prop in _fields:
		if props.has(prop) and not bool(props[prop].get("mixed", false)):
			var sp = _fields[prop]
			if is_instance_valid(sp):
				if sp.has_method("set_value_no_signal"):
					sp.set_value_no_signal(float(props[prop].get("value", 0.0)))
				elif sp.has_method("set_value"):
					sp.set_value(float(props[prop].get("value", 0.0)))
				elif "value" in sp:
					sp.value = float(props[prop].get("value", 0.0))
	if props.has("text_align") and not bool(props["text_align"].get("mixed", false)):
		_mark(_align_btns, _ALIGNS.find(String(props["text_align"].get("value", "left"))))
	if props.has("text_valign") and not bool(props["text_valign"].get("mixed", false)):
		_mark(_valign_btns, _VALIGNS.find(String(props["text_valign"].get("value", "top"))))

	if props.has("fill_color") and not bool(props["fill_color"].get("mixed", false)):
		var c = props["fill_color"].get("value")
		if c is Color and is_instance_valid(_cp_fill):
			_cp_fill.color = c
	if props.has("stroke_color") and not bool(props["stroke_color"].get("mixed", false)):
		var c = props["stroke_color"].get("value")
		if c is Color and is_instance_valid(_cp_stroke):
			_cp_stroke.color = c
	if props.has("stroke_width") and not bool(props["stroke_width"].get("mixed", false)):
		if is_instance_valid(_spin_stroke):
			if _spin_stroke.has_method("set_value_no_signal"):
				_spin_stroke.set_value_no_signal(float(props["stroke_width"].get("value", 0.0)))
			elif _spin_stroke.has_method("set_value"):
				_spin_stroke.set_value(float(props["stroke_width"].get("value", 0.0)))
			elif "value" in _spin_stroke:
				_spin_stroke.value = float(props["stroke_width"].get("value", 0.0))
	if props.has("font_size") and not bool(props["font_size"].get("mixed", false)):
		if is_instance_valid(_spin_size):
			if _spin_size.has_method("set_value_no_signal"):
				_spin_size.set_value_no_signal(float(props["font_size"].get("value", 24.0)))
			elif _spin_size.has_method("set_value"):
				_spin_size.set_value(float(props["font_size"].get("value", 24.0)))
			elif "value" in _spin_size:
				_spin_size.value = float(props["font_size"].get("value", 24.0))
	if props.has("font_weight") and not bool(props["font_weight"].get("mixed", false)):
		if is_instance_valid(_btn_bold):
			_btn_bold.button_pressed = int(props["font_weight"].get("value", 400)) >= 700
	if props.has("font_italic") and not bool(props["font_italic"].get("mixed", false)):
		if is_instance_valid(_btn_italic):
			_btn_italic.button_pressed = bool(props["font_italic"].get("value", false))

	var ctx := _editing()
	if not ctx.is_empty():
		var shape: Node2D = ctx[0]
		var ed = ctx[1]
		if ed.has_method("is_editing"):
			if is_instance_valid(_cp_fill):
				_cp_fill.color = ed.get_text_color()
			if is_instance_valid(_cp_stroke):
				_cp_stroke.color = ed.get_stroke_color()
			if is_instance_valid(_spin_stroke):
				if _spin_stroke.has_method("set_value_no_signal"):
					_spin_stroke.set_value_no_signal(float(ed.get_stroke_width()))
				elif "value" in _spin_stroke:
					_spin_stroke.value = float(ed.get_stroke_width())
			if is_instance_valid(_spin_size):
				if _spin_size.has_method("set_value_no_signal"):
					_spin_size.set_value_no_signal(float(ed.get_font_size()))
				elif "value" in _spin_size:
					_spin_size.value = float(ed.get_font_size())
		elif ed is TextEdit:
			var ed_te: TextEdit = ed as TextEdit
			var sel = _sel_range(ed_te)
			var cursor: int = 0
			if sel != null:
				cursor = int(sel["start"])
			else:
				var cl: int = ed_te.get_caret_line()
				for l in range(cl):
					cursor += ed_te.get_line(l).length() + 1
				cursor += ed_te.get_caret_column()
			var runs := _runs_of(shape, ed_te.text.length())
			var acc := 0
			var r_active: Dictionary = {}
			for r in runs:
				acc += int(r.get("length", 0))
				if cursor < acc:
					r_active = r
					break
			if r_active.is_empty() and not runs.is_empty():
				r_active = runs[runs.size() - 1]
			if not r_active.is_empty():
				if r_active.has("color") and is_instance_valid(_cp_fill):
					_cp_fill.color = r_active["color"]
				if r_active.has("stroke_color") and is_instance_valid(_cp_stroke):
					_cp_stroke.color = r_active["stroke_color"]
				if r_active.has("stroke_width") and is_instance_valid(_spin_stroke):
					if _spin_stroke.has_method("set_value_no_signal"):
						_spin_stroke.set_value_no_signal(float(r_active["stroke_width"]))
					elif _spin_stroke.has_method("set_value"):
						_spin_stroke.set_value(float(r_active["stroke_width"]))
					elif "value" in _spin_stroke:
						_spin_stroke.value = float(r_active["stroke_width"])
				if r_active.has("size") and is_instance_valid(_spin_size):
					if _spin_size.has_method("set_value_no_signal"):
						_spin_size.set_value_no_signal(float(r_active["size"]))
					elif _spin_size.has_method("set_value"):
						_spin_size.set_value(float(r_active["size"]))
					elif "value" in _spin_size:
						_spin_size.value = float(r_active["size"])
				if r_active.has("bold") and is_instance_valid(_btn_bold):
					_btn_bold.button_pressed = bool(r_active["bold"])
				if r_active.has("italic") and is_instance_valid(_btn_italic):
					_btn_italic.button_pressed = bool(r_active["italic"])
				if r_active.has("underline") and is_instance_valid(_btn_underline):
					_btn_underline.button_pressed = bool(r_active["underline"])

	if is_instance_valid(_btn_bold): _style_button(_btn_bold, _btn_bold.button_pressed)
	if is_instance_valid(_btn_italic): _style_button(_btn_italic, _btn_italic.button_pressed)
	if is_instance_valid(_btn_underline): _style_button(_btn_underline, _btn_underline.button_pressed)

	_syncing = false
