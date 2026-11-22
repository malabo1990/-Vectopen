## Cierre limpio: arranca la app y pide cerrar como la X de la ventana
## (NOTIFICATION_WM_CLOSE_REQUEST → camino normal de la app, con su aviso de
## cambios sin guardar). El registro no debe tener «leaked» ni errores.
##   test/run_e2e.sh clean_exit_e2e   (y revisar el registro tras «CLOSE»)
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()
	create_timer(120.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT (la app no se cerró)")
		quit(2))

func _run() -> void:
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	for i in 60:
		await process_frame
	# Nodos fuera del árbol que nadie libera (fugas al cerrar)
	var orphans: Array = Node.get_orphan_node_ids()
	print("ORPHANS %d" % orphans.size())
	for id in orphans:
		var n := instance_from_id(id) as Node
		if n == null:
			continue
		var top: Node = n
		while top.get_parent() != null:
			top = top.get_parent()
		if top == n or OS.has_environment("ORPHAN_ALL"):
			var sc: Script = n.get_script()
			print("ORPHAN raíz %s «%s» script=%s hijos=%d" % [n.get_class(), n.name, sc.resource_path if sc else "-", n.get_child_count(true)])
	print("CLOSE pidiendo cierre (como la X)")
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
