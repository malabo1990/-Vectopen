# ==========================================
# RUTA: res://scripts/managercolor_pickrColor.gd
# ==========================================
extends PanelContainer
class_name GestorColor

# 1. Referencias de Interfaz
@export var nodo_color_rect: ColorRect
@export var _brillo_slider: VSlider
@export var picker_panel: Panel
@export var gradient_editor: Control
@export var tab_solid: Button
@export var tab_linear: Button
@export var tab_radial: Button
@export var tab_conic: Button
@export var tab_diamond: Button
@export var tab_box: Button
@export var tab_spiral: Button
@export var tab_reflected: Button
@export var mode_dropdown: Button
@export var btn_mode_circle: Button
@export var btn_mode_triangle: Button
@export var btn_mode_square: Button
@export var style_tab_active: StyleBox
@export var style_tab_inactive: StyleBox
@export var style_circle_panel: StyleBox
@export var style_empty_panel: StyleBox

# 2. Señal local por si algún sub-nodo de la herramienta quiere escuchar de forma directa
signal color_actualizado(nuevo_color: Color)

var _from_core: bool = false
var current_tab: String = "solid"

# ── Eyedropper: pick any color visible in the window ──
const _EYEDROPPER_ICON := "res://icon/UI/menu/eyedropper.svg"
const _EYEDROPPER_CURSOR := preload("res://icon/UI/cursor/eyedropper.svg")
var _btn_eyedropper: Button = null
var _eyedropper_active: bool = false

func _ready() -> void:
	if _brillo_slider:
		_brillo_slider.value_changed.connect(_on_brillo_changed)
		_on_brillo_changed(_brillo_slider.value)
	
	if is_instance_valid(nodo_color_rect):
		_notificar_cambio_color(nodo_color_rect.color)
	
	if GlobalEvents.has_signal("gradient_changed") and not GlobalEvents.gradient_changed.is_connected(_on_global_gradient_changed):
		GlobalEvents.gradient_changed.connect(_on_global_gradient_changed)

	var cc := get_node_or_null("/root/ColorCore")
	if cc:
		if cc.has_signal("changed") and not cc.changed.is_connected(_on_colorcore_changed):
			cc.changed.connect(_on_colorcore_changed)
		if cc.has_signal("paint_changed") and not cc.paint_changed.is_connected(_on_colorcore_paint_changed):
			cc.paint_changed.connect(_on_colorcore_paint_changed)

	var tm := get_node_or_null("/root/ThemeManager")
	if tm:
		if tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)
		if tm.has_signal("color_slot_changed") and not tm.color_slot_changed.is_connected(_on_color_slot_changed):
			tm.color_slot_changed.connect(_on_color_slot_changed)

	_build_eyedropper_button()
	_conectar_controles_ui()
	_aplicar_tema()

func _on_theme_changed(_mode: String) -> void:
	_aplicar_tema()

func _on_color_slot_changed(_slot: String, _col: Color) -> void:
	_aplicar_tema()

func _aplicar_tema() -> void:
	if not is_inside_tree():
		return
	var tm := get_node_or_null("/root/ThemeManager")
	if not tm:
		return
	var S = tm.Slot
	var surface_col: Color = tm.get_color(S.PANEL_SURFACE)
	var border_col: Color = tm.get_color(S.BORDER)
	var is_dark: bool = tm.is_dark()

	# 1. Fondo sólido para el panel flotante (evita transparencia hacia el fondo)
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = surface_col
	rsb.border_color = border_col
	rsb.set_border_width_all(1)
	rsb.set_corner_radius_all(12)
	rsb.shadow_color = Color(0, 0, 0, 0.35 if is_dark else 0.08)
	rsb.shadow_size = 12
	rsb.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", rsb)

	_update_tab_styles()
	_update_mode_styles()

func _conectar_controles_ui() -> void:
	if tab_solid: tab_solid.pressed.connect(_on_tab_pressed.bind("solid"))
	if tab_linear: tab_linear.pressed.connect(_on_tab_pressed.bind("linear"))
	if tab_radial: tab_radial.pressed.connect(_on_tab_pressed.bind("radial"))
	if tab_conic: tab_conic.pressed.connect(_on_tab_pressed.bind("conic"))
	if tab_diamond: tab_diamond.pressed.connect(_on_tab_pressed.bind("diamond"))
	if tab_box: tab_box.pressed.connect(_on_tab_pressed.bind("box"))
	if tab_spiral: tab_spiral.pressed.connect(_on_tab_pressed.bind("spiral"))
	if tab_reflected: tab_reflected.pressed.connect(_on_tab_pressed.bind("reflected"))

	if mode_dropdown:
		if mode_dropdown is OptionButton:
			if not (mode_dropdown as OptionButton).item_selected.is_connected(_on_mode_dropdown_selected):
				(mode_dropdown as OptionButton).item_selected.connect(_on_mode_dropdown_selected)
		elif mode_dropdown is MenuButton:
			var pop: PopupMenu = (mode_dropdown as MenuButton).get_popup()
			if pop and not pop.id_pressed.is_connected(_on_mode_dropdown_selected):
				pop.id_pressed.connect(_on_mode_dropdown_selected)
		elif mode_dropdown is Button:
			if not (mode_dropdown as Button).pressed.is_connected(_on_mode_button_pressed):
				(mode_dropdown as Button).pressed.connect(_on_mode_button_pressed)
	if btn_mode_circle and not btn_mode_circle.pressed.is_connected(_on_mode_pressed):
		btn_mode_circle.pressed.connect(_on_mode_pressed.bind(0))
	if btn_mode_triangle and not btn_mode_triangle.pressed.is_connected(_on_mode_pressed):
		btn_mode_triangle.pressed.connect(_on_mode_pressed.bind(1))
	if btn_mode_square and not btn_mode_square.pressed.is_connected(_on_mode_pressed):
		btn_mode_square.pressed.connect(_on_mode_pressed.bind(2))

	if picker_panel and picker_panel.has_signal("color_changed"):
		if not picker_panel.color_changed.is_connected(_on_picker_color_changed):
			picker_panel.color_changed.connect(_on_picker_color_changed)

	if gradient_editor:
		if gradient_editor.has_signal("stop_selected"):
			if not gradient_editor.stop_selected.is_connected(_on_gradient_stop_selected):
				gradient_editor.stop_selected.connect(_on_gradient_stop_selected)
		if gradient_editor.has_method("get_gradient"):
			gradient_editor.visible = (current_tab != "solid")

	if GlobalEvents and GlobalEvents.has_signal("gradient_stop_selected"):
		if not GlobalEvents.gradient_stop_selected.is_connected(_on_canvas_stop_selected):
			GlobalEvents.gradient_stop_selected.connect(_on_canvas_stop_selected)

	_update_tab_styles()
	_update_mode_styles()
	if is_instance_valid(picker_panel) and picker_panel.has_method("get_picker_mode"):
		_apply_mode_layout(picker_panel.get_picker_mode())

func _on_mode_dropdown_selected(idx: int) -> void:
	_on_mode_pressed(idx)

func _on_mode_button_pressed() -> void:
	var next_m: int = 0
	if is_instance_valid(picker_panel) and picker_panel.has_method("get_picker_mode"):
		next_m = (picker_panel.get_picker_mode() + 1) % 3
	_on_mode_pressed(next_m)

func _on_tab_pressed(tab_name: String) -> void:
	var prev_tab := current_tab
	current_tab = tab_name
	_update_tab_styles()
	if current_tab == "solid":
		if is_instance_valid(gradient_editor):
			gradient_editor.visible = false
		var col: Color = nodo_color_rect.color if is_instance_valid(nodo_color_rect) else Color.WHITE
		establecer_color(col, true)
		var cc := get_tree().root.get_node_or_null("ColorCore") if (is_inside_tree() and get_tree() and get_tree().root) else null
		# Sólido en el objetivo activo. Antes forzaba «relleno» y el trazo
		# nunca cogía el color (bug: "trazos no puede añadir color").
		if cc and cc.has_method("set_paint"):
			cc.set_paint({"type": "solid", "color": col}, "")
		_deactivate_canvas_gradient_mode()
	else:
		if is_instance_valid(gradient_editor):
			gradient_editor.visible = true
			var g_type: int = 0
			if current_tab == "radial":
				g_type = 1
			elif current_tab in ["conic", "angular", "sweep"]:
				g_type = 2
			elif current_tab == "diamond":
				g_type = 3
			elif current_tab in ["box", "square"]:
				g_type = 4
			elif current_tab == "spiral":
				g_type = 5
			elif current_tab in ["reflected", "reflexionado"]:
				g_type = 6
			gradient_editor.gradient_type = g_type
			# Si venimos de sólido y tenemos un color base, inicializamos el degradado desde ese color
			if prev_tab == "solid" and is_instance_valid(nodo_color_rect):
				var base_col: Color = nodo_color_rect.color
				var g := Gradient.new()
				g.set_color(0, base_col)
				g.set_color(1, Color.WHITE if base_col.get_luminance() < 0.6 else Color(0.1, 0.1, 0.1, 1.0))
				_sync_gradient_guard = true
				gradient_editor.set_gradient_resource(g, g_type)
				_sync_gradient_guard = false
			if gradient_editor.has_method("_emit_gradient"):
				gradient_editor._emit_gradient()

func _deactivate_canvas_gradient_mode() -> void:
	if not is_inside_tree() or not get_tree():
		return
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas")
	if canvas and canvas.has_method("get_current_tool"):
		var cur_tool = canvas.get_current_tool()
		if cur_tool and "is_gradient_mode" in cur_tool:
			cur_tool.is_gradient_mode = false
		if cur_tool and "_bounding_box" in cur_tool and is_instance_valid(cur_tool._bounding_box):
			if cur_tool._bounding_box.has_method("deactivate_gradient_mode"):
				cur_tool._bounding_box.deactivate_gradient_mode()
	var tm := get_tree().root.get_node_or_null("ToolManager") if get_tree().root else null
	if tm and tm.has_method("get_active_tool"):
		var t = tm.get_active_tool()
		if t and "is_gradient_mode" in t:
			t.is_gradient_mode = false

func _on_mode_pressed(mode_idx: int) -> void:
	if is_instance_valid(picker_panel) and picker_panel.has_method("set_picker_mode"):
		picker_panel.set_picker_mode(mode_idx)
	if is_instance_valid(mode_dropdown):
		if mode_dropdown is OptionButton:
			if (mode_dropdown as OptionButton).selected != mode_idx:
				(mode_dropdown as OptionButton).select(mode_idx)
		elif mode_dropdown is MenuButton:
			var pop: PopupMenu = (mode_dropdown as MenuButton).get_popup()
			if pop:
				for i in range(pop.item_count):
					pop.set_item_checked(i, i == mode_idx)
	_update_mode_styles()
	_apply_mode_layout(mode_idx)

func _apply_mode_layout(mode_idx: int) -> void:
	if not is_instance_valid(picker_panel):
		return

	var parent_panel := picker_panel.get_parent() as Panel
	var root_box := parent_panel.get_parent() if parent_panel else null
	if root_box:
		var opacity_box = root_box.get_node_or_null("Circle_color_opasity")
		var wb_box = root_box.get_node_or_null("Circle_colorWB")
		# Sliders laterales obsoletos ocultos siempre (el selector HSV ya integra SV y alfa)
		if opacity_box: opacity_box.visible = false
		if wb_box: wb_box.visible = false

	if parent_panel:
		var target_style: StyleBox = style_empty_panel if mode_idx == 2 else style_circle_panel
		if target_style:
			parent_panel.add_theme_stylebox_override("panel", target_style)
			picker_panel.add_theme_stylebox_override("panel", target_style)

var _sync_gradient_guard: bool = false

func _on_picker_color_changed(new_color: Color) -> void:
	if current_tab != "solid" and is_instance_valid(gradient_editor):
		if is_instance_valid(nodo_color_rect):
			nodo_color_rect.color = new_color
		if not _sync_gradient_guard and gradient_editor.has_method("update_selected_stop_color"):
			_sync_gradient_guard = true
			gradient_editor.update_selected_stop_color(new_color)
			_sync_gradient_guard = false
	else:
		establecer_color(new_color, true)

func _apply_btn_style(btn: Button, is_active: bool) -> void:
	if not is_instance_valid(btn):
		return
	var tm := get_node_or_null("/root/ThemeManager") if is_inside_tree() else null
	var S = tm.Slot if tm else null
	var text_col: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color(0.12, 0.12, 0.16, 1.0)
	var muted_col: Color = tm.get_color(S.TEXT_SECONDARY) if (tm and S) else Color(0.50, 0.52, 0.58, 1.0)
	var accent_col: Color = tm.get_color(S.ACCENT) if (tm and S) else Color(0.04, 0.52, 1.0, 1.0)
	var surface_col: Color = tm.get_color(S.SURFACE_RAISED) if (tm and S) else Color(0.9, 0.9, 0.92, 1.0)
	var bg_col: Color = tm.get_color(S.BUTTON_BG) if (tm and S) else Color(0.96, 0.96, 0.98, 1.0)
	var border_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color(0.85, 0.85, 0.88, 1.0)

	var sb := StyleBoxFlat.new()
	sb.bg_color = surface_col if is_active else bg_col
	sb.border_color = accent_col if is_active else border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2

	var sb_hov := sb.duplicate() as StyleBoxFlat
	sb_hov.bg_color = tm.get_color(S.BUTTON_HOVER) if (tm and S) else surface_col

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_hov)
	btn.add_theme_stylebox_override("pressed", sb)

	btn.modulate = Color.WHITE
	btn.remove_theme_color_override("icon_normal_color")
	btn.remove_theme_color_override("icon_hover_color")
	btn.remove_theme_color_override("icon_pressed_color")
	btn.add_theme_color_override("font_color", text_col if is_active else muted_col)
	btn.add_theme_font_size_override("font_size", 11)

func _update_tab_styles() -> void:
	_apply_btn_style(tab_solid, current_tab == "solid")
	_apply_btn_style(tab_linear, current_tab == "linear")
	_apply_btn_style(tab_radial, current_tab == "radial")
	if is_instance_valid(tab_conic):
		_apply_btn_style(tab_conic, current_tab in ["conic", "angular", "sweep"])
	if is_instance_valid(tab_diamond):
		_apply_btn_style(tab_diamond, current_tab == "diamond")
	if is_instance_valid(tab_box):
		_apply_btn_style(tab_box, current_tab in ["box", "square"])
	if is_instance_valid(tab_spiral):
		_apply_btn_style(tab_spiral, current_tab == "spiral")
	if is_instance_valid(tab_reflected):
		_apply_btn_style(tab_reflected, current_tab in ["reflected", "reflexionado"])

func _update_mode_styles() -> void:
	var tm := get_node_or_null("/root/ThemeManager") if is_inside_tree() else null
	var S = tm.Slot if tm else null
	var btn_bg: Color = tm.get_color(S.BUTTON_BG) if (tm and S) else Color(0.18, 0.18, 0.21, 1.0)
	var btn_hov: Color = tm.get_color(S.BUTTON_HOVER) if (tm and S) else Color(0.24, 0.24, 0.28, 1.0)
	var border_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color(0.24, 0.24, 0.26, 1.0)
	var panel_text: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color(0.94, 0.94, 0.96, 1.0)
	var input_bg: Color = tm.get_color(S.INPUT_BG) if (tm and S) else Color(0.11, 0.11, 0.13, 1.0)
	var input_border: Color = tm.get_color(S.INPUT_BORDER) if (tm and S) else Color(0.24, 0.24, 0.27, 1.0)
	var icon_primary: Color = tm.get_color(S.ICON_PRIMARY) if (tm and S) else Color(0.9, 0.9, 0.92, 1.0)
	var accent_col: Color = tm.get_color(S.ACCENT) if (tm and S) else Color(0.04, 0.52, 1.0, 1.0)

	# 1. LineEdit Hex (#3366E6)
	var line_edit := find_child("LineEdit_dataColor", true, false) as LineEdit
	if line_edit:
		var lesb := StyleBoxFlat.new()
		lesb.bg_color = input_bg
		lesb.border_color = input_border
		lesb.set_border_width_all(1)
		lesb.set_corner_radius_all(6)
		lesb.content_margin_left = 6
		lesb.content_margin_right = 6
		line_edit.add_theme_stylebox_override("normal", lesb)
		line_edit.add_theme_stylebox_override("focus", lesb)
		line_edit.add_theme_color_override("font_color", panel_text)

	# 2. Botón copiar hex
	var btn_copy := find_child("Button", true, false) as Button
	if btn_copy and btn_copy.get_parent() and btn_copy.get_parent().name == "BoxContainer":
		var csb := StyleBoxFlat.new()
		csb.bg_color = btn_bg
		csb.border_color = border_col
		csb.set_border_width_all(1)
		csb.set_corner_radius_all(6)
		csb.set_content_margin_all(4)
		btn_copy.add_theme_stylebox_override("normal", csb)
		var csb_h := csb.duplicate() as StyleBoxFlat
		csb_h.bg_color = btn_hov
		btn_copy.add_theme_stylebox_override("hover", csb_h)
		if btn_copy.icon and tm and tm.has_method("make_white_icon"):
			btn_copy.icon = tm.make_white_icon(btn_copy.icon, 14)
		btn_copy.modulate = Color.WHITE
		btn_copy.add_theme_color_override("icon_normal_color", icon_primary)
		btn_copy.add_theme_color_override("icon_hover_color", panel_text)

	# 2b. Eyedropper (same chip as copy; accent outline while picking)
	if is_instance_valid(_btn_eyedropper):
		var esb := StyleBoxFlat.new()
		esb.bg_color = btn_bg
		esb.border_color = accent_col if _eyedropper_active else border_col
		esb.set_border_width_all(1)
		esb.set_corner_radius_all(6)
		esb.set_content_margin_all(3)
		_btn_eyedropper.add_theme_stylebox_override("normal", esb)
		_btn_eyedropper.add_theme_stylebox_override("pressed", esb)
		var esb_h := esb.duplicate() as StyleBoxFlat
		esb_h.bg_color = btn_hov
		_btn_eyedropper.add_theme_stylebox_override("hover", esb_h)
		_btn_eyedropper.add_theme_stylebox_override("hover_pressed", esb_h)
		_btn_eyedropper.icon = ProUIStyle.icon(_EYEDROPPER_ICON, accent_col if _eyedropper_active else icon_primary, 14)

	# 3. ModeDropdown
	if is_instance_valid(mode_dropdown):
		var msb := StyleBoxFlat.new()
		msb.bg_color = btn_bg
		msb.border_color = border_col
		msb.set_border_width_all(1)
		msb.set_corner_radius_all(6)
		msb.set_content_margin_all(4)
		mode_dropdown.add_theme_stylebox_override("normal", msb)
		var msb_h := msb.duplicate() as StyleBoxFlat
		msb_h.bg_color = btn_hov
		mode_dropdown.add_theme_stylebox_override("hover", msb_h)
		if mode_dropdown.icon and tm and tm.has_method("make_white_icon"):
			mode_dropdown.icon = tm.make_white_icon(mode_dropdown.icon, 14)
		mode_dropdown.modulate = Color.WHITE
		mode_dropdown.add_theme_color_override("icon_normal_color", icon_primary)

	# 4. Botón paleta circular debajo de la rueda
	var btn_pal := find_child("Button_palleteColor", true, false) as Button
	if btn_pal:
		var psb := StyleBoxFlat.new()
		psb.bg_color = btn_bg
		psb.border_color = border_col
		psb.set_border_width_all(1)
		psb.set_corner_radius_all(14)
		btn_pal.add_theme_stylebox_override("normal", psb)
		var psb_h := psb.duplicate() as StyleBoxFlat
		psb_h.bg_color = btn_hov
		btn_pal.add_theme_stylebox_override("hover", psb_h)
		if btn_pal.icon and tm and tm.has_method("make_white_icon"):
			btn_pal.icon = tm.make_white_icon(btn_pal.icon, 16)
		btn_pal.modulate = Color.WHITE
		btn_pal.add_theme_color_override("icon_normal_color", icon_primary)
		btn_pal.add_theme_color_override("icon_hover_color", accent_col)

	# 5. Botón "+" de añadir a paleta en GridContainer
	var btn_add := find_child("Button_add", true, false) as Button
	if btn_add:
		var asb := StyleBoxFlat.new()
		asb.bg_color = btn_bg
		asb.border_color = border_col
		asb.set_border_width_all(1)
		asb.set_corner_radius_all(4)
		btn_add.add_theme_stylebox_override("normal", asb)
		var asb_h := asb.duplicate() as StyleBoxFlat
		asb_h.bg_color = btn_hov
		btn_add.add_theme_stylebox_override("hover", asb_h)
		btn_add.add_theme_color_override("font_color", panel_text)
		btn_add.add_theme_color_override("font_hover_color", accent_col)

	if not is_instance_valid(picker_panel) or not picker_panel.has_method("get_picker_mode"):
		return
	var cur_mode: int = picker_panel.get_picker_mode()
	if is_instance_valid(mode_dropdown):
		if mode_dropdown is OptionButton and mode_dropdown.selected != cur_mode:
			mode_dropdown.select(cur_mode)
		elif mode_dropdown is MenuButton:
			var pop: PopupMenu = (mode_dropdown as MenuButton).get_popup()
			if pop:
				for i in range(pop.item_count):
					pop.set_item_checked(i, i == cur_mode)
	if is_instance_valid(btn_mode_circle): _apply_btn_style(btn_mode_circle, cur_mode == 0)
	if is_instance_valid(btn_mode_triangle): _apply_btn_style(btn_mode_triangle, cur_mode == 1)
	if is_instance_valid(btn_mode_square): _apply_btn_style(btn_mode_square, cur_mode == 2)


func _on_gradient_stop_selected(c: Color) -> void:
	if _sync_gradient_guard:
		return
	_sync_gradient_guard = true
	if is_instance_valid(picker_panel) and picker_panel.has_method("set_color"):
		picker_panel.set_color(c)
	if is_instance_valid(nodo_color_rect):
		nodo_color_rect.color = c
	_sync_gradient_guard = false

func _on_canvas_stop_selected(c: Color, idx: int) -> void:
	if is_instance_valid(gradient_editor) and gradient_editor.has_method("select_stop_by_index"):
		_sync_gradient_guard = true
		gradient_editor.select_stop_by_index(idx)
		_sync_gradient_guard = false
	_on_gradient_stop_selected(c)

func _on_colorcore_paint_changed(paint: Dictionary) -> void:
	if _sync_gradient_guard:
		return
	var ptype: String = str(paint.get("type", "solid"))
	var norm_tab := ptype
	if ptype in ["angular", "sweep"]:
		norm_tab = "conic"
	elif ptype in ["square"]:
		norm_tab = "box"
	elif ptype in ["mirror", "reflexionado"]:
		norm_tab = "reflected"
	if norm_tab != current_tab:
		current_tab = norm_tab
		_update_tab_styles()
	if current_tab == "solid":
		if is_instance_valid(gradient_editor):
			gradient_editor.visible = false
		var col: Color = paint.get("color", nodo_color_rect.color if is_instance_valid(nodo_color_rect) else Color.WHITE)
		if is_instance_valid(nodo_color_rect):
			nodo_color_rect.color = col
		if is_instance_valid(picker_panel) and picker_panel.has_method("set_color"):
			_sync_gradient_guard = true
			picker_panel.set_color(col)
			_sync_gradient_guard = false
	else:
		if is_instance_valid(gradient_editor):
			gradient_editor.visible = true
			var g_type := 0
			if current_tab == "radial":
				g_type = 1
			elif current_tab in ["conic", "angular", "sweep"]:
				g_type = 2
			elif current_tab == "diamond":
				g_type = 3
			elif current_tab in ["box", "square"]:
				g_type = 4
			elif current_tab == "spiral":
				g_type = 5
			elif current_tab in ["reflected", "reflexionado"]:
				g_type = 6
			gradient_editor.gradient_type = g_type
			var ang: float = float(paint.get("angle", 0.0))
			var p0: Vector2 = paint.get("p0", Vector2(-1, -1))
			var p1: Vector2 = paint.get("p1", Vector2(-1, -1))
			var stops = paint.get("stops", [])
			if stops is Gradient:
				_sync_gradient_guard = true
				gradient_editor.set_gradient_resource(stops, g_type, ang, true, p0, p1)
				_sync_gradient_guard = false
			elif stops is Array and not stops.is_empty():
				var g := Gradient.new()
				for i in range(stops.size()):
					var s = stops[i]
					var off: float = 0.0
					var col: Color = Color.WHITE
					if s is Dictionary:
						off = float(s.get("offset", 0.0))
						col = s.get("color", Color.WHITE)
					elif s is Array and s.size() >= 2:
						off = float(s[0])
						col = s[1] if s[1] is Color else Color.WHITE
					if i < g.get_point_count():
						g.set_offset(i, off)
						g.set_color(i, col)
					else:
						g.add_point(off, col)
				while g.get_point_count() > stops.size() and g.get_point_count() > 1:
					g.remove_point(g.get_point_count() - 1)
				if g.get_point_count() >= 2:
					_sync_gradient_guard = true
					gradient_editor.set_gradient_resource(g, g_type, ang, true, p0, p1)
					_sync_gradient_guard = false

func _on_colorcore_changed(fill: Color, stroke: Color, target: String) -> void:
	if current_tab != "solid":
		return
	var c := stroke if target == "stroke" else fill
	# Solo reflejar visualmente — NO re-emitir al bus (evita realimentación).
	if is_instance_valid(nodo_color_rect) and nodo_color_rect.color != c:
		nodo_color_rect.color = c
		if is_instance_valid(picker_panel) and picker_panel.has_method("set_color"):
			_sync_gradient_guard = true
			picker_panel.set_color(c)
			_sync_gradient_guard = false
		# Sin color_actualizado: sus dueños (Pro, inspector de Modern) lo
		# devolvían a ColorCore con SU objetivo y los selectores se rebotaban
		# el color sin fin (desbordamiento de pila al pasar a «trazo»).

# 3. Función SET profesional (Modifica el color y lo comunica a todo tu motor)
func establecer_color(nuevo_color: Color, force: bool = false) -> void:
	if not is_instance_valid(nodo_color_rect):
		return

	if nodo_color_rect.color != nuevo_color or force:
		nodo_color_rect.color = nuevo_color
		if is_instance_valid(picker_panel) and picker_panel.has_method("set_color"):
			_sync_gradient_guard = true
			picker_panel.set_color(nuevo_color)
			_sync_gradient_guard = false
		_notificar_cambio_color(nuevo_color)
		# Puente al sistema core (aplica a la selección con undo).
		if not _from_core:
			if is_inside_tree():
				var tree := get_tree()
				var cc := tree.root.get_node_or_null("ColorCore") if tree and tree.root else null
				if cc and cc.has_method("set_color"):
					cc.set_color(nuevo_color)

# ── Eyedropper ───────────────────────────────────────────────────────────────
func _build_eyedropper_button() -> void:
	var line_edit := find_child("LineEdit_dataColor", true, false) as LineEdit
	if line_edit == null or is_instance_valid(_btn_eyedropper):
		return
	_btn_eyedropper = Button.new()
	_btn_eyedropper.name = "BtnEyedropper"
	_btn_eyedropper.custom_minimum_size = Vector2(24, 24)
	_btn_eyedropper.focus_mode = Control.FOCUS_NONE
	_btn_eyedropper.toggle_mode = true
	_btn_eyedropper.tooltip_text = tr("Cuentagotas: haz clic en cualquier parte para copiar su color (Esc cancela)")
	_btn_eyedropper.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_btn_eyedropper.toggled.connect(_set_eyedropper_active)
	line_edit.get_parent().add_child(_btn_eyedropper)
	line_edit.get_parent().move_child(_btn_eyedropper, line_edit.get_index() + 1)

func _set_eyedropper_active(on: bool) -> void:
	_eyedropper_active = on
	if is_instance_valid(_btn_eyedropper) and _btn_eyedropper.button_pressed != on:
		_btn_eyedropper.set_pressed_no_signal(on)
	if on:
		Input.set_custom_mouse_cursor(_EYEDROPPER_CURSOR, Input.CURSOR_ARROW, Vector2(3, 21))
		Input.set_custom_mouse_cursor(_EYEDROPPER_CURSOR, Input.CURSOR_MOVE, Vector2(3, 21))
		Input.set_custom_mouse_cursor(_EYEDROPPER_CURSOR, Input.CURSOR_POINTING_HAND, Vector2(3, 21))
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(null, Input.CURSOR_MOVE)
		Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
		# Let SmartCursor restore its own arrow if it uses one
		var sc := get_node_or_null("/root/SmartCursor")
		if sc and sc.has_method("_update_cursor"):
			sc._update_cursor()
	_update_mode_styles()

## Color of the rendered window at a viewport position (whatever is on screen:
## canvas, images, UI).
func sample_screen_color(viewport_pos: Vector2) -> Color:
	var vp := get_viewport()
	if vp == null:
		return Color.BLACK
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return Color.BLACK
	var vis := vp.get_visible_rect().size
	var k := Vector2(img.get_width() / maxf(vis.x, 1.0), img.get_height() / maxf(vis.y, 1.0))
	var px := Vector2i(clampi(int(viewport_pos.x * k.x), 0, img.get_width() - 1), clampi(int(viewport_pos.y * k.y), 0, img.get_height() - 1))
	var c := img.get_pixelv(px)
	c.a = 1.0
	return c

func apply_sampled_color(c: Color) -> void:
	if is_instance_valid(picker_panel) and picker_panel.has_method("set_color"):
		picker_panel.set_color(c)
	_on_picker_color_changed(c)

func _input(event: InputEvent) -> void:
	if not _eyedropper_active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_set_eyedropper_active(false)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Clicking the eyedropper button itself just toggles it off
			if is_instance_valid(_btn_eyedropper) and _btn_eyedropper.get_global_rect().has_point(event.position):
				return
			apply_sampled_color(sample_screen_color(event.position))
		_set_eyedropper_active(false)
		get_viewport().set_input_as_handled()

# 4. Función GET limpia para que las herramientas de dibujo lean el color plano activo
func obtener_color() -> Color:
	if is_instance_valid(nodo_color_rect):
		return nodo_color_rect.color
	return Color.WHITE

# ── Control de Brillo ────────────────────────────────────────────────────────

func _on_brillo_changed(valor: float) -> void:
	if not is_instance_valid(nodo_color_rect) or not _brillo_slider:
		return
	var c := nodo_color_rect.color
	var v := valor / _brillo_slider.max_value
	var nuevo := Color.from_hsv(c.h, c.s, v, c.a)
	if nuevo != c:
		establecer_color(nuevo)

# ── Gestión Interna de Eventos (Cero Bucle Process) ───────────────────────────

# Centraliza la transmisión del color a todas las capas y objetos seleccionados
func _notificar_cambio_color(color_final: Color) -> void:
	# A) Emitir señal local del componente
	color_actualizado.emit(color_final)
	
	# B) Notificar al motor de objetos vectoriales
	if "object_style_changed" in GlobalEvents:
		GlobalEvents.object_style_changed.emit()
	
	# C) Notificar a la paleta de colores para que se actualice en tiempo real
	if "color_changed" in GlobalEvents:
		GlobalEvents.color_changed.emit(color_final)

# Si el usuario modifica el degradado general, podemos sincronizar el color primario de fondo
func _on_global_gradient_changed(gradient: Gradient) -> void:
	if is_instance_valid(gradient) and is_instance_valid(nodo_color_rect):
		if current_tab != "solid":
			if is_instance_valid(gradient_editor) and not _sync_gradient_guard and gradient_editor.has_method("set_gradient_resource"):
				_sync_gradient_guard = true
				gradient_editor.set_gradient_resource(gradient, gradient_editor.gradient_type, gradient_editor.gradient_angle, true, gradient_editor.gradient_p0, gradient_editor.gradient_p1)
				_sync_gradient_guard = false
			var sel_color := gradient.get_color(0)
			if is_instance_valid(gradient_editor) and gradient_editor.get("selected_handle") != null:
				sel_color = gradient_editor.selected_handle.color
			if nodo_color_rect.color != sel_color:
				nodo_color_rect.color = sel_color
			return
		if gradient.get_point_count() > 0:
			var primer_color = gradient.get_color(0)
			if nodo_color_rect.color != primer_color:
				nodo_color_rect.color = primer_color
				color_actualizado.emit(primer_color)
