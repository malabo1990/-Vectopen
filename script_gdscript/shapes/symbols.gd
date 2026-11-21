# =============================================================================
# RUTA: res://script_gdscript/shapes/symbols.gd
# COMPONENTES VINCULADOS / SÍMBOLOS (VAL-23), al estilo de Affinity:
#
# · Un componente es un GRUPO marcado (meta "symbol_id"). Todas sus copias en
#   el documento son iguales: editar el contenido de CUALQUIERA actualiza las
#   demás (al terminar cada paso de edición). La posición, giro y escala de
#   cada copia son suyos.
# · «Sincronizar» (sync_enabled) apagado = los cambios dentro de una copia son
#   RETOQUES LOCALES (meta "symbol_overrides" {ruta: {prop: valor}}): no se
#   propagan y se conservan cuando el componente cambia. Así un botón puede
#   decir «Continuar» y otro «Cancelar».
# · El contenido canónico vive en el documento (meta "symbols" del
#   ArtboardsContainer → manifest del .vtp "symbols"); cada copia guarda su
#   firma tras la última sincronización (meta "symbol_sig") para saber si la
#   editaron.
# · Desvincular = la copia pasa a ser un grupo normal.
# La propagación no es un paso de deshacer propio: deshacer la edición de la
# copia origen vuelve a propagar su estado anterior a las demás.
# =============================================================================
extends RefCounted

const CS = preload("res://scripts/canvas/canvas_serializer.gd")

const META_ID := "symbol_id"
const META_SIG := "symbol_sig"
const META_OVR := "symbol_overrides"
const META_DOC := "symbols"            # en el contenedor: {id: {name, content}}
const GROUP := "vectopen_symbol"

static var sync_enabled := true
static var _busy := false              # propagando: no registrar retoques
static var _dirty := {}                # instancia -> true (editada desde la última comprobación)
static var _scheduled := false
static var _full := false              # la próxima comprobación revisa todas las copias

# ── documento ────────────────────────────────────────────────────────────────
static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

static func container() -> Node:
	return preload("res://script_gdscript/text/text_styles.gd").container()

static func _table(c: Node = null) -> Dictionary:
	if c == null:
		c = container()
	return c.get_meta(META_DOC, {}) if c else {}

static func _set_table(c: Node, t: Dictionary) -> void:
	if is_instance_valid(c):
		c.set_meta(META_DOC, t)

static func is_instance(n: Node) -> bool:
	return is_instance_valid(n) and n.has_meta(META_ID) and String(n.get_meta(META_ID)) != ""

## Copia de componente que contiene a `n` (o `n` mismo); null si no hay.
static func instance_of(n: Node) -> Node:
	var p := n
	while p and not ("artboard_size" in p):
		if is_instance(p):
			return p
		p = p.get_parent()
	return null

static func symbol_of(n: Node) -> String:
	var r := instance_of(n)
	return String(r.get_meta(META_ID)) if r else ""

## Todas las copias del componente `id` (todas si id == "").
static func instances(id: String = "") -> Array:
	var tree := _tree()
	if tree == null:
		return []
	var out := []
	for n in tree.get_nodes_in_group(GROUP):
		if is_instance(n) and n.is_inside_tree() and (id == "" or String(n.get_meta(META_ID)) == id):
			out.append(n)
	return out

## Componente creado desde el recurso `asset_id` ("" si no hay).
static func for_asset(asset_id: String) -> String:
	var t := _table()
	for id in t:
		if String(t[id].get("asset", "")) == asset_id:
			return id
	return ""

## Componentes del documento: [{id, name, count}].
static func all() -> Array:
	var t := _table()
	var out := []
	for id in t:
		out.append({"id": id, "name": String(t[id].get("name", id)), "count": instances(id).size()})
	return out

static func _content_of(root: Node) -> Array:
	return CS.serialize_elements(root)

static func _sig(content: Array) -> int:
	return JSON.stringify(content).hash()

static func _new_id(t: Dictionary) -> String:
	var i := t.size() + 1
	while t.has("sym%d" % i):
		i += 1
	return "sym%d" % i

## Prepara un nodo como copia (grupo de registro + firma).
static func _tag(root: Node, id: String, content: Array) -> void:
	root.set_meta(META_ID, id)
	root.set_meta(META_SIG, _sig(content))
	if not root.is_in_group(GROUP):
		root.add_to_group(GROUP)

## Al cargar / pegar / duplicar: registrar las copias que traen la meta.
static func adopt(root: Node) -> void:
	if is_instance(root):
		root.set_meta(META_SIG, -1)   # firma desconocida: se toma sin propagar
		if not root.is_in_group(GROUP):
			root.add_to_group(GROUP)
		if not _resolve_pending:
			_resolve_pending = true
			_resolve_unknown.call_deferred()

static var _resolve_pending := false

## Firma de las copias recién cargadas/pegadas (al fotograma siguiente, ya
## en el árbol), para que su primera edición sí se propague.
static func _resolve_unknown() -> void:
	_resolve_pending = false
	for r in instances():
		if int(r.get_meta(META_SIG, 0)) == -1:
			r.set_meta(META_SIG, _sig(_content_of(r)))

# ── historial ────────────────────────────────────────────────────────────────
static var recorder: Callable = Callable()

static func _commit(action: String, do_fn: Callable, undo_fn: Callable) -> void:
	if recorder.is_valid():
		recorder.call(action, do_fn, undo_fn)
		do_fn.call()
		return
	var tree := _tree()
	var hm: Node = tree.root.get_node_or_null("HistoryManager") if tree else null
	if hm and hm.has_method("register_action"):
		hm.register_action(action)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()

# ── operaciones ──────────────────────────────────────────────────────────────
## Convierte un grupo en componente. Devuelve el id ("" si no es un grupo).
static func make(root: Node2D, symbol_name: String = "", extra: Dictionary = {}) -> String:
	if not is_instance_valid(root) or is_instance(root) or root.get_child_count() == 0:
		return ""
	var c := container()
	if c == null:
		return ""
	var t0: Dictionary = _table(c).duplicate(true)
	var id := _new_id(t0)
	var content := _content_of(root)
	var t1 := t0.duplicate(true)
	t1[id] = {"name": symbol_name if symbol_name.strip_edges() != "" else String(root.name), "content": content}
	t1[id].merge(extra)
	_commit("Componente · crear «%s»" % t1[id]["name"],
		func() -> void:
			_set_table(c, t1.duplicate(true))
			if is_instance_valid(root):
				_tag(root, id, content),
		func() -> void:
			_set_table(c, t0.duplicate(true))
			if is_instance_valid(root):
				_untag(root))
	return id

static func _untag(root: Node) -> void:
	for k in [META_ID, META_SIG, META_OVR]:
		if root.has_meta(k):
			root.remove_meta(k)
	if root.is_in_group(GROUP):
		root.remove_from_group(GROUP)

## Desvincula una copia: queda como grupo normal con su aspecto actual.
static func detach(n: Node) -> bool:
	var r := instance_of(n)
	if r == null:
		return false
	var id := String(r.get_meta(META_ID))
	var sig = r.get_meta(META_SIG, 0)
	var ovr = r.get_meta(META_OVR, {})
	_commit("Componente · desvincular",
		func() -> void:
			if is_instance_valid(r): _untag(r),
		func() -> void:
			if is_instance_valid(r):
				r.set_meta(META_ID, id)
				r.set_meta(META_SIG, sig)
				if not (ovr as Dictionary).is_empty(): r.set_meta(META_OVR, ovr)
				r.add_to_group(GROUP))
	return true

static func rename(id: String, new_name: String) -> bool:
	var c := container()
	var t0: Dictionary = _table(c).duplicate(true)
	if not t0.has(id) or new_name.strip_edges() == "":
		return false
	var t1 := t0.duplicate(true)
	t1[id]["name"] = new_name.strip_edges()
	_commit("Componente · renombrar",
		func() -> void: _set_table(c, t1.duplicate(true)),
		func() -> void: _set_table(c, t0.duplicate(true)))
	return true

## Nueva copia del componente (grupo) lista para añadir al documento.
static func instantiate(id: String) -> Node2D:
	var t := _table()
	if not t.has(id):
		return null
	var g := Node2D.new()
	g.name = String(t[id].get("name", "Componente")).validate_node_name()
	g.set_meta("shape_type", "group")
	var content: Array = t[id].get("content", [])
	CS.instantiate_elements(g, content.duplicate(true))
	_tag(g, id, content)
	return g

# ── retoques locales ─────────────────────────────────────────────────────────
## InspectorCore._write lo llama en cada escritura de propiedad.
static func note_write(shape: Node, prop: String, value) -> void:
	if _busy or not is_instance_valid(shape):
		return
	var r := instance_of(shape)
	if r == null:
		return
	if r == shape:
		return   # transformar la copia entera es suyo, no del componente
	_dirty[r] = true
	if not sync_enabled:
		var ovr: Dictionary = r.get_meta(META_OVR, {}).duplicate(true)
		var path := String(r.get_path_to(shape))
		var d: Dictionary = ovr.get(path, {})
		d[prop] = value
		ovr[path] = d
		r.set_meta(META_OVR, ovr)
	_schedule()

static func clear_overrides(n: Node) -> void:
	var r := instance_of(n)
	if r == null or not r.has_meta(META_OVR):
		return
	var before = r.get_meta(META_OVR)
	var id := String(r.get_meta(META_ID))
	_commit("Componente · quitar retoques",
		func() -> void:
			if is_instance_valid(r):
				r.remove_meta(META_OVR)
				_rebuild(r, _table().get(id, {}).get("content", [])),
		func() -> void:
			if is_instance_valid(r):
				r.set_meta(META_OVR, before)
				_rebuild(r, _table().get(id, {}).get("content", [])))

static func _apply_overrides(r: Node) -> void:
	var ovr: Dictionary = r.get_meta(META_OVR, {})
	if ovr.is_empty():
		return
	var ic: Node = _tree().root.get_node_or_null("InspectorCore")
	for path in ovr:
		var n := r.get_node_or_null(NodePath(path))
		if n == null or ic == null:
			continue
		for p in ovr[path]:
			ic._write(n, p, ovr[path][p])

## Contenido de `r` SIN sus retoques: se escriben un momento los valores del
## componente, se serializa y se vuelven a poner los retoques.
static func _base_content(r: Node, canon: Array) -> Array:
	var ovr: Dictionary = r.get_meta(META_OVR, {})
	if ovr.is_empty():
		return _content_of(r)
	var ic: Node = _tree().root.get_node_or_null("InspectorCore")
	if ic == null:
		return _content_of(r)
	# Valores base: los de una copia temporal del contenido canónico.
	var tmp := Node2D.new()
	CS.instantiate_elements(tmp, canon.duplicate(true))
	var saved := []
	for path in ovr:
		var n := r.get_node_or_null(NodePath(path))
		var b := tmp.get_node_or_null(NodePath(path))
		if n == null or b == null:
			continue
		for p in ovr[path]:
			var base_v = ic._read(b, p)
			if base_v != null:
				saved.append([n, p, ic._read(n, p)])
				ic._write(n, p, base_v)
	var out := _content_of(r)
	for s in saved:
		ic._write(s[0], s[1], s[2])
	tmp.free()
	return out

# ── sincronización ───────────────────────────────────────────────────────────
static func _schedule() -> void:
	if _scheduled:
		return
	_scheduled = true
	(func() -> void:
		_scheduled = false
		sync_now(_candidates())).call_deferred()

## Copias que pueden haber cambiado: las anotadas por note_write y las que
## contienen la selección (mover/editar nodos con las herramientas); todas
## tras deshacer/rehacer.
static func _candidates() -> Array:
	if _full:
		_full = false
		return instances()
	var out := {}
	for r in _dirty:
		if is_instance_valid(r):
			out[r] = true
	var ic: Node = _tree().root.get_node_or_null("InspectorCore")
	if ic and ic.has_method("selection"):
		for n in ic.selection():
			if is_instance_valid(n):
				var r := instance_of(n)
				if r:
					out[r] = true
	return out.keys()

## Llamar tras cada paso del historial. `full` = deshacer/rehacer.
static func on_history_step(full: bool = false) -> void:
	if _busy or _tree() == null or _tree().get_nodes_in_group(GROUP).is_empty():
		return
	_full = _full or full
	_schedule()

## Comprueba las copias: la que cambió (firma distinta) pasa su contenido al
## componente y a las demás copias. Devuelve cuántas copias se rehicieron.
static func sync_now(candidates: Variant = null) -> int:
	if _busy:
		return 0
	var all_inst: Array = instances() if candidates == null else (candidates as Array).filter(
		func(r) -> bool: return is_instance(r) and r.is_inside_tree())
	_dirty.clear()
	if all_inst.is_empty():
		return 0
	var c := container()
	var t: Dictionary = _table(c)
	var rebuilt := 0
	var done_ids := {}
	for r in all_inst:
		var id := String(r.get_meta(META_ID))
		if done_ids.has(id) or not t.has(id):
			continue
		var cur := _content_of(r)
		if int(r.get_meta(META_SIG, 0)) == -1:
			r.set_meta(META_SIG, _sig(cur))   # recién cargada / pegada
			continue
		if _sig(cur) == int(r.get_meta(META_SIG, 0)):
			continue
		done_ids[id] = true
		var canon: Array = t[id].get("content", [])
		var base := cur if not r.has_meta(META_OVR) else _base_content(r, canon)
		r.set_meta(META_SIG, _sig(cur))
		if not sync_enabled and _sig(base) == _sig(canon):
			continue   # solo retoques locales: no se propaga
		t[id]["content"] = base
		for other in instances(id):
			if other != r:
				_rebuild(other, base)
				rebuilt += 1
	if not done_ids.is_empty():
		_set_table(c, t)
		var ge: Node = _tree().root.get_node_or_null("GlobalEvents")
		if ge and ge.has_method("emit_safe"):
			ge.emit_safe("object_style_changed")
	return rebuilt

## Rehace el contenido de una copia con `content` + sus retoques.
static func _rebuild(r: Node, content: Array) -> void:
	_busy = true
	var sm: Node = _tree().root.get_node_or_null("SelectionManager")
	for ch in r.get_children():
		if ch is Node2D and not (String(ch.name) in ["ArtboardTitle"]):
			if sm and sm.has_method("is_selected") and sm.is_selected(ch):
				sm.deselect(ch)
			r.remove_child(ch)
			ch.queue_free()
	CS.instantiate_elements(r, content.duplicate(true))
	_apply_overrides(r)
	r.set_meta(META_SIG, _sig(_content_of(r)))
	_busy = false

# ── guardar / cargar ─────────────────────────────────────────────────────────
static func to_data(c: Node) -> Dictionary:
	var t := _table(c)
	var out := {}
	for id in t:
		out[id] = t[id].duplicate()
	return out

static func from_data(c: Node, data) -> void:
	if not is_instance_valid(c):
		return
	var t := {}
	if data is Dictionary:
		for id in data:
			if data[id] is Dictionary:
				t[String(id)] = (data[id] as Dictionary).duplicate(true)
				t[String(id)]["name"] = String(data[id].get("name", id))
	_set_table(c, t)
