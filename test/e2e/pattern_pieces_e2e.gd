## E2E VGSE fase 2: pincel de patrón con piezas de inicio / esquina / final.
## Tres figuras (lateral gris, inicio verde, final azul) + esquina amarilla en
## un trazo en «L»; se mira el color en pantalla en cada zona. Y la fila
## «Inicio / Esquina / Final» del panel Pincel aparece con «Patrón».
extends SceneTree

var K
var api
const OB = preload("res://script_gdscript/shapes/object_brush.gd")
const R = preload("res://script_gdscript/shapes/brush_stroke_render.gd")

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func px(ab: Node2D, p: Vector2) -> Color:
	var img := root.get_texture().get_image()
	var sp: Vector2 = K.canvas.get_viewport().get_canvas_transform() * (ab.global_position + p)
	return img.get_pixelv(Vector2i(sp))

func near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.12 and absf(a.g - b.g) < 0.12 and absf(a.b - b.b) < 0.12

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://pattern_pieces")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(900, 700), "Patrón", Color.WHITE)
	var shapes: Array = []
	for c in [Color(0.5, 0.5, 0.5), Color(0.1, 0.7, 0.2), Color(0.1, 0.3, 0.9), Color(0.95, 0.8, 0.1)]:
		var r = api.add_rect(Vector2(-500, -500), Vector2(40, 20), 0.0, "pieza")
		api.set_props(r, {"fill_color": c, "stroke_width": 0.0})
		shapes.append(r)
	var src: Array = OB.from_shapes(shapes, false)
	api.delete(shapes)
	var pts := PackedVector2Array()
	for i in 61:
		pts.append(Vector2(100 + i * 10.0, 150))
	for i in range(1, 41):
		pts.append(Vector2(700, 150 + i * 10.0))
	var l := Line2D.new()
	l.name = "Cenefa"
	l.points = pts
	l.width = 30.0
	l.default_color = Color.WHITE
	l.set_meta("brush_style", "object")
	l.set_meta("brush_obj", {"src": OB.to_data(src), "params": {"mode": "pattern", "spacing": 1.0,
		"start_piece": 1, "end_piece": 2, "corner_piece": 3}})
	api.add(l)
	R.attach(l)
	await K.look_at(ab)
	await K.frames(8)
	await RenderingServer.frame_post_draw
	await K.shot("cenefa")
	K.check("inicio con la pieza verde", near(px(ab, Vector2(110, 150)), Color(0.1, 0.7, 0.2)), str(px(ab, Vector2(110, 150))))
	K.check("lateral gris", near(px(ab, Vector2(400, 150)), Color(0.5, 0.5, 0.5)), str(px(ab, Vector2(400, 150))))
	K.check("final con la pieza azul", near(px(ab, Vector2(700, 540)), Color(0.1, 0.3, 0.9)), str(px(ab, Vector2(700, 540))))
	var corner_hit := false
	for q in [Vector2(690, 150), Vector2(700, 160), Vector2(680, 150), Vector2(700, 170)]:
		if near(px(ab, q), Color(0.95, 0.8, 0.1)):
			corner_hit = true
	K.check("esquina con la pieza amarilla", corner_hit, str(px(ab, Vector2(690, 150))))
	# Pieza CENTRADA en el giro: se ve amarillo a los dos lados por igual
	var left_y := near(px(ab, Vector2(688, 150)), Color(0.95, 0.8, 0.1))
	var down_y := near(px(ab, Vector2(700, 162)), Color(0.95, 0.8, 0.1))
	K.check("la pieza de esquina está centrada en el giro (amarilla a ambos lados)", left_y and down_y, "%s %s" % [px(ab, Vector2(688, 150)), px(ab, Vector2(700, 162))])
	# Editar las piezas de un trazo YA dibujado desde el inspector
	var ic = root.get_node("InspectorCore")
	api.select([l])
	await K.frames(4)
	K.check("el inspector ofrece las piezas del trazo", ic.current_props().has("pattern_corner_piece") and int(ic.current_props()["pattern_corner_piece"]["value"]) == 4, str(ic.current_props().get("pattern_corner_piece")))
	ic.apply("pattern_corner_piece", 2.0)   # la figura 2 (verde) en las esquinas
	await K.frames(4)
	await RenderingServer.frame_post_draw
	var green := Color(0.1, 0.7, 0.2)
	K.check("Pieza de esquina 2 → la esquina pasa a la pieza verde (a ambos lados del giro)",
		near(px(ab, Vector2(688, 150)), green) and near(px(ab, Vector2(700, 162)), green), "%s %s" % [px(ab, Vector2(688, 150)), px(ab, Vector2(700, 162))])
	api.undo()
	await K.frames(4)
	await RenderingServer.frame_post_draw
	K.check("deshacer → vuelve la pieza de esquina", near(px(ab, Vector2(688, 150)), Color(0.95, 0.8, 0.1)))
	api.select([])
	await K.frames(2)
	# Guardar / abrir conserva las piezas
	var abs: Array = await K.save_reload("patron")
	var ok_reload := false
	for a in abs:
		var c: Node = a.find_child("Cenefa", true, false)
		if c:
			var prm: Dictionary = (c.get_meta("brush_obj", {}) as Dictionary).get("params", {})
			ok_reload = int(prm.get("start_piece", -1)) == 1 and int(prm.get("end_piece", -1)) == 2 and int(prm.get("corner_piece", -1)) == 3
	K.check("reabrir conserva las piezas", ok_reload)
	# Panel Pincel: la fila aparece con «Patrón»
	K.canvas.switch_tool("brush")
	await K.frames(6)
	var grid: Node = null
	for n in root.find_children("ObjPieces", "", true, false):
		grid = n
	K.check("el panel Pincel tiene la fila Inicio / Esquina / Final", grid != null)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
