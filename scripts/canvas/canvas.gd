# =============================================================================
# VECTOPEN CORE — CORE SYSTEM ENGINE
# RUTA: res://scripts/canvas/canvas.gd
# =============================================================================
extends Node2D
class_name CanvasEditor

# --- REFERENCIAS A NODOS ---
@export_group("Required Nodes")
@export var camera: Camera2D
@export var artboards_container: Node2D

# --- REFERENCIA A UI EXTERNA ---
var toolbar_ui: Control 

# --- CONFIGURACIÓN DE NAVEGACIÓN ---
@export_group("Camera Settings")
@export var zoom_speed: float = 0.05
@export var zoom_min: float = 0.05
## 50000.0 (5.000.000%) — a pedido explícito, por encima del techo de Figma
## (256/25600%). camera.zoom sigue siendo float32 (como todo en Godot sin
## build de doble precisión), así que a este nivel el propio Transform2D de
## la cámara puede perder precisión visible en coordenadas grandes — es el
## mismo tipo de problema que resolvimos para la posición/tamaño de las
## figuras, pero aquí no tiene arreglo sin tocar la cámara a fondo.
@export var zoom_max: float = 50000.0
@export var pan_speed: float = 1.0

# --- CONFIGURACIÓN DE ZOOM CON TECLA Z ---
@export_group("Z-Zoom Settings")
@export var z_drag_sensitivity: float = 0.01
@export var z_drag_max_factor: float = 0.15

# --- EXPORTACIÓN DE PORCENTAJE DE ZOOM ---
@export_group("Zoom Output")
@export var zoom_percentage: float = 100.0:
	set(v):
		zoom_percentage = clamp(v, zoom_min * 100.0, zoom_max * 100.0)
		if is_instance_valid(camera):
			var target_zoom: float = zoom_percentage / 100.0
			camera.zoom = Vector2(target_zoom, target_zoom)
			# Marcar todo el viewport como sucio al cambiar el zoom
			mark_region_dirty(Rect2(Vector2.ZERO, get_viewport_rect().size))

# --- SCRIPTS DE HERRAMIENTAS (Inspector) ---
@export_group("Tool Scripts")
@export var MoveTool_Script: Script
@export var BrushTool_Script: Script
@export var RectangleTool_Script: Script
@export var PenTool_Script: Script
@export var ArtboardTool_Script: Script = preload("res://script_gdscript/tools/ArtboardTool.gd")
@export var CircleTool_Script: Script
@export var TriangleTool_Script: Script
@export var PentagonTool_Script: Script
@export var Star4Tool_Script: Script
@export var Star5Tool_Script: Script
@export var WaterDropTool_Script: Script
@export var BezierTool_Script: Script
@export var BrushTool_Script2: Script

@export_group("Text Tools")
@export var TextTool_Script: Script
@export var ParagraphTool_Script: Script

# --- ESTADO INTERNO ---
var current_tool        = null
var dragging: bool      = false
var is_space_pressed: bool = false
var is_ctrl_pressed: bool  = false
var is_cmd_pressed: bool   = false
var is_z_pressed: bool     = false

var _zoom_anchor: Vector2  = Vector2.ZERO
var _eraser_active: bool   = false
var _tool_before_eraser    = null
var _dirty_regions: Array[Rect2] = []  # Regiones que necesitan redibujarse

# --- Smart Cursor ---
@onready var smart_cursor = get_node("/root/SmartCursor")
var _cursor_material: ShaderMaterial = null
var _cursor_visible: bool = true
var _cursor_position: Vector2 = Vector2.ZERO

# Diccionario global para el registro dinámico de herramientas
var _herramientas_registradas: Dictionary = {}

# ── Ciclo de Vida del Canvas ─────────────────────────────────────────────────

func _ready() -> void:
	if not is_instance_valid(camera):
		print("[Vectopen Error]: Camera2D no asignada en el nodo Canvas.")
		return
	
	_inicializar_escena()
	_registrar_herramientas_iniciales()
	_initialize_smart_cursor()

func _inicializar_escena() -> void:
	if is_instance_valid(artboards_container) and artboards_container.get_child_count() > 0:
		var first_artboard = artboards_container.get_child(0)
		if "position" in first_artboard:
			first_artboard.position = Vector2(100, 100)
	_reset_camera()

func _registrar_herramientas_iniciales() -> void:
	if MoveTool_Script:
		registrar_herramienta("v", MoveTool_Script)
		change_tool(_new_tool(MoveTool_Script))

	if BrushTool_Script:     registrar_herramienta("b", BrushTool_Script)
	if RectangleTool_Script: registrar_herramienta("m", RectangleTool_Script)
	if PenTool_Script:       registrar_herramienta("p", PenTool_Script)
	if ArtboardTool_Script:  registrar_herramienta("a", ArtboardTool_Script)
	if TextTool_Script:      registrar_herramienta("t", TextTool_Script)

# --- API PÚBLICA DE GESTIÓN DINÁMICA ---

func registrar_herramienta(tecla_acceso: String, script_herramienta: Script) -> void:
	var tecla: String = tecla_acceso.to_lower().strip_edges()
	if tecla != "":
		_herramientas_registradas[tecla] = script_herramienta

func _new_tool(script: Script):
	if not script:
		return null
	if script.get_instance_base_type() == "RefCounted":
		return script.new(self)
	var tool = script.new()
	if "canvas" in tool:
		tool.canvas = self
	return tool

func change_tool(new_tool) -> void:
	if current_tool and current_tool.has_method("deactivate"):
		current_tool.deactivate()
	
	current_tool = new_tool
	
	if current_tool:
		print("==================================================")
		print("CANVAS NOTIFICACIÓN: ¡Herramienta Cambiada con Éxito!")
		print("==================================================")

	if current_tool and current_tool.has_method("activate"):
		current_tool.activate()
	else:
		_actualizar_cursor_navegacion()
	
	# ── NOTIFICACIÓN AL CONTENEDOR DEL LIENZO (OVERLAY CONTROL) ──
	if is_instance_valid(artboards_container) and artboards_container.has_method("set_active_tool"):
		if current_tool and current_tool.has_method("get_class_name") and current_tool.get_class_name() == "MoveTool":
			artboards_container.set_active_tool("movetool", current_tool)
		else:
			artboards_container.set_active_tool("other", null)
	
	_sincronizar_ui_toolbar()
	# Marcar todo el viewport como sucio al cambiar de herramienta
	mark_region_dirty(Rect2(Vector2.ZERO, get_viewport_rect().size))

func switch_tool(tool_type: String) -> void:
	var tool_manager = get_node_or_null("/root/ToolManager")
	match tool_type.to_lower():
		"move":
			if MoveTool_Script: change_tool(_new_tool(MoveTool_Script))
		"brush":
			if BrushTool_Script: change_tool(_new_tool(BrushTool_Script))
		"pen":
			if PenTool_Script: change_tool(_new_tool(PenTool_Script))
		"rectangle":
			if RectangleTool_Script: change_tool(_new_tool(RectangleTool_Script))
		"ellipse":
			if CircleTool_Script: change_tool(_new_tool(CircleTool_Script))
		"triangle":
			if TriangleTool_Script: change_tool(_new_tool(TriangleTool_Script))
		"pentagon":
			if PentagonTool_Script: change_tool(_new_tool(PentagonTool_Script))
		"star4":
			if Star4Tool_Script: change_tool(_new_tool(Star4Tool_Script))
		"star5":
			if Star5Tool_Script: change_tool(_new_tool(Star5Tool_Script))
		"waterdrop":
			if WaterDropTool_Script: change_tool(_new_tool(WaterDropTool_Script))
		"bezier":
			if BezierTool_Script: change_tool(_new_tool(BezierTool_Script))
		"select":
			if MoveTool_Script: change_tool(_new_tool(MoveTool_Script))
		"text":
			if TextTool_Script: change_tool(_new_tool(TextTool_Script))
		"paragraph":
			if ParagraphTool_Script: change_tool(_new_tool(ParagraphTool_Script))
		"hand":
			pass
		"artboard":
			if ArtboardTool_Script: change_tool(_new_tool(ArtboardTool_Script))
	if tool_manager and tool_manager.has_method("switch_tool"):
		tool_manager.switch_tool(tool_type)

# ── Procesamiento de Entrada Centralizado ────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_keyboard(event)
		return

	var en_modo_navegacion: bool = is_space_pressed or is_z_pressed or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE)
	
	if current_tool and not en_modo_navegacion:
		if current_tool.has_method("handle_input"):
			if current_tool.handle_input(event):
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMagnifyGesture:
		zoom_at_point(event.factor, get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		_handle_trackpad_pan(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

# ── Gestión de Teclado y Atajos de Teclas Cortas ────────────────────────────

func _handle_keyboard(event: InputEventKey) -> void:
	match event.keycode:
		KEY_SPACE: is_space_pressed = event.pressed; _actualizar_cursor_navegacion()
		KEY_CTRL:  is_ctrl_pressed  = event.pressed
		KEY_META:  is_cmd_pressed   = event.pressed
		KEY_Z:     is_z_pressed     = event.pressed; _actualizar_cursor_navegacion()

	if not event.pressed: return
	if get_viewport().gui_get_focus_owner() != null: return 

	if VectopenInput.is_action_triggered(event, "canvas_reset_zoom"):
		_reset_camera()
		get_viewport().set_input_as_handled()
		return

	if VectopenInput.is_action_triggered(event, "canvas_zoom_in"):
		zoom_at_point(1.2, get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	if VectopenInput.is_action_triggered(event, "canvas_zoom_out"):
		zoom_at_point(0.8, get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	if VectopenInput.is_action_triggered(event, "redo"):
		if HistoryManager:
			HistoryManager.redo()
		get_viewport().set_input_as_handled()
		return

	if VectopenInput.is_action_triggered(event, "undo"):
		if HistoryManager:
			HistoryManager.undo()
		get_viewport().set_input_as_handled()
		return

	var unicode_val = event.unicode if event.unicode != 0 else event.keycode
	var t_char: String = char(unicode_val).to_lower()
	if _herramientas_registradas.has(t_char):
		var script_target = _herramientas_registradas[t_char]
		change_tool(_new_tool(script_target))
		get_viewport().set_input_as_handled()

# ── Procesamiento de Clicks y Rueda del Ratón ─────────────────────────────────

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if (event.button_index == MOUSE_BUTTON_LEFT and is_space_pressed) or event.button_index == MOUSE_BUTTON_MIDDLE:
		dragging = event.pressed
		if not dragging: 
			_actualizar_cursor_navegacion()
		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_LEFT and is_z_pressed:
		dragging = event.pressed
		if event.pressed: 
			_zoom_anchor = get_global_mouse_position()
		else: 
			_actualizar_cursor_navegacion()
		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		var f: float = 1.0 + (zoom_speed * (2.0 if (is_ctrl_pressed or is_cmd_pressed) else 1.0))
		zoom_at_point(f, get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var f: float = 1.0 - (zoom_speed * (2.0 if (is_ctrl_pressed or is_cmd_pressed) else 1.0))
		zoom_at_point(f, get_global_mouse_position())
		get_viewport().set_input_as_handled()

# ── Procesamiento del Desplazamiento y Presión del Lápiz ──────────────────────

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if event.pen_inverted:
		if not _eraser_active:
			_eraser_active = true
			_tool_before_eraser = current_tool
	else:
		if _eraser_active:
			_eraser_active = false
			if _tool_before_eraser:
				change_tool(_tool_before_eraser)
				_tool_before_eraser = null

	if current_tool and event.pressure > 0.0:
		current_tool.set_meta("pen_pressure", event.pressure)

	if is_z_pressed and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var f: float = 1.0 - event.relative.y * z_drag_sensitivity
		f = clamp(f, 1.0 - z_drag_max_factor, 1.0 + z_drag_max_factor)
		zoom_at_point(f, _zoom_anchor)
		get_viewport().set_input_as_handled()
		return

	if is_cmd_pressed and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var f: float = clamp(1.0 - event.relative.y * z_drag_sensitivity, 1.0 - z_drag_max_factor, 1.0 + z_drag_max_factor)
		zoom_at_point(f, get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	if dragging and (is_space_pressed or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)):
		if is_instance_valid(camera) and camera.zoom.x > 0.0:
			camera.position -= event.relative * pan_speed / camera.zoom.x
			get_viewport().set_input_as_handled()
		return

func _handle_trackpad_pan(event: InputEventPanGesture) -> void:
	if is_cmd_pressed or is_ctrl_pressed:
		zoom_at_point(1.0 - event.delta.y * zoom_speed * 0.5, get_global_mouse_position())
	else:
		if is_instance_valid(camera) and camera.zoom.x > 0.0:
			camera.position -= event.delta * pan_speed / camera.zoom.x

# ── Control de Puntero UI ─────────────────────────────────────────────────────

func _actualizar_cursor_navegacion() -> void:
	if is_space_pressed: 
		Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	elif is_z_pressed:   
		Input.set_default_cursor_shape(Input.CURSOR_BDIAGSIZE)
	else:
		if current_tool and current_tool.has_method("activate"):
			current_tool.activate()
		else:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)

# ── Motor Gráfico (Vista previa de herramientas) ──────────────────────────────

func _draw() -> void:
	# Si hay regiones sucias, redibujar solo esas regiones
	if _dirty_regions.size() > 0:
		for region in _dirty_regions:
			draw_rect(region, Color.TRANSPARENT)  # Limpiar la región
			
			# Aplicar clipping a la región sucia
			var viewport_rect = Rect2(Vector2.ZERO, get_viewport_rect().size)
			var clip_rect = region.intersection(viewport_rect)
			RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, clip_rect)
			
			# Dibujar solo en la región sucia
			if current_tool and current_tool.has_method("draw_preview"):
				current_tool.draw_preview(self)
			

	else:
		# Redibujar todo si no hay regiones sucias
		if current_tool and current_tool.has_method("draw_preview"):
			current_tool.draw_preview(self)
	
	# Dibujar el cursor inteligente
	_draw_smart_cursor()


func _draw_smart_cursor() -> void:
	"""
	Dibuja el cursor inteligente en el canvas.
	"""
	if not _cursor_visible or not _cursor_material or not smart_cursor:
		return
	
	# Obtener la posición global del mouse
	var mouse_pos = _cursor_position
	if mouse_pos == Vector2.ZERO:
		mouse_pos = get_global_mouse_position()
	
	# Convertir a coordenadas locales
	var local_pos = to_local(mouse_pos)
	
	# Dibujar el cursor
	draw_set_transform(local_pos)
	
	var cs_size = smart_cursor.get_current_size()
	draw_rect(
		Rect2(-cs_size, -cs_size, cs_size * 2, cs_size * 2),
		Color(1, 1, 1, 1), 
		true
	)
	
	draw_set_transform(Vector2.ZERO)


# ── API Pública para Redraw Regional ───────────────────────────────────────

func mark_region_dirty(region: Rect2) -> void:
	"""
	Marca una región como 'sucia' para redibujado parcial.
	La región debe estar en coordenadas globales.
	"""
	if region.has_area():
		_dirty_regions.append(region)
		# Combinar regiones superpuestas para optimizar
		_combine_dirty_regions()
		queue_redraw()


func mark_point_dirty(_point_position: Vector2, radius: float = 10.0) -> void:
	"""
	Marca un punto y su área circundante como 'sucia'.
	Útil para cambios pequeños como selección o manipulación de nodos.
	"""
	var region = Rect2(
		global_position - Vector2(radius, radius),
		Vector2(radius * 2, radius * 2)
	)
	mark_region_dirty(region)


func _combine_dirty_regions() -> void:
	"""
	Combina regiones sucias que se superponen para reducir la cantidad de redibujos.
	"""
	if _dirty_regions.size() <= 1:
		return
	
	var combined_regions: Array[Rect2] = []
	var processed = []
	processed.resize(_dirty_regions.size())
	processed.fill(false)
	
	for i in _dirty_regions.size():
		if processed[i]:
			continue
			
		var current = _dirty_regions[i]
		var merged = current
		processed[i] = true
		
		for j in range(i + 1, _dirty_regions.size()):
			if processed[j]:
				continue
				
			if merged.intersects(_dirty_regions[j]):
				merged = merged.merge(_dirty_regions[j])
				processed[j] = true
			
		combined_regions.append(merged)
	
	_dirty_regions = combined_regions


# ==========================================
# SMART CURSOR SYSTEM
# ==========================================

func _initialize_smart_cursor() -> void:
	"""
	Inicializa el sistema de cursor inteligente.
	"""
	if not smart_cursor:
		push_error("SmartCursor: Sistema de cursor inteligente no disponible")
		return
	
	# Crear material para el cursor
	_cursor_material = ShaderMaterial.new()
	var shader = load("res://shaders/smart_cursor.gdshader")
	if shader:
		_cursor_material.shader = shader
	else:
		push_error("SmartCursor: No se pudo cargar el shader del cursor")
		return
	
	# Conectar señal de cambio de cursor
	smart_cursor.cursor_changed.connect(_on_cursor_changed)
	
	# Configurar cursor inicial
	_update_cursor_material()
	
	# Conectar señal de movimiento del mouse (diferido para evitar Window sin gui_input)
	call_deferred("_connect_gui_input")


func _on_cursor_changed(_shape: int, _color: Color, _animation: int, _size: float) -> void:
	"""
	Maneja el cambio de estado del cursor.
	"""
	_update_cursor_material()
	queue_redraw()


func _update_cursor_material() -> void:
	"""
	Actualiza el material del cursor con los parámetros actuales.
	"""
	if not _cursor_material or not smart_cursor:
		return
	
	# Obtener estado actual del cursor
	var _state = smart_cursor.get_current_state()
	var color = smart_cursor.get_current_color()
	
	# Configurar parámetros del shader
	_cursor_material.set_shader_parameter("shape", smart_cursor.get_current_shape())
	_cursor_material.set_shader_parameter("color", color)
	_cursor_material.set_shader_parameter("size", smart_cursor.get_current_size())
	_cursor_material.set_shader_parameter("pulse_factor", smart_cursor.get_pulse_factor())
	_cursor_material.set_shader_parameter("halo_factor", smart_cursor.get_halo_factor())
	_cursor_material.set_shader_parameter("rotation_angle", smart_cursor.get_rotation_angle())
	_cursor_material.set_shader_parameter("accessibility_mode", false)


func _on_gui_input(event: InputEvent) -> void:
	"""
	Actualiza la posición del cursor.
	"""
	if event is InputEventMouseMotion:
		_cursor_position = event.global_position
		queue_redraw()


func _connect_gui_input() -> void:
	var vp = get_viewport()
	if vp and vp.has_signal("gui_input"):
		vp.gui_input.connect(_on_gui_input)

# ── Métodos de Cámara y Sincronización ────────────────────────────────────────

func zoom_at_point(factor: float, world_point: Vector2) -> void:
	if not is_instance_valid(camera):
		return
		
	var old_zoom: float = camera.zoom.x
	var new_zoom: float = clamp(old_zoom * factor, zoom_min, zoom_max)
	if is_equal_approx(new_zoom, old_zoom): 
		return
		
	# Calcular la región afectada por el zoom
	var viewport_size = get_viewport_rect().size
	var region = Rect2(camera.position - (viewport_size / (2 * old_zoom)), 
					  viewport_size / old_zoom)
	
	camera.zoom = Vector2(new_zoom, new_zoom)
	camera.position += (world_point - camera.position) * (1.0 - new_zoom / old_zoom)
	
	zoom_percentage = new_zoom * 100.0
	mark_region_dirty(region)

func _reset_camera() -> void:
	if not is_instance_valid(camera):
		return
		
	# Marcar todo el viewport como sucio
	var viewport_size = get_viewport_rect().size
	mark_region_dirty(Rect2(Vector2.ZERO, viewport_size))
	
	if is_instance_valid(artboards_container) and artboards_container.get_child_count() > 0:
		var ab = artboards_container.get_child(0)
		var ab_size = ab.get("artboard_size") if ab.get("artboard_size") else Vector2(800, 600)
		if "position" in ab:
			camera.position = ab.position + ab_size / 2.0
	else:
		camera.position = Vector2.ZERO
		
	camera.zoom = Vector2.ONE
	zoom_percentage = 100.0

func get_current_tool():
	return current_tool

func _sincronizar_ui_toolbar() -> void:
	if is_instance_valid(toolbar_ui) and toolbar_ui.has_method("actualizar_botones_visuales"):
		toolbar_ui.call("actualizar_botones_visuales", current_tool)
		# Marcar solo la región de la toolbar como sucia
		if toolbar_ui:
			var toolbar_rect = toolbar_ui.get_global_rect()
			mark_region_dirty(toolbar_rect)
