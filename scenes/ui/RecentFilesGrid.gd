extends ItemList
class_name RecentFilesGrid

## ItemList (grid de iconos) con drag & drop delegado, igual que
## RecentFilesTree: reenvía _can_drop_data / _drop_data al handler
## (FileFlowLayout) usando el prefijo de método indicado ("_grid").

var drag_handler: Node
var method_prefix: String = "_grid"

## Arrastrar DESDE la vista de iconos (faltaba: no se podía arrastrar nada).
func _get_drag_data(at_position: Vector2) -> Variant:
	if drag_handler:
		var method := method_prefix + "_drag"
		if drag_handler.has_method(method):
			return drag_handler.call(method, at_position)
	return null

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if drag_handler:
		var method := method_prefix + "_can_drop"
		if drag_handler.has_method(method):
			return drag_handler.call(method, at_position, data)
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if drag_handler:
		var method := method_prefix + "_drop"
		if drag_handler.has_method(method):
			drag_handler.call(method, at_position, data)
