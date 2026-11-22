## E2E VAL-43: máscaras anidadas. Franja vertical (x 300–500) que recorta a
## una franja horizontal (y 250–350) que recorta un rectángulo rojo: solo debe
## verse rojo en el CRUCE. En pantalla, tras editar, en el PNG, en el SVG y
## al reabrir.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func px(ab: Node2D, p: Vector2) -> Color:
	var img := root.get_texture().get_image()
	var sp: Vector2 = K.canvas.get_viewport().get_canvas_transform() * (ab.global_position + p)
	return img.get_pixelv(Vector2i(sp))

func is_red(c: Color) -> bool:
	return c.r > 0.7 and c.g < 0.3 and c.b < 0.3

func check_cross(ab: Node2D, label: String, sample: Callable) -> void:
	var inside: Color = sample.call(Vector2(400, 300))
	var out_v: Color = sample.call(Vector2(400, 150))   # dentro de la vertical, fuera de la horizontal
	var out_h: Color = sample.call(Vector2(150, 300))   # dentro de la horizontal, fuera de la vertical
	K.check("%s: rojo en el cruce" % label, is_red(inside), str(inside))
	K.check("%s: la máscara interior recorta (no rojo fuera de la horizontal)" % label, not is_red(out_v), str(out_v))
	K.check("%s: la exterior recorta (no rojo fuera de la vertical)" % label, not is_red(out_h), str(out_h))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://nested_masks")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(800, 600), "Máscaras", Color.WHITE)
	var red = api.add_rect(Vector2(400, 300), Vector2(800, 600), 0.0, "Rojo")
	api.set_props(red, {"fill_color": Color(0.9, 0.1, 0.1), "stroke_width": 0.0})
	var band = api.add_rect(Vector2(400, 300), Vector2(800, 100), 0.0, "Horizontal")
	api.set_props(band, {"fill_color": Color(1, 1, 1, 0), "stroke_width": 0.0})
	var strip = api.add_rect(Vector2(400, 300), Vector2(200, 600), 0.0, "Vertical")
	api.set_props(strip, {"fill_color": Color(1, 1, 1, 0), "stroke_width": 0.0})
	K.check("máscara interior", api.make_mask(band, [red]))
	K.check("máscara exterior con la interior dentro (antes se rechazaba)", api.make_mask(strip, [band]))
	await K.look_at(ab)
	await K.frames(8)
	await RenderingServer.frame_post_draw
	check_cross(ab, "pantalla", func(p: Vector2) -> Color: return px(ab, p))
	# Editar el contenido: la copia se rehace
	api.set_props(red, {"fill_color": Color(0.1, 0.2, 0.9)})
	await K.frames(8)
	await RenderingServer.frame_post_draw
	var c2: Color = px(ab, Vector2(400, 300))
	K.check("editar el contenido se ve (azul en el cruce)", c2.b > 0.7 and c2.r < 0.3, str(c2))
	api.undo()
	await K.frames(8)
	await RenderingServer.frame_post_draw
	K.check("deshacer: rojo otra vez", is_red(px(ab, Vector2(400, 300))))
	K.check("el contenido se sigue pudiendo seleccionar", api.select([red]) == null and api.selection() == [red])
	api.select([])
	# PNG
	var png := ProjectSettings.globalize_path("user://nested_masks/cruce.png")
	var ok: bool = await api.export(png, ab)
	var img := Image.load_from_file(png) if ok else null
	if img:
		check_cross(ab, "PNG", func(p: Vector2) -> Color: return img.get_pixelv(Vector2i(p)))
	else:
		K.check("PNG exportado", false)
	# SVG: el recorte es la intersección (un cuadrado 200 × 100)
	var svg := ProjectSettings.globalize_path("user://nested_masks/cruce.svg")
	await api.export(svg, ab)
	var txt := FileAccess.get_file_as_string(svg)
	K.check("SVG con recorte", txt.contains("clipPath"))
	var re := RegEx.new()
	re.compile("<clipPath id=\"c[0-9]+\"><path d=\"([^\"]+)\"")
	var m := re.search(txt)
	var d := m.get_string(1) if m else ""
	K.check("el recorte del SVG es el cruce (x 300–500, y 250–350)", d.contains("300") and d.contains("500") and d.contains("250") and d.contains("350") and not d.contains(" 0 "), d)
	# Reabrir
	var abs: Array = await K.save_reload("cruce")
	await K.frames(10)
	await RenderingServer.frame_post_draw
	for a in abs:
		if String(a.name) == "Máscaras":
			await K.look_at(a)
			await K.frames(8)
			await RenderingServer.frame_post_draw
			check_cross(a, "reabierto", func(p: Vector2) -> Color: return px(a, p))
	await K.shot("cruce")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
