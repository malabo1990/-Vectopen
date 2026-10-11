## RENDER DEL TEXTO sin MSDF:
##   · AJUSTE: los efectos de texto (dibujados con los contornos reales)
##     coinciden con el texto visible (antes, con MSDF, la letra se veía ~7 %
##     más grande y los efectos quedaban desplazados);
##   · NITIDEZ con zoom: el borde de la letra sigue midiendo 1–2 px a zoom
##     1, 2, 4, 8, 16 y 32 (sobremuestreo por zoom) y sigue nítido a 64…4000×
##     (por encima del tope de raster, la letra se dibuja con su contorno);
##   · las fuentes del lienzo ya no usan MSDF.
##   godot --path . -s res://test/e2e/text_render_e2e.gd   (E2E_OUT=carpeta)
extends SceneTree

var canvas: Node2D
var fails: Array[String] = []

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

func _bbox(img: Image, r: Rect2i, pred: Callable) -> Rect2i:
	var lo := Vector2i(99999, 99999)
	var hi := Vector2i(-1, -1)
	var rr := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	for y in range(rr.position.y, rr.end.y):
		for x in range(rr.position.x, rr.end.x):
			if pred.call(img.get_pixel(x, y)):
				lo = lo.min(Vector2i(x, y))
				hi = hi.max(Vector2i(x, y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)

## Anchura (px) de la transición blanco→negro del primer borde vertical que
## encuentra en la fila y (10 % → 90 % de tinta).
func _edge(img: Image, y: int, x0: int, x1: int) -> int:
	var start := -1
	for x in range(x0, x1):
		var l := img.get_pixel(x, y).r
		if start < 0 and l < 0.9:
			start = x
		if start >= 0 and l <= 0.1:
			return x - start
		if start >= 0 and l >= 0.9:
			start = -1
	return 999

func _run() -> void:
	var out := OS.get_environment("E2E_OUT")
	if out == "": out = "user://text_render"
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(30)
	canvas = get_first_node_in_group("_vectopen_canvas")
	var ic = root.get_node("InspectorCore")
	var sm = root.get_node("SelectionManager")
	var native := ClassDB.class_exists("VectorRichText")
	print("TEXTO modo: ", "nativo" if native else "GDScript")
	for cl in root.find_children("*", "CanvasLayer", true, false):
		if not (cl as Node).is_ancestor_of(canvas):
			(cl as CanvasLayer).visible = false
	var cam = canvas.get_node("Camera2D")
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	ab.artboard_size = Vector2(6000, 6000)

	# ── 0. Fuentes sin MSDF ─────────────────────────────────────────────────
	var fc = root.get_node("FontCore")
	var f = fc.default_font()
	var base_f = f.base_font if f is FontVariation else f
	_check(base_f is FontFile and not (base_f as FontFile).multichannel_signed_distance_field, "la fuente del lienzo no usa MSDF")

	# ── 1. Ajuste efectos ↔ texto visible ──────────────────────────────────
	for fsz in [32, 64, 160, 300]:
		canvas.switch_tool("text")
		var t: Node2D = canvas.current_tool.create_at_center()
		sm.select(t); ic._sync_selection()
		ic.apply("text", "ROMA")
		ic.apply("font_size", fsz)
		canvas.switch_tool("move")
		cam.zoom = Vector2.ONE
		cam.global_position = canvas.current_tool._global_rect(t).get_center()
		sm.set_selection([]); ic._sync_selection()
		await _frames(10)
		var img0 := root.get_texture().get_image()
		var c := Vector2i(img0.get_size() / 2)
		var reg := Rect2i(c - Vector2i(700, 350), Vector2i(1400, 700))
		var ink := _bbox(img0, reg, func(col: Color) -> bool: return col.r < 0.5 and col.g < 0.5 and col.b < 0.5)
		sm.select(t); ic._sync_selection()
		ic.apply("effects", [{"type": "Color Overlay", "enabled": true, "color": Color(1, 0, 0, 1), "opacity": 1.0}])
		sm.set_selection([]); ic._sync_selection()
		await _frames(10)
		var img1 := root.get_texture().get_image()
		img1.save_png("%s/ajuste_%d.png" % [out, fsz])
		var red := _bbox(img1, ink.grow(40), func(col: Color) -> bool: return col.r > 0.5 and col.g < 0.45 and col.b < 0.45)
		var d := [red.position.x - ink.position.x, red.position.y - ink.position.y, red.end.x - ink.end.x, red.end.y - ink.end.y]
		var mx := 0
		for v in d:
			mx = maxi(mx, absi(v))
		# además: ningún píxel de tinta negra asoma fuera del rojo
		var leak := 0
		for y in range(ink.position.y, ink.end.y):
			for x in range(ink.position.x, ink.end.x):
				var col := img1.get_pixel(x, y)
				if col.r < 0.3 and col.g < 0.3 and col.b < 0.3:
					leak += 1
		print("TEXTO %3d pt  tinta=%s efecto=%s  bordes %s  negro asomando=%d px" % [fsz, ink, red, d, leak])
		_check(mx <= 2, "%d pt: el efecto coincide con la letra (desvío máx %d px)" % [fsz, mx])
		_check(leak <= ink.size.x * 0.02 + 4, "%d pt: la letra no asoma por fuera del efecto (%d px)" % [fsz, leak])
		t.queue_free()
		await _frames(3)

	# ── 2. Nitidez con zoom ────────────────────────────────────────────────
	canvas.switch_tool("text")
	var tz: Node2D = canvas.current_tool.create_at_center()
	sm.select(tz); ic._sync_selection()
	ic.apply("text", "IH")
	ic.apply("font_size", 24)
	canvas.switch_tool("move")
	sm.set_selection([]); ic._sync_selection()
	await _frames(5)
	var r0: Rect2 = canvas.current_tool._global_rect(tz)
	for z in [1.0, 2.0, 4.0, 8.0, 16.0, 32.0]:
		cam.zoom = Vector2(z, z)
		# centrar en la "I" (izquierda del texto)
		cam.global_position = Vector2(r0.position.x + r0.size.x * 0.25, r0.get_center().y)
		await _frames(25)   # el sobremuestreo se aplica al cambiar el zoom
		var img := root.get_texture().get_image()
		img.save_png("%s/zoom_%d.png" % [out, int(z)])
		var cy := img.get_height() / 2
		var w := 999
		for dy in [-4, 0, 4]:
			w = mini(w, _edge(img, cy + int(dy * z), 0, img.get_width()))
		print("TEXTO zoom %2d×  ancho del borde = %d px" % [int(z), w])
		_check(w <= 3, "zoom %d×: texto nítido (borde %d px)" % [int(z), w])

	# ── 3. Zoom EXTREMO: por encima del tope de raster la letra se dibuja con
	# su contorno; el borde tiene que seguir midiendo 1–3 px. Se centra la
	# cámara en el borde izquierdo de la "I" (medido a 32×) para que caiga en
	# pantalla aunque la letra ocupe miles de px.
	var img32 := root.get_texture().get_image()
	var half := Vector2(img32.get_size()) / 2.0
	var ink32 := _bbox(img32, Rect2i(Vector2i.ZERO, img32.get_size()), func(col: Color) -> bool: return col.r < 0.5)
	var cam32: Vector2 = cam.global_position
	var edge_world := Vector2(cam32.x + (ink32.position.x - half.x) / 32.0, cam32.y + (ink32.get_center().y - half.y) / 32.0)
	for z in [64.0, 128.0, 256.0, 1000.0, 4000.0]:
		cam.zoom = Vector2(z, z)
		cam.global_position = edge_world
		await _frames(25)
		var img := root.get_texture().get_image()
		img.save_png("%s/zoom_%d.png" % [out, int(z)])
		var cy := img.get_height() / 2
		var w := 999
		for dy in [-40, 0, 40]:
			w = mini(w, _edge(img, cy + dy, 0, img.get_width()))
		print("TEXTO zoom %4d×  ancho del borde = %d px" % [int(z), w])
		_check(w <= 3, "zoom %d×: texto nítido con contorno (borde %d px)" % [int(z), w])
	print("TEXTO FIN")
	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
