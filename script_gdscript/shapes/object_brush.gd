# =============================================================================
# RUTA: res://script_gdscript/shapes/object_brush.gd
# PINCEL DE OBJETO (VGSE fase 2): estampa una o varias figuras a lo largo de
# un trazo, repartidas por LONGITUD DE ARCO (no por el parámetro de la
# curva), con tamaño según la presión (medio grosor del eje), giro con el
# trazo, separación, dispersión y, con varias figuras, alternándolas.
#
# · Fuente: Array de objetos; cada objeto = Array de piezas
#   {"pts": PackedVector2Array (normalizados: centro 0,0, lado mayor 1),
#    "col": Color}. Se crea con from_shapes() a partir de la selección.
# · build(): malla {points, indices, colors} lista para el render del pincel.
# · Aleatorio con SEMILLA guardada en el trazo: el mismo trazo se ve igual
#   al recargar, deshacer o exportar.
# =============================================================================
extends RefCounted

const GeomCore = preload("res://script_gdscript/shapes/VectorGeometryCore.gd")

## Parámetros por defecto (se guardan en el trazo, meta «brush_obj»).
const DEFAULTS := {
	"spacing": 1.1,     # separación entre estampas, en tamaños de estampa
	"rotate": true,     # girar con la dirección del trazo
	"scatter": 0.0,     # desplazamiento lateral aleatorio (en tamaños)
	"size_jitter": 0.0, # variación aleatoria del tamaño (0..1)
	"angle_jitter": 0.0,# variación aleatoria del giro (grados)
	"multi": "sequence",# con varias figuras: "sequence" | "random"
	"seed": 1,
	"mode": "stamp",    # "stamp" (copias rígidas) | "pattern" (se doblan con la curva)
	"repeat": true,     # patrón: repetir a lo largo; false = UNA copia a su tamaño (texto en trazado)
	"align": 0.0,       # una copia: 0 inicio · 0,5 centro · 1 final del trazado
	"offset": 0.0,      # una copia: desplazamiento a lo largo (en longitudes del trazado)
	"flip": false,      # patrón: al otro lado de la curva (texto por debajo)
	"baseline": false,  # patrón: la figura APOYADA en la curva (texto en trazado), no centrada
	# "rigid": patrón: cada letra/pieza rígida, solo girada con la curva (sin
	# deformarse). Si no se indica: sí en una sola copia (texto en trazado).
	# Una copia (texto en trazado), opcionales:
	#   "start_at" / "end_at": tramo del trazado que ocupa (0..1; 0 y 1 = entero)
	#   "tracking": espacio extra entre letras, en altos del texto
	#   "valign": "baseline" (encima, apoyado) | "top" (debajo, colgando) | "center"
	#   "reverse": recorre el trazado al revés (al otro lado, se lee bien girado)
	#   ("flip" refleja las letras: modo espejo)
}

## Figuras de serie (si aún no se ha elegido ninguna de la selección).
static func preset(name: String) -> Array:
	match name:
		"dot":
			return [[{"pts": _circle(0.5, 24), "col": Color(0.15, 0.15, 0.18)}]]
		"leaf":
			var p := PackedVector2Array()
			for i in 33:
				var t := float(i) / 32.0 * TAU
				p.append(Vector2(cos(t) * 0.5, sin(t) * 0.22 * (1.0 - 0.35 * cos(t))))
			return [[{"pts": p, "col": Color(0.24, 0.55, 0.27)}]]
	# estrella de 5 puntas
	var s := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + float(i) * PI / 5.0
		var r := 0.5 if i % 2 == 0 else 0.2
		s.append(Vector2(cos(a), sin(a)) * r)
	return [[{"pts": s, "col": Color(0.95, 0.7, 0.15)}]]

static func _circle(r: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var t := float(i) / float(n) * TAU
		p.append(Vector2(cos(t), sin(t)) * r)
	return p

## Fuente a partir de objetos del lienzo (en espacio global): figuras,
## trazados Bézier (abiertos: su trazo), trazos de pincel (su forma real) y
## grupos (sus figuras). `combine`: todo junto como UN objeto (conserva la
## colocación); si no, cada objeto seleccionado es una estampa distinta.
static func from_shapes(shapes: Array, combine: bool = true) -> Array:
	var objs: Array = []
	for sh in shapes:
		var pieces: Array = []
		_collect(sh, pieces)
		if not pieces.is_empty():
			objs.append(pieces)
	if objs.is_empty():
		return []
	if combine:
		var all: Array = []
		for o in objs:
			all.append_array(o)
		objs = [all]
	var out: Array = []
	for o in objs:
		out.append(_normalize(o))
	return out

## Piezas {pts (global), col} de un objeto y, si es un grupo, de sus hijos.
static func _collect(node, pieces: Array, include_hidden: bool = false) -> void:
	if not is_instance_valid(node) or not (node is CanvasItem) or (not include_hidden and not (node as CanvasItem).visible):
		return
	var xf: Transform2D = (node as CanvasItem).get_global_transform()
	if node is Line2D:
		_collect_brush_stroke(node as Line2D, xf, pieces)
		return
	if String((node as Node).get_meta("shape_type", "")).begins_with("text"):
		if _collect_text(node, xf, pieces):
			return
	var polys: Array = GeomCore.get_evaluated_geometry(node)
	var closed: bool = not ("closed" in node) or bool(node.closed)
	var fill := Color(0, 0, 0, 0)
	if "fill_color" in node:
		fill = node.fill_color
	elif "color" in node and node is Polygon2D:
		fill = node.color
	var sw: float = float(node.stroke_width) if "stroke_width" in node else 0.0
	var sc: Color = node.stroke_color if "stroke_color" in node else Color(0, 0, 0, 0)
	for poly in polys:
		if poly.size() < 2:
			continue
		var g := PackedVector2Array()
		for q in poly:
			g.append(xf * q)
		var scale := maxf(xf.get_scale().x, 0.0001)
		if closed and g.size() >= 3 and fill.a > 0.01:
			pieces.append({"pts": g, "col": fill})
		if sw > 0.001 and sc.a > 0.01:
			for ring in _stroke_rings(g, sw * scale * 0.5, closed):
				pieces.append({"pts": ring, "col": sc})
		elif not closed and fill.a <= 0.01:
			# trazado abierto sin borde visible: al menos una línea fina
			for ring in _stroke_rings(g, 1.0 * scale, false):
				pieces.append({"pts": ring, "col": Color(0.15, 0.15, 0.18)})
	# Grupo (o figura con hijos): también sus figuras
	for c in (node as Node).get_children():
		if c is CanvasItem and not String(c.name).begins_with("_") and not (c.get_script() and String(c.get_script().resource_path).ends_with("brush_stroke_render.gd")):
			_collect(c, pieces)

## Texto (VGSE fase 3, texto como pincel): el contorno de cada letra con
## su color, con los huecos (la «o», la «a») respetados.
static func _collect_text(node: Node, xf: Transform2D, pieces: Array) -> bool:
	var TC = load("res://script_gdscript/text/text_core.gd")
	var SG = load("res://script_gdscript/shapes/stroke_geom.gd")
	var vrt = node.get_node_or_null("VectorRichText")
	if vrt == null:
		vrt = TC.ensure_vrt(node)
	if vrt == null or not vrt.has_method("get_glyph_outlines"):
		return false
	var to_node: Transform2D = (vrt as CanvasItem).get_transform() if vrt is CanvasItem else Transform2D.IDENTITY
	var any := false
	var gi := -1
	for o in vrt.get_glyph_outlines():
		gi += 1
		var rings: Array = []
		for sd in o.get("subs", []):
			var c := Curve2D.new()
			var an: PackedVector2Array = sd["anchors"]
			for i in an.size():
				c.add_point(to_node * an[i], to_node.basis_xform(sd["ins"][i]), to_node.basis_xform(sd["outs"][i]))
			if an.size() >= 2:
				c.add_point(to_node * an[0], to_node.basis_xform(sd["ins"][0]), Vector2.ZERO)
			var ring := c.tessellate(5, 3.0)
			if ring.size() >= 3:
				rings.append(xf * ring)
		var col: Color = o.get("fill", Color(0.15, 0.15, 0.18))
		for poly in SG.evenodd_fill(rings):
			if (poly as PackedVector2Array).size() >= 3:
				pieces.append({"pts": poly, "col": col, "g": gi})
				any = true
	return any

## Trazo de pincel: su forma REAL (anchura por presión, remates); si es un
## trazo de objeto, sus estampas.
static func _collect_brush_stroke(l: Line2D, xf: Transform2D, pieces: Array) -> void:
	if l.points.size() < 1:
		return
	var R = load("res://script_gdscript/shapes/brush_stroke_render.gd")
	var SG = load("res://script_gdscript/shapes/stroke_geom.gd")
	var ax: Array = R.centerline(l)
	var col := l.default_color
	col.a = maxf(col.a, 0.2)
	if String(l.get_meta("brush_style", "")) == "object":
		var bo: Dictionary = l.get_meta("brush_obj", {})
		var src: Array = from_data(bo.get("src", []))
		if src.is_empty():
			src = preset("star")
		for r in outlines(ax[0], ax[1], src, bo.get("params", {})):
			pieces.append({"pts": xf * (r["pts"] as PackedVector2Array), "col": r["col"]})
		return
	var caps := {Line2D.LINE_CAP_ROUND: 1, Line2D.LINE_CAP_BOX: 2}
	for ring in SG.outline(ax[0], ax[1], caps.get(l.begin_cap_mode, 0), caps.get(l.end_cap_mode, 0)):
		if (ring as PackedVector2Array).size() >= 3 and not Geometry2D.is_polygon_clockwise(ring):
			pieces.append({"pts": xf * (ring as PackedVector2Array), "col": col})

## Contorno de un borde de grosor 2·h: en una figura cerrada, un anillo
## (puenteado para poder rellenarlo); en un trazado abierto, su contorno.
static func _stroke_rings(pts: PackedVector2Array, h: float, closed: bool) -> Array:
	var SG = load("res://script_gdscript/shapes/stroke_geom.gd")
	var out: Array = []
	if closed:
		var outer := Geometry2D.offset_polygon(pts, h, Geometry2D.JOIN_MITER)
		var inner := Geometry2D.offset_polygon(pts, -h, Geometry2D.JOIN_MITER)
		if outer.is_empty():
			return out
		if inner.is_empty():
			out.append(outer[0])
		else:
			out.append(SG.bridge(outer[0], inner[0]))
		return out
	var half := PackedFloat32Array()
	half.resize(pts.size())
	half.fill(h)
	for ring in SG.outline(pts, half, 1, 1):
		if (ring as PackedVector2Array).size() >= 3 and not Geometry2D.is_polygon_clockwise(ring):
			out.append(ring)
	return out

# ── Texto en trazado / referencias (VGSE fase 3) ─────────────────────────────
## Trazado → puntos del eje en el espacio de `into` (padre del trazo).
static func path_points(path: Node, into: Node2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not is_instance_valid(path) or not (path is CanvasItem):
		return out
	var pts := PackedVector2Array()
	var closed: bool = not ("closed" in path) or bool(path.closed)
	if "curve" in path and path.curve != null:
		pts = (path.curve as Curve2D).get_baked_points()
	else:
		var g: Array = GeomCore.get_evaluated_geometry(path)
		if not g.is_empty():
			pts = g[0]
	if pts.size() < 2:
		return out
	if closed and pts[0].distance_to(pts[pts.size() - 1]) > 0.001:
		pts.append(pts[0])
	var xf: Transform2D = into.get_global_transform().affine_inverse() * (path as CanvasItem).get_global_transform()
	return xf * pts

## Fuente (normalizada) y alto real en el lienzo de un objeto, aunque esté
## oculto (el texto de un texto en trazado se oculta).
static func source_of(node: Node, into: Node2D) -> Dictionary:
	var pieces: Array = []
	_collect(node, pieces, true)
	if pieces.is_empty():
		return {}
	var inv := into.get_global_transform().affine_inverse()
	var r := _obj_rect(pieces.map(func(pc): return {"pts": inv * (pc["pts"] as PackedVector2Array), "col": pc["col"]}))
	return {"src": [_normalize(pieces)], "height": maxf(r.size.y, 0.01)}

## Rehace un texto en trazado (u otro trazo enlazado) a partir de sus objetos
## fuente: el texto (contenido, formato) y el trazado (forma, posición).
## true si cambió algo.
static func refresh_ref(line: Line2D) -> bool:
	var ref: Dictionary = line.get_meta("brush_ref", {})
	var parent := line.get_parent() as Node2D
	if ref.is_empty() or parent == null:
		return false
	var src_node := parent.get_node_or_null(NodePath(String(ref.get("source", ""))))
	var path_node := parent.get_node_or_null(NodePath(String(ref.get("path", ""))))
	if src_node == null or path_node == null:
		return false
	# En el espacio del PROPIO trazo: si se mueve (y lleva consigo su
	# trazado), las letras no se desplazan dos veces.
	var pts := path_points(path_node, line)
	var so := source_of(src_node, parent)
	if pts.size() < 2 or so.is_empty():
		return false
	var bo: Dictionary = line.get_meta("brush_obj", {}).duplicate()
	bo["src"] = to_data(so["src"])
	line.set_meta("brush_obj", bo)
	line.width = float(so["height"])
	line.points = pts
	return true

## Cada objeto normalizado (centro 0,0 y lado mayor 1).
static func _normalize_all(src: Array) -> Array:
	var out: Array = []
	for o in src:
		out.append(_normalize(o))
	return out

## Centro (0,0) y lado mayor 1.
static func _normalize(pieces: Array) -> Array:
	var r := Rect2()
	var first := true
	for pc in pieces:
		for q in pc["pts"]:
			if first:
				r = Rect2(q, Vector2.ZERO)
				first = false
			else:
				r = r.expand(q)
	var c := r.get_center()
	var s := maxf(maxf(r.size.x, r.size.y), 0.000001)
	var out: Array = []
	for pc in pieces:
		var p := PackedVector2Array()
		for q in pc["pts"]:
			p.append((q - c) / s)
		var np := {"pts": p, "col": pc["col"]}
		if pc.has("g"):
			np["g"] = pc["g"]
		out.append(np)
	return out

## Triángulos de cada pieza (una vez por fuente).
static func _triangulate(src: Array) -> Array:
	var out: Array = []
	for obj in src:
		var tri_obj: Array = []
		for pc in obj:
			var pts: PackedVector2Array = pc["pts"]
			var idx := Geometry2D.triangulate_polygon(pts)
			if idx.is_empty():
				# polígono que se corta: se descompone en convexos
				for cv in Geometry2D.decompose_polygon_in_convex(pts):
					var ci := Geometry2D.triangulate_polygon(cv)
					if not ci.is_empty():
						tri_obj.append({"pts": cv, "idx": ci, "col": pc["col"]})
				continue
			tri_obj.append({"pts": pts, "idx": idx, "col": pc["col"]})
		out.append(tri_obj)
	return out

## Generador reproducible (sin tocar el aleatorio global).
static func _rand(seed: int, i: int, k: int) -> float:
	var h := hash([seed, i, k])
	return float(h & 0xFFFFFF) / float(0xFFFFFF)

## Estampas a lo largo del eje. `pts` eje, `half` medio grosor por punto
## (tamaño de la estampa = 2·half, con la presión). Devuelve
## {points, indices, colors, stamps} (stamps = nº de estampas).
static func build(pts: PackedVector2Array, half: PackedFloat32Array, src: Array, params: Dictionary = {}) -> Dictionary:
	var m := {"points": PackedVector2Array(), "indices": PackedInt32Array(), "colors": PackedColorArray(), "stamps": 0}
	var n := pts.size()
	if n == 0 or src.is_empty() or half.size() < n:
		return m
	var pr := DEFAULTS.duplicate()
	pr.merge(params, true)
	if String(pr["mode"]) == "pattern" and n >= 2:
		return build_pattern(pts, half, src, pr)
	var tris := _triangulate(src)
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var cols: PackedColorArray = m["colors"]
	var lay := _stamp_layout(pts, half, tris.size(), pr)
	for st in lay:
		var xf: Transform2D = st["xf"]
		for pc in tris[int(st["oi"])]:
			var base := verts.size()
			for q in pc["pts"]:
				verts.append(xf * q)
				cols.append(pc["col"])
			for t in pc["idx"]:
				idx.append(base + t)
	m["points"] = verts
	m["indices"] = idx
	m["colors"] = cols
	m["stamps"] = lay.size()
	return m

## Dónde va cada estampa: [{xf: Transform2D (figura normalizada → eje), oi}]
## repartidas por LONGITUD DE ARCO; separación según el tamaño en cada sitio.
static func _stamp_layout(pts: PackedVector2Array, half: PackedFloat32Array, n_objs: int, pr: Dictionary) -> Array:
	var out: Array = []
	var n := pts.size()
	var cum := _cum(pts)
	var total := cum[n - 1]
	var seed := int(pr["seed"])
	var spacing := maxf(float(pr["spacing"]), 0.05)
	var d := 0.0
	var j := 0
	var s_i := 0
	while d <= total + 0.0001 and s_i < 20000:
		while j < n - 2 and cum[j + 1] < d:
			j += 1
		var j2 := mini(j + 1, n - 1)
		var seg := maxf(cum[j2] - cum[j], 0.000001)
		var f := clampf((d - cum[j]) / seg, 0.0, 1.0)
		var c := pts[j].lerp(pts[j2], f)
		var size := 2.0 * lerpf(half[j], half[j2], f)
		var dir := (pts[j2] - pts[j]).normalized() if j2 != j else Vector2.RIGHT
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var sz := maxf(size * (1.0 + float(pr["size_jitter"]) * (_rand(seed, s_i, 1) * 2.0 - 1.0)), 0.0)
		var ang := dir.angle() if bool(pr["rotate"]) else 0.0
		ang += deg_to_rad(float(pr["angle_jitter"])) * (_rand(seed, s_i, 2) * 2.0 - 1.0)
		var normal := Vector2(-dir.y, dir.x)
		var pos := c + normal * size * float(pr["scatter"]) * (_rand(seed, s_i, 3) * 2.0 - 1.0)
		out.append({"xf": Transform2D(ang, Vector2(sz, sz), 0.0, pos), "oi": _pick(n_objs, s_i, seed, pr)})
		s_i += 1
		d += maxf(size * spacing, total / 5000.0 + 0.0001)
	return out

static func _pick(n_objs: int, i: int, seed: int, pr: Dictionary) -> int:
	if n_objs <= 1:
		return 0
	if String(pr["multi"]) == "random":
		return int(_rand(seed, i, 4) * n_objs) % n_objs
	return i % n_objs

static func _cum(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	return cum

# ── Pincel de PATRÓN: la figura se dobla siguiendo la curva ─────────────────
const STRIPS_PER_TILE := 24

## Rectángulo de la figura y su proporción (largo / alto).
static func _obj_rect(obj: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for pc in obj:
		for q in pc["pts"]:
			if first:
				r = Rect2(q, Vector2.ZERO)
				first = false
			else:
				r = r.expand(q)
	return r

## Figura en espacio de TESELA: u a lo largo (0..aspecto, en altos de la
## figura) y v a lo ancho (-0,5..0,5).
static func _to_tile(obj: Array) -> Dictionary:
	var r := _obj_rect(obj)
	var h := maxf(r.size.y, 0.000001)
	var aspect := maxf(r.size.x / h, 0.02)
	var polys: Array = []
	for pc in obj:
		var poly := PackedVector2Array()
		for q in pc["pts"]:
			poly.append(Vector2((q.x - r.position.x) / h, (q.y - r.get_center().y) / h))
		polys.append({"pts": poly, "col": pc["col"], "g": int(pc.get("g", -1))})
	return {"aspect": aspect, "polys": polys}

## Tesela cortada en franjas finas en u y triangulada: al llevarla a la
## curva sus bordes se doblan. {aspect, pieces: [{pts, idx, col}]}
static func _tile(obj: Array) -> Dictionary:
	var t := _to_tile(obj)
	var aspect: float = t["aspect"]
	var strip_w := aspect / float(STRIPS_PER_TILE)
	var pieces: Array = []
	for pc in t["polys"]:
		for si in STRIPS_PER_TILE:
			var x0 := si * strip_w - (0.0001 if si == 0 else 0.0)
			var x1 := (si + 1) * strip_w + (0.0001 if si == STRIPS_PER_TILE - 1 else 0.0)
			var strip := PackedVector2Array([Vector2(x0, -1.0), Vector2(x1, -1.0), Vector2(x1, 1.0), Vector2(x0, 1.0)])
			# El corte puede dejar contornos y HUECOS (letras como la «o»):
			# relleno par-impar con los huecos puenteados (antes el hueco se
			# descartaba y la letra salía rellena).
			var cuts := Geometry2D.intersect_polygons(pc["pts"], strip)
			if cuts.is_empty():
				continue
			var SG = load("res://script_gdscript/shapes/stroke_geom.gd")
			for cut in SG.evenodd_fill(cuts):
				var sub := _subdivide(cut, strip_w * 0.5)
				var idx := Geometry2D.triangulate_polygon(sub)
				if idx.is_empty():
					idx = Geometry2D.triangulate_polygon(cut)
					sub = cut
				if not idx.is_empty():
					pieces.append({"pts": sub, "idx": idx, "col": pc["col"]})
	return {"aspect": aspect, "pieces": pieces}

## Plan B para triangular un contorno difícil: cortarlo en franjas finas
## (relleno par-impar en cada una) y triangular cada trozo.
static func _strip_tris(pc: Dictionary, n_strips: int = 16) -> Array:
	var out: Array = []
	var r := _obj_rect([pc])
	var w := maxf(r.size.x, 0.000001) / float(n_strips)
	var SG = load("res://script_gdscript/shapes/stroke_geom.gd")
	for si in n_strips:
		var x0 := r.position.x + si * w - 0.0001
		var x1 := r.position.x + (si + 1) * w + 0.0001
		var strip := PackedVector2Array([Vector2(x0, r.position.y - 1.0), Vector2(x1, r.position.y - 1.0), Vector2(x1, r.end.y + 1.0), Vector2(x0, r.end.y + 1.0)])
		var cuts := Geometry2D.intersect_polygons(pc["pts"], strip)
		for cut in SG.evenodd_fill(cuts):
			var idx := Geometry2D.triangulate_polygon(cut)
			if not idx.is_empty():
				out.append({"pts": cut, "idx": idx, "col": pc["col"]})
	return out

## Parte los lados largos (para que se doblen al seguir la curva).
static func _subdivide(poly: PackedVector2Array, max_len: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		out.append(a)
		var k := int(a.distance_to(b) / maxf(max_len, 0.0001))
		for j in range(1, k + 1):
			out.append(a.lerp(b, float(j) / float(k + 1)))
	return out

## Reparto de teselas a lo largo del eje (encajan justas de principio a fin)
## y normales suavizadas: lo comparten la malla y «convertir en figuras».
static func _pattern_ctx(pts: PackedVector2Array, half: PackedFloat32Array, aspects: Array, pr: Dictionary) -> Dictionary:
	var n := pts.size()
	var cum := _cum(pts)
	var total := cum[n - 1]
	var nrm := PackedVector2Array()
	nrm.resize(n)
	for i in n:
		var d0 := (pts[i] - pts[i - 1]).normalized() if i > 0 else (pts[1] - pts[0]).normalized()
		var d1 := (pts[i + 1] - pts[i]).normalized() if i < n - 1 else d0
		var t := (d0 + d1).normalized()
		if t == Vector2.ZERO:
			t = d1
		nrm[i] = Vector2(-t.y, t.x)
	var hmax := 0.0
	for hh in half:
		hmax = maxf(hmax, hh)
	var gap := maxf(maxf(float(pr["spacing"]), 0.05) - 1.0, 0.0)   # 1,1 → 10 % de hueco
	var nominal := float(aspects[0]) * 2.0 * hmax * (1.0 + gap)
	var count := clampi(int(round(total / maxf(nominal, 0.0001))), 1, 4000)
	var seg_len := total / float(count)
	var start := 0.0
	if not bool(pr.get("repeat", true)):
		# UNA copia a su tamaño natural (texto en trazado), alineada y
		# desplazada a lo largo del trazado; sin hueco.
		count = 1
		gap = 0.0
		seg_len = float(aspects[0]) * 2.0 * hmax
		var r := range_of(pr, total)
		start = r.x + (r.y - r.x - seg_len) * clampf(float(pr.get("align", 0.0)), 0.0, 1.0) + float(pr.get("offset", 0.0)) * total
	var order := PackedInt32Array()
	for ti in count:
		order.append(_pick(aspects.size(), ti, int(pr["seed"]), pr))
	return {"pts": pts, "half": half, "cum": cum, "nrm": nrm, "total": total,
		"count": count, "seg_len": seg_len, "gap": gap, "order": order, "start": start,
		"flip": -1.0 if bool(pr.get("flip", false)) else 1.0,
		"vshift": -0.5 if bool(pr.get("baseline", false)) else 0.0}

## Tramo [inicio, final] del trazado (en distancia) que ocupa una copia.
static func range_of(pr: Dictionary, total: float) -> Vector2:
	var a := clampf(float(pr.get("start_at", 0.0)), 0.0, 1.0)
	var b := clampf(float(pr.get("end_at", 1.0)), 0.0, 1.0)
	if b < a:
		var t := a
		a = b
		b = t
	return Vector2(a * total, b * total)

## Punto (u, v) de la tesela `ti` → curva: a la distancia s(u) y apartado
## v·grosor por la normal.
static func _warp(ctx: Dictionary, ti: int, q: Vector2, aspect: float) -> Vector2:
	var a := _axis_at(ctx, _s_of(ctx, ti, q.x, aspect))
	return a["p"] + a["n"] * (q.y + float(ctx.get("vshift", 0.0))) * 2.0 * float(a["h"])

## Distancia a lo largo del trazado de la coordenada u de la tesela `ti`.
static func _s_of(ctx: Dictionary, ti: int, u: float, aspect: float) -> float:
	var seg_len: float = ctx["seg_len"]
	var body := seg_len / (1.0 + float(ctx["gap"]))
	return float(ctx.get("start", 0.0)) + ti * seg_len + clampf(u / aspect, 0.0, 1.0) * body

## Como _s_of pero sin limitar u a la tesela (letras con espaciado extra).
static func _s_free(ctx: Dictionary, ti: int, u: float, aspect: float) -> float:
	var seg_len: float = ctx["seg_len"]
	var body := seg_len / (1.0 + float(ctx["gap"]))
	return float(ctx.get("start", 0.0)) + ti * seg_len + u / maxf(aspect, 0.000001) * body

## Letras de una tesela listas para colocar: agrupadas, con su espaciado
## extra ("du") y la línea base (mediana del pie de las letras: la «p» o la
## «g» bajan, pero no mueven la base). Ajusta ctx: base y alineación.
static func _rigid_groups(ctx: Dictionary, polys: Array, aspect: float, pr: Dictionary) -> Array:
	var groups := _glyph_groups(polys)
	groups.sort_custom(func(a, b): return a["u0"] < b["u0"])
	var trk := float(pr.get("tracking", 0.0))
	var bottoms: Array = []
	for k in groups.size():
		var grp: Dictionary = groups[k]
		grp["du"] = trk * k
		var bot := -INF
		for i in grp["polys"]:
			bot = maxf(bot, _obj_rect([polys[i]]).end.y)
		bottoms.append(bot)
	if bool(pr.get("baseline", false)) and not bottoms.is_empty():
		bottoms.sort()
		var base := float(bottoms[(bottoms.size() - 1) / 2])
		var top := 0.0
		for i in polys.size():
			top = minf(top, _obj_rect([polys[i]]).position.y)
		match String(pr.get("valign", "baseline")):
			"top": ctx["vshift"] = -top                     # cuelga: la parte de arriba toca el trazo
			"center": ctx["vshift"] = -(top + base) * 0.5   # centrado en el trazo
			_: ctx["vshift"] = -base
	if int(ctx["count"]) == 1 and groups.size() > 1 and absf(trk) > 0.0:
		var body := float(ctx["seg_len"]) / (1.0 + float(ctx["gap"]))
		var extra := trk * (groups.size() - 1) / maxf(aspect, 0.000001) * body
		ctx["start"] = float(ctx["start"]) - extra * clampf(float(pr.get("align", 0.0)), 0.0, 1.0)
	return groups

## Tramo que ocupa el texto (una copia) a lo largo del trazado: Vector2(s0, s1)
## en distancia, y el tramo permitido. Para los tiradores del lienzo.
static func text_span(pts0: PackedVector2Array, half0: PackedFloat32Array, src: Array, params: Dictionary) -> Dictionary:
	var pr0 := DEFAULTS.duplicate()
	pr0.merge(params, true)
	if src.is_empty() or pts0.size() < 2:
		return {}
	var rv := _oriented(pts0, half0, pr0)
	var pts: PackedVector2Array = rv[0]
	var half: PackedFloat32Array = rv[1]
	var pr: Dictionary = rv[2]
	var t := _to_tile(src[0])
	var ctx := _pattern_ctx(pts, half, [t["aspect"]], pr)
	var asp := float(t["aspect"])
	var groups := _rigid_groups(ctx, t["polys"], asp, pr)
	var a := INF
	var b := -INF
	for grp in groups:
		a = minf(a, _s_free(ctx, 0, float(grp["u0"]) + float(grp["du"]), asp))
		b = maxf(b, _s_free(ctx, 0, float(grp["u1"]) + float(grp["du"]), asp))
	var total := float(ctx["total"])
	var tx := Vector2(total - b, total - a) if bool(pr0.get("reverse", false)) else Vector2(a, b)
	return {"text": tx, "range": range_of(pr0, total), "total": total}

## «Invertir dirección»: el trazado recorrido al revés. Inicio, final,
## alineación y desplazamiento se traducen para que sigan refiriéndose al
## trazado original (los tiradores no cambian de sitio). [pts, half, pr]
static func _oriented(pts: PackedVector2Array, half: PackedFloat32Array, pr: Dictionary) -> Array:
	if not bool(pr.get("reverse", false)):
		return [pts, half, pr]
	var p2 := PackedVector2Array()
	var h2 := PackedFloat32Array()
	for i in range(pts.size() - 1, -1, -1):
		p2.append(pts[i])
		h2.append(half[mini(i, half.size() - 1)])
	var r := pr.duplicate()
	r["start_at"] = 1.0 - clampf(float(pr.get("end_at", 1.0)), 0.0, 1.0)
	r["end_at"] = 1.0 - clampf(float(pr.get("start_at", 0.0)), 0.0, 1.0)
	r["align"] = 1.0 - clampf(float(pr.get("align", 0.0)), 0.0, 1.0)
	r["offset"] = -float(pr.get("offset", 0.0))
	return [p2, h2, r]

## Punto del eje a la distancia s: {p, n (normal, con «al otro lado»), h (medio
## grosor)}. Fuera del trazado sigue recto por la tangente del extremo.
static func _axis_at(ctx: Dictionary, s: float) -> Dictionary:
	var cum: PackedFloat32Array = ctx["cum"]
	var pts: PackedVector2Array = ctx["pts"]
	var nrm: PackedVector2Array = ctx["nrm"]
	var half: PackedFloat32Array = ctx["half"]
	var n := pts.size()
	var total: float = ctx["total"]
	if s < 0.0 or s > total:
		# una copia que se sale del trazado: sigue recta por la tangente
		var e := 0 if s < 0.0 else n - 1
		var e2 := 1 if s < 0.0 else n - 2
		var tg := (pts[e] - pts[e2]).normalized() * (1.0 if s > total else -1.0)
		var over := (s - total) if s > total else -s
		return {"p": pts[e] + tg * over, "n": nrm[e] * float(ctx.get("flip", 1.0)), "h": half[e]}
	var j := clampi(cum.bsearch(s) - 1, 0, n - 2)
	var j2 := j + 1
	var f := clampf((s - cum[j]) / maxf(cum[j2] - cum[j], 0.000001), 0.0, 1.0)
	var no := nrm[j].lerp(nrm[j2], f).normalized() * float(ctx.get("flip", 1.0))
	return {"p": pts[j].lerp(pts[j2], f), "n": no, "h": lerpf(half[j], half[j2], f)}

# ── Letras rígidas (texto en trazado) ────────────────────────────────────────
static func _is_rigid(pr: Dictionary) -> bool:
	return bool(pr.get("rigid", not bool(pr.get("repeat", true))))

## Piezas de una tesela agrupadas por letra: [{u0, u1, polys: [índices]}].
## Con índice de letra ("g") se usa; si no (documentos antiguos), se agrupan
## las piezas que se solapan a lo largo (la «i» con su punto).
static func _glyph_groups(polys: Array) -> Array:
	var by_g := {}
	var loose: Array = []
	for i in polys.size():
		var pc: Dictionary = polys[i]
		var r := _obj_rect([pc])
		var it := {"u0": r.position.x, "u1": r.end.x, "polys": [i]}
		var g := int(pc.get("g", -1))
		if g < 0:
			loose.append(it)
		elif by_g.has(g):
			var e: Dictionary = by_g[g]
			e["u0"] = minf(e["u0"], it["u0"])
			e["u1"] = maxf(e["u1"], it["u1"])
			(e["polys"] as Array).append(i)
		else:
			by_g[g] = it
	loose.sort_custom(func(a, b): return a["u0"] < b["u0"])
	var merged: Array = []
	for it in loose:
		if not merged.is_empty() and it["u0"] < merged[-1]["u1"]:
			merged[-1]["u1"] = maxf(merged[-1]["u1"], it["u1"])
			(merged[-1]["polys"] as Array).append_array(it["polys"])
		else:
			merged.append(it)
	var out: Array = by_g.values()
	out.append_array(merged)
	return out

## Transformación rígida de una letra (u, v de la tesela → trazado): su
## centro sobre la curva y girada con la dirección media bajo la letra.
static func _glyph_xf(ctx: Dictionary, ti: int, grp: Dictionary, aspect: float) -> Transform2D:
	var u0: float = grp["u0"]
	var u1: float = grp["u1"]
	var uc := (u0 + u1) * 0.5
	var du := float(grp.get("du", 0.0))   # espaciado extra (tracking)
	var s0 := _s_free(ctx, ti, u0 + du, aspect)
	var s1 := _s_free(ctx, ti, u1 + du, aspect)
	var sc := _s_free(ctx, ti, uc + du, aspect)
	var a := _axis_at(ctx, sc)
	var t: Vector2 = _axis_at(ctx, s1)["p"] - _axis_at(ctx, s0)["p"]
	t = t.normalized() if t.length() > 0.000001 else Vector2(-a["n"].y, a["n"].x) * float(ctx.get("flip", 1.0))
	var nrm := Vector2(-t.y, t.x) * float(ctx.get("flip", 1.0))
	if nrm.dot(a["n"]) < 0.0:
		nrm = -nrm
	var hv := 2.0 * float(a["h"])                      # alto (v) en px
	var hu := (s1 - s0) / maxf(u1 - u0, 0.000001)      # largo (u) en px
	if u1 - u0 <= 0.000001:
		hu = hv
	var origin: Vector2 = a["p"] + nrm * float(ctx.get("vshift", 0.0)) * hv - t * uc * hu
	return Transform2D(t * hu, nrm * hv, origin)

## La figura repetida a lo largo del eje y DOBLADA con él. Grosor = 2·half.
static func build_pattern(pts: PackedVector2Array, half: PackedFloat32Array, src: Array, pr: Dictionary) -> Dictionary:
	var m := {"points": PackedVector2Array(), "indices": PackedInt32Array(), "colors": PackedColorArray(), "stamps": 0}
	if _cum(pts)[pts.size() - 1] <= 0.0001:
		return m
	if _is_rigid(pr):
		return _build_rigid(pts, half, src, pr)
	var tiles: Array = []
	var aspects: Array = []
	for obj in src:
		var t := _tile(obj)
		tiles.append(t)
		aspects.append(t["aspect"])
	var ctx := _pattern_ctx(pts, half, aspects, pr)
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var cols: PackedColorArray = m["colors"]
	for ti in int(ctx["count"]):
		var tile: Dictionary = tiles[(ctx["order"] as PackedInt32Array)[ti]]
		var asp := float(tile["aspect"])
		for pc in tile["pieces"]:
			var base := verts.size()
			for q in pc["pts"]:
				verts.append(_warp(ctx, ti, q, asp))
				cols.append(pc["col"])
			for t in pc["idx"]:
				idx.append(base + t)
	m["points"] = verts
	m["indices"] = idx
	m["colors"] = cols
	m["stamps"] = int(ctx["count"])
	return m

## Patrón con letras rígidas: cada letra entera, girada con la curva.
static func _build_rigid(pts0: PackedVector2Array, half0: PackedFloat32Array, src: Array, pr0: Dictionary) -> Dictionary:
	var rv := _oriented(pts0, half0, pr0)
	var pts: PackedVector2Array = rv[0]
	var half: PackedFloat32Array = rv[1]
	var pr: Dictionary = rv[2]
	var m := {"points": PackedVector2Array(), "indices": PackedInt32Array(), "colors": PackedColorArray(), "stamps": 0}
	var tiles: Array = []
	var aspects: Array = []
	for obj in src:
		var t := _to_tile(obj)
		var tris: Array = []
		for pc in t["polys"]:
			var tp: Array = []
			var ti0 := Geometry2D.triangulate_polygon(pc["pts"])
			if ti0.is_empty():
				tp = _strip_tris(pc)   # contorno raro (letras con hueco puenteado)
			else:
				tp = [{"pts": pc["pts"], "idx": ti0, "col": pc["col"]}]
			tris.append(tp)
		t["tris"] = tris
		tiles.append(t)
		aspects.append(t["aspect"])
	var ctx := _pattern_ctx(pts, half, aspects, pr)
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var cols: PackedColorArray = m["colors"]
	for ti in int(ctx["count"]):
		var tile: Dictionary = tiles[(ctx["order"] as PackedInt32Array)[ti]]
		var asp := float(tile["aspect"])
		for grp in _rigid_groups(ctx, tile["polys"], asp, pr):
			var gx := _glyph_xf(ctx, ti, grp, asp)
			for k in grp["polys"]:
				for tp in tile["tris"][k]:
					var base := verts.size()
					for q in tp["pts"]:
						verts.append(gx * q)
						cols.append(tp["col"])
					for t in tp["idx"]:
						idx.append(base + t)
	m["points"] = verts
	m["indices"] = idx
	m["colors"] = cols
	m["stamps"] = int(ctx["count"])
	return m

## Contornos de cada estampa (para «Convertir trazo en contorno»): Array de
## {pts (polígono cerrado, en el espacio del trazo), col}. En patrón, la
## figura doblada con la curva.
static func outlines(pts: PackedVector2Array, half: PackedFloat32Array, src: Array, params: Dictionary = {}) -> Array:
	var out: Array = []
	var n := pts.size()
	if n == 0 or src.is_empty() or half.size() < n:
		return out
	var pr := DEFAULTS.duplicate()
	pr.merge(params, true)
	if String(pr["mode"]) == "pattern" and n >= 2:
		if _cum(pts)[n - 1] <= 0.0001:
			return out
		if _is_rigid(pr):
			var rv := _oriented(pts, half, pr)
			pts = rv[0]
			half = rv[1]
			pr = rv[2]
		var tiles: Array = []
		var aspects: Array = []
		for obj in src:
			var t := _to_tile(obj)
			tiles.append(t)
			aspects.append(t["aspect"])
		var ctx := _pattern_ctx(pts, half, aspects, pr)
		for ti in int(ctx["count"]):
			var tile: Dictionary = tiles[(ctx["order"] as PackedInt32Array)[ti]]
			var asp := float(tile["aspect"])
			if _is_rigid(pr):
				for grp in _rigid_groups(ctx, tile["polys"], asp, pr):
					var gx := _glyph_xf(ctx, ti, grp, asp)
					for k in grp["polys"]:
						var pc: Dictionary = tile["polys"][k]
						out.append({"pts": gx * (pc["pts"] as PackedVector2Array), "col": pc["col"]})
				continue
			for pc in tile["polys"]:
				var ring := PackedVector2Array()
				for q in _subdivide(pc["pts"], asp / float(STRIPS_PER_TILE) * 0.5):
					ring.append(_warp(ctx, ti, q, asp))
				out.append({"pts": ring, "col": pc["col"]})
		return out
	for st in _stamp_layout(pts, half, src.size(), pr):
		var xf: Transform2D = st["xf"]
		for pc in src[int(st["oi"])]:
			out.append({"pts": xf * (pc["pts"] as PackedVector2Array), "col": pc["col"]})
	return out

## Datos para guardar (JSON): colores en hex, puntos como [x, y].
static func to_data(src: Array) -> Array:
	var out: Array = []
	for obj in src:
		var o: Array = []
		for pc in obj:
			var p: Array = []
			for q in pc["pts"]:
				p.append([snappedf(q.x, 0.0001), snappedf(q.y, 0.0001)])
			var d := {"pts": p, "col": (pc["col"] as Color).to_html(true)}
			if pc.has("g"):
				d["g"] = int(pc["g"])
			o.append(d)
		out.append(o)
	return out

static func from_data(data) -> Array:
	var out: Array = []
	if not (data is Array):
		return out
	for o in data:
		var obj: Array = []
		for pc in o:
			var p := PackedVector2Array()
			for q in pc.get("pts", []):
				if q is Array and q.size() >= 2:
					p.append(Vector2(float(q[0]), float(q[1])))
				elif q is Vector2:
					p.append(q)
			var col = pc.get("col", "262630")
			var piece := {"pts": p, "col": col if col is Color else Color.from_string(String(col), Color(0.15, 0.15, 0.18))}
			if pc.has("g"):
				piece["g"] = int(pc["g"])
			obj.append(piece)
		if not obj.is_empty():
			out.append(obj)
	return out
