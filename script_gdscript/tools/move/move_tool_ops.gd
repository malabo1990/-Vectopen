# =============================================================================
# RUTA: res://script_gdscript/tools/move/move_tool_ops.gd
# Operaciones sobre la selección: portapapeles, duplicar, borrar, agrupar,
# marquee, Alt+arrastre…
# Parte de la herramienta Mover (MoveTool), dividida por capas de herencia:
#   move_tool_core → transform → ops → threading → keyboard → 3d → draw → MoveTool
# El código se movió TAL CUAL desde MoveTool.gd (sin cambios de comportamiento).
# =============================================================================
extends "res://script_gdscript/tools/move/move_tool_transform.gd"


func select_all() -> void:
	_refresh_artboard()
	if not target_artboard:
		return
	selected_shapes.clear()
	var dl: Node = target_artboard.get_node_or_null("VectorDrawingLayer")
	if dl:
		for v_node in dl.get_children():
			if v_node is Node2D:
				selected_shapes.append(v_node)
	for node in target_artboard.get_children():
		if not (node is Node2D) or node.name in ["ArtboardTitle", "VectorDrawingLayer"]:
			continue
		selected_shapes.append(node)
	_update_macro_rect()
	_emit_selection_changed()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func delete_selected() -> void:
	if selected_shapes.is_empty():
		if SelectionManager and SelectionManager.has_method("get_selected"):
			var sel: Array = SelectionManager.get_selected()
			for s in sel:
				if is_instance_valid(s) and s is Node2D and not selected_shapes.has(s):
					selected_shapes.append(s)
	if selected_shapes.is_empty():
		return
	var nodes: Array = selected_shapes.duplicate()
	var parents: Array = []
	var indices: Array = []
	for n in nodes:
		if is_instance_valid(n):
			parents.append(n.get_parent())
			indices.append(n.get_index())
		else:
			parents.append(null)
			indices.append(-1)

	HistoryManager.register_action("Eliminar selección")
	HistoryManager.add_do(_do_remove_nodes.bind(nodes))
	HistoryManager.add_undo(_do_restore_nodes.bind(nodes, parents, indices))
	HistoryManager.commit()
	_do_remove_nodes(nodes)

func _do_restore_nodes(nodes: Array, parents: Array, indices: Array) -> void:
	for i in range(nodes.size()):
		var n = nodes[i]
		var p = parents[i]
		if is_instance_valid(n) and is_instance_valid(p) and not n.is_inside_tree():
			p.add_child(n)
			p.move_child(n, mini(indices[i], p.get_child_count() - 1))
	if SelectionManager and SelectionManager.has_method("set_selection"):
		SelectionManager.set_selection(nodes)
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func copy_selected() -> void:
	if selected_shapes.is_empty() or not SessionManager:
		return
	var clones: Array = []
	for s in selected_shapes:
		if is_instance_valid(s):
			# Los clones del portapapeles no entran en ningún árbol todavía —
			# el nombre no necesita ser único aquí, solo cuando de verdad se
			# inserten (paste_clipboard, contra target_artboard).
			clones.append(s.duplicate(DUPLICATE_SIGNALS | DUPLICATE_GROUPS | DUPLICATE_SCRIPTS))
	SessionManager.session.clipboard_shapes = clones

func cut_selected() -> void:
	copy_selected()
	delete_selected()

func paste_clipboard() -> void:
	if not SessionManager or not target_artboard:
		return
	var clipboard: Array = SessionManager.session.clipboard_shapes
	if clipboard.is_empty():
		return

	var new_nodes: Array = []
	for original in clipboard:
		if is_instance_valid(original):
			var clone: Node2D = original.duplicate(DUPLICATE_SIGNALS | DUPLICATE_GROUPS | DUPLICATE_SCRIPTS)
			clone.name = _unique_sibling_name(original.name, target_artboard)
			clone.position = original.position + Vector2(20, 20)
			new_nodes.append(clone)
	if new_nodes.is_empty():
		return

	_commit_add_nodes("Pegar", new_nodes)

## Node.duplicate() ya conserva el `.name` original (verificado con un print
## de depuración) — el problema real aparece después, en add_child(): cuando
## el nombre del clon COLISIONA con un hermano existente, la resolución
## automática de Godot para un nombre "heredado" de duplicate() no cae en el
## sufijo esperado ("TextTitle_Container_2") sino en un nombre anónimo tipo
## "@Node2D@599" — encontrado el 19/08/2026 verificando Ctrl+D en vivo varias
## veces. Se evita calculando aquí un nombre único ANTES de add_child(), sin
## depender de cómo Godot resuelva la colisión internamente.
## IMPORTANTE: `insert_parent` debe ser el padre donde el clon se va a
## insertar DE VERDAD (normalmente `target_artboard`), NO `original.get_parent()`
## a ciegas — si `original` es a su vez un clon todavía fuera de árbol (como
## los del portapapeles en paste_clipboard), `original.get_parent()` es null
## y la comprobación de unicidad no serviría de nada.
func _duplicate_named(original: Node2D, insert_parent: Node) -> Node2D:
	var clone: Node2D = original.duplicate(DUPLICATE_SIGNALS | DUPLICATE_GROUPS | DUPLICATE_SCRIPTS)
	clone.name = _unique_sibling_name(original.name, insert_parent)
	return clone

func _unique_sibling_name(base_name: String, parent: Node) -> String:
	# Nombre limpio "Base 2", "Base 3"… (estilo profesional), quitando un sufijo previo.
	var b := base_name
	var re := RegEx.new()
	re.compile("^(.*?)[ _]\\d+$")
	var m := re.search(b)
	if m:
		b = m.get_string(1)
	return NameUtils.unique_child_name(parent, b)

func duplicate_selected() -> void:
	if selected_shapes.is_empty() or not target_artboard:
		return
	var new_nodes: Array = []
	for s in selected_shapes:
		if is_instance_valid(s):
			var clone = _duplicate_named(s, target_artboard)
			clone.position = s.position + Vector2(20, 20)
			new_nodes.append(clone)
	if new_nodes.is_empty():
		return

	_commit_add_nodes("Duplicar selección", new_nodes)

## `gm`: posición actual del mouse (la misma que ya tenía _on_motion en este
## frame) — necesaria para re-anclar transform_initial_mouse a ESTE instante,
## ver el comentario grande más abajo.
## Estilo Figma/Affinity (pedido explícito del usuario tras probar la versión
## anterior en vivo: "se nota salta rápido... quiero igual a Affinity y
## Figma"). La versión anterior RESTAURABA los originales a su posición
## inicial, clonaba, y REASIGNABA selected_shapes/transform_initial_states/
## transform_initial_mouse a los clones para que el resto de _on_motion
## siguiera moviendo "otra cosa" — ese swap de identidad a mitad de gesto
## (con su propio _update_macro_rect/_emit_selection_changed) era la propia
## causa del salto, no solo un cálculo de posición mal ordenado.
##
## Figma/Affinity nunca sueltan el nodo que se está arrastrando: dejan una
## copia QUIETA en el punto de partida y el nodo bajo el cursor sigue siendo
## el mismo de siempre. Aquí replicamos eso — ni selected_shapes, ni
## transform_initial_states, ni transform_initial_mouse se tocan; el resto
## de _on_motion en este mismo frame (y en todos los siguientes) sigue
## moviendo `s` exactamente como si esto no hubiera pasado. El único nodo
## nuevo es el clon, que nace inmóvil en el snapshot inicial y no vuelve a
## participar en este gesto de arrastre.
## Alt+drag: leave a copy behind at the start position while the dragged
## shapes keep moving. The copy goes into the ORIGINAL's parent (same
## artboard / group), just below it. It used to require `target_artboard`,
## which is still null right after a session starts, so the first Alt+drag
## did nothing, and copies jumped to whichever artboard was active.
func _perform_alt_drag_duplication(_gm: Vector2) -> void:
	if selected_shapes.is_empty():
		return
	_alt_drag_duplicated = true

	var placements: Array = []   # [clone, parent, index]
	for s in selected_shapes:
		if not is_instance_valid(s) or not transform_initial_states.has(s):
			continue
		var parent: Node = s.get_parent()
		if parent == null:
			continue
		var clone: Node2D = _duplicate_named(s, parent)
		var idx: int = s.get_index()
		parent.add_child(clone)
		parent.move_child(clone, idx)
		_restore_transform(clone, transform_initial_states[s])
		placements.append([clone, parent, idx])

	if placements.is_empty():
		return

	var clones: Array = placements.map(func(p): return p[0])
	HistoryManager.register_action("Duplicar por arrastre (Alt)")
	HistoryManager.add_do(_do_place_nodes.bind(placements))
	HistoryManager.add_undo(_do_remove_nodes.bind(clones))
	HistoryManager.commit()

## Re-inserts nodes at their recorded parent/index (redo of Alt+drag).
func _do_place_nodes(placements: Array) -> void:
	for p in placements:
		var n: Node = p[0]
		var parent: Node = p[1]
		if is_instance_valid(n) and is_instance_valid(parent) and not n.is_inside_tree():
			parent.add_child(n)
			parent.move_child(n, clampi(int(p[2]), 0, parent.get_child_count() - 1))

func nudge_selected(direction: Vector2, big_step: bool = false) -> void:
	if selected_shapes.is_empty():
		return
	var delta: Vector2 = direction * (NUDGE_STEP_SHIFT if big_step else NUDGE_STEP)
	var nodes: Array = selected_shapes.duplicate()

	HistoryManager.register_action("Mover con teclado")
	HistoryManager.add_do(_do_nudge.bind(nodes, delta))
	HistoryManager.add_undo(_do_nudge.bind(nodes, -delta))
	HistoryManager.commit()
	_do_nudge(nodes, delta)

func _do_nudge(nodes: Array, delta: Vector2) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.global_position += delta
			_sync_doc_position_from_native(n)
	_update_bounding_box()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _force_text_loss_focus() -> void:
	var focus_owner = canvas.get_viewport().gui_get_focus_owner()
	if focus_owner and (focus_owner is TextEdit or focus_owner is LineEdit):
		focus_owner.release_focus()

func _apply_marquee() -> void:
	var mr: Rect2 = Rect2(marquee_start, marquee_end - marquee_start).abs()

	# Alt resta del marquee (quita de la selección lo que toca el rectángulo);
	# sin Alt, suma (comportamiento normal / con Shift, ver _on_press).
	var subtract: bool = Input.is_key_pressed(KEY_ALT)

	var mgr := ArtboardManager.find(get_tree()) if is_inside_tree() else null
	var artboards: Array = mgr.all_artboards() if mgr else ([target_artboard] if target_artboard else [])

	var candidates: Array[Node2D] = []
	for ab in artboards:
		if not is_instance_valid(ab):
			continue
		var dl: Node = ab.get_node_or_null("VectorDrawingLayer")
		if dl:
			for v_node in dl.get_children():
				if v_node is Node2D and not (String(v_node.name) in ["ArtboardTitle", "Contorno_Stroke"]):
					candidates.append(v_node)
		for node in ab.get_children():
			if node is Node2D and not (String(node.name) in ["ArtboardTitle", "VectorDrawingLayer", "Contorno_Stroke"]):
				candidates.append(node)

	var container: Node = canvas.get_node_or_null("ArtboardsContainer") if is_instance_valid(canvas) else null
	if container:
		for n in container.get_children():
			if n is Node2D and not (n is ArtboardEditor) and not (String(n.name) in ["ArtboardTitle", "Contorno_Stroke"]):
				candidates.append(n)

	for node in candidates:
		if is_instance_valid(node) and mr.intersects(_global_rect(node)):
			if subtract:
				selected_shapes.erase(node)
			elif not selected_shapes.has(node):
				selected_shapes.append(node)

	_update_macro_rect()
	_emit_selection_changed()   # un solo cambio para todo el marquee
	canvas.queue_redraw()
