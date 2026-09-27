# =============================================================================
# VECTOPEN — INSPECTOR LATERAL DOCKEADO (DOCKED INSPECTOR)
# RUTA: res://script_gdscript/ui/docked_inspector.gd
# Modos: Modern Panel (Figma UI3 / Apple Style) | Professional Panel (Affinity)
# Conectado a InspectorCore como fuente unica de verdad para la seleccion y Undo
# =============================================================================
class_name DockedInspector
extends PanelContainer

signal closed()

const VectorBooleanScript = preload("res://script_gdscript/shapes/VectorBoolean.gd")


# ── Botón Swatch personalizado con previsualización para Modern UI ──
class ColorSwatchButton extends Button:
	signal color_changed(new_color: Color)
	var color: Color = Color.WHITE:
		set(val):
			color = val
			queue_redraw()

	func _init(initial_color: Color = Color.WHITE) -> void:
		color = initial_color
		custom_minimum_size = Vector2(24, 24)
		focus_mode = Control.FOCUS_NONE
		flat = true

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		if color.a < 1.0:
			draw_rect(r, Color(0.85, 0.85, 0.87, 1.0), true)
		draw_rect(r, color, true)
		draw_rect(r, Color(0, 0, 0, 0.2), false, 1.0)

# ── Popover de Color (Panel completo de Smart UI) ──
var _color_popover: PanelContainer
var _color_popover_header_title: Label
var _pickr_instance: GestorColor
var _active_color_target: String = ""

# ── Nodos de cabecera ──
var lbl_title: Label
var lbl_selection: Label
var mode_selector: Control

# ── Contenedor de contenido con Scroll ──
var scroll_container: ScrollContainer
var content_container: VBoxContainer

# ── Sección Lienzo / Página (cuando no hay selección) ──
var sec_canvas: VBoxContainer
var picker_canvas_bg: Button
var lbl_canvas_hex: Label
var lbl_canvas_size: Label

# ── Sección Alineación (Barra segmentada de 8 botones) ──
var sec_align: VBoxContainer
var align_container: HBoxContainer
var _boolean_header: Control = null
var _boolean_bar_panel: PanelContainer
var boolean_container: VBoxContainer


# ── Sección Transformación (Cuadrícula compacta de 2 columnas) ──
var transform_panel: TransformPanel

# ── Sección Apariencia (Opacidad y visibilidad) ──
var sec_appearance: VBoxContainer
var spin_opacity: NumericField
var btn_toggle_visibility: Button
var _current_item_visible: bool = true

# ── Sección Tipografía (Texto contextual) ──
var sec_typography: VBoxContainer
var opt_font_family: OptionButton
var spin_font_size: NumericField
var opt_font_weight: OptionButton
var btn_align_left: Button
var btn_align_center: Button
var btn_align_right: Button

# ── Sección Relleno (Fill) ──
var sec_fill: VBoxContainer
var picker_fill: Button
var lbl_fill_hex: Label

# ── Sección Trazo (Stroke) ──
var sec_stroke: VBoxContainer
var picker_stroke: Button
var spin_stroke_width: NumericField
var opt_stroke_align: OptionButton

# ── Sección Efectos ──
var sec_effects: VBoxContainer
var btn_shadow_toggle: Button
var _has_shadow: bool = false

# ── Sección Exportación ──
var sec_export: VBoxContainer
var opt_export_format: OptionButton
var btn_export_selection: Button

# ── Secciones Paramétricas (Secciones 15, 16, 17) ──
var sec_parametric_circle: VBoxContainer
var opt_circle_mode: OptionButton
var spin_circle_start_angle: NumericField
var spin_circle_end_angle: NumericField
var spin_circle_inner_radius: NumericField

var sec_parametric_star: VBoxContainer
var spin_star_points: NumericField
var spin_star_inner_radius: NumericField
var spin_star_corner_radius: NumericField

var sec_parametric_rect: VBoxContainer
var spin_rect_corner_radius: NumericField

# ── Sección Modelo 3D ──
var sec_3d_model: VBoxContainer
var lbl_3d_path: Label
var btn_3d_change_file: Button
var spin_3d_rot_x: NumericField
var spin_3d_rot_y: NumericField
var spin_3d_rot_z: NumericField
var spin_3d_distance: NumericField
var spin_3d_fov: NumericField
var spin_3d_light_energy: NumericField
var btn_3d_reset_view: Button

# ── Estado de sincronización y tema ──
var _syncing: bool = false
var _is_dense: bool = false
var _has_selection: bool = false

# Tokens de color estándar (Figma UI3 neutral)
var _C_BG_INPUT := Color(0.945, 0.945, 0.961, 1.0) # #f1f1f5
var _C_BORDER_INPUT := Color(0.86, 0.86, 0.88, 1.0)
var _C_TEXT := Color(0.12, 0.12, 0.15, 1.0)
var _C_MUTED := Color(0.50, 0.50, 0.55, 1.0)
var _C_ACCENT := Color(0.04, 0.52, 1.0, 1.0)

var _pill_panels: Array[PanelContainer] = []
var _chip_buttons: Array[Button] = []
var _align_bar_panel: PanelContainer = null

func _ready() -> void:
	_pull_theme_tokens()
	_setup_panel_style()
	_build_ui()
	_connect_inspector_core()
	_update_from_inspector()
	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(_on_theme_changed)

func _pull_theme_tokens() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var is_dark := false
	if tm:
		if tm.has_method("is_dark"):
			is_dark = tm.is_dark()
		elif tm.has_method("get_mode"):
			is_dark = tm.get_mode() == "dark"
		elif "current_mode" in tm:
			is_dark = tm.current_mode == "dark"

	if tm and "Slot" in tm:
		var S = tm.Slot
		_C_BG_INPUT = tm.get_color(S.INPUT_BG)
		_C_BORDER_INPUT = tm.get_color(S.INPUT_BORDER)
		_C_TEXT = tm.get_color(S.PANEL_TEXT)
		_C_MUTED = tm.get_color(S.TEXT_SECONDARY)
		_C_ACCENT = tm.get_color(S.ACCENT)
	elif is_dark:
		_C_BG_INPUT = Color(0.173, 0.173, 0.18, 1.0) # #2c2c2e
		_C_BORDER_INPUT = Color(1.0, 1.0, 1.0, 0.12)
		_C_TEXT = Color(0.96, 0.96, 0.97, 1.0)
		_C_MUTED = Color(0.58, 0.58, 0.62, 1.0)
		_C_ACCENT = Color(0.35, 0.50, 0.68, 1.0)
	else:
		_C_BG_INPUT = Color(0.945, 0.945, 0.961, 1.0) # #f1f1f5
		_C_BORDER_INPUT = Color(0.86, 0.86, 0.88, 1.0)
		_C_TEXT = Color(0.12, 0.12, 0.15, 1.0)
		_C_MUTED = Color(0.50, 0.50, 0.55, 1.0)
		_C_ACCENT = Color(0.35, 0.50, 0.68, 1.0)

func _setup_panel_style() -> void:
	custom_minimum_size = Vector2(264, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	z_index = 50

	var tm = get_node_or_null("/root/ThemeManager")
	var bg_col := Color(0.98, 0.98, 0.99, 1.0) if _C_TEXT.v < 0.5 else Color(0.12, 0.12, 0.13, 1.0)
	var border_col := _C_BORDER_INPUT
	if tm and "Slot" in tm:
		bg_col = tm.get_color(tm.Slot.PANEL_BG)
		border_col = tm.get_color(tm.Slot.BORDER)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_width_left = 1
	sb.border_color = border_col
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)

func _on_theme_changed(_mode: String = "") -> void:
	_pull_theme_tokens()
	_setup_panel_style()
	if is_instance_valid(lbl_title):
		lbl_title.add_theme_color_override("font_color", _C_TEXT)
	if is_instance_valid(lbl_selection):
		lbl_selection.add_theme_color_override("font_color", _C_MUTED)
	if is_instance_valid(lbl_fill_hex):
		lbl_fill_hex.add_theme_color_override("font_color", _C_TEXT)
	if is_instance_valid(lbl_canvas_hex):
		lbl_canvas_hex.add_theme_color_override("font_color", _C_TEXT)
	if is_instance_valid(lbl_canvas_size):
		lbl_canvas_size.add_theme_color_override("font_color", _C_MUTED)
	if is_instance_valid(spin_opacity):
		_style_spinbox(spin_opacity)
	if is_instance_valid(spin_stroke_width):
		_style_spinbox(spin_stroke_width)
	if is_instance_valid(opt_stroke_align):
		_style_option_button(opt_stroke_align)
	if is_instance_valid(opt_export_format):
		_style_option_button(opt_export_format)
	if is_instance_valid(opt_circle_mode):
		_style_option_button(opt_circle_mode)
	if is_instance_valid(opt_font_family):
		_style_option_button(opt_font_family)
	if is_instance_valid(opt_font_weight):
		_style_option_button(opt_font_weight)
	if is_instance_valid(spin_3d_rot_x): _style_spinbox(spin_3d_rot_x)
	if is_instance_valid(spin_3d_rot_y): _style_spinbox(spin_3d_rot_y)
	if is_instance_valid(spin_3d_rot_z): _style_spinbox(spin_3d_rot_z)
	if is_instance_valid(spin_3d_distance): _style_spinbox(spin_3d_distance)
	if is_instance_valid(spin_3d_fov): _style_spinbox(spin_3d_fov)
	if is_instance_valid(spin_3d_light_energy): _style_spinbox(spin_3d_light_energy)
	if is_instance_valid(lbl_3d_path): lbl_3d_path.add_theme_color_override("font_color", _C_TEXT)
	if is_instance_valid(align_container):
		for btn in align_container.get_children():
			if btn is Button:
				_update_flat_icon_button_theme(btn)
	if is_instance_valid(_align_bar_panel):
		var bar_sb := StyleBoxFlat.new()
		bar_sb.bg_color = _C_BG_INPUT
		bar_sb.set_corner_radius_all(6)
		bar_sb.set_content_margin_all(2)
		_align_bar_panel.add_theme_stylebox_override("panel", bar_sb)
	if is_instance_valid(_boolean_header):
		_boolean_header.add_theme_color_override("font_color", _C_MUTED)
	if is_instance_valid(_boolean_bar_panel):
		var bool_sb := StyleBoxFlat.new()
		bool_sb.bg_color = _C_BG_INPUT
		bool_sb.border_width_left = 1
		bool_sb.border_width_right = 1
		bool_sb.border_width_top = 1
		bool_sb.border_width_bottom = 1
		bool_sb.border_color = _C_BORDER_INPUT
		bool_sb.set_corner_radius_all(6)
		bool_sb.content_margin_left = 6
		bool_sb.content_margin_right = 6
		bool_sb.content_margin_top = 5
		bool_sb.content_margin_bottom = 5
		_boolean_bar_panel.add_theme_stylebox_override("panel", bool_sb)
	if is_instance_valid(boolean_container):
		for row in boolean_container.get_children():
			if row is BoxContainer:
				for btn in row.get_children():
					if btn is Button:
						_update_flat_icon_button_theme(btn)
	for pc in _pill_panels:
		if is_instance_valid(pc):
			_style_input_pill(pc)
	for btn in _chip_buttons:
		if is_instance_valid(btn):
			_update_chip_button_theme(btn)
	if is_instance_valid(picker_canvas_bg):
		_style_color_picker(picker_canvas_bg)
	if is_instance_valid(picker_fill):
		_style_color_picker(picker_fill)
	if is_instance_valid(picker_stroke):
		_style_color_picker(picker_stroke)
	if is_instance_valid(_color_popover):
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.98, 0.98, 0.99, 1.0) if _C_TEXT.v < 0.5 else Color(0.14, 0.14, 0.15, 1.0)
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(1)
		sb.border_color = _C_BORDER_INPUT
		sb.shadow_color = Color(0, 0, 0, 0.28)
		sb.shadow_size = 14
		sb.shadow_offset = Vector2(0, 4)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		_color_popover.add_theme_stylebox_override("panel", sb)

func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root_vbox)

	# ── 1. CABECERA LIMPIA (SIN SELECTOR DE MODO DUPLICADO) ──
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	root_vbox.add_child(header)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	header.add_child(title_row)

	lbl_title = Label.new()
	lbl_title.text = "Inspector"
	lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_title.add_theme_font_size_override("font_size", 12)
	lbl_title.add_theme_color_override("font_color", _C_TEXT)
	title_row.add_child(lbl_title)

	# El selector de modo se mantiene instanciado para compatibilidad de tests,
	# pero invisible y sin ocupar espacio en el panel de propiedades (se aloja en TopBar)
	var selector_script = preload("res://script_gdscript/ui/ui_mode_selector.gd")
	mode_selector = selector_script.new()
	mode_selector.visible = false
	add_child(mode_selector)

	lbl_selection = Label.new()
	lbl_selection.text = "No selection"
	lbl_selection.add_theme_font_size_override("font_size", 10)
	lbl_selection.add_theme_color_override("font_color", _C_MUTED)
	header.add_child(lbl_selection)

	var sep1 := HSeparator.new()
	sep1.add_theme_constant_override("separation", 6)
	_style_separator(sep1)
	root_vbox.add_child(sep1)

	# ── 2. CONTENEDOR CON SCROLL PARA SECCIONES ──
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll_container)

	content_container = VBoxContainer.new()
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.add_theme_constant_override("separation", 6)
	scroll_container.add_child(content_container)

	# ── SECCION VACÍA: PROPIEDADES DE LIENZO / PÁGINA (CUANDO NO HAY SELECCIÓN) ──
	_build_canvas_section()

	# ── SECCION A: ALINEACION (BARRA SEGMENTADA INTEGRADA DE 8 BOTONES) ──
	_build_align_section()

	# ── SECCION B: TRANSFORM COMPACTO (FIGMA 2-COLUMN GRID) ──
	transform_panel = TransformPanel.new()
	transform_panel.name = "DockedTransformPanel"
	content_container.add_child(transform_panel)

	# ── SECCION C: APARIENCIA (OPACIDAD Y VISIBILIDAD) ──
	_build_appearance_section()

	# ── SECCION D: TIPOGRAFÍA (TEXTO CONTEXTUAL) ──
	_build_typography_section()

	# ── SECCIONES PARAMÉTRICAS (CÍRCULO, ESTRELLA, ESQUINAS) ──
	_build_parametric_circle_section()
	_build_parametric_star_section()
	_build_parametric_rect_section()
	_build_parametric_polygon_section()
	_build_3d_model_section()

	# ── SECCION E: RELLENO (FILL - FILA COMPACTA) ──
	_build_fill_section()

	# ── SECCION F: TRAZO (STROKE - FILA COMPACTA) ──
	_build_stroke_section()

	# ── SECCION G: EFECTOS (SHADOW - FILA COMPACTA) ──
	_build_effects_section()

	# ── SECCION H: EXPORTAR (SOLO CUANDO HAY ELEMENTO SELECCIONADO) ──
	_build_export_section()

func _create_section_header(title: String, on_add: Callable = Callable()) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = tr(title)
	lbl.set_meta("header_title_key", title)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", _C_MUTED)
	hbox.add_child(lbl)

	if on_add.is_valid():
		var btn_add := _create_chip_button("+", "%s %s" % [tr("New"), tr(title).to_lower()], Vector2(20, 20))
		btn_add.pressed.connect(on_add)
		hbox.add_child(btn_add)

	return hbox

func _add_section_header(title: String, on_add: Callable = Callable()) -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	_style_separator(sep)
	content_container.add_child(sep)
	content_container.add_child(_create_section_header(title, on_add))

func _style_separator(sep: HSeparator) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _C_BORDER_INPUT
	sb.border_width_top = 1
	sb.border_color = _C_BORDER_INPUT
	sep.add_theme_stylebox_override("separator", sb)

# ── PROPIEDADES DE PÁGINA (ESTADO "NO SELECTION") ──
func _build_canvas_section() -> void:
	sec_canvas = VBoxContainer.new()
	sec_canvas.add_theme_constant_override("separation", 8)
	content_container.add_child(sec_canvas)

	sec_canvas.add_child(_create_section_header("PAGE"))

	var row_bg := HBoxContainer.new()
	row_bg.add_theme_constant_override("separation", 6)
	sec_canvas.add_child(row_bg)

	picker_canvas_bg = ColorSwatchButton.new(Color.WHITE)
	_style_color_picker(picker_canvas_bg)
	picker_canvas_bg.color_changed.connect(_on_canvas_bg_changed)
	picker_canvas_bg.pressed.connect(func(): _open_color_popover("canvas", picker_canvas_bg))
	row_bg.add_child(picker_canvas_bg)

	lbl_canvas_hex = Label.new()
	lbl_canvas_hex.text = "#FFFFFF"
	lbl_canvas_hex.add_theme_font_size_override("font_size", 11)
	lbl_canvas_hex.add_theme_color_override("font_color", _C_TEXT)
	lbl_canvas_hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_bg.add_child(_wrap_input_pill(lbl_canvas_hex))

	var row_dim := HBoxContainer.new()
	row_dim.add_theme_constant_override("separation", 6)
	sec_canvas.add_child(row_dim)

	lbl_canvas_size = Label.new()
	lbl_canvas_size.text = "1920 × 1080 px"
	lbl_canvas_size.add_theme_font_size_override("font_size", 10)
	lbl_canvas_size.add_theme_color_override("font_color", _C_MUTED)
	lbl_canvas_size.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_dim.add_child(_wrap_input_pill(lbl_canvas_size))

	var hint_lbl := Label.new()
	hint_lbl.text = "Selecciona un objeto para editar sus propiedades."
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.add_theme_font_size_override("font_size", 9)
	hint_lbl.add_theme_color_override("font_color", _C_MUTED)
	sec_canvas.add_child(hint_lbl)

# ── SECCIÓN ALINEACIÓN (8 BOTONES SIN BORDES PESADOS) ──
func _build_align_section() -> void:
	sec_align = VBoxContainer.new()
	sec_align.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_align)

	sec_align.add_child(_create_section_header("ALIGNMENT"))

	# Contenedor tipo segmented control integrado
	_align_bar_panel = PanelContainer.new()
	var bar_sb := StyleBoxFlat.new()
	bar_sb.bg_color = _C_BG_INPUT
	bar_sb.set_corner_radius_all(6)
	bar_sb.set_content_margin_all(2)
	_align_bar_panel.add_theme_stylebox_override("panel", bar_sb)
	sec_align.add_child(_align_bar_panel)

	align_container = HBoxContainer.new()
	align_container.add_theme_constant_override("separation", 1)
	align_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_align_bar_panel.add_child(align_container)

	var aligns := [
		{"key": "left", "tooltip": "Alinear a la izquierda", "icon": "res://icon/UI/align_left_pro.svg", "fallback": "⇤"},
		{"key": "center_h", "tooltip": "Alinear al centro horizontal", "icon": "res://icon/UI/align_center_h_pro.svg", "fallback": "⇥⇤"},
		{"key": "right", "tooltip": "Alinear a la derecha", "icon": "res://icon/UI/align_right_pro.svg", "fallback": "⇥"},
		{"key": "top", "tooltip": "Alinear arriba", "icon": "res://icon/UI/align_top_pro.svg", "fallback": "⤒"},
		{"key": "middle", "tooltip": "Alinear al centro vertical", "icon": "res://icon/UI/align_center_v_pro.svg", "fallback": "⤓⤒"},
		{"key": "bottom", "tooltip": "Alinear abajo", "icon": "res://icon/UI/align_bottom_pro.svg", "fallback": "⤓"},
		{"key": "dist_h", "tooltip": "Distribuir horizontalmente", "icon": "res://icon/UI/distribute_h_pro.svg", "fallback": "⇹"},
		{"key": "dist_v", "tooltip": "Distribuir verticalmente", "icon": "res://icon/UI/distribute_v_pro.svg", "fallback": "⇳"}
	]

	for a in aligns:
		var btn := _create_flat_icon_button(a["fallback"], a["tooltip"], Vector2(28, 22))
		if ResourceLoader.exists(a["icon"]):
			var raw_tex: Texture2D = load(a["icon"])
			var tm = get_node_or_null("/root/ThemeManager")
			if tm and tm.has_method("make_white_icon"):
				btn.icon = tm.make_white_icon(raw_tex, 16)
			else:
				btn.icon = raw_tex
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
			# Native 16px: stretching made glyphs sit at different heights
			btn.expand_icon = false
			btn.text = ""
		var k: String = a["key"]
		btn.pressed.connect(func(): _on_align_pressed(k))
		align_container.add_child(btn)

	# ── Sub-barra Booleana (Union, Subtract, Intersect, Exclude / Actions) ──
	_boolean_header = _create_section_header("BOOLEAN OPERATIONS")
	sec_align.add_child(_boolean_header)

	_boolean_bar_panel = PanelContainer.new()
	var bool_sb := StyleBoxFlat.new()
	bool_sb.bg_color = _C_BG_INPUT
	bool_sb.border_width_left = 1
	bool_sb.border_width_right = 1
	bool_sb.border_width_top = 1
	bool_sb.border_width_bottom = 1
	bool_sb.border_color = _C_BORDER_INPUT
	bool_sb.set_corner_radius_all(6)
	bool_sb.content_margin_left = 6
	bool_sb.content_margin_right = 6
	bool_sb.content_margin_top = 5
	bool_sb.content_margin_bottom = 5
	_boolean_bar_panel.add_theme_stylebox_override("panel", bool_sb)
	sec_align.add_child(_boolean_bar_panel)

	boolean_container = VBoxContainer.new()
	boolean_container.add_theme_constant_override("separation", 4)
	boolean_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boolean_bar_panel.add_child(boolean_container)

	var row_ops := HBoxContainer.new()
	row_ops.alignment = BoxContainer.ALIGNMENT_CENTER
	row_ops.add_theme_constant_override("separation", 4)
	boolean_container.add_child(row_ops)

	var row_acts := HBoxContainer.new()
	row_acts.alignment = BoxContainer.ALIGNMENT_CENTER
	row_acts.add_theme_constant_override("separation", 4)
	boolean_container.add_child(row_acts)

	var bool_ops_primary := [
		{"key": "union", "tooltip": "Unión Booleana (No destructiva)", "icon": "res://icon/UI/boolean_union.svg", "fallback": "⋃"},
		{"key": "subtract", "tooltip": "Sustracción Booleana (No destructiva)", "icon": "res://icon/UI/boolean_subtract.svg", "fallback": "−"},
		{"key": "intersect", "tooltip": "Intersección Booleana (No destructiva)", "icon": "res://icon/UI/boolean_intersect.svg", "fallback": "⋂"},
		{"key": "exclude", "tooltip": "Exclusión Booleana / XOR (No destructiva)", "icon": "res://icon/UI/boolean_exclude.svg", "fallback": "⨂"}
	]

	var bool_ops_secondary := [
		{"key": "shape_builder", "tooltip": "Shape Builder (Smart Fusion Shift+M)", "icon": "res://icon/UI/shape_builder.svg", "fallback": "✦"},
		{"key": "flatten", "tooltip": "Aplanar a Curvas Bézier (Convert to Curves)", "icon": "res://icon/UI/boolean_flatten.svg", "fallback": "⤹"},
		{"key": "release", "tooltip": "Liberar Componentes (Desagrupar Booleano)", "icon": "res://icon/UI/boolean_release.svg", "fallback": "⛶"}
	]

	for b in bool_ops_primary:
		var btn := _create_flat_icon_button(b["fallback"], b["tooltip"], Vector2(34, 26))
		if ResourceLoader.exists(b["icon"]):
			var raw_tex: Texture2D = load(b["icon"])
			var tm = get_node_or_null("/root/ThemeManager")
			if tm and tm.has_method("make_white_icon"):
				btn.icon = tm.make_white_icon(raw_tex, 16)
			else:
				btn.icon = raw_tex
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
			btn.expand_icon = false
			btn.text = ""
		var k: String = b["key"]
		btn.pressed.connect(func(): _on_boolean_action_pressed(k))
		row_ops.add_child(btn)

	for b in bool_ops_secondary:
		var btn := _create_flat_icon_button(b["fallback"], b["tooltip"], Vector2(34, 26))
		if ResourceLoader.exists(b["icon"]):
			var raw_tex: Texture2D = load(b["icon"])
			var tm = get_node_or_null("/root/ThemeManager")
			if tm and tm.has_method("make_white_icon"):
				btn.icon = tm.make_white_icon(raw_tex, 16)
			else:
				btn.icon = raw_tex
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
			btn.expand_icon = false
			btn.text = ""
		var k: String = b["key"]
		btn.pressed.connect(func(): _on_boolean_action_pressed(k))
		row_acts.add_child(btn)

func _on_boolean_action_pressed(op: String) -> void:
	var bc = get_node_or_null("/root/BooleanCore")
	if is_instance_valid(bc) and bc.has_method("apply_operation"):
		bc.apply_operation(op)
		return
	if op == "shape_builder":
		var cnv = get_tree().get_first_node_in_group("_vectopen_canvas")
		if cnv and cnv.has_method("switch_tool"):
			cnv.switch_tool("shape_builder")
		return

	var ic = get_node_or_null("/root/InspectorCore")
	var sel: Array = ic.selection() if ic else []
	if sel.is_empty():
		return

	if sel.size() == 1 and sel[0] is VectorBooleanScript:
		var target_vb = sel[0]
		target_vb.set("operation", op)
		return

	if sel.size() < 2:
		return

	var first_shape = sel[0]
	var parent: Node = first_shape.get_parent()
	if not is_instance_valid(parent):
		return

	var vb: VectorShape = VectorBooleanScript.new() as VectorShape
	vb.name = "Boolean_" + op.capitalize()
	vb.set("operation", op)
	if "fill_color" in first_shape:
		vb.fill_color = first_shape.fill_color
	if "stroke_color" in first_shape:
		vb.stroke_color = first_shape.stroke_color
	if "stroke_width" in first_shape:
		vb.stroke_width = first_shape.stroke_width

	var insert_idx: int = first_shape.get_index()
	parent.add_child(vb)
	parent.move_child(vb, insert_idx)

	for s in sel:
		if is_instance_valid(s) and s.get_parent() == parent:
			s.reparent(vb, true)

	vb.call("invalidate_cache")


	var hm = get_node_or_null("/root/HistoryManager")
	if is_instance_valid(hm) and hm.has_method("create_action"):
		hm.create_action("Boolean " + op.capitalize())
		hm.commit_action()

	# InspectorCore no tiene set_selection: la selección vive en
	# SelectionManager (el espejo de abajo es solo compat para bounding_box).
	var sm = get_node_or_null("/root/SelectionManager")
	if is_instance_valid(sm) and sm.has_method("set_selection"):
		sm.set_selection([vb])
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas")
	if canvas and "current_tool" in canvas and canvas.current_tool and "selected_shapes" in canvas.current_tool:
		canvas.current_tool.selected_shapes.assign([vb])


# ── SECCIÓN APARIENCIA ──
func _build_appearance_section() -> void:
	sec_appearance = VBoxContainer.new()
	sec_appearance.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_appearance)

	sec_appearance.add_child(_create_section_header("APPEARANCE"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	sec_appearance.add_child(row)

	var lbl_op := Label.new()
	lbl_op.text = "Opacity"
	lbl_op.add_theme_font_size_override("font_size", 10)
	lbl_op.add_theme_color_override("font_color", _C_MUTED)
	lbl_op.custom_minimum_size = Vector2(46, 0)
	row.add_child(lbl_op)

	spin_opacity = NumericField.new("", "%", 0.0, 100.0, 1.0)
	spin_opacity.value = 100.0
	spin_opacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin_opacity.value_changed.connect(_on_fill_opacity_changed)
	row.add_child(spin_opacity)

	btn_toggle_visibility = _create_chip_button("👁", "Alternar visibilidad del objeto", Vector2(26, 24))
	btn_toggle_visibility.pressed.connect(_on_toggle_visibility_pressed)
	row.add_child(btn_toggle_visibility)

# ── SECCIÓN TIPOGRAFÍA (TEXTO CONTEXTUAL - SECCIÓN 4.2) ──
func _build_typography_section() -> void:
	sec_typography = VBoxContainer.new()
	sec_typography.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_typography)

	sec_typography.add_child(_create_section_header("TYPOGRAPHY"))

	# Fila 1: Familia y Peso
	var row_font := HBoxContainer.new()
	row_font.add_theme_constant_override("separation", 4)
	sec_typography.add_child(row_font)

	opt_font_family = OptionButton.new()
	opt_font_family.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_font_family.custom_minimum_size = Vector2(0, 22)
	opt_font_family.focus_mode = Control.FOCUS_NONE
	opt_font_family.add_theme_font_size_override("font_size", 10)
	for f in ["Inter", "Roboto", "Segoe UI", "Arial", "Consolas"]:
		opt_font_family.add_item(f)
	_style_option_button(opt_font_family)
	opt_font_family.item_selected.connect(_on_font_family_selected)
	row_font.add_child(opt_font_family)

	opt_font_weight = OptionButton.new()
	opt_font_weight.custom_minimum_size = Vector2(68, 22)
	opt_font_weight.focus_mode = Control.FOCUS_NONE
	opt_font_weight.add_theme_font_size_override("font_size", 10)
	for w in ["Regular", "Medium", "Bold", "Italic"]:
		opt_font_weight.add_item(w)
	_style_option_button(opt_font_weight)
	opt_font_weight.item_selected.connect(_on_font_weight_selected)
	row_font.add_child(opt_font_weight)

	# Fila 2: Tamaño y Alineación
	var row_size_align := HBoxContainer.new()
	row_size_align.add_theme_constant_override("separation", 4)
	sec_typography.add_child(row_size_align)

	spin_font_size = NumericField.new("Size", " pt", 6.0, 500.0, 1.0)
	spin_font_size.value = 16.0
	spin_font_size.custom_minimum_size = Vector2(80, 22)
	spin_font_size.value_changed.connect(_on_font_size_changed)
	row_size_align.add_child(spin_font_size)

	var align_row := HBoxContainer.new()
	align_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	align_row.add_theme_constant_override("separation", 2)
	row_size_align.add_child(align_row)

	btn_align_left = _create_chip_button("⇤", "Alinear a la izquierda", Vector2(24, 22))
	btn_align_left.pressed.connect(func(): _set_text_align("left"))
	align_row.add_child(btn_align_left)

	btn_align_center = _create_chip_button("≡", "Centrar texto", Vector2(24, 22))
	btn_align_center.pressed.connect(func(): _set_text_align("center"))
	align_row.add_child(btn_align_center)

	btn_align_right = _create_chip_button("⇥", "Alinear a la derecha", Vector2(24, 22))
	btn_align_right.pressed.connect(func(): _set_text_align("right"))
	align_row.add_child(btn_align_right)

func _on_font_family_selected(idx: int) -> void:
	if _syncing: return
	var font_name: String = opt_font_family.get_item_text(idx)
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("font_family", font_name)

func _on_font_weight_selected(idx: int) -> void:
	if _syncing: return
	var weight_name: String = opt_font_weight.get_item_text(idx).to_lower()
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("font_weight", weight_name)

func _on_font_size_changed(val: float) -> void:
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("font_size", val)

func _set_text_align(align_val: String) -> void:
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("text_align", align_val)
	_sync_text_align_buttons(align_val)

func _sync_text_align_buttons(align_val: String) -> void:
	if is_instance_valid(btn_align_left):
		btn_align_left.modulate = _C_ACCENT if align_val == "left" else Color.WHITE
	if is_instance_valid(btn_align_center):
		btn_align_center.modulate = _C_ACCENT if align_val == "center" else Color.WHITE
	if is_instance_valid(btn_align_right):
		btn_align_right.modulate = _C_ACCENT if align_val == "right" else Color.WHITE

# ── SECCIONES PARAMÉTRICAS (SECCIÓN 15, 16, 17) ──
func _build_parametric_circle_section() -> void:
	sec_parametric_circle = VBoxContainer.new()
	sec_parametric_circle.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_parametric_circle)

	sec_parametric_circle.add_child(_create_section_header("ELLIPSE GEOMETRY"))

	var row_mode := HBoxContainer.new()
	row_mode.add_theme_constant_override("separation", 4)
	sec_parametric_circle.add_child(row_mode)

	opt_circle_mode = OptionButton.new()
	opt_circle_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_circle_mode.custom_minimum_size = Vector2(0, 22)
	opt_circle_mode.focus_mode = Control.FOCUS_NONE
	opt_circle_mode.add_theme_font_size_override("font_size", 10)
	opt_circle_mode.add_item("Completo")
	opt_circle_mode.add_item("Arco")
	opt_circle_mode.add_item("Sector / Pie")
	opt_circle_mode.add_item("Cuerda")
	opt_circle_mode.add_item("Anillo / Donut")
	_style_option_button(opt_circle_mode)
	opt_circle_mode.item_selected.connect(func(idx: int):
		var modes: Array[String] = ["whole", "arc", "pie", "chord", "donut"]
		var m: String = modes[idx] if idx < modes.size() else "whole"
		_set_circle_param("shape_mode", m)
		_update_circle_mode_fields()
	)
	row_mode.add_child(opt_circle_mode)

	var row_angles := HBoxContainer.new()
	row_angles.add_theme_constant_override("separation", 4)
	sec_parametric_circle.add_child(row_angles)

	spin_circle_start_angle = NumericField.new("Start", "°", 0.0, 360.0, 1.0)
	spin_circle_start_angle.value = 0.0
	spin_circle_start_angle.custom_minimum_size = Vector2(80, 22)
	_bind_live_param(spin_circle_start_angle, "start_angle_deg")
	row_angles.add_child(spin_circle_start_angle)

	spin_circle_end_angle = NumericField.new("End", "°", 0.0, 360.0, 1.0)
	spin_circle_end_angle.value = 360.0
	spin_circle_end_angle.custom_minimum_size = Vector2(80, 22)
	_bind_live_param(spin_circle_end_angle, "end_angle_deg")
	row_angles.add_child(spin_circle_end_angle)

	var row_inner := HBoxContainer.new()
	row_inner.add_theme_constant_override("separation", 4)
	sec_parametric_circle.add_child(row_inner)

	spin_circle_inner_radius = NumericField.new("Inner", "%", 1.0, 95.0, 1.0)
	spin_circle_inner_radius.value = 50.0
	spin_circle_inner_radius.custom_minimum_size = Vector2(80, 22)
	_bind_live_param(spin_circle_inner_radius, "inner_radius_ratio", 0.01)
	row_inner.add_child(spin_circle_inner_radius)

func _build_parametric_star_section() -> void:
	sec_parametric_star = VBoxContainer.new()
	sec_parametric_star.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_parametric_star)

	sec_parametric_star.add_child(_create_section_header("STAR GEOMETRY"))

	var row_pts_ratio := HBoxContainer.new()
	row_pts_ratio.add_theme_constant_override("separation", 4)
	sec_parametric_star.add_child(row_pts_ratio)

	spin_star_points = NumericField.new("Points", "", 3.0, 64.0, 1.0)
	spin_star_points.value = 5.0
	spin_star_points.custom_minimum_size = Vector2(80, 22)
	_bind_live_param(spin_star_points, "points_count", 1.0, true)
	row_pts_ratio.add_child(spin_star_points)

	spin_star_inner_radius = NumericField.new("Ratio", "%", 5.0, 95.0, 1.0)
	spin_star_inner_radius.value = 38.2
	spin_star_inner_radius.custom_minimum_size = Vector2(80, 22)
	_bind_live_param(spin_star_inner_radius, "inner_radius_ratio", 0.01)
	row_pts_ratio.add_child(spin_star_inner_radius)

	var row_round := HBoxContainer.new()
	row_round.add_theme_constant_override("separation", 4)
	sec_parametric_star.add_child(row_round)

	spin_star_corner_radius = NumericField.new("Round", " px", 0.0, 50.0, 1.0)
	spin_star_corner_radius.value = 0.0
	spin_star_corner_radius.custom_minimum_size = Vector2(80, 22)
	_bind_live_param(spin_star_corner_radius, "corner_radius")
	row_round.add_child(spin_star_corner_radius)

func _build_parametric_rect_section() -> void:
	sec_parametric_rect = VBoxContainer.new()
	sec_parametric_rect.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_parametric_rect)

	sec_parametric_rect.add_child(_create_section_header("CORNER RADIUS"))

	var row_radius := HBoxContainer.new()
	row_radius.add_theme_constant_override("separation", 4)
	sec_parametric_rect.add_child(row_radius)

	spin_rect_corner_radius = NumericField.new("Radius", " px", 0.0, 500.0, 1.0)
	spin_rect_corner_radius.value = 0.0
	spin_rect_corner_radius.custom_minimum_size = Vector2(80, 22)
	_bind_live_param(spin_rect_corner_radius, "corner_radius")
	row_radius.add_child(spin_rect_corner_radius)

var sec_parametric_polygon: VBoxContainer
var spin_poly_sides: NumericField
var spin_poly_radius: NumericField
var _row_poly_sides: HBoxContainer
## prop -> {shape: value before the drag}, while a parametric field is scrubbed
var _live_before: Dictionary = {}

func _build_parametric_polygon_section() -> void:
	sec_parametric_polygon = VBoxContainer.new()
	sec_parametric_polygon.add_theme_constant_override("separation", 4)
	sec_parametric_polygon.visible = false
	content_container.add_child(sec_parametric_polygon)
	sec_parametric_polygon.add_child(_create_section_header("POLYGON"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	sec_parametric_polygon.add_child(row)
	_row_poly_sides = row

	spin_poly_sides = NumericField.new("Sides", "", 3.0, 64.0, 1.0)
	spin_poly_sides.value = 5.0
	spin_poly_sides.custom_minimum_size = Vector2(80, 22)
	spin_poly_sides.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bind_live_param(spin_poly_sides, "sides", 1.0, true)
	row.add_child(spin_poly_sides)

	spin_poly_radius = NumericField.new("Round", " px", 0.0, 200.0, 1.0)
	spin_poly_radius.value = 0.0
	spin_poly_radius.custom_minimum_size = Vector2(80, 22)
	spin_poly_radius.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bind_live_param(spin_poly_radius, "corner_radius")
	sec_parametric_polygon.add_child(spin_poly_radius)

func _sync_polygon_controls(shape: VectorPolygon) -> void:
	_syncing = true
	# Only regular polygons have a side count to edit; on a free-form polygon
	# changing it would replace the drawn shape.
	if is_instance_valid(_row_poly_sides):
		_row_poly_sides.visible = shape.is_regular
	if is_instance_valid(spin_poly_sides):
		spin_poly_sides.value = float(shape.sides)
	if is_instance_valid(spin_poly_radius):
		spin_poly_radius.value = shape.corner_radius
	_syncing = false

## Parametric fields: a click/typed value is one undo step; while dragging the
## figure updates live and a single undo step is recorded on release (instead
## of one per pixel of scrubbing).
func _bind_live_param(field: NumericField, prop: String, p_scale: float = 1.0, as_int: bool = false) -> void:
	var to_value := func(v: float) -> Variant:
		var x := v * p_scale
		if as_int:
			return int(round(x))
		return x
	field.drag_started.connect(func():
		var ic = get_node_or_null("/root/InspectorCore")
		if ic == null:
			return
		var before := {}
		for sh in ic.selection():
			before[sh] = ic._read(sh, prop)
		_live_before[prop] = before
	)
	field.value_changed.connect(func(v: float):
		if _syncing:
			return
		var ic = get_node_or_null("/root/InspectorCore")
		if ic == null:
			return
		if _live_before.has(prop):
			for sh in ic.selection():
				ic._write(sh, prop, to_value.call(v))
			ic._post_write()
		else:
			ic.apply(prop, to_value.call(v))
		if prop == "shape_mode":
			_update_circle_mode_fields()
	)
	field.drag_ended.connect(func():
		var ic = get_node_or_null("/root/InspectorCore")
		if ic and _live_before.has(prop):
			ic.commit_live(prop, _live_before[prop])
		_live_before.erase(prop)
	)

## Start/end only matter for arc, pie and chord; the inner ratio only for donut.
func _update_circle_mode_fields() -> void:
	if not is_instance_valid(opt_circle_mode):
		return
	var modes: Array[String] = ["whole", "arc", "pie", "chord", "donut"]
	var mode: String = modes[clampi(opt_circle_mode.selected, 0, modes.size() - 1)]
	var angles := mode in ["arc", "pie", "chord"]
	if is_instance_valid(spin_circle_start_angle):
		spin_circle_start_angle.get_parent().visible = angles
	if is_instance_valid(spin_circle_inner_radius):
		spin_circle_inner_radius.get_parent().visible = mode == "donut"

func _set_circle_param(param: String, val: Variant) -> void:
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply(param, val)

func _set_star_param(param: String, val: Variant) -> void:
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply(param, val)

func _set_rect_param(param: String, val: Variant) -> void:
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply(param, val)

func _sync_circle_controls(shape: VectorCircle) -> void:
	_syncing = true
	var modes: Array[String] = ["whole", "arc", "pie", "chord", "donut"]
	var idx: int = modes.find(shape.shape_mode)
	if idx >= 0 and is_instance_valid(opt_circle_mode):
		opt_circle_mode.selected = idx
	if is_instance_valid(spin_circle_start_angle):
		spin_circle_start_angle.value = shape.start_angle_deg
	if is_instance_valid(spin_circle_end_angle):
		spin_circle_end_angle.value = shape.end_angle_deg
	if is_instance_valid(spin_circle_inner_radius):
		spin_circle_inner_radius.value = shape.inner_radius_ratio * 100.0
	_syncing = false
	_update_circle_mode_fields()

func _sync_star_controls(shape: VectorStar) -> void:
	_syncing = true
	if is_instance_valid(spin_star_points):
		spin_star_points.value = float(shape.points_count)
	if is_instance_valid(spin_star_inner_radius):
		spin_star_inner_radius.value = shape.inner_radius_ratio * 100.0
	if is_instance_valid(spin_star_corner_radius):
		spin_star_corner_radius.value = shape.corner_radius
	_syncing = false

func _sync_rect_controls(shape: VectorRectangle) -> void:
	_syncing = true
	if is_instance_valid(spin_rect_corner_radius):
		spin_rect_corner_radius.value = shape.corner_radius
	_syncing = false

func _build_3d_model_section() -> void:
	sec_3d_model = VBoxContainer.new()
	sec_3d_model.add_theme_constant_override("separation", 6)
	content_container.add_child(sec_3d_model)

	sec_3d_model.add_child(_create_section_header("3D MODEL"))

	var row_file := HBoxContainer.new()
	row_file.add_theme_constant_override("separation", 4)
	sec_3d_model.add_child(row_file)

	lbl_3d_path = Label.new()
	lbl_3d_path.text = "Cubo (básico)"
	lbl_3d_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_3d_path.add_theme_font_size_override("font_size", 10)
	lbl_3d_path.add_theme_color_override("font_color", _C_TEXT)
	lbl_3d_path.clip_text = true
	row_file.add_child(_wrap_input_pill(lbl_3d_path))

	btn_3d_change_file = _create_chip_button("📂", "Cambiar archivo 3D (.glb / .gltf)", Vector2(24, 24))
	btn_3d_change_file.pressed.connect(_on_change_3d_file_pressed)
	row_file.add_child(btn_3d_change_file)

	var row_rot_xy := HBoxContainer.new()
	row_rot_xy.add_theme_constant_override("separation", 4)
	sec_3d_model.add_child(row_rot_xy)

	spin_3d_rot_x = NumericField.new("Rot X", "°", -360.0, 360.0, 1.0)
	spin_3d_rot_x.custom_minimum_size = Vector2(80, 22)
	spin_3d_rot_x.value_changed.connect(func(v: float): _set_3d_param("model_rotation_x", v))
	row_rot_xy.add_child(spin_3d_rot_x)

	spin_3d_rot_y = NumericField.new("Rot Y", "°", -360.0, 360.0, 1.0)
	spin_3d_rot_y.custom_minimum_size = Vector2(80, 22)
	spin_3d_rot_y.value_changed.connect(func(v: float): _set_3d_param("model_rotation_y", v))
	row_rot_xy.add_child(spin_3d_rot_y)

	var row_rot_z_fov := HBoxContainer.new()
	row_rot_z_fov.add_theme_constant_override("separation", 4)
	sec_3d_model.add_child(row_rot_z_fov)

	spin_3d_rot_z = NumericField.new("Rot Z", "°", -360.0, 360.0, 1.0)
	spin_3d_rot_z.custom_minimum_size = Vector2(80, 22)
	spin_3d_rot_z.value_changed.connect(func(v: float): _set_3d_param("model_rotation_z", v))
	row_rot_z_fov.add_child(spin_3d_rot_z)

	spin_3d_fov = NumericField.new("FOV", "°", 10.0, 120.0, 1.0)
	spin_3d_fov.custom_minimum_size = Vector2(80, 22)
	spin_3d_fov.value = 45.0
	spin_3d_fov.value_changed.connect(func(v: float): _set_3d_param("camera_fov", v))
	row_rot_z_fov.add_child(spin_3d_fov)

	var row_cam_light := HBoxContainer.new()
	row_cam_light.add_theme_constant_override("separation", 4)
	sec_3d_model.add_child(row_cam_light)

	spin_3d_distance = NumericField.new("Dist", "", 0.2, 50.0, 0.1)
	spin_3d_distance.custom_minimum_size = Vector2(80, 22)
	spin_3d_distance.value = 3.5
	spin_3d_distance.value_changed.connect(func(v: float): _set_3d_param("camera_distance", v))
	row_cam_light.add_child(spin_3d_distance)

	spin_3d_light_energy = NumericField.new("Luz", "", 0.0, 10.0, 0.1)
	spin_3d_light_energy.custom_minimum_size = Vector2(80, 22)
	spin_3d_light_energy.value = 1.2
	spin_3d_light_energy.value_changed.connect(func(v: float): _set_3d_param("light_energy", v))
	row_cam_light.add_child(spin_3d_light_energy)

	btn_3d_reset_view = _create_chip_button("Restablecer vista 3D", "Restablecer rotacion orbital y distancia de camara", Vector2(0, 24))
	btn_3d_reset_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_3d_reset_view.pressed.connect(_on_3d_reset_view_pressed)
	sec_3d_model.add_child(btn_3d_reset_view)

	var hint_lbl := Label.new()
	hint_lbl.text = "Tip: Doble clic en el lienzo para rotar y zoom con el ratón."
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.add_theme_font_size_override("font_size", 9)
	hint_lbl.add_theme_color_override("font_color", _C_MUTED)
	sec_3d_model.add_child(hint_lbl)

func _set_3d_param(param: String, val: Variant) -> void:
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply(param, val)

func _on_change_3d_file_pressed() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.glb ; Modelos 3D GLB (*.glb)", "*.gltf ; Modelos 3D GLTF (*.gltf)"])
	fd.title = "Seleccionar Modelo 3D"
	fd.file_selected.connect(func(path: String):
		_set_3d_param("model_path", path)
		if is_instance_valid(lbl_3d_path):
			lbl_3d_path.text = path.get_file()
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	var root := get_tree().root if get_tree() else null
	if root:
		root.add_child(fd)
		fd.popup_centered_ratio(0.7)

func _on_3d_reset_view_pressed() -> void:
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("selection"):
		var sel: Array = ic.selection()
		for s in sel:
			if is_instance_valid(s) and s.has_method("reset_view"):
				s.reset_view()
				_sync_3d_controls(s)

func _sync_3d_controls(model) -> void:
	_syncing = true
	if is_instance_valid(lbl_3d_path):
		var mp: String = model.model_path if "model_path" in model else ""
		lbl_3d_path.text = mp.get_file() if not mp.is_empty() else "Cubo (básico)"
	if is_instance_valid(spin_3d_rot_x) and "model_rotation" in model:
		spin_3d_rot_x.value = model.model_rotation.x
	if is_instance_valid(spin_3d_rot_y) and "model_rotation" in model:
		spin_3d_rot_y.value = model.model_rotation.y
	if is_instance_valid(spin_3d_rot_z) and "model_rotation" in model:
		spin_3d_rot_z.value = model.model_rotation.z
	if is_instance_valid(spin_3d_fov) and "camera_fov" in model:
		spin_3d_fov.value = model.camera_fov
	if is_instance_valid(spin_3d_distance) and "camera_distance" in model:
		spin_3d_distance.value = model.camera_distance
	if is_instance_valid(spin_3d_light_energy) and "light_energy" in model:
		spin_3d_light_energy.value = model.light_energy
	_syncing = false


# ── SECCIÓN RELLENO (FILL) ──
func _build_fill_section() -> void:
	sec_fill = VBoxContainer.new()
	sec_fill.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_fill)

	sec_fill.add_child(_create_section_header("FILL", func(): _on_fill_color_changed(Color.WHITE)))

	# Fila compacta: Muestra + HEX + Opacidad + Ojo + Menos
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	sec_fill.add_child(row)

	picker_fill = ColorSwatchButton.new(Color.WHITE)
	_style_color_picker(picker_fill)
	picker_fill.color_changed.connect(_on_fill_color_changed)
	picker_fill.pressed.connect(func(): _open_color_popover("fill", picker_fill))
	row.add_child(picker_fill)

	lbl_fill_hex = Label.new()
	lbl_fill_hex.text = "#FFFFFF"
	lbl_fill_hex.add_theme_font_size_override("font_size", 11)
	lbl_fill_hex.add_theme_color_override("font_color", _C_TEXT)
	lbl_fill_hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_wrap_input_pill(lbl_fill_hex))

	var btn_eye := _create_chip_button("👁", "Alternar relleno", Vector2(24, 24))
	btn_eye.pressed.connect(_on_toggle_visibility_pressed)
	row.add_child(btn_eye)

	var btn_minus := _create_chip_button("−", "Quitar relleno", Vector2(24, 24))
	btn_minus.pressed.connect(func(): _on_fill_color_changed(Color(1, 1, 1, 0)))
	row.add_child(btn_minus)

# ── SECCIÓN TRAZO (STROKE) ──
func _build_stroke_section() -> void:
	sec_stroke = VBoxContainer.new()
	sec_stroke.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_stroke)

	sec_stroke.add_child(_create_section_header("STROKE", func(): _on_stroke_width_changed(1.0)))

	# Fila compacta: Muestra + Grosor + Alineación + Ojo + Menos
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	sec_stroke.add_child(row)

	picker_stroke = ColorSwatchButton.new(Color.BLACK)
	_style_color_picker(picker_stroke)
	picker_stroke.color_changed.connect(_on_stroke_color_changed)
	picker_stroke.pressed.connect(func(): _open_color_popover("stroke", picker_stroke))
	row.add_child(picker_stroke)

	spin_stroke_width = NumericField.new("", " px", 0.0, 500.0, 0.5)
	spin_stroke_width.value = 1.0
	spin_stroke_width.custom_minimum_size = Vector2(62, 24)
	spin_stroke_width.value_changed.connect(_on_stroke_width_changed)
	row.add_child(spin_stroke_width)

	opt_stroke_align = OptionButton.new()
	opt_stroke_align.add_item("Center")
	opt_stroke_align.add_item("Inside")
	opt_stroke_align.add_item("Outside")
	opt_stroke_align.custom_minimum_size = Vector2(68, 24)
	opt_stroke_align.focus_mode = Control.FOCUS_NONE
	opt_stroke_align.add_theme_font_size_override("font_size", 9)
	_style_option_button(opt_stroke_align)
	row.add_child(opt_stroke_align)

	var btn_eye := _create_chip_button("👁", "Alternar trazo", Vector2(24, 24))
	row.add_child(btn_eye)

	var btn_minus := _create_chip_button("−", "Quitar trazo", Vector2(24, 24))
	btn_minus.pressed.connect(func(): _on_stroke_width_changed(0.0))
	row.add_child(btn_minus)

# ── SECCIÓN EFECTOS ──
func _build_effects_section() -> void:
	sec_effects = VBoxContainer.new()
	sec_effects.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_effects)

	sec_effects.add_child(_create_section_header("EFFECTS", func(): _on_shadow_toggle_pressed()))

	# Fila compacta: Nombre de efecto + Ajustes + Ojo + Menos
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	sec_effects.add_child(row)

	btn_shadow_toggle = _create_chip_button("▨ Drop Shadow", "Alternar sombra suave", Vector2(0, 24))
	btn_shadow_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_shadow_toggle.pressed.connect(_on_shadow_toggle_pressed)
	row.add_child(btn_shadow_toggle)

	var btn_cfg := _create_chip_button("⚙", "Ajustes de sombra", Vector2(24, 24))
	row.add_child(btn_cfg)

	var btn_eye := _create_chip_button("👁", "Alternar sombra", Vector2(24, 24))
	btn_eye.pressed.connect(_on_shadow_toggle_pressed)
	row.add_child(btn_eye)

	var btn_minus := _create_chip_button("−", "Quitar sombra", Vector2(24, 24))
	btn_minus.pressed.connect(func():
		if _has_shadow: _on_shadow_toggle_pressed()
	)
	row.add_child(btn_minus)

# ── SECCIÓN EXPORTAR (CONSOLIDADA AL FINAL) ──
func _build_export_section() -> void:
	sec_export = VBoxContainer.new()
	sec_export.add_theme_constant_override("separation", 6)
	content_container.add_child(sec_export)

	sec_export.add_child(_create_section_header("EXPORT", func(): _on_export_selection_pressed()))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	sec_export.add_child(row)

	opt_export_format = OptionButton.new()
	opt_export_format.add_item("PNG")
	opt_export_format.add_item("SVG")
	opt_export_format.add_item("JPG")
	opt_export_format.add_item("PDF")
	opt_export_format.custom_minimum_size = Vector2(62, 24)
	opt_export_format.focus_mode = Control.FOCUS_NONE
	opt_export_format.add_theme_font_size_override("font_size", 10)
	_style_option_button(opt_export_format)
	row.add_child(opt_export_format)

	btn_export_selection = _create_chip_button("Export", "Exportar seleccion activa", Vector2(0, 24))
	btn_export_selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_export_selection.pressed.connect(_on_export_selection_pressed)
	row.add_child(btn_export_selection)

# ── HELPERS DE ESTILOS DE COMPONENTES ──
func _style_input_pill(pc: PanelContainer) -> void:
	if not is_instance_valid(pc):
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = _C_BG_INPUT
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = _C_BORDER_INPUT
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)

func _wrap_input_pill(inner: Control) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pill_panels.append(pc)
	_style_input_pill(pc)
	pc.add_child(inner)
	return pc

func _style_spinbox(sb: Variant) -> void:
	if not is_instance_valid(sb):
		return
	if sb.has_method("get_line_edit"):
		var le = sb.get_line_edit()
		if is_instance_valid(le):
			le.add_theme_font_size_override("font_size", 10)
			le.add_theme_color_override("font_color", _C_TEXT)
			var sbf := StyleBoxFlat.new()
			sbf.bg_color = _C_BG_INPUT
			sbf.set_corner_radius_all(4)
			sbf.set_border_width_all(1)
			sbf.border_color = _C_BORDER_INPUT
			sbf.content_margin_left = 6
			sbf.content_margin_right = 6
			sbf.content_margin_top = 2
			sbf.content_margin_bottom = 2
			le.add_theme_stylebox_override("normal", sbf)
			le.add_theme_stylebox_override("focus", sbf)

func _style_color_picker(cp: Button) -> void:
	cp.focus_mode = Control.FOCUS_NONE
	var sbf := StyleBoxFlat.new()
	sbf.set_corner_radius_all(4)
	sbf.set_border_width_all(1)
	sbf.border_color = _C_BORDER_INPUT
	sbf.draw_center = false
	sbf.content_margin_left = 2
	sbf.content_margin_right = 2
	sbf.content_margin_top = 2
	sbf.content_margin_bottom = 2
	cp.add_theme_stylebox_override("normal", sbf)
	cp.add_theme_stylebox_override("hover", sbf)

func _style_option_button(opt: OptionButton) -> void:
	if not is_instance_valid(opt):
		return
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = _C_BG_INPUT
	sbf.set_corner_radius_all(4)
	sbf.set_border_width_all(1)
	sbf.border_color = _C_BORDER_INPUT
	sbf.content_margin_left = 6
	sbf.content_margin_right = 6
	sbf.content_margin_top = 2
	sbf.content_margin_bottom = 2

	var hover_sbf := sbf.duplicate() as StyleBoxFlat
	hover_sbf.bg_color = Color(0.88, 0.88, 0.91, 1.0) if _C_TEXT.v < 0.5 else Color(0.24, 0.24, 0.26, 1.0)

	var press_sbf := sbf.duplicate() as StyleBoxFlat
	press_sbf.bg_color = Color(0.82, 0.82, 0.86, 1.0) if _C_TEXT.v < 0.5 else Color(0.30, 0.30, 0.32, 1.0)
	press_sbf.border_color = _C_ACCENT

	opt.add_theme_stylebox_override("normal", sbf)
	opt.add_theme_stylebox_override("hover", hover_sbf)
	opt.add_theme_stylebox_override("pressed", press_sbf)
	opt.add_theme_stylebox_override("focus", sbf)
	opt.add_theme_stylebox_override("disabled", sbf)

	opt.add_theme_color_override("font_color", _C_TEXT)
	opt.add_theme_color_override("font_hover_color", _C_TEXT)
	opt.add_theme_color_override("font_pressed_color", _C_TEXT)
	opt.add_theme_color_override("font_focus_color", _C_TEXT)
	opt.add_theme_color_override("font_disabled_color", _C_MUTED)

	var pop := opt.get_popup()
	if is_instance_valid(pop):
		var pop_sb := StyleBoxFlat.new()
		var is_light: bool = _C_TEXT.v < 0.5
		pop_sb.bg_color = Color(0.98, 0.98, 0.99, 1.0) if is_light else Color(0.14, 0.14, 0.16, 1.0)
		pop_sb.border_color = _C_BORDER_INPUT
		pop_sb.set_border_width_all(1)
		pop_sb.set_corner_radius_all(6)
		pop_sb.content_margin_left = 6
		pop_sb.content_margin_right = 6
		pop_sb.content_margin_top = 4
		pop_sb.content_margin_bottom = 4
		pop_sb.shadow_color = Color(0, 0, 0, 0.12 if is_light else 0.40)
		pop_sb.shadow_size = 8
		pop_sb.shadow_offset = Vector2(0, 3)
		pop.add_theme_stylebox_override("panel", pop_sb)

		var pop_hov := StyleBoxFlat.new()
		pop_hov.bg_color = Color(_C_ACCENT.r, _C_ACCENT.g, _C_ACCENT.b, 0.18 if is_light else 0.35)
		pop_hov.set_corner_radius_all(4)
		pop.add_theme_stylebox_override("hover", pop_hov)

		pop.add_theme_color_override("font_color", _C_TEXT)
		pop.add_theme_color_override("font_hover_color", _C_TEXT)
		pop.add_theme_color_override("font_disabled_color", _C_MUTED)
		pop.add_theme_color_override("font_separator_color", _C_BORDER_INPUT)

func _update_flat_icon_button_theme(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var icon_color: Color = tm.get_color(S.ICON_PRIMARY) if (tm and S) else _C_TEXT
	var hover_color: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else _C_TEXT
	var hover_bg: Color = tm.get_color(S.INPUT_HOVER) if (tm and S) else (Color(0.88, 0.88, 0.91, 1.0) if _C_TEXT.v < 0.5 else Color(0.24, 0.24, 0.26, 1.0))
	var press_bg: Color = tm.get_color(S.BUTTON_PRESSED) if (tm and S) else (Color(0.82, 0.82, 0.86, 1.0) if _C_TEXT.v < 0.5 else Color(0.30, 0.30, 0.32, 1.0))

	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = hover_bg
	hover_sb.set_corner_radius_all(4)

	var press_sb := StyleBoxFlat.new()
	press_sb.bg_color = press_bg
	press_sb.set_corner_radius_all(4)

	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", press_sb)
	btn.add_theme_color_override("icon_normal_color", icon_color)
	btn.add_theme_color_override("icon_hover_color", hover_color)
	btn.add_theme_color_override("icon_pressed_color", _C_ACCENT)
	btn.add_theme_color_override("icon_focus_color", icon_color)
	btn.add_theme_color_override("font_color", _C_TEXT)

func _create_flat_icon_button(btn_text: String, tooltip: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = btn_text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 10)
	_update_flat_icon_button_theme(btn)
	return btn

func _update_chip_button_theme(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	var norm_sb := StyleBoxFlat.new()
	norm_sb.bg_color = _C_BG_INPUT
	norm_sb.set_corner_radius_all(4)
	norm_sb.set_border_width_all(1)
	norm_sb.border_color = _C_BORDER_INPUT
	norm_sb.content_margin_left = 4
	norm_sb.content_margin_right = 4
	norm_sb.content_margin_top = 2
	norm_sb.content_margin_bottom = 2

	var hover_sb := norm_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.88, 0.88, 0.91, 1.0) if _C_TEXT.v < 0.5 else Color(0.24, 0.24, 0.26, 1.0)

	var press_sb := norm_sb.duplicate() as StyleBoxFlat
	press_sb.bg_color = Color(0.82, 0.82, 0.86, 1.0) if _C_TEXT.v < 0.5 else Color(0.30, 0.30, 0.32, 1.0)

	btn.add_theme_stylebox_override("normal", norm_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", press_sb)
	btn.add_theme_color_override("font_color", _C_TEXT)

func _create_chip_button(btn_text: String, tooltip: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = btn_text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 10)
	_chip_buttons.append(btn)
	_update_chip_button_theme(btn)
	return btn

# ── CONEXIÓN Y EVENTOS ──
func _connect_inspector_core() -> void:
	var ic = get_node_or_null("/root/InspectorCore")
	if ic:
		if ic.has_signal("changed") and not ic.changed.is_connected(_on_inspector_changed):
			ic.changed.connect(_on_inspector_changed)
		if ic.has_signal("selection_size_changed") and not ic.selection_size_changed.is_connected(_on_selection_size_changed):
			ic.selection_size_changed.connect(_on_selection_size_changed)

	var lm = get_node_or_null("/root/LanguageManager")
	if lm and lm.has_signal("language_changed") and not lm.language_changed.is_connected(_on_language_changed):
		lm.language_changed.connect(_on_language_changed)

func _on_language_changed(_locale: String) -> void:
	for lbl in find_children("", "Label", true, false):
		if lbl.has_meta("header_title_key"):
			lbl.text = tr(String(lbl.get_meta("header_title_key")))

func _on_align_pressed(direction: String) -> void:
	var ic = get_node_or_null("/root/InspectorCore")
	if not ic: return
	if direction == "dist_h":
		if ic.has_method("distribute"): ic.distribute("horizontal")
	elif direction == "dist_v":
		if ic.has_method("distribute"): ic.distribute("vertical")
	elif ic.has_method("align"):
		ic.align(direction)

func _on_canvas_bg_changed(color: Color) -> void:
	if is_instance_valid(lbl_canvas_hex):
		lbl_canvas_hex.text = "#" + color.to_html(false).to_upper()
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("request_canvas_color_change"):
		ge.emit_safe("request_canvas_color_change", color)

func _on_fill_color_changed(color: Color) -> void:
	if is_instance_valid(lbl_fill_hex):
		lbl_fill_hex.text = "#" + color.to_html(false).to_upper()
	if not _syncing:
		var cc = get_node_or_null("/root/ColorCore")
		if cc and cc.has_method("set_color"):
			cc.set_color(color, "fill")
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("fill_color", color)

func _on_fill_opacity_changed(val: float) -> void:
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("opacity", val / 100.0)

func _on_toggle_visibility_pressed() -> void:
	_current_item_visible = !_current_item_visible
	btn_toggle_visibility.text = "👁" if _current_item_visible else "Ø"
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("visible", _current_item_visible)

func _on_stroke_color_changed(color: Color) -> void:
	if not _syncing:
		var cc = get_node_or_null("/root/ColorCore")
		if cc and cc.has_method("set_color"):
			cc.set_color(color, "stroke")
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("stroke_color", color)

func _on_stroke_width_changed(val: float) -> void:
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("stroke_width", val)

func _on_shadow_toggle_pressed() -> void:
	_has_shadow = !_has_shadow
	btn_shadow_toggle.modulate = Color(0.7, 1.0, 0.7) if _has_shadow else Color.WHITE
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		var effects := []
		if _has_shadow:
			effects.append({"type": "drop_shadow", "offset": Vector2(0, 4), "color": Color(0, 0, 0, 0.25), "blur": 8.0})
		ic.apply("effects", effects)

func _on_export_selection_pressed() -> void:
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("request_export_dialog"):
		ge.emit_safe("request_export_dialog")

func _get_selected_kind() -> String:
	var ic = get_node_or_null("/root/InspectorCore")
	if not ic or not ic.has_method("selection"):
		return "shape"
	var sel: Array = ic.selection()
	if sel.is_empty():
		return "none"
	if sel.size() > 1:
		return "multi"
	var shape = sel[0]
	if not is_instance_valid(shape):
		return "shape"
	if shape is VectorCircle:
		return "circle"
	if shape is VectorStar:
		return "star"
	if shape is VectorRectangle:
		return "rect"
	if shape.has_method("rotate_orbit") or (shape.has_meta("shape_type") and shape.get_meta("shape_type") == "3d"):
		return "model3d"
	if shape.has_meta("shape_type"):
		var st := String(shape.get_meta("shape_type"))
		if st.begins_with("text"):
			return "text"
		if st == "image":
			return "image"
		if st == "group":
			return "group"
	if shape.has_meta("is_group") or shape.name.begins_with("Group") or shape is CanvasGroup:
		return "group"
	if shape is Sprite2D or shape.has_meta("image_path"):
		return "image"
	return "shape"

# ── ACTUALIZACIÓN DE SELECCIÓN Y PROPIEDADES ──
func _on_selection_size_changed(count: int) -> void:
	_has_selection = count > 0
	if count == 0:
		lbl_title.text = "Page"
		lbl_selection.text = "No selection"
		if is_instance_valid(sec_canvas): sec_canvas.visible = true
		if is_instance_valid(sec_align): sec_align.visible = false
		if is_instance_valid(transform_panel): transform_panel.visible = false
		if is_instance_valid(sec_appearance): sec_appearance.visible = false
		if is_instance_valid(sec_typography): sec_typography.visible = false
		if is_instance_valid(sec_parametric_circle): sec_parametric_circle.visible = false
		if is_instance_valid(sec_parametric_star): sec_parametric_star.visible = false
		if is_instance_valid(sec_parametric_rect): sec_parametric_rect.visible = false
		if is_instance_valid(sec_parametric_polygon): sec_parametric_polygon.visible = false
		if is_instance_valid(sec_3d_model): sec_3d_model.visible = false
		if is_instance_valid(sec_fill): sec_fill.visible = false
		if is_instance_valid(sec_stroke): sec_stroke.visible = false
		if is_instance_valid(sec_effects): sec_effects.visible = false
		if is_instance_valid(sec_export): sec_export.visible = false
	else:
		if is_instance_valid(sec_canvas): sec_canvas.visible = false
		var kind := _get_selected_kind()
		var ic = get_node_or_null("/root/InspectorCore")
		var sel_node: Node = null
		if ic and ic.has_method("selection"):
			var sel: Array = ic.selection()
			if not sel.is_empty():
				sel_node = sel[0]

		var is_poly: bool = count == 1 and sel_node is VectorPolygon
		if is_instance_valid(sec_parametric_polygon):
			sec_parametric_polygon.visible = is_poly
		if is_poly:
			_sync_polygon_controls(sel_node)

		match kind:
			"circle":
				if is_instance_valid(sec_align): sec_align.visible = true
				if is_instance_valid(transform_panel): transform_panel.visible = true
				if is_instance_valid(sec_appearance): sec_appearance.visible = true
				if is_instance_valid(sec_typography): sec_typography.visible = false
				if is_instance_valid(sec_parametric_circle): sec_parametric_circle.visible = true
				if is_instance_valid(sec_parametric_star): sec_parametric_star.visible = false
				if is_instance_valid(sec_parametric_rect): sec_parametric_rect.visible = false
				if is_instance_valid(sec_3d_model): sec_3d_model.visible = false
				if is_instance_valid(sec_fill): sec_fill.visible = true
				if is_instance_valid(sec_stroke): sec_stroke.visible = true
				if is_instance_valid(sec_effects): sec_effects.visible = true
				if is_instance_valid(sec_export): sec_export.visible = true
				if sel_node is VectorCircle: _sync_circle_controls(sel_node)
			"star":
				if is_instance_valid(sec_align): sec_align.visible = true
				if is_instance_valid(transform_panel): transform_panel.visible = true
				if is_instance_valid(sec_appearance): sec_appearance.visible = true
				if is_instance_valid(sec_typography): sec_typography.visible = false
				if is_instance_valid(sec_parametric_circle): sec_parametric_circle.visible = false
				if is_instance_valid(sec_parametric_star): sec_parametric_star.visible = true
				if is_instance_valid(sec_parametric_rect): sec_parametric_rect.visible = false
				if is_instance_valid(sec_3d_model): sec_3d_model.visible = false
				if is_instance_valid(sec_fill): sec_fill.visible = true
				if is_instance_valid(sec_stroke): sec_stroke.visible = true
				if is_instance_valid(sec_effects): sec_effects.visible = true
				if is_instance_valid(sec_export): sec_export.visible = true
				if sel_node is VectorStar: _sync_star_controls(sel_node)
			"rect":
				if is_instance_valid(sec_align): sec_align.visible = true
				if is_instance_valid(transform_panel): transform_panel.visible = true
				if is_instance_valid(sec_appearance): sec_appearance.visible = true
				if is_instance_valid(sec_typography): sec_typography.visible = false
				if is_instance_valid(sec_parametric_circle): sec_parametric_circle.visible = false
				if is_instance_valid(sec_parametric_star): sec_parametric_star.visible = false
				if is_instance_valid(sec_parametric_rect): sec_parametric_rect.visible = true
				if is_instance_valid(sec_3d_model): sec_3d_model.visible = false
				if is_instance_valid(sec_fill): sec_fill.visible = true
				if is_instance_valid(sec_stroke): sec_stroke.visible = true
				if is_instance_valid(sec_effects): sec_effects.visible = true
				if is_instance_valid(sec_export): sec_export.visible = true
				if sel_node is VectorRectangle: _sync_rect_controls(sel_node)
			"model3d":
				if is_instance_valid(sec_align): sec_align.visible = true
				if is_instance_valid(transform_panel): transform_panel.visible = true
				if is_instance_valid(sec_appearance): sec_appearance.visible = true
				if is_instance_valid(sec_typography): sec_typography.visible = false
				if is_instance_valid(sec_parametric_circle): sec_parametric_circle.visible = false
				if is_instance_valid(sec_parametric_star): sec_parametric_star.visible = false
				if is_instance_valid(sec_parametric_rect): sec_parametric_rect.visible = false
				if is_instance_valid(sec_3d_model): sec_3d_model.visible = true
				if is_instance_valid(sec_fill): sec_fill.visible = false
				if is_instance_valid(sec_stroke): sec_stroke.visible = false
				if is_instance_valid(sec_effects): sec_effects.visible = true
				if is_instance_valid(sec_export): sec_export.visible = true
				if sel_node: _sync_3d_controls(sel_node)
			"text":
				if is_instance_valid(sec_align): sec_align.visible = true
				if is_instance_valid(transform_panel): transform_panel.visible = true
				if is_instance_valid(sec_appearance): sec_appearance.visible = true
				if is_instance_valid(sec_typography): sec_typography.visible = true
				if is_instance_valid(sec_parametric_circle): sec_parametric_circle.visible = false
				if is_instance_valid(sec_parametric_star): sec_parametric_star.visible = false
				if is_instance_valid(sec_parametric_rect): sec_parametric_rect.visible = false
				if is_instance_valid(sec_3d_model): sec_3d_model.visible = false
				if is_instance_valid(sec_fill):
					sec_fill.visible = true
					var hdr = sec_fill.get_child(0) if sec_fill.get_child_count() > 0 else null
					if hdr and hdr.get_child_count() > 0 and hdr.get_child(0) is Label:
						hdr.get_child(0).text = "TEXT COLOR"
				if is_instance_valid(sec_stroke): sec_stroke.visible = false
				if is_instance_valid(sec_effects): sec_effects.visible = true
				if is_instance_valid(sec_export): sec_export.visible = true
			"image":
				if is_instance_valid(sec_align): sec_align.visible = true
				if is_instance_valid(transform_panel): transform_panel.visible = true
				if is_instance_valid(sec_appearance): sec_appearance.visible = true
				if is_instance_valid(sec_typography): sec_typography.visible = false
				if is_instance_valid(sec_parametric_circle): sec_parametric_circle.visible = false
				if is_instance_valid(sec_parametric_star): sec_parametric_star.visible = false
				if is_instance_valid(sec_parametric_rect): sec_parametric_rect.visible = false
				if is_instance_valid(sec_3d_model): sec_3d_model.visible = false
				if is_instance_valid(sec_fill): sec_fill.visible = false
				if is_instance_valid(sec_stroke): sec_stroke.visible = false
				if is_instance_valid(sec_effects): sec_effects.visible = true
				if is_instance_valid(sec_export): sec_export.visible = true
			"group":
				if is_instance_valid(sec_align): sec_align.visible = true
				if is_instance_valid(transform_panel): transform_panel.visible = true
				if is_instance_valid(sec_appearance): sec_appearance.visible = true
				if is_instance_valid(sec_typography): sec_typography.visible = false
				if is_instance_valid(sec_parametric_circle): sec_parametric_circle.visible = false
				if is_instance_valid(sec_parametric_star): sec_parametric_star.visible = false
				if is_instance_valid(sec_parametric_rect): sec_parametric_rect.visible = false
				if is_instance_valid(sec_3d_model): sec_3d_model.visible = false
				if is_instance_valid(sec_fill): sec_fill.visible = false
				if is_instance_valid(sec_stroke): sec_stroke.visible = false
				if is_instance_valid(sec_effects): sec_effects.visible = true
				if is_instance_valid(sec_export): sec_export.visible = true
			_: # "shape", "multi"
				if is_instance_valid(sec_align): sec_align.visible = true
				if is_instance_valid(transform_panel): transform_panel.visible = true
				if is_instance_valid(sec_appearance): sec_appearance.visible = true
				if is_instance_valid(sec_typography): sec_typography.visible = false
				if is_instance_valid(sec_parametric_circle): sec_parametric_circle.visible = false
				if is_instance_valid(sec_parametric_star): sec_parametric_star.visible = false
				if is_instance_valid(sec_parametric_rect): sec_parametric_rect.visible = false
				if is_instance_valid(sec_3d_model): sec_3d_model.visible = false
				if is_instance_valid(sec_fill):
					sec_fill.visible = true
					var hdr = sec_fill.get_child(0) if sec_fill.get_child_count() > 0 else null
					if hdr and hdr.get_child_count() > 0 and hdr.get_child(0) is Label:
						hdr.get_child(0).text = "FILL"
				if is_instance_valid(sec_stroke): sec_stroke.visible = true
				if is_instance_valid(sec_effects): sec_effects.visible = true
				if is_instance_valid(sec_export): sec_export.visible = true

		if count == 1:
			var props: Dictionary = ic.current_props() if ic else {}
			var sname = props.get("name", {}).get("value", "Rectangle")
			lbl_title.text = str(sname)
			lbl_selection.text = "1 object selected"
		else:
			lbl_title.text = "Selection"
			lbl_selection.text = "%d objects selected" % count

		var show_bool: bool = count > 1 or (sel_node != null and sel_node is VectorBooleanScript)
		if is_instance_valid(_boolean_header):
			_boolean_header.visible = show_bool
		if is_instance_valid(_boolean_bar_panel):
			_boolean_bar_panel.visible = show_bool

func _on_inspector_changed(props: Dictionary) -> void:
	_syncing = true
	if is_instance_valid(picker_fill) and props.has("fill_color") and not props["fill_color"].get("mixed", false):
		var col: Color = props["fill_color"]["value"]
		picker_fill.color = col
		if is_instance_valid(lbl_fill_hex):
			lbl_fill_hex.text = "#" + col.to_html(false).to_upper()
	if is_instance_valid(spin_opacity) and props.has("opacity") and not props["opacity"].get("mixed", false):
		spin_opacity.value = float(props["opacity"]["value"]) * 100.0
	if is_instance_valid(picker_stroke) and props.has("stroke_color") and not props["stroke_color"].get("mixed", false):
		picker_stroke.color = props["stroke_color"]["value"]
	if is_instance_valid(spin_stroke_width) and props.has("stroke_width") and not props["stroke_width"].get("mixed", false):
		spin_stroke_width.value = float(props["stroke_width"]["value"])
	if props.has("visible") and not props["visible"].get("mixed", false):
		_current_item_visible = bool(props["visible"]["value"])
		if is_instance_valid(btn_toggle_visibility):
			btn_toggle_visibility.text = "👁" if _current_item_visible else "Ø"
	if is_instance_valid(spin_font_size) and props.has("font_size") and not props["font_size"].get("mixed", false):
		spin_font_size.value = float(props["font_size"]["value"])
	if is_instance_valid(opt_font_family) and props.has("font_family") and not props["font_family"].get("mixed", false):
		var ff: String = str(props["font_family"]["value"])
		for i in range(opt_font_family.item_count):
			if opt_font_family.get_item_text(i).to_lower() == ff.to_lower():
				opt_font_family.selected = i
				break
	if props.has("text_align") and not props["text_align"].get("mixed", false):
		_sync_text_align_buttons(str(props["text_align"]["value"]))
	if props.has("corner_radius") and not props["corner_radius"].get("mixed", false):
		var cr: float = float(props["corner_radius"]["value"])
		if is_instance_valid(spin_rect_corner_radius):
			spin_rect_corner_radius.value = cr
		if is_instance_valid(spin_star_corner_radius):
			spin_star_corner_radius.value = cr
	if props.has("shape_mode") and not props["shape_mode"].get("mixed", false):
		var smode: String = str(props["shape_mode"]["value"])
		var modes: Array[String] = ["whole", "arc", "pie", "chord", "donut"]
		var idx: int = modes.find(smode)
		if idx >= 0 and is_instance_valid(opt_circle_mode):
			opt_circle_mode.selected = idx
	if props.has("start_angle_deg") and not props["start_angle_deg"].get("mixed", false):
		if is_instance_valid(spin_circle_start_angle):
			spin_circle_start_angle.value = float(props["start_angle_deg"]["value"])
	if props.has("end_angle_deg") and not props["end_angle_deg"].get("mixed", false):
		if is_instance_valid(spin_circle_end_angle):
			spin_circle_end_angle.value = float(props["end_angle_deg"]["value"])
	if props.has("inner_radius_ratio") and not props["inner_radius_ratio"].get("mixed", false):
		var ratio_pct: float = float(props["inner_radius_ratio"]["value"]) * 100.0
		if is_instance_valid(spin_circle_inner_radius):
			spin_circle_inner_radius.value = ratio_pct
		if is_instance_valid(spin_star_inner_radius):
			spin_star_inner_radius.value = ratio_pct
	if props.has("points_count") and not props["points_count"].get("mixed", false):
		if is_instance_valid(spin_star_points):
			spin_star_points.value = float(props["points_count"]["value"])
	if props.has("model_path") and not props["model_path"].get("mixed", false):
		var mp: String = str(props["model_path"]["value"])
		if is_instance_valid(lbl_3d_path):
			lbl_3d_path.text = mp.get_file() if not mp.is_empty() else "Cubo (básico)"
	if props.has("model_rotation_x") and not props["model_rotation_x"].get("mixed", false):
		if is_instance_valid(spin_3d_rot_x):
			spin_3d_rot_x.value = float(props["model_rotation_x"]["value"])
	if props.has("model_rotation_y") and not props["model_rotation_y"].get("mixed", false):
		if is_instance_valid(spin_3d_rot_y):
			spin_3d_rot_y.value = float(props["model_rotation_y"]["value"])
	if props.has("model_rotation_z") and not props["model_rotation_z"].get("mixed", false):
		if is_instance_valid(spin_3d_rot_z):
			spin_3d_rot_z.value = float(props["model_rotation_z"]["value"])
	if props.has("camera_distance") and not props["camera_distance"].get("mixed", false):
		if is_instance_valid(spin_3d_distance):
			spin_3d_distance.value = float(props["camera_distance"]["value"])
	if props.has("camera_fov") and not props["camera_fov"].get("mixed", false):
		if is_instance_valid(spin_3d_fov):
			spin_3d_fov.value = float(props["camera_fov"]["value"])
	if props.has("light_energy") and not props["light_energy"].get("mixed", false):
		if is_instance_valid(spin_3d_light_energy):
			spin_3d_light_energy.value = float(props["light_energy"]["value"])
	_syncing = false

func _update_from_inspector() -> void:
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("current_props"):
		_on_inspector_changed(ic.current_props())
		if ic.has_method("selection"):
			_on_selection_size_changed(ic.selection().size())

func set_density(dense: bool) -> void:
	_is_dense = dense
	custom_minimum_size = Vector2(286, 0) if dense else Vector2(268, 0)
	if is_instance_valid(content_container):
		content_container.add_theme_constant_override("separation", 6 if dense else 10)

# ── GESTIÓN DEL POPOVER DE COLOR (PICKERCOLOR DE SMART) ──
func _ensure_color_popover() -> void:
	if is_instance_valid(_color_popover):
		return
	_color_popover = PanelContainer.new()
	_color_popover.top_level = true
	_color_popover.visible = false
	_color_popover.z_index = 250

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.98, 0.99, 1.0) if _C_TEXT.v < 0.5 else Color(0.14, 0.14, 0.15, 1.0)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = _C_BORDER_INPUT
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_color_popover.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_color_popover.add_child(vbox)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_popover_header_title = Label.new()
	_color_popover_header_title.text = "Color"
	_color_popover_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_popover_header_title.add_theme_font_size_override("font_size", 11)
	_color_popover_header_title.add_theme_color_override("font_color", _C_MUTED)
	header.add_child(_color_popover_header_title)

	var btn_close := _create_chip_button("✕", "Cerrar", Vector2(20, 20))
	btn_close.pressed.connect(func(): _color_popover.visible = false)
	header.add_child(btn_close)
	vbox.add_child(header)

	var scene := load("res://scenes/ui/pickr_color_tool.tscn")
	if scene:
		_pickr_instance = scene.instantiate() as GestorColor
		vbox.add_child(_pickr_instance)
		if _pickr_instance and _pickr_instance.has_signal("color_actualizado"):
			_pickr_instance.color_actualizado.connect(_on_popover_color_actualizado)

	add_child(_color_popover)

func _open_color_popover(target: String, anchor: Control) -> void:
	_ensure_color_popover()
	if not is_instance_valid(_color_popover):
		return
	if _color_popover.visible and _active_color_target == target:
		_color_popover.visible = false
		return

	_active_color_target = target
	if is_instance_valid(_color_popover_header_title):
		match target:
			"fill": _color_popover_header_title.text = "Relleno (Fill)"
			"stroke": _color_popover_header_title.text = "Trazo (Stroke)"
			"canvas": _color_popover_header_title.text = "Color de Lienzo"
			_: _color_popover_header_title.text = "Color"

	var cur_col: Color = Color.WHITE
	if target == "fill" and is_instance_valid(picker_fill):
		cur_col = picker_fill.color
	elif target == "stroke" and is_instance_valid(picker_stroke):
		cur_col = picker_stroke.color
	elif target == "canvas" and is_instance_valid(picker_canvas_bg):
		cur_col = picker_canvas_bg.color

	var cc = get_node_or_null("/root/ColorCore")
	if cc and cc.has_method("set_target"):
		cc.set_target(target)

	if is_instance_valid(_pickr_instance) and _pickr_instance.has_method("establecer_color"):
		_pickr_instance.establecer_color(cur_col, false)

	_color_popover.visible = true
	_color_popover.reset_size()

	var pop_w: float = _color_popover.size.x if _color_popover.size.x > 0 else 240.0
	var pos_x: float = global_position.x - pop_w - 8.0
	var pos_y: float = anchor.global_position.y - 20.0
	var vp_rect := get_viewport_rect()
	pos_y = clampf(pos_y, 40.0, maxf(40.0, vp_rect.size.y - _color_popover.size.y - 10.0))
	_color_popover.global_position = Vector2(pos_x, pos_y)

func _on_popover_color_actualizado(col: Color) -> void:
	match _active_color_target:
		"fill":
			if is_instance_valid(picker_fill):
				picker_fill.color = col
				picker_fill.color_changed.emit(col)
			_on_fill_color_changed(col)
		"stroke":
			if is_instance_valid(picker_stroke):
				picker_stroke.color = col
				picker_stroke.color_changed.emit(col)
			_on_stroke_color_changed(col)
		"canvas":
			if is_instance_valid(picker_canvas_bg):
				picker_canvas_bg.color = col
				picker_canvas_bg.color_changed.emit(col)
			_on_canvas_bg_changed(col)

func _input(event: InputEvent) -> void:
	if is_instance_valid(_color_popover) and _color_popover.visible:
		if event is InputEventMouseButton and event.pressed:
			var mp := get_global_mouse_position()
			if not _color_popover.get_global_rect().has_point(mp):
				var on_swatch: bool = false
				for b in [picker_fill, picker_stroke, picker_canvas_bg]:
					if is_instance_valid(b) and b.get_global_rect().has_point(mp):
						on_swatch = true
						break
				if not on_swatch:
					_color_popover.visible = false
