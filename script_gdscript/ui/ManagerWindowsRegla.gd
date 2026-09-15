# =============================================================================
# VECTOPEN — GESTOR DE VENTANA DE CONFIGURACIÓN Y REGLAS
# RUTA: res://script_gdscript/ui/ManagerWindowsRegla.gd
# Controla la apertura, cierre (botón ✕, tecla ESC) y visibilidad del panel
# =============================================================================
class_name ManagerWindowsRegla
extends PanelContainer

signal closed
signal opened

@onready var btn_close: Button = find_child("BtnClose", true, false) as Button

func _ready() -> void:
	if not btn_close:
		btn_close = find_child("ButtonClose", true, false) as Button
	if btn_close and not btn_close.pressed.is_connected(close_settings):
		btn_close.pressed.connect(close_settings)

func open_settings() -> void:
	visible = true
	move_to_front()
	opened.emit()

func close_settings() -> void:
	visible = false
	closed.emit()

func toggle_settings() -> void:
	if visible:
		close_settings()
	else:
		open_settings()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_settings()
		get_viewport().set_input_as_handled()
