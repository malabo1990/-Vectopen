# res://layers_tree.gd
# Script 1/2 - Visual, Estilo y Desplazamiento Píxel a Píxel para Tableta Gráfica (Botón Central)
extends Tree

# ==============================================================================
# CONFIGURACIÓN DE ARRASTRE PÍXEL A PÍXEL
# ==============================================================================
@export_group("Configuración Arrastre")
@export var velocidad_arrastre : float = 1.0

# ==============================================================================
# COLORES Y METRICAS CONFIGURABLES DESDE EL INSPECTOR
# ==============================================================================
@export_group("Fondo")
@export var color_bg       : Color = Color(1.00, 1.00, 1.00) ## Fondo del panel
@export_group("Texto normal")
@export var color_text     : Color = Color(0.08, 0.08, 0.08) ## Texto capas normales
@export var color_text_dim : Color = Color(0.55, 0.55, 0.55) ## Texto capa oculta
@export_group("Seleccion")
@export var color_select_bg   : Color = Color(0.80, 0.80, 0.80) ## Fondo item seleccionado
@export var color_select_text : Color = Color(0.08, 0.08, 0.08) ## Texto item seleccionado
@export var color_hover_bg    : Color = Color(0.93, 0.93, 0.93) ## Fondo hover
@export_group("Focus")
@export var color_focus_bg   : Color = Color(0.75, 0.75, 0.75) ## Fondo item con foco (teclado)
@export var color_focus_text : Color = Color(0.05, 0.05, 0.05) ## Texto item con foco
@export_group("Artboard")
@export var color_artboard_bg   : Color = Color(0.20, 0.20, 0.20) ## Fondo artboard
@export var color_artboard_text : Color = Color(1.00, 1.00, 1.00) ## Texto artboard
@export var color_artboard_dim  : Color = Color(0.55, 0.55, 0.55) ## Texto artboard oculto
@export_group("Checkbox Normal")
@export var color_check_bg     : Color = Color(1.00, 1.00, 1.00) ## Fondo checkbox
@export var color_check_border : Color = Color(0.65, 0.65, 0.65) ## Borde checkbox
@export var color_check_mark   : Color = Color(0.15, 0.15, 0.15) ## Marca checkbox
@export_group("Checkbox Artboard")
@export var color_check_ab_bg   : Color = Color(0.30, 0.30, 0.30) ## Fondo checkbox artboard
@export var color_check_ab_mark : Color = Color(1.00, 1.00, 1.00) ## Marca checkbox artboard
@export_group("Jerarquia")
@export var indent_size : int = 16 ## Pixeles de sangria por nivel de profundidad
@export var color_guide    : Color = Color(0.88, 0.88, 0.88) ## Lineas guia entre items

# Variables de control interno para el arrastre
var _arrastrando : bool = false
var _ultima_pos_y : float = 0.0

# ==============================================================================
func _ready() -> void:
	_apply_theme()
	# MOUSE_FILTER_STOP asegura que el nodo capture eventos cuando sea necesario
	mouse_filter = Control.MOUSE_FILTER_STOP

func refresh_theme() -> void:
	_apply_theme()

# ==============================================================================
# GESTIÓN DE ENTRADA GLOBAL (INTERCEPCIÓN DE PROCESAMIENTO)
# ==============================================================================
func _input(event: InputEvent) -> void:
	# Comprobamos si el mouse/lápiz está físicamente sobre el área del Tree
	var mouse_encima_del_tree = get_global_rect().has_point(get_global_mouse_position())
	
	# 1. Detectar clic y liberación del botón central (Rueda o botón físico del lápiz)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			if mouse_encima_del_tree:
				_arrastrando = true
				_ultima_pos_y = event.global_position.y
				mouse_default_cursor_shape = Control.CURSOR_DRAG
				# Consumimos el evento para que el Tree no intente seleccionar nada con el botón central
				get_viewport().set_input_as_handled()
		else:
			if _arrastrando:
				_arrastrando = false
				mouse_default_cursor_shape = Control.CURSOR_ARROW
				get_viewport().set_input_as_handled()

	# 2. Desplazamiento interactivo píxel a píxel
	if event is InputEventMouseMotion and _arrastrando:
		# Calculamos cuántos píxeles se ha movido el lápiz verticalmente
		var delta_y : float = event.global_position.y - _ultima_pos_y
		
		# Buscamos de forma activa la barra vertical interna de Godot
		for child in get_children():
			if child is VScrollBar:
				# Restamos o sumamos píxel a píxel directamente al valor real del scrollbar
				child.value -= delta_y * velocidad_arrastre
				break # Encontrada y procesada, salimos del bucle
		
		# Actualizamos la posición para el próximo frame de movimiento
		_ultima_pos_y = event.global_position.y
		get_viewport().set_input_as_handled()

# ==============================================================================
# TEMA GLOBAL
# ==============================================================================
func _apply_theme() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = color_bg
	bg.set_border_width_all(0)
	add_theme_stylebox_override("panel",    bg)
	add_theme_stylebox_override("bg",       bg)
	add_theme_stylebox_override("bg_focus", bg)

	add_theme_stylebox_override("selected",           _flat(color_select_bg, 2))
	add_theme_stylebox_override("selected_focus",   _flat(color_select_bg, 2))
	add_theme_stylebox_override("cursor",            _flat(color_focus_bg, 2))
	add_theme_stylebox_override("cursor_unfocused", _flat(color_focus_bg, 2))

	add_theme_color_override("font_color",          color_text)
	add_theme_color_override("font_selected_color", color_select_text)
	add_theme_color_override("font_outline_color",  color_text)

	add_theme_color_override("guide_color",              color_guide)
	add_theme_color_override("relationship_line_color", color_guide)
	add_theme_color_override("children_hl_line_color",  color_guide)
	add_theme_color_override("parent_hl_line_color",    color_guide)
	add_theme_color_override("drop_position_color",      Color(0.28, 0.55, 1.0))

	add_theme_constant_override("item_margin",              indent_size)
	add_theme_constant_override("inner_item_margin_left",   6)
	add_theme_constant_override("inner_item_margin_right", 4)
	add_theme_constant_override("v_separation",            2)
	add_theme_constant_override("h_separation",            4)
	add_theme_constant_override("draw_guides",              1)
	add_theme_constant_override("draw_relationship_lines", 1)

func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(2)
	return s

# ==============================================================================
# ESTILOS POR ITEM (Inalterados)
# ==============================================================================
func style_normal_item(item: TreeItem, c_vis: int, c_name: int, c_mask: int) -> void:
	item.set_custom_color(c_name, color_text)
	item.clear_custom_bg_color(c_vis)
	item.clear_custom_bg_color(c_name)
	item.clear_custom_bg_color(c_mask)

func style_artboard_item(item: TreeItem, c_vis: int, c_name: int, c_mask: int) -> void:
	item.set_custom_color(c_name, color_artboard_text)
	item.set_custom_bg_color(c_vis,  color_artboard_bg)
	item.set_custom_bg_color(c_name, color_artboard_bg)
	item.set_custom_bg_color(c_mask, color_artboard_bg)

func style_visibility(item: TreeItem, c_name: int, is_visible: bool, is_artboard: bool) -> void:
	if is_artboard:
		item.set_custom_color(c_name, color_artboard_text if is_visible else color_artboard_dim)
	else:
		item.set_custom_color(c_name, color_text if is_visible else color_text_dim)
