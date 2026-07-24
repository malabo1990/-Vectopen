# =============================================================================
# VECTOPEN CORE — EXPORT CACHE SYSTEM
# RUTA: res://autoloads/ExportCache.gd
# =============================================================================
extends Node

## Sistema de caché para optimizar exportaciones repetidas
## Reduce el tiempo de exportación al evitar reprocesar los mismos datos

signal cache_updated(cache_key: String, hit: bool)

# Configuración de la caché
var cache_max_size: int = 20
var cache_ttl: int = 300
var cache_enabled: bool = true

# Estructura de la caché
var _cache: Dictionary = {}
var _access_order: Array = []  # Para implementar LRU (Least Recently Used)

# ==========================================
# CICLO DE VIDA
# ==========================================

func _ready() -> void:
	# Limpiar caché periódicamente
	var timer = Timer.new()
	add_child(timer)
	timer.timeout.connect(_cleanup_cache)
	timer.start(60.0)  # Limpiar cada minuto


# ==========================================
# API PÚBLICA
# ==========================================

func get_cache_key(data: Dictionary, export_format: String) -> String:
	"""
	Genera una clave única para la caché basada en los datos y formato de exportación.
	"""
	var data_copy = data.duplicate(true)
	# Eliminar campos que no afectan la exportación
	if data_copy.has("timestamp"):
		data_copy.erase("timestamp")
	if data_copy.has("export_time"):
		data_copy.erase("export_time")
	
	# Ordenar las claves para consistencia
	var keys = data_copy.keys()
	keys.sort()
	
	var key_parts = []
	for key in keys:
		key_parts.append(str(key) + ":" + str(data_copy[key]))
	
	# Incluir el formato de exportación
	key_parts.append("format:" + export_format)
	
	# Generar hash MD5
	var key_string = str(key_parts)
	return key_string.md5_text()


func store(export_format: String, data: Dictionary, result: Variant) -> void:
	"""
	Almacena un resultado de exportación en la caché.
	"""
	if not cache_enabled:
		return
	
	var cache_key = get_cache_key(data, export_format)
	
	# Si la clave ya existe, actualizar el acceso
	if _cache.has(cache_key):
		_access_order.erase(cache_key)
	else:
		# Si la caché está llena, eliminar el menos usado
		if _access_order.size() >= cache_max_size:
			var lru_key = _access_order.pop_front()
			_cache.erase(lru_key)
	
	# Almacenar el nuevo resultado
	_cache[cache_key] = {
		"result": result,
		"timestamp": Time.get_unix_time_from_system(),
		"format": export_format,
		"data": data.duplicate(true)
	}
	
	# Registrar el acceso
	_access_order.append(cache_key)
	cache_updated.emit(cache_key, false)  # false = miss (almacenado)


func retrieve(export_format: String, data: Dictionary) -> Variant:
	"""
	Recupera un resultado de exportación de la caché.
	Devuelve null si no está en caché.
	"""
	if not cache_enabled:
		return null
	
	var cache_key = get_cache_key(data, export_format)
	
	# Verificar si la clave existe y no ha expirado
	if _cache.has(cache_key):
		var cache_entry = _cache[cache_key]
		if Time.get_unix_time_from_system() - cache_entry["timestamp"] <= cache_ttl:
			# Actualizar orden de acceso (LRU)
			_access_order.erase(cache_key)
			_access_order.append(cache_key)
			cache_updated.emit(cache_key, true)  # true = hit (recuperado)
			return cache_entry["result"]
		else:
			# Entrada expirada
			_cache.erase(cache_key)
			_access_order.erase(cache_key)
	
	return null


func clear() -> void:
	"""
	Limpia toda la caché.
	"""
	_cache.clear()
	_access_order.clear()


func get_cache_stats() -> Dictionary:
	"""
	Devuelve estadísticas de uso de la caché.
	"""
	return {
		"size": _cache.size(),
		"max_size": cache_max_size,
		"enabled": cache_enabled,
		"hit_rate": _get_hit_rate()
	}


func set_enabled(enabled: bool) -> void:
	"""
	Habilita o deshabilita la caché.
	"""
	cache_enabled = enabled
	if not enabled:
		clear()


# ==========================================
# MÉTODOS PRIVADOS
# ==========================================

func _cleanup_cache() -> void:
	"""
	Limpia entradas expiradas de la caché.
	"""
	var current_time = Time.get_unix_time_from_system()
	var expired_keys = []
	
	for key in _cache:
		var entry = _cache[key]
		if current_time - entry["timestamp"] > cache_ttl:
			expired_keys.append(key)
	
	for key in expired_keys:
		_cache.erase(key)
		_access_order.erase(key)


func _get_hit_rate() -> float:
	"""
	Calcula la tasa de aciertos de la caché (0.0 - 1.0).
	"""
	# Este es un método simplificado. En una implementación real,
	# deberías llevar un registro de hits y misses.
	if _cache.size() == 0:
		return 0.0
	
	# Estimación basada en el tamaño actual vs máximo
	return float(_cache.size()) / float(cache_max_size)