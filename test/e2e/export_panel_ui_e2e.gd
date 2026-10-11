# =============================================================================
# PRUEBA DE INTERFAZ REAL del panel de archivos (exportar / importar).
# Se ejecuta CON VENTANA (no headless): abre la app, abre el panel como el
# usuario y simula el ratón de verdad (Viewport.push_input): clics, dobles
# clics, arrastrar filas a carpetas, archivos al artboard, favoritos, soltar
# archivos del sistema. Imprime PASS/FAIL por paso y sale con código 1 si
# algo falla.
#
#   flatpak run --command=godot org.godotengine.Godot --path . \
#       -s res://test/e2e/export_panel_ui_e2e.gd
# =============================================================================
extends SceneTree

var api
var fails := 0
var dir := ""
var log_lines := PackedStringArray()

func _init() -> void:
	_run.call_deferred()

func check(name: String, ok: bool, extra: String = "") -> void:
	var line := ("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]")
	print(line)
	log_lines.append(line)
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

# ── ratón simulado ───────────────────────────────────────────────────────────
var _mouse := Vector2.ZERO
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

func click(at: Vector2) -> void:
	await move(at)
	await button(at, true)
	await button(at, false)
	await frames(2)

func double_click(at: Vector2) -> void:
	await click(at)
	await move(at)
	await button(at, true, true)
	await button(at, false)
	await frames(2)

func drag(from: Vector2, to: Vector2, steps: int = 12) -> void:
	await move(from)
	await button(from, true)
	for i in range(1, steps + 1):
		await move(from.lerp(to, float(i) / steps), MOUSE_BUTTON_MASK_LEFT)
	await frames(2)
	await button(to, false)
	await frames(4)

func key(code: int, ctrl: bool = false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.ctrl_pressed = ctrl
		ev.pressed = pressed
		root.push_input(ev)
		await process_frame

func PluginManagerClean(d: String) -> void:
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))

func center_of(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

func tree_item_center(tree: Tree, label_end: String) -> Vector2:
	var it := tree.get_root().get_first_child() if tree.get_root() else null
	while it:
		if String(it.get_text(1)).ends_with(label_end):
			var r := tree.get_item_area_rect(it, 1)
			return tree.get_global_transform() * (r.get_center() - Vector2(0, tree.get_scroll().y))
		it = it.get_next()
	return Vector2.INF

# ── escenario ────────────────────────────────────────────────────────────────
const KEEP := ["user://vectopen_export.cfg", "user://vectopen_places.cfg", "user://vectopen_layers_ui.cfg"]
var _kept := {}

const AssetLib = preload("res://script_gdscript/system/asset_library.gd")

func _run() -> void:
	# biblioteca de Recursos TEMPORAL: lo que se suelte no llega a la del usuario
	AssetLib._root_override = ProjectSettings.globalize_path("user://ui_e2e_assets")
	for k in KEEP:   # la configuración real del usuario no se toca
		if FileAccess.file_exists(k):
			_kept[k] = FileAccess.get_file_as_string(k)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await frames(90)
	api = root.get_node("PluginManager").api
	dir = ProjectSettings.globalize_path("user://ui_e2e")
	root.get_node("PluginManager")._remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir.path_join("Destino"))
	var f := FileAccess.open(dir.path_join("circulo.svg"), FileAccess.WRITE)
	f.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="60" height="60"><circle cx="30" cy="30" r="25" fill="#e33"/></svg>')
	f.close()
	for c in api.shapes():
		c.get_parent().remove_child(c)
	var star = api.add_star(Vector2(300, 300), 60, 5)
	var rect = api.add_rect(Vector2(500, 300), Vector2(120, 80), 10)

	# panel de capas en la pestaña Capas (Recursos aceptaría lo que se suelte)
	var ls = root.find_child("LayersSystem", true, false)
	if ls and ls.has_method("_switch_left_tab"):
		ls._switch_left_tab("capas")
	# 1. abrir el panel como el usuario (botón Exportar → señal)
	root.get_node("GlobalEvents").emit_safe("request_export_dialog")
	await frames(10)
	var panel: Control = root.find_child("Panel_export", true, false)
	check("el panel se abre con request_export_dialog", panel != null and panel.is_visible_in_tree())
	var rows = root.find_child("ExportRows", true, false)
	var ffl = root.find_child("FileFlowLayout", true, false)
	check("columna de exportar instalada", rows != null)
	var tree: Tree = ffl.recent_files_tree

	# 2. pestañas de ámbito con clic
	await click(center_of(rows._tabs.get_node("layers")))
	check("clic en «Capas» cambia el ámbito", rows.scope == "layers", rows.scope)
	await frames(4)
	check("una fila por capa", rows.rows().size() == 2, str(rows.rows().size()))

	# 3. barra de lugares: abrir una carpeta con clic
	ffl.sidebar.add_favorite(dir)
	await frames(4)
	var fav_row: Control = ffl.sidebar._fav_box.get_child(0)
	await click(center_of(fav_row))
	await frames(10)
	check("clic en un favorito abre la carpeta", ffl._view_mode == "files" and ffl._browse_dir == dir, "%s %s" % [ffl._view_mode, ffl._browse_dir])

	# 4. arrastrar una fila a una carpeta de la lista
	await frames(10)
	var row0: Control = rows.rows()[0]
	var dest := tree_item_center(tree, "Destino")
	check("la carpeta Destino aparece en la lista", dest != Vector2.INF)
	if dest != Vector2.INF:
		await drag(center_of(row0) - Vector2(row0.size.x * 0.3, 0), dest)
		await create_timer(0.5).timeout
		var files := DirAccess.get_files_at(dir.path_join("Destino"))
		check("arrastrar fila → carpeta exporta ahí", files.size() == 1, str(files))

	# 5. doble clic en una fila → carpeta de destino
	rows.set_dest(dir)
	var before := DirAccess.get_files_at(dir).size()
	await double_click(center_of(rows.rows()[1]) - Vector2(rows.rows()[1].size.x * 0.3, 0))
	await create_timer(0.5).timeout
	check("doble clic en una fila exporta al destino", DirAccess.get_files_at(dir).size() == before + 1, str(DirAccess.get_files_at(dir)))

	# 6. marcar + Ctrl+E
	before = DirAccess.get_files_at(dir).size()
	rows.rows()[0]._chk.button_pressed = true
	rows.rows()[1]._chk.button_pressed = true
	await move(center_of(rows))
	await key(KEY_E, true)
	await create_timer(0.8).timeout
	check("Ctrl+E exporta las filas marcadas", DirAccess.get_files_at(dir).size() == before + 2, str(DirAccess.get_files_at(dir)))

	# 7. arrastrar un archivo de la lista al artboard → importar ahí
	ffl.refresh_view()
	await frames(10)
	var svg_item := tree_item_center(tree, "circulo.svg")
	var n0: int = api.shapes().size()
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var ab = api.artboard()
	var target_world: Vector2 = ab.to_global(Vector2(200, 600))
	var target_screen: Vector2 = canvas.get_viewport().get_canvas_transform() * target_world
	check("circulo.svg aparece en la lista", svg_item != Vector2.INF)
	check("el punto de destino está sobre el artboard y fuera del panel",
		not panel.get_global_rect().has_point(target_screen), str(target_screen))
	if svg_item != Vector2.INF:
		await click(svg_item)
		await drag(svg_item, target_screen)
		await create_timer(0.3).timeout
		check("arrastrar archivo de la lista al artboard lo importa", api.shapes().size() == n0 + 1, "%d→%d" % [n0, api.shapes().size()])

	# 8. arrastrar una carpeta de la lista a Favoritos
	var fav_before: int = ffl.sidebar.favorites.size()
	var dest2 := tree_item_center(tree, "Destino")
	if dest2 != Vector2.INF:
		await click(dest2)
		await drag(dest2, center_of(ffl.sidebar._fav_box))
		await frames(4)
		check("arrastrar carpeta a Favoritos la añade", ffl.sidebar.favorites.size() == fav_before + 1, str(ffl.sidebar.favorites))

	# 9. soltar archivos del sistema sobre una fila → convertir
	await move(center_of(rows.rows()[0]))
	rows.rows()[0].format = "PDF"
	root.files_dropped.emit(PackedStringArray([dir.path_join("circulo.svg")]))
	await create_timer(0.8).timeout
	check("soltar archivo del sistema en una fila lo convierte", FileAccess.file_exists(dir.path_join("circulo.pdf")))

	# 10. soltar archivos del sistema sobre el lienzo → importar
	n0 = api.shapes().size()
	await move(target_screen)
	root.files_dropped.emit(PackedStringArray([dir.path_join("circulo.svg")]))
	await frames(6)
	check("soltar archivo del sistema en el lienzo lo importa", api.shapes().size() == n0 + 1, "%d→%d" % [n0, api.shapes().size()])

	# 11. el objeto importado al arrastrar queda CENTRADO donde se soltó
	var imported: Node2D = api.shapes()[-1]
	var box: Rect2 = preload("res://script_gdscript/system/vector_export.gd").bounds(
		preload("res://script_gdscript/system/vector_export.gd").collect(ab, true, [imported]))
	check("lo importado queda centrado en el punto soltado", box.get_center().distance_to(Vector2(200, 600)) < 2.0, str(box.get_center()))

	# 12. Ctrl+Z deshace la importación
	n0 = api.shapes().size()
	await move(target_screen)
	await key(KEY_Z, true)
	await frames(4)
	check("Ctrl+Z deshace la importación", api.shapes().size() == n0 - 1, "%d→%d" % [n0, api.shapes().size()])

	# 13. doble clic en un archivo de la lista → se importa
	ffl.set_view("files")
	ffl._navigate_dir(dir)
	await frames(10)
	n0 = api.shapes().size()
	var it_c := tree_item_center(tree, "circulo.svg")
	await double_click(it_c)
	await frames(6)
	check("doble clic en un archivo lo importa", api.shapes().size() == n0 + 1, "%d→%d" % [n0, api.shapes().size()])

	# 14. doble clic en una carpeta → entra
	var it_d := tree_item_center(tree, "Destino")
	await double_click(it_d)
	await frames(10)
	check("doble clic en una carpeta entra en ella", ffl._browse_dir == dir.path_join("Destino"), ffl._browse_dir)
	ffl._navigate_dir(dir)
	await frames(10)

	# 15. PNG a 2× arrastrando la fila a una carpeta
	await click(center_of(rows._tabs.get_node("layers")))
	await frames(4)
	var r0 = rows.rows()[0]
	r0._fmt.select(1)
	r0._fmt.item_selected.emit(1)
	r0._scale.select(1)
	r0._scale.item_selected.emit(1)
	PluginManagerClean(dir.path_join("Destino"))
	dest = tree_item_center(tree, "Destino")
	await drag(center_of(r0) - Vector2(r0.size.x * 0.3, 0), dest)
	await create_timer(1.0).timeout
	var pngs := DirAccess.get_files_at(dir.path_join("Destino"))
	var ok_png := pngs.size() == 1 and String(pngs[0]).ends_with("@2x.png")
	if ok_png:
		var img := Image.load_from_file(dir.path_join("Destino").path_join(pngs[0]))
		ok_png = img != null and img.get_width() > 200 and img.get_width() < 300
	check("PNG 2× por arrastre (tamaño ×2)", ok_png, str(pngs))

	# 16. Selección combinada → UN archivo
	api.select([star, rect])
	await click(center_of(rows._tabs.get_node("selection")))
	await frames(6)
	check("Selección: 1.ª fila combina los 2 objetos", rows.rows().size() == 3 and rows.rows()[0].nodes.size() == 2, str(rows.rows().size()))
	PluginManagerClean(dir.path_join("Destino"))
	dest = tree_item_center(tree, "Destino")
	await drag(center_of(rows.rows()[0]) - Vector2(rows.rows()[0].size.x * 0.3, 0), dest)
	await create_timer(0.6).timeout
	check("arrastrar la selección combinada → un archivo", DirAccess.get_files_at(dir.path_join("Destino")).size() == 1, str(DirAccess.get_files_at(dir.path_join("Destino"))))

	# 17. soltar una fila en un LUGAR de la barra lateral
	PluginManagerClean(dir.path_join("Destino"))
	ffl.sidebar.add_favorite(dir.path_join("Destino"))
	await frames(4)
	var fav_dest: Control = null
	for c in ffl.sidebar._fav_box.get_children():
		if "path" in c and c.path == dir.path_join("Destino"):
			fav_dest = c
	await drag(center_of(rows.rows()[1]) - Vector2(rows.rows()[1].size.x * 0.3, 0), center_of(fav_dest))
	await create_timer(0.6).timeout
	check("soltar fila en un favorito exporta ahí", DirAccess.get_files_at(dir.path_join("Destino")).size() == 1, str(DirAccess.get_files_at(dir.path_join("Destino"))))

	# 18. soltar una fila en «Recientes» → Biblioteca (VOP)
	rows.library_override = dir.path_join("Biblio")
	ffl.set_view("recent")
	await frames(10)
	await drag(center_of(rows.rows()[1]) - Vector2(rows.rows()[1].size.x * 0.3, 0), center_of(tree))
	await create_timer(0.6).timeout
	var lib := DirAccess.get_files_at(dir.path_join("Biblio"))
	check("soltar fila en Recientes → Biblioteca .vop", lib.size() == 1 and String(lib[0]).ends_with(".vop"), str(lib))

	# 19. enlace «Deshacer» de la línea de estado borra lo exportado
	var last: PackedStringArray = rows._last_written
	rows._on_status_link("undo")
	check("Deshacer exportación borra el archivo", not last.is_empty() and not FileAccess.file_exists(last[0]))

	# 20. vista de iconos: arrastrar fila sobre el icono de una carpeta
	ffl.set_view("files")
	ffl._navigate_dir(dir)
	ffl.set_details_mode(false)
	await frames(12)
	PluginManagerClean(dir.path_join("Destino"))
	var grid: ItemList = ffl._icon_list
	var gi := -1
	for i in grid.item_count:
		if String(grid.get_item_text(i)) == "Destino":
			gi = i
	check("la carpeta aparece en la vista de iconos", gi >= 0)
	if gi >= 0:
		var gr := grid.get_item_rect(gi)
		var gpos := grid.get_global_transform() * (gr.get_center() - Vector2(0, grid.get_v_scroll_bar().value))
		await drag(center_of(rows.rows()[1]) - Vector2(rows.rows()[1].size.x * 0.3, 0), gpos)
		await create_timer(0.6).timeout
		check("vista de iconos: fila → carpeta exporta ahí", DirAccess.get_files_at(dir.path_join("Destino")).size() == 1, str(DirAccess.get_files_at(dir.path_join("Destino"))))
	ffl.set_details_mode(true)

	# 21. con OTRO control encima del lienzo que también acepta soltados
	#     (como un panel de capas): el archivo se importa igualmente
	var blocker := Blocker.new()
	blocker.name = "Bloqueador"
	blocker.position = target_screen - Vector2(150, 150)
	blocker.size = Vector2(300, 300)
	var cl := CanvasLayer.new()
	cl.layer = 50
	root.add_child(cl)
	cl.add_child(blocker)
	ffl.set_view("files")
	ffl._navigate_dir(dir)
	await frames(10)
	n0 = api.shapes().size()
	var it_svg := tree_item_center(tree, "circulo.svg")
	await drag(it_svg, target_screen)
	await frames(6)
	check("con un control encima del lienzo, arrastrar archivo → importa", api.shapes().size() == n0 + 1 and not blocker.got_drop, "%d→%d bloqueado=%s" % [n0, api.shapes().size(), blocker.got_drop])
	cl.queue_free()

	# 22. desde la vista de ICONOS al artboard
	ffl.set_details_mode(false)
	await frames(10)
	n0 = api.shapes().size()
	var gi2 := -1
	for i in grid.item_count:
		if String(grid.get_item_text(i)) == "circulo.svg":
			gi2 = i
	if gi2 >= 0:
		var gpos2 := grid.get_global_transform() * (grid.get_item_rect(gi2).get_center() - Vector2(0, grid.get_v_scroll_bar().value))
		await click(gpos2)
		await drag(gpos2, target_screen)
		await frames(6)
	check("vista de iconos: arrastrar archivo → artboard lo importa", api.shapes().size() == n0 + 1, "%d→%d" % [n0, api.shapes().size()])
	ffl.set_details_mode(true)

	# 23. vista previa rápida de lo exportado (SVG, PNG, JPEG, WEBP, VOP)
	var prev_dir := dir.path_join("Prev")
	DirAccess.make_dir_recursive_absolute(prev_dir)
	await click(center_of(rows._tabs.get_node("layers")))
	await frames(4)
	var rr = rows.rows()[0]
	for fmt in ["SVG", "PNG", "JPEG", "WEBP", "VOP"]:
		rr.format = fmt
		rr.export_scale = 1.0
		await rows.export_rows_to([rr], prev_dir)
	await create_timer(0.5).timeout
	ffl._navigate_dir(prev_dir)
	await frames(10)
	for f2 in DirAccess.get_files_at(prev_dir):
		var c2 := tree_item_center(tree, f2)
		await click(c2)
		await frames(3)
		var tex: Texture2D = ffl._preview_texture.texture
		var real: bool = tex != null and tex != ffl._get_icon_for_file(prev_dir.path_join(f2)) and tex.get_width() > 40
		check("vista previa de %s muestra la imagen" % f2.get_extension().to_upper(), ffl._preview_panel.visible and real, str(tex.get_size()) if tex else "null")
	# miniaturas en la lista (hilo de miniaturas)
	await create_timer(1.5).timeout
	var thumbs := 0
	for f3 in DirAccess.get_files_at(prev_dir):
		if ffl._thumbnail_cache.has(prev_dir.path_join(f3)):
			thumbs += 1
	check("miniaturas para los 5 formatos", thumbs == 5, str(thumbs))
	# vista previa grande con Espacio
	await key(KEY_SPACE)
	await frames(3)
	var big: Control = ffl.get_node("BigPreviewLayer/BigPreviewOverlay")
	check("Espacio abre la vista previa grande", big.visible and ffl._big_texture.texture != null)
	await key(KEY_ESCAPE)

	# limpieza
	ffl.sidebar.remove_favorite(dir)
	ffl.sidebar.remove_favorite(dir.path_join("Destino"))
	root.get_node("PluginManager")._remove_dir(dir)
	for k in KEEP:
		if _kept.has(k):
			var fk := FileAccess.open(k, FileAccess.WRITE)
			fk.store_string(_kept[k])
			fk.close()
		elif FileAccess.file_exists(k):
			DirAccess.remove_absolute(k)
	root.get_node("PluginManager")._remove_dir(AssetLib._root_override)
	AssetLib._root_override = ""
	print("RESULT %s (%d fallos)" % ["OK" if fails == 0 else "FALLOS", fails])
	quit(1 if fails > 0 else 0)

## Simula otro panel encima del lienzo que acepta cualquier soltado.
class Blocker extends Control:
	var got_drop := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _can_drop_data(_at: Vector2, _data: Variant) -> bool:
		return true
	func _drop_data(_at: Vector2, _data: Variant) -> void:
		got_drop = true
