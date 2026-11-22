## E2E: «Tipo de esquina» en el panel Figuras · Rectángulo (Modern y Smart).
## Antes el redondeado inverso solo estaba en el inspector y el usuario no lo
## encontraba. Elegirlo cambia la forma (comprobada), se deshace con un paso y
## se aplica al crear un rectángulo nuevo desde el panel.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func panel() -> Control:
	for c in root.find_children("polygon", "Control", true, false):
		if (c as Control).is_visible_in_tree():
			return c
	return null

## ¿El punto a 0,35·r de la esquina ↗ (hacia dentro) está dentro de la figura?
## Redonda: sí. Redondeado inverso: no (la esquina se «muerde» hacia dentro).
func corner_filled(r: Node2D) -> bool:
	var rad: float = float(r.corner_radius)
	var p := Vector2(r.size.x * 0.5 - 0.35 * rad, -r.size.y * 0.5 + 0.35 * rad)
	return Geometry2D.is_point_in_polygon(p, r.get_effect_points())

func bbox() -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() and String(n.get_script().resource_path).ends_with("bounding_box.gd") and (n as CanvasItem).is_visible_in_tree():
			return n
	return null

func click_at(pos: Vector2, shift: bool, alt: bool, to: Vector2 = Vector2.INF) -> void:
	var dst := pos if to == Vector2.INF else to
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)
	await K.frames(2)
	var d := InputEventMouseButton.new()
	d.position = pos
	d.global_position = pos
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.shift_pressed = shift
	d.alt_pressed = alt
	Input.parse_input_event(d)
	await K.frames(2)
	if dst != pos:
		for i in range(1, 7):
			var m2 := InputEventMouseMotion.new()
			m2.position = pos.lerp(dst, i / 6.0)
			m2.global_position = m2.position
			m2.button_mask = MOUSE_BUTTON_MASK_LEFT
			m2.shift_pressed = shift
			Input.parse_input_event(m2)
			await K.frames(1)
	var u := InputEventMouseButton.new()
	u.position = dst
	u.global_position = dst
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.shift_pressed = shift
	u.alt_pressed = alt
	Input.parse_input_event(u)
	await K.frames(4)

## Mayús + clic en el tirador de redondeo: recorre los tipos de esquina.
func shift_click_cycle(mode: String) -> void:
	var r = api.add_rect(Vector2(150, 480), Vector2(160, 120), 24.0, "Ciclo")   # lejos de los paneles
	K.canvas.switch_tool("move")
	await K.frames(4)
	api.select([r])
	await K.frames(8)
	var bb := bbox()
	K.check("%s: caja de selección con tiradores de redondeo" % mode, bb != null and bb._radius_handle_centers(bb._zoom_comp(bb._get_zoom_scale())).size() == 4)
	if bb == null:
		return
	var hs: Array = bb._radius_handle_centers(bb._zoom_comp(bb._get_zoom_scale()))
	var h_tr: Vector2 = bb.get_screen_transform() * (hs[1] as Vector2)
	await click_at(h_tr, true, false)
	K.check("%s: Mayús+clic → Redondeado inverso en las 4 esquinas" % mode, Array(r.corner_styles) == [1, 1, 1, 1] and absf(float(r.corner_radius) - 24.0) < 0.01, str(r.corner_styles))
	await click_at(h_tr, true, false)
	K.check("%s: otro Mayús+clic → Chaflán" % mode, Array(r.corner_styles) == [2, 2, 2, 2], str(r.corner_styles))
	api.undo()
	await K.frames(3)
	K.check("%s: Ctrl+Z → vuelve a Redondeado inverso" % mode, Array(r.corner_styles) == [1, 1, 1, 1], str(r.corner_styles))
	await click_at(h_tr, true, true)
	K.check("%s: Mayús+Alt+clic → solo esa esquina cambia" % mode, Array(r.corner_styles) == [1, 2, 1, 1], str(r.corner_styles))
	var r0 := float(r.get_corner_radii().x)
	await click_at(h_tr, true, false, h_tr + Vector2(-25, 25))
	K.check("%s: Mayús+ARRASTRAR sigue cambiando el radio (no el tipo)" % mode, absf(float(r.get_corner_radii().y) - r0) > 2.0 and Array(r.corner_styles) == [1, 2, 1, 1], "%s %s" % [r.get_corner_radii(), r.corner_styles])
	await K.shot("ciclo_" + mode)

## Figuras estrechas con mucho redondeo: en zigzag / sierra los dientes de
## dos esquinas se pisaban y el relleno DESAPARECÍA. Todos los tipos, en
## horizontal y en vertical, deben mostrar su relleno en el centro.
func narrow_fill(mode: String) -> void:
	var ab2: Node2D = await K.artboard(Vector2(1600, 500), "Estrechas " + mode, Color.WHITE)
	await K.look_at(ab2)
	api.select([])
	var shapes: Array = []
	for st in 6:
		for v in [0, 1]:
			var sz := Vector2(228, 123) if v == 0 else Vector2(80, 220)
			var r = api.add_rect(Vector2(120 + st * 250, 140 + v * 230), sz, minf(sz.x, sz.y) * 0.5, "E%d" % st)
			api.set_props(r, {"fill_color": Color(0.2, 0.45, 0.9), "stroke_width": 1.0})
			r.corner_style = st
			shapes.append(r)
	await K.frames(6)
	await RenderingServer.frame_post_draw
	# se mide en la imagen de la PÁGINA (en Smart los paneles tapan parte)
	var img: Image = await ab2.render_to_image(1.0) if ab2.has_method("render_to_image") else root.get_texture().get_image()
	var bad: Array = []
	for r in shapes:
		var c := img.get_pixelv(Vector2i((r as Node2D).position))
		if not (c.b > 0.7 and c.r < 0.4):
			bad.append("%s/%s=%s" % [r.corner_style, r.size, c])
	K.check("%s: figuras estrechas con todos los tipos de esquina conservan el relleno" % mode, bad.is_empty(), ", ".join(bad))
	# la muesca no deja «paredes» de grosor cero (líneas sueltas fuera)
	var notch: Node2D = shapes[6]
	var pts: PackedVector2Array = notch.get_effect_points()
	var r_out := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r_out = r_out.expand(q)
	K.check("%s: muesca estrecha sin líneas sueltas (contorno limpio)" % mode, Geometry2D.triangulate_polygon(pts).size() >= 3 and r_out.size.x < notch.size.x - 1.0, "%s en %s" % [r_out, notch.size])
	await K.shot("estrechas_" + mode)

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://corner_style")
	for mode in ["modern", "smart"]:
		if not await K.boot(mode):
			quit(1)
			return
		api = K.api
		var ab: Node2D = await K.artboard(Vector2(800, 600), "Esquinas " + mode, Color.WHITE)
		var r = api.add_rect(Vector2(300, 300), Vector2(200, 140), 30.0, "R")
		await K.look_at(ab)
		K.canvas.switch_tool("rectangle")
		await K.frames(6)
		api.select([r])
		await K.frames(8)
		var p := panel()
		if p == null and mode == "smart":
			# Smart: el panel se abre con el botón de figuras de la barra
			for n in root.find_children("button_toolbshapes", "Button", true, false):
				if (n as Control).is_visible_in_tree():
					(n as BaseButton).pressed.emit()
			await K.frames(8)
			api.select([r])
			await K.frames(6)
			p = panel()
		K.check("%s: el panel Figuras está abierto" % mode, p != null)
		if p == null:
			continue
		if int(p.get("kind")) != 2:
			p.set_kind(2)
			await K.frames(4)
		var opt: OptionButton = p.find_child("CornerStyle_corner_style", true, false)
		K.check("%s: el panel ofrece «Tipo de esquina»" % mode, opt != null and opt.is_visible_in_tree())
		if opt == null:
			continue
		var labels: Array = []
		for i in opt.item_count:
			labels.append(opt.get_item_text(i))
		K.check("%s: incluye «Redondeado inverso» (con icono)" % mode, labels.has("Redondeado inverso") and opt.get_item_icon(1) != null, str(labels))
		var at := opt.get_global_rect().get_center()
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.global_position = at
		Input.parse_input_event(mm)
		await K.frames(3)
		var hov := root.gui_get_hovered_control()
		K.check("%s: el desplegable se puede pulsar" % mode, hov == opt or (hov != null and opt.is_ancestor_of(hov)), str(hov))
		K.check("%s: antes, esquina redonda (rellena hacia dentro)" % mode, corner_filled(r))
		var inv := labels.find("Redondeado inverso")
		opt.select(inv)
		opt.item_selected.emit(inv)
		await K.frames(4)
		K.check("%s: elegir Redondeado inverso cambia la figura" % mode, int(r.corner_style) == 1 and not corner_filled(r), "estilo %s" % r.corner_style)
		await K.shot("inverso_" + mode)
		api.undo()
		await K.frames(4)
		K.check("%s: un Ctrl+Z vuelve a la esquina redonda" % mode, int(r.corner_style) == 0 and corner_filled(r))
		api.redo()
		await K.frames(4)
		# un rectángulo nuevo desde el panel lleva el tipo elegido
		api.select([])
		await K.frames(4)
		p.create_in_center()
		await K.frames(6)
		var sel: Array = root.get_node("InspectorCore").selection()
		var nr = sel[0] if sel.size() == 1 else null
		K.check("%s: «Crear en el centro» usa el tipo de esquina elegido" % mode, nr != null and nr != r and int(nr.corner_style) == 1, str(nr))
		await shift_click_cycle(mode)
		await narrow_fill(mode)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
