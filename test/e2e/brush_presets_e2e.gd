# =============================================================================
# «MIS PINCELES» por la interfaz (VGSE fase 6): guardar el pincel actual con
# nombre, cambiarlo, recuperarlo con un clic (estilo, grosor, figura…),
# que se conserve en disco y borrarlo.
#   test/run_e2e.sh brush_presets_e2e
# =============================================================================
extends SceneTree

const OUT := "user://brush_presets"
const ZOOM := 1.0
const MAX_DEV_PX := 3.0
var fails := 0
var canvas

func _init() -> void:
	_run.call_deferred()
	create_timer(400.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

## Sin warp_mouse: un movimiento = una muestra (warp añadía otra casi en el
## mismo sitio y la prueba no se parecía al lápiz real).
func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func move(at: Vector2, held: bool, p: float) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.pressure = p if held else 0.0
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_send(mm)
	await process_frame

func btn(at: Vector2, down: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = at
	mb.global_position = at
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = down
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(mb)
	await process_frame

## Dibuja la lista de puntos (pantalla) con su presión; devuelve el Line2D.
func draw(pts: PackedVector2Array, prs: PackedFloat32Array) -> Line2D:
	await move(pts[0], false, 0.0)
	await btn(pts[0], true)
	for i in pts.size():
		await move(pts[i], true, prs[i])
	await btn(pts[pts.size() - 1], false)
	await frames(4)
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var l := ab.get_child(ab.get_child_count() - 1)
	if l is Line2D:
		var a0: float = (l as Line2D).default_color.a
		(l as Line2D).default_color = Color(0.16, 0.16, 0.18, a0)
		return l
	return null

## Desviación (px de pantalla) de cada muestra respecto al trazo dibujado.
func deviation(l: Line2D, pts: PackedVector2Array) -> Vector2:
	var xf: Transform2D = canvas.get_viewport().get_canvas_transform()
	var poly := PackedVector2Array()
	for q in l.points:
		poly.append(xf * l.to_global(q))
	var worst := 0.0
	var acc := 0.0
	var cnt := 0
	for i in range(2, pts.size() - 2):
		var best := INF
		for k in poly.size() - 1:
			var c := Geometry2D.get_closest_point_to_segment(pts[i], poly[k], poly[k + 1])
			best = minf(best, c.distance_to(pts[i]))
		worst = maxf(worst, best)
		acc += best
		cnt += 1
	return Vector2(worst, acc / maxf(1, cnt))

func click(c: Control) -> void:
	# Si está dentro del panel desplazable y no se ve, se baja hasta él
	# (como haría el usuario con la rueda).
	var sc := c.get_parent()
	while sc and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc:
		(sc as ScrollContainer).ensure_control_visible(c)
		await process_frame
		await process_frame
	var p := c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	_send(mm)
	await process_frame
	for down in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.position = p
		mb.global_position = p
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		_send(mb)
		await process_frame

## Cobertura a lo largo del trazo (fracción de muestras con tinta debajo):
## un aerógrafo en «rosario» deja huecos.
func coverage(img: Image, pts: PackedVector2Array) -> float:
	var hit := 0
	for i in range(3, pts.size() - 3):
		var q := pts[i]
		if img.get_pixel(int(q.x), int(q.y)).get_luminance() < 0.97:
			hit += 1
	return hit / float(maxi(1, pts.size() - 6))

func _run() -> void:
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("smart")
	await frames(10)
	canvas = get_first_node_in_group("_vectopen_canvas")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://brush_presets.cfg"))
	var tb: Button = null
	for x in root.find_children("*", "Button", true, false):
		if (x as Button).is_visible_in_tree() and String(x.name) == "button_toolbrush":
			tb = x
	await click(tb)
	await frames(10)
	var bt = canvas.current_tool
	await click(root.find_child("Style_object", true, false))
	await click(root.find_child("ObjLeaf", true, false))
	bt.brush_width = 7.5
	await frames(4)
	var name_le := root.find_child("PresetName", true, false) as LineEdit
	check("tarjeta «Mis pinceles» visible", name_le != null and name_le.is_visible_in_tree())
	name_le.text = "Hojas"
	await click(root.find_child("PresetSave", true, false))
	await frames(6)
	var chip := root.find_child("Preset_Hojas", true, false) as Button
	check("el pincel guardado aparece como botón", chip != null and chip.is_visible_in_tree())
	# cambiar a otro pincel
	await click(root.find_child("Style_pencil", true, false))
	bt.brush_width = 2.0
	await frames(4)
	await click(chip)
	await frames(6)
	check("un clic lo recupera (estilo, grosor y figura)", bt.brush_style == "object" and is_equal_approx(bt.brush_width, 7.5) and bt.object_source.size() == 1,
		"%s %.1f" % [bt.brush_style, bt.brush_width])
	var cfg := ConfigFile.new()
	check("se guarda en disco", cfg.load("user://brush_presets.cfg") == OK and String(cfg.get_value("presets", "list", "")).contains("Hojas"))
	await click(root.find_child("PresetDel_Hojas", true, false))
	await frames(6)
	check("la × lo borra", root.find_child("Preset_Hojas", true, false) == null or not (root.find_child("Preset_Hojas", true, false) as Control).is_visible_in_tree())
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
