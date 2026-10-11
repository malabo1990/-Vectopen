# =============================================================================
# VECTOPEN CORE — OBJECT POOLING SYSTEM
# RUTA: res://autoloads/ObjectPool.gd
# =============================================================================
extends Node

## Sistema centralizado de pooling para optimizar la creación/destrucción de objetos
## Reduce GC spikes y mejora el rendimiento en operaciones frecuentes

signal pool_initialized(pool_name: String, size: int)

# Configuración de pools
const POOL_CONFIG := {
	"BoundingBox": {
		"scene_path": "res://scenes/canvas/boundingbox.tscn",
		# ARRANQUE RÁPIDO: antes se creaban 20 al abrir (~250 ms antes de ver
		# la ventana). Solo hay una caja en uso a la vez y acquire() crea más
		# bajo demanda, así que basta con 2, precreadas DESPUÉS del primer
		# fotograma (ver _prewarm).
		"initial_size": 2,
		"max_size": 100
	}
}

# Pools activos
var _pools: Dictionary = {}

# ==========================================
# CICLO DE VIDA
# ==========================================

func _ready() -> void:
	# Inicializar todos los pools configurados
	for pool_name in POOL_CONFIG:
		_initialize_pool(pool_name)


func _initialize_pool(pool_name: String) -> void:
	if not POOL_CONFIG.has(pool_name):
		if ErrorHandler: ErrorHandler.report_pool("Pool no configurado - " + pool_name)
		else: push_error("ObjectPool: Pool no configurado - ", pool_name)
		return
	
	var config = POOL_CONFIG[pool_name]
	var pool = {
		"scene_path": config["scene_path"],
		"initial_size": config["initial_size"],
		"max_size": config["max_size"],
		"available": [],
		"in_use": [],
		"container": Node.new()
	}
	
	# Crear contenedor para el pool
	add_child(pool["container"])
	pool["container"].name = "Pool_" + pool_name
	
	_pools[pool_name] = pool
	# Pre-cargar objetos iniciales FUERA del arranque: uno por fotograma,
	# cuando la ventana ya se ve.
	_prewarm.call_deferred(pool_name)


func _prewarm(pool_name: String) -> void:
	var pool: Dictionary = _pools.get(pool_name, {})
	if pool.is_empty():
		return
	if is_inside_tree():
		await get_tree().process_frame
	while pool["available"].size() + pool["in_use"].size() < pool["initial_size"]:
		if is_inside_tree():
			await get_tree().process_frame
		if not is_instance_valid(pool["container"]):
			return
		var instance = _instantiate_scene(pool["scene_path"])
		if instance == null:
			break
		pool["available"].append(instance)
		pool["container"].add_child(instance)
		instance.visible = false
	pool_initialized.emit(pool_name, pool["initial_size"])


# ==========================================
# API PÚBLICA
# ==========================================

func acquire(pool_name: String) -> Node:
	"""
	Obtiene un objeto del pool. Si no hay disponibles, crea uno nuevo
	o devuelve null si se alcanzó el tamaño máximo.
	"""
	if not _pools.has(pool_name):
		push_error("ObjectPool: Pool no existe - ", pool_name)
		return null
	
	var pool = _pools[pool_name]

	# Si hay objetos disponibles, reutilizarlos. Defensa extra: descartar
	# cualquier referencia "available" ya liberada (no debería pasar ahora
	# que release() reparenta al contenedor propio del pool, ver ahí, pero
	# así un freed() externo al contrato del pool no vuelve a tumbar todo el
	# acquire() — solo se pierde esa instancia y se sigue con la siguiente).
	while pool["available"].size() > 0:
		var instance = pool["available"].pop_back()
		if not is_instance_valid(instance):
			continue
		pool["in_use"].append(instance)
		instance.visible = true
		_reset_instance(instance)
		return instance
	
	# Si no hay disponibles pero no hemos alcanzado el máximo, crear uno nuevo
	if pool["in_use"].size() + pool["available"].size() < pool["max_size"]:
		var instance = _instantiate_scene(pool["scene_path"])
		if instance:
			pool["container"].add_child(instance)
			pool["in_use"].append(instance)
			return instance
	
	# Pool agotado
	push_warning("ObjectPool: Pool agotado - ", pool_name)
	return null


func release(pool_name: String, instance: Node) -> void:
	"""
	Devuelve un objeto al pool para su reutilización.
	"""
	if not _pools.has(pool_name):
		push_error("ObjectPool: Pool no existe - ", pool_name)
		return
	
	var pool = _pools[pool_name]
	
	# Verificar si el objeto está en uso
	if instance in pool["in_use"]:
		pool["in_use"].erase(instance)
		pool["available"].append(instance)
		instance.visible = false
		_reset_instance(instance)
		# BUG REAL encontrado en vivo ("previously freed" al reusar del pool,
		# reproducible con PanelConfigWindowsElement_test.gd): quien toma
		# prestada una instancia (p.ej. MoveTool._acquire_bounding_box) la
		# reparenta a SU escena (reparent(canvas)) mientras la usa. Si
		# release() no la devuelve aquí al contenedor propio y persistente
		# del pool (hijo de este autoload, sobrevive a cambios de escena),
		# se queda colgando del canvas de esa escena — si esa escena se
		# destruye (cerrar documento, o un test terminando) con la instancia
		# todavía en su árbol, el pool queda con una referencia a un nodo YA
		# LIBERADO en "available", y el siguiente acquire() revienta al
		# tocarlo (instance.visible = true sobre un objeto freed).
		if is_instance_valid(instance) and instance.get_parent() != pool["container"]:
			if is_instance_valid(instance.get_parent()):
				instance.get_parent().remove_child(instance)
			pool["container"].add_child(instance)
	else:
		push_warning("ObjectPool: Intento de liberar objeto no en uso - ", pool_name, " - ", instance.name)


func get_pool_status(pool_name: String) -> Dictionary:
	"""
	Devuelve el estado actual del pool (estadísticas de uso).
	"""
	if not _pools.has(pool_name):
		return {"error": "Pool no existe"}
	
	var pool = _pools[pool_name]
	return {
		"pool_name": pool_name,
		"available": pool["available"].size(),
		"in_use": pool["in_use"].size(),
		"total": pool["available"].size() + pool["in_use"].size(),
		"max_size": pool["max_size"]
	}


func get_all_pools_status() -> Dictionary:
	"""
	Devuelve el estado de todos los pools.
	"""
	var status = {}
	for pool_name in _pools:
		status[pool_name] = get_pool_status(pool_name)
	return status


# ==========================================
# MÉTODOS PRIVADOS
# ==========================================

func _instantiate_scene(scene_path: String) -> Node:
	"""
	Instancia una escena desde un archivo .tscn o .scn.
	"""
	var scene = load(scene_path)
	if not scene:
		push_error("ObjectPool: No se pudo cargar la escena - ", scene_path)
		return null
	
	var instance = scene.instantiate()
	if not instance:
		push_error("ObjectPool: No se pudo instanciar la escena - ", scene_path)
		return null
	
	return instance


func _reset_instance(instance: Node) -> void:
	"""
	Restablece un objeto a su estado inicial para su reutilización.
	Usa el método reset_pooled() si existe (convention-based).
	"""
	if instance.has_method("reset_pooled"):
		instance.reset_pooled()
	else:
		if instance is Node2D:
			instance.position = Vector2.ZERO
			instance.scale = Vector2.ONE
			instance.visible = false
		elif instance is Control:
			instance.position = Vector2.ZERO
			instance.visible = false
