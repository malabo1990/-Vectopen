## E2E herramienta Luz (barra de herramientas ☀) y panel Iluminación, con
## ratón real: elegir «Foco» en el panel, arrastrar en el lienzo (alcance y
## dirección), la luz queda seleccionada y el panel la edita (deshacer);
## sombras por defecto, «Proyecta sombra», tipos ambiente / direccional.
## En Modern (barra inferior) y Smart (columna de herramientas).
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(280.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func drag(a_g: Vector2, b_g: Vector2) -> void:
	var tf: Transform2D = K.canvas.get_viewport().get_canvas_transform()
	var a := tf * a_g
	var b := tf * b_g
	var m0 := InputEventMouseMotion.new()
	m0.position = a
	m0.global_position = a
	_send(m0)
	await K.frames(2)
	var d := InputEventMouseButton.new()
	d.position = a
	d.global_position = a
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(d)
	await K.frames(2)
	for i in range(1, 9):
		var m := InputEventMouseMotion.new()
		m.position = a.lerp(b, i / 8.0)
		m.global_position = m.position
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(m)
		await process_frame
	var u := InputEventMouseButton.new()
	u.position = b
	u.global_position = b
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	_send(u)
	await K.frames(6)

func panel() -> Control:
	for n in root.find_children("light", "PanelContainer", true, false):
		return n
	return null

func lights() -> Array:
	return get_nodes_in_group("_vectopen_lights")

func run_mode(mode: String) -> void:
	if not await K.boot(mode):
		K.check("%s arranca" % mode, false)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(900, 600), "Luz " + mode, Color(0.3, 0.3, 0.3))
	var wall = api.add_rect(Vector2(500, 300), Vector2(40, 200), 0.0, "Muro")
	var deco = api.add_ellipse(Vector2(700, 150), Vector2(60, 60), "Adorno")
	await K.look_at(ab)
	api.select([])
	await K.frames(3)
	# Botón ☀ de la barra
	var btn: BaseButton = null
	if mode == "modern":
		for n in root.find_children("*", "", true, false):
			if n.get_script() and String(n.get_script().resource_path).ends_with("modern_bottom_toolbar.gd"):
				btn = n._buttons.get("light")
	else:
		for n in root.find_children("button_toollight", "Button", true, false):
			if (n as Control).is_visible_in_tree():
				btn = n
	K.check("%s: botón Luz en la barra de herramientas" % mode, btn != null)
	if btn == null:
		return
	btn.pressed.emit()
	await K.frames(6)
	var p := panel()
	K.check("%s: se abre el panel Iluminación" % mode, p != null and p.is_visible_in_tree())
	K.check("%s: la herramienta activa es Luz" % mode, String(K.canvas.current_tool.get_script().resource_path).ends_with("LightTool.gd"))
	# Tipo Foco en el panel
	var spot_b: Button = p.find_child("Type_spot", true, false)
	K.check("%s: el panel ofrece los tipos (foco, ambiente…)" % mode, spot_b != null and p.find_child("Type_ambient", true, false) != null)
	spot_b.pressed.emit()
	await K.frames(2)
	K.check("%s: con Foco se ve la fila «Apertura»" % mode, (p.find_child("Light_cone", true, false) as Control).visible)
	var n0 := lights().size()
	var a_g: Vector2 = ab.to_global(Vector2(250, 300))
	await drag(a_g, ab.to_global(Vector2(450, 300)))
	K.check("%s: arrastrar en el lienzo coloca la luz" % mode, lights().size() == n0 + 1)
	var L: Node = null
	for l in lights():
		if not l.is_queued_for_deletion():
			L = l
	K.check("%s: es un foco, alcance ≈ 200 y apuntando a la derecha" % mode, L != null and String(L.lamp_type) == "spot" and absf(float(L.lamp_radius) - 200.0) < 8.0 and absf(float(L.lamp_angle)) < 5.0, "%s %s %s" % [L.lamp_type, L.lamp_radius, L.lamp_angle] if L else "-")
	K.check("%s: queda seleccionada" % mode, api.selection() == [L])
	await K.frames(3)
	K.check("%s: sombras por defecto (el muro tiene sombra exterior)" % mode, wall.get_node_or_null("_LightShadow") != null)
	await K.frames(3)
	K.check("%s: el panel edita la luz seleccionada" % mode, String(p._hint.text).contains("seleccionada") and p.is_visible_in_tree())
	var nf = p.find_child("Light_energy", true, false)
	nf.value_changed.emit(250.0)
	await K.frames(2)
	K.check("%s: intensidad 250 %% desde el panel" % mode, absf(float(L.lamp_energy) - 2.5) < 0.01, str(L.lamp_energy))
	api.undo()
	await K.frames(2)
	K.check("%s: deshacer la intensidad" % mode, absf(float(L.lamp_energy) - 1.2) < 0.01, str(L.lamp_energy))
	# La caja de selección y la luz no se iluminan (antes azul → cian)
	var bb_ok := true
	for bbn in root.find_children("*", "", true, false):
		if bbn.get_script() and String(bbn.get_script().resource_path).ends_with("bounding_box.gd") and (bbn as CanvasItem).is_visible_in_tree():
			bb_ok = bb_ok and (bbn as CanvasItem).light_mask == 0
	K.check("%s: la caja de selección no la tiñe la luz (sin cian)" % mode, bb_ok and L.light_mask == 0)
	await RenderingServer.frame_post_draw
	var img_c := root.get_texture().get_image()
	var cyan := 0
	var blue := 0
	for yy in range(0, img_c.get_height(), 2):
		for xx in range(0, img_c.get_width(), 2):
			var cc := img_c.get_pixel(xx, yy)
			if cc.r < 0.25 and cc.g > 0.8 and cc.b > 0.8: cyan += 1
			if cc.r < 0.15 and cc.g > 0.4 and cc.g < 0.67 and cc.b > 0.8: blue += 1
	K.check("%s: la caja se ve AZUL como las demás (no cian)" % mode, cyan == 0 and blue > 50, "cian %d, azul %d" % [cyan, blue])
	# Tirador del alcance: arrastrar con el ratón cambia alcance y dirección
	var lh = load("res://script_gdscript/tools/move/light_handles.gd").new()
	lh.light = L
	var reach: Vector2 = lh.points()["reach"]
	var r0 := float(L.lamp_radius)
	await drag(reach, L.global_position + Vector2(0, 300) * ab.global_transform.get_scale().x)
	K.check("%s: tirador ● del alcance: 300 y hacia abajo" % mode, absf(float(L.lamp_radius) - 300.0) < 6.0 and absf(float(L.lamp_angle) - 90.0) < 3.0, "%s %s" % [L.lamp_radius, L.lamp_angle])
	api.undo()
	await K.frames(3)
	K.check("%s: UN Ctrl+Z deshace el arrastre" % mode, absf(float(L.lamp_radius) - r0) < 0.5 and absf(float(L.lamp_angle)) < 5.0, "%s %s" % [L.lamp_radius, L.lamp_angle])
	var cone_p: Vector2 = lh.points()["cone"]
	await drag(cone_p, L.global_position + Vector2.from_angle(deg_to_rad(40.0)) * 120.0)
	K.check("%s: tirador ◆ de la apertura del foco (≈ 80°)" % mode, absf(float(L.lamp_cone) - 80.0) < 6.0, str(L.lamp_cone))
	# Panel: Restablecer
	api.select([L])
	await K.frames(3)
	(p.find_child("Reset", true, false) as Button).pressed.emit()
	await K.frames(3)
	K.check("%s: «Restablecer» vuelve a los valores de fábrica" % mode, absf(float(L.lamp_cone) - 45.0) < 0.5 and absf(float(L.lamp_energy) - 1.2) < 0.01)
	api.undo()
	await K.frames(3)
	K.check("%s: y se puede deshacer" % mode, absf(float(L.lamp_cone) - 80.0) < 6.0, str(L.lamp_cone))
	K.check("%s: panel con tarjetas (tipo, luz, sombra)" % mode, p.find_child("Card_TIPO_DE_LUZ", true, false) != null and p.find_child("Card_SOMBRA", true, false) != null)
	# «Proyecta sombra» en una figura
	api.select([deco])
	await K.frames(3)
	var ic = root.get_node("InspectorCore")
	K.check("%s: las figuras ofrecen «Proyecta sombra»" % mode, ic.current_props().has("casts_shadow"))
	ic.apply("casts_shadow", false)
	await K.frames(4)
	K.check("%s: sin sombra, el adorno pierde su sombra" % mode, deco.get_node_or_null("_LightShadow") == null and wall.get_node_or_null("_LightShadow") != null)
	# Ambiente y direccional desde el panel (luz seleccionada)
	api.select([L])
	await K.frames(3)
	(p.find_child("Type_ambient", true, false) as Button).pressed.emit()
	await K.frames(2)
	K.check("%s: cambiar a ambiente (sin filas de alcance ni sombra)" % mode, String(L.lamp_type) == "ambient" and not (p.find_child("Light_radius", true, false) as Control).visible and not (p.find_child("Light_shadows", true, false) as Control).visible)
	(p.find_child("Type_directional", true, false) as Button).pressed.emit()
	await K.frames(4)
	await K.shot("luz_" + mode)
	api.delete([L])
	await K.frames(6)
	K.check("%s: borrar la luz quita las sombras" % mode, wall.get_node_or_null("_LightShadow") == null or lights().size() > 0)

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://light_tool")
	await run_mode("modern")
	await run_mode("smart")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
