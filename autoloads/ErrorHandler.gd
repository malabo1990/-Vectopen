# =============================================================================
# VECTOPEN CORE — ERROR HANDLER
# RUTA: res://autoloads/ErrorHandler.gd
# ORDEN DE CARGA: Primero (antes que cualquier autoload)
# =============================================================================
extends Node

## Sistema centralizado de manejo de errores.
## Proporciona reporte estructurado con categorías y severidad.

signal error_reported(category: String, code: int, message: String, severity: int)
signal warning_reported(category: String, message: String)

enum Severity {
	INFO,
	WARNING,
	ERROR,
	CRITICAL
}

enum Category {
	TOOL = 1,
	POOL = 2,
	CURSOR = 3,
	FILE = 4,
	CONFIG = 5,
	INPUT = 6,
	SCENE = 7,
	NETWORK = 8,
	GENERAL = 99
}

const CATEGORY_NAMES := {
	Category.TOOL: "Tool",
	Category.POOL: "Pool",
	Category.CURSOR: "Cursor",
	Category.FILE: "File",
	Category.CONFIG: "Config",
	Category.INPUT: "Input",
	Category.SCENE: "Scene",
	Category.NETWORK: "Network",
	Category.GENERAL: "General"
}

var _error_count: int = 0
var _warning_count: int = 0


func report(category: int, message: String, severity: int = Severity.ERROR, code: int = 0) -> void:
	var cat_name = CATEGORY_NAMES.get(category, "Unknown")
	var prefix = "[%s] " % cat_name

	match severity:
		Severity.INFO:
			print(prefix + message)
		Severity.WARNING:
			_warning_count += 1
			push_warning(prefix + message)
			warning_reported.emit(cat_name, message)
		Severity.ERROR:
			_error_count += 1
			push_error(prefix + " (code=%d) " % code + message)
			error_reported.emit(cat_name, code, message, severity)
		Severity.CRITICAL:
			_error_count += 1
			push_error(prefix + " [CRITICAL] (code=%d) " % code + message)
			error_reported.emit(cat_name, code, message, severity)


func report_tool(message: String, severity: int = Severity.ERROR, code: int = 0) -> void:
	report(Category.TOOL, message, severity, code)


func report_pool(message: String, severity: int = Severity.ERROR, code: int = 0) -> void:
	report(Category.POOL, message, severity, code)


func report_file(message: String, severity: int = Severity.ERROR, code: int = 0) -> void:
	report(Category.FILE, message, severity, code)


func report_config(message: String, severity: int = Severity.ERROR, code: int = 0) -> void:
	report(Category.CONFIG, message, severity, code)


func get_counts() -> Dictionary:
	return {
		"errors": _error_count,
		"warnings": _warning_count
	}


func reset_counts() -> void:
	_error_count = 0
	_warning_count = 0

# ── USR-35: errores de la app → informe y «Enviar a técnico» ─────────────────
const _BugReport = preload("res://script_gdscript/system/bug_report.gd")
const NOTICE_GAP_MS := 60000
var _app_logger: Logger = null
var _last_notice_ms := -NOTICE_GAP_MS
var _seen := {}

class _AppErrorLogger extends Logger:
	var owner_node: Node = null
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var text := rationale if rationale != "" else code
		var where := "%s:%d (%s)" % [file, line, function] if file != "" else function
		var trace := ""
		for bt in script_backtraces:
			if bt and not bt.is_empty():
				trace += bt.format(0, 2)
				# push_error / errores del motor: «dónde» = la línea del SCRIPT
				if (file == "" or not file.begins_with("res://")) and bt.get_frame_count() > 0:
					where = "%s:%d (%s)" % [bt.get_frame_file(0), bt.get_frame_line(0), bt.get_frame_function(0)]
		_BugReport.capture(text, where, trace)
		if is_instance_valid(owner_node):
			owner_node.call_deferred("_on_app_error", text)

func _enter_tree() -> void:
	if _app_logger == null:
		_app_logger = _AppErrorLogger.new()
		_app_logger.owner_node = self
		OS.add_logger(_app_logger)

func _exit_tree() -> void:
	if _app_logger:
		OS.remove_logger(_app_logger)
		_app_logger = null

## Aviso «Se ha producido un error… · clic = enviar a técnico»: como mucho uno
## por minuto y una vez por cada error distinto (no molestar).
func _on_app_error(text: String) -> void:
	var key := text.substr(0, 120)
	if _seen.has(key):
		return
	_seen[key] = true
	var now := Time.get_ticks_msec()
	if now - _last_notice_ms < NOTICE_GAP_MS:
		return
	_last_notice_ms = now
	var un := get_node_or_null("/root/UserNotices")
	if un and un.has_method("show_notice"):
		un.show_notice("error", tr("Se ha producido un error interno. Clic para enviar el informe al técnico."),
			func() -> void: open_contact("bug"))

## Diálogo «Contactar con el técnico» (Ayuda / Acerca de y el aviso de error).
func open_contact(kind: String = "bug") -> Window:
	return load("res://script_gdscript/ui/contact_dialog.gd").open(get_tree(), kind)
