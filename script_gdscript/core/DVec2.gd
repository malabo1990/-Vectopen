class_name DVec2
extends RefCounted

## Vector 2D de doble precisión (64 bits) para coordenadas de documento.
## Godot 4.7 GDScript no soporta sobrecarga de operadores en clases de script,
## por eso la API es por métodos explícitos en vez de +/-/*.

var x: float = 0.0
var y: float = 0.0

func _init(px: float = 0.0, py: float = 0.0) -> void:
	x = px
	y = py

static func from_v2(v: Vector2) -> DVec2:
	return DVec2.new(v.x, v.y)

static func array_from_v2(a: PackedVector2Array) -> Array[DVec2]:
	var out: Array[DVec2] = []
	for v in a:
		out.append(DVec2.from_v2(v))
	return out

func to_v2() -> Vector2:
	return Vector2(x, y)

func added(o: DVec2) -> DVec2:
	return DVec2.new(x + o.x, y + o.y)

func subtracted(o: DVec2) -> DVec2:
	return DVec2.new(x - o.x, y - o.y)

func scaled(f: float) -> DVec2:
	return DVec2.new(x * f, y * f)

func scaled2(fx: float, fy: float) -> DVec2:
	return DVec2.new(x * fx, y * fy)

func rotated(angle: float) -> DVec2:
	var c: float = cos(angle)
	var s: float = sin(angle)
	return DVec2.new(x * c - y * s, x * s + y * c)

func equals_approx(o: DVec2, eps: float = 1e-9) -> bool:
	return absf(x - o.x) <= eps and absf(y - o.y) <= eps

func _to_string() -> String:
	return "DVec2(%s, %s)" % [x, y]
