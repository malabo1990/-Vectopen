@tool
extends VectorShape
class_name VectorRectangle

@export var size: Vector2 = Vector2(100, 100)
@export var corner_radius: float = 0.0

const ROUNDED_RECT_CORNER_SEGMENTS: int = 16

func _init() -> void:
	_register_doc_extent("size")

func _draw():
	var rect = Rect2(-size/2, size)

	if corner_radius > 0:
		_draw_custom_rounded_rect(rect, fill_color, stroke_color, stroke_width, corner_radius)
	else:
		# Relleno
		if fill_color.a > 0:
			draw_rect(rect, fill_color, true)

		# Borde
		if stroke_width > 0:
			# draw_rect(rect, color, filled, width)
			draw_rect(rect, stroke_color, false, stroke_width)

## Dibuja el rectángulo redondeado como polígono propio (en vez de StyleBoxFlat,
## cuyo border_width/corner_radius son int en el motor y truncarían la precisión
## sub-píxel del radio y del grosor de trazo).
func _draw_custom_rounded_rect(rect: Rect2, f_color: Color, s_color: Color, s_width: float, radius: float):
	var verts := _generate_rounded_rect_vertices(rect, radius)

	if f_color.a > 0:
		draw_colored_polygon(verts, f_color)

	if s_width > 0:
		var closed_verts := verts
		closed_verts.append(verts[0])
		# sin antialias por-primitiva (rompe el batching); el MSAA 2D lo cubre
		draw_polyline(closed_verts, s_color, s_width, false)

func _generate_rounded_rect_vertices(rect: Rect2, radius: float) -> PackedVector2Array:
	var r: float = min(radius, min(rect.size.x, rect.size.y) / 2.0)
	var corners := [
		{"center": rect.position + Vector2(r, r), "start": PI},                                    # arriba-izquierda
		{"center": rect.position + Vector2(rect.size.x - r, r), "start": -PI / 2.0},                # arriba-derecha
		{"center": rect.position + Vector2(rect.size.x - r, rect.size.y - r), "start": 0.0},        # abajo-derecha
		{"center": rect.position + Vector2(r, rect.size.y - r), "start": PI / 2.0},                 # abajo-izquierda
	]

	var verts := PackedVector2Array()
	for corner in corners:
		var center: Vector2 = corner["center"]
		var start_angle: float = corner["start"]
		for i in range(ROUNDED_RECT_CORNER_SEGMENTS + 1):
			var angle: float = start_angle + (float(i) / ROUNDED_RECT_CORNER_SEGMENTS) * (PI / 2.0)
			verts.append(center + Vector2(cos(angle), sin(angle)) * r)
	return verts

func set_selected(selected: bool):
	is_selected = selected
	if selected:
		# Ejemplo: un ligero brillo o cambio de escala
		modulate = Color(1.2, 1.2, 1.2, 1.0) 
	else:
		modulate = Color(1, 1, 1, 1)
	queue_redraw() # Forzar a que se vuelva a dibujar

func get_state() -> Dictionary:
	return {
		"id": object_id,
		"type": "rectangle",
		"position": doc_position.to_v2(),
		"size": get_doc_extent().to_v2(),
		"fill_color": fill_color,
		"stroke_color": stroke_color,
		"stroke_width": stroke_width,
		"rotation": doc_rotation
	}

func serialize() -> Dictionary:
	return get_state()

func to_svg() -> String:
	# Agregamos soporte para corner_radius en SVG (rx). Formateado a 4 decimales
	# desde doc-space (doble precisión), no desde la caché de renderizado float32.
	var px: float = doc_position.x
	var py: float = doc_position.y
	var sx: float = get_doc_extent().x
	var sy: float = get_doc_extent().y
	var svg = '<rect x="%.4f" y="%.4f" width="%.4f" height="%.4f" rx="%.4f" fill="%s" stroke="%s" stroke-width="%.4f" transform="rotate(%.4f %.4f %.4f)" />' % [
		px - sx / 2.0,
		py - sy / 2.0,
		sx, sy,
		corner_radius,
		fill_color.to_html(),
		stroke_color.to_html(),
		stroke_width,
		rad_to_deg(doc_rotation),
		px, py
	]
	return svg

# Nota: Asegúrate de que la clase Layer esté definida o usa Node
func copy_to_layer(target_layer: Node):
	# Asumiendo que target_layer tiene acceso al manager a través de su padre
	var parent = target_layer.get_parent()
	if parent.has_method("create_rectangle"):
		parent.create_rectangle(
			position, size, target_layer.name
		)
		# Lógica para copiar propiedades al nuevo objeto...
