extends GdUnitTestSuite

func test_zoom_mantiene_punto_bajo_cursor() -> void:
	var canvas: Node2D = Node2D.new()
	canvas.set_script(load("res://scripts/canvas/canvas.gd"))
	var cam := Camera2D.new()
	cam.position = Vector2(300, 200)
	cam.zoom = Vector2.ONE
	canvas.set("camera", cam)
	canvas.set("zoom_min", 0.05)
	canvas.set("zoom_max", 20.0)
	add_child(cam)
	add_child(canvas)
	await get_tree().process_frame

	var viewport_size: Vector2 = canvas.get_viewport_rect().size
	var center: Vector2 = viewport_size / 2.0
	var cursor_screen := Vector2(600, 420)
	var world_before: Vector2 = cam.position + (cursor_screen - center) / cam.zoom.x

	canvas.zoom_at_point(1.5, world_before)

	var world_after: Vector2 = cam.position + (cursor_screen - center) / cam.zoom.x
	assert_that(world_after.distance_to(world_before)).is_less(0.01)

	canvas.zoom_at_point(0.7, world_before)
	var world_after2: Vector2 = cam.position + (cursor_screen - center) / cam.zoom.x
	assert_that(world_after2.distance_to(world_before)).is_less(0.01)
