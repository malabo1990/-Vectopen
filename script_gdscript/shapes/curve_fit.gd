# =============================================================================
# RUTA: res://script_gdscript/shapes/curve_fit.gd
# AJUSTE DE CURVAS BÉZIER a puntos dibujados a mano (algoritmo de Philip J.
# Schneider, "An Algorithm for Automatically Fitting Digitized Curves",
# Graphics Gems, 1990 — el que usan Illustrator / Inkscape para el pincel y
# el lápiz). Convierte el muestreo tembloroso del lápiz en pocas cúbicas
# lisas: el trazo queda con curvatura continua y sin "bultos".
#
#   fit(points, error) -> Curve2D
#   · error = distancia máxima (en las unidades de los puntos) entre la curva
#     y los puntos originales;
#   · las ESQUINAS reales (giro brusco) se respetan: ahí se corta y cada lado
#     lleva su propia tangente.
# =============================================================================
extends RefCounted

const MAX_ITER := 4
const CORNER_DEG := 70.0

## Puntos → Curve2D de cúbicas ajustadas.
static func fit(points: PackedVector2Array, error: float) -> Curve2D:
	var curve := Curve2D.new()
	var pts := _dedupe(points, maxf(error * 0.05, 0.001))
	if pts.size() < 2:
		for p in pts:
			curve.add_point(p)
		return curve
	if pts.size() == 2:
		curve.add_point(pts[0])
		curve.add_point(pts[1])
		return curve
	var segs: Array = []
	var corners := _corners(pts, error)
	for k in corners.size() - 1:
		var a: int = corners[k]
		var b: int = corners[k + 1]
		if b - a < 1:
			continue
		var sub := pts.slice(a, b + 1)
		if sub.size() == 2:
			var d := (sub[1] - sub[0]) / 3.0
			segs.append([sub[0], sub[0] + d, sub[1] - d, sub[1]])
			continue
		var t1 := _left_tangent(sub)
		var t2 := _right_tangent(sub)
		_fit_cubic(sub, 0, sub.size() - 1, t1, t2, error, segs)
	if segs.is_empty():
		curve.add_point(pts[0])
		curve.add_point(pts[pts.size() - 1])
		return curve
	# Segmentos → Curve2D (manejadores relativos)
	curve.add_point(segs[0][0], Vector2.ZERO, segs[0][1] - segs[0][0])
	for i in segs.size():
		var s: Array = segs[i]
		var out: Vector2 = Vector2.ZERO
		if i + 1 < segs.size():
			out = segs[i + 1][1] - segs[i + 1][0]
		curve.add_point(s[3], s[2] - s[3], out)
	return curve

static func _dedupe(points: PackedVector2Array, eps: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > eps:
			out.append(p)
	return out

## Índices de esquina (incluye el primero y el último): giro mayor que
## CORNER_DEG medido entre tramos de longitud ~ 3·error (ignora el temblor).
static func _corners(pts: PackedVector2Array, error: float) -> PackedInt32Array:
	var out := PackedInt32Array([0])
	var n := pts.size()
	var span := maxf(error * 3.0, 1.0)
	var cos_lim := cos(deg_to_rad(CORNER_DEG))
	var i := 1
	while i < n - 1:
		var a := _walk(pts, i, -1, span)
		var b := _walk(pts, i, 1, span)
		if a >= 0 and b >= 0:
			var v0 := (pts[i] - pts[a]).normalized()
			var v1 := (pts[b] - pts[i]).normalized()
			if v0.dot(v1) < cos_lim and i - out[out.size() - 1] >= 2:
				out.append(i)
				i += 2
				continue
		i += 1
	out.append(n - 1)
	return out

## Índice a distancia >= span desde i en la dirección dir (-1 si no hay).
static func _walk(pts: PackedVector2Array, i: int, dir: int, span: float) -> int:
	var j := i
	var acc := 0.0
	while true:
		var nj := j + dir
		if nj < 0 or nj >= pts.size():
			return -1
		acc += pts[nj].distance_to(pts[j])
		j = nj
		if acc >= span:
			return j
	return -1

static func _left_tangent(p: PackedVector2Array) -> Vector2:
	return _tangent_from(p, 0, 1)

static func _right_tangent(p: PackedVector2Array) -> Vector2:
	return _tangent_from(p, p.size() - 1, -1)

## Tangente de un extremo promediando unos cuantos puntos (más estable que
## usar solo el vecino, que lleva el temblor del arranque).
static func _tangent_from(p: PackedVector2Array, i: int, dir: int) -> Vector2:
	var acc := Vector2.ZERO
	var k := 1
	while k <= 3 and i + dir * k >= 0 and i + dir * k < p.size():
		acc += (p[i + dir * k] - p[i]).normalized() / float(k)
		k += 1
	return acc.normalized() if acc.length_squared() > 1e-12 else (p[i + dir] - p[i]).normalized()

static func _fit_cubic(p: PackedVector2Array, first: int, last: int, t1: Vector2, t2: Vector2,
		error: float, out: Array) -> void:
	if last - first == 1:
		var dist := p[first].distance_to(p[last]) / 3.0
		out.append([p[first], p[first] + t1 * dist, p[last] + t2 * dist, p[last]])
		return
	var u := _chord_params(p, first, last)
	var bez := _generate(p, first, last, u, t1, t2)
	var res := _max_error(p, first, last, bez, u)
	if res[0] < error * error:
		out.append(bez)
		return
	if res[0] < error * error * 16.0:
		for it in MAX_ITER:
			u = _reparam(p, first, last, u, bez)
			bez = _generate(p, first, last, u, t1, t2)
			res = _max_error(p, first, last, bez, u)
			if res[0] < error * error:
				out.append(bez)
				return
	var split: int = res[1]
	var tc := _center_tangent(p, split)
	_fit_cubic(p, first, split, t1, tc, error, out)
	_fit_cubic(p, split, last, -tc, t2, error, out)

static func _center_tangent(p: PackedVector2Array, i: int) -> Vector2:
	var v := p[i - 1] - p[i + 1]
	return v.normalized() if v.length_squared() > 1e-12 else Vector2.RIGHT

static func _chord_params(p: PackedVector2Array, first: int, last: int) -> PackedFloat32Array:
	var u := PackedFloat32Array()
	u.resize(last - first + 1)
	u[0] = 0.0
	for i in range(first + 1, last + 1):
		u[i - first] = u[i - first - 1] + p[i].distance_to(p[i - 1])
	var total := maxf(u[u.size() - 1], 0.000001)
	for i in u.size():
		u[i] /= total
	return u

## Cúbica de mínimos cuadrados con las tangentes de los extremos fijas.
static func _generate(p: PackedVector2Array, first: int, last: int, u: PackedFloat32Array,
		t1: Vector2, t2: Vector2) -> Array:
	var c00 := 0.0
	var c01 := 0.0
	var c11 := 0.0
	var x0 := 0.0
	var x1 := 0.0
	var p0 := p[first]
	var p3 := p[last]
	for i in u.size():
		var t := u[i]
		var mt := 1.0 - t
		var b0 := mt * mt * mt
		var b1 := 3.0 * t * mt * mt
		var b2 := 3.0 * t * t * mt
		var b3 := t * t * t
		var a1 := t1 * b1
		var a2 := t2 * b2
		c00 += a1.dot(a1)
		c01 += a1.dot(a2)
		c11 += a2.dot(a2)
		var tmp := p[first + i] - (p0 * (b0 + b1) + p3 * (b2 + b3))
		x0 += a1.dot(tmp)
		x1 += a2.dot(tmp)
	var det := c00 * c11 - c01 * c01
	var alpha_l := 0.0
	var alpha_r := 0.0
	if absf(det) > 1e-12:
		alpha_l = (x0 * c11 - x1 * c01) / det
		alpha_r = (c00 * x1 - c01 * x0) / det
	var seg_len := p0.distance_to(p3)
	var eps := 1e-6 * seg_len
	# Manejadores negativos, nulos o MÁS LARGOS que la cuerda: la solución de
	# mínimos cuadrados se ha ido (con ruido pasa) y la cúbica haría un bucle.
	if alpha_l < eps or alpha_r < eps or alpha_l > seg_len or alpha_r > seg_len:
		# Caída heurística (Wu/Barsky): un tercio de la cuerda
		var d := seg_len / 3.0
		return [p0, p0 + t1 * d, p3 + t2 * d, p3]
	return [p0, p0 + t1 * alpha_l, p3 + t2 * alpha_r, p3]

static func _bez(b: Array, t: float) -> Vector2:
	var mt := 1.0 - t
	return b[0] * (mt * mt * mt) + b[1] * (3.0 * mt * mt * t) + b[2] * (3.0 * mt * t * t) + b[3] * (t * t * t)

## [error² máximo, índice del punto peor]
static func _max_error(p: PackedVector2Array, first: int, last: int, b: Array, u: PackedFloat32Array) -> Array:
	var max_d := 0.0
	var idx := (last - first + 1) / 2 + first
	for i in range(first + 1, last):
		var d := _bez(b, u[i - first]).distance_squared_to(p[i])
		if d >= max_d:
			max_d = d
			idx = i
	return [max_d, idx]

## Newton–Raphson: acerca cada parámetro u al punto más cercano de la curva.
static func _reparam(p: PackedVector2Array, first: int, last: int, u: PackedFloat32Array, b: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(u.size())
	var d1 := [(b[1] - b[0]) * 3.0, (b[2] - b[1]) * 3.0, (b[3] - b[2]) * 3.0]
	var d2 := [(d1[1] - d1[0]) * 2.0, (d1[2] - d1[1]) * 2.0]
	for i in u.size():
		var t := u[i]
		var q := _bez(b, t) - p[first + i]
		var mt := 1.0 - t
		var q1: Vector2 = d1[0] * (mt * mt) + d1[1] * (2.0 * mt * t) + d1[2] * (t * t)
		var q2: Vector2 = d2[0] * mt + d2[1] * t
		var num := q.dot(q1)
		var den := q1.dot(q1) + q.dot(q2)
		out[i] = clampf(t - num / den, 0.0, 1.0) if absf(den) > 1e-12 else t
	return out
