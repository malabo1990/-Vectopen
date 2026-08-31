# ==========================================
# RUTA: res://scenes/canvas/artboard_manager.gd
# AUTORIDAD ÚNICA del sistema multi-artboard (lado escena / vista).
#
# El resto del código (herramientas, ShapeManager, MoveTool, minimapa) debía
# resolver "¿en qué artboard va esto?" cada uno por su cuenta, y casi todos
# hacían `ArtboardsContainer.get_child(0)` → SIEMPRE el primero. Por eso el
# multi-artboard "solo funcionaba con el principal": las figuras nuevas caían
# en el artboard 0 aunque estuvieras editando otro, y una figura suelta
# (fuera de todo artboard) no se reconocía como tal.
#
# Ahora todo pasa por aquí:
#   get_active_artboard()          -> el artboard que recibe elementos nuevos
#   artboard_at_point(world_pos)   -> qué artboard CONTIENE ese punto (null = fuera)
#   owning_artboard(node)          -> a qué artboard PERTENECE una figura existente
#   world_rect(ab)                 -> rect del artboard en coordenadas de mundo
# ==========================================
extends Node
class_name ArtboardManager

const GROUP_MANAGER := "artboard_manager"
const GROUP_ARTBOARD := "artboards"

@export var artboards: Array[ArtboardEditor] = []
var active_artboard: ArtboardEditor = null

## MRU de artboards activados. Mientras haya historial de undo, el streamer
## NO duerme estos: sus figuras están referenciadas por callables de
## HistoryManager y liberarlas dejaría el undo/redo sin efecto (ver punto 4).
var recent: Array[ArtboardEditor] = []
const RECENT_MAX := 4

var _container: Node2D = null


func _ready() -> void:
	add_to_group(GROUP_MANAGER)
	var scene := get_tree().current_scene if get_tree() else null
	_container = get_parent().get_node_or_null("ArtboardsContainer") if get_parent() else null
	if not _container and scene:
		_container = scene.find_child("ArtboardsContainer", true, false) as Node2D

	if _container:
		if not _container.child_entered_tree.is_connected(_on_container_child_entered):
			_container.child_entered_tree.connect(_on_container_child_entered)
		if not _container.child_exiting_tree.is_connected(_on_container_child_exiting):
			_container.child_exiting_tree.connect(_on_container_child_exiting)
		for child in _container.get_children():
			if child is ArtboardEditor:
				add_artboard(child)

	# Nunca dejar `active_artboard` en null si hay artboards: así las
	# herramientas siempre tienen destino.
	_ensure_active()
	print("ArtboardManager: %d artboards | activo = %s" % [
		artboards.size(), String(active_artboard.name) if active_artboard else "<ninguno>"])


# ─────────────────────────────────────────────────────────── registro
func add_artboard(ab: ArtboardEditor) -> void:
	if not is_instance_valid(ab):
		return
	if not ab.is_in_group(GROUP_ARTBOARD):
		ab.add_to_group(GROUP_ARTBOARD)
	if not artboards.has(ab):
		artboards.append(ab)
	_ensure_active()


func remove_artboard(ab: ArtboardEditor) -> void:
	artboards.erase(ab)
	if active_artboard == ab:
		active_artboard = null
		_ensure_active()


func _on_container_child_entered(node: Node) -> void:
	if node is ArtboardEditor:
		add_artboard(node)


func _on_container_child_exiting(node: Node) -> void:
	if node is ArtboardEditor:
		remove_artboard(node)


func all_artboards() -> Array[ArtboardEditor]:
	var out: Array[ArtboardEditor] = []
	for ab in artboards:
		if is_instance_valid(ab):
			out.append(ab)
	return out


# ─────────────────────────────────────────────────────────── activo
func set_active_artboard(target_ab: ArtboardEditor) -> void:
	if not is_instance_valid(target_ab):
		return
	if not artboards.has(target_ab):
		add_artboard(target_ab)
	var cambio := active_artboard != target_ab
	active_artboard = target_ab
	recent.erase(target_ab)
	recent.push_front(target_ab)
	if recent.size() > RECENT_MAX:
		recent.resize(RECENT_MAX)
	# Sincroniza is_selected SIEMPRE (barato) — no solo cuando cambia el activo:
	# el doble-clic en el título debe seleccionar el artboard aunque ya fuera
	# el activo por defecto al arrancar.
	for ab in artboards:
		if is_instance_valid(ab):
			ab.is_selected = (ab == target_ab)
	if cambio and has_node("/root/GlobalEvents"):
		get_node("/root/GlobalEvents").emit_safe("active_artboard_changed")


## El artboard que recibe elementos nuevos creados "sin punto" (botones
## "crear en el centro", pegar, importar...). Nunca null si hay artboards.
func get_active_artboard() -> ArtboardEditor:
	_ensure_active()
	return active_artboard


func _ensure_active() -> void:
	if is_instance_valid(active_artboard) and artboards.has(active_artboard):
		return
	active_artboard = null
	for ab in artboards:
		if is_instance_valid(ab):
			active_artboard = ab
			return


# ─────────────────────────────────────────────────────────── geometría
## Rect del artboard EN COORDENADAS DE MUNDO. Los artboards no se escalan ni
## rotan (ver tests), así que su AABB es exacto.
func world_rect(ab: ArtboardEditor) -> Rect2:
	if not is_instance_valid(ab):
		return Rect2()
	return Rect2(ab.global_position, ab.artboard_size)


## Qué artboard CONTIENE `world_point`. null = el punto está fuera de todos
## los artboards (elemento "suelto"). Si varios se solapan gana el último del
## contenedor (el que se dibuja encima).
func artboard_at_point(world_point: Vector2) -> ArtboardEditor:
	var hit: ArtboardEditor = null
	for ab in artboards:
		if is_instance_valid(ab) and world_rect(ab).has_point(world_point):
			hit = ab
	return hit


## A qué artboard PERTENECE una figura ya existente (por jerarquía de árbol,
## no por geometría). null si es hija directa del contenedor (suelta) o no
## cuelga de ningún artboard.
func owning_artboard(node: Node) -> ArtboardEditor:
	var cur: Node = node
	while is_instance_valid(cur):
		if cur is ArtboardEditor:
			return cur
		cur = cur.get_parent()
	return null


## ¿La figura está FUERA de su artboard (o fuera de todos)? Comprobación por
## el origen del nodo — suficiente para el aviso del panel de capas.
func is_element_outside(node: Node2D) -> bool:
	if not is_instance_valid(node):
		return false
	var owner_ab := owning_artboard(node)
	if owner_ab == null:
		return true  # suelto: fuera de todo artboard
	return not world_rect(owner_ab).has_point(node.global_position)


# ─────────────────────────────────────────────────────── acceso estático
## Localiza el ArtboardManager vivo desde cualquier sitio (herramientas, etc.).
static func find(tree: SceneTree) -> ArtboardManager:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP_MANAGER) as ArtboardManager
