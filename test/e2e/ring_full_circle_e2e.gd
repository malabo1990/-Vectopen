# =============================================================================
# UX-04: anillo de 0° a 360° sin la línea radial que lo atravesaba.
# Se dibuja con la herramienta real (arrastre en el lienzo) en modo Modern y
# se mira el resultado en píxeles: sobre el eje del ángulo 0, entre las dos
# circunferencias, no debe haber trazo.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/ring_full_circle_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const OUT := "user://ring_full_circle"
var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(180.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func mouse_move(at: Vector2, held: bool) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.warp_mouse(ev.position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await process_frame

func mouse_button(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = at
	ev.global_position = at
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.warp_mouse(ev.position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await process_frame

func is_cls(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls

func circles() -> Array:
	return root.find_children("*", "Node2D", true, false).filter(func(n): return is_cls(n, "VectorCircle"))

## Píxel de pantalla de un punto local de la figura.
func screen_px(img: Image, shape: Node2D, local: Vector2) -> Color:
	var p: Vector2 = shape.get_global_transform_with_canvas() * local
	var ip := Vector2i(p.round())
	if ip.x < 0 or ip.y < 0 or ip.x >= img.get_width() or ip.y >= img.get_height():
		return Color(0, 0, 0, 0)
	return img.get_pixelv(ip)

func is_red(c: Color) -> bool:
	return c.r > 0.6 and c.g < 0.35 and c.b < 0.35

## Mira el eje del ángulo 0 entre ambas circunferencias (donde estaba la línea)
## y la circunferencia exterior (que sí debe verse).
func check_pixels(shape, label: String) -> void:
	shape.fill_color = Color(0, 0, 0, 0)
	shape.stroke_color = Color(1, 0, 0, 1)
	shape.stroke_width = 3.0
	shape.queue_redraw()
	await frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(OUT.path_join(label + ".png"))
	var half: Vector2 = shape.size / 2.0
	var r_in: float = half.x * shape.inner_radius_ratio
	var red_axis := 0
	var samples := 0
	for k in range(1, 8):
		var x: float = lerpf(r_in, half.x, k / 8.0)
		# El trazo de las circunferencias ocupa los extremos: saltarlos.
		if absf(x - r_in) < 4.0 or absf(x - half.x) < 4.0:
			continue
		samples += 1
		if is_red(screen_px(img, shape, Vector2(x, 0))):
			red_axis += 1
	check(label + ": sin línea radial en 0°", samples > 0 and red_axis == 0, "%d/%d píxeles rojos" % [red_axis, samples])
	check(label + ": se ve la circunferencia exterior", is_red(screen_px(img, shape, Vector2(0, half.y))) or is_red(screen_px(img, shape, Vector2(0, half.y - 1))))
	check(label + ": se ve la circunferencia interior", is_red(screen_px(img, shape, Vector2(0, half.y * shape.inner_radius_ratio))) or is_red(screen_px(img, shape, Vector2(0, half.y * shape.inner_radius_ratio + 1))))

func _run() -> void:
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
	var gui = root.get_node("GlobalUI")
	gui.set_ui_mode("modern")
	await frames(30)

	var bar := root.find_children("*", "PanelContainer", true, false).filter(func(n): return is_cls(n, "ModernBottomToolbar"))
	var tb = bar[0] if bar.size() > 0 else null
	var poly = null
	for c in root.find_children("polygon", "Control", true, false):
		if c.get_script() != null:
			poly = c
	check("barra y panel de figuras", tb != null and poly != null)
	if tb == null or poly == null:
		_finish(ui_backup)
		return
	tb._buttons["shapes"].emit_signal("pressed")
	await frames(6)
	poly._tabs[3].emit_signal("pressed")
	await frames(6)
	poly._apply_values({"shape_mode": "donut", "start_angle_deg": 0.0, "end_angle_deg": 360.0, "ring_ratio": 0.5})
	await frames(4)
	var ce = get_first_node_in_group("_vectopen_canvas")
	check("herramienta de círculo activa", ce != null and ce.current_tool != null and ce.current_tool.get_script().resource_path.get_file().to_lower().contains("circle"))

	# Dibujar arrastrando en el centro de la vista.
	var vr := root.get_visible_rect()
	var a := vr.get_center() - Vector2(160, 160)
	var b := vr.get_center() + Vector2(160, 160)
	var before := circles().size()
	await mouse_move(a, false)
	await mouse_button(a, true)
	for i in range(1, 13):
		await mouse_move(a.lerp(b, i / 12.0), true)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("preview.png"))
	await mouse_button(b, false)
	await frames(6)
	var list := circles()
	check("se crea un anillo", list.size() == before + 1, "%d → %d" % [before, list.size()])
	if list.size() <= before:
		_finish(ui_backup)
		return
	var ring = list[-1]
	check("modo anillo 0–360", ring.shape_mode == "donut" and ring.is_full_ring(), "%s %s–%s" % [ring.shape_mode, ring.start_angle_deg, ring.end_angle_deg])

	var svg: String = ring.to_svg()
	check("SVG: dos contornos cerrados con evenodd", svg.count("M ") == 2 and svg.count(" Z") == 2 and svg.contains("evenodd"))
	var rings: Array = ring.ring_contours(ring.size / 2.0, ring.inner_radius_ratio)
	check("malla: %d vértices por circunferencia" % ring.CIRCLE_QUALITY, rings[0].size() == ring.CIRCLE_QUALITY and rings[1].size() == ring.CIRCLE_QUALITY)

	await check_pixels(ring, "anillo_360")
	ring.fill_color = Color(0, 0.3, 1, 1)
	ring.queue_redraw()
	await frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(OUT.path_join("anillo_relleno.png"))
	var mid: float = ring.size.x / 2.0 * 0.75
	var fill_ok := 0
	for ang in [0.0, 90.0, 180.0, 270.0, 45.0]:
		var cpx := screen_px(img, ring, Vector2.from_angle(deg_to_rad(ang)) * mid)
		if cpx.b > 0.7 and cpx.r < 0.3:
			fill_ok += 1
	var hole := screen_px(img, ring, Vector2.ZERO)
	check("relleno: se pinta todo el anillo (también en 0°)", fill_ok == 5, "%d/5" % fill_ok)
	check("relleno: el hueco queda vacío", not (hole.b > 0.7 and hole.r < 0.3), str(hole))
	ring.inner_radius_ratio = 0.25
	await check_pixels(ring, "anillo_hueco_25")
	ring.inner_radius_ratio = 0.8
	await check_pixels(ring, "anillo_hueco_80")
	ring.inner_radius_ratio = 0.5

	ring.end_angle_deg = 359.9995
	check("359,9995° cuenta como anillo completo", ring.is_full_ring())
	ring.end_angle_deg = 270.0
	check("arco parcial no es anillo completo", not ring.is_full_ring())
	var verts: PackedVector2Array = ring._generate_vertices()
	var steps: int = maxi(8, int(round(0.75 * ring.CIRCLE_QUALITY)))
	check("arco parcial: contorno exterior + interior (%d vértices)" % (2 * (steps + 1)), verts.size() == 2 * (steps + 1), str(verts.size()))
	check("arco parcial: SVG cerrado en un solo contorno", ring.to_svg().count("M ") == 1 and ring.to_svg().contains("Z"))
	_finish(ui_backup)

func _finish(ui_backup: String) -> void:
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		if f:
			f.store_string(ui_backup)
	print("RESULT: %s (%d fallos)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
