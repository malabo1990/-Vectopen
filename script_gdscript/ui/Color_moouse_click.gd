# ==========================================
# RUTA: res://scripts/tu_nodo_control.gd
# ==========================================
extends Control

# Exportar referencias a los ColorRect
@export var colorrect_verde: ColorRect
@export var colorrect_amarillo: ColorRect
@export var colorrect_rojo: ColorRect

# Exportar colores de activación
@export var color_verde: Color = Color.GREEN
@export var color_amarillo: Color = Color.YELLOW
@export var color_rojo: Color = Color.RED

# Guardar los colores originales
var color_original_verde: Color
var color_original_amarillo: Color
var color_original_rojo: Color

# Referencia al CanvasRoot
var _canvas_root: Node = null

func _ready() -> void:
	# Forzamos que este panel capture los clics pero no bloquee de forma destructiva
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	if colorrect_verde: color_original_verde = colorrect_verde.color
	if colorrect_amarillo: color_original_amarillo = colorrect_amarillo.color
	if colorrect_rojo: color_original_rojo = colorrect_rojo.color

	# Buscamos el nodo CanvasRoot según tu árbol de escenas (visto en tu captura)
	var current_scene := get_tree().current_scene if get_tree() else null
	if current_scene:
		_canvas_root = current_scene.find_child("CanvasRoot", true, false)
		if not _canvas_root:
			_canvas_root = current_scene

func _gui_input(event: InputEvent) -> void:
	# 1. FORZADO DIRECTO DE ENTRADA A LA HERRAMIENTA ACTIVA
	if is_instance_valid(_canvas_root):
		# Buscamos si el canvas tiene guardada la herramienta activa en alguna variable común
		var herramienta = _canvas_root.get("current_tool")
		
		# Si no la encuentra ahí, la buscamos dentro del gestor de scripts alternativo
		if herramienta == null and _canvas_root.has_node("Manager_script"):
			herramienta = _canvas_root.get_node("Manager_script").get("current_tool")
			
		if herramienta and herramienta.has_method("handle_input"):
			print("Diagnóstico Vectopen: Forzando envío de clic a la herramienta...")
			herramienta.handle_input(event)

	# 2. SISTEMA VISUAL DE COLORRECTS (Tu lógica original de testeo)
	if not event is InputEventMouseButton:
		return
	
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				if colorrect_verde: colorrect_verde.color = color_verde
				print("Click izquierdo PRESIONADO → Verde")
			else:
				if colorrect_verde: colorrect_verde.color = color_original_verde
				print("Click izquierdo LIBERADO → Color original")
		
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if colorrect_rojo: colorrect_rojo.color = color_rojo
				print("Click derecho PRESIONADO → Rojo")
			else:
				if colorrect_rojo: colorrect_rojo.color = color_original_rojo
				print("Click derecho LIBERADO → Color original")
				
		MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				if colorrect_amarillo: colorrect_amarillo.color = color_amarillo
				print("Click central PRESIONADO → Amarillo")
			else:
				if colorrect_amarillo: colorrect_amarillo.color = color_original_amarillo
				print("Click central LIBERADO → Color original")
