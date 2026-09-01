@tool
extends Node2D
class_name VectorShape

@export var object_id: String = ""
@export var fill_color: Color = Color.WHITE
@export var stroke_color: Color = Color.BLACK
@export var stroke_width: float = 2.0

## ── Relleno con degradado (opcional) ──────────────────────────────────────
## Si `fill_gradient` tiene >= 2 puntos, el relleno se dibuja como degradado
## (lineal o radial) en vez del `fill_color` plano. Todas las figuras dibujan
## su relleno con `draw_fill(points)`, así que el degradado funciona en
## rectángulo, círculo, polígono y cualquier figura nueva sin tocarlas.
@export var fill_gradient: Gradient = null:
	set(v):
		if fill_gradient and fill_gradient.changed.is_connected(_on_fill_gradient_changed):
			fill_gradient.changed.disconnect(_on_fill_gradient_changed)
		fill_gradient = v
		if fill_gradient and not fill_gradient.changed.is_connected(_on_fill_gradient_changed):
			fill_gradient.changed.connect(_on_fill_gradient_changed)
		_grad_tex = null
		queue_redraw()
## 0 = lineal, 1 = radial.
@export var fill_gradient_type: int = 0:
	set(v):
		fill_gradient_type = v
		_grad_tex = null
		queue_redraw()
## Ángulo del degradado lineal, en radianes (0 = izquierda→derecha).
@export var fill_gradient_angle: float = 0.0:
	set(v):
		fill_gradient_angle = v
		queue_redraw()

var _grad_tex: GradientTexture2D = null

var is_selected: bool = false
var effects: Array = []

func _on_fill_gradient_changed() -> void:
	_grad_tex = null
	queue_redraw()

func has_gradient_fill() -> bool:
	return fill_gradient != null and fill_gradient.get_point_count() >= 2

func clear_fill_gradient() -> void:
	fill_gradient = null

## Dibuja el relleno del polígono dado: degradado si hay `fill_gradient`,
## si no el `fill_color` plano. Las subclases lo llaman desde su `_draw()`.
func draw_fill(points: PackedVector2Array) -> void:
	if points.size() < 3:
		return
	if has_gradient_fill():
		draw_colored_polygon(points, Color.WHITE, _gradient_uvs(points), _ensure_grad_tex())
	elif fill_color.a > 0.0:
		draw_colored_polygon(points, fill_color)

func _ensure_grad_tex() -> GradientTexture2D:
	if _grad_tex == null and fill_gradient:
		_grad_tex = GradientTexture2D.new()
		_grad_tex.gradient = fill_gradient
		if fill_gradient_type == 1:
			_grad_tex.width = 128
			_grad_tex.height = 128
			_grad_tex.fill = GradientTexture2D.FILL_RADIAL
			_grad_tex.fill_from = Vector2(0.5, 0.5)
			_grad_tex.fill_to = Vector2(1.0, 0.5)
		else:
			_grad_tex.width = 256
			_grad_tex.height = 1
			_grad_tex.fill = GradientTexture2D.FILL_LINEAR
			_grad_tex.fill_from = Vector2(0.0, 0.0)
			_grad_tex.fill_to = Vector2(1.0, 0.0)
	return _grad_tex

func _gradient_uvs(points: PackedVector2Array) -> PackedVector2Array:
	var bb := _points_bounds(points)
	var uvs := PackedVector2Array()
	if fill_gradient_type == 1:
		var c := bb.get_center()
		var sx := maxf(bb.size.x, 0.001)
		var sy := maxf(bb.size.y, 0.001)
		for p in points:
			uvs.append(Vector2(0.5 + (p.x - c.x) / sx, 0.5 + (p.y - c.y) / sy))
	else:
		var dir := Vector2(cos(fill_gradient_angle), sin(fill_gradient_angle))
		var projs := PackedFloat32Array()
		var pmin := INF
		var pmax := -INF
		for p in points:
			var pr: float = (p - bb.position).dot(dir)
			projs.append(pr)
			pmin = minf(pmin, pr)
			pmax = maxf(pmax, pr)
		var span := maxf(pmax - pmin, 0.001)
		for pr in projs:
			uvs.append(Vector2((pr - pmin) / span, 0.0))
	return uvs

func _points_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var r := Rect2(points[0], Vector2.ZERO)
	for i in range(1, points.size()):
		r = r.expand(points[i])
	return r

## ── Coordenadas de documento en doble precisión (64 bits) ──────────────────
## Fuente de verdad para posición/rotación/tamaño/vértices. Los campos nativos
## de Node2D (position/rotation) y los @export de las subclases (size/vertices)
## quedan como una CACHÉ DE RENDERIZADO de una sola vía: doc-space -> nativo,
## nunca al revés (salvo la sincronización inicial en _ready(), que solo aplica
## si nadie llamó set_doc_*() todavía, p.ej. al cargar una escena guardada).
##
## Una figura NUEVA obtiene esto gratis con solo:
##   1) llamar _register_doc_extent("size", ...) y/o _register_doc_vertices("vertices")
##      una vez en su _init(), y
##   2) usar set_doc_position()/set_doc_extent()/set_doc_vertices() en vez de
##      asignar .position/.size/.vertices directamente.
## MoveTool despacha genéricamente por "shape is VectorShape" + has_doc_extent()/
## has_doc_vertices(), así que no hace falta tocar MoveTool.gd para una figura nueva.
var doc_position: DVec2 = DVec2.new()
var doc_rotation: float = 0.0

var _doc_extent: DVec2 = null
var _doc_extent_field: String = ""
var _doc_vertices: Array[DVec2] = []
var _doc_vertices_field: String = ""

var _doc_position_set: bool = false
var _doc_rotation_set: bool = false
var _doc_extent_set: bool = false
var _doc_vertices_set: bool = false

func _ready() -> void:
	# Sincronización inicial única: si nadie llamó set_doc_*() antes de _ready()
	# (p.ej. esta figura viene de una escena .tscn cargada del disco), doc-space
	# se rellena desde los valores nativos ya cargados. Si una herramienta de
	# creación ya llamó set_doc_*() antes de que el nodo entrara al árbol, esa
	# precisión explícita se respeta y NO se sobreescribe aquí.
	if not _doc_position_set:
		doc_position = DVec2.from_v2(position)
	if not _doc_rotation_set:
		doc_rotation = rotation
	if has_doc_extent() and not _doc_extent_set:
		_doc_extent = DVec2.from_v2(get(_doc_extent_field))
	if has_doc_vertices() and not _doc_vertices_set:
		_doc_vertices = DVec2.array_from_v2(get(_doc_vertices_field))

func get_doc_position() -> DVec2:
	return doc_position

func set_doc_position(p: DVec2) -> void:
	doc_position = p
	_doc_position_set = true
	position = p.to_v2()
	queue_redraw()

func get_doc_rotation() -> float:
	return doc_rotation

func set_doc_rotation(r: float) -> void:
	doc_rotation = r
	_doc_rotation_set = true
	rotation = r
	queue_redraw()

func _register_doc_extent(native_field: String) -> void:
	_doc_extent_field = native_field
	_doc_extent = DVec2.new()

func has_doc_extent() -> bool:
	return _doc_extent_field != ""

func get_doc_extent() -> DVec2:
	return _doc_extent

func set_doc_extent(e: DVec2) -> void:
	_doc_extent = e
	_doc_extent_set = true
	if _doc_extent_field != "":
		set(_doc_extent_field, e.to_v2())
	queue_redraw()

func _register_doc_vertices(native_field: String) -> void:
	_doc_vertices_field = native_field

func has_doc_vertices() -> bool:
	return _doc_vertices_field != ""

func get_doc_vertices() -> Array[DVec2]:
	return _doc_vertices

func set_doc_vertices(v: Array[DVec2]) -> void:
	_doc_vertices = v
	_doc_vertices_set = true
	if _doc_vertices_field != "":
		var packed := PackedVector2Array()
		for dv in v:
			packed.append(dv.to_v2())
		set(_doc_vertices_field, packed)
	queue_redraw()

func set_selected(selected: bool) -> void:
	is_selected = selected
	if selected:
		modulate = Color(1.2, 1.2, 1.2, 1.0)
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)
	queue_redraw()

func get_state() -> Dictionary:
	return {
		"id": object_id,
		"position": position,
		"rotation": rotation,
		"scale": scale,
		"fill_color": fill_color,
		"stroke_color": stroke_color,
		"stroke_width": stroke_width,
	}

func serialize() -> Dictionary:
	return get_state()

func to_svg() -> String:
	return ""

func _draw() -> void:
	pass
