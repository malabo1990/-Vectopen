# Captura de los avisos (Dynamic Island) para revisar el diseño.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 -s res://tools/notice_shot.gd
extends SceneTree

func _init() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://notice_%s.png" % n)

func _run() -> void:
	DisplayServer.window_set_current_screen(mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	for i in 20: await process_frame
	var ge = root.get_node("GlobalEvents")
	ge.user_notice.emit("error", "La página «Pag 2» de «libro.vtp» está dañada y no se puede mostrar. Se conservará tal cual al guardar.")
	await create_timer(0.08).timeout
	await _shot("a_birth")
	await create_timer(0.9).timeout
	await _shot("b_open")
	ge.user_notice.emit("success", "Guardado «libro.vtp»")
	root.get_node("UserNotices")._dismiss_by_id(root.get_node("UserNotices")._current.get_instance_id())
	await create_timer(1.2).timeout
	await _shot("c_success")
	quit(0)
