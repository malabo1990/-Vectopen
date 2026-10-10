# =============================================================================
# RUTA: res://autoloads/PluginManager.gd
# GESTOR DE COMPLEMENTOS (como Preferencias → Add-ons de Blender).
#
# Dónde se buscan:
#   · res://plugins/     incluidos con Vectopen (no se pueden desinstalar)
#   · user://addons/     instalados por el usuario (.zip, carpeta o .gd)
# Formato: carpeta con addon.cfg + main.gd (extends VectopenAddon). También
# se aceptan los plugins antiguos de un solo .gd con on_load()/on_unload().
#
# Estado activado/desactivado en user://vectopen_addons.cfg. Un complemento
# que falla al activarse queda desactivado y con su error visible.
# `api` (VectopenAPI) es la instancia compartida por complementos y scripts.
# =============================================================================
extends Node

signal plugin_loaded(plugin_name: String)
signal plugin_unloaded(plugin_name: String)
signal plugin_error(plugin_name: String, message: String)
## La lista de complementos (o su estado) cambió.
signal addons_changed

const PLUGINS_DIR := "res://plugins/"
const USER_DIR := "user://addons/"
const CONFIG_PATH := "user://vectopen_addons.cfg"
const LEGACY_CONFIG_PATH := "user://vectopen_plugins.cfg"

var api: VectopenAPI = null
var _addons: Dictionary = {}      # id -> info (ver _read_info)
var _instances: Dictionary = {}   # id -> Node
var _loaded_order: Array[String] = []

func _ready() -> void:
	api = VectopenAPI.new(self)
	refresh()
	for id in _addons:
		if _wants_enabled(id):
			enable(id, false)

# ── descubrimiento ───────────────────────────────────────────────────────────
## Vuelve a leer las carpetas (no activa ni desactiva nada).
func refresh() -> void:
	var found := {}
	for base in [PLUGINS_DIR, USER_DIR]:
		_scan(base, base == PLUGINS_DIR, found)
	# Los activos que ya no existen en disco se quedan hasta desactivarlos.
	for id in _instances:
		if not found.has(id) and _addons.has(id):
			found[id] = _addons[id]
	_addons = found
	addons_changed.emit()

func _scan(base: String, builtin: bool, out: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(base):
		return
	for d in DirAccess.get_directories_at(base):
		var dir := base + d + "/"
		if FileAccess.file_exists(dir + "addon.cfg"):
			out[d] = _read_info(d, dir, builtin)
	for f in DirAccess.get_files_at(base):
		# En una exportación los .gd aparecen como .gd.remap / .gdc.
		var fname := f.trim_suffix(".remap")
		if fname.ends_with(".gd") or fname.ends_with(".gdc"):
			var id := fname.get_basename()
			if not out.has(id):
				out[id] = {"id": id, "name": id.capitalize(), "version": "", "author": "",
					"description": "Plugin de un solo archivo", "category": "General",
					"api": VectopenAPI.API_VERSION, "dir": base, "main": base + id + ".gd",
					"builtin": builtin, "legacy": true, "default_enabled": true, "error": ""}

func _read_info(id: String, dir: String, builtin: bool) -> Dictionary:
	var cfg := ConfigFile.new()
	var err := cfg.load(dir + "addon.cfg")
	var main := String(cfg.get_value("addon", "main", "main.gd"))
	return {
		"id": id,
		"name": String(cfg.get_value("addon", "name", id.capitalize())),
		"version": String(cfg.get_value("addon", "version", "")),
		"author": String(cfg.get_value("addon", "author", "")),
		"description": String(cfg.get_value("addon", "description", "")),
		"category": String(cfg.get_value("addon", "category", "General")),
		"api": String(cfg.get_value("addon", "api", VectopenAPI.API_VERSION)),
		"default_enabled": bool(cfg.get_value("addon", "enabled_by_default", false)),
		"dir": dir, "main": dir + main, "builtin": builtin, "legacy": false,
		"error": "" if err == OK else "addon.cfg ilegible (%s)" % error_string(err),
	}

# ── consulta ─────────────────────────────────────────────────────────────────
## [{id, name, version, author, description, category, builtin, enabled, error}]
## ordenados por categoría y nombre.
func list_addons() -> Array:
	var out: Array = []
	for id in _addons:
		var a: Dictionary = _addons[id].duplicate()
		a["enabled"] = _instances.has(id)
		out.append(a)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["category"] != b["category"]:
			return String(a["category"]).naturalnocasecmp_to(String(b["category"])) < 0
		return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	return out

func get_info(id: String) -> Dictionary:
	return _addons.get(id, {})

func is_enabled(id: String) -> bool:
	return _instances.has(id)

func get_addon(id: String) -> Node:
	return _instances.get(id, null)

# ── activar / desactivar ─────────────────────────────────────────────────────
## Activa un complemento. Devuelve "" si fue bien o el mensaje de error.
func enable(id: String, persist: bool = true) -> String:
	if _instances.has(id):
		return ""
	if not _addons.has(id):
		return _fail(id, "No existe el complemento «%s»" % id)
	var info: Dictionary = _addons[id]
	info["error"] = ""
	if String(info["api"]).get_slice(".", 0) != VectopenAPI.API_VERSION.get_slice(".", 0):
		return _fail(id, "Necesita la API %s (Vectopen tiene la %s)" % [info["api"], VectopenAPI.API_VERSION])
	var cap := _ErrorCapture.new()
	OS.add_logger(cap)
	var script := ResourceLoader.load(String(info["main"]), "", ResourceLoader.CACHE_MODE_REPLACE) as Script
	var inst: Object = script.new() if script and script.can_instantiate() else null
	OS.remove_logger(cap)
	if inst == null or not (inst is Node):
		if inst and not (inst is RefCounted):
			inst.free()
		return _fail(id, cap.first("No se pudo cargar %s" % String(info["main"]).get_file()))
	var node := inst as Node
	if not (node is VectopenAddon) and not node.has_method("on_load"):
		node.free()
		return _fail(id, "main.gd debe heredar de VectopenAddon")
	node.name = id
	add_child(node)
	OS.add_logger(cap)
	if node is VectopenAddon:
		node.addon_id = id
		node.info = info.duplicate()
		node._vp_enable(api)
	else:
		node.call("on_load")
	OS.remove_logger(cap)
	if not cap.errors.is_empty():
		_teardown(id, node)
		return _fail(id, cap.first(""))
	_instances[id] = node
	_loaded_order.append(id)
	if persist:
		_save_enabled(id, true)
	plugin_loaded.emit(id)
	addons_changed.emit()
	return ""

func disable(id: String, persist: bool = true) -> void:
	if _instances.has(id):
		var node: Node = _instances[id]
		_instances.erase(id)
		_loaded_order.erase(id)
		_teardown(id, node)
		plugin_unloaded.emit(id)
	if persist:
		_save_enabled(id, false)
	addons_changed.emit()

func _teardown(_id: String, node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is VectopenAddon:
		node._vp_disable()
	elif node.has_method("on_unload"):
		node.call("on_unload")
	if node.get_parent() == self:
		remove_child(node)
	node.queue_free()

func _fail(id: String, msg: String) -> String:
	if _addons.has(id):
		_addons[id]["error"] = msg
	plugin_error.emit(id, msg)
	addons_changed.emit()
	return msg

## Recarga el código de un complemento activo (tras editarlo en disco).
func reload(id: String) -> String:
	var was := _instances.has(id)
	disable(id, false)
	refresh()
	return enable(id, false) if was else ""

# ── instalar / desinstalar ───────────────────────────────────────────────────
## Instala desde un .zip, una carpeta o un .gd. Devuelve {ok, id, error}.
## Si ya existía se actualiza (y se reactiva si estaba activo).
func install(path: String) -> Dictionary:
	var src := path.trim_suffix("/")
	var res: Dictionary
	if src.get_extension().to_lower() == "zip":
		res = _install_zip(src)
	elif DirAccess.dir_exists_absolute(src):
		res = _install_dir(src)
	elif src.get_extension().to_lower() == "gd":
		res = _install_gd(src)
	else:
		res = {"ok": false, "id": "", "error": "Formato no válido: usa .zip, una carpeta o un .gd"}
	if res["ok"]:
		var id := String(res["id"])
		var was := _instances.has(id)
		if was:
			disable(id, false)
		refresh()
		if was:
			enable(id, false)
	return res

func _install_zip(zip_path: String) -> Dictionary:
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return {"ok": false, "id": "", "error": "No se pudo abrir el .zip"}
	var files := zr.get_files()
	# addon.cfg en la raíz o dentro de UNA carpeta (lo normal en un zip).
	var prefix := ""
	var found := false
	for f in files:
		if f.get_file() == "addon.cfg" and f.count("/") <= 1:
			prefix = f.get_base_dir()
			found = true
			break
	if not found:
		zr.close()
		return {"ok": false, "id": "", "error": "El .zip no contiene addon.cfg"}
	var id := _safe_id(prefix if prefix != "" else zip_path.get_file().get_basename())
	var dest := USER_DIR + id + "/"
	_remove_dir(dest)
	DirAccess.make_dir_recursive_absolute(dest)
	for f in files:
		if f.ends_with("/") or (prefix != "" and not f.begins_with(prefix + "/")):
			continue
		var rel := f.substr(prefix.length() + 1) if prefix != "" else f
		if rel.is_empty() or ".." in rel.split("/"):
			continue
		DirAccess.make_dir_recursive_absolute((dest + rel).get_base_dir())
		var fa := FileAccess.open(dest + rel, FileAccess.WRITE)
		if fa:
			fa.store_buffer(zr.read_file(f))
			fa.close()
	zr.close()
	return _check_installed(id)

func _install_dir(dir: String) -> Dictionary:
	if not FileAccess.file_exists(dir + "/addon.cfg") and not FileAccess.file_exists(dir + "/main.gd"):
		return {"ok": false, "id": "", "error": "La carpeta no tiene addon.cfg ni main.gd"}
	var id := _safe_id(dir.get_file())
	var dest := USER_DIR + id + "/"
	if ProjectSettings.globalize_path(dest).trim_suffix("/") == ProjectSettings.globalize_path(dir):
		return _check_installed(id)
	_remove_dir(dest)
	_copy_dir(dir, dest)
	if not FileAccess.file_exists(dest + "addon.cfg"):
		_write_cfg(dest, id)
	return _check_installed(id)

func _install_gd(file: String) -> Dictionary:
	var id := _safe_id(file.get_file().get_basename())
	var dest := USER_DIR + id + "/"
	_remove_dir(dest)
	DirAccess.make_dir_recursive_absolute(dest)
	DirAccess.copy_absolute(file, dest + "main.gd")
	_write_cfg(dest, id)
	return _check_installed(id)

func _write_cfg(dest: String, id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("addon", "name", id.capitalize())
	cfg.set_value("addon", "version", "1.0.0")
	cfg.set_value("addon", "description", "")
	cfg.set_value("addon", "api", VectopenAPI.API_VERSION)
	cfg.set_value("addon", "main", "main.gd")
	cfg.save(dest + "addon.cfg")

func _check_installed(id: String) -> Dictionary:
	var dir := USER_DIR + id + "/"
	var cfg := ConfigFile.new()
	cfg.load(dir + "addon.cfg")
	var main := dir + String(cfg.get_value("addon", "main", "main.gd"))
	if not FileAccess.file_exists(main):
		_remove_dir(dir)
		return {"ok": false, "id": id, "error": "Falta %s" % main.get_file()}
	return {"ok": true, "id": id, "error": ""}

## Borra un complemento instalado por el usuario (los incluidos no).
func uninstall(id: String) -> bool:
	var info: Dictionary = _addons.get(id, {})
	if info.is_empty() or bool(info["builtin"]):
		return false
	disable(id, false)
	if bool(info["legacy"]):
		DirAccess.remove_absolute(String(info["main"]))
	else:
		_remove_dir(String(info["dir"]))
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	if cfg.has_section_key("enabled", id):
		cfg.erase_section_key("enabled", id)
	if cfg.has_section("settings:" + id):
		cfg.erase_section("settings:" + id)
	cfg.save(CONFIG_PATH)
	refresh()
	return true

## Carpeta de complementos del usuario (para abrirla en el gestor de archivos).
func user_dir() -> String:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	return ProjectSettings.globalize_path(USER_DIR)

static func _safe_id(s: String) -> String:
	var id := s.get_file().strip_edges().to_snake_case().validate_filename().replace(" ", "_")
	return id if id != "" else "addon"

static func _remove_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_remove_dir(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)

static func _copy_dir(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for d in DirAccess.get_directories_at(from):
		if not d.begins_with("."):
			_copy_dir(from.path_join(d), to.path_join(d))
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))

# ── estado persistente ───────────────────────────────────────────────────────
func _wants_enabled(id: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	if cfg.has_section_key("enabled", id):
		return bool(cfg.get_value("enabled", id))
	# Formato antiguo: lista de desactivados.
	var old := ConfigFile.new()
	if old.load(LEGACY_CONFIG_PATH) == OK and old.has_section_key(id, "disabled"):
		return not bool(old.get_value(id, "disabled"))
	return bool(_addons[id].get("default_enabled", false))

func _save_enabled(id: String, on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("enabled", id, on)
	cfg.save(CONFIG_PATH)

class _ErrorCapture extends Logger:
	var errors: PackedStringArray = []
	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var msg := (rationale if rationale != "" else code).trim_prefix("Parse Error: ")
		errors.append("%s:%d — %s" % [file.get_file(), line, msg] if file != "" else msg)
	func first(fallback: String) -> String:
		return errors[0] if not errors.is_empty() else fallback

# ── compatibilidad con la API anterior ───────────────────────────────────────
func get_plugin(p_name: String) -> Node:
	return get_addon(p_name)

func get_all_plugins() -> Array[String]:
	return _loaded_order.duplicate()

func is_plugin_loaded(p_name: String) -> bool:
	return is_enabled(p_name)

func disable_plugin(p_name: String) -> void:
	disable(p_name)

func reload_plugin(p_name: String) -> void:
	disable(p_name, false)
	refresh()
	enable(p_name)
