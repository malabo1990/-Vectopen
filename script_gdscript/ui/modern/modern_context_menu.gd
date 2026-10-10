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
@export var show_quick_bar: bool = false

func _ready() -> void:
	top_level = true
	visible = false
	z_index = 300
	_setup_styles()
	_build_menu()
	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_mode):
			_setup_styles()
			_build_menu()
		)
	var lm = get_node_or_null("/root/LanguageManager")
	if lm and lm.has_signal("language_changed"):
		lm.language_changed.connect(func(_locale):
			_build_menu()
		)

func _setup_styles() -> void:
	custom_minimum_size = Vector2(250, 0)
	
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var bg_col: Color = tm.get_color(S.PANEL_SURFACE) if (tm and S) else Color(0.12, 0.12, 0.13, 0.98)
	var border_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color(0.24, 0.24, 0.26, 1.0)
	var is_dark: bool = bg_col.get_luminance() < 0.5

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = border_col
	sb.shadow_color = Color(0, 0, 0, 0.35) if is_dark else Color(0, 0, 0, 0.14)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)

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

func _create_vertical_micro_divider(color: Color) -> Control:
	var vsep := VSeparator.new()
	vsep.custom_minimum_size = Vector2(1, 14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	vsep.add_theme_stylebox_override("separator", sb)
	vsep.add_theme_constant_override("separation", 4)
	return vsep

func _add_quick_tool(parent: Control, id: String, icon_glyph: String, tooltip: String) -> Button:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var text_col: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color(0.92, 0.92, 0.94, 1.0)
	var hover_bg: Color = tm.get_color(S.BUTTON_HOVER) if (tm and S) else Color(0.20, 0.20, 0.23, 0.8)
	var press_bg: Color = tm.get_color(S.BUTTON_PRESSED) if (tm and S) else Color(0.15, 0.15, 0.18, 1.0)

	var btn := Button.new()
	btn.text = icon_glyph
	btn.tooltip_text = tr(tooltip)
	btn.custom_minimum_size = Vector2(24, 22)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", text_col)

	var empty_sb := StyleBoxEmpty.new()
	var hov_sb := StyleBoxFlat.new()
	hov_sb.bg_color = hover_bg
	hov_sb.set_corner_radius_all(4)

	var press_sb := StyleBoxFlat.new()
	press_sb.bg_color = press_bg
	press_sb.set_corner_radius_all(4)

	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", hov_sb)
	btn.add_theme_stylebox_override("pressed", press_sb)

	btn.pressed.connect(func():
		_execute_action(id)
	)

	parent.add_child(btn)
	if not _items.has(id):
		_items[id] = btn
	return btn

func _build_level_1_quick_bar(container: Control) -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var bg_input: Color = tm.get_color(S.INPUT_BG) if (tm and S) else Color(0.16, 0.16, 0.18, 1.0)
	var border_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color(0.24, 0.24, 0.26, 0.5)

	# Fila 1: Portapapeles, Estructura, Orden, Voltear
	var bar1_panel := PanelContainer.new()
	var bar1_sb := StyleBoxFlat.new()
	bar1_sb.bg_color = bg_input
	bar1_sb.set_corner_radius_all(6)
	bar1_sb.border_color = border_col
	bar1_sb.set_border_width_all(1)
	bar1_sb.set_content_margin_all(2)
	bar1_panel.add_theme_stylebox_override("panel", bar1_sb)
	container.add_child(bar1_panel)

	var bar1 := HBoxContainer.new()
	bar1.add_theme_constant_override("separation", 2)
	bar1.alignment = BoxContainer.ALIGNMENT_CENTER
	bar1_panel.add_child(bar1)

	_add_quick_tool(bar1, "cut", "✂", "Cortar (Ctrl+X)")
	_add_quick_tool(bar1, "copy", "📄", "Copiar (Ctrl+C)")
	_add_quick_tool(bar1, "paste", "📋", "Pegar (Ctrl+V)")
	_add_quick_tool(bar1, "duplicate", "⧉", "Duplicar (Ctrl+D)")

	bar1.add_child(_create_vertical_micro_divider(border_col))

	_add_quick_tool(bar1, "group", "⊞", "Agrupar selección (Ctrl+G)")
	_add_quick_tool(bar1, "ungroup", "⊟", "Desagrupar (Ctrl+Shift+G)")

	bar1.add_child(_create_vertical_micro_divider(border_col))

	_add_quick_tool(bar1, "bring_forward", "↑", "Avanzar (])")
	_add_quick_tool(bar1, "send_backward", "↓", "Retroceder ([)")

	bar1.add_child(_create_vertical_micro_divider(border_col))

	_add_quick_tool(bar1, "flip_h", "⇄", "Voltear horizontal (Shift+H)")
	_add_quick_tool(bar1, "flip_v", "⇅", "Voltear vertical (Shift+V)")

	# Fila 2: Barra de Alineación y Distribución rápida
	var bar2_panel := PanelContainer.new()
	var bar2_sb := StyleBoxFlat.new()
	bar2_sb.bg_color = bg_input
	bar2_sb.set_corner_radius_all(6)
	bar2_sb.border_color = border_col
	bar2_sb.set_border_width_all(1)
	bar2_sb.set_content_margin_all(2)
	bar2_panel.add_theme_stylebox_override("panel", bar2_sb)
	container.add_child(bar2_panel)

	var bar2 := HBoxContainer.new()
	bar2.add_theme_constant_override("separation", 2)
	bar2.alignment = BoxContainer.ALIGNMENT_CENTER
	bar2_panel.add_child(bar2)

	_add_quick_tool(bar2, "align_left", "⇤", "Alinear a la izquierda")
	_add_quick_tool(bar2, "align_center_h", "⇥⇤", "Alinear al centro horizontal")
	_add_quick_tool(bar2, "align_right", "⇥", "Alinear a la derecha")
	_add_quick_tool(bar2, "align_top", "⤒", "Alinear arriba")
	_add_quick_tool(bar2, "align_middle", "⤓⤒", "Alinear al centro vertical")
	_add_quick_tool(bar2, "align_bottom", "⤓", "Alinear abajo")
	_add_quick_tool(bar2, "dist_h", "⇹", "Distribuir horizontalmente")
	_add_quick_tool(bar2, "dist_v", "⇳", "Distribuir verticalmente")

## Object-specific actions. Only actions ContextMenuActions really executes.
func _build_level_2_contextual_items(kind: String) -> void:
	match kind:
		"shape":
			_add_menu_item("invert_fill_stroke", "Invertir trazo / relleno", "Shift+X")
			_add_separator()
		"text":
			_add_menu_item("align_text_left", "Alinear texto izquierda", "")
			_add_menu_item("align_text_center", "Centrar texto", "")
			_add_menu_item("align_text_right", "Alinear texto derecha", "")
			_add_separator()
		"group":
			_add_menu_item("ungroup_all", "Desagrupar todo", "Ctrl+Shift+G")
			_add_separator()
		"multi":
			_add_menu_item("distribute_horizontal", "Distribuir horizontal", "")
			_add_menu_item("distribute_vertical", "Distribuir vertical", "")
			_add_separator()

func _build_menu() -> void:
	for c in get_children():
		c.queue_free()
	_items.clear()

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 2)
	add_child(_vbox)

	# ── NIVEL 1: MICROBARRA RÁPIDA (HORIZONTAL COMPACTA) ──
	if show_quick_bar:
		_build_level_1_quick_bar(_vbox)
		_add_separator()

	# ── NIVEL 2: MENÚ CONTEXTUAL EXTENDIDO SEGÚN OBJETO ──
	var kind := _get_selected_kind()
	_build_level_2_contextual_items(kind)

	# 1. Edición y portapapeles
	_add_menu_item("copy", "Copy", "Ctrl+C")
	_add_menu_item("cut", "Cortar", "Ctrl+X")
	_add_menu_item("paste", "Paste", "Ctrl+V")
	_add_menu_item("duplicate", "Duplicate", "Ctrl+D")

	_add_separator()

	# 2. Orden / Z-Index
	_add_menu_item("bring_to_front", "Bring to Front", "Ctrl+Shift+]")
	_add_menu_item("bring_forward", "Avanzar", "Ctrl+]")
	_add_menu_item("send_backward", "Retroceder", "Ctrl+[")
	_add_menu_item("send_to_back", "Send to Back", "Ctrl+Shift+[")

	_add_separator()

	# 3. Transformación / Voltear
	_add_menu_item("flip_h", "Flip Horizontal", "Shift+H")
	_add_menu_item("flip_v", "Flip Vertical", "Shift+V")

	_add_separator()

	# 4. Estructura y Agrupación
	_add_menu_item("group", "Agrupar selección", "Ctrl+G")
	_add_menu_item("ungroup", "Desagrupar", "Ctrl+Shift+G")
	_add_menu_item("rename", "Rename", "F2")

	_add_separator()

	# 5. Visibilidad y Bloqueo
	_add_menu_item("toggle_visibility", "Ocultar / Mostrar", "Ctrl+Shift+H")
	_add_menu_item("toggle_lock", "Bloquear", "Ctrl+Shift+L")

	_add_separator()

	# 6. Eliminar
	_add_menu_item("delete", "Remove", "Supr")

	_add_separator()

	# 7. Tema de la interfaz
	_build_theme_switcher(_vbox)
	_add_menu_item("toggle_theme", "Alternar Tema (Claro / Oscuro)", "F10")

## Theme row: one neutral swatch per theme (its panel color), no emoji.
func _build_theme_switcher(container: Control) -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if not tm:
		return
	var S = tm.Slot
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.custom_minimum_size = Vector2(0, 26)
	container.add_child(hbox)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(22, 0)
	hbox.add_child(pad)
	var lbl := Label.new()
	lbl.text = tr("Tema:")
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", tm.get_color(S.TEXT_SECONDARY))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)

	for tid in ["light", "dark", "dark_contrast", "godot_blue", "blender_gray"]:
		var palette: Dictionary = tm.THEMES[tid]
		var b := Button.new()
		b.tooltip_text = tr(String(tm.THEME_LABELS.get(tid, tid)))
		b.custom_minimum_size = Vector2(16, 16)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.focus_mode = Control.FOCUS_NONE
		var active: bool = tm.current_mode == tid
		var dot := StyleBoxFlat.new()
		dot.bg_color = palette[S.PANEL_BG]
		dot.set_corner_radius_all(8)
		dot.set_border_width_all(2 if active else 1)
		dot.border_color = tm.get_color(S.PANEL_TEXT) if active else tm.get_color(S.BORDER_STRONG)
		b.add_theme_stylebox_override("normal", dot)
		var hov := dot.duplicate() as StyleBoxFlat
		hov.border_color = tm.get_color(S.PANEL_TEXT)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", hov)
		b.pressed.connect(func():
			tm.set_mode(tid)
			visible = false
		)
		hbox.add_child(b)

## Low-contrast hairline with breathing room, easier on low-vision users.
func _add_separator() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var col: Color = tm.get_color(S.BORDER) if (tm and S) else Color(1.0, 1.0, 1.0, 0.08)
	col.a *= 0.6
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = col
	line.thickness = 1
	line.grow_begin = -8
	line.grow_end = -8
	sep.add_theme_stylebox_override("separator", line)
	sep.add_theme_constant_override("separation", 9)
	_vbox.add_child(sep)

const _MENU_ICON_DIR := "res://icon/UI/menu/"
const _ICON_ALIASES := {"ungroup_all": "ungroup", "distribute_horizontal": "flip_h", "distribute_vertical": "flip_v"}

func _add_menu_item(id: String, label: String, shortcut: String) -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var text_col: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color(0.92, 0.92, 0.94, 1.0)
	var muted_col: Color = tm.get_color(S.TEXT_MUTED) if (tm and S) else Color(0.55, 0.55, 0.58, 1.0)
	var icon_col: Color = tm.get_color(S.ICON_PRIMARY) if (tm and S) else text_col
	var hover_bg: Color = tm.get_color(S.BUTTON_HOVER) if (tm and S) else Color(0.20, 0.20, 0.23, 0.8)
	var press_bg: Color = tm.get_color(S.BUTTON_PRESSED) if (tm and S) else Color(0.15, 0.15, 0.18, 1.0)

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 26)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 8
	hbox.offset_right = -10
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Monochrome line icon, same color for every entry
	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(16, 16)
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_path: String = _MENU_ICON_DIR + String(_ICON_ALIASES.get(id, id)) + ".svg"
	icon_rect.texture = ProUIStyle.icon(icon_path, icon_col, 16)
	hbox.add_child(icon_rect)

	var lbl_name := Label.new()
	lbl_name.name = "Name"
	lbl_name.text = tr(label)
	lbl_name.add_theme_font_size_override("font_size", 12)
	lbl_name.add_theme_color_override("font_color", text_col)
	lbl_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl_name)

	# Shortcut: plain muted text pushed to the far right edge
	if shortcut != "":
		var lbl_shortcut := Label.new()
		lbl_shortcut.name = "Shortcut"
		lbl_shortcut.text = shortcut
		lbl_shortcut.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_shortcut.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl_shortcut.add_theme_font_size_override("font_size", 11)
		lbl_shortcut.add_theme_color_override("font_color", muted_col)
		hbox.add_child(lbl_shortcut)

	btn.add_child(hbox)
	# The row is anchored (not a container child), so size the button from it
	btn.custom_minimum_size.x = hbox.get_combined_minimum_size().x + 18.0

	var hov_sb := StyleBoxFlat.new()
	hov_sb.bg_color = hover_bg
	hov_sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hov_sb)
	var press_sb := StyleBoxFlat.new()
	press_sb.bg_color = press_bg
	press_sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("pressed", press_sb)
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var enabled := ContextMenuActions.is_enabled(id, self)
	btn.disabled = not enabled
	btn.modulate.a = 1.0 if enabled else 0.4
	btn.pressed.connect(func():
		_execute_action(id)
	)

	_vbox.add_child(btn)
	_items[id] = btn

func popup_at(pos: Vector2) -> void:
	_setup_styles()
	_build_menu()
	visible = true
	reset_size()
	var vp_size := get_viewport_rect().size
	var target_x: float = clampf(pos.x, 8.0, maxf(8.0, vp_size.x - size.x - 8.0))
	var target_y: float = clampf(pos.y, 8.0, maxf(8.0, vp_size.y - size.y - 8.0))
	global_position = Vector2(target_x, target_y)

func _execute_action(id: String) -> void:
	visible = false
	action_triggered.emit(id)
	ContextMenuActions.execute(id, self)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		if get_viewport():
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if not get_global_rect().has_point(event.global_position):
			visible = false
