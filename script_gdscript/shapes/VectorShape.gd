@tool
extends Node2D
class_name VectorShape

@export var object_id: String = ""
@export var fill_color: Color = Color.WHITE
@export var stroke_color: Color = Color.BLACK
@export var stroke_width: float = 2.0

var is_selected: bool = false
var effects: Array = []

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
