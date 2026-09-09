@tool
extends VectorShape
class_name VectorRectangle

@export var size: Vector2 = Vector2(100, 100)

## Radios de esquina independientes (editor profesional). Backing real.
var _r_tl: float = 0.0
var _r_tr: float = 0.0
var _r_br: float = 0.0
var _r_bl: float = 0.0

## Radio UNIFORME de conveniencia: leer devuelve el promedio; escribir pone los
## 4 a la vez. Los tools y el serializador antiguo usan esta propiedad.
@export var corner_radius: float = 0.0:
	set(v):
		var r := maxf(0.0, v)
		_r_tl = r; _r_tr = r; _r_br = r; _r_bl = r
		queue_redraw()
	get:
		return (_r_tl + _r_tr + _r_br + _r_bl) * 0.25

@export var corner_tl: float = 0.0:
	set(v): _r_tl = maxf(0.0, v); queue_redraw()
	get: return _r_tl
@export var corner_tr: float = 0.0:
	set(v): _r_tr = maxf(0.0, v); queue_redraw()
	get: return _r_tr
@export var corner_br: float = 0.0:
	set(v): _r_br = maxf(0.0, v); queue_redraw()
	get: return _r_br
@export var corner_bl: float = 0.0:
	set(v): _r_bl = maxf(0.0, v); queue_redraw()
	get: return _r_bl

## Los 4 radios como Vector4 (tl, tr, br, bl) — para el panel de transformación.
func get_corner_radii() -> Vector4:
	return Vector4(_r_tl, _r_tr, _r_br, _r_bl)

func set_corner_radii(v: Vector4) -> void:
	_r_tl = maxf(0.0, v.x)
	_r_tr = maxf(0.0, v.y)
	_r_br = maxf(0.0, v.z)
	_r_bl = maxf(0.0, v.w)
	queue_redraw()

const ROUNDED_RECT_CORNER_SEGMENTS: int = 16

func _init() -> void:
	_register_doc_extent("size")

func get_effect_points() -> PackedVector2Array:
	var rect: Rect2 = Rect2(-size/2, size)
	if _r_tl > 0 or _r_tr > 0 or _r_br > 0 or _r_bl > 0:
		return _generate_rounded_rect_vertices(rect)
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])

func _draw() -> void:
	var rect: Rect2 = Rect2(-size/2, size)
	var pts := get_effect_points()
	draw_effects_shadows(pts)

	if _r_tl > 0 or _r_tr > 0 or _r_br > 0 or _r_bl > 0:
		_draw_custom_rounded_rect(rect, fill_color, stroke_color, stroke_width, 0.0)
	else:
		# Relleno (plano o degradado — draw_fill decide)
		draw_fill(pts)

		# Borde
		if stroke_width > 0:
			var s_rect: Rect2 = rect
			if stroke_align == 1: # Inside
				s_rect = rect.grow(-stroke_width * 0.5)
			elif stroke_align == 2: # Outside
				s_rect = rect.grow(stroke_width * 0.5)
			if stroke_style == 0:
				var sp := _get_rendered_stroke_params(stroke_width, stroke_color)
				draw_rect(s_rect, sp[1], false, sp[0], false)
			else:
				var s_pts := PackedVector2Array([
					s_rect.position,
					Vector2(s_rect.end.x, s_rect.position.y),
					s_rect.end,
					Vector2(s_rect.position.x, s_rect.end.y),
				])
				draw_stroke_ring(s_pts)

	draw_effects_overlays(pts)

## Dibuja el rectángulo redondeado como polígono propio (en vez de StyleBoxFlat,
## cuyo border_width/corner_radius son int en el motor y truncarían la precisión
## sub-píxel del radio y del grosor de trazo).
func _draw_custom_rounded_rect(rect: Rect2, _f_color: Color, _s_color: Color, s_width: float, _unused: float) -> void:
	var verts := _generate_rounded_rect_vertices(rect)

	draw_fill(verts)

	if s_width > 0:
		var stroke_rect: Rect2 = rect
		if stroke_align == 1: # Inside
			stroke_rect = rect.grow(-s_width * 0.5)
		elif stroke_align == 2: # Outside
			stroke_rect = rect.grow(s_width * 0.5)
		var s_verts := _generate_rounded_rect_vertices(stroke_rect)
		draw_stroke_ring(s_verts)

func _generate_rounded_rect_vertices(rect: Rect2) -> PackedVector2Array:
	var max_r: float = min(rect.size.x, rect.size.y) / 2.0
	var rtl: float = clampf(_r_tl, 0.0, max_r)
	var rtr: float = clampf(_r_tr, 0.0, max_r)
	var rbr: float = clampf(_r_br, 0.0, max_r)
	var rbl: float = clampf(_r_bl, 0.0, max_r)
	var corners := [
		{"center": rect.position + Vector2(rtl, rtl), "start": PI, "r": rtl},                                # TL
		{"center": rect.position + Vector2(rect.size.x - rtr, rtr), "start": -PI / 2.0, "r": rtr},           # TR
		{"center": rect.position + Vector2(rect.size.x - rbr, rect.size.y - rbr), "start": 0.0, "r": rbr},   # BR
		{"center": rect.position + Vector2(rbl, rect.size.y - rbl), "start": PI / 2.0, "r": rbl},            # BL
	]

	var verts := PackedVector2Array()
	for corner in corners:
		var center: Vector2 = corner["center"]
		var start_angle: float = corner["start"]
		var r: float = corner["r"]
		if r <= 0.0:
			verts.append(center)   # esquina viva
			continue
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
	var s: Dictionary = super()
	s["type"] = "rectangle"
	s["position"] = doc_position.to_v2()
	s["size"] = get_doc_extent().to_v2()
	s["rotation"] = doc_rotation
	return s

func serialize() -> Dictionary:
	return get_state()

func to_svg() -> String:
	# Agregamos soporte para corner_radius en SVG (rx). Formateado a 4 decimales
	# desde doc-space (doble precisión), no desde la caché de renderizado float32.
	var px: float = doc_position.x
	var py: float = doc_position.y
	var sx: float = get_doc_extent().x
	var sy: float = get_doc_extent().y
	var filter_attr: String = get_svg_filter_attr()
	var svg = '<rect x="%.4f" y="%.4f" width="%.4f" height="%.4f" rx="%.4f" fill="%s" stroke="%s" stroke-width="%.4f" transform="rotate(%.4f %.4f %.4f)"%s />' % [
		px - sx / 2.0,
		py - sy / 2.0,
		sx, sy,
		corner_radius,
		fill_color.to_html(),
		stroke_color.to_html(),
		stroke_width,
		rad_to_deg(doc_rotation),
		px, py,
		filter_attr
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
