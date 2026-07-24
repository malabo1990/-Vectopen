# =============================================================================
# VECTOPEN CORE — SYSTEM TOOL ENGINE
# RUTA RECOMENDADA: res://script_gdscript/ArtboardTool.gd
# =============================================================================
extends Tool
class_name ArtboardTool

# Estados de control de geometría
var is_drawing: bool = false
var start_pos: Vector2 = Vector2.ZERO
var current_pos: Vector2 = Vector2.ZERO

# Paleta de color corporativa y minimalista para la previsualización (Estilo Apple / Figma)
const PREVIEW_FILL_COLOR := Color(0.05, 0.55, 0.91, 0.04)   # Azul sutil semitransparente
const PREVIEW_LINE_COLOR := Color(0.05, 0.55, 0.91, 0.70)   # Línea de precisión definida
const MIN_CREATION_SIZE  := 30.0                             # Umbral para ignorar clicks accidentales

# ── Ciclo de Vida de la Herramienta ──────────────────────────────────────────

func activate() -> void:
	# Cambiar el puntero del ratón a una cruz de alta precisión para diseño editorial/vectorial
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	is_drawing = false
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func deactivate() -> void:
	is_drawing = false
	if is_instance_valid(canvas):
		canvas.queue_redraw()

# ── Procesamiento de Entrada de Usuario ───────────────────────────────────────

func handle_input(event: InputEvent) -> bool:
	# 1. Seguridad: Si el cursor está interactuando con paneles flotantes o UI, no dibujar
	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false

	# Obtener coordenadas globales escaladas dentro del espacio de trabajo infinito
	var global_mouse: Vector2 = canvas.get_global_mouse_position()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# INICIO DEL ARRASTRE: Bloquear coordenadas iniciales
			is_drawing = true
			start_pos = global_mouse
			current_pos = global_mouse
			canvas.queue_redraw()
			return true
		else:
			# FIN DEL ARRASTRE: El usuario libera el click del ratón
			if is_drawing:
				is_drawing = false
				current_pos = global_mouse
				
				# Calcular dimensiones absolutas de la caja de arrastre
				var size: Vector2 = (current_pos - start_pos).abs()
				
				# Evitar la creación de nodos vacíos o imperceptibles en el lienzo
				if size.x >= MIN_CREATION_SIZE and size.y >= MIN_CREATION_SIZE:
					# Calcular la esquina superior izquierda real (permite arrastrar hacia arriba/atrás)
					var origin_pos: Vector2 = Vector2(
						min(start_pos.x, current_pos.x),
						min(start_pos.y, current_pos.y)
					)
					# Ejecutar la inicialización e inyección en el árbol de nodos
					_create_and_register_artboard(origin_pos, size)
				
				# Transición fluida y automática a la herramienta de movimiento/selección
				_switch_to_move_tool_safe()
				return true

	if event is InputEventMouseMotion:
		if is_drawing:
			# Actualizar coordenadas en tiempo real mientras el ratón se desplaza
			current_pos = global_mouse
			canvas.queue_redraw()
			return true

	return false

# ── Motor de Instanciación e Integración de Dependencias ─────────────────────

func _create_and_register_artboard(global_pos: Vector2, artboard_size: Vector2) -> void:
	if not is_instance_valid(canvas):
		return

	# 1. Cargar dinámicamente el script nativo de inicialización del Artboard
	var artboard_script = preload("res://scripts/canvas/artboard.gd")
	var new_ab = Node2D.new()
	new_ab.set_script(artboard_script)
	
	# 2. Configurar propiedades obligatorias definidas en tu clase 'Artboard'
	new_ab.global_position = global_pos
	new_ab.artboard_size = artboard_size
	
	# Generar un ID único basado en milisegundos para evitar colisiones de nombres en el árbol
	new_ab.name = "Artboard_" + str(Time.get_ticks_msec())
	
	# 3. Anclar el nodo dentro del contenedor jerárquico del Canvas asignado en 'canvas.tscn'
	if canvas.artboards_container:
		canvas.artboards_container.add_child(new_ab)
		print("[Vectopen Engine]: Instanciado nuevo lienzo: ", new_ab.name)
		
		# 4. Sincronización del Manager: Localizar el ArtboardManager activo en la escena
		var manager = canvas.find_child("ArtboardManager", true, false)
		if not manager and canvas.get_tree().current_scene:
			manager = canvas.get_tree().current_scene.find_child("ArtboardManager", true, false)
			
		# 5. Registrar el nuevo objeto y activarlo inmediatamente como foco global
		if manager and manager.has_method("add_artboard") and manager.has_method("set_active_artboard"):
			manager.add_artboard(new_ab)
			manager.set_active_artboard(new_ab)
			print("[Vectopen Engine]: Sincronización exitosa con ArtboardManager.")
		
		# Mantener redundancia de asignación directa si tu Canvas expone la variable expuesta
		if "active_artboard" in canvas:
			canvas.active_artboard = new_ab

func _switch_to_move_tool_safe() -> void:
	if is_instance_valid(canvas) and canvas.MoveTool_Script:
		# Instanciar el script de MoveTool pasándole el lienzo principal al constructor
		var move_tool_instance = canvas.MoveTool_Script.new(canvas)
		
		# IMPORTANTE: call_deferred ejecuta el cambio al final del frame de procesamiento actual.
		# Esto limpia la cola de eventos evitando que MoveTool reciba pulsaciones fantasma.
		canvas.call_deferred("change_tool", move_tool_instance)

# ── Renderizado en Pantalla del Rectángulo de Guía (Figma/Sketch style) ──────

func draw_preview(c: Node2D) -> void:
	# Esta función debe ser invocada desde el método _draw() de tu nodo Canvas
	# Ejemplo en canvas.gd: if current_tool has_method("draw_preview"): current_tool.draw_preview(self)
	if is_drawing:
		# Transformar posiciones globales del mundo a coordenadas locales del nodo de dibujo
		var local_start: Vector2 = c.to_local(start_pos)
		var local_current: Vector2 = c.to_local(current_pos)
		
		var preview_rect: Rect2 = Rect2(local_start, local_current - local_start)
		
		# Dibujar geometrías de guía bidimensionales limpias y optimizadas
		c.draw_rect(preview_rect, PREVIEW_FILL_COLOR, true)
		c.draw_rect(preview_rect, PREVIEW_LINE_COLOR, false, 1.0)
