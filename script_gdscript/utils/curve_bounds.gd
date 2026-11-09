# =============================================================================
# RUTA: res://script_gdscript/utils/curve_bounds.gd
# Caja de una curva (Path2D) con CACHÉ. Antes, la herramienta Mover y el
# recuadro de selección recorrían todos los puntos horneados de cada curva
# (con to_global punto a punto) en CADA fotograma: mover 9 000 objetos con
# 1 500 curvas costaba ~90 ms por paso. La caja local se guarda en la propia
# Curve2D y se borra sola cuando la curva cambia (señal `changed`).
# =============================================================================
extends RefCounted

const META := "_vo_bounds"
const HOOK := "_vo_bounds_hook"

static func _clear(wr: WeakRef) -> void:
	var c = wr.get_ref()
	if c and c.has_meta(META):
		c.remove_meta(META)

## Caja LOCAL de los puntos horneados (sin margen).
static func local_rect(c: Curve2D) -> Rect2:
	if c == null:
		return Rect2()
	if c.has_meta(META):
		return c.get_meta(META)
	var baked := c.get_baked_points()
	if baked.is_empty():
		return Rect2()
	var mn := baked[0]
	var mx := baked[0]
	for p in baked:
		mn = mn.min(p)
		mx = mx.max(p)
	var r := Rect2(mn, mx - mn)
	c.set_meta(META, r)
	if not c.has_meta(HOOK):
		c.set_meta(HOOK, true)
		c.changed.connect(_clear.bind(weakref(c)))
	return r

## Caja GLOBAL: las 4 esquinas de la caja local transformadas.
static func global_rect(path: Node2D, c: Curve2D) -> Rect2:
	var lr := local_rect(c)
	var xf := path.get_global_transform()
	var r := Rect2(xf * lr.position, Vector2.ZERO)
	for q in [xf * Vector2(lr.end.x, lr.position.y), xf * lr.end, xf * Vector2(lr.position.x, lr.end.y)]:
		r = r.expand(q)
	return r
