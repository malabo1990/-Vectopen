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
var _btn_close: Button
var _spin_size: SpinBox
var _slider_size: HSlider
var _spin_opacity: SpinBox
var _slider_opacity: HSlider
var _opt_smoothing: OptionButton
var _style_buttons: Dictionary = {}
var _hint_label: Label

# Presión del lápiz (sensor de tamaño, como Krita)
var _pressure_bar: ProgressBar
var _pressure_status: Label
var _chk_pressure: CheckBox
var _slider_pmin: HSlider
var _lbl_pmin: Label
var _opt_pcurve: OptionButton
var _slider_psmooth: HSlider
var _lbl_psmooth: Label
var _chk_speed: CheckBox
var _pressure_labels: Array[Label] = []
const _CURVES := [["Suave", 0.6], ["Lineal", 1.0], ["Firme", 1.7]]

var _syncing: bool = false

const STYLES_INFO := [
	{"id": "pencil", "name": "Lápiz", "icon_txt": "✏️", "desc": "Boceto fino y rápido"},
	{"id": "pen", "name": "Pluma", "icon_txt": "✒️", "desc": "Tinta y contorno nítido"},
	{"id": "marker", "name": "Marcador", "icon_txt": "🖍️", "desc": "Trazo ancho y semi-opaco"},
	{"id": "calligraphy", "name": "Caligráfico", "icon_txt": "🖌️", "desc": "Dinámica de variación angular"},
	{"id": "airbrush", "name": "Aerógrafo", "icon_txt": "💨", "desc": "Trazo amplio y difuminado"},
	{"id": "eraser", "name": "Borrador", "icon_txt": "🧹", "desc": "Elimina trazos vectoriales"},
]

func _ready() -> void:
	custom_minimum_size = Vector2(310, 0)
	ToolPanelDock.normalize_fonts(self)
	_build_ui()
	_connect_events()
	_connect_theme()
	_apply_theme()
	_sync_from_tool()

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

# ── Construcción de la Interfaz Gráfica ─────────────────────────────────────────

func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	# 1. Cabecera (Header)
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(header)

	_header_title = Label.new()
	_header_title.text = "Pincel & Estilos"
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_title.add_theme_font_size_override("font_size", 13)
	header.add_child(_header_title)

	# Sin botón ✕: ocultaba el panel y no había forma de volver a abrirlo
	# (se muestra solo con su herramienta).

	# Separador
	root_vbox.add_child(_create_h_separator())

	# 2. Control de Tamaño (Grosor)
	var size_box := VBoxContainer.new()
	size_box.add_theme_constant_override("separation", 4)
	root_vbox.add_child(size_box)

	var size_header := HBoxContainer.new()
	size_box.add_child(size_header)

	var lbl_size := Label.new()
	lbl_size.text = "Grosor (px)"
	lbl_size.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_size.add_theme_font_size_override("font_size", 11)
	size_header.add_child(lbl_size)

	_spin_size = SpinBox.new()
	_spin_size.min_value = 0.5
	_spin_size.max_value = 100.0
	_spin_size.step = 0.5
	_spin_size.value = 4.0
	_spin_size.custom_minimum_size = Vector2(65, 24)
	_spin_size.value_changed.connect(_on_size_spin_changed)
	size_header.add_child(_spin_size)

	_slider_size = HSlider.new()
	_slider_size.min_value = 0.5
	_slider_size.max_value = 100.0
	_slider_size.step = 0.5
	_slider_size.value = 4.0
	_slider_size.value_changed.connect(_on_size_slider_changed)
	size_box.add_child(_slider_size)

	# 3. Control de Opacidad
	var op_box := VBoxContainer.new()
	op_box.add_theme_constant_override("separation", 4)
	root_vbox.add_child(op_box)

	var op_header := HBoxContainer.new()
	op_box.add_child(op_header)

	var lbl_op := Label.new()
	lbl_op.text = "Opacidad (%)"
	lbl_op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_op.add_theme_font_size_override("font_size", 11)
	op_header.add_child(lbl_op)

	_spin_opacity = SpinBox.new()
	_spin_opacity.min_value = 5.0
	_spin_opacity.max_value = 100.0
	_spin_opacity.step = 1.0
	_spin_opacity.value = 100.0
	_spin_opacity.custom_minimum_size = Vector2(65, 24)
	_spin_opacity.value_changed.connect(_on_opacity_spin_changed)
	op_header.add_child(_spin_opacity)

	_slider_opacity = HSlider.new()
	_slider_opacity.min_value = 5.0
	_slider_opacity.max_value = 100.0
	_slider_opacity.step = 1.0
	_slider_opacity.value = 100.0
	_slider_opacity.value_changed.connect(_on_opacity_slider_changed)
	op_box.add_child(_slider_opacity)

	# 4. Suavizado / Estabilizador
	var smooth_row := HBoxContainer.new()
	smooth_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(smooth_row)

	var lbl_smooth := Label.new()
	lbl_smooth.text = "Suavizado"
	lbl_smooth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_smooth.add_theme_font_size_override("font_size", 11)
	smooth_row.add_child(lbl_smooth)

	_opt_smoothing = OptionButton.new()
	_opt_smoothing.add_item("Rápido (Boceto)", 0)
	_opt_smoothing.add_item("Equilibrado", 1)
	_opt_smoothing.add_item("Alto (Preciso)", 2)
	_opt_smoothing.add_item("Ultra Suave", 3)
	_opt_smoothing.select(1)
	_opt_smoothing.custom_minimum_size = Vector2(130, 26)
	_opt_smoothing.item_selected.connect(_on_smoothing_selected)
	smooth_row.add_child(_opt_smoothing)

	# Separador
	root_vbox.add_child(_create_h_separator())
	_build_pressure_ui(root_vbox)
	root_vbox.add_child(_create_h_separator())

	# 5. Tabla / Grid de Estilos (Krita / Blender)
	var lbl_styles := Label.new()
	lbl_styles.text = "Estilos de Pincel (Krita / Blender)"
	lbl_styles.add_theme_font_size_override("font_size", 11)
	root_vbox.add_child(lbl_styles)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	root_vbox.add_child(grid)

	_style_buttons.clear()
	for info in STYLES_INFO:
		var btn := Button.new()
		btn.text = "%s %s" % [info["icon_txt"], info["name"]]
		btn.tooltip_text = info["desc"]
		btn.custom_minimum_size = Vector2(134, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.toggle_mode = true
		var s_id: String = info["id"]
		btn.pressed.connect(func(): _select_style(s_id))
		grid.add_child(btn)
		_style_buttons[s_id] = btn

	# 6. Atajos y Ayuda Rápida
	_hint_label = Label.new()
	_hint_label.text = "Shift: Grosor  |  Ctrl: Eje recto  |  Alt: Línea continua"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 9)
	root_vbox.add_child(_hint_label)

## Sección "Presión del lápiz": medidor en vivo (para ver si llega la
## presión de la tableta) + sensor de tamaño: mínimo, curva, estabilizado y
## presión simulada por velocidad para el ratón.
func _build_pressure_ui(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Presión del lápiz"
	title.add_theme_font_size_override("font_size", 11)
	parent.add_child(title)
	_pressure_labels.append(title)

	var meter := HBoxContainer.new()
	meter.add_theme_constant_override("separation", 8)
	parent.add_child(meter)
	_pressure_bar = ProgressBar.new()
	_pressure_bar.min_value = 0.0
	_pressure_bar.max_value = 100.0
	_pressure_bar.show_percentage = false
	_pressure_bar.custom_minimum_size = Vector2(70, 8)
	_pressure_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pressure_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pressure_bar.tooltip_text = "Presión que llega ahora mismo del lápiz"
	meter.add_child(_pressure_bar)
	_pressure_status = Label.new()
	_pressure_status.add_theme_font_size_override("font_size", 10)
	_pressure_status.custom_minimum_size = Vector2(118, 0)
	meter.add_child(_pressure_status)
	_pressure_labels.append(_pressure_status)

	_chk_pressure = CheckBox.new()
	_chk_pressure.text = "Grosor según la presión"
	_chk_pressure.focus_mode = Control.FOCUS_NONE
	_chk_pressure.add_theme_font_size_override("font_size", 11)
	_chk_pressure.toggled.connect(func(on: bool) -> void: _set_pressure("pressure_size_enabled", on))
	parent.add_child(_chk_pressure)

	var r1 := _pressure_row(parent, "Grosor mínimo")
	_slider_pmin = HSlider.new()
	_slider_pmin.min_value = 0
	_slider_pmin.max_value = 100
	_slider_pmin.step = 1
	_slider_pmin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_pmin.tooltip_text = "Grosor con la presión mínima (porcentaje del grosor del pincel)"
	r1.add_child(_slider_pmin)
	_lbl_pmin = _value_label(r1)
	_slider_pmin.value_changed.connect(func(v: float) -> void:
		_lbl_pmin.text = "%d %%" % int(v)
		_set_pressure("pressure_min", v / 100.0))

	var r2 := _pressure_row(parent, "Curva")
	_opt_pcurve = OptionButton.new()
	for c in _CURVES:
		_opt_pcurve.add_item(c[0])
	_opt_pcurve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_pcurve.focus_mode = Control.FOCUS_NONE
	_opt_pcurve.tooltip_text = "Suave: poca fuerza ya engorda · Firme: hay que apretar más"
	_opt_pcurve.item_selected.connect(func(i: int) -> void: _set_pressure("pressure_gamma", float(_CURVES[i][1])))
	r2.add_child(_opt_pcurve)

	var r3 := _pressure_row(parent, "Estabilizar")
	_slider_psmooth = HSlider.new()
	_slider_psmooth.min_value = 0
	_slider_psmooth.max_value = 90
	_slider_psmooth.step = 5
	_slider_psmooth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_psmooth.tooltip_text = "Filtra el temblor de la presión (más = grosor más uniforme)"
	r3.add_child(_slider_psmooth)
	_lbl_psmooth = _value_label(r3)
	_slider_psmooth.value_changed.connect(func(v: float) -> void:
		_lbl_psmooth.text = "%d %%" % int(v)
		_set_pressure("pressure_smoothing", v / 100.0))

	_chk_speed = CheckBox.new()
	_chk_speed.text = "Sin lápiz: simular con la velocidad"
	_chk_speed.tooltip_text = "Con ratón: rápido = fino, lento = grueso"
	_chk_speed.focus_mode = Control.FOCUS_NONE
	_chk_speed.add_theme_font_size_override("font_size", 11)
	_chk_speed.toggled.connect(func(on: bool) -> void: _set_pressure("speed_pressure", on))
	parent.add_child(_chk_speed)
	set_process(true)

func _pressure_row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(84, 0)
	l.add_theme_font_size_override("font_size", 11)
	row.add_child(l)
	_pressure_labels.append(l)
	return row

func _value_label(row: Control) -> Label:
	var l := Label.new()
	l.custom_minimum_size = Vector2(36, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 10)
	row.add_child(l)
	_pressure_labels.append(l)
	return l

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
	_slider_pmin.value = tool.pressure_min * 100.0
	_lbl_pmin.text = "%d %%" % int(round(tool.pressure_min * 100.0))
	var best := 0
	for i in _CURVES.size():
		if absf(float(_CURVES[i][1]) - tool.pressure_gamma) < absf(float(_CURVES[best][1]) - tool.pressure_gamma):
			best = i
	_opt_pcurve.select(best)
	_slider_psmooth.value = tool.pressure_smoothing * 100.0
	_lbl_psmooth.text = "%d %%" % int(round(tool.pressure_smoothing * 100.0))
	_chk_speed.button_pressed = tool.speed_pressure

## Medidor en vivo: así se ve al momento si la tableta manda presión.
func _process(_dt: float) -> void:
	if not visible or not is_instance_valid(_pressure_bar):
		return
	var tool = _get_brush_tool()
	if tool == null:
		_pressure_status.text = "Pincel no activo"
		_pressure_bar.value = 0.0
		return
	_pressure_bar.value = clampf(tool.live_pressure, 0.0, 1.0) * 100.0
	if tool.pen_detected:
		_pressure_status.text = "Lápiz: %d %%" % int(round(tool.live_pressure * 100.0))
	else:
		_pressure_status.text = "Sin lápiz (ratón)"

func _create_h_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
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
			_spin_size.value = tool.brush_width
		if is_instance_valid(_slider_size):
			_slider_size.value = tool.brush_width
		if is_instance_valid(_spin_opacity):
			_spin_opacity.value = tool.brush_opacity * 100.0
		if is_instance_valid(_slider_opacity):
			_slider_opacity.value = tool.brush_opacity * 100.0
		_update_active_style_button(tool.brush_style)
		_sync_pressure_ui(tool)
	_syncing = false

func _on_size_slider_changed(val: float) -> void:
	if _syncing: return
	_syncing = true
	_spin_size.value = val
	var tool = _get_brush_tool()
	if tool:
		tool.brush_width = val
	_syncing = false

func _on_size_spin_changed(val: float) -> void:
	if _syncing: return
	_syncing = true
	_slider_size.value = val
	var tool = _get_brush_tool()
	if tool:
		tool.brush_width = val
	_syncing = false

func _on_opacity_slider_changed(val: float) -> void:
	if _syncing: return
	_syncing = true
	_spin_opacity.value = val
	var tool = _get_brush_tool()
	if tool:
		tool.brush_opacity = val / 100.0
	_syncing = false

func _on_opacity_spin_changed(val: float) -> void:
	if _syncing: return
	_syncing = true
	_slider_opacity.value = val
	var tool = _get_brush_tool()
	if tool:
		tool.brush_opacity = val / 100.0
	_syncing = false

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

# ── Estilización y Adaptabilidad al Tema ──────────────────────────────────────

func _apply_theme() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var is_dark := true
	# El método es is_dark() (antes se preguntaba por is_dark_theme(), que no
	# existe: siempre «oscuro» y texto blanco con el tema claro).
	if tm and tm.has_method("is_dark"):
		is_dark = tm.is_dark()
	elif tm and tm.has_method("get_current_mode"):
		is_dark = (tm.get_current_mode() == "dark")

	var bg_col := Color(0.14, 0.14, 0.17, 0.98) if is_dark else Color(0.96, 0.96, 0.98, 0.98)
	var border_col := Color(1, 1, 1, 0.12) if is_dark else Color(0, 0, 0, 0.15)
	var text_col := Color(0.95, 0.95, 0.95, 1.0) if is_dark else Color(0.12, 0.12, 0.14, 1.0)
	var sec_col := Color(0.70, 0.70, 0.75, 1.0) if is_dark else Color(0.40, 0.40, 0.45, 1.0)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", sb)

	if is_instance_valid(_header_title):
		_header_title.add_theme_color_override("font_color", text_col)
	if is_instance_valid(_hint_label):
		_hint_label.add_theme_color_override("font_color", sec_col)
	for l in _pressure_labels:
		if is_instance_valid(l):
			l.add_theme_color_override("font_color", sec_col if l != _pressure_labels[0] else text_col)
	for cb in [_chk_pressure, _chk_speed]:
		if is_instance_valid(cb):
			cb.add_theme_color_override("font_color", text_col)
			cb.add_theme_color_override("font_hover_color", text_col)
			cb.add_theme_color_override("font_pressed_color", text_col)
