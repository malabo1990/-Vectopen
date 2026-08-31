extends PanelContainer
class_name FormatConfigPanel

## Configuración contextual por formato: los botones de formato (SVG, PNG,
## JPEG...) actúan como selector; al elegir uno se reconfiguran las
## propiedades de abajo (opciones del OptionButton, visibilidad de
## Resolución) como en la mayoría de apps con configuración.

signal format_selected(format: String, config: Dictionary)

const FORMATS := {
	"SVG": {"label": "Estilo", "options": ["Optimizado", "Legible"], "raster": false},
	"PNG": {"label": "Color", "options": ["RGBA", "RGB"], "raster": true},
	"JPEG": {"label": "Calidad", "options": ["Alta", "Media", "Baja"], "raster": true},
	"JPEG XL": {"label": "Calidad", "options": ["Sin pérdida", "Con pérdida"], "raster": true},
	"WEBP": {"label": "Color", "options": ["RGBA", "RGB"], "raster": true},
	"EPS": {"label": "Espacio de color", "options": ["CMYK", "RGB"], "raster": false},
	"PDF": {"label": "Página", "options": ["A4", "Carta"], "raster": false},
	"TSCN": {"label": "Estilo", "options": ["Texto", "Binario"], "raster": false},
	"SCN": {"label": "Estilo", "options": ["Texto", "Binario"], "raster": false},
	"VOP": {"label": "Estilo", "options": ["Compacto", "Completo"], "raster": false},
}

const BUTTON_FORMATS := {
	"BtnSVG": "SVG",
	"BtnPNG": "PNG",
	"BtnJPEG": "JPEG",
	"BtnJPEGXL": "JPEG XL",
	"BtnWEBP": "WEBP",
	"BtnEPS": "EPS",
	"BtnPDF": "PDF",
	"BtnTSCN": "TSCN",
	"BtnSCN": "SCN",
	"BtnVOP": "VOP",
}

@onready var _format_grid: GridContainer = $MarginContainer/VBoxContainer/FormatGrid
@onready var _label_formato: Label = $MarginContainer/VBoxContainer/FormatoHBox/LabelFormato
@onready var _option_format: OptionButton = $MarginContainer/VBoxContainer/FormatoHBox/OptionFormat
@onready var _resolution_row: HBoxContainer = $MarginContainer/VBoxContainer/ResolucionHBox

var selected_format: String = "SVG"

func _ready() -> void:
	for button in _format_grid.get_children():
		if button is Button and BUTTON_FORMATS.has(button.name):
			_set_black_text(button)
			button.pressed.connect(_on_format_button_pressed.bind(button.name))
	_set_black_text(_option_format)
	_apply_format(selected_format)

func _set_black_text(control: Control) -> void:
	if control:
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			control.add_theme_color_override(color_name, Color.BLACK)

func _on_format_button_pressed(button_name: String) -> void:
	_apply_format(BUTTON_FORMATS[button_name])

func _apply_format(format: String) -> void:
	if not FORMATS.has(format):
		return
	selected_format = format
	var config: Dictionary = FORMATS[format]
	_label_formato.text = config["label"]
	_option_format.clear()
	for option in config["options"]:
		_option_format.add_item(option)
	_option_format.select(0)
	_resolution_row.visible = config["raster"]
	format_selected.emit(format, get_config())

func get_config() -> Dictionary:
	var cfg: Dictionary = FORMATS[selected_format]
	return {
		"format": selected_format,
		"option": cfg["options"][_option_format.selected if _option_format else 0],
		"quantity": _get_spin_value("CantidadHBox/SpinBoxCantidad"),
		"resolution": _get_spin_value("ResolucionHBox/SpinBoxResolucion"),
		"work_table": _get_spin_value("MesaTrabajoHBox/SpinBoxMesa"),
	}

func _get_spin_value(path: String) -> float:
	var node := get_node_or_null("MarginContainer/VBoxContainer/" + path)
	if node and "value" in node:
		return node.value
	return 0.0
