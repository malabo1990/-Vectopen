# ==========================================
# RUTA: res://scripts/GlobalUI.gd
# CONFIGURACIÓN: Mantener como Autoload (Singleton)
# ==========================================
extends Node

# ==========================================
# SISTEMA DE INTERFAZ ADAPTABLE (THREE UI MODES)
# ==========================================
const MODE_SMART := "smart"
const MODE_MODERN := "modern"
const MODE_PROFESSIONAL := "professional"
const VALID_MODES: Array[String] = [MODE_SMART, MODE_MODERN, MODE_PROFESSIONAL]
const CONFIG_PATH := "user://vectopen_ui.cfg"

signal ui_mode_changed(new_mode: String)

var ui_mode: String:
	get:
		return _ui_mode
	set(value):
		set_ui_mode(value)

var _ui_mode: String = MODE_SMART

# Controla si el puntero está interactuando con los paneles o menús
var is_mouse_over_ui: bool = false

func _ready() -> void:
	_ui_mode = _load_ui_mode()

func get_ui_mode() -> String:
	return _ui_mode

func set_ui_mode(new_mode: String) -> void:
	var m: String = new_mode.to_lower().strip_edges()
	if not VALID_MODES.has(m):
		push_warning("GlobalUI: Modo de UI inválido '%s'. Modos válidos: %s" % [new_mode, str(VALID_MODES)])
		return
	if _ui_mode == m:
		return
	_ui_mode = m
	_save_ui_mode(m)
	ui_mode_changed.emit(_ui_mode)
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("ui_mode_changed"):
		ge.emit_safe("ui_mode_changed", _ui_mode)

func is_smart_mode() -> bool:
	return _ui_mode == MODE_SMART

func is_modern_mode() -> bool:
	return _ui_mode == MODE_MODERN

func is_professional_mode() -> bool:
	return _ui_mode == MODE_PROFESSIONAL

func _load_ui_mode() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return MODE_SMART
	var loaded: String = cfg.get_value("ui", "mode", MODE_SMART)
	if VALID_MODES.has(loaded):
		return loaded
	return MODE_SMART

func _save_ui_mode(mode: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("ui", "mode", mode)
	cfg.save(CONFIG_PATH)


func _process(_delta: float) -> void:
	var viewport := get_viewport()
	if not viewport:
		return
	# Se considera UI SOLO si el Control bajo el cursor pertenece a la interfaz
	# (bajo un CanvasLayer o Window). Los Controles del lienzo —boundingbox,
	# títulos de artboard, handles— viven bajo Node2D y NO deben bloquear
	# el zoom ni el arrastre del canvas. Ver _es_ui_real()
	is_mouse_over_ui = _es_ui_real(viewport.gui_get_hovered_control())

## Un Control es de la UI real si, subiendo por el árbol, aparece un
## CanvasLayer (paneles de main.tscn) o un Window (diálogos/popups) ANTES
## que un Node2D (el mundo del lienzo). Los controles del mundo no son UI.
func _es_ui_real(control: Control) -> bool:
	if control == null:
		return false
	var node: Node = control
	while node:
		if node is CanvasLayer or node is Window:
			return true
		if node is Node2D:
			return false
		node = node.get_parent()
	return true
