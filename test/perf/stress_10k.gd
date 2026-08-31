# ==========================================
# RUTA: res://test/perf/stress_10k.gd
# Banco de pruebas EN JUEGO REAL: N elementos (por defecto 10.000) tipo
# WorldTextLabel repartidos en una rejilla, con Camera2D + CullManager.
#
# Tras 2 s de warmup ejecuta un BARRIDO DE ZOOM automatico y determinista:
#   1x (normal) -> 0.04x (todos en pantalla) -> 1x -> 2000x (zoom extremo) -> 1x
# y registra el FPS minimo en cada tramo.
#
# Expone (leible via query_runtime_node en /root/Stress10K):
#   spawn_ms          -> coste de crear los N nodos en _ready
#   element_count     -> N real
#   fps               -> FPS instantaneo
#   fps_min_normal    -> minimo con zoom ~1x (culling activo, ~200 visibles)
#   fps_min_zoomout   -> minimo con todos los elementos en pantalla a la vez
#   fps_min_zoomext   -> minimo a zoom extremo (>500x)
#   visible_count     -> nodos de world_content visibles ahora
#   total_group       -> nodos totales en world_content
#   cam_zoom          -> zoom actual
#   phase             -> spawning|warmup|normal|zoomout|back1|zoomext|done
# ==========================================
extends Node2D

const WorldTextLabelScript := preload("res://scripts/canvas/world_text_label.gd")
const CullManagerScript := preload("res://scenes/canvas/cull_manager.gd")

@export var element_count: int = 10000
@export var columns: int = 100
@export var cell: Vector2 = Vector2(340, 96)
@export var pan_speed: float = 900.0

var spawn_ms: float = 0.0
var fps: float = 0.0
var fps_min_normal: float = 99999.0
var fps_min_zoomout: float = 99999.0
var fps_min_zoomext: float = 99999.0
var fps_min_ramp: float = 99999.0   # minimo MIENTRAS se zoomea (transiciones)
var visible_count: int = 0
var total_group: int = 0
var cam_zoom: float = 1.0
var phase: String = "spawning"

var _cam: Camera2D
var _cull
var _content: Node2D
var _grid_center: Vector2
var _elapsed: float = 0.0
var _pan_dir: Vector2 = Vector2(1, 0.35)
var _recount_t: float = 0.0
var _log_t: float = 0.0
var _wheel_t: float = 0.0

# Programa de barrido: [fin_en_segundos, fase, zoom_objetivo]
# El zoom se aproxima por PASOS tipo rueda de raton (x1.15 / :1.15) para que
# sea una prueba honesta: nadie zoomea con un lerp continuo.
const PROGRAM := [
	[2.0,  "warmup",  1.0],
	[9.0,  "normal",  1.0],
	[18.0, "zoomout", 0.03],
	[26.0, "back1",   1.0],
	[40.0, "zoomext", 2000.0],
	[48.0, "done",    1.0],
]
const WHEEL_STEP := 1.15
const WHEEL_INTERVAL := 0.07   # ~14 pasos/s, como una rueda rapida


func _ready() -> void:
	_cam = Camera2D.new()
	_cam.name = "Cam"
	_cam.enabled = true
	add_child(_cam)
	_cam.make_current()

	_content = Node2D.new()
	_content.name = "Content"
	add_child(_content)

	@warning_ignore("integer_division")
	var rows := int(ceil(float(element_count) / float(columns)))
	_grid_center = Vector2(columns * cell.x, rows * cell.y) * 0.5
	_cam.position = _grid_center

	var t0 := Time.get_ticks_usec()
	for i in element_count:
		var col := i % columns
		@warning_ignore("integer_division")
		var row := i / columns
		var l: Label = WorldTextLabelScript.new()
		l.base_font_size = 13
		l.text = "Elem %d" % i
		l.add_theme_font_size_override("font_size", 13)
		l.position = Vector2(col * cell.x, row * cell.y)
		_content.add_child(l)
	spawn_ms = (Time.get_ticks_usec() - t0) / 1000.0

	_cull = CullManagerScript.new()
	_cull.name = "Cull"
	_cull.camera = _cam
	_cull.enabled = true
	add_child(_cull)

	phase = "warmup"
	print("[STRESS10K] spawn de %d elementos en %.0f ms" % [element_count, spawn_ms])
	_push("info", "spawn %d elems: %.0f ms" % [element_count, spawn_ms])


func _process(delta: float) -> void:
	_elapsed += delta
	fps = Engine.get_frames_per_second()

	# --- Programa de zoom determinista ---
	var target_zoom := 1.0
	var new_phase := "done"
	for step in PROGRAM:
		if _elapsed <= step[0]:
			new_phase = step[1]
			target_zoom = step[2]
			break
	phase = new_phase
	var ramping := false
	if _cam:
		var z := _cam.zoom.x
		_wheel_t += delta
		while _wheel_t >= WHEEL_INTERVAL and not is_equal_approx(z, target_zoom):
			_wheel_t -= WHEEL_INTERVAL
			if z < target_zoom:
				z = minf(z * WHEEL_STEP, target_zoom)
			else:
				z = maxf(z / WHEEL_STEP, target_zoom)
			ramping = true
		_cam.zoom = Vector2(z, z)
		cam_zoom = z

	# --- Auto-pan (da trabajo real al CullManager) ---
	if _cam and phase in ["normal", "back1"]:
		_cam.position += _pan_dir.normalized() * pan_speed * delta / maxf(0.05, _cam.zoom.x)
		var d := _cam.position - _grid_center
		if absf(d.x) > _grid_center.x * 0.8:
			_pan_dir.x = -_pan_dir.x
		if absf(d.y) > _grid_center.y * 0.8:
			_pan_dir.y = -_pan_dir.y
	elif _cam and phase in ["zoomext"]:
		pass
	elif _cam:
		# volver al centro para el zoom-out / extremo
		_cam.position = _cam.position.lerp(_grid_center, clampf(delta * 2.0, 0.0, 1.0))

	# FPS minimo mientras se zoomea activamente (transiciones = lo peor)
	if ramping and _elapsed > 3.0:
		fps_min_ramp = minf(fps_min_ramp, fps)

	# --- Registro de FPS minimo por tramo (ignora el primer 0.5 s del tramo) ---
	match phase:
		"normal":
			if _elapsed > 3.0:
				fps_min_normal = minf(fps_min_normal, fps)
		"zoomout":
			if _elapsed > 12.0 and not ramping:
				fps_min_zoomout = minf(fps_min_zoomout, fps)
		"zoomext":
			if _elapsed > 32.0 and not ramping:
				fps_min_zoomext = minf(fps_min_zoomext, fps)

	_recount_t += delta
	if _recount_t >= 0.5:
		_recount_t = 0.0
		var vis := 0
		var tot := 0
		for n in get_tree().get_nodes_in_group("world_content"):
			tot += 1
			if n is CanvasItem and n.visible:
				vis += 1
		visible_count = vis
		total_group = tot

	_log_t += delta
	if _log_t >= 2.0:
		_log_t = 0.0
		var line := "[STRESS10K] t=%.0fs %s fps=%.0f vis=%d/%d zoom=%.3f" % [
			_elapsed, phase, fps, visible_count, total_group, cam_zoom]
		print(line)
		_push("info", line)


func _push(level: String, text: String) -> void:
	var rt := get_node_or_null("/root/MCPRuntime")
	if rt and rt.has_method("push_runtime_log"):
		rt.push_runtime_log(level, text)
