# =============================================================================
# VECTOPEN — PANEL DE CONFIGURACIÓN BÉZIER Y EDICIÓN DE NODOS
# RUTA: res://script_gdscript/ui/panel_bezier.gd
# Proporciona herramientas de manipulación de nodos estilo Affinity e Illustrator
# (Eliminar, Unir/Cerrar, Romper, Cúspide, Suave, Simétrico, Recto y Tamaño de Tiradores)
# =============================================================================
extends PanelContainer

signal closed

# Referencias UI
var _header_title: Label
var _btn_close: Button
var _status_label: Label

var _btn_delete: Button
var _btn_join: Button
var _btn_split: Button

var _btn_mode_sharp: Button
var _btn_mode_smooth: Button
var _btn_mode_symmetric: Button
var _btn_mode_retract: Button

var _btn_handle_small: Button
var _btn_handle_medium: Button
var _btn_handle_large: Button

var _chk_all_handles: CheckBox
var _chk_closed: CheckBox
var _spin_stroke_width: SpinBox

var _syncing: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(310, 0)
	_build_ui()
	_connect_events()
	_connect_theme()
	_apply_theme()
	_sync_from_selection()

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
	var sm = get_node_or_null("/root/SelectionManager")
	if sm and sm.has_signal("selection_changed") and not sm.selection_changed.is_connected(_on_selection_changed):
		sm.selection_changed.connect(_on_selection_changed)

	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_on_inspector_changed):
		ic.changed.connect(_on_inspector_changed)

	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("request_bezier_panel") and not ge.request_bezier_panel.is_connected(_on_request_bezier_panel):
		ge.request_bezier_panel.connect(_on_request_bezier_panel)

func _on_request_bezier_panel() -> void:
	visible = true
	move_to_front()
	_sync_from_selection()

func _on_selection_changed(_sel: Array) -> void:
	_sync_from_selection()

func _on_inspector_changed(_props: Dictionary) -> void:
	_sync_from_selection()

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
	_header_title.text = "Bézier & Nodos"
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_title.add_theme_font_size_override("font_size", 13)
	header.add_child(_header_title)

	# Sin botón ✕: ocultaba el panel y no había forma de volver a abrirlo
	# (se muestra solo con su herramienta).

	# Subtítulo informativo
	_status_label = Label.new()
	_status_label.text = "Selecciona un trazo o nodo"
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.modulate = Color(1, 1, 1, 0.6)
	root_vbox.add_child(_status_label)

	# 2. Tarjeta: Acciones de Nodos (Eliminar, Unir, Romper)
	var actions_card := _create_card("Acciones de Nodos")
	root_vbox.add_child(actions_card)
	var actions_box := actions_card.get_child(0) as VBoxContainer

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)
	actions_box.add_child(actions_row)

	_btn_delete = _create_action_button("🗑️ Eliminar (X)", "Elimina los nodos seleccionados (Atajo: X o Supr)")
	_btn_delete.pressed.connect(_on_btn_delete_pressed)
	actions_row.add_child(_btn_delete)

	_btn_join = _create_action_button("🔗 Unir / Cerrar", "Une extremos abiertos o cierra/abre la figura")
	_btn_join.pressed.connect(_on_btn_join_pressed)
	actions_row.add_child(_btn_join)

	_btn_split = _create_action_button("✂️ Romper", "Divide el trazo en los nodos seleccionados")
	_btn_split.pressed.connect(_on_btn_split_pressed)
	actions_row.add_child(_btn_split)

	# 3. Tarjeta: Conversión de Nodos (Affinity / Illustrator)
	var modes_card := _create_card("Tipo de Nodo")
	root_vbox.add_child(modes_card)
	var modes_box := modes_card.get_child(0) as VBoxContainer

	var modes_grid := GridContainer.new()
	modes_grid.columns = 2
	modes_grid.add_theme_constant_override("h_separation", 6)
	modes_grid.add_theme_constant_override("v_separation", 6)
	modes_box.add_child(modes_grid)

	_btn_mode_sharp = _create_action_button("📐 Cúspide (Sharp)", "Tiradores independientes en ángulo (esquinas pronunciadas)")
	_btn_mode_sharp.pressed.connect(func(): _apply_node_mode("sharp"))
	modes_grid.add_child(_btn_mode_sharp)

	_btn_mode_smooth = _create_action_button("〰️ Suave (Smooth)", "Tiradores opuestos alineados en tangente continua")
	_btn_mode_smooth.pressed.connect(func(): _apply_node_mode("smooth"))
	modes_grid.add_child(_btn_mode_smooth)

	_btn_mode_symmetric = _create_action_button("⚖️ Simétrico", "Tiradores alineados con igual longitud y curvatura uniforme")
	_btn_mode_symmetric.pressed.connect(func(): _apply_node_mode("symmetric"))
	modes_grid.add_child(_btn_mode_symmetric)

	_btn_mode_retract = _create_action_button("📏 Recto / Retirar", "Retira todos los tiradores, dejando un vértice recto")
	_btn_mode_retract.pressed.connect(func(): _apply_node_mode("retract"))
	modes_grid.add_child(_btn_mode_retract)

	# 4. Tarjeta: Ajustes de Tiradores y Visualización
	var handles_card := _create_card("Visualización de Tiradores")
	root_vbox.add_child(handles_card)
	var handles_box := handles_card.get_child(0) as VBoxContainer

	var handles_row := HBoxContainer.new()
	handles_row.add_theme_constant_override("separation", 6)
	handles_box.add_child(handles_row)

	_btn_handle_small = _create_toggle_button("Pequeño", true)
	_btn_handle_small.pressed.connect(func(): _set_handle_size("small"))
	handles_row.add_child(_btn_handle_small)

	_btn_handle_medium = _create_toggle_button("Medio", false)
	_btn_handle_medium.pressed.connect(func(): _set_handle_size("medium"))
	handles_row.add_child(_btn_handle_medium)

	_btn_handle_large = _create_toggle_button("Grande", false)
	_btn_handle_large.pressed.connect(func(): _set_handle_size("large"))
	handles_row.add_child(_btn_handle_large)

	_chk_all_handles = CheckBox.new()
	_chk_all_handles.text = "Mostrar tiradores siempre"
	_chk_all_handles.button_pressed = true
	_chk_all_handles.focus_mode = Control.FOCUS_NONE
	_chk_all_handles.toggled.connect(_on_all_handles_toggled)
	handles_box.add_child(_chk_all_handles)

	# 5. Tarjeta: Propiedades Rápidas del Trazo
	var stroke_card := _create_card("Trazo Activo")
	root_vbox.add_child(stroke_card)
	var stroke_box := stroke_card.get_child(0) as VBoxContainer

	var closed_row := HBoxContainer.new()
	stroke_box.add_child(closed_row)

	_chk_closed = CheckBox.new()
	_chk_closed.text = "Trazo Cerrado (Relleno)"
	_chk_closed.focus_mode = Control.FOCUS_NONE
	_chk_closed.toggled.connect(_on_closed_toggled)
	closed_row.add_child(_chk_closed)

	var stroke_w_row := HBoxContainer.new()
	stroke_box.add_child(stroke_w_row)

	var lbl_w := Label.new()
	lbl_w.text = "Grosor:"
	lbl_w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stroke_w_row.add_child(lbl_w)

	_spin_stroke_width = SpinBox.new()
	_spin_stroke_width.min_value = 0.5
	_spin_stroke_width.max_value = 100.0
	_spin_stroke_width.step = 0.5
	_spin_stroke_width.value = 2.0
	_spin_stroke_width.suffix = "px"
	_spin_stroke_width.value_changed.connect(_on_stroke_width_changed)
	stroke_w_row.add_child(_spin_stroke_width)

# ── Helpers de Creación de Widgets ────────────────────────────────────────────

func _create_card(title: String) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.08)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)

	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(lbl)

	return pc

func _create_action_button(text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(0, 28)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	return b

func _create_toggle_button(text: String, is_active: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = is_active
	b.custom_minimum_size = Vector2(0, 24)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	return b

# ── Lógica de Operaciones de Nodos y Trazo ─────────────────────────────────────

func _get_active_path() -> Path2D:
	var sm = get_node_or_null("/root/SelectionManager")
	if is_instance_valid(sm) and sm.has_method("get_selected"):
		for item in sm.get_selected():
			if item is Path2D and is_instance_valid(item.curve):
				return item

	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if is_instance_valid(canvas) and "current_tool" in canvas:
		var ct = canvas.current_tool
		if is_instance_valid(ct):
			if "edit_path" in ct and is_instance_valid(ct.edit_path):
				return ct.edit_path
			if "_last_path" in ct and is_instance_valid(ct._last_path):
				return ct._last_path
			if "current_path" in ct and is_instance_valid(ct.current_path):
				return ct.current_path

	return null

func _get_node_tool() -> NodeSelectionTool:
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if is_instance_valid(canvas) and "current_tool" in canvas:
		if canvas.current_tool is NodeSelectionTool:
			return canvas.current_tool
	return null

func _sync_from_selection() -> void:
	if _syncing:
		return
	_syncing = true

	var path := _get_active_path()
	var node_tool := _get_node_tool()

	if is_instance_valid(path) and is_instance_valid(path.curve):
		var n_pts = path.curve.point_count
		var n_sel = node_tool.selected_nodes.size() if is_instance_valid(node_tool) else 0
		_status_label.text = "%s: %d puntos (%d seleccionados)" % [path.name, n_pts, n_sel]

		if "closed" in path:
			_chk_closed.button_pressed = path.closed
		if "stroke_width" in path:
			_spin_stroke_width.value = path.stroke_width
	else:
		_status_label.text = "Ningún trazo Bézier seleccionado"

	_syncing = false

func _on_btn_delete_pressed() -> void:
	var node_tool := _get_node_tool()
	if is_instance_valid(node_tool):
		node_tool.delete_selected_nodes()
		_sync_from_selection()
		return

	# Fallback si estamos en beziertool
	var path := _get_active_path()
	if is_instance_valid(path) and is_instance_valid(path.curve) and path.curve.point_count > 0:
		path.curve.remove_point(path.curve.point_count - 1)
		path.queue_redraw()
		var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
		if canvas: canvas.queue_redraw()
		_sync_from_selection()

func _on_btn_join_pressed() -> void:
	var node_tool := _get_node_tool()
	if is_instance_valid(node_tool):
		node_tool.join_or_close_path()
		_sync_from_selection()
		return

	var path := _get_active_path()
	if is_instance_valid(path):
		if "closed" in path:
			path.closed = not path.closed
		path.queue_redraw()
		var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
		if canvas: canvas.queue_redraw()
		_sync_from_selection()

func _on_btn_split_pressed() -> void:
	var node_tool := _get_node_tool()
	if is_instance_valid(node_tool):
		node_tool.split_curve_at_selected()
		_sync_from_selection()

func _apply_node_mode(mode: String) -> void:
	var node_tool := _get_node_tool()
	if is_instance_valid(node_tool):
		node_tool.set_selected_nodes_mode(mode)
		_sync_from_selection()
		return

	# Si la herramienta de nodos no está activa, activarla y aplicar
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
		canvas.switch_tool("nodeselection")
		var nt := _get_node_tool()
		if is_instance_valid(nt):
			nt.set_selected_nodes_mode(mode)
			_sync_from_selection()

func _set_handle_size(size_name: String) -> void:
	_btn_handle_small.button_pressed = (size_name == "small")
	_btn_handle_medium.button_pressed = (size_name == "medium")
	_btn_handle_large.button_pressed = (size_name == "large")

	var r: float = 3.2
	match size_name:
		"small": r = 3.0
		"medium": r = 4.5
		"large": r = 6.0

	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if is_instance_valid(canvas):
		canvas.set_meta("bezier_handle_radius", r)
		canvas.queue_redraw()

func _on_all_handles_toggled(pressed: bool) -> void:
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if is_instance_valid(canvas):
		canvas.set_meta("bezier_show_all_handles", pressed)
		canvas.queue_redraw()

func _on_closed_toggled(pressed: bool) -> void:
	if _syncing: return
	var path := _get_active_path()
	if is_instance_valid(path):
		if "closed" in path:
			path.closed = pressed
		path.queue_redraw()
		var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
		if canvas: canvas.queue_redraw()

func _on_stroke_width_changed(val: float) -> void:
	if _syncing: return
	var path := _get_active_path()
	if is_instance_valid(path):
		if "stroke_width" in path:
			path.stroke_width = val
		path.queue_redraw()
		var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
		if canvas: canvas.queue_redraw()

# ── Aplicación de Tema ────────────────────────────────────────────────────────

func _apply_theme() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var is_dark: bool = true
	if tm and tm.has_method("is_dark_theme"):
		is_dark = tm.is_dark_theme()

	var bg_col := Color(0.14, 0.14, 0.17, 0.98) if is_dark else Color(0.96, 0.96, 0.97, 0.98)
	var border_col := Color(1, 1, 1, 0.12) if is_dark else Color(0, 0, 0, 0.12)
	var text_col := Color(0.95, 0.95, 0.95) if is_dark else Color(0.1, 0.1, 0.12)

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
