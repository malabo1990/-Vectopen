# =============================================================================
# VECTOPEN — PANEL DE POLÍGONOS Y FIGURAS PARAMÉTRICAS
# RUTA: res://script_gdscript/ui/panel_polygon.gd
# Diseño profesional de alta calidad, contextual por figura, adaptable a temas
# =============================================================================
class_name PanelPolygon
extends PanelContainer

signal shape_created(shape: Node)
signal closed

enum ShapeType {
	TRIANGLE,
	RECTANGLE,
	RHOMBUS,
	CIRCLE,
	POLYGON,
	STAR5,
	STAR4,
	WATERDROP
}

var current_shape: ShapeType = ShapeType.POLYGON

# Contenedores principales
var _header_title: Label
var _btn_close: Button
var _shapes_grid: HBoxContainer
var _context_params_box: VBoxContainer
var _btn_create_center: Button
var _btn_apply_selection: Button

# Botones del selector de figuras
var _shape_buttons: Dictionary = {}

# Parámetros en memoria
var _param_triangle_type: String = "equilateral"
var _param_triangle_radius: float = 0.0

var _param_rect_w: float = 120.0
var _param_rect_h: float = 80.0
var _param_rect_radius: float = 0.0
var _param_rect_independent: bool = false
var _param_rect_corners: Vector4 = Vector4.ZERO

var _param_rhombus_w: float = 120.0
var _param_rhombus_h: float = 120.0
var _param_rhombus_radius: float = 0.0

var _param_circle_mode: String = "donut"
var _param_circle_inner_ratio: float = 0.5
var _param_circle_start_angle: float = 0.0
var _param_circle_end_angle: float = 360.0

var _param_poly_sides: int = 5
var _param_poly_radius: float = 0.0

var _param_star_points: int = 5
var _param_star_ratio: float = 0.382
var _param_star_radius: float = 0.0

var _param_drop_curvature: float = 0.5

var _syncing: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(330, 0)
	_build_ui()
	_connect_events()
	_connect_theme()
	_apply_theme()
	_switch_shape_tab(ShapeType.POLYGON)

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
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_on_inspector_changed):
		ic.changed.connect(_on_inspector_changed)

func _on_inspector_changed(_props: Dictionary) -> void:
	if not is_inside_tree():
		return
	if _syncing:
		return
	var sm = get_node_or_null("/root/SelectionManager")
	var nodes: Array = []
	if sm:
		if sm.has_method("get_selected"):
			nodes = sm.get_selected()
		elif sm.has_method("get_selected_nodes"):
			nodes = sm.get_selected_nodes()
	if nodes.is_empty():
		if is_instance_valid(_btn_apply_selection):
			_btn_apply_selection.visible = false
		return

	var sel = nodes[0]
	if is_instance_valid(_btn_apply_selection):
		_btn_apply_selection.visible = true

	_syncing = true
	if sel is VectorStar:
		_param_star_points = sel.points_count
		_param_star_ratio = sel.inner_radius_ratio
		_param_star_radius = sel.corner_radius
		_switch_shape_tab(ShapeType.STAR4 if sel.points_count == 4 else ShapeType.STAR5, true)
	elif sel is VectorCircle:
		_param_circle_mode = sel.shape_mode
		_param_circle_inner_ratio = sel.inner_radius_ratio
		_param_circle_start_angle = sel.start_angle_deg
		_param_circle_end_angle = sel.end_angle_deg
		_switch_shape_tab(ShapeType.CIRCLE, true)
	elif sel is VectorRectangle:
		_param_rect_radius = sel.corner_radius
		_param_rect_w = sel.size.x
		_param_rect_h = sel.size.y
		# Leer el estado REAL de las 4 esquinas — antes este panel nunca las
		# leía, así que un rectángulo con esquinas independientes ya
		# configuradas se mostraba como si tuviera un radio uniforme.
		var corners: Vector4 = sel.get_corner_radii() if sel.has_method("get_corner_radii") else Vector4(_param_rect_radius, _param_rect_radius, _param_rect_radius, _param_rect_radius)
		_param_rect_corners = corners
		_param_rect_independent = not (
			is_equal_approx(corners.x, corners.y) and
			is_equal_approx(corners.y, corners.z) and
			is_equal_approx(corners.z, corners.w)
		)
		_switch_shape_tab(ShapeType.RECTANGLE, true)
	elif sel is VectorPolygon:
		var kind: String = sel.get_meta("shape_kind", "")
		if kind == "triangle" or (sel.sides == 3 and not sel.is_regular):
			_param_triangle_radius = sel.corner_radius
			_switch_shape_tab(ShapeType.TRIANGLE, true)
		elif kind == "rhombus" or (sel.sides == 4 and not sel.is_regular):
			_param_rhombus_radius = sel.corner_radius
			_switch_shape_tab(ShapeType.RHOMBUS, true)
		elif sel.is_regular:
			_param_poly_sides = sel.sides
			_param_poly_radius = sel.corner_radius
			_switch_shape_tab(ShapeType.POLYGON, true)
		else:
			var n_pts = sel.base_vertices.size() if not sel.base_vertices.is_empty() else sel.vertices.size()
			if n_pts == 3:
				_param_triangle_radius = sel.corner_radius
				_switch_shape_tab(ShapeType.TRIANGLE, true)
			elif n_pts == 4:
				_param_rhombus_radius = sel.corner_radius
				_switch_shape_tab(ShapeType.RHOMBUS, true)
			else:
				_param_poly_sides = n_pts
				_param_poly_radius = sel.corner_radius
				_switch_shape_tab(ShapeType.POLYGON, true)
	_syncing = false

# ── CONSTRUCCIÓN DE UI ─────────────────────────────────────────────────────────
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
	_header_title.text = "Polígonos y Figuras"
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_title.add_theme_font_size_override("font_size", 13)
	header.add_child(_header_title)

	_btn_close = Button.new()
	_btn_close.text = "✕"
	_btn_close.custom_minimum_size = Vector2(22, 22)
	_btn_close.flat = true
	_btn_close.focus_mode = Control.FOCUS_NONE
	_btn_close.pressed.connect(func():
		visible = false
		closed.emit()
	)
	header.add_child(_btn_close)

	# 2. Selector de Figuras (7 botones estilados)
	var grid_card := PanelContainer.new()
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(0, 0, 0, 0.05)
	gsb.set_corner_radius_all(8)
	gsb.content_margin_left = 6
	gsb.content_margin_right = 6
	gsb.content_margin_top = 6
	gsb.content_margin_bottom = 6
	grid_card.add_theme_stylebox_override("panel", gsb)
	root_vbox.add_child(grid_card)

	_shapes_grid = HBoxContainer.new()
	_shapes_grid.alignment = BoxContainer.ALIGNMENT_CENTER
	_shapes_grid.add_theme_constant_override("separation", 4)
	grid_card.add_child(_shapes_grid)

	_create_shape_button(ShapeType.TRIANGLE, "res://icon/UI/triangle.svg", "Triángulo (3 lados)", "triangle")
	_create_shape_button(ShapeType.RECTANGLE, "res://icon/UI/icon_cuadrado.tscn", "Rectángulo / Cuadrado", "rectangle")
	_create_shape_button(ShapeType.RHOMBUS, "res://icon/UI/paint_diamond.svg", "Rombo / Diamante", "pentagon")
	_create_shape_button(ShapeType.CIRCLE, "res://icon/UI/icon_circle.tscn", "Círculo / Anillo / Tarta", "ellipse")
	_create_shape_button(ShapeType.POLYGON, "res://icon/UI/pentagon.svg", "Polígono Regular (3-20 lados)", "pentagon")
	_create_shape_button(ShapeType.STAR5, "res://icon/UI/star.svg", "Estrella 5 Puntas", "star5")
	_create_shape_button(ShapeType.STAR4, "res://icon/UI/flare.svg", "Estrella 4 Puntas", "star4")
	_create_shape_button(ShapeType.WATERDROP, "res://icon/UI/droplet.svg", "Gota / Lágrima", "waterdrop")

	# 3. Contenedor de Parámetros Dinámicos
	_context_params_box = VBoxContainer.new()
	_context_params_box.add_theme_constant_override("separation", 8)
	root_vbox.add_child(_context_params_box)

	# 4. Separador
	var sep := HSeparator.new()
	root_vbox.add_child(sep)

	# 5. Botones de Acción
	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(actions_row)

	_btn_create_center = Button.new()
	_btn_create_center.text = "+ Crear en Centro"
	_btn_create_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_create_center.custom_minimum_size = Vector2(0, 28)
	_btn_create_center.focus_mode = Control.FOCUS_NONE
	_btn_create_center.pressed.connect(_on_create_in_center_pressed)
	actions_row.add_child(_btn_create_center)

	_btn_apply_selection = Button.new()
	_btn_apply_selection.text = "Aplicar a Selección"
	_btn_apply_selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_apply_selection.custom_minimum_size = Vector2(0, 28)
	_btn_apply_selection.focus_mode = Control.FOCUS_NONE
	_btn_apply_selection.visible = false
	_btn_apply_selection.pressed.connect(_apply_to_canvas_selection)
	actions_row.add_child(_btn_apply_selection)

func _create_shape_button(type: ShapeType, icon_path: String, tip: String, tool_alias: String) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(36, 34)
	btn.tooltip_text = tip
	btn.focus_mode = Control.FOCUS_NONE
	btn.expand_icon = true

	if icon_path.ends_with(".svg") and ResourceLoader.exists(icon_path):
		btn.icon = load(icon_path)
	elif icon_path.ends_with(".tscn") and ResourceLoader.exists(icon_path):
		var scn: PackedScene = load(icon_path)
		if scn:
			var sub_node = Node.new()
			var script_loader = load("res://scenes/ui/iconButton_subviewport_escena.gd")
			if script_loader:
				sub_node.set_script(script_loader)
				sub_node.set("boton_objetivo", btn)
				sub_node.set("escena_con_viewport", scn)
				btn.add_child(sub_node)

	btn.pressed.connect(func():
		_switch_shape_tab(type, true)
		_activate_tool(tool_alias)
	)
	_shape_buttons[type] = btn
	_shapes_grid.add_child(btn)

func _activate_tool(tool_name: String) -> void:
	var ce = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if not ce:
		var parent = get_parent()
		while parent:
			if parent.has_method("switch_tool"):
				ce = parent
				break
			parent = parent.get_parent()
	if ce and ce.has_method("switch_tool"):
		ce.switch_tool(tool_name)

func _switch_shape_tab(type: ShapeType, update_params_ui: bool = true) -> void:
	current_shape = type
	_update_shape_button_styles()
	if update_params_ui:
		_build_context_params()

func _update_shape_button_styles() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var raised_col: Color = tm.get_color(S.SURFACE_RAISED) if tm else Color(0.2, 0.4, 0.9, 0.2)
	var accent_col: Color = tm.get_color(S.ACCENT) if tm else Color(0.2, 0.5, 1.0)
	var btn_bg: Color = tm.get_color(S.BUTTON_BG) if tm else Color(0.18, 0.18, 0.22)
	var border_col: Color = tm.get_color(S.BORDER) if tm else Color(1, 1, 1, 0.1)

	for t in _shape_buttons:
		var b: Button = _shape_buttons[t]
		var is_act: bool = (t == current_shape)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(1)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4

		if is_act:
			sb.bg_color = raised_col
			sb.border_color = accent_col
		else:
			sb.bg_color = btn_bg
			sb.border_color = border_col

		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)

# ── PARÁMETROS ESPECÍFICOS POR FIGURA ─────────────────────────────────────────
func _build_context_params() -> void:
	for c in _context_params_box.get_children():
		c.queue_free()

	match current_shape:
		ShapeType.TRIANGLE:
			_build_triangle_params()
		ShapeType.RECTANGLE:
			_build_rectangle_params()
		ShapeType.RHOMBUS:
			_build_rhombus_params()
		ShapeType.CIRCLE:
			_build_circle_params()
		ShapeType.POLYGON:
			_build_polygon_params()
		ShapeType.STAR5, ShapeType.STAR4:
			_build_star_params()
		ShapeType.WATERDROP:
			_build_waterdrop_params()

func _build_triangle_params() -> void:
	var sec_title := _create_subtitle("Parámetros de Triángulo")
	_context_params_box.add_child(sec_title)

	var row_type := HBoxContainer.new()
	row_type.add_theme_constant_override("separation", 6)
	_context_params_box.add_child(row_type)

	var lbl := _create_label("Tipo:")
	row_type.add_child(lbl)

	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_item("Equilátero", 0)
	opt.add_item("Isósceles", 1)
	opt.add_item("Rectángulo (90°)", 2)
	opt.item_selected.connect(func(idx: int):
		match idx:
			0: _param_triangle_type = "equilateral"
			1: _param_triangle_type = "isosceles"
			2: _param_triangle_type = "right_angle"
		_apply_to_canvas_selection()
	)
	row_type.add_child(opt)

	var row_radius := _create_slider_row("Esquina (Radio):", 0.0, 50.0, _param_triangle_radius, " px", func(v: float):
		_param_triangle_radius = v
		_apply_to_canvas_selection()
	)
	_context_params_box.add_child(row_radius)

func _build_rectangle_params() -> void:
	var sec_title := _create_subtitle("Parámetros de Rectángulo")
	_context_params_box.add_child(sec_title)

	var row_radius := _create_slider_row("Radio Esquinas:", 0.0, 100.0, _param_rect_radius, " px", func(v: float):
		_param_rect_radius = v
		_apply_to_canvas_selection()
	)
	_context_params_box.add_child(row_radius)

	var row_toggle := HBoxContainer.new()
	_context_params_box.add_child(row_toggle)
	var chk := CheckBox.new()
	chk.text = "Esquinas Independientes (TL, TR, BR, BL)"
	chk.button_pressed = _param_rect_independent
	chk.toggled.connect(func(b: bool):
		_param_rect_independent = b
		_build_context_params()
	)
	row_toggle.add_child(chk)

	if _param_rect_independent:
		var grid_corners := GridContainer.new()
		grid_corners.columns = 2
		_context_params_box.add_child(grid_corners)
		grid_corners.add_child(_create_slider_row("TL:", 0.0, 100.0, _param_rect_corners.x, " px", func(v):
			_param_rect_corners.x = v
			_apply_to_canvas_selection()
		))
		grid_corners.add_child(_create_slider_row("TR:", 0.0, 100.0, _param_rect_corners.y, " px", func(v):
			_param_rect_corners.y = v
			_apply_to_canvas_selection()
		))
		grid_corners.add_child(_create_slider_row("BL:", 0.0, 100.0, _param_rect_corners.w, " px", func(v):
			_param_rect_corners.w = v
			_apply_to_canvas_selection()
		))
		grid_corners.add_child(_create_slider_row("BR:", 0.0, 100.0, _param_rect_corners.z, " px", func(v):
			_param_rect_corners.z = v
			_apply_to_canvas_selection()
		))

func _build_rhombus_params() -> void:
	var sec_title := _create_subtitle("Parámetros de Rombo / Diamante")
	_context_params_box.add_child(sec_title)

	var row_w := _create_slider_row("Ancho:", 20.0, 400.0, _param_rhombus_w, " px", func(v: float):
		_param_rhombus_w = v
		_apply_to_canvas_selection()
	)
	_context_params_box.add_child(row_w)

	var row_h := _create_slider_row("Alto:", 20.0, 400.0, _param_rhombus_h, " px", func(v: float):
		_param_rhombus_h = v
		_apply_to_canvas_selection()
	)
	_context_params_box.add_child(row_h)

	var row_radius := _create_slider_row("Redondeo Esquinas:", 0.0, 60.0, _param_rhombus_radius, " px", func(v: float):
		_param_rhombus_radius = v
		_apply_to_canvas_selection()
	)
	_context_params_box.add_child(row_radius)

func _build_circle_params() -> void:
	var sec_title := _create_subtitle("Parámetros de Círculo y Anillo")
	_context_params_box.add_child(sec_title)

	var row_mode := HBoxContainer.new()
	row_mode.add_theme_constant_override("separation", 6)
	_context_params_box.add_child(row_mode)

	var lbl := _create_label("Modo:")
	row_mode.add_child(lbl)

	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_item("Círculo Completo", 0)
	opt.add_item("Anillo (Donut / Ring)", 1)
	opt.add_item("Tarta / Sector (Pie)", 2)
	opt.add_item("Arco Abierto (Arc)", 3)

	var mode_keys = ["whole", "donut", "pie", "arc"]
	var cur_idx = mode_keys.find(_param_circle_mode)
	if cur_idx >= 0: opt.selected = cur_idx

	opt.item_selected.connect(func(idx: int):
		_param_circle_mode = mode_keys[idx]
		_build_context_params()
		_apply_to_canvas_selection()
	)
	row_mode.add_child(opt)

	if _param_circle_mode == "donut":
		var row_ratio := _create_slider_row("Grosor Anillo (Int.):", 5.0, 95.0, _param_circle_inner_ratio * 100.0, " %", func(v: float):
			_param_circle_inner_ratio = v / 100.0
			_apply_to_canvas_selection()
		)
		_context_params_box.add_child(row_ratio)
	elif _param_circle_mode in ["pie", "arc"]:
		var row_start := _create_slider_row("Ángulo Inicio:", 0.0, 360.0, _param_circle_start_angle, " °", func(v: float):
			_param_circle_start_angle = v
			_apply_to_canvas_selection()
		)
		_context_params_box.add_child(row_start)

		var row_end := _create_slider_row("Ángulo Fin:", 0.0, 360.0, _param_circle_end_angle, " °", func(v: float):
			_param_circle_end_angle = v
			_apply_to_canvas_selection()
		)
		_context_params_box.add_child(row_end)

func _build_polygon_params() -> void:
	var sec_title := _create_subtitle("Polígono Regular")
	_context_params_box.add_child(sec_title)

	# Fila de chips rápidos (3, 4, 5, 6, 8, 12 lados)
	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 4)
	_context_params_box.add_child(quick_row)

	var lbl_quick := _create_label("Lados:")
	quick_row.add_child(lbl_quick)

	for n in [3, 4, 5, 6, 8, 10, 12]:
		var chip := Button.new()
		chip.text = str(n)
		chip.custom_minimum_size = Vector2(26, 22)
		chip.focus_mode = Control.FOCUS_NONE
		chip.pressed.connect(func():
			_param_poly_sides = n
			_build_context_params()
			_apply_to_canvas_selection()
		)
		quick_row.add_child(chip)

	var row_sides := _create_slider_row("Número de Lados:", 3.0, 20.0, float(_param_poly_sides), "", func(v: float):
		_param_poly_sides = int(v)
		_apply_to_canvas_selection()
	)
	_context_params_box.add_child(row_sides)

	var row_radius := _create_slider_row("Redondeo Esquinas:", 0.0, 50.0, _param_poly_radius, " px", func(v: float):
		_param_poly_radius = v
		_apply_to_canvas_selection()
	)
	_context_params_box.add_child(row_radius)

func _build_star_params() -> void:
	var sec_title := _create_subtitle("Estrella Paramétrica")
	_context_params_box.add_child(sec_title)

	# Chips rápidos de puntas (3, 4, 5, 6, 8, 12)
	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 4)
	_context_params_box.add_child(quick_row)

	var lbl_quick := _create_label("Puntas:")
	quick_row.add_child(lbl_quick)

	for p in [3, 4, 5, 6, 8, 12, 16]:
		var chip := Button.new()
		chip.text = str(p)
		chip.custom_minimum_size = Vector2(26, 22)
		chip.focus_mode = Control.FOCUS_NONE
		chip.pressed.connect(func():
			_param_star_points = p
			_build_context_params()
			_apply_to_canvas_selection()
		)
		quick_row.add_child(chip)

	var row_pts := _create_slider_row("Cantidad de Puntas:", 3.0, 32.0, float(_param_star_points), "", func(v: float):
		_param_star_points = int(v)
		_apply_to_canvas_selection()
	)
	_context_params_box.add_child(row_pts)

	var row_ratio := _create_slider_row("Profundidad (Ratio Int.):", 10.0, 90.0, _param_star_ratio * 100.0, " %", func(v: float):
		_param_star_ratio = v / 100.0
		_apply_to_canvas_selection()
	)
	_context_params_box.add_child(row_ratio)

	var row_radius := _create_slider_row("Redondeo de Puntas:", 0.0, 50.0, _param_star_radius, " px", func(v: float):
		_param_star_radius = v
		_apply_to_canvas_selection()
	)
	_context_params_box.add_child(row_radius)

func _build_waterdrop_params() -> void:
	var sec_title := _create_subtitle("Parámetros de Gota / Lágrima")
	_context_params_box.add_child(sec_title)

	var row_curve := _create_slider_row("Curvatura de Cola:", 10.0, 100.0, _param_drop_curvature * 100.0, " %", func(v: float):
		_param_drop_curvature = v / 100.0
		_apply_to_canvas_selection()
	)
	_context_params_box.add_child(row_curve)

# ── HELPERS DE CONTROLES ───────────────────────────────────────────────────────
func _create_subtitle(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 11)
	var tm = get_node_or_null("/root/ThemeManager")
	if tm:
		l.add_theme_color_override("font_color", tm.get_color(tm.Slot.TEXT_SECONDARY))
	return l

func _create_label(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 11)
	var tm = get_node_or_null("/root/ThemeManager")
	if tm:
		l.add_theme_color_override("font_color", tm.get_color(tm.Slot.PANEL_TEXT))
	return l

func _create_slider_row(label_text: String, min_v: float, max_v: float, curr_v: float, suffix: String, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl := _create_label(label_text)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.value = curr_v
	slider.custom_minimum_size = Vector2(90, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = ("%.1f" if suffix == " %" or suffix == " °" else "%d") % curr_v + suffix
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 11)
	var tm = get_node_or_null("/root/ThemeManager")
	if tm:
		val_lbl.add_theme_color_override("font_color", tm.get_color(tm.Slot.PANEL_TEXT))
	row.add_child(val_lbl)

	slider.value_changed.connect(func(val: float):
		val_lbl.text = ("%.1f" if suffix == " %" or suffix == " °" else "%d") % val + suffix
		cb.call(val)
	)

	return row

func _generate_triangle_points(type: String) -> PackedVector2Array:
	match type:
		"equilateral":
			var r: float = 70.0
			return PackedVector2Array([
				Vector2(0, -r),
				Vector2(r * 0.866, r * 0.5),
				Vector2(-r * 0.866, r * 0.5)
			])
		"right_angle":
			return PackedVector2Array([
				Vector2(-60, -60),
				Vector2(60, 60),
				Vector2(-60, 60)
			])
		_: # isosceles
			return PackedVector2Array([
				Vector2(0, -70),
				Vector2(60, 70),
				Vector2(-60, 70)
			])

# ── CREACIÓN Y APLICACIÓN AL CANVAS ───────────────────────────────────────────
func _on_create_in_center_pressed() -> void:
	var artboard = _get_active_artboard()
	if not artboard:
		print("PanelPolygon: No se encontró Artboard activo para crear la figura.")
		return

	var ab_size: Vector2 = Vector2(800, 600)
	if "artboard_size" in artboard:
		ab_size = artboard.artboard_size
	var center_pos: Vector2 = ab_size / 2.0

	var dp = get_node_or_null("/root/DrawPreferences")
	var fill_c: Color = dp.fill_color if dp else Color(0.88, 0.88, 0.88, 1.0)
	var stroke_c: Color = dp.stroke_color if dp else Color(0.1, 0.1, 0.1, 1.0)
	var stroke_w: float = dp.stroke_width if dp else 2.0

	var new_node: Node = null

	match current_shape:
		ShapeType.TRIANGLE:
			var poly = VectorPolygon.new()
			poly.name = NameUtils.unique_child_name(artboard, "Triángulo")
			poly.set_meta("shape_kind", "triangle")
			poly.sides = 3
			poly.corner_radius = _param_triangle_radius
			var base_pts := _generate_triangle_points(_param_triangle_type)
			poly.set_vertices_from_center(center_pos, base_pts)
			new_node = poly

		ShapeType.RHOMBUS:
			var poly = VectorPolygon.new()
			poly.name = NameUtils.unique_child_name(artboard, "Rombo")
			poly.set_meta("shape_kind", "rhombus")
			poly.sides = 4
			poly.corner_radius = _param_rhombus_radius
			var hw = _param_rhombus_w * 0.5
			var hh = _param_rhombus_h * 0.5
			poly.set_vertices_from_center(center_pos, PackedVector2Array([
				Vector2(0, -hh),
				Vector2(hw, 0),
				Vector2(0, hh),
				Vector2(-hw, 0)
			]))
			new_node = poly

		ShapeType.RECTANGLE:
			var rect = VectorRectangle.new()
			rect.name = NameUtils.unique_child_name(artboard, "Rectángulo")
			rect.size = Vector2(_param_rect_w, _param_rect_h)
			rect.set_doc_position(DVec2.from_v2(center_pos))
			rect.corner_radius = _param_rect_radius
			if _param_rect_independent:
				rect.set_corner_radii(_param_rect_corners)
			new_node = rect

		ShapeType.CIRCLE:
			var circ = VectorCircle.new()
			circ.name = NameUtils.unique_child_name(artboard, "Círculo" if _param_circle_mode == "whole" else "Anillo")
			circ.size = Vector2(140, 140)
			circ.set_doc_position(DVec2.from_v2(center_pos))
			circ.shape_mode = _param_circle_mode
			circ.inner_radius_ratio = _param_circle_inner_ratio
			circ.start_angle_deg = _param_circle_start_angle
			circ.end_angle_deg = _param_circle_end_angle
			new_node = circ

		ShapeType.POLYGON:
			var poly = VectorPolygon.new()
			var shape_lbl = "Pentágono" if _param_poly_sides == 5 else ("Polígono %dP" % _param_poly_sides)
			poly.name = NameUtils.unique_child_name(artboard, shape_lbl)
			poly.set_doc_position(DVec2.from_v2(center_pos))
			poly.sides = _param_poly_sides
			poly.radius = 70.0
			poly.corner_radius = _param_poly_radius
			poly.is_regular = true
			new_node = poly

		ShapeType.STAR5, ShapeType.STAR4:
			var star = VectorStar.new()
			var pts_cnt := _param_star_points if current_shape == ShapeType.STAR5 else 4
			star.name = NameUtils.unique_child_name(artboard, "Estrella %dP" % pts_cnt)
			star.size = Vector2(140, 140)
			star.points_count = pts_cnt
			star.inner_radius_ratio = _param_star_ratio
			star.corner_radius = _param_star_radius
			star.set_doc_position(DVec2.from_v2(center_pos))
			new_node = star

		ShapeType.WATERDROP:
			var drop_tool_script = load("res://script_gdscript/tools/WaterDropTool.gd")
			if drop_tool_script:
				var drop_tool = drop_tool_script.new()
				if "artboard" in drop_tool:
					drop_tool.artboard = artboard
				if drop_tool.has_method("create_at_center"):
					drop_tool.create_at_center()
					return

	if new_node and "fill_color" in new_node:
		new_node.fill_color = fill_c
		new_node.stroke_color = stroke_c
		new_node.stroke_width = stroke_w
		artboard.add_child(new_node)
		new_node.owner = artboard
		shape_created.emit(new_node)

		var hm = get_node_or_null("/root/HistoryManager")
		if hm and hm.has_method("record_create"):
			hm.record_create(new_node)

		var sm = get_node_or_null("/root/SelectionManager")
		if sm and sm.has_method("set_selection"):
			sm.set_selection([new_node])

func _apply_to_canvas_selection() -> void:
	var sm = get_node_or_null("/root/SelectionManager")
	var nodes: Array = []
	if sm:
		if sm.has_method("get_selected"):
			nodes = sm.get_selected()
		elif sm.has_method("get_selected_nodes"):
			nodes = sm.get_selected_nodes()
	if nodes.is_empty():
		return

	# Guard de re-entrancia (mismo flag que ya usa _on_inspector_changed en
	# la dirección contraria): cada ic.apply() de abajo emite `changed` al
	# terminar, que dispara _on_inspector_changed() — SIN este guard, esa
	# re-sincronización relee la figura A MITAD de aplicar varias props
	# seguidas (ej. "sides" antes que "corner_radius") y pisa los _param_*
	# de ESTE panel con el valor todavía viejo, así que la prop siguiente
	# se aplica con un valor corrompido (bug real, encontrado escribiendo
	# el test de regresión de esta misma ronda).
	_syncing = true

	var ic = get_node_or_null("/root/InspectorCore")
	var has_ic: bool = ic and ic.has_method("apply_multi")
	var sel = nodes[0]
	# OJO EN TODAS LAS RAMAS DE ABAJO:
	# 1) Nunca escribir el valor a mano ANTES de llamar a InspectorCore —
	#    `apply()`/`apply_multi()` deciden si hay algo que undo-ar
	#    comparando el valor VIEJO (leído recién ahí adentro) contra el
	#    nuevo; si ya lo escribimos nosotros acá, "viejo" y "nuevo" quedan
	#    iguales y no se registra nada en el historial (bug real
	#    encontrado en las 4 ramas: Star/Circle/Rectángulo/Polígono
	#    regular tenían este orden invertido — "Aplicar a Selección"
	#    nunca fue deshacible con Ctrl+Z para NINGUNA figura del panel).
	# 2) `apply_multi(dict, ...)` en vez de varios `apply()` sueltos — con
	#    2-4 `apply()` seguidos, cada uno arma SU PROPIA acción de undo, así
	#    que un solo click de este botón quedaba partido en 2-4 Ctrl+Z
	#    distintos. `apply_multi` agrupa todas las props en UN solo paso.
	# El escrito directo queda SOLO como fallback real para cuando
	# InspectorCore no está disponible.
	if sel is VectorStar:
		if has_ic:
			ic.apply_multi({
				"points_count": _param_star_points,
				"inner_radius_ratio": _param_star_ratio,
				"corner_radius": _param_star_radius,
			}, "Polígono · estrella")
		else:
			sel.points_count = _param_star_points
			sel.inner_radius_ratio = _param_star_ratio
			sel.corner_radius = _param_star_radius
			if sel.has_method("queue_redraw"):
				sel.queue_redraw()
	elif sel is VectorCircle:
		if has_ic:
			ic.apply_multi({
				"shape_mode": _param_circle_mode,
				"inner_radius_ratio": _param_circle_inner_ratio,
				"start_angle_deg": _param_circle_start_angle,
				"end_angle_deg": _param_circle_end_angle,
			}, "Polígono · círculo")
		else:
			sel.shape_mode = _param_circle_mode
			sel.inner_radius_ratio = _param_circle_inner_ratio
			sel.start_angle_deg = _param_circle_start_angle
			sel.end_angle_deg = _param_circle_end_angle
			if sel.has_method("queue_redraw"):
				sel.queue_redraw()
	elif sel is VectorRectangle:
		if _param_rect_independent:
			# Esquinas independientes: antes esto NUNCA se aplicaba a una
			# selección existente (solo funcionaba al crear la figura) — cada
			# esquina es una prop reconocida por InspectorCore (mismo Vector4
			# tl/tr/br/bl que VectorRectangle.set_corner_radii), así que se
			# aplica igual que cualquier otra prop: con undo real y a TODA la
			# selección, no solo al primer nodo.
			if has_ic:
				ic.apply_multi({
					"corner_tl": _param_rect_corners.x,
					"corner_tr": _param_rect_corners.y,
					"corner_br": _param_rect_corners.z,
					"corner_bl": _param_rect_corners.w,
				}, "Polígono · esquinas independientes")
			else:
				sel.set_corner_radii(_param_rect_corners)
				if sel.has_method("queue_redraw"):
					sel.queue_redraw()
		else:
			if ic and ic.has_method("apply"):
				ic.apply("corner_radius", _param_rect_radius)
			else:
				sel.corner_radius = _param_rect_radius
	elif sel is VectorPolygon:
		match current_shape:
			ShapeType.TRIANGLE:
				var pts = _generate_triangle_points(_param_triangle_type)
				_apply_polygon_preset("triangle", 3, pts, _param_triangle_radius)
			ShapeType.RHOMBUS:
				var hw = _param_rhombus_w * 0.5
				var hh = _param_rhombus_h * 0.5
				var pts = PackedVector2Array([
					Vector2(0, -hh),
					Vector2(hw, 0),
					Vector2(0, hh),
					Vector2(-hw, 0)
				])
				_apply_polygon_preset("rhombus", 4, pts, _param_rhombus_radius)
			_:
				if has_ic:
					ic.apply_multi({
						"sides": _param_poly_sides,
						"corner_radius": _param_poly_radius,
					}, "Polígono · regular")
				else:
					sel.is_regular = true
					sel.sides = _param_poly_sides
					sel.corner_radius = _param_poly_radius
					if sel.has_method("queue_redraw"):
						sel.queue_redraw()

	_syncing = false

## Aplica un preset de figura NO regular (Triángulo/Rombo) a TODOS los
## VectorPolygon de la selección actual — no solo `nodes[0]`.
## `InspectorCore.apply()` no sirve acá: su escritor de "sides" fuerza
## `is_regular = true` como efecto secundario (pensado para el caso de
## Polígono Regular), justo lo contrario de lo que necesita un Triángulo/
## Rombo (`base_vertices` + `is_regular = false`); y no hay ninguna prop
## genérica para `base_vertices` ni para el meta `shape_kind`. Por eso este
## helper arma su propia acción de undo/redo, mismo patrón que
## `InspectorCore.apply()` (register_action + add_do + add_undo + commit).
func _apply_polygon_preset(kind: String, sides: int, base_pts: PackedVector2Array, corner_r: float) -> void:
	var sm = get_node_or_null("/root/SelectionManager")
	var nodes: Array = []
	if sm:
		if sm.has_method("get_selected"):
			nodes = sm.get_selected()
		elif sm.has_method("get_selected_nodes"):
			nodes = sm.get_selected_nodes()

	var targets: Array = []
	for n in nodes:
		if n is VectorPolygon:
			targets.append(n)
	if targets.is_empty():
		return

	var recs := []
	for s in targets:
		recs.append({
			"s": s,
			"before_kind": s.get_meta("shape_kind", ""),
			"before_sides": s.sides,
			"before_regular": s.is_regular,
			"before_base": s.base_vertices.duplicate(),
			"before_radius": s.corner_radius,
		})

	var write_state := func(s: VectorPolygon, s_kind: String, s_sides: int, s_regular: bool, s_base: PackedVector2Array, s_radius: float) -> void:
		if not is_instance_valid(s):
			return
		s.set_meta("shape_kind", s_kind)
		# is_regular ANTES que sides: el setter de "sides" recalcula la figura
		# regular si is_regular ya está en true — hay que dejarlo en false
		# primero para no pisar base_vertices con un polígono regular.
		s.is_regular = s_regular
		s.sides = s_sides
		s.base_vertices = s_base.duplicate()
		# corner_radius AL FINAL: su setter (_recalculate_custom_polygon) es
		# quien recalcula `vertices` real a partir de `base_vertices` — tiene
		# que correr después de que base_vertices ya tenga el valor final.
		s.corner_radius = s_radius

	var do_fn := func() -> void:
		for r in recs:
			write_state.call(r["s"], kind, sides, false, base_pts, corner_r)
		_notify_shapes_changed()
	var undo_fn := func() -> void:
		for r in recs:
			write_state.call(r["s"], r["before_kind"], r["before_sides"], r["before_regular"], r["before_base"], r["before_radius"])
		_notify_shapes_changed()

	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Polígono · %s" % kind)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()

## Mismas notificaciones que InspectorCore._post_write() tras escribir una
## prop — refresca el Inspector y el Bounding Box (éste escucha
## `object_style_changed`, ver scenes/canvas/bounding_box.gd).
func _notify_shapes_changed() -> void:
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("object_style_changed"):
		if ge.has_method("emit_safe"):
			ge.emit_safe("object_style_changed")
		else:
			ge.object_style_changed.emit()
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and ic.has_method("current_props"):
		ic.changed.emit(ic.current_props())

func _get_active_artboard() -> Node:
	var ab_mgr = get_tree().get_first_node_in_group("artboard_manager") if get_tree() else null
	if ab_mgr and ab_mgr.has_method("get_active_artboard"):
		var ab = ab_mgr.get_active_artboard()
		if ab: return ab
	var all_ab = get_tree().get_nodes_in_group("artboard") if get_tree() else []
	if not all_ab.is_empty():
		return all_ab[0]
	return null

# ── ADAPTACIÓN DE TEMA ────────────────────────────────────────────────────────
func _apply_theme() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if not tm:
		return
	var S = tm.Slot
	var surface_col: Color = tm.get_color(S.PANEL_SURFACE)
	var border_col: Color = tm.get_color(S.BORDER)
	var text_col: Color = tm.get_color(S.PANEL_TEXT)
	var text_sec: Color = tm.get_color(S.TEXT_SECONDARY)
	var is_dark: bool = tm.is_dark()

	# 1. Contenedor Flotante
	var sb := StyleBoxFlat.new()
	sb.bg_color = surface_col
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.25 if is_dark else 0.08)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", sb)

	# 2. Textos de Cabecera
	if _header_title:
		_header_title.add_theme_color_override("font_color", text_col)
	if _btn_close:
		_btn_close.add_theme_color_override("font_color", text_sec)
		_btn_close.add_theme_color_override("font_hover_color", tm.get_color(S.NEGATIVE))

	# 3. Botones de Acción
	if _btn_create_center:
		if tm.has_method("style_button"):
			tm.style_button(_btn_create_center, true, 6)
		else:
			_btn_create_center.add_theme_font_size_override("font_size", 11)

	if _btn_apply_selection:
		if tm.has_method("style_button"):
			tm.style_button(_btn_apply_selection, false, 6)
		else:
			_btn_apply_selection.add_theme_font_size_override("font_size", 11)

	_update_shape_button_styles()
