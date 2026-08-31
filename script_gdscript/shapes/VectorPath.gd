# =============================================================================
# RUTA: res://scripts/VectorPath.gd
# =============================================================================
extends Path2D

const STROKE_COLOR := Color(0, 0, 0, 1) # Negro Vectopen
const STROKE_WIDTH := 3.0

func _ready() -> void:
	# Conexión limpia a la señal nativa de la curva en Godot 4
	if curve:
		if not curve.changed.is_connected(solicitar_redibuja):
			curve.changed.connect(solicitar_redibuja)
	solicitar_redibuja()

func solicitar_redibuja() -> void:
	queue_redraw()

func _draw() -> void:
	if not curve or curve.point_count < 2: return

	var baked_pts: PackedVector2Array = curve.get_baked_points()
	if baked_pts.size() < 2: return

	# 1. Relleno si la figura está cerrada
	if get_meta("is_closed", false):
		var fill_color := Color(0, 0, 0, 0.1)
		draw_polygon(baked_pts, [fill_color])

		# Cierre visual del trazo
		var closed_polyline := baked_pts
		closed_polyline.append(baked_pts[0])
		draw_polyline(closed_polyline, STROKE_COLOR, STROKE_WIDTH, false)
	else:
		# 2. Contorno abierto estándar
		draw_polyline(baked_pts, STROKE_COLOR, STROKE_WIDTH, false)

## Exporta este path como elemento <path> SVG. Usa los puntos horneados de
## la curva (misma fuente de datos que _draw()) en vez de reconstruir
## comandos bezier "C" desde los control points — más simple y consistente
## visualmente con lo que el usuario ve en el canvas.
func to_svg() -> String:
	if not curve or curve.point_count < 2:
		return ""
	var baked_pts: PackedVector2Array = curve.get_baked_points()
	if baked_pts.size() < 2:
		return ""

	var d := "M %f,%f " % [position.x + baked_pts[0].x, position.y + baked_pts[0].y]
	for i in range(1, baked_pts.size()):
		d += "L %f,%f " % [position.x + baked_pts[i].x, position.y + baked_pts[i].y]

	var is_closed: bool = get_meta("is_closed", false)
	if is_closed:
		d += "Z"

	var fill: String = "rgba(0,0,0,0.1)" if is_closed else "none"
	return '<path d="%s" fill="%s" stroke="%s" stroke-width="%f" />' % [
		d, fill, STROKE_COLOR.to_html(), STROKE_WIDTH
	]
