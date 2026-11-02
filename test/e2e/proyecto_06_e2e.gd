# =============================================================================
# FASE B · ENCARGO 06 — Isotipo con anillo (modo Smart)
# Foco: modo anillo 0–360°, degradado.
# Círculo → botón «Figuras» → «Forma: Anillo»; radio interior 70 %; anillo
# completo (0–360, sin costura) y abierto (30–300); degradado cónico; punto
# central; PNG/SVG con el hueco hueco; deshacer 20 pasos; guardar/reabrir.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/proyecto_06_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/06"
const FIXTURE := "res://test/fixtures/proyectos/06-isotipo-anillo.vtc"
const SIZE := Vector2(800, 800)
const C1 := Color(0.0, 0.75, 0.65)
const C2 := Color(0.35, 0.2, 0.9)

var fails := 0
var api
var CS
var ic

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

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

func visible_ctrl(nm: String) -> Control:
	for n in root.find_children(nm, "", true, false):
		if n is Control and (n as Control).is_visible_in_tree():
			return n
	return null

var panel: Control

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
	await frames(6)

## Como el usuario: valor en un campo del panel «Figuras» (Smart).
func set_field(key: String, v: float) -> bool:
	if panel == null or not panel._fields.has(key):
		return false
	var f: Control = panel._fields[key]
	var sc: float = float(f.get_meta("scale", 1.0))
	f.value = v * sc if key == "ring_ratio" else v
	f.value_changed.emit(f.value)
	await frames(3)
	return true

func is_bg(c: Color) -> bool:
	return c.r > 0.93 and c.g > 0.93 and c.b > 0.93

func _run() -> void:
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
	await frames(30)
	api = root.get_node("PluginManager").api
	ic = root.get_node("InspectorCore")
	CS = load("res://scripts/canvas/canvas_serializer.gd")
	var cont: Node2D = get_first_node_in_group("_vectopen_canvas").artboards_container
	var ab: Node2D = api.artboard()
	ab.artboard_size = SIZE
	# 1. Círculo y «Forma: Anillo» desde el inspector.
	var ring = api.add_ellipse(SIZE / 2.0, Vector2(560, 560), "Anillo")
	api.set_props(ring, {"stroke_width": 0.0})
	api.select([ring])
	await frames(10)
	# Botón «Figuras» de la barra de herramientas → panel de la elipse.
	var btn := visible_ctrl("button_toolbshapes") as Control
	check("la barra de Smart tiene el botón «Figuras»", btn != null)
	if btn:
		await click(btn)
	for n in root.find_children("polygon", "", true, false):
		if n.has_method("set_kind"):
			panel = n
	check("se abre el panel «Figuras» con la elipse seleccionada", panel != null and panel.is_visible_in_tree() and panel._fields.has("shape_mode"))
	var ob: OptionButton = panel._fields.get("shape_mode") if panel else null
	if ob:
		for i in ob.item_count:
			if String(ob.get_item_metadata(i)) == "donut":
				ob.select(i)
				ob.item_selected.emit(i)
		await frames(6)
	check("la figura pasa a anillo", String(ring.shape_mode) == "donut")
	var has_inner: bool = await set_field("ring_ratio", 0.7)
	check("«Hueco del anillo» al 70 %", has_inner and is_equal_approx(ring.inner_radius_ratio, 0.7), str(ring.inner_radius_ratio))
	# 2. Degradado cónico.
	ic.apply("fill_paint", {"type": "conic", "center": Vector2(0.5, 0.5), "angle": 0.0, "stops": [[0.0, C1], [1.0, C2]]})
	await frames(4)
	check("degradado cónico aplicado", ring.has_gradient_fill())
	# 3. Anillo completo 0–360: sin costura.
	var ok_a: bool = await set_field("start_angle_deg", 0.0)
	ok_a = ok_a and await set_field("end_angle_deg", 360.0)
	check("ángulos 0–360 desde el inspector", ok_a and is_equal_approx(ring.end_angle_deg, 360.0))
	var dot = api.add_ellipse(SIZE / 2.0, Vector2(80, 80), "Punto")
	api.set_props(dot, {"stroke_width": 0.0, "fill_color": C2})
	api.clear_selection()
	await frames(10)
	await shot("01_anillo_completo")
	var png := ProjectSettings.globalize_path(OUT.path_join("anillo_360.png"))
	var ok: bool = await api.export(png, ab)
	var img := Image.load_from_file(png) if ok else null
	check("PNG del anillo completo", img != null and img.get_size() == Vector2i(SIZE))
	if img:
		# Radio exterior 280, interior 196: muestreamos a 240 px del centro.
		var miss := 0
		for k in 72:
			var a := TAU * k / 72.0
			var p := SIZE / 2.0 + Vector2(cos(a), sin(a)) * 240.0
			if is_bg(img.get_pixel(int(p.x), int(p.y))):
				miss += 1
		check("anillo 0–360 cerrado, sin costura ni huecos", miss == 0, "%d huecos de 72" % miss)
		var hole := img.get_pixel(400, 400 - 150)
		check("el centro del anillo es hueco", is_bg(hole), str(hole))
		var a1 := img.get_pixel(400 + 240, 400)
		var a2 := img.get_pixel(400, 400 - 240)
		check("el degradado cambia de color alrededor del anillo", absf(a1.r - a2.r) + absf(a1.g - a2.g) + absf(a1.b - a2.b) > 0.15, "%s / %s" % [a1, a2])
	var svg := ProjectSettings.globalize_path(OUT.path_join("anillo_360.svg"))
	ok = await api.export(svg, ab)
	var st := FileAccess.get_file_as_string(svg) if ok else ""
	check("SVG del anillo con el hueco (par-impar)", st.contains("fill-rule=\"evenodd\"") or st.contains("<circle") == false and st.count(" M") + st.count("\"M") >= 2,
		"%d bytes" % st.length())
	# 4. Anillo abierto 30–300.
	api.select([ring])
	await frames(6)
	await set_field("start_angle_deg", 30.0)
	await set_field("end_angle_deg", 300.0)
	api.clear_selection()
	await frames(6)
	await shot("02_anillo_abierto")
	ok = await api.export(png, ab)
	img = Image.load_from_file(png) if ok else null
	if img:
		# Hueco del arco: entre 300° y 390° (abajo-derecha, ángulos de pantalla).
		var gap_a := deg_to_rad(345.0)
		var on_a := deg_to_rad(120.0)
		var gp := SIZE / 2.0 + Vector2(cos(gap_a), sin(gap_a)) * 240.0
		var op := SIZE / 2.0 + Vector2(cos(on_a), sin(on_a)) * 240.0
		check("anillo 30–300: abierto donde toca y lleno en el resto",
			is_bg(img.get_pixel(int(gp.x), int(gp.y))) and not is_bg(img.get_pixel(int(op.x), int(op.y))),
			"%s / %s" % [img.get_pixel(int(gp.x), int(gp.y)), img.get_pixel(int(op.x), int(op.y))])
	# 5. Deshacer 20 pasos sobre el ángulo final.
	var e0: float = ring.end_angle_deg
	for i in 20:
		api.set_prop(ring, "end_angle_deg", 300.0 - (i + 1) * 5.0)
	for i in 20:
		api.undo()
	await frames(4)
	check("deshacer 20 pasos", is_equal_approx(ring.end_angle_deg, e0), str(ring.end_angle_deg))
	# 6. Guardar y reabrir.
	var path := ProjectSettings.globalize_path(FIXTURE)
	check("guardar .vtc", CS.write_vtc(path, cont))
	for p in cont.get_children():
		if p.is_in_group("artboards"):
			cont.remove_child(p)
			p.free()
	CS.rebuild_from_vtc(cont, path)
	await frames(10)
	var ab2: Node2D = null
	for p in cont.get_children():
		if p.is_in_group("artboards"):
			ab2 = p
			if p.get("is_dormant"):
				await p.wake()
	await frames(20)
	var r2 = ab2.find_child("Anillo", true, false) if ab2 else null
	check("reabrir: anillo 30–300 al 70 % con degradado", r2 != null and String(r2.shape_mode) == "donut" and is_equal_approx(r2.start_angle_deg, 30.0)
		and is_equal_approx(r2.end_angle_deg, 300.0) and is_equal_approx(r2.inner_radius_ratio, 0.7) and r2.has_gradient_fill())
	root.get_node("ThemeManager").set_mode("dark")
	await frames(20)
	await shot("03_oscuro")
	root.get_node("ThemeManager").set_mode("light")
	await frames(6)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
