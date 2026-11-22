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

var _light: Light2D = null
static var _tex_cache := {}

func _init() -> void:
	name = "Luz"
	set_meta("shape_type", "light")

func _ready() -> void:
	add_to_group(GROUP)
	rebuild()
	# al abrir un documento la luz puede cargarse antes que las figuras:
	# los oclusores se calculan otra vez cuando la página ya está completa
	(func() -> void:
		await get_tree().process_frame
		if is_inside_tree():
			refresh_occluders()).call_deferred()

func params() -> Dictionary:
	return {"type": lamp_type, "color": lamp_color, "energy": lamp_energy, "radius": lamp_radius,
		"angle": lamp_angle, "falloff": lamp_falloff, "mode": lamp_mode, "shadows": lamp_shadows,
		"cone": lamp_cone, "shadow_color": lamp_shadow_color, "shadow_soft": lamp_shadow_soft}

func set_params(p: Dictionary) -> void:
	for k in p:
		if ("lamp_" + String(k)) in self:
			set("lamp_" + String(k), p[k])

## Cono del foco: radial recortado a `cone` grados hacia +X (la luz se gira).
static func _cone_tex(falloff: float, cone: float) -> Texture2D:
	var key := "cone_%.2f_%d" % [snappedf(falloff, 0.05), int(cone)]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var n := 256
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
			img.set_pixel(x, y, Color(1, 1, 1, a_edge * r_fall))
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t

static func _radial(falloff: float) -> Texture2D:
	var key := snappedf(falloff, 0.05)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.set_offset(0, clampf(key * 0.9, 0.0, 0.9))
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
	var want_point := lamp_type in ["point", "spot"]
	if _light and ((_light is PointLight2D) != want_point):
		_light.queue_free()
		_light = null
	if _light == null:
		_light = PointLight2D.new() if want_point else DirectionalLight2D.new()
		_light.name = "_Light"
		_light.set_meta(&"_vectopen_internal", true)
		add_child(_light, false, Node.INTERNAL_MODE_FRONT)
	_light.color = lamp_color
	_light.energy = lamp_energy
	_light.blend_mode = MODES[lamp_mode]
	var info: Dictionary = TYPE_INFO[lamp_type]
	_light.shadow_enabled = lamp_shadows and bool(info["shadows"])
	_light.shadow_color = lamp_shadow_color
	_light.shadow_filter = Light2D.SHADOW_FILTER_PCF13 if lamp_shadow_soft > 0.01 else Light2D.SHADOW_FILTER_NONE
	_light.shadow_filter_smooth = lamp_shadow_soft * 12.0
	if _light is PointLight2D:
		var pl := _light as PointLight2D
		if lamp_type == "spot":
			pl.texture = _cone_tex(lamp_falloff, lamp_cone)
			pl.rotation = deg_to_rad(lamp_angle) - global_rotation
		else:
			pl.texture = _radial(lamp_falloff)
			pl.rotation = 0.0
		pl.texture_scale = lamp_radius / 128.0
	else:
		var dl := _light as DirectionalLight2D
		if lamp_type == "ambient":
			# luz uniforme en toda la página: sin dirección ni sombras
			dl.rotation = 0.0
			dl.height = 1.0
			dl.max_distance = 0.0
		else:
			dl.rotation = deg_to_rad(lamp_angle - 90.0) - global_rotation
			dl.height = 0.0
			dl.max_distance = maxf(lamp_radius * 4.0, 2000.0)
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

## Pone / quita los oclusores según haya luces con sombra en la página.
func refresh_occluders() -> void:
	var page := _page()
	if page == null:
		return
	var any_shadow := false
	for l in page.find_children("*", "Node2D", true, false):
		if l.is_in_group(GROUP) and bool(l.get("lamp_shadows")) and bool(TYPE_INFO.get(String(l.get("lamp_type")), {}).get("shadows", false)):
			any_shadow = true
	for s in _shapes_under(page):
		var occ: LightOccluder2D = s.get_node_or_null(OCC_NAME)
		if not any_shadow or s.get_meta(CAST_META, true) == false:
			if occ:
				occ.queue_free()
			continue
		var pts: PackedVector2Array = s.get_effect_points()
		if pts.size() < 3:
			continue
		if occ == null:
			occ = LightOccluder2D.new()
			occ.name = OCC_NAME
			occ.set_meta(&"_vectopen_internal", true)
			s.add_child(occ, false, Node.INTERNAL_MODE_BACK)
		var poly := OccluderPolygon2D.new()
		poly.polygon = pts
		poly.closed = true
		poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
		occ.occluder = poly

## Tras cada paso del historial: los oclusores siguen la forma de las figuras.
static func on_history_step(tree: SceneTree) -> void:
	if tree == null:
		return
	for l in tree.get_nodes_in_group(GROUP):
		if bool(l.get("lamp_shadows")):
			l.call_deferred("refresh_occluders")

# ── selección y símbolo en el lienzo ─────────────────────────────────────────
## Caja de selección: el símbolo (no el alcance de la luz).
func get_effect_points() -> PackedVector2Array:
	var r := 14.0
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
