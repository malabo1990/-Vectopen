# ==========================================
# RUTA: res://scripts/canvas/world_text_label.gd
# Texto del mundo (lienzo) OPTIMIZADO para contenido masivo.
#
# Rendimiento:
#  - ZOOM ALTO (>= ZOOM_VECTOR_MIN): el font_size efectivo queda FIJO en
#    VECTOR_FONT (4096px). Solo se rasteriza UNA vez por texto (no por tick
#    de zoom). El overlay VECTORIAL (contornos Bezier, cacheados una sola
#    vez) mantiene la nitidez infinita por encima del bitmap.
#  - ZOOM NORMAL: re-raster con throttle (solo si eff cambia >= 4%).
#  - CULLING: los labels fuera del viewport de la camara NO se actualizan
#    ni se redibujan (_process no hace nada) → 10.000 textos viables
#    (solo se procesa lo visible en pantalla).
#  - build_outline_path(): Path2D con curvas reales para text-to-shape.
# ==========================================
extends Label
class_name WorldTextLabel

## Fuente por defecto (fallback si FontCore no está o la familia no resuelve).
const FONT_PATH := "res://assets/fonts/Inter-Regular.ttf"

## Metas de tipografía que este label respeta (las escribe InspectorCore /
## el panel de texto vía FontCore).
const META_FAMILY := "font_family"
const META_WEIGHT := "font_weight"
const META_ITALIC := "font_italic"

## Tamaño de fuente BASE en unidades del mundo (lo que se ve a zoom 1.0).
@export var base_font_size: int = 24

const MIN_FONT := 2
const VECTOR_FONT := 512       # tope de raster del bitmap (fallback); el
							   # overlay vectorial da la nitidez real a zoom alto.
							   # (4096 rasterizaba glifos ENORMES por texto —
							   # 8.8s por label → bloqueaba con 100+ textos)
const ZOOM_VECTOR_MIN := 16.0  # a partir de aqui eff fijo + overlay
const RASTER_THROTTLE := 0.04  # 4% de cambio de eff para re-rasterizar
const WORLD_SIZE_META := "world_text_size"
const CULL_MARGIN := 400.0     # margen de culling (px mundo)

var _last_zoom := -1.0
var _last_eff := -1
var _world_size := Vector2.ZERO
var _last_text := ""
var _cached_outline: Node2D = null   # contornos VECTOR_FONT (una vez)
var _outline_dirty := true
var _cached_polys: Array[PackedVector2Array] = []
var _polys_baked := false   # triangulación hecha (aunque diera vacío) → no re-bakear por frame

## Cache de layout para no recalcular metrics por cada cambio de zoom.
## Clave: texto + font_size efectivo. Valida el contenido SIN pedir al
## TextServer otra vez si ya se calculo (parte del cuello de botella actual:
## cada tick re-pedia metrics).
var _layout_cache_key: String = ""
var _layout_cache_size: Vector2 = Vector2.ZERO

## Tamaño "lógico" del texto en el mundo. Los tools cambian esto (CMD+arrastre).
var world_font_size: int = 0:
	set(v):
		if v != world_font_size and v > 0:
			world_font_size = v
			base_font_size = v
			if is_inside_tree():
				_apply_zoom(_canvas_zoom())

static var _fallback_font: Font = null
static var _ts: TextServer = null
## Fuente actual de ESTA instancia (resuelta por FontCore desde las metas).
var _font: Font = null
## Presupuesto GLOBAL de bakes de contorno por frame. Cuando 200+ labels
## cruzan ZOOM_VECTOR_MIN a la vez (zoom extremo de golpe), bakear todos sus
## contornos en 1 frame daba un tirón de 8-2 FPS. Repartimos: como máximo
## MAX_BAKES_PER_FRAME por frame; el resto sigue mostrando el bitmap (nítido
## de sobra a esa distancia) y se bakea en frames siguientes.
const MAX_BAKES_PER_FRAME := 6
static var _bake_frame: int = -1
static var _bakes_this_frame: int = 0

# ------------------------------------------------------------------ lifecycle
func _ready() -> void:
	_apply_font()
	if base_font_size <= 0:
		base_font_size = 24
	if world_font_size <= 0:
		world_font_size = base_font_size
	_last_text = text
	_last_zoom = 1.0
	_apply_zoom(1.0)
	# CULLING GLOBAL: el CullManager barre el grupo "world_content" una vez
	# cada 2 frames y apaga visible/process de lo no visible.
	add_to_group("world_content")
	# LOD sub-pixel: a zoom muy alejado el texto es ilegible; el CullManager
	# apaga los labels de este grupo cuando su huella en pantalla < min_screen_px
	# (aleja el zoom con 10.000 textos y sigue a 60 FPS).
	add_to_group("cull_subpixel")

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# El overlay vectorial es un Node2D fuera del árbol (solo referenciado):
		# liberarlo a mano o quedan huérfanos + RIDs de CanvasItem colgando.
		if is_instance_valid(_cached_outline):
			_cached_outline.free()
			_cached_outline = null

## Dónde viven las metas de tipografía: en este label o en su contenedor
## (InspectorCore / el serializador escriben en el contenedor de texto).
func _spec_source() -> Object:
	if has_meta(META_FAMILY) or has_meta(META_WEIGHT) or has_meta(META_ITALIC):
		return self
	var p := get_parent()
	if p and (p.has_meta(META_FAMILY) or p.has_meta(META_WEIGHT) or p.has_meta(META_ITALIC)):
		return p
	return self

func _font_core():
	var st := Engine.get_main_loop() as SceneTree
	return st.root.get_node_or_null("FontCore") if st else null

## Resuelve la fuente de esta instancia desde las metas vía FontCore y la aplica.
## Los RID de contorno los posee y libera FontCore (sin fugas al salir).
func _apply_font() -> void:
	var fc = _font_core()
	if fc and fc.has_method("get_font"):
		_font = fc.get_font(fc.spec_from_node(_spec_source()))
	# Tracking (interletra): FontVariation con spacing sobre la fuente resuelta.
	var ls := int(_spec_source().get_meta("letter_spacing", 0))
	if ls != 0 and _font:
		var fv := FontVariation.new()
		fv.base_font = _font
		fv.spacing_glyph = ls
		fv.spacing_space = ls
		_font = fv
	if _font == null:
		if _fallback_font == null:
			_fallback_font = load(FONT_PATH) as Font
		_font = _fallback_font
	if _font:
		add_theme_font_override("font", _font)

## Llamado por InspectorCore / el panel de texto cuando cambia la familia.
func apply_font_from_meta() -> void:
	_apply_font()
	_outline_dirty = true
	_polys_baked = false
	_layout_cache_key = ""
	_last_eff = -1
	if is_inside_tree():
		_refresh_local_rect()
	queue_redraw()

func _process(_delta: float) -> void:
	# CULLING: fuera del viewport => no hacemos nada (con 10.000 textos
	# solo se paga lo que se ve en pantalla).
	if not _is_visible_in_view():
		return
	var z := _canvas_zoom()
	if z <= 0.0:
		return
	if absf(z - _last_zoom) < 0.005:
		_sync_layout_if_content_changed()
		return
	_apply_zoom(z)

## Mientras no cambie el zoom, re-fija el layout si el texto cambió.
func _sync_layout_if_content_changed() -> void:
	if text == _last_text:
		return
	_last_text = text
	_outline_dirty = true
	_polys_baked = false
	_refresh_local_rect()
	queue_redraw()

func _is_visible_in_view() -> bool:
	var cam := _find_camera()
	if cam == null:
		return true
	var cam_zoom: Vector2 = cam.zoom
	if cam_zoom.x <= 0.0 or cam_zoom.y <= 0.0:
		cam_zoom = Vector2.ONE
	var vp_size: Vector2 = cam.get_viewport_rect().size
	var world_size: Vector2 = vp_size / cam_zoom
	var half: Vector2 = world_size * 0.5
	var view_rect := Rect2(cam.get_screen_center_position() - half, world_size)
	var gpos := get_global_position()
	var gscale := get_global_transform().get_scale()
	var gsize: Vector2 = size * gscale
	return view_rect.grow(CULL_MARGIN).intersects(Rect2(gpos, gsize))

func _find_camera() -> Camera2D:
	var node: Node = self
	while node:
		if node is Node2D and node.is_in_group("_vectopen_canvas"):
			var cam := node.get_node_or_null("Camera2D") as Camera2D
			if cam:
				return cam
			break
		node = node.get_parent()
	if is_inside_tree():
		var vp := get_viewport()
		if vp:
			return vp.get_camera_2d()
	return null

func _canvas_zoom() -> float:
	var cam := _find_camera()
	if cam:
		var z: float = cam.zoom.x
		if z > 0.0:
			return z
	return 1.0

# ------------------------------------------------------------------ rendering
## Aplica el render optimizado para el zoom dado. Geometría en el mundo
## constante: tamaño_mundo = rect(fuente eff) x (base/eff) = base SIEMPRE.
func _apply_zoom(z: float) -> void:
	if z <= 0.0:
		return
	_last_zoom = z
	var eff: int
	if z >= ZOOM_VECTOR_MIN:
		# A partir de aquí: el overlay vectorial mantiene la nitidez.
		# El bitmap queda FIJO en VECTOR_FONT (1 sola rasterización).
		eff = VECTOR_FONT
	else:
		eff = clampi(int(round(base_font_size * z)), MIN_FONT, VECTOR_FONT)
	# RÉGIMEN VECTORIAL YA FIJO: bitmap (eff), escala y overlay NO dependen del
	# zoom de cámara — no hay NADA que recalcular por frame mientras el usuario
	# sigue zoomeando. Sin este corte, 200+ labels visibles a zoom >16 hacían
	# add_theme_font_size_override + queue_redraw cada frame → 1 FPS a 1000x+.
	if eff == VECTOR_FONT and _last_eff == VECTOR_FONT:
		return
	# THROTTLE: no re-raster si el eff casi no cambió (energía/velocidad).
	if _last_eff >= 0 and absf(float(eff - _last_eff)) / maxf(1.0, eff) < RASTER_THROTTLE and eff < VECTOR_FONT:
		return
	_last_eff = eff
	add_theme_font_size_override("font_size", eff)
	var comp := base_font_size / float(eff)
	scale = Vector2(comp, comp)
	# NOTA: el outline se construye a VECTOR_FONT fijo y NO depende del zoom:
	# solo se invalida al cambiar el texto (== > _sync_layout_if_content_changed).
	_refresh_local_rect()
	queue_redraw()

func _refresh_local_rect() -> void:
	var font := get_theme_font("font")
	var z := _last_zoom if _last_zoom > 0.0 else 1.0
	if has_meta(WORLD_SIZE_META) or _world_size != Vector2.ZERO:
		var ws: Vector2 = get_meta(WORLD_SIZE_META, _world_size)
		var local := ws * z
		custom_minimum_size = local
		size = local
		return
	if font and text != "":
		var fs := maxi(1, get_theme_font_size("font_size"))
		# CACHE: solo preguntar metrics si el texto o el tamaño cambiaron
		var cache_key := "%s|%d" % [text, fs]
		if cache_key != _layout_cache_key:
			_layout_cache_key = cache_key
			_layout_cache_size = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, -1, 0)
		custom_minimum_size = Vector2.ZERO
		size = _layout_cache_size

## El tool indica el rect del texto EN UNIDADES DE MUNDO (para autowrap).
func set_world_size(ws: Vector2) -> void:
	_world_size = ws
	set_meta(WORLD_SIZE_META, ws)
	_refresh_local_rect()

## Mínimo del contenido en unidades de mundo (pregunta a la implementación
## nativa del Label: fuente base, escala 1, rect en mundo). Robusto con wrap.
func get_world_minimum_size() -> Vector2:
	var save_fs: int = get_theme_font_size("font_size")
	var save_scale := scale
	var save_size := size
	add_theme_font_size_override("font_size", maxi(1, base_font_size))
	scale = Vector2.ONE
	if has_meta(WORLD_SIZE_META) or _world_size != Vector2.ZERO:
		size = get_meta(WORLD_SIZE_META, _world_size)
	else:
		size = Vector2.ZERO
	var m := get_combined_minimum_size()
	add_theme_font_size_override("font_size", save_fs)
	scale = save_scale
	size = save_size
	return m

# ------------------------------------------------------------------ drawing
func _draw() -> void:
	# El bitmap del Label siempre visible por debajo (garantía).
	if _last_zoom < ZOOM_VECTOR_MIN:
		return
	# No pagar el bake de contornos para labels fuera de pantalla.
	if not _is_visible_in_view():
		return
	# Presupuesto global de bakes/frame: si aún no está bakeado y ya se gastó
	# el cupo, dejamos el bitmap otro frame y volvemos a intentarlo.
	if not _polys_baked:
		var fr := Engine.get_frames_drawn()
		if fr != _bake_frame:
			_bake_frame = fr
			_bakes_this_frame = 0
		if _bakes_this_frame >= MAX_BAKES_PER_FRAME:
			queue_redraw()
			return
		_bakes_this_frame += 1
	var polys := _get_triangle_polys()
	if polys.is_empty():
		return
	var col := font_color()
	for poly in polys:
		draw_colored_polygon(poly, col)

func font_color() -> Color:
	var c := get_theme_color("font_color")
	if c.a <= 0.0:
		c = Color.BLACK
	return c

# ------------------------------------------------------------------ outline (cache)
func _get_outline() -> Node2D:
	if not _outline_dirty and is_instance_valid(_cached_outline):
		return _cached_outline
	_outline_dirty = false
	if _cached_outline != null:
		_cached_outline.queue_free()
		_cached_outline = null
	_cached_outline = _build_outline_at(VECTOR_FONT)
	_cached_polys = []
	_polys_baked = false
	return _cached_outline

func _get_triangle_polys() -> Array[PackedVector2Array]:
	# Bake una sola vez: si la triangulación de un glifo da vacío NO se debe
	# reintentar cada frame (era el 2º origen del cuello de botella a zoom alto).
	if _polys_baked:
		return _cached_polys
	var outline := _get_outline()
	if outline == null:
		return _cached_polys
	_cached_polys = _triangulate_even_odd(outline)
	_polys_baked = true
	return _cached_polys

func _triangulate_even_odd(outline: Node2D) -> Array[PackedVector2Array]:
	var polys: Array[PackedVector2Array] = []
	var all := _outline_polygons(outline)
	if all.size() == 0:
		return polys
	all.sort_custom(func(a, b) -> bool: return _abs_area(a) > _abs_area(b))
	var outer := all[0]
	if _signed_area(outer) < 0.0:
		outer = _reversed(outer)
	var holes: Array[PackedVector2Array] = []
	for i in range(1, all.size()):
		var h := all[i]
		if _signed_area(h) > 0.0:
			h = _reversed(h)
		if Geometry2D.is_point_in_polygon(h[0], outer):
			holes.append(h)
	if holes.is_empty():
		if Geometry2D.triangulate_polygon(outer).size() > 0:
			polys.append(outer)
		return polys
	var combined := PackedVector2Array(outer)
	for hole in holes:
		combined = _attach_hole(combined, hole)
	if Geometry2D.triangulate_polygon(combined).size() > 0:
		polys.append(combined)
	return polys

func _outline_polygons(outline: Node2D) -> Array[PackedVector2Array]:
	var res: Array[PackedVector2Array] = []
	for child in outline.get_children():
		if child is Path2D and child.curve:
			var curve: Curve2D = (child as Path2D).curve
			curve.bake_interval = 2.5
			var pts: PackedVector2Array = curve.get_baked_points()
			if pts.size() >= 3:
				res.append(pts)
	return res

func _signed_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var j := (i + 1) % pts.size()
		a += pts[i].x * pts[j].y - pts[j].x * pts[i].y
	return a * 0.5

func _abs_area(pts: PackedVector2Array) -> float:
	return absf(_signed_area(pts))

func _reversed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size(), 0, -1):
		out.append(pts[i - 1])
	return out

func _attach_hole(combined: PackedVector2Array, hole: PackedVector2Array) -> PackedVector2Array:
	if hole.size() < 3:
		return combined
	var min_i := 0
	for i in hole.size():
		if hole[i].x < hole[min_i].x:
			min_i = i
	var hx: float = hole[min_i].x
	var hy: float = hole[min_i].y
	var best_idx := -1
	var best_dist := 0.0
	for i in combined.size():
		var cp: Vector2 = combined[i]
		if absf(cp.y - hy) < 2.0 and cp.x < hx:
			var d := hx - cp.x
			if best_idx < 0 or d < best_dist:
				best_idx = i
				best_dist = d
	if best_idx < 0:
		best_idx = 0
	var out := PackedVector2Array()
	for i in combined.size():
		out.append(combined[i])
		if i == best_idx:
			out.append(combined[i])
			for k in range(min_i, hole.size() + min_i):
				out.append(hole[k % hole.size()])
			out.append(out[best_idx])
	return out

# ------------------------------------------------------------------ outline builder
## CONVERTIR TEXTO A FORMA (text-to-shape): Path2D con curvas reales a
## tamaño base. Cache interno: _build_outline_at(VECTOR_FONT) para el overlay.
func build_outline_path() -> Node2D:
	return _build_outline_at(maxi(1, get_theme_font_size("font_size")))

func _build_outline_at(fs_use: int) -> Node2D:
	var ts := _get_ts()
	var rid := _make_outline_rid(ts)
	var font := get_theme_font("font")
	if not rid.is_valid() or not font:
		if rid.is_valid():
			ts.free_rid(rid)
		return null
	var container := Node2D.new()
	container.name = "TextOutline_%s" % name
	var fs: int = maxi(1, fs_use)

	var line_height: float = font.get_height(fs)
	var y_offset := 0.0
	var wrap_world := 0.0
	if autowrap_mode != TextServer.AUTOWRAP_OFF:
		wrap_world = (size * scale).x
	var lines := _wrap_lines(font, fs, wrap_world)

	for line in lines:
		var line_w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx := 0.0
		if horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and wrap_world > 0.0:
			cx += (wrap_world - line_w) / 2.0
		for i in line.length():
			var codepoint: int = line.unicode_at(i)
			var glyph: int = ts.font_get_glyph_index(rid, fs, codepoint, 0)
			var adv: float = ts.font_get_glyph_advance(rid, fs, glyph).x
			if glyph <= 0:
				cx += maxf(adv, font.get_char_size(codepoint, fs).x)
				continue
			_append_glyph_path(ts, rid, fs, glyph, container, cx, y_offset)
			cx += adv if adv > 0.0 else font.get_char_size(codepoint, fs).x
		y_offset += line_height

	ts.free_rid(rid)
	if container.get_child_count() == 0:
		container.queue_free()
		return null
	return container

static func _get_ts() -> TextServer:
	if _ts == null:
		_ts = TextServerManager.get_primary_interface()
	return _ts

## RID de TextServer EFÍMERO con los bytes de la fuente actual (los da FontCore),
## para leer los contornos de glifo. El llamador (`_build_outline_at`) SIEMPRE lo
## libera al terminar — así no hay fugas de RID al cerrar.
func _make_outline_rid(ts) -> RID:
	var bytes := PackedByteArray()
	var fc = _font_core()
	if fc and fc.has_method("font_bytes"):
		bytes = fc.font_bytes(fc.spec_from_node(_spec_source()))
	if bytes.is_empty():
		bytes = FileAccess.get_file_as_bytes(FONT_PATH)
	if bytes.is_empty():
		return RID()
	var r: RID = ts.create_font()
	if r.is_valid():
		ts.font_set_data(r, bytes)
	return r

func _append_glyph_path(ts, rid: RID, fs: int, glyph: int, container: Node2D, ox: float, oy: float) -> void:
	var data: Dictionary = ts.font_get_glyph_contours(rid, fs, glyph)
	if data.is_empty():
		return
	var points: PackedVector3Array = data.get("points", PackedVector3Array())
	var contours_idx: PackedInt32Array = data.get("contours", PackedInt32Array())
	if points.is_empty() or contours_idx.is_empty():
		return
	var start := 0
	for contour_end in contours_idx:
		var arc: PackedVector3Array = points.slice(start, int(contour_end) + 1)
		start = int(contour_end) + 1
		var curve := _contour_to_curve(arc, ox, oy)
		if curve == null or curve.point_count == 0:
			continue
		var path := Path2D.new()
		path.name = "Contour_%d" % container.get_child_count()
		path.curve = curve
		container.add_child(path)

func _contour_to_curve(arc: PackedVector3Array, ox: float, oy: float) -> Curve2D:
	if arc.size() < 2:
		return null
	var n := arc.size()
	var first_on := 0
	for j in n:
		if int(arc[j].z) == 1:
			first_on = j
			break
	var curve := Curve2D.new()
	var add_cubic := func(p0: Vector2, cp1: Vector2, cp2: Vector2, p1: Vector2) -> void:
		var i0: int = curve.point_count
		if i0 == 0:
			curve.add_point(Vector2(p0.x + ox, -p0.y + oy), Vector2.ZERO, Vector2(cp1.x - p0.x, -(cp1.y - p0.y)))
		else:
			curve.set_point_out(i0 - 1, Vector2(cp1.x - p0.x, -(cp1.y - p0.y)))
		curve.add_point(Vector2(p1.x + ox, -p1.y + oy), Vector2(cp2.x - p1.x, -(cp2.y - p1.y)), Vector2.ZERO)
	var add_line := func(p0: Vector2, p1: Vector2) -> void:
		var i0: int = curve.point_count
		if i0 == 0:
			curve.add_point(Vector2(p0.x + ox, -p0.y + oy), Vector2.ZERO, Vector2.ZERO)
		curve.add_point(Vector2(p1.x + ox, -p1.y + oy), Vector2.ZERO, Vector2.ZERO)

	var prev_on := Vector2(arc[first_on].x, arc[first_on].y)
	var start_pt := prev_on
	var i := (first_on + 1) % n
	var guard := 0
	while guard < n * 3 and i != first_on:
		guard += 1
		var tag := int(arc[i].z)
		if tag == 1:
			var pt := Vector2(arc[i].x, arc[i].y)
			add_line.call(prev_on, pt)
			prev_on = pt
			i = (i + 1) % n
		elif tag == 2:
			if int(arc[(i + 1) % n].z) == 2 and int(arc[(i + 2) % n].z) == 1:
				var cp1 := Vector2(arc[i].x, arc[i].y)
				var cp2 := Vector2(arc[(i + 1) % n].x, arc[(i + 1) % n].y)
				var end := Vector2(arc[(i + 2) % n].x, arc[(i + 2) % n].y)
				add_cubic.call(prev_on, cp1, cp2, end)
				prev_on = end
				i = (i + 3) % n
			else:
				i = (i + 1) % n
		else:
			var cx_ := Vector2(arc[i].x, arc[i].y)
			var after := arc[(i + 1) % n]
			var end: Vector2
			var next_i: int
			if int(after.z) == 0:
				var on_mid: Vector2 = (cx_ + Vector2(after.x, after.y)) / 2.0
				add_cubic.call(prev_on, prev_on + (cx_ - prev_on) * (2.0 / 3.0), on_mid + (Vector2(after.x, after.y) - on_mid) * (2.0 / 3.0), on_mid)
				var after2 := arc[(i + 2) % n]
				if int(after2.z) == 1:
					var end_pt := Vector2(after2.x, after2.y)
					add_cubic.call(on_mid, on_mid + (Vector2(after.x, after.y) - on_mid) * (2.0 / 3.0), end_pt + (Vector2(after.x, after.y) - end_pt) * (2.0 / 3.0), end_pt)
					prev_on = end_pt
					next_i = (i + 3) % n
				else:
					add_cubic.call(on_mid, on_mid + (Vector2(after.x, after.y) - on_mid) * (2.0 / 3.0), Vector2(after.x, after.y), Vector2(after.x, after.y))
					prev_on = Vector2(after.x, after.y)
					next_i = (i + 2) % n
			else:
				end = Vector2(after.x, after.y)
				add_cubic.call(prev_on, prev_on + (cx_ - prev_on) * (2.0 / 3.0), end + (cx_ - end) * (2.0 / 3.0), end)
				prev_on = end
				next_i = (i + 2) % n
			i = next_i

	if curve.point_count > 0:
		var last_p: Vector2 = curve.get_point_position(curve.point_count - 1)
		var first_p: Vector2 = Vector2(start_pt.x + ox, -start_pt.y + oy)
		if last_p.distance_to(first_p) > 0.01:
			add_line.call(prev_on, start_pt)
	return curve

func _wrap_lines(font: Font, fs: int, wrap_w: float) -> Array[String]:
	var raw: PackedStringArray = text.replace("\r\n", "\n").split("\n")
	var out: Array[String] = []
	if wrap_w <= 0.0 or not font:
		for r in raw:
			out.append(r)
		return out
	for line in raw:
		var words: PackedStringArray = line.split(" ", true)
		var current := ""
		for word in words:
			var probe := current + (" " if current.length() > 0 else "") + word
			var w: float = font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if w <= wrap_w or current.length() == 0:
				current = probe
			else:
				out.append(current)
				current = word
		out.append(current)
	return out
