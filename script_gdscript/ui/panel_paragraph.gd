# =============================================================================
# VECTOPEN - PANEL DE PÁRRAFO (configuración bajo los botones Texto/Párrafo)
# RUTA: res://script_gdscript/ui/panel_paragraph.gd
# Se monta por código dentro del popup `text` de tool.tscn (sin tocar el .tscn).
# Solo PÁRRAFO (alineación, vertical, sangrías) y MARCO Y FLUJO (tamaño,
# columnas, enlazado). El formato de carácter (fuente, tamaño, color, B/I/U,
# trazo…) vive en el panel Tipografía: así los dos paneles no se repiten.
# =============================================================================
class_name PanelParagraph
extends VBoxContainer

## Relleno largo para previsualizar marcos (estilo InDesign).
const LOREM := "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.\nDuis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

const NumField := preload("res://script_gdscript/ui/pro/pro_num_field.gd")
const _ICONS := "res://icon/UI/"

var _syncing := false
var _fields: Dictionary = {}
var _sections: Array[Control] = []
var _section_titles: Array[Label] = []
var _separators: Array[ColorRect] = []
var _buttons: Array[Button] = []          # botones de icono con estado
var _action_btns: Array[Button] = []      # acciones (sin estado activo)
var _align_btns: Array[Button] = []
var _valign_btns: Array[Button] = []
var _hint: Label = null
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
	if is_instance_valid(_hint):
		_hint.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
	for prop in _fields:
		var f = _fields[prop]
		if is_instance_valid(f) and f.has_method("apply_theme"):
			f.apply_theme()
	for b in _buttons:
		if is_instance_valid(b):
			_style_button(b, b.button_pressed)
	for b in _action_btns:
		if is_instance_valid(b):
			_style_action(b)
	_style_tool_buttons()

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

func _spacer(parent: Control) -> void:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(s)

func _build_ui() -> void:
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

	# Dónde está el resto: el formato de letra no se repite aquí.
	_hint = Label.new()
	_hint.text = tr("Fuente, tamaño, color y estilo de letra: panel Tipografía (clic derecho).")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE_SMALL)
	add_child(_hint)

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

## Arrastre de un campo: escribe en vivo (vía InspectorCore, así los demás
## paneles lo ven) sin crear undo; al soltar, _on_field registra UNO.
func _on_field_scrub(v: float, prop: String) -> void:
	if _syncing:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null or not ic.has_method("_write"):
		return
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
		var f = _fields[prop]
		if not is_instance_valid(f):
			continue
		if not props.has(prop):
			f.set_mixed(true, "—")
		elif bool(props[prop].get("mixed", false)):
			f.set_mixed(true)
		else:
			f.set_value_no_signal(float(props[prop].get("value", 0.0)))
	if props.has("text_align") and not bool(props["text_align"].get("mixed", false)):
		_mark(_align_btns, _ALIGNS.find(String(props["text_align"].get("value", "left"))))
	if props.has("text_valign") and not bool(props["text_valign"].get("mixed", false)):
		_mark(_valign_btns, _VALIGNS.find(String(props["text_valign"].get("value", "top"))))
	_syncing = false
