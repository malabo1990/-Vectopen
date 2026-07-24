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
