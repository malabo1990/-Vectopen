# =============================================================================
# RUTA: res://script_gdscript/shapes/stroke_profile.gd
# PERFIL DE GROSOR de un trazo (como el perfil de presión de Affinity): una
# lista de puntos (t, w) con t = posición a lo largo del trazo (0..1) y
# w = grosor relativo (0..1). Vacío = grosor uniforme.
#
# · sample(): interpolación cúbica monótona (suave, sin "rebotes" por encima
#   ni por debajo de los puntos).
# · outline(): el trazo como TIRA DE TRIÁNGULOS de grosor variable (sin los
#   cortes en las uniones que dejaba el cónico dibujado por segmentos y sin
#   depender de triangular un polígono que se cruza).
# · to_curve(): el perfil como Curve para Line2D.width_curve (pincel).
# =============================================================================
extends RefCounted

## Preajustes (en el orden del panel). "ideal" = trazo de pluma: entra fino,
## engorda pronto, se mantiene y sale afilado.
const PRESETS := {
	"uniform": [],
	"ideal": [Vector2(0, 0.08), Vector2(0.18, 0.9), Vector2(0.55, 1.0), Vector2(1, 0.05)],
	"taper": [Vector2(0, 0.05), Vector2(0.5, 1.0), Vector2(1, 0.05)],
	"taper_start": [Vector2(0, 0.05), Vector2(0.4, 1.0), Vector2(1, 1.0)],
	"taper_end": [Vector2(0, 1.0), Vector2(0.6, 1.0), Vector2(1, 0.05)],
	"swell": [Vector2(0, 0.35), Vector2(0.5, 1.0), Vector2(1, 0.35)],
	"pinch": [Vector2(0, 1.0), Vector2(0.5, 0.25), Vector2(1, 1.0)],
	"drop": [Vector2(0, 0.6), Vector2(0.2, 1.0), Vector2(1, 0.04)],
}
const PRESET_LABELS := {
	"uniform": "Uniforme", "ideal": "Ideal (pluma)", "taper": "Afilado",
	"taper_start": "Afilado inicio", "taper_end": "Afilado fin", "swell": "Engordado",
	"pinch": "Estrecho", "drop": "Gota",
}

## Normaliza a PackedVector2Array ordenado por t, con t en [0,1] y w en [0,1].
static func normalize(profile) -> PackedVector2Array:
	var out := PackedVector2Array()
	if profile is PackedVector2Array or profile is Array:
		for p in profile:
			if p is Vector2:
				out.append(Vector2(clampf(p.x, 0.0, 1.0), clampf(p.y, 0.0, 1.0)))
			elif p is Array and (p as Array).size() >= 2:
				out.append(Vector2(clampf(float(p[0]), 0.0, 1.0), clampf(float(p[1]), 0.0, 1.0)))
	var arr := Array(out)
	arr.sort_custom(func(a, b): return a.x < b.x)
	return PackedVector2Array(arr)

static func is_uniform(profile) -> bool:
	return normalize(profile).size() < 2

static func preset(name: String) -> PackedVector2Array:
	return normalize(PRESETS.get(name, []))

## Nombre del preajuste que coincide con el perfil ("" si es personalizado).
static func preset_name(profile) -> String:
	var p := normalize(profile)
	for k in PRESETS:
		var q := preset(k)
		if q.size() != p.size():
			continue
		var same := true
		for i in q.size():
			if not q[i].is_equal_approx(p[i]):
				same = false
				break
		if same:
			return k
	return ""

## Grosor relativo en t (0..1). Hermite monótono (Fritsch–Carlson).
static func sample(profile: PackedVector2Array, t: float) -> float:
	var n := profile.size()
	if n == 0:
		return 1.0
	if n == 1 or t <= profile[0].x:
		return profile[0].y
	if t >= profile[n - 1].x:
		return profile[n - 1].y
	var i := 0
	while i < n - 2 and t > profile[i + 1].x:
		i += 1
	var p0 := profile[i]
	var p1 := profile[i + 1]
	var h := maxf(p1.x - p0.x, 0.00001)
	var m0 := _slope(profile, i)
	var m1 := _slope(profile, i + 1)
	var s := (t - p0.x) / h
	var s2 := s * s
	var s3 := s2 * s
	var y := (2 * s3 - 3 * s2 + 1) * p0.y + (s3 - 2 * s2 + s) * h * m0 \
		+ (-2 * s3 + 3 * s2) * p1.y + (s3 - s2) * h * m1
	return clampf(y, 0.0, 1.0)

static func _slope(p: PackedVector2Array, i: int) -> float:
	var n := p.size()
	var d_prev := 0.0
	var d_next := 0.0
	if i > 0:
		d_prev = (p[i].y - p[i - 1].y) / maxf(p[i].x - p[i - 1].x, 0.00001)
	if i < n - 1:
		d_next = (p[i + 1].y - p[i].y) / maxf(p[i + 1].x - p[i].x, 0.00001)
	if i == 0:
		return d_next
	if i == n - 1:
		return d_prev
	if d_prev * d_next <= 0.0:
		return 0.0   # extremo local: plano (monótono)
	return 2.0 / (1.0 / d_prev + 1.0 / d_next)

## Tira de triángulos del trazo de grosor variable. Devuelve
## {"points": PackedVector2Array, "indices": PackedInt32Array}.
static func outline(pts: PackedVector2Array, width: float, profile: PackedVector2Array,
		round_start: bool = true, round_end: bool = true) -> Dictionary:
	var verts := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := pts.size()
	if n < 2 or width <= 0.0:
		return {"points": verts, "indices": idx}
	var cum := PackedFloat32Array()
	cum.resize(n)
	cum[0] = 0.0
	for i in range(1, n):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	var total := maxf(cum[n - 1], 0.0001)
	var half := PackedFloat32Array()
	half.resize(n)
	for i in n:
		half[i] = width * 0.5 * sample(profile, cum[i] / total)
	for i in n:
		var tan: Vector2
		if i == 0:
			tan = pts[1] - pts[0]
		elif i == n - 1:
			tan = pts[n - 1] - pts[n - 2]
		else:
			tan = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
		if tan.length_squared() < 1e-12:
			tan = Vector2.RIGHT
		tan = tan.normalized()
		var nrm := Vector2(-tan.y, tan.x)
		verts.append(pts[i] + nrm * half[i])
		verts.append(pts[i] - nrm * half[i])
	for i in n - 1:
		var a := i * 2
		idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	if round_start:
		_fan(verts, idx, pts[0], pts[0] - pts[1], half[0])
	if round_end:
		_fan(verts, idx, pts[n - 1], pts[n - 1] - pts[n - 2], half[n - 1])
	return {"points": verts, "indices": idx}

## Semicírculo de remate redondo hacia `dir`.
static func _fan(verts: PackedVector2Array, idx: PackedInt32Array, c: Vector2, dir: Vector2, r: float) -> void:
	if r < 0.05 or dir.length_squared() < 1e-12:
		return
	var base := dir.normalized().angle()
	var ci := verts.size()
	verts.append(c)
	var segs := clampi(int(r * 0.6) + 6, 6, 24)
	for k in segs + 1:
		var a := base - PI * 0.5 + PI * float(k) / float(segs)
		verts.append(c + Vector2(cos(a), sin(a)) * r)
	for k in segs:
		idx.append_array([ci, ci + 1 + k, ci + 2 + k])

## Perfil → Curve (Line2D.width_curve). null = uniforme.
static func to_curve(profile) -> Curve:
	var p := normalize(profile)
	if p.size() < 2:
		return null
	var c := Curve.new()
	c.bake_resolution = 256
	for k in 65:
		var t := float(k) / 64.0
		c.add_point(Vector2(t, sample(p, t)))
	return c

## Miniatura: silueta del perfil centrada en `r`.
static func draw_thumbnail(ci: CanvasItem, r: Rect2, profile, col: Color) -> void:
	var p := normalize(profile)
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var steps := 40
	for k in steps + 1:
		var t := float(k) / float(steps)
		var w := sample(p, t) * r.size.y * 0.5
		var x := r.position.x + t * r.size.x
		top.append(Vector2(x, r.get_center().y - w))
		bottom.append(Vector2(x, r.get_center().y + w))
	bottom.reverse()
	var poly := top + bottom
	if Geometry2D.triangulate_polygon(poly).is_empty():
		ci.draw_polyline(top, col, 1.0, true)
	else:
		ci.draw_colored_polygon(poly, col)
