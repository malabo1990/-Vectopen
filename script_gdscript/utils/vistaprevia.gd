# ==============================================================================
# RUTA: res://script_gdscript/utils/vistaprevia.gd
# VISTA PREVIA = NAVEGADOR (estilo Affinity / Figma):
#   · muestra la mesa de trabajo ACTIVA (antes siempre la primera) y se
#     reencuadra sola al cambiar de mesa o de tamaño;
#   · un recuadro de acento marca la zona que se ve en el lienzo;
#   · clic o arrastre dentro de la miniatura lleva el lienzo a ese punto;
#   · no pinta lo del editor (caja de selección, superposición de la
#     herramienta, títulos de las mesas): van en EDITOR_LAYER, que la
#     miniatura no dibuja (canvas_cull_mask).
# El slider sigue fijando el zoom de la miniatura.
# ==============================================================================
extends Control

@export_category("Componentes de UI")
@export var zoom_slider: Slider
@export var label_porcentaje: Label

## Capa de visibilidad de lo que solo es del editor (bit 2). El lienzo dibuja
## todas las capas; la miniatura solo la 1.
const EDITOR_LAYER := 2

var sub_viewport: SubViewport
var camera_miniatura: Camera2D
var artboard_real: Node2D
var _container: SubViewportContainer
var _view_rect: Control
var _fit_sig := ""

## El minimapa comparte world_2d con el lienzo, así que RE-RENDERIZA toda la
## escena. Lo refrescamos solo PREVIEW_HZ veces por segundo: para un minimapa
## es de sobra y devuelve ~toda la GPU al lienzo principal.
const PREVIEW_HZ := 6.0
var _preview_accum := 999.0

func _ready() -> void:
	sub_viewport = find_child("SubViewport", true, false) as SubViewport
	camera_miniatura = find_child("Camera2D", true, false) as Camera2D
	if not sub_viewport or not camera_miniatura:
		push_error("VistaPrevia: Estructura incorrecta en Main.tscn.")
		return
	sub_viewport.canvas_cull_mask = 1   # sin la capa del editor

	_container = find_child("SubViewportContainer", true, false) as SubViewportContainer
	if _container:
		_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_container.mouse_filter = Control.MOUSE_FILTER_STOP
		_container.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_container.gui_input.connect(_on_preview_input)
		_view_rect = Control.new()
		_view_rect.name = "ViewRect"
		_view_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_view_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_view_rect.draw.connect(_draw_view_rect)
		_container.add_child(_view_rect)

	var header_lbl := find_child("Label", true, false) as Label
	if header_lbl and header_lbl.get_parent() and header_lbl.get_parent().name == "HBoxContainer":
		header_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.92, 1.0))
		header_lbl.text = tr("Vista previa")

	await get_tree().process_frame
	_resolve_artboard()
	if artboard_real:
		sub_viewport.world_2d = artboard_real.get_viewport().world_2d
		camera_miniatura.make_current()
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_configurar_slider()
		_actualizar_posicion_camara()
	else:
		push_warning("VistaPrevia: No se encontró el 'Artboard' activo.")

func _process(delta: float) -> void:
	if not is_instance_valid(sub_viewport) or not is_visible_in_tree():
		return
	_preview_accum += delta
	if _preview_accum < 1.0 / PREVIEW_HZ:
		return
	_preview_accum = 0.0
	_resolve_artboard()
	if is_instance_valid(artboard_real) and is_instance_valid(camera_miniatura):
		var sig := "%s|%s" % [artboard_real.get_instance_id(), _get_artboard_size()]
		if sig != _fit_sig:
			_fit_sig = sig
			_configurar_slider()
		_actualizar_posicion_camara()
	# UPDATE_ONCE renderiza UN frame y vuelve solo a UPDATE_DISABLED.
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _view_rect:
		_view_rect.queue_redraw()

## Mesa de trabajo ACTIVA (ArtboardManager) o, si no hay gestor, la primera.
func _resolve_artboard() -> void:
	var mgr = ArtboardManager.find(get_tree()) if is_inside_tree() else null
	var ab: Node2D = mgr.get_active_artboard() if mgr and mgr.has_method("get_active_artboard") else null
	if ab == null and get_tree().current_scene:
		ab = get_tree().current_scene.find_child("Artboard", true, false) as Node2D
	if ab and ab != artboard_real:
		artboard_real = ab
		if sub_viewport and sub_viewport.world_2d != ab.get_viewport().world_2d:
			sub_viewport.world_2d = ab.get_viewport().world_2d

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
	camera_miniatura.global_position = artboard_real.global_position + (_get_artboard_size() * 0.5)

func _configurar_slider() -> void:
	if not zoom_slider:
		return
	if zoom_slider.value_changed.is_connected(_on_zoom_slider_value_changed):
		zoom_slider.value_changed.disconnect(_on_zoom_slider_value_changed)
	zoom_slider.min_value = 0.02
	zoom_slider.max_value = 1.0
	zoom_slider.step = 0.01
	# Zoom que encaja la mesa entera con margen
	var ab_size := _get_artboard_size()
	var vp := Vector2(sub_viewport.size) if sub_viewport else Vector2(240, 240)
	var fit_zoom := clampf(minf((vp.x - 20.0) / maxf(ab_size.x, 1.0), (vp.y - 20.0) / maxf(ab_size.y, 1.0)), 0.02, 1.0)
	zoom_slider.value = fit_zoom
	camera_miniatura.zoom = Vector2(fit_zoom, fit_zoom)
	_actualizar_texto_porcentaje(fit_zoom)
	zoom_slider.value_changed.connect(_on_zoom_slider_value_changed)

func _on_zoom_slider_value_changed(value: float) -> void:
	if is_instance_valid(camera_miniatura):
		camera_miniatura.zoom = Vector2(value, value)
		_actualizar_texto_porcentaje(value)
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _actualizar_texto_porcentaje(valor_zoom: float) -> void:
	if label_porcentaje:
		label_porcentaje.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1.0))
		label_porcentaje.text = str(roundi(valor_zoom * 100)) + "%"

# ── navegador ────────────────────────────────────────────────────────────────
func _canvas() -> Node:
	return get_tree().get_first_node_in_group("_vectopen_canvas") if is_inside_tree() else null

func _main_camera() -> Camera2D:
	var c = _canvas()
	var cam = c.get("camera") if c else null
	return cam as Camera2D

## Punto de la miniatura (local al contenedor) → mundo, y al revés.
func _preview_to_world(p: Vector2) -> Vector2:
	var vs := Vector2(sub_viewport.size)
	return camera_miniatura.global_position + (p - vs * 0.5) / camera_miniatura.zoom.x

func _world_to_preview(w: Vector2) -> Vector2:
	var vs := Vector2(sub_viewport.size)
	return (w - camera_miniatura.global_position) * camera_miniatura.zoom.x + vs * 0.5

## Zona del mundo que se ve ahora en el lienzo principal.
func _main_view_world_rect() -> Rect2:
	var c = _canvas()
	if c == null:
		return Rect2()
	var vp: Viewport = c.get_viewport()
	return vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()

func _on_preview_input(ev: InputEvent) -> void:
	var go := false
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		go = true
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		go = true
	if not go:
		return
	var cam := _main_camera()
	if cam == null:
		return
	# centrar el lienzo en el punto pulsado de la miniatura
	var target := _preview_to_world(ev.position)
	var view := _main_view_world_rect()
	cam.global_position += target - view.get_center()
	_container.accept_event()
	if _view_rect:
		_view_rect.queue_redraw()

func _draw_view_rect() -> void:
	if not is_instance_valid(camera_miniatura) or not is_instance_valid(sub_viewport):
		return
	var view := _main_view_world_rect()
	if view.size == Vector2.ZERO:
		return
	var a := _world_to_preview(view.position)
	var b := _world_to_preview(view.end)
	var r := Rect2(a, b - a).intersection(Rect2(Vector2.ZERO, Vector2(sub_viewport.size)).grow(-1))
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var tm = get_node_or_null("/root/ThemeManager")
	var acc: Color = tm.get_color(tm.Slot.ACCENT) if tm else Color(0.2, 0.6, 1.0)
	_view_rect.draw_rect(r, Color(acc.r, acc.g, acc.b, 0.12), true)
	_view_rect.draw_rect(r, acc, false, 1.5)
