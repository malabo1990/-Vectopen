# =============================================================================
# RUTA: res://script_gdscript/shapes/blend.gd
# FUSIÓN (Blend, como Illustrator / Affinity — informe de propuestas §3).
# Genera objetos intermedios entre dos figuras A y B:
#   · forma: los dos contornos remuestreados por longitud (mismo nº de
#     puntos, mismo sentido, punto de inicio alineado) e interpolados;
#   · color de relleno y de trazo, grosor de trazo y opacidad;
#   · pasos fijos («steps») o por distancia entre copias («distance»);
#   · a lo largo de un trazado guía opcional, orientadas o no con él.
# NO destructiva: un grupo «Fusión» (meta "blend") con A, B, la guía y los
# intermedios (meta "_blend_step"). Tras cada paso del historial, si A, B o
# la guía cambiaron (firma), los intermedios se rehacen solos. «Expandir»
# los deja como figuras independientes.
# =============================================================================
extends RefCounted

const META := "blend"
const GROUP := "_vectopen_blend"
const STEP_META := "_blend_step"
const END_META := "_blend_end"      # posición en la cadena: 0 = A, 1 = B, 2 = C…
const SPINE_META := "_blend_spine"
const SAMPLES := 128
const _SG = preload("res://script_gdscript/shapes/stroke_geom.gd")
const DEFAULTS := {"mode": "steps", "steps": 5, "spacing": 40.0, "orient": false}

static var recorder: Callable = Callable()
static var _scheduled := false
static var _busy := false

static func is_blend(n: Node) -> bool:
	return is_instance_valid(n) and n.has_meta(META)

static func blend_of(n: Node) -> Node2D:
	var p := n
	while p and not ("artboard_size" in p):
		if is_blend(p):
			return p
		p = p.get_parent()
	return null

static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

# ── geometría ────────────────────────────────────────────────────────────────
## Contorno de `n` en coordenadas del grupo (cerrado salvo trazados abiertos).
static func outline(n: Node2D) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if n is VectorPath:
		pts = VectorPath.closed_points((n as VectorPath).curve) if (n as VectorPath).closed \
			else _SG.curve_points((n as VectorPath).curve)
	elif n.has_method("get_effect_points"):
		pts = n.get_effect_points()
	return n.transform * pts

static func _closed(n: Node) -> bool:
	return not (n is VectorPath) or (n as VectorPath).closed

static func _cum(p: PackedVector2Array, closed: bool) -> PackedFloat32Array:
	var c := PackedFloat32Array([0.0])
	var m := p.size() + (1 if closed else 0)
	for i in range(1, m):
		c.append(c[i - 1] + p[(i - 1) % p.size()].distance_to(p[i % p.size()]))
	return c

## `count` puntos repartidos por longitud de arco.
static func resample(p: PackedVector2Array, count: int, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	if p.size() < 2:
		for i in count:
			out.append(p[0] if p.size() > 0 else Vector2.ZERO)
		return out
	var cum := _cum(p, closed)
	var total := cum[cum.size() - 1]
	var j := 0
	var denom := float(count) if closed else float(maxi(count - 1, 1))
	for k in count:
		var d := total * float(k) / denom
		while j < cum.size() - 2 and cum[j + 1] < d:
			j += 1
		var seg := maxf(cum[j + 1] - cum[j], 0.000001)
		var t := clampf((d - cum[j]) / seg, 0.0, 1.0)
		out.append(p[j % p.size()].lerp(p[(j + 1) % p.size()], t))
	return out

static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return a * 0.5

static func _centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v in p:
		c += v
	return c / maxf(p.size(), 1)

## B con el mismo sentido que A y girado para que su inicio case con el de A.
static func align(a: PackedVector2Array, b: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var bb := b.duplicate()
	if closed and signf(_area(a)) != signf(_area(bb)):
		bb.reverse()
	if not closed:
		# trazados abiertos: el sentido que acerque más los extremos
		if a[0].distance_to(bb[0]) + a[a.size() - 1].distance_to(bb[bb.size() - 1]) > \
				a[0].distance_to(bb[bb.size() - 1]) + a[a.size() - 1].distance_to(bb[0]):
			bb.reverse()
		return bb
	var ca := _centroid(a)
	var cb := _centroid(bb)
	var n := a.size()
	var best := 0
	var best_d := INF
	for s in n:
		var d := 0.0
		for i in range(0, n, 4):
			d += ((a[i] - ca) - (bb[(i + s) % n] - cb)).length_squared()
		if d < best_d:
			best_d = d
			best = s
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		out[i] = bb[(i + best) % n]
	return out

static func _lerp_pts(a: PackedVector2Array, b: PackedVector2Array, t: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(a.size())
	for i in a.size():
		out[i] = a[i].lerp(b[i], t)
	return out

## Punto y tangente a la fracción `f` de una polilínea.
static func _at(p: PackedVector2Array, cum: PackedFloat32Array, f: float) -> Array:
	var total := cum[cum.size() - 1]
	var d := clampf(f, 0.0, 1.0) * total
	for i in range(1, cum.size()):
		if cum[i] >= d:
			var seg := maxf(cum[i] - cum[i - 1], 0.000001)
			var q := p[i - 1].lerp(p[i % p.size()], (d - cum[i - 1]) / seg)
			return [q, (p[i % p.size()] - p[i - 1]).normalized()]
	return [p[p.size() - 1], (p[p.size() - 1] - p[maxi(p.size() - 2, 0)]).normalized()]

# ── crear / rehacer / expandir ───────────────────────────────────────────────
## Objetos clave de la fusión, en orden de la cadena (A → B → C …).
static func keys(g: Node2D) -> Array:
	var out: Array = []
	for c in g.get_children():
		if c is Node2D and c.has_meta(END_META):
			out.append(c)
	out.sort_custom(func(x, y) -> bool: return int(x.get_meta(END_META)) < int(y.get_meta(END_META)))
	return out

static func spine_of(g: Node2D) -> Node2D:
	for c in g.get_children():
		if c is Node2D and c.has_meta(SPINE_META):
			return c
	return null

## [primera clave, última clave, guía] (compatibilidad con la fusión de dos).
static func ends(g: Node2D) -> Array:
	var k := keys(g)
	return [k[0] if k.size() > 0 else null, k[-1] if k.size() > 1 else null, spine_of(g)]

static func params(g: Node2D) -> Dictionary:
	var p := DEFAULTS.duplicate()
	p.merge(g.get_meta(META, {}) as Dictionary, true)
	return p

static func _count(g: Node2D, a_pts: PackedVector2Array, b_pts: PackedVector2Array, spine_len: float) -> int:
	var p := params(g)
	if String(p["mode"]) == "distance":
		var dist := spine_len if spine_len > 0.0 else _centroid(a_pts).distance_to(_centroid(b_pts))
		return clampi(int(floor(dist / maxf(float(p["spacing"]), 0.5))) - 1, 0, 500)
	return clampi(int(p["steps"]), 0, 500)

## Firma de lo que define la fusión (A, B, guía, parámetros).
static func signature(g: Node2D) -> int:
	var e: Array = keys(g)
	e.append(spine_of(g))
	var parts: Array = [var_to_str(params(g))]
	for n in e:
		if n == null:
			parts.append(0)
			continue
		parts.append(outline(n))
		for k in ["fill_color", "stroke_color", "stroke_width"]:
			parts.append(n.get(k))
		if _has_grad(n):
			var gg: Gradient = n.get("fill_gradient")
			parts.append([gg.offsets, gg.colors, n.get("fill_gradient_type"), n.get("fill_gradient_angle"), n.get("fill_gradient_p0"), n.get("fill_gradient_p1")])
		parts.append(n.modulate)
	return hash(var_to_str(parts))

## Rehace los intermedios (sin historial).
static func rebuild(g: Node2D) -> void:
	if not is_instance_valid(g):
		return
	for c in g.get_children():
		if c.has_meta(STEP_META):
			g.remove_child(c)
			c.queue_free()
	# Cadena A → B → C …: intermedios entre cada par consecutivo de claves; la
	# guía (si la hay) se reparte a lo largo de TODA la cadena.
	var K := keys(g)
	var S: Node2D = spine_of(g)
	if K.size() < 2:
		return
	var closed := true
	for k in K:
		closed = closed and _closed(k)
	var spine := PackedVector2Array()
	var scum := PackedFloat32Array()
	if S != null:
		spine = outline(S)
		scum = _cum(spine, false)
	var spine_len: float = scum[scum.size() - 1] if scum.size() > 0 else 0.0
	var segs := K.size() - 1
	var orient := bool(params(g)["orient"])
	var prev := resample(outline(K[0]), SAMPLES, closed)
	for si in segs:
		var A: Node2D = K[si]
		var Bn: Node2D = K[si + 1]
		var pa := prev
		var pb := align(pa, resample(outline(Bn), SAMPLES, closed), closed)
		prev = pb
		var n := _count(g, pa, pb, spine_len / segs if spine_len > 0.0 else 0.0)
		var ca := _centroid(pa)
		var cb := _centroid(pb)
		for i in n:
			var lt := float(i + 1) / float(n + 1)
			var pts := _lerp_pts(pa, pb, lt)
			if spine.size() >= 2:
				var at: Array = _at(spine, scum, (float(si) + lt) / float(segs))
				var c_now := ca.lerp(cb, lt)
				var xf := Transform2D(0.0, at[0])
				if orient:
					xf = Transform2D((at[1] as Vector2).angle(), at[0])
				pts = xf * (Transform2D(0.0, -c_now) * pts)
			var grad := closed and (_has_grad(A) or _has_grad(Bn))
			var s: Node2D
			if grad:
				# Con DEGRADADO: polígono (VectorShape, que sí lo dibuja) con el
				# degradado interpolado entre las dos claves.
				var pg := VectorPolygon.new()
				pg.is_regular = false
				pg.vertices = pts
				_lerp_gradient(pg, A, Bn, lt)
				s = pg
			else:
				var curve := Curve2D.new()
				for v in pts:
					curve.add_point(v)
				var vp := VectorPath.new()
				vp.curve = curve
				vp.closed = closed
				s = vp
			s.name = "Paso %d-%d" % [si + 1, i + 1] if segs > 1 else "Paso %d" % (i + 1)
			s.fill_color = _get_col(A, "fill_color").lerp(_get_col(Bn, "fill_color"), lt)
			s.stroke_color = _get_col(A, "stroke_color").lerp(_get_col(Bn, "stroke_color"), lt)
			s.stroke_width = lerpf(float(A.get("stroke_width") if "stroke_width" in A else 0.0), float(Bn.get("stroke_width") if "stroke_width" in Bn else 0.0), lt)
			s.modulate.a = lerpf(A.modulate.a, Bn.modulate.a, lt)
			s.set_meta(STEP_META, si * 1000 + i)
			g.add_child(s)
			g.move_child(s, Bn.get_index())   # justo debajo de la clave siguiente
	g.set_meta("_blend_sig", signature(g))

static func _has_grad(n: Node) -> bool:
	return "fill_gradient" in n and n.get("fill_gradient") is Gradient and (n.get("fill_gradient") as Gradient).get_point_count() >= 2

## Degradado de `n` como Gradient (un color liso = degradado de ese color).
static func _grad_of(n: Node) -> Gradient:
	if _has_grad(n):
		return n.get("fill_gradient")
	var g := Gradient.new()
	var c := _get_col(n, "fill_color")
	g.set_color(0, c)
	g.set_color(1, c)
	return g

## Degradado del paso `t` entre A y B: paradas de los dos, colores mezclados;
## tipo, ángulo y puntos también interpolados.
static func _lerp_gradient(dst: Node, a: Node, b: Node, t: float) -> void:
	var ga := _grad_of(a)
	var gb := _grad_of(b)
	var offs: Array = []
	for g in [ga, gb]:
		for i in g.get_point_count():
			var o := snappedf(g.get_offset(i), 0.0001)
			if not offs.has(o):
				offs.append(o)
	offs.sort()
	var out := Gradient.new()
	out.offsets = PackedFloat32Array(offs)
	var cols := PackedColorArray()
	for o in offs:
		cols.append(ga.sample(o).lerp(gb.sample(o), t))
	out.colors = cols
	dst.fill_gradient = out
	var src_t: Node = a if (_has_grad(a) and (t < 0.5 or not _has_grad(b))) else b
	dst.fill_gradient_type = int(src_t.get("fill_gradient_type")) if "fill_gradient_type" in src_t else 0
	var aa: float = float(a.get("fill_gradient_angle")) if _has_grad(a) else float(b.get("fill_gradient_angle"))
	var ab: float = float(b.get("fill_gradient_angle")) if _has_grad(b) else aa
	dst.fill_gradient_angle = lerp_angle(aa, ab, t)
	var p0a: Vector2 = a.get("fill_gradient_p0") if _has_grad(a) else Vector2(-1, -1)
	var p0b: Vector2 = b.get("fill_gradient_p0") if _has_grad(b) else Vector2(-1, -1)
	var p1a: Vector2 = a.get("fill_gradient_p1") if _has_grad(a) else Vector2(-1, -1)
	var p1b: Vector2 = b.get("fill_gradient_p1") if _has_grad(b) else Vector2(-1, -1)
	if p0a != Vector2(-1, -1) and p0b != Vector2(-1, -1):
		dst.fill_gradient_p0 = p0a.lerp(p0b, t)
		dst.fill_gradient_p1 = p1a.lerp(p1b, t)
	elif p0a != Vector2(-1, -1) or p0b != Vector2(-1, -1):
		dst.fill_gradient_p0 = p0a if p0a != Vector2(-1, -1) else p0b
		dst.fill_gradient_p1 = p1a if p1a != Vector2(-1, -1) else p1b

static func _get_col(n: Node, k: String) -> Color:
	return n.get(k) if k in n and n.get(k) is Color else Color(0, 0, 0, 0)

## Crea la fusión de `a` y `b` (hermanos) con `opts`; `spine` opcional.
## Devuelve el grupo. El historial lo pone quien llama (API) con `recorder`.
static func make(a: Node2D, b: Node2D, opts: Dictionary = {}, spine: Node2D = null) -> Node2D:
	return make_chain([a, b], opts, spine)

## Fusión de VARIOS objetos (A → B → C …), en el orden de `objs` (la API y el
## menú los pasan de abajo arriba, como Illustrator). Todos hermanos.
static func make_chain(objs: Array, opts: Dictionary = {}, spine: Node2D = null) -> Node2D:
	if objs.size() < 2:
		return null
	var parent: Node = (objs[0] as Node).get_parent()
	for o in objs:
		if not (o is Node2D) or (o as Node).get_parent() != parent:
			return null
	if parent == null:
		return null
	var g := Node2D.new()
	g.name = "Fusión"
	g.set_meta("shape_type", "group")
	var p := DEFAULTS.duplicate()
	p.merge(opts, true)
	g.set_meta(META, p)
	var lo: int = objs.map(func(o) -> int: return (o as Node).get_index()).min()
	var do_fn := func() -> void:
		parent.add_child(g)
		parent.move_child(g, lo)
		var all: Array = objs.duplicate()
		if spine != null:
			all.append(spine)
		for n in all:
			n.get_parent().remove_child(n)
			g.add_child(n)
		for i in objs.size():
			(objs[i] as Node).set_meta(END_META, i)
		if spine:
			spine.set_meta(SPINE_META, true)
			g.move_child(spine, 0)
		g.add_to_group(GROUP)
		rebuild(g)
	var undo_fn := func() -> void:
		for c in g.get_children():
			if c.has_meta(STEP_META):
				g.remove_child(c)
				c.queue_free()
		var all: Array = [spine] + objs
		for n in all:
			if n != null and n.get_parent() == g:
				g.remove_child(n)
				parent.add_child(n)
				parent.move_child(n, mini(lo, parent.get_child_count() - 1))
				for m in [END_META, SPINE_META]:
					if n.has_meta(m):
						n.remove_meta(m)
		if g.get_parent():
			g.get_parent().remove_child(g)
	_commit("Fusión · crear", do_fn, undo_fn)
	return g

## Cambia parámetros (pasos, modo, separación, orientar) con deshacer.
static func set_params(g: Node2D, opts: Dictionary) -> void:
	var before: Dictionary = (g.get_meta(META) as Dictionary).duplicate()
	var after := before.duplicate()
	after.merge(opts, true)
	_commit("Fusión · ajustes", func() -> void:
		g.set_meta(META, after.duplicate())
		rebuild(g), func() -> void:
		g.set_meta(META, before.duplicate())
		rebuild(g))

## «Expandir»: los intermedios pasan a ser figuras normales; el grupo queda
## como grupo corriente.
static func expand(g: Node2D) -> void:
	var p: Dictionary = (g.get_meta(META) as Dictionary).duplicate()
	var marks: Array = []
	for c in g.get_children():
		for m in [STEP_META, END_META, SPINE_META]:
			if c.has_meta(m):
				marks.append([c, m, c.get_meta(m)])
	_commit("Fusión · expandir", func() -> void:
		for mk in marks:
			if is_instance_valid(mk[0]):
				mk[0].remove_meta(mk[1])
		g.remove_meta(META)
		g.remove_from_group(GROUP), func() -> void:
		for mk in marks:
			if is_instance_valid(mk[0]):
				mk[0].set_meta(mk[1], mk[2])
		g.set_meta(META, p.duplicate())
		g.add_to_group(GROUP))

## «Invertir orden»: la cadena va al revés (C → B → A); el apilado de las
## claves se respeta.
static func reverse(g: Node2D) -> void:
	var k := keys(g)
	if k.size() < 2:
		return
	var set_order := func(list: Array) -> void:
		for i in list.size():
			if is_instance_valid(list[i]):
				(list[i] as Node).set_meta(END_META, i)
		rebuild(g)
	var rev := k.duplicate()
	rev.reverse()
	_commit("Fusión · invertir orden", set_order.bind(rev), set_order.bind(k))

## «Soltar fusión»: quita los pasos y deja las claves (y la guía) sueltas
## donde estaba el grupo. Lo contrario de crearla.
static func release(g: Node2D) -> void:
	var parent := g.get_parent()
	if parent == null:
		return
	var p: Dictionary = (g.get_meta(META) as Dictionary).duplicate()
	var k := keys(g)
	var sp := spine_of(g)
	var at := g.get_index()
	var members: Array = ([sp] if sp else []) + k
	var marks: Array = []
	for n in members:
		for m in [END_META, SPINE_META]:
			if n.has_meta(m):
				marks.append([n, m, n.get_meta(m)])
	var do_fn := func() -> void:
		for c in g.get_children():
			if c.has_meta(STEP_META):
				g.remove_child(c)
				c.queue_free()
		var i := 0
		for n in members:
			if is_instance_valid(n) and n.get_parent() == g:
				g.remove_child(n)
				parent.add_child(n)
				parent.move_child(n, mini(at + i, parent.get_child_count() - 1))
				i += 1
		for mk in marks:
			if is_instance_valid(mk[0]) and mk[0].has_meta(mk[1]):
				mk[0].remove_meta(mk[1])
		g.remove_from_group(GROUP)
		if g.get_parent():
			g.get_parent().remove_child(g)
	var undo_fn := func() -> void:
		parent.add_child(g)
		parent.move_child(g, mini(at, parent.get_child_count() - 1))
		for n in members:
			if is_instance_valid(n) and n.get_parent():
				n.get_parent().remove_child(n)
				g.add_child(n)
		for mk in marks:
			if is_instance_valid(mk[0]):
				mk[0].set_meta(mk[1], mk[2])
		if sp:
			g.move_child(sp, 0)
		g.set_meta(META, p.duplicate())
		g.add_to_group(GROUP)
		rebuild(g)
	_commit("Fusión · soltar", do_fn, undo_fn)

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

# ── propiedades del inspector (InspectorCore pone el deshacer) ──────────────
const PROPS := ["blend_steps", "blend_mode", "blend_spacing", "blend_orient"]

static func handles(prop: String) -> bool:
	return PROPS.has(prop)

static func read_prop(n: Node, prop: String) -> Variant:
	if not is_blend(n):
		return null
	var p := params(n)
	match prop:
		"blend_steps": return float(p["steps"])
		"blend_mode": return String(p["mode"])
		"blend_spacing": return float(p["spacing"])
		"blend_orient": return bool(p["orient"])
	return null

static func write_prop(n: Node, prop: String, value: Variant) -> void:
	if not is_blend(n):
		return
	var p: Dictionary = (n.get_meta(META) as Dictionary).duplicate()
	match prop:
		"blend_steps": p["steps"] = clampi(int(round(float(value))), 0, 500)
		"blend_mode": p["mode"] = "distance" if String(value) == "distance" else "steps"
		"blend_spacing": p["spacing"] = maxf(0.5, float(value))
		"blend_orient": p["orient"] = bool(value)
	n.set_meta(META, p)
	rebuild(n)

# ── sincronización automática ────────────────────────────────────────────────
## Tras cada paso del historial (HistoryManager): rehacer las fusiones cuyos
## extremos cambiaron. En diferido, una vez por fotograma.
static func on_history_step() -> void:
	if _busy or _tree() == null or _tree().get_nodes_in_group(GROUP).is_empty():
		return
	if not _scheduled:
		_scheduled = true
		(func() -> void:
			_scheduled = false
			sync_now()).call_deferred()

static func sync_now() -> int:
	if _tree() == null:
		return 0
	_busy = true
	var n := 0
	for g in _tree().get_nodes_in_group(GROUP):
		if not is_blend(g):
			continue
		if int(g.get_meta("_blend_sig", 0)) == -1:
			g.set_meta("_blend_sig", signature(g))   # recién abierta: ya trae sus pasos
			continue
		if int(g.get_meta("_blend_sig", 0)) != signature(g):
			rebuild(g)
			n += 1
	_busy = false
	return n

## Al abrir un documento: los grupos con meta "blend" vuelven al grupo de
## sincronización (los intermedios ya vienen guardados).
static func adopt(g: Node) -> void:
	if is_blend(g):
		g.add_to_group(GROUP)
		g.set_meta("_blend_sig", -1)
