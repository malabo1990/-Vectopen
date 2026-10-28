# =============================================================================
# PRUEBA DE UI REAL: vista de Capas (iconos de tipo / miniaturas / compacta).
# Pedido del usuario: "que cada capa tenga icono para saber qué tipo (triángulo,
# cuadrado…)", "en configuración de capas opción de vista previa como Affinity
# o Photoshop" y "otra compacta como el Pixelmator antiguo: solo miniatura y
# 3 botones sin texto".
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/layers_view_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://layers_view"
const LAYERS_CFG := "user://vectopen_layers_ui.cfg"
const EXPECTED_CHECKS := 23
var fails := 0
var checks := 0
var ls = null

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

func item(n: Node) -> TreeItem:
	return ls.get("_node_to_item_map").get(n)

## ¿Hay píxeles de este color en la miniatura de la fila?
func thumb_has(n: Node, col: Color) -> bool:
	var it := item(n)
	if it == null or not it.has_meta("thumb"):
		return false
	var img := it.get_icon(0).get_image()
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var p := img.get_pixel(x, y)
			if p.a > 0.8 and absf(p.r - col.r) < 0.15 and absf(p.g - col.g) < 0.15 and absf(p.b - col.b) < 0.15:
				return true
	return false

func wait_thumbs(nodes: Array) -> void:
	for i in 120:
		var all_ok := true
		for n in nodes:
			var it := item(n)
			if it == null or not it.has_meta("thumb"):
				all_ok = false
		if all_ok:
			return
		await process_frame

func _run() -> void:
	var cfg_backup := FileAccess.get_file_as_string(LAYERS_CFG) if FileAccess.file_exists(LAYERS_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("smart")
	await frames(20)
	ls = root.find_child("LayersSystem", true, false)
	var Settings = load("res://script_gdscript/ui/panels/layers_settings.gd")
	Settings.save_value("layer_view", "icons")
	Settings.apply(ls)
	await frames(6)
	var api = load("res://script_gdscript/api/vectopen_api.gd").new(root)
	var tri: Node2D = api.add_polygon(Vector2(120, 150), 40, 3, 0.0, "Triángulo")
	var pent: Node2D = api.add_polygon(Vector2(220, 150), 40, 5, 0.0, "Pentágono")
	var sq: Node2D = api.add_rect(Vector2(320, 150), Vector2(70, 70), 0.0, "Cuadrado")
	var wide: Node2D = api.add_rect(Vector2(440, 150), Vector2(120, 60), 0.0, "Rect ancho")
	var circ: Node2D = api.add_ellipse(Vector2(120, 300), Vector2(70, 70), "Círculo")
	var star5: Node2D = api.add_star(Vector2(240, 300), 40, 5, 0.45, "Estrella 5")
	var star8: Node2D = api.add_star(Vector2(360, 300), 40, 8, 0.6, "Estrella 8")
	var red: Node2D = api.add_rect(Vector2(500, 300), Vector2(90, 60), 0.0, "Rojo")
	red.fill_color = Color(0.9, 0.1, 0.1)
	var txt: Node2D = api.add_text(Vector2(100, 420), "Hola", 28)
	await frames(30)

	# ── 1) ICONOS DE TIPO ──
	var icons := {}
	for pair in [["triángulo", tri], ["pentágono", pent], ["cuadrado", sq], ["rectángulo", wide],
			["círculo", circ], ["estrella 5", star5], ["estrella 8", star8]]:
		var it := item(pair[1])
		check("icono de %s presente" % pair[0], it != null and it.get_icon(0) != null)
		if it:
			icons[pair[0]] = it.get_icon(0)
	check("triángulo y pentágono tienen iconos distintos (antes: el mismo hexágono)", icons.get("triángulo") != icons.get("pentágono"))
	check("cuadrado y rectángulo ancho se distinguen", icons.get("cuadrado") != icons.get("rectángulo"))
	check("estrella de 5 y de 8 puntas se distinguen", icons.get("estrella 5") != icons.get("estrella 8"))
	check("círculo distinto de cuadrado", icons.get("círculo") != icons.get("cuadrado"))
	await shot("1_iconos")

	# ── 2) MINIATURAS desde Configuración de Capas (opción «Vista de capas») ──
	var gear: Button = null
	for c in root.find_children("Button", "Button", true, false):
		if c.text == "⚙" and c.tooltip_text.begins_with("Ajustes del panel"):
			gear = c
	if gear:
		gear.pressed.emit()
		await frames(4)
	var view_opt := root.find_child("LayerView", true, false) as OptionButton
	check("Configuración de Capas tiene «Vista de capas»", view_opt != null)
	if view_opt:
		view_opt.select(1)
		view_opt.item_selected.emit(1)
	await frames(6)
	check("la vista pasa a miniaturas", ls.get_layer_view() == "thumbs", ls.get_layer_view())
	await wait_thumbs([tri, red, txt])
	check("cada capa tiene su miniatura", item(tri) != null and item(tri).has_meta("thumb") and item(red).has_meta("thumb"))
	check("la miniatura muestra el color real (rojo)", thumb_has(red, Color(0.9, 0.1, 0.1)))
	check("modo miniaturas conserva el nombre", item(red).get_text(0) == "Rojo", item(red).get_text(0))
	await shot("2_miniaturas")
	# Cambiar el color → la miniatura se actualiza.
	root.get_node("SelectionManager").set_selection([red])
	await frames(4)
	root.get_node("InspectorCore").apply("fill_color", Color(0.1, 0.3, 0.9))
	await create_timer(0.5).timeout
	for i in 60:
		if thumb_has(red, Color(0.1, 0.3, 0.9)):
			break
		await process_frame
	check("al cambiar el color, la miniatura se actualiza (azul)", thumb_has(red, Color(0.1, 0.3, 0.9)))

	# ── 3) COMPACTA (Pixelmator): solo miniatura y 3 botones ──
	if view_opt:
		view_opt.select(2)
		view_opt.item_selected.emit(2)
	await frames(6)
	await wait_thumbs([red, tri])
	check("la vista pasa a compacta", ls.get_layer_view() == "compact")
	var itr := item(red)
	check("compacta: sin texto en la fila", itr != null and itr.get_text(0) == "", itr.get_text(0) if itr else "-")
	check("compacta: el nombre va en el tooltip", itr != null and itr.get_tooltip_text(0) == "Rojo")
	check("compacta: conserva los 3 botones (ver, bloquear, máscara)", itr != null and itr.get_button_count(2) == 3)
	check("compacta: con miniatura", itr != null and itr.has_meta("thumb"))
	await shot("3_compacta")
	# ── 4) De vuelta a iconos ──
	if view_opt:
		view_opt.select(0)
		view_opt.item_selected.emit(0)
	await frames(6)
	check("vuelve a iconos con nombre", item(tri) != null and item(tri).get_text(0) != "" and not item(tri).has_meta("thumb"))

	if gear and root.find_child("Configuracion de Capas", true, false):
		(root.find_child("Configuracion de Capas", true, false) as Control).visible = false
	for n in [tri, pent, sq, wide, circ, star5, star8, red, txt]:
		if is_instance_valid(n):
			n.queue_free()
	var f := FileAccess.open(LAYERS_CFG, FileAccess.WRITE)
	f.store_string(cfg_backup)
	f.close()
	if checks < EXPECTED_CHECKS:
		check("el test hizo todas sus comprobaciones", false, "%d de %d" % [checks, EXPECTED_CHECKS])
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
