# =============================================================================
# VECTOPEN — MODERN CONTEXT MENU (FIGMA & PENPOT STYLE)
# RUTA: res://script_gdscript/ui/modern/modern_context_menu.gd
# Menú contextual vertical estilizado para Modern UI con atajos y separadores
# =============================================================================
class_name ModernContextMenu
extends PanelContainer

signal action_triggered(action_id: String)

var _vbox: VBoxContainer
var _items: Dictionary = {}

func _ready() -> void:
	top_level = true
	visible = false
	z_index = 300
	_setup_styles()
	_build_menu()

func _setup_styles() -> void:
	custom_minimum_size = Vector2(210, 0)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.13, 0.98) # #1e1e21 elegante oscuro
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.24, 0.24, 0.26, 1.0)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)

func _build_menu() -> void:
	for c in get_children():
		c.queue_free()
	
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 2)
	add_child(_vbox)

	# 1. Edición y portapapeles
	_add_menu_item("copy", "Copiar", "Ctrl+C")
	_add_menu_item("cut", "Cortar", "Ctrl+X")
	_add_menu_item("paste", "Pegar", "Ctrl+V")
	_add_menu_item("duplicate", "Duplicar", "Ctrl+D")

	_add_separator()

	# 2. Orden / Z-Index
	_add_menu_item("bring_to_front", "Traer al frente", "Ctrl+]")
	_add_menu_item("bring_forward", "Avanzar", "]")
	_add_menu_item("send_backward", "Retroceder", "[")
	_add_menu_item("send_to_back", "Enviar al fondo", "Ctrl+[")

	_add_separator()

	# 3. Transformación / Voltear
	_add_menu_item("flip_h", "Voltear horizontal", "Shift+H")
	_add_menu_item("flip_v", "Voltear vertical", "Shift+V")

	_add_separator()

	# 4. Estructura y Agrupación
	_add_menu_item("group", "Agrupar selección", "Ctrl+G")
	_add_menu_item("ungroup", "Desagrupar", "Ctrl+Shift+G")
	_add_menu_item("rename", "Renombrar", "F2")

	_add_separator()

	# 5. Visibilidad y Bloqueo
	_add_menu_item("toggle_visibility", "Ocultar / Mostrar", "Ctrl+Shift+H")
	_add_menu_item("toggle_lock", "Bloquear / Desbloquear", "Ctrl+Shift+L")

	_add_separator()

	# 6. Eliminar
	_add_menu_item("delete", "Eliminar", "Supr", Color(0.95, 0.4, 0.4, 1.0))

func _add_separator() -> void:
	var sep := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 0.08)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sep.add_theme_stylebox_override("separator", sb)
	sep.add_theme_constant_override("separation", 6)
	_vbox.add_child(sep)

func _add_menu_item(id: String, label: String, shortcut: String, custom_color: Color = Color.TRANSPARENT) -> void:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 26)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl_name := Label.new()
	lbl_name.text = label
	lbl_name.add_theme_font_size_override("font_size", 12)
	lbl_name.add_theme_color_override("font_color", custom_color if custom_color != Color.TRANSPARENT else Color(0.92, 0.92, 0.94, 1.0))
	lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl_name)

	if shortcut != "":
		var lbl_shortcut := Label.new()
		lbl_shortcut.text = shortcut
		lbl_shortcut.add_theme_font_size_override("font_size", 10)
		lbl_shortcut.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58, 1.0))
		hbox.add_child(lbl_shortcut)

	btn.add_child(hbox)

	var hov_sb := StyleBoxFlat.new()
	hov_sb.bg_color = Color(0.20, 0.20, 0.23, 1.0)
	hov_sb.set_corner_radius_all(5)
	hov_sb.content_margin_left = 6
	hov_sb.content_margin_right = 6
	btn.add_theme_stylebox_override("hover", hov_sb)

	var press_sb := StyleBoxFlat.new()
	press_sb.bg_color = Color(0.25, 0.25, 0.29, 1.0)
	press_sb.set_corner_radius_all(5)
	press_sb.content_margin_left = 6
	press_sb.content_margin_right = 6
	btn.add_theme_stylebox_override("pressed", press_sb)

	var empty_sb := StyleBoxEmpty.new()
	empty_sb.content_margin_left = 6
	empty_sb.content_margin_right = 6
	btn.add_theme_stylebox_override("normal", empty_sb)

	btn.pressed.connect(func():
		_execute_action(id)
	)

	_vbox.add_child(btn)
	_items[id] = btn

func popup_at(pos: Vector2) -> void:
	visible = true
	reset_size()
	var vp_size := get_viewport_rect().size
	var target_x: float = clampf(pos.x, 8.0, maxf(8.0, vp_size.x - custom_minimum_size.x - 8.0))
	var target_y: float = clampf(pos.y, 8.0, maxf(8.0, vp_size.y - size.y - 8.0))
	global_position = Vector2(target_x, target_y)

func _execute_action(id: String) -> void:
	visible = false
	action_triggered.emit(id)
	
	var mt = _move_tool()
	match id:
		"copy":
			if mt and mt.has_method("copy_selected"): mt.copy_selected()
		"cut":
			if mt and mt.has_method("cut_selected"): mt.cut_selected()
		"paste":
			if mt and mt.has_method("paste_clipboard"): mt.paste_clipboard()
		"duplicate":
			if mt and mt.has_method("duplicate_selected"): mt.duplicate_selected()
		"delete":
			if mt and mt.has_method("delete_selected"): mt.delete_selected()
		"bring_to_front":
			_arrange_nodes(func(n, p): p.move_child(n, p.get_child_count() - 1))
		"bring_forward":
			_arrange_nodes(func(n, p): p.move_child(n, min(n.get_index() + 1, p.get_child_count() - 1)))
		"send_backward":
			_arrange_nodes(func(n, p): p.move_child(n, max(0, n.get_index() - 1)))
		"send_to_back":
			_arrange_nodes(func(n, p): p.move_child(n, 0))
		"flip_h":
			if mt and mt.selected_shapes.size() > 0:
				for n in mt.selected_shapes:
					if is_instance_valid(n) and n is Node2D:
						n.scale.x = -n.scale.x
				if mt.canvas: mt.canvas.queue_redraw()
		"flip_v":
			if mt and mt.selected_shapes.size() > 0:
				for n in mt.selected_shapes:
					if is_instance_valid(n) and n is Node2D:
						n.scale.y = -n.scale.y
				if mt.canvas: mt.canvas.queue_redraw()
		"group":
			var ls = _layers_system()
			if ls and ls.has_method("_on_btn_group_selected"):
				ls._on_btn_group_selected()
		"ungroup":
			var ls = _layers_system()
			if ls and ls.has_method("_on_btn_ungroup"):
				ls._on_btn_ungroup()
		"rename":
			_rename_active_item()
		"toggle_visibility":
			var ic = get_node_or_null("/root/InspectorCore")
			if ic and ic.has_method("current_props") and ic.has_method("apply"):
				var p = ic.current_props()
				var cur_v: bool = bool(p["visible"]["value"]) if p.has("visible") else true
				ic.apply("visible", !cur_v)
		"toggle_lock":
			var ic = get_node_or_null("/root/InspectorCore")
			if ic and ic.has_method("current_props") and ic.has_method("apply"):
				var p = ic.current_props()
				var cur_l: bool = bool(p["locked"]["value"]) if p.has("locked") else false
				ic.apply("locked", !cur_l)

func _arrange_nodes(arrange_fn: Callable) -> void:
	var mt = _move_tool()
	if mt and mt.selected_shapes.size() > 0:
		for n in mt.selected_shapes:
			if is_instance_valid(n) and n.get_parent():
				arrange_fn.call(n, n.get_parent())
		if mt.canvas:
			mt.canvas.queue_redraw()
		var sm = get_node_or_null("/root/SelectionManager")
		if sm and sm.has_signal("selection_changed"):
			sm.selection_changed.emit(mt.selected_shapes)

func _rename_active_item() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	var props: Dictionary = ic.current_props()
	if not props.has("name"):
		return
	var le := LineEdit.new()
	le.text = String(props["name"]["value"])
	le.custom_minimum_size = Vector2(180, 26)
	le.size = le.custom_minimum_size
	add_child(le)
	le.global_position = get_global_mouse_position()
	le.select_all()
	le.grab_focus()
	le.text_submitted.connect(func(t: String):
		ic.apply("name", t)
		le.queue_free()
	)
	le.focus_exited.connect(func():
		if is_instance_valid(le):
			le.queue_free()
	)

func _move_tool():
	var canvas := get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if canvas and canvas.has_method("get_current_tool"):
		var t = canvas.get_current_tool()
		if t and t.has_method("get_class_name") and t.get_class_name() == "MoveTool":
			return t
	return null

func _layers_system():
	var ls := get_tree().get_first_node_in_group("layers_system") if get_tree() else null
	if ls == null and get_tree() and get_tree().current_scene:
		ls = get_tree().current_scene.find_child("LayersSystem", true, false)
	return ls

func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton and event.pressed:
		if not get_global_rect().has_point(event.global_position):
			visible = false
