extends Node
class_name ControlVertical

# --- CONFIGURACIÓN EXPORTADA ---
@export var progress_bar: ProgressBar
@export var boton_aumentar: Button
@export var boton_reducir: Button
@export var boton_reset: Button

# Área que acepta el arrastre (puede ser Control o Node2D)
@export var area_drag: Node

# Referencia opcional a una calculadora para sincronización
@export var calculadora: Node  # ← Cambiado a Node (más genérico)

# --- CONFIGURACIÓN DE VALORES ---
@export var paso_incremento: float = 1.0
@export var sensibilidad_drag: float = 0.5      # píxeles de movimiento → cambio de valor
@export var valor_minimo: float = 0.0
@export var valor_maximo: float = 100.0
@export var valor_inicial: float = 0.0          # ← añadido para más control

# --- VARIABLES INTERNAS ---
var _arrastrando: bool = false
var _ultima_posicion_y: float = 0.0
## Eje del arrastre: -1 aún sin decidir, 0 horizontal (derecha = más),
## 1 vertical (arriba = más). Lo decide el primer movimiento (como ProNumField).
var _eje: int = -1
var _inicio := Vector2.ZERO
var _ultima := Vector2.ZERO


func _ready() -> void:
	# Validación mínima de componentes críticos
	if not progress_bar:
		push_warning("ControlVertical: progress_bar no está asignado")
	
	# Configurar ProgressBar
	if progress_bar:
		progress_bar.min_value = valor_minimo
		progress_bar.max_value = valor_maximo
		progress_bar.value = clamp(valor_inicial, valor_minimo, valor_maximo)
		progress_bar.show_percentage = false
	
	# Conectar señales de botones (con protección)
	if boton_aumentar:
		boton_aumentar.pressed.connect(_on_aumentar_presionado)
	if boton_reducir:
		boton_reducir.pressed.connect(_on_reducir_presionado)
	if boton_reset:
		boton_reset.pressed.connect(_on_reset_presionado)
	
	# Valor inicial
	_actualizar_todo()


# ============================================================================
#                              INPUT - DRAG VERTICAL
# ============================================================================
func _input(event: InputEvent) -> void:
	if not area_drag or not is_instance_valid(area_drag):
		return
	
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
			
		if event.pressed:
			if _punto_en_area(event.global_position):
				_arrastrando = true
				_ultima_posicion_y = event.global_position.y
				_eje = -1
				_inicio = event.global_position
				_ultima = event.global_position
				# Opcional: capturar mouse para mejor experiencia
				# Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # ← descomentar si quieres
		else:
			_arrastrando = false
			# Input.mouse_mode = Input.MOUSE_MODE_VISIBLE     # ← si usaste captured
	
	elif event is InputEventMouseMotion and _arrastrando:
		if _eje < 0:
			var d0: Vector2 = event.global_position - _inicio
			if d0.length() < 3.0:
				return
			_eje = 0 if absf(d0.x) >= absf(d0.y) else 1
		# horizontal: derecha = aumentar; vertical: arriba = aumentar
		var delta: float = (event.global_position.x - _ultima.x) if _eje == 0 else (_ultima.y - event.global_position.y)
		var cambio = delta * sensibilidad_drag
		var nuevo_valor = progress_bar.value + cambio
		
		_set_valor(nuevo_valor)
		_ultima = event.global_position
		_ultima_posicion_y = event.global_position.y


# ============================================================================
#                  DETECCIÓN DE PUNTO EN ÁREA (Control o Node2D)
# ============================================================================
func _punto_en_area(pos_global: Vector2) -> bool:
	if not is_instance_valid(area_drag):
		return false
	
	# Caso 1: es un nodo de tipo Control (UI)
	if area_drag is Control:
		return area_drag.get_global_rect().has_point(pos_global)
	
	# Caso 2: es un nodo 2D (Sprite2D, Area2D, Node2D, etc.)
	if area_drag is Node2D:
		var space_state = area_drag.get_world_2d().direct_space_state
		
		var params := PhysicsPointQueryParameters2D.new()
		params.position = pos_global
		# Si quieres ser más preciso, puedes usar collision_mask del CollisionShape
		# params.collision_mask = 0xFFFFFFFF  # o el que uses
		
		var hits = space_state.intersect_point(params, 32)
		
		for hit in hits:
			if hit.collider == area_drag or hit.collider.get_parent() == area_drag:
				return true
		
		# Fallback: distancia simple al centro (útil para sprites sin colisión)
		var distancia = area_drag.global_position.distance_to(pos_global)
		return distancia < 64.0  # ← ajusta este radio según necesidad
	
	return false


# ============================================================================
#                               BOTONES
# ============================================================================
func _on_aumentar_presionado() -> void:
	_set_valor(progress_bar.value + paso_incremento)


func _on_reducir_presionado() -> void:
	_set_valor(progress_bar.value - paso_incremento)


func _on_reset_presionado() -> void:
	_set_valor(valor_minimo)


# ============================================================================
#                            LÓGICA PRINCIPAL
# ============================================================================
func _set_valor(nuevo: float) -> void:
	if not progress_bar:
		return
		
	var valor_clampeado = clamp(nuevo, valor_minimo, valor_maximo)
	progress_bar.value = valor_clampeado
	
	if calculadora and calculadora.has_method("set_valor_numerico"):
		calculadora.set_valor_numerico(valor_clampeado)
	
	_actualizar_todo()


func _actualizar_todo() -> void:
	# Aquí puedes añadir más actualizaciones visuales si las necesitas
	# Ejemplo: cambiar color, texto adicional, etc.
	pass


# ============================================================================
#                             INTERFAZ PÚBLICA
# ============================================================================
func get_valor() -> float:
	return progress_bar.value if progress_bar else 0.0


func set_valor(nuevo_valor: float) -> void:
	_set_valor(nuevo_valor)


func get_porcentaje() -> float:
	if not progress_bar or is_equal_approx(progress_bar.max_value, progress_bar.min_value):
		return 0.0
	var rango = progress_bar.max_value - progress_bar.min_value
	return ((progress_bar.value - progress_bar.min_value) / rango) * 100.0
