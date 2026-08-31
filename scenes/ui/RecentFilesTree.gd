extends Tree
class_name RecentFilesTree

## Tree con drag & drop delegado: en Godot 4 _get_drag_data / _can_drop_data /
## _drop_data son métodos virtuales (no señales), así que este script los
## reenvía al nodo "drag_handler" usando el prefijo de método indicado
## (p.ej. "_recent_drag", "_export_can_drop", "_export_drop").
## FileFlowLayout se asigna como handler y resuelve el prefijo.

var drag_handler: Node
var method_prefix: String = "_recent"

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
