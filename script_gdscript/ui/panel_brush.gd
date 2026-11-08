# =============================================================================
# VECTOPEN — PANEL DE CONFIGURACIÓN DE PINCEL Y ESTILOS (KRITA / BLENDER)
# RUTA: res://script_gdscript/ui/panel_brush.gd
# Proporciona herramientas avanzadas de pincel vectorial: presets de trazo,
# grosor numérico, suavizado/estabilizador y opacidad dinámica.
# =============================================================================
extends PanelContainer

signal closed

# Referencias UI
var _header_title: Label
@warning_ignore("unused_private_class_variable")
var _btn_close: Button
var _spin_size: NumericField
var _spin_opacity: NumericField
var _opt_smoothing: OptionButton
var _style_buttons: Dictionary = {}
var _hint_label: Label

# Presión del lápiz (sensor de tamaño, como Krita)
var _pressure_bar: ProgressBar
var _pressure_status: Label
var _chk_pressure: CheckBox
var _spin_pmin: NumericField
var _opt_pcurve: OptionButton
var _spin_psmooth: NumericField
var _chk_speed: CheckBox
var _pressure_labels: Array[Label] = []

## Estilo común con el resto (colores del tema, como Capas) — UX-06.
const TPS = preload("res://script_gdscript/ui/components/tool_panel_style.gd")
var _section_labels: Array[Label] = []
var _row_labels: Array[Label] = []
var _separators: Array[HSeparator] = []
const _CURVES := [["Suave", 0.6], ["Lineal", 1.0], ["Firme", 1.7]]

var _syncing: bool = false

## UX-06: sin emojis; cada estilo se ve con una muestra DIBUJADA de su trazo
## (color del tema), como las muestras del panel de Trazo.
const STYLES_INFO := [
	{"id": "pencil", "name": "Lápiz", "desc": "Boceto fino y rápido"},
	{"id": "pen", "name": "Pluma", "desc": "Tinta y contorno nítido"},
	{"id": "marker", "name": "Marcador", "desc": "Trazo ancho y semi-opaco"},
	{"id": "calligraphy", "name": "Caligráfico", "desc": "Dinámica de variación angular"},
	{"id": "airbrush", "name": "Aerógrafo", "desc": "Trazo amplio y difuminado"},
	{"id": "object", "name": "Objeto", "desc": "Estampa figuras a lo largo del trazo"},
	{"id": "eraser", "name": "Borrador", "desc": "Elimina trazos vectoriales"},
]

func _ready() -> void:
	custom_minimum_size = Vector2(310, 0)
	ToolPanelDock.normalize_fonts(self)
	_build_ui()
	_connect_events()
	_connect_theme()
	_apply_theme()
	_sync_from_tool()
	get_viewport().size_changed.connect(func() -> void: _keep_on_screen.call_deferred())

# ── Conexión con Eventos y Tema ───────────────────────────────────────────────

func _connect_theme() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm:
		if tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)
		if tm.has_signal("color_slot_changed") and not tm.color_slot_changed.is_connected(_on_color_slot_changed):
			tm.color_slot_changed.connect(_on_color_slot_changed)

func _on_theme_changed(_mode: String) -> void:
	_apply_theme()

func _on_color_slot_changed(_slot: String, _color: Color) -> void:
	_apply_theme()

func _connect_events() -> void:
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("request_brush_panel") and not ge.request_brush_panel.is_connected(_on_request_brush_panel):
		ge.request_brush_panel.connect(_on_request_brush_panel)

func _on_request_brush_panel() -> void:
	visible = true
	move_to_front()
	_sync_from_tool()
	_keep_on_screen.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		# Al mostrarse lee los valores de la herramienta (antes enseñaba los
		# de fábrica del panel: «Mínimo 0 %», presión desmarcada).
		(func() -> void:
			_sync_from_tool()
			_keep_on_screen()).call_deferred()

# ── Construcción de la Interfaz Gráfica ─────────────────────────────────────────

## USR-09: diseño COMPACTO. Sin deslizadores (las casillas numéricas ya
## permiten escribir, arrastrar y la rueda): primero el estilo, luego
## grosor y opacidad en una fila, suavizado y la presión resumida. Si no
## cabe en la pantalla se desplaza dentro del panel y nunca queda tapado.
func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(k, 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_scroll.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.name = "Content"
	root_vbox.add_theme_constant_override("separation", 7)
	margin.add_child(root_vbox)

	_header_title = Label.new()
	_header_title.text = tr("Pincel y estilos")
	_header_title.add_theme_font_size_override("font_size", 13)
	root_vbox.add_child(_header_title)

	# 1. Estilos (dos columnas: nombre + muestra real del trazo)
	var grid := GridContainer.new()
	grid.name = "BrushStyles"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	root_vbox.add_child(grid)
	_style_buttons.clear()
	for info in STYLES_INFO:
		var btn := Button.new()
		btn.name = "Style_" + String(info["id"])
		btn.text = tr(String(info["name"]))
		btn.tooltip_text = tr(String(info["desc"]))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 28)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.toggle_mode = true
		btn.add_theme_font_size_override("font_size", 11)
		var glyph := _BrushGlyph.new(String(info["id"]))
		glyph.name = "Sample"
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.anchor_left = 0.56
		glyph.anchor_right = 1.0
		glyph.anchor_bottom = 1.0
		glyph.offset_right = -6
		glyph.offset_top = 4
		glyph.offset_bottom = -4
		btn.add_child(glyph)
		var s_id: String = info["id"]
		btn.pressed.connect(func(): _select_style(s_id))
		grid.add_child(btn)
		_style_buttons[s_id] = btn

	# 1 b. Dureza del lápiz (solo con el lápiz): 2H … 8B
	_grade_row = HBoxContainer.new()
	_grade_row.name = "PencilGrades"
	_grade_row.add_theme_constant_override("separation", 3)
	root_vbox.add_child(_grade_row)
	var lg := Label.new()
	lg.text = tr("Dureza")
	lg.add_theme_font_size_override("font_size", 11)
	lg.tooltip_text = tr("H: mina dura, gris claro y fino · B: blanda, oscura y cubre más")
	lg.mouse_filter = Control.MOUSE_FILTER_STOP
	_grade_row.add_child(lg)
	_row_labels.append(lg)
	_grade_buttons.clear()
	for gr in BrushStrokeRenderScript.GRADE_ORDER:
		var gb := Button.new()
		gb.name = "Grade_" + gr
		gb.text = gr
		gb.toggle_mode = true
		gb.focus_mode = Control.FOCUS_NONE
		gb.custom_minimum_size = Vector2(28, 22)
		gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gb.add_theme_font_size_override("font_size", 10)
		var g_id: String = gr
		gb.pressed.connect(func() -> void: _select_grade(g_id))
		_grade_row.add_child(gb)
		_grade_buttons[gr] = gb

	_build_object_ui(root_vbox)

	root_vbox.add_child(_create_h_separator())

	# 2. Grosor y opacidad en una fila; suavizado debajo
	var fields := GridContainer.new()
	fields.name = "Fields"
	fields.columns = 4
	fields.add_theme_constant_override("h_separation", 6)
	fields.add_theme_constant_override("v_separation", 6)
	root_vbox.add_child(fields)
	_spin_size = NumericField.new("", " px", 0.5, 100.0, 0.5)
	_spin_size.name = "FieldSize"
	_spin_size.decimals = 1
	_spin_size.value = 4.0
	_spin_size.value_changed.connect(_on_size_spin_changed)
	_field_pair(fields, "Grosor", _spin_size)
	_spin_opacity = NumericField.new("", " %", 5.0, 100.0, 1.0)
	_spin_opacity.name = "FieldOpacity"
	_spin_opacity.decimals = 0
	_spin_opacity.value = 100.0
	_spin_opacity.value_changed.connect(_on_opacity_spin_changed)
	_field_pair(fields, "Opacidad", _spin_opacity)

	var smooth_row := HBoxContainer.new()
	smooth_row.add_theme_constant_override("separation", 6)
	root_vbox.add_child(smooth_row)
	var lbl_smooth := Label.new()
	lbl_smooth.text = tr("Suavizado")
	lbl_smooth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_smooth.add_theme_font_size_override("font_size", 11)
	smooth_row.add_child(lbl_smooth)
	_row_labels.append(lbl_smooth)
	_opt_smoothing = OptionButton.new()
	_opt_smoothing.add_item(tr("Rápido (Boceto)"), 0)
	_opt_smoothing.add_item(tr("Equilibrado"), 1)
	_opt_smoothing.add_item(tr("Alto (Preciso)"), 2)
	_opt_smoothing.add_item(tr("Ultra Suave"), 3)
	_opt_smoothing.select(1)
	_opt_smoothing.custom_minimum_size = Vector2(150, 24)
	_opt_smoothing.focus_mode = Control.FOCUS_NONE
	_opt_smoothing.item_selected.connect(_on_smoothing_selected)
	smooth_row.add_child(_opt_smoothing)

	root_vbox.add_child(_create_h_separator())
	_build_pressure_ui(root_vbox)

	_hint_label = Label.new()
	_hint_label.text = tr("Mayús: grosor  ·  Ctrl: recta  ·  Alt: continuar")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 9)
	root_vbox.add_child(_hint_label)
	_keep_on_screen.call_deferred()

var _scroll: ScrollContainer
var _grade_row: HBoxContainer
var _grade_buttons: Dictionary = {}
const BrushStrokeRenderScript = preload("res://script_gdscript/shapes/brush_stroke_render.gd")

func _select_grade(grade: String) -> void:
	var tool = _get_brush_tool()
	if tool:
		tool.pencil_grade = grade
	_update_grade_buttons(grade)

func _update_grade_buttons(active: String) -> void:
	for g in _grade_buttons:
		var b: Button = _grade_buttons[g]
		b.set_pressed_no_signal(g == active)
		TPS.style_toggle(b, g == active)

## Etiqueta + casilla numérica dentro de una rejilla de 4 columnas.
# ── Pincel de objeto (VGSE fase 2) ───────────────────────────────────────────
var _object_box: VBoxContainer
var _obj_spacing: NumericField
var _obj_scatter: NumericField
var _obj_rotate: CheckBox
var _obj_random: CheckBox
var _obj_each: CheckBox
var _obj_pattern: CheckBox

## Opciones del pincel de objeto (solo con ese estilo): qué figura se
## estampa (la selección o una de serie), separación, dispersión, giro y,
## con varias figuras, si van una a una o al azar.
func _build_object_ui(parent: VBoxContainer) -> void:
	_object_box = VBoxContainer.new()
	_object_box.name = "ObjectBrush"
	_object_box.add_theme_constant_override("separation", 5)
	parent.add_child(_object_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	_object_box.add_child(row)
	var lf := Label.new()
	lf.text = tr("Figura")
	lf.add_theme_font_size_override("font_size", 11)
	row.add_child(lf)
	_row_labels.append(lf)
	for spec in [["ObjFromSelection", "Selección", "Usa las figuras seleccionadas como pincel"],
			["ObjStar", "Estrella", ""], ["ObjLeaf", "Hoja", ""], ["ObjDot", "Punto", ""]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = tr(spec[1])
		if spec[2] != "":
			b.tooltip_text = tr(spec[2])
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 22)
		b.add_theme_font_size_override("font_size", 10)
		var id: String = spec[0]
		b.pressed.connect(func() -> void: _on_object_source(id))
		row.add_child(b)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_object_box.add_child(grid)
	_obj_spacing = NumericField.new("", " %", 10.0, 500.0, 5.0)
	_obj_spacing.name = "ObjSpacing"
	_obj_spacing.decimals = 0
	_obj_spacing.value = 110.0
	_obj_spacing.tooltip_text = tr("Distancia entre figuras, en % de su tamaño")
	_obj_spacing.value_changed.connect(func(v: float) -> void: _set_obj("spacing", v / 100.0))
	_field_pair(grid, "Separación", _obj_spacing)
	_obj_scatter = NumericField.new("", " %", 0.0, 300.0, 5.0)
	_obj_scatter.name = "ObjScatter"
	_obj_scatter.decimals = 0
	_obj_scatter.value = 0.0
	_obj_scatter.tooltip_text = tr("Desplazamiento lateral al azar, en % del tamaño")
	_obj_scatter.value_changed.connect(func(v: float) -> void: _set_obj("scatter", v / 100.0))
	_field_pair(grid, "Dispersión", _obj_scatter)
	var checks := HBoxContainer.new()
	checks.add_theme_constant_override("separation", 6)
	_object_box.add_child(checks)
	_obj_rotate = CheckBox.new()
	_obj_rotate.name = "ObjRotate"
	_obj_rotate.text = tr("Girar con el trazo")
	_obj_rotate.button_pressed = true
	_obj_rotate.toggled.connect(func(on: bool) -> void: _set_obj("rotate", on))
	_obj_random = CheckBox.new()
	_obj_random.name = "ObjRandom"
	_obj_random.text = tr("Al azar")
	_obj_random.tooltip_text = tr("Con varias figuras: elegir una al azar en cada estampa (si no, una tras otra)")
	_obj_random.toggled.connect(func(on: bool) -> void: _set_obj("multi", "random" if on else "sequence"))
	_obj_each = CheckBox.new()
	_obj_each.name = "ObjEach"
	_obj_each.text = tr("Una a una")
	_obj_each.tooltip_text = tr("Al usar la selección: cada figura es una estampa distinta (si no, todas juntas)")
	for cb in [_obj_rotate, _obj_random, _obj_each]:
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 10)
		checks.add_child(cb)
	_obj_pattern = CheckBox.new()
	_obj_pattern.name = "ObjPattern"
	_obj_pattern.text = tr("Patrón: doblar con la curva")
	_obj_pattern.tooltip_text = tr("La figura se repite y se dobla siguiendo el trazo (cenefas, marcos); si no, copias rígidas")
	_obj_pattern.focus_mode = Control.FOCUS_NONE
	_obj_pattern.add_theme_font_size_override("font_size", 10)
	_obj_pattern.toggled.connect(func(on: bool) -> void: _set_obj("mode", "pattern" if on else "stamp"))
	_object_box.add_child(_obj_pattern)

func _set_obj(key: String, value) -> void:
	if _syncing:
		return
	var tool = _get_brush_tool()
	if tool and tool.has_method("set_object_param"):
		tool.set_object_param(key, value)

func _on_object_source(id: String) -> void:
	var tool = _get_brush_tool()
	if tool == null or not tool.has_method("use_selection_as_object"):
		return
	match id:
		"ObjFromSelection":
			if not tool.use_selection_as_object(not _obj_each.button_pressed):
				var un := get_node_or_null("/root/UserNotices")
				if un and un.has_method("show_notice"):
					un.show_notice("warning", tr("Selecciona una o varias figuras para usarlas como pincel"))
				return
		"ObjStar":
			tool.set_object_preset("star")
		"ObjLeaf":
			tool.set_object_preset("leaf")
		"ObjDot":
			tool.set_object_preset("dot")
	if tool.brush_style != "object":
		_select_style("object")

func _field_pair(grid: GridContainer, text: String, field: NumericField) -> void:
	var l := Label.new()
	l.text = tr(text)
	l.add_theme_font_size_override("font_size", 11)
	grid.add_child(l)
	_row_labels.append(l)
	field.custom_minimum_size = Vector2(76, 24)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(field)

## Presión del lápiz, resumida: medidor en la misma fila que el título,
## mínimo y estabilizado como casillas numéricas.
func _build_pressure_ui(parent: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	parent.add_child(head)
	var title := Label.new()
	title.text = tr("Presión del lápiz")
	head.add_child(title)
	_section_labels.append(title)
	_pressure_bar = ProgressBar.new()
	_pressure_bar.min_value = 0.0
	_pressure_bar.max_value = 100.0
	_pressure_bar.show_percentage = false
	_pressure_bar.custom_minimum_size = Vector2(40, 6)
	_pressure_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pressure_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pressure_bar.tooltip_text = tr("Presión que llega ahora mismo del lápiz")
	head.add_child(_pressure_bar)
	_pressure_status = Label.new()
	_pressure_status.add_theme_font_size_override("font_size", 10)
	head.add_child(_pressure_status)
	_pressure_labels.append(_pressure_status)

	_chk_pressure = CheckBox.new()
	_chk_pressure.text = tr("Grosor según la presión")
	_chk_pressure.focus_mode = Control.FOCUS_NONE
	_chk_pressure.add_theme_font_size_override("font_size", 11)
	_chk_pressure.toggled.connect(func(on: bool) -> void: _set_pressure("pressure_size_enabled", on))
	parent.add_child(_chk_pressure)

	var g := GridContainer.new()
	g.name = "PressureFields"
	g.columns = 4
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	parent.add_child(g)
	_spin_pmin = NumericField.new("", " %", 0.0, 100.0, 1.0)
	_spin_pmin.name = "FieldPressureMin"
	_spin_pmin.decimals = 0
	_spin_pmin.tooltip_text = tr("Grosor con la presión mínima (porcentaje del grosor del pincel)")
	_spin_pmin.value_changed.connect(func(v: float) -> void: _set_pressure("pressure_min", v / 100.0))
	_field_pair(g, "Mínimo", _spin_pmin)
	_spin_psmooth = NumericField.new("", " %", 0.0, 90.0, 5.0)
	_spin_psmooth.name = "FieldPressureSmooth"
	_spin_psmooth.decimals = 0
	_spin_psmooth.tooltip_text = tr("Filtra el temblor de la presión (más = grosor más uniforme)")
	_spin_psmooth.value_changed.connect(func(v: float) -> void: _set_pressure("pressure_smoothing", v / 100.0))
	_field_pair(g, "Estabilizar", _spin_psmooth)

	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 6)
	parent.add_child(r2)
	var lc := Label.new()
	lc.text = tr("Curva")
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lc.add_theme_font_size_override("font_size", 11)
	r2.add_child(lc)
	_row_labels.append(lc)
	_opt_pcurve = OptionButton.new()
	for c in _CURVES:
		_opt_pcurve.add_item(tr(c[0]))
	_opt_pcurve.custom_minimum_size = Vector2(150, 24)
	_opt_pcurve.focus_mode = Control.FOCUS_NONE
	_opt_pcurve.tooltip_text = tr("Suave: poca fuerza ya engorda · Firme: hay que apretar más")
	_opt_pcurve.item_selected.connect(func(i: int) -> void: _set_pressure("pressure_gamma", float(_CURVES[i][1])))
	r2.add_child(_opt_pcurve)

	_chk_speed = CheckBox.new()
	_chk_speed.text = tr("Sin lápiz: simular con la velocidad")
	_chk_speed.tooltip_text = tr("Con ratón: rápido = fino, lento = grueso")
	_chk_speed.focus_mode = Control.FOCUS_NONE
	_chk_speed.add_theme_font_size_override("font_size", 11)
	_chk_speed.toggled.connect(func(on: bool) -> void: _set_pressure("speed_pressure", on))
	parent.add_child(_chk_speed)
	set_process(true)

## Que el panel quepa siempre en la ventana: si sobresale por abajo (o por
## arriba) se sube, y si es más alto que la ventana se limita y se desplaza
## por dentro. Antes la parte de abajo quedaba tapada por el borde.
func _keep_on_screen() -> void:
	if not is_inside_tree() or not visible or _scroll == null:
		return
	var vp := get_viewport_rect().size
	var content := _scroll.get_child(0) as Control
	var want := content.get_combined_minimum_size().y if content else size.y
	var room := vp.y - 16.0
	_scroll.custom_minimum_size.y = minf(want, room - 4.0)
	reset_size()
	var r := get_global_rect()
	var dy := 0.0
	if r.end.y > vp.y - 8.0:
		dy = vp.y - 8.0 - r.end.y
	if r.position.y + dy < 8.0:
		dy = 8.0 - r.position.y
	if dy != 0.0:
		global_position.y += dy

func _set_pressure(prop: String, v: Variant) -> void:
	if _syncing:
		return
	var tool = _get_brush_tool()
	if tool:
		tool.set(prop, v)
		tool.save_pressure_settings()

func _sync_pressure_ui(tool) -> void:
	if not is_instance_valid(_chk_pressure) or tool == null:
		return
	_chk_pressure.button_pressed = tool.pressure_size_enabled
	_spin_pmin.set_value_silent(round(tool.pressure_min * 100.0))
	var best := 0
	for i in _CURVES.size():
		if absf(float(_CURVES[i][1]) - tool.pressure_gamma) < absf(float(_CURVES[best][1]) - tool.pressure_gamma):
			best = i
	_opt_pcurve.select(best)
	_spin_psmooth.set_value_silent(round(tool.pressure_smoothing * 100.0))
	_chk_speed.button_pressed = tool.speed_pressure

## Medidor en vivo: así se ve al momento si la tableta manda presión.
func _process(_dt: float) -> void:
	if not visible or not is_instance_valid(_pressure_bar):
		return
	var tool = _get_brush_tool()
	if tool == null:
		_pressure_status.text = tr("Pincel no activo")
		_pressure_bar.value = 0.0
		return
	_pressure_bar.value = clampf(tool.live_pressure, 0.0, 1.0) * 100.0
	if tool.pen_detected:
		_pressure_status.text = tr("Lápiz: %d %%") % int(round(tool.live_pressure * 100.0))
	else:
		_pressure_status.text = tr("Sin lápiz (ratón)")

func _create_h_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	_separators.append(sep)
	return sep

# ── Manejadores de Interacción ────────────────────────────────────────────────

func _get_brush_tool() -> BrushTool:
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if is_instance_valid(canvas) and canvas.has_method("get_current_tool"):
		var t = canvas.get_current_tool()
		if t is BrushTool:
			return t
	var tm = get_node_or_null("/root/ToolManager")
	if is_instance_valid(tm) and tm.has_method("get_tool"):
		var t = tm.get_tool("brush")
		if t is BrushTool:
			return t
	return null

func _sync_from_tool() -> void:
	if _syncing: return
	_syncing = true
	var tool = _get_brush_tool()
	if tool:
		if is_instance_valid(_spin_size):
			_spin_size.set_value_silent(tool.brush_width)
		if is_instance_valid(_spin_opacity):
			_spin_opacity.set_value_silent(tool.brush_opacity * 100.0)
		_update_active_style_button(tool.brush_style)
		if is_instance_valid(_grade_row):
			_grade_row.visible = tool.brush_style == "pencil"
			_update_grade_buttons(tool.pencil_grade)
		if is_instance_valid(_object_box):
			_object_box.visible = tool.brush_style == "object"
			if "object_params" in tool:
				var op: Dictionary = tool.object_params
				_obj_spacing.set_value_silent(float(op.get("spacing", 1.1)) * 100.0)
				_obj_scatter.set_value_silent(float(op.get("scatter", 0.0)) * 100.0)
				_obj_rotate.set_pressed_no_signal(bool(op.get("rotate", true)))
				_obj_random.set_pressed_no_signal(String(op.get("multi", "sequence")) == "random")
				_obj_pattern.set_pressed_no_signal(String(op.get("mode", "stamp")) == "pattern")
		_sync_pressure_ui(tool)
	_syncing = false

func _on_size_spin_changed(val: float) -> void:
	if _syncing: return
	var tool = _get_brush_tool()
	if tool:
		tool.brush_width = val

func _on_opacity_spin_changed(val: float) -> void:
	if _syncing: return
	var tool = _get_brush_tool()
	if tool:
		tool.brush_opacity = val / 100.0

func _on_smoothing_selected(idx: int) -> void:
	var tool = _get_brush_tool()
	if not tool: return
	match idx:
		0: tool.set_brush_preset("potato")
		1: tool.set_brush_preset("balanced")
		2: tool.set_brush_preset("high")
		3: tool.set_brush_preset("ultra")

func _select_style(style_id: String) -> void:
	var tool = _get_brush_tool()
	if tool:
		tool.apply_brush_style(style_id)
		_sync_from_tool()
	_update_active_style_button(style_id)

func _update_active_style_button(active_id: String) -> void:
	for s_id in _style_buttons:
		var btn: Button = _style_buttons[s_id]
		btn.button_pressed = (s_id == active_id)
		TPS.style_toggle(btn, btn.button_pressed)

# ── Estilización y Adaptabilidad al Tema ──────────────────────────────────────
## Todo con los colores del tema actual (UX-06): antes fondo, textos y
## secundarios eran fijos (claro / oscuro escritos a mano).
func _apply_theme() -> void:
	TPS.apply_frame(self)
	for g in _grade_buttons:
		TPS.style_toggle(_grade_buttons[g], (_grade_buttons[g] as Button).button_pressed)
	TPS.style_title(_header_title)
	TPS.style_muted(_hint_label)
	for l in _section_labels:
		TPS.style_section_label(l)
	for l in _row_labels:
		TPS.style_text(l)
	for l in _pressure_labels:
		TPS.style_muted(l)
	for sp in _separators:
		TPS.style_separator(sp)
	for s_id in _style_buttons:
		var btn: Button = _style_buttons[s_id]
		TPS.style_toggle(btn, btn.button_pressed)
		var g := btn.get_node_or_null("Sample") as Control
		if g:
			g.call("refresh_color")
			g.queue_redraw()
	for cb in [_chk_pressure, _chk_speed]:
		if is_instance_valid(cb):
			for k in ["font_color", "font_hover_color", "font_pressed_color"]:
				cb.add_theme_color_override(k, ProUIStyle.col("PANEL_TEXT"))


## Muestra de cada estilo (UX-16): un TRAZO REAL (Line2D) pintado por el mismo
## render que el lienzo (BrushStrokeRender, con la textura del estilo), con su
## grosor, opacidad, remates y presión. Lo que se ve es lo que se pinta.
class _BrushGlyph extends Control:
	const BrushStrokeRender = preload("res://script_gdscript/shapes/brush_stroke_render.gd")
	## grosor relativo al alto, opacidad, puntos de la curva de presión
	const SPEC := {
		"pencil": [0.10, 0.85, [[0.0, 0.55], [0.15, 1.0], [0.85, 0.9], [1.0, 0.5]]],
		"pen": [0.16, 1.0, [[0.0, 0.15], [0.35, 1.0], [0.7, 0.85], [1.0, 0.1]]],
		"marker": [0.55, 0.7, [[0.0, 1.0], [1.0, 1.0]]],
		"calligraphy": [0.42, 1.0, [[0.0, 0.25], [0.2, 1.0], [0.45, 0.3], [0.7, 1.0], [1.0, 0.2]]],
		"airbrush": [0.85, 0.55, [[0.0, 0.6], [0.5, 1.0], [1.0, 0.6]]],
		"object": [0.6, 1.0, [[0.0, 0.7], [0.5, 1.0], [1.0, 0.7]]],
	}
	var style_id := ""
	var _line: Line2D = null
	func _init(id: String) -> void:
		style_id = id
		clip_contents = true
		resized.connect(_rebuild)
	static func _a(c: Color, a: float) -> Color:
		var out := c
		out.a = a
		return out
	func _rebuild() -> void:
		queue_redraw()
		if not SPEC.has(style_id) or size.x < 10.0 or size.y < 6.0:
			return
		if _line == null:
			_line = Line2D.new()
			_line.name = "SampleStroke"
			_line.set_meta("brush_style", style_id)
			_line.begin_cap_mode = Line2D.LINE_CAP_BOX if style_id == "marker" else Line2D.LINE_CAP_ROUND
			_line.end_cap_mode = _line.begin_cap_mode
			_line.joint_mode = Line2D.LINE_JOINT_ROUND
			var wc := Curve.new()
			for pt in SPEC[style_id][2]:
				wc.add_point(Vector2(pt[0], pt[1]))
			_line.width_curve = wc
			add_child(_line)
			BrushStrokeRender.attach(_line)
		var h := size.y
		var spec: Array = SPEC[style_id]
		_line.width = maxf(1.2, h * float(spec[0]))
		_line.default_color = _a(ProUIStyle.col("PANEL_TEXT"), float(spec[1]))
		var pad := _line.width * 0.6 + 2.0
		var pts := PackedVector2Array()
		var n := 40
		for i in n:
			var t := float(i) / float(n - 1)
			pts.append(Vector2(pad + t * (size.x - pad * 2.0), h * 0.5 + sin(t * TAU) * (h * 0.5 - pad) * 0.8))
		_line.points = pts
		var r = _line.get_node_or_null(BrushStrokeRender.NODE_NAME)
		if r:
			r.queue_redraw()
	func refresh_color() -> void:
		if _line:
			_line.default_color = _a(ProUIStyle.col("PANEL_TEXT"), float(SPEC[style_id][1]))
	func _draw() -> void:
		if style_id != "eraser":
			return
		# Borrador: un trazo que se borra (discontinuo y atenuado) y la goma.
		var col := ProUIStyle.col("PANEL_TEXT")
		var h := size.y
		var n := 28
		var pts := PackedVector2Array()
		for i in n:
			var t := float(i) / float(n - 1)
			pts.append(Vector2(4.0 + t * (size.x - 22.0), h * 0.5 + sin(t * TAU) * h * 0.28))
		for i in range(0, n - 1, 3):
			draw_line(pts[i], pts[i + 1], _a(col, 0.45), 2.0, true)
		var e := Rect2(Vector2(size.x - 18.0, h * 0.5 - 6.0), Vector2(14, 10))
		var sb := StyleBoxFlat.new()
		sb.bg_color = _a(col, 0.15)
		sb.border_color = col
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		draw_style_box(sb, e)
