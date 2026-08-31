extends Node

signal recent_files_changed(files: Array)

const CONFIG_PATH := "user://recent_assets.cfg"
const MAX_FILES := 20

func get_files() -> Array:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	return cfg.get_value("History", "items", [])

func add_file(path: String) -> void:
	var file_name := path.get_file().get_basename()
	var ext := path.get_extension()
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	var files: Array = cfg.get_value("History", "items", [])
	for i in range(files.size()):
		if files[i]["path"] == path:
			files.remove_at(i)
			break
	files.insert(0, {
		"name": file_name,
		"path": path,
		"format": ext,
		"time": Time.get_unix_time_from_system()
	})
	if files.size() > MAX_FILES:
		files.resize(MAX_FILES)
	cfg.set_value("History", "items", files)
	cfg.save(CONFIG_PATH)
	recent_files_changed.emit(files)

func remove_file(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	var files: Array = cfg.get_value("History", "items", [])
	files = files.filter(func(f): return f["path"] != path)
	cfg.set_value("History", "items", files)
	cfg.save(CONFIG_PATH)
	recent_files_changed.emit(files)

func clear() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("History", "items", [])
	cfg.save(CONFIG_PATH)
	recent_files_changed.emit([])
