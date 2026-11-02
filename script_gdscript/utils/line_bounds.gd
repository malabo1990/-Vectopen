# =============================================================================
# RUTA: res://script_gdscript/utils/line_bounds.gd
# Caja de un Line2D (trazos de pincel: hasta decenas de miles de puntos) con
# CACHÉ. Antes, cada vez que se pedía la caja (inspector, herramienta Mover,
# recuadro de selección) se recorrían todos los puntos con to_global():
# seleccionar ~270 trazos tardaba ~200 ms por fotograma (UX-07).
# La caja local se guarda en una meta junto a una firma de los puntos
# (cantidad + primero + medio + último); si cambia, se recalcula.
# =============================================================================
extends RefCounted

const META := "_vo_local_bounds"

## Caja LOCAL (sin transformar) de los puntos del trazo.
static func local_rect(line: Line2D) -> Rect2:
	var pts := line.points
	var n := pts.size()
	if n == 0:
		return Rect2()
	@warning_ignore("integer_division")
	var sig := [n, pts[0], pts[n / 2], pts[n - 1]]
	var cached = line.get_meta(META) if line.has_meta(META) else null
	if cached is Array and (cached as Array).size() == 2 and cached[0] == sig:
		return cached[1]
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	var r := Rect2(mn, mx - mn)
	line.set_meta(META, [sig, r])
	return r

## Caja GLOBAL: las 4 esquinas de la caja local transformadas (rotación y
## escala incluidas), más medio grosor de margen.
static func global_rect(line: Line2D, min_pad: float = 0.0) -> Rect2:
	var lr := local_rect(line)
	var xf := line.get_global_transform()
	var c := [xf * lr.position, xf * Vector2(lr.end.x, lr.position.y), xf * lr.end, xf * Vector2(lr.position.x, lr.end.y)]
	var mn: Vector2 = c[0]
	var mx: Vector2 = c[0]
	for p in c:
		mn = mn.min(p)
		mx = mx.max(p)
	return Rect2(mn, mx - mn).grow(maxf(min_pad, line.width * 0.5))
