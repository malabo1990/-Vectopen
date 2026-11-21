# =============================================================================
# FASE B · ENCARGO 30 — Vectorizar una foto y depurar (modo Pro)
# Foco: umbrales, simplificación, rendimiento.
# Una «foto» sintética de 800 × 600 (cielo degradado, sol, montañas, ruido de
# sensor) se vectoriza con dos presets: «Ilustración» (menos colores) y
# «Foto (más detalle)». Se compara nº de trazados, tiempos y fluidez; se
# depura: «Simplificar trazado» sobre todo el resultado (menos nodos, mismo
# aspecto), se borran las motas diminutas, se mide el fotograma, se exporta
# un SVG razonable y se reabre.
#   test/run_e2e.sh proyecto_30_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/30"
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(580.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func photo() -> Image:
	var w := 800
	var h := 600
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 30
	for y in h:
		for x in w:
			var t := float(y) / h
			var c := Color("#4a90d9").lerp(Color("#f7c59f"), t)
			var d := Vector2(x, y).distance_to(Vector2(600, 180))
			if d < 70:
				c = Color("#fff3b0").lerp(c, clampf((d - 55) / 15.0, 0.0, 1.0))
			var ridge := 380.0 + sin(x * 0.012) * 60.0 + sin(x * 0.041) * 18.0
			if y > ridge:
				c = Color("#3d405b").lerp(Color("#2b2d42"), clampf((y - ridge) / 200.0, 0.0, 1.0))
			var ridge2 := 470.0 + sin(x * 0.02 + 1.0) * 40.0
			if y > ridge2:
				c = Color("#52796f")
			var nz := rng.randf_range(-0.035, 0.035)
			img.set_pixel(x, y, Color(clampf(c.r + nz, 0, 1), clampf(c.g + nz, 0, 1), clampf(c.b + nz, 0, 1)))
	return img

func paths(g: Node) -> Array:
	return g.find_children("*", "", true, false).filter(func(n) -> bool: return n is VectorPath)

func area_of(p: VectorPath) -> float:
	var pts := VectorPath.closed_points(p.curve)
	var a := 0.0
	for i in pts.size():
		a += pts[i].cross(pts[(i + 1) % pts.size()])
	return absf(a) * 0.5

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("professional"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	if not ClassDB.class_exists("VectorizerJob"):
		K.check("vectorizador nativo disponible", false)
		print("RESULT: 1 FAIL")
		quit(1)
		return
	var ab: Node2D = await K.artboard(Vector2(1700, 700), "Foto", Color.WHITE)
	var img := photo()
	var s1 = api.add_image(img, Vector2(420, 350), "Foto A")
	var s2 = api.add_image(img, Vector2(1280, 350), "Foto B")
	await K.frames(4)
	var t0 := Time.get_ticks_msec()
	var g1: Node2D = await api.vectorize(s1, "Ilustración", true, false)
	var ms1 := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var g2: Node2D = await api.vectorize(s2, "Foto (más detalle)", true, false)
	var ms2 := Time.get_ticks_msec() - t0
	K.note("ilustracion_ms", ms1)
	K.note("foto_ms", ms2)
	K.check("las dos vectorizaciones terminan", g1 != null and g2 != null)
	if g1 == null or g2 == null:
		print("RESULT: %d FAIL" % K.fails)
		quit(1)
		return
	var n1 := paths(g1).size()
	var n2 := paths(g2).size()
	K.note("trazados_ilustracion", n1)
	K.note("trazados_foto", n2)
	# «Foto» filtra más motas (menos trazados) pero con más precisión de color.
	var cols := func(g: Node) -> int:
		var seen := {}
		for p in paths(g):
			seen[(p.fill_color as Color).to_html(false)] = true
		return seen.size()
	var c1: int = cols.call(g1)
	var c2: int = cols.call(g2)
	K.note("colores_ilustracion", c1)
	K.note("colores_foto", c2)
	K.check("los dos presets dan resultados distintos", c1 != c2 or n1 != n2, "%d/%d tonos, %d/%d trazados" % [c1, c2, n1, n2])
	# Umbral binario: «Blanco y negro» deja como mucho 2 tonos
	var s3 = api.add_image(img, Vector2(420, 350), "Foto BN")
	var g3: Node2D = await api.vectorize(s3, "Blanco y negro", true, true)
	var c3: int = cols.call(g3) if g3 else 99
	K.check("umbral «Blanco y negro»: ≤ 2 tonos", g3 != null and c3 <= 2, str(c3))
	if g3:
		api.delete([g3, s3])
	K.check("cada vectorización en menos de 20 s", ms1 < 20000 and ms2 < 20000, "%d / %d ms" % [ms1, ms2])
	await K.look_at(ab)
	var fr: float = await K.frame_ms("vectorizado")
	K.check("con las dos a la vista, ≥ 30 fps", fr <= 34.0, "%.1f ms" % fr)
	await K.shot("01_vectorizado")
	# Depurar el detallado: motas diminutas fuera y simplificar
	var nodes0: int = api.count_nodes(g2)
	var tiny: Array = paths(g2).filter(func(p) -> bool: return area_of(p) < 12.0)
	K.note("motas", tiny.size())
	if not tiny.is_empty():
		api.delete(tiny)
	var n_after_del := paths(g2).size()
	K.check("borrar las motas (< 12 px²)", n_after_del == n2 - tiny.size(), "%d → %d" % [n2, n_after_del])
	var nodes_mid: int = api.count_nodes(g2)
	t0 = Time.get_ticks_msec()
	var removed: int = api.simplify_path(g2, 1.0)
	var ms_s := Time.get_ticks_msec() - t0
	var nodes1: int = api.count_nodes(g2)
	K.note("nodos_antes", nodes0)
	K.note("nodos_despues", nodes1)
	K.note("simplificar_ms", ms_s)
	K.check("simplificar quita al menos un 30 % de nodos", nodes1 < nodes_mid * 0.7, "%d → %d" % [nodes_mid, nodes1])
	K.check("y en menos de 10 s", ms_s < 10000, "%d ms" % ms_s)
	api.undo()
	K.check("deshacer la simplificación (un paso)", api.count_nodes(g2) == nodes_mid, "%d vs %d" % [api.count_nodes(g2), nodes_mid])
	api.redo()
	await K.frames(4)
	var fr2: float = await K.frame_ms("depurado")
	K.check("depurado: también ≥ 30 fps", fr2 <= 34.0, "%.1f ms" % fr2)
	await K.shot("02_depurado")
	var p_svg := ProjectSettings.globalize_path(OUT.path_join("foto.svg"))
	var ok: bool = await api.export(p_svg, ab)
	var size := FileAccess.get_file_as_bytes(p_svg).size() if ok else 0
	K.note("svg_kb", size / 1024)
	K.check("SVG exportado (sin las imágenes, < 3 MB)", ok and size < 3_000_000 and not FileAccess.get_file_as_string(p_svg).contains("<image"), "%d KB" % (size / 1024))
	await K.frames(10)
	var abs: Array = await K.save_reload("foto")
	for a in abs:
		if String(a.name) == "Foto":
			var np: int = a.find_children("*", "", true, false).filter(func(n) -> bool: return n is VectorPath).size()
			K.check("reabrir: los mismos trazados", np == n1 + n_after_del, "%d vs %d" % [np, n1 + n_after_del])
			await K.look_at(a)
			var fr3: float = await K.frame_ms("reabierto")
			K.check("reabierto ≥ 30 fps", fr3 <= 34.0, "%.1f ms" % fr3)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
