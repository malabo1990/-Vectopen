# =============================================================================
# PRUEBA A FONDO de las SOMBRAS (Drop Shadow / Inner Shadow) en la app real,
# midiendo PÍXELES de la ventana:
#   · se ve, hacia donde marca el desplazamiento, del color pedido;
#   · desactivada / opacidad 0 → no se ve;  más desenfoque/extensión → mayor;
#   · desenfoque grande NO se recorta en seco;
#   · sombra interior solo dentro de la figura;
#   · en vivo == horneada (zoom 1, zoom 2, girada) — fallos de nitidez/posición;
#   · deshacer/rehacer, duplicar, dos sombras, en grupo, exportar a PNG;
#   · todas las figuras: rectángulo, elipse, estrella, polígono, trazado, texto.
#   flatpak run --command=godot org.godotengine.Godot --path . \
#       -s res://test/e2e/shadow_fx_e2e.gd      (E2E_OUT=carpeta para capturas)
# =============================================================================
extends SceneTree

var fails := 0
var out := "user://shadow_fx"
var api
var canvas: Node2D
var cam: Camera2D
var ic
var sm
var hm

func _init() -> void:
	_run.call_deferred()

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func wait_ms(ms: int) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < ms:
		await process_frame

## Caja de la figura en PANTALLA (la de la herramienta Mover, sin efectos).
func screen_rect(shape: Node2D) -> Rect2:
	var xf := canvas.get_viewport().get_canvas_transform()
	var mt = canvas.current_tool
	var gr: Rect2 = mt._global_rect(shape) if mt and mt.has_method("_global_rect") else Rect2(shape.global_position, Vector2(100, 100))
	var a: Vector2 = xf * gr.position
	var b: Vector2 = xf * gr.end
	return Rect2(a.min(b), (b - a).abs())

## Captura sin selección (sin caja de selección encima).
func grab() -> Image:
	sm.set_selection([])
	ic._sync_selection()
	await frames(4)
	return root.get_texture().get_image()

## Compara dos capturas en `area` (pantalla). Devuelve: n cambiados fuera y
## dentro de `inside`, centro de los cambios de fuera, distancia máxima de un
## cambio al borde de `inside`, color medio cambiado, diferencia media.
func analyze(base: Image, img: Image, area: Rect2, inside: Rect2) -> Dictionary:
	var r := Rect2i(area).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var n_out := 0
	var n_in := 0
	var sum := Vector2.ZERO
	var far := 0.0
	var col := Color(0, 0, 0, 0)
	var acc := 0.0
	var tot := 0
	var darkest := 1.0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			var a := base.get_pixel(x, y)
			var b := img.get_pixel(x, y)
			var d := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			acc += d / 3.0
			tot += 1
			if d <= 0.06:
				continue
			var p := Vector2(x, y)
			if inside.has_point(p):
				n_in += 1
			else:
				n_out += 1
				sum += p
				col += b
				darkest = minf(darkest, b.get_luminance())
				var dx := maxf(maxf(inside.position.x - p.x, p.x - inside.end.x), 0.0)
				var dy := maxf(maxf(inside.position.y - p.y, p.y - inside.end.y), 0.0)
				far = maxf(far, Vector2(dx, dy).length())
	return {
		"out": n_out, "in": n_in, "far": far,
		"center": sum / maxf(1, n_out),
		"color": col / maxf(1, n_out),
		"mean": acc / maxf(1, tot) * 255.0,
		"darkest": darkest,
	}

func mean_diff(a: Image, b: Image, area: Rect2) -> float:
	return analyze(a, b, area, Rect2(-1, -1, 0, 0))["mean"]

func shadow(params: Dictionary = {}) -> Dictionary:
	var fx: Dictionary = {"type": "Drop Shadow", "enabled": true, "offset_x": 12.0, "offset_y": 12.0,
		"blur": 6.0, "spread": 0.0, "color": Color(0, 0, 0, 0.7)}
	fx.merge(params, true)
	return fx

func set_fx(node: Node, list: Array) -> void:
	api.set_prop(node, "effects", list)
	await frames(3)

## Centra la cámara en `node` con `zoom`.
func focus(node: Node2D, zoom: float = 1.0) -> void:
	cam.zoom = Vector2(zoom, zoom)
	var mt = canvas.current_tool
	var gr: Rect2 = mt._global_rect(node) if mt and mt.has_method("_global_rect") else Rect2(node.global_position, Vector2.ZERO)
	cam.global_position = gr.get_center()
	await frames(4)

func _run() -> void:
	var env_out := OS.get_environment("E2E_OUT")
	if env_out != "":
		out = env_out
	DirAccess.make_dir_recursive_absolute(out)
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)  # pantalla Huion completa
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await frames(20)
	api = root.get_node("PluginManager").api
	canvas = get_first_node_in_group("_vectopen_canvas")
	cam = canvas.get_node("Camera2D")
	ic = root.get_node("InspectorCore")
	sm = root.get_node("SelectionManager")
	hm = root.get_node("HistoryManager")
	for c in api.shapes():
		c.get_parent().remove_child(c)
		c.queue_free()
	var ab_size: Vector2 = api.artboard_size()
	var center: Vector2 = ab_size / 2.0

	# ── 1. Rectángulo: lo básico ────────────────────────────────────────────
	var rect: Node2D = api.add_rect(center, Vector2(220, 150))
	api.set_fill(rect, Color(0.15, 0.45, 0.9))
	await focus(rect)
	var r_in := screen_rect(rect)
	var area := r_in.grow(140)
	var base := await grab()
	await set_fx(rect, [shadow()])
	var live := await grab()
	live.get_region(Rect2i(area)).save_png(out + "/rect_sombra.png")
	var a := analyze(base, live, area, r_in)
	check("sombra se ve fuera de la figura", a["out"] > 200, "%d px" % a["out"])
	check("la figura opaca no cambia por dentro", a["in"] < 30, "%d px" % a["in"])
	var dir: Vector2 = a["center"] - r_in.get_center()
	check("desplazamiento (+12,+12) → sombra abajo a la derecha", dir.x > 3 and dir.y > 3, str(dir))
	check("sombra oscura (color negro)", float(a["darkest"]) < 0.45, "lum. mínima %.2f" % a["darkest"])

	await set_fx(rect, [shadow({"offset_x": -25.0, "offset_y": 0.0})])
	a = analyze(base, await grab(), area, r_in)
	dir = a["center"] - r_in.get_center()
	check("desplazamiento (-25,0) → sombra a la izquierda", dir.x < -5 and absf(dir.y) < 6, str(dir))
	await set_fx(rect, [shadow({"offset_x": 0.0, "offset_y": -25.0})])
	a = analyze(base, await grab(), area, r_in)
	dir = a["center"] - r_in.get_center()
	check("desplazamiento (0,-25) → sombra arriba", dir.y < -5 and absf(dir.x) < 6, str(dir))

	await set_fx(rect, [shadow({"enabled": false})])
	a = analyze(base, await grab(), area, r_in)
	check("sombra desactivada no se ve", a["out"] < 20, "%d px" % a["out"])
	await set_fx(rect, [shadow({"color": Color(0, 0, 0, 0.0)})])
	a = analyze(base, await grab(), area, r_in)
	check("sombra con opacidad 0 no se ve", a["out"] < 20, "%d px" % a["out"])

	await set_fx(rect, [shadow({"color": Color(1, 0, 0, 0.9), "blur": 2.0})])
	a = analyze(base, await grab(), area, r_in)
	var c: Color = a["color"]
	check("sombra roja se ve roja", c.r > c.g + 0.15 and c.r > c.b + 0.15, str(c))

	await set_fx(rect, [shadow({"offset_x": 0.0, "offset_y": 0.0, "blur": 2.0})])
	var a_b2 := analyze(base, await grab(), area, r_in)
	await set_fx(rect, [shadow({"offset_x": 0.0, "offset_y": 0.0, "blur": 30.0})])
	var img_b30 := await grab()
	img_b30.get_region(Rect2i(area)).save_png(out + "/rect_blur30.png")
	var a_b30 := analyze(base, img_b30, area, r_in)
	check("más desenfoque → sombra más extensa", a_b30["far"] > a_b2["far"] + 8, "%.0f → %.0f px" % [a_b2["far"], a_b30["far"]])
	# Sin recorte en seco: la sombra llega lejos y se desvanece, no corta en la caja.
	check("desenfoque 30 llega lejos (no recortado)", a_b30["far"] >= 22, "%.0f px" % a_b30["far"])
	await set_fx(rect, [shadow({"offset_x": 0.0, "offset_y": 0.0, "blur": 2.0, "spread": 14.0})])
	var a_sp := analyze(base, await grab(), area, r_in)
	check("extensión (spread) agranda la sombra", a_sp["out"] > a_b2["out"] * 1.3, "%d → %d px" % [a_b2["out"], a_sp["out"]])

	# ── 2. Sombra interior: solo dentro ─────────────────────────────────────
	await set_fx(rect, [{"type": "Inner Shadow", "enabled": true, "offset_x": 8.0, "offset_y": 8.0,
		"blur": 6.0, "spread": 0.0, "color": Color(0, 0, 0, 0.8)}])
	var inner_img := await grab()
	inner_img.get_region(Rect2i(area)).save_png(out + "/rect_interior.png")
	a = analyze(base, inner_img, area, r_in.grow(-1))
	check("sombra interior se ve dentro", a["in"] > 150, "%d px" % a["in"])
	check("sombra interior no se sale", a["out"] < 40, "%d px fuera" % a["out"])

	# ── 3. En vivo vs horneada (se hornea a textura tras ~0,3 s quieta) ────
	for z in [1.0, 2.0]:
		await set_fx(rect, [])
		await focus(rect, z)
		r_in = screen_rect(rect)
		area = r_in.grow(140.0 * z)
		var b0 := await grab()
		await set_fx(rect, [shadow({"blur": 10.0})])
		var l := await grab()
		await wait_ms(1000)
		var bk := await grab()
		bk.get_region(Rect2i(area).intersection(Rect2i(Vector2i.ZERO, bk.get_size()))).save_png(out + "/horneada_zoom%d.png" % int(z))
		var md := mean_diff(l, bk, area)
		check("zoom %.0f: horneada se ve igual que en vivo" % z, md < 2.5, "dif. media %.2f" % md)
		var al := analyze(b0, l, area, r_in)
		set_meta("far_z%d" % int(z), al["far"])
	var f1: float = get_meta("far_z1")
	var f2: float = get_meta("far_z2")
	check("zoom 2: la sombra escala con el documento", f2 > f1 * 1.6 and f2 < f1 * 2.4, "%.0f → %.0f px" % [f1, f2])

	# Girada 30°: en vivo == horneada, y se ve.
	await set_fx(rect, [])
	api.set_rotation(rect, 30.0)
	await focus(rect, 1.0)
	r_in = screen_rect(rect)
	area = r_in.grow(140)
	var b_rot := await grab()
	await set_fx(rect, [shadow({"blur": 8.0})])
	var l_rot := await grab()
	await wait_ms(1000)
	var bk_rot := await grab()
	bk_rot.get_region(Rect2i(area)).save_png(out + "/girada_horneada.png")
	check("girada: se ve la sombra", analyze(b_rot, l_rot, area, r_in)["out"] > 150)
	var md_rot := mean_diff(l_rot, bk_rot, area)
	check("girada: horneada se ve igual que en vivo", md_rot < 2.5, "dif. media %.2f" % md_rot)
	api.set_rotation(rect, 0.0)
	await frames(3)

	# ── 4. Deshacer / rehacer (camino del panel: InspectorCore.apply) ──────
	await set_fx(rect, [])
	await focus(rect)
	r_in = screen_rect(rect)
	area = r_in.grow(140)
	var b_u := await grab()
	hm.clear()
	sm.select(rect)
	ic._sync_selection()
	ic.apply("effects", [shadow()])
	await frames(3)
	hm.undo()
	await frames(3)
	var after_undo = ic._read(rect, "effects")
	var img_u := await grab()
	check("deshacer quita la sombra", (after_undo is Array and (after_undo as Array).is_empty()) and mean_diff(b_u, img_u, area) < 1.0,
		"efectos=%s dif=%.2f" % [after_undo, mean_diff(b_u, img_u, area)])
	hm.redo()
	await frames(3)
	var after_redo = ic._read(rect, "effects")
	check("rehacer la devuelve", after_redo is Array and (after_redo as Array).size() == 1, str(after_redo))

	# ── 5. Duplicar copia la sombra; dos sombras a la vez ──────────────────
	var dup: Node2D = api.duplicate(rect, Vector2(0, 260))
	await frames(3)
	var dfx = api.get_prop(dup, "effects")
	check("duplicar copia la sombra", dfx is Array and (dfx as Array).size() == 1, str(dfx))
	await set_fx(dup, [])
	await focus(dup)
	var d_in := screen_rect(dup)
	var d_area := d_in.grow(140)
	var b_two := await grab()
	await set_fx(dup, [shadow({"offset_x": 30.0, "offset_y": 0.0, "blur": 2.0, "color": Color(1, 0, 0, 0.9)}),
		shadow({"offset_x": -30.0, "offset_y": 0.0, "blur": 2.0, "color": Color(0, 0.8, 0, 0.9)})])
	var i_two := await grab()
	i_two.get_region(Rect2i(d_area)).save_png(out + "/dos_sombras.png")
	var right := analyze(b_two, i_two, Rect2(d_in.end.x, d_in.position.y, 60, d_in.size.y), d_in)
	var left := analyze(b_two, i_two, Rect2(d_in.position.x - 60, d_in.position.y, 60, d_in.size.y), d_in)
	check("dos sombras: la roja a la derecha", right["out"] > 50 and (right["color"] as Color).r > (right["color"] as Color).g, str(right["color"]))
	check("dos sombras: la verde a la izquierda", left["out"] > 50 and (left["color"] as Color).g > (left["color"] as Color).r, str(left["color"]))
	# dos sombras interiores: arriba-izquierda roja y abajo-derecha verde
	await set_fx(dup, [])
	var b_in2 := await grab()
	await set_fx(dup, [
		{"type": "Inner Shadow", "enabled": true, "offset_x": 14.0, "offset_y": 14.0, "blur": 2.0, "spread": 0.0, "color": Color(1, 0, 0, 0.9)},
		{"type": "Inner Shadow", "enabled": true, "offset_x": -14.0, "offset_y": -14.0, "blur": 2.0, "spread": 0.0, "color": Color(0, 0.8, 0, 0.9)}])
	var i_in2 := await grab()
	i_in2.get_region(Rect2i(d_area)).save_png(out + "/dos_interiores.png")
	var tl := analyze(b_in2, i_in2, Rect2(d_in.position, Vector2(20, 20)), Rect2(-1, -1, 0, 0))
	var br := analyze(b_in2, i_in2, Rect2(d_in.end - Vector2(20, 20), Vector2(20, 20)), Rect2(-1, -1, 0, 0))
	check("dos sombras interiores: la roja arriba-izquierda", tl["out"] > 10 and (tl["color"] as Color).r > (tl["color"] as Color).g, str(tl["color"]))
	check("dos sombras interiores: la verde abajo-derecha", br["out"] > 10 and (br["color"] as Color).g > (br["color"] as Color).r, str(br["color"]))
	dup.get_parent().remove_child(dup)
	dup.queue_free()
	# dos sombras en un TRAZADO (Bézier / pluma: VectorPath)
	var crv := Curve2D.new()
	for q in [Vector2(-90, -60), Vector2(90, -60), Vector2(90, 60), Vector2(-90, 60)]:
		crv.add_point(center + Vector2(0, 260) + q)
	var pth: Node2D = api.add_curve(crv, true)
	api.set_fill(pth, Color(0.3, 0.3, 0.9))
	await frames(3)
	await focus(pth)
	var p_in := screen_rect(pth)
	var b_pth := await grab()
	await set_fx(pth, [shadow({"offset_x": 30.0, "offset_y": 0.0, "blur": 2.0, "color": Color(1, 0, 0, 0.9)}),
		shadow({"offset_x": -30.0, "offset_y": 0.0, "blur": 2.0, "color": Color(0, 0.8, 0, 0.9)})])
	var i_pth := await grab()
	var pr := analyze(b_pth, i_pth, Rect2(p_in.end.x, p_in.position.y, 60, p_in.size.y), p_in)
	var pl := analyze(b_pth, i_pth, Rect2(p_in.position.x - 60, p_in.position.y, 60, p_in.size.y), p_in)
	check("trazado con dos sombras: roja a la derecha y verde a la izquierda",
		pr["out"] > 30 and pl["out"] > 30 and (pr["color"] as Color).r > (pr["color"] as Color).g and (pl["color"] as Color).g > (pl["color"] as Color).r,
		"der=%s izq=%s" % [pr["color"], pl["color"]])
	pth.get_parent().remove_child(pth)
	pth.queue_free()

	# ── 6. Todas las figuras: se ve y horneada == en vivo ──────────────────
	await set_fx(rect, [])
	var others := {
		"elipse": api.add_ellipse(center + Vector2(-260, 0), Vector2(160, 120)),
		"estrella": api.add_star(center + Vector2(260, 0), 80.0, 5),
		"polígono": api.add_polygon(center + Vector2(0, 240), 80.0, 6),
		"trazado": api.add_shape(PackedVector2Array([center + Vector2(-300, 220), center + Vector2(-180, 200),
			center + Vector2(-200, 320), center + Vector2(-320, 300)])),
		"texto": api.add_text(center + Vector2(160, 220), "Sombra", 64, Color(0.1, 0.1, 0.1)),
	}
	for nm in others:
		var n: Node2D = others[nm]
		if not (nm == "texto"):
			api.set_fill(n, Color(0.85, 0.35, 0.2))
		await frames(3)
		await focus(n)
		var s_in := screen_rect(n)
		var s_area := s_in.grow(120)
		var s_base := await grab()
		await set_fx(n, [shadow({"blur": 6.0})])
		var s_live := await grab()
		await wait_ms(1000)
		var s_bk := await grab()
		s_bk.get_region(Rect2i(s_area)).save_png(out + "/%s.png" % nm)
		var sa := analyze(s_base, s_live, s_area, s_in)
		# el texto: su caja ya incluye el hueco entre letras, donde cae la sombra
		var seen: int = sa["out"] + (sa["in"] if nm == "texto" else 0)
		check(nm + ": la sombra se ve", seen > 60, "%d px" % seen)
		var smd := mean_diff(s_live, s_bk, s_area)
		check(nm + ": horneada == en vivo", smd < 2.5, "dif. media %.2f" % smd)

	# ── 7. Sombra en un GRUPO ──────────────────────────────────────────────
	var g1: Node2D = api.add_rect(center + Vector2(-60, -260), Vector2(80, 80))
	var g2: Node2D = api.add_rect(center + Vector2(60, -260), Vector2(80, 80))
	api.set_fill(g1, Color(0.2, 0.6, 0.3))
	api.set_fill(g2, Color(0.2, 0.6, 0.3))
	var grp: Node2D = api.group([g1, g2])
	await frames(3)
	await focus(grp)
	var g_in := screen_rect(grp)
	var g_area := g_in.grow(120)
	var g_base := await grab()
	var g_ok: bool = api.set_prop(grp, "effects", [shadow()])
	await frames(3)
	var g_img := await grab()
	g_img.get_region(Rect2i(g_area)).save_png(out + "/grupo.png")
	var ga := analyze(g_base, g_img, g_area, g_in)
	check("grupo: acepta y muestra la sombra", g_ok and (ga["out"] + ga["in"]) > 60, "aceptada=%s %d px" % [g_ok, ga["out"] + ga["in"]])

	# ── 7b. Imagen con sombra: se ve, y se conserva al guardar y recargar ──
	var CS = load("res://scripts/canvas/canvas_serializer.gd")
	var im0 := Image.create(140, 100, false, Image.FORMAT_RGBA8)
	im0.fill(Color(0.9, 0.6, 0.1))
	var pic: Node2D = api.add_image(im0, center + Vector2(0, 300))
	await frames(3)
	await focus(pic)
	var pic_in := screen_rect(pic)
	var pic_area := pic_in.grow(100)
	var pic_b := await grab()
	api.set_prop(pic, "effects", [shadow()])
	await frames(4)
	var pic_i := await grab()
	pic_i.get_region(Rect2i(pic_area)).save_png(out + "/imagen.png")
	var pa := analyze(pic_b, pic_i, pic_area, pic_in)
	dir = pa["center"] - pic_in.get_center()
	check("imagen: la sombra se ve abajo a la derecha", pa["out"] > 150 and dir.x > 3 and dir.y > 3, "%d px dir=%s" % [pa["out"], dir])
	var pdata: Dictionary = CS._serialize_element(pic)
	var ppar := pic.get_parent()
	ppar.remove_child(pic)
	pic.queue_free()
	await frames(2)
	var pic2: Node2D = CS._element_from(pdata)
	ppar.add_child(pic2)
	CS._apply_transform(pic2, pdata)
	await frames(6)
	var pic_r := await grab()
	var prd := mean_diff(pic_i, pic_r, pic_area)
	check("imagen: la sombra se conserva al guardar y recargar", prd < 2.5, "dif. media %.2f" % prd)
	ppar.remove_child(pic2)
	pic2.queue_free()

	# ── 8. Exportar a PNG incluye la sombra ────────────────────────────────
	for n in api.shapes():
		if n != rect:
			n.visible = false
	await set_fx(rect, [])
	var p0 := ProjectSettings.globalize_path("user://shadow_fx_sin.png")
	var p1 := ProjectSettings.globalize_path("user://shadow_fx_con.png")
	var ok0: bool = await api.export(p0)
	await set_fx(rect, [shadow({"offset_x": 20.0, "offset_y": 20.0, "blur": 8.0})])
	var ok1: bool = await api.export(p1)
	check("exportar PNG funciona", ok0 and ok1)
	if ok0 and ok1:
		var e0 := Image.load_from_file(p0)
		var e1 := Image.load_from_file(p1)
		var full := Rect2(Vector2.ZERO, Vector2(e0.get_size()))
		var sc := float(e0.get_width()) / ab_size.x
		var rr := Rect2((center - Vector2(110, 75)) * sc, Vector2(220, 150) * sc)
		var ea := analyze(e0, e1, full, rr)
		e1.save_png(out + "/exportado.png")
		dir = ea["center"] - rr.get_center()
		check("PNG exportado lleva la sombra, abajo a la derecha", ea["out"] > 100 and dir.x > 3 and dir.y > 3, "%d px dir=%s" % [ea["out"], dir])


	# ── 9. CAPAS: la sombra cae sobre TODAS las capas de debajo ────────────
	#    (y la de una capa inferior nunca tapa a las de encima)
	for n in api.shapes():
		n.get_parent().remove_child(n)
		n.queue_free()
	await frames(3)
	var makers := {
		"rectángulo": func(at: Vector2) -> Node2D: return api.add_rect(at, Vector2(160, 110)),
		"elipse": func(at: Vector2) -> Node2D: return api.add_ellipse(at, Vector2(160, 110)),
		"estrella": func(at: Vector2) -> Node2D: return api.add_star(at, 70.0, 5),
		"trazado": func(at: Vector2) -> Node2D: return api.add_shape(PackedVector2Array([at + Vector2(-80, -50), at + Vector2(80, -60), at + Vector2(70, 55), at + Vector2(-75, 50)])),
		"texto": func(at: Vector2) -> Node2D: return api.add_text(at - Vector2(90, 30), "Capa", 72, Color(0.9, 0.1, 0.1)),
		"imagen": func(at: Vector2) -> Node2D:
			var im := Image.create(160, 110, false, Image.FORMAT_RGBA8)
			im.fill(Color(0.2, 0.8, 0.9))
			return api.add_image(im, at),
		"grupo": func(at: Vector2) -> Node2D:
			var a1: Node2D = api.add_rect(at - Vector2(45, 0), Vector2(70, 110))
			var a2: Node2D = api.add_rect(at + Vector2(45, 0), Vector2(70, 110))
			api.set_fill(a1, Color(0.2, 0.35, 1.0))
			api.set_fill(a2, Color(0.2, 0.35, 1.0))
			return api.group([a1, a2]),
	}
	var lowers := {
		"rectángulo": func(at: Vector2) -> Node2D:
			var r0: Node2D = api.add_rect(at, Vector2(520, 400))
			api.set_fill(r0, Color(1, 0.95, 0.3))
			return r0,
		"imagen": func(at: Vector2) -> Node2D:
			var im := Image.create(520, 400, false, Image.FORMAT_RGBA8)
			im.fill(Color(1, 0.95, 0.3))
			return api.add_image(im, at),
		"texto": func(at: Vector2) -> Node2D: return api.add_text(at - Vector2(260, 120), "████████\n████████\n████████", 110, Color(1, 0.95, 0.3)),
	}
	var ds := shadow({"offset_x": 28.0, "offset_y": 28.0, "blur": 3.0, "color": Color(0, 0, 0, 0.85)})
	for lname in lowers:
		for tname in makers:
			var low: Node2D = lowers[lname].call(center)
			var top: Node2D = makers[tname].call(center)
			if tname != "texto" and tname != "imagen" and tname != "grupo":
				api.set_fill(top, Color(0.2, 0.35, 1.0))
			await frames(3)
			await focus(top)
			var t_in := screen_rect(top)
			# zona donde cae la sombra (abajo-derecha), dentro de la capa de abajo
			var zone := Rect2(t_in.position + Vector2(28, 28), t_in.size).intersection(screen_rect(low).grow(-2))
			var lb := await grab()
			var fx_ok: bool = api.set_prop(top, "effects", [ds])
			await frames(4)
			var li := await grab()
			var za := analyze(lb, li, zone, t_in)
			check("%s con sombra ENCIMA de %s: la sombra oscurece la capa de abajo" % [tname, lname],
				fx_ok and za["out"] > 40 and float(za["darkest"]) < 0.6,
				"%d px, lum. mín %.2f" % [za["out"], za["darkest"]])
			if za["out"] <= 40:
				li.get_region(Rect2i(t_in.grow(80))).save_png(out + "/capas_%s_sobre_%s.png" % [tname, lname])
			api.set_prop(top, "effects", [])
			for n2 in [top, low]:
				n2.get_parent().remove_child(n2)
				n2.queue_free()
			await frames(2)
	# Al revés: la sombra de la capa de ABAJO no tapa a la de encima.
	for tname in makers:
		var low2: Node2D = api.add_rect(center - Vector2(150, 0), Vector2(160, 120))
		api.set_fill(low2, Color(0.3, 0.3, 0.3))
		var top2: Node2D = makers[tname].call(center + Vector2(60, 0))
		if tname != "texto" and tname != "imagen" and tname != "grupo":
			api.set_fill(top2, Color(0.2, 0.35, 1.0))
		await frames(3)
		await focus(top2)
		var u_in := screen_rect(top2)
		var ub := await grab()
		api.set_prop(low2, "effects", [shadow({"offset_x": 200.0, "offset_y": 0.0, "blur": 3.0, "spread": 20.0, "color": Color(0, 0, 0, 0.9)})])
		await frames(4)
		var ui := await grab()
		# píxeles PROPIOS de la capa de encima (no fondo): no deben cambiar
		var changed := 0
		var own := 0
		var own_col: Color = {"texto": Color(0.9, 0.1, 0.1), "imagen": Color(0.2, 0.8, 0.9)}.get(tname, Color(0.2, 0.35, 1.0))
		var rr2 := Rect2i(u_in.grow(-6)).intersection(Rect2i(Vector2i.ZERO, ub.get_size()))
		for y in range(rr2.position.y, rr2.end.y, 2):
			for x in range(rr2.position.x, rr2.end.x, 2):
				var c0 := ub.get_pixel(x, y)
				# solo píxeles del color EXACTO de la capa (el borde suavizado se
				# mezcla con lo de detrás, como debe)
				if absf(c0.r - own_col.r) + absf(c0.g - own_col.g) + absf(c0.b - own_col.b) > 0.08:
					continue
				# lejos del borde de la pieza (el suavizado del borde puede mezclarse)
				if ub.get_pixel(x - 3, y).get_luminance() > 0.9 or ub.get_pixel(x + 3, y).get_luminance() > 0.9 \
						or ub.get_pixel(x, y - 3).get_luminance() > 0.9 or ub.get_pixel(x, y + 3).get_luminance() > 0.9:
					continue
				own += 1
				var c1 := ui.get_pixel(x, y)
				if absf(c0.r - c1.r) + absf(c0.g - c1.g) + absf(c0.b - c1.b) > 0.06:
					changed += 1
		check("sombra de la capa de abajo NO tapa %s de encima" % tname, own > 20 and changed <= maxi(2, own / 50), "%d de %d px cambian" % [changed, own])
		if changed > maxi(2, own / 50):
			ui.get_region(Rect2i(u_in.grow(80))).save_png(out + "/tapado_%s.png" % tname)
		for n3 in [top2, low2]:
			n3.get_parent().remove_child(n3)
			n3.queue_free()
		await frames(2)

	print("RESULT %s (%d fallos)" % ["OK" if fails == 0 else "FALLOS", fails])
	quit(1 if fails > 0 else 0)
