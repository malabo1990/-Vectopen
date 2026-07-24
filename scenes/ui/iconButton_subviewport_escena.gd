@tool
extends Node

@export var boton_objetivo : Button:
	set(valor):
		boton_objetivo = valor
		if Engine.is_editor_hint():
			_actualizar_icono_en_editor()

@export var escena_con_viewport : PackedScene:
	set(valor):
		escena_con_viewport = valor
		if Engine.is_editor_hint():
			_actualizar_icono_en_editor()

var _instancia_actual: Node = null

func _ready() -> void:
	_actualizar_icono_en_editor()

func _actualizar_icono_en_editor() -> void:
	if not boton_objetivo or not escena_con_viewport:
		return

	# Limpieza segura de instancias viejas
	if _instancia_actual and is_instance_valid(_instancia_actual):
		_instancia_actual.queue_free()
		_instancia_actual = null

	# 1. Instanciamos la escena
	var nueva_instancia = escena_con_viewport.instantiate()
	_instancia_actual = nueva_instancia
	
	# 2. Buscamos el SubViewport interno
	var sub_viewport = nueva_instancia.get_node_or_null("SubViewport")
	if not sub_viewport or not sub_viewport is SubViewport:
		return
		
	# 3. Forzamos modo de actualización
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	# 4. Añadimos el hijo de forma diferida
	boton_objetivo.add_child.call_deferred(nueva_instancia)
	
	# 5. Ocultamos la raíz de la escena para que no estorbe visualmente
	if nueva_instancia is CanvasItem or nueva_instancia is Node3D:
		nueva_instancia.visible = false

	# 6. Esperamos un instante seguro para enlazar la textura final
	(func():
		if is_instance_valid(sub_viewport) and is_instance_valid(boton_objetivo):
			var textura_lista = sub_viewport.get_texture()
			if textura_lista:
				# --- CAMBIO 1: Evitamos que la textura se serialice en el .tscn ---
				textura_lista.resource_local_to_scene = false
				boton_objetivo.icon = textura_lista
	).call_deferred()

# --- CAMBIO 2: Limpieza absoluta al salir del árbol o guardar ---
func _exit_tree() -> void:
	if is_instance_valid(boton_objetivo):
		boton_objetivo.icon = null # Rompe la referencia antes de guardar
	if _instancia_actual and is_instance_valid(_instancia_actual):
		_instancia_actual.queue_free()
		_instancia_actual = null
