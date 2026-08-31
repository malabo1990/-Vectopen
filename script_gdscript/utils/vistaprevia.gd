# ==============================================================================
# RUTA: res://scripts/vistaprevia.gd
# SCRIPT LIMPIO: Respeta los valores originales del Slider del Inspector
# ==============================================================================
extends Control

@export_category("Componentes de UI")
@export var zoom_slider: Slider
@export var label_porcentaje: Label 

var sub_viewport: SubViewport
var camera_miniatura: Camera2D
var artboard_real: Node2D

## El minimapa comparte world_2d con el lienzo, así que RE-RENDERIZA toda la
## escena. A 60 FPS eso duplica el coste de dibujado y provoca tirones al hacer
## pan con muchas figuras. Lo refrescamos solo PREVIEW_HZ veces por segundo:
## para un minimapa es de sobra y devuelve ~toda la GPU al lienzo principal.
const PREVIEW_HZ := 6.0
var _preview_accum := 999.0

func _ready() -> void:
	sub_viewport = find_child("SubViewport", true, false) as SubViewport
	camera_miniatura = find_child("Camera2D", true, false) as Camera2D
	
	if not sub_viewport or not camera_miniatura:
		push_error("VistaPrevia: Estructura incorrecta en Main.tscn.")
		return

	await get_tree().process_frame
	
	var root_actual = get_tree().current_scene
	if root_actual:
		artboard_real = root_actual.find_child("Artboard", true, false) as Node2D
	
	if artboard_real:
		sub_viewport.world_2d = artboard_real.get_viewport().world_2d
		camera_miniatura.make_current()
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

		_actualizar_posicion_camara()
		_configurar_slider()
	else:
		push_warning("VistaPrevia: No se encontró el 'Artboard' activo.")

func _process(delta: float) -> void:
	if not is_instance_valid(sub_viewport):
		return
	_preview_accum += delta
	if _preview_accum < 1.0 / PREVIEW_HZ:
		return
	_preview_accum = 0.0
	if is_instance_valid(artboard_real) and is_instance_valid(camera_miniatura):
		_actualizar_posicion_camara()
	# UPDATE_ONCE renderiza UN frame y vuelve solo a UPDATE_DISABLED.
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _actualizar_posicion_camara() -> void:
	if "size" in artboard_real:
		camera_miniatura.global_position = artboard_real.global_position + (artboard_real.get("size") / 2)
	else:
		camera_miniatura.global_position = artboard_real.global_position

func _configurar_slider() -> void:
	if not zoom_slider: return
	
	# Desconectamos para evitar duplicados si se reinicia la UI
	if zoom_slider.value_changed.is_connected(_on_zoom_slider_value_changed):
		zoom_slider.value_changed.disconnect(_on_zoom_slider_value_changed)
	
	# Sincronizamos la cámara con el valor actual que tenga tu slider en el editor
	camera_miniatura.zoom = Vector2(zoom_slider.value, zoom_slider.value)
	
	# Mostramos el porcentaje inicial basado en tu diseño original
	_actualizar_texto_porcentaje(zoom_slider.value)
	
	zoom_slider.value_changed.connect(_on_zoom_slider_value_changed)

func _on_zoom_slider_value_changed(value: float) -> void:
	if is_instance_valid(camera_miniatura):
		camera_miniatura.zoom = Vector2(value, value)
		_actualizar_texto_porcentaje(value)

func _actualizar_texto_porcentaje(valor_zoom: float) -> void:
	if label_porcentaje:
		var porcentaje_entero = roundi(valor_zoom * 100)
		label_porcentaje.text = str(porcentaje_entero) + "%"
