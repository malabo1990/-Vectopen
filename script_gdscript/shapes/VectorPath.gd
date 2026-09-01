# =============================================================================
# RUTA: res://script_gdscript/shapes/VectorPath.gd
# Trazo Bézier editable (Path2D).
#
# El estilo se expone con los MISMOS nombres que VectorShape
# (fill_color / stroke_color / stroke_width) para que InspectorCore y el panel
# de trazos lo traten igual que a un rectángulo o un polígono, sin ramas
# especiales. `closed` mantiene sincronizada la meta "is_closed" que ya usan
# el serializador y MoveTool.
# =============================================================================
@tool
extends Path2D

@export var fill_color: Color = Color(0.09, 0.37, 0.65, 0.06):
	set(v):
		fill_color = v
		queue_redraw()

@export var stroke_color: Color = Color(0.22, 0.22, 0.22, 1.0):
	set(v):
		stroke_color = v
		queue_redraw()

@export var stroke_width: float = 2.0:
	set(v):
		stroke_width = maxf(0.0, v)
		queue_redraw()

@export var closed: bool = false:
	set(v):
		closed = v
		set_meta("is_closed", v)
		queue_redraw()

func _ready() -> void:
	# Compat: los trazos cargados de disco traen el estado como meta.
	if has_meta("is_closed"):
		closed = bool(get_meta("is_closed"))
	if curve and not curve.changed.is_connected(_solicitar_redibuja):
		curve.changed.connect(_solicitar_redibuja)
	queue_redraw()

func _solicitar_redibuja() -> void:
	queue_redraw()

func _draw() -> void:
	if not curve or curve.point_count < 2:
		return
	var baked: PackedVector2Array = curve.get_baked_points()
	if baked.size() < 2:
		return

	if closed:
		# Solo rellenar si el contorno es triangulable: un baked degenerado
		# (puntos casi colineales / auto-intersección) hace que el servidor de
		# render emita "triangulation failed". triangulate_polygon lo detecta
		# sin ruido (devuelve vacío) y así no dibujamos basura.
		if fill_color.a > 0.0 and baked.size() >= 3 \
				and not Geometry2D.triangulate_polygon(baked).is_empty():
			draw_colored_polygon(baked, fill_color)
		if stroke_width > 0.0:
			var ring := PackedVector2Array(baked)
			ring.append(baked[0])
			draw_polyline(ring, stroke_color, stroke_width, false)
	elif stroke_width > 0.0:
		draw_polyline(baked, stroke_color, stroke_width, false)

func is_path_closed() -> bool:
	return closed

## Exporta este path como elemento <path> SVG a partir de los puntos horneados
## (misma fuente que _draw()).
func to_svg() -> String:
	if not curve or curve.point_count < 2:
		return ""
	var baked_pts: PackedVector2Array = curve.get_baked_points()
	if baked_pts.size() < 2:
		return ""

	var d := "M %f,%f " % [position.x + baked_pts[0].x, position.y + baked_pts[0].y]
	for i in range(1, baked_pts.size()):
		d += "L %f,%f " % [position.x + baked_pts[i].x, position.y + baked_pts[i].y]
	if closed:
		d += "Z"

	var fill: String = fill_color.to_html() if (closed and fill_color.a > 0.0) else "none"
	return '<path d="%s" fill="%s" stroke="%s" stroke-width="%f" />' % [
		d, fill, stroke_color.to_html(), stroke_width
	]
