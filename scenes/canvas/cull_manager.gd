# ==========================================
# RUTA: res://scenes/canvas/cull_manager.gd
# Gestor de contenidos masivos: CULLING GLOBAL por visibilidad.
#
# Con 10.000+ textos/objetos, cada nodo con _process/_draw consí umu fuerza
# de trabajo aunque esté fuera de pantalla (Godot dibuja todo lo visible=true).
# Este manager, 1 vez por frame:
#  1. Calcula el rect visible de la cámara (world).
#  2. Marca visible=true/process=true SOLO los objetos dentro (margen).
#  3. Los demás: visible=false + process=false -> ni _draw ni _process
#     (O(1) por frame; el costo por objeto es solo 1 chequeo de rect).
#
# Uso: instanciar dentro de CanvasRoot, con la referencia al Camera2D.
# Los objetos candidatos se registran vía el grupo "world_content".
#
# LOD sub-pixel: los nodos también en el grupo "cull_subpixel" (p.ej. los
# WorldTextLabel) se apagan cuando su huella EN PANTALLA cae por debajo de
# min_screen_px — a ese zoom el texto es ilegible y dibujar 10.000 labels
# minúsculos a la vez costaba ~20 FPS. Con esto, alejar el zoom del todo
# vuelve a ir a 60 FPS (igual que Inkscape, que deja de pintar texto pequeño).
# ==========================================
extends Node
class_name CullManager

@export var camera: Camera2D
@export var cull_margin: float = 600.0
@export var enabled: bool = true
## Huella mínima en píxeles de pantalla para nodos del grupo "cull_subpixel".
@export var min_screen_px: float = 4.0

## STREAMING de artboards: dormir/despertar por proximidad al viewport.
## wake < sleep → histéresis (no oscila en el borde). En unidades de mundo.
@export var stream_artboards: bool = true
@export var wake_margin: float = 1200.0
@export var sleep_margin: float = 3500.0

## Cada cuánto frames se re-escanean (el zoom/pan no cambia cada frame).
const SCAN_INTERVAL := 2

var _tick := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if not enabled or camera == null:
		return
	_tick += 1
	if _tick % SCAN_INTERVAL != 0:
		return
	var cam_zoom: Vector2 = camera.zoom
	if cam_zoom.x <= 0.0 or cam_zoom.y <= 0.0:
		cam_zoom = Vector2.ONE
	var vp_size: Vector2 = camera.get_viewport_rect().size
	var world_size: Vector2 = vp_size / cam_zoom
	var half: Vector2 = world_size * 0.5
	var raw_view := Rect2(camera.get_screen_center_position() - half, world_size)
	var view_rect := raw_view.grow(cull_margin)
	var zoom_scalar: float = minf(cam_zoom.x, cam_zoom.y)

	if stream_artboards:
		_stream_artboards(raw_view)

	for node in get_tree().get_nodes_in_group("world_content"):
		if not is_instance_valid(node):
			continue
		var canvas := node as CanvasItem
		if canvas == null:
			continue
		var visible_now: bool = _overlaps(canvas, view_rect, zoom_scalar)
		if canvas.visible != visible_now:
			canvas.visible = visible_now
		# process solo si visible (los _process de world_content labels rastrean zoom)
		var should_process := visible_now
		if canvas.is_processing() != should_process:
			canvas.set_process(should_process)

## Despierta los artboards cuyo rect toca el viewport + wake_margin; duerme los
## que quedan fuera del viewport + sleep_margin (nunca el activo).
func _stream_artboards(raw_view: Rect2) -> void:
	var mgr := ArtboardManager.find(get_tree())
	if mgr == null:
		return
	var wake_rect := raw_view.grow(wake_margin)
	var sleep_rect := raw_view.grow(sleep_margin)
	var active := mgr.active_artboard
	# Mientras haya historial de undo, no dormir las páginas recientes: sus
	# nodos están referenciados por los callables de HistoryManager.
	var proteger: Array = mgr.recent if _hay_undo() else []
	# Presupuesto por escaneo: varios wakes (que el usuario vea contenido
	# pronto), 1 sleep (liberar no corre prisa). El resto en frames siguientes.
	var wakes_left := 3
	var slept := false
	for ab in mgr.all_artboards():
		if not is_instance_valid(ab):
			continue
		var r: Rect2 = ab.world_rect()
		if wake_rect.intersects(r):
			if ab.is_dormant and wakes_left > 0:
				ab.wake()
				wakes_left -= 1
		elif not sleep_rect.intersects(r) and ab != active and not (ab in proteger):
			if not ab.is_dormant and not slept:
				ab.sleep()
				slept = true


func _hay_undo() -> bool:
	var h := get_node_or_null("/root/HistoryManager")
	return h != null and h.has_method("can_undo") and h.can_undo()


func _overlaps(canvas: CanvasItem, view_rect: Rect2, zoom_scalar: float) -> bool:
	# Rect del nodo en coords de mundo: usamos global_transform + size si es
	# un Control, o un punto si es Node2D sin bounds.
	var node := canvas as Control
	if node:
		var gpos: Vector2 = node.get_global_position()
		var gscale: Vector2 = node.get_global_transform().get_scale()
		var wsize: Vector2 = node.size * gscale
		if not view_rect.intersects(Rect2(gpos, wsize)):
			return false
		# LOD sub-pixel: a este zoom el nodo es un borrón ilegible → no dibujar.
		if zoom_scalar > 0.0 and node.is_in_group("cull_subpixel"):
			if minf(wsize.x, wsize.y) * zoom_scalar < min_screen_px:
				return false
		return true
	var n2d := canvas as Node2D
	if n2d:
		return view_rect.has_point(n2d.to_global(Vector2.ZERO))
	return true
