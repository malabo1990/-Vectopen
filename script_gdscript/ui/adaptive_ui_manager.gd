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

# Componente dedicado de Professional UI (Affinity Studio style)
@export var pro_studio: Control

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

func _ready() -> void:
	_resolve_nodes()
	_store_defaults()
	_connect_events()
	
	# Aplicar el modo actual configurado en GlobalUI
	var current_mode = GlobalUI.get_ui_mode() if is_instance_valid(GlobalUI) else "smart"
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
	if is_instance_valid(GlobalUI) and GlobalUI.has_signal("ui_mode_changed"):
		if not GlobalUI.ui_mode_changed.is_connected(_on_ui_mode_changed):
			GlobalUI.ui_mode_changed.connect(_on_ui_mode_changed)

	var ge = get_node_or_null("/root/GlobalEvents")
	if is_instance_valid(ge) and ge.has_signal("request_settings_dialog"):
		if not ge.request_settings_dialog.is_connected(_on_request_settings_dialog):
			ge.request_settings_dialog.connect(_on_request_settings_dialog)

	if is_instance_valid(modern_nav_rail):
		if modern_nav_rail.has_signal("left_panel_toggled"):
			if not modern_nav_rail.left_panel_toggled.is_connected(_on_nav_rail_left_panel_toggled):
				modern_nav_rail.left_panel_toggled.connect(_on_nav_rail_left_panel_toggled)
		if modern_nav_rail.has_signal("section_selected"):
			if not modern_nav_rail.section_selected.is_connected(_on_nav_rail_section_selected):
				modern_nav_rail.section_selected.connect(_on_nav_rail_section_selected)

func _on_nav_rail_left_panel_toggled(is_open: bool) -> void:
	if GlobalUI.is_modern_mode() and is_instance_valid(layout_node):
		layout_node.visible = is_open
		_update_modern_rulers(is_open)

func _on_nav_rail_section_selected(section_id: String) -> void:
	if not GlobalUI.is_modern_mode():
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

func _on_request_settings_dialog() -> void:
	if not is_instance_valid(manager_windws_regla):
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
	if GlobalUI.is_modern_mode():
		var is_sidebar_open = is_instance_valid(layout_node) and layout_node.visible
		var left_x: float = (302.0 + 24.0 + 16.0) if is_sidebar_open else (42.0 + 24.0 + 16.0)
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
		GlobalUI.MODE_SMART:
			_apply_smart_mode()
		GlobalUI.MODE_MODERN:
			_apply_modern_mode()
		GlobalUI.MODE_PROFESSIONAL:
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
			btn_settings.offset_top = 1.0
			btn_settings.offset_bottom = 21.0
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
		layout_node.grow_horizontal = _default_layout_grow_horizontal

		var inner = layout_node.get_node_or_null("PanelContainer") as Control
		if inner:
			inner.anchor_left = _default_inner_anchor_left
			inner.anchor_right = _default_inner_anchor_right
			inner.anchor_top = _default_inner_anchor_top
			inner.anchor_bottom = _default_inner_anchor_bottom
			inner.offset_left = _default_inner_offset_left
			inner.offset_right = _default_inner_offset_right
			inner.offset_top = _default_inner_offset_top
			inner.offset_bottom = _default_inner_offset_bottom
			inner.custom_minimum_size = _default_inner_min_size

			# Restaurar estilo original de Capas (esquinas redondeadas)
			if _default_inner_stylebox:
				inner.add_theme_stylebox_override("panel", _default_inner_stylebox)
			else:
				inner.remove_theme_stylebox_override("panel")

			var margin_container = inner.get_node_or_null("MarginContainer") as MarginContainer
			if margin_container and not _default_margin_container_margins.is_empty():
				margin_container.add_theme_constant_override("margin_left", _default_margin_container_margins.get("left", 10))
				margin_container.add_theme_constant_override("margin_right", _default_margin_container_margins.get("right", 10))
				margin_container.add_theme_constant_override("margin_top", _default_margin_container_margins.get("top", 10))
				margin_container.add_theme_constant_override("margin_bottom", _default_margin_container_margins.get("bottom", 10))

			# Restaurar radios en el panel de LayersSystem
			var layers_panel = inner.find_child("Panel", true, false) as Panel
			if layers_panel:
				var lsb = layers_panel.get_theme_stylebox("panel")
				if lsb is StyleBoxFlat:
					var lsb_round: StyleBoxFlat = lsb.duplicate() as StyleBoxFlat
					lsb_round.set_corner_radius_all(14)
					layers_panel.add_theme_stylebox_override("panel", lsb_round)

			var tools = inner.find_child("Herramientas", true, false) as Control
			if tools:
				tools.visible = true
			var toggle_ctrl = inner.get_node_or_null("Control") as Control
			if toggle_ctrl:
				toggle_ctrl.visible = true

func _apply_modern_mode() -> void:
	# Modern Panel: Figma UI3 style.
	# Activar Top Bar, Nav Rail, Bottom Toolbar y Docked Inspector
	_set_modern_ui_visible(true)

	if is_instance_valid(pro_studio):
		pro_studio.visible = false

	if is_instance_valid(barra_visual_panel):
		barra_visual_panel.visible = false

	if is_instance_valid(logo_node):
		logo_node.visible = false

	# Ocultar widgets flotantes de Smart UI (ej. chip de teclado abajo a la izquierda)
	if is_instance_valid(keyboard_node):
		keyboard_node.visible = false

	if is_instance_valid(control2_node):
		control2_node.visible = false

	# Ajustar regla para que acompañe dinámicamente al sidebar y no se solape
	if is_instance_valid(windows_regla):
		windows_regla.offset_top = 36.0
		var is_open = true
		if is_instance_valid(modern_nav_rail) and "_panel_open" in modern_nav_rail:
			is_open = modern_nav_rail._panel_open
		_update_modern_rulers(is_open)

	if is_instance_valid(docked_inspector):
		docked_inspector.visible = true
		if docked_inspector.has_method("set_density"):
			docked_inspector.set_density(false)
		docked_inspector.anchor_left = 1.0
		docked_inspector.anchor_right = 1.0
		docked_inspector.anchor_top = 0.0
		docked_inspector.anchor_bottom = 1.0
		docked_inspector.offset_left = -268.0
		docked_inspector.offset_right = 0.0
		docked_inspector.offset_top = 36.0 # Bajo la ModernTopBar
		docked_inspector.offset_bottom = 0.0

	# Mover Layout / Capas al lateral izquierdo como drawer de capas (x = 42 a 302, y = 36 a fin)
	if is_instance_valid(layout_node):
		var is_open = true
		if is_instance_valid(modern_nav_rail) and "_panel_open" in modern_nav_rail:
			is_open = modern_nav_rail._panel_open
		layout_node.visible = is_open
		layout_node.anchor_left = 0.0
		layout_node.anchor_right = 0.0
		layout_node.anchor_top = 0.0
		layout_node.anchor_bottom = 1.0
		layout_node.offset_left = 42.0
		layout_node.offset_right = 42.0 + 260.0
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
			inner.custom_minimum_size = Vector2(260, 0)

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

			# Quitar radios en el panel interno de capas
			var layers_panel = inner.find_child("Panel", true, false) as Panel
			if layers_panel:
				var lsb = layers_panel.get_theme_stylebox("panel")
				if lsb is StyleBoxFlat:
					var lsb_flat: StyleBoxFlat = lsb.duplicate() as StyleBoxFlat
					lsb_flat.set_corner_radius_all(0)
					layers_panel.add_theme_stylebox_override("panel", lsb_flat)

			# Ocultar herramientas verticales en Modern UI (ya estan en ModernBottomToolbar)
			var tools = inner.find_child("Herramientas", true, false) as Control
			if tools:
				tools.visible = false
			# Ocultar boton flotante de toggle original
			var toggle_ctrl = inner.get_node_or_null("Control") as Control
			if toggle_ctrl:
				toggle_ctrl.visible = false

func _apply_professional_mode() -> void:
	# Professional Panel: Affinity / Illustrator style.
	# Ocultar la barra inferior de Modern UI
	_set_modern_ui_visible(false)

	if is_instance_valid(barra_visual_panel):
		barra_visual_panel.visible = false

	if is_instance_valid(logo_node):
		logo_node.visible = true

	if is_instance_valid(keyboard_node):
		keyboard_node.visible = false

	if is_instance_valid(control2_node):
		control2_node.visible = false

	if is_instance_valid(windows_regla):
		windows_regla.offset_top = 0.0
		var left_x: float = 320.0
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
			btn_settings.offset_top = 1.0
			btn_settings.offset_bottom = 21.0
		var regla_h = windows_regla.get_node_or_null("regla horizontal") as Control
		if regla_h:
			regla_h.offset_left = left_x + 24.0
			regla_h.offset_right = -320.0

	# Ocultar inspector de Modern UI
	if is_instance_valid(docked_inspector):
		docked_inspector.visible = false

	# Activar ProStudio lateral derecho (Affinity Studio)
	if is_instance_valid(pro_studio):
		pro_studio.visible = true
		pro_studio.anchor_left = 1.0
		pro_studio.anchor_right = 1.0
		pro_studio.anchor_top = 0.0
		pro_studio.anchor_bottom = 1.0
		pro_studio.offset_left = -320.0
		pro_studio.offset_right = 0.0
		pro_studio.offset_top = 28.0
		pro_studio.offset_bottom = 0.0

	# Barra de herramientas y capas acopladas a la izquierda con herramientas visibles
	if is_instance_valid(layout_node):
		layout_node.visible = true
		layout_node.anchor_left = 0.0
		layout_node.anchor_right = 0.0
		layout_node.anchor_top = 0.0
		layout_node.anchor_bottom = 1.0
		layout_node.offset_left = 0.0
		layout_node.offset_right = 320.0
		layout_node.offset_top = 28.0
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
			inner.custom_minimum_size = Vector2(320, 0)

			var tools = inner.find_child("Herramientas", true, false) as Control
			if tools:
				tools.visible = true
			var toggle_ctrl = inner.get_node_or_null("Control") as Control
			if toggle_ctrl:
				toggle_ctrl.visible = false

func _set_modern_ui_visible(show: bool) -> void:
	if is_instance_valid(modern_bottom_toolbar):
		modern_bottom_toolbar.visible = show
	if is_instance_valid(modern_top_bar):
		modern_top_bar.visible = show
	if is_instance_valid(modern_nav_rail):
		modern_nav_rail.visible = show

func _update_modern_rulers(sidebar_open: bool) -> void:
	if not is_instance_valid(windows_regla):
		return

	var left_x: float = (42.0 + 260.0) if sidebar_open else 42.0

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
		btn_settings.offset_top = 1.0
		btn_settings.offset_bottom = 21.0

	var regla_h = windows_regla.get_node_or_null("regla horizontal") as Control
	if regla_h:
		regla_h.offset_left = left_x + 24.0
		regla_h.offset_right = -268.0

	if is_instance_valid(manager_windws_regla) and manager_windws_regla.visible:
		_position_settings_dialog()

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

func is_focus_canvas_active() -> bool:
	return _focus_canvas_active
