# =============================================================================
# FASE B · ENCARGO 29 — Vectorizar un logo bitmap (modo Modern)
# Foco: VTracer, limpieza de nodos.
# Se dibuja un logo de 3 colores en un PNG de 512 px (disco, anillo, barra),
# se coloca como imagen y se vectoriza con el preset «Logo / icono». Se
# comprueba que salen trazados con los colores del logo, que la imagen
# original queda oculta, que «Simplificar trazado» quita nodos sin cambiar
# la forma (± tolerancia), deshacer, recolorear, exportar SVG ligero, reabrir.
#   test/run_e2e.sh proyecto_29_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/29"
const NAVY := Color("#1d3557")
const RED := Color("#e63946")
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(560.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

## Logo en mapa de bits con borde suave (supermuestreo 2×2).
func logo_image() -> Image:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var c := Vector2(256, 256)
	for y in n:
		for x in n:
			var acc := Color(0, 0, 0, 0)
			for sy in 2:
				for sx in 2:
					var p := Vector2(x + 0.25 + sx * 0.5, y + 0.25 + sy * 0.5)
					var d := p.distance_to(c)
					var col := Color.WHITE
					if d < 200 and d > 160:
						col = NAVY
					elif d < 120:
						col = RED
					if absf(p.y - 256) < 22 and p.x > 60 and p.x < 452 and d >= 120 and d <= 160:
						col = NAVY
					acc += col
			img.set_pixel(x, y, acc / 4.0)
	return img

func colors_of(g: Node) -> Array:
	var out := []
	for d in g.find_children("*", "", true, false):
		if "fill_color" in d:
			var fc: Color = d.fill_color
			if fc.a > 0.5 and not out.any(func(o) -> bool: return (o as Color).is_equal_approx(fc)):
				out.append(fc)
	return out

func near(c: Color, ref: Color) -> bool:
	return absf(c.r - ref.r) + absf(c.g - ref.g) + absf(c.b - ref.b) < 0.2

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("modern"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(800, 800), "Logo", Color.WHITE)
	if not ClassDB.class_exists("VectorizerJob"):
		K.check("vectorizador nativo disponible", false)
		print("RESULT: 1 FAIL")
		quit(1)
		return
	var sprite = api.add_image(logo_image(), Vector2(400, 400), "Logo escaneado")
	await K.frames(4)
	var t0 := Time.get_ticks_msec()
	var g: Node2D = await api.vectorize(sprite, "Logo / icono", true)
	K.note("vectorizar_ms", Time.get_ticks_msec() - t0)
	K.check("vectorizado en trazados", g != null and api._paths_in(g).size() >= 2, str(api._paths_in(g).size()) if g else "-")
	K.check("la imagen original queda oculta", not sprite.visible)
	if g == null:
		print("RESULT: %d FAIL" % K.fails)
		quit(1)
		return
	var cols := colors_of(g)
	K.check("salen el azul y el rojo del logo", cols.any(func(c) -> bool: return near(c, NAVY)) and cols.any(func(c) -> bool: return near(c, RED)), str(cols.map(func(c): return "#" + (c as Color).to_html(false))))
	# Caja del vectorizado ≈ caja del logo (disco de 400 px de 512 → mismo tamaño en página)
	var r: Rect2 = K.ic._mt._global_rect(g)
	K.check("sin el fondo blanco: el vectorizado ocupa lo que el logo (≈ 400 px)", absf(r.size.x - 400.0) < 30.0 and absf(r.size.y - 400.0) < 30.0, str(r.size))
	# Limpieza de nodos
	await K.look_at(ab)
	await RenderingServer.frame_post_draw
	var img_a := root.get_texture().get_image()
	await K.shot("00_antes_de_simplificar")
	var n0: int = api.count_nodes(g)
	var removed: int = api.simplify_path(g, 1.5)
	var n1: int = api.count_nodes(g)
	K.note("nodos_antes", n0)
	K.note("nodos_despues", n1)
	K.check("«Simplificar trazado» quita nodos", removed > 0 and n1 < n0, "%d → %d" % [n0, n1])
	await K.frames(3)
	await RenderingServer.frame_post_draw
	var img_b := root.get_texture().get_image()
	var xf: Transform2D = K.canvas.get_viewport().get_canvas_transform()
	var box := Rect2i((xf * r).position, (r.size * xf.get_scale()))
	var diff := 0
	var total := 0
	for y in range(box.position.y, box.end.y, 2):
		for x in range(box.position.x, box.end.x, 2):
			total += 1
			var ca := img_a.get_pixel(x, y)
			var cb := img_b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.3:
				diff += 1
	var frac := float(diff) / maxf(1.0, total)
	K.note("simplificar_pixeles_distintos_pct", snappedf(frac * 100.0, 0.01))
	K.check("simplificar no cambia lo que se ve (< 1,5 % de píxeles)", frac < 0.015, "%.2f %%" % (frac * 100.0))
	var r2: Rect2 = K.ic._mt._global_rect(g)
	K.check("…sin cambiar la forma (caja ± 3 px)", r2.position.distance_to(r.position) < 3.0 and absf(r2.size.x - r.size.x) < 3.0, "%s / %s" % [r, r2])
	api.undo()
	K.check("deshacer la simplificación (un paso)", api.count_nodes(g) == n0, str(api.count_nodes(g)))
	api.redo()
	# Recolorear el rojo a verde de marca
	for p in api._paths_in(g):
		if near(p.fill_color, RED):
			api.set_fill(p, Color("#2a9d8f"))
	K.check("recolorear las piezas rojas", colors_of(g).any(func(c) -> bool: return near(c, Color("#2a9d8f"))))
	await K.look_at(ab)
	await K.shot("01_vectorizado")
	await K.undo_redo(4)
	var p_svg := ProjectSettings.globalize_path(OUT.path_join("logo.svg"))
	var ok: bool = await api.export(p_svg, ab)
	var size := FileAccess.get_file_as_bytes(p_svg).size() if ok else 0
	K.check("SVG ligero (< 60 KB) y sin la imagen", ok and size < 60000 and not FileAccess.get_file_as_string(p_svg).contains("<image"), "%d bytes" % size)
	await K.frames(10)
	var abs: Array = await K.save_reload("logo")
	for a in abs:
		if String(a.name) == "Logo":
			var paths2 := 0
			for d in a.find_children("*", "", true, false):
				if d is VectorPath:
					paths2 += 1
			K.check("reabrir: los trazados del logo", paths2 >= 2, str(paths2))
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
