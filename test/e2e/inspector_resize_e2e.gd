# =============================================================================
# UX-14 — Inspector redimensionable por arrastre (Modern y Pro) y lateral
# flotante en Pro. Con el ratón de verdad:
#   · arrastrar el borde izquierdo del lateral lo ensancha / estrecha sin
#     saltos (cada paso sigue al ratón), con mínimo y máximo;
#   · la regla y el lienzo se apartan (no quedan debajo del panel);
#   · el ancho se guarda POR MODO y se recupera al volver a ese modo;
#   · doble clic en el borde vuelve al ancho por defecto;
#   · Pro: el botón «Inspector flotante» lo saca a una ventana (mismo nodo,
#     misma pestaña), se puede cambiar su tamaño y al cerrarla vuelve a su
#     sitio con el ancho que tenía.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/inspector_resize_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const LAYERS_CFG := "user://vectopen_layers_ui.cfg"
const OUT := "user://inspector_resize"

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

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

func motion(at: Vector2, held := false) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.warp_mouse(at)
	root.push_input(mm)
	await process_frame

func button(at: Vector2, pressed: bool, dbl := false) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = at
	mb.global_position = at
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.double_click = dbl
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(mb)
	await process_frame

func manager() -> Node:
	return root.find_child("AdaptiveUIManager", true, false)

func panel(mode: String) -> Control:
	var want := "docked_inspector.gd" if mode == "modern" else "pro_studio.gd"
	for c in root.find_children("*", "Control", true, false):
		var s = c.get_script()
		if s and String(s.resource_path).get_file() == want:
			return c
	return null

func ruler_right() -> float:
	var r := root.find_child("regla horizontal", true, false) as Control
	return r.get_global_rect().end.x if r else -1.0

## Arrastra el borde izquierdo del panel `dx` píxeles, en pasos; devuelve el
## mayor «salto» entre lo que se movió el ratón y lo que cambió el ancho.
func drag_edge(p: Control, dx: float) -> float:
	var y := p.get_global_rect().position.y + p.size.y * 0.5
	var x := p.get_global_rect().position.x
	await motion(Vector2(x, y))
	var hit := root.gui_get_hovered_control()
	check("el borde del panel se puede agarrar", hit != null and String(hit.name) == "InspectorEdgeResizer", str(hit))
	await button(Vector2(x, y), true)
	var worst := 0.0
	var steps := 12
	for i in steps:
		var w0 := p.size.x
		x += dx / steps
		await motion(Vector2(x, y), true)
		await frames(1)
		var moved := w0 - p.size.x          # hacia la izquierda = más ancho
		if p.size.x > 241.0 and p.size.x < manager()._right_max_w() - 1.0:
			worst = maxf(worst, absf(moved - dx / steps))
	await button(Vector2(x, y), false)
	await frames(4)
	return worst

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	var lay_backup := FileAccess.get_file_as_string(LAYERS_CFG) if FileAccess.file_exists(LAYERS_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var gui = root.get_node("GlobalUI")
	var widths := {}
	for mode in ["modern", "professional"]:
		gui.set_ui_mode(mode)
		await frames(30)
		var p := panel(mode)
		check("%s: lateral derecho visible" % mode, p != null and p.is_visible_in_tree())
		if p == null:
			continue
		var w0 := p.size.x
		var jump := await drag_edge(p, -160.0)
		check("%s: arrastrar a la izquierda lo ensancha" % mode, p.size.x > w0 + 120.0, "%.0f → %.0f" % [w0, p.size.x])
		check("%s: el arrastre sigue al ratón sin saltos" % mode, jump <= 2.0, "salto máx. %.1f px" % jump)
		check("%s: la regla se aparta (no queda debajo)" % mode, absf(ruler_right() - p.get_global_rect().position.x) <= 2.0,
			"regla hasta %.0f, panel desde %.0f" % [ruler_right(), p.get_global_rect().position.x])
		await shot("%s_ancho" % mode)
		# Límites.
		await drag_edge(p, 900.0)
		check("%s: no baja del mínimo" % mode, p.size.x >= 239.0, "%.0f" % p.size.x)
		await drag_edge(p, -2000.0)
		var vw: float = root.get_visible_rect().size.x
		check("%s: no pasa del máximo" % mode, p.size.x <= vw * 0.6 + 1.0, "%.0f de %.0f" % [p.size.x, vw])
		# Un ancho concreto para comprobar que se guarda.
		await drag_edge(p, 400.0)
		await drag_edge(p, -(150.0 + 40.0 * int(mode == "professional")))
		widths[mode] = p.size.x
	# Por modo: volver a cada uno recupera SU ancho.
	for mode in ["modern", "professional"]:
		gui.set_ui_mode(mode)
		await frames(30)
		var p := panel(mode)
		if p and widths.has(mode):
			check("%s: recupera su ancho al volver" % mode, absf(p.size.x - float(widths[mode])) <= 2.0, "%.0f vs %.0f" % [p.size.x, widths[mode]])
	var cf := ConfigFile.new()
	cf.load(LAYERS_CFG)
	check("el ancho se guarda para la próxima sesión",
		absf(float(cf.get_value("panel", "inspector_width_modern", 0.0)) - float(widths.get("modern", -1.0))) <= 2.0,
		str(cf.get_value("panel", "inspector_width_modern", 0.0)))
	# Doble clic en el borde: ancho por defecto.
	gui.set_ui_mode("modern")
	await frames(30)
	var pm := panel("modern")
	var at := Vector2(pm.get_global_rect().position.x, pm.get_global_rect().get_center().y)
	await motion(at)
	await button(at, true, true)
	await button(at, false)
	await frames(6)
	check("modern: doble clic en el borde vuelve al ancho por defecto", absf(pm.size.x - 268.0) <= 2.0, "%.0f" % pm.size.x)

	# ── Pro: flotar y reacoplar ──────────────────────────────────────────────
	gui.set_ui_mode("professional")
	await frames(30)
	var pp := panel("professional")
	var m := manager()
	var docked_w := pp.size.x
	pp.call("_select_tab_b", 2)          # pestaña «Efectos»
	await frames(4)
	var btn := root.find_child("BtnFloatInspector", true, false) as Button
	check("pro: hay botón de inspector flotante", btn != null and btn.is_visible_in_tree())
	if btn:
		var c := btn.get_global_rect().get_center()
		await motion(c)
		await button(c, true)
		await button(c, false)
		await frames(10)
	var win := pp.get_parent() as Window
	check("pro: el lateral flota en su ventana (el mismo nodo)", m.is_inspector_floating() and win != null and is_instance_valid(pp), str(pp.get_parent()))
	check("pro: conserva la pestaña", int(pp.get("_tab_b")) == 2, str(pp.get("_tab_b")))
	check("pro: el lienzo ocupa el hueco (la regla llega al borde)", absf(ruler_right() - root.get_visible_rect().size.x) <= 2.0, "%.0f" % ruler_right())
	await shot("pro_flotante")
	if win:
		win.size = Vector2i(420, 600)        # el usuario la redimensiona
		await frames(6)
		check("pro: la ventana se puede redimensionar y el contenido la sigue", absf(pp.size.x - 420.0) <= 2.0, "%.0f" % pp.size.x)
		win.close_requested.emit()           # cerrar = reacoplar
		await frames(10)
	check("pro: al cerrar vuelve a su sitio", not m.is_inspector_floating() and pp.get_parent() is Control and pp.is_visible_in_tree())
	check("pro: con el ancho que tenía acoplado", absf(pp.size.x - docked_w) <= 2.0, "%.0f vs %.0f" % [pp.size.x, docked_w])
	check("pro: el botón se apaga", btn != null and not btn.button_pressed)
	if btn:
		var c2 := btn.get_global_rect().get_center()
		await motion(c2)
		await button(c2, true)
		await button(c2, false)
		await frames(10)
		var win2 := pp.get_parent() as Window
		check("pro: al volver a flotar recuerda el tamaño de la ventana", win2 != null and win2.size == Vector2i(420, 600), str(win2.size) if win2 else "")
	# Cambiar de modo con el lateral flotando lo reacopla.
	gui.set_ui_mode("modern")
	await frames(20)
	check("cambiar de modo reacopla el lateral de Pro", not m.is_inspector_floating() and not (pp.get_parent() is Window))
	gui.set_ui_mode("professional")
	await frames(20)
	check("pro: vuelve bien acoplado", pp.is_visible_in_tree() and absf(pp.size.x - docked_w) <= 2.0, "%.0f" % pp.size.x)
	await shot("pro_reacoplado")

	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	var f2 := FileAccess.open(LAYERS_CFG, FileAccess.WRITE)
	if f2:
		f2.store_string(lay_backup)
		f2.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
