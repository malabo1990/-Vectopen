# ==========================================
# RUTA: res://scripts/managercolor_pickrColor.gd
# ==========================================
extends Node
class_name GestorColor

# 1. Referencias de Interfaz
@export var nodo_color_rect: ColorRect
@export var _brillo_slider: VSlider

# 2. Señal local por si algún sub-nodo de la herramienta quiere escuchar de forma directa
signal color_actualizado(nuevo_color: Color)

func _ready() -> void:
	if _brillo_slider:
		_brillo_slider.value_changed.connect(_on_brillo_changed)
		# Aplicar el valor inicial del slider al color (configurable en el inspector)
		_on_brillo_changed(_brillo_slider.value)
	
	# Si tenemos asignado el bloque visual, emitimos su color inicial al sistema
	if is_instance_valid(nodo_color_rect):
		_notificar_cambio_color(nodo_color_rect.color)
	
	# CONEXIÓN MAESTRA: Escuchar los cambios globales si vienen del Gradient u otros pickers
	if GlobalEvents.has_signal("gradient_changed") and not GlobalEvents.gradient_changed.is_connected(_on_global_gradient_changed):
		GlobalEvents.gradient_changed.connect(_on_global_gradient_changed)

# 3. Función SET profesional (Modifica el color y lo comunica a todo tu motor)
func establecer_color(nuevo_color: Color) -> void:
	if not is_instance_valid(nodo_color_rect): 
		return
		
	if nodo_color_rect.color != nuevo_color:
		nodo_color_rect.color = nuevo_color
		_notificar_cambio_color(nuevo_color)

# 4. Función GET limpia para que las herramientas de dibujo lean el color plano activo
func obtener_color() -> Color:
	if is_instance_valid(nodo_color_rect):
		return nodo_color_rect.color
	return Color.WHITE

# ── Control de Brillo ────────────────────────────────────────────────────────

func _on_brillo_changed(valor: float) -> void:
	if not is_instance_valid(nodo_color_rect) or not _brillo_slider:
		return
	var c := nodo_color_rect.color
	var v := valor / _brillo_slider.max_value
	var nuevo := Color.from_hsv(c.h, c.s, v, c.a)
	if nuevo != c:
		establecer_color(nuevo)

# ── Gestión Interna de Eventos (Cero Bucle Process) ───────────────────────────

# Centraliza la transmisión del color a todas las capas y objetos seleccionados
func _notificar_cambio_color(color_final: Color) -> void:
	# A) Emitir señal local del componente
	color_actualizado.emit(color_final)
	
	# B) Notificar al motor de objetos vectoriales
	if "object_style_changed" in GlobalEvents:
		GlobalEvents.object_style_changed.emit()
	
	# C) Notificar a la paleta de colores para que se actualice en tiempo real
	if "color_changed" in GlobalEvents:
		GlobalEvents.color_changed.emit(color_final)

# Si el usuario modifica el degradado general, podemos sincronizar el color primario de fondo
func _on_global_gradient_changed(gradient: Gradient) -> void:
	if is_instance_valid(gradient) and is_instance_valid(nodo_color_rect):
		# Tomamos el color del primer punto del degradado para mantener consistencia visual
		if gradient.get_point_count() > 0:
			var primer_color = gradient.get_color(0)
			if nodo_color_rect.color != primer_color:
				nodo_color_rect.color = primer_color
				color_actualizado.emit(primer_color)
