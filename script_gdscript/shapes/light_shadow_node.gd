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
const MAX_LAYERS := 48   # una cada ~2,5 px de recorrido (degradado continuo)
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
## Rápido: los contornos difuminados se calculan UNA vez por nivel de
## difuminado (4 niveles) y cada copia solo se desplaza (draw_set_transform);
## antes cada copia recalculaba su geometría (hasta 144 cálculos por figura).
const BLUR_LEVELS := 4
## Caché de contornos difuminados YA triangulados: al girar o mover la luz la
## forma de la figura no cambia, solo el desplazamiento → no se recalcula ni
## se vuelve a triangular nada (antes ~70 ms/fotograma con 30 figuras).
var _cache := {}

func _draw() -> void:
	var ci := get_canvas_item()
	var used := {}
	for s in shadows:
		var poly: PackedVector2Array = s["poly"]
		var off: Vector2 = s["off"]
		var col: Color = s["color"]
		var soft: float = float(s["soft"])
		var fade: float = float(s.get("fade", 0.7))
		var n := clampi(int(off.length() / 2.5), MIN_LAYERS, MAX_LAYERS)
		var rings := 2 if n > 24 else RINGS
		var levels: Array = []
		for lv in BLUR_LEVELS:
			var sft := snappedf(soft * (0.25 + float(lv + 1) / BLUR_LEVELS), 0.25)
			var key := hash([poly, sft, rings])
			used[key] = true
			if not _cache.has(key):
				_cache[key] = _tris(_rings(poly, sft, rings))
			levels.append(_cache[key])
		for i in range(n, 0, -1):
			var t := float(i) / n
			var a := col.a * (1.0 - fade * t) * 2.2 / n
			if a <= 0.002:
				continue
			var lv := clampi(int(t * BLUR_LEVELS - 0.001), 0, BLUR_LEVELS - 1)
			draw_set_transform(off * t)
			for m in levels[lv]:
				RenderingServer.canvas_item_add_triangle_array(ci, m[1], m[0],
					PackedColorArray([Color(col, clampf(a * float(m[2]), 0.0, 1.0))]))
		draw_set_transform(Vector2.ZERO)
	for k in _cache.keys():
		if not used.has(k):
			_cache.erase(k)

static func _tris(rings: Array) -> Array:
	var out: Array = []
	for r in rings:
		var idx := Geometry2D.triangulate_polygon(r[0])
		if idx.size() >= 3:
			out.append([r[0], idx, r[1]])
	return out

static func _rings(poly: PackedVector2Array, soft: float, rings: int) -> Array:
	if soft < 0.5:
		return [[poly, 1.0]]
	var out: Array = []
	for k in range(rings, 0, -1):
		var grow := soft * (float(k) / rings - 0.5)
		for g in Geometry2D.offset_polygon(poly, grow, Geometry2D.JOIN_ROUND):
			if not Geometry2D.is_polygon_clockwise(g) and g.size() >= 3:
				out.append([g, 1.4 / rings])
	return out

## La silueta `pts` (coordenadas locales) corrida `off`: sombra 2D plana.
static func shifted(pts: PackedVector2Array, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = pts[i] + off
	return out
