class_name StarTool
extends ToolBase

@export var points_count: int = 5
@export var inner_radius_ratio: float = 0.382
@export var corner_radius: float = 0.0

func activate() -> void:
	super()
	print("\n[StarTool]: Herramienta ACTIVADA (Paramétrica).")

func deactivate() -> void:
	print("[StarTool]: Herramienta DESACTIVADA.")
	super()

func handle_input(event: InputEvent) -> bool:
	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false

	if not canvas or not artboard:
		_refresh_dependencies()
	if not canvas or not artboard:
		return false

	var gm: Vector2 = canvas.get_global_mouse_position()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_drawing = true
			box_start_global = gm
			box_current_global = gm
			canvas.queue_redraw()
			return true
		else:
			if is_drawing:
				is_drawing = false
				_finalize_star()
				canvas.queue_redraw()
				return true

	if event is InputEventMouseMotion and is_drawing:
		box_current_global = gm
		canvas.queue_redraw()
		return true

	return false

func create_at_center() -> void:
	create_star_at_center()

func create_star_at_center() -> void:
	if not artboard:
		_refresh_dependencies()
	if not artboard:
		return

	var default_radius: float = 60.0
	var ab_size: Vector2 = Vector2(800, 600)
	if "artboard_size" in artboard:
		ab_size = artboard.artboard_size

	var local_center: Vector2 = ab_size / 2.0
	_spawn_shape(local_center, default_radius, 0.0)

func _calculate_geometry() -> Dictionary:
	var start: Vector2 = box_start_global
	var current: Vector2 = box_current_global
	var delta: Vector2 = current - start

	var center: Vector2 = start
	var radius_out: float = start.distance_to(current)
	var rotation_angle: float = delta.angle()

	if Input.is_key_pressed(KEY_SHIFT):
		rotation_angle = 0.0

	return {"center": center, "radius_out": radius_out, "rotation": rotation_angle}

func _finalize_star() -> void:
	var geom: Dictionary = _calculate_geometry()
	var final_radius: float = float(geom["radius_out"])
	var final_center_global: Vector2 = geom["center"]
	var final_rotation: float = float(geom["rotation"])

	if final_radius > 3.0:
		_retarget_artboard_at(final_center_global)
		var local_center: Vector2 = artboard.to_local(final_center_global)
		_spawn_shape(local_center, final_radius, final_rotation)

func _spawn_shape(local_center: Vector2, radius_out: float, rotation_angle: float) -> void:
	if not artboard:
		return

	var new_shape := VectorStar.new()
	new_shape.name = NameUtils.unique_child_name(artboard, "Estrella")
	new_shape.points_count = points_count
	new_shape.inner_radius_ratio = inner_radius_ratio
	new_shape.corner_radius = corner_radius
	new_shape.size = Vector2(radius_out * 2.0, radius_out * 2.0)
	new_shape.rotation = rotation_angle
	new_shape.set_doc_position(DVec2.from_v2(local_center))
	new_shape.set_doc_extent(DVec2.from_v2(Vector2(radius_out * 2.0, radius_out * 2.0)))
	new_shape.fill_color = FILL_COLOR
	new_shape.stroke_color = STROKE_COLOR
	new_shape.stroke_width = STROKE_WIDTH

	artboard.add_child(new_shape)
	new_shape.owner = artboard

func draw_preview(c: Node2D) -> void:
	if not is_drawing or not is_instance_valid(c):
		return

	var geom: Dictionary = _calculate_geometry()
	var local_center: Vector2 = c.to_local(geom["center"])
	var r_out: float = float(geom["radius_out"])
	var rot: float = float(geom["rotation"])

	var total_pts: int = points_count * 2
	var points_preview: PackedVector2Array = PackedVector2Array()
	var r_in: float = r_out * inner_radius_ratio

	for i in range(total_pts):
		var angle: float = i * (TAU / float(total_pts)) - (PI / 2.0) + rot
		var cur_r: float = r_out if (i % 2 == 0) else r_in
		points_preview.append(local_center + Vector2(cos(angle), sin(angle)) * cur_r)

	if points_preview.size() >= 3:
		c.draw_colored_polygon(points_preview, COLOR_PREVIEW_F)
		var stroke_preview: PackedVector2Array = points_preview
		stroke_preview.append(points_preview[0])
		var current_scale: float = c.global_transform.get_scale().x
		if current_scale <= 0.001: current_scale = 1.0
		var line_width: float = clampf(1.2 / current_scale, 0.6, 3.0)
		c.draw_polyline(stroke_preview, COLOR_PREVIEW_S, line_width, true)
