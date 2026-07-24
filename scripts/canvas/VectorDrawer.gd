# ==========================================
# RUTA: res://scripts/canvas/VectorDrawer.gd
# ==========================================
extends Node2D
class_name VectorDrawer

# --- PROPIEDADES DE ESTILO ---
@export var brush_color: Color = Color("#7000ff")
@export var brush_width: float = 4.0
@export var eraser_radius: float = 20.0

# --- ESTRUCTURAS DE DATOS ---
var lines: Array[Dictionary] = []
var current_line: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	pass # VectorDrawer vive como hijo del Artboard, no necesita buscarlo

# =============================================================================
# GESTIÓN DE LÍNEAS LIBRES (PINCEL Y BORRADOR)
# =============================================================================

func _guardar_linea_actual() -> void:
	if current_line.size() > 1:
		lines.append({
			"points": current_line,
			"color": brush_color,
			"width": brush_width
		})
	current_line = PackedVector2Array()
	queue_redraw()

func _erase_lines_at_position(pos: Vector2) -> void:
	var lines_to_keep: Array[Dictionary] = []
	var changed = false

	for line in lines:
		var should_delete = false
		for point in line["points"]:
			if point.distance_to(pos) < eraser_radius:
				should_delete = true
				break
		if should_delete:
			changed = true
		else:
			lines_to_keep.append(line)

	if changed:
		lines = lines_to_keep
		queue_redraw()

# =============================================================================
# PIPELINE DE RENDERIZADO VISUAL VECTORIAL
# =============================================================================

func _draw() -> void:
	# -------------------------------------------------------------------------
	# 1. LÍNEAS LIBRES (PINCEL)
	# -------------------------------------------------------------------------
	for line in lines:
		if line["points"].size() > 1:
			draw_polyline(line["points"], line["color"], line["width"], true)

	if current_line.size() > 1:
		draw_polyline(current_line, brush_color, brush_width, true)

	# -------------------------------------------------------------------------
	# 2. CURVAS BÉZIER GUARDADAS
	# -------------------------------------------------------------------------
	if has_meta("vector_layers"):
		var layers: Array = get_meta("vector_layers")
		for curve in layers:
			if curve is Curve2D and curve.point_count > 1:
				draw_polyline(curve.get_baked_points(), brush_color, brush_width, true)

	# -------------------------------------------------------------------------
	# 3. CURVA ACTIVA EN TIEMPO REAL CON MANEJADORES
	# -------------------------------------------------------------------------
	if has_meta("active_curve"):
		var active_curve: Curve2D = get_meta("active_curve")

		if active_curve.point_count > 1:
			draw_polyline(active_curve.get_baked_points(), Color("#7000ff"), brush_width, true)

		for i in range(active_curve.point_count):
			var pos = active_curve.get_point_position(i)
			var h_in  = pos + active_curve.get_point_in(i)
			var h_out = pos + active_curve.get_point_out(i)

			if active_curve.get_point_in(i) != Vector2.ZERO:
				draw_line(pos, h_in, Color(1, 1, 1, 0.5), 1.2, true)
				draw_circle(h_in, 3.5, Color("#7000ff"))
				draw_circle(h_in, 2.0, Color.WHITE)

			if active_curve.get_point_out(i) != Vector2.ZERO:
				draw_line(pos, h_out, Color(1, 1, 1, 0.5), 1.2, true)
				draw_circle(h_out, 3.5, Color("#7000ff"))
				draw_circle(h_out, 2.0, Color.WHITE)

			var node_size := Vector2(7, 7)
			var node_rect := Rect2(pos - (node_size / 2), node_size)
			draw_rect(node_rect, Color.WHITE, true)
			draw_rect(node_rect, Color("#7000ff"), false, 1.5)
