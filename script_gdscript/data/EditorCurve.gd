@tool
extends Control

# --- CONFIGURACIÓN AVANZADA DEL INSPECTOR ---

@export_group("Lienzo y Fondo", "bg_")
@export var bg_color: Color = Color(0.12, 0.12, 0.12, 1.0)
@export var bg_draw_border: bool = true
@export var bg_border_color: Color = Color(0.25, 0.25, 0.25, 1.0)

@export_subgroup("Cuadrícula", "grid_")
@export var grid_enable: bool = true
@export var grid_color: Color = Color(0.25, 0.25, 0.25, 0.2)
@export var grid_thickness: float = 1.0
@export var grid_divisions: int = 4

@export_group("Estilo de la Curva", "curve_")
@export var curve_main_color: Color = Color(0.0, 0.47, 1.0, 1.0) # Azul Figma
@export var curve_thickness: float = 2.0
@export var curve_bezier_resolution: int = 40 # Más alto = curva más suave

@export_group("Nodos y Palancas", "node_")
@export var node_default_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var node_selected_color: Color = Color(0.0, 0.47, 1.0, 1.0)
@export var node_radius: float = 5.0
@export var node_hover_margin: float = 10.0

@export_subgroup("Palancas Bézier (Handles)", "handle_")
@export var handle_line_color: Color = Color(1.0, 1.0, 1.0, 0.25)
@export var handle_line_thickness: float = 1.0
@export var handle_point_color: Color = Color(0.0, 0.75, 1.0, 1.0)
@export var handle_point_radius: float = 3.5

@export_group("Botonera Inferior", "btn_")
@export var btn_height: float = 30.0
@export var btn_bg_normal: Color = Color(0.16, 0.16, 0.16, 1.0)
@export var btn_bg_active: Color = Color(0.0, 0.35, 0.8, 1.0)
@export var btn_text_normal: Color = Color(0.6, 0.6, 0.6, 1.0)
@export var btn_text_active: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var btn_font_size: int = 10

@export_group("Datos", "curve_")
@export var curve_data: Resource:
	set(val):
		curve_data = val
		queue_redraw()

# --- VARIABLES DE ESTADO INTERNO ---
var selected_node: int = -1
var selected_handle_type: int = 0 # 0: Nodo, 1: Handle In, 2: Handle Out
var is_dragging: bool = false
var last_click_time: float = 0.0

var tipos = ["Linear", "Bézier", "Ease In", "Ease Out", "Sharp", "Step"]
var button_rects: Array[Rect2] = []

func _ready() -> void:
	custom_minimum_size = Vector2(250, 220)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	mouse_filter = MOUSE_FILTER_STOP
	
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)

# --- MATEMÁTICAS BÉZIER CÚBICA ---
func _get_bezier_point(t: float, p0: Vector2, h0_out: Vector2, h1_in: Vector2, p1: Vector2) -> Vector2:
	var q0 = p0.lerp(h0_out, t)
	var q1 = h0_out.lerp(h1_in, t)
	var q2 = h1_in.lerp(p1, t)
	var r0 = q0.lerp(q1, t)
	var r1 = q1.lerp(q2, t)
	return r0.lerp(r1, t)

# --- CONVERSORES DE ESPACIO ---
func _get_canvas_height() -> float:
	return size.y - btn_height

func _to_px(norm_pos: Vector2) -> Vector2:
	var margin = node_radius + 4.0
	var w = size.x - margin * 2
	var h = _get_canvas_height() - margin * 2
	return Vector2(margin + norm_pos.x * w, margin + norm_pos.y * h)

func _to_norm(px_pos: Vector2) -> Vector2:
	var margin = node_radius + 4.0
	var w = size.x - margin * 2
	var h = _get_canvas_height() - margin * 2
	return Vector2(clamp((px_pos.x - margin) / w, 0.0, 1.0), clamp((px_pos.y - margin) / h, 0.0, 1.0))

# --- GESTIÓN DE INPUTS ---
func _gui_input(event: InputEvent) -> void:
	if curve_data == null: return
	var p: PackedVector2Array = curve_data.get("points")
	var hi: PackedVector2Array = curve_data.get("handles_in")
	var ho: PackedVector2Array = curve_data.get("handles_out")
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var current_time = Time.get_ticks_msec() / 1000.0
		
		if event.pressed:
			# 1. Clic en botones inferiores
			for i in range(button_rects.size()):
				if button_rects[i].has_point(event.position):
					curve_data.set("curve_type", i)
					queue_redraw()
					accept_event()
					return
			
			# 2. Clic en palancas Bézier (Solo si el nodo está seleccionado y es modo Bézier)
			if selected_node != -1 and curve_data.get("curve_type") == 1:
				var px_in = _to_px(p[selected_node] + hi[selected_node])
				var px_out = _to_px(p[selected_node] + ho[selected_node])
				
				if event.position.distance_to(px_in) < node_hover_margin:
					selected_handle_type = 1
					is_dragging = true
					accept_event()
					return
				if event.position.distance_to(px_out) < node_hover_margin:
					selected_handle_type = 2
					is_dragging = true
					accept_event()
					return

			# 3. Clic en Nodos Principales
			var click_hit = false
			for i in range(p.size()):
				if event.position.distance_to(_to_px(p[i])) < node_hover_margin:
					selected_node = i
					selected_handle_type = 0
					is_dragging = true
					click_hit = true
					queue_redraw()
					accept_event()
					break
			
			# 4. DOBLE CLIC: Crear nuevo nodo intermedio
			if not click_hit and event.position.y < _get_canvas_height() and (current_time - last_click_time < 0.3):
				var new_pos_norm = _to_norm(event.position)
				_insertar_nodo_ordenado(new_pos_norm, p, hi, ho)
				accept_event()
				return
				
			if not click_hit:
				selected_node = -1
				queue_redraw()
				
			last_click_time = current_time
		else:
			is_dragging = false
			
	elif event is InputEventMouseMotion and is_dragging and selected_node != -1:
		var norm = _to_norm(event.position)
		
		if selected_handle_type == 0: # Nodo Principal
			if selected_node == 0: norm.x = 0.0
			elif selected_node == p.size() - 1: norm.x = 1.0
			p[selected_node] = norm
			_reordenar_nodos(p, hi, ho)
		elif selected_handle_type == 1: # Palanca Entrada
			hi[selected_node] = norm - p[selected_node]
		elif selected_handle_type == 2: # Palanca Salida
			ho[selected_node] = norm - p[selected_node]
			
		curve_data.set("points", p)
		curve_data.set("handles_in", hi)
		curve_data.set("handles_out", ho)
		queue_redraw()
		accept_event()

# --- SISTEMA DE ORDENACIÓN ---
func _insertar_nodo_ordenado(nuevo_punto: Vector2, p: PackedVector2Array, hi: PackedVector2Array, ho: PackedVector2Array) -> void:
	var idx = 1
	for i in range(p.size()):
		if nuevo_punto.x > p[i].x:
			idx = i + 1
			
	p.insert(idx, nuevo_punto)
	hi.insert(idx, Vector2(-0.1, 0.0))
	ho.insert(idx, Vector2(0.1, 0.0))
	
	curve_data.set("points", p)
	curve_data.set("handles_in", hi)
	curve_data.set("handles_out", ho)
	
	selected_node = idx
	selected_handle_type = 0
	is_dragging = true
	queue_redraw()

func _reordenar_nodos(p: PackedVector2Array, hi: PackedVector2Array, ho: PackedVector2Array) -> void:
	var p_actual = p[selected_node]
	if selected_node > 0 and p_actual.x < p[selected_node - 1].x:
		_swap(p, hi, ho, selected_node, selected_node - 1)
		selected_node -= 1
	elif selected_node < p.size() - 1 and p_actual.x > p[selected_node + 1].x:
		_swap(p, hi, ho, selected_node, selected_node + 1)
		selected_node += 1

func _swap(p: PackedVector2Array, hi: PackedVector2Array, ho: PackedVector2Array, i: int, j: int) -> void:
	var tmp_p = p[i]; p[i] = p[j]; p[j] = tmp_p
	var tmp_hi = hi[i]; hi[i] = hi[j]; hi[j] = tmp_hi
	var tmp_ho = ho[i]; ho[i] = ho[j]; ho[j] = tmp_ho

# --- RENDER VECTORIAL PERSONALIZADO ---
func _draw() -> void:
	var w = size.x
	var canvas_h = _get_canvas_height()
	
	# 1. Fondo del lienzo
	draw_rect(Rect2(0, 0, w, canvas_h), bg_color)
	if bg_draw_border:
		draw_rect(Rect2(0, 0, w, canvas_h), bg_border_color, false, 1.0)
	
	# 2. Cuadrícula técnica configurable
	if grid_enable and grid_divisions > 0:
		for i in range(1, grid_divisions):
			var x = (w / grid_divisions) * i
			var y = (canvas_h / grid_divisions) * i
			draw_line(Vector2(x, 0), Vector2(x, canvas_h), grid_color, grid_thickness)
			draw_line(Vector2(0, y), Vector2(w, y), grid_color, grid_thickness)
		
	if curve_data == null or not "points" in curve_data: return
	var p = curve_data.get("points")
	var type = curve_data.get("curve_type")
	
	# 3. Dibujo de las líneas de la curva
	if type == 0 or p.size() < 2: # Lineal
		var px_pts = PackedVector2Array()
		for pt in p: px_pts.append(_to_px(pt))
		draw_polyline(px_pts, curve_main_color, curve_thickness, true)
	elif type == 1: # Bézier Cúbico Avanzado
		var hi = curve_data.get("handles_in")
		var ho = curve_data.get("handles_out")
		for i in range(p.size() - 1):
			var b_pts = PackedVector2Array()
			for j in range(curve_bezier_resolution + 1):
				var t = j / float(curve_bezier_resolution)
				var pt = _get_bezier_point(t, p[i], p[i] + ho[i], p[i+1] + hi[i+1], p[i+1])
				b_pts.append(_to_px(pt))
			draw_polyline(b_pts, curve_main_color, curve_thickness, true)

	# 4. Palancas Bézier Inteligentes (Solo visibles al seleccionar el nodo)
	if type == 1 and selected_node != -1:
		var hi = curve_data.get("handles_in")
		var ho = curve_data.get("handles_out")
		var p_px = _to_px(p[selected_node])
		
		if selected_node > 0: # Palanca de entrada (In)
			var in_px = _to_px(p[selected_node] + hi[selected_node])
			draw_line(p_px, in_px, handle_line_color, handle_line_thickness)
			draw_circle(in_px, handle_point_radius, handle_point_color)
			draw_circle(in_px, handle_point_radius - 1.0, Color.WHITE, false, 1.0)
			
		if selected_node < p.size() - 1: # Palanca de salida (Out)
			var out_px = _to_px(p[selected_node] + ho[selected_node])
			draw_line(p_px, out_px, handle_line_color, handle_line_thickness)
			draw_circle(out_px, handle_point_radius, handle_point_color)
			draw_circle(out_px, handle_point_radius - 1.0, Color.WHITE, false, 1.0)

	# 5. Renderizado de los Nodos Principales
	for i in range(p.size()):
		var centro = _to_px(p[i])
		if i == selected_node:
			draw_circle(centro, node_radius + 2.0, node_selected_color)
			draw_circle(centro, node_radius - 0.5, Color.WHITE)
			draw_circle(centro, node_radius - 2.5, node_selected_color)
		else:
			draw_circle(centro, node_radius, bg_color.lightened(0.2))
			draw_circle(centro, node_radius - 1.0, node_default_color)

	# 6. Barra de Botones Inferior Estilo Figma
	button_rects.clear()
	var btn_w = w / tipos.size()
	var active_font = get_theme_font("font")
	
	for i in range(tipos.size()):
		var rect = Rect2(i * btn_w, canvas_h, btn_w, btn_height)
		button_rects.append(rect)
		
		var col_fondo = btn_bg_active if i == type else btn_bg_normal
		draw_rect(rect, col_fondo)
		draw_rect(rect, bg_border_color, false, 1.0) # Separadores finos
		
		if active_font:
			var texto_col = btn_text_active if i == type else btn_text_normal
			var text_offset_y = (btn_height / 2) + 4 # Centrado vertical simple
			draw_string(active_font, rect.position + Vector2(0, text_offset_y), tipos[i], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, btn_font_size, texto_col)
