# res://scenes/ui/layers_drop_handler.gd
# SCRIPT SECUNDARIO CORREGIDO: Herencia limpia de Node y clonación recursiva sin fallos
extends Node

@onready var tree: Tree = get_parent() as Tree

# 1. Iniciar el arrastre
func handle_get_drag_data(position: Vector2) -> Variant:
	if not tree: return null
	
	var item = tree.get_item_at_position(position)
	if not item: return null
		
	tree.mouse_default_cursor_shape = Control.CURSOR_DRAG
	
	var preview = Label.new()
	preview.text = "  Mover: " + item.get_text(0)
	preview.modulate = Color(0.22, 0.45, 0.85, 0.9)
	tree.set_drag_preview(preview)
	
	return item

# 2. Validar zonas permitidas de soltado
func handle_can_drop_data(position: Vector2, data: Variant) -> bool:
	if not data is TreeItem or not tree: return false
		
	var target_item = tree.get_item_at_position(position)
	if not target_item: return true # Permitir soltar abajo para extraer del grupo
		
	var item_arrastrado = data as TreeItem
	if item_arrastrado == target_item: return false
		
	# Evitar bucles infinitos en la jerarquía de capas
	var temp = target_item.get_parent()
	while temp != null:
		if temp == item_arrastrado:
			return false
		temp = temp.get_parent()
		
	return true

# 3. Procesar las líneas de posición o el rectángulo de hijo
func handle_drop_data(position: Vector2, data: Variant) -> void:
	if not tree: return
	
	var item_arrastrado = data as TreeItem
	var target_item = tree.get_item_at_position(position)
	
	tree.mouse_default_cursor_shape = Control.CURSOR_ARROW
	
	# Si se suelta en la parte baja del panel vacío -> Sacar a la raíz
	if not target_item:
		_clonar_item_en_destino(item_arrastrado, tree.get_root(), null, 0)
		_notificar_cambio()
		return

	var drop_section = tree.get_drop_section_at_position(position)
	
	if drop_section == 0:
		# RECTÁNGULO CENTRAL: Mover dentro de la capa como hijo (Crear Grupo)
		_clonar_item_en_destino(item_arrastrado, target_item, null, 0)
		target_item.collapsed = false
	elif drop_section == -1:
		# LÍNEA SUPERIOR: Cambiar posición justo arriba (Hermano)
		_clonar_item_en_destino(item_arrastrado, target_item.get_parent(), target_item, -1)
	elif drop_section == 1:
		# LÍNEA INFERIOR: Cambiar posición justo debajo (Hermano)
		_clonar_item_en_destino(item_arrastrado, target_item.get_parent(), target_item, 1)

	_notificar_cambio()

# ==============================================================================
# CLONACIÓN DE ELEMENTOS CON FILTRADO DE PROPIEDADES NATIVAS
# ==============================================================================
func _clonar_item_en_destino(item_viejo: TreeItem, nuevo_padre: TreeItem, destino_relativo: TreeItem, modo: int) -> void:
	if not nuevo_padre:
		nuevo_padre = tree.get_root()

	var item_nuevo: TreeItem = tree.create_item(nuevo_padre)
	
	if destino_relativo:
		if modo == -1:
			item_nuevo.move_before(destino_relativo)
		elif modo == 1:
			item_nuevo.move_after(destino_relativo)

	# Clonar celdas y filtrar colores vacíos para que no se vuelvan negros
	for i in range(tree.get_columns()):
		item_nuevo.set_text(i, item_viejo.get_text(i))
		item_nuevo.set_icon(i, item_viejo.get_icon(i))
		item_nuevo.set_checked(i, item_viejo.is_checked(i))
		item_nuevo.set_selectable(i, item_viejo.is_selectable(i))
		item_nuevo.set_metadata(i, item_viejo.get_metadata(i))
		
		var color_texto = item_viejo.get_custom_color(i)
		if color_texto.a > 0.01: 
			item_nuevo.set_custom_color(i, color_texto)
			
		var color_fondo = item_viejo.get_custom_bg_color(i)
		if color_fondo.a > 0.01: 
			item_nuevo.set_custom_bg_color(i, color_fondo)

	# Clonación recursiva de las subcapas
	var hijo_actual = item_viejo.get_first_child()
	while hijo_actual != null:
		_clonar_item_en_destino(hijo_actual, item_nuevo, null, 0)
		hijo_actual = hijo_actual.get_next()

	if item_viejo.get_first_child():
		item_nuevo.collapsed = false

	item_nuevo.select(0)
	item_viejo.free()

func _notificar_cambio() -> void:
	if tree and tree.owner and tree.owner.has_method("_on_layers_reordered"):
		tree.owner._on_layers_reordered()
