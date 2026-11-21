# =============================================================================
# FASE B · ENCARGO 14 — Retrato con máscaras (modo Pro)
# Foco: recorte entre dos Bézier.
# Retrato estilizado 800 × 1000: silueta de la cara (Bézier) que recorta una
# «foto» (imagen) y unas sombras; pelo (Bézier) que recorta un degradado de
# mechones (Bézier dentro de Bézier); ojo con iris recortado por el párpado
# (las máscaras anidadas se rechazan: VAL-43). «Crear máscara de recorte» desde el menú contextual con
# la selección (la de arriba recorta), editar un nodo de la máscara después
# (el recorte la sigue), soltar y volver a crear, deshacer, exportar SVG
# (clipPath) y PDF, guardar y reabrir con las máscaras intactas.
#   test/run_e2e.sh proyecto_14_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/14"
const SKIN := Color("#e8b796")
const HAIR := Color("#3b2a20")
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func bezier(pts: Array, name: String, fill: Color) -> Node2D:
	## pts: [[p, in, out], …] cerrada
	var c := Curve2D.new()
	for e in pts:
		c.add_point(e[0], e[1], e[2])
	c.add_point(pts[0][0], pts[0][1], Vector2.ZERO)
	var n = api.add_curve(c, true, name)
	api.set_props(n, {"fill_color": fill, "stroke_width": 0.0})
	return n

func oval(c: Vector2, r: Vector2, name: String, fill: Color) -> Node2D:
	var k := 0.5523
	return bezier([
		[c + Vector2(0, -r.y), Vector2(-r.x * k, 0), Vector2(r.x * k, 0)],
		[c + Vector2(r.x, 0), Vector2(0, -r.y * k), Vector2(0, r.y * k)],
		[c + Vector2(0, r.y), Vector2(r.x * k, 0), Vector2(-r.x * k, 0)],
		[c + Vector2(-r.x, 0), Vector2(0, r.y * k), Vector2(0, -r.y * k)],
	], name, fill)

## Píxel de la captura en un punto de la página.
func px(ab: Node2D, p: Vector2) -> Color:
	var img := root.get_texture().get_image()
	var sp: Vector2 = K.canvas.get_viewport().get_canvas_transform() * (ab.global_position + p)
	return img.get_pixelv(Vector2i(sp))

func context(action: String) -> void:
	var host: Node = null
	for n in root.find_children("*", "", true, false):
		if n.get_script() and String(n.get_script().resource_path).ends_with("smart_menu_extras.gd"):
			host = n.get_parent()
	if host:
		ContextMenuActions.execute(action, host)
	await K.frames(3)

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("professional"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(800, 1000), "Retrato", Color("#f1ece4"))
	# ── Cara: foto + sombra recortadas por la silueta ────────────────────────
	var photo = api.add_image(K.gradient_image(600, 760, Color("#f3c9a8"), Color("#b97a56")), Vector2(400, 520), "Foto")
	var shade = oval(Vector2(520, 600), Vector2(160, 240), "Sombra", Color(0.35, 0.18, 0.1, 0.35))
	var face = bezier([
		[Vector2(400, 230), Vector2(-120, 0), Vector2(120, 0)],
		[Vector2(600, 480), Vector2(0, -150), Vector2(0, 160)],
		[Vector2(400, 820), Vector2(130, 0), Vector2(-130, 0)],
		[Vector2(200, 480), Vector2(0, 160), Vector2(0, -150)],
	], "Silueta", SKIN)
	api.select([photo, shade, face])
	await K.frames(3)
	var host_ok := false
	for n in root.find_children("*", "", true, false):
		if n.get_script() and String(n.get_script().resource_path).ends_with("smart_menu_extras.gd"):
			n.get_parent().visible = true
			await K.frames(2)
			var b := n.get_parent().find_child("MakeMask", true, false) as Control
			host_ok = b != null and b.visible
			n.get_parent().visible = false
	K.check("el menú contextual ofrece «Crear máscara de recorte» con 3 objetos", host_ok)
	await context("make_mask")
	K.check("la silueta (arriba) recorta foto y sombra", photo.get_parent() == face and shade.get_parent() == face and face.clip_children != 0)
	await K.look_at(ab)
	await K.frames(4)
	await RenderingServer.frame_post_draw
	var outside := px(ab, Vector2(120, 520))   # fuera de la cara, dentro de la foto
	K.check("fuera de la silueta no se ve la foto", outside.is_equal_approx(Color("#f1ece4")) or (outside - Color("#f1ece4")).v < 0.03, str(outside))
	# ── Pelo: Bézier recortando mechones Bézier ──────────────────────────────
	var strands: Array = []
	for i in 9:
		var x := 180.0 + i * 55.0
		var s = bezier([
			[Vector2(x, 120), Vector2.ZERO, Vector2(30, 60)],
			[Vector2(x + 25, 420), Vector2(-20, -80), Vector2(10, 0)],
			[Vector2(x + 40, 420), Vector2(0, 0), Vector2(10, -120)],
		], "Mechón %d" % i, HAIR.lightened(0.05 * (i % 3)))
		strands.append(s)
	var hair = bezier([
		[Vector2(400, 140), Vector2(-200, 0), Vector2(200, 0)],
		[Vector2(640, 420), Vector2(0, -180), Vector2(-40, 20)],
		[Vector2(400, 300), Vector2(120, 0), Vector2(-120, 0)],
		[Vector2(160, 420), Vector2(40, 20), Vector2(0, -180)],
	], "Pelo", Color(0, 0, 0, 0))
	K.check("pelo: Bézier recorta los 9 mechones (solo recorta, sin relleno)", api.make_mask(hair, strands) and hair.clip_children == CanvasItem.CLIP_CHILDREN_ONLY)
	# ── Ojo: iris dentro del párpado, máscara ANIDADA dentro de la cara ──────
	var iris = oval(Vector2(330, 470), Vector2(22, 22), "Iris", Color("#3a6ea5"))
	var lid = bezier([
		[Vector2(290, 470), Vector2.ZERO, Vector2(20, -22)],
		[Vector2(370, 470), Vector2(-20, -22), Vector2(-20, 18)],
	], "Párpado", Color.WHITE)
	K.check("ojo: el párpado recorta el iris", api.make_mask(lid, [iris]))
	# VAL-43 (abierto): Godot no dibuja una máscara dentro de otra → se rechaza
	# con aviso en vez de dar un recorte roto. El ojo queda encima de la cara.
	K.check("máscara anidada rechazada con aviso (VAL-43)", not api.make_mask(face, [lid]) and lid.get_parent() == ab)
	await K.frames(4)
	await K.shot("01_retrato")
	# ── Editar un nodo de la máscara: el recorte la sigue ────────────────────
	var cv: Curve2D = face.curve
	var p1 := cv.get_point_position(1)
	api.begin("Mover nodo de la silueta")
	var c2: Curve2D = cv.duplicate()
	c2.set_point_position(1, p1 + Vector2(150, 0))
	api.set_prop(face, "curve", c2)
	api.end()
	await K.frames(4)
	await RenderingServer.frame_post_draw
	var widened := px(ab, Vector2(680, 480))
	K.check("al mover un nodo de la silueta se ve más foto", (widened - Color("#f1ece4")).v > 0.03 or not widened.is_equal_approx(Color("#f1ece4")), str(widened))
	api.undo()
	await K.frames(3)
	# ── Soltar y volver a crear ──────────────────────────────────────────────
	var freed: Array = api.release_mask(hair)
	K.check("soltar la máscara del pelo devuelve los 9 mechones", freed.size() == 9 and strands.all(func(s) -> bool: return s.get_parent() == ab) and hair.clip_children == 0)
	api.undo()
	await K.frames(2)
	K.check("deshacer «soltar» vuelve a recortar", strands.all(func(s) -> bool: return s.get_parent() == hair) and hair.clip_children != 0)
	await K.undo_redo(20)
	# ── Exportar ─────────────────────────────────────────────────────────────
	var ex: Dictionary = await K.export_all(ab, "retrato")
	if ex.has("svg"):
		var svg := FileAccess.get_file_as_string(ex["svg"])
		K.check("SVG con recortes (clipPath ≥ 3)", svg.count("<clipPath") >= 3, str(svg.count("<clipPath")))
	if ex.has("pdf"):
		var pdf := FileAccess.get_file_as_bytes(ex["pdf"]).get_string_from_ascii()
		K.check("PDF con trazados de recorte (W n)", pdf.contains(" W n") or pdf.contains("W\nn") or pdf.contains(" W*"), "")
	var abs: Array = await K.save_reload("retrato")
	for a in abs:
		if String(a.name) == "Retrato":
			var f2: Node = a.find_child("Silueta*", false, false)
			var h2: Node = a.find_child("Pelo*", false, false)
			K.check("reabrir: la silueta sigue recortando (foto, sombra)", f2 != null and f2.clip_children != 0 and f2.get_child_count() >= 2, str(f2.get_child_count()) if f2 else "-")
			K.check("reabrir: el pelo sigue recortando sus mechones", h2 != null and h2.clip_children != 0 and h2.get_child_count() == 9)
			var l2: Node = a.find_child("Párpado*", false, false)
			K.check("reabrir: la máscara del ojo", l2 != null and l2.clip_children != 0 and l2.get_child_count() == 1)
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
