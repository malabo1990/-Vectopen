# res://scripts/layer_item.gd
class_name LayerItem
extends RefCounted

var name: String = ""
var color: Color = Color.WHITE
var visible: bool = true
var locked: bool = false

# --- PROPIEDADES DE ESTRUCTURA ---
var is_group: bool = false
var is_clipping_mask: bool = false
var child_layers: Array[LayerItem] = []
var content_data: Array = [] # Datos vectoriales/píxeles si no es grupo

# Referencia débil (WeakRef) para el padre para evitar fugas de memoria
var _parent_ref: WeakRef = null

var parent_layer: LayerItem:
	get:
		return _parent_ref.get_ref() if _parent_ref else null
	set(value):
		if value == null:
			_parent_ref = null
		else:
			_parent_ref = weakref(value)

# Inicializador limpio
func _init(p_name: String = "Nueva Capa", p_is_group: bool = false) -> void:
	self.name = p_name
	self.is_group = p_is_group
