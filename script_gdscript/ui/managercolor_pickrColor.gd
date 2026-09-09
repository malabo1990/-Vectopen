# ==========================================
# RUTA: res://scripts/managercolor_pickrColor.gd
# ==========================================
extends Node
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

	_conectar_controles_ui()

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
		if cc:
			if cc.has_method("set_target"):
				cc.set_target("fill")
			if cc.has_method("set_paint"):
				cc.set_paint({"type": "solid", "color": col}, "fill")
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
		# Sliders laterales solo en modo círculo (0)
		if opacity_box: opacity_box.visible = (mode_idx == 0)
		if wb_box: wb_box.visible = (mode_idx == 0)

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
	var sb: StyleBox = style_tab_active if is_active else style_tab_inactive
	if sb:
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", style_tab_active if style_tab_active else sb)
	btn.add_theme_color_override("icon_normal_color", Color(0.12, 0.12, 0.16, 1.0) if is_active else Color(0.50, 0.52, 0.58, 1.0))
	btn.add_theme_color_override("icon_hover_color", Color(0.04, 0.52, 1.0, 1.0))
	btn.add_theme_color_override("icon_pressed_color", Color(0.04, 0.52, 1.0, 1.0))
	btn.add_theme_color_override("font_color", Color(0.12, 0.12, 0.16, 1.0) if is_active else Color(0.40, 0.42, 0.46, 1.0))
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

func _on_colorcore_changed(fill: Color, _stroke: Color, _target: String) -> void:
	if current_tab != "solid":
		return
	# Solo reflejar visualmente — NO re-emitir al bus (evita realimentación).
	if is_instance_valid(nodo_color_rect) and nodo_color_rect.color != fill:
		nodo_color_rect.color = fill
		color_actualizado.emit(fill)

# 3. Función SET profesional (Modifica el color y lo comunica a todo tu motor)
func establecer_color(nuevo_color: Color, force: bool = false) -> void:
	if not is_instance_valid(nodo_color_rect):
		return

	if nodo_color_rect.color != nuevo_color or force:
		nodo_color_rect.color = nuevo_color
		_notificar_cambio_color(nuevo_color)
		# Puente al sistema core (aplica a la selección con undo).
		if not _from_core:
			if is_inside_tree():
				var tree := get_tree()
				var cc := tree.root.get_node_or_null("ColorCore") if tree and tree.root else null
				if cc and cc.has_method("set_color"):
					cc.set_color(nuevo_color)

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
