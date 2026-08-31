class_name ToolBase
extends Node

@export var shape_manager: Node
@export var artboard: Node

var canvas: Node2D = null
var box_start_global: Vector2 = Vector2.ZERO
var box_current_global: Vector2 = Vector2.ZERO
var is_drawing: bool = false

const STROKE_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)
const STROKE_WIDTH: float = 1.0
const FILL_COLOR: Color = Color(0.88, 0.88, 0.88, 1.0)
const COLOR_PREVIEW_F: Color = Color(0.05, 0.55, 0.91, 0.05)
const COLOR_PREVIEW_S: Color = Color(0.05, 0.55, 0.91, 0.85)

func activate() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	_refresh_dependencies()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func deactivate() -> void:
	is_drawing = false
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func handle_input(_event: InputEvent) -> bool:
	return false

func draw_preview(_c: Node2D) -> void:
	pass

func get_class_name() -> String:
	return ""

func _refresh_dependencies() -> void:
	if not is_instance_valid(canvas):
		var parent_node = get_parent()
		if parent_node is Node2D:
			canvas = parent_node
		elif get_tree():
			canvas = get_tree().get_first_node_in_group("_vectopen_canvas")

	if is_instance_valid(canvas):
		# `artboard` = artboard ACTIVO (destino de figuras nuevas sin punto).
		# Se re-resuelve siempre: si el usuario cambió de artboard, apunta al
		# nuevo. Antes se cacheaba container.get_child(0) para siempre → todas
		# las figuras caían en el artboard 0.
		var mgr := _artboard_manager()
		if mgr:
			artboard = mgr.get_active_artboard()
		if not is_instance_valid(artboard):
			var container = canvas.get_node_or_null("ArtboardsContainer")
			if container and container.get_child_count() > 0:
				artboard = container.get_child(0)

		if not is_instance_valid(shape_manager):
			shape_manager = canvas.get_node_or_null("ShapeManager")

## ArtboardManager vivo (autoridad multi-artboard). null si no está en escena.
func _artboard_manager() -> ArtboardManager:
	if not get_tree():
		return null
	return ArtboardManager.find(get_tree())

## Fija `self.artboard` al artboard que contiene `world_point` (multi-artboard).
## Llamar al principio de _finalize_*() antes de convertir a coords locales.
func _retarget_artboard_at(world_point: Vector2) -> void:
	var t := _artboard_for_point(world_point)
	if is_instance_valid(t):
		artboard = t

## Artboard destino para una figura creada EN un punto del mundo:
## el que contiene el punto; si el punto cae fuera de todos, el activo (así
## la herramienta sigue siendo usable dibujando "al lado").
func _artboard_for_point(world_point: Vector2) -> Node:
	var mgr := _artboard_manager()
	if mgr:
		var hit := mgr.artboard_at_point(world_point)
		if is_instance_valid(hit):
			return hit
		var act := mgr.get_active_artboard()
		if is_instance_valid(act):
			return act
	_refresh_dependencies()
	return artboard
