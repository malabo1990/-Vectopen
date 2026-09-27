# =============================================================================
# RUTA: res://autoloads/SelectionCore.gd
# LÓGICA PURA (RefCounted, sin autoload, sin señales globales)
# =============================================================================
## SelectionCore — el ESTADO y las REGLAS de la selección, sin efectos lados.
##
## `SelectionManager` (autoload) es un wrapper delgado que posee una instancia
## de esta clase y añade lo único con efectos: señales `changed` /
## `active_changed` + re-emisión a `GlobalEvents.selection_changed`.
##
## Regla: toda decisión ("¿seleccionable?", "¿qué cambia con este modo?",
## "¿se coalescea el lote?") vive aquí. El wrapper solo emite.
class_name SelectionCore
extends RefCounted

## Modo de combinación al seleccionar.
##  REPLACE — reemplaza la selección por el nodo
##  ADD     — añade a la selección
##  TOGGLE  — quita si estaba, añade si no
enum Mode { REPLACE, ADD, TOGGLE }

## Nombres de nodos internos de render que NUNCA son capas de usuario.
const NON_LAYER := [
	"Contorno_Stroke", "Render_Visual", "DisplayLabel",
	"ArtboardTitle", "TitleEdit",
]

var _selected: Array[Node2D] = []
var _active: Node2D = null ## primario para el Inspector (último tocado)
var _anchor: Node2D = null ## ancla para selección por rango (Shift)
var _batch_depth: int = 0
var _dirty_in_batch: bool = false
## true cuando la última mutación cambió el conjunto y el wrapper debe emitir.
var _pending_emit: bool = false


func take_pending_emit() -> bool:
	var out := _pending_emit
	_pending_emit = false
	return out


# ── LECTURA ────────────────────────────────────────────────────────────────

## Copia defensiva del conjunto seleccionado, ya depurada de nodos liberados.
func get_selected() -> Array[Node2D]:
	_prune()
	return _selected.duplicate()


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


func in_batch() -> bool:
	return _batch_depth > 0


# ── ESCRITURA ──────────────────────────────────────────────────────────────

## Selecciona `node` según `mode`. `node` null + REPLACE = limpiar.
func select(node: Node2D, mode: int = Mode.REPLACE) -> void:
	if node == null:
		if mode == Mode.REPLACE:
			clear()
		return
	if not is_selectable(node):
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
	_mark_dirty()


## Selecciona un conjunto. REPLACE reemplaza; ADD suma; TOGGLE alterna cada uno.
func select_many(nodes: Array, mode: int = Mode.REPLACE) -> void:
	var clean: Array[Node2D] = []
	for n in nodes:
		if is_selectable(n) and n not in clean:
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
		_mark_dirty()


func clear() -> void:
	if _selected.is_empty() and _active == null:
		return
	_selected.clear()
	_active = null
	_anchor = null
	_mark_dirty()


# ── SELECCIÓN JERÁRQUICA ───────────────────────────────────────────────────

## Hijos-capa DIRECTOS de `group` (un nivel).
func select_children(group: Node, mode: int = Mode.REPLACE) -> void:
	if not is_instance_valid(group):
		return
	var kids: Array = []
	for c in group.get_children():
		if is_selectable(c):
			kids.append(c)
	select_many(kids, mode)


## TODOS los descendientes-capa de `group` (recursivo, sin el grupo).
func select_descendants(group: Node, mode: int = Mode.REPLACE) -> void:
	if not is_instance_valid(group):
		return
	var out: Array = []
	_collect_descendants(group, out)
	select_many(out, mode)


## `node` MÁS todos sus descendientes-capa (la rama entera).
func select_branch(node: Node, mode: int = Mode.REPLACE) -> void:
	if not is_instance_valid(node):
		return
	var out: Array = [node]
	_collect_descendants(node, out)
	select_many(out, mode)


func _collect_descendants(n: Node, out: Array) -> void:
	for c in n.get_children():
		if is_selectable(c):
			out.append(c)
		if c is Node2D:
			_collect_descendants(c, out)


# ── LOTES ──────────────────────────────────────────────────────────────────

func begin_batch() -> void:
	_batch_depth += 1


func end_batch() -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth == 0 and _dirty_in_batch:
		_dirty_in_batch = false
		_pending_emit = true


# ── REGLAS ─────────────────────────────────────────────────────────────────

## ¿`n` es capa de usuario seleccionable (figura / grupo / trazo / imagen)
## y no un nodo interno de render?
func is_selectable(n: Variant) -> bool:
	if not (n is Node2D) or not is_instance_valid(n):
		return false
	if String(n.name) in NON_LAYER:
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


func _mark_dirty() -> void:
	if _batch_depth > 0:
		_dirty_in_batch = true
		return
	_prune()
	_pending_emit = true
