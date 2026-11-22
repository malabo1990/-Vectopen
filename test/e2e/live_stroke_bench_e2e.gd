## VGSE fase 6: coste de DIBUJAR un trazo largo en vivo con la herramienta
## Pincel real. Clic real y luego muestras a 1 px (trazo lento con tableta):
## puntos del Line2D, ms de la vista previa por muestra y ms de redibujar
## (StrokeRender) a 1 000 / 5 000 / 10 000 muestras.
##   test/run_e2e.sh live_stroke_bench_e2e
extends SceneTree

var K

func _init() -> void:
	_run.call_deferred()
	create_timer(280.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://live_stroke")
	if not await K.boot("modern"):
		quit(1)
		return
	var ab: Node2D = await K.artboard(Vector2(4000, 3000), "Largo", Color.WHITE)
	await K.look_at(ab, 1.0)
	K.canvas.switch_tool("brush")
	await K.frames(6)
	var tool = K.canvas.current_tool
	var style := OS.get_environment("BRUSH_STYLE") if OS.has_environment("BRUSH_STYLE") else "pen"
	tool.brush_style = style
	var start_g := ab.to_global(Vector2(200, 1500))
	var sp: Vector2 = K.canvas.get_viewport().get_canvas_transform() * start_g
	var mb := InputEventMouseButton.new()
	mb.position = sp
	mb.global_position = sp
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(mb)
	await K.frames(2)
	K.check("el pincel empezó un trazo", tool.is_drawing and is_instance_valid(tool.current_line))
	if not tool.is_drawing:
		quit(1)
		return
	var line: Line2D = tool.current_line
	var r = line.get_node_or_null("StrokeRender")
	var marks := [1000, 5000, 10000]
	var t_prev := 0
	var n_prev := 0
	var i := 0
	var worst_frame := 0.0
	for mk in marks:
		var t0 := Time.get_ticks_usec()
		var rend := 0
		var frames := 0
		while i < mk:
			var a := float(i) * 0.004
			var p := Vector2(200 + i * 0.35, 1500 + sin(a) * 600.0)
			tool._on_new_raw_point(p, 0.6 + 0.3 * sin(a * 3.0))
			i += 1
			if i % 2 == 0 and r:
				var tr := Time.get_ticks_usec()
				r._draw()
				var dt := Time.get_ticks_usec() - tr
				rend += dt
				frames += 1
				if mk == marks[-1]:
					worst_frame = maxf(worst_frame, dt / 1000.0)
		var total_us := Time.get_ticks_usec() - t0
		var per_sample := float(total_us - rend) / float(mk - n_prev) / 1000.0
		var per_frame := float(rend) / maxf(frames, 1) / 1000.0
		print("BENCH muestras=%d puntos_linea=%d vista_previa_ms=%.3f redibujar_ms=%.2f" % [mk, line.points.size(), per_sample, per_frame])
		n_prev = mk
	print("BENCH peor_fotograma_ms=%.1f (10 000 muestras)" % worst_frame)
	var up := InputEventMouseButton.new()
	up.position = sp
	up.global_position = sp
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	_send(up)
	await K.frames(4)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
