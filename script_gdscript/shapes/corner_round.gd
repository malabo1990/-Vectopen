# =============================================================================
# RUTA: res://script_gdscript/shapes/corner_round.gd
# Redondeo de esquinas COMÚN de polígonos y estrellas. Antes cada figura lo
# hacía con 5 puntos fijos por esquina: con radios grandes se veía facetado.
# Aquí los puntos se adaptan al giro de la esquina (≈ cada 6°) y el radio de
# cada vértice puede ser distinto (puntas y valles de una estrella).
# =============================================================================
extends RefCounted

## `radii[i]` = radio del vértice i (si el array es más corto, se repite el
## último). `max_frac` = fracción máxima del lado más corto que puede ocupar.
static func round(raw: PackedVector2Array, radii: PackedFloat32Array, max_frac: float = 0.45) -> PackedVector2Array:
	var n := raw.size()
	if n < 3 or radii.is_empty():
		return raw
	var out := PackedVector2Array()
	for i in n:
		var p_prev := raw[(i - 1 + n) % n]
		var p := raw[i]
		var p_next := raw[(i + 1) % n]
		var want: float = radii[mini(i, radii.size() - 1)]
		var r := clampf(want, 0.0, minf(p.distance_to(p_prev), p.distance_to(p_next)) * max_frac)
		if r <= 0.1:
			out.append(p)
			continue
		var a := p + (p_prev - p).normalized() * r
		var b := p + (p_next - p).normalized() * r
		# Giro de la esquina → número de puntos (una curva cada ~6°).
		var turn := absf((p - p_prev).angle_to(p_next - p))
		var steps := clampi(int(ceil(rad_to_deg(turn) / 6.0)), 2, 32)
		for s in steps + 1:
			var t := float(s) / float(steps)
			var u := 1.0 - t
			out.append(a * (u * u) + p * (2.0 * u * t) + b * (t * t))
	return out
