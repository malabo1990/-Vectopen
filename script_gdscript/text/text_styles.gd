# =============================================================================
# RUTA: res://script_gdscript/text/text_styles.gd
# ESTILOS DE TEXTO CON NOMBRE (VAL-24): «Título», «Cuerpo», «Pie»…
#
# · Un estilo = nombre + propiedades tipográficas (STYLE_PROPS). Viven en el
#   DOCUMENTO (meta "text_styles" del ArtboardsContainer) y se guardan en el
#   manifest del .vtp ("text_styles").
# · Aplicar un estilo a textos escribe sus propiedades y los VINCULA
#   (meta "text_style" = id del estilo).
# · Redefinir un estilo actualiza todos los textos vinculados del documento
#   (también los de páginas dormidas, que se despiertan). Los retoques locales
#   se respetan: solo se cambia una propiedad si el texto tenía el valor
#   ANTERIOR del estilo (como InDesign / Affinity).
# · Todo pasa por HistoryManager: cada operación es UN paso de deshacer.
# =============================================================================
# Sin `class_name` a propósito (convención de text_core.gd): se usa con preload().
extends RefCounted

const META_DOC := "text_styles"    # en el contenedor: {id: {name, props}}
const META_ORDER := "text_styles_order"
const META_LINK := "text_style"    # en el texto: id del estilo

## Propiedades que forman un estilo (nombres del Inspector).
const STYLE_PROPS := ["font_family", "font_weight", "font_italic", "font_size",
	"line_spacing", "letter_spacing", "fill_color", "text_align"]

# ── documento ────────────────────────────────────────────────────────────────
static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

## Contenedor de páginas del documento abierto (o null).
static func container() -> Node:
	var tree := _tree()
	if tree == null:
		return null
	var canvas := tree.get_first_node_in_group("_vectopen_canvas")
	var c: Node = canvas.get_node_or_null("ArtboardsContainer") if canvas else null
	if c == null and tree.current_scene:
		c = tree.current_scene.find_child("ArtboardsContainer", true, false)
	return c

static func _ic() -> Node:
	var tree := _tree()
	return tree.root.get_node_or_null("InspectorCore") if tree else null

static func _table(c: Node = null) -> Dictionary:
	if c == null:
		c = container()
	return c.get_meta(META_DOC, {}) if c else {}

static func _order(c: Node = null) -> Array:
	if c == null:
		c = container()
	if c == null:
		return []
	var t := _table(c)
	var o: Array = (c.get_meta(META_ORDER, []) as Array).filter(func(id) -> bool: return t.has(id))
	for id in t:
		if not (id in o):
			o.append(id)
	return o

static func _set_state(c: Node, table: Dictionary, order: Array) -> void:
	if not is_instance_valid(c):
		return
	c.set_meta(META_DOC, table.duplicate(true))
	c.set_meta(META_ORDER, order.duplicate())

## Estilos del documento, en orden: [{id, name, props}].
static func all(c: Node = null) -> Array:
	var t := _table(c)
	var out := []
	for id in _order(c):
		var s: Dictionary = t[id]
		out.append({"id": id, "name": String(s.get("name", id)), "props": (s.get("props", {}) as Dictionary).duplicate()})
	return out

static func get_style(id: String, c: Node = null) -> Dictionary:
	var t := _table(c)
	if not t.has(id):
		return {}
	var s: Dictionary = t[id]
	return {"id": id, "name": String(s.get("name", id)), "props": (s.get("props", {}) as Dictionary).duplicate()}

static func find_by_name(style_name: String, c: Node = null) -> String:
	for s in all(c):
		if String(s["name"]).to_lower() == style_name.strip_edges().to_lower():
			return String(s["id"])
	return ""

static func is_text(n: Node) -> bool:
	return is_instance_valid(n) and n.has_meta("shape_type") and String(n.get_meta("shape_type")).begins_with("text_")

## Id del estilo vinculado a un texto ("" si no tiene o si ya no existe).
static func style_of(n: Node, c: Node = null) -> String:
	if not is_text(n):
		return ""
	var id := String(n.get_meta(META_LINK, ""))
	return id if _table(c).has(id) else ""

## Propiedades tipográficas actuales de un texto.
static func capture(n: Node) -> Dictionary:
	var ic := _ic()
	var out := {}
	if ic == null or not is_text(n):
		return out
	for p in STYLE_PROPS:
		var v = ic._read(n, p)
		if v != null:
			out[p] = v
	return out

## ¿El texto tiene retoques locales respecto a su estilo?
static func is_modified(n: Node, c: Node = null) -> bool:
	var id := style_of(n, c)
	if id == "":
		return false
	var cur := capture(n)
	var props: Dictionary = get_style(id, c)["props"]
	for p in props:
		if cur.has(p) and not _eq(cur[p], props[p]):
			return true
	return false

static func _eq(a, b) -> bool:
	if a is Color and b is Color:
		return (a as Color).is_equal_approx(b)
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 0.001
	return a == b

static func _new_id(t: Dictionary) -> String:
	var i := t.size() + 1
	while t.has("ts%d" % i):
		i += 1
	return "ts%d" % i

static func _unique_name(base: String, t: Dictionary, skip_id: String = "") -> String:
	base = base.strip_edges()
	if base == "":
		base = "Estilo"
	var names := {}
	for id in t:
		if id != skip_id:
			names[String(t[id].get("name", "")).to_lower()] = true
	if not names.has(base.to_lower()):
		return base
	var k := 2
	while names.has(("%s %d" % [base, k]).to_lower()):
		k += 1
	return "%s %d" % [base, k]

# ── historial ────────────────────────────────────────────────────────────────
## La API de scripts lo fija mientras llama: así el cambio entra en SU
## transacción (un script entero = un paso de deshacer).
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

static func _post() -> void:
	var ic := _ic()
	if ic and ic.has_method("_post_write"):
		ic._sync_selection()
		ic._post_write()

## Escribe props en un texto (sin historial) y fija/quita su vínculo.
static func _write_node(n: Node, props: Dictionary, link) -> void:
	if not is_instance_valid(n):
		return
	var ic := _ic()
	if ic:
		for p in props:
			ic._write(n, p, props[p])
	if link == null:
		pass
	elif String(link) == "":
		n.remove_meta(META_LINK)
	else:
		n.set_meta(META_LINK, String(link))

static func _snapshot(nodes: Array) -> Array:
	var out := []
	for n in nodes:
		out.append({"n": n, "props": capture(n), "link": String(n.get_meta(META_LINK, ""))})
	return out

static func _restore(snap: Array) -> void:
	for r in snap:
		_write_node(r["n"], r["props"], r["link"])

# ── operaciones (cada una es UN paso de deshacer) ────────────────────────────
## Crea un estilo con las propiedades de `source` (un texto) o un diccionario
## de props. Si `link_nodes` trae textos, quedan vinculados. Devuelve el id.
static func create(style_name: String, source: Variant, link_nodes: Array = []) -> String:
	var c := container()
	if c == null:
		return ""
	var props: Dictionary = capture(source) if source is Node else _clean_props(source as Dictionary)
	if props.is_empty():
		return ""
	var t0 := _table(c).duplicate(true)
	var o0 := _order(c)
	var id := _new_id(t0)
	var t1 := t0.duplicate(true)
	t1[id] = {"name": _unique_name(style_name, t0), "props": props}
	var o1 := o0.duplicate()
	o1.append(id)
	var texts := link_nodes.filter(is_text)
	var snap := _snapshot(texts)
	_commit("Estilo de texto · crear «%s»" % t1[id]["name"],
		func() -> void:
			_set_state(c, t1, o1)
			for n in texts:
				_write_node(n, props, id)
			_post(),
		func() -> void:
			_restore(snap)
			_set_state(c, t0, o0)
			_post())
	return id

## Aplica el estilo a los textos (quita retoques locales) y los vincula.
static func apply(id: String, nodes: Array) -> bool:
	var st := get_style(id)
	if st.is_empty():
		return false
	var texts := nodes.filter(is_text)
	if texts.is_empty():
		return false
	var props: Dictionary = st["props"]
	var snap := _snapshot(texts)
	_commit("Estilo de texto · aplicar «%s»" % st["name"],
		func() -> void:
			for n in texts:
				_write_node(n, props, id)
			_post(),
		func() -> void:
			_restore(snap)
			_post())
	return true

## Desvincula textos de su estilo (conservan su aspecto).
static func detach(nodes: Array) -> void:
	var texts := nodes.filter(func(n) -> bool: return is_text(n) and n.has_meta(META_LINK))
	if texts.is_empty():
		return
	var links := texts.map(func(n) -> String: return String(n.get_meta(META_LINK)))
	_commit("Estilo de texto · desvincular",
		func() -> void:
			for n in texts:
				if is_instance_valid(n): n.remove_meta(META_LINK)
			_post(),
		func() -> void:
			for i in texts.size():
				if is_instance_valid(texts[i]): texts[i].set_meta(META_LINK, links[i])
			_post())

## Redefine el estilo con nuevas props (un texto o un diccionario, puede ser
## parcial) y actualiza TODOS los textos vinculados del documento. Una
## propiedad se cambia en un texto solo si tenía el valor anterior del estilo
## (los retoques locales se conservan), salvo en `force_nodes` (p. ej. el
## texto del que se toma la definición), que quedan idénticos al estilo.
static func redefine(id: String, source: Variant) -> int:
	var c := container()
	var st := get_style(id, c)
	if st.is_empty():
		return 0
	var new_props: Dictionary = capture(source) if source is Node else _clean_props(source as Dictionary)
	var old_props: Dictionary = st["props"]
	var merged := old_props.duplicate()
	merged.merge(new_props, true)
	var changed := {}
	for p in merged:
		if not old_props.has(p) or not _eq(old_props[p], merged[p]):
			changed[p] = merged[p]
	if changed.is_empty():
		return 0
	var plan := []   # [{n, props}]
	for n in linked_texts(id, c, true):
		var cur := capture(n)
		var upd := {}
		for p in changed:
			var forced: bool = source is Node and n == source
			if forced or not old_props.has(p) or not cur.has(p) or _eq(cur[p], old_props[p]):
				upd[p] = changed[p]
		if not upd.is_empty():
			plan.append({"n": n, "props": upd})
	var texts := plan.map(func(r) -> Node: return r["n"])
	var snap := _snapshot(texts)
	var t0 := _table(c).duplicate(true)
	var t1 := t0.duplicate(true)
	t1[id]["props"] = merged
	var o := _order(c)
	_commit("Estilo de texto · redefinir «%s»" % st["name"],
		func() -> void:
			_set_state(c, t1, o)
			for r in plan:
				_write_node(r["n"], r["props"], null)
			_post(),
		func() -> void:
			_restore(snap)
			_set_state(c, t0, o)
			_post())
	return plan.size()

static func rename(id: String, new_name: String) -> bool:
	var c := container()
	var t0 := _table(c).duplicate(true)
	if not t0.has(id) or new_name.strip_edges() == "":
		return false
	var t1 := t0.duplicate(true)
	t1[id]["name"] = _unique_name(new_name, t0, id)
	var o := _order(c)
	_commit("Estilo de texto · renombrar",
		func() -> void:
			_set_state(c, t1, o)
			_post(),
		func() -> void:
			_set_state(c, t0, o)
			_post())
	return true

## Borra el estilo: sus textos quedan desvinculados con su aspecto actual.
static func remove(id: String) -> bool:
	var c := container()
	var t0 := _table(c).duplicate(true)
	if not t0.has(id):
		return false
	var o0 := _order(c)
	var t1 := t0.duplicate(true)
	t1.erase(id)
	var o1 := o0.filter(func(x) -> bool: return x != id)
	var texts := linked_texts(id, c, false)
	_commit("Estilo de texto · borrar «%s»" % t0[id]["name"],
		func() -> void:
			_set_state(c, t1, o1)
			for n in texts:
				if is_instance_valid(n): n.remove_meta(META_LINK)
			_post(),
		func() -> void:
			_set_state(c, t0, o0)
			for n in texts:
				if is_instance_valid(n): n.set_meta(META_LINK, id)
			_post())
	return true

## Textos vinculados al estilo `id` en todo el documento. `wake` = despertar
## antes las páginas dormidas (necesario para modificarlas).
static func linked_texts(id: String, c: Node = null, wake: bool = false) -> Array:
	if c == null:
		c = container()
	var out := []
	if c == null:
		return out
	for ch in c.get_children():
		if wake and ch.has_method("wake_now"):
			ch.wake_now()
		_collect(ch, id, out)
	return out

static func _collect(n: Node, id: String, out: Array) -> void:
	if is_text(n):
		if String(n.get_meta(META_LINK, "")) == id:
			out.append(n)
		return
	for ch in n.get_children():
		if ch is Node2D:
			_collect(ch, id, out)

# ── guardar / cargar ─────────────────────────────────────────────────────────
static func _clean_props(d: Dictionary) -> Dictionary:
	var out := {}
	for p in STYLE_PROPS:
		if d.has(p):
			out[p] = _dec(p, d[p])
	return out

static func _enc(p: String, v):
	if v is Color:
		return "#" + (v as Color).to_html(true)
	return v

static func _dec(p: String, v):
	match p:
		"fill_color":
			return Color.html(v) if v is String and Color.html_is_valid(v) else (v if v is Color else Color.BLACK)
		"font_weight", "line_spacing":
			return int(v)
		"font_size", "letter_spacing":
			return float(v)
		"font_italic":
			return bool(v)
		_:
			return String(v)

## Estilos del documento como datos JSON (manifest del .vtp).
static func to_data(c: Node) -> Array:
	var out := []
	for s in all(c):
		var props := {}
		for p in s["props"]:
			props[p] = _enc(p, s["props"][p])
		out.append({"id": s["id"], "name": s["name"], "props": props})
	return out

## Carga los estilos guardados (o los vacía si `data` está vacío).
static func from_data(c: Node, data) -> void:
	if not is_instance_valid(c):
		return
	var t := {}
	var o := []
	if data is Array:
		for s in data:
			if s is Dictionary and s.has("id"):
				var id := String(s["id"])
				t[id] = {"name": String(s.get("name", id)), "props": _clean_props(s.get("props", {}))}
				o.append(id)
	_set_state(c, t, o)
