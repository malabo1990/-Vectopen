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

signal changed(selected: Array)      ## el CONJUNTO seleccionado cambió
signal active_changed(node: Node)    ## cambió el elemento PRIMARIO (último tocado)

## Modo de combinación al seleccionar.
##  REPLACE — reemplaza la selección por el nodo
##  ADD     — añade a la selección
##  TOGGLE  — quita si estaba, añade si no
enum Mode { REPLACE, ADD, TOGGLE }

## Nombres de nodos internos de render que NUNCA son capas de usuario.
const _NON_LAYER := [
	"Contorno_Stroke", "Render_Visual", "DisplayLabel",
	"ArtboardTitle", "TitleEdit",
]

var _selected: Array[Node2D] = []
var _active: Node2D = null      ## el que el Inspector trata como principal
var _anchor: Node2D = null      ## ancla para selección por rango (Shift) — la fija el panel
var _batch_depth: int = 0       ## >0 → se suprime `changed` hasta cerrar el lote
var _dirty_in_batch: bool = false

# ═════════════════════════════════════════════════════════════════════════════
# LECTURA
# ═════════════════════════════════════════════════════════════════════════════

## Copia defensiva del conjunto seleccionado, ya depurada de nodos liberados.
func get_selected() -> Array[Node2D]:
	_prune()
	return _selected.duplicate()

## El elemento primario (para el Inspector). El último tocado, o el último de
## la lista si aquel dejó de ser válido.
func get_active() -> Node2D:
	if not is_instance_valid(_active) or not (_active in _selected):
		_active = _selected[_selected.size() - 1] if not _selected.is_empty() else null
	return _active

func get_anchor() -> Node2D:
	return _anchor if is_instance_valid(_anchor) else null

func set_anchor(node: Node2D) -> void:
	_anchor = node

func is_selected(node: Node) -> bool:
	return node in _selected

func count() -> int:
	_prune()
	return _selected.size()

func is_empty() -> bool:
	return count() == 0

# ═════════════════════════════════════════════════════════════════════════════
# ESCRITURA — API principal
# ═════════════════════════════════════════════════════════════════════════════

## Selecciona `node` según `mode`. `node` null + REPLACE = limpiar.
func select(node: Node2D, mode: int = Mode.REPLACE) -> void:
	if node == null:
		if mode == Mode.REPLACE:
			clear()
		return
	if not _selectable(node):
		return
	match mode:
		Mode.REPLACE:
			_selected = [node] as Array[Node2D]
			_active = node
			_anchor = node
		Mode.ADD:
			if node not in _selected:
				_selected.append(node)
			_active = node
			_anchor = node
		Mode.TOGGLE:
			if node in _selected:
				_selected.erase(node)
				if _active == node:
					_active = _selected[_selected.size() - 1] if not _selected.is_empty() else null
			else:
				_selected.append(node)
				_active = node
			_anchor = node
	_emit()

## Selecciona un conjunto. `mode` REPLACE reemplaza; ADD suma; TOGGLE alterna
## cada uno.
func select_many(nodes: Array, mode: int = Mode.REPLACE) -> void:
	var clean: Array[Node2D] = []
	for n in nodes:
		if _selectable(n) and n not in clean:
			clean.append(n)
	begin_batch()
	if mode == Mode.REPLACE:
		_selected = clean.duplicate()
		_active = clean[clean.size() - 1] if not clean.is_empty() else null
		_dirty_in_batch = true
	else:
		for n in clean:
			if mode == Mode.TOGGLE and n in _selected:
				_selected.erase(n)
			elif n not in _selected:
				_selected.append(n)
			_active = n
			_dirty_in_batch = true
	if not clean.is_empty():
		_anchor = clean[clean.size() - 1]
	end_batch()

## Reemplazo directo del conjunto (marquee, "seleccionar todo", duplicar…).
func set_selection(nodes: Array) -> void:
	select_many(nodes, Mode.REPLACE)

func deselect(node: Node2D) -> void:
	if node in _selected:
		_selected.erase(node)
		if _active == node:
			_active = _selected[_selected.size() - 1] if not _selected.is_empty() else null
		_emit()

func clear() -> void:
	if _selected.is_empty() and _active == null:
		return
	_selected.clear()
	_active = null
	_anchor = null
	_emit()

# ═════════════════════════════════════════════════════════════════════════════
# SELECCIÓN JERÁRQUICA (Fase 1: primitivas · Fase 2: interacción del panel)
# ═════════════════════════════════════════════════════════════════════════════

## Selecciona los hijos-capa DIRECTOS de `group` (un nivel).
func select_children(group: Node, mode: int = Mode.REPLACE) -> void:
	if not is_instance_valid(group):
		return
	var kids: Array = []
	for c in group.get_children():
		if _selectable(c):
			kids.append(c)
	select_many(kids, mode)

## Selecciona TODOS los descendientes-capa de `group` (recursivo, sin el grupo).
func select_descendants(group: Node, mode: int = Mode.REPLACE) -> void:
	if not is_instance_valid(group):
		return
	var out: Array = []
	_collect_descendants(group, out)
	select_many(out, mode)

## Selecciona `node` MÁS todos sus descendientes-capa (la rama entera).
func select_branch(node: Node, mode: int = Mode.REPLACE) -> void:
	if not is_instance_valid(node):
		return
	var out: Array = [node]
	_collect_descendants(node, out)
	select_many(out, mode)

func _collect_descendants(n: Node, out: Array) -> void:
	for c in n.get_children():
		if _selectable(c):
			out.append(c)
		if c is Node2D:
			_collect_descendants(c, out)

# ═════════════════════════════════════════════════════════════════════════════
# LOTES — suprime `changed` hasta cerrar (marquee, selección por rango…)
# ═════════════════════════════════════════════════════════════════════════════

func begin_batch() -> void:
	_batch_depth += 1

func end_batch() -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth == 0 and _dirty_in_batch:
		_dirty_in_batch = false
		_emit()

# ═════════════════════════════════════════════════════════════════════════════
# INTERNO
# ═════════════════════════════════════════════════════════════════════════════

## ¿`n` es una capa de usuario seleccionable (figura / grupo / trazo / imagen)
## y no un nodo interno de render?
func _selectable(n: Variant) -> bool:
	if not (n is Node2D) or not is_instance_valid(n):
		return false
	if String(n.name) in _NON_LAYER:
		return false
	# Bloqueo directo O heredado de un ancestro (grupo/artboard bloqueado
	# protege todo su contenido — como en un editor profesional).
	var a: Node = n
	while a != null:
		if a.has_meta("locked") and bool(a.get_meta("locked")):
			return false
		a = a.get_parent()
	return true

## ¿`n` está bloqueado por herencia (un ancestro sí, él no)?
func locked_by_inheritance(n: Node) -> bool:
	if not is_instance_valid(n):
		return false
	if n.has_meta("locked") and bool(n.get_meta("locked")):
		return false
	var a: Node = n.get_parent()
	while a != null:
		if a.has_meta("locked") and bool(a.get_meta("locked")):
			return true
		a = a.get_parent()
	return false

func _prune() -> void:
	var changed_any := false
	for i in range(_selected.size() - 1, -1, -1):
		if not is_instance_valid(_selected[i]):
			_selected.remove_at(i)
			changed_any = true
	if changed_any and not is_instance_valid(_active):
		_active = _selected[_selected.size() - 1] if not _selected.is_empty() else null

func _emit() -> void:
	if _batch_depth > 0:
		_dirty_in_batch = true
		return
	_prune()
	var snapshot: Array = _selected.duplicate()
	changed.emit(snapshot)
	active_changed.emit(get_active())
	# Compatibilidad con los oyentes previos (bounding_box, InspectorCore…).
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("selection_changed"):
		if ge.has_method("emit_safe"):
			ge.emit_safe("selection_changed", snapshot)
		else:
			ge.selection_changed.emit(snapshot)
