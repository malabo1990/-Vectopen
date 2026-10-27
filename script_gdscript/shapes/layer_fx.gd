# =============================================================================
# RUTA: res://script_gdscript/shapes/layer_fx.gd
# SOMBRAS (proyectada) para IMÁGENES y GRUPOS.
# Antes el panel Efectos las guardaba en el meta "effects" pero nadie las
# dibujaba: una imagen o un grupo con sombra no proyectaba nada sobre las
# capas de debajo.
#
# Un controlador "LayerFx" (Node, no es capa: is_shape lo ignora) por objeto.
# Cada sombra es un canvas item del RenderingServer hijo del objeto, dibujado
# DETRÁS de él (draw_behind_parent + índice -1) y en modo CanvasGroup: dentro
# se pinta la silueta (figuras, imágenes por su alfa, trazos, textos y
# subgrupos) y el shader text_fx_blur la desenfoca y la tiñe del color de la
# sombra. Así cae sobre todas las capas de debajo y nunca tapa a las de encima.
# Solo se repinta si cambian los efectos, la geometría o el zoom.
# =============================================================================
extends Node

const NAME := "LayerFx"
const BLUR_SHADER := "res://shaders/text_fx_blur.gdshader"
const SILHOUETTE_SHADER := "res://shaders/layer_fx_silhouette.gdshader"
const FxLight = preload("res://script_gdscript/shapes/fx_light.gd")

var shape: Node2D = null
var _roots: Array[RID] = []          # un canvas item (CanvasGroup) por sombra
var _items: Array[RID] = []          # siluetas (hijos de los roots)
var _mats: Array[ShaderMaterial] = []
var _sil_mat: ShaderMaterial = null
var _sig := ""
var _geom_sig := 0
var _zoom := -1.0

# ── API ─────────────────────────────────────────────────────────────────────
## ¿Le toca a LayerFx? Imágenes y grupos (las figuras, textos y trazos de
## pincel tienen su propio dibujo de efectos).
static func handles(s: Node) -> bool:
	if not (s is Node2D) or s is VectorShape or s is Line2D:
		return false
	if s.has_meta("shape_type") and String(s.get_meta("shape_type")).begins_with("text_"):
		return false
	return s is Sprite2D or String(s.get_meta("shape_type", "")) == "group" \
		or (not s.has_meta("shape_type") and s.get_child_count() > 0 and not ("artboard_size" in s))

## Crea / actualiza / quita las sombras de `s` según su meta "effects".
static func sync(s: Node) -> void:
	if not is_instance_valid(s) or not handles(s):
		return
	var node = s.get_node_or_null(NAME)
	if shadows_of(s).is_empty():
		if node:
			node.teardown()
			s.remove_child(node)
			node.queue_free()
		return
	if node == null:
		node = load("res://script_gdscript/shapes/layer_fx.gd").new()
		node.name = NAME
		node.shape = s
		s.add_child(node)
	node.shape = s
	node.refresh(true)

static func shadows_of(s: Node) -> Array:
	var raw = s.get_meta("effects", []) if s.has_meta("effects") else []
	var out: Array = []
	if raw is Array:
		for fx in FxLight.migrate_list(raw):
			if fx is Dictionary and bool(fx.get("enabled", true)) \
					and FxLight.canonical(String(fx.get("type", ""))) == "drop_shadow":
				out.append(fx)
	return out

# ── ciclo ───────────────────────────────────────────────────────────────────
func _ready() -> void:
	if shape == null:
		shape = get_parent() as Node2D
	refresh(true)

func _process(_dt: float) -> void:
	refresh(false)

func _exit_tree() -> void:
	teardown()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		teardown()

func teardown() -> void:
	for r in _items + _roots:
		if r.is_valid():
			RenderingServer.free_rid(r)
	_items.clear()
	_roots.clear()
	_sig = ""
	_geom_sig = 0

func refresh(force: bool) -> void:
	if not is_instance_valid(shape) or not shape.is_inside_tree():
		return
	var fx := shadows_of(shape)
	var sig := var_to_str(fx)
	var z := shape.get_global_transform_with_canvas().get_scale().x
	var parts: Array = []
	_collect(shape, Transform2D.IDENTITY, parts, true)
	var gsig := hash(parts.map(func(p: Array) -> String: return "%d|%s|%s" % [p[0], p[1], p[3]]))
	if not force and sig == _sig and gsig == _geom_sig:
		if not is_equal_approx(z, _zoom):
			_zoom = z
			_update_radius(fx)
		return
	_zoom = z
	_rebuild(fx, parts)
	_sig = sig
	_geom_sig = gsig

# ── silueta ─────────────────────────────────────────────────────────────────
## Piezas de la silueta en espacio de `shape`: [tipo, transform, datos, firma].
## tipo 0 = polígonos, 1 = textura (por su alfa), 2 = polilínea.
func _collect(n: Node, xf: Transform2D, out: Array, is_root: bool) -> void:
	if not is_root:
		if not (n is CanvasItem) or not (n as CanvasItem).visible:
			return
		if n is Node2D:
			xf = xf * (n as Node2D).transform
	if n is Sprite2D and (n as Sprite2D).texture:
		var sp := n as Sprite2D
		out.append([1, xf, [sp.texture, sp.get_rect()], "%s%s" % [sp.texture.get_rid(), sp.get_rect()]])
	elif n is VectorShape:
		var polys: Array = (n as VectorShape).get_evaluated_geometry()
		out.append([0, xf, polys, str(polys.size()) + str(polys[0].size() if polys.size() > 0 else 0) + str((n as VectorShape).get_local_bounding_box(polys[0]) if polys.size() > 0 and polys[0].size() > 2 else Rect2())])
	elif n is Line2D and (n as Line2D).points.size() > 1:
		var ln := n as Line2D
		out.append([2, xf, [ln.points, ln.width], "%d%s%f" % [ln.points.size(), ln.points[0], ln.width]])
	elif n is Node2D and n.has_meta("shape_type") and String(n.get_meta("shape_type")).begins_with("text_"):
		var dl = n.get_node_or_null("DisplayLabel")
		if dl and dl.has_method("_get_triangle_polys"):
			var tp: Array = dl._get_triangle_polys()
			var k := float(maxi(1, dl.get_theme_font_size("font_size"))) / float(maxi(1, int(dl.get("_outline_fs"))))
			var txf: Transform2D = xf * dl.get_transform() * Transform2D(0.0, Vector2(k, k), 0.0, Vector2.ZERO)
			out.append([0, txf, tp, "%d%s" % [tp.size(), String(n.get_meta("text", ""))]])
		return   # sus hijos son del propio texto, no capas
	if n.get_script() == get_script():
		return
	for c in n.get_children():
		if c is Node2D and String(c.name) != NAME:
			_collect(c, xf, out, false)

func _rebuild(fx: Array, parts: Array) -> void:
	teardown()
	if _sil_mat == null:
		_sil_mat = ShaderMaterial.new()
		_sil_mat.shader = load(SILHOUETTE_SHADER)
	var parent_ci := shape.get_canvas_item()
	var box := _bounds(parts)
	for i in fx.size():
		var e: Dictionary = fx[i]
		var root := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(root, parent_ci)
		RenderingServer.canvas_item_set_draw_behind_parent(root, true)
		RenderingServer.canvas_item_set_draw_index(root, -1 - (fx.size() - i))
		var blur := maxf(0.0, float(e.get("blur", 6.0)))
		var spread := maxf(0.0, float(e.get("spread", 0.0)))
		var margin := (blur * 1.6 + spread + 4.0) * maxf(1.0, _zoom)
		RenderingServer.canvas_item_set_canvas_group_mode(root, RenderingServer.CANVAS_GROUP_MODE_TRANSPARENT, margin, true, margin, true)
		var off := Vector2(float(e.get("offset_x", 4.0)), float(e.get("offset_y", 4.0)))
		RenderingServer.canvas_item_set_transform(root, Transform2D(0.0, off))
		if i >= _mats.size():
			var m := ShaderMaterial.new()
			m.shader = load(BLUR_SHADER)
			_mats.append(m)
		var mat := _mats[i]
		mat.set_shader_parameter("u_use_tint", true)
		mat.set_shader_parameter("u_type", 0)
		mat.set_shader_parameter("u_tint", _col(e.get("color"), Color(0, 0, 0, 0.4)))
		RenderingServer.canvas_item_set_material(root, mat.get_rid())
		_roots.append(root)
		# extensión (spread): silueta engordada con un trazo del grosor pedido
		for p in parts:
			var it := RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(it, root)
			RenderingServer.canvas_item_set_transform(it, p[1])
			_draw_part(it, p, spread)
			_items.append(it)
		if box.has_area():
			# área mínima del grupo: que el desenfoque no se recorte en el borde
			var pad := RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(pad, root)
			RenderingServer.canvas_item_add_rect(pad, box.grow(margin), Color(1, 1, 1, 0))
			_items.append(pad)
	_update_radius(fx)

func _draw_part(it: RID, p: Array, spread: float) -> void:
	match int(p[0]):
		0:
			for poly in p[2]:
				var pts: PackedVector2Array = poly
				if pts.size() < 3:
					continue
				var tri := Geometry2D.triangulate_polygon(pts)
				if tri.is_empty():
					continue
				RenderingServer.canvas_item_add_triangle_array(it, tri, pts, PackedColorArray([Color.WHITE]))
				if spread > 0.0:
					var ring := pts.duplicate()
					ring.append(pts[0])
					RenderingServer.canvas_item_add_polyline(it, ring, PackedColorArray([Color.WHITE]), spread * 2.0, true)
		1:
			var tex: Texture2D = p[2][0]
			var r: Rect2 = p[2][1]
			RenderingServer.canvas_item_set_material(it, _sil_mat.get_rid())
			RenderingServer.canvas_item_add_texture_rect(it, r, tex.get_rid())
			if spread > 0.0:
				RenderingServer.canvas_item_add_rect(it, r.grow(spread), Color(1, 1, 1, 0))
		2:
			RenderingServer.canvas_item_add_polyline(it, p[2][0], PackedColorArray([Color.WHITE]), float(p[2][1]) + spread * 2.0, true)

func _update_radius(fx: Array) -> void:
	for i in mini(fx.size(), _mats.size()):
		_mats[i].set_shader_parameter("u_radius", maxf(0.0, float(fx[i].get("blur", 6.0))) * _zoom)

## Caja de todas las piezas en espacio de `shape`.
func _bounds(parts: Array) -> Rect2:
	var pts := PackedVector2Array()
	for p in parts:
		var xf: Transform2D = p[1]
		match int(p[0]):
			0:
				for poly in p[2]:
					for q in poly:
						pts.append(xf * q)
			1:
				var r: Rect2 = p[2][1]
				for q in [r.position, r.end, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y)]:
					pts.append(xf * q)
			2:
				for q in p[2][0]:
					pts.append(xf * q)
	if pts.is_empty():
		return Rect2()
	var box := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		box = box.expand(q)
	return box

static func _col(v, def: Color) -> Color:
	if v is Color:
		return v
	if v is String:
		return Color.from_string(v, def)
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return def
