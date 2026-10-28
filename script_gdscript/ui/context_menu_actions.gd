# =============================================================================
# VECTOPEN — CONTEXT MENU ACTIONS
# RUTA: res://script_gdscript/ui/context_menu_actions.gd
# Single dispatcher for the actions offered by the canvas context menus
# (Modern and Professional). Z-order and flip changes are registered in
# HistoryManager so they can be undone.
# =============================================================================
class_name ContextMenuActions
extends RefCounted

## Actions that only make sense with at least one selected shape.
const NEEDS_SELECTION: Array[String] = [
	"copy", "cut", "duplicate", "delete",
	"bring_to_front", "bring_forward", "send_backward", "send_to_back",
	"flip_h", "flip_v", "rotate_cw", "rotate_ccw", "group", "ungroup", "ungroup_all", "rename",
	"toggle_visibility", "toggle_lock", "invert_fill_stroke",
	"align_left", "align_center_h", "align_right", "align_top", "align_middle", "align_bottom",
	"align_text_left", "align_text_center", "align_text_right",
	"boolean_flatten", "boolean_release",
]
## Actions that need two or more selected shapes.
const NEEDS_MULTI: Array[String] = [
	"dist_h", "dist_v", "distribute_horizontal", "distribute_vertical",
	"boolean_union", "boolean_subtract", "boolean_intersect", "boolean_exclude", "shape_builder"
]

static func execute(id: String, host: Node) -> void:
	var mt = move_tool(host)
	var ic := host.get_node_or_null("/root/InspectorCore")
	match id:
		"copy":
			if mt and mt.has_method("copy_selected"): mt.copy_selected()
		"cut":
			if mt and mt.has_method("cut_selected"): mt.cut_selected()
		"paste":
			if mt and mt.has_method("paste_clipboard"): mt.paste_clipboard()
		"duplicate":
			if mt and mt.has_method("duplicate_selected"): mt.duplicate_selected()
		"delete":
			if mt and mt.has_method("delete_selected"): mt.delete_selected()
		"bring_to_front", "bring_forward", "send_backward", "send_to_back":
			arrange(host, id)
		"flip_h":
			flip(host, true)
		"flip_v":
			flip(host, false)
		"rotate_cw":
			rotate_by(host, 90.0)
		"rotate_ccw":
			rotate_by(host, -90.0)
		# Antes llamaban a _on_btn_group_selected / _on_btn_ungroup, que NO
		# existen: Agrupar y Desagrupar del menú contextual no hacían nada.
		"group":
			var ls = layers_system(host)
			if ls and ls.has_method("_agrupar_seleccion"):
				ls._agrupar_seleccion()
		"ungroup", "ungroup_all":
			var ls = layers_system(host)
			if ls and ls.has_method("_desagrupar_seleccion"):
				ls._desagrupar_seleccion()
		"rename":
			rename_active_item(host)
		"toggle_visibility":
			if ic:
				var p: Dictionary = ic.current_props()
				var cur_v: bool = bool(p["visible"]["value"]) if p.has("visible") else true
				ic.apply("visible", not cur_v)
		"toggle_lock":
			# Selected shapes are unlocked by definition (locked ones can't be
			# selected), so this locks; unlocking happens from the layers panel.
			set_locked(host, selection(host), true)
		"invert_fill_stroke":
			if ic:
				var p: Dictionary = ic.current_props()
				var f_col: Color = p["fill_color"]["value"] if p.has("fill_color") and not p["fill_color"].get("mixed", false) else Color.WHITE
				var s_col: Color = p["stroke_color"]["value"] if p.has("stroke_color") and not p["stroke_color"].get("mixed", false) else Color.BLACK
				if ic.has_method("apply_multi"):
					ic.apply_multi({"fill_color": s_col, "stroke_color": f_col}, "Invertir relleno / trazo")
				else:
					ic.apply("fill_color", s_col)
					ic.apply("stroke_color", f_col)
		"align_text_left":
			if ic: ic.apply("text_align", "left")
		"align_text_center":
			if ic: ic.apply("text_align", "center")
		"align_text_right":
			if ic: ic.apply("text_align", "right")
		"align_left":
			if ic: ic.align("left")
		"align_center_h":
			if ic: ic.align("center_h")
		"align_right":
			if ic: ic.align("right")
		"align_top":
			if ic: ic.align("top")
		"align_middle":
			if ic: ic.align("middle")
		"align_bottom":
			if ic: ic.align("bottom")
		"dist_h", "distribute_horizontal":
			if ic: ic.distribute("horizontal")
		"dist_v", "distribute_vertical":
			if ic: ic.distribute("vertical")
		"boolean_union", "boolean_subtract", "boolean_intersect", "boolean_exclude", "shape_builder", "boolean_flatten", "boolean_release":
			var bc = host.get_node_or_null("/root/BooleanCore")
			if bc and bc.has_method("apply_operation"):
				var op: String = id.replace("boolean_", "")
				bc.apply_operation(op)
		"undo":
			var hm := host.get_node_or_null("/root/HistoryManager")
			if hm: hm.undo()
		"redo":
			var hm := host.get_node_or_null("/root/HistoryManager")
			if hm: hm.redo()
		"toggle_theme":
			var tm := host.get_node_or_null("/root/ThemeManager")
			if tm and tm.has_method("toggle"):
				tm.toggle()

static func selection(host: Node) -> Array:
	# SelectionManager is the single source of truth for the live selection
	var sm := host.get_node_or_null("/root/SelectionManager") if host and host.is_inside_tree() else null
	if sm and sm.has_method("get_selected"):
		var sel: Array = sm.get_selected().filter(func(n): return is_instance_valid(n))
		if not sel.is_empty():
			return sel
	var mt = move_tool(host)
	if mt and "selected_shapes" in mt:
		var out: Array = []
		for n in mt.selected_shapes:
			if is_instance_valid(n):
				out.append(n)
		return out
	return []

static func is_enabled(id: String, host: Node) -> bool:
	var count := selection(host).size()
	if NEEDS_MULTI.has(id):
		return count >= 2
	if NEEDS_SELECTION.has(id):
		return count >= 1
	return true

## "none" | "multi" | "text" | "image" | "group" | "shape"
static func selected_kind(host: Node) -> String:
	var sel := selection(host)
	if sel.is_empty():
		return "none"
	if sel.size() > 1:
		return "multi"
	var shape: Node = sel[0]
	if shape.has_meta("shape_type"):
		var st := String(shape.get_meta("shape_type"))
		if st.begins_with("text"):
			return "text"
		if st == "image":
			return "image"
		if st == "group":
			return "group"
	if shape.has_meta("is_group") or String(shape.name).begins_with("Group") or shape is CanvasGroup:
		return "group"
	if shape is Sprite2D or shape.has_meta("image_path"):
		return "image"
	return "shape"

## Z-order change for every selected shape, as one undoable step.
static func arrange(host: Node, id: String) -> void:
	var sel := selection(host)
	if sel.is_empty():
		return
	var before: Array = []
	var after: Array = []
	# Moving up processes top-most first so siblings don't leapfrog each other.
	var ordered := sel.duplicate()
	ordered.sort_custom(func(a, b): return a.get_index() > b.get_index())
	if id == "send_backward" or id == "send_to_back":
		ordered.reverse()
	for n in ordered:
		var p: Node = n.get_parent()
		if p == null:
			continue
		var last: int = p.get_child_count() - 1
		var target: int = n.get_index()
		match id:
			"bring_to_front": target = last
			"bring_forward": target = mini(n.get_index() + 1, last)
			"send_backward": target = maxi(n.get_index() - 1, 0)
			"send_to_back": target = 0
		if target == n.get_index():
			continue
		before.append([n, p, n.get_index()])
		after.append([n, p, target])
	if after.is_empty():
		return
	var names := {
		"bring_to_front": "Traer al frente", "bring_forward": "Avanzar",
		"send_backward": "Retroceder", "send_to_back": "Enviar al fondo",
	}
	var apply_order := func(entries: Array) -> void:
		for e in entries:
			if is_instance_valid(e[0]) and is_instance_valid(e[1]) and e[0].get_parent() == e[1]:
				e[1].move_child(e[0], clampi(e[2], 0, e[1].get_child_count() - 1))
		_after_change(host)
	var undo_entries := before.duplicate()
	undo_entries.reverse()
	_commit(host, String(names.get(id, "Organizar")),
		func(): apply_order.call(after),
		func(): apply_order.call(undo_entries))

## Mirrors every selected shape around its own origin, as one undoable step.
static func flip(host: Node, horizontal: bool) -> void:
	var nodes: Array = []
	for n in selection(host):
		if n is Node2D:
			nodes.append(n)
	if nodes.is_empty():
		return
	var toggle := func() -> void:
		for n in nodes:
			if is_instance_valid(n):
				if horizontal:
					n.scale.x = -n.scale.x
				else:
					n.scale.y = -n.scale.y
		_after_change(host)
	_commit(host, "Voltear horizontal" if horizontal else "Voltear vertical", toggle, toggle)

## Locks/unlocks shapes (meta "locked", honoured by SelectionManager and the
## layers panel) as one undoable step. Locked shapes leave the selection.
static func set_locked(host: Node, nodes: Array, locked: bool) -> void:
	var targets: Array = []
	for n in nodes:
		if is_instance_valid(n) and bool(n.get_meta("locked", false)) != locked:
			targets.append(n)
	if targets.is_empty():
		return
	var apply_lock := func(value: bool) -> void:
		var ls = layers_system(host)
		for n in targets:
			if not is_instance_valid(n):
				continue
			var item = null
			if ls and "_node_to_item_map" in ls:
				item = ls._node_to_item_map.get(n, null)
			if ls and ls.has_method("_set_lock"):
				ls._set_lock(item, n, value)
			else:
				n.set_meta("locked", value)
		if value:
			var sm := host.get_node_or_null("/root/SelectionManager")
			if sm and sm.has_method("clear"):
				sm.clear()
		_after_change(host)
	_commit(host, "Bloquear" if locked else "Desbloquear",
		func(): apply_lock.call(locked),
		func(): apply_lock.call(not locked))

## Rotates every selected shape by `degrees` relative to its own current angle
## (a multi-selection keeps its different rotations), as one undo step.
static func rotate_by(host: Node, degrees: float) -> void:
	var ic := host.get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	var recs: Array = []
	for s in selection(host):
		var cur = ic._read(s, "rotation")
		if cur == null:
			continue
		recs.append([s, float(cur), fposmod(float(cur) + degrees, 360.0)])
	if recs.is_empty():
		return
	var apply_rot := func(idx: int) -> void:
		for r in recs:
			if is_instance_valid(r[0]):
				ic._write(r[0], "rotation", r[idx])
		ic._post_write()
		_after_change(host)
	_commit(host, "Rotar %d°" % int(degrees), func(): apply_rot.call(2), func(): apply_rot.call(1))

static func _commit(host: Node, action_name: String, do_fn: Callable, undo_fn: Callable) -> void:
	# The project's UndoRedoManager does NOT run the action on commit (callers
	# apply the change themselves, then register it), so apply it here.
	do_fn.call()
	var hm := host.get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action(action_name)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()

static func _after_change(host: Node) -> void:
	var mt = move_tool(host)
	if mt and "canvas" in mt and mt.canvas:
		mt.canvas.queue_redraw()
	# Sin emisión manual: SelectionManager no tiene señal `selection_changed`
	# (la suya es `changed`; el puente a GlobalEvents lo hace él mismo en
	# cada cambio), así que ese bloque nunca llegaba a emitir.
	var dr := host.get_node_or_null("/root/DataRepository")
	if dr and "is_project_modified" in dr:
		dr.is_project_modified = true

static func rename_active_item(host: Node) -> void:
	var ic := host.get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	var props: Dictionary = ic.current_props()
	if not props.has("name"):
		return
	var le := LineEdit.new()
	le.text = String(props["name"]["value"])
	le.custom_minimum_size = Vector2(180, 24)
	le.size = le.custom_minimum_size
	le.top_level = true
	host.add_child(le)
	if host is CanvasItem:
		le.global_position = (host as CanvasItem).get_global_mouse_position()
	le.select_all()
	le.grab_focus()
	le.text_submitted.connect(func(t: String):
		ic.apply("name", t)
		le.queue_free()
	)
	le.focus_exited.connect(func():
		if is_instance_valid(le):
			le.queue_free()
	)

static func move_tool(host: Node):
	if host == null or not host.is_inside_tree():
		return null
	var canvas := host.get_tree().get_first_node_in_group("_vectopen_canvas")
	if canvas and canvas.has_method("get_current_tool"):
		var t = canvas.get_current_tool()
		if t and t.has_method("get_class_name") and t.get_class_name() == "MoveTool":
			return t
	return null

static func layers_system(host: Node):
	if host == null or not host.is_inside_tree():
		return null
	var tree := host.get_tree()
	var ls := tree.get_first_node_in_group("layers_system")
	if ls == null and tree.current_scene:
		ls = tree.current_scene.find_child("LayersSystem", true, false)
	return ls
