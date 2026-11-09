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
#   · UNIONES elegibles (UX-08): inglete (con límite; si lo supera, bisel,
#     como SVG/PDF), redonda o bisel. El pincel conserva su malla de siempre.
# =============================================================================
extends RefCounted

const StrokeProfile = preload("res://script_gdscript/shapes/stroke_profile.gd")

const MITER_LIMIT := 4.0

## Uniones entre tramos (stroke_join).
const JOIN_MITER := 0
const JOIN_ROUND := 1
const JOIN_BEVEL := 2
const JOIN_LABELS := {0: "Inglete", 1: "Redonda", 2: "Bisel"}
const MITER_LIMIT_MIN := 1.0
const MITER_LIMIT_MAX := 50.0

## Puntos precisos de la curva: subdivisión adaptativa por ÁNGULO (se ve
## lisa a cualquier zoom), sin duplicados.
static func curve_points(curve: Curve2D) -> PackedVector2Array:
	var c := _clean_curve(curve)
	var raw: PackedVector2Array
	if _has_straight(c):
		raw = _tess_mixed(c)
	else:
		raw = c.tessellate(7, 1.5)
	var out := PackedVector2Array()
	for p in raw:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > 1e-6:
			out.append(p)
	return out

## ¿Algún tramo recto (sin tiradores)?
static func _has_straight(c: Curve2D) -> bool:
	for i in range(c.point_count - 1):
		if c.get_point_out(i) == Vector2.ZERO and c.get_point_in(i + 1) == Vector2.ZERO:
			return true
	return false

static var _seg := Curve2D.new()

## Tramos rectos: sus dos extremos, sin pasar por Curve2D.tessellate (con
## tramos diminutos y coordenadas grandes, la precisión de Godot simula giros
## y metía hasta 64 puntos en cada recta: un contorno importado de 275 nodos
## salía con 17 000 puntos y abrir el archivo tardaba 25 s). Curvos: cada uno
## subdividido por ángulo como siempre.
static func _tess_mixed(c: Curve2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := c.point_count
	if n == 0:
		return out
	out.append(c.get_point_position(0))
	for i in range(n - 1):
		var a := c.get_point_position(i)
		var b := c.get_point_position(i + 1)
		var o := c.get_point_out(i)
		var inn := c.get_point_in(i + 1)
		if o == Vector2.ZERO and inn == Vector2.ZERO:
			out.append(b)
			continue
		_seg.clear_points()
		_seg.add_point(a, Vector2.ZERO, o)
		_seg.add_point(b, inn, Vector2.ZERO)
		var sub := _seg.tessellate(7, 1.5)
		for k in range(1, sub.size()):
			out.append(sub[k])
	return out

## Sin tramos de longitud CERO (nodo repetido sin tiradores): Godot los
## subdivide al máximo (128 puntos cada uno) y un contorno importado de 275
## nodos se convertía en 17 000 puntos (abrir un archivo tardaba 25 s).
static func _clean_curve(c: Curve2D) -> Curve2D:
	var n := c.point_count
	var dup := false
	for i in range(1, n):
		if c.get_point_position(i).distance_squared_to(c.get_point_position(i - 1)) < 1e-8 \
				and c.get_point_out(i - 1) == Vector2.ZERO and c.get_point_in(i) == Vector2.ZERO:
			dup = true
			break
	if not dup:
		return c
	var out := Curve2D.new()
	for i in n:
		var p := c.get_point_position(i)
		if out.point_count > 0 and p.distance_squared_to(out.get_point_position(out.point_count - 1)) < 1e-8 \
				and out.get_point_out(out.point_count - 1) == Vector2.ZERO and c.get_point_in(i) == Vector2.ZERO:
			out.set_point_out(out.point_count - 1, c.get_point_out(i))
			continue
		out.add_point(p, c.get_point_in(i), c.get_point_out(i))
	return out

## Tira de grosor variable (half = medio grosor por punto) con uniones y
## remates (0 plano, 1 redondo, 2 cuadrado). La usa el render del pincel.
## m["v"]: coordenada ATRAVÉS del trazo por vértice (borde = 0 ó 1, eje =
## 0,5; en uniones y remates, centro 0,5 y borde 1) — el sombreador la usa
## para el antialias del borde (1 px de pantalla a cualquier zoom).
## `joined`: uniones redondas SIN solapes (piezas que comparten arista con los
## tramos): imprescindible para los estilos con transparencia variable
## (aerógrafo, rotulador, lápiz), que si no marcan rayos en las curvas.
static func strip_mesh(pts: PackedVector2Array, half: PackedFloat32Array, cap_s: int, cap_e: int, joined := false) -> Dictionary:
	var m := {"points": PackedVector2Array(), "indices": PackedInt32Array(), "v": PackedFloat32Array()}
	if pts.size() >= 2:
		if joined:
			_halves(m, pts, half, cap_s, cap_e)
		else:
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
## Patrón de guiones del usuario: pares guion/hueco (impar → se repite
## para completarlo, como SVG). Vacío o inválido → [guion, hueco].
static func custom_pattern(p: PackedFloat32Array, dash: float, gap: float) -> Array:
	var out: Array = []
	for v in p:
		if v >= 0.0:
			out.append(maxf(v, 0.0))
	if out.size() % 2 == 1:
		out.append_array(out.duplicate())
	var total := 0.0
	for v in out:
		total += float(v)
	if out.size() < 2 or total <= 0.5:
		return [dash, gap]
	return out

## Texto «12 4 2 4» ↔ patrón.
static func parse_pattern(t: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part in t.replace(",", " ").split(" ", false):
		if part.is_valid_float() and float(part) >= 0.0:
			out.append(float(part))
	return out

static func pattern_text(p: PackedFloat32Array) -> String:
	var parts: Array[String] = []
	for v in p:
		parts.append(str(snappedf(v, 0.1)).trim_suffix(".0"))
	return " ".join(parts)

static func _pattern(m: Dictionary, pts: PackedVector2Array, closed: bool, pat: Array,
		width: float, cap_s: int, cap_e: int, jn: Array = [], offset: float = 0.0) -> void:
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
	# Desfase: el patrón empieza «antes» del inicio (se recorta a [0, total]).
	var s := -fposmod(offset * k, period * k) if absf(offset) > 0.0001 else 0.0
	var i := 0
	var first := true
	while s < total - 0.001:
		var is_dot := float(pat[i % pat.size()]) <= 0.0
		var on := float(real[i % real.size()]) * k
		var off := float(real[(i + 1) % real.size()]) * k
		if is_dot:
			var c := s + on * 0.5
			if c >= 0.0 and c <= total:
				_disc(m, point_at(pts, cum, c), width * 0.5)
		else:
			var a := maxf(s, 0.0)
			var e := minf(s + on, total)
			if e - a > 0.01:
				var d := sub_path(pts, cum, a, e)
				_strip(m, d, _const_half(d.size(), width * 0.5), false, cap_s if first else cap_e, cap_e, jn)
				first = false
		s += on + off
		i += 2

## Varias líneas paralelas: [[grosor relativo, desplazamiento relativo]…]
## (respecto al grosor total; el borde exterior coincide con él).
static func _lines(m: Dictionary, pts: PackedVector2Array, closed: bool, spec: Array,
		width: float, cap_s: int, cap_e: int, jn: Array = []) -> void:
	for l in spec:
		var sub := maxf(1.0, width * float(l[0]))
		var o := offset_line(pts, width * float(l[1]), closed) if not is_zero_approx(float(l[1])) else pts
		_strip(m, o, _const_half(o.size(), sub * 0.5), closed, cap_s, cap_e, jn)

## Onda (seno) o zigzag que ocupa el grosor del trazo, con un número entero
## de ciclos (acaba en el eje).
static func _wave(m: Dictionary, pts: PackedVector2Array, _closed: bool, width: float,
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
static func _rail(m: Dictionary, pts: PackedVector2Array, closed: bool, width: float, spacing: float, jn: Array = []) -> void:
	var line_w := maxf(1.0, width * 0.18)
	_strip(m, pts, _const_half(pts.size(), line_w * 0.5), closed, 0, 0, jn)
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

## Une el agujero `hole` al contorno `outer` por los vértices más cercanos
## (puente de ida y vuelta): un polígono simple que se puede triangular.
static func bridge(outer: PackedVector2Array, hole_in: PackedVector2Array) -> PackedVector2Array:
	# El agujero se recorre en sentido CONTRARIO al contorno: si no, el
	# polígono puenteado no se puede triangular (y no se dibujaba nada).
	var hole := hole_in
	if Geometry2D.is_polygon_clockwise(hole) == Geometry2D.is_polygon_clockwise(outer):
		hole = hole_in.duplicate()
		hole.reverse()
	var bi := 0
	var bj := 0
	var bd := INF
	for i in outer.size():
		@warning_ignore("integer_division")
		for j in range(0, hole.size(), maxi(1, hole.size() / 64)):
			var dd := outer[i].distance_squared_to(hole[j])
			if dd < bd:
				bd = dd
				bi = i
				bj = j
	var res := PackedVector2Array()
	for i in range(bi + 1):
		res.append(outer[i])
	for k in range(hole.size() + 1):
		res.append(hole[(bj + k) % hole.size()])
	for i in range(bi, outer.size()):
		res.append(outer[i])
	return res

## Anillos (polígonos cerrados) → polígonos simples rellenables con la regla
## PAR-IMPAR: profundidad de anidamiento par = relleno, impar = agujero.
static func evenodd_fill(rings: Array) -> Array:
	var n := rings.size()
	var depth := PackedInt32Array()
	depth.resize(n)
	for i in n:
		var r: PackedVector2Array = rings[i]
		if r.size() < 3:
			depth[i] = -1
			continue
		var d := 0
		for j in n:
			if i != j and (rings[j] as PackedVector2Array).size() >= 3 \
					and Geometry2D.is_point_in_polygon(r[0], rings[j]):
				d += 1
		depth[i] = d
	var out: Array = []
	for i in n:
		if depth[i] < 0 or depth[i] % 2 == 1:
			continue
		var poly: PackedVector2Array = rings[i]
		for j in n:
			if depth[j] == depth[i] + 1 and Geometry2D.is_point_in_polygon((rings[j] as PackedVector2Array)[0], rings[i]):
				poly = bridge(poly, rings[j])
		if not Geometry2D.triangulate_polygon(poly).is_empty():
			out.append(poly)
		else:
			out.append_array(Geometry2D.decompose_polygon_in_convex(poly))
	return out

## Quita los micro-tramos (más cortos que `tol`) y los "picos" que vuelven
## hacia atrás. Un clic con un temblor del ratón deja manejadores de 2–3 px
## en una esquina: la curva hace ahí un bucle diminuto que, al engordarlo,
## doblaba el trazo sobre sí mismo (manchas, cortes y líneas cruzadas).
## Todo lo que se quita queda por debajo del propio grosor del trazo.
static func clean(pts: PackedVector2Array, tol: float, _closed: bool) -> PackedVector2Array:
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

## Tolerancia de la limpieza: proporcional al grosor (los microbucles de un
## tirador diminuto quedan bajo el trazo), pero nunca más del 2 % del tamaño
## de la figura. Antes había un mínimo fijo de 0,5 y hasta 6 unidades: en una
## figura pequeña se comía los lados de la curva y, con mucho zoom, el borde
## salía poligonal y con escalones.
static func clean_tol(pts: PackedVector2Array, width: float) -> float:
	if pts.is_empty():
		return 0.0
	var mn := pts[0]
	var mx := pts[0]
	for q in pts:
		mn = mn.min(q)
		mx = mx.max(q)
	var diag := (mx - mn).length()
	return clampf(minf(width * 0.15, diag * 0.02), 0.0001, 6.0)

## Unidades del lienzo por PÍXEL de pantalla en el espacio de `ci` (zoom de
## la vista y escala del propio nodo). El grosor mínimo visible es 1 px de
## PANTALLA: antes era 1 unidad y, con mucho zoom, un trazo fino salía como
## una banda ancha transparente en vez de una línea fina.
static func screen_px(ci: CanvasItem) -> float:
	var vp := ci.get_viewport() if ci.is_inside_tree() else null
	var z: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	var sc := ci.get_global_transform().get_scale() if ci.is_inside_tree() else Vector2.ONE
	return 1.0 / maxf(z * maxf(absf(sc.x), absf(sc.y)), 1e-6)

const THIN_GROUP := "vo_thin_stroke"

## Grosor y color con los que se dibuja un trazo: por debajo de 1 px de
## pantalla se dibuja a 1 px atenuado (si no, se ve punteado o desaparece).
## Los trazos cerca de ese límite se apuntan a THIN_GROUP para redibujarse
## al cambiar el zoom (CullManager).
static func render_width(ci: CanvasItem, w: float, col: Color) -> Array:
	if w <= 0.0:
		return [w, col]
	var floor_w := screen_px(ci)
	if w < floor_w * 4.0:
		if not ci.is_in_group(THIN_GROUP):
			ci.add_to_group(THIN_GROUP)
	elif ci.is_in_group(THIN_GROUP):
		ci.remove_from_group(THIN_GROUP)
	if w < floor_w:
		var c := col
		c.a *= w / floor_w
		return [floor_w, c]
	return [w, col]

## Grosor de cada línea del estilo doble y su separación al centro (el borde
## exterior de las dos coincide con el grosor total del trazo).
static func double_metrics(width: float) -> Vector2:
	var sub := maxf(1.0, width * 0.3)
	return Vector2(sub, width * 0.35)

## Malla del trazo. style: 0 sólido, 1 discontinuo, 2 punteado, 4 doble
## (3 = perfil "afilado" antiguo, lo resuelve quien llama pasándolo en profile).
static func build(pts: PackedVector2Array, closed: bool, style: int, width: float,
		cap_start: int, cap_end: int, profile: PackedVector2Array,
		dash: float, gap: float, join: int = JOIN_MITER, miter_limit: float = MITER_LIMIT,
		dash_offset: float = 0.0, dash_pattern: PackedFloat32Array = PackedFloat32Array()) -> Dictionary:
	var m := {"points": PackedVector2Array(), "indices": PackedInt32Array()}
	if pts.size() < 2 or width <= 0.0:
		return m
	pts = clean(pts, clean_tol(pts, width), closed)
	if pts.size() < 2:
		return m
	if closed:
		cap_start = 0
		cap_end = 0
	dash = maxf(dash, 0.5)
	gap = maxf(gap, 0.5)
	var jn := [clampi(join, JOIN_MITER, JOIN_BEVEL), clampf(miter_limit, MITER_LIMIT_MIN, MITER_LIMIT_MAX)]
	match style:
		1:
			# UX-18: patrón personalizado (guion, hueco, guion, hueco…) y desfase.
			_pattern(m, pts, closed, custom_pattern(dash_pattern, dash, gap), width, cap_start, cap_end, jn, dash_offset)
		2:
			for c in dots(pts, closed, width, gap):
				_disc(m, c, width * 0.5)
		4:
			_lines(m, pts, closed, [[0.3, 0.35], [0.3, -0.35]], width, cap_start, cap_end, jn)
		5:   # guion-punto
			_pattern(m, pts, closed, [dash, gap, 0.0, gap], width, cap_start, cap_end, jn)
		6:   # guion-punto-punto
			_pattern(m, pts, closed, [dash, gap, 0.0, gap, 0.0, gap], width, cap_start, cap_end, jn)
		7:   # guiones largos
			_pattern(m, pts, closed, [dash * 2.5, gap], width, cap_start, cap_end, jn)
		8:   # guiones cortos
			_pattern(m, pts, closed, [maxf(width, dash * 0.35), gap * 0.6], width, cap_start, cap_end, jn)
		9:   # triple
			_lines(m, pts, closed, [[0.2, 0.4], [0.2, 0.0], [0.2, -0.4]], width, cap_start, cap_end, jn)
		10:  # grueso + fino
			_lines(m, pts, closed, [[0.55, 0.225], [0.15, -0.425]], width, cap_start, cap_end, jn)
		11:  # ondulado
			_wave(m, pts, closed, width, maxf(dash, width * 1.5), false)
		12:  # zigzag
			_wave(m, pts, closed, width, maxf(dash, width * 1.2), true)
		13:  # puntos cuadrados (tramos de largo = grosor, remate plano)
			_pattern(m, pts, closed, [width, gap], width, 0, 0, jn)
		14:  # vía (línea fina con traviesas)
			_rail(m, pts, closed, width, maxf(dash, width * 0.8), jn)
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
			_strip(m, pts, half, closed, cap_start, cap_end, jn)
	return m

# ── tira con uniones y remates ───────────────────────────────────────────────
static func _const_half(n: int, h: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(h)
	return a

## jn = [unión, límite de inglete]; vacío = malla antigua (pincel).
static func _strip(m: Dictionary, pts_in: PackedVector2Array, half_in: PackedFloat32Array,
		closed: bool, cap_s: int, cap_e: int, jn: Array = []) -> void:
	if not jn.is_empty():
		_strip_joined(m, pts_in, half_in, closed, cap_s, cap_e, int(jn[0]), float(jn[1]))
		return
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
	if m.has("v"):
		var vv: PackedFloat32Array = m["v"]
		for k in count:
			vv.append(0.0)
			vv.append(1.0)
		m["v"] = vv
	for j in joins:
		_disc(m, j[0], j[1])
	if not closed:
		if cap_s == 1:
			_fan(m, pts[0], pts[0] - pts[1], half[0])
		if cap_e == 1:
			_fan(m, pts[n - 1], pts[n - 1] - pts[n - 2], half[n - 1])

## Tira con la unión pedida. Cada tramo es un cuadrilátero; en cada vértice
## con giro, el lado INTERIOR se cierra en el punto de inglete interior y el
## EXTERIOR se rellena con la pieza de unión (punta, arco o bisel), que
## comparte arista con los dos tramos: sin solapes (el trazo semitransparente
## no oscurece las esquinas).
static func _strip_joined(m: Dictionary, pts_in: PackedVector2Array, half_in: PackedFloat32Array,
		closed: bool, cap_s: int, cap_e: int, join: int, limit: float) -> void:
	var pts := pts_in.duplicate()
	var half := half_in.duplicate()
	var n := pts.size()
	if closed and n > 1 and pts[0].distance_squared_to(pts[n - 1]) < 1e-6:
		pts.remove_at(n - 1)
		half.remove_at(n - 1)
		n -= 1
	if n < 2:
		return
	if not closed:
		if cap_s == 2:
			pts[0] = pts[0] + (pts[0] - pts[1]).normalized() * half[0]
		if cap_e == 2:
			pts[n - 1] = pts[n - 1] + (pts[n - 1] - pts[n - 2]).normalized() * half[n - 1]
	var l_in := PackedVector2Array()
	var l_out := PackedVector2Array()
	var r_in := PackedVector2Array()
	var r_out := PackedVector2Array()
	l_in.resize(n)
	l_out.resize(n)
	r_in.resize(n)
	r_out.resize(n)
	var patches: Array = []   # polígonos [interior, exterior…] en abanico
	for i in n:
		var p := pts[i]
		var h := half[i]
		var has_prev := closed or i > 0
		var has_next := closed or i < n - 1
		var v0 := (p - pts[(i - 1 + n) % n]) if has_prev else Vector2.ZERO
		var v1 := (pts[(i + 1) % n] - p) if has_next else Vector2.ZERO
		var d0 := v0.normalized() if v0 != Vector2.ZERO else v1.normalized()
		var d1 := v1.normalized() if v1 != Vector2.ZERO else d0
		var n0 := Vector2(-d0.y, d0.x)
		var n1 := Vector2(-d1.y, d1.x)
		var cr := d0.cross(d1)
		var mdir := n0 + n1
		if mdir.length_squared() < 1e-8:
			# Vuelta de 180°: extremo plano en cada lado; redonda = semicírculo.
			l_in[i] = p + n0 * h
			r_in[i] = p - n0 * h
			l_out[i] = p + n1 * h
			r_out[i] = p - n1 * h
			if join == JOIN_ROUND:
				_fan(m, p, d0, h)
			continue
		mdir = mdir.normalized()
		var mlen := h / maxf(mdir.dot(n1), 0.0001)
		if absf(cr) < 1e-6 or mlen - h < 0.02:
			# Recto o giro mínimo (curvas teseladas): inglete, sin pieza.
			l_in[i] = p + mdir * mlen
			l_out[i] = l_in[i]
			r_in[i] = p - mdir * mlen
			r_out[i] = r_in[i]
			continue
		var s_out := -signf(cr)              # +1: el exterior es el lado izquierdo (+n)
		var reach := minf(v0.length(), v1.length())
		var in_len := minf(mlen, sqrt(h * h + reach * reach))
		var inner := p - mdir * s_out * in_len
		var a := p + n0 * h * s_out
		var b := p + n1 * h * s_out
		if s_out > 0.0:
			l_in[i] = a
			l_out[i] = b
			r_in[i] = inner
			r_out[i] = inner
		else:
			r_in[i] = a
			r_out[i] = b
			l_in[i] = inner
			l_out[i] = inner
		var poly := [p, inner, a]   # p (eje) = centro del abanico
		match join:
			JOIN_ROUND:
				var a0 := (a - p).angle()
				var sweep := wrapf((b - p).angle() - a0, -PI, PI)
				var segs := clampi(int(absf(sweep) * maxf(h, 1.0) / 2.0) + 2, 2, 48)
				for k in range(1, segs):
					var t := a0 + sweep * float(k) / float(segs)
					poly.append(p + Vector2(cos(t), sin(t)) * h)
			JOIN_MITER:
				if mlen <= h * limit:
					poly.append(p + mdir * s_out * mlen)
		poly.append(b)
		patches.append([poly, s_out])
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var want_v := m.has("v")
	var vv: PackedFloat32Array = m["v"] if want_v else PackedFloat32Array()
	for k in (n if closed else n - 1):
		var j := (k + 1) % n
		var v := verts.size()
		verts.append_array([l_out[k], r_out[k], l_in[j], r_in[j]])
		idx.append_array([v, v + 1, v + 2, v + 1, v + 3, v + 2])
		if want_v:
			vv.append_array([0.0, 1.0, 0.0, 1.0])
	for pe in patches:
		var poly: Array = pe[0]
		var c := verts.size()
		for q in poly:
			verts.append(q)
		# Abanico desde el eje (p) por todo el contorno de la pieza: el punto
		# interior y el arco exterior; así la pieza encaja con los dos tramos.
		var cnt := poly.size()
		for k in range(1, cnt):
			idx.append_array([c, c + k, c + 1 + (k % (cnt - 1))])
		if want_v:
			# p = eje (0,5); interior = borde del lado de dentro; arco = borde de fuera.
			var outer_v := 0.0 if float(pe[1]) > 0.0 else 1.0
			vv.append(0.5)
			vv.append(1.0 - outer_v)
			for k in range(2, cnt):
				vv.append(outer_v)
	m["points"] = verts
	m["indices"] = idx
	if want_v:
		m["v"] = vv
	if not closed:
		if cap_s == 1:
			_fan(m, pts[0], pts[0] - pts[1], half[0])
		if cap_e == 1:
			_fan(m, pts[n - 1], pts[n - 1] - pts[n - 2], half[n - 1])

static func _fan(m: Dictionary, c: Vector2, dir: Vector2, r: float) -> void:
	if r < 0.0005 or dir.length_squared() < 1e-12:
		return
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var a0 := dir.normalized().angle() - PI * 0.5
	var segs := clampi(int(r * 0.8) + 16, 16, 48)
	var ci := verts.size()
	verts.append(c)
	for k in segs + 1:
		var a := a0 + PI * float(k) / float(segs)
		verts.append(c + Vector2(cos(a), sin(a)) * r)
	for k in segs:
		idx.append_array([ci, ci + 1 + k, ci + 2 + k])
	m["points"] = verts
	m["indices"] = idx
	_radial_v(m, segs + 1)

static func _disc(m: Dictionary, c: Vector2, r: float) -> void:
	if r < 0.0005:
		return
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var segs := clampi(int(r * 1.2) + 32, 32, 64)
	var ci := verts.size()
	verts.append(c)
	for k in segs:
		var a := TAU * float(k) / float(segs)
		verts.append(c + Vector2(cos(a), sin(a)) * r)
	for k in segs:
		idx.append_array([ci, ci + 1 + k, ci + 1 + (k + 1) % segs])
	m["points"] = verts
	m["indices"] = idx
	_radial_v(m, segs)

## Centro (0,5) + `rim` vértices de borde (1) en m["v"], si se pide.
static func _radial_v(m: Dictionary, rim: int) -> void:
	if not m.has("v"):
		return
	var vv: PackedFloat32Array = m["v"]
	vv.append(0.5)
	for k in rim:
		vv.append(1.0)
	m["v"] = vv

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
		@warning_ignore("integer_division")
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

# ── contorno del trazo (VGSE fase 1: geometría derivada → trazado) ───────────
## Contorno de un trazo de anchura variable como polígonos (Geometry2D: los
## agujeros van en sentido horario). Se recorre un lado, el remate final, el
## otro lado al revés y el remate inicial, con uniones redondas en el lado
## EXTERIOR de los giros cerrados; luego Clipper une con regla «positiva»:
## los cruces del trazo consigo mismo quedan rellenos, los pliegues del lado
## interior de las curvas cerradas desaparecen y lo que el trazo encierra
## (un lazo) queda como agujero.
static func outline(pts_in: PackedVector2Array, half_in: PackedFloat32Array, cap_s: int, cap_e: int) -> Array:
	var pts := PackedVector2Array()
	var half := PackedFloat32Array()
	for i in pts_in.size():
		if pts.is_empty() or pts_in[i].distance_squared_to(pts[pts.size() - 1]) > 1e-6:
			pts.append(pts_in[i])
			half.append(maxf(half_in[mini(i, half_in.size() - 1)], 0.01))
	var n := pts.size()
	if n == 0:
		return []
	if n == 1:
		var d := {"points": PackedVector2Array(), "indices": PackedInt32Array()}
		_disc(d, pts[0], half[0])
		var ring: PackedVector2Array = d["points"].slice(1)
		return [ring]
	if cap_s == 2:
		pts[0] = pts[0] + (pts[0] - pts[1]).normalized() * half[0]
	if cap_e == 2:
		pts[n - 1] = pts[n - 1] + (pts[n - 1] - pts[n - 2]).normalized() * half[n - 1]
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var d0 := (pts[i] - pts[i - 1]).normalized() if i > 0 else (pts[1] - pts[0]).normalized()
		var d1 := (pts[i + 1] - pts[i]).normalized() if i < n - 1 else d0
		var n0 := Vector2(-d0.y, d0.x)
		var n1 := Vector2(-d1.y, d1.x)
		var h := half[i]
		var mdir := n0 + n1
		var mlen := INF
		if mdir.length_squared() > 1e-8:
			mdir = mdir.normalized()
			mlen = h / maxf(mdir.dot(n1), 0.0001)
		if mlen <= h * MITER_LIMIT:
			left.append(pts[i] + mdir * mlen)
			right.append(pts[i] - mdir * mlen)
			continue
		# Giro cerrado: arco por fuera, punto del eje por dentro (lo cubre
		# el resto del trazo; la unión positiva limpia el solape).
		var turn := d0.cross(d1)
		var arc := _arc(pts[i], (n0 if turn <= 0.0 else -n0) * h, (n1 if turn <= 0.0 else -n1) * h)
		if turn <= 0.0:
			left.append_array(arc)
			right.append(pts[i])
		else:
			left.append(pts[i])
			right.append_array(arc)
	var ring := PackedVector2Array()
	if cap_s == 1:
		ring.append_array(_arc(pts[0], -Vector2(-(pts[1] - pts[0]).normalized().y, (pts[1] - pts[0]).normalized().x) * half[0],
			Vector2(-(pts[1] - pts[0]).normalized().y, (pts[1] - pts[0]).normalized().x) * half[0], true))
	ring.append_array(left)
	if cap_e == 1:
		var de := (pts[n - 1] - pts[n - 2]).normalized()
		var ne := Vector2(-de.y, de.x)
		ring.append_array(_arc(pts[n - 1], ne * half[n - 1], -ne * half[n - 1], true))
	var rr := right.duplicate()
	rr.reverse()
	ring.append_array(rr)
	return union_positive(ring)

## Arco de `a` a `b` (vectores desde `c`, mismo radio) por el lado corto;
## `half_turn`: media vuelta por delante (remates redondos).
static func _arc(c: Vector2, a: Vector2, b: Vector2, half_turn: bool = false) -> PackedVector2Array:
	var r := a.length()
	var a0 := a.angle()
	var sweep := -PI if half_turn else wrapf(b.angle() - a0, -PI, PI)
	# Mínimo 16 por media vuelta: con mucho zoom un radio pequeño en el
	# lienzo son muchos px de pantalla y se veía poligonal.
	var segs := clampi(int(absf(sweep) / PI * clampf(r * 0.8 + 16.0, 16.0, 48.0)), 2, 48)
	var out := PackedVector2Array()
	for k in segs + 1:
		var t := a0 + sweep * float(k) / float(segs)
		out.append(c + Vector2(cos(t), sin(t)) * r)
	return out

## Unión con regla «positiva» de un polígono que se corta a sí mismo (la
## orientación del recorrido decide qué es dentro). Clipper la aplica al
## desplazar: se desplaza una fracción ínfima.
static func union_positive(ring: PackedVector2Array) -> Array:
	if ring.size() < 3:
		return []
	var res: Array = Geometry2D.offset_polygon(ring, 0.001, Geometry2D.JOIN_MITER)
	var area := 0.0
	for p in res:
		area += absf(_area(p))
	if area < 1e-6 or not _has_outer(res):
		var rev := ring.duplicate()
		rev.reverse()
		res = Geometry2D.offset_polygon(rev, 0.001, Geometry2D.JOIN_MITER)
	return res

static func _has_outer(polys: Array) -> bool:
	for p in polys:
		if not Geometry2D.is_polygon_clockwise(p):
			return true
	return false

static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return a * 0.5


# ── trazo en dos mitades sin solapes (VGSE fase 1: cúspides y pliegues) ──────
## Malla del trazo como DOS MITADES: del eje (v = 0,5) a cada borde (v = 0 a
## la izquierda, 1 a la derecha). En cada borde:
##   · lado exterior de un giro cerrado → arco redondo (todos sus puntos
##     «cuelgan» del mismo punto del eje: abanico);
##   · lado interior con un giro más cerrado que el grosor → el borde se
##     cruza consigo mismo: se corta el lazo en el cruce.
## Ningún triángulo pisa a otro: el aerógrafo, el rotulador y el lápiz (con
## transparencia que varía a lo ancho) no marcan rayos ni pajaritas.
## Librería nativa (rust/vectopen_io, VectopenIO.stroke_halves): la misma
## malla 20–50× más rápida. Sin ella (o con VECTOPEN_GEOM=gdscript) se usa
## el GDScript de abajo.
static var _geom_io: Object = null
static var _geom_checked := false

static func _native_geom() -> Object:
	if not _geom_checked:
		_geom_checked = true
		if OS.get_environment("VECTOPEN_GEOM") != "gdscript" and ClassDB.class_exists("VectopenIO"):
			var io: Object = ClassDB.instantiate("VectopenIO")
			if io and io.has_method("stroke_halves"):
				_geom_io = io
	return _geom_io

static func _halves(m: Dictionary, pts_in: PackedVector2Array, half_in: PackedFloat32Array, cap_s: int, cap_e: int) -> void:
	var io := _native_geom()
	if io and (m["points"] as PackedVector2Array).is_empty() and half_in.size() >= pts_in.size():
		var r: Dictionary = io.stroke_halves(pts_in, half_in, cap_s, cap_e)
		m["points"] = r["points"]
		m["indices"] = r["indices"]
		if m.has("v"):
			m["v"] = r["v"]
		m["k"] = r["k"]
		m["beyond"] = r["beyond"]
		return
	_halves_gd(m, pts_in, half_in, cap_s, cap_e)

static func _halves_gd(m: Dictionary, pts_in: PackedVector2Array, half_in: PackedFloat32Array, cap_s: int, cap_e: int) -> void:
	var pts := pts_in.duplicate()
	var half := half_in.duplicate()
	var n := pts.size()
	if cap_s == 2:
		pts[0] = pts[0] + (pts[0] - pts[1]).normalized() * half[0]
	if cap_e == 2:
		pts[n - 1] = pts[n - 1] + (pts[n - 1] - pts[n - 2]).normalized() * half[n - 1]
	# Puntas: fuera los micro-puntos a menos de ¾ de grosor del extremo (el
	# «gancho» al apoyar / levantar el lápiz): giraban el remate y dejaban una
	# costura. El extremo se conserva.
	var trimmed := _trim_ends(pts, half)
	pts = trimmed[0]
	half = trimmed[1]
	n = pts.size()
	var cum := _cumulative(pts)
	var d_s := (pts[1] - pts[0]).normalized()
	var d_e := (pts[n - 1] - pts[n - 2]).normalized()
	var sides := [_side(pts, half, 1.0), _side(pts, half, -1.0)]
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var vv: PackedFloat32Array = m["v"] if m.has("v") else PackedFloat32Array()
	# m["k"]: punto del eje de cada vértice; m["beyond"]: cuánto pasa del
	# extremo (remates). Con ellos el render hace el desvanecido de las
	# puntas y el flujo por presión del aerógrafo.
	var kk: PackedInt32Array = PackedInt32Array()
	var axis0 := verts.size()
	for i in n:
		verts.append(pts[i])
		vv.append(0.5)
		kk.append(i)
	for si in 2:
		var side: Array = _cut_loops(sides[si], cum, half, pts)
		var sv := 0.0 if si == 0 else 1.0
		var base := verts.size()
		for e in side:
			verts.append(e[0])
			vv.append(sv)
			kk.append(int(e[1]))
		# Cremallera eje ↔ borde (los dueños del borde no decrecen).
		var k := 0
		var o: int = side[0][1]
		var last := side.size() - 1
		while true:
			if k < last and int(side[k + 1][1]) <= o:
				idx.append_array([axis0 + o, base + k, base + k + 1])
				k += 1
			elif o < n - 1:
				idx.append_array([base + k, axis0 + o, axis0 + o + 1])
				o += 1
			elif k < last:
				idx.append_array([axis0 + o, base + k, base + k + 1])
				k += 1
			else:
				break
	m["points"] = verts
	m["indices"] = idx
	if m.has("v"):
		m["v"] = vv
	var beyond := PackedFloat32Array()
	beyond.resize(kk.size())
	for cap in [[cap_s, 0, -d_s], [cap_e, n - 1, d_e]]:
		if int(cap[0]) != 1:
			continue
		var c0 := (m["points"] as PackedVector2Array).size()
		var ki: int = cap[1]
		var dir: Vector2 = (cap[2] as Vector2).normalized()
		_fan(m, pts[ki], cap[2], half[ki])
		var vs: PackedVector2Array = m["points"]
		for q in range(c0, vs.size()):
			kk.append(ki)
			beyond.append(maxf(0.0, (vs[q] - pts[ki]).dot(dir)))
	m["k"] = kk
	m["beyond"] = beyond

static func _trim_ends(pts: PackedVector2Array, half: PackedFloat32Array) -> Array:
	var n := pts.size()
	if n <= 3:
		return [pts, half]
	var cum := _cumulative(pts)
	var total := cum[n - 1]
	var ws := minf(half[0] * 1.5, total * 0.25)
	var we := minf(half[n - 1] * 1.5, total * 0.25)
	var op := PackedVector2Array([pts[0]])
	var oh := PackedFloat32Array([half[0]])
	for i in range(1, n - 1):
		if cum[i] >= ws and total - cum[i] >= we:
			op.append(pts[i])
			oh.append(half[i])
	op.append(pts[n - 1])
	oh.append(half[n - 1])
	return [op, oh] if op.size() >= 2 else [pts, half]

## Un borde: [[punto, índice del eje]]. `sgn` +1 izquierda (+n), -1 derecha.
static func _side(pts: PackedVector2Array, half: PackedFloat32Array, sgn: float) -> Array:
	var n := pts.size()
	var out: Array = []
	for i in n:
		var d0 := (pts[i] - pts[i - 1]).normalized() if i > 0 else (pts[1] - pts[0]).normalized()
		var d1 := (pts[i + 1] - pts[i]).normalized() if i < n - 1 else d0
		var n0 := Vector2(-d0.y, d0.x) * sgn
		var n1 := Vector2(-d1.y, d1.x) * sgn
		var h := half[i]
		var mdir := n0 + n1
		var outer := d0.cross(d1) * sgn < 0.0
		if mdir.length_squared() < 1e-8:
			out.append([pts[i] + n0 * h, i])
			out.append([pts[i] + n1 * h, i])
			continue
		mdir = mdir.normalized()
		var mlen := h / maxf(mdir.dot(n1), 0.0001)
		if outer and mlen > h * 1.02:
			# Exterior de un giro: arco redondo colgado del punto del eje.
			for q in _arc(pts[i], n0 * h, n1 * h):
				out.append([q, i])
		else:
			# Recto o interior: inglete, como mucho hasta donde llegan los
			# tramos vecinos (si no, en una vuelta casi de 180° —el «gancho»
			# de un lápiz real— el inglete salía como un pincho de cientos de
			# píxeles).
			var reach := minf(pts[i].distance_to(pts[maxi(i - 1, 0)]), pts[i].distance_to(pts[mini(i + 1, n - 1)]))
			if i == 0 or i == n - 1:
				reach = h
			out.append([pts[i] + mdir * minf(mlen, sqrt(h * h + reach * reach)), i])
	return out

## Quita los lazos de un borde (lado interior de un giro más cerrado que el
## grosor): busca cruces con tramos cercanos y los sustituye por el punto de
## cruce, que hereda el dueño del primer punto quitado (abanico en el eje).
static func _cut_loops(side: Array, cum: PackedFloat32Array, half: PackedFloat32Array, axis: PackedVector2Array = PackedVector2Array()) -> Array:
	# Un lazo solo existe donde el borde va HACIA ATRÁS respecto al eje: se
	# busca solo cerca de esos retrocesos. Una sola pasada sobre el borde
	# original (antes, tras cada corte se copiaba el borde y se recalculaban
	# los retrocesos: con muchas curvas cerradas costaba >10 ms por punto
	# mientras se dibujaba y el trazo iba por detrás del lápiz).
	var n := side.size()
	var nxt := _next_backtrack(side, axis)
	var out: Array = []
	var i := 0
	while i < n:
		out.append(side[i])
		if i >= n - 3:
			i += 1
			continue
		var r: int = nxt[i]
		if r < 0:
			out.append_array(side.slice(i + 1))
			break
		var c0 := cum[int(side[i][1])]
		var reach := half[int(side[i][1])] * 4.0 + 1.0
		if cum[int(side[r][1])] - c0 > reach:
			i += 1
			continue
		var a: Vector2 = side[i][0]
		var b: Vector2 = side[i + 1][0]
		var hit := -1
		var x := Vector2.ZERO
		var j := i + 2
		# el cruce más lejano corta el lazo entero de una vez
		while j < n - 1 and cum[int(side[j][1])] - c0 <= reach:
			var rr = Geometry2D.segment_intersects_segment(a, b, side[j][0], side[j + 1][0])
			if rr != null:
				hit = j
				x = rr
			j += 1
		if hit >= 0:
			out.append([x, int(side[i + 1][1])])
			i = hit + 1
			continue
		i += 1
	return out

## nxt[q] = primer tramo ≥ q del borde que retrocede respecto al eje (-1 si
## no hay ninguno más). Sin eje: todos cuentan (búsqueda completa).
static func _next_backtrack(side: Array, axis: PackedVector2Array) -> PackedInt32Array:
	var n := side.size()
	var nxt := PackedInt32Array()
	nxt.resize(n)
	var nextr := -1
	for q in range(n - 1, -1, -1):
		var back := true
		if axis.size() >= 2 and q < n - 1:
			var o: int = side[q][1]
			var ad := axis[mini(o + 1, axis.size() - 1)] - axis[maxi(o - 1, 0)]
			back = ((side[q + 1][0] as Vector2) - (side[q][0] as Vector2)).dot(ad) < 0.0
		elif q == n - 1:
			back = false
		if back:
			nextr = q
		nxt[q] = nextr
	return nxt


# ── aerógrafo por sellos (VGSE fase 2: pincel de patrón a lo largo) ─────────
## Malla del aerógrafo: SELLOS (discos de caída suave) cada ~¼ de radio a lo
## largo del eje, como un aerógrafo de verdad: la pintura se acumula donde se
## insiste y los garabatos más cerrados que el grosor, las vueltas de 180° y
## las puntas salen bien sin pliegues ni aletas.
## Devuelve {points, indices, v, a} (a = opacidad de cada vértice por sello,
## ya con el flujo por presión).
static func stamps(pts: PackedVector2Array, half: PackedFloat32Array, flow: PackedFloat32Array) -> Dictionary:
	var io := _native_geom()
	if io and io.has_method("stroke_stamps") and half.size() >= pts.size():
		return io.stroke_stamps(pts, half, flow)   # nativo (Rust), mismo resultado
	return stamps_gd(pts, half, flow)

static func stamps_gd(pts: PackedVector2Array, half: PackedFloat32Array, flow: PackedFloat32Array) -> Dictionary:
	var m := {"points": PackedVector2Array(), "indices": PackedInt32Array(), "v": PackedFloat32Array(), "a": PackedFloat32Array()}
	var n := pts.size()
	if n == 0:
		return m
	var cum := _cumulative(pts)
	var total := cum[n - 1]
	var hmax := 0.0
	for h in half:
		hmax = maxf(hmax, h)
	# Paso relativo al radio (antes mínimo 0,25 unidades: con mucho zoom y
	# un aerógrafo fino los sellos quedaban separados, como un rosario).
	var step := maxf(hmax * 0.25, 0.0001)
	var count := int(total / step) + 1
	if count > 6000:
		step = total / 6000.0
		count = 6001
	# Opacidad por sello: en el centro de un tramo recto se acumulan unos
	# 2r/paso sellos → casi opaco (95 %) con la opacidad del pincel.
	var per := 1.0 - pow(0.05, step / maxf(2.0 * hmax, 0.001))
	var j := 0
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var vv: PackedFloat32Array = m["v"]
	var aa: PackedFloat32Array = m["a"]
	for s_i in count:
		var d := minf(s_i * step, total)
		while j < n - 2 and cum[j + 1] < d:
			j += 1
		var seg := maxf(cum[mini(j + 1, n - 1)] - cum[j], 1e-6)
		var f := clampf((d - cum[j]) / seg, 0.0, 1.0)
		var j2 := mini(j + 1, n - 1)
		var c := pts[j].lerp(pts[j2], f)
		var r := lerpf(half[j], half[j2], f)
		var fl := lerpf(flow[j] if j < flow.size() else 1.0, flow[j2] if j2 < flow.size() else 1.0, f)
		var segs := clampi(int(r * 0.6) + 16, 16, 32)
		var ci := verts.size()
		verts.append(c)
		vv.append(0.5)
		aa.append(per * fl)
		for k in segs:
			var t := TAU * float(k) / float(segs)
			verts.append(c + Vector2(cos(t), sin(t)) * r)
			vv.append(1.0)
			aa.append(per * fl)
		for k in segs:
			idx.append_array([ci, ci + 1 + k, ci + 1 + (k + 1) % segs])
	m["points"] = verts
	m["indices"] = idx
	m["v"] = vv
	m["a"] = aa
	return m
