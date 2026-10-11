# =============================================================================
# VECTOPEN — GESTOR DE INTERFAZ ADAPTABLE (ADAPTIVE UI MANAGER)
# RUTA: res://script_gdscript/ui/adaptive_ui_manager.gd
# Coordina la disposicion reactiva de paneles segun el modo activo:
#   - smart: Canvas First (Canvas maximo, inspector dockeado oculto, menu contextual)
#   - modern: Inspector First & Bottom Toolbar (Figma UI3 style: Top Bar, Nav Rail,
#             Bottom Toolbar flotante, Docked Inspector, Ctrl+K Command Palette, Tab Focus Canvas)
#   - professional: Full Panels (Alta densidad, herramientas y capas a la izquierda, inspector completo a la derecha)
# =============================================================================
class_name AdaptiveUIManager
extends Node

@export var docked_inspector: Control
@export var layout_node: Control
@export var tool_in_mouse: Control

# Componentes dedicados de Modern UI (Figma UI3 style)
@export var modern_bottom_toolbar: Control
@export var modern_top_bar: Control
@export var modern_nav_rail: Control
@export var command_palette: Control

# Componentes dedicados de Professional UI
@export var pro_studio: Control
@export var pro_top_bar: Control

# Professional layout metrics: compact docked panels under a full-width top bar
const PRO_TOP_H := 30.0
const PRO_LEFT_W := 320.0
const PRO_RIGHT_W := 272.0
# Modern layout: layers drawer docked flush to the left edge (no side rail)
const MODERN_LEFT_W := 260.0
## Separación estándar entre paneles flotantes y bordes / barras.
const EDGE_GAP := 10.0

# Elementos existentes de main.tscn a armonizar
@export var barra_visual_panel: Control
@export var logo_node: Control
@export var windows_regla: Control
@export var keyboard_node: Control
@export var control2_node: Control
@export var manager_windws_regla: Control

# Posiciones y anclajes por defecto de Layout para restaurar fielmente
var _default_layout_anchor_left: float = 1.0
var _default_layout_anchor_right: float = 1.0
var _default_layout_anchor_top: float = 0.5
var _default_layout_anchor_bottom: float = 0.5
var _default_layout_offset_left: float = -106.0
var _default_layout_offset_right: float = 0.0
var _default_layout_offset_top: float = -20.0
var _default_layout_offset_bottom: float = 20.0
var _default_layout_grow_horizontal: int = Control.GROW_DIRECTION_BEGIN

# Posiciones y anclajes por defecto del PanelContainer interno de Layout
var _default_inner_anchor_left: float = 1.0
var _default_inner_anchor_right: float = 1.0
var _default_inner_anchor_top: float = 0.5
var _default_inner_anchor_bottom: float = 0.5
var _default_inner_offset_left: float = -476.0
var _default_inner_offset_right: float = 0.0
var _default_inner_offset_top: float = -150.0
var _default_inner_offset_bottom: float = 300.0
var _default_inner_min_size: Vector2 = Vector2(0, 450)
var _default_inner_stylebox: StyleBox = null
var _default_margin_container_margins: Dictionary = {}

var _has_stored_defaults: bool = false

# Estado de modo Focus Canvas (Tab)
var _focus_canvas_active: bool = false
var _pre_focus_states: Dictionary = {}

# Smart UI: Controles de zoom compactos en BARRA_VISUAL
var _smart_btn_zoom_out: Button = null
var _smart_lbl_zoom: Label = null
var _smart_btn_zoom_in: Button = null
var _smart_cached_canvas = null
var _smart_last_synced_zoom: float = -1.0

func _process(_delta: float) -> void:
	_sync_smart_zoom_from_canvas()

func _ready() -> void:
	_resolve_nodes()
	_store_defaults()
	_connect_events()
	# Live keyboard / mouse chip (bottom-left, Smart mode)
	if is_instance_valid(keyboard_node) and keyboard_node.find_children("", "InputHud", false, false).is_empty():
		var hud := InputHud.new()
		hud.name = "InputHud"
		keyboard_node.add_child(hud)
	
	# Aplicar el modo actual configurado en GlobalUI
	var gui = get_node_or_null("/root/GlobalUI")
	var current_mode: String = gui.get_ui_mode() if is_instance_valid(gui) else "smart"
	apply_ui_mode(current_mode)

func _resolve_nodes() -> void:
	var parent := get_parent()
	if not is_instance_valid(parent):
		return
	
	if not is_instance_valid(docked_inspector):
		docked_inspector = parent.find_child("DockedInspector", true, false) as Control
	if not is_instance_valid(layout_node):
		layout_node = parent.find_child("Layout", true, false) as Control
	if not is_instance_valid(tool_in_mouse):
		tool_in_mouse = parent.find_child("tool_in_Mouse", true, false) as Control
	if not is_instance_valid(modern_bottom_toolbar):
		modern_bottom_toolbar = parent.find_child("ModernBottomToolbar", true, false) as Control
	if not is_instance_valid(modern_top_bar):
		modern_top_bar = parent.find_child("ModernTopBar", true, false) as Control
	if not is_instance_valid(modern_nav_rail):
		modern_nav_rail = parent.find_child("ModernNavRail", true, false) as Control
	if not is_instance_valid(command_palette):
		command_palette = parent.find_child("CommandPalette", true, false) as Control
	if not is_instance_valid(pro_studio):
		pro_studio = parent.find_child("ProStudio", true, false) as Control
		if not is_instance_valid(pro_studio):
			var scene := load("res://scenes/ui/pro/pro_studio.tscn")
			if scene:
				pro_studio = scene.instantiate() as Control
				pro_studio.name = "ProStudio"
				pro_studio.visible = false
				parent.add_child.call_deferred(pro_studio)
	if not is_instance_valid(pro_top_bar):
		pro_top_bar = parent.find_child("ProTopBar", true, false) as Control
		if not is_instance_valid(pro_top_bar):
			pro_top_bar = ProTopBar.new()
			pro_top_bar.name = "ProTopBar"
			pro_top_bar.visible = false
			parent.add_child.call_deferred(pro_top_bar)

	if not is_instance_valid(logo_node):
		logo_node = parent.find_child("Logo", true, false) as Control
	if not is_instance_valid(windows_regla):
		windows_regla = parent.find_child("windows_ recla", true, false) as Control
	if not is_instance_valid(keyboard_node):
		keyboard_node = parent.find_child("keyboard", true, false) as Control
	if not is_instance_valid(control2_node):
		control2_node = parent.find_child("Control2", true, false) as Control
	if not is_instance_valid(manager_windws_regla):
		manager_windws_regla = parent.find_child("MANAGER WINDWS_REGLA", true, false) as Control

	if not is_instance_valid(barra_visual_panel):
		var bv = parent.find_child("BARRA_VISUAL", true, false)
		if bv and bv.get_parent() and bv.get_parent().get_parent() is PanelContainer:
			barra_visual_panel = bv.get_parent().get_parent() as Control

func _store_defaults() -> void:
	if is_instance_valid(layout_node) and not _has_stored_defaults:
		_default_layout_anchor_left = layout_node.anchor_left
		_default_layout_anchor_right = layout_node.anchor_right
		_default_layout_anchor_top = layout_node.anchor_top
		_default_layout_anchor_bottom = layout_node.anchor_bottom
		_default_layout_offset_left = layout_node.offset_left
		_default_layout_offset_right = layout_node.offset_right
		_default_layout_offset_top = layout_node.offset_top
		_default_layout_offset_bottom = layout_node.offset_bottom
		_default_layout_grow_horizontal = layout_node.grow_horizontal

		var inner = layout_node.get_node_or_null("PanelContainer") as Control
		if inner:
			_default_inner_anchor_left = inner.anchor_left
			_default_inner_anchor_right = inner.anchor_right
			_default_inner_anchor_top = inner.anchor_top
			_default_inner_anchor_bottom = inner.anchor_bottom
			_default_inner_offset_left = inner.offset_left
			_default_inner_offset_right = inner.offset_right
			_default_inner_offset_top = inner.offset_top
			_default_inner_offset_bottom = inner.offset_bottom
			_default_inner_min_size = inner.custom_minimum_size
			if inner.has_theme_stylebox_override("panel"):
				_default_inner_stylebox = inner.get_theme_stylebox("panel")
			else:
				_default_inner_stylebox = null

			var margin_container = inner.get_node_or_null("MarginContainer") as MarginContainer
			if margin_container:
				_default_margin_container_margins = {
					"left": margin_container.get_theme_constant("margin_left"),
					"top": margin_container.get_theme_constant("margin_top"),
					"right": margin_container.get_theme_constant("margin_right"),
					"bottom": margin_container.get_theme_constant("margin_bottom")
				}

		_has_stored_defaults = true

func _connect_events() -> void:
	var gui = get_node_or_null("/root/GlobalUI")
	if is_instance_valid(gui) and gui.has_signal("ui_mode_changed"):
		if not gui.ui_mode_changed.is_connected(_on_ui_mode_changed):
			gui.ui_mode_changed.connect(_on_ui_mode_changed)

	var ge = get_node_or_null("/root/GlobalEvents")
	if is_instance_valid(ge) and ge.has_signal("request_settings_dialog"):
		if not ge.request_settings_dialog.is_connected(_on_request_settings_dialog):
			ge.request_settings_dialog.connect(_on_request_settings_dialog)

	_connect_nav_rail()

	# Arranque por fases: paneles que llegan después del primer fotograma.
	var phases := get_parent().get_node_or_null("StartupPhases") if get_parent() else null
	if phases and phases.has_signal("panel_added") and not phases.panel_added.is_connected(_on_phase_panel_added):
		phases.panel_added.connect(_on_phase_panel_added)

	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_mode):
			var g = get_node_or_null("/root/GlobalUI")
			var cur_mode: String = g.get_ui_mode() if is_instance_valid(g) else "smart"
			apply_ui_mode(cur_mode)
		)

	var lm = get_node_or_null("/root/LanguageManager")
	if lm and lm.has_signal("language_changed"):
		lm.language_changed.connect(func(_loc):
			if is_instance_valid(_smart_btn_zoom_out) and _smart_btn_zoom_out.has_meta("tooltip_key"):
				_smart_btn_zoom_out.tooltip_text = tr(String(_smart_btn_zoom_out.get_meta("tooltip_key")))
			if is_instance_valid(_smart_btn_zoom_in) and _smart_btn_zoom_in.has_meta("tooltip_key"):
				_smart_btn_zoom_in.tooltip_text = tr(String(_smart_btn_zoom_in.get_meta("tooltip_key")))
			if is_instance_valid(_smart_lbl_zoom) and _smart_lbl_zoom.has_meta("tooltip_key"):
				_smart_lbl_zoom.tooltip_text = tr(String(_smart_lbl_zoom.get_meta("tooltip_key")))
			if is_instance_valid(barra_visual_panel):
				var bv = barra_visual_panel.find_child("BARRA_VISUAL", true, false)
				if is_instance_valid(bv):
					for btn_name: String in ["Button", "Button2", "BUTTON_PEWVIEW"]:
						var b = bv.get_node_or_null(btn_name) as Button
						if is_instance_valid(b) and b.has_meta("tooltip_key"):
							b.tooltip_text = tr(String(b.get_meta("tooltip_key")))
		)

func _on_nav_rail_left_panel_toggled(is_open: bool) -> void:
	var gui = get_node_or_null("/root/GlobalUI")
	var is_modern: bool = is_instance_valid(gui) and gui.has_method("is_modern_mode") and gui.is_modern_mode()
	if is_modern and is_instance_valid(layout_node):
		layout_node.visible = is_open
		_update_modern_rulers(is_open)

func _on_nav_rail_section_selected(section_id: String) -> void:
	var gui = get_node_or_null("/root/GlobalUI")
	var is_modern: bool = is_instance_valid(gui) and gui.has_method("is_modern_mode") and gui.is_modern_mode()
	if not is_modern:
		return
	if section_id == "canvas":
		if is_instance_valid(layout_node):
			layout_node.visible = false
		_update_modern_rulers(false)
	elif section_id == "layers" or section_id == "assets":
		if is_instance_valid(layout_node):
			layout_node.visible = true
		_update_modern_rulers(true)
	elif section_id == "settings":
		_on_request_settings_dialog()

func _connect_nav_rail() -> void:
	if not is_instance_valid(modern_nav_rail):
		return
	if modern_nav_rail.has_signal("left_panel_toggled"):
		if not modern_nav_rail.left_panel_toggled.is_connected(_on_nav_rail_left_panel_toggled):
			modern_nav_rail.left_panel_toggled.connect(_on_nav_rail_left_panel_toggled)
	if modern_nav_rail.has_signal("section_selected"):
		if not modern_nav_rail.section_selected.is_connected(_on_nav_rail_section_selected):
			modern_nav_rail.section_selected.connect(_on_nav_rail_section_selected)

## StartupPhases añadió un panel (fase 2/3): localizarlo. En modo Smart todos
## llegan ocultos, igual que los dejaba _apply_smart_mode.
func _on_phase_panel_added(_panel: Control) -> void:
	_resolve_nodes()
	_connect_nav_rail()

func _on_request_settings_dialog() -> void:
	if not is_instance_valid(manager_windws_regla):
		_resolve_nodes()
	if not is_instance_valid(manager_windws_regla):
		# Abierto antes de la fase 3: crear ya la ventana de ajustes.
		var phases := get_parent().get_node_or_null("StartupPhases") if get_parent() else null
		if phases and phases.has_method("ensure"):
			phases.ensure("MANAGER WINDWS_REGLA")
			_resolve_nodes()
	if is_instance_valid(manager_windws_regla):
		if manager_windws_regla.has_method("toggle_settings"):
			if not manager_windws_regla.visible:
				_position_settings_dialog()
			manager_windws_regla.toggle_settings()
		else:
			manager_windws_regla.visible = !manager_windws_regla.visible
			if manager_windws_regla.visible:
				_position_settings_dialog()
				manager_windws_regla.move_to_front()

func _position_settings_dialog() -> void:
	if not is_instance_valid(manager_windws_regla):
		return
	var dialog_w: float = 480.0
	var dialog_h: float = 480.0
	var gui = get_node_or_null("/root/GlobalUI")
	var is_modern: bool = is_instance_valid(gui) and gui.has_method("is_modern_mode") and gui.is_modern_mode()
	if is_modern:
		var is_sidebar_open = is_instance_valid(layout_node) and layout_node.visible
		var left_x: float = (MODERN_LEFT_W + 24.0 + 16.0) if is_sidebar_open else (24.0 + 16.0)
		manager_windws_regla.offset_left = left_x
		manager_windws_regla.offset_right = left_x + dialog_w
		manager_windws_regla.offset_top = 24.0
		manager_windws_regla.offset_bottom = 24.0 + dialog_h
	else:
		manager_windws_regla.offset_left = 28.0
		manager_windws_regla.offset_right = 28.0 + dialog_w
		manager_windws_regla.offset_top = 28.0
		manager_windws_regla.offset_bottom = 28.0 + dialog_h

func _on_ui_mode_changed(new_mode: String) -> void:
	apply_ui_mode(new_mode)

func apply_ui_mode(mode: String) -> void:
	_resolve_nodes()
	_store_defaults()

	# Si estaba activo el modo Focus Canvas, restaurarlo
	if _focus_canvas_active:
		_focus_canvas_active = false

	match mode:
		"smart":
			_apply_smart_mode()
		"modern":
			_apply_modern_mode()
		"professional":
			_apply_professional_mode()
		_:
			_apply_smart_mode()

func _apply_smart_mode() -> void:
	# Smart Panel: Canvas First. Ocultar chrome de Modern UI y Docked Inspector
	_set_modern_ui_visible(false)
	
	if is_instance_valid(docked_inspector):
		docked_inspector.visible = false

	if is_instance_valid(pro_studio):
		pro_studio.visible = false
	if is_instance_valid(pro_top_bar):
		pro_top_bar.visible = false
	
	if is_instance_valid(barra_visual_panel):
		barra_visual_panel.visible = true

	if is_instance_valid(logo_node):
		logo_node.visible = true

	if is_instance_valid(keyboard_node):
		keyboard_node.visible = true

	if is_instance_valid(control2_node):
		control2_node.visible = true

	if is_instance_valid(windows_regla):
		windows_regla.offset_top = 0.0
		var regla_v = windows_regla.get_node_or_null("regla vertical") as Control
		if regla_v:
			regla_v.offset_left = 0.0
			regla_v.offset_right = 24.0
			regla_v.offset_top = 0.0
			regla_v.offset_bottom = 0.0
		var btn_settings = windows_regla.get_node_or_null("Button") as Control
		if btn_settings:
			btn_settings.offset_left = 0.0
			btn_settings.offset_right = 24.0
			btn_settings.offset_top = 0.0
			btn_settings.offset_bottom = 24.0
			btn_settings.custom_minimum_size = Vector2(24, 24)
			btn_settings.visible = true
		var regla_h = windows_regla.get_node_or_null("regla horizontal") as Control
		if regla_h:
			regla_h.offset_left = 0.0
			regla_h.offset_right = 0.0
		if is_instance_valid(manager_windws_regla):
			manager_windws_regla.offset_left = 24.0
			manager_windws_regla.offset_top = 24.0

	# Restaurar Layout y su PanelContainer al diseno original de Vectopen
	if is_instance_valid(layout_node) and _has_stored_defaults:
		layout_node.visible = true
		layout_node.anchor_left = _default_layout_anchor_left
		layout_node.anchor_right = _default_layout_anchor_right
		layout_node.anchor_top = _default_layout_anchor_top
		layout_node.anchor_bottom = _default_layout_anchor_bottom
		layout_node.offset_left = _default_layout_offset_left
		layout_node.offset_right = _default_layout_offset_right
		layout_node.offset_top = _default_layout_offset_top
		layout_node.offset_bottom = _default_layout_offset_bottom
		layout_node.grow_horizontal = _default_layout_grow_horizontal as Control.GrowDirection

		var inner = layout_node.get_node_or_null("PanelContainer") as Control
		if inner:
			inner.anchor_left = _default_inner_anchor_left
			inner.anchor_right = _default_inner_anchor_right
			inner.anchor_top = _default_inner_anchor_top
			inner.anchor_bottom = _default_inner_anchor_bottom
			# 10 px de aire con el borde derecho de la ventana (antes tocaba)
			inner.offset_right = -EDGE_GAP
			inner.offset_left = _default_inner_offset_left - _default_inner_offset_right - EDGE_GAP
			inner.offset_top = _default_inner_offset_top
			inner.offset_bottom = _default_inner_offset_bottom
			inner.custom_minimum_size = _default_inner_min_size
			inner.grow_horizontal = Control.GROW_DIRECTION_BEGIN

			# Estilo de Capas en Smart mode con radio redondeado y color de tema reactivo
			var tm = get_node_or_null("/root/ThemeManager")
			var S = tm.Slot if tm else null
			var sb := StyleBoxFlat.new()
			if tm and S:
				sb.bg_color = tm.get_color(S.PANEL_SURFACE)
				sb.border_color = tm.get_color(S.BORDER)
			else:
				sb.bg_color = Color(0.98, 0.98, 0.99, 1.0)
			if _default_inner_stylebox is StyleBoxFlat:
				sb.corner_radius_top_left = (_default_inner_stylebox as StyleBoxFlat).corner_radius_top_left
				sb.corner_radius_top_right = (_default_inner_stylebox as StyleBoxFlat).corner_radius_top_right
				sb.corner_radius_bottom_right = (_default_inner_stylebox as StyleBoxFlat).corner_radius_bottom_right
				sb.corner_radius_bottom_left = (_default_inner_stylebox as StyleBoxFlat).corner_radius_bottom_left
			else:
				sb.set_corner_radius_all(10)
			sb.set_border_width_all(1)
			inner.add_theme_stylebox_override("panel", sb)

			var margin_container = inner.get_node_or_null("MarginContainer") as MarginContainer
			if margin_container and not _default_margin_container_margins.is_empty():
				margin_container.add_theme_constant_override("margin_left", _default_margin_container_margins.get("left", 10))
				margin_container.add_theme_constant_override("margin_right", _default_margin_container_margins.get("right", 10))
				margin_container.add_theme_constant_override("margin_top", _default_margin_container_margins.get("top", 10))
				margin_container.add_theme_constant_override("margin_bottom", _default_margin_container_margins.get("bottom", 10))

			# Restaurar radios y tema en el panel de LayersSystem
			var layers_panel = inner.find_child("Panel", true, false) as Panel
			if layers_panel:
				var lsb := StyleBoxFlat.new()
				if tm and S:
					lsb.bg_color = tm.get_color(S.PANEL_SURFACE)
					lsb.border_color = tm.get_color(S.BORDER)
				else:
					lsb.bg_color = Color(0.98, 0.98, 0.99, 1.0)
					lsb.border_color = Color(0.88, 0.88, 0.90, 1.0)
				lsb.set_corner_radius_all(14)
				lsb.set_border_width_all(0)
				layers_panel.add_theme_stylebox_override("panel", lsb)

			var tools = inner.find_child("Herramientas", true, false) as Control
			if tools:
				tools.visible = true
			var toggle_ctrl = inner.get_node_or_null("Control") as Control
			if toggle_ctrl:
				toggle_ctrl.visible = true

	_update_toolbar_subpanels_direction(false)
	_theme_smart_floating_controls()
	_fit_smart_panel_height.call_deferred()

## Smart mode: the floating layers card has a fixed 450px height from the scene,
## but the vertical tool column is taller, so it used to poke out below the card.
## Grow the card so it always wraps the whole tool column.
func _fit_smart_panel_height() -> void:
	# Wait one frame so the containers have their final layout
	if is_inside_tree():
		await get_tree().process_frame
	var gui = get_node_or_null("/root/GlobalUI")
	if is_instance_valid(gui) and gui.get_ui_mode() != "smart":
		return
	if not is_instance_valid(layout_node):
		return
	var inner = layout_node.get_node_or_null("PanelContainer") as Control
	if inner == null:
		return
	var tools = inner.find_child("Herramientas", true, false) as Control
	if tools == null or not tools.visible:
		return
	# The tool column draws its own card as a child that isn't reflected in its
	# minimum size, so measure the lowest visible child directly.
	var bottom := tools.get_global_rect().end.y
	for c in tools.get_children():
		if c is Control and c.visible:
			bottom = maxf(bottom, (c as Control).get_global_rect().end.y)
	var margin_bottom := 0.0
	var mc = inner.get_node_or_null("MarginContainer") as MarginContainer
	if mc:
		margin_bottom = float(mc.get_theme_constant("margin_bottom"))
	var sb := inner.get_theme_stylebox("panel")
	if sb:
		margin_bottom += sb.get_margin(SIDE_BOTTOM)
	var needed: float = bottom - inner.global_position.y + margin_bottom
	if needed > inner.size.y + 0.5:
		inner.custom_minimum_size.y = needed
		inner.offset_bottom = inner.offset_top + needed

func _apply_modern_mode() -> void:
	# Modern Panel: Figma UI3 style.
	# Activar Top Bar, Nav Rail, Bottom Toolbar y Docked Inspector
	_set_modern_ui_visible(true)

	if is_instance_valid(pro_studio):
		pro_studio.visible = false
	if is_instance_valid(pro_top_bar):
		pro_top_bar.visible = false

	if is_instance_valid(barra_visual_panel):
		barra_visual_panel.visible = false

	if is_instance_valid(logo_node):
		logo_node.visible = false

	# Ocultar widgets flotantes de Smart UI (ej. chip de teclado abajo a la izquierda)
	if is_instance_valid(keyboard_node):
		keyboard_node.visible = false

	if is_instance_valid(control2_node):
		control2_node.visible = false

	if is_instance_valid(docked_inspector):
		docked_inspector.visible = true
		if docked_inspector.has_method("set_density"):
			docked_inspector.set_density(false)
		docked_inspector.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		docked_inspector.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		docked_inspector.grow_vertical = Control.GROW_DIRECTION_BOTH
		docked_inspector.anchor_left = 1.0
		docked_inspector.anchor_right = 1.0
		docked_inspector.anchor_top = 0.0
		docked_inspector.anchor_bottom = 1.0
		docked_inspector.offset_left = -268.0
		docked_inspector.offset_right = 0.0
		docked_inspector.offset_top = 36.0 # Bajo la ModernTopBar
		docked_inspector.offset_bottom = 0.0

	# Ajustar regla para que acompañe dinámicamente al sidebar y no se solape
	if is_instance_valid(windows_regla):
		windows_regla.offset_top = 36.0
		_update_modern_rulers(true)

	# Mover Layout / Capas al lateral izquierdo como drawer de capas (x = 42 a 302, y = 36 a fin)
	if is_instance_valid(layout_node):
		layout_node.visible = true
		layout_node.anchor_left = 0.0
		layout_node.anchor_right = 0.0
		layout_node.anchor_top = 0.0
		layout_node.anchor_bottom = 1.0
		layout_node.offset_left = 0.0
		layout_node.offset_right = MODERN_LEFT_W
		layout_node.offset_top = 36.0
		layout_node.offset_bottom = 0.0
		layout_node.grow_horizontal = Control.GROW_DIRECTION_END

		var inner = layout_node.get_node_or_null("PanelContainer") as Control
		if inner:
			inner.anchor_left = 0.0
			inner.anchor_right = 1.0
			inner.anchor_top = 0.0
			inner.anchor_bottom = 1.0
			inner.offset_left = 0.0
			inner.offset_right = 0.0
			inner.offset_top = 0.0
			inner.offset_bottom = 0.0
			inner.custom_minimum_size = Vector2(MODERN_LEFT_W, 0)

			# Capas en modo moderno: sin radios las esquinas (docking flat estilo Figma UI3)
			var sb := StyleBoxFlat.new()
			var tm = get_node_or_null("/root/ThemeManager")
			var S = tm.Slot if tm else null
			if tm and S:
				sb.bg_color = tm.get_color(S.PANEL_SURFACE)
				sb.border_color = tm.get_color(S.BORDER)
			else:
				sb.bg_color = Color(0.98, 0.98, 0.99, 1.0)
				sb.border_color = Color(0.88, 0.88, 0.90, 1.0)
			sb.set_corner_radius_all(0)
			sb.border_width_right = 1
			sb.border_width_left = 0
			sb.border_width_top = 0
			sb.border_width_bottom = 0
			sb.content_margin_left = 0
			sb.content_margin_right = 0
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
			inner.add_theme_stylebox_override("panel", sb)

			var margin_container = inner.get_node_or_null("MarginContainer") as MarginContainer
			if margin_container:
				margin_container.add_theme_constant_override("margin_left", 6)
				margin_container.add_theme_constant_override("margin_right", 6)
				margin_container.add_theme_constant_override("margin_top", 6)
				margin_container.add_theme_constant_override("margin_bottom", 6)

			# Quitar radios y aplicar tema en el panel interno de capas
			var layers_panel = inner.find_child("Panel", true, false) as Panel
			if layers_panel:
				var lsb := StyleBoxFlat.new()
				if tm and S:
					lsb.bg_color = tm.get_color(S.PANEL_SURFACE)
					lsb.border_color = tm.get_color(S.BORDER)
				else:
					lsb.bg_color = Color(0.98, 0.98, 0.99, 1.0)
					lsb.border_color = Color(0.88, 0.88, 0.90, 1.0)
				lsb.set_corner_radius_all(0)
				lsb.set_border_width_all(0)
				layers_panel.add_theme_stylebox_override("panel", lsb)

			# Herramientas verticales visibles en Modern UI y Pro UI
			var tools = inner.find_child("Herramientas", true, false) as Control
			if tools:
				tools.visible = true
			# Ocultar boton flotante de toggle original
			var toggle_ctrl = inner.get_node_or_null("Control") as Control
			if toggle_ctrl:
				toggle_ctrl.visible = false

	_update_toolbar_subpanels_direction(false, true)
	# ancho real de la barra (contenido) y reglas a su lado
	set_left_dock_width.call_deferred(-1.0)

func _apply_professional_mode() -> void:
	# Professional Panel: dense docked panels under a compact full-width top bar.
	# Ocultar la barra inferior de Modern UI
	_set_modern_ui_visible(false)

	if is_instance_valid(barra_visual_panel):
		barra_visual_panel.visible = false

	# The top bar replaces the floating logo in this mode
	if is_instance_valid(logo_node):
		logo_node.visible = false

	if is_instance_valid(pro_top_bar):
		pro_top_bar.visible = true
		pro_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
		pro_top_bar.offset_left = 0.0
		pro_top_bar.offset_right = 0.0
		pro_top_bar.offset_top = 0.0
		pro_top_bar.offset_bottom = PRO_TOP_H
		pro_top_bar.move_to_front()

	if is_instance_valid(keyboard_node):
		keyboard_node.visible = false

	if is_instance_valid(control2_node):
		control2_node.visible = false

	if is_instance_valid(windows_regla):
		windows_regla.offset_top = PRO_TOP_H
		var left_x: float = PRO_LEFT_W
		var regla_v = windows_regla.get_node_or_null("regla vertical") as Control
		if regla_v:
			regla_v.offset_left = left_x
			regla_v.offset_right = left_x + 24.0
			regla_v.offset_top = 24.0
			regla_v.offset_bottom = 0.0
		var btn_settings = windows_regla.get_node_or_null("Button") as Control
		if btn_settings:
			btn_settings.offset_left = left_x
			btn_settings.offset_right = left_x + 24.0
			btn_settings.offset_top = 0.0
			btn_settings.offset_bottom = 24.0
			btn_settings.custom_minimum_size = Vector2(24, 24)
			# Settings are reached from the top bar in this mode
			btn_settings.visible = false
		var regla_h = windows_regla.get_node_or_null("regla horizontal") as Control
		if regla_h:
			regla_h.offset_left = left_x + 24.0
			var right_offset: float = -PRO_RIGHT_W if is_instance_valid(pro_studio) else 0.0
			regla_h.offset_right = right_offset
		if windows_regla.has_method("_aplicar_estilo_tema"):
			windows_regla._aplicar_estilo_tema()

	# Ocultar inspector de Modern UI
	if is_instance_valid(docked_inspector):
		docked_inspector.visible = false

	# Activar ProStudio lateral derecho
	if is_instance_valid(pro_studio):
		pro_studio.visible = true
		pro_studio.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		pro_studio.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		pro_studio.grow_vertical = Control.GROW_DIRECTION_BOTH
		pro_studio.anchor_left = 1.0
		pro_studio.anchor_right = 1.0
		pro_studio.anchor_top = 0.0
		pro_studio.anchor_bottom = 1.0
		pro_studio.custom_minimum_size.x = PRO_RIGHT_W
		pro_studio.offset_left = -PRO_RIGHT_W
		pro_studio.offset_right = 0.0
		pro_studio.offset_top = PRO_TOP_H
		pro_studio.offset_bottom = 0.0

	# Barra de herramientas y capas acopladas a la izquierda con herramientas visibles
	if is_instance_valid(layout_node):
		layout_node.visible = true
		layout_node.anchor_left = 0.0
		layout_node.anchor_right = 0.0
		layout_node.anchor_top = 0.0
		layout_node.anchor_bottom = 1.0
		layout_node.offset_left = 0.0
		layout_node.offset_right = PRO_LEFT_W
		layout_node.offset_top = PRO_TOP_H
		layout_node.offset_bottom = 0.0
		layout_node.grow_horizontal = Control.GROW_DIRECTION_END

		var inner = layout_node.get_node_or_null("PanelContainer") as Control
		if inner:
			inner.anchor_left = 0.0
			inner.anchor_right = 1.0
			inner.anchor_top = 0.0
			inner.anchor_bottom = 1.0
			inner.offset_left = 0.0
			inner.offset_right = 0.0
			inner.offset_top = 0.0
			inner.offset_bottom = 0.0
			inner.custom_minimum_size = Vector2(PRO_LEFT_W, 0)

			# Same flat PANEL_BG as the Studio and top bar so the chrome reads as one frame
			var sb := StyleBoxFlat.new()
			var tm = get_node_or_null("/root/ThemeManager")
			var S = tm.Slot if tm else null
			if tm and S:
				sb.bg_color = tm.get_color(S.PANEL_BG)
				sb.border_color = tm.get_color(S.BORDER)
			else:
				sb.bg_color = Color(0.14, 0.14, 0.16, 1.0)
				sb.border_color = Color(0.24, 0.24, 0.26, 1.0)
			sb.set_corner_radius_all(0)
			sb.border_width_right = 1
			sb.border_width_left = 0
			sb.border_width_top = 0
			sb.border_width_bottom = 0
			sb.content_margin_left = 0
			sb.content_margin_right = 0
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
			inner.add_theme_stylebox_override("panel", sb)

			# Tight margins: tools column + layers list must fit the docked width
			var margin_container = inner.get_node_or_null("MarginContainer") as MarginContainer
			if margin_container:
				for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
					margin_container.add_theme_constant_override(side, 4)

			var layers_panel = inner.find_child("Panel", true, false) as Panel
			if layers_panel:
				var lsb := StyleBoxFlat.new()
				if tm and S:
					lsb.bg_color = tm.get_color(S.PANEL_SURFACE)
					lsb.border_color = tm.get_color(S.BORDER)
				else:
					lsb.bg_color = Color(0.14, 0.14, 0.16, 1.0)
					lsb.border_color = Color(0.24, 0.24, 0.26, 1.0)
				lsb.set_corner_radius_all(0)
				lsb.set_border_width_all(0)
				layers_panel.add_theme_stylebox_override("panel", lsb)

			var tools = inner.find_child("Herramientas", true, false) as Control
			if tools:
				tools.visible = true
			var toggle_ctrl = inner.get_node_or_null("Control") as Control
			if toggle_ctrl:
				toggle_ctrl.visible = false

	_update_toolbar_subpanels_direction(true)
	# ancho real de la barra (contenido) y reglas a su lado
	set_left_dock_width.call_deferred(-1.0)

func _update_toolbar_subpanels_direction(is_pro: bool, is_modern: bool = false) -> void:
	if not is_instance_valid(layout_node):
		return
	var tools = layout_node.find_child("Herramientas", true, false) as Control
	if not is_instance_valid(tools):
		return

	var is_docked_left: bool = is_pro or is_modern
	var left_base: float = (PRO_LEFT_W + 5.0) if is_pro else ((MODERN_LEFT_W + 5.0) if is_modern else -325.0)

	var poly = tools.get_node_or_null("polygon") as Control
	if is_instance_valid(poly):
		poly.z_index = 100
		if is_docked_left:
			poly.offset_left = left_base
			poly.offset_right = left_base + 296.0
		else:
			poly.offset_left = -325.0
			poly.offset_right = -29.0

	var txt = tools.get_node_or_null("text") as Control
	if is_instance_valid(txt):
		txt.z_index = 100
		if is_docked_left:
			txt.offset_left = left_base
			txt.offset_right = left_base + 310.0
		else:
			txt.offset_left = -325.0
			txt.offset_right = -15.0

	var sel = tools.get_node_or_null("Selector") as Control
	if is_instance_valid(sel):
		sel.z_index = 100
		if is_docked_left:
			sel.offset_left = left_base
			sel.offset_right = left_base + 153.0
		else:
			sel.offset_left = -180.0
			sel.offset_right = -27.0

	var bez = tools.get_node_or_null("bezier") as Control
	if is_instance_valid(bez):
		bez.z_index = 100
		if is_docked_left:
			bez.offset_left = left_base
			bez.offset_right = left_base + 310.0
		else:
			bez.offset_left = -325.0
			bez.offset_right = -15.0

	var bru = tools.get_node_or_null("brush") as Control
	if is_instance_valid(bru):
		bru.z_index = 100
		if is_docked_left:
			bru.offset_left = left_base
			bru.offset_right = left_base + 310.0
		else:
			bru.offset_left = -325.0
			bru.offset_right = -15.0

	# Ajuste final con la geometría REAL: cada subpanel queda a EDGE_GAP del
	# borde exterior del panel de capas (antes: polígonos pegado, texto a 4
	# px, selector a 27…), también cada vez que se abre.
	for sub_name in ["polygon", "text", "Selector", "bezier", "brush"]:
		var sp = tools.get_node_or_null(sub_name) as Control
		if is_instance_valid(sp):
			if not sp.visibility_changed.is_connected(_align_subpanel):
				sp.visibility_changed.connect(_align_subpanel.bind(sp))
			if sp.visible:
				_align_subpanel.call_deferred(sp)

## Coloca un subpanel de herramientas a EDGE_GAP del panel de capas: a su
## izquierda en Smart (flotante a la derecha), a su derecha si está acoplado.
func _align_subpanel(sp: Control) -> void:
	if not is_instance_valid(sp) or not sp.is_visible_in_tree() or not is_instance_valid(layout_node):
		return
	await get_tree().process_frame   # tamaño final ya calculado
	if not is_instance_valid(sp):
		return
	var frame := layout_node.get_node_or_null("PanelContainer") as Control
	if frame == null:
		return
	var fr := frame.get_global_rect()
	var r := sp.get_global_rect()
	var docked_left := frame.get_global_rect().position.x < get_viewport().get_visible_rect().size.x * 0.5
	var delta: float = (fr.end.x + EDGE_GAP - r.position.x) if docked_left else (fr.position.x - EDGE_GAP - r.end.x)
	if absf(delta) > 0.5:
		sp.offset_left += delta
		sp.offset_right += delta

func _set_modern_ui_visible(show: bool) -> void:
	if is_instance_valid(modern_bottom_toolbar):
		modern_bottom_toolbar.visible = show
	if is_instance_valid(modern_top_bar):
		modern_top_bar.visible = show
	# The side rail was removed from Modern: settings live in the top bar and
	# the layers drawer is always docked.
	if is_instance_valid(modern_nav_rail):
		modern_nav_rail.visible = false

func _update_modern_rulers(sidebar_open: bool) -> void:
	if not is_instance_valid(windows_regla):
		return

	var left_x: float = MODERN_LEFT_W if sidebar_open else 0.0

	var regla_v = windows_regla.get_node_or_null("regla vertical") as Control
	if regla_v:
		regla_v.offset_left = left_x
		regla_v.offset_right = left_x + 24.0
		regla_v.offset_top = 24.0
		regla_v.offset_bottom = 0.0

	var btn_settings = windows_regla.get_node_or_null("Button") as Control
	if btn_settings:
		btn_settings.offset_left = left_x
		btn_settings.offset_right = left_x + 24.0
		btn_settings.offset_top = 0.0
		btn_settings.offset_bottom = 24.0
		btn_settings.custom_minimum_size = Vector2(24, 24)
		btn_settings.visible = false

	var regla_h = windows_regla.get_node_or_null("regla horizontal") as Control
	if regla_h:
		regla_h.offset_left = left_x + 24.0
		var right_offset: float = 0.0
		if is_instance_valid(pro_studio) and pro_studio.visible:
			right_offset = -PRO_RIGHT_W
		elif is_instance_valid(docked_inspector) and docked_inspector.visible:
			right_offset = -268.0
		regla_h.offset_right = right_offset

	if is_instance_valid(manager_windws_regla) and manager_windws_regla.visible:
		_position_settings_dialog()

	if windows_regla.has_method("_aplicar_estilo_tema"):
		windows_regla._aplicar_estilo_tema()
	if windows_regla.has_method("queue_redraw"):
		windows_regla.queue_redraw()
	if regla_v and regla_v.has_method("queue_redraw"):
		regla_v.queue_redraw()
	if regla_h and regla_h.has_method("queue_redraw"):
		regla_h.queue_redraw()

# ── Atajos Globales de Teclado (Ctrl + K y Tab) ──────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return

	# Si el foco esta en un editor de texto editable, no interceptar
	var viewport := get_viewport()
	if is_instance_valid(viewport):
		var focus_owner = viewport.gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			return

	# Escape: Cerrar ventana de configuración si está abierta
	if event.keycode == KEY_ESCAPE:
		if is_instance_valid(manager_windws_regla) and manager_windws_regla.visible:
			if manager_windws_regla.has_method("close_settings"):
				manager_windws_regla.close_settings()
			else:
				manager_windws_regla.visible = false
			if is_instance_valid(viewport):
				viewport.set_input_as_handled()
			return

	# 1. Ctrl + K: Abrir/Cerrar Command Palette
	if event.keycode == KEY_K and (event.ctrl_pressed or event.meta_pressed):
		_toggle_command_palette()
		viewport.set_input_as_handled()
		return

	# 2. Tab: Alternar modo Focus Canvas (despejar interfaz)
	if event.keycode == KEY_TAB and not event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed:
		_toggle_focus_canvas()
		viewport.set_input_as_handled()
		return

func _toggle_command_palette() -> void:
	if not is_instance_valid(command_palette):
		_resolve_nodes()
	if is_instance_valid(command_palette):
		if command_palette.visible:
			if command_palette.has_method("close_palette"):
				command_palette.close_palette()
			else:
				command_palette.visible = false
		else:
			if command_palette.has_method("open_palette"):
				command_palette.open_palette()
			else:
				command_palette.visible = true

func _toggle_focus_canvas() -> void:
	_resolve_nodes()
	_focus_canvas_active = !_focus_canvas_active

	var ui_elements := [
		docked_inspector,
		pro_studio,
		pro_top_bar,
		layout_node,
		modern_bottom_toolbar,
		modern_top_bar,
		modern_nav_rail,
		barra_visual_panel,
		logo_node,
		windows_regla,
		keyboard_node,
		control2_node,
		manager_windws_regla
	]

	if _focus_canvas_active:
		# Guardar visibilidad previa y ocultar todo
		_pre_focus_states.clear()
		for elem in ui_elements:
			if is_instance_valid(elem):
				_pre_focus_states[elem] = elem.visible
				elem.visible = false
	else:
		# Restaurar visibilidad previa
		for elem in ui_elements:
			if is_instance_valid(elem) and _pre_focus_states.has(elem):
				elem.visible = _pre_focus_states[elem]
		_pre_focus_states.clear()

func _theme_smart_floating_controls() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if not tm:
		return
	var S = tm.Slot
	var surface_col: Color = tm.get_color(S.PANEL_SURFACE)
	var border_col: Color = tm.get_color(S.BORDER)
	var text_col: Color = tm.get_color(S.PANEL_TEXT)
	var icon_primary: Color = tm.get_color(S.ICON_PRIMARY)

	var input_hud: Node = null
	if is_instance_valid(keyboard_node):
		var huds := keyboard_node.find_children("", "InputHud", false, false)
		input_hud = huds[0] if not huds.is_empty() else null
	if is_instance_valid(input_hud) and input_hud.has_method("_apply_theme"):
		# The live input chip styles itself (key caps, drawn mouse, icons)
		input_hud._apply_theme()
	if is_instance_valid(keyboard_node) and not is_instance_valid(input_hud):
		var pc = keyboard_node.get_node_or_null("PanelContainer") as PanelContainer
		if pc:
			var ksb := StyleBoxFlat.new()
			ksb.bg_color = surface_col
			ksb.border_color = border_col
			ksb.set_border_width_all(1)
			ksb.set_corner_radius_all(13)
			ksb.shadow_color = Color(0, 0, 0, 0.2) if surface_col.get_luminance() < 0.5 else Color(0, 0, 0, 0.08)
			ksb.shadow_size = 6
			pc.add_theme_stylebox_override("panel", ksb)
		for lbl in keyboard_node.find_children("", "Label", true, false):
			(lbl as Label).add_theme_color_override("font_color", text_col)
		var k_hov := StyleBoxFlat.new()
		k_hov.bg_color = tm.get_color(S.BUTTON_HOVER)
		k_hov.set_corner_radius_all(6)
		var k_prs := StyleBoxFlat.new()
		k_prs.bg_color = tm.get_color(S.BUTTON_PRESSED)
		k_prs.set_corner_radius_all(6)
		for btn in keyboard_node.find_children("", "Button", true, false):
			var b := btn as Button
			if b.icon and tm.has_method("make_white_icon"):
				b.icon = tm.make_white_icon(b.icon, 16)
			b.modulate = Color.WHITE
			b.add_theme_color_override("icon_normal_color", icon_primary)
			b.add_theme_color_override("icon_hover_color", text_col)
			b.add_theme_color_override("icon_pressed_color", tm.get_color(S.ACCENT))
			b.add_theme_color_override("icon_focus_color", icon_primary)
			b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			b.add_theme_stylebox_override("hover", k_hov)
			b.add_theme_stylebox_override("pressed", k_prs)
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	if is_instance_valid(keyboard_node):
		var panel_kb = keyboard_node.find_child("Panel_keyboard", true, false) as PanelContainer
		if panel_kb:
			var pkb_sb := StyleBoxFlat.new()
			pkb_sb.bg_color = surface_col
			pkb_sb.border_color = border_col
			pkb_sb.set_border_width_all(1)
			pkb_sb.set_corner_radius_all(12)
			pkb_sb.shadow_color = Color(0, 0, 0, 0.35) if surface_col.get_luminance() < 0.5 else Color(0, 0, 0, 0.12)
			pkb_sb.shadow_size = 16
			pkb_sb.shadow_offset = Vector2(0, 6)
			panel_kb.add_theme_stylebox_override("panel", pkb_sb)
			for le in panel_kb.find_children("", "LineEdit", true, false):
				var edit := le as LineEdit
				var le_sb := StyleBoxFlat.new()
				le_sb.bg_color = tm.get_color(S.INPUT_BG)
				le_sb.border_color = border_col
				le_sb.set_border_width_all(1)
				le_sb.set_corner_radius_all(6)
				le_sb.content_margin_left = 6
				le_sb.content_margin_right = 6
				edit.add_theme_stylebox_override("normal", le_sb)
				edit.add_theme_color_override("font_color", text_col)

	if is_instance_valid(barra_visual_panel):
		_setup_smart_zoom_controls()

		# Disposición compacta y minimalista
		barra_visual_panel.custom_minimum_size = Vector2(0, 32)
		barra_visual_panel.anchor_left = 1.0
		barra_visual_panel.anchor_right = 1.0
		barra_visual_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		barra_visual_panel.offset_top = 34.0
		barra_visual_panel.offset_bottom = 60.0
		barra_visual_panel.offset_right = -16.0
		barra_visual_panel.offset_left = -215.0
		barra_visual_panel.z_index = 100

		var margin_container = barra_visual_panel.get_node_or_null("MarginContainer") as MarginContainer
		if margin_container:
			margin_container.add_theme_constant_override("margin_left", 6)
			margin_container.add_theme_constant_override("margin_right", 6)
			margin_container.add_theme_constant_override("margin_top", 2)
			margin_container.add_theme_constant_override("margin_bottom", 2)

		var bv = barra_visual_panel.find_child("BARRA_VISUAL", true, false) as BoxContainer
		if bv:
			bv.add_theme_constant_override("separation", 3)

		var bsb := StyleBoxFlat.new()
		bsb.bg_color = surface_col
		bsb.border_color = border_col
		bsb.set_border_width_all(1)
		bsb.set_corner_radius_all(13) # Altura 26px -> radio 13px = píldora suave
		bsb.shadow_color = Color(0, 0, 0, 0.25) if surface_col.get_luminance() < 0.5 else Color(0, 0, 0, 0.08)
		bsb.shadow_size = 6
		bsb.shadow_offset = Vector2(0, 2)
		barra_visual_panel.add_theme_stylebox_override("panel", bsb)

		var hov_sb := StyleBoxFlat.new()
		hov_sb.bg_color = tm.get_color(S.BUTTON_HOVER)
		hov_sb.set_corner_radius_all(4)

		var prs_sb := StyleBoxFlat.new()
		prs_sb.bg_color = tm.get_color(S.BUTTON_PRESSED)
		prs_sb.border_color = tm.get_color(S.ACCENT)
		prs_sb.set_border_width_all(1)
		prs_sb.set_corner_radius_all(4)

		var hov_prs_sb := StyleBoxFlat.new()
		hov_prs_sb.bg_color = tm.get_color(S.BUTTON_HOVER)
		hov_prs_sb.border_color = tm.get_color(S.ACCENT)
		hov_prs_sb.set_border_width_all(1)
		hov_prs_sb.set_corner_radius_all(4)

		# Botones visuales preexistentes (Color Picker, Efectos, Vista Previa)
		var btn_configs: Dictionary = {
			"Button": {
				"key": "Color Picker",
				"target_name": "pickr_color_windows",
			},
			"Button2": {
				"key": "Effects",
				"target_name": "panel__effects",
			},
			"BUTTON_PEWVIEW": {
				"key": "Preview",
				"target_name": "Panel_PREVIEW",
			}
		}

		var main_root = barra_visual_panel.get_parent()
		for btn_name: String in btn_configs:
			var cfg: Dictionary = btn_configs[btn_name]
			var b = bv.get_node_or_null(btn_name) as Button if bv else null
			if b:
				b.toggle_mode = true
				b.set_meta("tooltip_key", cfg["key"])
				b.tooltip_text = tr(String(cfg["key"]))
				if "target_panel" in b and (b.target_panel == null or not is_instance_valid(b.target_panel)):
					if is_instance_valid(main_root):
						var target = main_root.find_child(String(cfg["target_name"]), true, false) as Control
						if is_instance_valid(target):
							b.target_panel = target
				if "target_panel" in b and is_instance_valid(b.target_panel):
					b.button_pressed = b.target_panel.visible
					b.target_panel.offset_top = 66.0
					b.target_panel.offset_right = -16.0

				# Same visual size and centering for every icon in the bar
				b.custom_minimum_size = Vector2(26, 26)
				b.expand_icon = false
				b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
				b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				if b.icon and tm.has_method("make_white_icon"):
					b.icon = tm.make_white_icon(b.icon, 16)
				b.modulate = Color.WHITE
				b.add_theme_color_override("icon_normal_color", icon_primary)
				b.add_theme_color_override("icon_hover_color", text_col)
				b.add_theme_color_override("icon_pressed_color", tm.get_color(S.ACCENT))
				b.add_theme_color_override("icon_focus_color", icon_primary)
				b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
				b.add_theme_stylebox_override("hover", hov_sb)
				b.add_theme_stylebox_override("pressed", prs_sb)
				b.add_theme_stylebox_override("hover_pressed", hov_prs_sb)

		# Aplicar tema a Panel_PREVIEW si existe
		var prev_panel = main_root.find_child("Panel_PREVIEW", true, false) as Panel if is_instance_valid(main_root) else null
		if is_instance_valid(prev_panel):
			var psb := StyleBoxFlat.new()
			psb.bg_color = surface_col
			psb.border_color = border_col
			psb.set_border_width_all(1)
			psb.set_corner_radius_all(10)
			psb.shadow_color = Color(0, 0, 0, 0.2) if surface_col.get_luminance() < 0.5 else Color(0, 0, 0, 0.08)
			psb.shadow_size = 8
			prev_panel.add_theme_stylebox_override("panel", psb)
			for plbl in prev_panel.find_children("", "Label", true, false):
				(plbl as Label).add_theme_color_override("font_color", text_col)

		# Separador vertical
		var sep = bv.get_node_or_null("SmartZoomSep") as VSeparator if bv else null
		if sep:
			var sep_sb := StyleBoxFlat.new()
			sep_sb.bg_color = border_col
			sep_sb.border_width_left = 1
			sep_sb.border_color = border_col
			sep.add_theme_stylebox_override("separator", sep_sb)

		# Botones − y +
		var zoom_btns: Array[Button] = [_smart_btn_zoom_out, _smart_btn_zoom_in]
		for zbtn: Button in zoom_btns:
			if is_instance_valid(zbtn):
				zbtn.custom_minimum_size = Vector2(20, 20)
				zbtn.add_theme_color_override("font_color", text_col)
				zbtn.add_theme_color_override("font_hover_color", text_col)
				zbtn.add_theme_color_override("font_pressed_color", tm.get_color(S.ACCENT))
				zbtn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
				zbtn.add_theme_stylebox_override("hover", hov_sb)
				zbtn.add_theme_stylebox_override("pressed", prs_sb)

		# Etiqueta / chip del valor del zoom
		if is_instance_valid(_smart_lbl_zoom):
			_smart_lbl_zoom.custom_minimum_size = Vector2(38, 20)
			_smart_lbl_zoom.add_theme_color_override("font_color", text_col)
			var chip_bg: Color = tm.get_color(S.INPUT_BG) if S else Color(0.93, 0.93, 0.95, 0.8)
			var lsb := StyleBoxFlat.new()
			lsb.bg_color = chip_bg
			lsb.set_corner_radius_all(4)
			lsb.content_margin_left = 3
			lsb.content_margin_right = 3
			_smart_lbl_zoom.add_theme_stylebox_override("normal", lsb)

func _setup_smart_zoom_controls() -> void:
	if not is_instance_valid(barra_visual_panel):
		return
	var bv = barra_visual_panel.find_child("BARRA_VISUAL", true, false) as BoxContainer
	if not is_instance_valid(bv):
		return

	if bv.get_node_or_null("SmartZoomSep") != null:
		return

	var sep := VSeparator.new()
	sep.name = "SmartZoomSep"
	sep.custom_minimum_size = Vector2(4, 14)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(sep)

	var btn_out := Button.new()
	btn_out.name = "SmartZoomOut"
	btn_out.text = "−"
	btn_out.tooltip_text = tr("Reducir zoom")
	btn_out.set_meta("tooltip_key", "Reducir zoom")
	btn_out.custom_minimum_size = Vector2(20, 20)
	btn_out.focus_mode = Control.FOCUS_NONE
	btn_out.add_theme_font_size_override("font_size", 12)
	btn_out.pressed.connect(_on_smart_zoom_out_pressed)
	bv.add_child(btn_out)
	_smart_btn_zoom_out = btn_out

	var lbl := Label.new()
	lbl.name = "SmartZoomLabel"
	lbl.text = "100%"
	lbl.custom_minimum_size = Vector2(38, 20)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.tooltip_text = tr("Arrastra para hacer zoom · Doble clic: 100%")
	lbl.set_meta("tooltip_key", "Arrastra para hacer zoom · Doble clic: 100%")
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	lbl.gui_input.connect(_on_smart_zoom_label_gui_input)
	bv.add_child(lbl)
	_smart_lbl_zoom = lbl

	var btn_in := Button.new()
	btn_in.name = "SmartZoomIn"
	btn_in.text = "+"
	btn_in.tooltip_text = tr("Aumentar zoom")
	btn_in.set_meta("tooltip_key", "Aumentar zoom")
	btn_in.custom_minimum_size = Vector2(20, 20)
	btn_in.focus_mode = Control.FOCUS_NONE
	btn_in.add_theme_font_size_override("font_size", 12)
	btn_in.pressed.connect(_on_smart_zoom_in_pressed)
	bv.add_child(btn_in)
	_smart_btn_zoom_in = btn_in

func _find_smart_canvas():
	if is_instance_valid(_smart_cached_canvas):
		return _smart_cached_canvas
	if get_tree():
		_smart_cached_canvas = get_tree().get_first_node_in_group("_vectopen_canvas")
	return _smart_cached_canvas

func _on_smart_zoom_out_pressed() -> void:
	var c = _find_smart_canvas()
	if is_instance_valid(c):
		if c.has_method("zoom_at_point") and is_instance_valid(c.camera):
			c.zoom_at_point(0.8, c.camera.position)
		elif "zoom_percentage" in c:
			c.zoom_percentage = clampf(float(c.zoom_percentage) - 25.0, 10.0, 5000.0)
	_sync_smart_zoom_from_canvas()

func _on_smart_zoom_in_pressed() -> void:
	var c = _find_smart_canvas()
	if is_instance_valid(c):
		if c.has_method("zoom_at_point") and is_instance_valid(c.camera):
			c.zoom_at_point(1.25, c.camera.position)
		elif "zoom_percentage" in c:
			c.zoom_percentage = clampf(float(c.zoom_percentage) + 25.0, 10.0, 5000.0)
	_sync_smart_zoom_from_canvas()

var _smart_zoom_dragging: bool = false

## Same gesture as the Modern toolbar: double-click resets, drag zooms smoothly.
func _on_smart_zoom_label_gui_input(event: InputEvent) -> void:
	var c = _find_smart_canvas()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_smart_zoom_dragging = event.pressed and not event.double_click
		if event.double_click and is_instance_valid(c):
			if c.has_method("_reset_camera"):
				c._reset_camera()
			elif "zoom_percentage" in c:
				c.zoom_percentage = 100.0
			if is_instance_valid(_smart_lbl_zoom):
				_smart_lbl_zoom.text = "100%"
			_smart_last_synced_zoom = 100.0
	elif event is InputEventMouseMotion and _smart_zoom_dragging and is_instance_valid(c):
		var factor := exp(float(event.relative.x) * ModernBottomToolbar.ZOOM_DRAG_SENSITIVITY)
		if c.has_method("zoom_at_point") and "camera" in c and is_instance_valid(c.camera):
			c.zoom_at_point(factor, c.camera.position)
		elif "zoom_percentage" in c:
			c.zoom_percentage = clampf(c.zoom_percentage * factor, 10.0, 5000.0)

func _sync_smart_zoom_from_canvas() -> void:
	if not is_instance_valid(_smart_lbl_zoom) or not is_instance_valid(barra_visual_panel) or not barra_visual_panel.visible:
		return
	var c = _find_smart_canvas()
	if is_instance_valid(c) and "zoom_percentage" in c:
		var cur: float = roundf(float(c.zoom_percentage))
		if cur != _smart_last_synced_zoom:
			_smart_last_synced_zoom = cur
			_smart_lbl_zoom.text = "%d%%" % int(cur)

func is_focus_canvas_active() -> bool:
	return _focus_canvas_active

## Modos con la barra de capas ACOPLADA a la izquierda (Modern, Professional):
## cambia su ancho y mueve las reglas con ella, para que el lienzo ocupe el
## hueco (botón carpeta: ocultar el contenido del panel). w < 0 = ancho normal.
func set_left_dock_width(w: float) -> void:
	var gui = get_node_or_null("/root/GlobalUI")
	var mode: String = gui.get_ui_mode() if gui and gui.has_method("get_ui_mode") else "smart"
	if mode == "smart" or not is_instance_valid(layout_node):
		return
	var full: float = PRO_LEFT_W if mode == "professional" else MODERN_LEFT_W
	var inner = layout_node.get_node_or_null("PanelContainer") as Control
	var width: float = full if w < 0.0 else w
	if inner:
		# crece hacia la DERECHA (heredaba «hacia la izquierda» del modo Smart
		# y, si el contenido pedía más ancho, se salía de la pantalla)
		inner.grow_horizontal = Control.GROW_DIRECTION_END
		inner.custom_minimum_size.x = 0.0
		if w < 0.0:
			# ancho normal, o el que de verdad necesita el contenido si es mayor
			width = maxf(full, inner.get_combined_minimum_size().x)
		inner.custom_minimum_size.x = width
	layout_node.offset_right = layout_node.offset_left + width
	if is_instance_valid(windows_regla):
		var regla_v = windows_regla.get_node_or_null("regla vertical") as Control
		if regla_v:
			regla_v.offset_left = width
			regla_v.offset_right = width + 24.0
		var btn_settings = windows_regla.get_node_or_null("Button") as Control
		if btn_settings:
			btn_settings.offset_left = width
			btn_settings.offset_right = width + 24.0
		var regla_h = windows_regla.get_node_or_null("regla horizontal") as Control
		if regla_h:
			regla_h.offset_left = width + 24.0
