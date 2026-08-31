extends Node2D
## Comprobación VISUAL manual del bounding box.
##   sin args  → una figura, cicla zoom 0.2x→12x
##   --multi   → 3 figuras multiseleccionadas + rotación en vivo
## No es un test gdUnit4.

const CANVAS := preload("res://scenes/canvas/canvas.tscn")
const ZOOMS := [0.2, 1.0, 4.0, 12.0]

var _cam: Camera2D
var _rect: Node2D
var _t = null
var _multi := false
var _idx := 0
var _accum := 0.0
var _ang := 0.0

func _ready() -> void:
	_multi = "--multi" in OS.get_cmdline_user_args()
	var canvas: Node2D = CANVAS.instantiate()
	add_child(canvas)
	get_tree().current_scene = canvas
	await get_tree().process_frame
	await get_tree().process_frame

	var mgr := ArtboardManager.find(get_tree())
	var ab: ArtboardEditor = mgr.get_active_artboard()
	ab.global_position = Vector2.ZERO
	ab.artboard_size = Vector2(800, 600)

	_t = canvas.current_tool
	if not (_t and _t.get_class_name() == "MoveTool"):
		canvas.switch_tool("move"); await get_tree().process_frame
		_t = canvas.current_tool
	_cam = canvas.get_node("Camera2D") as Camera2D

	if _multi:
		var shapes := []
		for p in [Vector2(280, 200), Vector2(420, 260), Vector2(340, 360)]:
			var r := VectorRectangle.new()
			r.size = Vector2(70, 50)
			r.fill_color = Color(0.9, 0.4, 0.2)
			ab.add_child(r); r.global_position = p
			shapes.append(r)
		await get_tree().process_frame
		_t.selected_shapes.assign(shapes)
		_t._update_bounding_box()
		_cam.zoom = Vector2(1.6, 1.6)
		_cam.global_position = Vector2(360, 280)
		_t.start_handle_transform("rot_handle")
		_t.transform_initial_mouse = _t.initial_macro_center + Vector2(120, 0)
	else:
		_rect = VectorRectangle.new()
		_rect.size = Vector2(60, 40)
		_rect.fill_color = Color(0.9, 0.35, 0.2)
		ab.add_child(_rect); _rect.global_position = Vector2(300, 220)
		await get_tree().process_frame
		_t.selected_shapes.assign([_rect])
		_t._update_bounding_box()
		_aplicar_zoom()

func _aplicar_zoom() -> void:
	var z: float = ZOOMS[_idx]
	_cam.zoom = Vector2(z, z)
	_cam.global_position = _rect.global_position + _rect.size * 0.5
	print("[bbox_check] zoom=", z, "x")

func _process(delta: float) -> void:
	if _multi and _t:
		_ang += delta * 0.6
		var c: Vector2 = _t.initial_macro_center
		_t._on_motion(c + Vector2(120, 0).rotated(_ang))
		return
	_accum += delta
	if _accum >= 2.5:
		_accum = 0.0
		_idx = (_idx + 1) % ZOOMS.size()
		_aplicar_zoom()
