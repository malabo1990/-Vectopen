# =============================================================================
# RUTA: res://script_gdscript/shapes/light_shadow_node.gd
# SOMBRA EXTERIOR de una figura (iluminación 2D): la silueta de la figura,
# plana, corrida en sentido contrario a cada luz que la alcanza (sombra 2D, no
# un volumen extruido), dibujada DETRÁS de la figura (show_behind_parent) y
# encima de lo que hay debajo. La figura sigue iluminada (antes el oclusor de
# Godot la dejaba oscura por dentro: «solo sombra interior»).
# Borde difuminado por capas crecientes cada vez más transparentes.
# Nodo interno: no se guarda (se rehace) ni se selecciona.
# =============================================================================
extends Node2D

## [{"poly": contorno local, "off": desplazamiento local hasta el final,
##   "color": Color, "soft": difuminado en px, "fade": 0..1}]
var shadows: Array = []

const MIN_LAYERS := 8    # copias de la silueta entre la figura y el final:
const MAX_LAYERS := 72   # una cada ~2 px de recorrido (degradado continuo)
const RINGS := 3         # anillos de difuminado de cada copia

func _init() -> void:
	name = "_LightShadow"
	show_behind_parent = true
	light_mask = 1
	set_meta(&"_vectopen_internal", true)

## Sombra 2D: la silueta se repite desde la figura (t = 0) hasta su final
## (t = 1). Junto a la figura es oscura y nítida; hacia el final cada copia es
## más transparente («Desvanecer») y más difusa (penumbra), como una sombra
## real que se aleja del objeto.
func _draw() -> void:
	for s in shadows:
		var poly: PackedVector2Array = s["poly"]
		var off: Vector2 = s["off"]
		var col: Color = s["color"]
		var soft: float = float(s["soft"])
		var fade: float = float(s.get("fade", 0.7))
		var n := clampi(int(off.length() / 2.0), MIN_LAYERS, MAX_LAYERS)
		for i in range(n, 0, -1):
			var t := float(i) / n
			var a := col.a * (1.0 - fade * t) * 2.2 / n
			if a <= 0.002:
				continue
			var p := shifted(poly, off * t)
			_blurred(p, Color(col, clampf(a, 0.0, 1.0)), soft * (0.25 + t), n > 24)

func _blurred(poly: PackedVector2Array, col: Color, soft: float, many: bool) -> void:
	if soft < 0.5:
		draw_colored_polygon(poly, col)
		return
	# con muchas copias, 2 anillos bastan (las copias ya se funden entre sí)
	var rings := 2 if many else RINGS
	for k in range(rings, 0, -1):
		var grow := soft * (float(k) / rings - 0.5)
		for g in Geometry2D.offset_polygon(poly, grow, Geometry2D.JOIN_ROUND):
			if not Geometry2D.is_polygon_clockwise(g) and g.size() >= 3:
				draw_colored_polygon(g, Color(col, col.a / rings * 1.4))

## La silueta `pts` (coordenadas locales) corrida `off`: sombra 2D plana.
static func shifted(pts: PackedVector2Array, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = pts[i] + off
	return out
