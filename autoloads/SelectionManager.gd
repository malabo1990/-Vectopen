# =============================================================================
# RUTA: res://autoloads/SelectionManager.gd
# AUTOLOAD (Singleton)
# =============================================================================
extends Node
## SelectionManager — autoridad ÚNICA sobre la selección VIVA del editor
## (nodos `Node2D` de la escena). Sustituye a los dos sistemas de selección
## paralelos que había antes:
##   · `MoveTool.selected_shapes` (Node2D, editor vivo)
##   · `DataRepository`/`ProjectManager.selected_shapes` (IDs de ShapeData)
##
## Todas las superficies leen y escriben aquí: Canvas/MoveTool, panel de capas,
## Bounding Box e Inspector. Ver docs/es/guides/PANEL_DE_CAPAS_PROFESIONAL.md
## (Fase 1: fundación de selección).
##
## Compatibilidad: cada cambio re-emite `GlobalEvents.selection_changed(shapes)`
## para que los oyentes previos (bounding_box, InspectorCore) sigan funcionando
## sin tocarlos.
##
## Arquitectura: el ESTADO y las REGLAS viven en `SelectionCore`
## (RefCounted puro, testeable sin árbol). Este autoload es solo el wrapper
## con efectos: señales + re-emisión a GlobalEvents.

signal changed(selected: Array)      ## el CONJUNTO seleccionado cambió
signal active_changed(node: Node)    ## cambió el elemento PRIMARIO (último tocado)

## Modo de combinación al seleccionar. Alias de `SelectionCore.Mode`
## (se mantiene aquí para no romper los ~30 archivos que usan `Mode.ADD`…).
enum Mode { REPLACE, ADD, TOGGLE }

## Nombres de nodos internos de render que NUNCA son capas de usuario.
## (Se mantiene por compatibilidad; la fuente de verdad es `SelectionCore.NON_LAYER`.)
const _NON_LAYER := [
	"Contorno_Stroke", "Render_Visual", "DisplayLabel",
	"ArtboardTitle", "TitleEdit",
]

## preload directo (no `class_name` global): el caché de clases del editor
## aún no conoce el archivo nuevo y sin esto el parse fallaría hasta el
## próximo escaneo.
const CoreScript := preload("res://autoloads/SelectionCore.gd")

var _core: CoreScript
var active_editing_object: Node2D = null

func set_active_editing_object(obj: Node2D) -> void:
	active_editing_object = obj

func get_active_editing_object() -> Node2D:
	if is_instance_valid(active_editing_object):
		return active_editing_object
	return null

func has_active_text_edit() -> bool:
	return is_instance_valid(active_editing_object)


func _ready() -> void:
	_core = CoreScript.new()

# ═════════════════════════════════════════════════════════════════════════════
# LECTURA (delegan a SelectionCore)
# ═════════════════════════════════════════════════════════════════════════════

func _c() -> CoreScript:
	if _core == null:
		_core = CoreScript.new()
	return _core

## Copia defensiva del conjunto seleccionado, ya depurada de nodos liberados.
func get_selected() -> Array[Node2D]:
	return _c().get_selected()

## El elemento primario (para el Inspector). El último tocado, o el último de
## la lista si aquel dejó de ser válido.
func get_active() -> Node2D:
	return _c().get_active()

func get_anchor() -> Node2D:
	return _c().get_anchor()

func set_anchor(node: Node2D) -> void:
	_c().set_anchor(node)

func is_selected(node: Node) -> bool:
	return _c().is_selected(node)

func count() -> int:
	return _c().count()

func is_empty() -> bool:
	return _c().is_empty()

# ═════════════════════════════════════════════════════════════════════════════
# ESCRITURA — API principal (delegan + emiten si el core marcó cambio)
# ═════════════════════════════════════════════════════════════════════════════

## Selecciona `node` según `mode`. `node` null + REPLACE = limpiar.
func select(node: Node2D, mode: int = Mode.REPLACE) -> void:
	_c().select(node, mode)
	_flush()

## Selecciona un conjunto. `mode` REPLACE reemplaza; ADD suma; TOGGLE alterna
## cada uno.
func select_many(nodes: Array, mode: int = Mode.REPLACE) -> void:
	_c().select_many(nodes, mode)
	_flush()

## Reemplazo directo del conjunto (marquee, "seleccionar todo", duplicar…).
func set_selection(nodes: Array) -> void:
	_c().set_selection(nodes)
	_flush()

func deselect(node: Node2D) -> void:
	_c().deselect(node)
	_flush()

func clear() -> void:
	_c().clear()
	_flush()

# ═════════════════════════════════════════════════════════════════════════════
# SELECCIÓN JERÁRQUICA (Fase 1: primitivas · Fase 2: interacción del panel)
# ═════════════════════════════════════════════════════════════════════════════

## Selecciona los hijos-capa DIRECTOS de `group` (un nivel).
func select_children(group: Node, mode: int = Mode.REPLACE) -> void:
	_c().select_children(group, mode)
	_flush()

## Selecciona TODOS los descendientes-capa de `group` (recursivo, sin el grupo).
func select_descendants(group: Node, mode: int = Mode.REPLACE) -> void:
	_c().select_descendants(group, mode)
	_flush()

## Selecciona `node` MÁS todos sus descendientes-capa (la rama entera).
func select_branch(node: Node, mode: int = Mode.REPLACE) -> void:
	_c().select_branch(node, mode)
	_flush()

# ═════════════════════════════════════════════════════════════════════════════
# LOTES — suprime `changed` hasta cerrar (marquee, selección por rango…)
# ═════════════════════════════════════════════════════════════════════════════

func begin_batch() -> void:
	_c().begin_batch()

func end_batch() -> void:
	_c().end_batch()
	_flush()

# ═════════════════════════════════════════════════════════════════════════════
# INTERNO / COMPAT
# ═════════════════════════════════════════════════════════════════════════════

## Compat: antes vivía aquí; ahora delega a `SelectionCore.is_selectable`.
func _selectable(n: Variant) -> bool:
	return _c().is_selectable(n)

## ¿`n` está bloqueado por herencia (un ancestro sí, él no)?
func locked_by_inheritance(n: Node) -> bool:
	return _c().locked_by_inheritance(n)

func _prune() -> void:
	# El podado real lo hace el core en cada lectura/emisión.
	pass

## Emite solo si el core registró un cambio pendiente (respeta lotes).
func _flush() -> void:
	if _c().take_pending_emit():
		_emit()

func _emit() -> void:
	var snapshot: Array = _c().get_selected()
	changed.emit(snapshot)
	active_changed.emit(_c().get_active())
	# Compatibilidad con los oyentes previos (bounding_box, InspectorCore…).
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("selection_changed"):
		if ge.has_method("emit_safe"):
			ge.emit_safe("selection_changed", snapshot)
		else:
			ge.selection_changed.emit(snapshot)
