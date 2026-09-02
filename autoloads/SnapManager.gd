extends Node

signal snap_mode_changed(mode: String, enabled: bool)
signal grid_size_changed(size: float)

const CONFIG_PATH := "user://vectopen_snap.cfg"

var grid_enabled: bool = false
var grid_size: float = 10.0
var snap_to_objects: bool = true
var snap_to_center: bool = true
var snap_to_guides: bool = true
var show_guides: bool = true

## Guías de regla (coords de MUNDO). Las publica `regla.gd`:
##   guide_x = líneas VERTICALES (una coord X cada una)
##   guide_y = líneas HORIZONTALES (una coord Y cada una)
var guide_x: Array = []
var guide_y: Array = []

func set_guides(vertical_x: Array, horizontal_y: Array) -> void:
	guide_x = vertical_x.duplicate()
	guide_y = horizontal_y.duplicate()

## Umbral del imán, en píxeles de PANTALLA (constante a cualquier zoom).
const SMART_SNAP_PX := 11.0
## Umbral (px pantalla) para igualar separaciones / distribuir.
const SPACING_SNAP_PX := 9.0
## Tolerancia (px mundo) al comparar dos separaciones "iguales".
const SPACING_MATCH_EPS := 1.5

func _ready() -> void:
	_load_config()

func snap_position(pos: Vector2) -> Vector2:
	if grid_enabled and grid_size > 0:
		pos.x = round(pos.x / grid_size) * grid_size
		pos.y = round(pos.y / grid_size) * grid_size
	return pos

## Imán inteligente. Ajusta el rect global arrastrado (`moving`, coords de MUNDO)
## contra `candidates` con TRES estrategias, en orden de prioridad por eje:
##   1. Alineación de bordes (izq/der, arr/ab) y centros con otras figuras.
##   2. Igualar separación: si el hueco a un vecino coincide con OTRO hueco ya
##      existente entre dos figuras, engancha a esa misma distancia.
##   3. Distribución: centra la figura entre su vecino de un lado y el del otro.
## `zoom` = escala del viewport (umbral constante en pantalla). Devuelve:
##   { "offset": Vector2, "guides": Array, "spacing": Array }
##   guide   = { axis, coord, a, b }                    (línea de alineación)
##   spacing = { axis, perp, segs: [[lo,hi], ...], gap } (barras de separación)
func smart_snap(moving: Rect2, candidates: Array, zoom: float) -> Dictionary:
	var res := { "offset": Vector2.ZERO, "guides": [], "spacing": [] }
	if moving.size == Vector2.ZERO:
		return res
	var usar_obj: bool = snap_to_objects and not candidates.is_empty()
	var usar_guias: bool = snap_to_guides and (not guide_x.is_empty() or not guide_y.is_empty())
	if not usar_obj and not usar_guias:
		return res
	var z: float = maxf(zoom, 0.0001)
	var thr: float = SMART_SNAP_PX / z
	var thr_sp: float = SPACING_SNAP_PX / z

	var mx := [moving.position.x, moving.position.x + moving.size.x * 0.5, moving.end.x]
	var my := [moving.position.y, moving.position.y + moving.size.y * 0.5, moving.end.y]

	var best_dx: float = INF
	var line_x: Dictionary = {}
	var best_dy: float = INF
	var line_y: Dictionary = {}

	if usar_obj:
		for cand in candidates:
			var c: Rect2 = cand
			if c.size == Vector2.ZERO:
				continue
			var cx := [c.position.x, c.position.x + c.size.x * 0.5, c.end.x]
			var cy := [c.position.y, c.position.y + c.size.y * 0.5, c.end.y]
			for ai in 3:
				for bi in 3:
					if not snap_to_center and (ai == 1 or bi == 1):
						continue
					var d: float = cx[bi] - mx[ai]
					if absf(d) <= thr and absf(d) < absf(best_dx):
						best_dx = d
						line_x = { "coord": cx[bi], "a": minf(moving.position.y, c.position.y), "b": maxf(moving.end.y, c.end.y) }
					var e: float = cy[bi] - my[ai]
					if absf(e) <= thr and absf(e) < absf(best_dy):
						best_dy = e
						line_y = { "coord": cy[bi], "a": minf(moving.position.x, c.position.x), "b": maxf(moving.end.x, c.end.x) }

	# ── Guías de regla (línea vertical → eje X ; horizontal → eje Y) ──
	if usar_guias:
		for gx in guide_x:
			for ai in 3:
				if not snap_to_center and ai == 1:
					continue
				var d: float = float(gx) - mx[ai]
				if absf(d) <= thr and absf(d) < absf(best_dx):
					best_dx = d
					line_x = { "coord": float(gx), "a": moving.position.y, "b": moving.end.y, "guide": true }
		for gy in guide_y:
			for ai in 3:
				if not snap_to_center and ai == 1:
					continue
				var e: float = float(gy) - my[ai]
				if absf(e) <= thr and absf(e) < absf(best_dy):
					best_dy = e
					line_y = { "coord": float(gy), "a": moving.position.x, "b": moving.end.x, "guide": true }

	if best_dx != INF:
		res["offset"].x = best_dx
		line_x["axis"] = "x"
		res["guides"].append(line_x)
	if best_dy != INF:
		res["offset"].y = best_dy
		line_y["axis"] = "y"
		res["guides"].append(line_y)

	# ── Separación (solo en el eje que NO se alineó por borde) ──
	var mv := Rect2(moving.position + res["offset"], moving.size)
	if best_dx == INF:
		var sx := _spacing_snap(mv, candidates, true, thr_sp)
		if not sx.is_empty():
			res["offset"].x += sx["delta"]
			res["spacing"].append(sx["info"])
	if best_dy == INF:
		var sy := _spacing_snap(mv, candidates, false, thr_sp)
		if not sy.is_empty():
			res["offset"].y += sy["delta"]
			res["spacing"].append(sy["info"])
	return res

## Vecinos de `mv` en un eje (horizontal=true → izquierda/derecha). Devuelve
## {} o { "delta": float, "info": Dictionary }.
func _spacing_snap(mv: Rect2, candidates: Array, horizontal: bool, thr: float) -> Dictionary:
	var m_lo: float = mv.position.x if horizontal else mv.position.y
	var m_hi: float = mv.end.x if horizontal else mv.end.y
	var p_lo: float = mv.position.y if horizontal else mv.position.x
	var p_hi: float = mv.end.y if horizontal else mv.end.x
	var size: float = m_hi - m_lo

	var left_hi: float = -INF   # borde interno del vecino del lado bajo
	var right_lo: float = INF   # borde interno del vecino del lado alto
	# huecos ya existentes entre pares de candidatos (para "igualar separación")
	var edges_lo: Array[float] = []
	var edges_hi: Array[float] = []

	for cand in candidates:
		var c: Rect2 = cand
		if c.size == Vector2.ZERO:
			continue
		var c_plo: float = c.position.y if horizontal else c.position.x
		var c_phi: float = c.end.y if horizontal else c.end.x
		if c_phi <= p_lo or c_plo >= p_hi:
			continue  # no comparten "fila"/"columna"
		var c_lo: float = c.position.x if horizontal else c.position.y
		var c_hi: float = c.end.x if horizontal else c.end.y
		if c_hi <= m_lo:
			if c_hi > left_hi:
				left_hi = c_hi
			if edges_lo.size() < 32:
				edges_hi.append(c_hi)
				edges_lo.append(c_lo)
		elif c_lo >= m_hi:
			if c_lo < right_lo:
				right_lo = c_lo
			if edges_lo.size() < 32:
				edges_hi.append(c_hi)
				edges_lo.append(c_lo)

	# 1. Distribución: centrado entre ambos vecinos.
	if left_hi != -INF and right_lo != INF and (right_lo - left_hi) > size:
		var gap: float = (right_lo - left_hi - size) * 0.5
		var target_lo: float = left_hi + gap
		var delta: float = target_lo - m_lo
		if absf(delta) <= thr:
			return { "delta": delta,
				"info": {
					"axis": "x" if horizontal else "y",
					"perp": (p_lo + p_hi) * 0.5,
					"gap": gap,
					"segs": [[left_hi, target_lo], [target_lo + size, right_lo]],
				} }

	# 2. Igualar separación: replicar un hueco existente hacia el vecino más cercano.
	var existing: Array[float] = []
	for i in edges_lo.size():
		for j in edges_hi.size():
			var g: float = edges_lo[i] - edges_hi[j]
			if g > 1.0:
				existing.append(g)
	if not existing.is_empty():
		if left_hi != -INF:
			for g in existing:
				var target_lo: float = left_hi + g
				var delta: float = target_lo - m_lo
				if absf(delta) <= thr:
					return { "delta": delta,
						"info": {
							"axis": "x" if horizontal else "y",
							"perp": (p_lo + p_hi) * 0.5,
							"gap": g,
							"segs": [[left_hi, target_lo]],
						} }
		if right_lo != INF:
			for g in existing:
				var target_hi: float = right_lo - g
				var delta: float = target_hi - m_hi
				if absf(delta) <= thr:
					return { "delta": delta,
						"info": {
							"axis": "x" if horizontal else "y",
							"perp": (p_lo + p_hi) * 0.5,
							"gap": g,
							"segs": [[target_hi, right_lo]],
						} }
	return {}

func snap_value(value: float) -> float:
	if grid_enabled and grid_size > 0:
		return round(value / grid_size) * grid_size
	return value

func set_grid_enabled(enabled: bool) -> void:
	grid_enabled = enabled
	_save_config()
	snap_mode_changed.emit("grid", enabled)

func set_grid_size(size: float) -> void:
	grid_size = max(size, 1.0)
	_save_config()
	grid_size_changed.emit(grid_size)

func set_snap_to_objects(enabled: bool) -> void:
	snap_to_objects = enabled
	snap_to_center = enabled
	_save_config()
	snap_mode_changed.emit("objects", enabled)

func set_snap_to_center(enabled: bool) -> void:
	snap_to_center = enabled
	_save_config()
	snap_mode_changed.emit("center", enabled)

func set_snap_to_guides(enabled: bool) -> void:
	snap_to_guides = enabled
	_save_config()
	snap_mode_changed.emit("guides", enabled)

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	grid_enabled = cfg.get_value("snap", "grid_enabled", false)
	grid_size = cfg.get_value("snap", "grid_size", 10.0)
	snap_to_objects = cfg.get_value("snap", "snap_to_objects", true)
	snap_to_center = cfg.get_value("snap", "snap_to_center", true)
	snap_to_guides = cfg.get_value("snap", "snap_to_guides", true)
	show_guides = cfg.get_value("snap", "show_guides", true)

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("snap", "grid_enabled", grid_enabled)
	cfg.set_value("snap", "grid_size", grid_size)
	cfg.set_value("snap", "snap_to_objects", snap_to_objects)
	cfg.set_value("snap", "snap_to_center", snap_to_center)
	cfg.set_value("snap", "snap_to_guides", snap_to_guides)
	cfg.set_value("snap", "show_guides", show_guides)
	cfg.save(CONFIG_PATH)
