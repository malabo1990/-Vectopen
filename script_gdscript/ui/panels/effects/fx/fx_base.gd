extends PanelContainer
class_name EffectFxBase

## Base class for every effect entry added to the Effects panel's "+" list.
## Subclasses set effect_name in _ready() before calling super._ready(),
## then wire their own parameter controls via _emit_param().

signal remove_requested(fx_node: Node)
signal move_up_requested(fx_node: Node)
signal move_down_requested(fx_node: Node)
signal param_changed(fx_node: Node, prop: String, value: Variant)

var effect_name: String = ""
var is_updating_ui: bool = false

@onready var _enabled_checkbox: CheckBox = %Enabled
@onready var _remove_button: Button = %Remove
var _btn_up: Button = null
var _btn_down: Button = null

func _ready() -> void:
	_enabled_checkbox.toggled.connect(_on_enabled_toggled)
	_remove_button.pressed.connect(_on_remove_pressed)
	_setup_reorder_buttons()
	# Colores con el selector de la app (pickr_color_tool), como los paneles
	# de texto, en vez del ColorPicker genérico de Godot.
	var popover = load("res://script_gdscript/ui/pro/text_color_popover.gd")
	for cp in find_children("*", "ColorPickerButton", true, false):
		popover.attach(cp, tr(effect_name) if effect_name != "" else tr("Color"))
	# Diseño común (tarjeta plegable, campos pro, colores del tema). Diferido:
	# los efectos añaden filas propias tras super._ready() (tipo de desenfoque…).
	dress.call_deferred()

## Viste la tarjeta con el diseño del panel (también al cambiar de tema).
func dress() -> void:
	if not is_instance_valid(_enabled_checkbox):
		return
	var ui = load("res://script_gdscript/ui/panels/effects/fx_ui.gd")
	ui.dress_card(self, _enabled_checkbox.get_parent() as Container, "fx_" + effect_name)

func _setup_reorder_buttons() -> void:
	if not _remove_button:
		return
	var parent_header = _remove_button.get_parent()
	if not parent_header:
		return

	_btn_up = Button.new()
	_btn_up.text = "▲"
	_btn_up.tooltip_text = "Subir efecto"
	_btn_up.flat = true
	_btn_up.custom_minimum_size = Vector2(20, 20)
	_btn_up.add_theme_font_size_override("font_size", 9)
	_btn_up.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 1.0))
	_btn_up.add_theme_color_override("font_hover_color", Color(0.1, 0.5, 1.0, 1.0))
	_btn_up.pressed.connect(func(): move_up_requested.emit(self))

	_btn_down = Button.new()
	_btn_down.text = "▼"
	_btn_down.tooltip_text = "Bajar efecto"
	_btn_down.flat = true
	_btn_down.custom_minimum_size = Vector2(20, 20)
	_btn_down.add_theme_font_size_override("font_size", 9)
	_btn_down.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 1.0))
	_btn_down.add_theme_color_override("font_hover_color", Color(0.1, 0.5, 1.0, 1.0))
	_btn_down.pressed.connect(func(): move_down_requested.emit(self))

	var remove_idx = _remove_button.get_index()
	parent_header.add_child(_btn_up)
	parent_header.move_child(_btn_up, remove_idx)
	parent_header.add_child(_btn_down)
	parent_header.move_child(_btn_down, remove_idx + 1)

func _on_enabled_toggled(active: bool) -> void:
	if is_updating_ui:
		return
	_emit_param("enabled", active)

func _on_remove_pressed() -> void:
	remove_requested.emit(self)

func _emit_param(property: String, value: Variant) -> void:
	if is_updating_ui:
		return
	param_changed.emit(self, property, value)
	GlobalEvents.emit_safe("effect_parameter_updated", effect_name, property, value)

func get_params() -> Dictionary:
	return {
		"type": effect_name,
		"enabled": _enabled_checkbox.button_pressed if _enabled_checkbox else true,
	}

func set_params(dict: Dictionary) -> void:
	is_updating_ui = true
	if _enabled_checkbox and dict.has("enabled"):
		_enabled_checkbox.button_pressed = bool(dict["enabled"])
	is_updating_ui = false
