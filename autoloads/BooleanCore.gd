# =============================================================================
# VECTOPEN — BOOLEAN CORE (AUTOLOAD / SINGLETON)
# RUTA: res://autoloads/BooleanCore.gd
# Capa central entre la selección del canvas, herramientas, UI, atajos y MCP
# para la gestión de Booleanos No Destructivos, Shape Builder, Flatten y Release.
# =============================================================================
extends Node

signal boolean_applied(boolean_node: CanvasItem, operation: String)
signal boolean_flattened(old_node: CanvasItem, new_path: VectorPath)
signal boolean_released(released_shapes: Array[CanvasItem])
signal operation_changed(boolean_node: CanvasItem, new_op: String)

const VectorBooleanScript = preload("res://script_gdscript/shapes/VectorBoolean.gd")
const VectorPathScript = preload("res://script_gdscript/shapes/VectorPath.gd")
const _GeomCore = preload("res://script_gdscript/shapes/VectorGeometryCore.gd")

const OP_UNION := "union"
const OP_SUBTRACT := "subtract"
const OP_INTERSECT := "intersect"
const OP_EXCLUDE := "exclude"

func is_boolean(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	if node is VectorBooleanScript:
		return true
	if node is Object and node.get_script() == VectorBooleanScript:
		return true
	if node is Node and node.has_method("get_evaluated_geometry") and "operation" in node:
		return true
	return false

func get_boolean_operation(node: Variant) -> String:
	if is_boolean(node):
		return str(node.get("operation"))
	return ""

func _resolve_boolean_target(target: Node = null) -> VectorShape:
	var cand: Node = target
	if not is_instance_valid(cand):
		var sel := get_selection()
		if not sel.is_empty():
			cand = sel[0]
	if not is_instance_valid(cand):
		return null
	if is_boolean(cand):
		return cand as VectorShape
	if is_instance_valid(cand.get_parent()) and is_boolean(cand.get_parent()):
		return cand.get_parent() as VectorShape
	return null

func get_selection() -> Array[CanvasItem]:
	var sm = get_node_or_null("/root/SelectionManager")
	if is_instance_valid(sm) and sm.has_method("get_selected"):
		var s: Array = sm.get_selected()
		var res: Array[CanvasItem] = []
		for item in s:
			if is_instance_valid(item) and item is CanvasItem:
				res.append(item)
		if not res.is_empty():
			return res

	var ic = get_node_or_null("/root/InspectorCore")
	if is_instance_valid(ic) and ic.has_method("selection"):
		var s: Array = ic.selection()
		var res: Array[CanvasItem] = []
		for item in s:
			if is_instance_valid(item) and item is CanvasItem:
				res.append(item)
		if not res.is_empty():
			return res

	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas")
	if is_instance_valid(canvas) and "current_tool" in canvas and canvas.current_tool and "selected_shapes" in canvas.current_tool:
		var res: Array[CanvasItem] = []
		for item in canvas.current_tool.selected_shapes:
			if is_instance_valid(item) and item is CanvasItem:
				res.append(item)
		return res
	return []

func can_perform_boolean(shapes: Array = []) -> bool:
	var list: Array = shapes if not shapes.is_empty() else get_selection()
	if list.size() >= 2:
		return true
	if list.size() == 1 and (is_boolean(list[0]) or _resolve_boolean_target(list[0]) != null):
		return true
	return false

func apply_operation(op: String, shapes: Array = []) -> CanvasItem:
	var clean_op := op.to_lower().strip_edges()
	if clean_op == "shape_builder":
		activate_shape_builder()
		return null
	if clean_op == "flatten":
		var target: Node = shapes[0] if not shapes.is_empty() else null
		return flatten_boolean(target, shapes)
	if clean_op == "release":
		var target: Node = shapes[0] if not shapes.is_empty() else null
		release_boolean(target, shapes)
		return null

	var sel: Array[CanvasItem] = []
	if shapes.is_empty():
		sel = get_selection()
	else:
		for s in shapes:
			if is_instance_valid(s) and s is CanvasItem:
				sel.append(s)

	if sel.is_empty():
		return null

	# Caso 1: Si hay 1 solo nodo y es VectorBoolean (o hijo de booleano), cambiar su operación viva
	var single_vb := _resolve_boolean_target(sel[0] if sel.size() == 1 else null)
	if sel.size() == 1 and single_vb != null:
		set_boolean_operation(single_vb, clean_op)
		return single_vb

	# Caso 2: Se necesitan al menos 2 figuras para crear un nuevo booleano
	if sel.size() < 2:
		return null

	var first_shape := sel[0]
	var parent: Node = first_shape.get_parent()
	if not is_instance_valid(parent):
		return null

	var insert_idx: int = first_shape.get_index()

	# Instanciar el nodo VectorBoolean
	var vb: VectorShape = VectorBooleanScript.new() as VectorShape
	vb.name = "Boolean_" + clean_op.capitalize()
	vb.set("operation", clean_op)

	# Heredar estilo visual de la figura primaria
	if "fill_color" in first_shape:
		vb.fill_color = first_shape.fill_color
	if "stroke_color" in first_shape:
		vb.stroke_color = first_shape.stroke_color
	if "stroke_width" in first_shape:
		vb.stroke_width = first_shape.stroke_width

	var orig_children: Array[CanvasItem] = []
	var orig_indices: Array[int] = []
	var orig_visibilities: Array[bool] = []

	for s in sel:
		if is_instance_valid(s) and s.get_parent() == parent:
			orig_children.append(s)
			orig_indices.append(s.get_index())
			orig_visibilities.append(s.visible)

	var hm = get_node_or_null("/root/HistoryManager")
	if is_instance_valid(hm) and hm.has_method("register_action"):
		hm.register_action("Boolean " + clean_op.capitalize())
		hm.add_do(Callable(self, "_do_apply_boolean").bind(vb, parent, insert_idx, orig_children))
		hm.add_undo(Callable(self, "_undo_apply_boolean").bind(vb, parent, orig_children, orig_indices, orig_visibilities))
		hm.commit()

	_do_apply_boolean(vb, parent, insert_idx, orig_children)
	boolean_applied.emit(vb, clean_op)
	return vb

func set_boolean_operation(vb: CanvasItem, new_op: String) -> void:
	if not is_boolean(vb):
		return
	var old_op: String = str(vb.get("operation"))
	if old_op == new_op:
		return

	var hm = get_node_or_null("/root/HistoryManager")
	if is_instance_valid(hm) and hm.has_method("register_action"):
		hm.register_action("Cambiar operación booleana")
		hm.add_do(Callable(self, "_do_set_operation").bind(vb, new_op))
		hm.add_undo(Callable(self, "_do_set_operation").bind(vb, old_op))
		hm.commit()

	_do_set_operation(vb, new_op)

func _do_set_operation(vb: CanvasItem, op: String) -> void:
	if is_instance_valid(vb):
		vb.set("operation", op)
		if vb.has_method("invalidate_cache"):
			vb.call("invalidate_cache")
		operation_changed.emit(vb, op)

func flatten_boolean(target: Node = null, shapes: Array = []) -> VectorPath:
	var vb: VectorShape = _resolve_boolean_target(target)
	var sel: Array[CanvasItem] = []
	if not shapes.is_empty():
		for s in shapes:
			if is_instance_valid(s) and s is CanvasItem:
				sel.append(s)
	else:
		sel = get_selection()

	# Caso especial Figma/Affinity: Si no es un booleano directo pero hay 2+ figuras seleccionadas,
	# fusionarlas con union y aplanar directamente a un VectorPath.
	if vb == null and sel.size() >= 2:
		var first_s := sel[0]
		var sel_parent := first_s.get_parent()
		if is_instance_valid(sel_parent):
			var target_inv: Transform2D = (sel_parent as CanvasItem).global_transform.affine_inverse() if (sel_parent is CanvasItem) else Transform2D.IDENTITY
			var sel_polys := _GeomCore.compute_multi_boolean("union", sel, target_inv)
			if not sel_polys.is_empty():
				var sel_new_path: VectorPath = _create_path_from_polygons(sel_polys, first_s)
				var sel_insert_idx := first_s.get_index()
				var orig_indices: Array[int] = []
				for s in sel:
					orig_indices.append(s.get_index())

				var hm_inst = get_node_or_null("/root/HistoryManager")
				if is_instance_valid(hm_inst) and hm_inst.has_method("register_action"):
					hm_inst.register_action("Aplanar Selección a Curvas")
					hm_inst.add_do(Callable(self, "_do_flatten_selection").bind(sel, sel_new_path, sel_parent, sel_insert_idx))
					hm_inst.add_undo(Callable(self, "_undo_flatten_selection").bind(sel, sel_new_path, sel_parent, orig_indices))
					hm_inst.commit()

				_do_flatten_selection(sel, sel_new_path, sel_parent, sel_insert_idx)
				boolean_flattened.emit(first_s, sel_new_path)
				return sel_new_path

	if not is_boolean(vb):
		return null

	var parent := vb.get_parent()
	if not is_instance_valid(parent):
		return null

	var polys: Array[PackedVector2Array] = []
	if vb.has_method("get_evaluated_geometry"):
		polys = vb.call("get_evaluated_geometry")
	if polys.is_empty():
		return null

	var insert_idx := vb.get_index()
	var new_path: VectorPath = _create_path_from_polygons(polys, vb)
	new_path.transform = vb.transform

	var hm = get_node_or_null("/root/HistoryManager")
	if is_instance_valid(hm) and hm.has_method("register_action"):
		hm.register_action("Aplanar Booleano a Curvas")
		hm.add_do(Callable(self, "_do_flatten_boolean").bind(vb, new_path, parent, insert_idx))
		hm.add_undo(Callable(self, "_undo_flatten_boolean").bind(vb, new_path, parent, insert_idx))
		hm.commit()

	_do_flatten_boolean(vb, new_path, parent, insert_idx)
	boolean_flattened.emit(vb, new_path)
	return new_path

func _create_path_from_polygons(polys: Array[PackedVector2Array], style_source: CanvasItem) -> VectorPath:
	var new_path: VectorPath = VectorPathScript.new() as VectorPath
	new_path.name = "Flattened_Path"
	if style_source:
		new_path.name = style_source.name.replace("Boolean_", "Flattened_")
		if "fill_color" in style_source:
			new_path.fill_color = style_source.fill_color
		if "stroke_color" in style_source:
			new_path.stroke_color = style_source.stroke_color
		if "stroke_width" in style_source:
			new_path.stroke_width = style_source.stroke_width
		if "effects" in style_source:
			new_path.effects = style_source.effects.duplicate(true)

	new_path.closed = true
	var curve := Curve2D.new()

	var main_poly := polys[0]
	for p in polys:
		if p.size() > main_poly.size():
			main_poly = p

	for i in range(main_poly.size()):
		var pt: Vector2 = main_poly[i]
		if i == main_poly.size() - 1 and pt.distance_to(main_poly[0]) < 0.1:
			continue
		curve.add_point(pt)

	new_path.curve = curve
	new_path.set_meta("evaluated_geometry", polys)
	return new_path

func release_boolean(target: Node = null, shapes: Array = []) -> Array[CanvasItem]:
	var cand: Node = target
	if not is_instance_valid(cand) and not shapes.is_empty():
		cand = shapes[0]
	var vb: VectorShape = _resolve_boolean_target(cand)
	if not is_boolean(vb):
		return []

	var parent := vb.get_parent()
	if not is_instance_valid(parent):
		return []

	var insert_idx := vb.get_index()
	var children: Array[CanvasItem] = []
	var orig_vis: Array[bool] = []
	for child in vb.get_children():
		if is_instance_valid(child) and child is CanvasItem:
			children.append(child)
			orig_vis.append(child.visible)

	if children.is_empty():
		return []

	var hm = get_node_or_null("/root/HistoryManager")
	if is_instance_valid(hm) and hm.has_method("register_action"):
		hm.register_action("Liberar Booleano")
		hm.add_do(Callable(self, "_do_release_boolean").bind(vb, parent, children))
		hm.add_undo(Callable(self, "_undo_release_boolean").bind(vb, parent, insert_idx, children, orig_vis))
		hm.commit()

	_do_release_boolean(vb, parent, children)
	boolean_released.emit(children)
	return children

func activate_shape_builder() -> bool:
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas")
	if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
		canvas.switch_tool("shape_builder")
		return true
	return false

# ── MÉTODOS DE APLICACIÓN / UNDO / REDO ──

func _do_apply_boolean(vb: CanvasItem, parent: Node, insert_idx: int, children: Array[CanvasItem]) -> void:
	if not is_instance_valid(parent):
		return
	if vb.get_parent() != parent:
		parent.add_child(vb)
		parent.move_child(vb, insert_idx)
	for c in children:
		if is_instance_valid(c):
			if c.get_parent() != vb:
				c.reparent(vb, true)
			c.visible = false
	if vb.has_method("invalidate_cache"):
		vb.call("invalidate_cache")
	_select_shapes([vb])

func _undo_apply_boolean(vb: CanvasItem, parent: Node, children: Array[CanvasItem], orig_indices: Array[int], orig_vis: Array[bool]) -> void:
	if not is_instance_valid(parent):
		return
	for i in range(children.size()):
		var c = children[i]
		if is_instance_valid(c):
			if c.get_parent() != parent:
				c.reparent(parent, true)
			if i < orig_indices.size() and orig_indices[i] < parent.get_child_count():
				parent.move_child(c, orig_indices[i])
			if i < orig_vis.size():
				c.visible = orig_vis[i]
			else:
				c.visible = true
	if is_instance_valid(vb) and vb.get_parent() == parent:
		parent.remove_child(vb)
	_select_shapes(children)

func _do_flatten_boolean(vb: CanvasItem, new_path: VectorPath, parent: Node, insert_idx: int) -> void:
	if not is_instance_valid(parent):
		return
	if is_instance_valid(vb) and vb.get_parent() == parent:
		parent.remove_child(vb)
	if is_instance_valid(new_path):
		if new_path.get_parent() != parent:
			parent.add_child(new_path)
			parent.move_child(new_path, insert_idx)
		_select_shapes([new_path])

func _undo_flatten_boolean(vb: CanvasItem, new_path: VectorPath, parent: Node, insert_idx: int) -> void:
	if not is_instance_valid(parent):
		return
	if is_instance_valid(new_path) and new_path.get_parent() == parent:
		parent.remove_child(new_path)
	if is_instance_valid(vb):
		if vb.get_parent() != parent:
			parent.add_child(vb)
			parent.move_child(vb, insert_idx)
		_select_shapes([vb])

func _do_flatten_selection(sources: Array[CanvasItem], new_path: VectorPath, parent: Node, insert_idx: int) -> void:
	if not is_instance_valid(parent):
		return
	for s in sources:
		if is_instance_valid(s) and s.get_parent() == parent:
			s.visible = false
	if is_instance_valid(new_path):
		if new_path.get_parent() != parent:
			parent.add_child(new_path)
			parent.move_child(new_path, insert_idx)
		_select_shapes([new_path])

func _undo_flatten_selection(sources: Array[CanvasItem], new_path: VectorPath, parent: Node, orig_indices: Array[int]) -> void:
	if not is_instance_valid(parent):
		return
	if is_instance_valid(new_path) and new_path.get_parent() == parent:
		parent.remove_child(new_path)
	for i in range(sources.size()):
		var s = sources[i]
		if is_instance_valid(s):
			s.visible = true
			if i < orig_indices.size() and orig_indices[i] < parent.get_child_count():
				parent.move_child(s, orig_indices[i])
	_select_shapes(sources)

func _do_release_boolean(vb: CanvasItem, parent: Node, children: Array[CanvasItem]) -> void:
	if not is_instance_valid(parent):
		return
	for c in children:
		if is_instance_valid(c):
			if c.get_parent() != parent:
				c.reparent(parent, true)
			c.visible = true
	if is_instance_valid(vb) and vb.get_parent() == parent:
		parent.remove_child(vb)
	_select_shapes(children)

func _undo_release_boolean(vb: CanvasItem, parent: Node, insert_idx: int, children: Array[CanvasItem], orig_vis: Array[bool]) -> void:
	if not is_instance_valid(parent):
		return
	if is_instance_valid(vb):
		if vb.get_parent() != parent:
			parent.add_child(vb)
			parent.move_child(vb, insert_idx)
		for i in range(children.size()):
			var c = children[i]
			if is_instance_valid(c):
				if c.get_parent() != vb:
					c.reparent(vb, true)
				if i < orig_vis.size():
					c.visible = orig_vis[i]
				else:
					c.visible = false
		if vb.has_method("invalidate_cache"):
			vb.call("invalidate_cache")
		_select_shapes([vb])

func _select_shapes(shapes: Array) -> void:
	var sm = get_node_or_null("/root/SelectionManager")
	if is_instance_valid(sm) and sm.has_method("set_selection"):
		sm.set_selection(shapes)
	# Sin emisión manual de GlobalEvents: SelectionManager ya re-emite
	# `selection_changed` en cada cambio (antes se emitía dos veces:
	# una con la lista sin filtrar y otra con el snapshot del Manager).
	var ic = get_node_or_null("/root/InspectorCore")
	if is_instance_valid(ic) and ic.has_method("_sync_selection"):
		ic._sync_selection()
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas")
	if is_instance_valid(canvas):
		if "current_tool" in canvas and canvas.current_tool and "selected_shapes" in canvas.current_tool:
			canvas.current_tool.selected_shapes.assign(shapes)
		canvas.queue_redraw()
