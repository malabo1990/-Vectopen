# =============================================================================
# UX-21 — Con la pestaña «Efectos» de Pro FLOTANDO, los iconos Shader /
# Script / Vectorizar de la barra superior deben traerla a la vista:
#   · la ventana flotante se ve (no oculta ni minimizada) y entera en pantalla;
#   · la sección pedida está abierta y visible dentro de la ventana;
#   · volver a pulsar el icono la cierra.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/pro_float_effects_icons_e2e.gd
# =============================================================================
extends SceneTree

var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	root.push_input(mm)
	await process_frame
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.position = at
		mb.global_position = at
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(mb)
		await process_frame
	await frames(10)

func icon(id: String) -> Button:
	for n in root.find_children("Fx_" + id, "Button", true, false):
		if (n as Control).is_visible_in_tree():
			return n
	return null

func _run() -> void:
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("professional")
	await frames(30)
	var cv = get_first_node_in_group("_vectopen_canvas")
	var ab = cv.get_node("manager_script").get_active_artboard()
	var rect: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	ab.add_child(rect)
	rect.owner = ab
	rect.size = Vector2(120, 80)
	root.get_node("SelectionManager").set_selection([rect])
	await frames(10)
	var pro: Control = null
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == "ProStudio" and (n as Control).is_visible_in_tree():
			pro = n
	check("lateral de Pro", pro != null)
	if pro == null:
		print("RESULT: 1 FAIL")
		quit(1)
		return
	pro.float_tab("b", "Efectos")
	await frames(10)
	var vp := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	for id in ["shader", "script", "vectorize"]:
		var b := icon(id)
		check("icono %s" % id, b != null)
		if b == null:
			continue
		var win := pro.find_child("ProTab_Efectos", true, false) as Window
		check("%s: «Efectos» sigue flotando" % id, win != null)
		if win:
			# El usuario la había minimizado / tapado: el icono debe traerla.
			win.visible = false
		await click(b)
		win = pro.find_child("ProTab_Efectos", true, false) as Window
		check("%s: la ventana flotante se muestra" % id, win != null and win.visible)
		if win == null:
			continue
		var wr := Rect2(Vector2(win.position), Vector2(win.size))
		check("%s: la ventana cabe en la pantalla" % id, vp.grow(1.0).encloses(wr), "%s" % wr)
		var node: String = {"shader": "SecShader", "script": "SecScript", "vectorize": "SecVectorize"}[id]
		var sec := win.find_child(node, true, false) as Control
		check("%s: la sección está en la ventana y abierta" % id, sec != null and sec.is_visible_in_tree() and sec.is_open())
		if sec:
			var sr := sec.get_global_rect()
			var hdr := sec.get_node_or_null("Header") as Control
			var hr := hdr.get_global_rect() if hdr else sr
			check("%s: su cabecera está a la vista en la ventana" % id, Rect2(Vector2.ZERO, Vector2(win.size)).grow(1.0).encloses(hr), "%s en %s" % [hr, win.size])
		await click(b)
		check("%s: volver a pulsar la cierra" % id, sec == null or not sec.is_open() or not sec.is_visible_in_tree())
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
