# =============================================================================
# VECTOPEN — UNIVERSAL COMMAND PALETTE (FIGMA UI3 STYLE)
# RUTA: res://script_gdscript/ui/modern/command_palette.gd
# Paleta modal de búsqueda de comandos rápidos, herramientas y acciones (Ctrl + K)
# =============================================================================
class_name CommandPalette
extends PanelContainer

signal command_executed(cmd_id: String)

var search_edit: LineEdit
var items_container: VBoxContainer
var scroll_container: ScrollContainer

var _commands: Array[Dictionary] = []
var _filtered_indices: Array[int] = []
var _selected_filtered_idx: int = 0

func _ready() -> void:
	_setup_styles()
	_register_default_commands()
	_build_ui()
	visible = false

func _setup_styles() -> void:
	custom_minimum_size = Vector2(460, 320)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.98, 0.99, 1.0)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.80, 0.80, 0.84, 1.0)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 20
	sb.shadow_offset = Vector2(0, 8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	add_theme_stylebox_override("panel", sb)

func _register_default_commands() -> void:
	_commands = [
		{"id": "tool_select", "name": "Select / Move Tool", "shortcut": "V", "category": "Tools", "action": func(): _switch_tool("select")},
		{"id": "tool_frame", "name": "Frame / Artboard Tool", "shortcut": "F", "category": "Tools", "action": func(): _switch_tool("artboard")},
		{"id": "tool_rectangle", "name": "Rectangle Tool", "shortcut": "R", "category": "Tools", "action": func(): _switch_tool("rectangle")},
		{"id": "tool_ellipse", "name": "Ellipse Tool", "shortcut": "O", "category": "Tools", "action": func(): _switch_tool("ellipse")},
		{"id": "tool_pen", "name": "Pen Tool", "shortcut": "P", "category": "Tools", "action": func(): _switch_tool("pen")},
		{"id": "tool_text", "name": "Text Tool", "shortcut": "T", "category": "Tools", "action": func(): _switch_tool("text")},
		{"id": "align_left", "name": "Align Left", "shortcut": "", "category": "Align", "action": func(): _align("left")},
		{"id": "align_center_h", "name": "Align Center Horizontal", "shortcut": "", "category": "Align", "action": func(): _align("center_h")},
		{"id": "align_right", "name": "Align Right", "shortcut": "", "category": "Align", "action": func(): _align("right")},
		{"id": "align_top", "name": "Align Top", "shortcut": "", "category": "Align", "action": func(): _align("top")},
		{"id": "align_middle", "name": "Align Center Vertical", "shortcut": "", "category": "Align", "action": func(): _align("middle")},
		{"id": "align_bottom", "name": "Align Bottom", "shortcut": "", "category": "Align", "action": func(): _align("bottom")},
		{"id": "zoom_100", "name": "Zoom to 100%", "shortcut": "Shift + 0", "category": "View", "action": func(): _set_zoom(100.0)},
		{"id": "zoom_in", "name": "Zoom In", "shortcut": "Ctrl + +", "category": "View", "action": func(): _zoom_delta(25.0)},
		{"id": "zoom_out", "name": "Zoom Out", "shortcut": "Ctrl + -", "category": "View", "action": func(): _zoom_delta(-25.0)},
		{"id": "undo", "name": "Undo", "shortcut": "Ctrl + Z", "category": "Edit", "action": func(): _undo()},
		{"id": "redo", "name": "Redo", "shortcut": "Ctrl + Y", "category": "Edit", "action": func(): _redo()},
		{"id": "ui_smart", "name": "Switch UI: Smart Panel (Canvas First)", "shortcut": "", "category": "Interface", "action": func(): _set_ui_mode("smart")},
		{"id": "ui_modern", "name": "Switch UI: Modern Panel (Figma Style)", "shortcut": "", "category": "Interface", "action": func(): _set_ui_mode("modern")},
		{"id": "ui_pro", "name": "Switch UI: Professional Panel (Affinity Style)", "shortcut": "", "category": "Interface", "action": func(): _set_ui_mode("professional")},
		{"id": "export", "name": "Export Document / Artboard", "shortcut": "Ctrl + E", "category": "File", "action": func(): _export_doc()},
		{"id": "import_3d", "name": "Import 3D Model (GLB / GLTF)...", "shortcut": "", "category": "File", "action": func(): _import_3d_model()},
	]

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Buscador
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Search Vectopen actions, tools, commands... (Esc to close)"
	search_edit.custom_minimum_size = Vector2(0, 34)
	search_edit.clear_button_enabled = true
	search_edit.add_theme_font_size_override("font_size", 12)
	search_edit.text_changed.connect(_on_search_text_changed)
	search_edit.gui_input.connect(_on_search_gui_input)
	vbox.add_child(search_edit)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# Lista de resultados con Scroll
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll_container)

	items_container = VBoxContainer.new()
	items_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_container.add_theme_constant_override("separation", 4)
	scroll_container.add_child(items_container)

func open_palette() -> void:
	visible = true
	_selected_filtered_idx = 0
	if is_instance_valid(search_edit):
		search_edit.text = ""
		search_edit.grab_focus()
	_refresh_list()

func close_palette() -> void:
	visible = false

func _on_search_text_changed(_new_text: String) -> void:
	_selected_filtered_idx = 0
	_refresh_list()

func _refresh_list() -> void:
	for c in items_container.get_children():
		c.queue_free()

	var query := search_edit.text.strip_edges().to_lower() if is_instance_valid(search_edit) else ""
	_filtered_indices.clear()

	for i in range(_commands.size()):
		var cmd = _commands[i]
		var cname: String = cmd["name"].to_lower()
		var cat: String = cmd["category"].to_lower()
		var sc: String = cmd["shortcut"].to_lower()

		if query == "" or cname.contains(query) or cat.contains(query) or sc.contains(query):
			_filtered_indices.append(i)

	for fi in range(_filtered_indices.size()):
		var orig_idx = _filtered_indices[fi]
		var cmd = _commands[orig_idx]

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 30)
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		var is_selected = (fi == _selected_filtered_idx)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.88, 0.88, 0.92, 1.0) if is_selected else Color(0.96, 0.96, 0.97, 0.5)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		btn.add_theme_stylebox_override("normal", sb)

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var cat_lbl := Label.new()
		cat_lbl.text = "[%s]" % cmd["category"]
		cat_lbl.add_theme_font_size_override("font_size", 10)
		cat_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.50, 1.0))
		row.add_child(cat_lbl)

		var name_lbl := Label.new()
		name_lbl.text = " " + cmd["name"]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color(0.12, 0.12, 0.15, 1.0))
		row.add_child(name_lbl)

		if cmd["shortcut"] != "":
			var sc_lbl := Label.new()
			sc_lbl.text = cmd["shortcut"]
			sc_lbl.add_theme_font_size_override("font_size", 10)
			sc_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60, 1.0))
			row.add_child(sc_lbl)

		btn.add_child(row)
		var target_fi = fi
		btn.pressed.connect(func(): _execute_filtered(target_fi))
		items_container.add_child(btn)

func _on_search_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return

	if event.keycode == KEY_ESCAPE:
		close_palette()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DOWN:
		if _filtered_indices.size() > 0:
			_selected_filtered_idx = (_selected_filtered_idx + 1) % _filtered_indices.size()
			_refresh_list()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_UP:
		if _filtered_indices.size() > 0:
			_selected_filtered_idx = (_selected_filtered_idx - 1 + _filtered_indices.size()) % _filtered_indices.size()
			_refresh_list()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if _filtered_indices.size() > 0:
			_execute_filtered(_selected_filtered_idx)
		get_viewport().set_input_as_handled()

func _execute_filtered(fi: int) -> void:
	if fi >= 0 and fi < _filtered_indices.size():
		var orig_idx = _filtered_indices[fi]
		var cmd = _commands[orig_idx]
		close_palette()
		cmd["action"].call()
		command_executed.emit(cmd["id"])

# ── Acciones de comandos ──────────────────────────────────────────────────────

func _switch_tool(tool_id: String) -> void:
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
		canvas.switch_tool(tool_id)

func _align(direction: String) -> void:
	var ic = get_node_or_null("/root/InspectorCore")
	if is_instance_valid(ic) and ic.has_method("align"):
		ic.align(direction)

func _set_zoom(pct: float) -> void:
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if is_instance_valid(canvas) and "zoom_percentage" in canvas:
		canvas.zoom_percentage = pct

func _zoom_delta(delta_pct: float) -> void:
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if is_instance_valid(canvas) and "zoom_percentage" in canvas:
		canvas.zoom_percentage = clamp(canvas.zoom_percentage + delta_pct, 10.0, 5000.0)

func _undo() -> void:
	var hm = get_node_or_null("/root/HistoryManager")
	if is_instance_valid(hm) and hm.has_method("undo"):
		hm.undo()

func _redo() -> void:
	var hm = get_node_or_null("/root/HistoryManager")
	if is_instance_valid(hm) and hm.has_method("redo"):
		hm.redo()

func _set_ui_mode(mode: String) -> void:
	if is_instance_valid(GlobalUI):
		GlobalUI.set_ui_mode(mode)

func _export_doc() -> void:
	var ge = get_node_or_null("/root/GlobalEvents")
	if is_instance_valid(ge) and ge.has_signal("request_export_dialog"):
		ge.emit_safe("request_export_dialog")

func _import_3d_model() -> void:
	var im = get_node_or_null("/root/ImportExportManager")
	if is_instance_valid(im) and im.has_method("import_3d_model"):
		im.import_3d_model()

