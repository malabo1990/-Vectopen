@tool
extends Node2D
class_name VectorShape

@export var object_id: String = ""
@export var fill_color: Color = Color.WHITE
@export var stroke_color: Color = Color.BLACK
@export var stroke_width: float = 2.0:
	set(v):
		stroke_width = maxf(0.0, v)
		queue_redraw()

## 0: Solid, 1: Dashed, 2: Dotted, 4: Double
@export var stroke_style: int = 0:
	set(v):
		stroke_style = v
		queue_redraw()

## 0: Center, 1: Inside, 2: Outside
@export var stroke_align: int = 0:
	set(v):
		stroke_align = v
		queue_redraw()

@export var stroke_dash_len: float = 12.0:
	set(v):
		stroke_dash_len = maxf(1.0, v)
		queue_redraw()

@export var stroke_dash_gap: float = 8.0:
	set(v):
		stroke_dash_gap = maxf(1.0, v)
		queue_redraw()

## ── Relleno con degradado (opcional) ──────────────────────────────────────
## Si `fill_gradient` tiene >= 2 puntos, el relleno se dibuja como degradado
## (lineal o radial) en vez del `fill_color` plano. Todas las figuras dibujan
## su relleno con `draw_fill(points)`, así que el degradado funciona en
## rectángulo, círculo, polígono y cualquier figura nueva sin tocarlas.
@export var fill_gradient: Gradient = null:
	set(v):
		if fill_gradient and fill_gradient.changed.is_connected(_on_fill_gradient_changed):
			fill_gradient.changed.disconnect(_on_fill_gradient_changed)
		fill_gradient = v
		if fill_gradient and not fill_gradient.changed.is_connected(_on_fill_gradient_changed):
			fill_gradient.changed.connect(_on_fill_gradient_changed)
		_grad_tex = null
		queue_redraw()
## 0 = lineal, 1 = radial, 2 = cónico, 3 = diamante, 4 = cuadrado/box, 5 = espiral.
@export var fill_gradient_type: int = 0:
	set(v):
		fill_gradient_type = v
		_grad_tex = null
		queue_redraw()
var _internal_point_update: bool = false

## Ángulo del degradado lineal, en radianes (0 = izquierda→derecha).
@export var fill_gradient_angle: float = 0.0:
	set(v):
		fill_gradient_angle = v
		if not _internal_point_update and fill_gradient_p0 != Vector2(-1, -1) and fill_gradient_p1 != Vector2(-1, -1):
			var center := (fill_gradient_p0 + fill_gradient_p1) * 0.5 if fill_gradient_type == 0 else fill_gradient_p0
			var span := fill_gradient_p0.distance_to(fill_gradient_p1) * 0.5 if fill_gradient_type == 0 else fill_gradient_p0.distance_to(fill_gradient_p1)
			var dir := Vector2(cos(v), sin(v))
			if fill_gradient_type == 0:
				fill_gradient_p0 = center - dir * span
				fill_gradient_p1 = center + dir * span
			else:
				fill_gradient_p1 = fill_gradient_p0 + dir * span
		_grad_tex = null
		queue_redraw()

## Puntos extremos normalizados (0..1) del degradado en el espacio de la caja de la figura.
## Vector2(-1, -1) indica no inicializado (se calcula a partir de fill_gradient_angle).
@export var fill_gradient_p0: Vector2 = Vector2(-1, -1):
	set(v):
		fill_gradient_p0 = v
		_grad_tex = null
		queue_redraw()

@export var fill_gradient_p1: Vector2 = Vector2(-1, -1):
	set(v):
		fill_gradient_p1 = v
		_grad_tex = null
		queue_redraw()

func get_gradient_p0_norm() -> Vector2:
	if fill_gradient_p0 != Vector2(-1, -1):
		return fill_gradient_p0
	var dir := Vector2(cos(fill_gradient_angle), sin(fill_gradient_angle))
	if fill_gradient_type in [1, 2, 3, 4, 5]:
		return Vector2(0.5, 0.5)
	return Vector2(0.5, 0.5) - dir * 0.45

func get_gradient_p1_norm() -> Vector2:
	if fill_gradient_p1 != Vector2(-1, -1):
		return fill_gradient_p1
	var dir := Vector2(cos(fill_gradient_angle), sin(fill_gradient_angle))
	return Vector2(0.5, 0.5) + dir * 0.45

func set_gradient_endpoint_0(norm_p0: Vector2) -> void:
	var cur_p1 := get_gradient_p1_norm()
	fill_gradient_p1 = cur_p1
	fill_gradient_p0 = norm_p0
	var diff := cur_p1 - norm_p0
	if diff.length_squared() > 0.0001:
		_internal_point_update = true
		fill_gradient_angle = diff.angle()
		_internal_point_update = false
	if _grad_tex is GradientTexture2D and fill_gradient_type in [0, 1, 2]:
		_grad_tex.fill_from = norm_p0
		_grad_tex.fill_to = cur_p1
	else:
		_grad_tex = null
	queue_redraw()

func set_gradient_endpoint_1(norm_p1: Vector2) -> void:
	var cur_p0 := get_gradient_p0_norm()
	fill_gradient_p0 = cur_p0
	fill_gradient_p1 = norm_p1
	var diff := norm_p1 - cur_p0
	if diff.length_squared() > 0.0001:
		_internal_point_update = true
		fill_gradient_angle = diff.angle()
		_internal_point_update = false
	if _grad_tex is GradientTexture2D and fill_gradient_type in [0, 1, 2]:
		_grad_tex.fill_from = cur_p0
		_grad_tex.fill_to = norm_p1
	else:
		_grad_tex = null
	queue_redraw()

func set_gradient_points(p0_norm: Vector2, p1_norm: Vector2) -> void:
	fill_gradient_p0 = p0_norm
	fill_gradient_p1 = p1_norm
	var diff := p1_norm - p0_norm
	if diff.length_squared() > 0.0001:
		_internal_point_update = true
		fill_gradient_angle = diff.angle()
		_internal_point_update = false
	if _grad_tex is GradientTexture2D and fill_gradient_type in [0, 1, 2]:
		_grad_tex.fill_from = p0_norm
		_grad_tex.fill_to = p1_norm
	else:
		_grad_tex = null
	queue_redraw()

var _grad_tex: Texture2D = null

var is_selected: bool = false
var effects: Array = []

func _on_fill_gradient_changed() -> void:
	_grad_tex = null
	queue_redraw()

func has_gradient_fill() -> bool:
	return fill_gradient != null and fill_gradient.get_point_count() >= 2

func clear_fill_gradient() -> void:
	fill_gradient = null
	_grad_tex = null
	queue_redraw()

## Dibuja sombras de efectos (Drop Shadow) antes del relleno de la figura.
func draw_effects_shadows(points: PackedVector2Array) -> void:
	if effects.is_empty() or points.size() < 3:
		return
	for fx in effects:
		if not (fx is Dictionary):
			continue
		if not bool(fx.get("enabled", true)):
			continue
		var type: String = String(fx.get("type", "")).to_lower().replace(" ", "_")
		if type == "drop_shadow":
			_render_drop_shadow(points, fx)

## Dibuja efectos superpuestos (Inner Shadow, Outline, Color Overlay) después del contorno.
func draw_effects_overlays(points: PackedVector2Array) -> void:
	if effects.is_empty() or points.size() < 3:
		return
	for fx in effects:
		if not (fx is Dictionary):
			continue
		if not bool(fx.get("enabled", true)):
			continue
		var type: String = String(fx.get("type", "")).to_lower().replace(" ", "_")
		match type:
			"inner_shadow":
				_render_inner_shadow(points, fx)
			"outline":
				_render_outline_effect(points, fx)
			"color_overlay":
				_render_color_overlay(points, fx)

func _parse_fx_color(val: Variant, default_col: Color) -> Color:
	if val is Color:
		return val
	if val is String:
		return Color.from_string(val, default_col)
	if val is Array and val.size() >= 3:
		var a: float = float(val[3]) if val.size() >= 4 else 1.0
		return Color(float(val[0]), float(val[1]), float(val[2]), a)
	return default_col

func _render_drop_shadow(points: PackedVector2Array, fx: Dictionary) -> void:
	var offset := Vector2(float(fx.get("offset_x", 4.0)), float(fx.get("offset_y", 4.0)))
	var blur := maxf(0.0, float(fx.get("blur", 6.0)))
	var spread := float(fx.get("spread", 0.0))
	var base_col := _parse_fx_color(fx.get("color", null), Color(0.0, 0.0, 0.0, 0.4))
	if base_col.a <= 0.001:
		return

	if blur <= 0.5:
		var shifted := PackedVector2Array()
		for p in points:
			shifted.append(p + offset)
		if spread != 0.0:
			var polys := Geometry2D.offset_polygon(shifted, spread, Geometry2D.JOIN_ROUND)
			for poly in polys:
				if poly.size() >= 3:
					draw_colored_polygon(poly, base_col)
		else:
			draw_colored_polygon(shifted, base_col)
		return

	# Falloff multi-paso suave (aproximación Gaussiana de alta fidelidad)
	var passes: int = clampi(int(blur * 0.75), 4, 8)
	var max_expand: float = blur * 1.25 + spread
	var min_expand: float = spread - blur * 0.25

	for i in range(passes):
		var t: float = float(i) / float(passes - 1)
		var exp_dist: float = lerpf(min_expand, max_expand, t)
		var factor: float = exp(-2.2 * t * t)
		var pass_alpha: float = (base_col.a / float(passes)) * factor * 1.6
		pass_alpha = clampf(pass_alpha, 0.005, 1.0)
		var pass_col := Color(base_col.r, base_col.g, base_col.b, pass_alpha)

		var offset_pts := Geometry2D.offset_polygon(points, exp_dist, Geometry2D.JOIN_ROUND)
		if offset_pts.is_empty():
			continue
		for poly in offset_pts:
			if poly.size() >= 3:
				var translated := PackedVector2Array()
				for pt in poly:
					translated.append(pt + offset)
				draw_colored_polygon(translated, pass_col)

func _render_inner_shadow(points: PackedVector2Array, fx: Dictionary) -> void:
	var offset := Vector2(float(fx.get("offset_x", 2.0)), float(fx.get("offset_y", 2.0)))
	var blur := maxf(0.5, float(fx.get("blur", 4.0)))
	var base_col := _parse_fx_color(fx.get("color", null), Color(0.0, 0.0, 0.0, 0.5))
	if base_col.a <= 0.001:
		return

	var passes: int = clampi(int(blur * 0.75), 3, 6)
	for i in range(passes):
		var t: float = float(i) / float(passes)
		var inward: float = lerpf(0.5, blur + 2.0, t)
		var alpha: float = (base_col.a / float(passes)) * (1.0 - t * 0.5)
		var pass_col := Color(base_col.r, base_col.g, base_col.b, alpha)

		var inners := Geometry2D.offset_polygon(points, -inward, Geometry2D.JOIN_ROUND)
		if inners.is_empty():
			continue
		for inner_poly in inners:
			var clipped := Geometry2D.clip_polygons(points, inner_poly)
			for ring in clipped:
				if ring.size() >= 3:
					var shifted := PackedVector2Array()
					for pt in ring:
						shifted.append(pt + offset * (1.0 - t))
					draw_colored_polygon(shifted, pass_col)

func _render_outline_effect(points: PackedVector2Array, fx: Dictionary) -> void:
	var width := maxf(0.5, float(fx.get("width", 2.0)))
	var col := _parse_fx_color(fx.get("color", null), Color.BLACK)
	if col.a <= 0.001:
		return
	var ring := PackedVector2Array(points)
	if not ring[0].is_equal_approx(ring[-1]):
		ring.append(ring[0])
	var sp := _get_rendered_stroke_params(width, col)
	draw_polyline(ring, sp[1], sp[0], false)

func _render_color_overlay(points: PackedVector2Array, fx: Dictionary) -> void:
	var col := _parse_fx_color(fx.get("color", null), Color(1.0, 0.0, 0.0, 1.0))
	var opacity := clampf(float(fx.get("opacity", 1.0)), 0.0, 1.0)
	var final_col := Color(col.r, col.g, col.b, col.a * opacity)
	if final_col.a <= 0.001:
		return
	draw_colored_polygon(points, final_col)

func get_svg_filter_attr() -> String:
	for fx in effects:
		if fx is Dictionary and bool(fx.get("enabled", true)):
			var type: String = String(fx.get("type", "")).to_lower().replace(" ", "_")
			if type == "drop_shadow":
				var ox: float = float(fx.get("offset_x", 4.0))
				var oy: float = float(fx.get("offset_y", 4.0))
				var blur: float = float(fx.get("blur", 6.0))
				var col: Color = _parse_fx_color(fx.get("color", null), Color(0, 0, 0, 0.4))
				return ' style="filter: drop-shadow(%.1fpx %.1fpx %.1fpx rgba(%d,%d,%d,%.2f));"' % [
					ox, oy, blur, int(col.r * 255), int(col.g * 255), int(col.b * 255), col.a
				]
	return ""

## Dibuja el relleno del polígono dado: degradado si hay `fill_gradient`,
## si no el `fill_color` plano. Las subclases lo llaman desde su `_draw()`.
func draw_fill(points: PackedVector2Array) -> void:
	if points.size() < 3:
		return
	if has_gradient_fill():
		draw_colored_polygon(points, Color.WHITE, _gradient_uvs(points), _ensure_grad_tex())
	elif fill_color.a > 0.0:
		draw_colored_polygon(points, fill_color)

## Calcula el ancho de trazo y color con atenuación subpíxel para evitar que líneas < 1px se vean punteadas o desaparezcan.
func _get_rendered_stroke_params(w: float = -1.0, col: Color = Color(-1, -1, -1, -1)) -> Array:
	var req_w: float = stroke_width if w < 0.0 else w
	var req_col: Color = stroke_color if col.r < 0.0 else col
	if req_w < 1.0 and req_w > 0.0:
		var c := req_col
		c.a *= req_w
		return [1.0, c]
	return [req_w, req_col]

## Dibuja el contorno cerrado soportando estilos de trazo (Solid, Dashed, Dotted, Double).
func draw_stroke_ring(points: PackedVector2Array) -> void:
	if stroke_width <= 0.0 or points.size() < 2:
		return
	var ring := PackedVector2Array(points)
	if not ring[0].is_equal_approx(ring[-1]):
		ring.append(ring[0])
	var sp := _get_rendered_stroke_params()
	var rend_w: float = sp[0]
	var rend_col: Color = sp[1]
	match stroke_style:
		1: # Dashed
			_draw_ring_dashed(ring, rend_w, rend_col)
		2: # Dotted
			_draw_ring_dotted(ring, rend_col)
		4: # Double
			_draw_ring_double(ring, rend_col)
		_: # Solid
			draw_polyline(ring, rend_col, rend_w, false)

func _draw_ring_dashed(ring: PackedVector2Array, rend_w: float = -1.0, rend_col: Color = Color(-1, -1, -1, -1)) -> void:
	var use_w: float = stroke_width if rend_w < 0.0 else rend_w
	var use_col: Color = stroke_color if rend_col.r < 0.0 else rend_col
	var dash: float = maxf(stroke_dash_len, 2.0)
	var gap: float = maxf(stroke_dash_gap, 2.0)
	var drawing: bool = true
	var rem: float = dash
	var cur_pts: PackedVector2Array = []
	for i in range(ring.size() - 1):
		var p1: Vector2 = ring[i]
		var p2: Vector2 = ring[i + 1]
		var seg_len: float = p1.distance_to(p2)
		if seg_len <= 0.0001:
			continue
		var dir: Vector2 = (p2 - p1) / seg_len
		var curr_d: float = 0.0
		while curr_d < seg_len:
			var step: float = minf(rem, seg_len - curr_d)
			var next_p: Vector2 = p1 + dir * (curr_d + step)
			if drawing:
				if cur_pts.is_empty():
					cur_pts.append(p1 + dir * curr_d)
				cur_pts.append(next_p)
			curr_d += step
			rem -= step
			if rem <= 0.0001:
				if drawing:
					if cur_pts.size() >= 2:
						draw_polyline(cur_pts, use_col, use_w, false)
					cur_pts.clear()
					drawing = false
					rem = gap
				else:
					drawing = true
					rem = dash
	if drawing and cur_pts.size() >= 2:
		draw_polyline(cur_pts, use_col, use_w, false)

func _draw_ring_dotted(ring: PackedVector2Array, rend_col: Color = Color(-1, -1, -1, -1)) -> void:
	var use_col: Color = stroke_color if rend_col.r < 0.0 else rend_col
	var dot_radius: float = maxf(1.0, stroke_width * 0.5)
	var spacing: float = maxf(stroke_dash_gap + stroke_width, stroke_width * 2.5)
	var dist_accum: float = 0.0
	draw_circle(ring[0], dot_radius, use_col)
	for i in range(ring.size() - 1):
		var p1: Vector2 = ring[i]
		var p2: Vector2 = ring[i + 1]
		var seg_len: float = p1.distance_to(p2)
		if seg_len <= 0.0001:
			continue
		var dir: Vector2 = (p2 - p1) / seg_len
		var d: float = 0.0
		while d < seg_len:
			var needed: float = spacing - dist_accum
			if d + needed <= seg_len:
				d += needed
				draw_circle(p1 + dir * d, dot_radius, use_col)
				dist_accum = 0.0
			else:
				dist_accum += (seg_len - d)
				break

func _draw_ring_double(ring: PackedVector2Array, rend_col: Color = Color(-1, -1, -1, -1)) -> void:
	var use_col: Color = stroke_color if rend_col.r < 0.0 else rend_col
	var sub_w: float = maxf(1.0, stroke_width * 0.35)
	var off: float = stroke_width * 0.45
	var l1: PackedVector2Array = []
	var l2: PackedVector2Array = []
	var n_pts: int = ring.size()
	for i in range(n_pts):
		var prev_p: Vector2 = ring[(i - 1 + n_pts) % n_pts]
		var next_p: Vector2 = ring[(i + 1) % n_pts]
		var tangent: Vector2 = (next_p - prev_p).normalized()
		var n: Vector2 = Vector2(-tangent.y, tangent.x)
		l1.append(ring[i] + n * off)
		l2.append(ring[i] - n * off)
	draw_polyline(l1, use_col, sub_w, false)
	draw_polyline(l2, use_col, sub_w, false)

func _ensure_grad_tex() -> Texture2D:
	if _grad_tex == null and fill_gradient:
		if fill_gradient_type in [3, 4, 5]:
			_grad_tex = _generate_procedural_texture(fill_gradient_type)
		else:
			var gt := GradientTexture2D.new()
			gt.gradient = fill_gradient
			gt.repeat = GradientTexture2D.REPEAT_NONE
			if fill_gradient_type == 1:
				gt.width = 1024
				gt.height = 1024
				gt.fill = GradientTexture2D.FILL_RADIAL
				gt.fill_from = get_gradient_p0_norm()
				gt.fill_to = get_gradient_p1_norm()
			elif fill_gradient_type == 2:
				gt.width = 1024
				gt.height = 1024
				gt.fill = GradientTexture2D.FILL_CONIC
				gt.fill_from = get_gradient_p0_norm()
				gt.fill_to = get_gradient_p1_norm()
			else:
				gt.width = 1024
				gt.height = 1024
				gt.fill = GradientTexture2D.FILL_LINEAR
				gt.fill_from = get_gradient_p0_norm()
				gt.fill_to = get_gradient_p1_norm()
			_grad_tex = gt
	elif _grad_tex and fill_gradient_type in [0, 1, 2]:
		if _grad_tex is GradientTexture2D:
			_grad_tex.fill_from = get_gradient_p0_norm()
			_grad_tex.fill_to = get_gradient_p1_norm()
	elif fill_gradient_type in [3, 4, 5]:
		_grad_tex = _generate_procedural_texture(fill_gradient_type)
	return _grad_tex

func _generate_procedural_texture(type: int) -> ImageTexture:
	if not is_instance_valid(fill_gradient) or fill_gradient.get_point_count() == 0:
		return null
	var res := 512
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	var p0 := get_gradient_p0_norm()
	var p1 := get_gradient_p1_norm()
	var radius := maxf(p0.distance_to(p1), 0.001)
	var dir := (p1 - p0) / radius
	var ang := dir.angle()
	var cos_a := cos(-ang)
	var sin_a := sin(-ang)

	for y in range(res):
		for x in range(res):
			var uv := Vector2(float(x) / float(res - 1), float(y) / float(res - 1))
			var diff := uv - p0
			var rot_diff := Vector2(diff.x * cos_a - diff.y * sin_a, diff.x * sin_a + diff.y * cos_a)
			var t: float = 0.0
			if type == 3: # Diamante / Rombo
				var d := absf(rot_diff.x) + absf(rot_diff.y)
				t = clampf(d / radius, 0.0, 1.0)
			elif type == 4: # Cuadrado / Box
				var d := maxf(absf(rot_diff.x), absf(rot_diff.y))
				t = clampf(d / radius, 0.0, 1.0)
			elif type == 5: # Espiral
				var r := diff.length()
				var angle := diff.angle() - ang
				var norm_angle := fposmod(angle / TAU, 1.0)
				t = fposmod(norm_angle + (r / radius) * 2.0, 1.0)
			img.set_pixel(x, y, fill_gradient.sample(t))
	return ImageTexture.create_from_image(img)

func _gradient_uvs(points: PackedVector2Array) -> PackedVector2Array:
	var bb := _points_bounds(points)
	var uvs := PackedVector2Array()
	var sx := maxf(bb.size.x, 0.001)
	var sy := maxf(bb.size.y, 0.001)
	for p in points:
		uvs.append(Vector2((p.x - bb.position.x) / sx, (p.y - bb.position.y) / sy))
	return uvs

func _points_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var r := Rect2(points[0], Vector2.ZERO)
	for i in range(1, points.size()):
		r = r.expand(points[i])
	return r

## ── Coordenadas de documento en doble precisión (64 bits) ──────────────────
## Fuente de verdad para posición/rotación/tamaño/vértices. Los campos nativos
## de Node2D (position/rotation) y los @export de las subclases (size/vertices)
## quedan como una CACHÉ DE RENDERIZADO de una sola vía: doc-space -> nativo,
## nunca al revés (salvo la sincronización inicial en _ready(), que solo aplica
## si nadie llamó set_doc_*() todavía, p.ej. al cargar una escena guardada).
##
## Una figura NUEVA obtiene esto gratis con solo:
##   1) llamar _register_doc_extent("size", ...) y/o _register_doc_vertices("vertices")
##      una vez en su _init(), y
##   2) usar set_doc_position()/set_doc_extent()/set_doc_vertices() en vez de
##      asignar .position/.size/.vertices directamente.
## MoveTool despacha genéricamente por "shape is VectorShape" + has_doc_extent()/
## has_doc_vertices(), así que no hace falta tocar MoveTool.gd para una figura nueva.
var doc_position: DVec2 = DVec2.new()
var doc_rotation: float = 0.0

var _doc_extent: DVec2 = null
var _doc_extent_field: String = ""
var _doc_vertices: Array[DVec2] = []
var _doc_vertices_field: String = ""

var _doc_position_set: bool = false
var _doc_rotation_set: bool = false
var _doc_extent_set: bool = false
var _doc_vertices_set: bool = false

func _ready() -> void:
	# Sincronización inicial única: si nadie llamó set_doc_*() antes de _ready()
	# (p.ej. esta figura viene de una escena .tscn cargada del disco), doc-space
	# se rellena desde los valores nativos ya cargados. Si una herramienta de
	# creación ya llamó set_doc_*() antes de que el nodo entrara al árbol, esa
	# precisión explícita se respeta y NO se sobreescribe aquí.
	if not _doc_position_set:
		doc_position = DVec2.from_v2(position)
	if not _doc_rotation_set:
		doc_rotation = rotation
	if has_doc_extent() and not _doc_extent_set:
		_doc_extent = DVec2.from_v2(get(_doc_extent_field))
	if has_doc_vertices() and not _doc_vertices_set:
		_doc_vertices = DVec2.array_from_v2(get(_doc_vertices_field))

func get_doc_position() -> DVec2:
	return doc_position

func set_doc_position(p: DVec2) -> void:
	doc_position = p
	_doc_position_set = true
	position = p.to_v2()
	queue_redraw()

func get_doc_rotation() -> float:
	return doc_rotation

func set_doc_rotation(r: float) -> void:
	doc_rotation = r
	_doc_rotation_set = true
	rotation = r
	queue_redraw()

func _register_doc_extent(native_field: String) -> void:
	_doc_extent_field = native_field
	_doc_extent = DVec2.new()

func has_doc_extent() -> bool:
	return _doc_extent_field != ""

func get_doc_extent() -> DVec2:
	return _doc_extent

func set_doc_extent(e: DVec2) -> void:
	_doc_extent = e
	_doc_extent_set = true
	if _doc_extent_field != "":
		set(_doc_extent_field, e.to_v2())
	queue_redraw()

func _register_doc_vertices(native_field: String) -> void:
	_doc_vertices_field = native_field

func has_doc_vertices() -> bool:
	return _doc_vertices_field != ""

func get_doc_vertices() -> Array[DVec2]:
	return _doc_vertices

func set_doc_vertices(v: Array[DVec2]) -> void:
	_doc_vertices = v
	_doc_vertices_set = true
	if _doc_vertices_field != "":
		var packed := PackedVector2Array()
		for dv in v:
			packed.append(dv.to_v2())
		set(_doc_vertices_field, packed)
	queue_redraw()

func set_selected(selected: bool) -> void:
	is_selected = selected
	if selected:
		modulate = Color(1.2, 1.2, 1.2, 1.0)
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)
	queue_redraw()

func get_state() -> Dictionary:
	return {
		"id": object_id,
		"position": position,
		"rotation": rotation,
		"scale": scale,
		"fill_color": fill_color,
		"stroke_color": stroke_color,
		"stroke_width": stroke_width,
		"effects": effects.duplicate(true),
	}

func serialize() -> Dictionary:
	return get_state()

func to_svg() -> String:
	return ""

func _draw() -> void:
	pass
