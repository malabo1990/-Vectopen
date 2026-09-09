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
#
# FORMATO ENRIQUECIDO POR RANGO (rich_runs):
#  - El overlay vectorial soporta color/negrita/cursiva/subrayado POR RANGO
#    de caracteres (no solo un estilo uniforme para todo el bloque). Cada
#    glifo se agrupa en su propio nodo (antes: todos los contornos del label
#    se mezclaban en UNA sola triangulación "outer+holes" global, lo que
#    rompía cualquier texto de más de un glifo con hueco — ver
#    _triangulate_contours). Negrita/cursiva se sintetizan a nivel de
#    TextServer (font_set_embolden / font_set_transform) sobre un RID por
#    combinación de estilo, cacheado durante el build.
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

## Emulación de negrita/cursiva a nivel de contorno (mismo valor que usa
## FontCore.get_font() para el bitmap vía FontVariation.variation_embolden,
## así el overlay vectorial y el bitmap concuerdan).
const BOLD_EMBOLDEN := 1.0
const ITALIC_SHEAR := 0.22

var _last_zoom := -1.0
var _last_eff := -1
var _world_size := Vector2.ZERO
var _last_text := ""
var _last_h_align: int = -1
var _last_v_align: int = -1
var _cached_outline: Node2D = null   # contornos VECTOR_FONT (una vez)
var _outline_dirty := true
var _cached_polys: Array = []        # Array[{"poly": PackedVector2Array, "run": int}]
var _cached_underlines: Array = []   # Array[{"rect": Rect2, "color": Color}]
var _polys_baked := false   # triangulación hecha (aunque diera vacío) → no re-bakear por frame

## Runs de formato enriquecido: Array[{length:int, color:Color, bold:bool,
## italic:bool, underline:bool}], en orden, cubriendo TODO `text` sin huecos
## (suma de length == text.length()). Vacío o desincronizado con el largo
## actual de `text` → se usa un único run "legacy" con el estilo de tema del
## label completo (ver _effective_runs). El dueño (TextTool / el
## serializador) es quien mantiene esto sincronizado con `text`.
var rich_runs: Array = []

## Proporciones de tamaño de letra (curva o degradado por posición):
## { "mode": "Aaa"|"aAa"|"aaA"|"AaA", "start": float, "mid": float, "end": float }
var letter_proportions: Dictionary = {}

func set_letter_proportions(props: Dictionary) -> void:
	letter_proportions = props
	_outline_dirty = true
	_polys_baked = false
	_layout_cache_key = ""
	if has_letter_proportions():
		visible_ratio = 0.0
	else:
		visible_ratio = 1.0
	_apply_zoom(_canvas_zoom())
	_refresh_local_rect()
	queue_redraw()

func has_letter_proportions() -> bool:
	if not letter_proportions.is_empty() and letter_proportions.has("mode") and String(letter_proportions.get("mode", "")) != "":
		return true
	var src := _spec_source()
	if src and src != self and src.has_meta("letter_proportions"):
		var p = src.get_meta("letter_proportions")
		if p is Dictionary and not p.is_empty() and p.has("mode") and String(p.get("mode", "")) != "":
			return true
	return false

func get_effective_letter_proportions() -> Dictionary:
	if not letter_proportions.is_empty() and letter_proportions.has("mode"):
		return letter_proportions
	var src := _spec_source()
	if src and src != self and src.has_meta("letter_proportions"):
		var p = src.get_meta("letter_proportions")
		if p is Dictionary and not p.is_empty():
			return p
	return {}

func _calculate_glyph_scale(mode: String, t: float, s_start: float, s_mid: float, s_mid2: float, s_end: float) -> float:
	match mode:
		"Aaa", "aaA":
			if not is_equal_approx(s_mid, lerpf(s_start, s_end, 1.0 / 3.0)) or not is_equal_approx(s_mid2, lerpf(s_start, s_end, 2.0 / 3.0)):
				if t <= 1.0 / 3.0:
					return lerpf(s_start, s_mid, t * 3.0)
				elif t <= 2.0 / 3.0:
					return lerpf(s_mid, s_mid2, (t - 1.0 / 3.0) * 3.0)
				else:
					return lerpf(s_mid2, s_end, (t - 2.0 / 3.0) * 3.0)
			return lerpf(s_start, s_end, t)
		"aAa", "AaA":
			if t <= 1.0 / 3.0:
				return lerpf(s_start, s_mid, t * 3.0)
			elif t <= 2.0 / 3.0:
				return lerpf(s_mid, s_mid2, (t - 1.0 / 3.0) * 3.0)
			else:
				return lerpf(s_mid2, s_end, (t - 2.0 / 3.0) * 3.0)
		_:
			return 1.0

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

## Fija los runs de formato enriquecido y fuerza rebake del overlay vectorial.
## `runs`: Array[{length:int, color:Color, bold:bool, italic:bool, underline:bool}].
func set_rich_runs(runs: Array) -> void:
	rich_runs = runs
	_outline_dirty = true
	_polys_baked = false
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

## Mientras no cambie el zoom, re-fija el layout si el texto o la alineación cambiaron.
func _sync_layout_if_content_changed() -> void:
	if text == _last_text and horizontal_alignment == _last_h_align and vertical_alignment == _last_v_align:
		return
	_last_text = text
	_last_h_align = horizontal_alignment
	_last_v_align = vertical_alignment
	_outline_dirty = true
	_polys_baked = false
	if has_letter_proportions():
		visible_ratio = 0.0
	else:
		visible_ratio = 1.0
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
	if z >= ZOOM_VECTOR_MIN or has_letter_proportions():
		# A partir de aquí o con proporciones activas: el overlay vectorial mantiene la nitidez.
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
	var ws := Vector2.ZERO
	if has_meta(WORLD_SIZE_META):
		ws = get_meta(WORLD_SIZE_META)
	elif _world_size != Vector2.ZERO:
		ws = _world_size
	else:
		var p := get_parent()
		if p and p.has_meta("width") and p.has_meta("height"):
			ws = Vector2(float(p.get_meta("width")), float(p.get_meta("height")))
			_world_size = ws
			set_meta(WORLD_SIZE_META, ws)

	if ws != Vector2.ZERO:
		var fs_cur := maxi(1, get_theme_font_size("font_size"))
		var comp := float(maxi(1, base_font_size)) / float(fs_cur)
		var local := ws / maxf(0.0001, comp)
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
	# El bitmap del Label siempre visible por debajo (garantía), salvo si hay proporciones activas
	if _last_zoom < ZOOM_VECTOR_MIN and not has_letter_proportions():
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
	var entries := _get_triangle_polys()
	if entries.is_empty():
		return
	var runs := _effective_runs()
	var default_col := font_color()
	for e in entries:
		var run_idx: int = e.get("run", 0)
		var col: Color = default_col
		if run_idx >= 0 and run_idx < runs.size():
			col = runs[run_idx].get("color", default_col)
		draw_colored_polygon(e["poly"], col)
	for u in _cached_underlines:
		draw_rect(u["rect"], u["color"])

func font_color() -> Color:
	var src := _spec_source()
	if src and src.has_meta("text_color"):
		return src.get_meta("text_color")
	var c := get_theme_color("font_color")
	if c.a <= 0.0:
		c = Color.BLACK
	return c

# ------------------------------------------------------------------ rich runs
## Normaliza `rich_runs`: si está vacío o no cubre exactamente `text.length()`
## caracteres, cae a un único run "legacy" con el estilo de tema/meta del
## label completo (compatibilidad con textos sin formato por rango).
func _effective_runs() -> Array:
	var total := 0
	for r in rich_runs:
		total += int(r.get("length", 0))
	if not rich_runs.is_empty() and total == text.length():
		return rich_runs
	var src := _spec_source()
	return [{
		"length": text.length(),
		"color": font_color(),
		"bold": int(src.get_meta("font_weight", 400)) >= 700,
		"italic": bool(src.get_meta("font_italic", false)),
		"underline": false,
	}]

## Índice del run (en `runs`) que cubre la posición `idx` (0-based) de `text`.
func _run_index_for_char(runs: Array, idx: int) -> int:
	var acc := 0
	for i in runs.size():
		acc += int(runs[i].get("length", 0))
		if idx < acc:
			return i
	return maxi(0, runs.size() - 1)

# ------------------------------------------------------------------ outline (cache)
func _get_outline() -> Node2D:
	if horizontal_alignment != _last_h_align or vertical_alignment != _last_v_align:
		_last_h_align = horizontal_alignment
		_last_v_align = vertical_alignment
		_outline_dirty = true
	if not _outline_dirty and is_instance_valid(_cached_outline):
		return _cached_outline
	_outline_dirty = false
	if _cached_outline != null:
		_cached_outline.queue_free()
		_cached_outline = null
	_cached_outline = _build_outline_at(VECTOR_FONT)
	_cached_polys = []
	_cached_underlines = []
	_polys_baked = false
	return _cached_outline

func _get_triangle_polys() -> Array:
	# Bake una sola vez: si la triangulación de un glifo da vacío NO se debe
	# reintentar cada frame (era el 2º origen del cuello de botella a zoom alto).
	if _polys_baked:
		return _cached_polys
	var outline := _get_outline()
	if outline == null:
		return _cached_polys
	_cached_polys = _triangulate_by_glyph(outline)
	_cached_underlines = _build_underlines(outline)
	_polys_baked = true
	return _cached_polys

## Triangula CADA GLIFO por separado (antes: un único "outer+holes" global
## para TODO el label, que solo dejaba visible el glifo con el contorno más
## grande y descartaba el resto — roto para cualquier texto de 2+ letras con
## algún hueco tipo O/A/B/8 de por medio). Cada entrada queda etiquetada con
## el run al que pertenece su glifo, para colorear por rango en _draw().
func _triangulate_by_glyph(outline: Node2D) -> Array:
	var out: Array = []
	for glyph_node in outline.get_children():
		if not (glyph_node is Node2D):
			continue
		var contours := _outline_polygons(glyph_node)
		if contours.is_empty():
			continue
		var run_idx := int(glyph_node.get_meta("run_index", 0))
		for poly in _triangulate_contours(contours):
			out.append({"poly": poly, "run": run_idx})
	return out

## Agrupa glifos consecutivos (mismo run + misma línea) en segmentos de
## subrayado. Aproximación tipográfica razonable (no lee métricas exactas de
## la fuente): grosor y desplazamiento proporcionales al tamaño de fuente.
func _build_underlines(outline: Node2D) -> Array:
	var runs := _effective_runs()
	var segs: Array = []
	# Estado del segmento en curso. OJO: nunca envolver el "flush" en un
	# lambda que lea estas variables — en GDScript un lambda captura las
	# locales POR VALOR (una copia congelada al crear el lambda), así que
	# nunca vería las actualizaciones del bucle. Se hace en línea, dos veces.
	var cur_run := -1
	var cur_line := 0.0
	var cur_x0 := 0.0
	var cur_x1 := 0.0
	var has_pending := false

	for glyph_node in outline.get_children():
		if not (glyph_node is Node2D):
			continue
		var run_idx := int(glyph_node.get_meta("run_index", 0))
		var line_y := float(glyph_node.get_meta("baseline_y", 0.0))
		var x0 := float(glyph_node.get_meta("x0", 0.0))
		var x1 := float(glyph_node.get_meta("x1", x0))
		if has_pending and run_idx == cur_run and is_equal_approx(line_y, cur_line):
			cur_x1 = x1
			continue
		if has_pending and cur_run >= 0 and cur_run < runs.size() and bool(runs[cur_run].get("underline", false)):
			var thickness: float = maxf(1.0, VECTOR_FONT * 0.05)
			var y: float = cur_line + VECTOR_FONT * 0.12
			segs.append({
				"rect": Rect2(cur_x0, y, cur_x1 - cur_x0, thickness),
				"color": runs[cur_run].get("color", Color.BLACK),
			})
		cur_run = run_idx
		cur_line = line_y
		cur_x0 = x0
		cur_x1 = x1
		has_pending = true
	if has_pending and cur_run >= 0 and cur_run < runs.size() and bool(runs[cur_run].get("underline", false)):
		var thickness: float = maxf(1.0, VECTOR_FONT * 0.05)
		var y: float = cur_line + VECTOR_FONT * 0.12
		segs.append({
			"rect": Rect2(cur_x0, y, cur_x1 - cur_x0, thickness),
			"color": runs[cur_run].get("color", Color.BLACK),
		})
	return segs

## Triangula los contornos de UN SOLO glifo con la regla par-impar, pero SIN
## asumir que todo el glifo es "un exterior con huecos": glifos con partes
## separadas (i, j, %, =, :) tienen VARIOS exteriores disjuntos dentro del
## mismo glifo. Para cada contorno se busca el contenedor más pequeño que lo
## envuelve (si alguno); sin contenedor = es un exterior propio, con
## contenedor = es un hueco de ESE exterior (soporta huecos múltiples, p.ej.
## la "8", y anidado simple).
func _triangulate_contours(contours: Array) -> Array:
	var polys: Array[PackedVector2Array] = []
	var n := contours.size()
	if n == 0:
		return polys
	var areas: Array = []
	for c in contours:
		areas.append(_abs_area(c))
	var parent: Array = []
	for i in n:
		var best_j := -1
		var best_area := INF
		for j in n:
			if i == j or areas[j] <= areas[i]:
				continue
			var cj: PackedVector2Array = contours[j]
			if Geometry2D.is_point_in_polygon(contours[i][0], cj) and areas[j] < best_area:
				best_area = areas[j]
				best_j = j
		parent.append(best_j)
	var holes_of: Dictionary = {}
	for i in n:
		if parent[i] != -1:
			if not holes_of.has(parent[i]):
				holes_of[parent[i]] = []
			holes_of[parent[i]].append(i)
	for i in n:
		if parent[i] != -1:
			continue
		var outer: PackedVector2Array = contours[i]
		if _signed_area(outer) < 0.0:
			outer = _reversed(outer)
		var holes: Array[PackedVector2Array] = []
		for hidx in holes_of.get(i, []):
			var h: PackedVector2Array = contours[hidx]
			if _signed_area(h) > 0.0:
				h = _reversed(h)
			holes.append(h)
		if holes.is_empty():
			if outer.size() >= 3 and Geometry2D.triangulate_polygon(outer).size() > 0:
				polys.append(outer)
			continue
		var combined := PackedVector2Array(outer)
		for hole in holes:
			combined = _attach_hole(combined, hole)
		if combined.size() >= 3 and Geometry2D.triangulate_polygon(combined).size() > 0:
			polys.append(combined)
	return polys

func _outline_polygons(outline: Node2D) -> Array[PackedVector2Array]:
	var res: Array[PackedVector2Array] = []
	for child in outline.get_children():
		if child is Path2D and child.curve:
			var curve: Curve2D = (child as Path2D).curve
			curve.bake_interval = 2.0
			var pts: PackedVector2Array = curve.get_baked_points()
			var clean := PackedVector2Array()
			for p in pts:
				if clean.is_empty() or clean[-1].distance_to(p) > 0.05:
					clean.append(p)
			if clean.size() > 1 and clean[0].distance_to(clean[-1]) < 0.05:
				clean.remove_at(clean.size() - 1)
			if clean.size() >= 3:
				res.append(clean)
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
## `grouped=false`: contorno PLANO — Path2D como hijos DIRECTOS (el contrato
## público de esta función, para exportar/editar el texto como trazados
## sueltos). El overlay interno (_get_outline) usa `grouped=true`: un
## Node2D "Glyph_N" por glifo, con meta run_index/baseline_y/x0/x1, para
## poder colorear/subrayar por rango — ver _triangulate_by_glyph.
func build_outline_path() -> Node2D:
	return _build_outline_at(maxi(1, get_theme_font_size("font_size")), false)

func _build_outline_at(fs_use: int, grouped: bool = true) -> Node2D:
	var ts := _get_ts()
	var base_bytes := _outline_font_bytes()
	var font := get_theme_font("font")
	if base_bytes.is_empty() or not font:
		return null
	var container := Node2D.new()
	container.name = "TextOutline_%s" % name
	var fs: int = maxi(1, fs_use)
	var runs := _effective_runs()

	var ws := Vector2.ZERO
	if has_meta(WORLD_SIZE_META):
		ws = get_meta(WORLD_SIZE_META)
	elif _world_size != Vector2.ZERO:
		ws = _world_size
	else:
		var p := get_parent()
		if p and p.has_meta("width") and p.has_meta("height"):
			ws = Vector2(float(p.get_meta("width")), float(p.get_meta("height")))

	var font_scale := float(fs) / float(maxi(1, base_font_size))
	var box_w := ws.x * font_scale if ws.x > 0.0 else size.x
	var box_h := ws.y * font_scale if ws.y > 0.0 else size.y

	var wrap_limit := 0.0
	if autowrap_mode != TextServer.AUTOWRAP_OFF and box_w > 0.0:
		wrap_limit = box_w
	var lines := _wrap_lines(font, fs, wrap_limit)

	# RID por combinación de estilo (regular/negrita/cursiva), creados bajo
	# demanda y liberados todos al terminar — evita crear 1 RID por glifo.
	var rid_cache: Dictionary = {}

	var prop := get_effective_letter_proportions()
	var has_prop := not prop.is_empty() and prop.has("mode") and String(prop.get("mode", "")) != ""
	var prop_mode := String(prop.get("mode", ""))
	var s_start := float(prop.get("start", 1.0))
	var s_mid := float(prop.get("mid", 1.0))
	var s_mid2 := float(prop.get("mid2", s_mid))
	var s_end := float(prop.get("end", 1.0))
	var total_chars := maxi(1, text.length())
	var ls: float = float(_spec_source().get_meta("letter_spacing", 0)) * font_scale

	var line_height: float = font.get_height(fs)
	var ls_extra: float = float(get_theme_constant("line_spacing")) * font_scale
	var advance_y: float = line_height + ls_extra
	var total_text_h: float = float(lines.size()) * line_height + maxf(0.0, float(lines.size() - 1)) * ls_extra
	var base_ascent: float = font.get_ascent(fs)
	var y_offset: float = base_ascent
	if box_h > total_text_h:
		match vertical_alignment:
			VERTICAL_ALIGNMENT_CENTER:
				y_offset = base_ascent + (box_h - total_text_h) * 0.5
			VERTICAL_ALIGNMENT_BOTTOM:
				y_offset = base_ascent + (box_h - total_text_h)
			_:
				y_offset = base_ascent

	for line in lines:
		var line_text: String = line["text"]
		var line_start: int = line["start"]
		var line_w := 0.0
		if has_prop:
			var rid_measure: RID = _get_rid_for_style(ts, base_bytes, rid_cache, false, false)
			for j in line_text.length():
				var c_idx := line_start + j
				var t_j := float(c_idx) / maxf(1.0, float(total_chars - 1))
				var s_j := _calculate_glyph_scale(prop_mode, t_j, s_start, s_mid, s_mid2, s_end)
				var c_fs := maxi(2, int(round(fs * s_j)))
				var cp := line_text.unicode_at(j)
				var gl := ts.font_get_glyph_index(rid_measure, c_fs, cp, 0)
				var ad := ts.font_get_glyph_advance(rid_measure, c_fs, gl).x
				line_w += (ad if ad > 0.0 else font.get_char_size(cp, c_fs).x) + ls
		else:
			line_w = font.get_string_size(line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + (float(line_text.length()) * ls)
		var cx := 0.0
		if box_w > line_w:
			match horizontal_alignment:
				HORIZONTAL_ALIGNMENT_CENTER:
					cx = (box_w - line_w) * 0.5
				HORIZONTAL_ALIGNMENT_RIGHT:
					cx = box_w - line_w
				_:
					cx = 0.0
		for i in line_text.length():
			var char_idx := line_start + i
			var char_fs := fs
			if has_prop:
				var t := float(char_idx) / maxf(1.0, float(total_chars - 1))
				var s_factor := _calculate_glyph_scale(prop_mode, t, s_start, s_mid, s_mid2, s_end)
				char_fs = maxi(2, int(round(fs * s_factor)))
			var run_idx := _run_index_for_char(runs, char_idx)
			var run: Dictionary = runs[run_idx] if run_idx < runs.size() else runs[0]
			var rid: RID = _get_rid_for_style(ts, base_bytes, rid_cache, bool(run.get("bold", false)), bool(run.get("italic", false)))
			var codepoint: int = line_text.unicode_at(i)
			var glyph: int = ts.font_get_glyph_index(rid, char_fs, codepoint, 0)
			var adv: float = ts.font_get_glyph_advance(rid, char_fs, glyph).x
			var char_adv := (adv if adv > 0.0 else font.get_char_size(codepoint, char_fs).x) + ls
			if glyph <= 0:
				cx += char_adv
				continue
			var next_cx: float = cx + char_adv
			if grouped:
				var glyph_group := Node2D.new()
				glyph_group.name = "Glyph_%d" % container.get_child_count()
				glyph_group.set_meta("run_index", run_idx)
				glyph_group.set_meta("baseline_y", y_offset)
				glyph_group.set_meta("x0", cx)
				glyph_group.set_meta("x1", next_cx)
				_append_glyph_path(ts, rid, char_fs, glyph, glyph_group, cx, y_offset)
				if glyph_group.get_child_count() > 0:
					container.add_child(glyph_group)
				else:
					glyph_group.free()  # nunca entró al árbol: huérfano si no se libera a mano
			else:
				_append_glyph_path(ts, rid, char_fs, glyph, container, cx, y_offset)
			cx = next_cx
		y_offset += advance_y

	for rid in rid_cache.values():
		ts.free_rid(rid)
	if container.get_child_count() == 0:
		container.queue_free()
		return null
	return container

static func _get_ts() -> TextServer:
	if _ts == null:
		_ts = TextServerManager.get_primary_interface()
	return _ts

## Bytes de la fuente actual (los da FontCore, según la spec de metas de esta
## instancia). Cacheados por instancia para no releer el archivo por glifo.
var _outline_bytes_cache: PackedByteArray = PackedByteArray()
func _outline_font_bytes() -> PackedByteArray:
	if not _outline_bytes_cache.is_empty():
		return _outline_bytes_cache
	var fc = _font_core()
	if fc and fc.has_method("font_bytes"):
		_outline_bytes_cache = fc.font_bytes(fc.spec_from_node(_spec_source()))
	if _outline_bytes_cache.is_empty():
		_outline_bytes_cache = FileAccess.get_file_as_bytes(FONT_PATH)
	return _outline_bytes_cache

## RID de TextServer para una combinación (negrita, cursiva) dada, creado y
## configurado (font_set_embolden / font_set_transform) la primera vez que se
## pide, cacheado en `cache` para el resto de glifos de esta misma tanda de
## build. El llamador libera TODOS los RID de `cache` al terminar.
func _get_rid_for_style(ts, base_bytes: PackedByteArray, cache: Dictionary, bold: bool, italic: bool) -> RID:
	var key := "%d_%d" % [1 if bold else 0, 1 if italic else 0]
	if cache.has(key):
		return cache[key]
	var r: RID = ts.create_font()
	if r.is_valid():
		ts.font_set_data(r, base_bytes)
		if bold and ts.has_method("font_set_embolden"):
			ts.font_set_embolden(r, BOLD_EMBOLDEN)
		if italic and ts.has_method("font_set_transform"):
			# Cizalla sintética: el tope de cada glifo se inclina hacia la
			# derecha (convención habitual de cursiva sintética/oblique).
			ts.font_set_transform(r, Transform2D(Vector2(1, 0), Vector2(-ITALIC_SHEAR, 1), Vector2.ZERO))
	cache[key] = r
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
	var n := arc.size()
	if n < 2:
		return null

	# Expandir puntos on-curve implícitos entre puntos off-curve consecutivos (especificación TrueType)
	var exp_pts: Array[Vector2] = []
	var exp_tags: Array[int] = []

	for j in n:
		var curr := Vector2(arc[j].x + ox, arc[j].y + oy)
		var ctag := int(arc[j].z)
		exp_pts.append(curr)
		exp_tags.append(ctag)
		var nxt := Vector2(arc[(j + 1) % n].x + ox, arc[(j + 1) % n].y + oy)
		var ntag := int(arc[(j + 1) % n].z)
		if ctag == 0 and ntag == 0:
			exp_pts.append((curr + nxt) * 0.5)
			exp_tags.append(1)

	var total := exp_pts.size()
	var first_on := 0
	for j in total:
		if exp_tags[j] == 1:
			first_on = j
			break

	var pts: Array[Vector2] = []
	var tags: Array[int] = []
	for j in total:
		var idx := (first_on + j) % total
		pts.append(exp_pts[idx])
		tags.append(exp_tags[idx])

	var curve := Curve2D.new()
	var add_cubic := func(p0: Vector2, cp1: Vector2, cp2: Vector2, p1: Vector2) -> void:
		var i0 := curve.point_count
		if i0 == 0:
			curve.add_point(p0, Vector2.ZERO, cp1 - p0)
		else:
			curve.set_point_out(i0 - 1, cp1 - p0)
		curve.add_point(p1, cp2 - p1, Vector2.ZERO)

	var add_line := func(p0: Vector2, p1: Vector2) -> void:
		var i0 := curve.point_count
		if i0 == 0:
			curve.add_point(p0, Vector2.ZERO, Vector2.ZERO)
		curve.add_point(p1, Vector2.ZERO, Vector2.ZERO)

	var prev_on := pts[0]
	var i := 1
	while i < total:
		var tag := tags[i]
		if tag == 1:
			add_line.call(prev_on, pts[i])
			prev_on = pts[i]
			i += 1
		elif tag == 0:
			var cp := pts[i]
			var p1 := pts[(i + 1) % total]
			var cp1 := prev_on + (cp - prev_on) * (2.0 / 3.0)
			var cp2 := p1 + (cp - p1) * (2.0 / 3.0)
			add_cubic.call(prev_on, cp1, cp2, p1)
			prev_on = p1
			i += 2
		elif tag == 2:
			var cp1 := pts[i]
			var cp2 := pts[(i + 1) % total]
			var p1 := pts[(i + 2) % total]
			add_cubic.call(prev_on, cp1, cp2, p1)
			prev_on = p1
			i += 3

	# Cerrar el contorno de vuelta al inicio
	var start_pt := pts[0]
	if curve.point_count > 0:
		var last_p := curve.get_point_position(curve.point_count - 1)
		if last_p.distance_to(start_pt) > 0.01:
			add_line.call(prev_on, start_pt)

	return curve

## Devuelve Array[{"text":String, "start":int}] — `start` = índice del primer
## carácter de esa línea en el `text` ORIGINAL (sin re-envolver), para poder
## mapear cada carácter a su run de formato aunque el autowrap reparta las
## palabras en líneas distintas a las del texto tal cual se escribió.
func _wrap_lines(font: Font, fs: int, wrap_w: float) -> Array:
	var out: Array = []
	var raw_lines: PackedStringArray = text.replace("\r\n", "\n").split("\n")
	var raw_start := 0
	for r in raw_lines:
		if wrap_w <= 0.0 or not font:
			out.append({"text": r, "start": raw_start})
		else:
			var words: PackedStringArray = r.split(" ", true)
			var current := ""
			var current_start := raw_start
			var cursor := raw_start
			for word in words:
				var probe := current + (" " if current.length() > 0 else "") + word
				var w: float = font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				if w <= wrap_w or current.length() == 0:
					current = probe
				else:
					out.append({"text": current, "start": current_start})
					current_start = cursor
					current = word
				cursor += word.length() + 1
			out.append({"text": current, "start": current_start})
		raw_start += r.length() + 1
	return out
