# =============================================================================
# RUTA: res://script_gdscript/shapes/global_colors.gd
# COLORES GLOBALES DEL DOCUMENTO (encargo 25, manual de marca): muestras con
# nombre («Azul marca», «Arena»…) guardadas en el .vtp. Un objeto puede
# VINCULAR su relleno y/o su trazo a una muestra (metas "fill_global" /
# "stroke_global" = id); al cambiar la muestra cambian todos los objetos que
# la usan. Un color puesto a mano después desvincula ese canal.
# Mismo patrón que TextStyles: meta del ArtboardsContainer + manifest, un
# paso de deshacer por operación.
# =============================================================================
extends RefCounted

const META_DOC := "doc_colors"            # {id: {name, color}}
const META_ORDER := "doc_colors_order"
const LINK := {"fill": "fill_global", "stroke": "stroke_global"}
const PROP := {"fill": "fill_color", "stroke": "stroke_color"}

static var recorder: Callable = Callable()

static func container() -> Node:
	return preload("res://script_gdscript/text/text_styles.gd").container()

static func _ic() -> Node:
	var t := Engine.get_main_loop() as SceneTree
	return t.root.get_node_or_null("InspectorCore") if t else null

static func _table(c: Node = null) -> Dictionary:
	if c == null:
		c = container()
	return c.get_meta(META_DOC, {}) if c else {}

static func _order(c: Node) -> Array:
	var t := _table(c)
	var o: Array = (c.get_meta(META_ORDER, []) as Array).filter(func(id) -> bool: return t.has(id)) if c else []
	for id in t:
		if not (id in o):
			o.append(id)
	return o

static func _set_state(c: Node, t: Dictionary, o: Array) -> void:
	if is_instance_valid(c):
		c.set_meta(META_DOC, t.duplicate(true))
		c.set_meta(META_ORDER, o.duplicate())

static func all() -> Array:
	var c := container()
	var t := _table(c)
	var out := []
	if c == null:
		return out
	for id in _order(c):
		out.append({"id": id, "name": String(t[id]["name"]), "color": t[id]["color"]})
	return out

static func get_color(id: String) -> Variant:
	var t := _table()
	return t[id]["color"] if t.has(id) else null

static func find_by_name(n: String) -> String:
	for e in all():
		if String(e["name"]).to_lower() == n.strip_edges().to_lower():
			return String(e["id"])
	return ""

static func _commit(action: String, do_fn: Callable, undo_fn: Callable) -> void:
	if recorder.is_valid():
		recorder.call(action, do_fn, undo_fn)
		do_fn.call()
		return
	var hm: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("HistoryManager")
	if hm:
		hm.register_action(action)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()

static func _post() -> void:
	var ic := _ic()
	if ic and ic.has_method("_post_write"):
		ic._sync_selection()
		ic._post_write()

static func _guard_write(n: Variant, prop: String, value) -> void:
	# Escribir sin desvincular (la desvinculación es para cambios a mano).
	# Los nodos de las copias de un componente se rehacen al propagar: los
	# ya liberados se saltan (la propagación pone el color en las demás).
	if not is_instance_valid(n):
		return
	_writing = true
	var ic := _ic()
	if ic:
		ic._write(n, prop, value)
	_writing = false

static var _writing := false

## InspectorCore._write: un color puesto A MANO desvincula ese canal.
static func note_write(n: Node, prop: String) -> void:
	if _writing or not is_instance_valid(n):
		return
	var p2: String = {"fill_paint": "fill_color", "stroke_paint": "stroke_color"}.get(prop, prop)
	for ch in PROP:
		if PROP[ch] == p2 and n.has_meta(LINK[ch]):
			n.remove_meta(LINK[ch])

static func add(name: String, color: Color) -> String:
	var c := container()
	if c == null:
		return ""
	var t0 := _table(c).duplicate(true)
	var o0 := _order(c)
	var i := t0.size() + 1
	while t0.has("gc%d" % i):
		i += 1
	var id := "gc%d" % i
	var t1 := t0.duplicate(true)
	t1[id] = {"name": name.strip_edges() if name.strip_edges() != "" else "Color %d" % i, "color": color}
	var o1 := o0.duplicate()
	o1.append(id)
	_commit("Color global · crear «%s»" % t1[id]["name"],
		func() -> void:
			_set_state(c, t1, o1)
			_post(),
		func() -> void:
			_set_state(c, t0, o0)
			_post())
	return id

## Vincula el canal ("fill" / "stroke") de los objetos a la muestra.
static func apply(id: String, nodes: Array, channel: String = "fill") -> bool:
	var col = get_color(id)
	if col == null or not LINK.has(channel):
		return false
	var ic := _ic()
	var recs := []
	for n in nodes:
		if is_instance_valid(n) and ic and ic._read(n, PROP[channel]) != null:
			recs.append({"n": n, "before": ic._read(n, PROP[channel]), "link": String(n.get_meta(LINK[channel], ""))})
	if recs.is_empty():
		return false
	_commit("Color global · aplicar",
		func() -> void:
			for r in recs:
				if not is_instance_valid(r["n"]): continue
				_guard_write(r["n"], PROP[channel], col)
				r["n"].set_meta(LINK[channel], id)
			_post(),
		func() -> void:
			for r in recs:
				if not is_instance_valid(r["n"]): continue
				_guard_write(r["n"], PROP[channel], r["before"])
				if r["link"] == "": r["n"].remove_meta(LINK[channel])
				else: r["n"].set_meta(LINK[channel], r["link"])
			_post())
	return true

## Cambia la muestra y TODOS los objetos vinculados (rellenos y trazos).
static func set_color(id: String, color: Color) -> int:
	var c := container()
	var t0 := _table(c).duplicate(true)
	if not t0.has(id):
		return 0
	var t1 := t0.duplicate(true)
	t1[id]["color"] = color
	var old: Color = t0[id]["color"]
	var o := _order(c)
	var linked := linked_nodes(id)
	_commit("Color global · cambiar «%s»" % t0[id]["name"],
		func() -> void:
			_set_state(c, t1, o)
			for e in linked:
				_guard_write(e[0], PROP[e[1]], color)
			_post(),
		func() -> void:
			_set_state(c, t0, o)
			for e in linked:
				_guard_write(e[0], PROP[e[1]], old)
			_post())
	return linked.size()

static func rename(id: String, new_name: String) -> bool:
	var c := container()
	var t0 := _table(c).duplicate(true)
	if not t0.has(id) or new_name.strip_edges() == "":
		return false
	var t1 := t0.duplicate(true)
	t1[id]["name"] = new_name.strip_edges()
	var o := _order(c)
	_commit("Color global · renombrar",
		func() -> void: _set_state(c, t1, o),
		func() -> void: _set_state(c, t0, o))
	return true

## [[nodo, canal]…] vinculados a la muestra en todo el documento (despierta
## las páginas dormidas para poder cambiarlas).
static func linked_nodes(id: String) -> Array:
	var out := []
	var c := container()
	if c == null:
		return out
	for ab in c.get_children():
		if ab.has_method("wake_now"):
			ab.wake_now()
		for n in ab.find_children("*", "", true, false) + [ab]:
			for ch in LINK:
				if String(n.get_meta(LINK[ch], "")) == id:
					out.append([n, ch])
	return out

# ── guardar / cargar ─────────────────────────────────────────────────────────
static func to_data(c: Node) -> Array:
	var out := []
	var t := _table(c)
	for id in _order(c) if c else []:
		out.append({"id": id, "name": t[id]["name"], "color": "#" + (t[id]["color"] as Color).to_html(true)})
	return out

static func from_data(c: Node, data) -> void:
	var t := {}
	var o := []
	if data is Array:
		for e in data:
			if e is Dictionary and e.has("id"):
				t[String(e["id"])] = {"name": String(e.get("name", e["id"])), "color": Color.html(String(e.get("color", "#000000")))}
				o.append(String(e["id"]))
	_set_state(c, t, o)
