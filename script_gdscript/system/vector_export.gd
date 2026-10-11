# =============================================================================
# RUTA: res://script_gdscript/system/vector_export.gd
# EXPORTACIÓN VECTORIAL (SVG, PDF, EPS) desde UNA sola geometría.
#
# collect() recorre el artboard (también dentro de los grupos) y convierte
# cada objeto en primitivas en coordenadas del artboard, con su
# transformación completa (posición, rotación, escala de grupos):
#   · path  — contornos M/L/C/Z (Bézier reales para trazados, elipses y
#             esquinas redondeadas), relleno, degradado, trazo, opacidad.
#   · text  — texto (líneas, tamaño, color, familia).
#   · image — imágenes (Sprite2D) con su transformación.
# Después to_svg / to_pdf / to_eps escriben el formato.
#
# Lo que solo existe al rasterizar (shaders del usuario, filtros, efectos
# salvo la sombra en SVG) no se puede expresar en vectorial: collect()
# lo apunta en `warnings` para que el panel avise y sugiera PNG.
# =============================================================================
extends RefCounted

const K := 0.5522847498   # Bézier de un cuarto de círculo
const SKIP := ["ArtboardTitle", "TitleEdit", "Contorno_Stroke", "Render_Visual", "DisplayLabel", "VectorRichText"]

# ── recogida ─────────────────────────────────────────────────────────────────
## {size, bg (Color o null), items: [...], warnings: PackedStringArray}
## `only`: exportar solo esos objetos (selección); vacío = todo el artboard.
static func collect(ab: Node2D, transparent: bool = false, only: Array = []) -> Dictionary:
	var size: Vector2 = ab.artboard_size if "artboard_size" in ab else Vector2(800, 600)
	var bg: Variant = null
	if not transparent:
		var fc: Color = ab.get("fill_color") if "fill_color" in ab else Color.WHITE
		if fc.a > 0.0:
			bg = fc
	var out := {"size": size, "bg": bg, "items": [], "warnings": PackedStringArray()}
	var inv := ab.get_global_transform().affine_inverse()
	for ch in (only if not only.is_empty() else ab.get_children()):
		if is_instance_valid(ch):
			_walk(ch, inv, _inherited_opacity(ch, ab), out)
	return out

static func _inherited_opacity(n: Node, ab: Node) -> float:
	var op := 1.0
	var p := n.get_parent()
	while p and p != ab:
		if p is CanvasItem:
			op *= (p as CanvasItem).modulate.a
		p = p.get_parent()
	return op

static func _walk(n: Node, inv: Transform2D, opacity: float, out: Dictionary) -> void:
	if not (n is CanvasItem) or String(n.name) in SKIP or n is SubViewport:
		return
	var ci := n as CanvasItem
	if not ci.visible:
		return
	var op := opacity * ci.modulate.a * ci.self_modulate.a
	if op <= 0.001:
		return
	if not (n is Node2D):
		return
	var xf: Transform2D = inv * (n as Node2D).get_global_transform()
	_note_raster_only(n, out)
	if n is VectorShape:
		_shape(n, xf, op, out)
	elif n is Path2D:
		_path2d(n, xf, op, out)
	elif n is Sprite2D:
		_sprite(n, xf, op, out)
	elif n is Line2D:
		var l := n as Line2D
		if l.points.size() >= 2:
			out["items"].append(_item(_lines(xf, [l.points], false), null, l.default_color, l.width * _scale_of(xf), op, 1, false))
	elif n is Polygon2D:
		var pg := n as Polygon2D
		if pg.polygon.size() >= 3:
			out["items"].append(_item(_lines(xf, [pg.polygon], true), pg.color, null, 0.0, op, 0, false))
	elif n.has_meta("shape_type") and String(n.get_meta("shape_type")).begins_with("text"):
		_text(n, xf, op, out)
	else:
		for ch in n.get_children():   # grupo
			_walk(ch, inv, op, out)

static func _note_raster_only(n: Node, out: Dictionary) -> void:
	var w: PackedStringArray = out["warnings"]
	if n.has_meta("custom_shader") and n.get_meta("custom_shader") is Dictionary and not (n.get_meta("custom_shader") as Dictionary).is_empty():
		_warn(w, "shaders")
	if n.has_meta("filters") and n.get_meta("filters") is Array and not (n.get_meta("filters") as Array).is_empty():
		_warn(w, "filtros")
	if "effects" in n and n.get("effects") is Array:
		for fx in n.get("effects"):
			if fx is Dictionary and bool(fx.get("enabled", true)) and String(fx.get("type", "")) != "Drop Shadow":
				_warn(w, "efectos")

static func _warn(w: PackedStringArray, what: String) -> void:
	if not (what in w):
		w.append(what)

static func _scale_of(xf: Transform2D) -> float:
	return sqrt(absf(xf.determinant()))

## Primitiva de contorno. `subs`: [{ops: [...], closed}]
static func _item(subs: Array, fill: Variant, stroke: Variant, width: float, op: float, cap: int, evenodd: bool) -> Dictionary:
	return {"t": "path", "subs": subs, "fill": fill, "stroke": stroke, "width": width,
		"opacity": op, "cap": cap, "evenodd": evenodd, "grad": null, "shadow": null}

static func _shape(s: VectorShape, xf: Transform2D, op: float, out: Dictionary) -> void:
	var subs: Array = []
	if s is VectorRectangle:
		subs = [_rect(xf, s.size, s.get_shape_corner_radii())]
	elif s is VectorCircle and String(s.shape_mode) == "whole":
		subs = [_ellipse(xf, s.size / 2.0)]
	else:
		var polys: Array = s.get_evaluated_geometry()
		subs = _lines(xf, polys, true)
	if subs.is_empty():
		return
	var fill: Variant = s.fill_color if s.fill_color.a > 0.0 else null
	var stroke: Variant = s.stroke_color if (s.stroke_width > 0.0 and s.stroke_color.a > 0.0) else null
	var it := _item(subs, fill, stroke, s.stroke_width * _scale_of(xf), op, 0, false)
	if s.has_gradient_fill():
		var g: Gradient = s.fill_gradient
		var stops: Array = []
		for i in g.get_point_count():
			stops.append([g.get_offset(i), g.get_color(i)])
		it["grad"] = {"type": s.fill_gradient_type, "angle": s.fill_gradient_angle, "stops": stops}
		it["fill"] = g.get_color(0)
	for fx in s.effects:
		if fx is Dictionary and bool(fx.get("enabled", true)) and String(fx.get("type", "")) == "Drop Shadow":
			it["shadow"] = fx
	out["items"].append(it)

static func _path2d(p: Path2D, xf: Transform2D, op: float, out: Dictionary) -> void:
	if p.curve == null or p.curve.point_count < 2:
		return
	var closed: bool = bool(p.get("closed")) if "closed" in p else false
	var subs: Array = [_curve(xf, p.curve, closed)]
	var evenodd := false
	if "subpaths" in p:
		for c in p.get("subpaths"):
			if c is Curve2D and c.point_count >= 2:
				subs.append(_curve(xf, c, true))
				evenodd = true
	var fc: Color = p.get("fill_color") if "fill_color" in p else Color(0, 0, 0, 0)
	var sc: Color = p.get("stroke_color") if "stroke_color" in p else Color.BLACK
	var sw: float = float(p.get("stroke_width")) if "stroke_width" in p else 2.0
	var cap: int = int(p.get("stroke_cap_end")) if "stroke_cap_end" in p else 0
	var fill: Variant = fc if (closed and fc.a > 0.0) else null
	var stroke: Variant = sc if (sw > 0.0 and sc.a > 0.0) else null
	out["items"].append(_item(subs, fill, stroke, sw * _scale_of(xf), op, cap, evenodd))

static func _sprite(sp: Sprite2D, xf: Transform2D, op: float, out: Dictionary) -> void:
	if sp.texture == null:
		return
	var img := sp.texture.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var size := Vector2(img.get_size())
	var origin := sp.offset - (size / 2.0 if sp.centered else Vector2.ZERO)
	out["items"].append({"t": "image", "xf": xf * Transform2D(0.0, origin), "size": size, "image": img, "opacity": op})

static func _text(n: Node, xf: Transform2D, op: float, out: Dictionary) -> void:
	var txt := String(n.get_meta("text", ""))
	var dl := n.get_node_or_null("DisplayLabel") as Label
	if txt == "" and dl:
		txt = dl.text
	if txt.strip_edges() == "":
		return
	var col: Color = n.get_meta("text_color") if n.has_meta("text_color") else Color.BLACK
	# la fuente REAL del texto (FontCore la resuelve en la etiqueta): para
	# convertir el texto a curvas con su forma exacta
	var font: Font = dl.get_theme_font(&"font") if dl else null
	out["items"].append({"t": "text", "xf": xf, "text": txt, "size": float(n.get_meta("font_size", 24)), "font": font,
		"color": col, "family": String(n.get_meta("font_family", "sans-serif")),
		"bold": int(n.get_meta("font_weight", 400)) >= 600, "italic": bool(n.get_meta("font_italic", false)),
		"line_height": 1.2 + float(n.get_meta("line_spacing", 0)) / 100.0, "opacity": op})

# ── geometría → ops (en coordenadas del artboard) ────────────────────────────
static func _lines(xf: Transform2D, polys: Array, closed: bool) -> Array:
	var subs: Array = []
	for poly in polys:
		if poly.size() < 2:
			continue
		var ops: Array = [["M", xf * poly[0]]]
		for i in range(1, poly.size()):
			ops.append(["L", xf * poly[i]])
		subs.append({"ops": ops, "closed": closed})
	return subs

static func _curve(xf: Transform2D, c: Curve2D, closed: bool) -> Dictionary:
	var n := c.point_count
	var ops: Array = [["M", xf * c.get_point_position(0)]]
	var segs := n if closed else n - 1
	for k in segs:
		var i := k
		var j := (k + 1) % n
		var a := c.get_point_position(i)
		var b := c.get_point_position(j)
		var c1 := a + c.get_point_out(i)
		var c2 := b + c.get_point_in(j)
		if c.get_point_out(i).is_zero_approx() and c.get_point_in(j).is_zero_approx():
			ops.append(["L", xf * b])
		else:
			ops.append(["C", xf * c1, xf * c2, xf * b])
	return {"ops": ops, "closed": closed}

static func _ellipse(xf: Transform2D, r: Vector2) -> Dictionary:
	var kx := r.x * K
	var ky := r.y * K
	var ops: Array = [["M", xf * Vector2(r.x, 0)],
		["C", xf * Vector2(r.x, ky), xf * Vector2(kx, r.y), xf * Vector2(0, r.y)],
		["C", xf * Vector2(-kx, r.y), xf * Vector2(-r.x, ky), xf * Vector2(-r.x, 0)],
		["C", xf * Vector2(-r.x, -ky), xf * Vector2(-kx, -r.y), xf * Vector2(0, -r.y)],
		["C", xf * Vector2(kx, -r.y), xf * Vector2(r.x, -ky), xf * Vector2(r.x, 0)]]
	return {"ops": ops, "closed": true}

## Rectángulo centrado con radios (tl, tr, br, bl) — arcos Bézier.
static func _rect(xf: Transform2D, size: Vector2, radii: Vector4) -> Dictionary:
	var h := size / 2.0
	var lim := minf(h.x, h.y)
	var tl := clampf(radii.x, 0.0, lim)
	var tr := clampf(radii.y, 0.0, lim)
	var br := clampf(radii.z, 0.0, lim)
	var bl := clampf(radii.w, 0.0, lim)
	var ops: Array = [["M", xf * Vector2(-h.x + tl, -h.y)], ["L", xf * Vector2(h.x - tr, -h.y)]]
	if tr > 0.0:
		ops.append(["C", xf * Vector2(h.x - tr + tr * K, -h.y), xf * Vector2(h.x, -h.y + tr - tr * K), xf * Vector2(h.x, -h.y + tr)])
	ops.append(["L", xf * Vector2(h.x, h.y - br)])
	if br > 0.0:
		ops.append(["C", xf * Vector2(h.x, h.y - br + br * K), xf * Vector2(h.x - br + br * K, h.y), xf * Vector2(h.x - br, h.y)])
	ops.append(["L", xf * Vector2(-h.x + bl, h.y)])
	if bl > 0.0:
		ops.append(["C", xf * Vector2(-h.x + bl - bl * K, h.y), xf * Vector2(-h.x, h.y - bl + bl * K), xf * Vector2(-h.x, h.y - bl)])
	ops.append(["L", xf * Vector2(-h.x, -h.y + tl)])
	if tl > 0.0:
		ops.append(["C", xf * Vector2(-h.x, -h.y + tl - tl * K), xf * Vector2(-h.x + tl - tl * K, -h.y), xf * Vector2(-h.x + tl, -h.y)])
	return {"ops": ops, "closed": true}

## Rectángulo que ocupa lo recogido (contornos + medio trazo, textos aprox.,
## imágenes). Rect2() si no hay nada.
static func bounds(data: Dictionary) -> Rect2:
	var r := Rect2()
	var any := false
	for it in data["items"]:
		var pts := PackedVector2Array()
		var grow := 0.0
		match it["t"]:
			"path":
				for sub in it["subs"]:
					for o in sub["ops"]:
						for k in range(1, o.size()):
							pts.append(o[k])
				grow = float(it["width"]) / 2.0 if it["stroke"] != null else 0.0
			"text":
				var lines: PackedStringArray = String(it["text"]).split("\n")
				var w := 0
				for l in lines:
					w = maxi(w, l.length())
				var box := Vector2(w * float(it["size"]) * 0.6, lines.size() * float(it["size"]) * float(it["line_height"]))
				var xf: Transform2D = it["xf"]
				pts.append_array([xf * Vector2.ZERO, xf * Vector2(box.x, 0), xf * box, xf * Vector2(0, box.y)])
			"image":
				var xf2: Transform2D = it["xf"]
				var sz: Vector2 = it["size"]
				pts.append_array([xf2 * Vector2.ZERO, xf2 * Vector2(sz.x, 0), xf2 * sz, xf2 * Vector2(0, sz.y)])
		for p in pts:
			if not any:
				r = Rect2(p, Vector2.ZERO)
				any = true
			else:
				r = r.expand(p)
		if any and grow > 0.0:
			r = r.grow(grow)
	return r

## Mueve todo `delta` y fija el tamaño del lienzo (exportar un elemento
## recortado a su caja).
static func offset(data: Dictionary, delta: Vector2, size: Vector2) -> Dictionary:
	var d := data.duplicate(true)
	d["size"] = size
	var t := Transform2D(0.0, delta)
	for it in d["items"]:
		match it["t"]:
			"path":
				for sub in it["subs"]:
					for o in sub["ops"]:
						for k in range(1, o.size()):
							o[k] = o[k] + delta
			"text", "image":
				it["xf"] = t * it["xf"]
	return d

# ═════════════════════════ Texto → curvas (contornos) ═══════════════════════
## Cambia cada texto por sus CONTORNOS con la fuente real (modelado con
## TextServer: kerning y ligaduras como en pantalla). Así PDF/EPS/SVG se ven
## con tu fuente en cualquier programa, sin incrustarla. El texto deja de ser
## editable como texto en el archivo exportado (como «Convertir a curvas»).
static func texts_to_curves(data: Dictionary) -> Dictionary:
	var d := data.duplicate()
	var items: Array = []
	for it in data["items"]:
		if it["t"] == "text" and it.get("font") is Font:
			var subs := text_outline_subs(it)
			if not subs.is_empty():
				var p := _item(subs, it["color"], null, 0.0, float(it["opacity"]), 0, false)
				p["nonzero_glyphs"] = true
				items.append(p)
				continue
		items.append(it)
	d["items"] = items
	return d

## Contornos del texto `it` en coordenadas del artboard.
static func text_outline_subs(it: Dictionary) -> Array:
	var font: Font = it["font"]
	var size := int(round(float(it["size"])))
	var xf: Transform2D = it["xf"]
	var ts := TextServerManager.get_primary_interface()
	var lh := float(it["size"]) * float(it["line_height"])
	var asc := font.get_ascent(size)
	var subs: Array = []
	var lines: PackedStringArray = String(it["text"]).split("\n")
	for li in lines.size():
		var sid := ts.create_shaped_text()
		ts.shaped_text_add_string(sid, lines[li], font.get_rids(), size)
		var pen := Vector2(0.0, asc + li * lh)
		for g in ts.shaped_text_get_glyphs(sid):
			var off: Vector2 = g.get("offset", Vector2.ZERO)
			var rid: RID = g.get("font_rid", RID())
			var idx := int(g.get("index", 0))
			if rid.is_valid() and idx > 0:
				_glyph_subs(ts, rid, int(g.get("font_size", size)), idx, pen + off, xf, subs)
			pen.x += float(g.get("advance", 0.0)) * int(g.get("repeat", 1))
		ts.free_rid(sid)
	return subs

## Contornos de un glifo TrueType/CFF: puntos (x, y, etiqueta) donde la
## etiqueta 1 = sobre la curva, 0 = control cuadrático, 2 = control cúbico.
static func _glyph_subs(ts: TextServer, rid: RID, fs: int, glyph: int, origin: Vector2, xf: Transform2D, out: Array) -> void:
	var data: Dictionary = ts.font_get_glyph_contours(rid, fs, glyph)
	var pts: PackedVector3Array = data.get("points", PackedVector3Array())
	var ends: PackedInt32Array = data.get("contours", PackedInt32Array())
	var start := 0
	for e in ends:
		var arc := pts.slice(start, int(e) + 1)
		start = int(e) + 1
		var ops := _contour_ops(arc, origin, xf)
		if ops.size() >= 2:
			out.append({"ops": ops, "closed": true})

static func _contour_ops(arc: PackedVector3Array, o: Vector2, xf: Transform2D) -> Array:
	var n := arc.size()
	if n < 2:
		return []
	# puntos con etiqueta; se insertan los "sobre la curva" implícitos entre
	# dos controles cuadráticos seguidos
	var P: Array = []
	for j in n:
		var a := arc[j]
		var b := arc[(j + 1) % n]
		var ta := int(a.z) & 3
		var tb := int(b.z) & 3
		P.append([Vector2(a.x, a.y), ta])
		if ta == 0 and tb == 0:
			P.append([(Vector2(a.x, a.y) + Vector2(b.x, b.y)) * 0.5, 1])
	var first := -1
	for j in P.size():
		if P[j][1] == 1:
			first = j
			break
	if first < 0:
		return []
	var m := P.size()
	var ops: Array = [["M", xf * (P[first][0] + o)]]
	var cur: Vector2 = P[first][0]
	var k := 1
	while k <= m:
		var q: Array = P[(first + k) % m]
		if q[1] == 1:
			ops.append(["L", xf * (q[0] + o)])
			cur = q[0]
			k += 1
		elif q[1] == 0:
			var e: Vector2 = P[(first + k + 1) % m][0]
			var c: Vector2 = q[0]
			ops.append(["C", xf * (cur + (c - cur) * 2.0 / 3.0 + o), xf * (e + (c - e) * 2.0 / 3.0 + o), xf * (e + o)])
			cur = e
			k += 2
		else:
			var c1: Vector2 = q[0]
			var c2: Vector2 = P[(first + k + 1) % m][0]
			var e2: Vector2 = P[(first + k + 2) % m][0]
			ops.append(["C", xf * (c1 + o), xf * (c2 + o), xf * (e2 + o)])
			cur = e2
			k += 3
	return ops

# ══════════════════ Escena de Godot PORTABLE (sin scripts) ═══════════════════
## Convierte lo recogido en nodos NATIVOS de Godot: Polygon2D (relleno, con
## agujeros resueltos), Line2D (trazo), Label (texto), Sprite2D (imagen
## incluida). Se abre y se ve en CUALQUIER proyecto de Godot, sin Vectopen.
static func to_godot_scene(data: Dictionary, root_name: String) -> Node2D:
	var root := Node2D.new()
	root.name = root_name.validate_node_name() if root_name != "" else "Vectopen"
	if data["bg"] != null:
		var bg := Polygon2D.new()
		bg.name = "Fondo"
		var sz: Vector2 = data["size"]
		bg.polygon = PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)])
		bg.color = data["bg"]
		root.add_child(bg)
	var idx := 0
	for it in data["items"]:
		idx += 1
		match it["t"]:
			"path":
				var g := Node2D.new()
				g.name = "Forma%d" % idx
				if float(it["opacity"]) < 0.999:
					g.modulate.a = float(it["opacity"])
				var rings: Array = []
				for sub in it["subs"]:
					rings.append([_flatten(sub["ops"]), sub["closed"]])
				if it["fill"] != null:
					var closed_rings: Array = []
					for r in rings:
						if (r[0] as PackedVector2Array).size() >= 3:
							closed_rings.append(r[0])
					var polys: Array = StrokeGeom.evenodd_fill(closed_rings) if closed_rings.size() > 1 else closed_rings
					for poly in polys:
						var pg := Polygon2D.new()
						pg.name = "Relleno"
						pg.polygon = poly
						pg.color = it["fill"]
						pg.antialiased = true
						g.add_child(pg, true)
				if it["stroke"] != null:
					for r in rings:
						var ln := Line2D.new()
						ln.name = "Trazo"
						ln.points = r[0]
						ln.closed = r[1]
						ln.width = float(it["width"])
						ln.default_color = it["stroke"]
						ln.joint_mode = Line2D.LINE_JOINT_ROUND
						var cap: int = [Line2D.LINE_CAP_NONE, Line2D.LINE_CAP_ROUND, Line2D.LINE_CAP_BOX][clampi(int(it["cap"]), 0, 2)]
						ln.begin_cap_mode = cap
						ln.end_cap_mode = cap
						ln.antialiased = true
						g.add_child(ln, true)
				if g.get_child_count() > 0:
					root.add_child(g)
				else:
					g.free()
			"text":
				var holder := Node2D.new()
				holder.name = "Texto%d" % idx
				holder.transform = it["xf"]
				holder.modulate.a = float(it["opacity"])
				var l := Label.new()
				l.text = it["text"]
				l.add_theme_font_size_override("font_size", int(round(float(it["size"]))))
				l.add_theme_color_override("font_color", it["color"])
				l.add_theme_constant_override("line_spacing", int(float(it["size"]) * (float(it["line_height"]) - 1.2)))
				holder.add_child(l)
				root.add_child(holder)
			"image":
				var sp := Sprite2D.new()
				sp.name = "Imagen%d" % idx
				sp.centered = false
				sp.texture = ImageTexture.create_from_image(it["image"])
				sp.transform = it["xf"]
				sp.modulate.a = float(it["opacity"])
				root.add_child(sp)
	_own(root, root)
	return root

static func _own(root: Node, n: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(root, c)

## Contorno M/L/C → polilínea (Bézier subdivididas según su tamaño).
static func _flatten(ops: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cur := Vector2.ZERO
	for o in ops:
		match o[0]:
			"M", "L":
				cur = o[1]
				out.append(cur)
			"C":
				var p0 := cur
				var c1: Vector2 = o[1]
				var c2: Vector2 = o[2]
				var p3: Vector2 = o[3]
				var n := clampi(int((p0.distance_to(c1) + c1.distance_to(c2) + c2.distance_to(p3)) / 4.0), 4, 64)
				for i in range(1, n + 1):
					var t := float(i) / n
					var u := 1.0 - t
					out.append(p0 * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + p3 * t * t * t)
				cur = p3
	if out.size() > 2 and out[0].is_equal_approx(out[out.size() - 1]):
		out.remove_at(out.size() - 1)
	return out

const StrokeGeom = preload("res://script_gdscript/shapes/stroke_geom.gd")

# ═══════════════════════════ VOP: capa "render" ═════════════════════════════
## Primitivas en JSON neutro (para lectores de VOP que no conocen las figuras
## de Vectopen: addons de Blender/Godot, web…). Ver docs: VOP_FORMAT.
static func to_render_json(data: Dictionary) -> Dictionary:
	var items: Array = []
	for it in data["items"]:
		match it["t"]:
			"path":
				var subs: Array = []
				for sub in it["subs"]:
					var ops: Array = []
					for o in sub["ops"]:
						var e: Array = [o[0]]
						for k in range(1, o.size()):
							e.append_array([_r(o[k].x), _r(o[k].y)])
						ops.append(e)
					subs.append({"ops": ops, "closed": sub["closed"]})
				var d := {"type": "path", "subpaths": subs, "fill": _jc(it["fill"]), "stroke": _jc(it["stroke"]),
					"stroke_width": _r(it["width"]), "cap": ["butt", "round", "square"][clampi(int(it["cap"]), 0, 2)],
					"fill_rule": "evenodd" if it["evenodd"] else "nonzero", "opacity": _r(it["opacity"])}
				if it["grad"] != null:
					var stops: Array = []
					for st in it["grad"]["stops"]:
						stops.append([_r(st[0]), _jc(st[1])])
					d["gradient"] = {"kind": "linear" if int(it["grad"]["type"]) == 0 else "radial",
						"angle": _r(float(it["grad"]["angle"])), "stops": stops, "units": "bbox"}
				items.append(d)
			"text":
				items.append({"type": "text", "transform": _jx(it["xf"]), "text": it["text"], "size": _r(it["size"]),
					"color": _jc(it["color"]), "family": it["family"], "bold": it["bold"], "italic": it["italic"],
					"line_height": _r(it["line_height"]), "opacity": _r(it["opacity"])})
			"image":
				items.append({"type": "image", "transform": _jx(it["xf"]), "width": _r(it["size"].x), "height": _r(it["size"].y),
					"png_base64": Marshalls.raw_to_base64((it["image"] as Image).save_png_to_buffer()), "opacity": _r(it["opacity"])})
	return {"units": "px", "origin": "top-left", "y_down": true,
		"background": _jc(data["bg"]), "items": items}

static func _r(v: float) -> float:
	return snappedf(v, 0.001)

static func _jc(c: Variant) -> Variant:
	return null if c == null else "#" + (c as Color).to_html(true)

static func _jx(xf: Transform2D) -> Array:
	return [_r(xf.x.x), _r(xf.x.y), _r(xf.y.x), _r(xf.y.y), _r(xf.origin.x), _r(xf.origin.y)]

# ═══════════════════════════════════ SVG ═════════════════════════════════════
static func to_svg(data: Dictionary) -> String:
	var size: Vector2 = data["size"]
	var defs := PackedStringArray()
	var body := PackedStringArray()
	if data["bg"] != null:
		body.append('<rect width="%s" height="%s"%s data-vectopen="background"/>' % [_n(size.x), _n(size.y), _paint("fill", data["bg"])])
	var gid := 0
	for it in data["items"]:
		match it["t"]:
			"path":
				var extra := ""
				if it["grad"] != null:
					gid += 1
					defs.append(_svg_gradient("g%d" % gid, it["grad"]))
					extra += ' fill="url(#g%d)"' % gid
				else:
					extra += _paint("fill", it["fill"])
				if it["stroke"] != null:
					extra += _paint("stroke", it["stroke"]) + ' stroke-width="%s" stroke-linejoin="round"' % _n(it["width"])
					extra += [' stroke-linecap="butt"', ' stroke-linecap="round"', ' stroke-linecap="square"'][clampi(int(it["cap"]), 0, 2)]
				if it["evenodd"]:
					extra += ' fill-rule="evenodd"'
				if it["opacity"] < 0.999:
					extra += ' opacity="%s"' % _n(it["opacity"])
				if it["shadow"] != null:
					gid += 1
					defs.append(_svg_shadow("s%d" % gid, it["shadow"]))
					extra += ' filter="url(#s%d)"' % gid
				body.append('<path d="%s"%s/>' % [_svg_d(it["subs"]), extra])
			"text":
				body.append(_svg_text(it))
			"image":
				var xf: Transform2D = it["xf"]
				var b64 := Marshalls.raw_to_base64((it["image"] as Image).save_png_to_buffer())
				body.append('<image width="%s" height="%s" transform="%s"%s href="data:image/png;base64,%s"/>' % [
					_n(it["size"].x), _n(it["size"].y), _matrix(xf),
					(' opacity="%s"' % _n(it["opacity"])) if it["opacity"] < 0.999 else "", b64])
	var out := '<?xml version="1.0" encoding="UTF-8"?>\n'
	out += '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s">\n' % [_n(size.x), _n(size.y), _n(size.x), _n(size.y)]
	if not defs.is_empty():
		out += "<defs>\n" + "\n".join(defs) + "\n</defs>\n"
	out += "\n".join(body) + "\n</svg>\n"
	return out

static func _n(v: float) -> String:
	var s := "%.3f" % v
	s = s.rstrip("0").rstrip(".")
	return "0" if s == "-0" or s == "" else s

static func _p(v: Vector2) -> String:
	return _n(v.x) + " " + _n(v.y)

static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)

static func _paint(attr: String, c: Variant) -> String:
	if c == null:
		return ' %s="none"' % attr
	var col: Color = c
	var s := ' %s="%s"' % [attr, _hex(col)]
	if col.a < 0.999:
		s += ' %s-opacity="%s"' % [attr, _n(col.a)]
	return s

static func _matrix(xf: Transform2D) -> String:
	return "matrix(%s %s %s %s %s %s)" % [_n(xf.x.x), _n(xf.x.y), _n(xf.y.x), _n(xf.y.y), _n(xf.origin.x), _n(xf.origin.y)]

static func _svg_d(subs: Array) -> String:
	var parts := PackedStringArray()
	for sub in subs:
		for o in sub["ops"]:
			match o[0]:
				"M": parts.append("M" + _p(o[1]))
				"L": parts.append("L" + _p(o[1]))
				"C": parts.append("C" + _p(o[1]) + " " + _p(o[2]) + " " + _p(o[3]))
		if sub["closed"]:
			parts.append("Z")
	return " ".join(parts)

static func _svg_gradient(id: String, g: Dictionary) -> String:
	var stops := ""
	for st in g["stops"]:
		var c: Color = st[1]
		stops += '<stop offset="%s" stop-color="%s"%s/>' % [_n(st[0]), _hex(c), (' stop-opacity="%s"' % _n(c.a)) if c.a < 0.999 else ""]
	if int(g["type"]) == 0:
		var d := Vector2(cos(float(g["angle"])), sin(float(g["angle"]))) * 0.5
		return '<linearGradient id="%s" x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>' % [
			id, _n(0.5 - d.x), _n(0.5 - d.y), _n(0.5 + d.x), _n(0.5 + d.y), stops]
	return '<radialGradient id="%s" cx="0.5" cy="0.5" r="0.5">%s</radialGradient>' % [id, stops]

static func _svg_shadow(id: String, fx: Dictionary) -> String:
	var c: Variant = fx.get("color", Color(0, 0, 0, 0.4))
	var col: Color = c if c is Color else Color(0, 0, 0, 0.4)
	return '<filter id="%s" x="-50%%" y="-50%%" width="200%%" height="200%%"><feDropShadow dx="%s" dy="%s" stdDeviation="%s" flood-color="%s" flood-opacity="%s"/></filter>' % [
		id, _n(float(fx.get("offset_x", 4.0))), _n(float(fx.get("offset_y", 4.0))), _n(float(fx.get("blur", 6.0)) / 2.0), _hex(col), _n(col.a)]

static func _svg_text(it: Dictionary) -> String:
	var size: float = it["size"]
	var lh: float = size * float(it["line_height"])
	var spans := ""
	var lines: PackedStringArray = String(it["text"]).split("\n")
	for i in lines.size():
		spans += '<tspan x="0" y="%s">%s</tspan>' % [_n(size * 0.8 + i * lh), lines[i].xml_escape()]
	return '<text transform="%s" font-family="%s" font-size="%s"%s%s%s%s>%s</text>' % [
		_matrix(it["xf"]), String(it["family"]).xml_escape(), _n(size),
		' font-weight="bold"' if it["bold"] else "", ' font-style="italic"' if it["italic"] else "",
		_paint("fill", it["color"]), (' opacity="%s"' % _n(it["opacity"])) if it["opacity"] < 0.999 else "", spans]

# ═══════════════════════════════════ PDF ═════════════════════════════════════
## PDF 1.4 de una página del tamaño del artboard (1 px = 1 pt).
static func to_pdf(data_in: Dictionary) -> PackedByteArray:
	# Tu fuente no está entre las 14 de un lector PDF: el texto va como curvas.
	var data := texts_to_curves(data_in)
	var size: Vector2 = data["size"]
	var content := PackedStringArray(["1 0 0 -1 0 %s cm" % _n(size.y)])
	var gstates := {}      # "ca|CA" -> nombre
	var images: Array = []  # [Image, opacity]
	if data["bg"] != null:
		content.append(_pdf_col(data["bg"], false) + " 0 0 %s %s re f" % [_n(size.x), _n(size.y)])
	for it in data["items"]:
		match it["t"]:
			"path":
				var fill: Variant = it["fill"]
				var stroke: Variant = it["stroke"]
				var ca: float = (fill.a if fill != null else 1.0) * float(it["opacity"])
				var CA: float = (stroke.a if stroke != null else 1.0) * float(it["opacity"])
				var s := "q "
				if ca < 0.999 or CA < 0.999:
					s += "/%s gs " % _gs(gstates, ca, CA)
				if fill != null:
					s += _pdf_col(fill, false) + " "
				if stroke != null:
					s += _pdf_col(stroke, true) + " %s w %d J 1 j " % [_n(it["width"]), clampi(int(it["cap"]), 0, 2)]
				s += _pdf_path(it["subs"], false)
				var star := "*" if it["evenodd"] else ""
				s += (" B" + star) if (fill != null and stroke != null) else ((" f" + star) if fill != null else (" S" if stroke != null else " n"))
				content.append(s + " Q")
			"text":
				var xf: Transform2D = it["xf"]
				var size_t: float = it["size"]
				var lh: float = size_t * float(it["line_height"])
				var s2 := "q %s cm " % _pdf_matrix(xf)
				if float(it["opacity"]) * (it["color"] as Color).a < 0.999:
					s2 += "/%s gs " % _gs(gstates, float(it["opacity"]) * (it["color"] as Color).a, 1.0)
				s2 += _pdf_col(it["color"], false) + " BT /%s %s Tf" % [_pdf_font(it), _n(size_t)]
				var lines: PackedStringArray = String(it["text"]).split("\n")
				for i in lines.size():
					s2 += " 1 0 0 -1 0 %s Tm (%s) Tj" % [_n(size_t * 0.8 + i * lh), _pdf_str(lines[i])]
				content.append(s2 + " ET Q")
			"image":
				images.append([it["image"], float(it["opacity"])])
				var w: Vector2 = it["size"]
				var g := ("/%s gs " % _gs(gstates, it["opacity"], 1.0)) if float(it["opacity"]) < 0.999 else ""
				content.append("q %s cm %s%s 0 0 %s 0 %s cm /Im%d Do Q" % [_pdf_matrix(it["xf"]), g, _n(w.x), _n(-w.y), _n(w.y), images.size()])
	var stream := "\n".join(content).to_utf8_buffer()
	# objetos: 1 catálogo, 2 páginas, 3 página, 4 contenido, 5-8 fuentes, después gs e imágenes
	var objs: Array = []   # PackedByteArray por objeto (1-based por índice+1)
	objs.append("<< /Type /Catalog /Pages 2 0 R >>".to_utf8_buffer())
	objs.append("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".to_utf8_buffer())
	objs.append(PackedByteArray())   # página: se rellena al final
	objs.append(_pdf_stream("", stream))
	for f in ["Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica-BoldOblique"]:
		objs.append(("<< /Type /Font /Subtype /Type1 /BaseFont /%s /Encoding /WinAnsiEncoding >>" % f).to_utf8_buffer())
	var gs_res := ""
	for key in gstates:
		var parts: PackedStringArray = String(key).split("|")
		objs.append(("<< /Type /ExtGState /ca %s /CA %s >>" % [parts[0], parts[1]]).to_utf8_buffer())
		gs_res += "/%s %d 0 R " % [gstates[key], objs.size()]
	var img_res := ""
	for i in images.size():
		var img: Image = (images[i][0] as Image).duplicate()
		img.convert(Image.FORMAT_RGBA8)
		var rgb := PackedByteArray()
		var alpha := PackedByteArray()
		var px := img.get_data()
		var has_alpha := false
		rgb.resize(px.size() / 4 * 3)
		alpha.resize(px.size() / 4)
		for p in range(px.size() / 4):
			rgb[p * 3] = px[p * 4]
			rgb[p * 3 + 1] = px[p * 4 + 1]
			rgb[p * 3 + 2] = px[p * 4 + 2]
			alpha[p] = px[p * 4 + 3]
			if px[p * 4 + 3] < 255:
				has_alpha = true
		var smask := ""
		if has_alpha:
			objs.append(_pdf_stream("/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceGray /BitsPerComponent 8" % [img.get_width(), img.get_height()], alpha))
			smask = " /SMask %d 0 R" % objs.size()
		objs.append(_pdf_stream("/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8%s" % [img.get_width(), img.get_height(), smask], rgb))
		img_res += "/Im%d %d 0 R " % [i + 1, objs.size()]
	objs[2] = ("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %s %s] /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R /F3 7 0 R /F4 8 0 R >>%s%s >> >>" % [
		_n(size.x), _n(size.y), (" /ExtGState << %s>>" % gs_res) if gs_res != "" else "", (" /XObject << %s>>" % img_res) if img_res != "" else ""]).to_utf8_buffer()
	var pdf := "%PDF-1.4\n%âãÏÓ\n".to_utf8_buffer()
	var offsets := PackedInt64Array()
	for i in objs.size():
		offsets.append(pdf.size())
		pdf.append_array(("%d 0 obj\n" % (i + 1)).to_utf8_buffer())
		pdf.append_array(objs[i])
		pdf.append_array("\nendobj\n".to_utf8_buffer())
	var xref_at := pdf.size()
	var xref := "xref\n0 %d\n0000000000 65535 f \n" % (objs.size() + 1)
	for o in offsets:
		xref += "%010d 00000 n \n" % o
	xref += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % [objs.size() + 1, xref_at]
	pdf.append_array(xref.to_utf8_buffer())
	return pdf

static func _pdf_stream(dict: String, data: PackedByteArray) -> PackedByteArray:
	var b := ("<< %s /Length %d >>\nstream\n" % [dict, data.size()]).replace("<<  /Length", "<< /Length").to_utf8_buffer()
	b.append_array(data)
	b.append_array("\nendstream".to_utf8_buffer())
	return b

static func _gs(gstates: Dictionary, ca: float, CA: float) -> String:
	var key := "%s|%s" % [_n(clampf(ca, 0, 1)), _n(clampf(CA, 0, 1))]
	if not gstates.has(key):
		gstates[key] = "GS%d" % (gstates.size() + 1)
	return gstates[key]

static func _pdf_col(c: Color, stroke: bool) -> String:
	return "%s %s %s %s" % [_n(c.r), _n(c.g), _n(c.b), "RG" if stroke else "rg"]

static func _pdf_matrix(xf: Transform2D) -> String:
	return "%s %s %s %s %s %s" % [_n(xf.x.x), _n(xf.x.y), _n(xf.y.x), _n(xf.y.y), _n(xf.origin.x), _n(xf.origin.y)]

static func _pdf_path(subs: Array, ps: bool) -> String:
	var parts := PackedStringArray()
	for sub in subs:
		for o in sub["ops"]:
			match o[0]:
				"M": parts.append(_p(o[1]) + (" moveto" if ps else " m"))
				"L": parts.append(_p(o[1]) + (" lineto" if ps else " l"))
				"C": parts.append(_p(o[1]) + " " + _p(o[2]) + " " + _p(o[3]) + (" curveto" if ps else " c"))
		if sub["closed"]:
			parts.append("closepath" if ps else "h")
	return " ".join(parts)

static func _pdf_font(it: Dictionary) -> String:
	return "F%d" % (1 + (1 if it["bold"] else 0) + (2 if it["italic"] else 0))

## Cadena PDF/PostScript en Latin-1 (WinAnsi); lo que no cabe → "?".
static func _pdf_str(s: String) -> String:
	var out := ""
	for ch in s:
		var u := ch.unicode_at(0)
		if ch == "(" or ch == ")" or ch == "\\":
			out += "\\" + ch
		elif u >= 32 and u < 127:
			out += ch
		elif u >= 160 and u <= 255:
			out += "\\%03o" % u
		else:
			out += "?"
	return out

# ═══════════════════════════════════ EPS ═════════════════════════════════════
## PostScript encapsulado (EPSF-3.0). Sin transparencia (no existe en PS):
## las imágenes con alfa se mezclan sobre blanco.
static func to_eps(data_in: Dictionary) -> String:
	var data := texts_to_curves(data_in)   # tu fuente, como curvas
	var size: Vector2 = data["size"]
	var o := PackedStringArray([
		"%!PS-Adobe-3.0 EPSF-3.0",
		"%%%%BoundingBox: 0 0 %d %d" % [ceili(size.x), ceili(size.y)],
		"%%%%HiResBoundingBox: 0 0 %s %s" % [_n(size.x), _n(size.y)],
		"%%Creator: Vectopen",
		"%%EndComments",
		# Helvetica con codificación Latin-1 (á, é, ñ…), no la estándar de PS.
		"/reencode { findfont dup length dict begin { 1 index /FID ne { def } { pop pop } ifelse } forall /Encoding ISOLatin1Encoding def currentdict end definefont pop } bind def",
		"/Helvetica-L1 /Helvetica reencode /Helvetica-Bold-L1 /Helvetica-Bold reencode",
		"/Helvetica-Oblique-L1 /Helvetica-Oblique reencode /Helvetica-BoldOblique-L1 /Helvetica-BoldOblique reencode",
		"gsave 0 %s translate 1 -1 scale 1 setlinejoin" % _n(size.y)])
	if data["bg"] != null:
		var bg: Color = data["bg"]
		o.append("%s %s %s setrgbcolor 0 0 %s %s rectfill" % [_n(bg.r), _n(bg.g), _n(bg.b), _n(size.x), _n(size.y)])
	for it in data["items"]:
		match it["t"]:
			"path":
				var path := "newpath " + _pdf_path(it["subs"], true)
				var fill_op := "eofill" if it["evenodd"] else "fill"
				if it["fill"] != null:
					var f: Color = it["fill"]
					o.append("gsave %s %s %s %s setrgbcolor %s grestore" % [path, _n(f.r), _n(f.g), _n(f.b), fill_op])
				if it["stroke"] != null:
					var s: Color = it["stroke"]
					o.append("gsave %s %s %s %s setrgbcolor %s setlinewidth %d setlinecap stroke grestore" % [path, _n(s.r), _n(s.g), _n(s.b), _n(it["width"]), clampi(int(it["cap"]), 0, 2)])
			"text":
				var c: Color = it["color"]
				var size_t: float = it["size"]
				var lh: float = size_t * float(it["line_height"])
				var font: String = ["Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica-BoldOblique"][(1 if it["bold"] else 0) + (2 if it["italic"] else 0)] + "-L1"
				var lines: PackedStringArray = String(it["text"]).split("\n")
				for i in lines.size():
					o.append("gsave [%s] concat %s %s %s setrgbcolor /%s findfont %s scalefont setfont 0 %s translate 1 -1 scale 0 0 moveto (%s) show grestore" % [
						_pdf_matrix(it["xf"]), _n(c.r), _n(c.g), _n(c.b), font, _n(size_t), _n(size_t * 0.8 + i * lh), _pdf_str(lines[i])])
			"image":
				var img: Image = (it["image"] as Image).duplicate()
				img.convert(Image.FORMAT_RGBA8)
				var w := img.get_width()
				var h := img.get_height()
				var px := img.get_data()
				var hex := PackedStringArray()
				var line := ""
				for p in range(w * h):
					var a := px[p * 4 + 3] / 255.0
					for k in 3:
						line += "%02x" % int(round(px[p * 4 + k] * a + 255.0 * (1.0 - a)))
					if line.length() >= 120:
						hex.append(line)
						line = ""
				if line != "":
					hex.append(line)
				var sz: Vector2 = it["size"]
				o.append("gsave [%s] concat %s %s scale /pix %d string def %d %d 8 [%d 0 0 %d 0 0] {currentfile pix readhexstring pop} false 3 colorimage" % [
					_pdf_matrix(it["xf"]), _n(sz.x), _n(sz.y), w * 3, w, h, w, h])
				o.append_array(hex)
				o.append("grestore")
	o.append("grestore")
	o.append("showpage")
	o.append("%%EOF")
	return "\n".join(o) + "\n"
