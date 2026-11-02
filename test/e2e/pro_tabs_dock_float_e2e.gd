# =============================================================================
# UX-09 — Pro: pestañas del lateral reordenables y flotantes (como Affinity).
# Con el ratón de verdad (arrastrar y soltar de Godot):
#   · arrastrar «Efectos» sobre la mitad izquierda de «Transformar» la pone
#     primera; durante el arrastre se ve la marca de inserción; la pestaña
#     activa no cambia;
#   · arrastrar «Muestras» y soltarla sobre el lienzo la abre en una ventana
#     flotante con la MISMA página (no se recrea) y su botón desaparece;
#   · doble clic en la cabecera de la ventana la vuelve a acoplar (mismo nodo);
#   · el orden y las flotantes se guardan y se recuperan (reconstrucción del
#     lateral = como al reiniciar).
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/pro_tabs_dock_float_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const TABS_CFG := "user://vectopen_pro_tabs.cfg"
const OUT := "user://pro_tabs"

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

var _last_mouse := Vector2.ZERO

func motion(at: Vector2, held := false) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	# Godot detecta el arrastre sumando «relative» (con 0 nunca empieza).
	mm.relative = at - _last_mouse
	mm.screen_relative = mm.relative
	_last_mouse = at
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

## Arrastra de `a` a `b` como el ratón; `mid` se llama a mitad (marca).
func drag(a: Vector2, b: Vector2, mid: Callable = Callable()) -> void:
	await motion(a)
	await button(a, true)
	for i in 16:
		await motion(a.lerp(b, (i + 1) / 16.0), true)
		if i == 12 and mid.is_valid():
			await mid.call()
	await frames(2)
	await button(b, false)
	await frames(8)

func studio() -> Control:
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == "ProStudio":
			return n
	return null

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	var tabs_backup := FileAccess.get_file_as_string(TABS_CFG) if FileAccess.file_exists(TABS_CFG) else ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TABS_CFG))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
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
	var ps := studio()
	check("lateral Pro visible", ps != null and ps.is_visible_in_tree())
	if ps == null:
		_finish(ui_backup, tabs_backup)
		return
	# ── Reordenar ────────────────────────────────────────────────────────────
	ps._select_tab_b(1)                 # activa: «Texto»
	await frames(4)
	var active_page = ps._pages_b[1]
	var fx := ps._tab_button("b", "Efectos") as Button
	var tr_ := ps._tab_button("b", "Transformar") as Button
	var marker_seen := [false]
	await drag(fx.get_global_rect().get_center(), tr_.get_global_rect().position + Vector2(4, tr_.size.y * 0.5),
		func() -> void:
			var m = ps.get("_drop_marker")
			marker_seen[0] = m != null and (m as Control).visible)
	check("durante el arrastre se ve la marca de inserción", marker_seen[0])
	check("arrastrar reordena (Efectos primero)", ps.tab_order("b") == ["Efectos", "Transformar", "Texto"], str(ps.tab_order("b")))
	check("la pestaña activa no cambia", ps._tab_b == 1 and active_page.visible, "tab_b=%d" % ps._tab_b)
	await shot("reordenado")
	# ── Flotar ───────────────────────────────────────────────────────────────
	var mu := ps._tab_button("a", "Muestras") as Button
	var page_mu = ps._pages_a[1]
	var page_id: int = page_mu.get_instance_id()
	var canvas_at := Vector2(root.get_visible_rect().size.x * 0.45, root.get_visible_rect().size.y * 0.5)
	await drag(mu.get_global_rect().get_center(), canvas_at)
	await frames(6)
	check("soltar fuera la deja flotando", ps.is_tab_floating("Muestras"))
	var win := root.find_child("ProTab_Muestras", true, false) as Window
	check("en su ventana, con la MISMA página", win != null and is_instance_valid(page_mu) and page_mu.get_instance_id() == page_id and win.is_ancestor_of(page_mu))
	check("la página se ve en la ventana", is_instance_valid(page_mu) and page_mu.is_visible_in_tree())
	check("su botón ya no está en la tira", not mu.visible)
	await shot("flotante")
	# ── Persistencia: reconstruir el lateral (como al reiniciar) ────────────
	ps._rebuild()
	await frames(12)
	ps = studio()
	check("tras reconstruir conserva el orden", ps.tab_order("b") == ["Efectos", "Transformar", "Texto"], str(ps.tab_order("b")))
	check("tras reconstruir sigue flotando", ps.is_tab_floating("Muestras"))
	win = root.find_child("ProTab_Muestras", true, false) as Window
	check("la ventana flotante vuelve con su nombre", win != null)
	# ── Reacoplar con doble clic ─────────────────────────────────────────────
	if win:
		var page_now = ps._pages_a[1]
		var hdr := win.find_child("DockHeader", true, false) as Control
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.double_click = true
		hdr.gui_input.emit(ev)
		await frames(8)
		check("doble clic la vuelve a acoplar", not ps.is_tab_floating("Muestras") and (ps._tab_button("a", "Muestras") as Button).visible)
		check("acoplada con el mismo nodo de página", is_instance_valid(page_now) and ps._pages_a[1] == page_now and not (page_now.get_parent() is Window) and page_now.is_visible_in_tree())
	var cf := ConfigFile.new()
	cf.load(TABS_CFG)
	check("lo guardado: orden y ninguna flotante", str(cf.get_value("order", "b", [])) == str(["Efectos", "Transformar", "Texto"]) and (cf.get_value("float", "tabs", {}) as Dictionary).is_empty(), "%s / %s" % [cf.get_value("order", "b", []), cf.get_value("float", "tabs", {})])
	await shot("reacoplado")
	_finish(ui_backup, tabs_backup)

func _finish(ui_backup: String, tabs_backup: String) -> void:
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	if tabs_backup != "":
		var f2 := FileAccess.open(TABS_CFG, FileAccess.WRITE)
		f2.store_string(tabs_backup)
		f2.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TABS_CFG))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
