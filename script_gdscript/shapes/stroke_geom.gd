# =============================================================================
# RUTA: res://script_gdscript/shapes/stroke_geom.gd
# GEOMETRÍA PRECISA del trazo de un VectorPath, para TODOS los estilos, como
# una sola malla de triángulos:
#   · uniones en inglete (miter) con límite y unión REDONDA en los giros
#     cerrados (draw_polyline no unía los tramos: esquinas rotas / facetas);
#   · remates (plano / redondo / cuadrado) en cada línea: en cada guion del
#     discontinuo y en las DOS líneas del doble (antes el remate cuadrado del
#     doble era un bloque macizo que tapaba las dos);
#   · discontinuo y punteado con el patrón AJUSTADO para empezar y acabar en
#     guion / punto (las puntas de flecha siempre se apoyan en trazo);
#   · perfil de grosor (StrokeProfile) en el sólido.
# =============================================================================
extends RefCounted

const StrokeProfile = preload("res://script_gdscript/shapes/stroke_profile.gd")

const MITER_LIMIT := 4.0

## Puntos precisos de la curva: subdivisión adaptativa por ÁNGULO (se ve
## lisa a cualquier zoom), sin duplicados.
static func curve_points(curve: Curve2D) -> PackedVector2Array:
	var raw := curve.tessellate(7, 1.5)
	var out := PackedVector2Array()
	for p in raw:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > 1e-6:
			out.append(p)
	return out

## Tira de grosor variable (half = medio grosor por punto) con uniones y
## remates (0 plano, 1 redondo, 2 cuadrado). La usa el render del pincel.
static func strip_mesh(pts: PackedVector2Array, half: PackedFloat32Array, cap_s: int, cap_e: int) -> Dictionary:
	var m := {"points": PackedVector2Array(), "indices": PackedInt32Array()}
	if pts.size() >= 2:
		_strip(m, pts, half, false, cap_s, cap_e)
	elif pts.size() == 1 and half.size() > 0:
		_disc(m, pts[0], half[0])
	return m

## Estilos que tienen patrón (los campos guion / hueco tienen efecto).
const PATTERNED := [1, 2, 5, 6, 7, 8, 11, 12, 13, 14]
const STYLE_ORDER := [0, 1, 2, 5, 6, 7, 8, 13, 4, 9, 10, 11, 12, 14]
const STYLE_LABELS := {
	0: "Sólido", 1: "Discontinuo", 2: "Punteado", 4: "Doble", 5: "Guion y punto",
	6: "Guion y dos puntos", 7: "Guiones largos", 8: "Guiones cortos", 9: "Triple",
	10: "Grueso y fino", 11: "Ondulado", 12: "Zigzag", 13: "Puntos cuadrados", 14: "Vía",
}

## Patrón de encendido/apagado: [on, off, on, off…]; on = 0 es un punto
## redondo de diámetro = grosor. Se escala para acabar en tramo completo.
static func _pattern(m: Dictionary, pts: PackedVector2Array, closed: bool, pat: Array,
		width: float, cap_s: int, cap_e: int) -> void:
	var cum := _cumulative(pts)
	var total := cum[cum.size() - 1]
	if total <= 0.0:
		return
	# Un punto (on = 0) ocupa su diámetro (= grosor): si no, con huecos más
	# pequeños que el grosor los puntos se comían a los guiones.
	var real: Array = []
	for j in pat.size():
		var v := float(pat[j])
		real.append(width if (j % 2 == 0 and v <= 0.0) else v)
	var period := 0.0
	for v in real:
		period += float(v)
	var last_off := float(pat[pat.size() - 1])
	var k := 1.0
	if closed:
		k = total / (maxf(1.0, roundf(total / period)) * period)
	else:
		k = (total + last_off) / (maxf(1.0, roundf((total + last_off) / period)) * period)
	var s := 0.0
	var i := 0
	var first := true
	while s < total - 0.001:
		var is_dot := float(pat[i % pat.size()]) <= 0.0
		var on := float(real[i % real.size()]) * k
		var off := float(real[(i + 1) % real.size()]) * k
		if is_dot:
			_disc(m, point_at(pts, cum, minf(s + on * 0.5, total)), width * 0.5)
		else:
			var e := minf(s + on, total)
			var d := sub_path(pts, cum, s, e)
			_strip(m, d, _const_half(d.size(), width * 0.5), false, cap_s if first else cap_e, cap_e)
		first = false
		s += on + off
		i += 2

## Varias líneas paralelas: [[grosor relativo, desplazamiento relativo]…]
## (respecto al grosor total; el borde exterior coincide con él).
static func _lines(m: Dictionary, pts: PackedVector2Array, closed: bool, spec: Array,
		width: float, cap_s: int, cap_e: int) -> void:
	for l in spec:
		var sub := maxf(1.0, width * float(l[0]))
		var o := offset_line(pts, width * float(l[1]), closed) if not is_zero_approx(float(l[1])) else pts
		_strip(m, o, _const_half(o.size(), sub * 0.5), closed, cap_s, cap_e)

## Onda (seno) o zigzag que ocupa el grosor del trazo, con un número entero
## de ciclos (acaba en el eje).
static func _wave(m: Dictionary, pts: PackedVector2Array, closed: bool, width: float,
		wavelength: float, zigzag: bool) -> void:
	var cum := _cumulative(pts)
	var total := cum[cum.size() - 1]
	if total <= 0.0:
		return
	var line_w := maxf(1.0, width * 0.2)
	var amp := maxf(0.0, width * 0.5 - line_w * 0.5)
	var cycles := maxf(1.0, roundf(total / wavelength))
	var steps := int(cycles) * (2 if zigzag else 24)
	var out := PackedVector2Array()
	for k in steps + 1:
		var d := total * float(k) / float(steps)
		var p := point_at(pts, cum, d)
		var p2 := point_at(pts, cum, minf(d + 0.5, total))
		var p1 := point_at(pts, cum, maxf(d - 0.5, 0.0))
		var t := (p2 - p1).normalized()
		var nrm := Vector2(-t.y, t.x)
		var ph := d / total * cycles
		var y := 0.0
		if zigzag:
			if k > 0 and k < steps:
				y = 1.0 if k % 2 == 1 else -1.0
		else:
			y = sin(ph * TAU)
		out.append(p + nrm * amp * y)
	_strip(m, out, _const_half(out.size(), line_w * 0.5), false, 1, 1)

## Vía: línea central fina + traviesas perpendiculares repartidas.
static func _rail(m: Dictionary, pts: PackedVector2Array, closed: bool, width: float, spacing: float) -> void:
	var line_w := maxf(1.0, width * 0.18)
	_strip(m, pts, _const_half(pts.size(), line_w * 0.5), closed, 0, 0)
	var cum := _cumulative(pts)
	var total := cum[cum.size() - 1]
	var n := maxi(1, int(roundf(total / spacing)))
	for k in (n if closed else n + 1):
		var d := total * float(k) / float(n)
		var p := point_at(pts, cum, d)
		var t := (point_at(pts, cum, minf(d + 0.5, total)) - point_at(pts, cum, maxf(d - 0.5, 0.0))).normalized()
		var nrm := Vector2(-t.y, t.x) * width * 0.5
		var tick := PackedVector2Array([p - nrm, p + nrm])
		_strip(m, tick, _const_half(2, line_w * 0.5), false, 0, 0)

## Quita los micro-tramos (más cortos que `tol`) y los "picos" que vuelven
## hacia atrás. Un clic con un temblor del ratón deja manejadores de 2–3 px
## en una esquina: la curva hace ahí un bucle diminuto que, al engordarlo,
## doblaba el trazo sobre sí mismo (manchas, cortes y líneas cruzadas).
## Todo lo que se quita queda por debajo del propio grosor del trazo.
static func clean(pts: PackedVector2Array, tol: float, closed: bool) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, n - 1):
		# Junto a los extremos, el doble de margen: un manejador diminuto ahí
		# torcía el arranque del trazo (un "gancho").
		var t := tol * 2.0 if (pts[i].distance_to(pts[0]) < tol * 2.0 or pts[i].distance_to(pts[n - 1]) < tol * 2.0) else tol
		if pts[i].distance_to(out[out.size() - 1]) >= t:
			out.append(pts[i])
	var last := pts[n - 1]
	if out.size() > 1 and out[out.size() - 1].distance_to(last) < tol:
		out[out.size() - 1] = last   # el extremo real manda
	else:
		out.append(last)
	# Picos: un vértice cuyo tramo de llegada y de salida casi se oponen
	# (giro > ~170°) con algún tramo corto respecto a la tolerancia.
	var changed := true
	while changed and out.size() >= 3:
		changed = false
		for i in range(1, out.size() - 1):
			var a := out[i] - out[i - 1]
			var b := out[i + 1] - out[i]
			if a.length() < tol * 3.0 or b.length() < tol * 3.0:
				if a.normalized().dot(b.normalized()) < -0.985:
					out.remove_at(i)
					changed = true
					break
	return out

## Grosor de cada línea del estilo doble y su separación al centro (el borde
## exterior de las dos coincide con el grosor total del trazo).
static func double_metrics(width: float) -> Vector2:
	var sub := maxf(1.0, width * 0.3)
	return Vector2(sub, width * 0.35)

## Malla del trazo. style: 0 sólido, 1 discontinuo, 2 punteado, 4 doble
## (3 = perfil "afilado" antiguo, lo resuelve quien llama pasándolo en profile).
static func build(pts: PackedVector2Array, closed: bool, style: int, width: float,
		cap_start: int, cap_end: int, profile: PackedVector2Array,
		dash: float, gap: float) -> Dictionary:
	var m := {"points": PackedVector2Array(), "indices": PackedInt32Array()}
	if pts.size() < 2 or width <= 0.0:
		return m
	pts = clean(pts, clampf(width * 0.15, 0.5, 6.0), closed)
	if pts.size() < 2:
		return m
	if closed:
		cap_start = 0
		cap_end = 0
	dash = maxf(dash, 0.5)
	gap = maxf(gap, 0.5)
	match style:
		1:
			_pattern(m, pts, closed, [dash, gap], width, cap_start, cap_end)
		2:
			for c in dots(pts, closed, width, gap):
				_disc(m, c, width * 0.5)
		4:
			_lines(m, pts, closed, [[0.3, 0.35], [0.3, -0.35]], width, cap_start, cap_end)
		5:   # guion-punto
			_pattern(m, pts, closed, [dash, gap, 0.0, gap], width, cap_start, cap_end)
		6:   # guion-punto-punto
			_pattern(m, pts, closed, [dash, gap, 0.0, gap, 0.0, gap], width, cap_start, cap_end)
		7:   # guiones largos
			_pattern(m, pts, closed, [dash * 2.5, gap], width, cap_start, cap_end)
		8:   # guiones cortos
			_pattern(m, pts, closed, [maxf(width, dash * 0.35), gap * 0.6], width, cap_start, cap_end)
		9:   # triple
			_lines(m, pts, closed, [[0.2, 0.4], [0.2, 0.0], [0.2, -0.4]], width, cap_start, cap_end)
		10:  # grueso + fino
			_lines(m, pts, closed, [[0.55, 0.225], [0.15, -0.425]], width, cap_start, cap_end)
		11:  # ondulado
			_wave(m, pts, closed, width, maxf(dash, width * 1.5), false)
		12:  # zigzag
			_wave(m, pts, closed, width, maxf(dash, width * 1.2), true)
		13:  # puntos cuadrados (tramos de largo = grosor, remate plano)
			_pattern(m, pts, closed, [width, gap], width, 0, 0)
		14:  # vía (línea fina con traviesas)
			_rail(m, pts, closed, width, maxf(dash, width * 0.8))
		_:
			var half := PackedFloat32Array()
			half.resize(pts.size())
			if StrokeProfile.is_uniform(profile):
				half.fill(width * 0.5)
			else:
				var cum := _cumulative(pts)
				var total := maxf(cum[cum.size() - 1], 0.0001)
				for i in pts.size():
					half[i] = width * 0.5 * StrokeProfile.sample(profile, cum[i] / total)
			_strip(m, pts, half, closed, cap_start, cap_end)
	return m

# ── tira con uniones y remates ───────────────────────────────────────────────
static func _const_half(n: int, h: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(h)
	return a

static func _strip(m: Dictionary, pts_in: PackedVector2Array, half_in: PackedFloat32Array,
		closed: bool, cap_s: int, cap_e: int) -> void:
	var pts := pts_in.duplicate()
	var half := half_in.duplicate()
	var n := pts.size()
	if n < 2:
		return
	if closed and pts[0].distance_squared_to(pts[n - 1]) < 1e-6:
		pts.remove_at(n - 1)
		half.remove_at(n - 1)
		n -= 1
	if n < 2:
		return
	# Remate cuadrado: se alarga el extremo medio grosor.
	if not closed:
		if cap_s == 2:
			pts[0] = pts[0] + (pts[0] - pts[1]).normalized() * half[0]
		if cap_e == 2:
			pts[n - 1] = pts[n - 1] + (pts[n - 1] - pts[n - 2]).normalized() * half[n - 1]
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var base := verts.size()
	var joins: Array = []   # uniones redondas (se añaden al final)
	var count := n + (1 if closed else 0)
	for k in count:
		var i := k % n
		var has_prev := closed or i > 0
		var has_next := closed or i < n - 1
		var d0 := (pts[i] - pts[(i - 1 + n) % n]).normalized() if has_prev else Vector2.ZERO
		var d1 := (pts[(i + 1) % n] - pts[i]).normalized() if has_next else Vector2.ZERO
		if d0 == Vector2.ZERO:
			d0 = d1
		if d1 == Vector2.ZERO:
			d1 = d0
		var n0 := Vector2(-d0.y, d0.x)
		var n1 := Vector2(-d1.y, d1.x)
		var mdir := (n0 + n1)
		var off: Vector2
		var h := half[i]
		if mdir.length_squared() < 1e-8:
			off = n1 * h   # vuelta de 180°
			joins.append([pts[i], h])
		else:
			mdir = mdir.normalized()
			var denom := mdir.dot(n1)
			var mlen := h / maxf(denom, 0.0001)
			if mlen > h * MITER_LIMIT:
				# Giro muy cerrado: unión redonda (sin pico infinito ni hueco).
				off = mdir * h
				joins.append([pts[i], h])
			else:
				off = mdir * mlen
		verts.append(pts[i] + off)
		verts.append(pts[i] - off)
	for k in count - 1:
		var a := base + k * 2
		idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	m["points"] = verts
	m["indices"] = idx
	for j in joins:
		_disc(m, j[0], j[1])
	if not closed:
		if cap_s == 1:
			_fan(m, pts[0], pts[0] - pts[1], half[0])
		if cap_e == 1:
			_fan(m, pts[n - 1], pts[n - 1] - pts[n - 2], half[n - 1])

static func _fan(m: Dictionary, c: Vector2, dir: Vector2, r: float) -> void:
	if r < 0.01 or dir.length_squared() < 1e-12:
		return
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var a0 := dir.normalized().angle() - PI * 0.5
	var segs := clampi(int(r * 0.8) + 8, 8, 48)
	var ci := verts.size()
	verts.append(c)
	for k in segs + 1:
		var a := a0 + PI * float(k) / float(segs)
		verts.append(c + Vector2(cos(a), sin(a)) * r)
	for k in segs:
		idx.append_array([ci, ci + 1 + k, ci + 2 + k])
	m["points"] = verts
	m["indices"] = idx

static func _disc(m: Dictionary, c: Vector2, r: float) -> void:
	if r < 0.01:
		return
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var segs := clampi(int(r * 1.2) + 10, 10, 64)
	var ci := verts.size()
	verts.append(c)
	for k in segs:
		var a := TAU * float(k) / float(segs)
		verts.append(c + Vector2(cos(a), sin(a)) * r)
	for k in segs:
		idx.append_array([ci, ci + 1 + k, ci + 1 + (k + 1) % segs])
	m["points"] = verts
	m["indices"] = idx

# ── desplazamiento, guiones, puntos ──────────────────────────────────────────
## Polilínea paralela a `d` (con inglete, para que las dos líneas del doble
## mantengan la distancia exacta en las curvas).
static func offset_line(pts: PackedVector2Array, d: float, closed: bool) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var has_prev := closed or i > 0
		var has_next := closed or i < n - 1
		var d0 := (pts[i] - pts[(i - 1 + n) % n]).normalized() if has_prev else Vector2.ZERO
		var d1 := (pts[(i + 1) % n] - pts[i]).normalized() if has_next else Vector2.ZERO
		if d0 == Vector2.ZERO:
			d0 = d1
		if d1 == Vector2.ZERO:
			d1 = d0
		var mdir := Vector2(-d0.y, d0.x) + Vector2(-d1.y, d1.x)
		if mdir.length_squared() < 1e-8:
			out.append(pts[i] + Vector2(-d1.y, d1.x) * d)
			continue
		mdir = mdir.normalized()
		var denom := maxf(mdir.dot(Vector2(-d1.y, d1.x)), 1.0 / MITER_LIMIT)
		out.append(pts[i] + mdir * (d / denom))
	return _remove_offset_loops(pts, out, closed)

## En el lado interior de un giro cerrado, los tramos cortos de la paralela
## salen INVERTIDOS respecto al original (un bucle): se funden sus extremos
## en el punto medio hasta que ningún tramo vaya al revés.
static func _remove_offset_loops(src: PackedVector2Array, off: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var a := src.duplicate()
	var b := off.duplicate()
	var guard := 0
	var changed := true
	while changed and b.size() >= 3 and guard < 512:
		changed = false
		guard += 1
		var segs := b.size() - 1
		for i in segs:
			if (closed and (i == 0 or i == segs - 1)):
				continue
			var so := a[i + 1] - a[i]
			var sb := b[i + 1] - b[i]
			if so.dot(sb) < 0.0:
				var mid := (b[i] + b[i + 1]) * 0.5
				b[i] = mid
				b.remove_at(i + 1)
				a.remove_at(i + 1)
				changed = true
				break
	return b

static func _cumulative(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	return cum

static func length(pts: PackedVector2Array) -> float:
	var c := _cumulative(pts)
	return c[c.size() - 1] if c.size() > 0 else 0.0

## Tramo de la polilínea entre las distancias a y b (con sus vértices).
static func sub_path(pts: PackedVector2Array, cum: PackedFloat32Array, a: float, b: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(point_at(pts, cum, a))
	for i in pts.size():
		if cum[i] > a and cum[i] < b:
			out.append(pts[i])
	out.append(point_at(pts, cum, b))
	return out

static func point_at(pts: PackedVector2Array, cum: PackedFloat32Array, d: float) -> Vector2:
	var n := pts.size()
	if d <= 0.0:
		return pts[0]
	if d >= cum[n - 1]:
		return pts[n - 1]
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg := maxf(cum[hi] - cum[lo], 0.000001)
	return pts[lo].lerp(pts[hi], (d - cum[lo]) / seg)

## Guiones con el patrón escalado para que el trazo empiece y acabe con guion
## completo (abierto) o cierre sin costura (cerrado).
static func dashes(pts: PackedVector2Array, closed: bool, dash: float, gap: float) -> Array:
	var cum := _cumulative(pts)
	var total := cum[cum.size() - 1]
	var out: Array = []
	if total <= 0.0:
		return out
	var period := dash + gap
	var k := 1.0
	if closed:
		var nper := maxf(1.0, roundf(total / period))
		k = total / (nper * period)
	else:
		var nd := maxf(1.0, roundf((total + gap) / period))
		k = (total + gap) / (nd * period)
	var dl := dash * k
	var gl := gap * k
	var s := 0.0
	while s < total - 0.001:
		var e := minf(s + dl, total)
		out.append({"pts": sub_path(pts, cum, s, e), "first": is_zero_approx(s)})
		s = e + gl
	return out

## Centros de los puntos, repartidos para que haya uno en cada extremo.
static func dots(pts: PackedVector2Array, closed: bool, width: float, gap: float) -> PackedVector2Array:
	var cum := _cumulative(pts)
	var total := cum[cum.size() - 1]
	var out := PackedVector2Array()
	var spacing := maxf(gap + width, width * 1.6)
	var n := maxi(1, int(roundf(total / spacing)))
	var count := n if closed else n + 1
	for k in count:
		out.append(point_at(pts, cum, total * float(k) / float(n)))
	return out
