## E2E iluminación 2D — MATRIZ de tipos y direcciones, medida en PANTALLA:
##  · direccional en 5 direcciones: la sombra cae del lado contrario a la luz
##    (y no del lado de la luz);
##  · la sombra es 2D: más oscura junto a la figura y se desvanece hacia el
##    final; «Desvanecer» 0 la deja uniforme;
##  · influencia: el foco solo da sombra dentro de su cono; la puntual solo
##    dentro de su alcance; la ambiente nunca;
##  · la luz cae suave hasta el final de su alcance (sin corte);
##  · TIEMPO REAL: cambiar la dirección (código, panel, tirador a mitad del
##    arrastre) o mover la figura / la luz rehace la sombra en ese momento.
extends SceneTree

var K
var api
var ab: Node2D
var box: Node2D
const C := Vector2(450, 300)   # centro de la figura (coordenadas de página)

func _init() -> void:
	_run.call_deferred()
	create_timer(420.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

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
	await K.frames(4)
	await RenderingServer.frame_post_draw

## Oscurecimiento que da la sombra en `p`: luminancia sin sombra − con sombra.
func darkening(L: Node2D, p: Vector2) -> float:
	L.lamp_shadows = false
	await settle()
	var off := lum_at(p)
	L.lamp_shadows = true
	await settle()
	return off - lum_at(p)

func shadow_count() -> int:
	var sh = box.get_node_or_null("_LightShadow")
	return 0 if sh == null else (sh.shadows as Array).size()

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://light_matrix")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	ab = await K.artboard(Vector2(900, 600), "Matriz", Color(0.55, 0.55, 0.55))
	var floor_r = api.add_rect(Vector2(450, 300), Vector2(900, 600), 0.0, "Suelo")
	api.set_props(floor_r, {"fill_color": Color(0.55, 0.55, 0.55), "stroke_width": 0.0})
	floor_r.set_meta("casts_shadow", false)
	box = api.add_rect(C, Vector2(60, 60), 0.0, "Caja")
	api.set_props(box, {"fill_color": Color(0.9, 0.9, 0.9), "stroke_width": 0.0})
	await K.look_at(ab)

	# ── 1. Direccional en varias direcciones ─────────────────────────────────
	var L = api.add_light(Vector2(120, 120), "directional", {"energy": 0.4, "color": Color(1, 1, 1),
		"shadow_length": 150.0, "shadow_fade": 0.7, "shadow_soft": 0.2, "shadow_color": Color(0, 0, 0, 0.7)})
	for ang in [0.0, 90.0, 180.0, -90.0, 45.0]:
		L.lamp_angle = ang
		var dir := Vector2.from_angle(deg_to_rad(ang))
		var d_shadow: float = await darkening(L, C + dir * 60.0)
		var d_lit: float = await darkening(L, C - dir * 60.0)
		K.check("direccional %d°: sombra del lado contrario a la luz" % int(ang), d_shadow > 0.04, "%.3f" % d_shadow)
		K.check("direccional %d°: nada de sombra del lado de la luz" % int(ang), d_lit < 0.015, "%.3f" % d_lit)
	await K.shot("direccional_45")

	# ── 2. Sombra 2D: oscura junto a la figura, se desvanece hacia el final ──
	L.lamp_angle = 0.0
	var near: float = await darkening(L, C + Vector2(50, 0))
	var far: float = await darkening(L, C + Vector2(165, 0))
	K.check("la sombra se desvanece hacia su final", near > far + 0.03, "cerca %.3f, final %.3f" % [near, far])
	var beyond: float = await darkening(L, C + Vector2(260, 0))
	K.check("más allá de su longitud no hay sombra", beyond < 0.012, "%.3f" % beyond)
	L.lamp_shadow_fade = 0.0
	var far_u: float = await darkening(L, C + Vector2(165, 0))
	K.check("Desvanecer 0 → la sombra llega oscura al final", far_u > far + 0.02, "%.3f vs %.3f" % [far_u, far])
	L.lamp_shadow_fade = 0.7
	L.lamp_shadow_soft = 1.0
	var soft_edge: float = await darkening(L, C + Vector2(110, 38))
	L.lamp_shadow_soft = 0.0
	var hard_edge: float = await darkening(L, C + Vector2(110, 38))
	K.check("Difuminado: el borde de la sombra se difumina", soft_edge > hard_edge + 0.005, "%.3f vs %.3f" % [soft_edge, hard_edge])
	L.lamp_shadow_soft = 0.2
	await K.shot("sombra_desvanece")

	# ── 3. Tiempo real ───────────────────────────────────────────────────────
	L.lamp_angle = 180.0
	await K.frames(2)
	await RenderingServer.frame_post_draw
	K.check("tiempo real (código): al girar a 180° la sombra pasa a la izquierda",
		lum_at(C + Vector2(-60, 0)) < lum_at(C + Vector2(60, 0)) - 0.04)
	# panel: la luz seleccionada se edita y la sombra sigue al momento
	api.select([L])
	await K.frames(6)
	var spin: Node = null
	for n in root.find_children("Light_angle", "", true, false):
		if (n as Control).is_visible_in_tree():
			spin = n
	K.check("el panel muestra Dirección", spin != null)
	if spin:
		# escribir «90» en Dirección: la sombra gira MIENTRAS se escribe
		spin._enter_edit()
		spin._line_edit.text = "90"
		spin._line_edit.text_changed.emit("90")
		await K.frames(2)
		await RenderingServer.frame_post_draw
		K.check("tiempo real (panel): escribiendo 90 la sombra ya va abajo, sin pulsar Intro",
			absf(float(L.lamp_angle) - 90.0) < 1.0 and lum_at(C + Vector2(0, 60)) < lum_at(C + Vector2(0, -60)) - 0.04,
			"ángulo %s" % L.lamp_angle)
		spin._on_line_edit_submitted("90")
		await K.frames(3)
		K.check("Intro confirma 90", absf(float(L.lamp_angle) - 90.0) < 1.0)
		api.undo()
		await K.frames(3)
		K.check("un Ctrl+Z vuelve a 180 (el valor de antes de escribir)", absf(absf(float(L.lamp_angle)) - 180.0) < 1.0, "%s" % L.lamp_angle)
		api.redo()
		await K.frames(3)
		# Esc mientras se escribe: vuelve como estaba
		spin._enter_edit()
		spin._line_edit.text = "30"
		spin._line_edit.text_changed.emit("30")
		await K.frames(2)
		var mid_ang := float(L.lamp_angle)
		spin._exit_edit(false)
		await K.frames(2)
		K.check("Esc deshace la vista previa", absf(mid_ang - 30.0) < 1.0 and absf(float(L.lamp_angle) - 90.0) < 1.0, "%s → %s" % [mid_ang, L.lamp_angle])
	# tirador: a MITAD del arrastre la sombra ya ha girado
	if K.canvas.current_tool == null or not String(K.canvas.current_tool.get_script().resource_path).ends_with("MoveTool.gd"):
		K.canvas.switch_tool("move")
		await K.frames(3)
		api.select([L])
		await K.frames(3)
	var lh = load("res://script_gdscript/tools/move/light_handles.gd").new()
	lh.light = L
	var tf: Transform2D = K.canvas.get_viewport().get_canvas_transform()
	var a: Vector2 = tf * lh.points()["reach"]
	var b: Vector2 = tf * (L.global_position + Vector2(-80, 0) * ab.global_transform.get_scale().x)
	var m0 := InputEventMouseMotion.new()
	m0.position = a
	m0.global_position = a
	_send(m0)
	await K.frames(2)
	var dn := InputEventMouseButton.new()
	dn.position = a
	dn.global_position = a
	dn.button_index = MOUSE_BUTTON_LEFT
	dn.pressed = true
	dn.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(dn)
	await K.frames(2)
	for i in range(1, 7):
		var mm := InputEventMouseMotion.new()
		mm.position = a.lerp(b, i / 6.0)
		mm.global_position = mm.position
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(mm)
		await process_frame
	await K.frames(2)
	await RenderingServer.frame_post_draw
	K.check("tiempo real (tirador): a mitad del arrastre la sombra ya va a la izquierda",
		absf(absf(float(L.lamp_angle)) - 180.0) < 6.0 and lum_at(C + Vector2(-60, 0)) < lum_at(C + Vector2(60, 0)) - 0.04,
		"ángulo %s" % L.lamp_angle)
	await K.shot("tirador_mitad")
	var up := InputEventMouseButton.new()
	up.position = b
	up.global_position = b
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	_send(up)
	await K.frames(6)
	# mover la figura: la sombra va con ella
	box.position += Vector2(0, 80)
	await settle()
	K.check("mover la figura: su sombra va con ella", lum_at(C + Vector2(-60, 80)) < lum_at(C + Vector2(60, 80)) - 0.04)
	box.position -= Vector2(0, 80)
	api.select([])
	L.queue_free()
	await K.frames(4)

	# ── 4. Foco: solo dentro del cono ────────────────────────────────────────
	var S = api.add_light(C + Vector2(-200, 0), "spot", {"energy": 1.0, "radius": 500.0, "cone": 40.0,
		"angle": 0.0, "color": Color(1, 1, 1), "shadow_length": 150.0, "shadow_color": Color(0, 0, 0, 0.7)})
	await settle()
	K.check("foco hacia la figura: hay sombra", shadow_count() == 1)
	var d_spot: float = await darkening(S, C + Vector2(60, 0))
	K.check("foco hacia la figura: la sombra cae detrás (a la derecha)", d_spot > 0.03, "%.3f" % d_spot)
	await K.shot("foco_dentro")
	S.lamp_angle = 180.0
	await settle()
	K.check("foco hacia otro lado: la figura NO tiene sombra (fuera del cono)", shadow_count() == 0)
	S.lamp_angle = 60.0   # cono de 40° → la figura (a 0°) queda fuera
	await settle()
	K.check("foco desviado 60° (cono 40°): sin sombra", shadow_count() == 0)
	await K.shot("foco_fuera")
	S.lamp_angle = 0.0
	# la luz del foco cae suave hasta el final (sin corte)
	S.lamp_shadows = false
	await settle()
	var l1 := lum_at(C + Vector2(-200 + 150, 0) + Vector2(0, -20))
	var l2 := lum_at(S.position + Vector2(300, -20))
	var l3 := lum_at(S.position + Vector2(450, -20))
	var l4 := lum_at(S.position + Vector2(520, -20))
	K.check("la luz se apaga poco a poco hacia el final del alcance", l1 > l2 and l2 > l3 and l3 >= l4 - 0.005, "%.3f %.3f %.3f %.3f" % [l1, l2, l3, l4])
	K.check("cerca del final apenas queda luz (sin corte brusco)", l3 - l4 < 0.05, "%.3f→%.3f" % [l3, l4])
	S.queue_free()
	await K.frames(4)

	# ── 5. Puntual: dentro / fuera del alcance; dirección según su posición ──
	var P = api.add_light(C + Vector2(0, -150), "point", {"energy": 1.0, "radius": 450.0,
		"color": Color(1, 1, 1), "shadow_length": 150.0, "shadow_color": Color(0, 0, 0, 0.7)})
	await settle()
	var d_pt: float = await darkening(P, C + Vector2(0, 60))
	K.check("puntual encima: la sombra cae abajo", d_pt > 0.03, "%.3f" % d_pt)
	P.position = C + Vector2(150, 0)
	await settle()
	var d_pt2: float = await darkening(P, C + Vector2(-60, 0))
	K.check("tiempo real: mover la luz a la derecha → sombra a la izquierda", d_pt2 > 0.03, "%.3f" % d_pt2)
	P.lamp_radius = 100.0   # la figura (a 150 px) queda fuera del alcance
	await settle()
	K.check("puntual sin alcance hasta la figura: sin sombra", shadow_count() == 0)
	await K.shot("puntual")
	P.queue_free()
	await K.frames(4)

	# ── 6. Ambiente: aclara todo, nunca sombra ───────────────────────────────
	var A = api.add_light(C + Vector2(-200, -150), "ambient", {"energy": 0.5, "color": Color(1, 1, 1)})
	await settle()
	K.check("ambiente: sin sombra", shadow_count() == 0)
	A.queue_free()
	await K.frames(4)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
