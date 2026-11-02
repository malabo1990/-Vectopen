# =============================================================================
# UX-03: modos de vista del panel de PÁGINAS (Simple, Pliegos, Rejilla) con
# documentos de 1, 2, 5 y 8 páginas. Clics reales en los botones de modo.
#   · Pliegos: la portada sola (a la derecha) y luego 2‑3, 4‑5…; con nº par
#     de páginas la última queda sola a la izquierda;
#   · Rejilla: las columnas llenan el ancho del panel y siguen su ancho;
#   · cambiar de modo no pierde la selección ni el desplazamiento;
#   · el modo se recuerda (otra instancia del panel lo carga).
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/pages_panel_modes_e2e.gd
# =============================================================================
extends SceneTree

const PREFS := "user://vectopen_pages.cfg"
const LAYERS_CFG := "user://vectopen_layers_ui.cfg"
const OUT := "user://pages_panel_modes"
var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _send(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		Input.warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await process_frame

func click(c: Control, what: String) -> void:
	var at := c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = at
	mv.global_position = at
	await _send(mv)
	var hit := root.gui_get_hovered_control()
	check("se puede pulsar " + what, hit == c or (hit != null and c.is_ancestor_of(hit)), str(hit))
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		e.global_position = at
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		await _send(e)
	await frames(3)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

## Deja el documento con `n` páginas.
func set_pages(api, panel, n: int) -> void:
	var ps: Array = panel.pages()
	while ps.size() < n:
		api.add_artboard(Vector2(794, 1123), "Página")
		ps = panel.pages()
	if ps.size() > n:
		api.delete(ps.slice(n))
	await frames(4)
	panel.refresh()
	await frames(2)

func same_row(a: Rect2, b: Rect2) -> bool:
	return absf(a.position.y - b.position.y) < 0.5

func check_spread(panel, n: int) -> void:
	var r: Array = []
	for i in n:
		r.append(panel._cell_rect(i))
	var mid: float = panel.grid.size.x * 0.5
	check("pliego %d pág.: la portada va sola y a la derecha" % n,
		r[0].position.x >= mid - 1.0 and (n == 1 or not same_row(r[0], r[1])))
	var ok := true
	var i := 1
	while i < n:
		if i + 1 < n:
			# par a la izquierda, impar a la derecha, en la misma fila
			ok = ok and same_row(r[i], r[i + 1]) and r[i].end.x <= mid + 1.0 and r[i + 1].position.x >= mid - 1.0
			if i + 2 < n:
				ok = ok and not same_row(r[i + 1], r[i + 2])
		else:
			ok = ok and r[i].end.x <= mid + 1.0 and not same_row(r[i - 1], r[i])
		i += 2
	check("pliego %d pág.: emparejamiento 2‑3, 4‑5… correcto hasta el final" % n, ok)

func _run() -> void:
	var prefs_backup := FileAccess.get_file_as_string(PREFS) if FileAccess.file_exists(PREFS) else ""
	var layers_backup := FileAccess.get_file_as_string(LAYERS_CFG) if FileAccess.file_exists(LAYERS_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(20)
	var api = root.get_node("PluginManager").api
	var ls = current_scene.find_child("LayersSystem", true, false)
	ls._switch_left_tab("paginas")
	await frames(10)
	var panel = current_scene.find_child("PagesPanel", true, false)
	check("panel de páginas visible", panel != null and panel.is_visible_in_tree())
	if panel == null:
		_finish(prefs_backup, layers_backup)
		return
	var b_simple: Button = panel.find_child("ModeSimple", true, false)
	var b_spread: Button = panel.find_child("ModeSpread", true, false)
	var b_grid: Button = panel.find_child("ModeGrid", true, false)
	check("hay botones de los tres modos", b_simple != null and b_spread != null and b_grid != null)
	if b_simple == null or b_spread == null or b_grid == null:
		_finish(prefs_backup, layers_backup)
		return

	for n in [1, 2, 5, 8]:
		await set_pages(api, panel, n)
		check("documento de %d páginas" % n, panel.pages().size() == n, str(panel.pages().size()))
		await click(b_spread, "Pliegos (%d pág.)" % n)
		check("modo pliegos activo (%d pág.)" % n, panel.view_mode == 1 and b_spread.button_pressed)
		check_spread(panel, n)
		await shot("pliegos_%d" % n)
		await click(b_grid, "Rejilla (%d pág.)" % n)
		check("modo rejilla activo (%d pág.)" % n, panel.view_mode == 2 and b_grid.button_pressed)
		await click(b_simple, "Simple (%d pág.)" % n)
		check("modo simple activo (%d pág.)" % n, panel.view_mode == 0 and b_simple.button_pressed)

	# Rejilla: columnas que llenan el ancho y siguen el ancho del panel.
	await set_pages(api, panel, 8)
	await click(b_grid, "Rejilla")
	var zoom: HSlider = panel.find_child("ThumbSize", true, false)
	for cols in [2, 4]:
		zoom.value = cols
		await frames(3)
		var r0: Rect2 = panel._cell_rect(0)
		var rl: Rect2 = panel._cell_rect(cols - 1)
		var used: float = rl.end.x - r0.position.x
		check("rejilla de %d columnas llena el ancho del panel" % cols,
			same_row(r0, rl) and not same_row(r0, panel._cell_rect(cols)) and used >= panel.grid.size.x - 24.0 and used <= panel.grid.size.x + 0.5,
			"%.0f de %.0f px" % [used, panel.grid.size.x])
	await shot("rejilla")
	var w_before: float = panel._cell_rect(0).size.x
	var sc: ScrollContainer = panel._scroll
	var old_min: float = panel.custom_minimum_size.x
	var host := panel.get_parent() as Control
	var host_w: float = host.size.x if host else 0.0
	panel.grid.size.x = panel.grid.size.x * 0.6
	panel._relayout()
	check("la miniatura de la rejilla se ajusta al ancho del panel", panel._cell_rect(0).size.x < w_before - 4.0,
		"%.0f → %.0f" % [w_before, panel._cell_rect(0).size.x])
	panel._relayout.call_deferred()
	await frames(4)

	# Cambiar de modo conserva selección y desplazamiento.
	await set_pages(api, panel, 40)
	await click(b_simple, "Simple")
	panel.go_to_page(30)
	await frames(4)
	var sel_before: Array = panel._selected_in_order()
	for m in [b_spread, b_grid, b_simple, b_spread]:
		await click(m, "modo «%s»" % m.name)
		var vr: Vector2i = panel._visible_range()
		check("tras «%s» sigue seleccionada la página 31" % m.name, panel._selected_in_order() == sel_before)
		check("tras «%s» la página 31 sigue a la vista" % m.name, vr.x <= 30 and 30 <= vr.y, "%d‑%d" % [vr.x + 1, vr.y + 1])

	# Persistencia: otra instancia del panel carga el modo guardado.
	var cf := ConfigFile.new()
	cf.load(PREFS)
	check("el modo se guarda en las preferencias", String(cf.get_value("pages", "view_mode", "")) == "spread")
	var other = load("res://script_gdscript/ui/panels/pages/pages_panel.gd").new()
	root.add_child(other)
	await frames(2)
	check("un panel nuevo (otra sesión) abre en Pliegos", other.view_mode == 1 and (other.find_child("ModeSpread", true, false) as Button).button_pressed)
	other.queue_free()
	await set_pages(api, panel, 1)
	_finish(prefs_backup, layers_backup)

func _finish(prefs_backup: String, layers_backup: String) -> void:
	for pair in [[PREFS, prefs_backup], [LAYERS_CFG, layers_backup]]:
		if pair[1] != "":
			var f := FileAccess.open(pair[0], FileAccess.WRITE)
			if f:
				f.store_string(pair[1])
		elif FileAccess.file_exists(pair[0]) and pair[0] == PREFS:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("RESULT: %s (%d fallos)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
