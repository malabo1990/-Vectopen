# =============================================================================
# RUTA: res://script_gdscript/shapes/filter_fx.gd
# FILTROS de la pestaña "Filtros" (panel Efectos): cristal esmerilado, grano,
# duotono, neón, aberración cromática, glitch, semitono y pixelado.
#
# Funcionan sobre el RENDER REAL de cualquier objeto (figura, texto, imagen,
# grupo), sin tocar su dibujo: un nodo controlador ("FilterFx") cuelga en el
# servidor de render el canvas item del objeto de un "host" propio
# (mismo padre y mismo orden de dibujo):
#
#   padre ─ host ─┬─ cristal   (detrás: copia del fondo + desenfoque, opcional)
#                 └─ grupo     (canvas group + filter_fx.gdshader, opcional)
#                      └─ objeto (su canvas item, con sus hijos y efectos)
#
# El árbol de escena no cambia (selección, capas, guardado intactos). Los
# parámetros viven en el meta "filters" (Array de Dictionary), igual que
# "effects": deshacer y guardar van por InspectorCore / el serializador.
# =============================================================================
extends Node

const NAME := "FilterFx"
const FX_SHADER := "res://shaders/filter_fx.gdshader"
const GLASS_SHADER := "res://shaders/filter_glass.gdshader"

const ORDER := ["glass", "neon", "duotone", "grain", "chromatic", "glitch", "halftone", "pixelate"]

const LABELS := {
	"glass": "Frosted Glass",
	"grain": "Grain",
	"duotone": "Duotone",
	"neon": "Neon",
	"chromatic": "Chromatic Aberration",
	"glitch": "Glitch",
	"halftone": "Halftone",
	"pixelate": "Pixelate",
}

const DEFAULTS := {
	"glass": {"blur": 16.0, "tint": Color(1, 1, 1, 1), "tint_amount": 20.0, "frost": 12.0, "saturation": 120.0},
	"grain": {"amount": 30.0, "size": 1.0, "mono": true},
	"duotone": {"dark": Color(0.12, 0.05, 0.38, 1), "light": Color(1.0, 0.62, 0.36, 1), "mix": 100.0},
	"neon": {"color": Color(0.15, 1.0, 0.85, 1), "radius": 12.0, "intensity": 120.0, "tint": 70.0},
	"chromatic": {"amount": 3.0, "angle": 0.0},
	"glitch": {"amount": 35.0, "shift": 10.0, "band": 6.0, "seed": 1.0},
	"halftone": {"cell": 8.0, "angle": 45.0, "scale": 100.0},
	"pixelate": {"size": 8.0},
}

## Filtros que necesitan el canvas group (todos menos el cristal).
const PIXEL_TYPES := ["grain", "duotone", "neon", "chromatic", "glitch", "halftone", "pixelate"]

var shape: Node2D = null
var _host := RID()
var _group := RID()
var _glass := RID()
var _mat: ShaderMaterial = null
var _glass_mat: ShaderMaterial = null
var _fx_ref = null
var _sig := ""
var _active: Dictionary = {}       # tipo -> dict del filtro activo
var _l2s := Transform2D()
var _idx := -1
var _vis := true
var _mod := Color.WHITE
var _margin := -1.0
var _mips := false
var _glass_dirty := true
var _glass_xf := Transform2D()
var _polys_ref = null

# ── SHADER DEL USUARIO (pestaña Shader) ──────────────────────────────────────
# Capa opcional por encima de los filtros: host → [shader del usuario] →
# [filtros] → objeto. Meta "custom_shader" = {name, code, params, margin,
# enabled}. El código es un canvas_item de Godot que lee el render del objeto
# con un sampler hint_screen_texture (como los filtros).
var _cgroup := RID()
var _cmat: ShaderMaterial = null
var _ccode := ""
var _cs_ref = null
var _cmargin := -1.0
static var _shader_cache: Dictionary = {}   # código -> Shader

# ── API ─────────────────────────────────────────────────────────────────────
## Crea / actualiza / quita los filtros del objeto según su meta "filters".
static func sync(s: Node) -> void:
	if not (s is CanvasItem) or not is_instance_valid(s):
		return
	var node = s.get_node_or_null(NAME)
	if enabled_filters(s).is_empty() and get_custom(s).is_empty():
		if node:
			node.uninstall()
			# Fuera del árbol YA (ver TextFx.sync): un sync en el mismo frame no
			# debe reutilizar un nodo moribundo.
			s.remove_child(node)
			node.queue_free()
		return
	if node == null:
		node = load("res://script_gdscript/shapes/filter_fx.gd").new()
		node.name = NAME
		node.shape = s
		s.add_child(node)
	node.refresh(true)

static func canonical(t: String) -> String:
	var n := t.to_lower().strip_edges().replace(" ", "_")
	match n:
		"chromatic_aberration", "aberracion_cromatica", "aberración_cromática": return "chromatic"
		"cristal", "cristal_esmerilado", "frosted_glass", "backdrop_blur": return "glass"
		"grano", "noise": return "grain"
		"duotono": return "duotone"
		"neón": return "neon"
		"semitono": return "halftone"
		"pixelado", "pixelar", "mosaic": return "pixelate"
	return n

static func make(t: String) -> Dictionary:
	var c := canonical(t)
	var d: Dictionary = (DEFAULTS.get(c, {}) as Dictionary).duplicate(true)
	d["type"] = c
	d["enabled"] = true
	return d

static func get_filters(s: Node) -> Array:
	var raw = s.get_meta("filters", []) if s.has_meta("filters") else []
	return raw if raw is Array else []

## Shader del usuario activo ({} si no hay o está desactivado).
static func get_custom(s: Node) -> Dictionary:
	var c = s.get_meta("custom_shader", null) if s.has_meta("custom_shader") else null
	if c is Dictionary and bool(c.get("enabled", true)) and String(c.get("code", "")).strip_edges() != "":
		return c
	return {}

static func shader_for(code: String) -> Shader:
	if _shader_cache.has(code):
		return _shader_cache[code]
	if _shader_cache.size() > 64:
		_shader_cache.clear()
	var sh := Shader.new()
	sh.code = code
	_shader_cache[code] = sh
	return sh

static func enabled_filters(s: Node) -> Array:
	var out: Array = []
	for f in get_filters(s):
		if f is Dictionary and bool(f.get("enabled", true)) and DEFAULTS.has(canonical(String(f.get("type", "")))):
			out.append(f)
	return out

static func _num(f: Dictionary, k: String, t: String) -> float:
	return float(f.get(k, DEFAULTS[t].get(k, 0.0)))

static func _col(v, def: Color) -> Color:
	if v is Color:
		return v
	if v is String:
		return Color.from_string(v, def)
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return def

# ── ciclo ───────────────────────────────────────────────────────────────────
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			shape = get_parent() as Node2D
			# Al re-entrar (reordenar en capas, agrupar…) Godot ya volvió a
			# colgar el canvas item del objeto de su padre: se reinstala.
			_install()
			refresh(true)
		NOTIFICATION_EXIT_TREE:
			uninstall()

func _process(_dt: float) -> void:
	refresh(false)

func refresh(force: bool) -> void:
	if not is_instance_valid(shape) or not shape.is_inside_tree():
		return
	var raw = shape.get_meta("filters") if shape.has_meta("filters") else null
	var craw = shape.get_meta("custom_shader") if shape.has_meta("custom_shader") else null
	if force or not is_same(raw, _fx_ref) or not is_same(craw, _cs_ref):
		_fx_ref = raw
		_cs_ref = craw
		var list := enabled_filters(shape)
		var sig := var_to_str(list) + "|" + var_to_str(get_custom(shape))
		if force or sig != _sig:
			_sig = sig
			_active.clear()
			for f in list:
				_active[canonical(String(f.get("type", "")))] = f
			_install()
			_layout()
			_apply_params()
			_l2s = Transform2D()   # fuerza transformaciones / márgenes
			_margin = -1.0
			_glass_dirty = true
	if not _host.is_valid():
		return
	# Orden de dibujo, visibilidad y opacidad (el cristal no los hereda del objeto)
	var idx := shape.get_index()
	if idx != _idx:
		_idx = idx
		RenderingServer.canvas_item_set_draw_index(_host, idx)
	var vis := shape.visible
	if vis != _vis:
		_vis = vis
		RenderingServer.canvas_item_set_visible(_host, vis)
	if _glass.is_valid():
		var m := shape.modulate
		if m != _mod:
			_mod = m
			RenderingServer.canvas_item_set_modulate(_glass, m)
		var xf := shape.get_transform()
		if not xf.is_equal_approx(_glass_xf):
			_glass_xf = xf
			RenderingServer.canvas_item_set_transform(_glass, xf)
		if _text_polys_changed():
			_glass_dirty = true
		if _glass_dirty:
			_glass_dirty = false
			_draw_glass()
	# Pantalla <-> local (zoom / paneo / mover): solo uniforms
	var vp := shape.get_viewport()
	if vp == null:
		return
	var l2s := vp.get_final_transform() * shape.get_global_transform_with_canvas()
	if not l2s.is_equal_approx(_l2s):
		_l2s = l2s
		_update_transform_uniforms()

# ── instalación en el servidor de render ────────────────────────────────────
func _parent_rid() -> RID:
	var p := shape.get_parent()
	if p is CanvasItem:
		return (p as CanvasItem).get_canvas_item()
	return shape.get_canvas()

func _install() -> void:
	if _host.is_valid() or not is_instance_valid(shape) or not shape.is_inside_tree():
		return
	_host = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_host, _parent_rid())
	_idx = shape.get_index()
	RenderingServer.canvas_item_set_draw_index(_host, _idx)
	_vis = shape.visible
	RenderingServer.canvas_item_set_visible(_host, _vis)
	RenderingServer.canvas_item_set_parent(shape.get_canvas_item(), _host)
	if not shape.draw.is_connected(_on_shape_draw):
		shape.draw.connect(_on_shape_draw)

func uninstall() -> void:
	if is_instance_valid(shape) and shape.draw.is_connected(_on_shape_draw):
		shape.draw.disconnect(_on_shape_draw)
	if not _host.is_valid():
		return
	if is_instance_valid(shape) and shape.is_inside_tree():
		RenderingServer.canvas_item_set_parent(shape.get_canvas_item(), _parent_rid())
		RenderingServer.canvas_item_set_draw_index(shape.get_canvas_item(), shape.get_index())
	for r in [_glass, _group, _cgroup, _host]:
		if r.is_valid():
			RenderingServer.free_rid(r)
	_glass = RID()
	_group = RID()
	_cgroup = RID()
	_host = RID()
	_cmargin = -1.0
	_idx = -1
	_margin = -1.0

## Crea / quita el cristal y el grupo según los filtros activos.
func _layout() -> void:
	if not _host.is_valid():
		return
	var need_group := false
	for t in PIXEL_TYPES:
		if _active.has(t):
			need_group = true
			break
	var need_glass := _active.has("glass")
	if need_glass and not _glass.is_valid():
		_glass = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(_glass, _host)
		RenderingServer.canvas_item_set_draw_behind_parent(_glass, true)
		if _glass_mat == null:
			_glass_mat = ShaderMaterial.new()
			_glass_mat.shader = load(GLASS_SHADER)
		RenderingServer.canvas_item_set_material(_glass, _glass_mat.get_rid())
		_glass_xf = Transform2D()
		_mod = Color(-1, -1, -1, -1)
		_glass_dirty = true
	elif not need_glass and _glass.is_valid():
		RenderingServer.free_rid(_glass)
		_glass = RID()
	if need_group and not _group.is_valid():
		_group = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(_group, _host)
		if _mat == null:
			_mat = ShaderMaterial.new()
			_mat.shader = load(FX_SHADER)
		RenderingServer.canvas_item_set_material(_group, _mat.get_rid())
		_margin = -1.0
	# Shader del usuario: grupo propio entre el host y los filtros.
	var need_custom := not get_custom(shape).is_empty()
	if need_custom and not _cgroup.is_valid():
		_cgroup = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(_cgroup, _host)
		if _cmat == null:
			_cmat = ShaderMaterial.new()
		RenderingServer.canvas_item_set_material(_cgroup, _cmat.get_rid())
		_cmargin = -1.0
	var outer := _cgroup if need_custom else _host
	if _group.is_valid():
		RenderingServer.canvas_item_set_parent(_group, outer)
	var target := _group if need_group else outer
	RenderingServer.canvas_item_set_parent(shape.get_canvas_item(), target)
	if not need_group and _group.is_valid():
		RenderingServer.free_rid(_group)
		_group = RID()
	if not need_custom and _cgroup.is_valid():
		RenderingServer.free_rid(_cgroup)
		_cgroup = RID()
		_ccode = ""

# ── parámetros ──────────────────────────────────────────────────────────────
func _apply_params() -> void:
	var cs := get_custom(shape) if is_instance_valid(shape) else {}
	if _cmat and not cs.is_empty():
		var code := String(cs.get("code", ""))
		if code != _ccode:
			_ccode = code
			_cmat.shader = shader_for(code)
		var params = cs.get("params", {})
		if params is Dictionary:
			for k in params:
				_cmat.set_shader_parameter(String(k), params[k])
	if _mat:
		var m := _mat
		var on := func(t: String) -> bool: return _active.has(t)
		m.set_shader_parameter("u_gl_on", on.call("glitch"))
		if _active.has("glitch"):
			var f: Dictionary = _active["glitch"]
			m.set_shader_parameter("u_gl_amount", clampf(_num(f, "amount", "glitch") / 100.0, 0.0, 1.0))
			m.set_shader_parameter("u_gl_shift", _num(f, "shift", "glitch"))
			m.set_shader_parameter("u_gl_band", maxf(0.5, _num(f, "band", "glitch")))
			m.set_shader_parameter("u_gl_seed", _num(f, "seed", "glitch"))
		m.set_shader_parameter("u_px_on", on.call("pixelate"))
		if _active.has("pixelate"):
			m.set_shader_parameter("u_px_size", maxf(0.5, _num(_active["pixelate"], "size", "pixelate")))
		m.set_shader_parameter("u_ca_on", on.call("chromatic"))
		if _active.has("chromatic"):
			var f: Dictionary = _active["chromatic"]
			m.set_shader_parameter("u_ca_amount", maxf(0.0, _num(f, "amount", "chromatic")))
			m.set_shader_parameter("u_ca_angle", deg_to_rad(_num(f, "angle", "chromatic")))
		m.set_shader_parameter("u_ht_on", on.call("halftone"))
		if _active.has("halftone"):
			var f: Dictionary = _active["halftone"]
			m.set_shader_parameter("u_ht_cell", maxf(1.0, _num(f, "cell", "halftone")))
			m.set_shader_parameter("u_ht_angle", deg_to_rad(_num(f, "angle", "halftone")))
			m.set_shader_parameter("u_ht_scale", maxf(0.0, _num(f, "scale", "halftone")) / 100.0)
		m.set_shader_parameter("u_duo_on", on.call("duotone"))
		if _active.has("duotone"):
			var f: Dictionary = _active["duotone"]
			m.set_shader_parameter("u_duo_dark", _col(f.get("dark"), DEFAULTS["duotone"]["dark"]))
			m.set_shader_parameter("u_duo_light", _col(f.get("light"), DEFAULTS["duotone"]["light"]))
			m.set_shader_parameter("u_duo_mix", clampf(_num(f, "mix", "duotone") / 100.0, 0.0, 1.0))
		m.set_shader_parameter("u_gr_on", on.call("grain"))
		if _active.has("grain"):
			var f: Dictionary = _active["grain"]
			m.set_shader_parameter("u_gr_amount", clampf(_num(f, "amount", "grain") / 100.0, 0.0, 1.0) * 0.5)
			m.set_shader_parameter("u_gr_size", maxf(0.25, _num(f, "size", "grain")))
			m.set_shader_parameter("u_gr_mono", bool(f.get("mono", true)))
		m.set_shader_parameter("u_neon_on", on.call("neon"))
		if _active.has("neon"):
			var f: Dictionary = _active["neon"]
			m.set_shader_parameter("u_neon_color", _col(f.get("color"), DEFAULTS["neon"]["color"]))
			m.set_shader_parameter("u_neon_radius", maxf(0.0, _num(f, "radius", "neon")))
			m.set_shader_parameter("u_neon_intensity", maxf(0.0, _num(f, "intensity", "neon")) / 100.0)
			m.set_shader_parameter("u_neon_tint", clampf(_num(f, "tint", "neon") / 100.0, 0.0, 1.0))
	if _glass_mat and _active.has("glass"):
		var f: Dictionary = _active["glass"]
		var tint := _col(f.get("tint"), Color.WHITE)
		tint.a = clampf(_num(f, "tint_amount", "glass") / 100.0, 0.0, 1.0)
		_glass_mat.set_shader_parameter("u_tint", tint)
		_glass_mat.set_shader_parameter("u_frost", clampf(_num(f, "frost", "glass") / 100.0, 0.0, 1.0) * 0.4)
		_glass_mat.set_shader_parameter("u_saturation", maxf(0.0, _num(f, "saturation", "glass")) / 100.0)

## Margen (px de pantalla) que el grupo necesita alrededor del objeto: el
## halo del neón y los desplazamientos de glitch / aberración salen fuera.
func _needed_margin_local() -> float:
	var m := 0.0
	if _active.has("neon"):
		m += _num(_active["neon"], "radius", "neon") * 1.6
	if _active.has("glitch"):
		m += absf(_num(_active["glitch"], "shift", "glitch"))
	if _active.has("chromatic"):
		m += absf(_num(_active["chromatic"], "amount", "chromatic"))
	return m

func _update_transform_uniforms() -> void:
	var zoom := _l2s.get_scale().abs().x
	if _cmat and _cgroup.is_valid():
		# Uniformes de ayuda (si el shader los declara): pantalla <-> local
		# del objeto y zoom, como los filtros.
		var inv0 := _l2s.affine_inverse()
		_cmat.set_shader_parameter("u_l2s_x", _l2s.x)
		_cmat.set_shader_parameter("u_l2s_y", _l2s.y)
		_cmat.set_shader_parameter("u_l2s_o", _l2s.origin)
		_cmat.set_shader_parameter("u_s2l_x", inv0.x)
		_cmat.set_shader_parameter("u_s2l_y", inv0.y)
		_cmat.set_shader_parameter("u_s2l_o", inv0.origin)
		_cmat.set_shader_parameter("u_zoom", zoom)
		var cm := ceilf(float(get_custom(shape).get("margin", 0.0)) * zoom) + 2.0
		if not is_equal_approx(cm, _cmargin):
			_cmargin = cm
			RenderingServer.canvas_item_set_canvas_group_mode(_cgroup,
				RenderingServer.CANVAS_GROUP_MODE_TRANSPARENT, cm, true, cm, false)
	if _mat:
		var inv := _l2s.affine_inverse()
		_mat.set_shader_parameter("u_l2s_x", _l2s.x)
		_mat.set_shader_parameter("u_l2s_y", _l2s.y)
		_mat.set_shader_parameter("u_l2s_o", _l2s.origin)
		_mat.set_shader_parameter("u_s2l_x", inv.x)
		_mat.set_shader_parameter("u_s2l_y", inv.y)
		_mat.set_shader_parameter("u_s2l_o", inv.origin)
		_mat.set_shader_parameter("u_zoom", zoom)
	if _group.is_valid():
		var margin := ceilf(_needed_margin_local() * zoom) + 2.0
		var mips := _active.has("neon")
		if not is_equal_approx(margin, _margin) or mips != _mips:
			_margin = margin
			_mips = mips
			RenderingServer.canvas_item_set_canvas_group_mode(_group,
				RenderingServer.CANVAS_GROUP_MODE_TRANSPARENT, margin, true, margin, mips)
	if _glass_mat and _active.has("glass"):
		var blur := maxf(0.0, _num(_active["glass"], "blur", "glass"))
		_glass_mat.set_shader_parameter("u_blur_px", minf(blur * zoom, 160.0))
		_glass_mat.set_shader_parameter("u_grain_cell", 1.0 / maxf(zoom, 0.05))

# ── cristal ─────────────────────────────────────────────────────────────────
func _on_shape_draw() -> void:
	_glass_dirty = true

func _text_polys_changed() -> bool:
	var dl = shape.get_node_or_null("DisplayLabel")
	if dl == null or not dl.has_method("_get_triangle_polys"):
		return false
	var p = dl._get_triangle_polys()
	if is_same(p, _polys_ref):
		return false
	_polys_ref = p
	return true

## Silueta del objeto en su espacio local (polígonos simples).
func _silhouette() -> Array:
	var out: Array = []
	var dl = shape.get_node_or_null("DisplayLabel")
	if dl != null and dl.has_method("_get_triangle_polys"):
		var k := float(maxi(1, dl.get_theme_font_size("font_size"))) / float(maxi(1, int(dl.get("_outline_fs"))))
		var xf: Transform2D = dl.get_transform() * Transform2D(0.0, Vector2(k, k), 0.0, Vector2.ZERO)
		for p in dl._get_triangle_polys():
			out.append(xf * PackedVector2Array(p))
		return out
	if shape.has_method("get_evaluated_geometry"):
		for p in shape.get_evaluated_geometry():
			out.append(PackedVector2Array(p))
		if not out.is_empty():
			return out
	if shape.has_method("get_rect"):
		var r: Rect2 = shape.get_rect()
		out.append(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
	return out

func _draw_glass() -> void:
	if not _glass.is_valid():
		return
	RenderingServer.canvas_item_clear(_glass)
	var polys := _silhouette()
	var bounds := Rect2()
	var first := true
	var white := PackedColorArray([Color.WHITE])
	for poly in polys:
		var pts := PackedVector2Array(poly)
		if pts.size() < 3:
			continue
		var idx := Geometry2D.triangulate_polygon(pts)
		if idx.is_empty():
			continue
		RenderingServer.canvas_item_add_triangle_array(_glass, idx, pts, white)
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		bounds = r if first else bounds.merge(r)
		first = false
	if first:
		return
	# Copia del fondo SOLO alrededor del objeto (+ radio del desenfoque)
	var grow := maxf(0.0, _num(_active.get("glass", {}), "blur", "glass")) * 1.6 + 4.0
	RenderingServer.canvas_item_set_copy_to_backbuffer(_glass, true, bounds.grow(grow))
