# =============================================================================
# RUTA: res://script_gdscript/tools/move/table_handles.gd
# TABLAS v2 (VAL-56): tiradores en el lienzo para la tabla seleccionada.
#   · arrastrar una línea VERTICAL de la rejilla cambia el ancho de la
#     columna de su izquierda (la tabla crece o encoge, como Figma);
#   · arrastrar el borde INFERIOR cambia el alto de las filas.
# En vivo durante el gesto y UN paso de deshacer al soltar (Table.edit).
# Misma forma que text_path_handles.gd (target / hit / begin / update /
# finish / cancel / draw); lo usa la herramienta Mover.
# =============================================================================
extends RefCounted

const Table = preload("res://script_gdscript/shapes/table.gd")
const GRAB_PX := 5.0       # distancia de agarre, en px de pantalla
const MIN_COL := 16.0      # ancho mínimo de columna (documento)
const MIN_ROW := 12.0

var table: Node2D = null
var hover: Dictionary = {}   # {"kind": "col"|"row", "i": columna}
var drag: Dictionary = {}
var _before: Dictionary = {}
var _start_local := Vector2.ZERO
var _start_val := 0.0

## Tabla seleccionada (sola) o null.
static func target(sel: Array) -> Node2D:
	if sel.size() != 1 or not is_instance_valid(sel[0]):
		return null
	return sel[0] if Table.is_table(sel[0]) else null

static func _spec(t: Node2D) -> Dictionary:
	return t.get_meta(Table.META)

static func _total_w(spec: Dictionary) -> float:
	var w := 0.0
	for c in spec["col_w"]:
		w += float(c)
	return w

## ¿Qué tirador hay bajo `gm` (global)? {} si ninguno.
func hit(gm: Vector2, zoom: float) -> Dictionary:
	if not is_instance_valid(table):
		return {}
	var spec := _spec(table)
	var lp := table.to_local(gm)
	var tol := GRAB_PX / maxf(zoom * table.global_transform.get_scale().x, 0.0001)
	var tw := _total_w(spec)
	var th := float(spec["row_h"]) * int(spec["rows"])
	if lp.y < -tol or lp.y > th + tol or lp.x < -tol or lp.x > tw + tol:
		return {}
	# líneas verticales (la de cada columna, a su derecha)
	var x := 0.0
	var cw: Array = spec["col_w"]
	for c in cw.size():
		x += float(cw[c])
		if absf(lp.x - x) <= tol:
			return {"kind": "col", "i": c}
	if absf(lp.y - th) <= tol:
		return {"kind": "row", "i": 0}
	return {}

func begin(h: Dictionary, gm: Vector2) -> void:
	drag = h.duplicate()
	Table.sync_from_children(table)
	_before = _spec(table).duplicate(true)
	_start_local = table.to_local(gm)
	if String(h["kind"]) == "col":
		_start_val = float((_before["col_w"] as Array)[int(h["i"])])
	else:
		_start_val = float(_before["row_h"])

func _apply(spec: Dictionary, gm: Vector2) -> void:
	var lp := table.to_local(gm)
	if String(drag["kind"]) == "col":
		(spec["col_w"] as Array)[int(drag["i"])] = maxf(MIN_COL, _start_val + lp.x - _start_local.x)
	else:
		# el borde inferior baja todas las filas: el alto crece / rows
		var rows := maxi(1, int(spec["rows"]))
		spec["row_h"] = maxf(MIN_ROW, _start_val + (lp.y - _start_local.y) / rows)

## Vista previa en vivo (sin historial).
func update(gm: Vector2) -> void:
	if drag.is_empty() or not is_instance_valid(table):
		return
	var spec := _before.duplicate(true)
	_apply(spec, gm)
	table.set_meta(Table.META, spec)
	Table.rebuild(table)

## Un paso de deshacer con el resultado final.
func finish(gm: Vector2 = Vector2.INF) -> void:
	if drag.is_empty() or not is_instance_valid(table):
		drag = {}
		return
	var final_spec: Dictionary = _spec(table).duplicate(true)
	if gm != Vector2.INF:
		final_spec = _before.duplicate(true)
		_apply(final_spec, gm)
	table.set_meta(Table.META, _before.duplicate(true))
	var changed := var_to_str(final_spec) != var_to_str(_before)
	if changed:
		var what := "Tabla · ancho de columna" if String(drag["kind"]) == "col" else "Tabla · alto de filas"
		Table.edit(table, what, func(s: Dictionary) -> void:
			s.clear()
			s.merge(final_spec, true))
	else:
		Table.rebuild(table)
	drag = {}

func cancel() -> void:
	if not drag.is_empty() and is_instance_valid(table):
		table.set_meta(Table.META, _before.duplicate(true))
		Table.rebuild(table)
	drag = {}

## Marcas de los tiradores (en el CanvasItem `c`, coordenadas locales de c).
func draw(c: Node2D, zoom: float) -> void:
	if not is_instance_valid(table):
		return
	var spec := _spec(table)
	var k := 1.0 / maxf(zoom, 0.0002)
	var xf := c.get_global_transform().affine_inverse() * table.get_global_transform()
	var tw := _total_w(spec)
	var th := float(spec["row_h"]) * int(spec["rows"])
	var acc := Color(0.15, 0.55, 1.0, 0.95)
	var x := 0.0
	var cw: Array = spec["col_w"]
	for ci in cw.size():
		x += float(cw[ci])
		var on: bool = (hover.get("kind", "") == "col" and int(hover.get("i", -1)) == ci) or \
			(drag.get("kind", "") == "col" and int(drag.get("i", -1)) == ci)
		var a := xf * Vector2(x, 0)
		var b := xf * Vector2(x, th)
		if on:
			c.draw_line(a, b, acc, 2.0 * k)
		# pestaña encima de la tabla
		c.draw_rect(Rect2(a + Vector2(-3, -10) * k, Vector2(6, 7) * k), acc, true)
	var on_row: bool = hover.get("kind", "") == "row" or drag.get("kind", "") == "row"
	var bl := xf * Vector2(0, th)
	var br := xf * Vector2(tw, th)
	if on_row:
		c.draw_line(bl, br, acc, 2.0 * k)
	# a un cuarto del ancho: el centro del borde es el tirador de escalar
	# de la caja de selección
	var mid := bl.lerp(br, 0.25)
	c.draw_rect(Rect2(mid + Vector2(-7, 3) * k, Vector2(14, 5) * k), acc, true)
