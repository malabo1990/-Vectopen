## E2E: modos de fusión del panel Capas (antes no hacían nada). Fondo de
## color + figura encima; cada modo cambia el píxel como dice su fórmula; con
## el desplegable real del panel, deshacer, grupo (los hijos heredan),
## guardar/abrir y exportar PNG.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(400.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func px(ab: Node2D, p: Vector2) -> Color:
	var img := root.get_texture().get_image()
	var sp: Vector2 = K.canvas.get_viewport().get_canvas_transform() * (ab.global_position + p)
	return img.get_pixelv(Vector2i(sp))

func near(a: Color, b: Color, tol := 0.06) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://blend_modes")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(800, 600), "Fusión", Color.WHITE)
	var bg = api.add_rect(Vector2(400, 300), Vector2(800, 600), 0.0, "Fondo")
	api.set_props(bg, {"fill_color": Color(0.8, 0.2, 0.2), "stroke_width": 0.0})
	var top = api.add_rect(Vector2(400, 300), Vector2(300, 300), 0.0, "Encima")
	api.set_props(top, {"fill_color": Color(0.5, 0.5, 0.5), "stroke_width": 0.0})
	await K.look_at(ab)
	# Desplegable real del panel Capas
	var ls: Node = null
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == "LayerSystem":
			ls = n
	var opt: OptionButton = ls._opt_blend_mode if ls else null
	K.check("el panel Capas tiene el desplegable de fusión", opt != null)
	api.select([top])
	await K.frames(4)
	var b := Color(0.8, 0.2, 0.2)
	var s := Color(0.5, 0.5, 0.5)
	var expect := {
		"Normal": s,
		"Multiplicar": Color(b.r * s.r, b.g * s.g, b.b * s.b),
		"Pantalla": Color(b.r + s.r - b.r * s.r, b.g + s.g - b.g * s.g, b.b + s.b - b.b * s.b),
		"Aclarar": Color(maxf(b.r, s.r), maxf(b.g, s.g), maxf(b.b, s.b)),
		"Oscurecer": Color(minf(b.r, s.r), minf(b.g, s.g), minf(b.b, s.b)),
		"Diferencia": Color(absf(b.r - s.r), absf(b.g - s.g), absf(b.b - s.b)),
		"Superponer": Color(1.0 - 2.0 * (1.0 - b.r) * (1.0 - s.r), 2.0 * b.g * s.g, 2.0 * b.b * s.b),
	}
	for label in expect:
		if opt:
			for i in opt.item_count:
				if opt.get_item_text(i) == label:
					opt.select(i)
					opt.item_selected.emit(i)
		await K.frames(4)
		await RenderingServer.frame_post_draw
		var c := px(ab, Vector2(400, 300))
		K.check("%s: el color sigue su fórmula" % label, near(c, expect[label], 0.08), "%s vs %s" % [c, expect[label]])
	K.check("el inspector lee el modo", String(api.get_prop(top, "blend_mode")) == "Superponer")
	api.undo()
	await K.frames(3)
	K.check("deshacer vuelve al modo anterior", String(api.get_prop(top, "blend_mode")) == "Diferencia")
	# Grupo: los hijos heredan
	var a1 = api.add_ellipse(Vector2(150, 150), Vector2(120, 120), "Hijo 1")
	api.set_props(a1, {"fill_color": Color(0.5, 0.5, 0.5), "stroke_width": 0.0})
	var g = api.group([a1], "Grupo fusión")
	api.set_prop(g, "blend_mode", "Multiplicar")
	await K.frames(4)
	await RenderingServer.frame_post_draw
	var cg := px(ab, Vector2(150, 150))
	K.check("grupo en Multiplicar: el hijo multiplica", near(cg, expect["Multiplicar"], 0.08), str(cg))
	# Guardar / abrir
	api.set_prop(top, "blend_mode", "Pantalla")
	var abs: Array = await K.save_reload("fusion")
	for a in abs:
		if String(a.name) == "Fusión":
			var t2: Node = a.find_child("Encima", false, false)
			K.check("reabrir: el modo se conserva", t2 != null and String(api.get_prop(t2, "blend_mode")) == "Pantalla")
			await K.look_at(a)
			await K.frames(6)
			await RenderingServer.frame_post_draw
			K.check("reabrir: y se ve", near(px(a, Vector2(400, 300)), expect["Pantalla"], 0.08), str(px(a, Vector2(400, 300))))
			var png := ProjectSettings.globalize_path("user://blend_modes/fusion.png")
			var ok: bool = await api.export(png, a)
			var img := Image.load_from_file(png) if ok else null
			K.check("PNG exportado con el modo", img != null and near(img.get_pixel(400, 300), expect["Pantalla"], 0.08), str(img.get_pixel(400, 300)) if img else "-")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
