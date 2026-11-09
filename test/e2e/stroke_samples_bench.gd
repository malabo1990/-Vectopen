# Benchmark de UN trazo con 1 000, 10 000 y 100 000 muestras (VGSE §9):
# tiempo de generación de la geometría, memoria y coste de añadir un punto
# (dibujar en vivo). Sin ventana:
#   flatpak run --command=godot org.godotengine.Godot --headless --path . -s res://test/e2e/stroke_samples_bench.gd
extends SceneTree
func _init() -> void:
	var R = load("res://script_gdscript/shapes/brush_stroke_render.gd")
	var holder := Node2D.new()
	root.add_child(holder)
	for n in [1000, 10000, 100000]:
		for style in ["pen", "pencil", "airbrush"]:
			var l := Line2D.new()
			var pts := PackedVector2Array()
			pts.resize(n)
			for i in n:
				pts[i] = Vector2(i * 0.5, sin(i * 0.02) * 40.0 + cos(i * 0.005) * 80.0)
			l.points = pts
			l.width = 6.0
			l.set_meta("brush_style", style)
			var c := Curve.new()
			c.add_point(Vector2(0, 0.4))
			c.add_point(Vector2(0.5, 1.0))
			c.add_point(Vector2(1, 0.4))
			l.width_curve = c
			holder.add_child(l)
			var r = R.attach(l)
			var m0 := OS.get_static_memory_usage()
			var t0 := Time.get_ticks_usec()
			r._draw()
			var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
			var mem_mb := (OS.get_static_memory_usage() - m0) / 1048576.0
			t0 = Time.get_ticks_usec()
			for k in 5:
				var p2 := l.points
				p2.append(p2[p2.size() - 1] + Vector2(0.5, 0.0))
				l.points = p2
				r._draw()
			var add_ms := (Time.get_ticks_usec() - t0) / 5000.0
			var verts: int = (r._geom["m"]["points"] as PackedVector2Array).size()
			print("STROKE muestras=%d estilo=%s generar=%.1f ms  añadir_punto=%.1f ms  memoria=%.1f MB  vértices=%d" % [n, style, gen_ms, add_ms, mem_mb, verts])
			l.queue_free()
	quit(0)
