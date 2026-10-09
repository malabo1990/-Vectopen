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

const NumField := preload("res://script_gdscript/ui/pro/pro_num_field.gd")
const _ICONS := "res://icon/UI/"

var _syncing := false
var _fields: Dictionary = {}
var _sections: Array[Control] = []
var _section_titles: Array[Label] = []
var _separators: Array[ColorRect] = []
var _buttons: Array[Button] = []          # botones de icono/texto con estado
var _action_btns: Array[Button] = []      # acciones (sin estado activo)
var _swatches: Array[ColorPickerButton] = []
var _align_btns: Array[Button] = []
var _valign_btns: Array[Button] = []

var _btn_bold: Button = null
var _btn_italic: Button = null
var _btn_underline: Button = null
var _btn_family: Button = null
var _family_menu: PopupMenu = null
var _opt_style: OptionButton = null
var _spin_size: Control = null
var _cp_fill: ColorPickerButton = null
var _cp_stroke: ColorPickerButton = null
var _spin_stroke: Control = null
var _scrub_before: Dictionary = {}       # prop -> {figura: valor previo}

const _ALIGNS := ["left", "center", "right", "fill"]
const _ALIGN_ICONS := ["txt_align_left", "txt_align_center", "txt_align_right", "txt_align_justify"]
const _ALIGN_TIPS := ["Alinear a la izquierda", "Centrar", "Alinear a la derecha", "Justificar"]
const _VALIGNS := ["top", "middle", "bottom"]
const _VALIGN_ICONS := ["text_valign_top", "text_valign_middle", "text_valign_bottom"]
const _VALIGN_TIPS := ["Alinear arriba", "Centrar verticalmente", "Alinear abajo"]

## Busca la sección ya montada (preload-safe: no usa el class_name global,
## que el caché del editor aún no conoce para este archivo nuevo).
static func find_in(text_panel: Node) -> Node:
	if text_panel == null:
		return null
	return text_panel.find_child("ParagraphConfig", true, false)

var _popup: Control = null

func _ready() -> void:
	add_theme_constant_override("separation", 10)
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
	visibility_changed.connect(_on_visibility_sync)
	_apply_theme()
	_sync({})

func _on_close_popup() -> void:
	if is_instance_valid(_popup):
		_popup.visible = false

func _on_selection_size_changed(_count: int) -> void:
	_sync({})

## Estilo profesional (Figma / Illustrator): secciones planas separadas por
## una línea fina, campos de 24 px con icono y botones de icono de 16 px.
func _apply_theme(_mode: String = "") -> void:
	for sep in _separators:
		if is_instance_valid(sep):
			sep.color = ProUIStyle.col("BORDER")
	for tl in _section_titles:
		if is_instance_valid(tl):
			tl.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
	for prop in _fields:
		var f = _fields[prop]
		if is_instance_valid(f) and f.has_method("apply_theme"):
			f.apply_theme()
	if is_instance_valid(_spin_stroke) and _spin_stroke.has_method("apply_theme"):
		_spin_stroke.apply_theme()
	for b in _buttons:
		if is_instance_valid(b):
			_style_button(b, b.button_pressed)
	for b in _action_btns:
		if is_instance_valid(b):
			_style_action(b)
	for cp in _swatches:
		if is_instance_valid(cp):
			_style_swatch(cp)
	var hole := _cp_stroke.get_node_or_null("Hole") as Panel if is_instance_valid(_cp_stroke) else null
	if hole:
		hole.add_theme_stylebox_override("panel", ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 2, ProUIStyle.col("INPUT_BORDER")))
	_style_tool_buttons()
	for w in [_btn_family, _opt_style]:
		if is_instance_valid(w):
			_style_dropdown(w)
	if is_instance_valid(_family_menu):
		ProUIStyle.style_popup(_family_menu)

## Botón de icono con estado (activo = fondo elevado + icono en acento).
func _style_button(btn: Button, pressed: bool = false) -> void:
	if not is_instance_valid(btn):
		return
	var accent := ProUIStyle.col("ACCENT")
	var normal := ProUIStyle.flat(Color(accent, 0.28) if pressed else Color(0, 0, 0, 0), 4,
		Color(accent, 0.7) if pressed else Color(0, 0, 0, 0), 0, 0)
	var hover := ProUIStyle.flat(Color(accent, 0.36) if pressed else ProUIStyle.col("BUTTON_HOVER"), 4,
		Color(accent, 0.7) if pressed else Color(0, 0, 0, 0), 0, 0)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_stylebox_override("hover_pressed", hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Activo: icono en color de texto sobre fondo de acento (contraste en
	# claro y oscuro); el azul sobre azul no se distinguía en tema oscuro.
	var fg := ProUIStyle.col("PANEL_TEXT") if pressed else ProUIStyle.col("ICON_PRIMARY")
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(k, fg)
	var path := String(btn.get_meta("icon_path", ""))
	if path != "":
		btn.icon = ProUIStyle.icon(path, fg, 16)

## Botón de acción (icono + texto corto, sin estado).
func _style_action(btn: Button) -> void:
	var bg := ProUIStyle.col("INPUT_BG")
	btn.add_theme_stylebox_override("normal", ProUIStyle.flat(bg, 4, ProUIStyle.col("INPUT_BORDER"), 6, 0))
	btn.add_theme_stylebox_override("hover", ProUIStyle.flat(ProUIStyle.col("BUTTON_HOVER"), 4, ProUIStyle.col("BORDER_STRONG"), 6, 0))
	btn.add_theme_stylebox_override("pressed", ProUIStyle.flat(ProUIStyle.col("BUTTON_PRESSED"), 4, ProUIStyle.col("ACCENT"), 6, 0))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE)
	var fg := ProUIStyle.col("PANEL_TEXT")
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(k, fg)
	var path := String(btn.get_meta("icon_path", ""))
	if path != "":
		btn.icon = ProUIStyle.icon(path, ProUIStyle.col("TEXT_SECONDARY"), 16)

## Muestra de color: cuadrado con borde, el color ocupa casi toda la caja.
func _style_swatch(cp: ColorPickerButton) -> void:
	var sb := ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 4, ProUIStyle.col("INPUT_BORDER"), 3, 3)
	var sbh := ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 4, ProUIStyle.col("BORDER_STRONG"), 3, 3)
	cp.add_theme_stylebox_override("normal", sb)
	cp.add_theme_stylebox_override("hover", sbh)
	cp.add_theme_stylebox_override("pressed", sbh)
	cp.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _style_dropdown(w: Button) -> void:
	w.add_theme_stylebox_override("normal", ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 4, ProUIStyle.col("INPUT_BORDER"), 8, 0))
	w.add_theme_stylebox_override("hover", ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 4, ProUIStyle.col("BORDER_STRONG"), 8, 0))
	w.add_theme_stylebox_override("pressed", ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 4, ProUIStyle.col("ACCENT"), 8, 0))
	w.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	w.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE + 1)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		w.add_theme_color_override(k, ProUIStyle.col("PANEL_TEXT"))
	var arrow := ProUIStyle.icon("res://icon/UI/nav-arrow-down.svg", ProUIStyle.col("TEXT_SECONDARY"), 12)
	if w is OptionButton:
		w.add_theme_icon_override("arrow", arrow)
		ProUIStyle.style_popup((w as OptionButton).get_popup())
	else:
		w.icon = arrow

func _on_tool_changed(_tool_name: String) -> void:
	_style_tool_buttons()

const _TOOL_BTNS := {"text": ["txt_tool_title", "Texto", "Texto de título: clic en el lienzo (T)"],
	"paragraph": ["txt_tool_paragraph", "Párrafo", "Marco de párrafo: arrastra en el lienzo"]}

## Los dos botones del popup (tool.tscn) con icono + nombre y la herramienta
## activa resaltada, en vez de dos iconos enmarcados sin texto.
func _style_tool_buttons() -> void:
	if not is_instance_valid(_popup):
		return
	var grid := _popup.get_node_or_null("MarginContainer/BoxContainer/GridContainer") as GridContainer
	if grid == null:
		return
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	var cur := ""
	var t = canvas.current_tool if canvas and "current_tool" in canvas else null
	if t and t.get_script():
		cur = {"TextTool.gd": "text", "ParagraphTool.gd": "paragraph"}.get(String(t.get_script().resource_path).get_file(), "")
	for b in grid.get_children():
		if not (b is Button) or not ("tool_name" in b) or not _TOOL_BTNS.has(String(b.tool_name)):
			continue
		var spec: Array = _TOOL_BTNS[String(b.tool_name)]
		var btn := b as Button
		btn.text = tr(String(spec[1]))
		btn.tooltip_text = tr(String(spec[2]))
		btn.expand_icon = false
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 28)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.set_meta("icon_path", _ICONS + String(spec[0]) + ".svg")
		btn.add_theme_constant_override("h_separation", 8)
		if String(b.tool_name) == cur:
			_style_button(btn, true)
			for k in ["normal", "hover", "pressed", "hover_pressed"]:
				var sb := btn.get_theme_stylebox(k) as StyleBoxFlat
				if sb:
					sb.content_margin_left = 10
		else:
			_style_action(btn)
			for k in ["normal", "hover", "pressed"]:
				var sb := btn.get_theme_stylebox(k) as StyleBoxFlat
				if sb:
					sb.content_margin_left = 10
		btn.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE + 1)
	var title := _popup.get_node_or_null("MarginContainer/BoxContainer/Label") as Label
	if title:
		title.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE + 2)
		title.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))

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

## Sección plana: línea fina + título + filas.
func _section(title: String) -> VBoxContainer:
	if not _sections.is_empty():
		var sep := ColorRect.new()
		sep.custom_minimum_size = Vector2(0, 1)
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_separators.append(sep)
		add_child(sep)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_sections.append(box)
	var lbl := Label.new()
	lbl.text = tr(title)
	lbl.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE)
	_section_titles.append(lbl)
	box.add_child(lbl)
	return box

func _row(parent: Control, sep: int = 6) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", sep)
	parent.add_child(row)
	return row

## Campo numérico con icono (o letra) arrastrable. Con `prop` se conecta a
## InspectorCore: en vivo al arrastrar y UNA acción de undo al soltar.
func _num(parent: Control, icon: String, glyph: String, min_v: float, max_v: float, tip: String, prop: String = "", step_v: float = 1.0, suffix_txt: String = "") -> Control:
	var f = NumField.new(_ICONS + icon + ".svg" if icon != "" else "", glyph, tr(tip))
	f.min_value = min_v
	f.max_value = max_v
	f.step = step_v
	f.suffix = suffix_txt
	parent.add_child(f)
	if not prop.is_empty():
		f.value_changed.connect(_on_field.bind(prop))
		f.scrub_changed.connect(_on_field_scrub.bind(prop))
		f.scrub_ended.connect(_on_field_scrub_end.bind(prop))
		_fields[prop] = f
	return f

func _icon_toggle(icon: String, tip: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tr(tip)
	b.custom_minimum_size = Vector2(28, 24)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.set_meta("icon_path", _ICONS + icon + ".svg")
	b.toggled.connect(func(on: bool) -> void: _style_button(b, on))
	_buttons.append(b)
	return b

## Grupo segmentado de iconos (uno activo a la vez).
func _seg_group(parent: Control, icons: Array, tips: Array, cb: Callable) -> Array[Button]:
	var row := _row(parent, 2)
	var out: Array[Button] = []
	for i in icons.size():
		var b := _icon_toggle(String(icons[i]), String(tips[i]))
		b.pressed.connect(cb.bind(i))
		row.add_child(b)
		out.append(b)
	return out

func _action(parent: Control, icon: String, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = tr(text)
	b.tooltip_text = tr(tip)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 24)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("icon_path", _ICONS + icon + ".svg")
	b.pressed.connect(cb)
	_action_btns.append(b)
	parent.add_child(b)
	return b

func _swatch(parent: Control, tip: String, cb: Callable) -> ColorPickerButton:
	var cp := ColorPickerButton.new()
	cp.tooltip_text = tr(tip)
	cp.color = Color.BLACK
	cp.custom_minimum_size = Vector2(24, 24)
	cp.focus_mode = Control.FOCUS_NONE
	cp.color_changed.connect(cb)
	parent.add_child(cp)
	_swatches.append(cp)
	return cp

func _spacer(parent: Control) -> void:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(s)

func _build_ui() -> void:
	# ── Carácter ──
	var sec_char := _section("Carácter")
	var row_font := _row(sec_char)
	_btn_family = Button.new()
	_btn_family.text = "Inter"
	_btn_family.tooltip_text = tr("Familia tipográfica")
	_btn_family.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_btn_family.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_btn_family.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_btn_family.clip_text = true
	_btn_family.focus_mode = Control.FOCUS_NONE
	_btn_family.custom_minimum_size = Vector2(0, 24)
	_btn_family.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_family.size_flags_stretch_ratio = 1.6
	_btn_family.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_btn_family.pressed.connect(_open_family_menu)
	row_font.add_child(_btn_family)
	_family_menu = PopupMenu.new()
	_family_menu.max_size = Vector2i(320, 420)
	_family_menu.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_family_menu.index_pressed.connect(_on_family_index)
	add_child(_family_menu)

	_opt_style = OptionButton.new()
	_opt_style.tooltip_text = tr("Estilo / grosor")
	_opt_style.focus_mode = Control.FOCUS_NONE
	_opt_style.custom_minimum_size = Vector2(0, 24)
	_opt_style.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_style.fit_to_longest_item = false
	_opt_style.clip_text = true
	for st in ["Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Black", "Italic", "Bold Italic"]:
		_opt_style.add_item(st)
	_opt_style.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_opt_style.get_popup().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_opt_style.select(1)
	_opt_style.item_selected.connect(_on_style_selected)
	row_font.add_child(_opt_style)

	var row_metrics := _row(sec_char)
	_spin_size = _num(row_metrics, "txt_size", "", 4.0, 400.0, "Tamaño de fuente", "", 1.0, "pt")
	_spin_size.value_changed.connect(_fmt_size)
	_spin_size.scrub_changed.connect(_on_field_scrub.bind("font_size"))
	_spin_size.set_value_no_signal(24.0)
	_fields["font_size"] = _spin_size
	_num(row_metrics, "txt_leading", "", -20.0, 300.0, "Interlineado", "line_spacing", 1.0, "px")
	_num(row_metrics, "txt_tracking", "", -10.0, 100.0, "Espaciado entre letras (tracking)", "letter_spacing", 0.5, "px")

	var row_fmt := _row(sec_char, 2)
	_btn_bold = _icon_toggle("txt_bold", "Negrita (Ctrl+B)")
	_btn_bold.pressed.connect(func(): _fmt_toggle("bold"))
	row_fmt.add_child(_btn_bold)
	_btn_italic = _icon_toggle("txt_italic", "Cursiva (Ctrl+I)")
	_btn_italic.pressed.connect(func(): _fmt_toggle("italic"))
	row_fmt.add_child(_btn_italic)
	_btn_underline = _icon_toggle("txt_underline", "Subrayado (Ctrl+U)")
	_btn_underline.pressed.connect(func(): _fmt_toggle("underline"))
	row_fmt.add_child(_btn_underline)
	_spacer(row_fmt)
	_cp_fill = _swatch(row_fmt, "Color del texto", _fmt_color)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(4, 0)
	row_fmt.add_child(gap)
	_cp_stroke = _swatch(row_fmt, "Color del trazo / contorno", _fmt_stroke_color)
	# Trazo = anillo (hueco en el centro), como en Illustrator / Affinity.
	var hole := Panel.new()
	hole.name = "Hole"
	hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hole.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hole.offset_left = 6; hole.offset_top = 6; hole.offset_right = -6; hole.offset_bottom = -6
	_cp_stroke.add_child(hole)
	_spin_stroke = NumField.new(_ICONS + "txt_stroke_width.svg", "", tr("Grosor del trazo (0 = sin trazo)"))
	_spin_stroke.min_value = 0.0
	_spin_stroke.max_value = 50.0
	_spin_stroke.step = 0.5
	_spin_stroke.suffix = "px"
	_spin_stroke.size_flags_horizontal = Control.SIZE_FILL
	_spin_stroke.custom_minimum_size = Vector2(78, 24)
	_spin_stroke.value_changed.connect(_fmt_stroke_width)
	_spin_stroke.scrub_changed.connect(_on_field_scrub.bind("stroke_width"))
	row_fmt.add_child(_spin_stroke)

	# ── Párrafo ──
	var sec_par := _section("Párrafo")
	var row_align := _row(sec_par, 8)
	_align_btns = _seg_group(row_align, _ALIGN_ICONS, _ALIGN_TIPS, _on_align)
	_spacer(row_align)
	_valign_btns = _seg_group(row_align, _VALIGN_ICONS, _VALIGN_TIPS, _on_valign)

	var row_indents := _row(sec_par)
	_num(row_indents, "txt_indent_left", "", 0.0, 500.0, "Sangría izquierda", "indent_left", 1.0, "px")
	_num(row_indents, "txt_indent_right", "", 0.0, 500.0, "Sangría derecha", "indent_right", 1.0, "px")
	_num(row_indents, "txt_indent_first", "", -500.0, 500.0, "Sangría de primera línea (negativa = francesa)", "indent_first", 1.0, "px")

	# ── Marco y flujo ──
	var sec_frame := _section("Marco y flujo")
	var row_dims := _row(sec_frame)
	_num(row_dims, "", "W", 40.0, 4000.0, "Ancho del marco", "width", 1.0, "px")
	_num(row_dims, "", "H", 20.0, 4000.0, "Alto del marco", "height", 1.0, "px")
	var row_cols := _row(sec_frame)
	_num(row_cols, "txt_columns", "", 1.0, 16.0, "Número de columnas", "columns", 1.0, "")
	_num(row_cols, "txt_gutter", "", 0.0, 200.0, "Medianil (espacio entre columnas)", "column_gap", 1.0, "px")
	var row_actions := _row(sec_frame, 4)
	_action(row_actions, "txt_unlink", "Desvincular", "Romper el enlace con el marco siguiente", _on_unlink)
	_action(row_actions, "txt_reflow", "Reorganizar", "Recalcular el flujo del texto encadenado", _on_reflow)
	_action(row_actions, "txt_lorem", "Relleno", "Rellenar el párrafo seleccionado con texto de muestra", _on_lorem)

# ── familia y estilo ────────────────────────────────────────────────────────

func _open_family_menu() -> void:
	var fc := get_node_or_null("/root/FontCore")
	if fc == null or not is_instance_valid(_family_menu):
		return
	_family_menu.clear()
	var fams: PackedStringArray = fc.list_families()
	var cur := _btn_family.text
	for i in fams.size():
		_family_menu.add_radio_check_item(fams[i])
		_family_menu.set_item_checked(i, fams[i] == cur)
	ProUIStyle.style_popup(_family_menu)
	var r := _btn_family.get_global_rect()
	_family_menu.popup(Rect2i(Vector2i(r.position + Vector2(0, r.size.y + 2)), Vector2i(int(maxf(r.size.x, 200.0)), 0)))

func _on_family_index(idx: int) -> void:
	var fam := _family_menu.get_item_text(idx)
	_btn_family.text = fam
	_ic_apply("font_family", fam)

func _on_style_selected(idx: int) -> void:
	var fc := get_node_or_null("/root/FontCore")
	var st := _opt_style.get_item_text(idx)
	var parts: Dictionary = fc.style_to_spec_parts(st) if fc else {}
	var w := int(parts.get("weight", {"Light": 300, "ExtraBold": 800, "Black": 900}.get(st, 400)))
	if st in ["Light", "ExtraBold", "Black"]:
		w = {"Light": 300, "ExtraBold": 800, "Black": 900}[st]
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply_multi"):
		ic.apply_multi({"font_weight": w, "font_italic": bool(parts.get("italic", false))}, "Texto · estilo")

## Nombre del estilo más cercano a (peso, cursiva) para el desplegable.
func _style_index(weight: int, italic: bool) -> int:
	if italic:
		return 8 if weight >= 600 else 7
	var names := {300: 0, 400: 1, 500: 2, 600: 3, 700: 4, 800: 5, 900: 6}
	var best := 1
	var dist := 10000
	for w in names:
		if absi(int(w) - weight) < dist:
			dist = absi(int(w) - weight)
			best = int(names[w])
	return best

# ── acciones ────────────────────────────────────────────────────────────────

func _on_field(v: float, prop: String) -> void:
	if _syncing:
		return
	if _scrub_before.has(prop):
		# Fin de un arrastre: ya está escrito en vivo → UNA acción de undo.
		var ic := get_node_or_null("/root/InspectorCore")
		var before: Dictionary = _scrub_before[prop]
		_scrub_before.erase(prop)
		if ic and ic.has_method("commit_live"):
			ic.commit_live(prop, before)
		return
	_ic_apply(prop, v)

## Arrastre del icono de un campo: escribe en vivo sin crear undo.
func _on_field_scrub(v: float, prop: String) -> void:
	if _syncing:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null or not ic.has_method("_write"):
		return
	if prop in ["font_size", "stroke_width"] and not _editing().is_empty():
		return   # editando: se aplica a la selección de letras al soltar
	if not _scrub_before.has(prop):
		var before := {}
		for s in ic.selection():
			var b = ic._read(s, prop)
			if b != null:
				before[s] = b
		_scrub_before[prop] = before
	for s in (_scrub_before[prop] as Dictionary):
		if is_instance_valid(s):
			ic._write(s, prop, v)
	ic._post_write()

## Fin de arrastre ya escrito en vivo → UNA acción de undo. true si lo era.
func _commit_scrub(prop: String) -> bool:
	if not _scrub_before.has(prop):
		return false
	var before: Dictionary = _scrub_before[prop]
	_scrub_before.erase(prop)
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("commit_live"):
		ic.commit_live(prop, before)
	return true

func _on_field_scrub_end(_v: float, _prop: String) -> void:
	pass   # value_changed llega justo después → _on_field confirma

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
		btns[i].set_pressed_no_signal(i == idx)
		_style_button(btns[i], i == idx)

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
	if _commit_scrub("font_size"):
		return
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
	if _commit_scrub("stroke_width"):
		return
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

## Oculto (popup cerrado) no se sincroniza en cada selección: con 300
## figuras costaba ~1,4 ms por clic. Se pone al día al mostrarse.
var _sync_dirty := false

func _on_visibility_sync() -> void:
	if _sync_dirty and is_visible_in_tree():
		_sync_dirty = false
		_sync({})

func _sync(props: Dictionary = {}) -> void:
	if is_inside_tree() and not is_visible_in_tree():
		_sync_dirty = true
		return
	_syncing = true
	if props.is_empty():
		var ic := get_node_or_null("/root/InspectorCore")
		if ic and ic.has_method("current_props"):
			props = ic.current_props()

	for prop in _fields:
		if not props.has(prop):
			var ef = _fields[prop]
			if is_instance_valid(ef) and ef.has_method("set_mixed"):
				ef.set_mixed(true, "—")
		if props.has(prop) and bool(props[prop].get("mixed", false)):
			var mf = _fields[prop]
			if is_instance_valid(mf) and mf.has_method("set_mixed"):
				mf.set_mixed(true)
		if props.has(prop) and not bool(props[prop].get("mixed", false)):
			var sp = _fields[prop]
			if is_instance_valid(sp):
				if sp.has_method("set_value_no_signal"):
					sp.set_value_no_signal(float(props[prop].get("value", 0.0)))
				elif sp.has_method("set_value"):
					sp.set_value(float(props[prop].get("value", 0.0)))
				elif "value" in sp:
					sp.value = float(props[prop].get("value", 0.0))
	if props.has("font_family") and is_instance_valid(_btn_family):
		_btn_family.text = tr("Mixto") if bool(props["font_family"].get("mixed", false)) else String(props["font_family"].get("value", "Inter"))
		var fc := get_node_or_null("/root/FontCore")
		var f: Font = fc.get_font(fc.make_spec(_btn_family.text)) if fc and not bool(props["font_family"].get("mixed", false)) else null
		if f:
			_btn_family.add_theme_font_override("font", f)
		else:
			_btn_family.remove_theme_font_override("font")
	if props.has("font_weight") and is_instance_valid(_opt_style):
		var w_mixed := bool(props["font_weight"].get("mixed", false))
		var it_mixed := props.has("font_italic") and bool(props["font_italic"].get("mixed", false))
		if w_mixed or it_mixed:
			_opt_style.select(-1)
			_opt_style.text = tr("Mixto")
		else:
			var it := bool(props["font_italic"].get("value", false)) if props.has("font_italic") else false
			_opt_style.select(_style_index(int(props["font_weight"].get("value", 400)), it))
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
	if is_instance_valid(_spin_stroke) and _spin_stroke.has_method("set_mixed"):
		if not props.has("stroke_width"):
			_spin_stroke.set_mixed(true, "—")
		elif bool(props["stroke_width"].get("mixed", false)):
			_spin_stroke.set_mixed(true)
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
