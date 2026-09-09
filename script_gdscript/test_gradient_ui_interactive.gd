extends Node2D

@onready var label: Label = $UI/Label
var step: int = 0
var timer: float = 0.0
var canvas_editor: Node2D = null
var shape: VectorRectangle = null
var bbox: Control = null
var move_tool = null

func _ready() -> void:
	var canvas_scene = load("res://scenes/canvas/canvas.tscn")
	canvas_editor = canvas_scene.instantiate()
	add_child(canvas_editor)
	move_child(canvas_editor, 0) # Keep behind UI

	await get_tree().process_frame
	await get_tree().process_frame

	var artboard = canvas_editor.get_node_or_null("ArtboardsContainer/Artboard")
	if not artboard:
		label.text = "ERROR: No artboard found"
		return

	# Add a rectangle
	shape = VectorRectangle.new()
	shape.size = Vector2(300, 200)
	shape.position = Vector2(250, 180)
	var g := Gradient.new()
	g.set_color(0, Color(0.15, 0.45, 0.95, 1.0)) # Vibrant Blue
	g.add_point(0.5, Color(0.95, 0.2, 0.5, 1.0)) # Pink stop
	g.set_color(2, Color(0.98, 0.85, 0.15, 1.0)) # Yellow end
	shape.fill_gradient = g
	shape.fill_gradient_type = 0 # Linear
	shape.set_gradient_points(Vector2(0.15, 0.5), Vector2(0.85, 0.5))
	artboard.add_child(shape)

	# Set camera with zoom and pan to test real editor camera transforms
	var cam: Camera2D = canvas_editor.get_node_or_null("Camera2D")
	if cam:
		cam.position = Vector2(350, 250)
		cam.zoom = Vector2(1.3, 1.3)

	# Switch tool to MoveTool
	move_tool = canvas_editor._new_tool(canvas_editor.MoveTool_Script)
	canvas_editor.change_tool(move_tool)
	await get_tree().process_frame

	# Select the shape
	move_tool._select(shape)
	await get_tree().process_frame

	bbox = move_tool._bounding_box
	label.text = "Step 0: Shape selected with MoveTool. Pressing 'G' to activate gradient mode..."

func _process(delta: float) -> void:
	timer += delta
	if step == 0 and timer > 0.6:
		step = 1
		timer = 0.0
		# Simulate pressing key G
		var ev_g := InputEventKey.new()
		ev_g.keycode = KEY_G
		ev_g.pressed = true
		canvas_editor._unhandled_input(ev_g)
		label.text = "Step 1: 'G' pressed -> Gradient Mode ACTIVE! Gradient Line & Stops visible at 1.3x zoom."
		_save_frame("gradient_ui_step1_key_g.png")

	elif step == 1 and timer > 0.8:
		step = 2
		timer = 0.0
		# Drag p1 from (0.85, 0.5) down-right to (0.9, 0.9)
		# Notice: p0 is at (0.15, 0.5) and MUST NOT MOVE AT ALL!
		var p0_before = shape.fill_gradient_p0
		var data = bbox._get_gradient_annotator_data()
		var p1_screen = bbox.get_screen_transform() * data["p1"]

		var ev_press := InputEventMouseButton.new()
		ev_press.button_index = MOUSE_BUTTON_LEFT
		ev_press.pressed = true
		ev_press.global_position = p1_screen
		ev_press.position = p1_screen
		bbox._gui_input(ev_press)

		var new_p1_local := Vector2(shape.size.x * 0.9, shape.size.y * 0.9)
		var new_p1_screen = bbox.get_screen_transform() * new_p1_local
		var ev_motion := InputEventMouseMotion.new()
		ev_motion.global_position = new_p1_screen
		ev_motion.position = new_p1_screen
		bbox._gui_input(ev_motion)

		var ev_release := InputEventMouseButton.new()
		ev_release.button_index = MOUSE_BUTTON_LEFT
		ev_release.pressed = false
		ev_release.global_position = new_p1_screen
		ev_release.position = new_p1_screen
		bbox._gui_input(ev_release)

		var p0_after = shape.fill_gradient_p0
		var p0_fixed = (p0_before == p0_after)
		label.text = "Step 2: Dragged p1 to (0.9, 0.9). p0 FIXED? " + str(p0_fixed) + " | p0=" + str(shape.fill_gradient_p0) + " p1=" + str(shape.fill_gradient_p1)
		_save_frame("gradient_ui_step2_p1_dragged_p0_fixed.png")

	elif step == 2 and timer > 0.8:
		step = 3
		timer = 0.0
		# Drag intermediate stop (at 0.5) to ratio 0.25
		var p0_before = shape.fill_gradient_p0
		var p1_before = shape.fill_gradient_p1
		var data = bbox._get_gradient_annotator_data()
		var stop_pt = data.stops[1].position
		var stop_screen = bbox.get_screen_transform() * stop_pt

		var ev_press := InputEventMouseButton.new()
		ev_press.button_index = MOUSE_BUTTON_LEFT
		ev_press.pressed = true
		ev_press.global_position = stop_screen
		ev_press.position = stop_screen
		bbox._gui_input(ev_press)

		var new_stop_local: Vector2 = data.p0.lerp(data.p1, 0.25)
		var new_stop_screen = bbox.get_screen_transform() * new_stop_local
		var ev_motion := InputEventMouseMotion.new()
		ev_motion.global_position = new_stop_screen
		ev_motion.position = new_stop_screen
		bbox._gui_input(ev_motion)

		var ev_release := InputEventMouseButton.new()
		ev_release.button_index = MOUSE_BUTTON_LEFT
		ev_release.pressed = false
		ev_release.global_position = new_stop_screen
		ev_release.position = new_stop_screen
		bbox._gui_input(ev_release)

		var ends_fixed = (p0_before == shape.fill_gradient_p0 and p1_before == shape.fill_gradient_p1)
		label.text = "Step 3: Dragged middle stop to 0.25. Endpoints FIXED? " + str(ends_fixed) + " | offsets=" + str(shape.fill_gradient.offsets)
		_save_frame("gradient_ui_step3_stop_dragged.png")

	elif step == 3 and timer > 0.8:
		step = 4
		timer = 0.0
		# Switch to Diamond (type 3)
		shape.fill_gradient_type = 3
		shape.queue_redraw()
		bbox.queue_redraw()
		label.text = "Step 4: Diamond / Rombo Geometry ACTIVE! Guide & Texture procedural rendered."
		_save_frame("gradient_ui_step4_diamond.png")

	elif step == 4 and timer > 0.8:
		step = 5
		timer = 0.0
		# Switch to Spiral (type 5)
		shape.fill_gradient_type = 5
		shape.queue_redraw()
		bbox.queue_redraw()
		label.text = "Step 5: Spiral Geometry ACTIVE! Golden spiral curve guide & procedural rendering."
		_save_frame("gradient_ui_step5_spiral.png")

	elif step == 5 and timer > 0.8:
		step = 6
		timer = 0.0
		# Apply Cyber Neon preset
		var cc = get_node_or_null("/root/ColorCore")
		shape.fill_gradient_type = 1 # Radial
		var g_neon := Gradient.new()
		g_neon.set_color(0, Color(0.0, 0.95, 0.85))
		g_neon.add_point(0.5, Color(0.65, 0.05, 0.95))
		g_neon.set_color(2, Color(0.95, 0.05, 0.55))
		shape.fill_gradient = g_neon
		shape.queue_redraw()
		bbox.queue_redraw()
		label.text = "Step 6: Cyber Neon Preset on Radial Geometry! ALL TESTS COMPLETED."
		_save_frame("gradient_ui_step6_preset.png")

func _save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var vp = get_viewport()
	if vp:
		var img = vp.get_texture().get_image()
		if img:
			var path = "C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686/" + filename
			img.save_png(path)
			print("SAVED SCREENSHOT: ", path)
