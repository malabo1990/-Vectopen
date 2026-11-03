# =============================================================================
# RUTA: res://script_gdscript/shapes/brush_stroke_render.gd
# RENDER DE CALIDAD de un trazo de pincel (Line2D) + su DEGRADADO.
#
# · Line2D dibuja un trazo grueso de puntos densos con un círculo en cada
#   unión: con grosor variable (presión) el borde salía festoneado. Este nodo
#   hijo dibuja el mismo trazo con la geometría precisa de los trazados
#   (StrokeGeom: tira continua con inglete, uniones y remates redondos) y el
#   Line2D deja de pintarse (self_modulate alfa 0). El Line2D sigue siendo el
#   modelo: puntos, grosor, curva de presión, color — borrador, guardado,
#   efectos y selección no cambian.
# · Degradado 2D (lineal / radial) con DOS PUNTOS en el espacio, como las
#   figuras: color por vértice. Expone la misma API que VectorShape
#   (fill_gradient, get_gradient_p0_norm, set_gradient_points…) para que la
#   caja de selección (tecla G) dibuje y arrastre sus controles.
# Los datos viven como metas del Line2D (se guardan con él).
# =============================================================================
extends Node2D

const StrokeGeom = preload("res://script_gdscript/shapes/stroke_geom.gd")
const STROKE_SHADER := preload("res://shaders/brush_stroke.gdshader")
## Material compartido de los trazos sin degradado (no rompe el agrupado de
## dibujo); con degradado cada trazo tiene el suyo (uniformes propios).
static var _shared_mat: ShaderMaterial = null
const NODE_NAME := "StrokeRender"

var line: Line2D = null
## Sombreador del trazo (antialias + textura + degradado). Va en el elemento
## hijo que pinta la malla, no en este nodo: este, si el trazo es
## semitransparente, es un GRUPO (se compone entero y luego se le aplica la
## opacidad), así un trazo que se cruza consigo mismo no se oscurece en el
## cruce, en las uniones ni en los remates.
var stroke_material: ShaderMaterial = null
var _mesh_ci := RID()
var _internal_point_update := false
var _grad_tex: GradientTexture1D = null

## Añade (o devuelve) el render de `l`.
static func attach(l: Line2D) -> Node2D:
	if not is_instance_valid(l):
		return null
	var r := l.get_node_or_null(NODE_NAME) as Node2D
	if r == null:
		r = load("res://script_gdscript/shapes/brush_stroke_render.gd").new()
		r.name = NODE_NAME
		l.add_child(r)
	r.line = l
	r._hide_native()
	r._update_material()
	r.queue_redraw()
	return r

static func of(l: Node) -> Node2D:
	return l.get_node_or_null(NODE_NAME) as Node2D if is_instance_valid(l) else null

func _ready() -> void:
	if line == null:
		line = get_parent() as Line2D
	_hide_native()
	_update_material()
	if line and not line.draw.is_connected(queue_redraw):
		# El Line2D se redibuja al cambiar puntos / grosor / curva / color.
		line.draw.connect(queue_redraw)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _mesh_ci.is_valid():
		RenderingServer.free_rid(_mesh_ci)
		_mesh_ci = RID()

func _mesh_item() -> RID:
	if not _mesh_ci.is_valid():
		_mesh_ci = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(_mesh_ci, get_canvas_item())
		if stroke_material:
			RenderingServer.canvas_item_set_material(_mesh_ci, stroke_material.get_rid())
	return _mesh_ci

## Opacidad del trazo como grupo (ver stroke_material).
func _set_group(alpha: float) -> void:
	var translucent := alpha < 0.999
	RenderingServer.canvas_item_set_canvas_group_mode(get_canvas_item(),
		RenderingServer.CANVAS_GROUP_MODE_TRANSPARENT if translucent else RenderingServer.CANVAS_GROUP_MODE_DISABLED,
		4.0, false, 0.0, false)
	modulate.a = alpha if translucent else 1.0

func _hide_native() -> void:
	if is_instance_valid(line):
		line.self_modulate.a = 0.0

# ── dibujo ───────────────────────────────────────────────────────────────────
func _draw() -> void:
	var ci := _mesh_item()
	RenderingServer.canvas_item_clear(ci)
	if not is_instance_valid(line):
		return
	var pts := line.points
	if pts.is_empty() or line.width <= 0.0:
		return
	pts = StrokeGeom.clean(pts, clampf(line.width * 0.05, 0.05, 2.0), false)
	var n := pts.size()
	var half := PackedFloat32Array()
	half.resize(n)
	var cum := PackedFloat32Array()
	cum.resize(n)
	for i in range(1, n):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	var total := maxf(cum[n - 1], 0.0001)
	var wc := line.width_curve
	for i in n:
		var f := wc.sample_baked(cum[i] / total) if wc else 1.0
		half[i] = maxf(line.width * 0.5 * f, 0.05)
	var m := StrokeGeom.strip_mesh(pts, half, _cap(line.begin_cap_mode), _cap(line.end_cap_mode))
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	if idx.is_empty():
		return
	var cols := _colors(verts, pts, cum, total)
	# Opacidad del pincel → del grupo; la malla, opaca (sin solapes visibles).
	var alpha := line.default_color.a
	_set_group(alpha)
	if alpha < 0.999 and alpha > 0.0:
		for i in cols.size():
			cols[i].a = clampf(cols[i].a / alpha, 0.0, 1.0)
	# UX-16: la TEXTURA del estilo (grano del lápiz, bordes del marcador,
	# difuminado del aerógrafo, bisel caligráfico). Antes se ignoraba y todos
	# los estilos salían como una banda lisa.
	var tex := style_texture(line)
	var uvs := _uvs(verts, pts, cum, total, half, m.get("v", PackedFloat32Array()), tex != null)
	RenderingServer.canvas_item_add_triangle_array(ci, idx, verts, cols,
		uvs, PackedInt32Array(), PackedFloat32Array(), tex.get_rid() if tex else RID())

## Textura del estilo del trazo (meta «brush_style»: también en documentos
## guardados, que no conservan la textura del Line2D).
static func style_texture(l: Line2D) -> Texture2D:
	if not is_instance_valid(l):
		return null
	var st := String(l.get_meta("brush_style", ""))
	if st in ["pencil", "marker", "airbrush", "calligraphy"]:
		return BrushTool._get_brush_texture(st)
	return null

## UV de la tira (StrokeGeom.strip_mesh: 2 vértices por punto, a cada lado):
## u a lo largo (en mosaico cada «grosor», o estirada en el aerógrafo) y v a
## lo ancho. Remates y uniones (añadidos al final): v según la distancia al
## eje (centro = 0,5; borde = 1), así un aerógrafo no deja manchas en las puntas.
## `across`: la v que da StrokeGeom (exacta y sin buscar el punto más
## cercano); `textured`: solo entonces hace falta la u.
func _uvs(verts: PackedVector2Array, pts: PackedVector2Array, cum: PackedFloat32Array, total: float,
		half: PackedFloat32Array, across: PackedFloat32Array = PackedFloat32Array(), textured: bool = true) -> PackedVector2Array:
	var uv := PackedVector2Array()
	uv.resize(verts.size())
	var stretch := String(line.get_meta("brush_style", "")) == "airbrush"
	var tile := maxf(line.width * 2.0, 1.0)
	var n := pts.size()
	var has_v := across.size() == verts.size()
	for i in verts.size():
		var k := -1
		if i < n * 2:
			@warning_ignore("integer_division")
			k = i / 2
		elif textured or not has_v:
			k = _nearest(pts, verts[i])
		var u := 0.0
		if textured and k >= 0:
			u = cum[k] / total if stretch else cum[k] / tile
		var v: float
		if has_v:
			v = across[i]
		elif i < n * 2:
			v = 0.0 if i % 2 == 0 else 1.0
		else:
			v = 0.5 + 0.5 * clampf(verts[i].distance_to(pts[k]) / maxf(half[k], 0.001), 0.0, 1.0)
		uv[i] = Vector2(u, v)
	return uv

static func _cap(mode: int) -> int:
	match mode:
		Line2D.LINE_CAP_ROUND:
			return 1
		Line2D.LINE_CAP_BOX:
			return 2
	return 0

## Color por vértice: degradado 2D, el degradado a lo largo del Line2D, o
## el color liso.
func _colors(verts: PackedVector2Array, pts: PackedVector2Array, cum: PackedFloat32Array, total: float) -> PackedColorArray:
	var base := line.default_color
	if has_gradient_fill():
		# El color lo pone el shader (GPU): aquí solo la opacidad del pincel.
		return PackedColorArray([Color(1, 1, 1, base.a)])
	if line.gradient:
		# Degradado a lo largo del trazo (el del Line2D): por el punto más
		# cercano de la línea central.
		var out2 := PackedColorArray()
		out2.resize(verts.size())
		for i in verts.size():
			@warning_ignore("integer_division")
			var k := mini(i / 2, pts.size() - 1) if i < pts.size() * 2 else _nearest(pts, verts[i])
			out2[i] = line.gradient.sample(cum[k] / total)
		return out2
	return PackedColorArray([base])

static func _nearest(pts: PackedVector2Array, v: Vector2) -> int:
	var best := 0
	var bd := INF
	for i in pts.size():
		var d := pts[i].distance_squared_to(v)
		if d < bd:
			bd = d
			best = i
	return best

## Shader del degradado: activo si hay degradado. Mover los puntos / cambiar
## el tipo solo toca uniformes (sin recalcular ni redibujar la malla).
func _update_material() -> void:
	if not is_instance_valid(line):
		return
	var g := fill_gradient
	if g == null or g.get_point_count() < 2:
		if _shared_mat == null:
			_shared_mat = ShaderMaterial.new()
			_shared_mat.shader = STROKE_SHADER
		_use_material(_shared_mat)
		return
	var mat := stroke_material
	if mat == null or mat == _shared_mat:
		mat = ShaderMaterial.new()
		mat.shader = STROKE_SHADER
		mat.set_shader_parameter("use_grad", true)
		_use_material(mat)
	if _grad_tex == null:
		_grad_tex = GradientTexture1D.new()
		_grad_tex.width = 256
	if _grad_tex.gradient != g:
		_grad_tex.gradient = g   # la textura sigue los cambios de las paradas
	mat.set_shader_parameter("grad_tex", _grad_tex)
	mat.set_shader_parameter("p0", _a())
	mat.set_shader_parameter("p1", _b())
	mat.set_shader_parameter("gtype", fill_gradient_type)

func _use_material(mat: ShaderMaterial) -> void:
	stroke_material = mat
	RenderingServer.canvas_item_set_material(_mesh_item(), mat.get_rid())

func _set_ends(a: Variant, b: Variant) -> void:
	if a != null:
		line.set_meta("brush_grad_a", a)
	if b != null:
		line.set_meta("brush_grad_b", b)
	_update_material()

# ── API de degradado (igual que VectorShape, para la caja de selección) ───────
## Rectángulo local del trazo: el MISMO que usa la caja de selección
## (bounding_box._local_rect_cloned) para normalizar los puntos.
func annot_rect() -> Rect2:
	if not is_instance_valid(line) or line.points.is_empty():
		return Rect2(Vector2(-10, -10), Vector2(20, 20))
	var mn := line.points[0]
	var mx := mn
	for p in line.points:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	return Rect2(mn, mx - mn).grow(maxf(6.0, line.width * 0.5))

func _to_norm(p: Vector2) -> Vector2:
	var r := annot_rect()
	return Vector2((p.x - r.position.x) / maxf(r.size.x, 0.0001), (p.y - r.position.y) / maxf(r.size.y, 0.0001))

func _from_norm(n: Vector2) -> Vector2:
	var r := annot_rect()
	return r.position + Vector2(n.x * r.size.x, n.y * r.size.y)

func _a() -> Vector2:
	return line.get_meta("brush_grad_a", _from_norm(Vector2(0.1, 0.5)))

func _b() -> Vector2:
	return line.get_meta("brush_grad_b", _from_norm(Vector2(0.9, 0.5)))

var fill_gradient: Gradient:
	get:
		return line.get_meta("brush_grad") if is_instance_valid(line) and line.has_meta("brush_grad") else null
	set(v):
		if not is_instance_valid(line):
			return
		var had := has_gradient_fill()
		if v:
			line.set_meta("brush_grad", v)
		elif line.has_meta("brush_grad"):
			line.remove_meta("brush_grad")
		_update_material()
		if had != has_gradient_fill():
			queue_redraw()   # cambia el color de los vértices (liso ↔ degradado)

## 0 lineal, 1 radial.
var fill_gradient_type: int:
	get:
		return int(line.get_meta("brush_grad_type", 0)) if is_instance_valid(line) else 0
	set(v):
		if is_instance_valid(line):
			line.set_meta("brush_grad_type", 1 if v == 1 else 0)
			_update_material()

var fill_gradient_p0: Vector2:
	get:
		return _to_norm(_a())
	set(v):
		_set_ends(_from_norm(v), null)

var fill_gradient_p1: Vector2:
	get:
		return _to_norm(_b())
	set(v):
		_set_ends(null, _from_norm(v))

## Ángulo del eje; al cambiarlo gira alrededor del centro (como las figuras).
var fill_gradient_angle: float:
	get:
		return (_b() - _a()).angle()
	set(v):
		if _internal_point_update or not is_instance_valid(line):
			return
		var a := _a()
		var b := _b()
		var c := (a + b) * 0.5
		var half_span := a.distance_to(b) * 0.5
		var d := Vector2(cos(v), sin(v)) * half_span
		_set_ends(c - d, c + d)

var fill_color: Color:
	get:
		return line.default_color if is_instance_valid(line) else Color.WHITE
	set(v):
		if is_instance_valid(line):
			line.default_color = v

func has_gradient_fill() -> bool:
	var g := fill_gradient
	return g != null and g.get_point_count() >= 2

func get_gradient_p0_norm() -> Vector2:
	return fill_gradient_p0

func get_gradient_p1_norm() -> Vector2:
	return fill_gradient_p1

func set_gradient_points(p0_norm: Vector2, p1_norm: Vector2) -> void:
	_set_ends(_from_norm(p0_norm), _from_norm(p1_norm))

func set_gradient_endpoint_0(p0_norm: Vector2) -> void:
	_set_ends(_from_norm(p0_norm), null)

func set_gradient_endpoint_1(p1_norm: Vector2) -> void:
	_set_ends(null, _from_norm(p1_norm))

## Degradado inicial al pulsar G: del color del trazo a blanco (o casi negro
## si es claro), de izquierda a derecha — igual que las figuras.
func ensure_default_gradient() -> void:
	if has_gradient_fill():
		return
	var g := Gradient.new()
	var base := line.default_color
	base.a = 1.0
	g.set_color(0, base)
	g.set_color(1, Color.WHITE if base.get_luminance() < 0.6 else Color(0.1, 0.1, 0.1, 1.0))
	fill_gradient = g
	set_gradient_points(Vector2(0.1, 0.5), Vector2(0.9, 0.5))
