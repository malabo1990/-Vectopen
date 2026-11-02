# =============================================================================
# UX-01 — «El recorte se ve mal en la zona de las dos Bézier».
# Pone como MÁSCARA (clip_children, igual que el botón de Capas) trazados con
# tramos Bézier y dentro un rectángulo rojo. Compara píxel a píxel lo que se
# ve con la geometría EXACTA de la curva (teselada muy fina), a 100 % y 800 %:
#   A · «lente» cerrada con DOS nodos Bézier;
#   B · «S» cerrada con dos Bézier que se cruzan (autointersección);
#   C · cerrada con el primer punto repetido al final (cierre de la pluma);
#   D · ABIERTA con dos Bézier (como Illustrator: recorta su área implícita).
# Se ignora una franja de 1,5 px en el borde (antialias).
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/clip_mask_bezier_e2e.gd
# Capturas en user://clip_mask_bezier/.
# =============================================================================
extends SceneTree

const OUT := "user://clip_mask_bezier"
const RED := Color(0.95, 0.05, 0.05)

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

func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func canvas() -> Node:
	return get_first_node_in_group("_vectopen_canvas")

func artboard() -> Node:
	var c = canvas()
	var m = c.get_node_or_null("manager_script") if c else null
	return m.get_active_artboard() if m and m.has_method("get_active_artboard") else null

func lens() -> Curve2D:
	var c := Curve2D.new()
	c.add_point(Vector2(0, 0), Vector2(0, 120), Vector2(0, -120))
	c.add_point(Vector2(260, 0), Vector2(0, -120), Vector2(0, 120))
	return c

func s_shape() -> Curve2D:
	var c := Curve2D.new()
	c.add_point(Vector2(0, 0), Vector2.ZERO, Vector2(200, -160))
	c.add_point(Vector2(260, 160), Vector2(-260, 0), Vector2.ZERO)
	c.add_point(Vector2(260, 0), Vector2.ZERO, Vector2(-200, 160))
	c.add_point(Vector2(0, 160), Vector2(260, 0), Vector2.ZERO)
	return c

func repeated_close() -> Curve2D:
	var c := Curve2D.new()
	c.add_point(Vector2(0, 80), Vector2.ZERO, Vector2(60, -110))
	c.add_point(Vector2(260, 80), Vector2(-60, -110), Vector2(-60, 110))
	c.add_point(Vector2(0, 80), Vector2(60, 110), Vector2.ZERO)   # = primero
	return c

func open_two() -> Curve2D:
	var c := Curve2D.new()
	c.add_point(Vector2(0, 160), Vector2.ZERO, Vector2(40, -220))
	c.add_point(Vector2(260, 160), Vector2(-40, -220), Vector2.ZERO)
	return c

## Contorno exacto: tramo a tramo con muchas muestras (+ cierre curvo).
func exact_outline(c: Curve2D, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := c.point_count
	var segs := n if closed else n - 1
	for i in segs:
		var a := c.get_point_position(i)
		var ao := c.get_point_out(i)
		var j := (i + 1) % n
		var b := c.get_point_position(j)
		var bi := c.get_point_in(j)
		for k in 400:
			var t := k / 400.0
			out.append(a.bezier_interpolate(a + ao, b + bi, b, t))
	return out

## Regla par-impar con todas las muestras (sirve con autointersecciones).
func inside(p: Vector2, poly: PackedVector2Array) -> bool:
	var c := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a := poly[i]
		var b := poly[j]
		if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			c = not c
		j = i
	return c

func dist_to(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	var n := poly.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % n])
		best = minf(best, p.distance_to(q))
	return best

func is_red(c: Color) -> bool:
	return c.r > 0.6 and c.g < 0.35 and c.b < 0.35

func measure(tag: String, mask: Node2D, outline: PackedVector2Array) -> void:
	await frames(6)
	var img := await grab()
	img.save_png(OUT.path_join(tag + ".png"))
	var xf: Transform2D = mask.get_global_transform_with_canvas()
	var scr := PackedVector2Array()
	for p in outline:
		scr.append(xf * p)
	var bb := Rect2(scr[0], Vector2.ZERO)
	for p in scr:
		bb = bb.expand(p)
	# Solo la zona del lienzo que no tapan los paneles (Capas, Inspector,
	# barra inferior).
	var vs := Vector2(img.get_size())
	var free := Rect2(Vector2(vs.x * 0.22, 70), Vector2(vs.x * 0.62, vs.y - 170))
	bb = bb.grow(6).intersection(free)
	var step := maxi(1, int(maxf(bb.size.x, bb.size.y) / 220.0))
	var total := 0
	var bad := 0
	var miss_in := 0
	var leak_out := 0
	for y in range(int(bb.position.y), int(bb.end.y), step):
		for x in range(int(bb.position.x), int(bb.end.x), step):
			var p := Vector2(x + 0.5, y + 0.5)
			if dist_to(p, scr) < 1.5:
				continue
			total += 1
			var want := inside(p, scr)
			var got := is_red(img.get_pixel(x, y))
			if want != got:
				bad += 1
				if want:
					miss_in += 1
				else:
					leak_out += 1
	var ratio := float(bad) / maxf(1.0, total)
	check("%s: el recorte sigue la curva" % tag, ratio < 0.004,
		"%.2f %% mal (%d dentro sin pintar, %d fuera pintados) de %d" % [ratio * 100.0, miss_in, leak_out, total])

func make_mask(ab: Node, curve: Curve2D, closed: bool, at: Vector2) -> Node2D:
	var vp: Node2D = load("res://script_gdscript/shapes/VectorPath.gd").new()
	vp.name = "Máscara"
	vp.curve = curve
	vp.closed = closed
	vp.fill_color = Color(0.2, 0.4, 0.9) if closed else Color(0, 0, 0, 0)
	vp.stroke_width = 0.0
	vp.position = at
	ab.add_child(vp)
	vp.owner = ab
	var r: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	r.name = "Contenido"
	r.size = Vector2(700, 700)
	r.position = Vector2(130, 80)        # el rectángulo va centrado en su origen
	r.fill_color = RED
	r.stroke_width = 0.0
	vp.add_child(r)
	r.owner = ab
	vp.clip_children = CanvasItem.CLIP_CHILDREN_ONLY   # igual que en Capas
	vp.set_meta("clip_mask", true)
	return vp

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
	root.get_node("GlobalUI").set_ui_mode("modern")
	await frames(20)
	var ab := artboard()
	var cv = canvas()
	var cases := [["A_lente", lens(), true], ["B_S_cruzada", s_shape(), true],
		["C_cierre_repetido", repeated_close(), true], ["D_abierta", open_two(), false]]
	for cs in cases:
		var m := make_mask(ab, cs[1], cs[2], Vector2(200, 300))
		var outline := exact_outline(cs[1], true)
		# 100 %: centrar la máscara.
		cv.camera.zoom = Vector2.ONE
		cv.camera.global_position = m.global_position + Vector2(130, 80)
		await measure("%s_100" % cs[0], m, outline)
		# 800 %: acercar a la zona curva más cerrada (un extremo).
		cv.camera.zoom = Vector2(8, 8)
		cv.camera.global_position = m.global_position + outline[outline.size() / 4]
		await measure("%s_800" % cs[0], m, outline)
		m.queue_free()
		await frames(3)
	cv.camera.zoom = Vector2.ONE
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
