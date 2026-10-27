# ==============================================================================
# SCRIPT ÚNICO COMPLETO: Asignado a tu nodo raíz de reglas
# Soporta: Arrastrar, Seleccionar, Mover, Borrar, Flashes y Colores Exportados
# ==============================================================================
extends Control

@onready var regla_horizontal: PanelContainer = $"regla horizontal"
@onready var regla_vertical: PanelContainer = $"regla vertical"

var camera: Camera2D

# ------------------------------------------------------------------------------
# PROPIEDADES EXPORTADAS PARA EL INSPECTOR
# ------------------------------------------------------------------------------
@export_category("Estilo de Guías")
@export var color_guia_normal: Color = Color(0, 0.7, 0.9, 0.4)     # Azul translúcido estándar
@export var color_guia_seleccionada: Color = Color(0, 0.9, 1, 0.8) # Azul brillante al tocarla
@export var color_guia_previsualizacion: Color = Color(1, 0.6, 0, 0.8) # Naranja al arrastrar una nueva

@export_category("Feedback Visual (Flashes)")
@export var color_flash_crear: Color = Color(0, 1, 0, 0.3)   # Verde sutil
@export var color_flash_eliminar: Color = Color(1, 0, 0, 0.3) # Rojo sutil

# Configuración de interacción
const TOLERANCIA_SELECCION: float = 6.0 

# Posición del mouse en pantalla
var mouse_pantalla: Vector2 = Vector2.ZERO

# Listas de guías (Coordenadas del lienzo)
var guias_horizontales: Array[float] = []
var guias_verticales: Array[float] = []

# Estados de arrastre para NUEVAS guías
var arrastrando_nueva_h: bool = false
var arrastrando_nueva_v: bool = false

# Estados para MODIFICAR guías existentes
var indice_guia_activa: int = -1
var moviendo_guia_h: bool = false
var moviendo_guia_v: bool = false
var indice_guia_hover: int = -1
var hover_es_horizontal: bool = false

# Colores dinámicos internos para la animación del flash
var color_actual_flash_h: Color = Color(0, 0, 0, 0)
var color_actual_flash_v: Color = Color(0, 0, 0, 0)
var _btn_settings_original_icon: Texture2D = null

func _ready() -> void:
	await get_tree().process_frame
	camera = get_viewport().get_camera_2d()
	
	if not camera:
		push_warning("Reglas: No se detectó la Camera2D activa.")
		return

	# Conectar señales de dibujo nativas de los PanelContainer
	if regla_horizontal:
		regla_horizontal.draw.connect(_dibujar_regla_horizontal)
		regla_horizontal.mouse_filter = Control.MOUSE_FILTER_STOP
		regla_horizontal.gui_input.connect(_input_regla_horizontal)
		
	if regla_vertical:
		regla_vertical.draw.connect(_dibujar_regla_vertical)
		regla_vertical.mouse_filter = Control.MOUSE_FILTER_STOP
		regla_vertical.gui_input.connect(_input_regla_vertical)
	
	set_focus_mode(Control.FOCUS_ALL)
	z_index = 5
	_aplicar_estilo_tema()
	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_mode): _aplicar_estilo_tema())
	_actualizar_vistas()

## Where the two rulers meet. When the settings button that used to sit there
## is hidden (Modern / Pro), fill the square with the ruler color so the corner
## reads as part of the rulers instead of an empty gap.
func _update_ruler_corner(btn: Control, bg_col: Color, border_col: Color) -> void:
	var corner := get_node_or_null("RulerCorner") as Panel
	if corner == null:
		corner = Panel.new()
		corner.name = "RulerCorner"
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(corner)
	if btn:
		corner.anchor_left = btn.anchor_left
		corner.anchor_right = btn.anchor_right
		corner.anchor_top = btn.anchor_top
		corner.anchor_bottom = btn.anchor_bottom
		corner.offset_left = btn.offset_left
		corner.offset_right = btn.offset_right
		corner.offset_top = btn.offset_top
		corner.offset_bottom = btn.offset_bottom
		move_child(corner, btn.get_index())
	corner.visible = btn == null or not btn.visible
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	corner.add_theme_stylebox_override("panel", sb)

func _aplicar_estilo_tema() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var bg_col: Color = tm.get_color(S.RULER_BG) if (tm and S) else Color(0.19, 0.19, 0.19, 1.0)
	var border_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color(0.28, 0.28, 0.32, 1.0)
	
	var sb_h := StyleBoxFlat.new()
	sb_h.bg_color = bg_col
	sb_h.border_width_bottom = 1
	sb_h.border_color = border_col
	if regla_horizontal:
		regla_horizontal.add_theme_stylebox_override("panel", sb_h)
		
	var sb_v := StyleBoxFlat.new()
	sb_v.bg_color = bg_col
	sb_v.border_width_right = 1
	sb_v.border_color = border_col
	if regla_vertical:
		regla_vertical.add_theme_stylebox_override("panel", sb_v)
		
	var btn_settings = get_node_or_null("Button") as Button
	_update_ruler_corner(btn_settings, bg_col, border_col)
	if btn_settings:
		var btn_hov: Color = tm.get_color(S.BUTTON_HOVER) if (tm and S) else bg_col.lightened(0.1)
		var btn_prs: Color = tm.get_color(S.BUTTON_PRESSED) if (tm and S) else bg_col.darkened(0.1)
		var icon_col: Color = tm.get_color(S.ICON_PRIMARY) if (tm and S) else Color.WHITE
		var text_col: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color.WHITE
		var accent: Color = tm.get_color(S.ACCENT) if (tm and S) else Color.CYAN

		var sb_btn := StyleBoxFlat.new()
		sb_btn.bg_color = bg_col
		sb_btn.border_width_right = 1
		sb_btn.border_width_bottom = 1
		sb_btn.border_color = border_col

		var sb_btn_h := sb_btn.duplicate()
		sb_btn_h.bg_color = btn_hov

		var sb_btn_p := sb_btn.duplicate()
		sb_btn_p.bg_color = btn_prs

		btn_settings.add_theme_stylebox_override("normal", sb_btn)
		btn_settings.add_theme_stylebox_override("hover", sb_btn_h)
		btn_settings.add_theme_stylebox_override("pressed", sb_btn_p)
		btn_settings.add_theme_stylebox_override("focus", sb_btn)

		btn_settings.modulate = Color.WHITE
		if _btn_settings_original_icon == null and btn_settings.icon != null:
			_btn_settings_original_icon = btn_settings.icon
		var raw_btn_icon: Texture2D = _btn_settings_original_icon if _btn_settings_original_icon != null else btn_settings.icon
		if raw_btn_icon and tm and tm.has_method("make_white_icon"):
			btn_settings.icon = tm.make_white_icon(raw_btn_icon, 14)
		btn_settings.add_theme_color_override("icon_normal_color", icon_col)
		btn_settings.add_theme_color_override("icon_hover_color", text_col)
		btn_settings.add_theme_color_override("icon_pressed_color", accent)
		btn_settings.add_theme_color_override("icon_focus_color", icon_col)
		
	_actualizar_vistas()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_pantalla = event.position
		_verificar_hover_guias()
		
		if indice_guia_activa >= 0:
			if moviendo_guia_h and camera and indice_guia_activa < guias_horizontales.size():
				guias_horizontales[indice_guia_activa] = _snap_guia(_pantalla_a_lienzo_y(mouse_pantalla.y))
			elif moviendo_guia_v and camera and indice_guia_activa < guias_verticales.size():
				guias_verticales[indice_guia_activa] = _snap_guia(_pantalla_a_lienzo_x(mouse_pantalla.x))
			
		_actualizar_vistas()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if indice_guia_hover != -1:
				grab_focus()
				indice_guia_activa = indice_guia_hover
				if hover_es_horizontal:
					moviendo_guia_h = true
					moviendo_guia_v = false
				else:
					moviendo_guia_v = true
					moviendo_guia_h = false
			else:
				indice_guia_activa = -1 
		else:
			# --- ACCIÓN AL SOLTAR EL CLIC ---
			if arrastrando_nueva_h and camera:
				var limit_y = regla_horizontal.global_position.y + regla_horizontal.size.y
				if mouse_pantalla.y > limit_y:
					guias_horizontales.append(_snap_guia(_pantalla_a_lienzo_y(mouse_pantalla.y)))
					_lanzar_flash(true, color_flash_crear)
				arrastrando_nueva_h = false

			elif arrastrando_nueva_v and camera:
				var limit_x = regla_vertical.global_position.x + regla_vertical.size.x
				if mouse_pantalla.x > limit_x:
					guias_verticales.append(_snap_guia(_pantalla_a_lienzo_x(mouse_pantalla.x)))
					_lanzar_flash(false, color_flash_crear)
				arrastrando_nueva_v = false
				
			elif moviendo_guia_h and indice_guia_activa >= 0 and indice_guia_activa < guias_horizontales.size():
				var limit_y = regla_horizontal.global_position.y + regla_horizontal.size.y
				if mouse_pantalla.y <= limit_y:
					guias_horizontales.remove_at(indice_guia_activa)
					_lanzar_flash(true, color_flash_eliminar)
				indice_guia_activa = -1
				moviendo_guia_h = false
				
			elif moviendo_guia_v and indice_guia_activa >= 0 and indice_guia_activa < guias_verticales.size():
				var limit_x = regla_vertical.global_position.x + regla_vertical.size.x
				if mouse_pantalla.x <= limit_x:
					guias_verticales.remove_at(indice_guia_activa)
					_lanzar_flash(false, color_flash_eliminar)
				indice_guia_activa = -1
				moviendo_guia_v = false
				
			moviendo_guia_h = false
			moviendo_guia_v = false
			_verificar_hover_guias()
			_actualizar_vistas()

	# Borrar guías con teclado de forma segura (Delete / Backspace)
	if event is InputEventKey and event.pressed and indice_guia_activa != -1:
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			if hover_es_horizontal and indice_guia_activa >= 0 and indice_guia_activa < guias_horizontales.size():
				guias_horizontales.remove_at(indice_guia_activa)
				_lanzar_flash(true, color_flash_eliminar)
			elif not hover_es_horizontal and indice_guia_activa >= 0 and indice_guia_activa < guias_verticales.size():
				guias_verticales.remove_at(indice_guia_activa)
				_lanzar_flash(false, color_flash_eliminar)
			
			moviendo_guia_h = false
			moviendo_guia_v = false
			indice_guia_activa = -1
			indice_guia_hover = -1
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			_actualizar_vistas()

func _process(_delta: float) -> void:
	if camera:
		_actualizar_vistas()

# ==============================================================================
# ENTRADAS DE LAS BARRAS DE REGLA
# ==============================================================================
func _input_regla_horizontal(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if indice_guia_hover == -1:
			arrastrando_nueva_h = true

func _input_regla_vertical(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if indice_guia_hover == -1:
			arrastrando_nueva_v = true

# ==============================================================================
# DETECCIÓN DE CERCANÍA (Hover) A LAS GUÍAS
# ==============================================================================
func _verificar_hover_guias() -> void:
	if not camera or arrastrando_nueva_h or arrastrando_nueva_v or moviendo_guia_h or moviendo_guia_v:
		return

	var view_size = get_viewport_rect().size
	var lienzo_start = camera.get_screen_center_position() - (view_size / 2) / camera.zoom
	
	indice_guia_hover = -1
	
	for i in range(guias_horizontales.size()):
		var screen_y = (guias_horizontales[i] - lienzo_start.y) * camera.zoom.y
		if abs(mouse_pantalla.y - screen_y) < TOLERANCIA_SELECCION:
			indice_guia_hover = i
			hover_es_horizontal = true
			mouse_default_cursor_shape = Control.CURSOR_VSPLIT
			return
			
	for i in range(guias_verticales.size()):
		var screen_x = (guias_verticales[i] - lienzo_start.x) * camera.zoom.x
		if abs(mouse_pantalla.x - screen_x) < TOLERANCIA_SELECCION:
			indice_guia_hover = i
			hover_es_horizontal = false
			mouse_default_cursor_shape = Control.CURSOR_HSPLIT
			return
			
	mouse_default_cursor_shape = Control.CURSOR_ARROW

# ==============================================================================
# RENDERIZADO Y DIBUJO
# ==============================================================================
func _dibujar_regla_horizontal() -> void:
	if not camera: return
	var size_h = regla_horizontal.size
	
	if color_actual_flash_h.a > 0.0:
		regla_horizontal.draw_rect(Rect2(Vector2.ZERO, size_h), color_actual_flash_h)
		
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var text_col: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color.WHITE
	var tick_sub_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color.DARK_GRAY
	var tick_main_col: Color = text_col

	var zoom = camera.zoom.x
	var lienzo_start_x = camera.get_screen_center_position().x - (get_viewport_rect().size.x / 2) / zoom
	var paso_pixeles = _calcular_paso(zoom)
	var offset_gx = regla_horizontal.global_position.x
	var visible_start_x = lienzo_start_x + (offset_gx / zoom)
	var x_actual = floor(visible_start_x / paso_pixeles) * paso_pixeles
	while true:
		var pos_x = (x_actual - lienzo_start_x) * zoom - offset_gx
		if pos_x > size_h.x: break
		var sub_paso = paso_pixeles / 10.0
		for i in range(10):
			var sub_x = pos_x + (i * sub_paso * zoom)
			if sub_x > size_h.x: break
			if sub_x >= 0:
				regla_horizontal.draw_line(Vector2(sub_x, size_h.y - (4.0 if i != 5 else 8.0)), Vector2(sub_x, size_h.y), tick_sub_col, 1.0)
		if pos_x >= 0:
			regla_horizontal.draw_line(Vector2(pos_x, size_h.y - 14), Vector2(pos_x, size_h.y), tick_main_col, 1.2)
			regla_horizontal.draw_string(ThemeDB.fallback_font, Vector2(pos_x + 3, 12), str(int(x_actual)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, text_col)
		x_actual += paso_pixeles

	var mouse_x_local = regla_horizontal.get_local_mouse_position().x
	if mouse_x_local >= 0 and mouse_x_local <= size_h.x:
		regla_horizontal.draw_line(Vector2(mouse_x_local, 0), Vector2(mouse_x_local, size_h.y), Color.CYAN, 1.0)

func _dibujar_regla_vertical() -> void:
	if not camera: return
	var size_v = regla_vertical.size
	
	if color_actual_flash_v.a > 0.0:
		regla_vertical.draw_rect(Rect2(Vector2.ZERO, size_v), color_actual_flash_v)
		
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var text_col: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color.WHITE
	var tick_sub_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color.DARK_GRAY
	var tick_main_col: Color = text_col

	var zoom = camera.zoom.y
	var lienzo_start_y = camera.get_screen_center_position().y - (get_viewport_rect().size.y / 2) / zoom
	var paso_pixeles = _calcular_paso(zoom)
	var offset_gy = regla_vertical.global_position.y
	var visible_start_y = lienzo_start_y + (offset_gy / zoom)
	var y_actual = floor(visible_start_y / paso_pixeles) * paso_pixeles
	while true:
		var pos_y = (y_actual - lienzo_start_y) * zoom - offset_gy
		if pos_y > size_v.y: break
		var sub_paso = paso_pixeles / 10.0
		for i in range(10):
			var sub_y = pos_y + (i * sub_paso * zoom)
			if sub_y > size_v.y: break
			if sub_y >= 0:
				regla_vertical.draw_line(Vector2(size_v.x - (4.0 if i != 5 else 8.0), sub_y), Vector2(size_v.x, sub_y), tick_sub_col, 1.0)
		if pos_y >= 0:
			regla_vertical.draw_line(Vector2(size_v.x - 14, pos_y), Vector2(size_v.x, pos_y), tick_main_col, 1.2)
			regla_vertical.draw_string(ThemeDB.fallback_font, Vector2(3, pos_y + 10), str(int(y_actual)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, text_col)
		y_actual += paso_pixeles

	var mouse_y_local = regla_vertical.get_local_mouse_position().y
	if mouse_y_local >= 0 and mouse_y_local <= size_v.y:
		regla_vertical.draw_line(Vector2(0, mouse_y_local), Vector2(size_v.x, mouse_y_local), Color.CYAN, 1.0)

func _draw() -> void:
	if not camera: return
	var zoom = camera.zoom
	var view_size = get_viewport_rect().size
	var lienzo_start = camera.get_screen_center_position() - (view_size / 2) / zoom
	var gpos = global_position

	# Delimitar estrictamente el área visible del lienzo (sin dibujar sobre inspectores ni barras)
	var min_x: float = 0.0
	var max_x: float = view_size.x
	var min_y: float = 0.0
	var max_y: float = view_size.y

	var p = get_parent()
	if p:
		var di = p.find_child("DockedInspector", true, false) as Control
		if di and di.visible:
			max_x = minf(max_x, di.global_position.x)
		var ps = p.find_child("ProStudio", true, false) as Control
		if ps and ps.visible:
			max_x = minf(max_x, ps.global_position.x)
		var lay = p.find_child("Layout", true, false) as Control
		if _is_left_dock(lay):
			min_x = maxf(min_x, lay.global_position.x + lay.size.x)
		var topb = p.find_child("ModernTopBar", true, false) as Control
		if topb and topb.visible:
			min_y = maxf(min_y, topb.global_position.y + topb.size.y)
		var ptop = p.find_child("ProTopBar", true, false) as Control
		if ptop and ptop.visible:
			min_y = maxf(min_y, ptop.global_position.y + ptop.size.y)

	# Dibujar guías horizontales fijadas
	for i in range(guias_horizontales.size()):
		var local_y = (guias_horizontales[i] - lienzo_start.y) * zoom.y - gpos.y
		if local_y >= min_y and local_y <= max_y:
			var col = color_guia_seleccionada if (indice_guia_activa == i and hover_es_horizontal) else color_guia_normal
			draw_line(Vector2(min_x, local_y), Vector2(max_x, local_y), col, 1.2 if idx_activo(i, true) else 1.0)

	# Dibujar guías verticales fijadas
	for i in range(guias_verticales.size()):
		var local_x = (guias_verticales[i] - lienzo_start.x) * zoom.x - gpos.x
		if local_x >= min_x and local_x <= max_x:
			var col = color_guia_seleccionada if (indice_guia_activa == i and not hover_es_horizontal) else color_guia_normal
			draw_line(Vector2(local_x, min_y), Vector2(local_x, max_y), col, 1.2 if idx_activo(i, false) else 1.0)

	# Previsualización dinámica al crear
	if arrastrando_nueva_h:
		var local_my = mouse_pantalla.y - gpos.y
		if local_my >= min_y and local_my <= max_y:
			draw_line(Vector2(min_x, local_my), Vector2(max_x, local_my), color_guia_previsualizacion, 1.0)
			_etiqueta_coord(true, local_my, _pantalla_a_lienzo_y(mouse_pantalla.y))
	if arrastrando_nueva_v:
		var local_mx = mouse_pantalla.x - gpos.x
		if local_mx >= min_x and local_mx <= max_x:
			draw_line(Vector2(local_mx, min_y), Vector2(local_mx, max_y), color_guia_previsualizacion, 1.0)
			_etiqueta_coord(false, local_mx, _pantalla_a_lienzo_x(mouse_pantalla.x))

	# Etiqueta de coordenada al mover una guía existente (estilo Figma/Illustrator)
	if moviendo_guia_h and indice_guia_activa >= 0 and indice_guia_activa < guias_horizontales.size():
		var sy: float = (guias_horizontales[indice_guia_activa] - lienzo_start.y) * zoom.y - gpos.y
		_etiqueta_coord(true, sy, guias_horizontales[indice_guia_activa])
	if moviendo_guia_v and indice_guia_activa >= 0 and indice_guia_activa < guias_verticales.size():
		var sx: float = (guias_verticales[indice_guia_activa] - lienzo_start.x) * zoom.x - gpos.x
		_etiqueta_coord(false, sx, guias_verticales[indice_guia_activa])

## ¿El panel de capas está ACOPLADO a la izquierda (Modern / Pro)? En Smart
## flota a la derecha: antes se tomaba igual como borde izquierdo y las guías
## quedaban fuera de la pantalla (no se veía ninguna).
func _is_left_dock(lay: Control) -> bool:
	if lay == null or not lay.is_visible_in_tree():
		return false
	var vs := get_viewport_rect().size
	var r := lay.get_global_rect()
	return r.position.x < vs.x * 0.5 and r.size.x < vs.x * 0.5

## Pastilla con la coordenada de mundo junto a la guía que se arrastra.
func _etiqueta_coord(es_horizontal: bool, screen_pos: float, world_coord: float) -> void:
	var font := ThemeDB.fallback_font
	if not font:
		return

	var vp_size := get_viewport_rect().size
	var min_x := (regla_vertical.position.x + regla_vertical.size.x) if regla_vertical else 0.0
	var max_x := (regla_horizontal.position.x + regla_horizontal.size.x) if regla_horizontal else vp_size.x
	var min_y := (regla_horizontal.position.y + regla_horizontal.size.y) if regla_horizontal else 0.0
	var max_y := vp_size.y

	var p = get_parent()
	if is_instance_valid(p):
		var di = p.find_child("DockedInspector", true, false) as Control
		if di and di.visible:
			max_x = minf(max_x, di.position.x)
		var ps = p.find_child("ProStudio", true, false) as Control
		if ps and ps.visible:
			max_x = minf(max_x, ps.position.x)
		var lay = p.find_child("Layout", true, false) as Control
		if _is_left_dock(lay):
			min_x = maxf(min_x, lay.position.x + lay.size.x)
		var topb = p.find_child("ModernTopBar", true, false) as Control
		if topb and topb.visible:
			min_y = maxf(min_y, topb.position.y + topb.size.y)
		var ptop = p.find_child("ProTopBar", true, false) as Control
		if ptop and ptop.visible:
			min_y = maxf(min_y, ptop.position.y + ptop.size.y)

	# Si la posición en pantalla cae fuera del área del lienzo visible, no dibujar
	if es_horizontal:
		if screen_pos < min_y or screen_pos > max_y:
			return
	else:
		if screen_pos < min_x or screen_pos > max_x:
			return

	var txt := str(roundi(world_coord))
	var fs := 10
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := Vector2(6, 3)
	var box_w := tw + pad.x * 2
	var box_h := fs + pad.y * 2

	var origen: Vector2
	var left_label_x = min_x + 4.0
	var top_label_y = min_y + 4.0

	if es_horizontal:
		var orig_y := screen_pos - 8.0 - pad.y * 2.0
		if orig_y < min_y + 4.0:
			orig_y = screen_pos + 8.0
		origen = Vector2(left_label_x, orig_y)
	else:
		var orig_x := screen_pos + 8.0
		if orig_x + box_w > max_x - 4.0:
			orig_x = screen_pos - box_w - 8.0
		origen = Vector2(orig_x, top_label_y)

	# Asegurar que la caja quede completamente dentro del lienzo visible
	if origen.x < min_x or (origen.x + box_w) > max_x:
		return
	if origen.y < min_y or (origen.y + box_h) > max_y:
		return

	var caja := Rect2(origen, Vector2(box_w, box_h))
	draw_rect(caja, Color(0.12, 0.12, 0.14, 0.92), true)
	draw_string(font, origen + Vector2(pad.x, fs + pad.y - 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

## Redondea la coord de una guía: al paso de cuadrícula si está activa, si no al píxel.
func _snap_guia(world_coord: float) -> float:
	var sm := get_node_or_null("/root/SnapManager")
	if sm and sm.grid_enabled and sm.grid_size > 0.0:
		return round(world_coord / sm.grid_size) * sm.grid_size
	return round(world_coord)

func idx_activo(idx: int, es_h: bool) -> bool:
	return indice_guia_activa == idx and hover_es_horizontal == es_h

# ==============================================================================
# SISTEMA DE DESTELLOS ANIMADOS (Flashes)
# ==============================================================================
func _lanzar_flash(es_horizontal: bool, color_inicial: Color) -> void:
	var tween = create_tween()
	if es_horizontal:
		color_actual_flash_h = color_inicial
		tween.tween_property(self, "color_actual_flash_h:a", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		color_actual_flash_v = color_inicial
		tween.tween_property(self, "color_actual_flash_v:a", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _actualizar_vistas() -> void:
	if regla_horizontal: regla_horizontal.queue_redraw()
	if regla_vertical: regla_vertical.queue_redraw()
	queue_redraw()
	_publicar_guias_al_snap()

## Publica las guías (coords de mundo) al SnapManager para que las figuras
## puedan imantarse a ellas al arrastrar. `guias_verticales` = coords X (líneas
## verticales); `guias_horizontales` = coords Y (líneas horizontales).
func _publicar_guias_al_snap() -> void:
	var sm := get_node_or_null("/root/SnapManager")
	if sm and sm.has_method("set_guides"):
		sm.set_guides(guias_verticales, guias_horizontales)

# ==============================================================================
# CONVERSIONES MATEMÁTICAS
# ==============================================================================
func _calcular_paso(zoom: float) -> int:
	if zoom > 6: return 10
	if zoom > 2: return 50
	if zoom < 0.4: return 500
	return 100

func _pantalla_a_lienzo_x(px: float) -> float:
	return (camera.get_screen_center_position().x - (get_viewport_rect().size.x / 2) / camera.zoom.x) + (px / camera.zoom.x)

func _pantalla_a_lienzo_y(px: float) -> float:
	return (camera.get_screen_center_position().y - (get_viewport_rect().size.y / 2) / camera.zoom.y) + (px / camera.zoom.y)

# ── API pública para Panel de Configuración ──────────────────────────────

func set_ruler_h_visible(v: bool) -> void:
	if regla_horizontal: regla_horizontal.visible = v

func set_ruler_v_visible(v: bool) -> void:
	if regla_vertical: regla_vertical.visible = v

func is_ruler_h_visible() -> bool:
	return regla_horizontal.visible if regla_horizontal else false

func is_ruler_v_visible() -> bool:
	return regla_vertical.visible if regla_vertical else false

func clear_all_guides() -> void:
	guias_horizontales.clear()
	guias_verticales.clear()
	queue_redraw()
	_publicar_guias_al_snap()

## Guías activas en coords de mundo (para el imán / API externa).
func get_guides_x() -> Array:
	return guias_verticales.duplicate()

func get_guides_y() -> Array:
	return guias_horizontales.duplicate()

func toggle_guides_visible(v: bool) -> void:
	if not v:
		clear_all_guides()
