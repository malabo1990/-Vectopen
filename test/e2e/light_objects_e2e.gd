## E2E iluminación: SOMBRA de textos, párrafos, trazos de pincel y trazados
## Bézier (abiertos y cerrados), no solo de las figuras. Luz direccional
## hacia la derecha: a la derecha de cada objeto se oscurece (medido en
## pantalla, con la sombra apagada / encendida).
extends SceneTree

var K
var api
var ab: Node2D

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func lum_at(p: Vector2) -> float:
	var img := root.get_texture().get_image()
	var sp: Vector2 = K.canvas.get_viewport().get_canvas_transform() * ab.to_global(p)
	var acc := 0.0
	for dx in [-2, 0, 2]:
		for dy in [-2, 0, 2]:
			var c := img.get_pixelv(Vector2i(sp) + Vector2i(dx, dy))
			acc += (c.r + c.g + c.b) / 3.0
	return acc / 9.0

func settle() -> void:
	await K.frames(5)
	await RenderingServer.frame_post_draw

func darkening(L: Node2D, p: Vector2) -> float:
	L.lamp_shadows = false
	await settle()
	var off := lum_at(p)
	L.lamp_shadows = true
	await settle()
	return off - lum_at(p)

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://light_objects")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	ab = await K.artboard(Vector2(1000, 700), "Sombras de todo", Color(0.8, 0.8, 0.8))
	await K.look_at(ab)
	# texto grande
	var t = api.add_text(Vector2(60, 60), "SOMBRA", 72, Color(0.15, 0.15, 0.6))
	# párrafo
	var p = api.add_text_box(Rect2(60, 220, 300, 120), "Texto de párrafo con varias líneas para la sombra.", 28, Color(0.1, 0.1, 0.1))
	# trazo de pincel
	var l := Line2D.new()
	l.name = "Pincel"
	l.points = PackedVector2Array([Vector2(520, 100), Vector2(620, 160), Vector2(720, 110), Vector2(820, 170)])
	l.width = 18.0
	l.default_color = Color(0.6, 0.1, 0.1)
	l.set_meta("brush_style", "pen")
	ab.add_child(l)
	load("res://script_gdscript/shapes/brush_stroke_render.gd").attach(l)
	# Bézier abierto (solo trazo) y cerrado (relleno)
	var bo = api.add_path(PackedVector2Array([Vector2(520, 320), Vector2(640, 380), Vector2(760, 320)]), false, "Bézier abierto")
	api.set_props(bo, {"stroke_width": 12.0, "stroke_color": Color(0.1, 0.4, 0.1)})
	var bc = api.add_path(PackedVector2Array([Vector2(520, 480), Vector2(640, 460), Vector2(660, 580), Vector2(540, 600)]), true, "Bézier cerrado")
	api.set_props(bc, {"fill_color": Color(0.2, 0.5, 0.9), "stroke_width": 0.0})
	var L = api.add_light(Vector2(40, 40), "directional", {"energy": 1.5, "angle": 0.0, "color": Color(1, 1, 1),
		"shadow_length": 60.0, "shadow_fade": 0.2, "shadow_soft": 0.1, "shadow_color": Color(0, 0, 0, 0.8), "height": 0.5})
	await K.frames(20)
	var BL = load("res://script_gdscript/shapes/vector_light.gd")
	for n in [t, p, l, bo, bc]:
		K.check("«%s» tiene su sombra" % n.name, n.get_node_or_null("_LightShadow") != null and BL.shadow_polys(n).size() > 0, str(BL.shadow_polys(n).size()))
	# a la derecha (y un poco abajo, donde cae la sombra corrida) se oscurece
	var probes := {
		"texto": Vector2(60 + 300, 100),     # dentro de la sombra de las últimas letras
		"pincel": Vector2(838, 178),
		"Bézier abierto": Vector2(775, 324),
		"Bézier cerrado": Vector2(680, 560),
	}
	for k in probes:
		var d: float = await darkening(L, probes[k])
		K.check("la sombra de %s se ve en pantalla" % k, d > 0.03, "%.3f" % d)
	var tl: Node = t.get_node("DisplayLabel")
	K.check("la sombra del texto sigue las LETRAS (muchos polígonos)", BL.shadow_polys(t).size() >= 6, str(BL.shadow_polys(t).size()))
	# cambiar el texto rehace su sombra
	var n0: int = BL.shadow_polys(t).size()
	api.set_props(t, {"text": "SOMBRA LARGA"})   # como en la app: con historial
	await K.frames(12)
	K.check("cambiar el texto rehace su sombra", BL.shadow_polys(t).size() > n0, "%d → %d" % [n0, BL.shadow_polys(t).size()])
	# rendimiento: girar la luz con textos en escena
	var t0 := Time.get_ticks_usec()
	for i in 60:
		L.lamp_angle = float(i * 6)
		await process_frame
	var fps := 60.0 / ((Time.get_ticks_usec() - t0) / 1000000.0)
	print("BENCH luz_objetos_fps_girando=%.1f" % fps)
	K.check("girar la luz con textos y trazos va fluido (≥ 25 fps)", fps >= 25.0, "%.1f fps" % fps)
	L.lamp_angle = 20.0
	await settle()
	await K.shot("sombras_de_todo")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
