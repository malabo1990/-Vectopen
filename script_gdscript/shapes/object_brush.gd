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

## Fuente a partir de figuras del lienzo (en espacio global). `combine`:
## todas juntas como UN objeto (conservan su colocación); si no, cada figura
## es un objeto (pincel multiobjeto).
static func from_shapes(shapes: Array, combine: bool = true) -> Array:
	var objs: Array = []
	for sh in shapes:
		if not is_instance_valid(sh) or not (sh is CanvasItem):
			continue
		var polys: Array = GeomCore.get_evaluated_geometry(sh)
		var xf: Transform2D = (sh as CanvasItem).get_global_transform()
		var col := Color(0.15, 0.15, 0.18)
		if "fill_color" in sh:
			col = sh.fill_color
		elif "default_color" in sh:
			col = sh.default_color
		var pieces: Array = []
		for poly in polys:
			if poly.size() < 3:
				continue
			var g := PackedVector2Array()
			for q in poly:
				g.append(xf * q)
			pieces.append({"pts": g, "col": col})
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
		out.append({"pts": p, "col": pc["col"]})
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
	var tris := _triangulate(src)
	var cum := PackedFloat32Array()
	cum.resize(n)
	for i in range(1, n):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	var total := cum[n - 1]
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var cols: PackedColorArray = m["colors"]
	var seed := int(pr["seed"])
	var spacing := maxf(float(pr["spacing"]), 0.05)
	var d := 0.0
	var j := 0
	var s_i := 0
	var guard := 0
	while d <= total + 0.0001 and guard < 20000:
		guard += 1
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
		var sz := size * (1.0 + float(pr["size_jitter"]) * (_rand(seed, s_i, 1) * 2.0 - 1.0))
		sz = maxf(sz, 0.0)
		var ang := dir.angle() if bool(pr["rotate"]) else 0.0
		ang += deg_to_rad(float(pr["angle_jitter"])) * (_rand(seed, s_i, 2) * 2.0 - 1.0)
		var normal := Vector2(-dir.y, dir.x)
		var pos := c + normal * size * float(pr["scatter"]) * (_rand(seed, s_i, 3) * 2.0 - 1.0)
		var oi := 0
		if tris.size() > 1:
			oi = int(_rand(seed, s_i, 4) * tris.size()) % tris.size() if String(pr["multi"]) == "random" else s_i % tris.size()
		var xf := Transform2D(ang, Vector2(sz, sz), 0.0, pos)
		for pc in tris[oi]:
			var base := verts.size()
			for q in pc["pts"]:
				verts.append(xf * q)
				cols.append(pc["col"])
			for t in pc["idx"]:
				idx.append(base + t)
		s_i += 1
		# siguiente estampa: separación según el tamaño AQUÍ (con presión)
		d += maxf(size * spacing, total / 5000.0 + 0.0001)
	m["points"] = verts
	m["indices"] = idx
	m["colors"] = cols
	m["stamps"] = s_i
	return m

## Datos para guardar (JSON): colores en hex, puntos como [x, y].
static func to_data(src: Array) -> Array:
	var out: Array = []
	for obj in src:
		var o: Array = []
		for pc in obj:
			var p: Array = []
			for q in pc["pts"]:
				p.append([snappedf(q.x, 0.0001), snappedf(q.y, 0.0001)])
			o.append({"pts": p, "col": (pc["col"] as Color).to_html(true)})
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
			obj.append({"pts": p, "col": col if col is Color else Color.from_string(String(col), Color(0.15, 0.15, 0.18))})
		if not obj.is_empty():
			out.append(obj)
	return out
