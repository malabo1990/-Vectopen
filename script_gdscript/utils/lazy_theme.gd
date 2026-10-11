# =============================================================================
# VECTOPEN — TEMA DIFERIDO PARA PANELES OCULTOS
# RUTA: res://script_gdscript/utils/lazy_theme.gd
# ARRANQUE RÁPIDO: estilizar paneles que empiezan ocultos (ajustes, exportar…)
# costaba cientos de ms al abrir Vectopen. apply() aplica el tema YA si el nodo
# se ve, o la próxima vez que se muestre. Un cambio de tema con el panel oculto
# solo lo marca como pendiente.
# =============================================================================
class_name LazyTheme
extends RefCounted

const _META := &"_lazy_theme_pending"

## Ejecuta `fn` ahora si `node` se ve en el árbol; si no, al mostrarse.
static func apply(node: CanvasItem, fn: Callable) -> void:
	if node == null:
		return
	if not node.is_inside_tree() or node.is_visible_in_tree():
		node.remove_meta(_META)
		fn.call()
		return
	if not node.has_meta(_META):
		node.visibility_changed.connect(_on_visibility.bind(node))
	node.set_meta(_META, fn)

static func _on_visibility(node: CanvasItem) -> void:
	if not is_instance_valid(node) or not node.has_meta(_META) or not node.is_visible_in_tree():
		return
	var fn: Callable = node.get_meta(_META)
	node.remove_meta(_META)
	node.visibility_changed.disconnect(_on_visibility.bind(node))
	if fn.is_valid():
		fn.call()
