# ==========================================
# RUTA: res://test/perf/profile_real.gd
# Perfil del JUEGO REAL: canvas.tscn + N figuras (VectorCircle). Pan
# determinista idéntico por etapa. Fuerza el panel del minimapa VISIBLE y
# compara el coste según su modo de refresco.
#   Godot res://test/perf/profile_real.tscn -- --count 800
# ==========================================
extends Node

const CANVAS := "res://scenes/canvas/canvas.tscn"
const START := Vector2(400, 560)
const MEASURE_S := 4.0
const WARM_S := 1.2

var count: int = 800
var zoom: float = 1.0
var _scene: Node = null
var _cam: Camera2D = null
var _artboard: Node2D = null
var _sv: SubViewport = null
var _phase := "load"
var _t := 0.0
var _fps: Array[float] = []
var _ft: Array[float] = []
var _draw: Array[float] = []
var _stage := 0

var STAGES := [
	"WARMUP (descartado)",
	"pan (estado real)",
	"pan (repetición, control de ruido)",
]


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--count" and i + 1 < a.size():
			count = int(a[i + 1])
		elif a[i] == "--zoom" and i + 1 < a.size():
			zoom = float(a[i + 1])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_scene = load(CANVAS).instantiate()
	add_child(_scene)
	get_tree().current_scene = _scene
	for _i in 4:
		await get_tree().process_frame
	_cam = _scene.get_node_or_null("Camera2D")
	_artboard = _scene.get_node_or_null("ArtboardsContainer/Artboard")
	_sv = _find_type(_scene, "SubViewport") as SubViewport
	if not _artboard:
		print("[PROFILE] ERROR sin artboard"); get_tree().quit(); return
	# panel del minimapa VISIBLE (así el throttle de vistaprevia.gd corre)
	var pv := _find_named(_scene, "Panel_PREVIEW")
	if pv and "visible" in pv: pv.visible = true
	var t_spawn := Time.get_ticks_msec()
	for i in count:
		var c := VectorCircle.new()
		c.fill_color = [Color.RED, Color.SKY_BLUE, Color.SEA_GREEN, Color.GOLD][i % 4]
		c.size = Vector2.ONE * (14.0 + float(i % 5) * 10.0)   # 14..54 px mundo
		c.position = Vector2(randf() * 780.0, randf() * 1100.0)
		_artboard.add_child(c)
	var spawn_ms := Time.get_ticks_msec() - t_spawn
	# esperar a que el panel de capas termine de sincronizar (batch de 100ms)
	var t_sync := Time.get_ticks_msec()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame
	var sync_ms := Time.get_ticks_msec() - t_sync
	print("[PROFILE] count=%d nodos=%d perfil=%s | spawn=%dms sync_capas=%dms" % [
		count, get_tree().get_node_count(), _profile(), spawn_ms, sync_ms])
	var nl := _find_named(_scene, "Numer layer")
	if nl and "text" in nl:
		print("[PROFILE] label 'Numer layer' = \"%s\"  (esperado ~%d)" % [nl.text, count])
	_begin()


func _profile() -> String:
	var pm = get_node_or_null("/root/PerformanceManager")
	return (pm.quality_preset if pm and "quality_preset" in pm else "?")


func _begin() -> void:
	Engine.max_fps = 0
	var pm = get_node_or_null("/root/PerformanceManager")
	if pm: pm.set_process(false)
	_phase = "measure"
	_t = 0.0
	_fps.clear(); _ft.clear(); _draw.clear()
	if _cam:
		_cam.position = START
		_cam.zoom = Vector2(zoom, zoom)


func _process(delta: float) -> void:
	if _phase != "measure":
		return
	_t += delta
	if _cam:
		var ang := _t * TAU * 0.5
		# pan proporcional al zoom: a más zoom, recorrido más corto en mundo
		_cam.position = START + Vector2(cos(ang), sin(ang)) * (900.0 / zoom)
	if _t > WARM_S:
		_fps.append(Engine.get_frames_per_second())
		_ft.append(delta * 1000.0)
		_draw.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if _t > WARM_S + MEASURE_S:
		_report()
		_advance()


func _avg(x: Array) -> float:
	if x.is_empty(): return 0.0
	var s := 0.0
	for v in x: s += v
	return s / x.size()

func _min(x: Array) -> float:
	if x.is_empty(): return 0.0
	var m: float = x[0]
	for v in x: m = minf(m, v)
	return m


func _report() -> void:
	print("[PROFILE] S%d %-38s fps_avg=%5.0f  fps_min=%5.0f  draw_avg=%5.0f" % [
		_stage, STAGES[_stage], _avg(_fps), _min(_fps), _avg(_draw)])


func _advance() -> void:
	_stage += 1
	if _stage >= STAGES.size():
		print("[PROFILE] === FIN ===")
		get_tree().quit()
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_begin()


func _find_named(root: Node, nm: String) -> Node:
	if root.name == nm: return root
	for c in root.get_children():
		var r := _find_named(c, nm)
		if r: return r
	return null

func _find_type(root: Node, cls: String) -> Node:
	if root.get_class() == cls: return root
	for c in root.get_children():
		var r := _find_type(c, cls)
		if r: return r
	return null
