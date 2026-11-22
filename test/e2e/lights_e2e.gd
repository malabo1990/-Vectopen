## E2E iluminación 2D (informe §2): luz puntual que aclara cerca y no lejos;
## sombras detrás de una figura; inspector con deshacer; guardar / abrir;
## el PNG exportado lleva la luz y no el símbolo.
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

func lum(c: Color) -> float:
	return (c.r + c.g + c.b) / 3.0

func shot_px(ab: Node2D, p: Vector2) -> float:
	await K.frames(4)
	await RenderingServer.frame_post_draw
	return lum(px(ab, p))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://lights")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(900, 600), "Luces", Color(0.25, 0.25, 0.25))
	var floor_r = api.add_rect(Vector2(450, 300), Vector2(900, 600), 0.0, "Suelo")
	api.set_props(floor_r, {"fill_color": Color(0.3, 0.3, 0.3), "stroke_width": 0.0})
	await K.look_at(ab)
	var near_p := Vector2(250, 300)
	var far_p := Vector2(820, 80)
	var behind_p := Vector2(560, 300)
	var base_near: float = await shot_px(ab, near_p)
	var L = api.add_light(Vector2(200, 300), "point", {"radius": 300.0, "energy": 1.5, "color": Color(1, 1, 1), "shadows": false})
	K.check("se crea la luz", L != null and String(L.get_meta("shape_type", "")) == "light")
	var lit_near: float = await shot_px(ab, near_p)
	var lit_far: float = await shot_px(ab, far_p)
	K.check("aclara cerca de la luz", lit_near > base_near + 0.15, "%.2f → %.2f" % [base_near, lit_near])
	K.check("no fuera de su alcance", absf(lit_far - base_near) < 0.05, "%.2f" % lit_far)
	# Sombras: un muro entre la luz y el punto de detrás
	var wall = api.add_rect(Vector2(420, 300), Vector2(30, 200), 0.0, "Muro")
	api.set_props(wall, {"fill_color": Color(0.1, 0.1, 0.1), "stroke_width": 0.0})
	api.select([L])
	await K.frames(3)
	var ic = root.get_node("InspectorCore")
	K.check("el inspector ofrece las opciones de la luz", ic.current_props().has("lamp_radius") and ic.current_props().has("lamp_shadows"))
	ic.apply("lamp_radius", 500.0)
	api.select([])
	var no_shadow: float = await shot_px(ab, behind_p)
	api.select([L])
	await K.frames(2)
	ic.apply("lamp_shadows", true)
	api.select([])
	var with_shadow: float = await shot_px(ab, behind_p)
	api.select([])
	print("SOMBRA sin=%.3f con=%.3f base=%.3f" % [no_shadow, with_shadow, base_near])
	K.check("con sombras, detrás del muro queda oscuro", with_shadow < no_shadow - 0.05, "%.2f vs %.2f" % [with_shadow, no_shadow])
	K.check("el muro tiene su oclusor interno", wall.get_node_or_null("_LightOccluder") != null)
	api.undo()
	await K.frames(3)
	K.check("deshacer (sombras)", not bool(L.lamp_shadows))
	api.redo()
	await K.frames(3)
	# Guardar / abrir
	var abs: Array = await K.save_reload("luces")
	var L2: Node = null
	for a in abs:
		for n in a.find_children("*", "Node2D", true, false):
			if String(n.get_meta("shape_type", "")) == "light":
				L2 = n
	K.check("reabrir: la luz y sus ajustes", L2 != null and bool(L2.lamp_shadows) and absf(float(L2.lamp_radius) - 500.0) < 0.5)
	await K.frames(4)
	var wall2: Node = L2.get_parent().find_child("Muro", true, false) if L2 else null
	K.check("reabrir: el muro vuelve a tener su oclusor", wall2 != null and wall2.get_node_or_null("_LightOccluder") != null)
	K.check("reabrir: el oclusor no se guardó como figura", L2 != null and L2.get_parent().find_children("_LightOccluder*", "", true, false).size() <= 2)
	# PNG
	if L2:
		var ab2: Node2D = L2.get_parent() as Node2D
		while ab2 and not ("artboard_size" in ab2):
			ab2 = ab2.get_parent()
		var png := ProjectSettings.globalize_path("user://lights/luces.png")
		var ok: bool = await api.export(png, ab2)
		var img := Image.load_from_file(png) if ok else null
		K.check("PNG con la luz", img != null and lum(img.get_pixelv(Vector2i(near_p))) > base_near + 0.15, str(img.get_pixelv(Vector2i(near_p))) if img else "-")
		var sym := img.get_pixelv(Vector2i(200, 300)) if img else Color.BLACK
		K.check("PNG sin el símbolo amarillo de la luz", not (sym.r > 0.9 and sym.b < 0.3), str(sym))
	await K.look_at(abs[0] if not abs.is_empty() else ab)
	await K.shot("luces")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
