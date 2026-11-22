# =============================================================================
# RUTA: res://script_gdscript/shapes/mask_stroke.gd
# BORDE DE LA MÁSCARA DE RECORTE, ENCIMA del contenido (como Illustrator).
# Godot recorta los hijos a todo lo que dibuja la máscara —borde incluido— y
# los pinta ENCIMA: el borde de la figura-máscara no se veía nunca. Ahora un
# nodo interno hermano («_MaskStroke_<id>», justo después de la máscara)
# vuelve a dibujar ese borde por encima del contenido recortado.
#   · Sigue a la máscara en tiempo real (mover, girar, cambiar el borde).
#   · No se guarda (nodo interno) ni sale en Capas; sí al exportar a imagen.
# Lo llama nested_masks.refresh_under (tras cada paso del historial, al abrir
# y en las copias de exportación).
# =============================================================================
extends Node2D

const PREFIX := "_MaskStroke_"

var mask: Node2D = null
var _sig := 0

## ¿`m` es una máscara de recorte con borde visible?
static func wants(m: Node) -> bool:
	if not (m is CanvasItem) or int((m as CanvasItem).clip_children) == CanvasItem.CLIP_CHILDREN_DISABLED:
		return false
	if String(m.name).begins_with("_"):
		return false
	if not ("stroke_width" in m) or float(m.get("stroke_width")) <= 0.0:
		return false
	var c = m.get("stroke_color")
	return c is Color and (c as Color).a > 0.0

static func outline(m: Node) -> PackedVector2Array:
	if m is VectorPath:
		return VectorPath.closed_points((m as VectorPath).curve)
	if m.has_method("get_effect_points"):
		return m.get_effect_points()
	return PackedVector2Array()

## Pone o quita el borde de cada máscara bajo `root`.
static func refresh_under(root: Node) -> void:
	if root == null:
		return
	for m in root.find_children("*", "CanvasItem", true, false):
		if String(m.name).begins_with(PREFIX):
			var ms = m.get("mask")
			if not is_instance_valid(ms) or not wants(ms) or ms.get_parent() != m.get_parent():
				m.queue_free()
			continue
		if not wants(m) or m.get_parent() == null:
			continue
		var nm := PREFIX + str(m.get_instance_id())
		if m.get_parent().get_node_or_null(nm) == null:
			var o = load("res://script_gdscript/shapes/mask_stroke.gd").new()
			o.name = nm
			o.mask = m
			o.set_meta(&"_vectopen_internal", true)
			m.get_parent().add_child(o)
			m.get_parent().move_child(o, m.get_index() + 1)
			o.sync()

func _process(_d: float) -> void:
	if not is_instance_valid(mask) or not wants(mask) or mask.get_parent() != get_parent():
		queue_free()
		return
	sync()

## Sigue a la máscara: posición, visibilidad, capa de dibujo y borde.
func sync() -> void:
	if not is_instance_valid(mask):
		return
	transform = mask.transform
	visible = mask.visible
	visibility_layer = mask.visibility_layer
	z_index = mask.z_index
	light_mask = mask.light_mask
	if get_index() != mask.get_index() + 1 and get_parent() == mask.get_parent():
		get_parent().move_child(self, mini(mask.get_index() + 1, get_parent().get_child_count() - 1))
	var pts := outline(mask)
	var s := hash([pts, mask.get("stroke_width"), mask.get("stroke_color"), mask.modulate])
	if s != _sig:
		_sig = s
		modulate = mask.modulate
		queue_redraw()

func _draw() -> void:
	if not is_instance_valid(mask):
		return
	var pts := outline(mask)
	if pts.size() < 2:
		return
	var w := float(mask.get("stroke_width"))
	var col: Color = mask.get("stroke_color")
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		draw_line(a, b, col, w, true)
		if w > 1.5:
			draw_circle(a, w * 0.5, col)   # uniones redondas (sin huecos en las esquinas)
