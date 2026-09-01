extends Node

signal snap_mode_changed(mode: String, enabled: bool)
signal grid_size_changed(size: float)

const CONFIG_PATH := "user://vectopen_snap.cfg"

var grid_enabled: bool = false
var grid_size: float = 10.0
var snap_to_objects: bool = true
var snap_to_center: bool = true
var show_guides: bool = true

## Umbral del imán, en píxeles de PANTALLA (constante a cualquier zoom).
const SMART_SNAP_PX := 7.0

func _ready() -> void:
	_load_config()

func snap_position(pos: Vector2) -> Vector2:
	if grid_enabled and grid_size > 0:
		pos.x = round(pos.x / grid_size) * grid_size
		pos.y = round(pos.y / grid_size) * grid_size
	return pos

## Imán inteligente: ajusta el rect global arrastrado (`moving`) a los rects
## candidatos por bordes izquierda/centro/derecha y arriba/centro/abajo. Todo en
## coordenadas de MUNDO; `zoom` es la escala del viewport (para que el umbral sea
## constante en pantalla). Devuelve:
##   { "offset": Vector2, "guides": Array }
## donde cada guía es { "axis": "x"|"y", "coord": float, "a": float, "b": float }
## (segmento perpendicular que une los bordes alineados).
func smart_snap(moving: Rect2, candidates: Array, zoom: float) -> Dictionary:
	var res := { "offset": Vector2.ZERO, "guides": [] }
	if not snap_to_objects or candidates.is_empty() or moving.size == Vector2.ZERO:
		return res
	var thr: float = SMART_SNAP_PX / maxf(zoom, 0.0001)

	var mx := [moving.position.x, moving.position.x + moving.size.x * 0.5, moving.end.x]
	var my := [moving.position.y, moving.position.y + moving.size.y * 0.5, moving.end.y]

	var best_dx: float = INF
	var line_x: Dictionary = {}
	var best_dy: float = INF
	var line_y: Dictionary = {}

	for cand in candidates:
		var c: Rect2 = cand
		if c.size == Vector2.ZERO:
			continue
		var cx := [c.position.x, c.position.x + c.size.x * 0.5, c.end.x]
		var cy := [c.position.y, c.position.y + c.size.y * 0.5, c.end.y]
		for a in mx:
			for b in cx:
				if not snap_to_center and (a == mx[1] or b == cx[1]):
					continue
				var d: float = b - a
				if absf(d) <= thr and absf(d) < absf(best_dx):
					best_dx = d
					line_x = { "coord": b, "a": minf(moving.position.y, c.position.y), "b": maxf(moving.end.y, c.end.y) }
		for a in my:
			for b in cy:
				if not snap_to_center and (a == my[1] or b == cy[1]):
					continue
				var d: float = b - a
				if absf(d) <= thr and absf(d) < absf(best_dy):
					best_dy = d
					line_y = { "coord": b, "a": minf(moving.position.x, c.position.x), "b": maxf(moving.end.x, c.end.x) }

	if best_dx != INF:
		res["offset"].x = best_dx
		line_x["axis"] = "x"
		res["guides"].append(line_x)
	if best_dy != INF:
		res["offset"].y = best_dy
		line_y["axis"] = "y"
		res["guides"].append(line_y)
	return res

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

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	grid_enabled = cfg.get_value("snap", "grid_enabled", false)
	grid_size = cfg.get_value("snap", "grid_size", 10.0)
	snap_to_objects = cfg.get_value("snap", "snap_to_objects", true)
	snap_to_center = cfg.get_value("snap", "snap_to_center", true)
	show_guides = cfg.get_value("snap", "show_guides", true)

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("snap", "grid_enabled", grid_enabled)
	cfg.set_value("snap", "grid_size", grid_size)
	cfg.set_value("snap", "snap_to_objects", snap_to_objects)
	cfg.set_value("snap", "snap_to_center", snap_to_center)
	cfg.set_value("snap", "show_guides", show_guides)
	cfg.save(CONFIG_PATH)
