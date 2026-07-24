# ==========================================
# RUTA: res://scripts/canvas/artboard_title.gd
# ==========================================
extends Node2D

signal rename_requested(new_name: String)

var title_text: String = "Artboard 1"

func _ready() -> void:
	_reposition()

func _reposition() -> void:
	# Fijado matemáticamente a la esquina superior izquierda (0,0) local del Artboard
	# Separado un margen constante de 16 píxeles hacia arriba de manera limpia
	position = Vector2(0, -18) 
	queue_redraw()

func _draw() -> void:
	var font = ThemeDB.fallback_font
	var font_size := 11 # Dimensión Figma compacta profesional
	
	# Obtener dimensiones exactas del texto en píxeles
	var text_size = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var padding = Vector2(6, 3)
	var bg_size = text_size + padding * 2
	
	# Rectángulo contenedor ajustado al texto
	var bg_rect = Rect2(Vector2(0, -bg_size.y + 2), bg_size)
	
	# Detectar estado de selección del padre
	var parent_artboard = get_parent()
	var is_selected = parent_artboard.get("is_selected") if parent_artboard else false
	
	# Colores de fondo de la píldora (Gris Figma / Grafito oscuro)
	var bg_color = Color("#2c2c2c") if is_selected else Color("#1e1e1e", 0.9)
	draw_rect(bg_rect, bg_color, true)
	
	# Texto con contraste nítido (Blanco puro vs Gris claro)
	var text_color = Color.WHITE if is_selected else Color(0.75, 0.75, 0.75)
	
	# Dibujar el string centrado dentro de su píldora protectora
	draw_string(font, Vector2(padding.x, 0), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
