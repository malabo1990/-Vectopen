## E2E informe §1: tipo de esquina (redonda / inversa / chaflán / muesca)
## desde el inspector; se ve, se deshace y sale en el SVG.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func px(ab: Node2D, p: Vector2) -> Color:
	var img := root.get_texture().get_image()
	var sp: Vector2 = K.canvas.get_viewport().get_canvas_transform() * (ab.global_position + p)
	return img.get_pixelv(Vector2i(sp))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://corner_styles")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(600, 400), "Esquinas", Color.WHITE)
	var r = api.add_rect(Vector2(300, 200), Vector2(300, 200), 0.0, "Placa")
	api.set_props(r, {"fill_color": Color(0.1, 0.4, 0.9), "stroke_width": 0.0, "corner_radius": 60.0})
	await K.look_at(ab)
	api.select([r])
	await K.frames(6)
	var ic = root.get_node("InspectorCore")
	K.check("el inspector ofrece «Tipo de esquina»", ic.current_props().has("corner_style"))
	var opt: OptionButton = null
	for n in root.find_children("Opt_corner_style", "", true, false):
		if (n as Control).is_visible_in_tree():
			opt = n
	if opt == null:
		for n in root.find_children("*corner_style*", "OptionButton", true, false):
			if (n as Control).is_visible_in_tree():
				opt = n
	K.check("hay un desplegable visible para el tipo", opt != null)
	# Punto a 15 px de la esquina superior izquierda, en diagonal:
	# redonda → fuera (blanco); inversa → también fuera; chaflán → fuera;
	# a 45 px en diagonal: redonda → dentro; inversa → FUERA (arco de 60 desde la punta)
	var tl := Vector2(150, 100)
	ic.apply("corner_style", "inverted")
	await K.frames(4)
	await RenderingServer.frame_post_draw
	var c_inv: Color = px(ab, tl + Vector2(38, 38))
	ic.apply("corner_style", "round")
	await K.frames(4)
	await RenderingServer.frame_post_draw
	var c_round: Color = px(ab, tl + Vector2(38, 38))
	K.check("inversa: el hueco cóncavo deja ver el fondo", c_inv.b > 0.95 and c_inv.r > 0.95, str(c_inv))
	K.check("redonda: ese punto está dentro", c_round.b > 0.8 and c_round.r < 0.3, str(c_round))
	ic.apply("corner_style", "chamfer")
	await K.frames(3)
	api.undo()
	await K.frames(3)
	K.check("deshacer vuelve a «redonda»", String(ic._read(r, "corner_style")) == "round")
	api.redo()
	await K.frames(3)
	var svg := ProjectSettings.globalize_path("user://corner_styles/placa.svg")
	await api.export(svg, ab)
	var txt := FileAccess.get_file_as_string(svg)
	K.check("SVG con el chaflán (trazado, sin rx)", txt.contains("<path") and not txt.contains(" rx="), txt.substr(0, 200))
	await K.shot("chaflan")
	ic.apply("corner_style", "zigzag")
	ic.apply("corner_style_br", "sawtooth")
	await K.frames(4)
	K.check("zigzag y sierra desde el inspector", String(ic._read(r, "corner_style_tl")) == "zigzag" and String(ic._read(r, "corner_style_br")) == "sawtooth")
	await K.shot("zigzag")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
