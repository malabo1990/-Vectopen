# =============================================================================
# PRUEBA DE INTERFAZ REAL de la pestaña Recursos (con ventana, ratón
# simulado). Usa una biblioteca temporal: la del usuario no se toca.
#   flatpak run --command=godot org.godotengine.Godot --path . \
#       -s res://test/e2e/assets_ui_e2e.gd
# =============================================================================
extends SceneTree

const Lib = preload("res://script_gdscript/system/asset_library.gd")
const VX = preload("res://script_gdscript/system/vector_export.gd")
var api
var fails := 0
var _mouse := Vector2.ZERO

func _init() -> void:
	_run.call_deferred()

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func move(to: Vector2, mask: int = 0) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = to - _mouse
	ev.button_mask = mask
	_mouse = to
	root.push_input(ev)
	await process_frame

func button(at: Vector2, pressed: bool, dbl: bool = false, btn: int = MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = at
	ev.global_position = at
	ev.button_index = btn
	ev.pressed = pressed
	ev.double_click = dbl
	ev.button_mask = (MOUSE_BUTTON_MASK_LEFT if btn == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	root.push_input(ev)
	await process_frame

func click(at: Vector2, btn: int = MOUSE_BUTTON_LEFT) -> void:
	await move(at)
	await button(at, true, false, btn)
	await button(at, false, false, btn)
	await frames(2)

func double_click(at: Vector2) -> void:
	await click(at)
	await move(at)
	await button(at, true, true)
	await button(at, false)
	await frames(3)

func drag(from: Vector2, to: Vector2, steps: int = 12) -> void:
	await move(from)
	await button(from, true)
	for i in range(1, steps + 1):
		await move(from.lerp(to, float(i) / steps), MOUSE_BUTTON_MASK_LEFT)
	await frames(2)
	await button(to, false)
	await frames(4)

func _wipe(d: String) -> void:
	for sub in DirAccess.get_directories_at(d):
		_wipe(d.path_join(sub))
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))
	DirAccess.remove_absolute(d)

func center_of(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

var _kept := {}

func _run() -> void:
	for k in ["user://vectopen_layers_ui.cfg", "user://vectopen_assets_ui.cfg"]:
		if FileAccess.file_exists(k):
			_kept[k] = FileAccess.get_file_as_string(k)
	var dir := ProjectSettings.globalize_path("user://assets_ui_e2e")
	DirAccess.make_dir_recursive_absolute(dir)
	_wipe(dir)   # siempre desde cero (una ejecución cortada deja restos)
	DirAccess.make_dir_recursive_absolute(dir)
	Lib._root_override = dir.path_join("lib")
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await frames(90)
	api = root.get_node("PluginManager").api
	for c in api.shapes():
		c.get_parent().remove_child(c)
	var star = api.add_star(Vector2(300, 300), 60, 5)
	star.fill_color = Color(1, 0.75, 0.1)
	var rect = api.add_rect(Vector2(500, 300), Vector2(120, 80), 10)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var ab = api.artboard()
	var to_screen := func(p: Vector2) -> Vector2: return canvas.get_viewport().get_canvas_transform() * ab.to_global(p)

	# 1. pestaña Recursos con clic
	var tab: Button = root.find_child("TabRecursos", true, false)
	check("existe la pestaña Recursos", tab != null and tab.is_visible_in_tree())
	await click(center_of(tab))
	await frames(4)
	var panel = root.find_child("RecursosPanel", true, false)
	check("clic en Recursos muestra el panel", panel != null and panel.is_visible_in_tree())

	# 2. guardar la selección con el botón (sección activa = General)
	api.select([star])
	await frames(2)
	await click(center_of(panel._add_btn))
	await frames(4)
	var gen: String = panel.current_sub
	var g_gen: ItemList = panel.grid_of(gen)
	check("«+ Selección» añade un recurso con miniatura", g_gen.item_count == 1 and g_gen.get_item_icon(0) != null, str(g_gen.item_count))

	# 3. arrastrar el recurso al artboard → queda centrado donde se suelta
	var n0: int = api.shapes().size()
	var item_pos: Vector2 = g_gen.get_global_transform() * g_gen.get_item_rect(0).get_center()
	var target: Vector2 = to_screen.call(Vector2(200, 650))
	await drag(item_pos, target)
	await frames(4)
	check("arrastrar recurso al artboard lo coloca", api.shapes().size() == n0 + 1, "%d→%d" % [n0, api.shapes().size()])
	if api.shapes().size() == n0 + 1:
		var box: Rect2 = VX.bounds(VX.collect(ab, true, [api.shapes()[-1]]))
		check("…centrado donde se soltó", box.get_center().distance_to(Vector2(200, 650)) < 3.0, str(box.get_center()))

	# 4. doble clic → al centro; Ctrl+Z lo deshace
	n0 = api.shapes().size()
	await double_click(item_pos)
	await frames(3)
	check("doble clic en un recurso lo coloca", api.shapes().size() == n0 + 1, "%d→%d" % [n0, api.shapes().size()])
	var ev := InputEventKey.new()
	ev.keycode = KEY_Z
	ev.ctrl_pressed = true
	ev.pressed = true
	await move(target)
	root.push_input(ev)
	await frames(3)
	check("Ctrl+Z deshace la colocación", api.shapes().size() == n0, "%d" % api.shapes().size())

	# 5. ORGANIZAR: tres recursos más en General, otra sección «Clientes»
	for n in ["B", "C"]:
		api.select([rect])
		panel.add_selection(n, gen)
	var cli: String = Lib.add_subcategory(panel.current_cat, "Clientes")
	panel.refresh()
	await frames(4)
	var names := func(sub: String) -> Array: return (Lib.subcategory(sub)["items"] as Array).map(func(i) -> String: return i["name"])
	check("sección nueva visible", panel.section(cli) != null)
	# 5a. reordenar dentro de la sección: arrastrar «C» sobre el primero
	g_gen = panel.grid_of(gen)
	var p_first: Vector2 = g_gen.get_global_transform() * g_gen.get_item_rect(0).get_center()
	var p_c: Vector2 = g_gen.get_global_transform() * g_gen.get_item_rect(2).get_center()
	await drag(p_c, p_first)
	await frames(4)
	check("arrastrar para reordenar dentro de la sección", names.call(gen)[0] == "C", str(names.call(gen)))
	# 5b. mover a otra sección soltando en su cuadrícula
	g_gen = panel.grid_of(gen)
	var g_cli: ItemList = panel.grid_of(cli)
	await drag(g_gen.get_global_transform() * g_gen.get_item_rect(0).get_center(), center_of(g_cli))
	await frames(4)
	check("arrastrar a otra sección lo mueve", names.call(cli) == ["C"] and not ("C" in names.call(gen)), "%s | %s" % [names.call(gen), names.call(cli)])
	# 5c. mover soltando en la CABECERA de la sección
	g_gen = panel.grid_of(gen)
	await drag(g_gen.get_global_transform() * g_gen.get_item_rect(0).get_center(), center_of(panel.header_of(cli)))
	await frames(4)
	check("soltar en la cabecera de una sección lo mueve ahí", names.call(cli).size() == 2, str(names.call(cli)))
	# 5d. reordenar secciones arrastrando la cabecera
	await drag(center_of(panel.header_of(cli)), center_of(panel.header_of(gen)))
	await frames(4)
	var order: Array = (Lib.category(panel.current_cat)["subs"] as Array).map(func(x) -> String: return x["name"])
	check("arrastrar cabecera reordena las secciones", order[0] == "Clientes", str(order))
	# 5e. plegar con clic en la cabecera (y se recuerda)
	await click(center_of(panel.header_of(cli)))
	await frames(4)
	check("clic en la cabecera pliega la sección", not panel.grid_of(cli).visible and bool(Lib.subcategory(cli)["collapsed"]))
	await click(center_of(panel.header_of(cli)))
	await frames(4)
	check("otro clic la despliega", panel.grid_of(cli).visible)

	# 6. zoom de miniaturas
	panel._zoom.value = 96
	await frames(2)
	check("el zoom cambia el tamaño de las miniaturas", panel.grid_of(gen).fixed_icon_size == Vector2i(96, 96))
	panel._zoom.value = 56

	# 7. fila de Exportar → sección (parte visible: Exportar tapa la de abajo)
	root.get_node("GlobalEvents").emit_safe("request_export_dialog")
	await frames(10)
	var rows = root.find_child("ExportRows", true, false)
	rows.set_scope("layers")
	await frames(4)
	var ep: Control = root.find_child("Panel_export", true, false)
	var hdr: Control = panel.header_of(cli)
	var before: int = names.call(cli).size()
	if hdr.get_global_rect().position.y < ep.get_global_rect().position.y:
		var r0: Control = rows.rows()[0]
		await drag(center_of(r0) - Vector2(r0.size.x * 0.3, 0), center_of(hdr))
		await frames(4)
		check("fila de Exportar → cabecera de sección la guarda ahí", names.call(cli).size() == before + 1, "%d→%d" % [before, names.call(cli).size()])
	else:
		check("cabecera visible sobre el panel Exportar", false, "tapada")

	# 8. archivo del sistema soltado en una sección → recurso ahí, no al lienzo
	var svg := dir.path_join("hoja.svg")
	var f := FileAccess.open(svg, FileAccess.WRITE)
	f.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><path d="M20 2 C35 10 35 30 20 38 C5 30 5 10 20 2Z" fill="#2a2"/></svg>')
	f.close()
	before = names.call(cli).size()
	n0 = api.shapes().size()
	hdr = panel.header_of(cli)   # el panel se reconstruyó tras el cambio
	await move(center_of(hdr))
	root.files_dropped.emit(PackedStringArray([svg]))
	await create_timer(0.8).timeout
	check("archivo del sistema soltado en una sección → recurso ahí", names.call(cli).size() == before + 1 and api.shapes().size() == n0, "%d→%d" % [before, names.call(cli).size()])

	# cerrar el panel de Exportar con su ✕ (tapa la parte baja de la pantalla)
	var close_btn: Button = ep.find_child("BtnClose", true, false)
	await click(center_of(close_btn))
	await frames(4)
	check("✕ cierra el panel de Exportar", not ep.is_visible_in_tree())

	# 9. clic derecho
	g_gen = panel.grid_of(gen)
	if g_gen.item_count > 0 and not (g_gen.get_item_metadata(0) as Dictionary).is_empty():
		await click(g_gen.get_global_transform() * g_gen.get_item_rect(0).get_center(), MOUSE_BUTTON_RIGHT)
		await frames(3)
		check("clic derecho abre el menú del recurso", panel._item_menu.visible)
		panel._item_menu.hide()

	# 10. paquete .vopassets con subcategorías a otra biblioteca
	var pkg := dir.path_join("mis.vopassets")
	check("exportar paquete .vopassets", Lib.export_package(pkg) == OK and FileAccess.file_exists(pkg))
	var total := Lib.category_items(panel.current_cat).size()
	Lib._root_override = dir.path_join("lib_otro")
	panel.current_cat = ""
	panel.refresh()
	var r: Dictionary = panel.import_package(pkg)
	var imp_cat: Dictionary = Lib.categories().filter(func(c) -> bool: return Lib.category_items(c["id"]).size() > 0)[0]
	check("importar el paquete conserva las secciones", r["ok"] and int(r["items"]) == total and (imp_cat["subs"] as Array).any(func(x) -> bool: return x["name"] == "Clientes"), str(r))

	# 11. botón de la barra (carpeta) muestra / oculta el panel con Recursos
	var btn: Button = root.find_child("button_capas", true, false)
	var was: bool = panel.is_visible_in_tree()
	if btn:
		var frame_c: Control = root.find_child("Layout", true, false).get_node("PanelContainer")
		var w_before: float = frame_c.size.x
		await click(center_of(btn))
		await frames(6)
		var hidden_now: bool = not panel.is_visible_in_tree()
		check("al ocultar, el panel se encoge (no queda una caja vacía)", frame_c.size.x < 100.0, "%d → %d px" % [w_before, frame_c.size.x])
		check("…y el botón sigue visible para volver a abrirlo", btn.is_visible_in_tree())
		await click(center_of(btn))
		await frames(4)
		check("botón carpeta oculta y vuelve a mostrar el panel (Recursos)", was and hidden_now and panel.is_visible_in_tree(), "%s %s %s" % [was, hidden_now, panel.is_visible_in_tree()])
		await frames(4)
		check("al mostrar, recupera su ancho", absf(frame_c.size.x - w_before) < 1.0, "%d px" % frame_c.size.x)
		# modos acoplados: la barra y la regla se mueven; y al cambiar de modo
		# con el panel oculto sigue encogido
		var gui = root.get_node("GlobalUI")
		var prev_mode: String = gui.get_ui_mode()
		var rv: Control = root.find_child("regla vertical", true, false)
		for mode in ["modern", "professional"]:
			gui.set_ui_mode(mode)
			await frames(20)
			var rx0: float = rv.get_global_rect().position.x
			await click(center_of(btn))
			await frames(10)
			check("%s: al ocultar, barra y regla se encogen" % mode, frame_c.get_global_rect().size.x < 100.0 and rv.get_global_rect().position.x < 100.0, "panel %d, regla %d→%d" % [frame_c.get_global_rect().size.x, rx0, rv.get_global_rect().position.x])
			await click(center_of(btn))
			await frames(10)
			check("%s: al mostrar vuelve todo" % mode, absf(rv.get_global_rect().position.x - rx0) < 1.0, "regla %d" % rv.get_global_rect().position.x)
		await click(center_of(btn))
		await frames(6)
		gui.set_ui_mode("modern")
		await frames(25)
		check("cambiar de modo con el panel oculto: sigue encogido", frame_c.get_global_rect().size.x < 100.0, "%d" % frame_c.get_global_rect().size.x)
		await click(center_of(btn))
		await frames(6)
		gui.set_ui_mode(prev_mode)
		await frames(20)
	else:
		check("botón carpeta (button_capas) encontrado", false)

	# 12. ⚙ ajustes del panel de capas (antes una maqueta sin código)
	var gear: Button = root.find_child("Layout", true, false).find_child("Button", true, false)
	gear = null
	for c in root.find_children("Button", "Button", true, false):
		if c.text == "⚙" and c.tooltip_text.begins_with("Ajustes del panel"):
			gear = c
	check("botón ⚙ de ajustes visible", gear != null and gear.is_visible_in_tree() and gear.size.x >= 20)
	if gear:
		await click(center_of(gear))
		await frames(3)
		var host: Control = gear.get_parent().get_node("Configuracion de Capas")
		check("⚙ abre los ajustes", host.is_visible_in_tree())
		var tree: Tree = root.find_child("LayersSystem", true, false).get("layer_tree")
		var fs: HSlider = host.find_child("FontSize", true, false)
		fs.value = 16
		await frames(2)
		check("tamaño del texto de las capas se aplica", tree == null or tree.get_theme_font_size("font_size") == 16)
		var opc: HSlider = host.find_child("Opacity", true, false)
		opc.value = 70
		await frames(2)
		var lay_panel: CanvasItem = root.find_child("Layout", true, false).get_node("PanelContainer")
		check("opacidad del panel se aplica", absf(lay_panel.modulate.a - 0.7) < 0.01, str(lay_panel.modulate.a))
		var ths: HSlider = host.find_child("Thumb", true, false)
		ths.value = 100
		await frames(2)
		check("miniaturas de Recursos desde los ajustes", panel.thumb_size == 100)
		var cfgf := ConfigFile.new()
		cfgf.load("user://vectopen_layers_ui.cfg")
		check("los ajustes se guardan", int(cfgf.get_value("panel", "font_size", 0)) == 16)
		await click(center_of(host.find_child("Reset", true, false)))
		await frames(2)
		check("Restablecer vuelve a los valores normales", absf(lay_panel.modulate.a - 1.0) < 0.01 and panel.thumb_size == 56)
		await click(center_of(gear))

	Lib._root_override = ""
	root.get_node("PluginManager")._remove_dir(dir)
	for k in ["user://vectopen_layers_ui.cfg", "user://vectopen_assets_ui.cfg"]:
		if _kept.has(k):
			var fk := FileAccess.open(k, FileAccess.WRITE)
			fk.store_string(_kept[k])
			fk.close()
		elif FileAccess.file_exists(k):
			DirAccess.remove_absolute(k)
	print("RESULT %s (%d fallos)" % ["OK" if fails == 0 else "FALLOS", fails])
	quit(1 if fails > 0 else 0)
