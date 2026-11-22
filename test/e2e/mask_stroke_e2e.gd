## E2E: el BORDE de la figura-máscara se ve ENCIMA del contenido recortado
## (como Illustrator; antes el contenido lo tapaba siempre). Sigue a la
## máscara al moverla, desaparece sin borde o sin máscara, no se guarda en
## el archivo y vuelve al reabrir.
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
	return img.get_pixelv(Vector2i(K.canvas.get_viewport().get_canvas_transform() * ab.to_global(p)))

func red(c: Color) -> bool:
	return c.r > 0.75 and c.g < 0.3 and c.b < 0.3

func shot_px(ab: Node2D, p: Vector2) -> Color:
	await K.frames(4)
	await RenderingServer.frame_post_draw
	return px(ab, p)

func overlays(parent: Node) -> int:
	return parent.get_children().filter(func(n) -> bool: return String(n.name).begins_with("_MaskStroke_")).size()

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://mask_stroke")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(800, 500), "Borde máscara", Color.WHITE)
	await K.look_at(ab)
	var c = api.add_rect(Vector2(400, 250), Vector2(500, 300), 0.0, "Contenido")
	api.set_props(c, {"fill_color": Color(0.2, 0.5, 0.9), "stroke_width": 0.0})
	var m = api.add_ellipse(Vector2(400, 250), Vector2(300, 200), "Máscara")
	api.set_props(m, {"fill_color": Color(1, 1, 1), "stroke_color": Color(0.9, 0.1, 0.1), "stroke_width": 10.0})
	api.make_mask(m, [c])
	var edge: Color = await shot_px(ab, Vector2(550, 250))
	K.check("el borde rojo de la máscara se ve encima del contenido", red(edge), str(edge))
	var mid: Color = await shot_px(ab, Vector2(400, 250))
	K.check("dentro se ve el contenido recortado", mid.b > 0.7 and mid.r < 0.4, str(mid))
	var out: Color = await shot_px(ab, Vector2(620, 250))
	K.check("fuera de la máscara no hay contenido", out.r > 0.9 and out.b > 0.9, str(out))
	# capas: no aparece la capa interna
	var lp = root.find_children("*", "Tree", true, false)
	var listed := false
	for t in lp:
		var it: TreeItem = (t as Tree).get_root()
		var stack: Array = [it]
		while not stack.is_empty():
			var x: TreeItem = stack.pop_back()
			if x == null:
				continue
			if x.get_text(0).begins_with("_MaskStroke"):
				listed = true
			for ch in x.get_children():
				stack.append(ch)
	K.check("el borde interno no sale en Capas", not listed)
	# mover la máscara: el borde la sigue
	api.set_props(m, {"position": m.position + Vector2(60, 0)})
	var edge2: Color = await shot_px(ab, Vector2(610, 250))
	K.check("al mover la máscara el borde la sigue", red(edge2), str(edge2))
	api.undo()
	await K.frames(3)
	# sin borde: no se dibuja
	api.set_props(m, {"stroke_width": 0.0})
	await K.frames(4)
	K.check("sin borde no hay capa de borde", overlays(m.get_parent()) == 0, str(overlays(m.get_parent())))
	api.undo()
	await K.frames(4)
	K.check("deshacer: vuelve el borde", overlays(m.get_parent()) == 1)
	# guardar / abrir: no se guarda, vuelve al abrir
	var abs: Array = await K.save_reload("borde")
	var m2: Node = null
	for x in abs:
		m2 = x.find_child("Máscara", true, false)
		if m2:
			break
	K.check("reabrir: la máscara vuelve con su borde (sin duplicados)", m2 != null and overlays(m2.get_parent()) == 1, str(overlays(m2.get_parent())) if m2 else "-")
	if m2:
		await K.look_at(m2.get_parent() if "artboard_size" in m2.get_parent() else abs[0])
		var e3: Color = await shot_px(m2.get_parent(), (m2 as Node2D).position + Vector2(150, 0))
		K.check("reabrir: el borde se ve", red(e3), str(e3))
	await K.shot("borde_mascara")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
