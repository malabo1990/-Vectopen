# =============================================================================
# RUTA: res://script_gdscript/text/text_fx.gd
# EFECTOS DEL PANEL "EFECTOS" APLICADOS A TEXTOS (título y párrafo).
# Antes se guardaban en el meta "effects" del texto pero no se dibujaba nada.
#
# Un nodo controlador ("TextFx") por texto con efectos crea capas hermanas
# del editor nativo / label:
#   detrás  (TextFxBack):  sombra (CanvasGroup + desenfoque GPU), 3D, contorno
#   delante (TextFxFront): sombra / brillo interior (recortados a las letras),
#                          desenfoque, superposición de color y de degradado
# La geometría son los polígonos de los glifos del overlay vectorial
# (WorldTextLabel), que ya están en caché: dibujar cuesta muy poco y solo se
# repinta cuando cambian el texto, los efectos o el zoom (para el desenfoque).
# =============================================================================
extends Node

const NAME := "TextFx"
const BLUR_SHADER := "res://shaders/text_fx_blur.gdshader"
const INNER_SHADER := "res://shaders/text_fx_inner.gdshader"
const OUTLINE_SHADER := "res://shaders/text_fx_outline.gdshader"

var shape: Node2D = null
var _back: Node2D = null
var _front: Node2D = null
var _sig := ""
var _zoom := -1.0
var _polys_ref: Array = []
var _hid_label := false

# ── API ─────────────────────────────────────────────────────────────────────
## Crea / actualiza / quita los efectos del texto según su meta "effects".
static func sync(s: Node2D) -> void:
	if not is_instance_valid(s):
		return
	var node = s.get_node_or_null(NAME)
	if enabled_effects(s).is_empty():
		if node:
			node.teardown()
			# Fuera del árbol YA: si no, un sync en el mismo frame lo reutilizaría
			# moribundo (queue_free) y el efecto nuevo desaparecería al final.
			s.remove_child(node)
			node.queue_free()
		return
	if node == null:
		node = load("res://script_gdscript/text/text_fx.gd").new()
		node.name = NAME
		node.shape = s
		s.add_child(node)
	node.shape = s
	node.refresh(true)

static func canonical(t: String) -> String:
	var n := t.to_lower().replace(" ", "_")
	return "3d" if n == "threed" else n

static func enabled_effects(s: Node2D) -> Array:
	var raw = s.get_meta("effects", []) if s.has_meta("effects") else []
	var out: Array = []
	if raw is Array:
		for fx in raw:
			if fx is Dictionary and bool(fx.get("enabled", true)):
				out.append(fx)
	return out

# ── ciclo ───────────────────────────────────────────────────────────────────
func _ready() -> void:
	if shape == null:
		shape = get_parent() as Node2D
	refresh(true)

func _process(_dt: float) -> void:
	refresh(false)
	_update_centers()
	if _bake_at > 0 and Time.get_ticks_msec() >= _bake_at and not _baking:
		_bake_at = 0
		_bake()

func teardown() -> void:
	_unbake()
	_bake_at = 0
	for n in [_back, _front]:
		if is_instance_valid(n):
			if n.get_parent():
				n.get_parent().remove_child(n)
			n.queue_free()
	_back = null
	_front = null
	_restore_label()

func _exit_tree() -> void:
	# Si el texto se borra, las capas se van con él (son hermanas).
	pass

## Repinta si cambió algo: glifos (texto/formato) o efectos. Un cambio SOLO
## de zoom no redibuja nada: únicamente actualiza el radio del desenfoque
## (los polígonos están en espacio del texto). Antes cada paso de zoom
## redibujaba todas las capas de todos los textos (163 ms/frame con 100).
var _fx_ref = null
var _xf_ref := Transform2D()

func refresh(force: bool) -> void:
	if not is_instance_valid(shape):
		return
	var dl = shape.get_node_or_null("DisplayLabel")
	if dl == null or not dl.has_method("_get_triangle_polys"):
		return
	var polys: Array = dl._get_triangle_polys()
	var raw = shape.get_meta("effects", null)
	var z := shape.get_global_transform_with_canvas().get_scale().x
	var fx_changed := force or not is_same(raw, _fx_ref)
	var fx: Array = []
	if fx_changed:
		fx = enabled_effects(shape)
		var sig := var_to_str(fx)
		fx_changed = force or sig != _sig
		_sig = sig
		_fx_ref = raw
	var xf := _glyph_xform(dl)
	var geom_changed := not is_same(polys, _polys_ref) or not xf.is_equal_approx(_xf_ref)
	var zoom_changed := not is_equal_approx(z, _zoom)
	if not fx_changed and not geom_changed and not zoom_changed:
		return
	_polys_ref = polys
	_xf_ref = xf
	_zoom = z
	if fx_changed:
		_build_layers(enabled_effects(shape))
	if fx_changed or zoom_changed:
		_update_uniforms(fx)
	if fx_changed or geom_changed:
		_redraw_all()
	# Horneado: tras unos instantes sin cambios, cada CanvasGroup (sombra,
	# desenfoque, interiores) se renderiza UNA vez a textura. Un zoom grande
	# (×1,5) lo rehace con la resolución adecuada.
	if fx_changed or geom_changed:
		_unbake()
		_bake_at = Time.get_ticks_msec() + BAKE_DELAY_MS
	elif _baked_zoom > 0.0 and (z / _baked_zoom > 1.5 or _baked_zoom / z > 1.5):
		# Zoom: se sigue mostrando la textura horneada (escalada) y se
		# rehornea a la nueva resolución al parar. Volver a en vivo durante el
		# zoom costaba ~0,3 ms por texto y frame.
		_bake_at = Time.get_ticks_msec() + BAKE_DELAY_MS

# ── capas ───────────────────────────────────────────────────────────────────
func _ensure_layer(nm: String, front: bool) -> Node2D:
	var n := shape.get_node_or_null(nm) as Node2D
	if n == null:
		n = Node2D.new()
		n.name = nm
		shape.add_child(n)
	# Detrás de todo (antes del editor / label) o delante de todo.
	if front:
		shape.move_child(n, shape.get_child_count() - 1)
	else:
		shape.move_child(n, 0)
	return n

func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

func _build_layers(fx: Array) -> void:
	_back = _ensure_layer("TextFxBack", false)
	_front = _ensure_layer("TextFxFront", true)
	_clear(_back)
	_clear(_front)
	var hide_label := false
	for e in fx:
		var t := canonical(String(e.get("type", "")))
		match t:
			"drop_shadow":
				var g := _group(_back, BLUR_SHADER, e)
				_drawer(g, "glyphs_offset", e)
			"3d":
				# Extrusión exterior opcional + relieve interior (bisel): brillo
				# en los bordes del lado de la luz y sombra en el opuesto.
				if bool(e.get("extrude", true)):
					_drawer(_back, "extrude", e)
				var bev := float(e.get("bevel", 8.0))
				if bev > 0.2:
					var ang := deg_to_rad(float(e.get("angle", 45.0)))
					var dir := Vector2(cos(ang), sin(ang))
					for role in ["hi", "lo"]:
						var gb := _group(_front, INNER_SHADER, e)
						gb.set_meta("bevel_role", role)
						var add3 := CanvasItemMaterial.new()
						add3.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
						var m1 := _drawer(gb, "mask", e)
						m1.material = add3
						var m2 := _drawer(gb, "mask_offset", e)
						m2.material = add3
						m2.set_meta("off", dir * bev * (0.5 if role == "hi" else -0.5))
			"outline":
				var go := _group(_back, OUTLINE_SHADER, e)
				_drawer(go, "mask", e).material = null
				go.get_child(0).set_meta("kind", "mask_alpha")
			"inner_shadow", "inner_glow":
				# Letras en ROJO + letras desplazadas en VERDE (aditivo) → el
				# shader calcula dentro × (1 − desplazada desenfocada).
				var g := _group(_front, INNER_SHADER, e)
				var add := CanvasItemMaterial.new()
				add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				var d1 := _drawer(g, "mask", e)
				d1.material = add
				var d2 := _drawer(g, "mask_offset", e)
				d2.material = add
			"blur":
				var g := _group(_front, BLUR_SHADER, e)
				_drawer(g, "glyphs_color", e)
				hide_label = true
			"color_overlay":
				_drawer(_front, "color_overlay", e)
			"gradient_overlay":
				_drawer(_front, "gradient_overlay", e)
	if hide_label:
		_hide_label()
	else:
		_restore_label()

func _group(parent: Node, shader_path: String, e: Dictionary) -> CanvasGroup:
	var g := CanvasGroup.new()
	g.use_mipmaps = true   # desenfoques grandes: se muestrea un mip suavizado
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	g.material = m
	g.set_meta("fx", e)
	parent.add_child(g)
	return g

func _drawer(parent: Node, kind: String, e: Dictionary, on: Node2D = null) -> Node2D:
	var d: Node2D = on
	if d == null:
		d = Node2D.new()
		parent.add_child(d)
	d.set_meta("kind", kind)
	d.set_meta("fx", e)
	d.draw.connect(_draw_kind.bind(d))
	return d

func _update_uniforms(fx: Array) -> void:
	for layer in [_back, _front]:
		if not is_instance_valid(layer):
			continue
		for g in layer.find_children("*", "CanvasGroup", true, false):
			var e: Dictionary = g.get_meta("fx", {})
			var m := g.material as ShaderMaterial
			var t := canonical(String(e.get("type", "")))
			var radius := 0.0
			match t:
				"drop_shadow":
					radius = float(e.get("blur", 6.0))
					m.set_shader_parameter("u_use_tint", true)
					m.set_shader_parameter("u_tint", _col(e.get("color"), Color(0, 0, 0, 0.4)))
				"blur":
					radius = float(e.get("radius", 5.0))
					m.set_shader_parameter("u_use_tint", false)
					var bt: int = maxi(0, ["gaussian", "motion", "radial", "spin"].find(String(e.get("blur_type", "gaussian"))))
					var ba := deg_to_rad(float(e.get("angle", 0.0)))
					m.set_shader_parameter("u_type", bt)
					m.set_shader_parameter("u_dir", Vector2(cos(ba), sin(ba)))
					m.set_shader_parameter("u_zoom_k", float(e.get("radius", 5.0)) / 50.0)
					m.set_shader_parameter("u_spin", deg_to_rad(float(e.get("radius", 5.0))))
					g.set_meta("needs_center", bt >= 2)
				"inner_shadow":
					radius = maxf(0.5, float(e.get("blur", 4.0)))
					m.set_shader_parameter("u_color", _col(e.get("color"), Color(0, 0, 0, 0.5)))
				"3d":
					var role := String(g.get_meta("bevel_role", "hi"))
					radius = maxf(0.5, float(e.get("bevel", 8.0)) * 0.5)
					if role == "hi":
						m.set_shader_parameter("u_color", Color(1, 1, 1, 0.85 * clampf(float(e.get("highlight", 70.0)) / 100.0, 0.0, 1.0)))
					else:
						m.set_shader_parameter("u_color", Color(0, 0, 0, 0.75 * clampf(float(e.get("shadow", 60.0)) / 100.0, 0.0, 1.0)))
				"outline":
					radius = maxf(0.5, float(e.get("width", 2.0)))
					m.set_shader_parameter("u_color", _col(e.get("color"), Color.BLACK))
				"inner_glow":
					radius = maxf(0.5, float(e.get("radius", 8.0)))
					var c := _col(e.get("color"), Color.WHITE)
					c.a *= clampf(float(e.get("opacity", 1.0)), 0.0, 1.0)
					m.set_shader_parameter("u_color", c)
			m.set_shader_parameter("u_radius", radius * _zoom)
			g.fit_margin = radius * 2.0 + 4.0
			if t == "blur" and String(e.get("blur_type", "gaussian")) in ["radial", "spin"]:
				g.fit_margin = 160.0   # el arrastre radial / giratorio sale lejos
			g.clear_margin = g.fit_margin

func _redraw_all() -> void:
	for layer in [_back, _front]:
		if not is_instance_valid(layer):
			continue
		for n in layer.find_children("*", "Node2D", true, false):
			if n.has_meta("kind"):
				(n as Node2D).queue_redraw()

## Desenfoque radial / giratorio: centro del texto en UV de pantalla (cambia
## al desplazar la vista). Solo para los grupos que lo usan y en vivo.
func _update_centers() -> void:
	if not is_instance_valid(_front) or not is_instance_valid(shape):
		return
	var vp := shape.get_viewport()
	if vp == null:
		return
	var vs := vp.get_visible_rect().size
	var c_local := Vector2(float(shape.get_meta("width", 0.0)), float(shape.get_meta("height", 0.0))) * 0.5
	var c_screen: Vector2 = shape.get_global_transform_with_canvas() * c_local
	for g in _front.find_children("*", "CanvasGroup", true, false):
		if g.get_meta("needs_center", false) and g.visible:
			(g.material as ShaderMaterial).set_shader_parameter("u_center", c_screen / vs)

# ── horneado a textura ───────────────────────────────────────────────────────
const BAKE_DELAY_MS := 300
var _bake_at := 0
var _baking := false
var _baked_zoom := 0.0
var _baked: Array = []   # [{group, sprite}]

func _unbake() -> void:
	for b in _baked:
		if is_instance_valid(b["sprite"]):
			b["sprite"].queue_free()
		if is_instance_valid(b["group"]):
			b["group"].visible = true
	_baked.clear()
	_baked_zoom = 0.0

## Rect (espacio del texto) que ocupa el contenido de un grupo + su margen.
func _group_rect(g: CanvasGroup, dl) -> Rect2:
	var xf := _glyph_xform(dl)
	var r := Rect2()
	var first := true
	for p in dl._get_triangle_polys():
		for v in p["poly"]:
			var w: Vector2 = xf * v
			if first:
				r = Rect2(w, Vector2.ZERO)
				first = false
			else:
				r = r.expand(w)
	var e: Dictionary = g.get_meta("fx", {})
	var off := Vector2(float(e.get("offset_x", 0.0)), float(e.get("offset_y", 0.0)))
	if canonical(String(e.get("type", ""))) == "drop_shadow":
		r = r.merge(Rect2(r.position + off, r.size))
	var radius := maxf(float(e.get("blur", 0.0)), float(e.get("radius", 0.0)))
	if canonical(String(e.get("type", ""))) == "3d":
		radius = float(e.get("bevel", 8.0))
	elif canonical(String(e.get("type", ""))) == "outline":
		radius = float(e.get("width", 2.0))
	var bt := String(e.get("blur_type", "gaussian"))
	if bt == "radial":
		return r.grow(r.size.length() * 0.5 * radius / 50.0 + 6.0)
	if bt == "spin":
		return r.grow(r.size.length() * 0.5 + 6.0)
	return r.grow(radius * 2.0 + maxf(0.0, float(e.get("spread", 0.0))) + 4.0)

func _bake() -> void:
	if not is_instance_valid(shape) or not is_inside_tree():
		return
	var dl = shape.get_node_or_null("DisplayLabel")
	if dl == null:
		return
	var groups: Array = []
	for layer in [_back, _front]:
		if is_instance_valid(layer):
			groups += layer.find_children("*", "CanvasGroup", true, false)
	if groups.is_empty():
		return
	_baking = true
	var old: Array = _baked.duplicate()
	_baked.clear()
	var z := maxf(0.05, shape.get_global_transform_with_canvas().get_scale().x)
	var sc := clampf(z * 1.25, 1.0, 4.0)     # px de textura por unidad del texto
	var jobs: Array = []
	for g in groups:
		var rect := _group_rect(g, dl)
		var px := Vector2i(ceili(rect.size.x * sc), ceili(rect.size.y * sc))
		if px.x < 2 or px.y < 2 or px.x * px.y > 4096 * 4096:
			continue
		var vp := SubViewport.new()
		vp.size = px
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var root := Node2D.new()
		root.transform = Transform2D(0.0, Vector2(sc, sc), 0.0, -rect.position * sc)
		vp.add_child(root)
		var cg := CanvasGroup.new()
		var m := (g.material as ShaderMaterial).duplicate() as ShaderMaterial
		m.set_shader_parameter("u_radius", float(m.get_shader_parameter("u_radius")) / maxf(_zoom, 0.0001) * sc)
		if g.get_meta("needs_center", false):
			var cl := Vector2(float(shape.get_meta("width", 0.0)), float(shape.get_meta("height", 0.0))) * 0.5
			m.set_shader_parameter("u_center", (cl - rect.position) / rect.size)
		cg.material = m
		cg.use_mipmaps = true
		cg.fit_margin = g.fit_margin
		cg.clear_margin = g.clear_margin
		root.add_child(cg)
		for d in g.get_children():
			if d is Node2D and d.has_meta("kind"):
				var nd := Node2D.new()
				nd.set_meta("kind", d.get_meta("kind"))
				nd.set_meta("fx", d.get_meta("fx"))
				if d.has_meta("off"):
					nd.set_meta("off", d.get_meta("off"))
				nd.material = d.material
				nd.draw.connect(_draw_kind.bind(nd))
				cg.add_child(nd)
		add_child(vp)
		jobs.append({"group": g, "vp": vp, "rect": rect, "sc": sc})
	await RenderingServer.frame_post_draw
	for j in jobs:
		var vp: SubViewport = j["vp"]
		var g: CanvasGroup = j["group"]
		if is_instance_valid(g) and is_instance_valid(vp):
			var img := vp.get_texture().get_image()
			var tex := ImageTexture.create_from_image(img)
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = false
			spr.position = j["rect"].position
			spr.scale = Vector2.ONE / float(j["sc"])
			var pm := CanvasItemMaterial.new()
			pm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
			spr.material = pm
			g.get_parent().add_child(spr)
			g.get_parent().move_child(spr, g.get_index())
			g.visible = false
			_baked.append({"group": g, "sprite": spr})
		if is_instance_valid(vp):
			vp.queue_free()
	for b in old:
		if is_instance_valid(b["sprite"]):
			b["sprite"].queue_free()
	_baked_zoom = z
	_baking = false

# ── ocultar el texto original (desenfoque) ──────────────────────────────────
func _visible_text_nodes() -> Array:
	var out: Array = []
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		out.append(vrt)
	else:
		var dl = shape.get_node_or_null("DisplayLabel")
		if dl:
			out.append(dl)
	return out

func _hide_label() -> void:
	if _hid_label:
		return
	for n in _visible_text_nodes():
		n.set_meta("fx_prev_alpha", n.self_modulate.a)
		n.self_modulate.a = 0.0
	_hid_label = true

func _restore_label() -> void:
	if not _hid_label or not is_instance_valid(shape):
		return
	for n in _visible_text_nodes():
		if n.has_meta("fx_prev_alpha"):
			n.self_modulate.a = float(n.get_meta("fx_prev_alpha"))
			n.remove_meta("fx_prev_alpha")
	_hid_label = false

# ── dibujo ──────────────────────────────────────────────────────────────────
static func _col(v, def: Color) -> Color:
	if v is Color:
		return v
	if v is String:
		return Color.from_string(v, def)
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return def

## Transformación de los polígonos del overlay al espacio del texto.
func _glyph_xform(dl) -> Transform2D:
	var k := float(maxi(1, dl.get_theme_font_size("font_size"))) / float(maxi(1, int(dl.get("_outline_fs"))))
	return dl.get_transform() * Transform2D(0.0, Vector2(k, k), 0.0, Vector2.ZERO)

func _text_color(dl) -> Color:
	if shape.has_meta("text_color") and shape.get_meta("text_color") is Color:
		return shape.get_meta("text_color")
	return dl.get_theme_color("font_color") if dl.has_method("get_theme_color") else Color.BLACK

func _draw_kind(d: Node2D) -> void:
	if not is_instance_valid(shape):
		return
	var dl = shape.get_node_or_null("DisplayLabel")
	if dl == null:
		return
	var polys: Array = dl._get_triangle_polys()
	if polys.is_empty():
		return
	var e: Dictionary = d.get_meta("fx", {})
	var kind := String(d.get_meta("kind"))
	var xf := _glyph_xform(dl)
	var k := xf.get_scale().x
	match kind:
		"glyphs_offset":   # sombra: glifos desplazados (+ extensión)
			var off := Vector2(float(e.get("offset_x", 4.0)), float(e.get("offset_y", 4.0)))
			d.draw_set_transform_matrix(Transform2D(0.0, off) * xf)
			for p in polys:
				d.draw_colored_polygon(p["poly"], Color.WHITE)
			var spread := float(e.get("spread", 0.0))
			if spread > 0.05:
				_stroke_all(d, dl, Color.WHITE, spread * 2.0 / k)
		"mask_alpha":
			d.draw_set_transform_matrix(xf)
			for p in polys:
				d.draw_colored_polygon(p["poly"], Color.WHITE)
		"mask":
			d.draw_set_transform_matrix(xf)
			for p in polys:
				d.draw_colored_polygon(p["poly"], Color(1, 0, 0, 1))
		"mask_offset":
			var off2 := Vector2.ZERO
			if d.has_meta("off"):
				off2 = d.get_meta("off")
			elif canonical(String(e.get("type", ""))) == "inner_shadow":
				off2 = Vector2(float(e.get("offset_x", 2.0)), float(e.get("offset_y", 2.0)))
			d.draw_set_transform_matrix(Transform2D(0.0, off2) * xf)
			for p in polys:
				d.draw_colored_polygon(p["poly"], Color(0, 1, 0, 1))
		"glyphs_color":    # desenfoque: el texto con sus colores
			d.draw_set_transform_matrix(xf)
			var runs: Array = dl._effective_runs() if dl.has_method("_effective_runs") else []
			var base := _text_color(dl)
			for p in polys:
				var ri := int(p.get("run", 0))
				var c := base
				if ri >= 0 and ri < runs.size() and runs[ri] is Dictionary and runs[ri].has("color"):
					c = runs[ri]["color"]
				d.draw_colored_polygon(p["poly"], c)
		"outline":
			var w := maxf(0.5, float(e.get("width", 2.0)))
			_stroke_all(d, dl, _col(e.get("color"), Color.BLACK), w * 2.0 / k, xf)
		"color_overlay":
			var c2 := _col(e.get("color"), Color.RED)
			c2.a *= clampf(float(e.get("opacity", 1.0)), 0.0, 1.0)
			d.draw_set_transform_matrix(xf)
			for p in polys:
				d.draw_colored_polygon(p["poly"], c2)
		"gradient_overlay":
			_draw_gradient(d, polys, e, xf)
		"extrude":
			_draw_extrude(d, dl, polys, e, xf)

func _stroke_all(d: Node2D, dl, col: Color, width_local: float, xf = null) -> void:
	if xf != null:
		d.draw_set_transform_matrix(xf)
	for s in dl._get_stroke_polys():
		for c in s.get("contours", []):
			var ring := PackedVector2Array(c)
			if ring.size() < 2:
				continue
			ring.append(ring[0])
			d.draw_polyline(ring, col, width_local, true)

func _bbox(polys: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for p in polys:
		for v in p["poly"]:
			if first:
				r = Rect2(v, Vector2.ZERO)
				first = false
			else:
				r = r.expand(v)
	return r

## Textura del degradado (ángulo incluido) generada aquí y cacheada:
## GradientTexture2D se rellena en diferido y el primer dibujo salía blanco.
static var _grad_cache: Dictionary = {}

static func _gradient_texture(e: Dictionary) -> Texture2D:
	var cols = e.get("colors", [])
	var offs = e.get("offsets", [])
	var key := var_to_str([cols, offs, float(e.get("angle", 0.0))])
	if _grad_cache.has(key):
		return _grad_cache[key]
	var g := Gradient.new()
	if cols is Array and cols.size() >= 2:
		g.colors = PackedColorArray(cols.map(func(c): return _col(c, Color.BLACK)))
		g.offsets = PackedFloat32Array(offs) if offs is Array and offs.size() == cols.size() else PackedFloat32Array([0.0, 1.0])
	else:
		g.colors = PackedColorArray([Color(0.95, 0.3, 0.2), Color(0.25, 0.3, 0.95)])
	var a := deg_to_rad(float(e.get("angle", 0.0)))
	var dir := Vector2(cos(a), sin(a))
	# Proyección máxima de las esquinas: el degradado cubre toda la caja.
	var span := absf(dir.x) + absf(dir.y)
	const N := 64
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var p := Vector2((x + 0.5) / N - 0.5, (y + 0.5) / N - 0.5)
			img.set_pixel(x, y, g.sample(clampf(p.dot(dir) / span + 0.5, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	if _grad_cache.size() > 64:
		_grad_cache.clear()
	_grad_cache[key] = tex
	return tex

func _draw_gradient(d: Node2D, polys: Array, e: Dictionary, xf: Transform2D) -> void:
	var tex := _gradient_texture(e)
	var bb := _bbox(polys)
	var op := clampf(float(e.get("opacity", 1.0)), 0.0, 1.0)
	d.draw_set_transform_matrix(xf)
	for p in polys:
		var pts: PackedVector2Array = p["poly"]
		var uvs := PackedVector2Array()
		uvs.resize(pts.size())
		for i in pts.size():
			uvs[i] = (pts[i] - bb.position) / Vector2(maxf(bb.size.x, 0.001), maxf(bb.size.y, 0.001))
		d.draw_colored_polygon(pts, Color(1, 1, 1, op), uvs, tex)

## Extrusión 3D: malla con paredes iluminadas y degradado de profundidad
## (script_gdscript/shapes/fx_extrude.gd). Antes: copias oscuras apiladas,
## que se veían como una sombra. La malla se cachea por glifos + parámetros.
func _draw_extrude(d: Node2D, dl, polys: Array, e: Dictionary, xf: Transform2D) -> void:
	var key := [polys, var_to_str(e), xf]
	var cached = d.get_meta("mesh_key", null)
	var mesh: ArrayMesh = d.get_meta("mesh", null) if cached != null and is_same(cached[0], polys) and cached[1] == key[1] and (cached[2] as Transform2D).is_equal_approx(xf) else null
	if mesh == null:
		var contours: Array = []
		for st in dl._get_stroke_polys():
			for c in st.get("contours", []):
				contours.append(xf * PackedVector2Array(c))
		var caps: Array = []
		for p in polys:
			caps.append(xf * PackedVector2Array(p["poly"]))
		mesh = load("res://script_gdscript/shapes/fx_extrude.gd").build(contours, caps, e, _text_color(dl))
		d.set_meta("mesh", mesh)
		d.set_meta("mesh_key", key)
	if mesh:
		d.draw_set_transform_matrix(Transform2D())
		d.draw_mesh(mesh, null)
