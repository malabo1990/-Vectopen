@tool
extends VectorShape
class_name VectorCircle

@export var size: Vector2 = Vector2(100, 100)

const CIRCLE_QUALITY: int = 128

## Caché de vértices: _generate_vertices() hace 128 cos/sin; regenerarlo en cada
## _draw (y encima 2 veces) es puro desperdicio cuando el tamaño no cambia.
var _verts_cache: PackedVector2Array = PackedVector2Array()
var _verts_cache_size: Vector2 = Vector2(-1, -1)

func _init() -> void:
	_register_doc_extent("size")

func get_effect_points() -> PackedVector2Array:
	return _cached_vertices()

func _draw() -> void:
	if fill_color.a <= 0 and stroke_width <= 0 and not has_gradient_fill() and effects.is_empty():
		return
	var verts := _cached_vertices()
	draw_effects_shadows(verts)
	draw_fill(verts)
	if stroke_width > 0:
		var ring_verts := verts
		if stroke_align == 1: # Inside
			var s_size := Vector2(maxf(0.0, size.x - stroke_width), maxf(0.0, size.y - stroke_width))
			ring_verts = _generate_vertices_for_size(s_size)
		elif stroke_align == 2: # Outside
			var s_size := size + Vector2(stroke_width, stroke_width)
			ring_verts = _generate_vertices_for_size(s_size)
		draw_stroke_ring(ring_verts)
	draw_effects_overlays(verts)

func _cached_vertices() -> PackedVector2Array:
	if _verts_cache.is_empty() or _verts_cache_size != size:
		_verts_cache = _generate_vertices()
		_verts_cache_size = size
	return _verts_cache

## Vértices centrados en el origen local (-size/2 .. +size/2), igual que
## VectorRectangle. "position" es el CENTRO de la figura en ambas clases —
## antes este método sumaba "half" a cada vértice, tratando position como
## esquina superior-izquierda, lo que desalineaba el círculo respecto al
## bounding box (que sí asume position = centro, ver MoveTool._global_rect()).
func _generate_vertices() -> PackedVector2Array:
	return _generate_vertices_for_size(size)

func _generate_vertices_for_size(target_size: Vector2) -> PackedVector2Array:
	var verts := PackedVector2Array()
	var half := target_size / 2.0
	for i in range(CIRCLE_QUALITY):
		var angle := (i * 2.0 * PI) / CIRCLE_QUALITY
		verts.append(Vector2(cos(angle) * half.x, sin(angle) * half.y))
	return verts

func to_svg() -> String:
	var extent: DVec2 = get_doc_extent()
	var cx: float = doc_position.x
	var cy: float = doc_position.y
	var rx: float = extent.x / 2.0
	var ry: float = extent.y / 2.0
	var filter_attr: String = get_svg_filter_attr()
	return '<ellipse cx="%.4f" cy="%.4f" rx="%.4f" ry="%.4f" fill="%s" stroke="%s" stroke-width="%.4f"%s />' % [
		cx, cy, rx, ry,
		fill_color.to_html(), stroke_color.to_html(), stroke_width,
		filter_attr
	]

func get_state() -> Dictionary:
	var s := super()
	s["type"] = "circle"
	s["position"] = doc_position.to_v2()
	s["rotation"] = doc_rotation
	s["size"] = get_doc_extent().to_v2()
	return s

func serialize() -> Dictionary:
	return get_state()
