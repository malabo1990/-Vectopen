## CALIDAD DEL DESENFOQUE con valores MÁXIMOS (y medios) a varios zooms.
## Para cada caso: captura SIN el objeto (fondo) y CON el efecto; se analiza
## la diferencia (así el borde del artboard / la UI no cuentan):
##   · EXACTO: rectángulo y círculo contra la gaussiana calculada en CPU
##     (desenfoque, sombra, sombra interior, brillo interior): error medio
##     y máximo por píxel;
##   · SUAVE: en perfiles hacia fuera (o hacia dentro) el efecto decae de
##     forma MONÓTONA (sin anillos / "capas sólidas") y sin saltos (cortes);
##   · COLA: en el borde de la región el efecto ya ha llegado al fondo
##     (no se corta en el marco del quad / del grupo).
##   godot --path . -s res://test/e2e/blur_quality_e2e.gd   (E2E_OUT=carpeta, BQ_ONLY=filtro)
extends SceneTree

var canvas: Node2D
var cam: Camera2D
var ab: Node2D
var ic
var sm
var out := "user://blur_quality"
var fails: Array[String] = []
var rows: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
		print("E2E FAIL ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _wait_ms(ms: int) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < ms:
		await process_frame

# ── matemáticas de referencia (CPU) ──────────────────────────────────────────
static func erf(x: float) -> float:
	var s := signf(x)
	var a := absf(x)
	var t := 1.0 / (1.0 + 0.3275911 * a)
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-a * a)
	return s * y

static func ncdf(z: float) -> float:
	return 0.5 + 0.5 * erf(z * 0.70710678)

## Cobertura gaussiana exacta de un rectángulo centrado (semiejes h).
static func rect_cover(p: Vector2, h: Vector2, s: float) -> float:
	if h.x <= 0.0 or h.y <= 0.0:
		return 0.0
	var ax := ncdf((h.x - p.x) / s) - ncdf((-h.x - p.x) / s)
	var ay := ncdf((h.y - p.y) / s) - ncdf((-h.y - p.y) / s)
	return ax * ay

## Tabla radial de la cobertura gaussiana de un disco de radio R (integración
## fina por filas, 600 filas): cover(r) para r en pasos de dr.
static func disk_table(R: float, s: float, rmax: float, dr: float) -> PackedFloat32Array:
	var tab := PackedFloat32Array()
	var n := int(rmax / dr) + 2
	for k in n:
		var px := k * dr
		var acc := 0.0
		var N := 600
		var a := maxf(-R, -4.5 * s)
		var b := minf(R, 4.5 * s)
		if b <= a:
			tab.append(0.0)
			continue
		var dy := (b - a) / N
		for i in N:
			var y := a + (i + 0.5) * dy
			var w := R * sqrt(maxf(0.0, 1.0 - y * y / (R * R)))
			acc += exp(-0.5 * (y / s) * (y / s)) * (ncdf((w - px) / s) - ncdf((-w - px) / s))
		tab.append(acc * dy / s * 0.39894228)
	return tab

static func table_at(tab: PackedFloat32Array, r: float, dr: float) -> float:
	var f := r / dr
	var i := int(f)
	if i >= tab.size() - 1:
		return tab[tab.size() - 1]
	return lerpf(tab[i], tab[i + 1], f - i)

# ── capturas ────────────────────────────────────────────────────────────────
func _shot() -> Image:
	await _frames(6)
	return root.get_texture().get_image()

func _screen_rect(n: Node2D) -> Rect2:
	var xf := canvas.get_viewport().get_canvas_transform()
	var gr: Rect2 = canvas.current_tool._global_rect(n)
	var p0: Vector2 = xf * gr.position
	var p1: Vector2 = xf * gr.end
	return Rect2(p0, p1 - p0).abs()

static func lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

## Perfil (diferencia de luminancia efecto − fondo) desde `from` hacia `dir`.
func _profile(E: Image, B: Image, from: Vector2, dir: Vector2, length: int) -> PackedFloat32Array:
	var pr := PackedFloat32Array()
	var sz := E.get_size()
	for i in length:
		var p := Vector2i((from + dir * i).round())
		if p.x < 0 or p.y < 0 or p.x >= sz.x or p.y >= sz.y:
			break
		pr.append(lum(E.get_pixelv(p)) - lum(B.get_pixelv(p)))
	return pr

## Analiza un perfil que debe decaer hacia 0: devuelve
## [violaciones de monotonía (> tol), salto máximo, valor final, valor máx].
static func _analyze(pr: PackedFloat32Array, tol: float) -> Array:
	var viol := 0
	var max_step := 0.0
	var peak := 0.0
	for i in pr.size():
		peak = maxf(peak, absf(pr[i]))
	for i in range(1, pr.size()):
		var a := absf(pr[i - 1])
		var b := absf(pr[i])
		max_step = maxf(max_step, absf(b - a))
		if b > a + tol:
			viol += 1
	var tail := absf(pr[pr.size() - 1]) if pr.size() > 0 else 1.0
	return [viol, max_step, tail, peak]

# ── casos ───────────────────────────────────────────────────────────────────
func _apply_fx(n: Node2D, fx: Array, filters: Array = []) -> void:
	sm.select(n); ic._sync_selection()
	ic.apply("effects", fx)
	ic.apply("filters", filters)
	sm.set_selection([]); ic._sync_selection()

func _center_on(n: Node2D, zoom: float) -> void:
	cam.zoom = Vector2(zoom, zoom)
	var r: Rect2 = canvas.current_tool._global_rect(n)
	cam.global_position = r.get_center()

## Ejecuta un caso: devuelve imágenes E, B y la caja del objeto en pantalla.
func _capture(n: Node2D, zoom: float, fx: Array, filters: Array = []) -> Array:
	_apply_fx(n, [], [])
	_center_on(n, zoom)
	n.visible = false
	var B := await _shot()
	n.visible = true
	_apply_fx(n, fx, filters)
	# los textos hornean sus efectos a los 0,3 s: se mide lo que queda
	await _wait_ms(500)
	var E := await _shot()
	return [E, B, _screen_rect(n)]

## Perfiles hacia fuera desde el borde de la caja (derecha, abajo, izquierda,
## arriba y diagonal de esquina) y comprobaciones de suavidad / cola.
func _outer_checks(name: String, E: Image, B: Image, box: Rect2, extent_px: float, inner_skip: float = 2.0) -> Dictionary:
	var c := box.get_center()
	var L := int(extent_px + 30)
	var dirs := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1, 1).normalized()]
	var starts := [
		Vector2(box.end.x + inner_skip, c.y), Vector2(c.x, box.end.y + inner_skip),
		Vector2(box.position.x - inner_skip, c.y), Vector2(c.x, box.position.y - inner_skip),
		box.end + Vector2(inner_skip, inner_skip),
	]
	var worst := {"viol": 0, "step": 0.0, "tail": 0.0, "peak": 0.0}
	for k in dirs.size():
		var pr := _profile(E, B, starts[k], dirs[k], L)
		if pr.size() < 4:
			continue
		var a := _analyze(pr, 2.5 / 255.0)
		worst["viol"] = maxi(worst["viol"], a[0])
		worst["step"] = maxf(worst["step"], a[1])
		# la cola solo cuenta si el perfil no se salió de la pantalla
		if pr.size() >= L:
			worst["tail"] = maxf(worst["tail"], a[2])
		worst["peak"] = maxf(worst["peak"], a[3])
	return worst

## Error contra la referencia exacta en una rejilla de la región.
func _exact_error(E: Image, B: Image, region: Rect2, expected: Callable) -> Array:
	var sz := E.get_size()
	var r := Rect2i(region).intersection(Rect2i(Vector2i.ZERO, sz))
	var acc := 0.0
	var n := 0
	var mx := 0.0
	for y in range(r.position.y, r.end.y, 3):
		for x in range(r.position.x, r.end.x, 3):
			var exp_c: Variant = expected.call(Vector2(x + 0.5, y + 0.5), B.get_pixel(x, y))
			if exp_c == null:
				continue
			var e := E.get_pixel(x, y)
			var d := (absf(e.r - exp_c.r) + absf(e.g - exp_c.g) + absf(e.b - exp_c.b)) / 3.0
			acc += d
			mx = maxf(mx, d)
			n += 1
	return [acc / maxf(1, n) * 255.0, mx * 255.0, n]

func _local(n: Node2D, sp: Vector2) -> Vector2:
	return n.get_global_transform_with_canvas().affine_inverse() * sp

## Busca LÍNEAS DURAS en toda la región: salto vertical u horizontal máximo
## de la diferencia (efecto − fondo), fuera de la caja del objeto (+3 px).
func _max_jump(E: Image, B: Image, region: Rect2, inner: Rect2) -> float:
	var r := Rect2i(region).intersection(Rect2i(Vector2i(1, 1), E.get_size() - Vector2i(2, 2)))
	var mx := 0.0
	var ib := inner.grow(3.0)
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			if ib.has_point(Vector2(x, y)):
				continue
			var d0 := lum(E.get_pixel(x, y)) - lum(B.get_pixel(x, y))
			var dx := lum(E.get_pixel(x + 1, y)) - lum(B.get_pixel(x + 1, y))
			var dy := lum(E.get_pixel(x, y + 1)) - lum(B.get_pixel(x, y + 1))
			mx = maxf(mx, maxf(absf(dx - d0), absf(dy - d0)))
	return mx

func _row(name: String, zoom: float, m: Dictionary, exact: Array = []) -> void:
	var ex := "" if exact.is_empty() else "  exacto: medio %.2f máx %.1f (/255)" % [exact[0], exact[1]]
	print("BQ %-38s z%.1f  anillos=%d  salto_máx=%.1f  cola=%.1f  pico=%.0f%s" % [name, zoom, m["viol"], m["step"] * 255.0, m["tail"] * 255.0, m["peak"] * 255.0, ex])

func _run() -> void:
	var env_out := OS.get_environment("E2E_OUT")
	if env_out != "": out = env_out
	DirAccess.make_dir_recursive_absolute(out)
	var only := OS.get_environment("BQ_ONLY")
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _frames(30)
	canvas = get_first_node_in_group("_vectopen_canvas")
	ic = root.get_node("InspectorCore")
	sm = root.get_node("SelectionManager")
	root.get_node("ThemeManager").set_mode("light")
	cam = canvas.get_node("Camera2D")
	ab = canvas.get_node("manager_script").get_active_artboard()
	ab.artboard_size = Vector2(6000, 6000)   # fondo blanco amplio
	print("BQ modo: ", "nativo" if ClassDB.class_exists("VectorRichText") else "GDScript")
	# Sin UI encima del lienzo: los halos grandes llegan bajo los paneles.
	for cl in root.find_children("*", "CanvasLayer", true, false):
		if not (cl as Node).is_ancestor_of(canvas):
			(cl as CanvasLayer).visible = false

	var fill := Color(0.15, 0.4, 0.9)
	var rect = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.size = Vector2(200, 140)
	rect.fill_color = fill
	rect.stroke_width = 0.0
	ab.add_child(rect)
	rect.position = Vector2(1500, 1500)
	var circ = load("res://script_gdscript/shapes/VectorCircle.gd").new()
	circ.size = Vector2(160, 160)
	circ.fill_color = fill
	circ.stroke_width = 0.0
	ab.add_child(circ)
	circ.position = Vector2(3000, 1500)
	var star = load("res://script_gdscript/shapes/VectorPolygon.gd").new()
	var sv := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5
		sv.append(Vector2(cos(a), sin(a)) * (90.0 if i % 2 == 0 else 40.0))
	star.vertices = sv
	star.fill_color = fill
	star.stroke_width = 0.0
	ab.add_child(star)
	star.position = Vector2(4500, 1500)
	var path = load("res://script_gdscript/shapes/VectorPath.gd").new()
	var cv := Curve2D.new()
	cv.add_point(Vector2(-90, -60), Vector2.ZERO, Vector2(60, -40))
	cv.add_point(Vector2(90, -60), Vector2(-20, -40), Vector2(40, 60))
	cv.add_point(Vector2(60, 70), Vector2(40, 0), Vector2(-60, 20))
	cv.add_point(Vector2(-80, 50), Vector2(30, 30), Vector2(-30, -40))
	path.curve = cv
	path.closed = true
	path.fill_color = fill
	path.stroke_width = 0.0
	ab.add_child(path)
	path.position = Vector2(1500, 3500)
	canvas.switch_tool("text")
	await _frames()
	var title: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(title); ic._sync_selection()
	ic.apply("text", "Blur")
	ic.apply("font_size", 120)
	if title.get_parent() != ab:
		title.reparent(ab)
	title.position = Vector2(3000, 3400)
	canvas.switch_tool("move")
	sm.set_selection([]); ic._sync_selection()
	for n in [rect, circ, star, path, title]:
		n.visible = true
	await _frames(5)

	# ── A. RECTÁNGULO contra la gaussiana exacta ───────────────────────────
	var CASES_R := [
		["desenfoque 200 (máx)", [{"type": "Blur", "enabled": true, "radius": 200.0, "blur_type": "gaussian"}], 1.0],
		["desenfoque 200 (máx)", [{"type": "Blur", "enabled": true, "radius": 200.0, "blur_type": "gaussian"}], 0.5],
		["desenfoque 60", [{"type": "Blur", "enabled": true, "radius": 60.0, "blur_type": "gaussian"}], 2.0],
		["desenfoque 8", [{"type": "Blur", "enabled": true, "radius": 8.0, "blur_type": "gaussian"}], 1.0],
		["sombra 100 desplaz 30", [{"type": "Drop Shadow", "enabled": true, "offset_x": 30.0, "offset_y": 30.0, "blur": 100.0, "spread": 0.0, "color": Color(0, 0, 0, 0.8)}], 1.0],
		["sombra 100 extensión 100", [{"type": "Drop Shadow", "enabled": true, "offset_x": 0.0, "offset_y": 0.0, "blur": 100.0, "spread": 100.0, "color": Color(0, 0, 0, 0.8)}], 0.5],
		["sombra 100 desplaz 100", [{"type": "Drop Shadow", "enabled": true, "offset_x": 100.0, "offset_y": 100.0, "blur": 100.0, "spread": 0.0, "color": Color(0, 0, 0, 0.8)}], 2.0],
		["sombra interior 100", [{"type": "Inner Shadow", "enabled": true, "offset_x": 20.0, "offset_y": 20.0, "blur": 100.0, "spread": 0.0, "color": Color(0, 0, 0, 0.8)}], 1.0],
		["brillo interior 100", [{"type": "Inner Glow", "enabled": true, "color": Color(1, 0.9, 0.2), "radius": 100.0, "opacity": 1.0}], 1.0],
	]
	for cs in CASES_R:
		var nm: String = "rect " + cs[0]
		if only != "" and not nm.contains(only):
			continue
		var z: float = cs[2]
		var fx: Array = cs[1]
		var e: Dictionary = fx[0]
		var res: Array = await _capture(rect, z, fx)
		var E: Image = res[0]
		var B: Image = res[1]
		var box: Rect2 = res[2]
		E.save_png("%s/%s_z%.1f.png" % [out, nm.replace(" ", "_"), z])
		var h: Vector2 = rect.size * 0.5
		var t := String(e["type"])
		var expected: Callable
		var region := box
		var sig := 0.0
		var outer := true
		match t:
			"Blur":
				sig = float(e["radius"]) * 0.5
				region = box.grow(3.2 * sig * z)
				expected = func(sp: Vector2, bg: Color) -> Variant:
					var a := rect_cover(_local(rect, sp), h, sig)
					return bg.lerp(fill, a)
			"Drop Shadow":
				sig = float(e["blur"]) * 0.5
				var off := Vector2(e["offset_x"], e["offset_y"])
				var spr: float = e["spread"]
				var col: Color = e["color"]
				region = box.grow(3.2 * sig * z + spr * z).merge(Rect2(box.position + off * z, box.size).grow(3.2 * sig * z + spr * z))
				expected = func(sp: Vector2, bg: Color) -> Variant:
					var lp := _local(rect, sp)
					if absf(lp.x) < h.x + 1.5 / z and absf(lp.y) < h.y + 1.5 / z:
						return null   # la figura (y su borde)
					var a := rect_cover(lp - off, h + Vector2(spr, spr), sig) * col.a
					return bg.lerp(Color(col.r, col.g, col.b), a)
			"Inner Shadow":
				outer = false
				sig = float(e["blur"]) * 0.5
				var off2 := Vector2(e["offset_x"], e["offset_y"])
				var col2: Color = e["color"]
				region = box
				expected = func(sp: Vector2, _bg: Color) -> Variant:
					var lp := _local(rect, sp)
					if absf(lp.x) > h.x - 1.5 / z or absf(lp.y) > h.y - 1.5 / z:
						return null
					var a := (1.0 - rect_cover(lp - off2, h, sig)) * col2.a
					return fill.lerp(Color(col2.r, col2.g, col2.b), a)
			"Inner Glow":
				outer = false
				var R: float = e["radius"]
				sig = R * 0.25
				var col3: Color = e["color"]
				region = box
				expected = func(sp: Vector2, _bg: Color) -> Variant:
					var lp := _local(rect, sp)
					if absf(lp.x) > h.x - 1.5 / z or absf(lp.y) > h.y - 1.5 / z:
						return null
					var a := (1.0 - rect_cover(lp, h - Vector2(R * 0.5, R * 0.5), sig))
					return fill.lerp(col3, a)
		var ex := _exact_error(E, B, region, expected)
		var m := {"viol": 0, "step": 0.0, "tail": 0.0, "peak": 0.0}
		if outer:
			var ext := 3.2 * sig * z + absf(float(e.get("spread", 0.0))) * z + Vector2(float(e.get("offset_x", 0.0)), float(e.get("offset_y", 0.0))).length() * z
			m = _outer_checks(nm, E, B, box, ext, 2.0 if t != "Blur" else -0.0)
			if t == "Blur":
				# el desenfoque ocupa también el interior: perfil desde el centro
				var pr := _profile(E, B, box.get_center(), Vector2.RIGHT, int(box.size.x * 0.5 + ext + 30))
				var a2 := _analyze(pr, 2.5 / 255.0)
				m["viol"] = maxi(m["viol"], a2[0])
				m["step"] = maxf(m["step"], a2[1])
			_check(m["tail"] < 4.0 / 255.0, "%s z%.1f: el halo llega al fondo, sin corte (cola %.1f/255)" % [nm, z, m["tail"] * 255.0])
			_check(m["viol"] == 0, "%s z%.1f: decae sin anillos / capas (%d)" % [nm, z, m["viol"]])
		_check(ex[0] < 2.5 and ex[1] < 14.0, "%s z%.1f: igual que la gaussiana exacta (medio %.2f, máx %.1f)" % [nm, z, ex[0], ex[1]])
		_row(nm, z, m, ex)
		_apply_fx(rect, [])

	# ── B. CÍRCULO contra la gaussiana exacta del disco ────────────────────
	for zc in [1.0, 2.0]:
		var nm2 := "círculo desenfoque 200 (máx)"
		if only != "" and not nm2.contains(only):
			break
		var fxc := [{"type": "Blur", "enabled": true, "radius": 200.0, "blur_type": "gaussian"}]
		var resc: Array = await _capture(circ, zc, fxc)
		var Ec: Image = resc[0]
		var Bc: Image = resc[1]
		var boxc: Rect2 = resc[2]
		Ec.save_png("%s/circulo_desenfoque_200_z%.1f.png" % [out, zc])
		var sigc := 100.0
		var tab := disk_table(80.0, sigc, 80.0 + 4.6 * sigc, 1.0)
		var exc := _exact_error(Ec, Bc, boxc.grow(3.2 * sigc * zc), func(sp: Vector2, bg: Color) -> Variant:
			var lp := _local(circ, sp)
			return bg.lerp(fill, table_at(tab, lp.length(), 1.0)))
		var mc := _outer_checks(nm2, Ec, Bc, boxc, 3.2 * sigc * zc, 0.0)
		_check(exc[0] < 2.5 and exc[1] < 14.0, "%s z%.1f: igual que la gaussiana exacta (medio %.2f, máx %.1f)" % [nm2, zc, exc[0], exc[1]])
		_check(mc["viol"] == 0 and mc["tail"] < 4.0 / 255.0, "%s z%.1f: suave y sin corte" % [nm2, zc])
		_row(nm2, zc, mc, exc)
		_apply_fx(circ, [])

	# ── C. Estrella, trazado y texto: suavidad, sin anillos ni cortes ──────
	var GEN := [
		["desenfoque 200 (máx)", [{"type": "Blur", "enabled": true, "radius": 200.0, "blur_type": "gaussian"}], [], 320.0, true, 100.0, 1.0],
		["desenfoque 40", [{"type": "Blur", "enabled": true, "radius": 40.0, "blur_type": "gaussian"}], [], 64.0, true, 20.0, 1.0],
		["sombra 100", [{"type": "Drop Shadow", "enabled": true, "offset_x": 30.0, "offset_y": 30.0, "blur": 100.0, "spread": 0.0, "color": Color(0, 0, 0, 0.8)}], [], 205.0, false, 50.0, 1.0],
		["sombra 100 extensión 50", [{"type": "Drop Shadow", "enabled": true, "offset_x": 0.0, "offset_y": 0.0, "blur": 100.0, "spread": 50.0, "color": Color(0, 0, 0, 0.8)}], [], 215.0, false, 50.0, 1.0],
		["neón 100", [], [{"type": "neon", "enabled": true, "color": Color(1, 0.1, 0.9), "radius": 100.0, "intensity": 400.0, "tint": 60.0}], 165.0, false, 50.0, 6.4],
	]
	for target in [["estrella", star], ["trazado", path], ["texto", title]]:
		for cs2 in GEN:
			var nm3: String = "%s %s" % [target[0], cs2[0]]
			if only != "" and not nm3.contains(only):
				continue
			for zz in [0.5, 1.0, 2.0]:
				var n3: Node2D = target[1]
				var res3: Array = await _capture(n3, zz, cs2[1], cs2[2])
				var E3: Image = res3[0]
				var B3: Image = res3[1]
				var box3: Rect2 = res3[2]
				E3.save_png("%s/%s_z%.1f.png" % [out, nm3.replace(" ", "_"), zz])
				var ext3: float = float(cs2[3]) * zz
				var m3 := _outer_checks(nm3, E3, B3, box3, ext3, 0.0 if cs2[4] else 3.0)
				if target[0] == "estrella" and String(cs2[0]).contains("extensión"):
					# justo fuera de un vértice CÓNCAVO la sombra debe verse (antes
					# quedaban cuñas blancas por un recorte aproximado)
					var ang := -PI / 2 + PI / 5
					var lp := Vector2(cos(ang), sin(ang)) * 46.0
					var sp: Vector2 = n3.get_global_transform_with_canvas() * lp
					var cc := E3.get_pixelv(Vector2i(sp))
					_check(lum(cc) < 0.75, "%s z%.1f: sombra pegada en las esquinas cóncavas (lum %.2f)" % [nm3, zz, lum(cc)])
				_check(m3["tail"] < 4.0 / 255.0, "%s z%.1f: el halo llega al fondo, sin corte (cola %.1f/255)" % [nm3, zz, m3["tail"] * 255.0])
				_check(m3["viol"] <= 1, "%s z%.1f: decae sin anillos / capas (%d)" % [nm3, zz, m3["viol"]])
				# sin saltos: el mayor escalón entre píxeles vecinos no supera
				# ~3× la pendiente máxima de una gaussiana de ese σ
				var sig_px: float = float(cs2[5]) * zz
				# (neón: intensidad 400 % × 1,6 amplifica la pendiente antes de saturar)
				var thr: float = maxf(6.0 / 255.0, 3.0 * float(cs2[6]) * m3["peak"] / (sig_px * 2.5066))
				_check(m3["step"] <= thr, "%s z%.1f: sin saltos / líneas duras (%.1f > %.1f /255)" % [nm3, zz, m3["step"] * 255.0, thr * 255.0])
				if not cs2[4]:
					var jr := _max_jump(E3, B3, box3.grow(ext3), box3)
					_check(jr <= thr, "%s z%.1f: ninguna línea dura en toda la región (%.1f > %.1f /255)" % [nm3, zz, jr * 255.0, thr * 255.0])
				_check(m3["peak"] > 10.0 / 255.0, "%s z%.1f: el efecto se ve (pico %.0f)" % [nm3, zz, m3["peak"] * 255.0])
				_row(nm3, zz, m3)
				_apply_fx(n3, [], [])

	# ── D. Contorno 100 en texto: banda del ancho pedido, sin festones ─────
	if only == "" or "contorno".contains(only) or only.contains("contorno"):
		for zo in [0.5, 1.0]:
			var reso: Array = await _capture(title, zo, [{"type": "Outline", "enabled": true, "width": 100.0, "color": Color(0.9, 0.1, 0.1)}])
			var Eo: Image = reso[0]
			var Bo: Image = reso[1]
			var boxo: Rect2 = reso[2]
			Eo.save_png("%s/texto_contorno_100_z%.1f.png" % [out, zo])
			# ancho de la banda en la fila donde la TINTA llega más a la derecha
			# (punto extremo convexo: ahí la dilatación sobresale exactamente w)
			var best_ink := -1
			var w_px := 0
			for yy in range(int(boxo.position.y), int(boxo.end.y), 1):
				var last_ink := -1
				var last_red := -1
				for xx in range(int(boxo.position.x), mini(Eo.get_width(), int(boxo.end.x + 200 * zo))):
					var col := Eo.get_pixel(xx, yy)
					if col.r < 0.5 and col.g < 0.5 and col.b < 0.5:
						last_ink = xx
					elif col.r > 0.6 and col.g < 0.4:
						last_red = xx
				if last_ink > best_ink and last_red > last_ink:
					best_ink = last_ink
					w_px = last_red - last_ink
			var expect_px: float = 100.0 * zo
			_check(absf(w_px - expect_px) < 0.25 * expect_px + 8.0, "texto contorno 100 z%.1f: banda de ~%.0f px (medida %d)" % [zo, expect_px, w_px])
			print("BQ texto contorno 100 z%.1f  ancho_medido=%d px (esperado ~%.0f)" % [zo, w_px, expect_px])
			_apply_fx(title, [])

	print("BQ FIN")
	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
