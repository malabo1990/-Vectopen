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

	# Centrar el contenedor del viewport en el panel
	var svc := find_child("SubViewportContainer", true, false) as Control
	if svc:
		svc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Ajustar colores del título si es necesario para tema oscuro
	var header_lbl := find_child("Label", true, false) as Label
	if header_lbl and header_lbl.get_parent() and header_lbl.get_parent().name == "HBoxContainer":
		header_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.92, 1.0))
		header_lbl.text = tr("Vista previa")

	await get_tree().process_frame
	
	var root_actual = get_tree().current_scene
	if root_actual:
		artboard_real = root_actual.find_child("Artboard", true, false) as Node2D
	
	if artboard_real:
		sub_viewport.world_2d = artboard_real.get_viewport().world_2d
		camera_miniatura.make_current()
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

		_configurar_slider()
		_actualizar_posicion_camara()
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

func _get_artboard_size() -> Vector2:
	if not is_instance_valid(artboard_real):
		return Vector2(800, 600)
	if "artboard_size" in artboard_real:
		return artboard_real.artboard_size
	if "size" in artboard_real:
		return artboard_real.get("size")
	return Vector2(800, 600)

func _actualizar_posicion_camara() -> void:
	if not is_instance_valid(artboard_real) or not is_instance_valid(camera_miniatura):
		return
	var ab_size := _get_artboard_size()
	camera_miniatura.global_position = artboard_real.global_position + (ab_size * 0.5)

func _configurar_slider() -> void:
	if not zoom_slider: return
	
	# Desconectamos para evitar duplicados si se reinicia la UI
	if zoom_slider.value_changed.is_connected(_on_zoom_slider_value_changed):
		zoom_slider.value_changed.disconnect(_on_zoom_slider_value_changed)

	zoom_slider.min_value = 0.05
	zoom_slider.max_value = 1.0
	zoom_slider.step = 0.01

	# Ajustar zoom inicial para encajar todo el artboard con margen
	var ab_size := _get_artboard_size()
	var vp_w := float(sub_viewport.size.x) if sub_viewport else 240.0
	var vp_h := float(sub_viewport.size.y) if sub_viewport else 240.0
	var fit_zoom := clampf(minf((vp_w - 20.0) / maxf(ab_size.x, 1.0), (vp_h - 20.0) / maxf(ab_size.y, 1.0)), 0.05, 1.0)
	zoom_slider.value = fit_zoom

	camera_miniatura.zoom = Vector2(fit_zoom, fit_zoom)
	_actualizar_texto_porcentaje(fit_zoom)
	
	zoom_slider.value_changed.connect(_on_zoom_slider_value_changed)

func _on_zoom_slider_value_changed(value: float) -> void:
	if is_instance_valid(camera_miniatura):
		camera_miniatura.zoom = Vector2(value, value)
		_actualizar_texto_porcentaje(value)

func _actualizar_texto_porcentaje(valor_zoom: float) -> void:
	if label_porcentaje:
		label_porcentaje.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1.0))
		var porcentaje_entero = roundi(valor_zoom * 100)
		label_porcentaje.text = str(porcentaje_entero) + "%"
