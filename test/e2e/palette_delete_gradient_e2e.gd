# =============================================================================
# UX-03 — Muestras guardadas: borrar con clic derecho y guardar degradados.
# En el selector de color (Modern), con clics reales:
#   · «+» guarda un color plano y, con un degradado activo, el DEGRADADO;
#   · clic derecho en una muestra → menú con Eliminar / Duplicar;
#   · Eliminar la quita; Ctrl+Z la recupera;
#   · si algún objeto usa la muestra, se pide confirmación antes;
#   · tras «reiniciar» (cargar de disco en un selector nuevo) el degradado
#     está y, al pulsarlo, se aplica IDÉNTICO (tipo y puntos);
#   · los selectores de los otros modos ven los mismos cambios.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/palette_delete_gradient_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const PAL_CFG := "user://vectopen_palette.cfg"

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

func motion(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.warp_mouse(at)
	root.push_input(mm)
	await process_frame

func button(at: Vector2, pressed: bool, which := MOUSE_BUTTON_LEFT) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = at
	mb.global_position = at
	mb.button_index = which
	mb.pressed = pressed
	mb.button_mask = (MOUSE_BUTTON_MASK_LEFT if which == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	root.push_input(mb)
	await process_frame

func click(c: Control, what: String, which := MOUSE_BUTTON_LEFT) -> void:
	if c == null or not c.is_visible_in_tree():
		check("se puede pulsar " + what, false, "no visible")
		return
	var at := c.get_global_rect().get_center()
	await motion(at)
	var hit := root.gui_get_hovered_control()
	check("se puede pulsar " + what, hit == c or (hit != null and c.is_ancestor_of(hit)), str(hit))
	await button(at, true, which)
	await button(at, false, which)
	await frames(6)

func is_cls(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls

func artboard() -> Node:
	var c = get_first_node_in_group("_vectopen_canvas")
	var m = c.get_node_or_null("manager_script") if c else null
	return m.get_active_artboard() if m and m.has_method("get_active_artboard") else null

func visible_picker() -> Control:
	for n in root.find_children("*", "", true, false):
		if is_cls(n, "GestorColor") and (n as Control).is_visible_in_tree():
			return n
	return null

func swatch(grid: Node, i: int) -> Control:
	for c in grid.get_children():
		if int(c.get_meta("swatch_index", -1)) == i:
			return c
	return null

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	var pal_backup := FileAccess.get_file_as_string(PAL_CFG) if FileAccess.file_exists(PAL_CFG) else ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PAL_CFG))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("modern")
	await frames(30)
	var ab := artboard()
	var rect: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.name = "Rect paleta"
	ab.add_child(rect)
	rect.owner = ab
	rect.size = Vector2(200, 140)
	rect.position = Vector2(300, 300)
	rect.fill_color = Color(0.3, 0.6, 0.9)
	var sm = root.get_node("SelectionManager")
	sm.set_selection([rect])
	await frames(8)
	var di := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "DockedInspector"))
	await click(di[0].picker_fill, "muestra de relleno")
	var pk := visible_picker()
	check("selector abierto", pk != null)
	if pk == null:
		_finish(ui_backup, pal_backup)
		return
	var grid = pk.find_child("GridContainer_palette_Color", true, false)
	check("rejilla de muestras vacía al empezar", grid.saved.is_empty(), str(grid.saved.size()))
	# 1) Color plano.
	pk.establecer_color(Color(0.9, 0.1, 0.2), true)
	await frames(4)
	await click(grid.add_button, "«+» (color)")
	check("«+» guarda el color plano", grid.saved.size() == 1 and grid.saved[0] is Color, str(grid.saved))
	# 2) Degradado.
	await click(pk.tab_linear, "pestaña degradado lineal")
	check("el rectángulo tiene degradado", rect.has_gradient_fill())
	await click(grid.add_button, "«+» (degradado)")
	var g_entry = grid.saved[grid.saved.size() - 1] if grid.saved.size() > 0 else null
	check("«+» guarda el DEGRADADO (con sus puntos)", g_entry is Dictionary and (g_entry["stops"] as Array).size() >= 2 and String(g_entry["type"]) == "linear", str(g_entry))
	check("la muestra del degradado se dibuja como degradado", swatch(grid, 1) is TextureRect)
	# 3) Clic derecho → Eliminar (no está en uso) y deshacer.
	await click(swatch(grid, 0), "clic derecho en el color", MOUSE_BUTTON_RIGHT)
	var menu = grid.get("_menu")
	check("clic derecho abre el menú", menu != null and (menu as PopupMenu).visible)
	if menu:
		check("el menú ofrece Eliminar y Duplicar", (menu as PopupMenu).get_item_text(0) == tr("Eliminar") and (menu as PopupMenu).get_item_text(1) == tr("Duplicar"))
		(menu as PopupMenu).hide()
		(menu as PopupMenu).id_pressed.emit(0)
		await frames(4)
	check("Eliminar quita la muestra", grid.saved.size() == 1 and grid.saved[0] is Dictionary, str(grid.saved.size()))
	root.get_node("HistoryManager").undo()
	await frames(4)
	check("deshacer recupera la muestra borrada", grid.saved.size() == 2 and grid.saved[0] is Color, str(grid.saved.size()))
	# 4) En uso → confirmación.
	rect.stroke_color = grid.saved[0]
	rect.stroke_width = 4.0
	await click(swatch(grid, 0), "clic derecho en el color en uso", MOUSE_BUTTON_RIGHT)
	menu = grid.get("_menu")
	if menu:
		(menu as PopupMenu).hide()
		(menu as PopupMenu).id_pressed.emit(0)
		await frames(4)
	var dlg = grid.get("_confirm")
	check("si está en uso pide confirmación", dlg != null and (dlg as Window).visible and grid.saved.size() == 2)
	if dlg:
		(dlg as ConfirmationDialog).get_ok_button().pressed.emit()
		await frames(4)
	check("al confirmar se elimina", grid.saved.size() == 1, str(grid.saved.size()))
	# 5) Duplicar.
	await click(swatch(grid, 0), "clic derecho en el degradado", MOUSE_BUTTON_RIGHT)
	menu = grid.get("_menu")
	if menu:
		(menu as PopupMenu).hide()
		(menu as PopupMenu).id_pressed.emit(1)
		await frames(4)
	check("Duplicar añade una copia", grid.saved.size() == 2 and str(grid.saved[0]) == str(grid.saved[1]))
	# 6) Otros modos ven lo mismo.
	var others := 0
	for g in get_nodes_in_group("palette_save_grid"):
		if g != grid and g.saved.size() == grid.saved.size():
			others += 1
	check("los selectores de los otros modos ven los mismos cambios", others >= 1, str(get_nodes_in_group("palette_save_grid").size()))
	# 7) «Reinicio»: se carga de disco y se reaplica idéntico.
	var loaded: Array = load("res://script_gdscript/ui/PaletteSaveGrid.gd").load_entries()
	check("tras reiniciar el degradado sigue guardado", loaded.size() == 2 and loaded[0] is Dictionary and str(loaded[0]["stops"]) == str(g_entry["stops"]), str(loaded.size()))
	rect.fill_color = Color(0.5, 0.5, 0.5)
	sm.set_selection([rect])
	await frames(6)
	await click(pk.tab_solid, "pestaña sólido")
	pk = visible_picker()
	if pk:
		grid = pk.find_child("GridContainer_palette_Color", true, false)
		await click(swatch(grid, 0), "muestra de degradado")
	var fp = root.get_node("InspectorCore")._read(rect, "fill_paint")
	check("el degradado guardado se aplica idéntico", fp is Dictionary and String(fp.get("type")) == "linear" and str(fp.get("stops")) == str(g_entry["stops"]), str(fp))
	rect.queue_free()
	_finish(ui_backup, pal_backup)

func _finish(ui_backup: String, pal_backup: String) -> void:
	await frames(2)
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	if pal_backup != "":
		var f2 := FileAccess.open(PAL_CFG, FileAccess.WRITE)
		f2.store_string(pal_backup)
		f2.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PAL_CFG))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
