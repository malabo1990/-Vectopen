extends Node

const CONFIG_PATH := "user://vectopen_draw.cfg"

var fill_color: Color:
	get: return _load_color("fill", Color(0.88, 0.88, 0.88, 1.0))
	set(v): _save_color("fill", v)

var stroke_color: Color:
	get: return _load_color("stroke", Color.BLACK)
	set(v): _save_color("stroke", v)

var text_color: Color:
	get: return _load_color("text", Color.BLACK)
	set(v): _save_color("text", v)

var text_size: int:
	get: return _load_int("text_size", 32)
	set(v): _save_int("text_size", v)

func _load_color(key: String, default: Color) -> Color:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK: return default
	return cfg.get_value("draw", key, default)

func _save_color(key: String, color: Color) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("draw", key, color)
	cfg.save(CONFIG_PATH)

func _load_int(key: String, default: int) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK: return default
	return cfg.get_value("draw", key, default)

func _save_int(key: String, value: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("draw", key, value)
	cfg.save(CONFIG_PATH)
