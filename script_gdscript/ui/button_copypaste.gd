extends Control

@export var button_pega: Button
@export var button_copia: Button
@export var lineedit: LineEdit
@export var label_tooltip: Label

var copied_value: String = ""

func _ready():
	# Conectar señales de los botones
	if button_copia:
		button_copia.pressed.connect(_on_copy_pressed)
		button_copia.mouse_entered.connect(_on_copy_mouse_entered)
		button_copia.mouse_exited.connect(_on_mouse_exited)
	if button_pega:
		button_pega.pressed.connect(_on_paste_pressed)
		button_pega.mouse_entered.connect(_on_paste_mouse_entered)
		button_pega.mouse_exited.connect(_on_mouse_exited)
	
	# Inicializar tooltip
	if label_tooltip:
		label_tooltip.text = ""

func _on_copy_pressed():
	if lineedit:
		copied_value = lineedit.text
		# Opcional: Copiar al portapapeles del sistema
		DisplayServer.clipboard_set(copied_value)

func _on_paste_pressed():
	if lineedit:
		# Priorizar valor copiado internamente, sino usar portapapeles
		var value_to_paste = copied_value if copied_value != "" else DisplayServer.clipboard_get()
		lineedit.text = value_to_paste

func _on_copy_mouse_entered():
	if label_tooltip:
		label_tooltip.text = "Copy"

func _on_paste_mouse_entered():
	if label_tooltip:
		label_tooltip.text = "Paste"

func _on_mouse_exited():
	if label_tooltip:
		label_tooltip.text = ""
