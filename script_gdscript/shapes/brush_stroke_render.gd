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
const ObjectBrush = preload("res://script_gdscript/shapes/object_brush.gd")
const StrokeTextures = preload("res://script_gdscript/shapes/stroke_textures.gd")
const STROKE_SHADER := preload("res://shaders/brush_stroke.gdshader")
## Material compartido de los trazos sin degradado (no rompe el agrupado de
## dibujo); con degradado cada trazo tiene el suyo (uniformes propios).
static var _shared_mats: Dictionary = {}   # estilo → material compartido
## Estilo del pincel → uniforme `style` del sombreador.
const STYLE_IDS := {"pencil": 1, "marker": 2, "airbrush": 3}
## Durezas del lápiz: [oscuridad del grafito, cuánto grano rellena, suavidad].
## Las duras (H) dejan ver mucho papel y son grises; las blandas (B) cubren
## más, son más oscuras y de borde más suave.
const PENCIL_GRADES := {
	"2H": [0.45, 0.36, 0.05], "H": [0.55, 0.45, 0.06], "HB": [0.66, 0.55, 0.07],
	"B": [0.75, 0.64, 0.08], "2B": [0.83, 0.72, 0.09], "4B": [0.91, 0.82, 0.11],
	"6B": [0.96, 0.90, 0.13], "8B": [1.0, 0.97, 0.15],
}
const GRADE_ORDER := ["2H", "H", "HB", "B", "2B", "4B", "6B", "8B"]
const DEFAULT_GRADE := "HB"

static func _set_grade(mat: ShaderMaterial, grade: String) -> void:
	var gp: Array = PENCIL_GRADES.get(grade, PENCIL_GRADES[DEFAULT_GRADE])
	mat.set_shader_parameter("pencil_dark", float(gp[0]))
	mat.set_shader_parameter("pencil_fill", float(gp[1]))
	mat.set_shader_parameter("pencil_soft", float(gp[2]))

## Caligrafía: ángulo de la plumilla (grados) y anchura mínima relativa.
const NIB_ANGLE_DEG := 45.0
const NIB_MIN := 0.12
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
	set_process(is_instance_valid(line) and line.has_meta("brush_ref"))
	_hide_native()
	_update_material()
	if line and not line.draw.is_connected(queue_redraw):
		# El Line2D se redibuja al cambiar puntos / grosor / curva / color.
		line.draw.connect(queue_redraw)

## Trazo ENLAZADO (texto en trazado, VGSE fase 3): si cambian el texto o
## el trazado de los que sale, se rehace solo.
var _ref_key := 0

## Mover / girar / escalar el texto en trazado lleva consigo su trazado y su
## texto de origen (como Illustrator). Antes el texto se separaba de la curva.
## Funciona igual con arrastre, flechas, inspector o deshacer: se aplica a
## ellos el mismo cambio que sufrió el trazo enlazado.
var _ref_xf_set := false
var _ref_line_xf := Transform2D.IDENTITY
var _ref_others: Dictionary = {}   # nodo → su transform la última vez

func _carry_linked() -> void:
	var parent := line.get_parent()
	if parent == null:
		return
	var ref: Dictionary = line.get_meta("brush_ref", {})
	var others: Array = []
	for key in ["path", "source"]:
		var n := parent.get_node_or_null(NodePath(String(ref.get(key, "")))) as Node2D
		if n:
			others.append(n)
	if not _ref_xf_set:
		_ref_xf_set = true
		_ref_line_xf = line.transform
		for n in others:
			_ref_others[n] = n.transform
		return
	if not line.transform.is_equal_approx(_ref_line_xf):
		var delta := line.transform * _ref_line_xf.affine_inverse()
		for n in others:
			var before: Transform2D = _ref_others.get(n, n.transform)
			# si ya se movió igual (estaba seleccionado también), no repetir
			if not n.transform.is_equal_approx(delta * before):
				n.transform = delta * n.transform
		_ref_line_xf = line.transform
	for n in others:
		_ref_others[n] = n.transform

func _process(_delta: float) -> void:
	if not is_instance_valid(line) or not line.has_meta("brush_ref"):
		set_process(false)
		return
	_carry_linked()
	var k := _ref_watch_key()
	if k != _ref_key:
		_ref_key = k
		if ObjectBrush.refresh_ref(line):
			queue_redraw()

func _ref_watch_key() -> int:
	var ref: Dictionary = line.get_meta("brush_ref", {})
	var parent := line.get_parent()
	if parent == null:
		return 0
	var parts: Array = []
	for key in ["source", "path"]:
		var n := parent.get_node_or_null(NodePath(String(ref.get(key, ""))))
		if n == null:
			parts.append(null)
			continue
		parts.append((n as CanvasItem).get_global_transform() if n is CanvasItem else null)
		for mk in ["text", "runs", "font_size", "text_color", "font_family"]:
			parts.append(var_to_str(n.get_meta(mk)) if n.has_meta(mk) else "")
		if "curve" in n and n.curve != null:
			parts.append((n.curve as Curve2D).get_baked_points())
		for c in n.get_children():
			if c is CanvasItem and not c.has_method("get_glyph_outlines"):
				parts.append((c as CanvasItem).get_transform())
		var vrt = n.get_node_or_null("VectorRichText")
		if vrt and vrt.has_method("get_text"):
			parts.append(vrt.get_text())
	return hash(parts)

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

var _group: CanvasGroup = null

## Opacidad del trazo como grupo (ver stroke_material): la malla se pinta
## opaca dentro de un CanvasGroup interno y el grupo lleva la opacidad.
func _set_group(alpha: float) -> void:
	# El lápiz siempre en grupo (ver _shader_for: escribe sin mezclar).
	# Lápiz: grupo (escritura sin mezclar) SOLO si el trazo se pliega; cada
	# grupo es un pase aparte en la GPU (2000 lápices = más de la mitad del
	# fotograma con 10 000 elementos).
	var translucent := alpha < 0.999 or _pencil_folds
	if translucent and _group == null:
		_group = CanvasGroup.new()
		_group.name = "OpacityGroup"
		add_child(_group, false, Node.INTERNAL_MODE_FRONT)
	if _group:
		_group.visible = translucent
		_group.self_modulate.a = alpha
	var host := _group.get_canvas_item() if translucent else get_canvas_item()
	RenderingServer.canvas_item_set_parent(_mesh_item(), host)

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
	# VGSE: geometría DERIVADA en caché (eje, malla, UV). Solo se recalcula
	# si cambia lo que la define; color, degradado u opacidad solo repintan.
	var key := _geom_key()
	if key != _geom_cache_key or _geom.is_empty():
		_geom = _build_geom()
		_geom_cache_key = key
		geom_builds += 1
		var folds := style_id(line) == 1 and bool(_geom.get("folds", false))
		if folds != _pencil_folds:
			_pencil_folds = folds
			_update_material()
	var ax: Array = _geom["ax"]
	pts = ax[0]
	var half: PackedFloat32Array = ax[1]
	var cum: PackedFloat32Array = ax[2]
	var n := pts.size()
	var total := maxf(cum[n - 1], 0.0001)
	var m: Dictionary = _geom["m"]
	var verts: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	if idx.is_empty():
		return
	var cols: PackedColorArray
	var gio0: Object = StrokeGeom._native_geom()
	if _geom.has("pencil_a") and gio0 and not (line.gradient and not has_gradient_fill()):
		# Lápiz: opacidad por vértice ya calculada con la forma (caché); aquí
		# solo el color (nativo).
		cols = gio0.colors_from_alpha(_geom["pencil_a"], Color(1, 1, 1, line.default_color.a) if has_gradient_fill() else line.default_color)
	elif m.has("colors"):
		# Pincel de objeto: los colores de las figuras estampadas.
		cols = m["colors"]
	else:
		cols = _colors(verts, pts, cum, total, m, half, ax[3] if ax.size() > 3 else PackedFloat32Array())
	var gio: Object = StrokeGeom._native_geom()
	if m.has("a") and gio and gio.has_method("colors_from_alpha") and not (line.gradient and not has_gradient_fill()):
		# Aerógrafo por sellos, en nativo (108 000 vértices: ~15 ms en GDScript).
		cols = gio.colors_from_alpha(m["a"], cols[0])
	elif m.has("a"):
		# Aerógrafo por sellos: cada sello con su opacidad (flujo por presión).
		var sa: PackedFloat32Array = m["a"]
		var c0: Color = cols[0]
		cols = PackedColorArray()
		cols.resize(verts.size())
		for i in verts.size():
			var c := c0
			if line.gradient and not has_gradient_fill():
				c = line.gradient.sample(clampf(float(i) / maxf(1.0, verts.size() - 1.0), 0.0, 1.0))
			c.a *= sa[i]
			cols[i] = c
	# Variación de color a lo largo del trazo (VGSE fase 4): tono y luz que
	# cambian suave por la longitud recorrida (solo pintura: no rehace la forma).
	var jit := float(line.get_meta("brush_color_jitter", 0.0)) if line.has_meta("brush_color_jitter") else 0.0
	if jit > 0.001 and m.has("k"):
		cols = _jitter_colors(cols, m["k"], cum, jit, line.width, verts.size())
	# Opacidad del pincel → del grupo; la malla, opaca (sin solapes visibles).
	var alpha := line.default_color.a
	_set_group(alpha)
	if alpha < 0.999 and alpha > 0.0:
		for i in cols.size():
			cols[i].a = clampf(cols[i].a / alpha, 0.0, 1.0)
	# UX-16: la TEXTURA del estilo (grano del lápiz, bordes del marcador,
	# difuminado del aerógrafo, bisel caligráfico). Antes se ignoraba y todos
	# los estilos salían como una banda lisa.
	# El estilo (grano del lápiz, tinta del rotulador, aerógrafo) lo pinta el
	# sombreador sin imágenes; antes eran texturas repetidas en el Line2D.
	RenderingServer.canvas_item_add_triangle_array(ci, idx, verts, cols, _geom["uvs"])

var _pencil_folds := false

## ¿El trazo se PLIEGA sobre sí mismo? (giro con radio menor que el medio
## grosor: el lado interior de la malla se solapa). Solo entonces el lápiz
## necesita su grupo (sin él, el solape se pinta dos veces: cuñas negras).
static func _has_folds(pts: PackedVector2Array, half: PackedFloat32Array) -> bool:
	for i in range(1, pts.size() - 1):
		var a := pts[i] - pts[i - 1]
		var b := pts[i + 1] - pts[i]
		var la := a.length()
		var lb := b.length()
		if la < 1e-6 or lb < 1e-6:
			continue
		var th := absf(a.angle_to(b))
		if th < 0.05:
			continue
		if half[i] * tan(minf(th, 3.0) * 0.5) > minf(la, lb):
			return true
	return false

## Colores con variación suave de tono y luz por la longitud recorrida.
static func _jitter_colors(cols: PackedColorArray, ks: PackedInt32Array, cum: PackedFloat32Array, amount: float, width: float, nverts: int) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(nverts)
	var single := cols.size() == 1
	var period := maxf(width * 6.0, 0.5)
	for i in nverts:
		var c: Color = cols[0] if single else cols[mini(i, cols.size() - 1)]
		var t := cum[ks[mini(i, ks.size() - 1)]] / period
		var n1 := sin(t * 1.7) * 0.6 + sin(t * 0.63 + 1.3) * 0.4
		var n2 := sin(t * 1.13 + 2.1) * 0.5 + sin(t * 0.41) * 0.5
		var h := fposmod(c.h + n1 * 0.08 * amount, 1.0)
		var v := clampf(c.v + n2 * 0.25 * amount * (1.0 if c.v < 0.5 else -1.0), 0.0, 1.0)
		var s2 := clampf(c.s + absf(n1) * 0.2 * amount, 0.0, 1.0) if c.s > 0.05 else c.s
		out[i] = Color.from_hsv(h, s2, v, c.a)
	return out

## Veces que se ha recalculado la geometría (pruebas y perfiles).
var geom_builds := 0
var _geom: Dictionary = {}
var _geom_cache_key := 0

## Lo que define la forma: puntos, grosor, curva de presión, remates,
## estilo y ángulo de plumilla. NO el color, el degradado ni la opacidad.
func _geom_key() -> int:
	var wk := 0
	var wc := line.width_curve
	if wc:
		var acc := PackedFloat32Array()
		for i in wc.point_count:
			var q := wc.get_point_position(i)
			acc.append_array([q.x, q.y, wc.get_point_left_tangent(i), wc.get_point_right_tangent(i)])
		wk = hash([wc.get_instance_id(), acc, wc.bake_resolution, wc.min_value, wc.max_value])
	return hash([line.points, line.width, wk, line.begin_cap_mode, line.end_cap_mode,
		String(line.get_meta("brush_style", "")), float(line.get_meta("nib_angle", NIB_ANGLE_DEG)),
		hash(line.get_meta("brush_obj", {})), line.has_meta("brush_texture"), hash(line.get_meta("brush_geo", {}))])

## Malla que se dibuja ({points, indices}, en local del trazo) si ya está
## calculada para la forma ACTUAL; si no, vacío (no se fuerza: con miles de
## trazos fuera de pantalla saldría caro).
func visual_mesh() -> Dictionary:
	if _geom.is_empty() or not is_instance_valid(line) or _geom_key() != _geom_cache_key:
		return {}
	return _geom.get("m", {})

var _bounds_key := 0
var _bounds := Rect2()

## Caja LOCAL de lo que se ve (presión, remates, figuras, texto en trazado);
## Rect2() si la malla aún no está calculada.
func visual_bounds() -> Rect2:
	var m := visual_mesh()
	if m.is_empty():
		return Rect2()
	if _bounds_key == _geom_cache_key and _bounds.has_area():
		return _bounds
	var v: PackedVector2Array = m.get("points", PackedVector2Array())
	if v.is_empty():
		return Rect2()
	var mn := v[0]
	var mx := v[0]
	for q in v:
		mn = mn.min(q)
		mx = mx.max(q)
	_bounds = Rect2(mn, mx - mn)
	_bounds_key = _geom_cache_key
	return _bounds

func _build_geom() -> Dictionary:
	var ax := centerline(line)
	var pts: PackedVector2Array = ax[0]
	var half: PackedFloat32Array = ax[1]
	var cum: PackedFloat32Array = ax[2]
	var total := maxf(cum[pts.size() - 1], 0.0001) if pts.size() > 0 else 1.0
	if String(line.get_meta("brush_style", "")) == "object":
		# Pincel de objeto (VGSE fase 2): figuras estampadas a lo largo del eje.
		var bo: Dictionary = line.get_meta("brush_obj", {})
		var src: Array = ObjectBrush.from_data(bo.get("src", []))
		if src.is_empty():
			src = ObjectBrush.preset("star")
		var mo: Dictionary = ObjectBrush.build(pts, half, src, bo.get("params", {}))
		var ouv := PackedVector2Array()
		ouv.resize((mo["points"] as PackedVector2Array).size())
		ouv.fill(Vector2(0.0, 0.5))
		return {"ax": ax, "m": mo, "uvs": ouv}
	var air := String(line.get_meta("brush_style", "")) == "airbrush"
	var m := StrokeGeom.stamps(pts, half, ax[3]) if air \
		else StrokeGeom.strip_mesh(pts, half, _cap(line.begin_cap_mode), _cap(line.end_cap_mode), true)
	var verts: PackedVector2Array = m["points"]
	var uvs := PackedVector2Array()
	if not (m["indices"] as PackedInt32Array).is_empty():
		# Con textura «a lo largo» hace falta la u (longitud recorrida).
		uvs = _uvs(verts, pts, cum, total, half, m.get("v", PackedFloat32Array()), line.has_meta("brush_texture"))
		if line.has_meta("brush_texture") and m.has("k"):
			# Textura «a lo largo»: u = longitud recorrida en teselas de 2
			# grosores, por el punto del eje de CADA vértice (la malla no es
			# una tira de 2 vértices por punto: _uvs lo suponía).
			var kt: PackedInt32Array = m["k"]
			var tile := maxf(line.width * 2.0, 0.001)
			for i in mini(uvs.size(), kt.size()):
				uvs[i].x = cum[kt[i]] / tile
		if String(line.get_meta("brush_style", "")) == "pencil" and m.has("k"):
			# Lápiz: u = longitud recorrida (unidades del lienzo) para las vetas
			# de la mina a lo largo del trazo.
			var ks: PackedInt32Array = m["k"]
			for i in mini(uvs.size(), ks.size()):
				uvs[i].x = cum[ks[i]]
	var out := {"ax": ax, "m": m, "uvs": uvs, "folds": _has_folds(pts, half) if String(line.get_meta("brush_style", "")) == "pencil" else false}
	var gio: Object = StrokeGeom._native_geom()
	if String(line.get_meta("brush_style", "")) == "pencil" and m.has("k") and gio and gio.has_method("pencil_alpha"):
		out["pencil_a"] = gio.pencil_alpha(m["k"], m.get("beyond", PackedFloat32Array()), cum, half,
			ax[3] if ax.size() > 3 else PackedFloat32Array(), total)
	return out

## Eje del trazo tal como se pinta: [puntos, medio grosor, longitud acumulada].
## Lo usan el render y «Convertir trazo en contorno» (misma forma exacta).
static func centerline(l: Line2D) -> Array:
	var pts := StrokeGeom.clean(l.points, clampf(l.width * 0.05, 0.0005, 2.0), false)
	# Un punto al menos cada grosor: en un tramo recto la limpieza deja solo
	# los extremos, y lo que va por vértice (presión del lápiz, desvanecido
	# de las puntas) se estiraba por todo el trazo (salía a medio tono).
	var geo: Dictionary = l.get_meta("brush_geo", {}) if l.has_meta("brush_geo") else {}
	var geo_period := maxf(l.width * float(geo.get("size", 1.5)), 0.05)
	pts = _densify(pts, maxf(minf(l.width, geo_period / 8.0) if not geo.is_empty() else l.width, 0.02))
	if not geo.is_empty():
		pts = _geo_fx(pts, l.width * float(geo.get("amount", 0.5)), geo_period, String(geo.get("type", "wave")), hash(l.points[0]) if l.points.size() > 0 else 0)
	var n := pts.size()
	var half := PackedFloat32Array()
	half.resize(n)
	var cum := PackedFloat32Array()
	cum.resize(n)
	for i in range(1, n):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	var total := maxf(cum[n - 1], 0.0001) if n > 0 else 1.0
	var wc := l.width_curve
	var flow := PackedFloat32Array()
	var air := String(l.get_meta("brush_style", "")) == "airbrush"
	var pencil := String(l.get_meta("brush_style", "")) == "pencil"
	var nib := String(l.get_meta("brush_style", "")) == "calligraphy"
	var nib_dir := Vector2.from_angle(deg_to_rad(float(l.get_meta("nib_angle", NIB_ANGLE_DEG))))
	for i in n:
		var f := wc.sample_baked(cum[i] / total) if wc else 1.0
		if nib and n > 1:
			# Plumilla plana: el trazo es ancho de través y fino a lo largo
			# del ángulo de la plumilla (geometría pura: se exporta y se
			# puede convertir en contorno).
			# Dirección medida en un tramo de longitud (no entre puntos
			# vecinos: en la vista previa están muy juntos y el grosor
			# salía dentado).
			var win := maxf(l.width * 0.6, 2.0)
			var a := i
			while a > 0 and cum[i] - cum[a] < win:
				a -= 1
			var b := i
			while b < n - 1 and cum[b] - cum[i] < win:
				b += 1
			var t := (pts[b] - pts[a]).normalized()
			f *= NIB_MIN + (1.0 - NIB_MIN) * absf(t.cross(nib_dir))
		if air:
			# La presión en el aerógrafo es sobre todo flujo: poco cambio de
			# anchura (si no, con poca presión quedaba una línea dura y fina).
			flow.append(clampf(pow(f, 0.8), 0.0, 1.0))
			f = 0.6 + 0.4 * f
		elif pencil:
			# Lápiz (como Krita): la presión cambia el GROSOR (rozar = fino)
			# y la oscuridad (va al sombreador como «flujo»).
			flow.append(clampf(f, 0.0, 1.0))
			f = 0.3 + 0.7 * f
		half[i] = maxf(l.width * 0.5 * f, l.width * 0.01)
	return [pts, half, cum, flow]

## EFECTO GEOMÉTRICO del eje (VGSE fase 5): ondulado, zigzag o rugoso; mueve
## los puntos por la normal (forma REAL: se respeta al convertir en contorno,
## en la sombra y al exportar). Extremos fijos (fundido en el primer y el
## último periodo).
static func _geo_fx(pts: PackedVector2Array, amp: float, period: float, kind: String, seed: int) -> PackedVector2Array:
	var n := pts.size()
	if n < 3 or amp <= 0.0:
		return pts
	var cum := PackedFloat32Array()
	cum.resize(n)
	for i in range(1, n):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	var total := cum[n - 1]
	var out := pts.duplicate()
	for i in range(1, n - 1):
		var d := (pts[i + 1] - pts[i - 1]).normalized()
		var nrm := Vector2(-d.y, d.x)
		var t := cum[i] / period
		var f := 0.0
		match kind:
			"zigzag":
				f = 1.0 - 4.0 * absf(fposmod(t + 0.25, 1.0) - 0.5)
			"rough":
				var k := int(floor(t * 2.0))
				var a := float(hash([seed, k]) & 0xFFFF) / 32767.5 - 1.0
				var b := float(hash([seed, k + 1]) & 0xFFFF) / 32767.5 - 1.0
				var fr := t * 2.0 - k
				f = lerpf(a, b, fr * fr * (3.0 - 2.0 * fr))
			_:
				f = sin(t * TAU)
		var fade := clampf(minf(cum[i], total - cum[i]) / maxf(period, 0.001), 0.0, 1.0)
		out[i] = pts[i] + nrm * f * amp * fade
	return out

static func _densify(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var k := int(a.distance_to(b) / step)
		for j in range(1, k + 1):
			var t := float(j) / float(k + 1)
			out.append(a.lerp(b, t))
		out.append(b)
	return out

## Estilo del trazo para el sombreador (meta «brush_style»: también en
## documentos guardados). 0 = pluma / caligráfico.
static func style_id(l: Line2D) -> int:
	if not is_instance_valid(l):
		return 0
	return int(STYLE_IDS.get(String(l.get_meta("brush_style", "")), 0))

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
func _colors(verts: PackedVector2Array, pts: PackedVector2Array, cum: PackedFloat32Array, total: float,
		m: Dictionary = {}, half: PackedFloat32Array = PackedFloat32Array(), flow: PackedFloat32Array = PackedFloat32Array()) -> PackedColorArray:
	var base := line.default_color
	var ks: PackedInt32Array = m.get("k", PackedInt32Array())
	var has_k := ks.size() == verts.size()
	var air := String(line.get_meta("brush_style", "")) == "airbrush" and has_k
	var pencil := String(line.get_meta("brush_style", "")) == "pencil" and has_k
	var c_base := Color(1, 1, 1, base.a) if has_gradient_fill() else base
	if not air and not pencil and not line.gradient:
		# El color lo pone el shader (degradado 2D) o es liso.
		return PackedColorArray([c_base])
	var bey: PackedFloat32Array = m.get("beyond", PackedFloat32Array())
	var out2 := PackedColorArray()
	out2.resize(verts.size())
	for i in verts.size():
		var k: int
		if has_k:
			k = ks[i]
		else:
			@warning_ignore("integer_division")
			k = mini(i / 2, pts.size() - 1) if i < pts.size() * 2 else _nearest(pts, verts[i])
		var c := c_base
		if line.gradient and not has_gradient_fill():
			c = line.gradient.sample(cum[k] / total)
		if air:
			# Aerógrafo: la presión es FLUJO (más o menos pintura) y las puntas
			# se desvanecen a lo largo ~1,5 grosores, como un spray de verdad.
			var h := half[k]
			var d := minf(cum[k], total - cum[k]) - (bey[i] if i < bey.size() else 0.0)
			c.a *= smoothstep(-h, h * 1.5, d) * (flow[k] if k < flow.size() else 1.0)
		elif pencil:
			# El sombreador lee la presión en el alfa (rellena más o menos
			# grano); la opacidad del pincel la pone el grupo.
			var hp := half[k]
			var dp := minf(cum[k], total - cum[k]) - (bey[i] if i < bey.size() else 0.0)
			# Hacia la punta queda menos grafito (la mina apenas apoya): sin
			# el «botón» oscuro y de borde liso en cada extremo.
			c.a *= maxf(flow[k] if k < flow.size() else 1.0, 0.02) * lerpf(0.25, 1.0, smoothstep(-hp, hp * 1.2, dp))
		out2[i] = c
	return out2

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
	var sid := style_id(line)
	var grade := String(line.get_meta("pencil_grade", DEFAULT_GRADE)) if sid == 1 else ""
	var overwrite := sid == 1 and _pencil_folds
	var key := "%d:%s:%s" % [sid, grade, "f" if overwrite else ""]
	var tex: Dictionary = line.get_meta("brush_texture", {}) if line.has_meta("brush_texture") else {}
	if (g == null or g.get_point_count() < 2) and tex.is_empty():
		if not _shared_mats.has(key):
			var sm := ShaderMaterial.new()
			sm.shader = _shader_for(sid) if overwrite else STROKE_SHADER
			sm.set_shader_parameter("style", sid)
			_set_grade(sm, grade)
			_shared_mats[key] = sm
		_use_material(_shared_mats[key])
		return
	var mat := stroke_material
	if mat == null or _shared_mats.values().has(mat):
		mat = ShaderMaterial.new()
		mat.set_shader_parameter("use_grad", true)
		_use_material(mat)
	mat.shader = _shader_for(sid) if overwrite else STROKE_SHADER
	mat.set_shader_parameter("style", sid)
	_set_grade(mat, grade)
	if _grad_tex == null:
		_grad_tex = GradientTexture1D.new()
		_grad_tex.width = 256
	if _grad_tex.gradient != g:
		_grad_tex.gradient = g   # la textura sigue los cambios de las paradas
	# Textura dentro del trazo (VGSE fase 4)
	mat.set_shader_parameter("use_tex", not tex.is_empty())
	if not tex.is_empty():
		var tname := String(tex.get("name", "canvas"))
		mat.set_shader_parameter("stroke_tex", StrokeTextures.image_texture(String(tex.get("path", ""))) if tname == "image" else StrokeTextures.get_texture(tname))
		mat.set_shader_parameter("tex_mode", 1.0 if String(tex.get("mode", "along")) == "paper" else 0.0)
		mat.set_shader_parameter("tex_scale", float(tex.get("scale", 1.0)))
		mat.set_shader_parameter("tex_strength", float(tex.get("strength", 1.0)))
	if g == null or g.get_point_count() < 2:
		mat.set_shader_parameter("use_grad", false)
		return
	mat.set_shader_parameter("use_grad", true)
	mat.set_shader_parameter("grad_tex", _grad_tex)
	mat.set_shader_parameter("p0", _a())
	mat.set_shader_parameter("p1", _b())
	mat.set_shader_parameter("gtype", fill_gradient_type)

## Lápiz: escribe cada píxel SIN mezclar dentro de su grupo interno. En
## los giros más cerrados que el grosor la malla se pliega y, con mezcla,
## esos triángulos se pintaban dos veces (cuñas negras). El valor del lápiz
## solo depende de la posición en el papel y de la presión, así que un
## píxel pintado dos veces queda igual. El grupo compone luego el trazo.
static var _pencil_shader: Shader = null

static func _shader_for(sid: int) -> Shader:
	if sid != 1:
		return STROKE_SHADER
	if _pencil_shader == null:
		_pencil_shader = Shader.new()
		_pencil_shader.code = STROKE_SHADER.code.replace("shader_type canvas_item;",
			"shader_type canvas_item;\nrender_mode blend_disabled;\n#define OVERWRITE")
	return _pencil_shader

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
