# =============================================================================
# RUTA: res://script_gdscript/shapes/master_pages.gd
# PÁGINAS MAESTRAS (informe de propuestas §5, como InDesign): una página se
# marca «maestra» (cabecera, pie, número de página, fondo, logo…) y las
# páginas que la usan la muestran DEBAJO de su contenido. En esas páginas no
# se puede tocar (es una capa interna «_MasterLayer»): se edita en la maestra
# y todas se actualizan solas. Los campos {pág} / {total} de la maestra dan el
# número de CADA página.
#   · metas de página: "is_master" (bool) y "master" (nombre de la maestra);
#   · la capa no se guarda (se rehace) pero sí sale al exportar.
# =============================================================================
extends RefCounted

const IS_META := "is_master"
const USE_META := "master"
const LAYER := "_MasterLayer"

static var recorder: Callable = Callable()

static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

static func pages(tree: SceneTree) -> Array:
	return tree.get_nodes_in_group("artboards") if tree else []

static func is_master(page: Node) -> bool:
	return is_instance_valid(page) and bool(page.get_meta(IS_META, false))

static func masters(tree: SceneTree) -> Array:
	return pages(tree).filter(func(p) -> bool: return is_master(p))

static func master_of(page: Node) -> Node:
	var nm := String(page.get_meta(USE_META, ""))
	if nm == "" or is_master(page):
		return null
	for m in masters(page.get_tree()):
		if String(m.name) == nm:
			return m
	return null

static func _sig(master: Node) -> int:
	var CS = load("res://scripts/canvas/canvas_serializer.gd")
	return hash(var_to_str([CS.serialize_elements(master), master.get("artboard_size")]))

## Pone / rehace / quita la capa de la maestra en `page` (sin historial).
static func refresh_page(page: Node, master: Node = null) -> void:
	if not is_instance_valid(page):
		return
	if master == null:
		master = master_of(page)
	var layer: Node2D = page.get_node_or_null(LAYER)
	if master == null:
		if layer:
			page.remove_child(layer)
			layer.queue_free()
		return
	var sig := _sig(master)
	if layer and int(layer.get_meta("sig", 0)) == sig and String(layer.get_meta("from", "")) == String(master.name):
		return
	if layer == null:
		layer = Node2D.new()
		layer.name = LAYER
		page.add_child(layer)
	page.move_child(layer, 0)
	for c in layer.get_children():
		layer.remove_child(c)
		c.queue_free()
	var CS = load("res://scripts/canvas/canvas_serializer.gd")
	CS.instantiate_elements(layer, CS.serialize_elements(master))
	layer.set_meta("sig", sig)
	layer.set_meta("from", String(master.name))
	# números de página de ESTA página
	load("res://script_gdscript/text/page_fields.gd").refresh_under(layer)

## Todas las páginas del documento.
static func refresh_all(tree: SceneTree) -> void:
	for p in pages(tree):
		if not (p.get_parent() is SubViewport):
			refresh_page(p)

static func on_history_step(tree: SceneTree) -> void:
	if tree == null:
		return
	(func() -> void: refresh_all(tree)).call_deferred()

## Copia de exportación (raster): la maestra debajo del contenido de `copy`.
static func attach_to_copy(page: Node, copy: Node) -> void:
	var m := master_of(page)
	if m == null:
		return
	var CS = load("res://scripts/canvas/canvas_serializer.gd")
	var layer := Node2D.new()
	layer.name = LAYER
	copy.add_child(layer)
	copy.move_child(layer, 1 if copy.get_child_count() > 1 and copy.get_child(0) is ColorRect else 0)
	CS.instantiate_elements(layer, CS.serialize_elements(m))

# ── cambios con deshacer ─────────────────────────────────────────────────────
static func set_is_master(page: Node, on: bool) -> void:
	var before := is_master(page)
	_commit("Página · maestra", func() -> void:
		if on: page.set_meta(IS_META, true)
		elif page.has_meta(IS_META): page.remove_meta(IS_META)
		refresh_all(page.get_tree()), func() -> void:
		if before: page.set_meta(IS_META, true)
		elif page.has_meta(IS_META): page.remove_meta(IS_META)
		refresh_all(page.get_tree()))

static func set_master(pages_list: Array, master_name: String) -> void:
	var befores: Array = pages_list.map(func(p) -> String: return String(p.get_meta(USE_META, "")))
	var apply_names := func(names: Array) -> void:
		for i in pages_list.size():
			var p: Node = pages_list[i]
			if not is_instance_valid(p):
				continue
			if String(names[i]) == "":
				if p.has_meta(USE_META): p.remove_meta(USE_META)
			else:
				p.set_meta(USE_META, String(names[i]))
			refresh_page(p)
	var after: Array = []
	for p in pages_list:
		after.append(master_name)
	_commit("Página · usar maestra", func() -> void: apply_names.call(after),
		func() -> void: apply_names.call(befores))

static func _commit(action: String, do_fn: Callable, undo_fn: Callable) -> void:
	if recorder.is_valid():
		recorder.call(action, do_fn, undo_fn)
		do_fn.call()
		return
	var hm: Node = _tree().root.get_node_or_null("HistoryManager") if _tree() else null
	if hm:
		hm.register_action(action)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()
