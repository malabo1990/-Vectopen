# =============================================================================
# BENCHMARK de documentos grandes: N elementos variados (figuras, trazos de
# pincel y textos) en modo PC POTENTE (calidad ultra) o PC DÉBIL (potato,
# objetivo de memoria ~2 GB). Mide: crear/instanciar (≈ abrir), fps con
# todo a la vista, desplazar, zoom, seleccionar todo, mover la selección,
# guardar, cargar y memoria. Salida: líneas «BENCH clave=valor».
#   E2E_TIMEOUT=1800 E2E_ENV="BENCH_N=10000 BENCH_MODE=low" \
#       test/run_e2e.sh scene_benchmark_e2e
# =============================================================================
extends SceneTree

var fails := 0
var canvas
var N := 1000
var MODE := "high"

func _init() -> void:
	N = int(OS.get_environment("BENCH_N")) if OS.has_environment("BENCH_N") else 1000
	MODE = OS.get_environment("BENCH_MODE") if OS.has_environment("BENCH_MODE") else "high"
	_run.call_deferred()
	create_timer(float(OS.get_environment("BENCH_TIMEOUT")) if OS.has_environment("BENCH_TIMEOUT") else 1700.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func bench(key: String, value) -> void:
	print("BENCH %s=%s" % [key, str(value)])

## ms medios por fotograma durante `n` fotogramas, llamando a `step` en cada uno.
func frame_ms(n: int, step: Callable = Callable()) -> float:
	await RenderingServer.frame_post_draw
	var t0 := Time.get_ticks_usec()
	for i in n:
		if step.is_valid():
			step.call(i)
		await process_frame
	await RenderingServer.frame_post_draw
	return (Time.get_ticks_usec() - t0) / 1000.0 / float(n)

func mem_mb() -> float:
	return OS.get_static_memory_usage() / 1048576.0

func _run() -> void:
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("smart")
	await frames(10)
	var pm = root.get_node("PerformanceManager")
	pm.set_quality("ultra" if MODE == "high" else "potato")
	await frames(10)
	bench("N", N)
	bench("modo", MODE)
	bench("calidad", pm.quality_preset)
	bench("tope_fps_del_modo", pm.target_fps)
	# Capacidad REAL (sin reposo a 30 fps, sin tope ni sincronización vertical):
	# así se ven los cuellos de botella; el tope del modo se anota aparte.
	pm.set_idle_render(false)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	canvas = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").api
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var mem0 := mem_mb()
	# ── plantilla variada (20 elementos) ──
	var tpl := Node2D.new()
	ab.add_child(tpl)
	var made: Array = []
	for i in 6:
		made.append(api.add_rect(Vector2(i * 30, 0), Vector2(22, 16)))
	for i in 4:
		made.append(api.add_ellipse(Vector2(i * 30, 30), Vector2(20, 20)))
	for i in 3:
		made.append(api.add_star(Vector2(i * 30, 60), 11, 5))
	for i in 4:
		var l := Line2D.new()
		var pts := PackedVector2Array()
		for k in 24:
			pts.append(Vector2(i * 30 + k * 1.1, 90 + sin(k * 0.5) * 6.0))
		l.points = pts
		l.width = 3.0
		l.default_color = Color(0.15, 0.15, 0.2)
		l.set_meta("brush_style", ["pen", "pencil", "marker", "calligraphy"][i])
		ab.add_child(l)
		load("res://script_gdscript/shapes/brush_stroke_render.gd").attach(l)
		made.append(l)
	for i in 3:
		made.append(api.add_text(Vector2(i * 40, 120), "Txt%d" % i, 12, Color.BLACK))
	await frames(4)
	for n in made:
		if is_instance_valid(n) and n.get_parent() != tpl:
			n.reparent(tpl)
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	var tpl_data: Array = Ser.serialize_elements(tpl)
	tpl.queue_free()
	await frames(4)
	var per := tpl_data.size()
	bench("plantilla", per)
	# ── crear N (como al abrir un documento) ──
	var holder := Node2D.new()
	holder.name = "Bench"
	ab.add_child(holder)
	var cols := int(ceil(sqrt(float(N) / float(per))))
	var t0 := Time.get_ticks_msec()
	var copies := int(ceil(float(N) / float(per)))
	for c in copies:
		var block := Node2D.new()
		block.name = "B%d" % c
		block.set_meta("shape_type", "group")   # grupo de verdad: se guarda
		block.position = Vector2((c % cols) * 200, (c / cols) * 160)
		holder.add_child(block)
		Ser.instantiate_elements(block, tpl_data)
		if c % 50 == 49:
			await process_frame
	var t_create := Time.get_ticks_msec() - t0
	await frames(10)
	var count := 0
	for b in holder.get_children():
		count += b.get_child_count()
	bench("elementos", count)
	bench("crear_ms", t_create)
	var bounds := Rect2(holder.global_position, Vector2(cols * 200, int(ceil(float(copies) / cols)) * 160))
	# ── todo a la vista ──
	var vs := root.get_visible_rect().size
	cam.position = bounds.get_center()
	cam.zoom = Vector2.ONE * clampf(minf(vs.x / bounds.size.x, vs.y / bounds.size.y) * 0.9, 0.01, 4.0)
	await frames(20)
	bench("fps_todo_visible", snappedf(1000.0 / await frame_ms(60), 0.1))
	bench("mem_mb", snappedf(mem_mb(), 1))
	bench("mem_doc_mb", snappedf(mem_mb() - mem0, 1))
	bench("vram_mb", snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 1))
	# ── desplazar (pan) y zoom ──
	var z0 := cam.zoom
	var p0 := cam.position
	bench("fps_desplazar", snappedf(1000.0 / await frame_ms(90, func(i): cam.position = p0 + Vector2(sin(i * 0.1), cos(i * 0.1)) * 200.0 / z0.x), 0.1))
	bench("fps_zoom", snappedf(1000.0 / await frame_ms(90, func(i): cam.zoom = z0 * (1.0 + 0.5 * sin(i * 0.07))), 0.1))
	cam.zoom = Vector2.ONE
	cam.position = p0
	await frames(10)
	bench("fps_zoom_100", snappedf(1000.0 / await frame_ms(60), 0.1))
	# ── seleccionar todo y mover la selección ──
	var all: Array = []
	for b in holder.get_children():
		all.append_array(b.get_children())
	var sm = root.get_node("SelectionManager")
	t0 = Time.get_ticks_msec()
	sm.set_selection(all)
	await process_frame
	bench("seleccionar_todo_ms", Time.get_ticks_msec() - t0)
	t0 = Time.get_ticks_msec()
	for k in 10:
		for nd in all:
			(nd as Node2D).position += Vector2(1, 0)
		await process_frame
	bench("mover_seleccion_ms_por_paso", snappedf((Time.get_ticks_msec() - t0) / 10.0, 0.1))
	sm.clear()
	await frames(4)
	# ── guardar y cargar ──
	var path := OS.get_cache_dir().path_join("vectopen_bench_%d.vtp" % N)
	var dr = root.get_node("DataRepository")
	t0 = Time.get_ticks_msec()
	var saved: String = dr.save_project(path)
	bench("guardar_ms", Time.get_ticks_msec() - t0)
	bench("archivo_mb", snappedf(FileAccess.get_file_as_bytes(saved).size() / 1048576.0, 0.01) if saved != "" else -1)
	check("se guarda", saved != "")
	t0 = Time.get_ticks_msec()
	var ok: bool = dr.load_project(saved) if saved != "" else false
	await frames(10)
	bench("cargar_ms", Time.get_ticks_msec() - t0)
	var after := 0
	var ab2: Node2D = canvas.get_node("manager_script").get_active_artboard()
	for nd in ab2.find_children("*", "", true, false):
		if nd is CanvasItem and (nd.has_meta("shape_type") or nd is Line2D) and String(nd.get_meta("shape_type", "")) != "group":
			after += 1
	bench("elementos_tras_cargar", after)
	check("se carga con todos los elementos (%d de %d)" % [after, count], ok and after >= count)
	bench("mem_tras_cargar_mb", snappedf(mem_mb(), 1))
	if MODE == "low":
		check("modo PC débil: cabe en ~2 GB (memoria de la app < 1400 MB)", mem_mb() < 1400.0, "%.0f MB" % mem_mb())
	DirAccess.remove_absolute(path)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
