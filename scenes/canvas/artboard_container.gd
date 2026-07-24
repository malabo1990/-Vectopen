# res://scenes/canvas/artboard_container.gd
extends Container # Tu contenedor principal del lienzo

@export var bounding_box_scene: PackedScene = preload("res://scenes/canvas/boundingbox.tscn")

var current_bounding_box: Control = null
var current_tool_instance: Tool = null # Aquí guardas la instancia de MoveTool cuando se activa

func _ready() -> void:
	if bounding_box_scene:
		current_bounding_box = bounding_box_scene.instantiate()
		add_child(current_bounding_box)
		current_bounding_box.hide()

## Llamar a esta función cuando el gestor de herramientas cambie a MoveTool
func set_active_tool(tool_instance: Tool) -> void:
	current_tool_instance = tool_instance

func _process(_delta: float) -> void:
	# Verificamos si la herramienta actual es MoveTool y si tiene elementos seleccionados
	if current_bounding_box and current_tool_instance and current_tool_instance.has_method("get_class_name") and current_tool_instance.selected_shapes.size() > 0:
		
		# Obtenemos el rectángulo macro que une todas las figuras (Figma style)
		var macro: Rect2 = current_tool_instance._get_macro_rect()
		
		# Obtenemos la escala de zoom actual del lienzo para que los tiradores no se deformen
		var t_scale: float = get_global_transform().get_scale().x
		if t_scale <= 0.001: t_scale = 1.0
		
		# Pasamos los datos al script del .tscn para que se dibuje perfectamente
		current_bounding_box.update_overlay(
			macro,
			current_tool_instance.current_blender_mode,
			current_tool_instance.current_axis,
			t_scale
		)
	else:
		if current_bounding_box and current_bounding_box.visible:
			current_bounding_box.hide()
