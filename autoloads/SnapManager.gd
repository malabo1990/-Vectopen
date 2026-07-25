extends Node

signal snap_mode_changed(mode: String, enabled: bool)
signal grid_size_changed(size: float)

const CONFIG_PATH := "user://vectopen_snap.cfg"

var grid_enabled: bool = false
var grid_size: float = 10.0
var snap_to_objects: bool = false
var snap_to_center: bool = false
var show_guides: bool = true

func _ready() -> void:
	_load_config()

func snap_position(pos: Vector2) -> Vector2:
	if grid_enabled and grid_size > 0:
		pos.x = round(pos.x / grid_size) * grid_size
		pos.y = round(pos.y / grid_size) * grid_size
	return pos

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
	snap_to_objects = cfg.get_value("snap", "snap_to_objects", false)
	snap_to_center = cfg.get_value("snap", "snap_to_center", false)
	show_guides = cfg.get_value("snap", "show_guides", true)

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("snap", "grid_enabled", grid_enabled)
	cfg.set_value("snap", "grid_size", grid_size)
	cfg.set_value("snap", "snap_to_objects", snap_to_objects)
	cfg.set_value("snap", "snap_to_center", snap_to_center)
	cfg.set_value("snap", "show_guides", show_guides)
	cfg.save(CONFIG_PATH)
