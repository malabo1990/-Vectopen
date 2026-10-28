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

const StrokePaint = preload("res://script_gdscript/shapes/stroke_paint.gd")

## ── Degradado en el trazo (opcional) ──────────────────────────────────────
## Con >= 2 puntos el trazo se pinta con este degradado (0 lineal, 1 radial)
## en vez de `stroke_color`. Ver StrokePaint.
@export var stroke_gradient: Gradient = null:
	set(v):
		if stroke_gradient and stroke_gradient.changed.is_connected(queue_redraw):
			stroke_gradient.changed.disconnect(queue_redraw)
		stroke_gradient = v
		if stroke_gradient and not stroke_gradient.changed.is_connected(queue_redraw):
			stroke_gradient.changed.connect(queue_redraw)
		queue_redraw()
@export var stroke_gradient_type: int = 0:
	set(v):
		stroke_gradient_type = v
		queue_redraw()
@export var stroke_gradient_angle: float = 0.0:
	set(v):
		stroke_gradient_angle = v
		queue_redraw()

func has_gradient_stroke() -> bool:
	return stroke_gradient != null and stroke_gradient.get_point_count() >= 2

func clear_stroke_gradient() -> void:
	stroke_gradient = null

func stroke_colors_for(points: PackedVector2Array) -> PackedColorArray:
	return StrokePaint.colors_for(points, stroke_gradient, stroke_gradient_type, stroke_gradient_angle)

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
	if fill_gradient_type in [1, 2, 3, 4, 5, 6]:
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
	if _grad_tex is GradientTexture2D and fill_gradient_type in [0, 2]:
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
	if _grad_tex is GradientTexture2D and fill_gradient_type in [0, 2]:
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
	if _grad_tex is GradientTexture2D and fill_gradient_type in [0, 2]:
		_grad_tex.fill_from = p0_norm
		_grad_tex.fill_to = p1_norm
	else:
		_grad_tex = null
	queue_redraw()

var _grad_tex: Texture2D = null

var is_selected: bool = false
@export var effects: Array = []:
	set(v):
		effects = v
		if effects.is_empty():
			if _shadow_ci.is_valid():
				RenderingServer.canvas_item_clear(_shadow_ci)
			if _inner_shadow_ci.is_valid():
				RenderingServer.canvas_item_clear(_inner_shadow_ci)
			if _bevel_3d_ci.is_valid():
				RenderingServer.canvas_item_clear(_bevel_3d_ci)
			if _inner_glow_ci.is_valid():
				RenderingServer.canvas_item_clear(_inner_glow_ci)
			_clear_extra_fx("ds", 0)
			_clear_extra_fx("is", 0)
		queue_redraw()

static var _shadow_shader: Shader = null
static var _blur_shader: Shader = null
static var _inner_shadow_shader: Shader = null
static var _bevel_3d_shader: Shader = null
var _shadow_mat: ShaderMaterial = null
var _blur_mat: ShaderMaterial = null
var _inner_shadow_mat: ShaderMaterial = null
var _bevel_3d_mat: ShaderMaterial = null
var _shadow_ci: RID = RID()
var _inner_shadow_ci: RID = RID()
var _bevel_3d_ci: RID = RID()
## Brillo interior: capa y material PROPIOS (antes compartía los de la sombra
## interior y se borraba al final del mismo dibujo si no había sombra interior).
var _inner_glow_ci: RID = RID()
var _inner_glow_mat: ShaderMaterial = null
## 2.ª, 3.ª… sombra proyectada ("ds1"…) e interior ("is1"…): capa y material
## PROPIOS por sombra. Antes había una sola capa: la sombra proyectada pintaba
## solo la primera de la lista y la interior solo la última.
var _extra_fx_cis: Dictionary = {}
var _extra_fx_mats: Dictionary = {}

func _extra_fx_ci(key: String, draw_index: int) -> RID:
	var r: RID = _extra_fx_cis.get(key, RID())
	if not r.is_valid() and is_inside_tree():
		r = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(r, get_canvas_item())
		RenderingServer.canvas_item_set_draw_index(r, draw_index)
		_extra_fx_cis[key] = r
	return r

func _extra_fx_mat(key: String, shader: Shader) -> ShaderMaterial:
	var m: ShaderMaterial = _extra_fx_mats.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = shader
		_extra_fx_mats[key] = m
	return m

## Vacía las capas extra `prefix`N que sobran (N >= `used`).
func _clear_extra_fx(prefix: String, used: int) -> void:
	for k in _extra_fx_cis:
		if String(k).begins_with(prefix) and int(String(k).substr(prefix.length())) >= maxi(used, 1):
			RenderingServer.canvas_item_clear(_extra_fx_cis[k])

func _free_extra_fx() -> void:
	for k in _extra_fx_cis:
		if (_extra_fx_cis[k] as RID).is_valid():
			RenderingServer.free_rid(_extra_fx_cis[k])
	_extra_fx_cis.clear()

func _get_shadow_shader() -> Shader:
	if _shadow_shader == null:
		_shadow_shader = load("res://shaders/vector_shadow_sdf.gdshader")
	return _shadow_shader

func _get_shadow_material() -> ShaderMaterial:
	if _shadow_mat == null:
		_shadow_mat = ShaderMaterial.new()
		_shadow_mat.shader = _get_shadow_shader()
	return _shadow_mat

func _get_blur_shader() -> Shader:
	if _blur_shader == null:
		_blur_shader = load("res://shaders/vector_blur_sdf.gdshader")
	return _blur_shader

func _get_blur_material() -> ShaderMaterial:
	if _blur_mat == null:
		_blur_mat = ShaderMaterial.new()
		_blur_mat.shader = _get_blur_shader()
	return _blur_mat

func _get_inner_shadow_shader() -> Shader:
	if _inner_shadow_shader == null:
		_inner_shadow_shader = load("res://shaders/vector_inner_shadow_sdf.gdshader")
	return _inner_shadow_shader

func _get_inner_shadow_material() -> ShaderMaterial:
	if _inner_shadow_mat == null:
		_inner_shadow_mat = ShaderMaterial.new()
		_inner_shadow_mat.shader = _get_inner_shadow_shader()
	return _inner_shadow_mat

func _get_bevel_3d_shader() -> Shader:
	if _bevel_3d_shader == null:
		_bevel_3d_shader = load("res://shaders/vector_3d_bevel_sdf.gdshader")
	return _bevel_3d_shader

func _get_bevel_3d_material() -> ShaderMaterial:
	if _bevel_3d_mat == null:
		_bevel_3d_mat = ShaderMaterial.new()
		_bevel_3d_mat.shader = _get_bevel_3d_shader()
	return _bevel_3d_mat

func _ensure_bevel_3d_ci() -> bool:
	if not is_inside_tree():
		return false
	if not _bevel_3d_ci.is_valid():
		_bevel_3d_ci = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(_bevel_3d_ci, get_canvas_item())
		RenderingServer.canvas_item_set_draw_index(_bevel_3d_ci, 2)
	return _bevel_3d_ci.is_valid()

func _exit_tree() -> void:
	if _shadow_ci.is_valid():
		RenderingServer.free_rid(_shadow_ci)
		_shadow_ci = RID()
	if _inner_shadow_ci.is_valid():
		RenderingServer.free_rid(_inner_shadow_ci)
		_inner_shadow_ci = RID()
	if _bevel_3d_ci.is_valid():
		RenderingServer.free_rid(_bevel_3d_ci)
		_bevel_3d_ci = RID()
	if _inner_glow_ci.is_valid():
		RenderingServer.free_rid(_inner_glow_ci)
		_inner_glow_ci = RID()
	_free_extra_fx()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and not _light_store.is_empty():
		_update_light_dirs()
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		FxPolyGpu.free_all(_light_store)
	if what == NOTIFICATION_PREDELETE:
		_free_extra_fx()
		if _shadow_ci.is_valid():
			RenderingServer.free_rid(_shadow_ci)
			_shadow_ci = RID()
		if _inner_shadow_ci.is_valid():
			RenderingServer.free_rid(_inner_shadow_ci)
			_inner_shadow_ci = RID()
		if _bevel_3d_ci.is_valid():
			RenderingServer.free_rid(_bevel_3d_ci)
			_bevel_3d_ci = RID()
		if _inner_glow_ci.is_valid():
			RenderingServer.free_rid(_inner_glow_ci)
			_inner_glow_ci = RID()

## Retorna los puntos de contorno de la figura para efectos
func get_effect_points() -> PackedVector2Array:
	return PackedVector2Array()

## Retorna la geometría evaluada en coordenadas locales (GeometryProvider)
func get_evaluated_geometry() -> Array[PackedVector2Array]:
	var pts := get_effect_points()
	if pts.is_empty():
		return []
	return [pts]


## Métodos polimórficos de geometría para los shaders SDF (subclases los sobreescriben)
func get_shape_type_code() -> int:
	return 2 # 0: Rect, 1: Circle, 2: Polygon

func get_shape_corner_radii() -> Vector4:
	return Vector4.ZERO

func get_shape_size() -> Vector2:
	if "size" in self:
		return self.size
	return Vector2(100.0, 100.0)

func get_local_bounding_box(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2(-50.0, -50.0, 100.0, 100.0)
	var min_p := points[0]
	var max_p := points[0]
	for i in range(1, points.size()):
		var p := points[i]
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	return Rect2(min_p, max_p - min_p)

func _subsample_points(pts: PackedVector2Array, max_pts: int = 64) -> PackedVector2Array:
	if pts.size() <= max_pts:
		return pts
	var step: float = float(pts.size()) / float(max_pts)
	var sampled := PackedVector2Array()
	for i in range(max_pts):
		sampled.append(pts[int(i * step)])
	return sampled

func _on_fill_gradient_changed() -> void:
	_grad_tex = null
	queue_redraw()

func has_gradient_fill() -> bool:
	return fill_gradient != null and fill_gradient.get_point_count() >= 2

func clear_fill_gradient() -> void:
	fill_gradient = null
	_grad_tex = null
	queue_redraw()

## Dibuja efectos que van detrás del relleno de la figura (Drop Shadow, 3D Extrusión).
func draw_effects_shadows(points: PackedVector2Array) -> void:
	if effects.is_empty() or points.size() < 3:
		if _shadow_ci.is_valid():
			RenderingServer.canvas_item_clear(_shadow_ci)
		_clear_extra_fx("ds", 0)
		return

	var ds_list: Array = []
	var threed_fx: Dictionary = {}
	for fx in FxLight.migrate_list(effects):
		if fx is Dictionary and bool(fx.get("enabled", true)):
			var type: String = FxLight.canonical(String(fx.get("type", "")))
			if type == "drop_shadow":
				ds_list.append(fx)
			elif type == "extrusion" and threed_fx.is_empty():
				threed_fx = fx

	# 1. Drop shadow (GPU SDF con fallback CPU): TODAS las de la lista
	for i in ds_list.size():
		if not _ensure_shadow_ci():
			_render_drop_shadow_fallback(points, ds_list[i])
		elif i == 0:
			_render_drop_shadow_gpu(points, ds_list[i])
		else:
			var key := "ds%d" % i
			_render_drop_shadow_gpu(points, ds_list[i], _extra_fx_ci(key, -1), _extra_fx_mat(key, _get_shadow_shader()))
	if ds_list.is_empty() and _shadow_ci.is_valid():
		RenderingServer.canvas_item_clear(_shadow_ci)
	_clear_extra_fx("ds", ds_list.size())

	# 2. Extrusión (efecto propio, detrás de la figura)
	if not threed_fx.is_empty():
		_render_3d_extrusion(points, threed_fx)

func _ensure_shadow_ci() -> bool:
	if not is_inside_tree():
		return false
	if not _shadow_ci.is_valid():
		_shadow_ci = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(_shadow_ci, get_canvas_item())
		RenderingServer.canvas_item_set_draw_index(_shadow_ci, -1)
	return _shadow_ci.is_valid()

func _ensure_inner_shadow_ci() -> bool:
	if not is_inside_tree():
		return false
	if not _inner_shadow_ci.is_valid():
		_inner_shadow_ci = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(_inner_shadow_ci, get_canvas_item())
		RenderingServer.canvas_item_set_draw_index(_inner_shadow_ci, 1)
	return _inner_shadow_ci.is_valid()

const FxPolyGpu = preload("res://script_gdscript/shapes/fx_poly_gpu.gd")
const FxLight = preload("res://script_gdscript/shapes/fx_light.gd")
## Canvas items / materiales de 3D y Bisel y relieve (dos pasadas cada uno:
## sombras en multiplicar y luces en trama, como Photoshop).
var _light_store: Dictionary = {}

func _render_light_fx(points: PackedVector2Array, fx: Dictionary, key: String) -> void:
	var box := get_local_bounding_box(points).grow(FxLight.outer_margin(fx))
	var idx := 3
	for pass_name in ["mul", "scr"]:
		var ci := FxPolyGpu._ci(self, _light_store, key + pass_name, idx)
		idx += 1
		RenderingServer.canvas_item_clear(ci)
		var m := FxPolyGpu._mat(_light_store, key + pass_name, "res://shaders/vector_light_%s.gdshader" % pass_name)
		set_fx_shape_uniforms(m, points, 0.0)
		FxLight.set_uniforms(m, self, fx)
		RenderingServer.canvas_item_set_material(ci, m.get_rid())
		RenderingServer.canvas_item_add_rect(ci, box, Color.WHITE)
	_light_store[key + "_fx"] = fx
	# la luz es del lienzo: al girar la figura se recalcula su dirección local
	set_notify_transform(true)

func _update_light_dirs() -> void:
	for key in ["3d", "bevel_emboss"]:
		var fx = _light_store.get(key + "_fx")
		if not (fx is Dictionary):
			continue
		var d := FxLight.LIGHT_3D if key == "3d" else FxLight.BEVEL
		var dir := FxLight.light_dir(self, float(fx.get("azimuth", d["azimuth"])), float(fx.get("elevation", d["elevation"])))
		for pass_name in ["mul", "scr"]:
			var m: ShaderMaterial = _light_store.get(key + pass_name + "_mat")
			if m:
				m.set_shader_parameter("u_light_dir", dir)

## Uniforms de la figura para los shaders de efectos (fx_gauss): tipo,
## tamaño / radios y, en polígonos, los puntos (crecidos `pregrow` en CPU:
## sombra con extensión, sombra interior con encogimiento) y su caja.
func set_fx_shape_uniforms(mat: ShaderMaterial, points: PackedVector2Array, pregrow: float) -> void:
	var shape_code: int = get_shape_type_code()
	mat.set_shader_parameter("u_shape_type", shape_code)
	mat.set_shader_parameter("u_poly_pregrow", 0.0)
	if shape_code == 0:
		mat.set_shader_parameter("u_rect_size", get_shape_size())
		mat.set_shader_parameter("u_corner_radii", get_shape_corner_radii())
	elif shape_code == 1:
		mat.set_shader_parameter("u_radii", get_shape_size() * 0.5)
	else:
		var orig: PackedVector2Array = _subsample_points(points, 64)
		var oarr: Array[Vector2] = []
		for q in orig:
			oarr.append(q)
		mat.set_shader_parameter("u_orig_points", oarr)
		mat.set_shader_parameter("u_orig_count", orig.size())
		var src := points
		if absf(pregrow) > 0.01:
			var grown := Geometry2D.offset_polygon(points, pregrow, Geometry2D.JOIN_ROUND)
			var best := PackedVector2Array()
			for g in grown:
				if g.size() > best.size():
					best = g
			if best.size() >= 3:
				src = best
				mat.set_shader_parameter("u_poly_pregrow", pregrow)
		var pts: PackedVector2Array = _subsample_points(src, 64)
		var count: int = mini(pts.size(), 64)
		mat.set_shader_parameter("u_poly_count", count)
		var arr: Array[Vector2] = []
		var lo := pts[0] if count > 0 else Vector2.ZERO
		var hi := lo
		for i in range(count):
			arr.append(pts[i])
			lo = lo.min(pts[i])
			hi = hi.max(pts[i])
		mat.set_shader_parameter("u_poly_points", arr)
		mat.set_shader_parameter("u_poly_bounds", Vector4(lo.x, lo.y, hi.x, hi.y))

func _render_drop_shadow_gpu(points: PackedVector2Array, fx: Dictionary, ci: RID = RID(), mat_in: ShaderMaterial = null) -> void:
	if not ci.is_valid():
		ci = _shadow_ci
	var offset := Vector2(float(fx.get("offset_x", 4.0)), float(fx.get("offset_y", 4.0)))
	var blur := maxf(0.0, float(fx.get("blur", 6.0)))
	var spread := float(fx.get("spread", 0.0))
	var base_col := _parse_fx_color(fx.get("color", null), Color(0.0, 0.0, 0.0, 0.4))

	if base_col.a <= 0.001:
		RenderingServer.canvas_item_clear(ci)
		return

	var mat := mat_in if mat_in != null else _get_shadow_material()
	var shape_code: int = get_shape_type_code()
	set_fx_shape_uniforms(mat, points, spread if shape_code == 2 else 0.0)

	mat.set_shader_parameter("u_shadow_offset", offset)
	mat.set_shader_parameter("u_blur", blur)
	mat.set_shader_parameter("u_spread", spread)
	mat.set_shader_parameter("u_shadow_color", base_col)

	# El halo gaussiano llega a 3σ = 1,5 × desenfoque: el quad lo cubre entero.
	var margin: float = blur * 1.6 + maxf(0.0, spread) + 4.0
	var box: Rect2 = get_local_bounding_box(points)
	var quad: Rect2 = box.grow(margin)
	quad.position += offset

	RenderingServer.canvas_item_clear(ci)
	RenderingServer.canvas_item_set_material(ci, mat.get_rid())
	RenderingServer.canvas_item_add_rect(ci, quad, Color.WHITE)

func _render_drop_shadow_fallback(points: PackedVector2Array, fx: Dictionary) -> void:
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
				var outside := Geometry2D.clip_polygons(poly, points)
				for out_p in outside:
					if out_p.size() >= 3:
						draw_colored_polygon(out_p, base_col)
		else:
			var outside := Geometry2D.clip_polygons(shifted, points)
			for out_p in outside:
				if out_p.size() >= 3:
					draw_colored_polygon(out_p, base_col)
		return

	# Falloff multi-paso de alta densidad (22 pasadas con curva Gaussiana continua)
	var passes: int = clampi(int(blur * 1.5), 12, 24)
	var max_expand: float = blur * 1.4 + spread
	var min_expand: float = spread - blur * 0.15

	for i in range(passes):
		var t: float = float(i) / float(passes - 1) if passes > 1 else 0.0
		var exp_dist: float = lerpf(min_expand, max_expand, t)
		var factor: float = exp(-2.5 * t * t)
		var pass_alpha: float = (base_col.a / float(passes)) * factor * 1.85
		pass_alpha = clampf(pass_alpha, 0.002, 1.0)
		var pass_col := Color(base_col.r, base_col.g, base_col.b, pass_alpha)

		var offset_pts := Geometry2D.offset_polygon(points, exp_dist, Geometry2D.JOIN_ROUND)
		if offset_pts.is_empty():
			continue
		for poly in offset_pts:
			if poly.size() >= 3:
				var translated := PackedVector2Array()
				for pt in poly:
					translated.append(pt + offset)
				var outside := Geometry2D.clip_polygons(translated, points)
				for out_p in outside:
					if out_p.size() >= 3:
						draw_colored_polygon(out_p, pass_col)

## Comprueba si el efecto Blur está activo y lo renderiza con el shader Gaussiano SDF.
func maybe_render_blur(points: PackedVector2Array) -> bool:
	var blur_fx: Dictionary = {}
	for fx in effects:
		if fx is Dictionary and bool(fx.get("enabled", true)):
			var type: String = String(fx.get("type", "")).to_lower().replace(" ", "_")
			if type == "blur":
				blur_fx = fx
				break

	if blur_fx.is_empty():
		if material == _blur_mat and _blur_mat != null:
			material = null
		return false

	var radius: float = maxf(0.0, float(blur_fx.get("radius", 5.0)))
	var preserve_alpha: bool = bool(blur_fx.get("preserve_alpha", false))

	if radius <= 0.1:
		if material == _blur_mat and _blur_mat != null:
			material = null
		return false

	var mat := _get_blur_material()
	material = mat

	var shape_code: int = get_shape_type_code()
	set_fx_shape_uniforms(mat, points, 0.0)

	mat.set_shader_parameter("u_blur_radius", radius)
	mat.set_shader_parameter("u_preserve_alpha", preserve_alpha)
	var btype: int = ["gaussian", "motion", "radial", "spin"].find(String(blur_fx.get("blur_type", "gaussian")))
	btype = maxi(0, btype)
	var bang := deg_to_rad(float(blur_fx.get("angle", 0.0)))
	mat.set_shader_parameter("u_blur_type", btype)
	mat.set_shader_parameter("u_motion_dir", Vector2(cos(bang), sin(bang)))
	var cbox := get_local_bounding_box(points)
	mat.set_shader_parameter("u_center", cbox.get_center())
	mat.set_shader_parameter("u_fill_color", fill_color)
	mat.set_shader_parameter("u_stroke_color", stroke_color)
	mat.set_shader_parameter("u_stroke_width", stroke_width)

	# Halo gaussiano completo (3σ = 1,5 × radio) + medio trazo. Antes 1,1 ×
	# radio: el desenfoque se cortaba en el borde del quad.
	var margin: float = (radius * 1.6 + stroke_width * 0.5 + 4.0) if not preserve_alpha else stroke_width * 0.5 + 2.0
	if btype == 1:
		margin = radius + 2.0
	elif btype == 2:
		margin = cbox.size.length() * 0.5 * radius / 100.0 + 4.0
	elif btype == 3:
		margin = cbox.size.length() * 0.5 * (1.0 - cos(minf(PI, deg_to_rad(radius) * 0.5))) + cbox.size.length() * 0.25 + 4.0
	var box: Rect2 = get_local_bounding_box(points)
	var quad: Rect2 = box.grow(margin)
	draw_rect(quad, Color.WHITE)
	return true

## Dibuja efectos superpuestos (Inner Shadow, Outline, Color Overlay, Inner Glow, 3D Bevel) después del contorno.
func draw_effects_overlays(points: PackedVector2Array) -> void:
	if effects.is_empty() or points.size() < 3:
		if _inner_shadow_ci.is_valid():
			RenderingServer.canvas_item_clear(_inner_shadow_ci)
		if _bevel_3d_ci.is_valid():
			RenderingServer.canvas_item_clear(_bevel_3d_ci)
		if _inner_glow_ci.is_valid():
			RenderingServer.canvas_item_clear(_inner_glow_ci)
		_clear_extra_fx("is", 0)
		for k in ["3d", "bevel_emboss"]:
			FxPolyGpu.clear(_light_store, k + "mul")
			FxPolyGpu.clear(_light_store, k + "scr")
		return

	var has_inner_shadow: bool = false
	var inner_n: int = 0
	var has_inner_glow: bool = false
	var has_3d: bool = false
	var light_used: Array = []
	for fx in FxLight.migrate_list(effects):
		if not (fx is Dictionary):
			continue
		if not bool(fx.get("enabled", true)):
			continue
		var type: String = FxLight.canonical(String(fx.get("type", "")))
		match type:
			"inner_shadow":
				has_inner_shadow = true
				if not _ensure_inner_shadow_ci():
					_render_inner_shadow_fallback(points, fx)
				elif inner_n == 0:
					_render_inner_shadow_gpu(points, fx)
				else:
					var key := "is%d" % inner_n
					_render_inner_shadow_gpu(points, fx, _extra_fx_ci(key, 1), _extra_fx_mat(key, _get_inner_shadow_shader()))
				inner_n += 1
			"outline":
				_render_outline_effect(points, fx)
			"color_overlay":
				_render_color_overlay(points, fx)
			"gradient_overlay":
				_render_gradient_overlay(points, fx)
			"inner_glow":
				has_inner_glow = true
				_render_inner_glow(points, fx)
			"3d", "bevel_emboss":
				# 3D (iluminación, Affinity) / Bisel y relieve (Photoshop)
				if is_inside_tree() and not light_used.has(type):
					light_used.append(type)
					_render_light_fx(points, fx, type)

	for k in ["3d", "bevel_emboss"]:
		if not light_used.has(k):
			FxPolyGpu.clear(_light_store, k + "mul")
			FxPolyGpu.clear(_light_store, k + "scr")
	if not has_inner_shadow and _inner_shadow_ci.is_valid():
		RenderingServer.canvas_item_clear(_inner_shadow_ci)
	_clear_extra_fx("is", inner_n)
	if not has_3d and _bevel_3d_ci.is_valid():
		RenderingServer.canvas_item_clear(_bevel_3d_ci)
	if not has_inner_glow and _inner_glow_ci.is_valid():
		RenderingServer.canvas_item_clear(_inner_glow_ci)

func _parse_fx_color(val: Variant, default_col: Color) -> Color:
	if val is Color:
		return val
	if val is String:
		return Color.from_string(val, default_col)
	if val is Array and val.size() >= 3:
		var a: float = float(val[3]) if val.size() >= 4 else 1.0
		return Color(float(val[0]), float(val[1]), float(val[2]), a)
	return default_col

func _render_inner_shadow_gpu(points: PackedVector2Array, fx: Dictionary, ci: RID = RID(), mat_in: ShaderMaterial = null) -> void:
	if not ci.is_valid():
		ci = _inner_shadow_ci
	var offset := Vector2(float(fx.get("offset_x", 2.0)), float(fx.get("offset_y", 2.0)))
	var blur := maxf(0.0, float(fx.get("blur", 4.0)))
	var spread := float(fx.get("spread", fx.get("choke", 0.0)))
	var base_col := _parse_fx_color(fx.get("color", null), Color(0.0, 0.0, 0.0, 0.5))

	if base_col.a <= 0.001:
		RenderingServer.canvas_item_clear(ci)
		return

	var mat := mat_in if mat_in != null else _get_inner_shadow_material()
	var shape_code: int = get_shape_type_code()
	set_fx_shape_uniforms(mat, points, -spread if shape_code == 2 else 0.0)

	mat.set_shader_parameter("u_offset", offset)
	mat.set_shader_parameter("u_blur", blur)
	mat.set_shader_parameter("u_spread", spread)
	mat.set_shader_parameter("u_shadow_color", base_col)

	var box: Rect2 = get_local_bounding_box(points)
	RenderingServer.canvas_item_clear(ci)
	RenderingServer.canvas_item_set_material(ci, mat.get_rid())
	RenderingServer.canvas_item_add_rect(ci, box.grow(2.0), Color.WHITE)

func _render_inner_shadow_fallback(points: PackedVector2Array, fx: Dictionary) -> void:
	var offset := Vector2(float(fx.get("offset_x", 2.0)), float(fx.get("offset_y", 2.0)))
	var blur := maxf(0.5, float(fx.get("blur", 4.0)))
	var spread := float(fx.get("spread", fx.get("choke", 0.0)))
	var base_col := _parse_fx_color(fx.get("color", null), Color(0.0, 0.0, 0.0, 0.5))
	if base_col.a <= 0.001 or points.size() < 3:
		return

	var passes: int = clampi(int(blur * 1.5), 8, 20)
	for i in range(passes):
		var t: float = float(i) / float(passes - 1) if passes > 1 else 0.0
		var inward: float = lerpf(0.0, blur * 1.2, t)
		var factor: float = exp(-2.2 * t * t)
		var pass_alpha: float = (base_col.a / float(passes)) * factor * 2.0
		pass_alpha = clampf(pass_alpha, 0.002, 1.0)
		var pass_col := Color(base_col.r, base_col.g, base_col.b, pass_alpha)

		var shifted := PackedVector2Array()
		for pt in points:
			shifted.append(pt + offset)

		var caster_polys: Array[PackedVector2Array]
		var total_offset: float = spread - inward
		if absf(total_offset) > 0.05:
			caster_polys = Geometry2D.offset_polygon(shifted, -total_offset, Geometry2D.JOIN_ROUND)
		else:
			caster_polys = [shifted]

		if caster_polys.is_empty():
			draw_colored_polygon(points, pass_col)
		else:
			for caster in caster_polys:
				if caster.size() >= 3:
					var crescents := Geometry2D.clip_polygons(points, caster)
					for cres in crescents:
						if cres.size() >= 3:
							draw_colored_polygon(cres, pass_col)

func _render_outline_effect(points: PackedVector2Array, fx: Dictionary) -> void:
	var width := maxf(0.5, float(fx.get("width", 2.0)))
	var col := _parse_fx_color(fx.get("color", null), Color.BLACK)
	if col.a <= 0.001:
		return
	# Contorno EXTERIOR (como en Photoshop / Illustrator): banda de `width`
	# pegada por fuera del borde. Antes iba centrado en el borde, encima del
	# trazo de la figura, y apenas se notaba.
	var outer := Geometry2D.offset_polygon(points, width * 0.5, Geometry2D.JOIN_ROUND)
	if outer.is_empty():
		outer = [points]
	for poly in outer:
		var ring := PackedVector2Array(poly)
		if ring.size() < 2:
			continue
		ring.append(ring[0])
		draw_polyline(ring, col, width, true)

func _render_color_overlay(points: PackedVector2Array, fx: Dictionary) -> void:
	var col := _parse_fx_color(fx.get("color", null), Color(1.0, 0.0, 0.0, 1.0))
	var opacity := clampf(float(fx.get("opacity", 1.0)), 0.0, 1.0)
	var final_col := Color(col.r, col.g, col.b, col.a * opacity)
	if final_col.a <= 0.001:
		return
	draw_colored_polygon(points, final_col)

func _render_gradient_overlay(points: PackedVector2Array, fx: Dictionary) -> void:
	var opacity := clampf(float(fx.get("opacity", 1.0)), 0.0, 1.0)
	if opacity <= 0.001:
		return
	# Degradado PROPIO del efecto (colores, posiciones y ángulo). Antes solo
	# funcionaba si la figura ya tenía relleno degradado y no usaba el ángulo.
	var tex: Texture2D = load("res://script_gdscript/text/text_fx.gd")._gradient_texture(fx)
	var box := get_local_bounding_box(points)
	var uvs := PackedVector2Array()
	uvs.resize(points.size())
	for i in points.size():
		uvs[i] = (points[i] - box.position) / Vector2(maxf(box.size.x, 0.001), maxf(box.size.y, 0.001))
	draw_colored_polygon(points, Color(1, 1, 1, opacity), uvs, tex)

func _render_inner_glow(points: PackedVector2Array, fx: Dictionary) -> void:
	var col := _parse_fx_color(fx.get("color", null), Color.WHITE)
	# El panel envía radius / opacity (antes se leía "intensity", que el
	# panel no tiene: los controles no hacían nada).
	var radius := maxf(0.5, float(fx.get("radius", 8.0 * float(fx.get("intensity", 1.0)))))
	var opacity := clampf(float(fx.get("opacity", 1.0)), 0.0, 1.0)
	# Brillo interior: pleno en el borde y se apaga hacia dentro en ~radio
	# (sombra interior sin desplazar, con el emisor encogido 2σ).
	var glow_fx := {
		"offset_x": 0.0,
		"offset_y": 0.0,
		"blur": radius * 0.5,
		"spread": radius * 0.5,
		"color": Color(col.r, col.g, col.b, clampf(col.a * opacity, 0.0, 1.0)),
	}
	if is_inside_tree():
		if not _inner_glow_ci.is_valid():
			_inner_glow_ci = RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(_inner_glow_ci, get_canvas_item())
			RenderingServer.canvas_item_set_draw_index(_inner_glow_ci, 1)
		if _inner_glow_mat == null:
			_inner_glow_mat = ShaderMaterial.new()
			_inner_glow_mat.shader = _get_inner_shadow_shader()
		_render_inner_shadow_gpu(points, glow_fx, _inner_glow_ci, _inner_glow_mat)
	else:
		_render_inner_shadow_fallback(points, glow_fx)

func _render_3d_extrusion(points: PackedVector2Array, fx: Dictionary) -> void:
	# Malla con paredes iluminadas por una luz fija y degradado de profundidad
	# (fx_extrude.gd). Antes la luz iba opuesta a la extrusión: todas las
	# paredes visibles salían casi igual de oscuras y parecía una sombra.
	if points.size() < 3:
		return
	var base_col: Color = fill_color if fill_color.a > 0.05 else (stroke_color if stroke_color.a > 0.05 else Color(0.5, 0.5, 0.5, 1.0))
	var key := var_to_str([fx, base_col, points.size(), points[0], points[points.size() / 2]])
	if key != _extrude_key:
		_extrude_key = key
		_extrude_mesh = load("res://script_gdscript/shapes/fx_extrude.gd").build([points], [points], fx, base_col)
	if _extrude_mesh:
		draw_mesh(_extrude_mesh, null)

var _extrude_mesh: ArrayMesh = null
var _extrude_key := ""

func _render_3d_bevel_gpu(points: PackedVector2Array, fx: Dictionary) -> void:
	if points.size() < 3:
		RenderingServer.canvas_item_clear(_bevel_3d_ci)
		return
	var bevel_size: float = maxf(0.0, float(fx.get("bevel", 8.0)))
	if bevel_size <= 0.2:
		RenderingServer.canvas_item_clear(_bevel_3d_ci)
		return

	var depth: float = float(fx.get("depth", 8.0))
	var angle_deg: float = float(fx.get("angle", 45.0))
	var highlight_pct: float = clampf(float(fx.get("highlight", 70.0)), 0.0, 100.0)
	var shadow_pct: float = clampf(float(fx.get("shadow", 60.0)), 0.0, 100.0)
	var contour: int = clampi(int(fx.get("contour", 0)), 0, 4)

	var mat := _get_bevel_3d_material()
	var shape_code: int = get_shape_type_code()
	mat.set_shader_parameter("u_shape_type", shape_code)

	if shape_code == 0:
		mat.set_shader_parameter("u_rect_size", get_shape_size())
		mat.set_shader_parameter("u_corner_radii", get_shape_corner_radii())
	elif shape_code == 1:
		mat.set_shader_parameter("u_radii", get_shape_size() * 0.5)
	else:
		var pts: PackedVector2Array = _subsample_points(points, 64)
		var count: int = mini(pts.size(), 64)
		mat.set_shader_parameter("u_poly_count", count)
		var arr: Array[Vector2] = []
		for i in range(count):
			arr.append(pts[i])
		mat.set_shader_parameter("u_poly_points", arr)

	mat.set_shader_parameter("u_depth", depth)
	mat.set_shader_parameter("u_bevel", bevel_size)
	mat.set_shader_parameter("u_angle", angle_deg)
	mat.set_shader_parameter("u_highlight", highlight_pct)
	mat.set_shader_parameter("u_shadow", shadow_pct)
	mat.set_shader_parameter("u_contour", contour)

	var box: Rect2 = get_local_bounding_box(points)
	RenderingServer.canvas_item_clear(_bevel_3d_ci)
	RenderingServer.canvas_item_set_material(_bevel_3d_ci, mat.get_rid())
	RenderingServer.canvas_item_add_rect(_bevel_3d_ci, box.grow(2.0), Color.WHITE)

func _render_3d_bevel_fallback(points: PackedVector2Array, fx: Dictionary) -> void:
	if points.size() < 3:
		return
	var bevel_size: float = maxf(0.0, float(fx.get("bevel", 8.0)))
	var highlight_pct: float = clampf(float(fx.get("highlight", 70.0)), 0.0, 100.0)
	var shadow_pct: float = clampf(float(fx.get("shadow", 60.0)), 0.0, 100.0)
	var angle_deg: float = float(fx.get("angle", 45.0))
	var rad: float = deg_to_rad(angle_deg)
	var dir := Vector2(cos(rad), sin(rad))
	var light_dir := -dir

	if bevel_size <= 0.2:
		return

	# Bisel suave multi-paso con mayor densidad (16 pases) y decaimiento continuo
	var passes: int = clampi(int(bevel_size * 1.5), 8, 18)
	for i in range(passes):
		var t0: float = float(i) / float(passes)
		var t1: float = float(i + 1) / float(passes)
		var d0: float = bevel_size * t0
		var d1: float = bevel_size * t1

		var outer_polys: Array[PackedVector2Array]
		if d0 > 0.05:
			outer_polys = Geometry2D.offset_polygon(points, -d0, Geometry2D.JOIN_ROUND)
		else:
			outer_polys = [points]
		if outer_polys.is_empty():
			continue

		var inner_polys := Geometry2D.offset_polygon(points, -d1, Geometry2D.JOIN_ROUND)
		if inner_polys.is_empty():
			continue

		var bands := Geometry2D.clip_polygons(outer_polys[0], inner_polys[0])
		if bands.is_empty():
			continue

		var shift_dist: float = (d1 - d0) * 1.2 + 0.5

		# Highlight
		if highlight_pct > 0.5:
			var shifted_for_hl := PackedVector2Array()
			for pt in inner_polys[0]:
				shifted_for_hl.append(pt - light_dir * shift_dist)
			var hl_alpha: float = (highlight_pct / 100.0) * pow(1.0 - t0, 0.8) * (0.8 / float(passes))
			hl_alpha = clampf(hl_alpha, 0.002, 0.9)
			var hl_col := Color(1.0, 1.0, 1.0, hl_alpha)
			for b_poly in bands:
				var hl_crescents := Geometry2D.clip_polygons(b_poly, shifted_for_hl)
				for cres in hl_crescents:
					if cres.size() >= 3:
						draw_colored_polygon(cres, hl_col)

		# Shadow
		if shadow_pct > 0.5:
			var shifted_for_sh := PackedVector2Array()
			for pt in inner_polys[0]:
				shifted_for_sh.append(pt + light_dir * shift_dist)
			var sh_alpha: float = (shadow_pct / 100.0) * pow(1.0 - t0, 0.8) * (0.8 / float(passes))
			sh_alpha = clampf(sh_alpha, 0.002, 0.9)
			var sh_col := Color(0.0, 0.0, 0.0, sh_alpha)
			for b_poly in bands:
				var sh_crescents := Geometry2D.clip_polygons(b_poly, shifted_for_sh)
				for cres in sh_crescents:
					if cres.size() >= 3:
						draw_colored_polygon(cres, sh_col)

	# Cresta especular suave
	if highlight_pct > 10.0 and points.size() >= 3:
		var shifted_edge := PackedVector2Array()
		for pt in points:
			shifted_edge.append(pt - light_dir * 1.2)
		var edge_hl := Geometry2D.clip_polygons(points, shifted_edge)
		var edge_col := Color(1.0, 1.0, 1.0, clampf((highlight_pct / 100.0) * 0.35, 0.02, 0.7))
		for poly in edge_hl:
			if poly.size() >= 3:
				draw_colored_polygon(poly, edge_col)

func get_svg_filter_attr() -> String:
	# Una drop-shadow() por sombra (CSS las encadena; antes solo la 1.ª).
	var parts: PackedStringArray = []
	for fx in effects:
		if fx is Dictionary and bool(fx.get("enabled", true)):
			var type: String = String(fx.get("type", "")).to_lower().replace(" ", "_")
			if type == "drop_shadow":
				var ox: float = float(fx.get("offset_x", 4.0))
				var oy: float = float(fx.get("offset_y", 4.0))
				var blur: float = float(fx.get("blur", 6.0))
				var col: Color = _parse_fx_color(fx.get("color", null), Color(0, 0, 0, 0.4))
				parts.append("drop-shadow(%.1fpx %.1fpx %.1fpx rgba(%d,%d,%d,%.2f))" % [
					ox, oy, blur, int(col.r * 255), int(col.g * 255), int(col.b * 255), col.a
				])
	return "" if parts.is_empty() else ' style="filter: %s;"' % " ".join(parts)

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
			if has_gradient_stroke():
				var cols := stroke_colors_for(ring)
				if rend_col.a < stroke_color.a and stroke_color.a > 0.0:
					for i in cols.size():
						cols[i].a *= rend_col.a / stroke_color.a
				draw_polyline_colors(ring, cols, rend_w, false)
			else:
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
		if fill_gradient_type in [1, 3, 4, 5, 6]:
			_grad_tex = _generate_procedural_texture(fill_gradient_type)
		else:
			var gt := GradientTexture2D.new()
			gt.gradient = fill_gradient
			gt.repeat = GradientTexture2D.REPEAT_NONE
			if fill_gradient_type == 2:
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
	elif _grad_tex and fill_gradient_type in [0, 2]:
		if _grad_tex is GradientTexture2D:
			_grad_tex.fill_from = get_gradient_p0_norm()
			_grad_tex.fill_to = get_gradient_p1_norm()
	elif fill_gradient_type in [1, 3, 4, 5, 6]:
		_grad_tex = _generate_procedural_texture(fill_gradient_type)
	return _grad_tex

func _generate_procedural_texture(type: int) -> ImageTexture:
	if not is_instance_valid(fill_gradient) or fill_gradient.get_point_count() == 0:
		return null
	var res := 512
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	var p0 := get_gradient_p0_norm()
	var p1 := get_gradient_p1_norm()

	var bb_w := 1.0
	var bb_h := 1.0
	var verts = get("vertices")
	if verts is PackedVector2Array and verts.size() > 0:
		var bb := _points_bounds(verts)
		bb_w = maxf(bb.size.x, 1.0)
		bb_h = maxf(bb.size.y, 1.0)
	else:
		var sz = get("size")
		if sz is Vector2:
			bb_w = maxf(sz.x, 1.0)
			bb_h = maxf(sz.y, 1.0)

	var p0_px := Vector2(p0.x * bb_w, p0.y * bb_h)
	var p1_px := Vector2(p1.x * bb_w, p1.y * bb_h)
	var radius_px := maxf(p0_px.distance_to(p1_px), 0.001)
	var dir_px := (p1_px - p0_px) / radius_px
	var ang := dir_px.angle()
	var cos_a := cos(-ang)
	var sin_a := sin(-ang)

	for y in range(res):
		var py := (float(y) / float(res - 1)) * bb_h
		var dy_px := py - p0_px.y
		for x in range(res):
			var px := (float(x) / float(res - 1)) * bb_w
			var dx_px := px - p0_px.x
			var diff_px := Vector2(dx_px, dy_px)

			var t: float = 0.0
			if type == 1: # Círculo euclidiano perfecto (NUNCA elipse)
				var dist_px := diff_px.length()
				t = clampf(dist_px / radius_px, 0.0, 1.0)
			elif type == 3: # Diamante / Rombo
				var rot_diff := Vector2(diff_px.x * cos_a - diff_px.y * sin_a, diff_px.x * sin_a + diff_px.y * cos_a)
				var d := absf(rot_diff.x) + absf(rot_diff.y)
				t = clampf(d / radius_px, 0.0, 1.0)
			elif type == 4: # Cuadrado / Box (Cubino)
				var rot_diff := Vector2(diff_px.x * cos_a - diff_px.y * sin_a, diff_px.x * sin_a + diff_px.y * cos_a)
				var d := maxf(absf(rot_diff.x), absf(rot_diff.y))
				t = clampf(d / radius_px, 0.0, 1.0)
			elif type == 5: # Espiral de Arquímedes
				var r := diff_px.length()
				var angle := diff_px.angle() - ang
				var norm_angle := fposmod(angle / TAU, 1.0)
				t = fposmod(norm_angle + (r / radius_px) * 2.0, 1.0)
			elif type == 6: # Reflexionado (Espejo simétrico a ambos lados de P0)
				var rot_diff := Vector2(diff_px.x * cos_a - diff_px.y * sin_a, diff_px.x * sin_a + diff_px.y * cos_a)
				t = clampf(absf(rot_diff.x) / radius_px, 0.0, 1.0)

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
