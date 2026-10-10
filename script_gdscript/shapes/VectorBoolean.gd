# =============================================================================
# VECTOPEN — VECTOR BOOLEAN (NO DESTRUCTIVO)
# RUTA: res://script_gdscript/shapes/VectorBoolean.gd
# Operaciones booleanas vivas y paramétricas (Union, Subtract, Intersect, Exclude)
# Conserva los objetos originales como hijos editables y evalúa la geometría al vuelo.
# Funciona como GeometryProvider para Render, Mask, Clip y Exportación SVG.
# =============================================================================
@tool
extends VectorShape
class_name VectorBoolean

const _GeomCore = preload("res://script_gdscript/shapes/VectorGeometryCore.gd")

## Operación booleana activa: "union", "subtract", "intersect", "exclude"
@export var operation: String = "union":

	set(v):
		var clean := v.to_lower().strip_edges()
		if operation != clean:
			operation = clean
			invalidate_cache()

## Caché de geometría evaluada
var _cached_polygons: Array[PackedVector2Array] = []
var _cache_dirty: bool = true
var _child_transforms: Dictionary = {} # Node -> Transform2D

func _ready() -> void:
	child_entered_tree.connect(_on_child_tree_changed)
	child_exiting_tree.connect(_on_child_tree_changed)
	child_order_changed.connect(invalidate_cache)
	set_notify_transform(true)
	_sync_children_visibility()
	invalidate_cache()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		invalidate_cache()

func _process(_delta: float) -> void:
	# Monitorear si algún hijo cambió su transform o geometría sin disparar señal
	var sources := get_source_shapes()
	for s in sources:
		var cur_xf = s.transform
		if not _child_transforms.has(s) or _child_transforms[s] != cur_xf:
			_child_transforms[s] = cur_xf
			invalidate_cache()

func _on_child_tree_changed(_child: Node) -> void:
	_sync_children_visibility()
	invalidate_cache()

## Oculta la visualización directa de los hijos para mostrar únicamente la geometría booleana compuesta
func _sync_children_visibility() -> void:
	for s in get_source_shapes():
		if s.visible:
			s.visible = false

## Invalida el caché de geometría y solicita redibujo
func invalidate_cache() -> void:
	_cache_dirty = true
	queue_redraw()

## Retorna la lista de figuras origen (hijos válidos)
func get_source_shapes() -> Array[CanvasItem]:
	var sources: Array[CanvasItem] = []
	for child in get_children():
		if is_instance_valid(child) and (child is CanvasItem):
			sources.append(child)
	return sources

## Implementación de GeometryProvider: retorna la geometría evaluada viva
func get_evaluated_geometry() -> Array[PackedVector2Array]:
	if _cache_dirty:
		_evaluate_geometry()
	return _cached_polygons

func get_effect_points() -> PackedVector2Array:
	var polys := get_evaluated_geometry()
	if polys.is_empty():
		return PackedVector2Array()
	# Retorna el polígono más grande para el cálculo de caja/efectos
	var best := polys[0]
	var max_len := best.size()
	for p in polys:
		if p.size() > max_len:
			max_len = p.size()
			best = p
	return best

func _evaluate_geometry() -> void:
	var sources := get_source_shapes()
	if sources.is_empty():
		_cached_polygons = []
		_cache_dirty = false
		return

	# Evalúa el booleano en el espacio local de este VectorBoolean
	_cached_polygons = _GeomCore.compute_multi_boolean(operation, sources, global_transform.affine_inverse())
	_cache_dirty = false

func _draw() -> void:
	var polys := get_evaluated_geometry()
	if polys.is_empty():
		return

	for poly in polys:
		if poly.size() < 3:
			continue

		draw_effects_shadows(poly)

		# Relleno de la figura evaluada (sólido o degradado)
		draw_fill(poly)

		# Borde
		if stroke_width > 0.0:
			var ring := PackedVector2Array(poly)
			ring.append(poly[0])
			var sp := _get_rendered_stroke_params()
			draw_polyline(ring, sp[1], sp[0], false)

		draw_effects_overlays(poly)

## Exportación SVG con la geometría evaluada real
func to_svg() -> String:
	var polys := get_evaluated_geometry()
	if polys.is_empty():
		return ""
	var d_str := ""
	for poly in polys:
		if poly.size() < 3: continue
		d_str += "M %.2f %.2f " % [poly[0].x, poly[0].y]
		for i in range(1, poly.size()):
			d_str += "L %.2f %.2f " % [poly[i].x, poly[i].y]
		d_str += "Z "

	var col_hex := "#%02x%02x%02x" % [int(fill_color.r * 255), int(fill_color.g * 255), int(fill_color.b * 255)]
	var strk_hex := "#%02x%02x%02x" % [int(stroke_color.r * 255), int(stroke_color.g * 255), int(stroke_color.b * 255)]
	return '<path d="%s" fill="%s" stroke="%s" stroke-width="%.1f"%s />' % [
		d_str.strip_edges(), col_hex, strk_hex, stroke_width, get_svg_filter_attr()
	]

## Serialización para guardar/cargar proyecto
func get_state() -> Dictionary:
	var st := {
		"type": "VectorBoolean",
		"operation": operation,
		"fill_color": fill_color.to_html(true),
		"stroke_color": stroke_color.to_html(true),
		"stroke_width": stroke_width,
		"effects": effects.duplicate(true),
		"children": []
	}
	for child in get_source_shapes():
		if child.has_method("get_state"):
			st["children"].append(child.get_state())
	return st
