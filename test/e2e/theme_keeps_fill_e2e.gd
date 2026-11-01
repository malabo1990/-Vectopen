# =============================================================================
# Cambiar de tema (claro ↔ oscuro) con un objeto seleccionado NO debe tocar su
# relleno: antes el selector de color reaplicaba su color por defecto (azul)
# y borraba el degradado. Se prueba en los 3 modos de UI.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/theme_keeps_fill_e2e.gd
# =============================================================================
extends SceneTree

const EXPECTED_CHECKS := 12
var checks := 0
var fails := 0

func _init() -> void:
	create_timer(120.0).timeout.connect(func(): print("WATCHDOG"); quit(2))
	_run.call_deferred()

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("OK   ", what)
	else:
		fails += 1
		print("FAIL ", what)

func _trace(tag: String) -> void:
	for bt in Engine.capture_script_backtraces(false):
		print("TRACE ", tag, "\n", bt.format())

func _find_with(n: Node, prop: String) -> Node:
	if prop in n:
		return n
	for c in n.get_children():
		var r := _find_with(c, prop)
		if r:
			return r
	return null

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
	var tm = root.get_node("ThemeManager")
	var gui = root.get_node("GlobalUI")
	var start_mode: String = "dark" if tm.is_dark() else "light"
	var ic = root.get_node("InspectorCore")
	var tracing := [false]
	ic.changed.connect(func(p): if tracing[0]: print("IC.changed ", p.keys()); _trace("InspectorCore.changed"))
	for mode in ["smart", "modern", "professional"]:
		gui.set_ui_mode(mode)
		await frames(20)
		var g := Gradient.new()
		g.colors = PackedColorArray([Color("#ffd36b"), Color("#ff3d77")])
		var sh = api.add_ellipse(Vector2(200, 200), Vector2(120, 120), "ThemeProbe")
		sh.fill_color = Color("#22aa55")
		sh.fill_gradient = g
		api.select([sh])
		await frames(20)
		var fill_before: Color = sh.fill_color
		tracing[0] = true
		for t in ["dark", "light", "dark"]:
			tm.set_mode(t)
			await frames(15)
		tracing[0] = false
		check(sh.fill_gradient != null and sh.fill_gradient.get_point_count() >= 2, "%s: degradado intacto tras cambiar tema" % mode)
		check(sh.fill_color.is_equal_approx(fill_before), "%s: color de relleno intacto (%s → %s)" % [mode, fill_before.to_html(), sh.fill_color.to_html()])
		check(api.selection().has(sh), "%s: sigue seleccionado" % mode)
		api.clear_selection()
		sh.queue_free()
		await frames(5)
	# Capas: los nodos internos del efecto de texto (TextFxBack, CanvasGroup,
	# Sprite2D…) no deben salir como capas.
	var t = api.add_text(Vector2(40, 400), "Sombra", 48, Color.BLACK)
	api.add_effect(t, "Drop Shadow", {})
	await frames(40)
	var ls := _find_with(current_scene, "_node_to_item_map")
	var internos := []
	if ls:
		for n in ls._node_to_item_map.keys():
			if is_instance_valid(n) and t.is_ancestor_of(n):
				internos.append(String(n.name))
	check(ls != null and ls._node_to_item_map.has(t), "capas: el texto aparece")
	check(internos.is_empty(), "capas: sin nodos internos del efecto %s" % [internos])
	# El contador de Capas cuenta lo mismo que muestra el árbol.
	var en_arbol := 0
	for n in ls._node_to_item_map.keys():
		if is_instance_valid(n) and n is Node2D and not ls._es_artboard(n):
			en_arbol += 1
	ls._actualizar_contador()
	var lbl_txt: String = ls._contador_label.text if is_instance_valid(ls._contador_label) else ""
	check(lbl_txt.begins_with("%d " % en_arbol), "capas: contador «%s» = filas del árbol (%d)" % [lbl_txt, en_arbol])
	tm.set_mode(start_mode)
	await frames(5)
	if checks != EXPECTED_CHECKS:
		print("FAIL checks=%d esperado=%d" % [checks, EXPECTED_CHECKS])
		fails += 1
	print("RESULT ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
