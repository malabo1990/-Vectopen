# =============================================================================
# RUTA: res://script_gdscript/tools/move/select_prefs.gd
# Preferencias de selección de la herramienta Mover (USR-38).
# · deep_select = «Selección directa (atravesar grupos)»: el clic coge el
#   objeto que hay bajo el cursor aunque esté dentro de grupos; Ctrl + clic
#   coge entonces el grupo de primer nivel (al revés que por defecto, como
#   la selección directa de Illustrator / Affinity).
# Se guarda en user://vectopen_files.cfg, sección "select".
# =============================================================================
extends RefCounted

const PREFS_PATH := "user://vectopen_files.cfg"

static var _loaded := false
static var _deep := false

static func deep_select() -> bool:
	if not _loaded:
		_loaded = true
		var cfg := ConfigFile.new()
		if cfg.load(PREFS_PATH) == OK:
			_deep = bool(cfg.get_value("select", "deep_select", false))
	return _deep

static func set_deep_select(on: bool) -> void:
	_loaded = true
	_deep = on
	var cfg := ConfigFile.new()
	cfg.load(PREFS_PATH)
	cfg.set_value("select", "deep_select", on)
	cfg.save(PREFS_PATH)
