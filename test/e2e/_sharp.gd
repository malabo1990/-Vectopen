extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
## anchura (px) de la transición 10→90 % en la fila central de un borde vertical
func _edge_w(img: Image) -> float:
	var y := img.get_height() / 2
	var best := 999.0
	var prev := 1.0
	var x0 := -1
	for x in img.get_width():
		var l := img.get_pixel(x, y).r
		if x0 < 0 and l < 0.9 and prev >= 0.9:
			x0 = x
		if x0 >= 0 and l <= 0.1:
			best = minf(best, float(x - x0))
			x0 = -1
		if l > 0.9:
			x0 = -1
		prev = l
	return best
func _run() -> void:
	for i in 3: await process_frame
	var ff: FontFile = load("res://assets/fonts/Inter-Regular.ttf")
	var nomsdf: FontFile = ff.duplicate()
	nomsdf.multichannel_signed_distance_field = false
	var bg := ColorRect.new(); bg.color = Color.WHITE; bg.size = Vector2(100000, 100000); bg.position = -bg.size / 2
	root.add_child(bg)
	var cam := Camera2D.new(); root.add_child(cam); cam.make_current()
	for f in [ff, nomsdf]:
		var n := Node2D.new(); root.add_child(n)
		n.draw.connect(func() -> void: n.draw_string(f, Vector2(-6, 8), "I", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.BLACK))
		for z in [1.0, 4.0, 16.0]:
			cam.zoom = Vector2(z, z)
			cam.position = Vector2(0, 0)
			n.queue_redraw()
			for i in 4: await process_frame
			var img := root.get_texture().get_image()
			print("NIT msdf=%s zoom=%.0f  ancho del borde = %.0f px" % [f.multichannel_signed_distance_field, z, _edge_w(img)])
		n.queue_free()
		await process_frame
	print("NIT oversampling viewport=", root.get("oversampling"), " props:", ", ".join(PackedStringArray(root.get_property_list().map(func(p): return p["name"]).filter(func(s): return String(s).contains("oversampl")))))
	quit()
