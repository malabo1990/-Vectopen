# =============================================================================
# RUTA: res://script_gdscript/shapes/fx_poly_gpu.gd
# Efectos de TRAZADOS (VectorPath, pluma / Bézier) en GPU con los mismos
# shaders gaussianos exactos que las figuras (fx_gauss): sombra proyectada,
# sombra interior, brillo interior y desenfoque.
# Antes los trazados dibujaban la sombra y el brillo como 12–24 polígonos
# sólidos superpuestos (se veían los "escalones") y el desenfoque no hacía
# nada. `store` es un Dictionary del propio trazado con sus canvas items.
# =============================================================================
extends RefCounted

const SHADOW := "res://shaders/vector_shadow_sdf.gdshader"
const INNER := "res://shaders/vector_inner_shadow_sdf.gdshader"
const BLUR := "res://shaders/vector_blur_sdf.gdshader"

static func _col(v, def: Color) -> Color:
	if v is Color:
		return v
	if v is String:
		return Color.from_string(v, def)
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return def

static func _mat(store: Dictionary, key: String, path: String) -> ShaderMaterial:
	var m: ShaderMaterial = store.get(key + "_mat")
	if m == null:
		m = ShaderMaterial.new()
		m.shader = load(path)
		store[key + "_mat"] = m
	return m

## Canvas item propio (orden: -1 detrás del trazado, 1 delante).
static func _ci(node: CanvasItem, store: Dictionary, key: String, index: int) -> RID:
	var r: RID = store.get(key + "_ci", RID())
	if not r.is_valid():
		r = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(r, node.get_canvas_item())
		RenderingServer.canvas_item_set_draw_index(r, index)
		store[key + "_ci"] = r
	return r

static func clear(store: Dictionary, key: String) -> void:
	var r: RID = store.get(key + "_ci", RID())
	if r.is_valid():
		RenderingServer.canvas_item_clear(r)

static func free_all(store: Dictionary) -> void:
	for k in store.keys():
		if String(k).ends_with("_ci") and (store[k] as RID).is_valid():
			RenderingServer.free_rid(store[k])
	store.clear()

static func _bounds(points: PackedVector2Array) -> Rect2:
	var r := Rect2(points[0], Vector2.ZERO)
	for p in points:
		r = r.expand(p)
	return r

static func _subsample(pts: PackedVector2Array, max_pts: int) -> PackedVector2Array:
	if pts.size() <= max_pts:
		return pts
	var out := PackedVector2Array()
	var stp := float(pts.size()) / float(max_pts)
	for i in max_pts:
		out.append(pts[int(i * stp)])
	return out

## Uniforms de polígono (fx_gauss). `pregrow` = offset aplicado en CPU.
static func set_poly(mat: ShaderMaterial, points: PackedVector2Array, pregrow: float) -> void:
	var src := points
	mat.set_shader_parameter("u_poly_pregrow", 0.0)
	var orig := _subsample(points, 64)
	var oarr: Array[Vector2] = []
	for q in orig:
		oarr.append(q)
	mat.set_shader_parameter("u_orig_points", oarr)
	mat.set_shader_parameter("u_orig_count", orig.size())
	if absf(pregrow) > 0.01:
		var best := PackedVector2Array()
		for g in Geometry2D.offset_polygon(points, pregrow, Geometry2D.JOIN_ROUND):
			if g.size() > best.size():
				best = g
		if best.size() >= 3:
			src = best
			mat.set_shader_parameter("u_poly_pregrow", pregrow)
	var pts := _subsample(src, 64)
	var arr: Array[Vector2] = []
	for p in pts:
		arr.append(p)
	var b := _bounds(pts)
	mat.set_shader_parameter("u_shape_type", 2)
	mat.set_shader_parameter("u_poly_count", pts.size())
	mat.set_shader_parameter("u_poly_points", arr)
	mat.set_shader_parameter("u_poly_bounds", Vector4(b.position.x, b.position.y, b.end.x, b.end.y))

static func drop_shadow(node: CanvasItem, store: Dictionary, points: PackedVector2Array, fx: Dictionary) -> void:
	var ci := _ci(node, store, "shadow", -1)
	RenderingServer.canvas_item_clear(ci)
	var col := _col(fx.get("color"), Color(0, 0, 0, 0.4))
	if col.a <= 0.001 or points.size() < 3:
		return
	var off := Vector2(float(fx.get("offset_x", 4.0)), float(fx.get("offset_y", 4.0)))
	var blur := maxf(0.0, float(fx.get("blur", 6.0)))
	var spread := float(fx.get("spread", 0.0))
	var m := _mat(store, "shadow", SHADOW)
	set_poly(m, points, spread)
	m.set_shader_parameter("u_shadow_offset", off)
	m.set_shader_parameter("u_blur", blur)
	m.set_shader_parameter("u_spread", spread)
	m.set_shader_parameter("u_shadow_color", col)
	var quad := _bounds(points).grow(blur * 1.6 + maxf(0.0, spread) + 4.0)
	quad.position += off
	RenderingServer.canvas_item_set_material(ci, m.get_rid())
	RenderingServer.canvas_item_add_rect(ci, quad, Color.WHITE)

static func inner_shadow(node: CanvasItem, store: Dictionary, key: String, points: PackedVector2Array, fx: Dictionary) -> void:
	var ci := _ci(node, store, key, 1)
	RenderingServer.canvas_item_clear(ci)
	var col := _col(fx.get("color"), Color(0, 0, 0, 0.5))
	if col.a <= 0.001 or points.size() < 3:
		return
	var spread := float(fx.get("spread", fx.get("choke", 0.0)))
	var m := _mat(store, key, INNER)
	set_poly(m, points, -spread)
	m.set_shader_parameter("u_offset", Vector2(float(fx.get("offset_x", 2.0)), float(fx.get("offset_y", 2.0))))
	m.set_shader_parameter("u_blur", maxf(0.0, float(fx.get("blur", 4.0))))
	m.set_shader_parameter("u_spread", spread)
	m.set_shader_parameter("u_shadow_color", col)
	RenderingServer.canvas_item_set_material(ci, m.get_rid())
	RenderingServer.canvas_item_add_rect(ci, _bounds(points).grow(2.0), Color.WHITE)

## Brillo interior = sombra interior sin desplazar con el emisor encogido 2σ.
static func inner_glow(node: CanvasItem, store: Dictionary, points: PackedVector2Array, fx: Dictionary) -> void:
	var c := _col(fx.get("color"), Color.WHITE)
	var radius := maxf(0.5, float(fx.get("radius", 8.0)))
	c.a = clampf(c.a * clampf(float(fx.get("opacity", 1.0)), 0.0, 1.0), 0.0, 1.0)
	inner_shadow(node, store, "glow", points, {"offset_x": 0.0, "offset_y": 0.0, "blur": radius * 0.5, "spread": radius * 0.5, "color": c})

## Desenfoque del trazado cerrado: dibuja SU relleno+trazo desenfocados en
## un canvas item propio. Devuelve false si no hay desenfoque activo.
static func blur(node: CanvasItem, store: Dictionary, points: PackedVector2Array, fx: Dictionary,
		fill: Color, stroke: Color, stroke_w: float) -> bool:
	var radius := maxf(0.0, float(fx.get("radius", 5.0)))
	if radius <= 0.1 or points.size() < 3:
		clear(store, "blur")
		return false
	var ci := _ci(node, store, "blur", 0)
	RenderingServer.canvas_item_clear(ci)
	var m := _mat(store, "blur", BLUR)
	set_poly(m, points, 0.0)
	var bt: int = maxi(0, ["gaussian", "motion", "radial", "spin"].find(String(fx.get("blur_type", "gaussian"))))
	var ang := deg_to_rad(float(fx.get("angle", 0.0)))
	var box := _bounds(points)
	m.set_shader_parameter("u_blur_radius", radius)
	m.set_shader_parameter("u_blur_type", bt)
	m.set_shader_parameter("u_motion_dir", Vector2(cos(ang), sin(ang)))
	m.set_shader_parameter("u_center", box.get_center())
	m.set_shader_parameter("u_preserve_alpha", bool(fx.get("preserve_alpha", false)))
	m.set_shader_parameter("u_fill_color", fill)
	m.set_shader_parameter("u_stroke_color", stroke)
	m.set_shader_parameter("u_stroke_width", stroke_w)
	var margin := radius * 1.6 + stroke_w * 0.5 + 4.0
	if bt == 2:
		margin = box.size.length() * 0.5 * radius / 100.0 + 4.0
	elif bt == 3:
		margin = box.size.length() * 0.75 + 4.0
	RenderingServer.canvas_item_set_material(ci, m.get_rid())
	RenderingServer.canvas_item_add_rect(ci, box.grow(margin), Color.WHITE)
	return true

## 3D (iluminación) / Bisel y relieve de un trazado cerrado: dos pasadas
## (sombras en multiplicar, luces en trama) con vector_light_*.gdshader.
static func light(node: CanvasItem, store: Dictionary, points: PackedVector2Array, fx: Dictionary, key: String) -> void:
	var FxLight = load("res://script_gdscript/shapes/fx_light.gd")
	var box := _bounds(points).grow(FxLight.outer_margin(fx))
	var idx := 3
	for pass_name in ["mul", "scr"]:
		var ci := _ci(node, store, key + pass_name, idx)
		idx += 1
		RenderingServer.canvas_item_clear(ci)
		var m := _mat(store, key + pass_name, "res://shaders/vector_light_%s.gdshader" % pass_name)
		set_poly(m, points, 0.0)
		FxLight.set_uniforms(m, node, fx)
		RenderingServer.canvas_item_set_material(ci, m.get_rid())
		RenderingServer.canvas_item_add_rect(ci, box, Color.WHITE)
	store[key + "_fx"] = fx

## La luz es del lienzo: al girar el objeto se recalcula su dirección local.
static func update_light_dirs(node: CanvasItem, store: Dictionary) -> void:
	var FxLight = load("res://script_gdscript/shapes/fx_light.gd")
	for key in ["3d", "bevel_emboss"]:
		var fx = store.get(key + "_fx")
		if not (fx is Dictionary):
			continue
		var d: Dictionary = FxLight.LIGHT_3D if key == "3d" else FxLight.BEVEL
		var dir: Vector3 = FxLight.light_dir(node, float(fx.get("azimuth", d["azimuth"])), float(fx.get("elevation", d["elevation"])))
		for pass_name in ["mul", "scr"]:
			var m: ShaderMaterial = store.get(key + pass_name + "_mat")
			if m:
				m.set_shader_parameter("u_light_dir", dir)
