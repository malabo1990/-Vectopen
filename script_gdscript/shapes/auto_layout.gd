# =============================================================================
# RUTA: res://script_gdscript/shapes/auto_layout.gd
# AUTO LAYOUT (informe de propuestas §4, como Figma / Penpot): un GRUPO pasa
# a ser contenedor que coloca solos a sus hijos.
#   · modo: "row" (HBox), "column" (VBox), "grid" (filas × columnas) o "wrap"
#     (fila que salta de línea según el ancho: content flow);
#   · gap (separación), padding (margen interior), alineación principal
#     (start / center / end / space-between) y transversal (start / center /
#     end), columnas (grid), ancho de salto (wrap), tamaño automático;
#   · fondo opcional: un rectángulo hijo marcado "layout_bg" que se ajusta al
#     contenido (así un rectángulo se convierte en contenedor);
#   · orden = el de las capas.
# Se guarda en el .vtp (meta "layout") y se recoloca tras cada paso del
# historial (sin pasos propios: es determinista).
# =============================================================================
extends RefCounted

const META := "layout"
const BG_META := "layout_bg"
const GROUP := "_vectopen_layout"
const MODES := ["row", "column", "grid", "wrap"]
const DEFAULTS := {"mode": "row", "gap": 16.0, "padding": 16.0, "align": "start",
	"cross": "start", "columns": 3, "wrap_width": 600.0, "auto": true}

static var recorder: Callable = Callable()
static var _busy := false
static var _scheduled := false

static func is_layout(n: Node) -> bool:
	return is_instance_valid(n) and n.has_meta(META)

static func params(g: Node) -> Dictionary:
	var p := DEFAULTS.duplicate()
	p.merge(g.get_meta(META, {}) as Dictionary, true)
	return p

static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

# ── cajas ────────────────────────────────────────────────────────────────────
## Caja de `n` en coordenadas de su padre.
static func box(n: Node2D) -> Rect2:
	var pts := PackedVector2Array()
	if n.has_method("get_effect_points"):
		pts = n.get_effect_points()
	elif n is Line2D:
		pts = (n as Line2D).points
	elif n is Sprite2D and (n as Sprite2D).texture:
		var s := (n as Sprite2D).texture.get_size()
		pts = PackedVector2Array([-s / 2.0, s / 2.0]) if (n as Sprite2D).centered else PackedVector2Array([Vector2.ZERO, s])
	elif n.has_meta("shape_type") and String(n.get_meta("shape_type")).begins_with("text"):
		var w := float(n.get_meta("width", 100.0))
		var h := float(n.get_meta("height", 30.0))
		pts = PackedVector2Array([Vector2.ZERO, Vector2(w, h)])
	if pts.is_empty():
		var r := Rect2()
		var first := true
		for c in n.get_children():
			if c is Node2D and not _skip(c):
				var b := box(c)
				if b.size == Vector2.ZERO and b.position == Vector2.ZERO:
					continue
				b = Rect2(n.transform * b.position, Vector2.ZERO).expand(n.transform * b.end)
				r = b if first else r.merge(b)
				first = false
		return r
	var out := Rect2(n.transform * pts[0], Vector2.ZERO)
	for p in pts:
		out = out.expand(n.transform * p)
	return out

static func _skip(c: Node) -> bool:
	return String(c.name).begins_with("_") or c.has_meta(&"_vectopen_internal")

static func _move(n: Node2D, delta: Vector2) -> void:
	if delta.length_squared() < 0.000001:
		return
	if n is VectorShape:
		(n as VectorShape).set_doc_position(DVec2.from_v2(n.position + delta))
	else:
		n.position += delta

static func items(g: Node) -> Array:
	return g.get_children().filter(func(c) -> bool:
		return c is Node2D and not _skip(c) and not c.has_meta(BG_META) and (c as Node2D).visible)

static func background(g: Node) -> Node2D:
	for c in g.get_children():
		if c is Node2D and c.has_meta(BG_META):
			return c
	return null

# ── colocar ──────────────────────────────────────────────────────────────────
## Recoloca los hijos de `g` (sin historial).
static func apply(g: Node2D) -> void:
	if not is_layout(g):
		return
	var p := params(g)
	var its := items(g)
	var bg := background(g)
	var pad := float(p["padding"])
	var gap := float(p["gap"])
	var mode := String(p["mode"])
	# Sin fondo: se coloca a partir de donde estaban los objetos al crear el
	# contenedor (antes desde el origen del grupo → «saltaban» de sitio).
	var origin: Vector2 = p.get("origin", Vector2.ZERO) if p.get("origin") is Vector2 else Vector2.ZERO
	var fixed := Vector2.ZERO   # interior disponible si el tamaño NO es automático
	if bg:
		var bb := box(bg)
		origin = bb.position
		if not bool(p["auto"]):
			fixed = bb.size - Vector2(pad, pad) * 2.0
	var boxes: Array = []
	for it in its:
		boxes.append(box(it))
	var placed: Array = []   # posiciones (esquina) por ítem
	var content := Vector2.ZERO
	match mode:
		"row", "column":
			var main := 0 if mode == "row" else 1
			var cross := 1 - main
			var total := 0.0
			var cross_max := 0.0
			for b in boxes:
				total += (b as Rect2).size[main]
				cross_max = maxf(cross_max, (b as Rect2).size[cross])
			total += gap * maxf(boxes.size() - 1, 0)
			var avail_main: float = fixed[main] if fixed[main] > 0.0 else total
			var avail_cross: float = fixed[cross] if fixed[cross] > 0.0 else cross_max
			var cursor := 0.0
			var extra := maxf(avail_main - total, 0.0)
			var step_gap := gap
			match String(p["align"]):
				"center": cursor = extra / 2.0
				"end": cursor = extra
				"space-between":
					if boxes.size() > 1:
						step_gap = gap + extra / (boxes.size() - 1)
			for b in boxes:
				var r: Rect2 = b
				var pos := Vector2.ZERO
				pos[main] = cursor
				var off := 0.0
				match String(p["cross"]):
					"center": off = (avail_cross - r.size[cross]) / 2.0
					"end": off = avail_cross - r.size[cross]
				pos[cross] = off
				placed.append(pos)
				cursor += r.size[main] + step_gap
			content[main] = avail_main
			content[cross] = avail_cross
		"grid":
			var cols := maxi(1, int(p["columns"]))
			var cw := 0.0
			var ch := 0.0
			for b in boxes:
				cw = maxf(cw, (b as Rect2).size.x)
				ch = maxf(ch, (b as Rect2).size.y)
			for i in boxes.size():
				var r: Rect2 = boxes[i]
				var cell := Vector2((i % cols) * (cw + gap), (i / cols) * (ch + gap))
				var off := Vector2.ZERO
				match String(p["cross"]):
					"center": off = (Vector2(cw, ch) - r.size) / 2.0
					"end": off = Vector2(cw, ch) - r.size
				placed.append(cell + off)
			var rows := int(ceil(boxes.size() / float(cols)))
			content = Vector2(mini(cols, boxes.size()) * (cw + gap) - gap, rows * (ch + gap) - gap).max(Vector2.ZERO)
		"wrap":
			var limit: float = fixed.x if fixed.x > 0.0 else float(p["wrap_width"])
			var x := 0.0
			var y := 0.0
			var line_h := 0.0
			var widest := 0.0
			for b in boxes:
				var r: Rect2 = b
				if x > 0.0 and x + r.size.x > limit:
					x = 0.0
					y += line_h + gap
					line_h = 0.0
				placed.append(Vector2(x, y))
				x += r.size.x + gap
				widest = maxf(widest, x - gap)
				line_h = maxf(line_h, r.size.y)
			content = Vector2(widest, y + line_h)
	var start := origin + Vector2(pad, pad)
	for i in its.size():
		_move(its[i], start + placed[i] - (boxes[i] as Rect2).position)
	# fondo a la medida (tamaño automático)
	if bg and bool(p["auto"]) and bg is VectorRectangle:
		var size := content + Vector2(pad, pad) * 2.0
		var r := bg as VectorRectangle
		r.size = size.max(Vector2(1, 1))
		if r.has_method("set_doc_extent"):
			r.set_doc_extent(DVec2.from_v2(r.size))
		_move(r, origin + size / 2.0 - r.position)
	g.set_meta("_layout_sig", _sig(g))

static func _sig(g: Node) -> int:
	var parts: Array = [var_to_str(params(g))]
	for it in items(g):
		parts.append(box(it))   # tamaño Y posición: un hijo arrastrado vuelve a su sitio
		parts.append(it.name)
	var bg := background(g)
	if bg:
		parts.append(box(bg))
	return hash(var_to_str(parts))

# ── crear / ajustes / quitar ─────────────────────────────────────────────────
## Hace contenedor el grupo `g` (o crea el fondo si `bg_rect`).
static func make(g: Node2D, opts: Dictionary = {}, bg_rect: Node2D = null) -> void:
	var before = g.get_meta(META) if g.has_meta(META) else null
	var p := DEFAULTS.duplicate()
	p.merge(opts, true)
	var snap := _snapshot(g)
	# Que NO cambie de sitio: el contenedor empieza donde estaban los objetos
	# (su esquina superior izquierda) y los coloca en el orden en que se ven
	# (izquierda → derecha en fila; arriba → abajo en columna / rejilla).
	if bg_rect == null and not p.has("origin"):
		var its0 := items(g)
		if not its0.is_empty():
			var u: Rect2 = box(its0[0])
			for it in its0:
				u = u.merge(box(it))
			p["origin"] = u.position - Vector2(float(p["padding"]), float(p["padding"]))
	var visual: Array = items(g)
	var m := String(p["mode"])
	visual.sort_custom(func(a, b) -> bool:
		var ra: Rect2 = box(a)
		var rb: Rect2 = box(b)
		if m == "column":
			return ra.position.y < rb.position.y
		if m == "row":
			return ra.position.x < rb.position.x
		# rejilla / salto: por filas
		if absf(ra.position.y - rb.position.y) > minf(ra.size.y, rb.size.y) * 0.5:
			return ra.position.y < rb.position.y
		return ra.position.x < rb.position.x)
	var do_fn := func() -> void:
		var first_free := 1 if bg_rect else 0
		for i in visual.size():
			if is_instance_valid(visual[i]) and visual[i].get_parent() == g:
				g.move_child(visual[i], mini(first_free + i, g.get_child_count() - 1))
		g.set_meta(META, p.duplicate())
		if bg_rect:
			bg_rect.set_meta(BG_META, true)
			if bg_rect.get_index() != 0:
				g.move_child(bg_rect, 0)
		g.add_to_group(GROUP)
		apply(g)
	var undo_fn := func() -> void:
		if before == null:
			g.remove_meta(META)
			g.remove_from_group(GROUP)
		else:
			g.set_meta(META, before)
		if bg_rect and bg_rect.has_meta(BG_META):
			bg_rect.remove_meta(BG_META)
		_restore(snap)
	_commit("Contenedor · crear", do_fn, undo_fn)

static func _snapshot(g: Node) -> Array:
	var out: Array = []
	for c in g.get_children():
		if c is Node2D:
			out.append([c, (c as Node2D).position, (c as VectorRectangle).size if c is VectorRectangle else Vector2.ZERO, c.get_index()])
	return out

static func _restore(snap: Array) -> void:
	for s in snap:
		var n: Node2D = s[0]
		if not is_instance_valid(n):
			continue
		if n is VectorRectangle and s[2] != Vector2.ZERO:
			(n as VectorRectangle).size = s[2]
		_move(n, (s[1] as Vector2) - n.position)
		if n.get_parent():
			n.get_parent().move_child(n, mini(int(s[3]), n.get_parent().get_child_count() - 1))

static func release(g: Node2D) -> void:
	var p: Dictionary = (g.get_meta(META) as Dictionary).duplicate()
	_commit("Contenedor · quitar", func() -> void:
		g.remove_meta(META)
		g.remove_from_group(GROUP), func() -> void:
		g.set_meta(META, p.duplicate())
		g.add_to_group(GROUP)
		apply(g))

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

# ── inspector (InspectorCore pone el deshacer) ──────────────────────────────
const PROPS := ["layout_mode", "layout_gap", "layout_padding", "layout_align", "layout_cross",
	"layout_columns", "layout_wrap_width", "layout_auto"]

static func handles(prop: String) -> bool:
	return PROPS.has(prop)

static func read_prop(n: Node, prop: String) -> Variant:
	if not is_layout(n):
		return null
	var p := params(n)
	var k := prop.trim_prefix("layout_")
	match k:
		"gap", "padding", "wrap_width": return float(p[k])
		"columns": return float(p[k])
		"auto": return bool(p[k])
	return String(p[k])

static func write_prop(n: Node, prop: String, value: Variant) -> void:
	if not is_layout(n):
		return
	var p: Dictionary = (n.get_meta(META) as Dictionary).duplicate()
	var k := prop.trim_prefix("layout_")
	match k:
		"mode": p[k] = String(value) if String(value) in MODES else "row"
		"gap", "padding": p[k] = maxf(0.0, float(value))
		"wrap_width": p[k] = maxf(10.0, float(value))
		"columns": p[k] = clampi(int(round(float(value))), 1, 64)
		"auto": p[k] = bool(value)
		_: p[k] = String(value)
	n.set_meta(META, p)
	apply(n)

# ── sincronización ───────────────────────────────────────────────────────────
static func on_history_step(tree: SceneTree) -> void:
	if _busy or tree == null or tree.get_nodes_in_group(GROUP).is_empty() or _scheduled:
		return
	_scheduled = true
	(func() -> void:
		_scheduled = false
		sync_now(tree)).call_deferred()

static func sync_now(tree: SceneTree) -> int:
	_busy = true
	var n := 0
	for g in tree.get_nodes_in_group(GROUP):
		if is_layout(g) and int(g.get_meta("_layout_sig", 0)) != _sig(g):
			apply(g)
			n += 1
	_busy = false
	return n

static func adopt(g: Node) -> void:
	if is_layout(g):
		g.add_to_group(GROUP)
