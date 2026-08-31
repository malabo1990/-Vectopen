# ==========================================
# RUTA: res://test/perf/stress_scale.gd
# Barrido de ESCALA: ¿cuántos elementos aguanta a 30 FPS (o al cap dado)?
#
# Uso (headless):
#   Godot res://test/perf/stress_scale.tscn --quit-after 100000 -- --count 50000 --fpscap 30
# El "--" separa los args del juego; se leen con OS.get_cmdline_user_args().
#
# Escenario: rejilla de N WorldTextLabel + Camera2D + CullManager con
# auto-pan continuo (simula trabajar sobre el lienzo). Tras 3 s de warmup mide
# 6 s y saca una línea RESULT con: spawn_ms, fps medio/mín, ms de frame (CPU),
# nodos visibles, y FPS "sin cap" (techo real). Luego cierra solo.
# ==========================================
extends Node2D

const WorldTextLabelScript := preload("res://scripts/canvas/world_text_label.gd")
const CullManagerScript := preload("res://scenes/canvas/cull_manager.gd")

var count: int = 10000
var fpscap: int = 30
var fixed_zoom: float = 0.0   # >0 => cámara fijada a ese zoom (prueba de zoom máximo)
var probe_dist: float = 60000.0   # distancia al origen del label sonda (precisión float32)
var columns: int = 0
var cell: Vector2 = Vector2(340, 96)
var _probe: Control = null         # label real cuya posición en pantalla vigilamos
var _prev_screen: Vector2 = Vector2.INF
var _start_screen: Vector2 = Vector2.INF
var _expected_px: float = 0.0      # cuánto DEBERÍA haberse movido la sonda en pantalla
var _max_jump: float = 0.0         # mayor salto de la sonda en un solo frame
var _still_frames: int = 0         # frames en que la sonda no se movió nada
var _pan_frames: int = 0

var _cam: Camera2D
var _cull
var _grid_center: Vector2
var _elapsed := 0.0
var _pan_dir := Vector2(1, 0.4)
var spawn_ms := 0.0

var _phase := "warmup"          # warmup -> measure -> uncap -> done
var _fps_samples: Array[float] = []
var _ft_samples: Array[float] = []
var _uncap_samples: Array[float] = []
var _vis := 0


func _ready() -> void:
	_parse_args()
	Engine.max_fps = fpscap
	columns = maxi(1, int(round(sqrt(float(count)) * 1.6)))

	_cam = Camera2D.new()
	_cam.enabled = true
	add_child(_cam)
	_cam.make_current()

	var content := Node2D.new()
	content.name = "Content"
	add_child(content)

	var rows := int(ceil(float(count) / float(columns)))
	_grid_center = Vector2(columns * cell.x, rows * cell.y) * 0.5
	_cam.position = _grid_center

	var t0 := Time.get_ticks_usec()
	for i in count:
		var l: Label = WorldTextLabelScript.new()
		l.base_font_size = 13
		l.text = "Elem %d" % i
		l.add_theme_font_size_override("font_size", 13)
		l.position = Vector2((i % columns) * cell.x, (i / columns) * cell.y)
		content.add_child(l)
	spawn_ms = (Time.get_ticks_usec() - t0) / 1000.0

	_cull = CullManagerScript.new()
	_cull.camera = _cam
	_cull.enabled = true
	add_child(_cull)

	if fixed_zoom > 0.0:
		_cam.zoom = Vector2(fixed_zoom, fixed_zoom)
		# label sonda LEJOS del origen: es donde la precisión float32 de la
		# cámara (Transform2D) se nota más al hacer pan a zoom extremo.
		_probe = content.get_child(count - 1) as Control
		if _probe:
			# lo colocamos a `probe_dist` del origen (coords grandes = peor precisión float32)
			_probe.position = Vector2(1, 1).normalized() * probe_dist
			_cam.position = _probe.position

	print("[SCALE] count=%d fpscap=%d zoom=%s spawn_ms=%.0f" % [
		count, fpscap, ("%.0f" % fixed_zoom) if fixed_zoom > 0.0 else "pan", spawn_ms])


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--count" and i + 1 < args.size():
			count = maxi(1, int(args[i + 1]))
		elif args[i] == "--fpscap" and i + 1 < args.size():
			fpscap = maxi(0, int(args[i + 1]))
		elif args[i] == "--zoom" and i + 1 < args.size():
			fixed_zoom = maxf(0.0, float(args[i + 1]))
		elif args[i] == "--dist" and i + 1 < args.size():
			probe_dist = maxf(0.0, float(args[i + 1]))


func _process(delta: float) -> void:
	_elapsed += delta

	if fixed_zoom > 0.0:
		# Zoom fijo: pedimos un pan CONSTANTE de ~8 px/frame en pantalla
		# (world_delta = 8 / zoom). La sonda debería avanzar 8 px cada frame;
		# si la precisión float32 de la cámara no da, se queda quieta y luego
		# pega un salto. Medimos: px reales vs pedidos, salto máx, frames quietos.
		if _cam and _probe and _elapsed > 3.5:
			var world_step := Vector2(1.0, 0.6).normalized() * (8.0 / fixed_zoom)
			_cam.position += world_step
			_expected_px += 8.0
			_pan_frames += 1
			var screen_now: Vector2 = _probe.get_global_transform_with_canvas().origin
			if _start_screen.x == INF:
				_start_screen = screen_now
			if _prev_screen.x != INF:
				var jump := _prev_screen.distance_to(screen_now)
				_max_jump = maxf(_max_jump, jump)
				if jump < 0.01:
					_still_frames += 1
			_prev_screen = screen_now
	elif _cam:
		# Auto-pan continuo (trabajo real para el CullManager cada frame).
		_cam.position += _pan_dir.normalized() * 700.0 * delta
		var d := _cam.position - _grid_center
		if absf(d.x) > _grid_center.x * 0.7: _pan_dir.x = -_pan_dir.x
		if absf(d.y) > _grid_center.y * 0.7: _pan_dir.y = -_pan_dir.y

	var fps := Engine.get_frames_per_second()
	var ft := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 \
		+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	match _phase:
		"warmup":
			if _elapsed > 3.0:
				_phase = "measure"
		"measure":
			_fps_samples.append(fps)
			_ft_samples.append(ft)
			if _elapsed > 9.0:
				_vis = _count_visible()
				Engine.max_fps = 0   # quitar el cap: medir el techo real
				_phase = "uncap"
		"uncap":
			if _elapsed > 11.0:
				_uncap_samples.append(fps)
			if _elapsed > 14.0:
				_report()
				_phase = "done"
				get_tree().quit()


func _count_visible() -> int:
	var n := 0
	for x in get_tree().get_nodes_in_group("world_content"):
		if x is CanvasItem and x.visible:
			n += 1
	return n


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
	var fps_avg := _avg(_fps_samples)
	var fps_min := _minv(_fps_samples)
	var ft_avg := _avg(_ft_samples)
	var uncap := _avg(_uncap_samples)
	var holds := "SI" if fps_min >= float(fpscap) - 2.0 else "NO"
	print("[SCALE] RESULT count=%d | spawn=%.0fms | @%dfps: avg=%.1f min=%.1f cpu=%.1fms | aguanta=%s | techo_sin_cap=%.0ffps | visibles=%d" % [
		count, spawn_ms, fpscap, fps_avg, fps_min, ft_avg, holds, uncap, _vis])
	if fixed_zoom > 0.0:
		var actual_px := _start_screen.distance_to(_prev_screen) if _start_screen.x != INF else 0.0
		var still_pct := 100.0 * _still_frames / maxf(1.0, _pan_frames)
		print("[SCALE] ZOOM=%.0f dist=%.0f | pan pedido=%.0fpx real=%.0fpx (%.0f%%) | salto max=%.1fpx | frames quietos=%.0f%%" % [
			fixed_zoom, probe_dist, _expected_px, actual_px, 100.0 * actual_px / maxf(1.0, _expected_px),
			_max_jump, still_pct])
