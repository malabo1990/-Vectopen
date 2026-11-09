# =============================================================================
# KIT DE CAMPAÑAS (encargos 31–35): piezas comunes para montar anuncios
# profesionales completos en pruebas e2e y medir su rendimiento:
# varias mesas de trabajo, Bézier, polígonos, máscaras, pincel, pincel hecho
# de figuras seleccionadas, texto en trazado, grupos, exportar a todos los
# formatos y volver a importar, guardar/reabrir, deshacer en serie.
# Uso: var K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
# =============================================================================
extends RefCounted

const R = preload("res://script_gdscript/shapes/brush_stroke_render.gd")
const OB = preload("res://script_gdscript/shapes/object_brush.gd")

var t: SceneTree
var out_dir: String
var api
var canvas
var cont: Node
var sm
var hm
var ic
var CS
var IEM
var fails := 0
var bench: Dictionary = {}

func _init(tree: SceneTree, out: String) -> void:
	t = tree
	out_dir = out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await t.process_frame

func note(key: String, value) -> void:
	bench[key] = value
	print("BENCH %s=%s" % [key, str(value)])

## Arranca Vectopen en la pantalla de pruebas, en el modo pedido.
func boot(mode: String = "modern") -> bool:
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	t.change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await t.process_frame
	await frames(30)
	t.root.get_node("GlobalUI").set_ui_mode(mode)
	await frames(30)
	canvas = t.get_first_node_in_group("_vectopen_canvas")
	api = t.root.get_node("PluginManager").api
	sm = t.root.get_node("SelectionManager")
	hm = t.root.get_node("HistoryManager")
	ic = t.root.get_node("InspectorCore")
	IEM = t.root.get_node_or_null("ImportExportManager")
	CS = load("res://scripts/canvas/canvas_serializer.gd")
	cont = api.artboard().get_parent() if api.artboard() else null
	return canvas != null and cont != null

var _first_used := false

## Mesa de trabajo: la primera reutiliza la que trae el documento nuevo.
func artboard(size: Vector2, name: String, bg: Color = Color.WHITE) -> Node2D:
	var ab: Node2D
	if not _first_used:
		_first_used = true
		ab = api.artboard()
		ab.artboard_size = size
		ab.name = name
		for c in ab.get_children():
			if c.has_meta("shape_type") or c is Line2D or c is Path2D:
				c.queue_free()
	else:
		ab = api.add_artboard(size, name)
	if "fill_color" in ab:
		ab.fill_color = bg
	api.set_active_artboard(ab)
	await frames(2)
	return ab

func look_at(ab: Node2D, zoom: float = 0.0) -> void:
	var cam: Camera2D = canvas.camera
	var vp: Vector2 = canvas.get_viewport().get_visible_rect().size
	var z := zoom if zoom > 0.0 else minf(vp.x / (ab.artboard_size.x * 1.35), vp.y / (ab.artboard_size.y * 1.25))
	cam.zoom = Vector2(z, z)
	cam.position = ab.global_position + ab.artboard_size / 2.0
	await frames(6)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	t.root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))

# ── Formas ───────────────────────────────────────────────────────────────────
## Onda Bézier de `a` a `b`.
func wave(a: Vector2, b: Vector2, amp: float, waves: int, color: Color, width: float, name: String = "Onda") -> Node2D:
	var c := Curve2D.new()
	var n := waves * 2
	for i in n + 1:
		var f := float(i) / float(n)
		var p := a.lerp(b, f) + Vector2(0, amp * (1.0 if i % 2 == 0 else -1.0))
		var h := (b - a) / float(n) * 0.5
		c.add_point(p, -h if i > 0 else Vector2.ZERO, h if i < n else Vector2.ZERO)
	var p2 = api.add_curve(c, false, name)
	api.set_props(p2, {"stroke_width": width, "stroke_color": color})
	return p2

## Mancha orgánica cerrada (Bézier suave).
func blob(center: Vector2, r: float, lobes: int, jitter: float, fill: Color, name: String = "Mancha", seed: int = 1) -> Node2D:
	var c := Curve2D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := lobes * 2
	for i in n:
		var a := TAU * i / n
		var rr := r * (1.0 + rng.randf_range(-jitter, jitter))
		var p := center + Vector2(cos(a), sin(a)) * rr
		var tg := Vector2(-sin(a), cos(a)) * rr * 0.55 * TAU / n
		c.add_point(p, -tg, tg)
	var p2 = api.add_curve(c, true, name)
	api.set_props(p2, {"fill_color": fill, "stroke_width": 0.0})
	return p2

func gradient_image(w: int, h: int, c1: Color, c2: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, c1.lerp(c2, (float(x) / w + float(y) / h) * 0.5))
	return img

var _ls: Node = null

## Máscara: `child` queda recortado por `mask_shape` (como el panel Capas).
func mask(mask_shape: Node2D, child: Node2D) -> bool:
	if not is_instance_valid(_ls):
		for n in t.root.find_children("*", "", true, false):
			if n.get_script() and n.get_script().get_global_name() == "LayerSystem":
				_ls = n
				break
	var ls: Node = _ls
	if ls == null:
		return false
	var gp: Vector2 = child.global_position
	child.get_parent().remove_child(child)
	mask_shape.add_child(child)
	child.global_position = gp
	ls._set_clip(null, mask_shape, ls._modo_clip(mask_shape))
	await frames(3)
	return mask_shape.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED

# ── Pinceles ─────────────────────────────────────────────────────────────────
func brush(pts: PackedVector2Array, width: float, style: String, color: Color, taper: bool = true, name: String = "Pincel") -> Line2D:
	var l := Line2D.new()
	l.name = name
	l.points = pts
	l.width = width
	l.default_color = color
	l.set_meta("brush_style", style)
	if taper:
		var wc := Curve.new()
		wc.add_point(Vector2(0, 0.25))
		wc.add_point(Vector2(0.5, 1.0))
		wc.add_point(Vector2(1, 0.2))
		l.width_curve = wc
	api.add(l)
	R.attach(l)
	return l

## Pincel de OBJETO hecho con figuras ya dibujadas (como «Selección» del panel).
func object_brush(shapes: Array, pts: PackedVector2Array, width: float, params: Dictionary = {}, name: String = "Pincel de figuras") -> Line2D:
	var src: Array = OB.from_shapes(shapes, true)
	var l := Line2D.new()
	l.name = name
	l.points = pts
	l.width = width
	l.default_color = Color.WHITE
	l.set_meta("brush_style", "object")
	var prm := {"spacing": 1.2, "rotate": true}
	prm.merge(params, true)
	l.set_meta("brush_obj", {"src": OB.to_data(src), "params": prm})
	api.add(l)
	R.attach(l)
	return l

func arc_points(center: Vector2, r: float, a0: float, a1: float, n: int = 48) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(center + Vector2(cos(a), sin(a)) * r)
	return out

func scribble(a: Vector2, b: Vector2, amp: float, n: int = 80, seed: int = 3) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := PackedVector2Array()
	for i in n:
		var f := float(i) / (n - 1)
		out.append(a.lerp(b, f) + Vector2(0, sin(f * TAU * 2.0) * amp + rng.randf_range(-amp, amp) * 0.08))
	return out

## Texto en trazado con parámetros (align, start_at, end_at, tracking, valign…).
func text_on_path(text: String, size: float, color: Color, path: Node2D, params: Dictionary = {}) -> Line2D:
	var at: Vector2 = path.position
	var tx = api.add_text(at, text, size, color)
	await frames(2)
	var l: Line2D = api.text_on_path(tx, path)
	if l and not params.is_empty():
		var bo: Dictionary = (l.get_meta("brush_obj") as Dictionary).duplicate(true)
		(bo["params"] as Dictionary).merge(params, true)
		l.set_meta("brush_obj", bo)
		l.queue_redraw()
	await frames(3)
	return l

# ── Recuento, exportar, importar, guardar ────────────────────────────────────
func count_shapes(root_node: Node) -> int:
	var n := 0
	for c in root_node.find_children("*", "", true, false):
		if (c is VectorShape or c is Line2D or c is Path2D or c is Sprite2D or c.has_meta("shape_type")) and not String(c.name).begins_with("_") and not (c.get_parent() is Line2D):
			n += 1
	return n

## Exporta `ab` a todos los formatos; devuelve {ext: ruta} de los que salieron.
func export_all(ab: Node2D, base: String) -> Dictionary:
	var out := {}
	for ext in ["svg", "pdf", "eps", "png", "jpg", "webp", "vop"]:
		var p := ProjectSettings.globalize_path(out_dir.path_join("%s.%s" % [base, ext]))
		var t0 := Time.get_ticks_msec()
		var ok: bool = await api.export(p, ab)
		var ms := Time.get_ticks_msec() - t0
		var sz := FileAccess.get_file_as_bytes(p).size() if FileAccess.file_exists(p) else 0
		check("exportar %s (%s)" % [ext.to_upper(), ab.name], ok and sz > 64, "%d bytes · %d ms" % [sz, ms])
		if ok and sz > 64:
			out[ext] = p
	# La exportación a imagen duplica un momento el contenido para dibujarlo
	# aparte y lo libera después: esperar a que termine.
	await frames(30)
	return out

## Vuelve a importar SVG / PDF / EPS en una mesa nueva y cuenta lo que entra.
func import_back(paths: Dictionary, label: String) -> void:
	for ext in ["svg", "pdf", "eps"]:
		if not paths.has(ext) or IEM == null:
			continue
		var ab: Node2D = api.add_artboard(Vector2(1200, 1200), "Import %s %s" % [label, ext])
		await frames(2)
		var before := count_shapes(ab)
		var res: Dictionary = IEM.import_any(paths[ext], ab)
		await frames(10)
		var after := count_shapes(ab)
		check("importar %s exportado (%s)" % [ext.to_upper(), label], bool(res.get("ok", false)) and after > before, "%s · %d figuras" % [str(res.get("error", "")), after - before])

## Guarda en .vtc, quita todo y lo vuelve a abrir. Devuelve las mesas reabiertas.
func save_reload(name: String) -> Array:
	var path := ProjectSettings.globalize_path(out_dir.path_join(name + ".vtc"))
	var n0 := count_shapes(cont)
	var t0 := Time.get_ticks_msec()
	check("guardar %s.vtc" % name, CS.write_vtc(path, cont))
	note("%s_guardar_ms" % name, Time.get_ticks_msec() - t0)
	for p in cont.get_children():
		if p.is_in_group("artboards"):
			cont.remove_child(p)
			p.free()
	t0 = Time.get_ticks_msec()
	CS.rebuild_from_vtc(cont, path)
	await frames(10)
	var abs: Array = []
	for p in cont.get_children():
		if p.is_in_group("artboards"):
			abs.append(p)
			# Las mesas grandes se cargan por tandas (varios fotogramas):
			# terminar la carga antes de contar.
			if p.has_method("wake_now"):
				p.wake_now()
			elif p.get("is_dormant"):
				await p.wake()
	await frames(20)
	note("%s_abrir_ms" % name, Time.get_ticks_msec() - t0)
	var n1 := count_shapes(cont)
	check("reabrir %s sin pérdidas (%d figuras)" % [name, n0], n1 == n0, "%d → %d" % [n0, n1])
	return abs

## Deshacer `n` pasos y rehacerlos: el documento vuelve a estar igual.
func undo_redo(n: int) -> void:
	var c0 := count_shapes(cont)
	var done := 0
	for i in n:
		if not hm.can_undo():
			break
		hm.undo()
		done += 1
		await t.process_frame
	for i in done:
		hm.redo()
		await t.process_frame
	await frames(4)
	check("deshacer y rehacer %d pasos" % done, done >= mini(n, 10) and count_shapes(cont) == c0, "%d pasos · %d → %d" % [done, c0, count_shapes(cont)])

## Tiempo medio de fotograma (ms) redibujando todo lo visible.
func frame_ms(label: String, nframes: int = 30) -> float:
	await frames(3)
	var t0 := Time.get_ticks_usec()
	for i in nframes:
		await RenderingServer.frame_post_draw
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / nframes
	note(label + "_frame_ms", snappedf(ms, 0.1))
	return ms

func memory_mb() -> float:
	return snappedf(OS.get_static_memory_usage() / 1048576.0, 1.0)
