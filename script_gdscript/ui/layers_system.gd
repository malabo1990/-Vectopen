# =============================================================================
# VECTOPEN STUDIO — LAYER SYSTEM (CORE BACKEND)
# ARCHIVO: res://script_gdscript/layers_system.gd
# MODALIDAD: @tool
# =============================================================================
@tool
extends Node
class_name LayerSystem

# ─── REFERENCIAS DE ARQUITECTURA ──────────────────────────────────────────────
@export_group("Componentes Core")
@export var layer_tree         : Tree      # Componente UI LayerTree
@export var artboard_container : Node2D    # ArtboardsContainer de canvas.tscn

# ─── ESTADO OPERATIVO INTERNO ─────────────────────────────────────────────────
var _bloquear_sincronizacion : bool = false
var _artboards_conectados    : Array[Node2D] = []
var _update_timer           : Timer = null
var _pending_changes        : Array[Dictionary] = []
var _node_to_item_map       : Dictionary = {}  # Mapeo nodo → TreeItem

# =============================================================================
# INICIALIZACIÓN Y CONEXIONES DE SEÑALES
# =============================================================================
func _ready() -> void:
	# Localizar componentes automáticamente en la escena viva si quedan null
	if not layer_tree:
		var escena_activa = get_tree().current_scene
		if escena_activa:
			layer_tree = escena_activa.find_child("LayerTree", true, false) as Tree
			if not layer_tree:
				layer_tree = escena_activa.find_child("Tree", true, false) as Tree

	if not artboard_container:
		var escena_activa = get_tree().current_scene
		if escena_activa:
			artboard_container = escena_activa.find_child("ArtboardsContainer", true, false) as Node2D

	# Crear timer para actualizaciones batch
	_setup_update_timer()
	
	conectar_senales_sistema()
	sincronizar_arbol_completo()


func conectar_senales_sistema() -> void:
	if not is_instance_valid(artboard_container):
		return
			
	# Monitorear si se añaden o quitan Artboards del contenedor principal
	if not artboard_container.child_entered_tree.is_connected(_on_node_added):
		artboard_container.child_entered_tree.connect(_on_node_added)
			
	# CORRECCIÓN DEL CRASH: 'child_exiting_tree' en lugar de 'child_exited_tree'
	if not artboard_container.child_exiting_tree.is_connected(_on_node_removed):
		artboard_container.child_exiting_tree.connect(_on_node_removed)

	# Conectar el evento de edición del propio Tree
	if is_instance_valid(layer_tree):
		if not layer_tree.item_edited.is_connected(_on_layer_tree_item_edited):
			layer_tree.item_edited.connect(_on_layer_tree_item_edited)

	# Refrescar el árbol (y con él, el indicador de "fuera del artboard") cuando
	# se termina de mover/transformar una figura — MoveTool.gd no emitía esta
	# señal (existía en GlobalEvents pero nada la disparaba); se conectó
	# también ahí. Sin esto, arrastrar una figura fuera del artboard no
	# actualizaba el panel de capas hasta el siguiente cambio estructural.
	if GlobalEvents and not GlobalEvents.object_transformed.is_connected(_on_object_transformed):
		GlobalEvents.object_transformed.connect(_on_object_transformed)


func _on_object_transformed() -> void:
	sincronizar_arbol_completo()


# =============================================================================
# SINCRO CORE: CONSTRUCCIÓN JERÁRQUICA DE LA UI
# =============================================================================
func sincronizar_arbol_completo() -> void:
	if _bloquear_sincronizacion or not is_instance_valid(layer_tree) or not is_instance_valid(artboard_container):
		return

	_bloquear_sincronizacion = true
	layer_tree.clear()
	_node_to_item_map.clear()
	_pending_changes.clear()

	# Crear la raíz invisible obligatoria para el Tree
	var raiz_oculta : TreeItem = layer_tree.create_item()
	if not raiz_oculta:
		_bloquear_sincronizacion = false
		return

	# Limpiar registro de artboards antiguos para evitar fugas de memoria
	_artboards_conectados.clear()

	# Recorrer los hijos directos del contenedor (Artboards)
	for artboard in artboard_container.get_children():
		if artboard is Node2D:
			# Escuchar cambios internos de este Artboard (para cuando crees rectángulos/líneas)
			_vincular_senales_artboard(artboard)
			# Construir su estructura de forma recursiva hacia abajo
			_construir_nodo_recursivo(raiz_oculta, artboard, artboard)

	_bloquear_sincronizacion = false
	_repintar_canvas()


func _construir_nodo_recursivo(parent_item: TreeItem, real_node: Node2D, artboard_actual: Node2D) -> void:
	if not is_instance_valid(real_node) or real_node.name == "Contorno_Stroke":
		return # Ignorar líneas estéticas auxiliares de las herramientas

	# Crear el TreeItem para este nodo
	var item = _create_tree_item(parent_item, real_node, artboard_actual)

	# 4. Incursión Recursiva: Procesar elementos internos del nodo (Figuras del lienzo)
	for hijo in real_node.get_children():
		if hijo is Node2D:
			_construir_nodo_recursivo(item, hijo, artboard_actual)

## Comprueba si el ORIGEN del nodo cae fuera del rectángulo del artboard.
## Es una comprobación simple por punto (no el AABB completo de la figura,
## que ya se calcula de forma más precisa y duplicada en MoveTool.gd y
## bounding_box.gd) — suficiente para el indicador de aviso del panel de
## capas sin añadir una tercera copia de esa lógica geométrica.
func _esta_fuera_del_artboard(real_node: Node2D, artboard_actual: Node2D) -> bool:
	if not is_instance_valid(artboard_actual) or real_node == artboard_actual:
		return false
	if not ("artboard_size" in artboard_actual):
		return false
	var rect := Rect2(artboard_actual.global_position, artboard_actual.artboard_size)
	return not rect.has_point(real_node.global_position)

func _create_tree_item(parent_item: TreeItem, real_node: Node2D, artboard_actual: Node2D = null) -> TreeItem:
	# 1. Identificar el tipo de capa para el estilo visual
	var type : String = "shape"
	if real_node.has_meta("shape_type"):
		type = real_node.get_meta("shape_type") as String
	elif real_node.name.to_lower().contains("artboard"):
		type = "artboard"
	elif real_node.get_child_count() > 0:
		type = "group"

	# 2. Instanciar el TreeItem de forma segura
	var item : TreeItem = layer_tree.create_item(parent_item)
	if not item:
		return null

	# 3. Inicializar las 3 columnas reglamentarias de Vectopen
	item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)   # Columna 0: Visibilidad (Ojo)
	item.set_cell_mode(1, TreeItem.CELL_MODE_STRING)  # Columna 1: Nombre del objeto
	item.set_cell_mode(2, TreeItem.CELL_MODE_CHECK)   # Columna 2: Bloqueo (Candado)

	# Configurar textos y permisos de edición
	item.set_text(1, real_node.name)
	item.set_editable(0, true)
	item.set_editable(1, true)
	item.set_editable(2, true)

	# Guardar referencias bidireccionales en los metadatos del ítem
	item.set_metadata(1, real_node)
	item.set_metadata(0, type)

	# Sincronizar checkboxes con el estado real del motor
	item.set_checked(0, real_node.visible)
	var is_locked : bool = real_node.get_meta("locked", false)
	item.set_checked(2, is_locked)

	# Aplicar paleta de color correspondiente (Gris, Azul para grupos, etc.)
	_aplicar_estilo_visibilidad(item, real_node.visible, type)

	# Aviso visual si la figura quedó fuera de los límites de su artboard
	# (arrastrada fuera, o creada con coordenadas fuera de rango).
	if type != "artboard" and _esta_fuera_del_artboard(real_node, artboard_actual):
		item.set_text(1, real_node.name + "  ⚠ fuera del artboard")
		item.set_tooltip_text(1, "Esta figura está fuera de los límites del artboard")
		if real_node.visible:
			item.set_custom_color(1, Color(0.95, 0.65, 0.15))  # Naranja de aviso

	# Mapear nodo → TreeItem para actualizaciones incrementales
	_node_to_item_map[real_node] = item

	return item


# =============================================================================
# CONTROLADORES DE EVENTOS DE INTERFAZ Y LIENZO
# =============================================================================
func _on_layer_tree_item_edited() -> void:
	if _bloquear_sincronizacion or not is_instance_valid(layer_tree):
		return

	var item_editado = layer_tree.get_edited()
	if not item_editado:
		return

	var columna : int = layer_tree.get_edited_column()
	var nodo_real : Node2D = item_editado.get_metadata(1) as Node2D
	var tipo : String = item_editado.get_metadata(0) as String

	if not is_instance_valid(nodo_real):
		return

	match columna:
		0: # Interruptor de Visibilidad (Ojo)
			var visual : bool = item_editado.is_checked(0)
			nodo_real.visible = visual
			_aplicar_estilo_visibilidad(item_editado, visual, tipo)
			_repintar_canvas()
		1: # Cambio de nombre por doble clic
			var texto : String = item_editado.get_text(1).strip_edges()
			if texto != "":
				nodo_real.name = texto
			else:
				item_editado.set_text(1, nodo_real.name)
		2: # Interruptor de Bloqueo (Candado)
			var bloqueado : bool = item_editado.is_checked(2)
			nodo_real.set_meta("locked", bloqueado)


func _on_node_added(nodo: Node) -> void:
	# Se dispara cuando se agrega un nodo
	if nodo is Node2D:
		_pending_changes.append({"node": nodo, "action": "added"})
		_schedule_update()

func _on_node_removed(nodo: Node) -> void:
	# Se dispara cuando se quita un nodo
	if nodo is Node2D:
		_pending_changes.append({"node": nodo, "action": "removed"})
		_schedule_update()

func _schedule_update() -> void:
	# Programar una actualización batch si no está ya programada
	if _update_timer and not _update_timer.is_stopped():
		_update_timer.start()

func _setup_update_timer() -> void:
	# Crear timer para actualizaciones batch
	_update_timer = Timer.new()
	_update_timer.wait_time = 0.1  # 100ms de batch
	_update_timer.timeout.connect(_process_pending_changes)
	_update_timer.one_shot = true
	add_child(_update_timer)

func _process_pending_changes() -> void:
	if _pending_changes.is_empty() or _bloquear_sincronizacion:
		return
	
	_bloquear_sincronizacion = true
	
	# Procesar solo los cambios pendientes
	for change in _pending_changes:
		var nodo = change["node"]
		var action = change["action"]
		
		if action == "added":
			# Encontrar el padre en el árbol
			var parent_node = nodo.get_parent()
			if parent_node and _node_to_item_map.has(parent_node):
				var parent_item = _node_to_item_map[parent_node]
				# Crear TreeItem para este nodo
				_create_tree_item(parent_item, nodo, _encontrar_artboard_ancestro(nodo))
			elif artboard_container and artboard_container == nodo.get_parent():
				# Es un artboard directo
				_create_tree_item(layer_tree.get_root(), nodo, nodo)
			
		elif action == "removed":
			# Eliminar el TreeItem correspondiente
			if _node_to_item_map.has(nodo):
				var item = _node_to_item_map[nodo]
				if item and item.get_parent():
					item.get_parent().remove_child(item)
					_node_to_item_map.erase(nodo)
	
	_pending_changes.clear()
	_bloquear_sincronizacion = false
	_repintar_canvas()


# =============================================================================
# ASISTENTES TÉCNICOS Y RECONEXIÓN DINÁMICA
# =============================================================================

## Sube por los padres hasta encontrar el artboard directo de artboard_container
## al que pertenece nodo — usado por la ruta de alta incremental (drag&drop
## nuevo desde otra herramienta) para saber contra qué artboard comprobar
## "fuera de límites".
func _encontrar_artboard_ancestro(nodo: Node) -> Node2D:
	var actual: Node = nodo
	while actual:
		if is_instance_valid(artboard_container) and actual.get_parent() == artboard_container:
			return actual as Node2D
		actual = actual.get_parent()
	return null

func _vincular_senales_artboard(artboard: Node2D) -> void:
	# Conecta las señales del Artboard para que el árbol se entere si creas un rectángulo dentro de él
	if not artboard in _artboards_conectados:
		_artboards_conectados.append(artboard)
		if not artboard.child_entered_tree.is_connected(_on_canvas_structure_changed):
			artboard.child_entered_tree.connect(_on_canvas_structure_changed)
		if not artboard.child_exiting_tree.is_connected(_on_canvas_structure_changed):
			artboard.child_exiting_tree.connect(_on_canvas_structure_changed)


func _on_canvas_structure_changed(_nodo: Node) -> void:
	# Diferido a propósito: este handler llega SÍNCRONAMENTE desde
	# child_entered_tree, es decir, en mitad de add_child() — antes de que el
	# código que crea la figura llegue a asignarle su posición real (p.ej.
	# TextTool._create_new_title_at() hace primero add_child() y RECIÉN
	# DESPUÉS position = local_pos). Sincronizar aquí mismo evaluaba el
	# indicador de "fuera del artboard" contra la posición (0,0) por defecto
	# de todo Node2D recién creado, nunca la posición final. call_deferred()
	# lo pospone al final del frame actual, cuando esa asignación ya ocurrió.
	sincronizar_arbol_completo.call_deferred()

func _aplicar_estilo_visibilidad(item: TreeItem, esta_visible: bool, tipo: String) -> void:
	if not esta_visible:
		item.set_custom_color(1, Color(0.44, 0.44, 0.46)) # Atenuado corporativo
	else:
		match tipo:
			"artboard":
				item.set_custom_color(1, Color(0.95, 0.95, 0.96))
			"group":
				item.set_custom_color(1, Color(0.35, 0.75, 0.98)) # Azul elegante para grupos
			_:
				item.set_custom_color(1, Color(0.84, 0.84, 0.86)) # Blanco/Gris para vectores


func _repintar_canvas() -> void:
	if is_instance_valid(artboard_container):
		var raiz_canvas = artboard_container.get_parent()
		if raiz_canvas and raiz_canvas.has_method("queue_redraw"):
			raiz_canvas.queue_redraw()
