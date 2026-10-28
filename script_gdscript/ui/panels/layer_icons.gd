# =============================================================================
# VECTOPEN — ICONO DE TIPO PARA CADA CAPA
# RUTA: res://script_gdscript/ui/panels/layer_icons.gd
#
# Pedido del usuario: "que cada capa tenga icono para saber qué tipo de
# elemento es, como triángulo, cuadrado, etc.". Antes todo VectorPolygon
# salía con el mismo hexágono (triángulos, gotas, corazones…) y la elipse no
# distinguía anillo / tarta / arco.
#
# El icono se DIBUJA con la geometría del tipo (los mismos contornos que el
# panel de Polígonos): triángulo, cuadrado, rectángulo, pentágono…, estrella
# de N puntas, círculo / elipse / anillo / tarta / arco, gota, corazón…
# Blanco con alfa (como los SVG de la lista): el árbol lo tiñe con el tema.
# Cacheado por clave de tipo (no por objeto): 500 triángulos = 1 icono.
# =============================================================================
extends RefCounted

const SIZE := 32          # se dibuja a 32 px y el árbol lo muestra a ~14-16
const PAD := 4.0
const LINE := 2.2

static var _cache: Dictionary = {}

## Clave del tipo geométrico de `n`, o "" si no es una figura paramétrica
## (entonces la lista usa su icono SVG de siempre: texto, imagen, grupo…).
static func key_for(n: Node) -> String:
	if n is VectorRectangle:
		var sz: Vector2 = n.size
		var round := float(n.corner_radius) > 0.5 if "corner_radius" in n else false
		var sq := absf(sz.x - sz.y) < maxf(sz.x, sz.y) * 0.08
		return ("square" if sq else "rect") + ("_round" if round else "")
	if n is VectorCircle:
		var mode := String(n.shape_mode) if "shape_mode" in n else "whole"
		if mode == "donut":
			return "ring"
		if mode == "pie":
			return "pie"
		if mode == "arc":
			return "arc"
		var s: Vector2 = n.size
		return "circle" if absf(s.x - s.y) < maxf(s.x, s.y) * 0.08 else "ellipse"
	if n is VectorStar:
		return "star_%d" % clampi(int(n.points_count), 3, 12)
	if n is VectorPolygon:
		var sk := String(n.get_meta("shape_kind", ""))
		if sk == "drop":
			return "drop"
		if sk.begins_with("custom_"):
			return sk
		if bool(n.get("is_regular")):
			return "poly_%d" % clampi(int(n.sides), 3, 12)
		return "poly_free"
	return ""

static func icon_for(n: Node) -> Texture2D:
	var k := key_for(n)
	if k == "":
		return null
	if _cache.has(k):
		return _cache[k]
	var pts := _outline(k)
	if pts.size() < 2:
		return null
	var tex := _render(pts, k in ["arc"])
	_cache[k] = tex
	return tex

## Contorno normalizado (±1) del tipo.
static func _outline(k: String) -> PackedVector2Array:
	var PP = load("res://script_gdscript/ui/panel_polygon.gd")
	match k:
		"square", "square_round":
			return _rounded_rect(Vector2(1, 1), 0.35 if k.ends_with("round") else 0.0)
		"rect", "rect_round":
			return _rounded_rect(Vector2(1, 0.62), 0.3 if k.ends_with("round") else 0.0)
		"circle":
			return _ellipse(Vector2(1, 1), 0.0, TAU)
		"ellipse":
			return _ellipse(Vector2(1, 0.62), 0.0, TAU)
		"ring":
			# Dos círculos: se unen con un tramo invisible (separados abajo).
			var o := _ellipse(Vector2(1, 1), 0.0, TAU)
			o.append(Vector2.INF)
			o.append_array(_ellipse(Vector2(0.5, 0.5), 0.0, TAU))
			return o
		"pie":
			var p := PackedVector2Array([Vector2.ZERO])
			# Tres cuartos de círculo (de las 12 a las 9), cerrado al centro.
			p.append_array(_ellipse(Vector2(1, 1), -PI / 2.0, PI))
			p.append(Vector2.ZERO)
			return p
		"arc":
			return _ellipse(Vector2(1, 1), PI * 0.75, PI * 2.25)
		"drop":
			return PP._normalized(PP.kind_icon(4))
		"poly_free":
			return _closed(PP._normalized(PackedVector2Array([Vector2(-40, 30), Vector2(-10, -40), Vector2(40, -10), Vector2(25, 40)])))
	if k.begins_with("star_"):
		return _closed(PP._normalized(PP.star_points(int(k.substr(5)), 0.45)))
	if k.begins_with("poly_"):
		var sides := int(k.substr(5))
		var ang := 45.0 if sides == 4 else 0.0
		return _closed(PP._normalized(PP.poly_points(sides, ang)))
	if k.begins_with("custom_"):
		return _closed(PP.custom_points(k.substr(7)))
	return PackedVector2Array()

static func _closed(p: PackedVector2Array) -> PackedVector2Array:
	if p.size() > 1 and not p[0].is_equal_approx(p[-1]):
		p.append(p[0])
	return p

static func _ellipse(r: Vector2, a0: float, a1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := 40
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(Vector2(cos(a) * r.x, sin(a) * r.y))
	return out

static func _rounded_rect(half: Vector2, rad: float) -> PackedVector2Array:
	if rad <= 0.0:
		return PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y), Vector2(-half.x, -half.y)])
	var out := PackedVector2Array()
	var corners := [Vector2(half.x - rad, -half.y + rad), Vector2(half.x - rad, half.y - rad),
		Vector2(-half.x + rad, half.y - rad), Vector2(-half.x + rad, -half.y + rad)]
	var start := [-PI / 2.0, 0.0, PI / 2.0, PI]
	for i in 4:
		for j in 7:
			var a: float = start[i] + PI / 2.0 * j / 6.0
			out.append(corners[i] + Vector2(cos(a), sin(a)) * rad)
	out.append(out[0])
	return out

## Dibuja el contorno (blanco, alfa suave) en una textura SIZE×SIZE.
static func _render(pts: PackedVector2Array, _open: bool) -> Texture2D:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var bb := Rect2()
	var have := false
	for p in pts:
		if p == Vector2.INF:
			continue
		if not have:
			bb = Rect2(p, Vector2.ZERO)
			have = true
		else:
			bb = bb.expand(p)
	var span := maxf(bb.size.x, bb.size.y)
	if span <= 0.0:
		return ImageTexture.create_from_image(img)
	var k := (SIZE - PAD * 2.0) / span
	var off := Vector2(SIZE, SIZE) / 2.0 - bb.get_center() * k
	var prev := Vector2.INF
	for p in pts:
		if p == Vector2.INF:
			prev = Vector2.INF
			continue
		var q := p * k + off
		if prev != Vector2.INF:
			_line(img, prev, q)
		prev = q
	return ImageTexture.create_from_image(img)

static func _line(img: Image, a: Vector2, b: Vector2) -> void:
	var steps := maxi(1, int(ceil(a.distance_to(b) * 3.0)))
	var r := LINE * 0.5
	for i in steps + 1:
		var c := a.lerp(b, float(i) / steps)
		for y in range(int(floor(c.y - r - 1)), int(ceil(c.y + r + 1)) + 1):
			for x in range(int(floor(c.x - r - 1)), int(ceil(c.x + r + 1)) + 1):
				if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
					continue
				var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
				var al := clampf(r + 0.5 - d, 0.0, 1.0)
				if al > img.get_pixel(x, y).a:
					img.set_pixel(x, y, Color(1, 1, 1, al))
