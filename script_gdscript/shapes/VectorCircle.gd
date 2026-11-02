@tool
extends VectorShape
class_name VectorCircle

@export var size: Vector2 = Vector2(100, 100):
	set(v):
		size = v
		_verts_cache.clear()
		queue_redraw()

## Modos geométricos paramétricos (Sección 16 de especificación):
## "whole" (círculo completo), "arc" (arco abierto), "pie" (sector),
## "chord" (segmento/cuerda), "donut" (anillo)
@export var shape_mode: String = "whole":
	set(v):
		shape_mode = v
		_verts_cache.clear()
		queue_redraw()

@export var start_angle_deg: float = 0.0:
	set(v):
		start_angle_deg = v
		_verts_cache.clear()
		queue_redraw()

@export var end_angle_deg: float = 360.0:
	set(v):
		end_angle_deg = v
		_verts_cache.clear()
		queue_redraw()

@export var inner_radius_ratio: float = 0.5:
	set(v):
		inner_radius_ratio = clampf(v, 0.01, 0.95)
		_verts_cache.clear()
		queue_redraw()

const CIRCLE_QUALITY: int = 128
## Un arco a menos de esto de la vuelta completa (p. ej. 359,999°) cuenta como
## vuelta completa.
const FULL_TURN_TOLERANCE_DEG: float = 0.01

var _verts_cache: PackedVector2Array = PackedVector2Array()
var _verts_cache_size: Vector2 = Vector2(-1, -1)

func _init() -> void:
	_register_doc_extent("size")

func get_shape_type_code() -> int:
	return 1

func get_shape_size() -> Vector2:
	return size

func get_effect_points() -> PackedVector2Array:
	return _cached_vertices()

func _draw() -> void:
	if fill_color.a <= 0 and stroke_width <= 0 and not has_gradient_fill() and effects.is_empty():
		return
	var verts: PackedVector2Array = _cached_vertices()
	if verts.is_empty():
		return
	draw_effects_shadows(verts)

	if maybe_render_blur(verts):
		draw_effects_overlays(verts)
		return

	if shape_mode == "arc":
		if stroke_width > 0 and verts.size() >= 2:
			var sp: Array = _get_rendered_stroke_params(stroke_width, stroke_color)
			draw_polyline(verts, sp[1], sp[0], true)
	elif is_full_ring():
		var stroke_size: Vector2 = size
		if stroke_align == 1:
			stroke_size = Vector2(maxf(0.0, size.x - stroke_width), maxf(0.0, size.y - stroke_width))
		elif stroke_align == 2:
			stroke_size = size + Vector2(stroke_width, stroke_width)
		_draw_full_ring(stroke_size)
	else:
		draw_fill(verts)
		if stroke_width > 0:
			var ring_verts: PackedVector2Array = verts
			if stroke_align == 1: # Inside
				var s_size: Vector2 = Vector2(maxf(0.0, size.x - stroke_width), maxf(0.0, size.y - stroke_width))
				ring_verts = _generate_vertices_for_size(s_size)
			elif stroke_align == 2: # Outside
				var s_size: Vector2 = size + Vector2(stroke_width, stroke_width)
				ring_verts = _generate_vertices_for_size(s_size)
			draw_stroke_ring(ring_verts)

	draw_effects_overlays(verts)

## Recorrido angular en radianes; 0 o casi 360° = vuelta completa (TAU).
static func arc_span(start_deg: float, end_deg: float) -> float:
	var span_deg: float = fposmod(end_deg - start_deg, 360.0)
	if span_deg < FULL_TURN_TOLERANCE_DEG or span_deg > 360.0 - FULL_TURN_TOLERANCE_DEG:
		return TAU
	return deg_to_rad(span_deg)

## Anillo de vuelta completa: se dibuja como DOS circunferencias cerradas
## (sin el segmento radial que unía la exterior con la interior).
func is_full_ring() -> bool:
	return shape_mode == "donut" and is_equal_approx(arc_span(start_angle_deg, end_angle_deg), TAU)

## [exterior, interior] de un anillo completo, cada una cerrada y sin repetir
## el primer punto. `half` = semiejes exteriores.
static func ring_contours(half: Vector2, ratio: float, center: Vector2 = Vector2.ZERO, quality: int = CIRCLE_QUALITY) -> Array[PackedVector2Array]:
	var inner: Vector2 = half * clampf(ratio, 0.01, 0.95)
	var outer_pts := PackedVector2Array()
	var inner_pts := PackedVector2Array()
	for i in range(quality):
		var a: float = (i * TAU) / quality
		var d := Vector2(cos(a), sin(a))
		outer_pts.append(center + d * half)
		inner_pts.append(center + d * inner)
	return [outer_pts, inner_pts]

func _draw_full_ring(target_size: Vector2) -> void:
	var rings := ring_contours(size / 2.0, inner_radius_ratio)
	var outer: PackedVector2Array = rings[0]
	var inner: PackedVector2Array = rings[1]
	var n: int = outer.size()
	# Relleno: tira de triángulos entre las dos circunferencias.
	if has_gradient_fill() or fill_color.a > 0.0:
		var pts := PackedVector2Array(outer)
		pts.append_array(inner)
		var idx := PackedInt32Array()
		for i in range(n):
			var j: int = (i + 1) % n
			idx.append_array([i, j, n + i, j, n + j, n + i])
		var cols := PackedColorArray()
		var col: Color = Color.WHITE if has_gradient_fill() else fill_color
		cols.resize(pts.size())
		cols.fill(col)
		var uvs := PackedVector2Array()
		var tex := RID()
		if has_gradient_fill():
			var bb := _points_bounds(outer)
			var sx := maxf(bb.size.x, 0.001)
			var sy := maxf(bb.size.y, 0.001)
			for p in pts:
				uvs.append(Vector2((p.x - bb.position.x) / sx, (p.y - bb.position.y) / sy))
			var t: Texture2D = _ensure_grad_tex()
			if t:
				tex = t.get_rid()
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols, uvs, PackedInt32Array(), PackedFloat32Array(), tex)
	# Trazo: cada circunferencia por separado.
	if stroke_width > 0.0:
		var stroke_rings := rings
		if not target_size.is_equal_approx(size):
			stroke_rings = ring_contours(target_size / 2.0, inner_radius_ratio)
		draw_stroke_ring(stroke_rings[0])
		draw_stroke_ring(stroke_rings[1])

func _cached_vertices() -> PackedVector2Array:
	if _verts_cache.is_empty() or _verts_cache_size != size:
		_verts_cache = _generate_vertices()
		_verts_cache_size = size
	return _verts_cache

func _generate_vertices() -> PackedVector2Array:
	return _generate_vertices_for_size(size)

func _generate_vertices_for_size(target_size: Vector2) -> PackedVector2Array:
	var verts: PackedVector2Array = PackedVector2Array()
	var half: Vector2 = target_size / 2.0
	if half.x <= 0.0 or half.y <= 0.0:
		return verts

	if shape_mode == "whole":
		for i in range(CIRCLE_QUALITY):
			var angle: float = (i * 2.0 * PI) / CIRCLE_QUALITY
			verts.append(Vector2(cos(angle) * half.x, sin(angle) * half.y))
		return verts

	var s_rad: float = deg_to_rad(start_angle_deg)
	var e_rad: float = deg_to_rad(end_angle_deg)
	var span: float = arc_span(start_angle_deg, end_angle_deg)

	var steps: int = maxi(8, int(round((span / TAU) * CIRCLE_QUALITY)))

	match shape_mode:
		"arc":
			for i in range(steps + 1):
				var t: float = float(i) / float(steps)
				var a: float = s_rad + span * t
				verts.append(Vector2(cos(a) * half.x, sin(a) * half.y))
		"pie":
			verts.append(Vector2.ZERO)
			for i in range(steps + 1):
				var t: float = float(i) / float(steps)
				var a: float = s_rad + span * t
				verts.append(Vector2(cos(a) * half.x, sin(a) * half.y))
		"chord":
			for i in range(steps + 1):
				var t: float = float(i) / float(steps)
				var a: float = s_rad + span * t
				verts.append(Vector2(cos(a) * half.x, sin(a) * half.y))
		"donut":
			var inner: Vector2 = half * clampf(inner_radius_ratio, 0.01, 0.95)
			if is_equal_approx(span, TAU):
				for i in range(CIRCLE_QUALITY):
					var a: float = (i * 2.0 * PI) / CIRCLE_QUALITY
					verts.append(Vector2(cos(a) * half.x, sin(a) * half.y))
				verts.append(Vector2(cos(0.0) * half.x, sin(0.0) * half.y))
				verts.append(Vector2(cos(0.0) * inner.x, sin(0.0) * inner.y))
				for i in range(CIRCLE_QUALITY, -1, -1):
					var a: float = (i * 2.0 * PI) / CIRCLE_QUALITY
					verts.append(Vector2(cos(a) * inner.x, sin(a) * inner.y))
			else:
				for i in range(steps + 1):
					var t: float = float(i) / float(steps)
					var a: float = s_rad + span * t
					verts.append(Vector2(cos(a) * half.x, sin(a) * half.y))
				for i in range(steps, -1, -1):
					var t: float = float(i) / float(steps)
					var a: float = s_rad + span * t
					verts.append(Vector2(cos(a) * inner.x, sin(a) * inner.y))
		_:
			for i in range(CIRCLE_QUALITY):
				var angle: float = (i * 2.0 * PI) / CIRCLE_QUALITY
				verts.append(Vector2(cos(angle) * half.x, sin(angle) * half.y))

	return verts

func to_svg() -> String:
	var extent: DVec2 = get_doc_extent()
	var cx: float = doc_position.x
	var cy: float = doc_position.y
	var rx: float = extent.x / 2.0
	var ry: float = extent.y / 2.0
	var filter_attr: String = get_svg_filter_attr()
	if shape_mode == "whole":
		return '<ellipse cx="%.4f" cy="%.4f" rx="%.4f" ry="%.4f" fill="%s" stroke="%s" stroke-width="%.4f"%s />' % [
			cx, cy, rx, ry,
			fill_color.to_html(), stroke_color.to_html(), stroke_width,
			filter_attr
		]
	if is_full_ring():
		var rings := ring_contours(Vector2(rx, ry), inner_radius_ratio, Vector2(cx, cy))
		var sub: PackedStringArray = PackedStringArray()
		for ring in rings:
			var seg: PackedStringArray = PackedStringArray()
			for i in range(ring.size()):
				seg.append(("M %.4f %.4f" if i == 0 else "L %.4f %.4f") % [ring[i].x, ring[i].y])
			sub.append(" ".join(seg) + " Z")
		return '<path d="%s" fill-rule="evenodd" fill="%s" stroke="%s" stroke-width="%.4f"%s />' % [
			" ".join(sub), fill_color.to_html(), stroke_color.to_html(), stroke_width, filter_attr
		]
	var verts: PackedVector2Array = _cached_vertices()
	if verts.is_empty():
		return ""
	var d_parts: PackedStringArray = PackedStringArray()
	for i in range(verts.size()):
		var p: Vector2 = verts[i] + Vector2(cx, cy)
		if i == 0:
			d_parts.append("M %.4f %.4f" % [p.x, p.y])
		else:
			d_parts.append("L %.4f %.4f" % [p.x, p.y])
	if shape_mode != "arc":
		d_parts.append("Z")
	var fill_str: String = "none" if shape_mode == "arc" else fill_color.to_html()
	return '<path d="%s" fill="%s" stroke="%s" stroke-width="%.4f"%s />' % [
		" ".join(d_parts), fill_str, stroke_color.to_html(), stroke_width, filter_attr
	]

func get_state() -> Dictionary:
	var s: Dictionary = super()
	s["type"] = "circle"
	s["position"] = doc_position.to_v2()
	s["rotation"] = doc_rotation
	s["size"] = get_doc_extent().to_v2()
	s["shape_mode"] = shape_mode
	s["start_angle_deg"] = start_angle_deg
	s["end_angle_deg"] = end_angle_deg
	s["inner_radius_ratio"] = inner_radius_ratio
	return s

func serialize() -> Dictionary:
	return get_state()
