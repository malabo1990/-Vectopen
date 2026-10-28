# =============================================================================
# PRUEBA DE UI REAL: ancho del panel de Capas arrastrando su borde, y estilo
# del campo de renombrar una capa.
# Pedido del usuario: "línea izquierda puede drag para cambiar tamaño de panel
# (Smart) y en modern y pro es la derecha, entre panel y regla" y "al editar
# el nombre de una capa sale fondo negro y texto blanco… antes azul un poco
# transparente, elegante, estilo Apple".
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/panel_resize_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://panel_resize"
const LAYERS_CFG := "user://vectopen_layers_ui.cfg"
const UI_CFG := "user://vectopen_ui.cfg"
const EXPECTED_CHECKS := 35
var fails := 0
var checks := 0
var main: Control

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

func ev_move(at: Vector2, mask: int) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.button_mask = mask
	root.push_input(e)
	await process_frame

func ev_btn(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(e)
	await process_frame

## Arrastra el asa `dx` píxeles con eventos reales.
func drag_handle(h: Control, dx: float, what: String) -> void:
	var a := h.get_global_rect().get_center()
	await ev_move(a, 0)
	var hov := root.gui_get_hovered_control()
	check("%s: el asa del borde se puede coger" % what, hov == h, str(hov))
	await ev_btn(a, true)
	for i in 10:
		await ev_move(a + Vector2(dx * (i + 1) / 10.0, 0), MOUSE_BUTTON_MASK_LEFT)
	await ev_btn(a + Vector2(dx, 0), false)
	await frames(6)

func inner() -> Control:
	return main.find_child("Layout", true, false).get_node("PanelContainer") as Control

func _run() -> void:
	var cfg_backup := FileAccess.get_file_as_string(LAYERS_CFG) if FileAccess.file_exists(LAYERS_CFG) else ""
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	main = current_scene.find_child("main", true, false) as Control
	var gui = root.get_node("GlobalUI")
	var handle := main.find_child("LayersEdgeResizer", true, false) as Control

	# ── SMART: borde IZQUIERDO ──
	gui.set_ui_mode("smart")
	await frames(25)
	check("existe el asa del borde del panel", handle != null)
	if handle == null:
		print("RESULT: 1 FAIL")
		quit(1)
		return
	var p := inner()
	check("smart: el asa está en el borde izquierdo del panel", absf(handle.get_global_rect().get_center().x - p.get_global_rect().position.x) < 2.0,
		"%s vs %s" % [handle.get_global_rect(), p.get_global_rect()])
	var w0 := p.size.x
	await drag_handle(handle, -80.0, "smart")
	check("smart: arrastrar a la izquierda ensancha el panel (+80)", absf(p.size.x - (w0 + 80.0)) < 3.0, "%.0f → %.0f" % [w0, p.size.x])
	check("smart: el panel sigue pegado a la derecha", absf(p.get_global_rect().end.x - (root.get_visible_rect().size.x - 10.0)) < 3.0, str(p.get_global_rect()))
	await shot("1_smart_ancho")
	await drag_handle(handle, 2000.0, "smart (estrechar mucho)")
	check("smart: no baja del ancho mínimo", p.size.x >= 299.0, "%.0f" % p.size.x)
	await drag_handle(handle, -120.0, "smart")
	var smart_w := p.size.x

	# ── MODERN: borde DERECHO, la regla se aparta ──
	gui.set_ui_mode("modern")
	await frames(30)
	p = inner()
	check("modern: el asa está en el borde derecho del panel", absf(handle.get_global_rect().get_center().x - p.get_global_rect().end.x) < 2.0,
		"%s vs %s" % [handle.get_global_rect(), p.get_global_rect()])
	var rv := main.find_child("regla vertical", true, false) as Control
	var m0 := p.size.x
	var r0 := rv.get_global_rect().position.x
	await drag_handle(handle, 70.0, "modern")
	check("modern: arrastrar a la derecha ensancha el panel (+70)", absf(p.size.x - (m0 + 70.0)) < 3.0, "%.0f → %.0f" % [m0, p.size.x])
	check("modern: la regla se aparta con el panel", absf(rv.get_global_rect().position.x - (r0 + 70.0)) < 3.0, "%.0f → %.0f" % [r0, rv.get_global_rect().position.x])
	var corner := main.find_child("RulerCorner", true, false) as Control
	if corner and corner.is_visible_in_tree():
		check("modern: la esquina de las reglas se mueve con ellas", absf(corner.get_global_rect().position.x - rv.get_global_rect().position.x) < 2.0,
			"%s vs %s" % [corner.get_global_rect(), rv.get_global_rect()])
	await shot("2_modern_ancho")
	var modern_w := p.size.x

	# ── PRO ──
	gui.set_ui_mode("professional")
	await frames(30)
	p = inner()
	var pr0 := p.size.x
	await drag_handle(handle, 50.0, "pro")
	check("pro: arrastrar ensancha el panel (+50)", absf(p.size.x - (pr0 + 50.0)) < 3.0, "%.0f → %.0f" % [pr0, p.size.x])
	await shot("3_pro_ancho")

	# ── Se recuerda por modo ──
	gui.set_ui_mode("modern")
	await frames(30)
	check("modern: recuerda su ancho al volver", absf(inner().size.x - modern_w) < 3.0, "%.0f vs %.0f" % [inner().size.x, modern_w])
	gui.set_ui_mode("smart")
	await frames(30)
	check("smart: recuerda su ancho al volver", absf(inner().size.x - smart_w) < 3.0, "%.0f vs %.0f" % [inner().size.x, smart_w])

	# ── Ajustes de Capas (⚙) en Modern / Pro: por encima de las reglas ──
	for mode in ["modern", "professional"]:
		gui.set_ui_mode(mode)
		await frames(30)
		var gear: Button = null
		for c in root.find_children("Button", "Button", true, false):
			if c.text == "⚙" and c.tooltip_text.begins_with("Ajustes del panel") and c.is_visible_in_tree():
				gear = c
		check("%s: el ⚙ de Capas se ve" % mode, gear != null)
		if gear == null:
			continue
		var gc := gear.get_global_rect().get_center()
		await ev_move(gc, 0)
		await ev_btn(gc, true)
		await ev_btn(gc, false)
		await frames(8)
		var host := main.find_child("Configuracion de Capas", true, false) as Control
		check("%s: se abren los Ajustes de Capas" % mode, host != null and host.is_visible_in_tree())
		if host:
			var hr := host.get_global_rect()
			var rv2 := main.find_child("regla vertical", true, false) as Control
			var rh := main.find_child("regla horizontal", true, false) as Control
			check("%s: Ajustes no quedan bajo la regla vertical" % mode, not hr.intersects(rv2.get_global_rect()), "%s vs %s" % [hr, rv2.get_global_rect()])
			check("%s: Ajustes no quedan bajo la regla horizontal" % mode, not hr.intersects(rh.get_global_rect()), "%s vs %s" % [hr, rh.get_global_rect()])
			check("%s: Ajustes dentro de la ventana" % mode, root.get_visible_rect().encloses(hr), str(hr))
			# Se puede pulsar su contenido (nada lo tapa).
			var title_pt := hr.position + Vector2(hr.size.x * 0.5, 20)
			await ev_move(title_pt, 0)
			var hov := root.gui_get_hovered_control()
			check("%s: nada tapa los Ajustes" % mode, hov != null and (hov == host or host.is_ancestor_of(hov)), str(hov))
			await shot("5_%s_ajustes" % mode)
			host.visible = false
			await frames(3)

	# ── Renombrar una capa: campo azul translúcido (no negro) ──
	var ls = root.find_child("LayersSystem", true, false)
	var tree: Tree = ls.get("layer_tree")
	var it := tree.get_root().get_first_child() if tree.get_root() else null
	if it:
		tree.set_selected(it, 0)
		await frames(3)
		tree.edit_selected(true)
		await frames(6)
	var le: LineEdit = null
	for c in tree.find_children("*", "LineEdit", true, false):
		if (c as LineEdit).is_visible_in_tree():
			le = c
	check("renombrar: aparece el campo de edición", le != null)
	if le:
		var sb := le.get_theme_stylebox("normal") as StyleBoxFlat
		var bg: Color = sb.bg_color if sb else Color.BLACK
		var tm = root.get_node("ThemeManager")
		var acc: Color = tm.get_color(tm.Slot.ACCENT)
		check("renombrar: el fondo ya no es negro", bg.get_luminance() > 0.3 or tm.is_dark(), str(bg))
		check("renombrar: fondo teñido del azul de acento", bg.b >= bg.r, str(bg))
		check("renombrar: borde azul de acento", sb != null and sb.border_color.is_equal_approx(Color(acc, 0.85)))
		check("renombrar: esquinas redondeadas", sb != null and sb.corner_radius_top_left >= 4)
		var fc := le.get_theme_color("font_color")
		check("renombrar: texto legible sobre el fondo", absf(fc.get_luminance() - bg.get_luminance()) > 0.4, "%s / %s" % [fc, bg])
		await shot("4_renombrar")
		le.release_focus()
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.pressed = true
		le.get_viewport().push_input(ev)
		await frames(4)

	var f := FileAccess.open(LAYERS_CFG, FileAccess.WRITE)
	f.store_string(cfg_backup)
	f.close()
	if ui_backup != "":
		var f2 := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f2.store_string(ui_backup)
		f2.close()
	if checks < EXPECTED_CHECKS:
		check("el test hizo todas sus comprobaciones", false, "%d de %d" % [checks, EXPECTED_CHECKS])
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
