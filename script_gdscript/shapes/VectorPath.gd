# =============================================================================
# RUTA: res://script_gdscript/shapes/VectorPath.gd
# Trazo Bézier editable (Path2D).
#
# El estilo se expone con los MISMOS nombres que VectorShape
# (fill_color / stroke_color / stroke_width) para que InspectorCore y el panel
# de trazos lo traten igual que a un rectángulo o un polígono, sin ramas
# especiales. `closed` mantiene sincronizada la meta "is_closed" que ya usan
# el serializador y MoveTool.
# =============================================================================
@tool
extends Path2D
class_name VectorPath
const StrokeProfile = preload("res://script_gdscript/shapes/stroke_profile.gd")
const StrokeMarkers = preload("res://script_gdscript/shapes/stroke_markers.gd")
const StrokeGeom = preload("res://script_gdscript/shapes/stroke_geom.gd")

@export var fill_color: Color = Color(0.09, 0.37, 0.65, 1.0):
	set(v):
		fill_color = v
		queue_redraw()

@export var stroke_color: Color = Color(0.22, 0.22, 0.22, 1.0):
	set(v):
		stroke_color = v
		queue_redraw()

@export var stroke_width: float = 2.0:
	set(v):
		stroke_width = maxf(0.0, v)
		queue_redraw()

@export var closed: bool = false:
	set(v):
		closed = v
		set_meta("is_closed", v)
		queue_redraw()

@export var effects: Array = []:
	set(v):
		effects = v
		queue_redraw()

## 0: Butt (Plano), 1: Round (Redondo), 2: Square (Cuadrado)
@export var stroke_cap_start: int = 0:
	set(v):
		stroke_cap_start = v
		queue_redraw()

@export var stroke_cap_end: int = 0:
	set(v):
		stroke_cap_end = v
		queue_redraw()

## 0: Solid, 1: Dashed, 2: Dotted, 3: Tapered, 4: Double
@export var stroke_style: int = 0:
	set(v):
		stroke_style = v
		queue_redraw()

## 0: None, 1: Arrow, 2: Triangle, 3: Circle, 4: Square
@export var stroke_pointer_start: int = 0:
	set(v):
		stroke_pointer_start = v
		queue_redraw()

@export var stroke_pointer_end: int = 0:
	set(v):
		stroke_pointer_end = v
		queue_redraw()

## Subtrazados EXTRA del mismo objeto (agujeros o islas), rellenos con la
## regla par-impar: una "O" o un anillo vectorizado es UN trazado con su
## hueco (antes cada subtrazado era una forma rellena aparte que tapaba el
## interior).
@export var subpaths: Array[Curve2D] = []:
	set(v):
		subpaths = v
		queue_redraw()

## Perfil de grosor (StrokeProfile): puntos (t, w). Vacío = uniforme.
@export var stroke_profile: PackedVector2Array = PackedVector2Array():
	set(v):
		stroke_profile = StrokeProfile.normalize(v)
		queue_redraw()

## Escala de las puntas de flecha (1 = 100 %).
@export var stroke_pointer_scale: float = 1.0:
	set(v):
		stroke_pointer_scale = clampf(v, 0.25, 5.0)
		queue_redraw()

@export var stroke_dash_len: float = 12.0:
	set(v):
		stroke_dash_len = maxf(1.0, v)
		queue_redraw()

@export var stroke_dash_gap: float = 8.0:
	set(v):
		stroke_dash_gap = maxf(1.0, v)
		queue_redraw()

func _ready() -> void:
	# Compat: los trazos cargados de disco traen el estado como meta.
	if has_meta("is_closed"):
		closed = bool(get_meta("is_closed"))
	if has_meta("stroke_cap_start"):
		stroke_cap_start = int(get_meta("stroke_cap_start"))
	if has_meta("stroke_cap_end"):
		stroke_cap_end = int(get_meta("stroke_cap_end"))
	if has_meta("stroke_style"):
		stroke_style = int(get_meta("stroke_style"))
	if has_meta("stroke_pointer_start"):
		stroke_pointer_start = int(get_meta("stroke_pointer_start"))
	if has_meta("stroke_pointer_end"):
		stroke_pointer_end = int(get_meta("stroke_pointer_end"))
	if has_meta("stroke_profile"):
		stroke_profile = StrokeProfile.normalize(get_meta("stroke_profile"))
	if has_meta("stroke_pointer_scale"):
		stroke_pointer_scale = float(get_meta("stroke_pointer_scale"))
	if has_meta("stroke_dash_len"):
		stroke_dash_len = float(get_meta("stroke_dash_len"))
	if has_meta("stroke_dash_gap"):
		stroke_dash_gap = float(get_meta("stroke_dash_gap"))
	if curve and not curve.changed.is_connected(_solicitar_redibuja):
		curve.changed.connect(_solicitar_redibuja)
	queue_redraw()

func _solicitar_redibuja() -> void:
	queue_redraw()

func _draw() -> void:
	if not curve or curve.point_count < 2:
		return
	# Puntos PRECISOS (subdivisión adaptativa por ángulo) en vez de los
	# horneados cada 5 px: curvas lisas y uniones exactas a cualquier zoom.
	var pts := StrokeGeom.curve_points(curve)
	if pts.size() < 2:
		return

	if closed:
		if maybe_render_blur(pts):
			return
		draw_effects_shadows(pts)
		if subpaths.is_empty():
			if fill_color.a > 0.0 and pts.size() >= 3 \
					and not Geometry2D.triangulate_polygon(pts).is_empty():
				draw_colored_polygon(pts, fill_color)
			if stroke_width > 0.0:
				_draw_stroke_mesh(pts, true)
		else:
			var rings: Array = [pts]
			for c in subpaths:
				if c and c.point_count >= 2:
					rings.append(StrokeGeom.curve_points(c))
			if fill_color.a > 0.0:
				for poly in StrokeGeom.evenodd_fill(rings):
					draw_colored_polygon(poly, fill_color)
			if stroke_width > 0.0:
				for r in rings:
					_draw_stroke_mesh(r, true)
		draw_effects_overlays(pts)
	elif stroke_width > 0.0:
		# Bajo una punta la línea acaba en su base (punta afilada, y con el
		# estilo doble las dos líneas mueren dentro de la flecha).
		_draw_stroke_mesh(_trim_for_pointers(pts), false)
		_draw_pointers(pts)

## Grosor y color efectivos: por debajo de 1 px se dibuja a 1 px atenuado
## (si no, las líneas finas se ven punteadas o desaparecen).
func _render_width_color() -> Array:
	if stroke_width > 0.0 and stroke_width < 1.0:
		var c := stroke_color
		c.a *= stroke_width
		return [1.0, c]
	return [stroke_width, stroke_color]

## Estilo efectivo + perfil (el "cónico" antiguo = sólido con perfil Afilado).
func _style_and_profile() -> Array:
	if stroke_style == 3:
		return [0, stroke_profile if not StrokeProfile.is_uniform(stroke_profile) else StrokeProfile.preset("taper")]
	return [stroke_style, stroke_profile if stroke_style == 0 else PackedVector2Array()]

func _draw_stroke_mesh(pts: PackedVector2Array, is_closed: bool) -> void:
	var wc := _render_width_color()
	var sp := _style_and_profile()
	var m := StrokeGeom.build(pts, is_closed, int(sp[0]), float(wc[0]),
		stroke_cap_start, stroke_cap_end, sp[1], stroke_dash_len, stroke_dash_gap)
	if (m["indices"] as PackedInt32Array).is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), m["indices"], m["points"],
		PackedColorArray([wc[1]]))

func _pointer_size() -> float:
	return StrokeMarkers.size_for(stroke_width, stroke_pointer_scale)

## Grosor de línea de las puntas "de contorno" (flecha abierta, barra,
## anillo, triángulo hueco): el de la línea real del estilo.
func _pointer_line_width(at_start: bool) -> float:
	var sp := _style_and_profile()
	match int(sp[0]):
		4:
			return StrokeGeom.double_metrics(stroke_width).x
		9, 11, 12, 14:
			return maxf(1.0, stroke_width * 0.2)
		10:
			return maxf(1.0, stroke_width * 0.55)
	var prof: PackedVector2Array = sp[1]
	if not StrokeProfile.is_uniform(prof):
		return maxf(1.0, stroke_width * StrokeProfile.sample(prof, 0.0 if at_start else 1.0))
	return stroke_width

## Cuánto se acorta el cuerpo bajo cada punta, según su tipo y el estilo.
func _trim_len(type: int) -> float:
	# Con el doble, el borde exterior de las dos líneas está a ±grosor/2,
	# igual que el de una línea simple: el mismo recorte sirve para ambos.
	return StrokeMarkers.trim(type, _pointer_size(), stroke_width)

func _trim_for_pointers(points: PackedVector2Array) -> PackedVector2Array:
	var p := points
	if stroke_pointer_start > 0:
		p = StrokeMarkers.trim_points(p, _trim_len(stroke_pointer_start), true)
	if stroke_pointer_end > 0:
		p = StrokeMarkers.trim_points(p, _trim_len(stroke_pointer_end), false)
	return p if p.size() >= 2 else points

func _draw_pointers(points: PackedVector2Array) -> void:
	if closed or points.size() < 2:
		return
	var sz := _pointer_size()
	var col: Color = _render_width_color()[1]
	if stroke_pointer_start > 0:
		StrokeMarkers.draw(self, points[0], _end_dir(points, true, sz), stroke_pointer_start, sz, col, _pointer_line_width(true))
	if stroke_pointer_end > 0:
		StrokeMarkers.draw(self, points[points.size() - 1], _end_dir(points, false, sz), stroke_pointer_end, sz, col, _pointer_line_width(false))

## Dirección de la punta medida a lo largo del último tramo de longitud ~sz/2
## (el último segmento de la curva puede ser casi un punto y la flecha salía
## torcida).
func _end_dir(points: PackedVector2Array, at_start: bool, sz: float) -> Vector2:
	var n := points.size()
	var tip: Vector2 = points[0] if at_start else points[n - 1]
	var ref: Vector2 = tip
	var acc := 0.0
	for k in range(1, n):
		var q: Vector2 = points[k] if at_start else points[n - 1 - k]
		acc += q.distance_to(ref)
		ref = q
		if acc >= sz * 0.5:
			break
	var d := tip - ref
	return d.normalized() if d.length_squared() > 1e-10 else Vector2.RIGHT

func is_path_closed() -> bool:
	return closed

## Exporta este path como elemento <path> SVG a partir de los puntos horneados
## Curvas EXACTAS: cada tramo como Bézier cúbica (C) con sus manejadores
## (antes, la polilínea horneada cada 5 px).
func to_svg() -> String:
	if not curve or curve.point_count < 2:
		return ""
	var o := position
	var n := curve.point_count
	var p0 := curve.get_point_position(0) + o
	var d := "M %f,%f " % [p0.x, p0.y]
	var segs := n if closed else n - 1
	for k in segs:
		var i := k
		var j := (k + 1) % n
		var a := curve.get_point_position(i) + o
		var b := curve.get_point_position(j) + o
		var c1 := a + curve.get_point_out(i)
		var c2 := b + curve.get_point_in(j)
		d += "C %f,%f %f,%f %f,%f " % [c1.x, c1.y, c2.x, c2.y, b.x, b.y]
	if closed:
		d += "Z"

	var fill: String = fill_color.to_html() if (closed and fill_color.a > 0.0) else "none"
	var cap_str: String = "butt"
	if stroke_cap_end == 1: cap_str = "round"
	elif stroke_cap_end == 2: cap_str = "square"

	var dash_str: String = "none"
	var dl := stroke_dash_len
	var dg := stroke_dash_gap
	match stroke_style:
		1: dash_str = "%f,%f" % [dl, dg]
		2: dash_str = "0.01,%f" % [dg + stroke_width]
		5: dash_str = "%f,%f,0.01,%f" % [dl, dg, dg]
		6: dash_str = "%f,%f,0.01,%f,0.01,%f" % [dl, dg, dg, dg]
		7: dash_str = "%f,%f" % [dl * 2.5, dg]
		8: dash_str = "%f,%f" % [maxf(stroke_width, dl * 0.35), dg * 0.6]
		13: dash_str = "%f,%f" % [stroke_width, dg]

	return '<path d="%s" fill="%s" stroke="%s" stroke-width="%f" stroke-linecap="%s" stroke-dasharray="%s" />' % [
		d, fill, stroke_color.to_html(), stroke_width, cap_str, dash_str
	]

## Efectos en GPU con los shaders gaussianos exactos de las figuras
## (fx_poly_gpu). Canvas items propios en este diccionario.
const FxPolyGpu = preload("res://script_gdscript/shapes/fx_poly_gpu.gd")
const FxLight = preload("res://script_gdscript/shapes/fx_light.gd")
var _fxgpu: Dictionary = {}

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and not _fxgpu.is_empty():
		FxPolyGpu.update_light_dirs(self, _fxgpu)
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		FxPolyGpu.free_all(_fxgpu)

func _active_fx(kind: String) -> Dictionary:
	for fx in effects:
		if fx is Dictionary and bool(fx.get("enabled", true)) \
				and String(fx.get("type", "")).to_lower().replace(" ", "_") == kind:
			return fx
	return {}

## Desenfoque del trazado cerrado (antes no hacía nada).
func maybe_render_blur(points: PackedVector2Array) -> bool:
	var fx := _active_fx("blur")
	if fx.is_empty() or not is_inside_tree():
		FxPolyGpu.clear(_fxgpu, "blur")
		return false
	if not FxPolyGpu.blur(self, _fxgpu, points, fx, fill_color, stroke_color, stroke_width):
		return false
	for k in ["shadow", "inner", "glow"]:
		FxPolyGpu.clear(_fxgpu, k)
	return true

func draw_effects_shadows(points: PackedVector2Array) -> void:
	if _active_fx("drop_shadow").is_empty():
		FxPolyGpu.clear(_fxgpu, "shadow")
	if effects.is_empty() or points.size() < 3:
		return
	for fx in FxLight.migrate_list(effects):
		if not (fx is Dictionary) or not bool(fx.get("enabled", true)):
			continue
		var type: String = FxLight.canonical(String(fx.get("type", "")))
		if type == "drop_shadow":
			_render_drop_shadow(points, fx)
		elif type == "extrusion":
			_render_3d_extrusion(points, fx)

func draw_effects_overlays(points: PackedVector2Array) -> void:
	if _active_fx("inner_shadow").is_empty():
		FxPolyGpu.clear(_fxgpu, "inner")
	if _active_fx("inner_glow").is_empty():
		FxPolyGpu.clear(_fxgpu, "glow")
	FxPolyGpu.clear(_fxgpu, "blur")
	var light_used: Array = []
	for fx in FxLight.migrate_list(effects):
		if not (fx is Dictionary) or not bool(fx.get("enabled", true)) or points.size() < 3:
			continue
		var type: String = FxLight.canonical(String(fx.get("type", "")))
		if type in ["3d", "bevel_emboss"]:
			if is_inside_tree() and not light_used.has(type):
				light_used.append(type)
				FxPolyGpu.light(self, _fxgpu, points, fx, type)
				set_notify_transform(true)
			continue
		match type:
			"inner_shadow":
				_render_inner_shadow(points, fx)
			"outline":
				_render_outline_effect(points, fx)
			"color_overlay":
				_render_color_overlay(points, fx)
			"gradient_overlay":
				_render_gradient_overlay(points, fx)
			"inner_glow":
				_render_inner_glow(points, fx)
	for k in ["3d", "bevel_emboss"]:
		if not light_used.has(k):
			FxPolyGpu.clear(_fxgpu, k + "mul")
			FxPolyGpu.clear(_fxgpu, k + "scr")

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
	if is_inside_tree():
		FxPolyGpu.drop_shadow(self, _fxgpu, points, fx)
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

func _render_inner_shadow(points: PackedVector2Array, fx: Dictionary) -> void:
	var offset := Vector2(float(fx.get("offset_x", 2.0)), float(fx.get("offset_y", 2.0)))
	var blur := maxf(0.5, float(fx.get("blur", 4.0)))
	var spread := float(fx.get("spread", fx.get("choke", 0.0)))
	var base_col := _parse_fx_color(fx.get("color", null), Color(0.0, 0.0, 0.0, 0.5))
	if base_col.a <= 0.001 or points.size() < 3:
		return
	if is_inside_tree():
		FxPolyGpu.inner_shadow(self, _fxgpu, "inner", points, fx)
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
	# Contorno EXTERIOR: banda de `width` pegada por fuera del borde.
	var outer := Geometry2D.offset_polygon(points, width * 0.5, Geometry2D.JOIN_ROUND)
	if outer.is_empty():
		outer = [points]
	for poly in outer:
		var ring := PackedVector2Array(poly)
		if ring.size() < 2:
			continue
		ring.append(ring[0])
		draw_polyline(ring, col, width, true)

## Superposición de degradado con el degradado PROPIO del efecto (colores,
## posiciones y ángulo), igual que en VectorShape.
func _render_gradient_overlay(points: PackedVector2Array, fx: Dictionary) -> void:
	var opacity := clampf(float(fx.get("opacity", 1.0)), 0.0, 1.0)
	if opacity <= 0.001 or points.size() < 3:
		return
	var tex: Texture2D = load("res://script_gdscript/text/text_fx.gd")._gradient_texture(fx)
	var lo := points[0]
	var hi := points[0]
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var sz := (hi - lo).max(Vector2(0.001, 0.001))
	var uvs := PackedVector2Array()
	uvs.resize(points.size())
	for i in points.size():
		uvs[i] = (points[i] - lo) / sz
	draw_colored_polygon(points, Color(1, 1, 1, opacity), uvs, tex)

func _render_color_overlay(points: PackedVector2Array, fx: Dictionary) -> void:
	var col := _parse_fx_color(fx.get("color", null), Color(1.0, 0.0, 0.0, 1.0))
	var opacity := clampf(float(fx.get("opacity", 1.0)), 0.0, 1.0)
	var final_col := Color(col.r, col.g, col.b, col.a * opacity)
	if final_col.a <= 0.001:
		return
	draw_colored_polygon(points, final_col)

func _render_inner_glow(points: PackedVector2Array, fx: Dictionary) -> void:
	var col := _parse_fx_color(fx.get("color", null), Color.WHITE)
	# radius / opacity del panel (antes "intensity", que el panel no envía).
	var radius := maxf(0.5, float(fx.get("radius", 8.0 * float(fx.get("intensity", 1.0)))))
	var opacity := clampf(float(fx.get("opacity", 1.0)), 0.0, 1.0)
	var glow_fx := {
		"offset_x": 0.0,
		"offset_y": 0.0,
		"blur": radius,
		"color": Color(col.r, col.g, col.b, clampf(col.a * opacity, 0.0, 1.0))
	}
	if is_inside_tree():
		FxPolyGpu.inner_glow(self, _fxgpu, points, fx)
		return
	_render_inner_shadow(points, glow_fx)

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

func get_evaluated_geometry() -> Array[PackedVector2Array]:
	if not curve:
		return []
	var pts := curve.get_baked_points()
	if pts.is_empty():
		return []
	return [pts]

func get_effect_points() -> PackedVector2Array:
	if not curve:
		return PackedVector2Array()
	return curve.get_baked_points()

func _render_3d_bevel(points: PackedVector2Array, fx: Dictionary) -> void:
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
