# ==========================================
# RUTA: res://test/perf/stress_bezier.gd
# Benchmark BÉZIER EXTREMO: un VectorPath (Path2D + Curve2D) con N puntos de
# control. Mide por separado:
#   create   -> añadir N puntos a la curva
#   first_bake-> primer get_baked_points()  (geometría "activa")
#   pan      -> FPS con la curva quieta (el baked está cacheado por Godot)
#   edit_pt  -> mover UN punto de control: coste de re-bake completo
#   add_pt   -> añadir un punto al final
#
#   Godot res://test/perf/stress_bezier.tscn -- --points 10000
#
# Objetivo: ver dónde el coste deja de ser O(1) "porque la geometría existe"
# y pasa a ser O(N) por operación.
# ==========================================
extends Node

const CANVAS := "res://scenes/canvas/canvas.tscn"

var points: int = 5000
var _scene: Node2D
var _cam: Camera2D
var _path: Path2D
var _phase := "load"
var _t := 0.0
var _fps: Array[float] = []
var _r := {}


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--points" and i + 1 < a.size():
			points = maxi(2, int(a[i + 1]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_scene = load(CANVAS).instantiate()
	add_child(_scene)
	for _i in 4:
		await get_tree().process_frame
	_cam = _scene.get_node_or_null("Camera2D")
	var pm = get_node_or_null("/root/PerformanceManager")
	if pm: pm.set_process(false)
	var mgr := _scene.get_node_or_null("manager_script") as ArtboardManager
	var ab: ArtboardEditor = mgr.get_active_artboard()

	# 1. crear la curva
	var t0 := Time.get_ticks_usec()
	var vp_script := load("res://script_gdscript/shapes/VectorPath.gd")
	_path = Path2D.new()
	_path.set_script(vp_script)
	var curve := Curve2D.new()
	var r := 400.0
	for i in points:
		var ang := TAU * float(i) / float(points) * 8.0   # espiral densa
		var rad := r * (0.2 + 0.8 * float(i) / float(points))
		var p := Vector2(cos(ang), sin(ang)) * rad + Vector2(r, r)
		var tang := Vector2(-sin(ang), cos(ang)) * (rad * 0.05)
		curve.add_point(p, -tang, tang)
	_r["create_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	_path.curve = curve
	ab.add_child(_path)
	await get_tree().process_frame

	# 2. primer bake (geometría activa)
	t0 = Time.get_ticks_usec()
	var baked := curve.get_baked_points()
	_r["first_bake_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	_r["control_points"] = curve.point_count
	_r["baked_points"] = baked.size()
	_r["mem_mb"] = int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)

	# encuadre
	if _cam:
		_cam.position = Vector2(400, 400) + ab.global_position
		_cam.zoom = Vector2(0.4, 0.4)

	_begin("pan")


func _begin(m: String) -> void:
	_phase = m
	_t = 0.0
	_fps.clear()


func _process(delta: float) -> void:
	match _phase:
		"pan":
			_t += delta
			if _cam:
				_cam.position.x += 500.0 * delta
			if _t > 1.0:
				_fps.append(Engine.get_frames_per_second())
			if _t > 4.0:
				_r["fps_pan"] = "%.0f (min %.0f)" % [_avg(_fps), _minv(_fps)]
				_measure_edit()
				_report()
				get_tree().quit()


func _measure_edit() -> void:
	var curve: Curve2D = _path.curve
	# mover UN punto de control 50 veces y medir el coste medio (incluye el
	# re-bake completo que Godot hace al invalidarse la curva).
	var reps := 50
	var t0 := Time.get_ticks_usec()
	for i in reps:
		var idx := curve.point_count / 2
		var pos := curve.get_point_position(idx)
		curve.set_point_position(idx, pos + Vector2(1, 0))
		var _b := curve.get_baked_points()   # fuerza el re-bake
	_r["edit_1pt_ms"] = "%.2f" % ((Time.get_ticks_usec() - t0) / 1000.0 / reps)

	# añadir un punto al final
	t0 = Time.get_ticks_usec()
	for i in reps:
		curve.add_point(curve.get_point_position(curve.point_count - 1) + Vector2(2, 2))
		var _b := curve.get_baked_points()
	_r["add_1pt_ms"] = "%.2f" % ((Time.get_ticks_usec() - t0) / 1000.0 / reps)


func _avg(a: Array) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0
	for v in a: s += v
	return s / a.size()

func _minv(a: Array) -> float:
	if a.is_empty(): return 0.0
	var m: float = a[0]
	for v in a: m = minf(m, v)
	return m


func _report() -> void:
	print("[BEZIER] RESULT")
	for k in ["control_points", "baked_points", "create_ms", "first_bake_ms",
			"mem_mb", "fps_pan", "edit_1pt_ms", "add_1pt_ms"]:
		print("  %-16s = %s" % [k, str(_r.get(k, "?"))])
