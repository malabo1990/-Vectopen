# =============================================================================
# RUTA: res://script_gdscript/shapes/vector_light.gd
# LUZ 2D (informe de propuestas §2): objeto del documento que ilumina la
# página con las luces 2D de Godot.
#   · tipo: "point" (radial, desde un punto) o "directional" (como el sol);
#   · color, intensidad, radio (alcance), ángulo (dirección), caída (dureza
#     del borde: 0 suave … 1 dura), modo: sumar / mezclar / restar;
#   · sombras dinámicas: las figuras de la página proyectan sombra (se les
#     pone un oclusor interno con su contorno, que se rehace al cambiarlas).
# Se guarda en el .vtp (kind "light") y sale en PNG/JPEG/WEBP (la copia de
# exportación la vuelve a crear). SVG/PDF no tienen luces: no salen ahí.
# El símbolo (sol / flecha y su alcance) solo se dibuja en el lienzo.
# =============================================================================
extends Node2D

const GROUP := "_vectopen_lights"
const OCC_NAME := "_LightOccluder"
## Tipos de luz (registro: añadir aquí los futuros, con su etiqueta y si
## usan alcance / dirección / apertura). El panel y el inspector lo leen.
const TYPES := ["point", "spot", "directional", "ambient"]
const TYPE_INFO := {
	"point": {"label": "Puntual", "radius": true, "angle": false, "cone": false, "shadows": true},
	"spot": {"label": "Foco", "radius": true, "angle": true, "cone": true, "shadows": true},
	"directional": {"label": "Direccional (sol)", "radius": false, "angle": true, "cone": false, "shadows": true},
	"ambient": {"label": "Ambiente", "radius": false, "angle": false, "cone": false, "shadows": false},
}
const CAST_META := "casts_shadow"   # false en un objeto = no proyecta sombra
## Capa de iluminación del CONTENIDO del documento: las luces solo alumbran
## lo que la tiene (la página y sus objetos). La caja de selección, los
## tiradores y el resto del editor no → no se tiñen (antes el azul salía cian).
const DOC_LIGHT_BIT := 2
const MODES := {"add": Light2D.BLEND_MODE_ADD, "mix": Light2D.BLEND_MODE_MIX, "sub": Light2D.BLEND_MODE_SUB}

var lamp_type := "point":
	set(v):
		lamp_type = v if v in TYPES else "point"
		rebuild()
var lamp_color := Color(1.0, 0.92, 0.75):
	set(v):
		lamp_color = v
		rebuild()
var lamp_energy := 1.0:
	set(v):
		lamp_energy = clampf(v, 0.0, 16.0)
		rebuild()
var lamp_radius := 300.0:
	set(v):
		lamp_radius = clampf(v, 4.0, 20000.0)
		rebuild()
var lamp_angle := 45.0:      # grados (dirección de la luz direccional)
	set(v):
		lamp_angle = wrapf(v, -180.0, 180.0)
		rebuild()
var lamp_falloff := 0.0:     # 0 = borde muy suave · 1 = duro
	set(v):
		lamp_falloff = clampf(v, 0.0, 1.0)
		rebuild()
var lamp_mode := "add":
	set(v):
		lamp_mode = v if MODES.has(v) else "add"
		rebuild()
var lamp_shadows := true:
	set(v):
		lamp_shadows = v
		rebuild()
var lamp_cone := 45.0:       # apertura del foco (grados)
	set(v):
		lamp_cone = clampf(v, 5.0, 170.0)
		rebuild()
var lamp_shadow_color := Color(0, 0, 0, 0.85):
	set(v):
		lamp_shadow_color = v
		rebuild()
var lamp_shadow_soft := 0.3:  # 0 = sombra nítida · 1 = muy difuminada
	set(v):
		lamp_shadow_soft = clampf(v, 0.0, 1.0)
		rebuild()
var lamp_shadow_length := 150.0:   # px que se alarga la sombra
	set(v):
		lamp_shadow_length = clampf(v, 0.0, 20000.0)
		rebuild()
var lamp_height := 0.5:   # altura de la luz: 0 = rasante (sombras largas) · 1 = cenital (cortas)
	set(v):
		lamp_height = clampf(v, 0.0, 1.0)
		rebuild()
var lamp_shadow_fade := 0.7:   # 0 = sombra uniforme · 1 = se desvanece del todo hacia su final
	set(v):
		lamp_shadow_fade = clampf(v, 0.0, 1.0)
		rebuild()

var _light: Light2D = null
static var _tex_cache := {}

func _init() -> void:
	name = "Luz"
	set_meta("shape_type", "light")

## Ajustes de fábrica (botón «Restablecer» del panel).
const DEFAULTS := {"color": Color(1.0, 0.92, 0.75), "energy": 1.2, "radius": 300.0, "angle": 45.0,
	"cone": 45.0, "falloff": 0.0, "mode": "add", "shadows": true, "shadow_color": Color(0, 0, 0, 0.6),
	"shadow_soft": 0.3, "shadow_length": 150.0, "shadow_fade": 0.7, "height": 0.5}

## Firma de lo que mueve las sombras (esta luz y la posición de las figuras):
## si cambia —arrastrar la luz o una figura, el panel, los tiradores— las
## sombras se rehacen en ese mismo fotograma (tiempo real).
var _light_sig := 0
var _shapes_sig := 0
var _sig_tick := 0

func _process(_d: float) -> void:
	if not _on_canvas():
		return
	var page := _page()
	if page == null:
		return
	var changed := false
	var ls := hash([global_transform, params(), visible])
	if ls != _light_sig:
		_light_sig = ls
		changed = true
	_sig_tick += 1
	if changed or _sig_tick % 2 == 0:   # figuras: cada 2 fotogramas basta
		var parts: Array = []
		for sh in _shapes_under(page):
			parts.append((sh as Node2D).global_transform)
		var ss := hash(parts)
		if ss != _shapes_sig:
			_shapes_sig = ss
			changed = true
	if changed:
		refresh_occluders()

func _ready() -> void:
	add_to_group(GROUP)
	light_mask = 0   # el símbolo y la caja de la luz no se iluminan a sí mismos
	rebuild()
	# al abrir un documento la luz puede cargarse antes que las figuras:
	# los oclusores se calculan otra vez cuando la página ya está completa
	(func() -> void:
		await get_tree().process_frame
		if is_inside_tree():
			var pg := _page()
			if pg:
				mark_content(pg)
			refresh_occluders()).call_deferred()

func params() -> Dictionary:
	return {"type": lamp_type, "color": lamp_color, "energy": lamp_energy, "radius": lamp_radius,
		"angle": lamp_angle, "falloff": lamp_falloff, "mode": lamp_mode, "shadows": lamp_shadows,
		"cone": lamp_cone, "shadow_color": lamp_shadow_color, "shadow_soft": lamp_shadow_soft,
		"shadow_length": lamp_shadow_length, "shadow_fade": lamp_shadow_fade,
		"height": lamp_height}

func set_params(p: Dictionary) -> void:
	for k in p:
		if ("lamp_" + String(k)) in self:
			set("lamp_" + String(k), p[k])

## Cono del foco: radial recortado a `cone` grados hacia +X (la luz se gira).
static func _cone_tex(falloff: float, cone: float) -> Texture2D:
	# variantes cada 2° y 128 px: generar 256² píxeles en GDScript al cambiar
	# la apertura costaba decenas de ms por fotograma
	var key := "cone_%.2f_%d" % [snappedf(falloff, 0.1), int(cone / 2.0) * 2]
	if _tex_cache.has(key):
		return _tex_cache[key]
	cone = float(int(cone / 2.0) * 2)
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var half := deg_to_rad(cone) * 0.5
	var soft_a := maxf(half * 0.25, 0.02)
	var inner := clampf(falloff * 0.9, 0.0, 0.9)
	for y in n:
		for x in n:
			var v := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0) / (n / 2.0)
			var r := v.length()
			if r >= 1.0:
				continue
			var ang := absf(v.angle())
			var a_edge := clampf((half - ang) / soft_a, 0.0, 1.0)
			var r_fall := 1.0 if r <= inner else clampf(1.0 - (r - inner) / maxf(1.0 - inner, 0.001), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a_edge * r_fall * r_fall))
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t

static func _flat_tex() -> Texture2D:
	if _tex_cache.has("flat"):
		return _tex_cache["flat"]
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var t := ImageTexture.create_from_image(img)
	_tex_cache["flat"] = t
	return t

static func _radial(falloff: float) -> Texture2D:
	var key := snappedf(falloff, 0.05)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var g := Gradient.new()
	# caída suave hasta el final del alcance (no un corte): curva tipo
	# cuadrática, la luz se apaga poco a poco hacia el borde
	var inner := clampf(key * 0.9, 0.0, 0.9)
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.set_offset(0, inner)
	for f in [0.25, 0.5, 0.75]:
		var a := pow(1.0 - f, 2.0)
		g.add_point(inner + (1.0 - inner) * f, Color(1, 1, 1, a))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	_tex_cache[key] = t
	return t

## Rehace la luz de Godot con los parámetros (y los oclusores si hay sombras).
func rebuild() -> void:
	if not is_inside_tree():
		return
	# TODAS las luces son PointLight2D: DirectionalLight2D ignora la máscara de
	# capas en Godot 4.7 y teñía la caja de selección y los tiradores (azul →
	# cian). La direccional / ambiente = textura plana enorme (igual en toda la
	# página); su dirección solo cuenta para las sombras (las calculamos aquí).
	if _light and not (_light is PointLight2D):
		_light.queue_free()
		_light = null
	if _light == null:
		_light = PointLight2D.new()
		_light.name = "_Light"
		_light.set_meta(&"_vectopen_internal", true)
		add_child(_light, false, Node.INTERNAL_MODE_FRONT)
	_light.color = lamp_color
	_light.energy = lamp_energy
	_light.blend_mode = MODES[lamp_mode]
	# La sombra la dibujamos nosotros (light_shadow_node.gd: sombra EXTERIOR
	# detrás de cada figura); la de Godot dejaba la figura oscura por dentro.
	_light.shadow_enabled = false
	_light.range_item_cull_mask = DOC_LIGHT_BIT
	var pl := _light as PointLight2D
	match lamp_type:
		"spot":
			pl.texture = _cone_tex(lamp_falloff, lamp_cone)
			pl.rotation = deg_to_rad(lamp_angle) - global_rotation
			pl.texture_scale = lamp_radius / 64.0   # textura de 128 px
		"directional", "ambient":
			pl.texture = _flat_tex()
			pl.rotation = 0.0
			pl.texture_scale = 40000.0 / 4.0   # cubre de sobra cualquier página
		_:
			pl.texture = _radial(lamp_falloff)
			pl.rotation = 0.0
			pl.texture_scale = lamp_radius / 128.0
	# las sombras las rehace _process UNA vez por fotograma (antes cada
	# propiedad las rehacía al momento y otra vez en _process)
	if not is_inside_tree():
		refresh_occluders()
	queue_redraw()

# ── sombras: oclusores internos en las figuras de la misma página ───────────
func _page() -> Node:
	var p := get_parent()
	while p and not ("artboard_size" in p) and p.get_parent() and not (p.get_parent() is SubViewport):
		if p.name == "VectorDrawingLayer":
			p = p.get_parent()
			break
		p = p.get_parent()
	return p

static func _shapes_under(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is Node2D and not String(c.name).begins_with("_") and not c.has_meta(&"_vectopen_internal"):
			if c.get_script() and String(c.get_script().resource_path).ends_with("vector_light.gd"):
				continue
			if c.has_method("get_effect_points"):
				out.append(c)
			out.append_array(_shapes_under(c))
	return out

## Sombras EXTERIORES de las figuras de la página (todas las luces con
## sombra): un nodo interno «_LightShadow» detrás de cada figura.
const _ShadowNode = preload("res://script_gdscript/shapes/light_shadow_node.gd")

func refresh_occluders() -> void:
	var page := _page()
	if page == null:
		return
	var lights: Array = []
	for l in page.find_children("*", "Node2D", true, false):
		if l.is_in_group(GROUP) and bool(l.get("lamp_shadows")) and bool(TYPE_INFO.get(String(l.get("lamp_type")), {}).get("shadows", false)) and (l as Node2D).visible:
			lights.append(l)
	var fill := ambient_fill(page)
	for s in _shapes_under(page):
		var old_occ: Node = s.get_node_or_null(OCC_NAME)
		if old_occ:
			old_occ.queue_free()   # documentos de antes: oclusores de Godot fuera
		var sh: Node2D = s.get_node_or_null("_LightShadow")
		if lights.is_empty() or s.get_meta(CAST_META, true) == false:
			if sh:
				sh.queue_free()
			continue
		var pts: PackedVector2Array = s.get_effect_points()
		if pts.size() < 3:
			continue
		if sh == null:
			sh = _ShadowNode.new()
			s.add_child(sh, false, Node.INTERNAL_MODE_FRONT)
		var list: Array = []
		var sxf: Transform2D = (s as Node2D).global_transform
		var inv := sxf.affine_inverse()
		var scale_k := maxf(sxf.get_scale().x, 0.0001)
		var center := Vector2.ZERO
		for q in pts:
			center += q
		var gcenter: Vector2 = sxf * (center / pts.size())
		for l in lights:
			var info := shadow_for(l, gcenter, fill)
			if info.is_empty():
				continue   # la luz no llega a esta figura: sin sombra
			var off: Vector2 = inv.basis_xform(info["offset"])
			# cuanto más se separa la sombra, más difusa (penumbra)
			var spread: float = (info["offset"] as Vector2).length() * 0.35
			var entry := {"poly": pts, "off": off, "color": info["color"],
				"soft": float(l.lamp_shadow_soft) * (8.0 + spread) * float(info["soft_k"]) / scale_k,
				"fade": float(l.lamp_shadow_fade)}
			if info.has("src"):
				entry["src"] = inv * (info["src"] as Vector2)
				entry["grow"] = float(info["grow"])
			list.append(entry)
		sh.shadows = list
		sh.queue_redraw()

## Cuánto alumbra la luz `l` el punto global `gp` (0 = nada, 1 = de lleno).
## Puntual: cae con la distancia hasta el alcance. Foco: además, solo dentro
## del cono. Direccional: igual en toda la página. Ambiente: sin dirección.
static func influence(l: Node2D, gp: Vector2) -> float:
	var t := String(l.get("lamp_type"))
	if t == "directional" or t == "ambient":
		return 1.0
	var d := gp - l.global_position
	var radius: float = float(l.get("lamp_radius")) * maxf(l.global_transform.get_scale().x, 0.0001)
	var k := clampf(1.0 - d.length() / maxf(radius, 0.001), 0.0, 1.0)
	if t == "spot" and k > 0.0:
		var half := deg_to_rad(float(l.get("lamp_cone"))) * 0.5
		var ang := absf(Vector2.from_angle(deg_to_rad(float(l.get("lamp_angle")))).angle_to(d))
		var edge := maxf(half * 0.25, 0.02)
		k *= clampf((half - ang) / edge, 0.0, 1.0)
	return k

## Sombra 2D que la luz `l` da a una figura con centro global `gp`, como
## sería de verdad. Depende de TODAS las propiedades de la luz:
##   · intensidad → más luz, sombra más marcada (poca luz, sombra tenue);
##   · alcance / apertura / dirección → solo donde llega la luz (influence);
##   · altura → rasante = sombra larga, cenital = corta; la puntual además
##     alarga la sombra cuanto más lejos está la figura;
##   · borde duro → luz dura = sombra nítida, luz suave = sombra difusa;
##   · color → la sombra toma el tono complementario (luz cálida, sombra fría);
##   · mezcla «Restar» → la figura tapa el oscurecimiento: su «sombra» aclara;
##   · `fill` = luz ambiente de la página, que rellena (aclara) las sombras.
## {"offset", "strength" 0..1, "soft_k", "color"} o {} si no hay sombra.
static func shadow_for(l: Node2D, gp: Vector2, fill: float = 0.0) -> Dictionary:
	var t := String(l.get("lamp_type"))
	if not bool(TYPE_INFO.get(t, {}).get("shadows", false)) or not bool(l.get("lamp_shadows")):
		return {}
	var k := influence(l, gp)
	var energy := float(l.get("lamp_energy"))
	var e := 1.0 - exp(-energy * 1.4)
	var strength := sqrt(k) * e * (1.0 - clampf(fill, 0.0, 0.9))
	if strength <= 0.01:
		return {}
	var length: float = float(l.get("lamp_shadow_length")) * maxf(l.global_transform.get_scale().x, 0.0001)
	var h := float(l.get("lamp_height"))
	var hf := (1.15 - h) * 1.6
	var dir: Vector2
	var amount := hf
	if t == "directional":
		dir = Vector2.from_angle(deg_to_rad(float(l.get("lamp_angle"))))
	else:
		var d := gp - l.global_position
		dir = d.normalized() if d.length() > 0.001 else Vector2.DOWN
		amount = (0.25 + 0.75 * (1.0 - k)) * hf
	var col: Color = l.get("lamp_shadow_color")
	if String(l.get("lamp_mode")) == "sub":
		col = Color(1, 1, 1, col.a * 0.6)
	else:
		var lc: Color = l.get("lamp_color")
		var comp := Color(1.0 - lc.r, 1.0 - lc.g, 1.0 - lc.b) * 0.5
		var a0 := col.a
		col = col.lerp(comp, 0.45 * lc.s)
		col.a = a0
	col.a *= strength
	var soft_k := 1.4 - float(l.get("lamp_falloff"))
	var out := {"offset": dir * length * amount, "strength": strength, "soft_k": soft_k, "color": col}
	if t != "directional":
		# Luz puntual / foco: proyección CENTRAL desde la luz. Cada punto de la
		# figura se aleja de la luz a lo largo de SU rayo, así que los bordes
		# de la sombra siguen los rayos que pasan por las esquinas (como de
		# verdad). La direccional (sol) son rayos paralelos: desplazamiento.
		var dist := maxf((gp - l.global_position).length(), 1.0)
		out["src"] = l.global_position
		out["grow"] = 1.0 + length * amount / dist
	return out

## Luz ambiente de la página (rellena las sombras): 0..0.9.
static func ambient_fill(page: Node) -> float:
	var f := 0.0
	for a in page.get_tree().get_nodes_in_group(GROUP):
		if String(a.get("lamp_type")) == "ambient" and (a as Node2D).visible and String(a.get("lamp_mode")) != "sub" and a._page() == page:
			f += float(a.get("lamp_energy")) * 0.45
	return clampf(f, 0.0, 0.9)

## La página y lo suyo entran en la capa que alumbran las luces.
static func mark_content(page: Node) -> void:
	if page is CanvasItem:
		(page as CanvasItem).light_mask |= DOC_LIGHT_BIT
	for ci in page.find_children("*", "CanvasItem", true, false):
		if ci.is_in_group(GROUP):
			continue   # el símbolo de la luz no
		(ci as CanvasItem).light_mask |= DOC_LIGHT_BIT

## Tras cada paso del historial: los oclusores siguen la forma de las figuras.
static func on_history_step(tree: SceneTree) -> void:
	if tree == null:
		return
	if tree.get_nodes_in_group(GROUP).is_empty():
		# sin luces: fuera las sombras que quedaran (luz borrada)
		for ab in tree.get_nodes_in_group("artboards"):
			for sh in ab.find_children("_LightShadow", "", true, false):
				sh.queue_free()
		return
	for l in tree.get_nodes_in_group(GROUP):
		var pg = l._page()
		if pg:
			mark_content(pg)
		l.call_deferred("refresh_occluders")

# ── selección y símbolo en el lienzo ─────────────────────────────────────────
## Caja de selección: el símbolo (no el alcance de la luz).
func get_effect_points() -> PackedVector2Array:
	var r := 22.0   # zona cómoda para cogerla (el símbolo mide ~28 px)
	return PackedVector2Array([Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)])

func _on_canvas() -> bool:
	var p := get_parent()
	while p:
		if p is SubViewport:
			return false   # copia de exportación (cuelga de la página) o visor
		if p.is_in_group("_vectopen_canvas"):
			return true
		p = p.get_parent()
	return false

func _draw() -> void:
	if not _on_canvas():
		return   # en la copia de exportación no se dibuja el símbolo
	var c := Color(1.0, 0.75, 0.1)
	draw_circle(Vector2.ZERO, 7.0, c)
	for i in 8:
		var a := TAU * i / 8.0
		draw_line(Vector2.from_angle(a) * 10.0, Vector2.from_angle(a) * 14.0, c, 2.0)
	if lamp_type == "point":
		draw_arc(Vector2.ZERO, lamp_radius, 0.0, TAU, 96, Color(c, 0.35), 1.0)
	elif lamp_type == "spot":
		var a0 := deg_to_rad(lamp_angle) - global_rotation
		var h := deg_to_rad(lamp_cone) * 0.5
		draw_line(Vector2.ZERO, Vector2.from_angle(a0 - h) * lamp_radius, Color(c, 0.5), 1.0)
		draw_line(Vector2.ZERO, Vector2.from_angle(a0 + h) * lamp_radius, Color(c, 0.5), 1.0)
		draw_arc(Vector2.ZERO, lamp_radius, a0 - h, a0 + h, 32, Color(c, 0.35), 1.0)
	elif lamp_type == "ambient":
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 32, Color(c, 0.6), 1.0)
	else:
		var d := Vector2.from_angle(deg_to_rad(lamp_angle) - global_rotation)
		draw_line(Vector2.ZERO, d * 60.0, c, 2.0)
		draw_line(d * 60.0, d * 60.0 - d.rotated(0.4) * 12.0, c, 2.0)
		draw_line(d * 60.0, d * 60.0 - d.rotated(-0.4) * 12.0, c, 2.0)
