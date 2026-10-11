# =============================================================================
# Lector de VOP (formato vectorial abierto de Vectopen, versión 2) para
# Godot 4.2+. Lee la capa «render» (especificación: VOP_FORMAT.md) y crea
# nodos nativos: Polygon2D (relleno, agujeros, degradados), Line2D (trazo),
# Label (texto) y Sprite2D (imágenes). No necesita Vectopen.
#
# En el editor lo usa el importador. En el juego también se puede usar:
#     var escena := VopReader.load_scene("res://logo.vop")   # Node2D
#     add_child(escena)
# =============================================================================
class_name VopReader
extends RefCounted

const SUPPORTED_MAJOR := 2

## JSON del archivo o null si no es un VOP compatible.
static func read_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or String(data.get("format", "")) != "vop":
		return null
	if int(data.get("version", 0)) != SUPPORTED_MAJOR or not (data.get("render") is Dictionary):
		push_warning("VopReader: versión de VOP no soportada (%s)" % data.get("version", "?"))
		return null
	return data

## Carga un .vop como Node2D listo para añadir a la escena.
static func load_scene(path: String, options: Dictionary = {}) -> Node2D:
	var data = read_file(path)
	if data == null:
		return null
	var o := options.duplicate()
	o["name"] = o.get("name", path.get_file().get_basename())
	return build(data, o)

## options: include_background (true), curve_detail (1.0), antialiased (true), name.
static func build(data: Dictionary, options: Dictionary = {}) -> Node2D:
	var render: Dictionary = data["render"]
	var detail := float(options.get("curve_detail", 1.0))
	var aa := bool(options.get("antialiased", true))
	var root := Node2D.new()
	root.name = String(options.get("name", data.get("name", "VOP"))).validate_node_name()
	var size: Array = data.get("size", [0, 0])
	root.set_meta("vop_size", Vector2(float(size[0]), float(size[1])))
	var bg = render.get("background")
	if bg != null and bool(options.get("include_background", true)):
		var b := Polygon2D.new()
		b.name = "Fondo"
		var s := Vector2(float(size[0]), float(size[1]))
		b.polygon = PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)])
		b.color = _col(bg)
		root.add_child(b)
	var i := 0
	for it in render.get("items", []):
		i += 1
		var n: Node = null
		match String(it.get("type", "")):
			"path": n = _path(it, detail, aa)
			"text": n = _text(it)
			"image": n = _image(it)
		if n:
			n.name = "%s%d" % [String(it.get("type", "item")).capitalize(), i]
			root.add_child(n)
	_own(root, root)
	return root

# ── trazados ─────────────────────────────────────────────────────────────────
static func _path(it: Dictionary, detail: float, aa: bool) -> Node2D:
	var g := Node2D.new()
	g.modulate.a = float(it.get("opacity", 1.0))
	var rings: Array = []
	for sub in it.get("subpaths", []):
		rings.append([_flatten(sub.get("ops", []), detail), bool(sub.get("closed", false))])
	var fill = it.get("fill")
	var grad = it.get("gradient")
	if fill != null or grad != null:
		var closed_rings: Array = []
		for r in rings:
			if (r[0] as PackedVector2Array).size() >= 3:
				closed_rings.append(r[0])
		var polys: Array = _fill_polys(closed_rings, String(it.get("fill_rule", "nonzero")) == "evenodd")
		var bb := _bounds(closed_rings)
		for poly in polys:
			var pg := Polygon2D.new()
			pg.name = "Relleno"
			pg.polygon = poly
			pg.antialiased = aa
			if grad is Dictionary:
				_apply_gradient(pg, grad, bb)
			else:
				pg.color = _col(fill)
			g.add_child(pg, true)
	var stroke = it.get("stroke")
	if stroke != null:
		for r in rings:
			if (r[0] as PackedVector2Array).size() < 2:
				continue
			var ln := Line2D.new()
			ln.name = "Trazo"
			ln.points = r[0]
			ln.closed = r[1]
			ln.width = float(it.get("stroke_width", 1.0))
			ln.default_color = _col(stroke)
			ln.joint_mode = Line2D.LINE_JOINT_ROUND
			var cap: int = {"round": Line2D.LINE_CAP_ROUND, "square": Line2D.LINE_CAP_BOX}.get(String(it.get("cap", "butt")), Line2D.LINE_CAP_NONE)
			ln.begin_cap_mode = cap
			ln.end_cap_mode = cap
			ln.antialiased = aa
			g.add_child(ln, true)
	if g.get_child_count() == 0:
		g.free()
		return null
	return g

## ["M",x,y] ["L",x,y] ["C",c1x,c1y,c2x,c2y,x,y] → polilínea.
static func _flatten(ops: Array, detail: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cur := Vector2.ZERO
	for o in ops:
		match String(o[0]):
			"M", "L":
				cur = Vector2(float(o[1]), float(o[2]))
				out.append(cur)
			"C":
				var p0 := cur
				var c1 := Vector2(float(o[1]), float(o[2]))
				var c2 := Vector2(float(o[3]), float(o[4]))
				var p3 := Vector2(float(o[5]), float(o[6]))
				var n := clampi(int((p0.distance_to(c1) + c1.distance_to(c2) + c2.distance_to(p3)) / 4.0 * detail), 3, 128)
				for k in range(1, n + 1):
					var t := float(k) / n
					var u := 1.0 - t
					out.append(p0 * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + p3 * t * t * t)
				cur = p3
	if out.size() > 2 and out[0].is_equal_approx(out[out.size() - 1]):
		out.remove_at(out.size() - 1)
	return out

## Relleno de varios anillos: par-impar (agujeros) o unión (nonzero).
static func _fill_polys(rings: Array, evenodd: bool) -> Array:
	if rings.size() <= 1:
		return rings
	if not evenodd:
		return rings
	var n := rings.size()
	var depth := PackedInt32Array()
	depth.resize(n)
	for a in n:
		var d := 0
		for b in n:
			if a != b and Geometry2D.is_point_in_polygon((rings[a] as PackedVector2Array)[0], rings[b]):
				d += 1
		depth[a] = d
	var out: Array = []
	for a in n:
		if depth[a] % 2 == 1:
			continue
		var poly: PackedVector2Array = rings[a]
		for b in n:
			if depth[b] == depth[a] + 1 and Geometry2D.is_point_in_polygon((rings[b] as PackedVector2Array)[0], rings[a]):
				poly = _bridge(poly, rings[b])
		if Geometry2D.triangulate_polygon(poly).is_empty():
			out.append_array(Geometry2D.decompose_polygon_in_convex(poly))
		else:
			out.append(poly)
	return out

## Une un agujero al contorno por los vértices más cercanos.
static func _bridge(outer: PackedVector2Array, hole_in: PackedVector2Array) -> PackedVector2Array:
	var hole := hole_in
	if Geometry2D.is_polygon_clockwise(hole) == Geometry2D.is_polygon_clockwise(outer):
		hole = hole_in.duplicate()
		hole.reverse()
	var bi := 0
	var bj := 0
	var bd := INF
	for a in outer.size():
		for b in range(0, hole.size(), maxi(1, hole.size() / 64)):
			var dd := outer[a].distance_squared_to(hole[b])
			if dd < bd:
				bd = dd
				bi = a
				bj = b
	var res := PackedVector2Array()
	for a in range(bi + 1):
		res.append(outer[a])
	for k in range(hole.size() + 1):
		res.append(hole[(bj + k) % hole.size()])
	for a in range(bi, outer.size()):
		res.append(outer[a])
	return res

static func _bounds(rings: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for ring in rings:
		for p in ring:
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r

## Degradado lineal/radial en coordenadas de la caja («units: bbox»).
static func _apply_gradient(pg: Polygon2D, g: Dictionary, bb: Rect2) -> void:
	var grad := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for st in g.get("stops", []):
		offs.append(float(st[0]))
		cols.append(_col(st[1]))
	if offs.size() >= 2:
		grad.offsets = offs
		grad.colors = cols
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	if String(g.get("kind", "linear")) == "radial":
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
	else:
		var a := float(g.get("angle", 0.0))
		var d := Vector2(cos(a), sin(a)) * 0.5
		tex.fill_from = Vector2(0.5, 0.5) - d
		tex.fill_to = Vector2(0.5, 0.5) + d
	pg.texture = tex
	pg.color = Color.WHITE
	var uv := PackedVector2Array()
	var sz := bb.size.max(Vector2(0.001, 0.001))
	for p in pg.polygon:
		uv.append((p - bb.position) / sz * 256.0)
	pg.uv = uv

# ── texto e imágenes ─────────────────────────────────────────────────────────
static func _xf(a: Array) -> Transform2D:
	return Transform2D(Vector2(float(a[0]), float(a[1])), Vector2(float(a[2]), float(a[3])), Vector2(float(a[4]), float(a[5])))

static func _text(it: Dictionary) -> Node2D:
	var holder := Node2D.new()
	holder.transform = _xf(it.get("transform", [1, 0, 0, 1, 0, 0]))
	holder.modulate.a = float(it.get("opacity", 1.0))
	var size := float(it.get("size", 16.0))
	var l := Label.new()
	l.text = String(it.get("text", ""))
	l.add_theme_font_size_override("font_size", int(round(size)))
	l.add_theme_color_override("font_color", _col(it.get("color", "#000000ff")))
	l.add_theme_constant_override("line_spacing", int(size * (float(it.get("line_height", 1.2)) - 1.2)))
	var family := String(it.get("family", ""))
	if family != "" and family != "sans-serif":
		var f := SystemFont.new()
		f.font_names = PackedStringArray([family, "sans-serif"])
		f.font_weight = 700 if bool(it.get("bold", false)) else 400
		f.font_italic = bool(it.get("italic", false))
		l.add_theme_font_override("font", f)
	holder.add_child(l)
	return holder

static func _image(it: Dictionary) -> Node2D:
	var img := Image.new()
	if img.load_png_from_buffer(Marshalls.base64_to_raw(String(it.get("png_base64", "")))) != OK:
		return null
	var sp := Sprite2D.new()
	sp.centered = false
	sp.texture = ImageTexture.create_from_image(img)
	var xf := _xf(it.get("transform", [1, 0, 0, 1, 0, 0]))
	# la imagen ocupa width×height antes de la transformación
	var w := float(it.get("width", img.get_width()))
	var h := float(it.get("height", img.get_height()))
	sp.transform = xf * Transform2D(0.0, Vector2(w / img.get_width(), h / img.get_height()), 0.0, Vector2.ZERO)
	sp.modulate.a = float(it.get("opacity", 1.0))
	return sp

static func _col(v: Variant) -> Color:
	if v == null:
		return Color(0, 0, 0, 0)
	var s := String(v).trim_prefix("#")
	return Color.html(s) if Color.html_is_valid(s) else Color.BLACK

static func _own(root: Node, n: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(root, c)
