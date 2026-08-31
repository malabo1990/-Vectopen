extends Node2D
## Comprobación VISUAL manual del bounding box. Cicla el zoom en bucle
## (0.2x → 1x → 4x → 12x) fijando el nombre del zoom en el título de ventana,
## para inspeccionar que los handles y la línea se ven SIEMPRE del mismo tamaño.
## No es un test gdUnit4.

const CANVAS := preload("res://scenes/canvas/canvas.tscn")
const ZOOMS := [0.2, 1.0, 4.0, 12.0]

var _cam: Camera2D
var _rect: Node2D
var _idx := 0
var _accum := 0.0

func _ready() -> void:
	var canvas: Node2D = CANVAS.instantiate()
	add_child(canvas)
	get_tree().current_scene = canvas
	await get_tree().process_frame
	await get_tree().process_frame

	var mgr := ArtboardManager.find(get_tree())
	var ab: ArtboardEditor = mgr.get_active_artboard()
	ab.global_position = Vector2.ZERO
	ab.artboard_size = Vector2(800, 600)

	_rect = VectorRectangle.new()
	_rect.name = "RectPrueba"
	_rect.size = Vector2(60, 40)
	_rect.fill_color = Color(0.9, 0.35, 0.2, 1)
	ab.add_child(_rect)
	_rect.global_position = Vector2(300, 220)
	await get_tree().process_frame

	var tool = canvas.current_tool
	if not (tool and tool.get_class_name() == "MoveTool"):
		canvas.switch_tool("move")
		await get_tree().process_frame
		tool = canvas.current_tool
	tool.selected_shapes.assign([_rect])
	tool._update_bounding_box()

	_cam = canvas.get_node("Camera2D") as Camera2D
	_apply()

func _apply() -> void:
	var z: float = ZOOMS[_idx]
	_cam.zoom = Vector2(z, z)
	_cam.global_position = _rect.global_position + _rect.size * 0.5
	DisplayServer.window_set_title("bbox check — zoom %sx" % z)
	print("[bbox_check] zoom=", z, "x")

func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 2.5:
		_accum = 0.0
		_idx = (_idx + 1) % ZOOMS.size()
		_apply()
