# =============================================================================
# RUTA: res://script_gdscript/shapes/stroke_markers.gd
# PUNTAS de flecha de los extremos de un trazo (inicio / fin). La misma
# función dibuja la punta en el lienzo (VectorPath) y su icono en el panel
# Trazos, así lo que se elige es exactamente lo que se ve.
#
# trim(): cuánto se acorta la línea bajo una punta RELLENA, para que el
# grosor del trazo no asome por la punta (antes la línea llegaba hasta la
# punta y la dejaba roma).
# =============================================================================
extends RefCounted

## Índice = valor de stroke_pointer_start / stroke_pointer_end (los 0–4 son
## los de siempre, para no romper archivos guardados).
const TYPES := ["none", "arrow", "triangle", "circle", "square", "stealth", "diamond", "bar", "ring", "open_triangle"]
const LABELS := {
	"none": "Ninguna", "arrow": "Flecha abierta", "triangle": "Triángulo", "circle": "Círculo",
	"square": "Cuadrado", "stealth": "Flecha afilada", "diamond": "Rombo", "bar": "Barra",
	"ring": "Anillo", "open_triangle": "Triángulo hueco",
}

## Tamaño de la punta para un trazo de grosor `w` y escala `scale` (1 = 100 %).
static func size_for(w: float, scale: float = 1.0) -> float:
	return maxf(w * 3.5, 12.0) * clampf(scale, 0.25, 5.0)

## Longitud a recortar del trazo (de grosor total `w`) bajo la punta, según
## su forma: el cuerpo termina justo DENTRO de la punta, sin asomar.
static func trim(type: int, sz: float, w: float = 0.0) -> float:
	match type:
		1:      # flecha abierta (alas de pendiente 0.5): donde los bordes de
			return w   # la línea (±w/2) tocan las alas
		2:      # triángulo: un poco antes de su base (solape sin hueco)
			return sz * 0.9
		5:      # flecha afilada: la muesca está a 0.7·sz en el centro
			return sz * 0.65
		6:      # rombo: hasta su mitad
			return sz * 0.5
		3, 4:   # círculo / cuadrado rellenos: hasta el centro
			return sz * 0.35
		8:      # anillo (centro a 0.35·sz, radio 0.35·sz): hasta su borde
			return sz * 0.7
		9:      # triángulo hueco: hasta la base
			return sz
	return 0.0

## Dibuja la punta `type` en `pos` mirando hacia `dir` (unitario).
static func draw(ci: CanvasItem, pos: Vector2, dir: Vector2, type: int, sz: float, col: Color, line_w: float) -> void:
	if type <= 0:
		return
	var t := dir.normalized()
	var n := Vector2(-t.y, t.x)
	var lw := maxf(1.5, line_w)
	match type:
		1:  # flecha abierta (V)
			var a := pos - t * sz + n * (sz * 0.5)
			var b := pos - t * sz - n * (sz * 0.5)
			ci.draw_polyline(PackedVector2Array([a, pos, b]), col, lw, true)
		2:  # triángulo relleno
			ci.draw_colored_polygon(PackedVector2Array([pos, pos - t * sz + n * (sz * 0.5), pos - t * sz - n * (sz * 0.5)]), col)
		3:  # círculo
			ci.draw_circle(pos - t * (sz * 0.35), sz * 0.4, col)
		4:  # cuadrado
			var h := sz * 0.35
			var c := pos - t * h
			ci.draw_colored_polygon(PackedVector2Array([c + t * h + n * h, c - t * h + n * h, c - t * h - n * h, c + t * h - n * h]), col)
		5:  # flecha afilada (stealth): triángulo con la base hundida
			ci.draw_colored_polygon(PackedVector2Array([pos, pos - t * sz + n * (sz * 0.5), pos - t * (sz * 0.7), pos - t * sz - n * (sz * 0.5)]), col)
		6:  # rombo
			var h2 := sz * 0.5
			ci.draw_colored_polygon(PackedVector2Array([pos, pos - t * h2 + n * (sz * 0.35), pos - t * sz, pos - t * h2 - n * (sz * 0.35)]), col)
		7:  # barra perpendicular
			ci.draw_line(pos + n * (sz * 0.5), pos - n * (sz * 0.5), col, lw, true)
		8:  # anillo
			ci.draw_arc(pos - t * (sz * 0.35), sz * 0.35, 0.0, TAU, 32, col, lw, true)
		9:  # triángulo hueco
			var a2 := pos - t * sz + n * (sz * 0.5)
			var b2 := pos - t * sz - n * (sz * 0.5)
			ci.draw_polyline(PackedVector2Array([pos, a2, b2, pos]), col, lw, true)

## Acorta `pts` por el inicio (from_start) o el final una longitud `d`.
static func trim_points(pts: PackedVector2Array, d: float, from_start: bool) -> PackedVector2Array:
	if d <= 0.0 or pts.size() < 2:
		return pts
	var p := pts.duplicate()
	if from_start:
		p.reverse()
	var left := d
	while p.size() >= 2:
		var last := p[p.size() - 1]
		var prev := p[p.size() - 2]
		var seg := last.distance_to(prev)
		if seg > left:
			p[p.size() - 1] = last + (prev - last) / seg * left
			break
		left -= seg
		p.remove_at(p.size() - 1)
	if from_start:
		p.reverse()
	return p
