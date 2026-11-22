# =============================================================================
# RUTA: res://script_gdscript/shapes/nested_masks.gd
# MÁSCARAS ANIDADAS (VAL-43). Godot no anida `clip_children`: la máscara de
# DENTRO se ignoraba. Decidido: recorte propio de la máscara interior.
#   · La máscara interior M (y todo lo suyo) deja de dibujarse en la vista
#     principal: su `visibility_layer` pasa a HIDE_BIT, que la vista no pinta.
#     Sigue en el documento: se selecciona, se edita y se guarda igual.
#   · Una copia de M (serializador) se dibuja en un SubViewport propio, donde
#     su recorte SÍ funciona; el resultado se muestra con un Sprite2D hermano
#     de M (dentro de la máscara exterior, que lo recorta).
#   · Se rehace al cambiar M (firma) y con más resolución al acercarse.
# Lo llama HistoryManager tras cada paso, al abrir y la exportación raster.
# =============================================================================
extends RefCounted

const HIDE_BIT := 1 << 19
const BAKE := "_NestedMaskBake"
const SS := 2.0          # supermuestreo de la copia (nitidez)
const MAX_TEX := 4096

static func _is_mask(n: Node) -> bool:
	return n is CanvasItem and int((n as CanvasItem).clip_children) != CanvasItem.CLIP_CHILDREN_DISABLED

static func _mask_ancestor(n: Node) -> Node:
	var p := n.get_parent()
	while p and not ("artboard_size" in p) and not (p is SubViewport):
		if _is_mask(p):
			return p
		p = p.get_parent()
	return null

static func _set_layer(n: Node, bit: int) -> void:
	if n is CanvasItem and not String(n.name).begins_with(BAKE):
		(n as CanvasItem).visibility_layer = bit
	for c in n.get_children(true):
		if not String(c.name).begins_with(BAKE):
			_set_layer(c, bit)

## Repasa todas las máscaras bajo `root` (página o copia de exportación).
## `vp` = la vista que debe ocultar los originales (por defecto la principal).
static func refresh_under(root: Node, vp: Viewport = null) -> int:
	if root == null:
		return 0
	if vp == null:
		vp = root.get_viewport()
	if vp:
		vp.canvas_cull_mask = vp.canvas_cull_mask & ~HIDE_BIT
	var n := 0
	for m in root.find_children("*", "CanvasItem", true, false):
		if String(m.name).begins_with(BAKE) or m.get_parent() is SubViewport and String(m.get_parent().name).begins_with(BAKE):
			continue
		var bake: Node = m.get_parent().get_node_or_null(BAKE + "_" + str(m.get_instance_id())) if m.get_parent() else null
		if _is_mask(m) and _mask_ancestor(m) != null:
			_bake(m, bake)
			n += 1
		elif bake:
			bake.queue_free()
			_set_layer(m, 1)
	# el borde de cada máscara, encima de su contenido recortado
	load("res://script_gdscript/shapes/mask_stroke.gd").refresh_under(root)
	return n

static func _sig(m: Node2D) -> int:
	var CS = load("res://scripts/canvas/canvas_serializer.gd")
	return hash(var_to_str([CS._serialize_element(m), m.transform]))

static func _bounds(m: Node2D) -> Rect2:
	var pts: PackedVector2Array = m.get_effect_points() if m.has_method("get_effect_points") else PackedVector2Array()
	if pts.is_empty():
		return Rect2()
	var r := Rect2(m.transform * pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(m.transform * p)
	return r

static func _bake(m: Node2D, bake: Node) -> void:
	_set_layer(m, HIDE_BIT)
	var parent := m.get_parent()
	var sig := _sig(m)
	if bake and int(bake.get_meta("sig", 0)) == sig:
		return
	var r := _bounds(m)
	if not r.has_area():
		return
	var k := minf(SS, MAX_TEX / maxf(r.size.x, r.size.y))
	if bake == null:
		bake = Sprite2D.new()
		bake.name = BAKE + "_" + str(m.get_instance_id())
		bake.set_meta(&"_vectopen_internal", true)
		bake.centered = false
		parent.add_child(bake)
	parent.move_child(bake, m.get_index() + 1)
	for c in bake.get_children(true):
		c.queue_free()
	var vp := SubViewport.new()
	vp.name = BAKE + "_vp"
	vp.transparent_bg = true
	vp.size = Vector2i((r.size * k).ceil()).max(Vector2i.ONE)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_cull_mask = 0xFFFFFFFF
	bake.add_child(vp, false, Node.INTERNAL_MODE_BACK)
	var CS = load("res://scripts/canvas/canvas_serializer.gd")
	var holder := Node2D.new()
	holder.scale = Vector2(k, k)
	holder.position = -r.position * k
	vp.add_child(holder)
	CS.instantiate_elements(holder, [CS._serialize_element(m)])
	_set_layer(holder, 1)
	bake.texture = vp.get_texture()
	bake.position = r.position
	bake.scale = Vector2(1.0 / k, 1.0 / k)
	bake.set_meta("sig", sig)
	# una vez dibujada, la copia deja de redibujarse cada fotograma
	(func() -> void:
		var tree := Engine.get_main_loop() as SceneTree
		for i in 3:
			await tree.process_frame
		if is_instance_valid(vp):
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE).call()

## Tras cada paso del historial: todas las páginas del documento.
static func on_history_step(tree: SceneTree) -> void:
	if tree == null:
		return
	(func() -> void:
		for ab in tree.get_nodes_in_group("artboards"):
			refresh_under(ab)).call_deferred()
