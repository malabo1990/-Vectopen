## UX-07: seleccionar TODO en un documento con cientos de trazos de pincel
## (face.vtp) no debe bloquear la interfaz. Mide el fotograma más lento al
## pulsar Ctrl+A y la memoria tras 10 ciclos seleccionar/deseleccionar.
##   VTP_PATH=/ruta/face.vtp godot --path . --screen 1 -s res://test/perf/brush_selection_perf.gd
extends SceneTree

var fails: Array[String] = []
var _worst := 0
var _last := 0
var _measuring := false

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): printerr("WATCHDOG"); quit(2))
	_run.call_deferred()

func _process(_d: float) -> bool:
	var now := Time.get_ticks_msec()
	if _measuring and _last > 0:
		_worst = maxi(_worst, now - _last)
	_last = now
	return false

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("PERF OK   " if cond else "PERF FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _key(code: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.ctrl_pressed = ctrl
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame

func _count(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		c += 1 + _count(ch)
	return c

func _run() -> void:
	var path := OS.get_environment("VTP_PATH")
	DisplayServer.window_set_current_screen(mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(20)
	if path == "" or not FileAccess.file_exists(path):
		_check(false, "VTP_PATH apunta a face.vtp (%s)" % path)
		quit(1)
		return
	var t := Time.get_ticks_msec()
	root.get_node("SaveManager").open(path)
	await _frames(30)
	print("PERF abrir %d ms" % (Time.get_ticks_msec() - t))
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").api
	var ab: Node2D = api.artboard()
	# STRESS=N: duplica los trazos N-1 veces (p. ej. 4 → ~1000 trazos).
	var mult := maxi(1, int(OS.get_environment("STRESS")) if OS.get_environment("STRESS") != "" else 1)
	if mult > 1:
		var lines := ab.get_children().filter(func(c): return c is Line2D)
		for k in mult - 1:
			for l in lines:
				var d: Node2D = l.duplicate()
				d.position += Vector2(5 * (k + 1), 5 * (k + 1))
				ab.add_child(d)
		await _frames(5)
	var top := ab.get_children().filter(func(c): return c is Node2D).size()
	print("PERF capas de primer nivel=%d nodos=%d" % [top, _count(ab)])
	canvas.switch_tool("move")
	await _frames(5)
	var sm = root.get_node("SelectionManager")
	var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	for cycle in 10:
		_worst = 0
		_measuring = true
		var t0 := Time.get_ticks_msec()
		await _key(KEY_A, true)
		await _frames(10)
		_measuring = false
		var n_sel: int = sm.get_selected().size()
		print("PERF ciclo %d: seleccionados=%d fotograma más lento=%d ms total=%d ms" % [cycle, n_sel, _worst, Time.get_ticks_msec() - t0])
		if cycle == 0:
			_check(n_sel >= 250 * mult, "Ctrl+A selecciona los trazos (%d)" % n_sel)
			# Con ~1000 trazos, seleccionar TODO puede rozar los 100 ms; el
			# criterio (UX-07) es seleccionar ~389 con 1000 trazos: abajo.
			var lim := 100 if mult == 1 else 150
			_check(_worst < lim, "seleccionar todo no bloquea (peor fotograma %d ms < %d)" % [_worst, lim])
		_worst = 0
		_measuring = true
		await _key(KEY_ESCAPE)
		sm.clear()
		await _frames(6)
		_measuring = false
		if cycle == 0:
			_check(_worst < 100, "deseleccionar no bloquea (peor fotograma %d ms)" % _worst)
	# Criterio UX-07: 389 elementos seleccionados con el documento lleno.
	var some: Array = ab.get_children().filter(func(c): return c is Line2D).slice(0, 389)
	for cycle in 3:
		_worst = 0
		_measuring = true
		sm.set_selection(some)
		await _frames(10)
		_measuring = false
		print("PERF 389 elementos (ciclo %d): peor fotograma %d ms" % [cycle, _worst])
		if cycle == 0:
			_check(_worst < 100, "seleccionar 389 con %d trazos < 100 ms (%d ms)" % [top, _worst])
		sm.clear()
		await _frames(6)
	var mem1 := Performance.get_monitor(Performance.MEMORY_STATIC)
	print("PERF memoria %.1f MB → %.1f MB" % [mem0 / 1048576.0, mem1 / 1048576.0])
	_check(mem1 - mem0 < 64 * 1048576.0, "memoria estable tras 10 ciclos (+%.1f MB)" % ((mem1 - mem0) / 1048576.0))
	print("PERF RESULT %d fallos" % fails.size())
	quit(0 if fails.is_empty() else 1)
