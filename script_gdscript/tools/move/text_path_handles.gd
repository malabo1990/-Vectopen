extends RefCounted
## Tiradores del TEXTO EN TRAZADO en el lienzo (como Illustrator / Affinity):
## ▶ inicio y ◀ final del tramo que ocupa el texto, y ◆ en el centro del
## texto para deslizarlo por el trazado. Se arrastran a lo largo de la curva.
## Al soltar se guarda con deshacer (vía InspectorCore).

const R = preload("res://script_gdscript/shapes/brush_stroke_render.gd")
const OB = preload("res://script_gdscript/shapes/object_brush.gd")

const HIT_PX := 14.0
const SIZE_PX := 11.0
const COL := Color(0.16, 0.47, 0.95)
const COL_EDGE := Color(1, 1, 1)

var line: Line2D = null
var drag := ""                 # "start" | "end" | "mid" | ""
var _drag_s0 := 0.0            # distancia donde empezó el arrastre
var _before := {}              # params al empezar (para deshacer)
var hover := ""

## El texto en trazado seleccionado (uno solo), o null.
static func target(selected: Array) -> Line2D:
	if selected.size() != 1:
		return null
	var l = selected[0]
	if not is_instance_valid(l):
		return null
	if l is Line2D and l.has_meta("brush_ref") and l.is_visible_in_tree():
		return l
	return null

static func _params(l: Line2D) -> Dictionary:
	return ((l.get_meta("brush_obj", {}) as Dictionary).get("params", {}) as Dictionary)

## Eje del trazo tal como se dibuja: [pts, half, cum] (en local del Line2D).
static func _axis(l: Line2D) -> Array:
	return R.centerline(l)

## Datos de los tiradores en coordenadas GLOBALES:
## {start: {p, t, n}, end: {...}, mid: {...}, span, range, total}
static func layout(l: Line2D) -> Dictionary:
	var ax := _axis(l)
	var pts: PackedVector2Array = ax[0]
	var half: PackedFloat32Array = ax[1]
	if pts.size() < 2:
		return {}
	var bo: Dictionary = l.get_meta("brush_obj", {})
	var src: Array = OB.from_data(bo.get("src", []))
	var sp: Dictionary = OB.text_span(pts, half, src, bo.get("params", {}))
	if sp.is_empty():
		return {}
	var cum := _cum(pts)
	var xf := l.get_global_transform()
	var rg: Vector2 = sp["range"]
	var tx: Vector2 = sp["text"]
	# "n": hacia el lado CONTRARIO al texto (ahí van los triángulos)
	var pa := _params(l)
	var flip := -1.0 if bool(pa.get("flip", false)) else 1.0
	if bool(pa.get("reverse", false)):
		flip = -flip
	if String(pa.get("valign", "baseline")) == "top":
		flip = -flip
	var out := {"span": tx, "range": rg, "total": sp["total"]}
	for k in [["start", rg.x], ["end", rg.y], ["mid", (tx.x + tx.y) * 0.5]]:
		var at := _at(pts, cum, clampf(float(k[1]), 0.0, float(sp["total"])))
		var p: Vector2 = xf * at[0]
		var t: Vector2 = xf.basis_xform(at[1]).normalized()
		out[k[0]] = {"p": p, "t": t, "n": Vector2(-t.y, t.x) * flip}
	return out

static func _cum(pts: PackedVector2Array) -> PackedFloat32Array:
	var c := PackedFloat32Array()
	c.resize(pts.size())
	for i in range(1, pts.size()):
		c[i] = c[i - 1] + pts[i].distance_to(pts[i - 1])
	return c

## [punto, tangente] a la distancia s.
static func _at(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Array:
	var n := pts.size()
	var j := clampi(cum.bsearch(s) - 1, 0, n - 2)
	var f := clampf((s - cum[j]) / maxf(cum[j + 1] - cum[j], 0.000001), 0.0, 1.0)
	var t := (pts[j + 1] - pts[j]).normalized()
	return [pts[j].lerp(pts[j + 1], f), t if t != Vector2.ZERO else Vector2.RIGHT]

## Distancia a lo largo del trazado del punto del eje más cercano a `gp` (global).
static func project(l: Line2D, gp: Vector2) -> float:
	var pts: PackedVector2Array = _axis(l)[0]
	var cum := _cum(pts)
	var q: Vector2 = l.get_global_transform().affine_inverse() * gp
	var best := INF
	var best_s := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var f := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
		var d := q.distance_squared_to(a + ab * f)
		if d < best:
			best = d
			best_s = cum[i] + ab.length() * f
	return best_s

## Dónde se dibuja cada tirador (global): los triángulos un poco apartados
## de la curva, al lado contrario del texto, para no taparlo.
static func _handle_pos(h: Dictionary, k: String, zoom: float) -> Vector2:
	# ◆ también al lado contrario de las letras: encima de ellas tapaba el
	# arrastre del texto entero.
	return h["p"] + h["n"] * (SIZE_PX * 1.6 / zoom)

## Tirador bajo el ratón ("start" | "end" | "mid" | "").
func hit(gp: Vector2, zoom: float) -> String:
	if line == null:
		return ""
	var lay := layout(line)
	if lay.is_empty():
		return ""
	var best := ""
	var best_d := HIT_PX / zoom
	for k in ["mid", "start", "end"]:
		var d := gp.distance_to(_handle_pos(lay[k], k, zoom))
		if d <= best_d:
			best_d = d
			best = k
	return best

func begin(k: String, gp: Vector2) -> void:
	drag = k
	_before = _params(line).duplicate(true)
	_drag_s0 = project(line, gp)

## Arrastre: mueve el tirador a lo largo de la curva (en vivo, sin deshacer).
func update(gp: Vector2) -> void:
	if drag == "" or line == null:
		return
	var lay := layout_cached()
	var total: float = maxf(float(lay.get("total", 0.0)), 0.0001)
	var s := project(line, gp)
	var prm := _before.duplicate(true)
	var a := float(prm.get("start_at", 0.0))
	var b := float(prm.get("end_at", 1.0))
	match drag:
		"start":
			prm["start_at"] = clampf(s / total, 0.0, maxf(b - 0.01, 0.0))
		"end":
			prm["end_at"] = clampf(s / total, minf(a + 0.01, 1.0), 1.0)
		"mid":
			# desliza el tramo entero (conserva su largo)
			var d := (s - _drag_s0) / total
			d = clampf(d, -a, 1.0 - b)
			prm["start_at"] = a + d
			prm["end_at"] = b + d
	_set_params(prm)

var _lay_cache := {}
func layout_cached() -> Dictionary:
	if _lay_cache.is_empty():
		_lay_cache = layout(line)
	return _lay_cache

## Suelta: deja los parámetros y registra deshacer.
func finish() -> void:
	if drag == "" or line == null:
		drag = ""
		return
	var after := _params(line).duplicate(true)
	_set_params(_before)
	drag = ""
	_lay_cache = {}
	var ic := line.get_node_or_null("/root/InspectorCore")
	var sel_ok := ic != null and ic.has_method("apply")
	if not sel_ok:
		_set_params(after)
		return
	var v := Vector2(float(after.get("start_at", 0.0)), float(after.get("end_at", 1.0)))
	var v0 := Vector2(float(_before.get("start_at", 0.0)), float(_before.get("end_at", 1.0)))
	if not v.is_equal_approx(v0):
		ic.apply("path_text_range", v)

func cancel() -> void:
	if drag != "" and line != null:
		_set_params(_before)
	drag = ""
	_lay_cache = {}

func _set_params(prm: Dictionary) -> void:
	var bo: Dictionary = (line.get_meta("brush_obj", {}) as Dictionary).duplicate(true)
	bo["params"] = prm
	line.set_meta("brush_obj", bo)
	line.queue_redraw()
	var r := line.get_node_or_null(R.NODE_NAME)
	if r:
		r.queue_redraw()

## Dibujo en el lienzo `c` (Node2D del canvas).
func draw(c: Node2D, zoom: float) -> void:
	if line == null:
		return
	var lay := layout(line)
	if lay.is_empty():
		return
	var k := 1.0 / maxf(zoom, 0.0002)
	var sz := SIZE_PX * k
	# tramo permitido: marcas finas en la curva
	for key in ["start", "end"]:
		var h: Dictionary = lay[key]
		var at := c.to_local(_handle_pos(h, key, zoom))
		var t: Vector2 = h["t"] * (1.0 if key == "start" else -1.0)
		var nn: Vector2 = h["n"]
		# raya que une el triángulo con la curva
		c.draw_line(c.to_local(h["p"]), at, COL, 1.25 * k, true)
		var tri := PackedVector2Array([at + t * sz, at - t * sz * 0.6 + nn * sz * 0.8, at - t * sz * 0.6 - nn * sz * 0.8])
		var col := COL.lightened(0.25) if hover == key or drag == key else COL
		c.draw_colored_polygon(tri, col)
		tri.append(tri[0])
		c.draw_polyline(tri, COL_EDGE, 1.0 * k, true)
	var m: Dictionary = lay["mid"]
	c.draw_line(c.to_local(m["p"]), c.to_local(_handle_pos(m, "mid", zoom)), COL, 1.25 * k, true)
	var mp := c.to_local(_handle_pos(m, "mid", zoom))
	var t2: Vector2 = m["t"] * sz * 0.75
	var n2: Vector2 = m["n"] * sz * 0.75
	var dia := PackedVector2Array([mp + t2, mp + n2, mp - t2, mp - n2])
	c.draw_colored_polygon(dia, COL.lightened(0.25) if hover == "mid" or drag == "mid" else COL)
	dia.append(dia[0])
	c.draw_polyline(dia, COL_EDGE, 1.0 * k, true)
