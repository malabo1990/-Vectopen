## Perfil de SelectionManager.select con 300 figuras: tiempo por oyente.
##   godot --path . -s res://test/e2e/select_profile.gd
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(30)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var sm = root.get_node("SelectionManager")
	var ge = root.get_node("GlobalEvents")
	canvas.switch_tool("text")
	await _frames(3)
	var shapes: Array = []
	for i in 300:
		if not canvas.current_tool.has_method("create_at_center"):
			canvas.switch_tool("text")
		var s = canvas.current_tool.create_at_center()
		if s:
			s.position += Vector2((i % 20) * 60, (i / 20) * 40)
			shapes.append(s)
	canvas.switch_tool("move")
	await _frames(10)
	var t0 := Time.get_ticks_usec()
	for i in 20:
		sm.select(shapes[i])
	print("PROF total select: %.2f ms" % ((Time.get_ticks_usec() - t0) / 20000.0))
	var sigs := [[sm, "changed"], [sm, "active_changed"], [ge, "selection_changed"]]
	var arg_for := {"changed": [[shapes[5]]], "active_changed": [shapes[5]], "selection_changed": [[shapes[5]]]}
	for pair in sigs:
		var obj: Object = pair[0]
		var sig: String = pair[1]
		for c in obj.get_signal_connection_list(sig):
			var cb: Callable = c["callable"]
			var tt := Time.get_ticks_usec()
			for k in 10:
				cb.callv(arg_for[sig])
			var ms := (Time.get_ticks_usec() - tt) / 10000.0
			var tgt = cb.get_object()
			var tname: String = (tgt.get_script().resource_path.get_file() if tgt and tgt.get_script() else str(tgt))
			print("PROF %-18s %6.2f ms  %s.%s" % [sig, ms, tname, cb.get_method()])
	var ic = root.get_node("InspectorCore")
	var tt0 := Time.get_ticks_usec()
	for k in 10:
		ic._sync_selection()
	print("PROF ic._sync_selection %.2f ms" % ((Time.get_ticks_usec() - tt0) / 10000.0))
	tt0 = Time.get_ticks_usec()
	var props := {}
	for k in 10:
		props = ic.current_props()
	print("PROF ic.current_props %.2f ms" % ((Time.get_ticks_usec() - tt0) / 10000.0))
	for c in ic.get_signal_connection_list("changed"):
		var cb: Callable = c["callable"]
		var tt := Time.get_ticks_usec()
		for k in 10:
			cb.call(props)
		var tgt = cb.get_object()
		var tname: String = (tgt.get_script().resource_path.get_file() if tgt and tgt.get_script() else str(tgt))
		print("PROF ic.changed %6.2f ms  %s.%s" % [(Time.get_ticks_usec() - tt) / 10000.0, tname, cb.get_method()])
	quit(0)
