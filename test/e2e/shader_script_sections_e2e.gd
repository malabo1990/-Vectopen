# =============================================================================
# Shader y Script también en el panel derecho de Modern y Pro (antes solo en
# la ventana Efectos de Smart). Abre cada sección y comprueba que monta el
# panel real (editor de shaders / consola de scripts).
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/shader_script_sections_e2e.gd
# =============================================================================
extends SceneTree

const EXPECTED_CHECKS := 16
var checks := 0
var fails := 0

func _init() -> void:
	create_timer(150.0).timeout.connect(func(): print("WATCHDOG"); quit(2))
	_run.call_deferred()

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func check(ok: bool, what: String) -> void:
	checks += 1
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func _run() -> void:
	DisplayServer.window_set_current_screen(mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var api = load("res://script_gdscript/api/vectopen_api.gd").new(root)
	var gui = root.get_node("GlobalUI")
	var r = api.add_rect(Vector2(200, 200), Vector2(120, 80))
	for mode in ["modern", "professional"]:
		gui.set_ui_mode(mode)
		await frames(25)
		api.select([r])
		await frames(15)
		var host: Node = current_scene
		if mode == "professional":
			for n in current_scene.find_children("*", "", true, false):
				if n.has_method("_select_tab_b"):
					host = n          # el panel Pro (no las secciones ocultas de Modern)
					break
		var sh := host.find_child("SecShader", true, false)
		var sc := host.find_child("SecScript", true, false)
		check(sh != null and sc != null, "%s: secciones SHADER y SCRIPT existen" % mode)
		if sh == null or sc == null:
			checks += 6
			fails += 6
			continue
		if mode == "professional":
			# Pestaña «Efectos» del grupo inferior (Transformar · Texto · Efectos).
			if host.has_method("_select_tab_b"):
				host._select_tab_b(2)
			await frames(10)
		# UX-19: sin nada asignado, ocultas; se abren con su icono de la barra.
		check(not sh.is_visible_in_tree(), "%s: SHADER oculto sin shader asignado" % mode)
		check(not sc.is_visible_in_tree(), "%s: SCRIPT oculto hasta pulsar su icono" % mode)
		for id in ["shader", "script"]:
			for b in current_scene.find_children("Fx_" + id, "Button", true, false):
				if (b as Button).is_visible_in_tree():
					(b as Button).button_pressed = true
					break
			await frames(12)
		if not sh.is_open():
			sh._toggle()
		if not sc.is_open():
			sc._toggle()
		await frames(15)
		check(sh.find_child("ShaderContent", true, false) != null, "%s: SHADER monta el editor de shaders" % mode)
		check(sc.find_child("ScriptContent", true, false) != null, "%s: SCRIPT monta la consola de scripts" % mode)
		for sec in [sh, sc]:
			var cont: Control = sec.find_child("ShaderContent" if sec == sh else "ScriptContent", true, false)
			check(cont.get_combined_minimum_size().x <= sec.get_parent_control().size.x + 1, "%s: %s cabe a lo ancho del panel (%.0f px)" % [mode, sec.name, cont.get_combined_minimum_size().x])
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://sections_%s.png" % mode)
		for id in ["shader", "script"]:
			for b in current_scene.find_children("Fx_" + id, "Button", true, false):
				if (b as Button).is_visible_in_tree():
					(b as Button).button_pressed = false
		await frames(5)
	api.select([])
	await frames(5)
	check(checks == 14, "comprobaciones por modo completas")
	check(true, "fin")
	if checks != EXPECTED_CHECKS:
		print("FAIL checks=%d esperado=%d" % [checks, EXPECTED_CHECKS])
		fails += 1
	print("RESULT ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
