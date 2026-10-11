## 3D (iluminación, Affinity) · BISEL Y RELIEVE (Photoshop) · EXTRUSIÓN.
## Comprobaciones OBJETIVAS sobre la app real (captura con y sin efecto):
##   · lado hacia la luz más claro y lado contrario más oscuro; al girar el
##     acimut se invierte; elevación 90° → simétrico; zona plana sin cambio;
##     opacidad 0 = nada; ambiente 100 aplana; hundido invierte; girar la
##     figura no gira la luz (es del lienzo);
##   · bisel: cada estilo actúa solo donde debe (dentro / fuera / ambos);
##   · suavidad (sin saltos), valores MÁXIMOS, zoom 0,5 / 1 / 2;
##   · texto y trazado; extrusión como efecto propio;
##   · panel (tarjetas, dial, 1 deshacer), guardar / recargar, "3D" antiguo.
##   godot --path . -s res://test/e2e/relief_e2e.gd   (E2E_OUT=carpeta)
extends SceneTree

var canvas: Node2D
var cam: Camera2D
var ab: Node2D
var ic
var sm
var out := "user://relief"
var fails: Array[String] = []
var CS = null

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
		print("E2E FAIL ", msg)
	else:
		print("ok   ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _wait_ms(ms: int) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < ms:
		await process_frame

static func lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

func _shot() -> Image:
	await _frames(6)
	return root.get_texture().get_image()

func _apply(n: Node2D, fx: Array) -> void:
	sm.select(n); ic._sync_selection()
	ic.apply("effects", fx)
	sm.set_selection([]); ic._sync_selection()

func _center_on(n: Node2D, zoom: float) -> void:
	cam.zoom = Vector2(zoom, zoom)
	cam.global_position = canvas.current_tool._global_rect(n).get_center()

## [E, B] con el efecto y sin él (misma vista).
func _pair(n: Node2D, zoom: float, fx: Array) -> Array:
	_apply(n, [])
	_center_on(n, zoom)
	var B := await _shot()
	_apply(n, fx)
	await _wait_ms(450)   # los textos hornean a los 0,3 s
	var E := await _shot()
	return [E, B]

func _sp(n: Node2D, local: Vector2) -> Vector2i:
	return Vector2i((n.get_global_transform_with_canvas() * local).round())

## Media de (E − B) en luminancia en un rectángulo LOCAL de la figura.
func _dl(E: Image, B: Image, n: Node2D, r: Rect2) -> float:
	var acc := 0.0
	var c := 0
	for i in 5:
		for j in 5:
			var lp := r.position + r.size * Vector2((i + 0.5) / 5.0, (j + 0.5) / 5.0)
			var p := _sp(n, lp)
			if p.x < 0 or p.y < 0 or p.x >= E.get_width() or p.y >= E.get_height():
				continue
			acc += lum(E.get_pixelv(p)) - lum(B.get_pixelv(p))
			c += 1
	return acc / maxf(1, c) * 255.0

## Mayor salto entre vecinos de (E − B) en una línea local de a a b.
func _jump(E: Image, B: Image, n: Node2D, a: Vector2, b: Vector2) -> float:
	var pa := Vector2(_sp(n, a))
	var pb := Vector2(_sp(n, b))
	var L := int(pa.distance_to(pb))
	var prev := 0.0
	var mx := 0.0
	for i in L:
		var p := Vector2i(pa.lerp(pb, float(i) / maxf(1, L)).round())
		var v := lum(E.get_pixelv(p)) - lum(B.get_pixelv(p))
		if i > 0:
			mx = maxf(mx, absf(v - prev))
		prev = v
	return mx * 255.0

## Luminancia máxima (0..255) dentro de un rectángulo LOCAL de la figura.
func _max_l(E: Image, n: Node2D, r: Rect2) -> float:
	var mx := 0.0
	for i in 40:
		for j in 30:
			var p := _sp(n, r.position + r.size * Vector2((i + 0.5) / 40.0, (j + 0.5) / 30.0))
			mx = maxf(mx, lum(E.get_pixelv(p)))
	return mx * 255.0

func _find_script_node(nd: Node, suffix: String) -> Node:
	if nd.get_script() and String(nd.get_script().resource_path).ends_with(suffix):
		return nd
	for c in nd.get_children():
		var r := _find_script_node(c, suffix)
		if r:
			return r
	return null

func _run() -> void:
	var env_out := OS.get_environment("E2E_OUT")
	if env_out != "": out = env_out
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(30)
	canvas = get_first_node_in_group("_vectopen_canvas")
	ic = root.get_node("InspectorCore")
	sm = root.get_node("SelectionManager")
	var hm = root.get_node("HistoryManager")
	CS = load("res://scripts/canvas/canvas_serializer.gd")
	root.get_node("ThemeManager").set_mode("light")
	cam = canvas.get_node("Camera2D")
	ab = canvas.get_node("manager_script").get_active_artboard()
	ab.artboard_size = Vector2(6000, 6000)
	for cl in root.find_children("*", "CanvasLayer", true, false):
		if not (cl as Node).is_ancestor_of(canvas):
			(cl as CanvasLayer).visible = false
	print("RELIEVE modo: ", "nativo" if ClassDB.class_exists("VectorRichText") else "GDScript")
	var FxLight = load("res://script_gdscript/shapes/fx_light.gd")

	var base := Color(0.6, 0.6, 0.6)
	var rect = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.size = Vector2(200, 140)
	rect.fill_color = base
	rect.stroke_width = 0.0
	ab.add_child(rect)
	rect.position = Vector2(1500, 1500)
	var h: Vector2 = rect.size * 0.5
	var L3 := func(extra: Dictionary) -> Array:
		var d: Dictionary = FxLight.defaults("3d")
		d["type"] = "3D"
		d["enabled"] = true
		d.merge(extra, true)
		return [d]
	var BV := func(extra: Dictionary) -> Array:
		var d: Dictionary = FxLight.defaults("bevel_emboss")
		d["type"] = "Bevel Emboss"
		d["enabled"] = true
		d.merge(extra, true)
		return [d]
	# zonas locales del rectángulo
	var right := Rect2(h.x - 12, -20, 8, 40)
	var left := Rect2(-h.x + 4, -20, 8, 40)
	var top := Rect2(-30, -h.y + 4, 60, 8)
	var bottom := Rect2(-30, h.y - 12, 60, 8)
	var center := Rect2(-15, -10, 30, 20)
	var out_r := Rect2(h.x + 6, -20, 10, 40)
	var out_l := Rect2(-h.x - 16, -20, 10, 40)

	# ── A. 3D con luz arriba-derecha (acimut 45°, elevación 45°) ───────────
	for z in [0.5, 1.0, 2.0]:
		var r: Array = await _pair(rect, z, L3.call({"radius": 100.0, "azimuth": 45.0, "elevation": 45.0, "specular": 0.0}))
		var E: Image = r[0]
		var B: Image = r[1]
		E.save_png("%s/3d_az45_z%.1f.png" % [out, z])
		var dr := _dl(E, B, rect, right)
		var dlf := _dl(E, B, rect, left)
		var dt := _dl(E, B, rect, top)
		var db := _dl(E, B, rect, bottom)
		var dc := _dl(E, B, rect, center)
		print("3D z%.1f  der=%.1f izq=%.1f arr=%.1f abj=%.1f centro=%.1f fuera=%.1f" % [z, dr, dlf, dt, db, dc, _dl(E, B, rect, out_r)])
		_check(dr > 6.0 and dt > 6.0, "3D z%.1f: lados hacia la luz (derecha / arriba) más claros (%.1f, %.1f)" % [z, dr, dt])
		_check(dlf < -6.0 and db < -6.0, "3D z%.1f: lados contrarios (izquierda / abajo) más oscuros (%.1f, %.1f)" % [z, dlf, db])
		_check(absf(dc) < 3.0, "3D z%.1f: la zona plana del centro no cambia (%.1f)" % [z, dc])
		_check(absf(_dl(E, B, rect, out_r)) < 1.0 and absf(_dl(E, B, rect, out_l)) < 1.0, "3D z%.1f: fuera de la figura nada" % z)
		var j := _jump(E, B, rect, Vector2(-h.x + 1, 0), Vector2(0, 0))
		# (a menos zoom la misma pendiente ocupa menos px: umbral escalado)
		_check(j < 14.0 / minf(z, 1.0), "3D z%.1f: sombreado continuo, sin saltos (%.1f/255)" % [z, j])
	# acimut opuesto
	var r2: Array = await _pair(rect, 1.0, L3.call({"radius": 100.0, "azimuth": 225.0, "elevation": 45.0, "specular": 0.0}))
	_check(_dl(r2[0], r2[1], rect, right) < -6.0 and _dl(r2[0], r2[1], rect, left) > 6.0, "3D: acimut 225° invierte (luz abajo-izquierda)")
	# elevación 90: simétrico
	var r3: Array = await _pair(rect, 1.0, L3.call({"radius": 100.0, "elevation": 90.0, "specular": 0.0}))
	# perfil horizontal completo: comparar cada píxel con su simétrico
	var E3: Image = r3[0]
	var B3: Image = r3[1]
	var pl := Vector2(_sp(rect, Vector2(-h.x, 0)))
	var pr := Vector2(_sp(rect, Vector2(h.x, 0)))
	var nn := int(pr.x - pl.x)
	var asym := 0.0
	for i in range(2, nn / 2):
		var a := lum(E3.get_pixel(int(pl.x) + i, int(pl.y))) - lum(B3.get_pixel(int(pl.x) + i, int(pl.y)))
		var b := lum(E3.get_pixel(int(pr.x) - 1 - i, int(pl.y))) - lum(B3.get_pixel(int(pr.x) - 1 - i, int(pl.y)))
		asym = maxf(asym, absf(a - b))
	_check(asym * 255.0 < 4.0, "3D: elevación 90° → simétrico píxel a píxel (máx dif %.1f/255)" % (asym * 255.0))
	# opacidad 0
	var r4: Array = await _pair(rect, 1.0, L3.call({"radius": 100.0, "opacity": 0.0}))
	_check(absf(_dl(r4[0], r4[1], rect, left)) < 1.0 and absf(_dl(r4[0], r4[1], rect, right)) < 1.0, "3D: opacidad 0 = sin efecto")
	# ambiente 100
	var r5: Array = await _pair(rect, 1.0, L3.call({"radius": 100.0, "ambient": 100.0, "azimuth": 45.0, "specular": 0.0}))
	_check(absf(_dl(r5[0], r5[1], rect, left)) < 3.0, "3D: ambiente 100 %% rellena las sombras (%.1f)" % _dl(r5[0], r5[1], rect, left))
	# hundido
	var r6: Array = await _pair(rect, 1.0, L3.call({"radius": 100.0, "azimuth": 45.0, "sunken": true, "specular": 0.0}))
	_check(_dl(r6[0], r6[1], rect, left) > 6.0 and _dl(r6[0], r6[1], rect, right) < -6.0, "3D: hundido invierte luces y sombras")
	# especular: el brillo añade luz en el lado iluminado
	var r7: Array = await _pair(rect, 1.0, L3.call({"radius": 100.0, "azimuth": 45.0, "specular": 100.0, "shininess": 30.0}))
	var r7b: Array = await _pair(rect, 1.0, L3.call({"radius": 100.0, "azimuth": 45.0, "specular": 0.0}))
	var mx_on := _max_l(r7[0], rect, Rect2(-h, h * 2.0))
	var mx_off := _max_l(r7b[0], rect, Rect2(-h, h * 2.0))
	_check(mx_on > mx_off + 10.0, "3D: el especular añade un brillo (máx %.0f > %.0f)" % [mx_on, mx_off])
	# girar la figura 90°: la luz sigue en el lienzo (derecha de pantalla)
	rect.rotation = PI / 2
	var r8: Array = await _pair(rect, 1.0, L3.call({"radius": 100.0, "azimuth": 0.0, "elevation": 45.0, "specular": 0.0}))
	# tras girar 90°, el lado local "arriba" (−y) queda a la derecha en pantalla
	_check(_dl(r8[0], r8[1], rect, top) > 6.0 and _dl(r8[0], r8[1], rect, bottom) < -6.0, "3D: al girar la figura la luz no gira con ella")
	rect.rotation = 0.0
	# perfiles y valores máximos
	for prof in [0, 1, 2]:
		var rp: Array = await _pair(rect, 1.0, L3.call({"radius": 200.0, "relief": 200.0, "link": false, "soften": 50.0, "profile": prof, "specular": 100.0, "shininess": 100.0, "azimuth": 45.0}))
		(rp[0] as Image).save_png("%s/3d_max_perfil%d.png" % [out, prof])
		var jm := _jump(rp[0], rp[1], rect, Vector2(-h.x + 1, 0), Vector2(h.x - 1, 0))
		_check(jm < 20.0, "3D máx perfil %d: sin saltos (%.1f)" % [prof, jm])
		_check(_dl(rp[0], rp[1], rect, right) > _dl(rp[0], rp[1], rect, left), "3D máx perfil %d: lado de la luz más claro" % prof)
	# Como la captura de Affinity: radio 100, suavizar 7,2, especular 47, brillo 97
	var rect2 = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect2.size = Vector2(92, 140)
	rect2.fill_color = Color(0.604, 0.604, 0.604)
	rect2.stroke_width = 0.0
	ab.add_child(rect2)
	rect2.position = Vector2(2200, 1500)
	var ra: Array = await _pair(rect2, 2.33, L3.call({"radius": 100.0, "soften": 7.2, "diffuse": 100.0, "specular": 47.0, "shininess": 97.0, "ambient": 0.0, "azimuth": 45.0, "elevation": 45.0}))
	(ra[0] as Image).save_png(out + "/3d_como_affinity.png")
	rect2.queue_free()

	# ── B. Bisel y relieve: estilos ────────────────────────────────────────
	var styles := ["interior", "exterior", "relieve", "almohadilla"]
	for st in 4:
		var rb: Array = await _pair(rect, 1.0, BV.call({"style": st, "size": 14.0, "azimuth": 180.0, "elevation": 30.0}))
		var E: Image = rb[0]
		var B: Image = rb[1]
		E.save_png("%s/bisel_%s.png" % [out, styles[st]])
		var in_l := _dl(E, B, rect, Rect2(-h.x + 2, -20, 6, 40))
		var in_r := _dl(E, B, rect, Rect2(h.x - 8, -20, 6, 40))
		var ou_l := _dl(E, B, rect, Rect2(-h.x - 8, -20, 6, 40))
		var ou_r := _dl(E, B, rect, Rect2(h.x + 2, -20, 6, 40))
		var far := _dl(E, B, rect, Rect2(h.x + 30, -20, 6, 40))
		var ctr := _dl(E, B, rect, center)
		print("bisel %-11s dentro izq=%.1f der=%.1f · fuera izq=%.1f der=%.1f · lejos=%.1f centro=%.1f" % [styles[st], in_l, in_r, ou_l, ou_r, far, ctr])
		_check(absf(far) < 1.0 and absf(ctr) < 2.0, "bisel %s: lejos del borde y en el centro no cambia" % styles[st])
		match st:
			0:
				_check(in_l > 8.0 and in_r < -8.0, "bisel interior: luz a la izquierda (luz a 180°) y sombra a la derecha, dentro")
				_check(absf(ou_l) < 1.0 and absf(ou_r) < 1.0, "bisel interior: fuera no cambia")
			1:
				_check(absf(in_l) < 1.0 and absf(in_r) < 1.0, "bisel exterior: dentro no cambia")
				# fuera el relieve baja hacia fuera: el lado izquierdo mira lejos de la luz
				# luz a la izquierda: fuera-derecha mira lejos de la luz → sombra; la
				# luz (trama) sobre el fondo BLANCO no cambia nada (como Photoshop)
				_check(ou_r < -8.0 and ou_l >= -1.0, "bisel exterior: sombra fuera a la derecha, nada oscuro fuera a la izquierda")
			2:
				_check(in_l > 4.0 and in_r < -4.0 and ou_r < -8.0, "relieve: dentro luz izquierda / sombra derecha, fuera sombra derecha")
			3:
				# borde hundido: dentro como un bisel (luz izquierda), fuera al revés
				_check(in_l > 4.0 and in_r < -4.0 and ou_l < -8.0, "almohadilla: dentro luz izquierda / sombra derecha, fuera sombra izquierda")
	# técnica + máximos
	for tech in [0, 1, 2]:
		var rt: Array = await _pair(rect, 1.0, BV.call({"technique": tech, "size": 200.0, "depth": 1000.0, "soften": 50.0, "azimuth": 120.0}))
		(rt[0] as Image).save_png("%s/bisel_max_tecnica%d.png" % [out, tech])
		var jt := _jump(rt[0], rt[1], rect, Vector2(-h.x + 1, 0), Vector2(h.x - 1, 0))
		_check(jt < 40.0, "bisel máx técnica %d: sin saltos raros (%.1f)" % [tech, jt])

	# ── C. Trazado y estrella ──────────────────────────────────────────────
	var path = load("res://script_gdscript/shapes/VectorPath.gd").new()
	var cv := Curve2D.new()
	cv.add_point(Vector2(-90, -60), Vector2.ZERO, Vector2(60, -40))
	cv.add_point(Vector2(90, -60), Vector2(-20, -40), Vector2(40, 60))
	cv.add_point(Vector2(60, 70), Vector2(40, 0), Vector2(-60, 20))
	cv.add_point(Vector2(-80, 50), Vector2(30, 30), Vector2(-30, -40))
	path.curve = cv
	path.closed = true
	path.fill_color = base
	path.stroke_width = 0.0
	ab.add_child(path)
	path.position = Vector2(3000, 1500)
	var rpth: Array = await _pair(path, 1.0, L3.call({"radius": 100.0, "azimuth": 0.0, "specular": 0.0}))
	(rpth[0] as Image).save_png(out + "/trazado_3d.png")
	# perfil horizontal por el centro: máximo en la mitad derecha (luz) y
	# mínimo en la izquierda
	var Ep: Image = rpth[0]
	var Bp: Image = rpth[1]
	var cpy: int = _sp(path, Vector2(0, 0)).y
	var cpx: int = _sp(path, Vector2(0, 0)).x
	var mx_r := -1.0
	var mn_l := 1.0
	for x in range(cpx - 160, cpx + 160):
		var dv := lum(Ep.get_pixel(x, cpy)) - lum(Bp.get_pixel(x, cpy))
		if x > cpx:
			mx_r = maxf(mx_r, dv)
		else:
			mn_l = minf(mn_l, dv)
	_check(mx_r * 255.0 > 10.0 and mn_l * 255.0 < -10.0, "trazado 3D: derecha (luz) clara %.0f, izquierda oscura %.0f" % [mx_r * 255.0, mn_l * 255.0])
	var rpb: Array = await _pair(path, 1.0, BV.call({"style": 1, "size": 16.0}))
	(rpb[0] as Image).save_png(out + "/trazado_bisel_exterior.png")
	var rpx: Array = await _pair(path, 1.0, [{"type": "Extrusion", "enabled": true, "depth": 30.0, "angle": 45.0, "highlight": 70.0, "shadow": 60.0}])
	(rpx[0] as Image).save_png(out + "/trazado_extrusion.png")
	_check(absf(_dl(rpx[0], rpx[1], path, Rect2(80, 60, 20, 20))) > 4.0, "trazado: la extrusión se ve fuera (abajo-derecha)")
	_apply(path, [])

	# ── D. Texto ───────────────────────────────────────────────────────────
	canvas.switch_tool("text")
	await _frames()
	var title: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(title); ic._sync_selection()
	ic.apply("text", "ROCA")
	ic.apply("font_size", 160)
	ic.apply("fill_color", Color(0.6, 0.6, 0.6))
	if title.get_parent() != ab:
		title.reparent(ab)
	title.position = Vector2(1500, 3000)
	canvas.switch_tool("move")
	sm.set_selection([]); ic._sync_selection()
	for k in [["3d", L3.call({"radius": 12.0, "azimuth": 0.0, "specular": 0.0})], ["bisel", BV.call({"size": 10.0, "azimuth": 0.0})]]:
		for az in [0.0, 180.0]:
			var fxl: Array = (k[1] as Array).duplicate(true)
			fxl[0]["azimuth"] = az
			var rt2: Array = await _pair(title, 1.0, fxl)
			var E: Image = rt2[0]
			var B: Image = rt2[1]
			E.save_png("%s/texto_%s_az%d.png" % [out, k[0], int(az)])
			# píxeles de letra cerca de un borde DERECHO / IZQUIERDO
			var box: Rect2 = canvas.current_tool._global_rect(title)
			var xf := canvas.get_viewport().get_canvas_transform()
			var r0 := Rect2i(Rect2(xf * box.position, xf * box.end - xf * box.position))
			var sr := 0.0
			var nr := 0
			var sl := 0.0
			var nl := 0
			for y in range(r0.position.y, r0.end.y, 2):
				for x in range(r0.position.x + 4, r0.end.x - 4, 1):
					if lum(B.get_pixel(x, y)) > 0.75:
						continue   # fondo
					var d := lum(E.get_pixel(x, y)) - lum(B.get_pixel(x, y))
					if lum(B.get_pixel(x + 4, y)) > 0.9:
						sr += d
						nr += 1
					elif lum(B.get_pixel(x - 4, y)) > 0.9:
						sl += d
						nl += 1
			var mr := sr / maxf(1, nr) * 255.0
			var ml := sl / maxf(1, nl) * 255.0
			print("texto %s az%d  borde der=%.1f izq=%.1f" % [k[0], int(az), mr, ml])
			if az == 0.0:
				_check(mr > ml + 6.0, "texto %s, luz a la derecha: bordes derechos más claros (%.1f vs %.1f)" % [k[0], mr, ml])
			else:
				_check(ml > mr + 6.0, "texto %s, luz a la izquierda: bordes izquierdos más claros (%.1f vs %.1f)" % [k[0], ml, mr])
	var rtx: Array = await _pair(title, 1.0, [{"type": "Extrusion", "enabled": true, "depth": 20.0, "angle": 45.0, "highlight": 70.0, "shadow": 60.0}])
	(rtx[0] as Image).save_png(out + "/texto_extrusion.png")
	var dsum := 0.0
	for y in range(0, (rtx[0] as Image).get_height(), 7):
		for x in range(0, (rtx[0] as Image).get_width(), 7):
			dsum += absf(lum((rtx[0] as Image).get_pixel(x, y)) - lum((rtx[1] as Image).get_pixel(x, y)))
	_check(dsum > 5.0, "texto: la extrusión se ve")

	# ── E. "3D" antiguo → Extrusión + Bisel y relieve ──────────────────────
	var legacy := [{"type": "3D", "enabled": true, "depth": 8.0, "bevel": 8.0, "angle": 45.0, "highlight": 70.0, "shadow": 60.0, "contour": 0, "extrude": true}]
	var rl: Array = await _pair(rect, 1.0, legacy)
	(rl[0] as Image).save_png(out + "/antiguo_3d.png")
	_check(absf(_dl(rl[0], rl[1], rect, left)) > 3.0, "3D antiguo: se sigue viendo (convertido)")
	var panel = _find_script_node(root, "panels/effects/effects.gd")
	sm.select(rect); ic._sync_selection()
	panel._sync_from_inspector()
	await _frames(3)
	var names: Array = []
	for c in panel._effects_list.get_children():
		names.append(c.effect_name)
	_check(names == ["Extrusion", "Bevel Emboss"], "panel: el 3D antiguo aparece como Extrusión + Bisel y relieve (%s)" % [names])

	# ── F. Panel: añadir las tres, dial, 1 deshacer ────────────────────────
	ic.apply("effects", [])
	panel._sync_from_inspector()
	for nm in ["3D", "Bevel Emboss", "Extrusion"]:
		panel._add_new_effect(nm)
		await _frames(2)
	panel._sync_from_inspector()
	await _frames(3)
	var fxs = ic._read(rect, "effects")
	_check(fxs.size() == 3 and FxLight.canonical(String(fxs[0]["type"])) == "3d" and FxLight.canonical(String(fxs[1]["type"])) == "bevel_emboss" and FxLight.canonical(String(fxs[2]["type"])) == "extrusion", "panel: se añaden 3D, Bisel y relieve y Extrusión")
	var card = panel._effects_list.get_child(0)
	var dial = card.get("_dial")
	_check(dial != null, "panel: la tarjeta 3D tiene el dial de dirección")
	hm.clear()
	if dial:
		dial._from(dial.size * 0.5 + Vector2(dial.size.x * 0.4, 0))   # luz a la derecha
		await _wait_ms(700)
	var az_now: float = float(ic._read(rect, "effects")[0].get("azimuth", -1))
	_check(absf(az_now) < 2.0 or absf(az_now - 360.0) < 2.0, "panel: el dial pone el acimut (%.0f)" % az_now)
	var steps := 0
	while hm.can_undo() and steps < 20:
		hm.undo()
		steps += 1
	_check(steps == 1, "panel: mover el dial = 1 paso de deshacer (%d)" % steps)
	# guardar / recargar
	_apply(rect, L3.call({"radius": 100.0, "azimuth": 45.0, "specular": 0.0}))
	_center_on(rect, 1.0)
	var before := await _shot()
	var data: Dictionary = CS._serialize_element(rect)
	var parent: Node = rect.get_parent()
	rect.free()
	await _frames(2)
	var re: Node2D = CS._element_from(data)
	parent.add_child(re)
	CS._apply_transform(re, data)
	await _frames(6)
	var after := await _shot()
	var diff := 0.0
	var cnt := 0
	for y in range(0, before.get_height(), 9):
		for x in range(0, before.get_width(), 9):
			diff += absf(lum(before.get_pixel(x, y)) - lum(after.get_pixel(x, y)))
			cnt += 1
	_check(diff / cnt * 255.0 < 0.5, "guardar / recargar: el 3D se ve igual (%.2f)" % (diff / cnt * 255.0))

	print("RELIEVE FIN")
	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
