# =============================================================================
# FASE B · ENCARGO 35 — «Muro de marca» (Pro) — CARGA MASIVA
# Un mural publicitario con N elementos (por defecto 10 000; 50 000 con
# E2E_ENV="WALL_N=50000 WALL_MODE=low") que mezcla TODO: polígonos, Bézier,
# textos, trazos de pincel, pinceles de figuras, textos en trazado y
# máscaras. Mide crear, fotograma, zoom, ratón (clic preciso), seleccionar
# todo, mover, exportar SVG/PNG, guardar, abrir y memoria.
#   E2E_TIMEOUT=1800 E2E_ENV="WALL_N=10000" test/run_e2e.sh proyecto_35_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/35"
var K
var N := 10000
var MODE := "high"

func _init() -> void:
	N = int(OS.get_environment("WALL_N")) if OS.has_environment("WALL_N") else 10000
	MODE = OS.get_environment("WALL_MODE") if OS.has_environment("WALL_MODE") else "high"
	_run.call_deferred()
	create_timer(1700.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("professional"):
		print("RESULT: no arranca")
		quit(1)
		return
	var pm = root.get_node_or_null("PerformanceManager")
	if pm and pm.has_method("set_quality"):
		pm.set_quality("ultra" if MODE == "high" else "potato")
	var api = K.api
	K.note("N", N)
	K.note("modo", MODE)
	var cols := int(ceil(sqrt(float(N) * 1.6)))
	var cell := 60.0
	var size := Vector2(cols * cell + 120, ceil(float(N) / cols) * cell + 120)
	var wall: Node2D = await K.artboard(size, "Muro", Color("#0f1220"))
	# Piezas base para pinceles de figuras
	var leaf = api.add_star(Vector2(-200, -200), 10, 6, 0.5, "Semilla estrella")
	var palette := [Color("#ff4d6d"), Color("#ffd166"), Color("#06d6a0"), Color("#118ab2"), Color("#ef476f"), Color("#f8f9fa")]
	var t0 := Time.get_ticks_msec()
	var made := 0
	var specials := {"texto_trazado": 0, "pincel_figuras": 0, "mascara": 0, "pincel": 0}
	var kind_us := {}
	var kind_n := {}
	for i in N:
		var cx := 60.0 + (i % cols) * cell + cell * 0.5
		var cy := 60.0 + (i / cols) * cell + cell * 0.5
		var col: Color = palette[i % palette.size()]
		var kind := i % 20
		var node: Node2D = null
		var tk := Time.get_ticks_usec()
		match kind:
			0, 1, 2, 3, 4:
				node = api.add_polygon(Vector2(cx, cy), 22, 3 + i % 6, 2.0, "P%d" % i)
				api.set_props(node, {"fill_color": col, "stroke_width": 0.0})
			5, 6, 7:
				node = api.add_star(Vector2(cx, cy), 24, 5, 0.45, "S%d" % i)
				api.set_props(node, {"fill_color": col, "stroke_width": 1.0, "stroke_color": Color.WHITE})
			8, 9, 10:
				var c := Curve2D.new()
				c.add_point(Vector2(cx - 24, cy + 10), Vector2.ZERO, Vector2(10, -30))
				c.add_point(Vector2(cx + 24, cy - 10), Vector2(-10, 30), Vector2.ZERO)
				node = api.add_curve(c, false, "C%d" % i)
				api.set_props(node, {"stroke_color": col, "stroke_width": 3.0})
			11, 12, 13:
				node = api.add_text(Vector2(cx - 26, cy - 14), "AD%d" % (i % 100), 18, col)
			14, 15, 16:
				node = K.brush(PackedVector2Array([Vector2(cx - 24, cy), Vector2(cx, cy - 12), Vector2(cx + 24, cy + 6)]), 5.0, ["pen", "marker", "pencil"][i % 3], col, true, "B%d" % i)
				specials["pincel"] += 1
			17:
				if specials["pincel_figuras"] < 200:
					node = K.object_brush([leaf], PackedVector2Array([Vector2(cx - 26, cy), Vector2(cx + 26, cy)]), 12.0, {"spacing": 1.3}, "OB%d" % i)
					specials["pincel_figuras"] += 1
			18:
				if specials["mascara"] < 100:
					var m = api.add_ellipse(Vector2(cx, cy), Vector2(46, 46), "M%d" % i)
					api.set_props(m, {"fill_color": Color.WHITE, "stroke_width": 0.0})
					var inner = api.add_rect(Vector2(cx + 10, cy + 10), Vector2(46, 46), 0.0, "MI%d" % i)
					api.set_props(inner, {"fill_color": col, "stroke_width": 0.0})
					await K.mask(m, inner)
					node = m
					specials["mascara"] += 1
			19:
				if specials["texto_trazado"] < 50:
					var c2 := Curve2D.new()
					c2.add_point(Vector2(cx - 26, cy + 10), Vector2.ZERO, Vector2(14, -26))
					c2.add_point(Vector2(cx + 26, cy + 10), Vector2(-14, -26), Vector2.ZERO)
					var arc = api.add_curve(c2, false, "Arco%d" % i)
					api.set_props(arc, {"stroke_width": 0.0})
					await K.text_on_path("VECTOPEN", 9, col, arc, {"align": 0.5})
					specials["texto_trazado"] += 1
					node = arc
		var kname: String = ["pol", "pol", "pol", "pol", "pol", "estrella", "estrella", "estrella", "curva", "curva", "curva", "texto", "texto", "texto", "pincel", "pincel", "pincel", "figuras", "mascara", "trazado"][kind]
		kind_us[kname] = int(kind_us.get(kname, 0)) + (Time.get_ticks_usec() - tk)
		kind_n[kname] = int(kind_n.get(kname, 0)) + (1 if node else 0)
		if node:
			made += 1
		if i % 2000 == 1999:
			await process_frame
	leaf.visible = false
	K.note("crear_ms", Time.get_ticks_msec() - t0)
	for kn in kind_us:
		if int(kind_n.get(kn, 0)) > 0:
			K.note("crear_%s_ms_c_u" % kn, snappedf(float(kind_us[kn]) / 1000.0 / int(kind_n[kn]), 0.01))
	K.note("figuras", K.count_shapes(K.cont))
	for k in specials:
		K.note(k, specials[k])
	K.check("mural creado con %d elementos" % made, made >= int(N * 0.85), str(made))
	await K.frames(10)
	await K.look_at(wall)
	var fm: float = await K.frame_ms("todo_visible")
	K.note("fps_todo_visible", snappedf(1000.0 / maxf(fm, 0.001), 0.1))
	await K.shot("01_muro")
	# Zoom continuo (sin detenerse) y al 100 %
	var cam: Camera2D = K.canvas.camera
	var z0: float = cam.zoom.x
	var tz := Time.get_ticks_usec()
	for i in 40:
		var z := z0 * (1.0 + i * 0.05)
		cam.zoom = Vector2(z, z)
		await RenderingServer.frame_post_draw
	K.note("fps_zoom", snappedf(40.0 / ((Time.get_ticks_usec() - tz) / 1000000.0), 0.1))
	await K.look_at(wall, 1.0)
	await K.frame_ms("zoom_100")
	# Ratón (clic preciso)
	var mt = K.canvas.get_current_tool()
	if mt and mt.has_method("_shape_at"):
		mt._shape_at_hover(wall.to_global(Vector2(80, 80)))   # construye la rejilla
		var tb := Time.get_ticks_usec()
		mt._hgrid_build()
		K.note("rejilla_ms", snappedf((Time.get_ticks_usec() - tb) / 1000.0, 0.1))
		var th := Time.get_ticks_usec()
		for i in 200:
			mt._shape_at_hover(wall.to_global(Vector2(60 + (i * 37) % int(size.x - 120), 60 + (i * 53) % int(size.y - 120))))
		var hov := (Time.get_ticks_usec() - th) / 1000.0 / 200.0
		K.note("hover_ms", snappedf(hov, 0.01))
		K.check("buscar bajo el ratón < 8 ms con %d elementos" % N, hov < 8.0, "%.2f ms" % hov)
	if OS.has_environment("HIT_PROFILE") and mt:
		var per := {}
		var far: Vector2 = wall.to_global(Vector2(size.x * 0.5, size.y * 0.5))
		for c in wall.get_children():
			if not (c is Node2D):
				continue
			var key := c.get_class() + ("/brush" if c is Line2D else "") + ("/group" if mt._es_grupo_movetool(c) else "")
			var t1 := Time.get_ticks_usec()
			if mt._es_grupo_movetool(c):
				mt._rama_contiene_punto(c, far)
			else:
				mt._node_contains_point(c, far)
			var d := Time.get_ticks_usec() - t1
			if not per.has(key):
				per[key] = [0, 0]
			per[key][0] += 1
			per[key][1] += d
		for k in per:
			print("PROF %s n=%d total=%.2f ms media=%.1f us" % [k, per[k][0], per[k][1] / 1000.0, float(per[k][1]) / per[k][0]])
	# Seleccionar todo y mover
	var all: Array = []
	for c in wall.get_children():
		if c is Node2D and String(c.name) != "ArtboardTitle":
			all.append(c)
	var ts := Time.get_ticks_msec()
	K.sm.set_selection(all)
	await K.frames(2)
	K.note("seleccionar_todo_ms", Time.get_ticks_msec() - ts)
	if OS.has_environment("DRAG_PROFILE"):
		var tsn := Time.get_ticks_usec()
		mt.transform_initial_states.clear()
		for n in mt.selected_shapes:
			mt.transform_initial_states[n] = mt._snapshot(n)
		print("PROF snapshots_ms=%.1f (n=%d)" % [(Time.get_ticks_usec() - tsn) / 1000.0, mt.selected_shapes.size()])
		var tmr := Time.get_ticks_usec()
		mt._macro_rect_inicial()
		print("PROF macro_rect_inicial_ms=%.1f" % ((Time.get_ticks_usec() - tmr) / 1000.0))
		var tsc := Time.get_ticks_usec()
		var cands: Array = mt._snap_candidates()
		print("PROF snap_candidates_ms=%.1f (n=%d)" % [(Time.get_ticks_usec() - tsc) / 1000.0, cands.size()])
		var tss := Time.get_ticks_usec()
		var snm = root.get_node("SnapManager")
		snm.smart_snap(Rect2(0, 0, 100, 100), cands, 1.0)
		print("PROF smart_snap_ms=%.1f" % ((Time.get_ticks_usec() - tss) / 1000.0))
		var tub := Time.get_ticks_usec()
		mt._update_bounding_box()
		print("PROF update_bbox_ms=%.1f" % ((Time.get_ticks_usec() - tub) / 1000.0))
		mt.is_dragging_shape = true
		mt.transform_initial_mouse = wall.to_global(size * 0.5)
		var tmo := Time.get_ticks_usec()
		mt._on_motion(wall.to_global(size * 0.5) + Vector2(5, 0), {"shift": false, "alt": false, "ctrl": false})
		print("PROF on_motion_ms=%.1f" % ((Time.get_ticks_usec() - tmo) / 1000.0))
		mt.is_dragging_shape = false
	if OS.has_environment("MOVE_TYPE_PROFILE"):
		K.sm.clear()
		await K.frames(4)
		var groups := {}
		for n in all:
			var k: String = n.get_class() + ("/" + String(n.get_meta("shape_type", "")) if n.has_meta("shape_type") else "")
			if not groups.has(k):
				groups[k] = []
			groups[k].append(n)
		var cm = null
		for n in root.find_children("*", "", true, false):
			if n.get_script() and String(n.get_script().resource_path).ends_with("cull_manager.gd"):
				cm = n
		var pp = null
		for n in root.find_children("*", "", true, false):
			if n.get_script() and String(n.get_script().resource_path).ends_with("pages_panel.gd"):
				pp = n
		for variant in ["normal", "sin_cull", "sin_paginas"]:
			if cm:
				cm.enabled = variant != "sin_cull"
			if pp:
				pp.set_process(variant != "sin_paginas")
			var arrp: Array = groups.get("Path2D", [])
			var tv := Time.get_ticks_usec()
			for rep in 5:
				for n in arrp:
					(n as Node2D).position += Vector2(1, 0)
				await RenderingServer.frame_post_draw
			print("PROF variante %s: curvas %.1f ms/fotograma" % [variant, (Time.get_ticks_usec() - tv) / 5000.0])
		if cm:
			cm.enabled = true
		if pp:
			pp.set_process(true)
		for k in groups:
			var arr: Array = groups[k]
			var tg := Time.get_ticks_usec()
			for rep in 5:
				var tl := Time.get_ticks_usec()
				for n in arr:
					(n as Node2D).position += Vector2(1, 0)
				if rep == 0:
					print("PROF bucle %s n=%d %.1f ms" % [k, arr.size(), (Time.get_ticks_usec() - tl) / 1000.0])
				await RenderingServer.frame_post_draw
			print("PROF mover %s n=%d → %.1f ms/fotograma" % [k, arr.size(), (Time.get_ticks_usec() - tg) / 5000.0])
		K.sm.set_selection(all)
		await K.frames(3)
	# Arrastre REAL con el ratón sobre la selección (como un usuario)
	var xf: Transform2D = K.canvas.get_viewport().get_canvas_transform()
	var a: Vector2 = xf * wall.to_global(size * 0.5)
	var ev := InputEventMouseMotion.new()
	ev.position = a
	ev.global_position = a
	Input.parse_input_event(ev)
	await process_frame
	var pr := InputEventMouseButton.new()
	pr.position = a
	pr.global_position = a
	pr.button_index = MOUSE_BUTTON_LEFT
	pr.pressed = true
	pr.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(pr)
	await process_frame
	var tm := Time.get_ticks_usec()
	for i in 10:
		var mv := InputEventMouseMotion.new()
		mv.position = a + Vector2((i + 1) * 4, 0)
		mv.global_position = mv.position
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mv)
		await RenderingServer.frame_post_draw
	K.note("arrastrar_seleccion_ms_por_paso", snappedf((Time.get_ticks_usec() - tm) / 10000.0, 0.1))
	var up := InputEventMouseButton.new()
	up.position = a + Vector2(40, 0)
	up.global_position = up.position
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	Input.parse_input_event(up)
	await K.frames(4)
	if OS.has_environment("HIT_PROFILE"):
		var bb = null
		for n in root.find_children("Boundingbox", "", true, false):
			bb = n
		var sel_typed: Array[Node2D] = []
		for n in all:
			sel_typed.append(n)
		if bb and bb.has_method("_get_macro_rect_cloned"):
			var tb := Time.get_ticks_usec()
			bb._get_macro_rect_cloned(sel_typed)
			print("PROF caja_seleccion_ms=%.1f" % ((Time.get_ticks_usec() - tb) / 1000.0))
		var per := {}
		for n in all:
			var k: String = n.get_class() + ("/" + String(n.get_meta("shape_type", "")) if n.has_meta("shape_type") else "")
			var t1 := Time.get_ticks_usec()
			mt._global_rect(n)
			if not per.has(k):
				per[k] = [0, 0]
			per[k][0] += 1
			per[k][1] += Time.get_ticks_usec() - t1
		for k in per:
			print("PROF rect %s n=%d total=%.1f ms" % [k, per[k][0], per[k][1] / 1000.0])
		var tf := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		print("PROF fotograma_sin_mover_ms=%.1f" % ((Time.get_ticks_usec() - tf) / 1000.0))
	K.sm.clear()
	await K.frames(3)
	# Exportar SVG y PNG
	for ext in ["svg", "png"]:
		var p := ProjectSettings.globalize_path(OUT.path_join("muro_%d.%s" % [N, ext]))
		var te := Time.get_ticks_msec()
		var ok: bool = await api.export(p, wall)
		K.note("exportar_%s_ms" % ext, Time.get_ticks_msec() - te)
		K.check("exportar %s con %d elementos" % [ext.to_upper(), N], ok and FileAccess.file_exists(p))
	await K.frames(30)
	# Guardar y abrir
	await K.save_reload("muro_%d" % N)
	K.note("memoria_mb", K.memory_mb())
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
