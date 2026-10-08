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

## Alias para compatibilidad con código/herramientas que acceden a font_size directamente
var font_size: int:
	get:
		return base_font_size
	set(v):
		base_font_size = v
		add_theme_font_size_override("font_size", v)
		_last_eff = -1
		_outline_dirty = true
		_polys_baked = false
		_layout_cache_key = ""
		if is_inside_tree():
			_refresh_local_rect()
		queue_redraw()

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
const BOLD_EMBOLDEN := 0.3
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
var _cached_strokes: Array = []      # Array[{"contours": Array[PackedVector2Array], "run": int}]
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
	_cached_strokes = []
	_cached_polys = []
	_cached_underlines = []
	_layout_cache_key = ""
	_sync_visibility()
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

## Sangrías estilo Publisher (unidades de mundo, como width/height):
## indent_left/right en todas las líneas, indent_first solo en la primera
## de cada párrafo (negativa = francesa/hanging). Como el Label nativo no
## sabe sangrar la primera línea, el texto sangrado se renderiza SOLO por
## el overlay vectorial (mismo precedente que letter_proportions).
func indent_world() -> Vector3:
	return Vector3(
		float(_text_meta("indent_left", 0.0)),
		float(_text_meta("indent_right", 0.0)),
		float(_text_meta("indent_first", 0.0))
	)

## Meta de párrafo: del label o, si no, del contenedor. _spec_source() solo
## mira el contenedor cuando este tiene metas de FUENTE, así que en un
## párrafo sin familia propia se ignoraban la interletra y las sangrías.
func _text_meta(key: String, def: Variant) -> Variant:
	if has_meta(key):
		return get_meta(key)
	var p := get_parent()
	if p and p.has_meta(key):
		return p.get_meta(key)
	return def

func has_indents() -> bool:
	var iw := indent_world()
	return absf(iw.x) > 0.001 or absf(iw.y) > 0.001 or absf(iw.z) > 0.001

## Relee las metas de sangría y re-bakea (lo llama InspectorCore).
func apply_indent_meta() -> void:
	invalidate_layout()

## Relee las metas de trazo/borde y re-bakea (lo llama InspectorCore).
func apply_stroke_meta() -> void:
	invalidate_layout()

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
## Cambio EXPLÍCITO del usuario (no tick de zoom): salta el throttle de
## raster, invalida el overlay vectorial y repinta en este mismo frame.
## Sin esto, pasos <4% se tragaba el throttle y el overlay quedaba con la
## medida vieja (texto que "no cambia" + parpadeo/desdoble a zoom alto).
var world_font_size: int = 0:
	set(v):
		if v != world_font_size and v > 0:
			world_font_size = v
			base_font_size = v
			_last_eff = -1
			_outline_dirty = true
			_polys_baked = false
			_layout_cache_key = ""
			if is_inside_tree():
				_apply_zoom(_canvas_zoom())
				_refresh_local_rect()
			queue_redraw()

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
	_restore_style_from_container()
	# CULLING GLOBAL: el CullManager barre el grupo "world_content" una vez
	# cada 2 frames y apaga visible/process de lo no visible.
	add_to_group("world_content")
	# LOD sub-pixel: a zoom muy alejado el texto es ilegible; el CullManager
	# apaga los labels de este grupo cuando su huella en pantalla < min_screen_px
	# (aleja el zoom con 10.000 textos y sigue a 60 FPS).
	add_to_group("cull_subpixel")

## letter_proportions / rich_runs are runtime-only vars, so Node.duplicate()
## (copy, paste, Ctrl+D, Alt+drag) dropped them and the copy looked different.
## The text container keeps both as metas; rebuild them from there.
func _restore_style_from_container() -> void:
	var p := get_parent()
	if p == null:
		return
	if letter_proportions.is_empty() and p.has_meta("letter_proportions"):
		var lp = p.get_meta("letter_proportions")
		if lp is Dictionary and not lp.is_empty() and String(lp.get("mode", "")) != "":
			set_letter_proportions((lp as Dictionary).duplicate(true))
	if rich_runs.is_empty() and p.has_meta("runs"):
		var runs = p.get_meta("runs")
		if runs is Array and not runs.is_empty():
			set_rich_runs((runs as Array).duplicate(true))

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
	# spacing_glyph va en px ABSOLUTOS del tamaño rasterizado: se re-escala en
	# cada cambio de tamaño efectivo (_update_tracking_spacing) para que en
	# el mundo mida siempre letter_spacing, a cualquier zoom.
	_tracking_fv = null
	if absf(letter_spacing_world()) > 0.0001 and _font:
		_tracking_fv = FontVariation.new()
		_tracking_fv.base_font = _font
		_font = _tracking_fv
		_update_tracking_spacing(get_theme_font_size("font_size") if _last_eff < 0 else _last_eff)
	if _font == null:
		if _fallback_font == null:
			var fb = load(FONT_PATH)
			if fb is FontFile:
				fb.multichannel_signed_distance_field = true
				fb.msdf_pixel_range = 16
				fb.msdf_size = 64
				fb.antialiasing = TextServer.FONT_ANTIALIASING_LCD
				fb.generate_mipmaps = true
			_fallback_font = fb as Font
		_font = _fallback_font
	if _font:
		add_theme_font_override("font", _font)

## FontVariation de tracking de esta instancia (null sin interletra).
var _tracking_fv: FontVariation = null

## Interletra en unidades de mundo (admite fracciones).
func letter_spacing_world() -> float:
	return float(_text_meta("letter_spacing", 0.0))

## Ajusta el spacing del bitmap al tamaño rasterizado `fs_raster`.
func _update_tracking_spacing(fs_raster: int) -> void:
	if _tracking_fv == null:
		return
	var px := int(round(letter_spacing_world() * float(maxi(1, fs_raster)) / float(maxi(1, base_font_size))))
	if _tracking_fv.spacing_glyph != px:
		_tracking_fv.spacing_glyph = px
		_tracking_fv.spacing_space = px

## Fuente sin la variación de tracking: para medir a cualquier tamaño se usa
## esta + tracking escalado a mano (la variación trae px de OTRO tamaño).
func _untracked_font() -> Font:
	var f := get_theme_font("font")
	if _tracking_fv != null and f == _tracking_fv:
		return _tracking_fv.base_font
	return f

## Ancho de `s` a tamaño `fs`, con el tracking escalado a `fs`.
func _measure(s: String, fs: int) -> float:
	var f := _untracked_font()
	if f == null:
		return 0.0
	var ls := letter_spacing_world() * float(fs) / float(maxi(1, base_font_size))
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + float(s.length()) * ls

## Como _measure, pero respetando el tamaño propio de cada run (`abs_start`
## = índice de `s` en `text`): sin esto el wrap medía todo a tamaño base y
## los tramos grandes desbordaban el marco.
func _measure_span(abs_start: int, s: String, fs: int) -> float:
	if not has_sized_runs():
		return _measure(s, fs)
	var f := _untracked_font()
	if f == null:
		return 0.0
	var runs := _effective_runs()
	var ls := letter_spacing_world() * float(fs) / float(maxi(1, base_font_size))
	var w := float(s.length()) * ls
	var i := 0
	while i < s.length():
		var ri := _run_index_for_char(runs, abs_start + i)
		var run_end := 0
		for k in ri + 1:
			run_end += int(runs[k].get("length", 0))
		var seg_len := clampi(run_end - (abs_start + i), 1, s.length() - i)
		var cfs := _sized_char_fs(runs, abs_start + i, fs)
		w += f.get_string_size(s.substr(i, seg_len), HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		i += seg_len
	return w

## Tamaño de fuente que manda en una línea (el mayor de sus runs): la altura
## de línea crece con el tramo más grande en vez de solaparse.
func _line_fs(line: Dictionary, fs: int) -> int:
	if not has_sized_runs():
		return fs
	var runs := _effective_runs()
	var start := int(line.get("start", 0))
	var mx := fs if String(line.get("text", "")).is_empty() else 0
	for i in String(line.get("text", "")).length():
		mx = maxi(mx, _sized_char_fs(runs, start + i, fs))
	return maxi(mx, 1)

## Invalida layout + overlay vectorial y re-bakea (interlineado, sangrías,
## trazo… cualquier meta que cambie la geometría del texto).
func invalidate_layout() -> void:
	_outline_dirty = true
	_polys_baked = false
	_cached_strokes = []
	_cached_polys = []
	_cached_underlines = []
	_layout_cache_key = ""
	_sync_visibility()
	_apply_zoom(_canvas_zoom())
	_refresh_local_rect()
	queue_redraw()

## Llamado por InspectorCore / el panel de texto cuando cambia la familia.
func apply_font_from_meta() -> void:
	# Los contornos del overlay vectorial salen de estos bytes: sin vaciarlos,
	# a zoom alto (o con runs/trazo/sangría) seguía la familia ANTERIOR.
	_outline_bytes_cache = PackedByteArray()
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
	_cached_strokes = []
	_cached_polys = []
	_cached_underlines = []
	_layout_cache_key = ""
	_sync_visibility()
	_apply_zoom(_canvas_zoom())
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

## Mientras no cambie el zoom, re-fija el layout si el texto o la alineación cambiaron.
func _sync_layout_if_content_changed() -> void:
	if text == _last_text and horizontal_alignment == _last_h_align and vertical_alignment == _last_v_align:
		return
	_last_text = text
	_last_h_align = horizontal_alignment
	_last_v_align = vertical_alignment
	_outline_dirty = true
	_polys_baked = false
	_cached_strokes = []
	_cached_polys = []
	_cached_underlines = []
	_sync_visibility()
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
	if z >= ZOOM_VECTOR_MIN or is_vector_override_active():
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
	_update_tracking_spacing(eff)
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

## Mínimo del contenido en unidades de mundo (medición directa sin depender
## de si el Label está visible o en el árbol, compatible con runs y autowrap).
func get_world_minimum_size(custom_text: String = "") -> Vector2:
	var body := custom_text if custom_text != "" else text
	if body.is_empty():
		var fs_empty := maxi(1, base_font_size)
		var f_empty := get_theme_font("font")
		var h_empty := float(f_empty.get_height(fs_empty)) if f_empty else float(fs_empty)
		return Vector2(20.0, maxf(24.0, h_empty))

	var font := get_theme_font("font")
	var fs_base := maxi(1, base_font_size)

	# 1. Si es autowrap (Párrafo envuelto en marco rectangular)
	if autowrap_mode != TextServer.AUTOWRAP_OFF:
		var fw := 0.0
		if has_meta(WORLD_SIZE_META):
			fw = (get_meta(WORLD_SIZE_META) as Vector2).x
		elif _world_size != Vector2.ZERO:
			fw = _world_size.x
		else:
			var p := get_parent()
			if p and p.has_meta("width"):
				fw = float(p.get_meta("width"))
		var wh := wrapped_content_height(body)
		return Vector2(maxf(20.0, fw), maxf(24.0, wh))

	# 2. Si es texto de línea única / título (sin autowrap)
	if font == null:
		return Vector2(float(body.length()) * float(fs_base) * 0.65, float(fs_base) * 1.25)

	var eff_runs: Array = _effective_runs()
	var has_custom_sizes := false
	for r in eff_runs:
		if r is Dictionary and r.has("size") and not is_equal_approx(float(r["size"]), float(fs_base)):
			has_custom_sizes = true
			break

	if not has_custom_sizes:
		var sz := font.get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_base)
		var h := maxf(sz.y, float(font.get_height(fs_base)))
		return Vector2(sz.x, h)

	# Medir por segmentos de runs si tienen tamaños de fuente diferentes
	var total_w := 0.0
	var max_h := float(font.get_height(fs_base))
	var pos := 0
	for r in eff_runs:
		if not (r is Dictionary):
			continue
		var r_len: int = int(r.get("length", 0))
		if pos >= body.length():
			break
		var actual_len: int = mini(r_len, body.length() - pos)
		if actual_len <= 0:
			continue
		var slice: String = body.substr(pos, actual_len)
		var r_fs: int = int(round(float(r.get("size", fs_base))))
		r_fs = maxi(1, r_fs)
		var sz := font.get_string_size(slice, HORIZONTAL_ALIGNMENT_LEFT, -1, r_fs)
		total_w += sz.x
		max_h = maxf(max_h, float(font.get_height(r_fs)))
		pos += actual_len

	if pos < body.length():
		var rest := body.substr(pos)
		var sz := font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_base)
		total_w += sz.x
		max_h = maxf(max_h, float(font.get_height(fs_base)))

	return Vector2(maxf(total_w, 20.0), maxf(max_h, 24.0))

# ------------------------------------------------------------------ drawing
func _draw() -> void:
	# El bitmap del Label siempre visible por debajo (garantía), salvo si el régimen vectorial está activo
	if _last_zoom < ZOOM_VECTOR_MIN and not is_vector_override_active():
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

	var runs := _effective_runs()

	# 1. Dibujar trazo (stroke) detrás del relleno para mantener legibilidad perfecta de la fuente
	if has_stroke():
		var base_scale := float(VECTOR_FONT) / float(maxi(1, base_font_size))
		var def_sw := stroke_width() * base_scale
		var def_sc := stroke_color()
		for s in _get_stroke_polys():
			var run_idx: int = s.get("run", 0)
			var sw := def_sw
			var sc := def_sc
			if run_idx >= 0 and run_idx < runs.size():
				var r: Dictionary = runs[run_idx]
				if r.has("stroke_width"):
					sw = float(r["stroke_width"]) * base_scale
				if r.has("stroke_color"):
					sc = r["stroke_color"]
			if sw > 0.001 and sc.a > 0.001:
				for contour in s.get("contours", []):
					var ring: PackedVector2Array = contour
					if ring.size() >= 2:
						if not ring[0].is_equal_approx(ring[-1]):
							ring = PackedVector2Array(ring)
							ring.append(ring[0])
						draw_polyline(ring, sc, sw, true)

	# 2. Dibujar relleno con color por run
	var entries := _get_triangle_polys()
	if not entries.is_empty():
		var default_col := font_color()
		for e in entries:
			var run_idx: int = e.get("run", 0)
			var col: Color = default_col
			if run_idx >= 0 and run_idx < runs.size():
				col = runs[run_idx].get("color", default_col)
			draw_colored_polygon(e["poly"], col)

	# 3. Dibujar subrayados
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

func font_weight() -> int:
	var src := _spec_source()
	if src and src.has_meta(META_WEIGHT):
		return int(src.get_meta(META_WEIGHT))
	return 400

func font_italic() -> bool:
	var src := _spec_source()
	if src and src.has_meta(META_ITALIC):
		return bool(src.get_meta(META_ITALIC))
	return false

func stroke_width() -> float:
	var src := _spec_source()
	if src:
		if src.has_meta("stroke_width"):
			return maxf(0.0, float(src.get_meta("stroke_width")))
		if src.has_meta("text_outline"):
			return maxf(0.0, float(src.get_meta("text_outline")))
	if has_theme_constant_override("outline_size"):
		return maxf(0.0, float(get_theme_constant("outline_size")))
	return 0.0

func stroke_color() -> Color:
	var src := _spec_source()
	if src:
		if src.has_meta("stroke_color"):
			return src.get_meta("stroke_color")
		if src.has_meta("text_outline_color"):
			return src.get_meta("text_outline_color")
	if has_theme_color_override("font_outline_color"):
		return get_theme_color("font_outline_color")
	return Color.BLACK

func has_stroke() -> bool:
	if stroke_width() > 0.001:
		return true
	for r in _effective_runs():
		if float(r.get("stroke_width", 0.0)) > 0.001:
			return true
	return false

func has_rich_runs() -> bool:
	var runs := _effective_runs()
	if runs.size() > 1:
		return true
	if runs.size() == 1:
		var r: Dictionary = runs[0]
		if r.has("color") and not (r["color"] as Color).is_equal_approx(font_color()):
			return true
		if float(r.get("stroke_width", 0.0)) > 0.001:
			return true
		if float(r.get("size", 0.0)) > 0.0 and int(round(r.get("size", 0.0))) != base_font_size:
			return true
		if bool(r.get("bold", false)) != (font_weight() >= 700):
			return true
		if bool(r.get("italic", false)) != font_italic():
			return true
		if bool(r.get("underline", false)):
			return true
	return false

func is_vector_override_active() -> bool:
	return has_letter_proportions() or has_indents() or has_sized_runs() or has_rich_runs() or has_stroke()

func _sync_visibility() -> void:
	if is_vector_override_active():
		visible_ratio = 0.0
	else:
		visible_ratio = 1.0

# ------------------------------------------------------------------ rich runs
## Motor de runs COMPARTIDO (BBCode avanzado): lo usan TextTool, el panel de
## párrafo e InspectorCore para no triplicar la lógica de rangos.
static func runs_of(shape: Node2D, text_len: int) -> Array:
	var runs: Array = shape.get_meta("runs", [])
	var total := 0
	for r in runs:
		total += int(r.get("length", 0))
	if not runs.is_empty() and total == text_len:
		return runs
	var def_sw: float = float(shape.get_meta("stroke_width", shape.get_meta("text_outline", 0.0)))
	var def_sc: Color = shape.get_meta("stroke_color", shape.get_meta("text_outline_color", Color.BLACK))
	return [{
		"length": text_len,
		"color": shape.get_meta("text_color", Color.BLACK),
		"stroke_color": def_sc,
		"stroke_width": def_sw,
		"bold": int(shape.get_meta("font_weight", 400)) >= 700,
		"italic": bool(shape.get_meta("font_italic", false)),
		"underline": false,
	}]

static func split_runs(runs: Array, cuts: Array) -> Array:
	var out: Array = []
	var pos := 0
	for r in runs:
		var len_: int = int(r.get("length", 0))
		var pts: Array = [pos, pos + len_]
		for c in cuts:
			if c > pos and c < pos + len_:
				pts.append(c)
		pts.sort()
		for i in range(pts.size() - 1):
			if int(pts[i + 1]) > int(pts[i]):
				var nr: Dictionary = (r as Dictionary).duplicate()
				nr["length"] = int(pts[i + 1]) - int(pts[i])
				out.append(nr)
		pos += len_
	return out

static func merge_runs(runs: Array) -> Array:
	var out: Array = []
	for r in runs:
		if not out.is_empty():
			var last: Dictionary = out[out.size() - 1]
			var same_col: bool = (last.get("color", Color.BLACK) as Color).is_equal_approx(r.get("color", Color.BLACK))
			var same_sc: bool = (last.get("stroke_color", Color.BLACK) as Color).is_equal_approx(r.get("stroke_color", Color.BLACK))
			var same_sw: bool = is_equal_approx(float(last.get("stroke_width", 0.0)), float(r.get("stroke_width", 0.0)))
			if same_col and same_sc and same_sw \
					and bool(last.get("bold", false)) == bool(r.get("bold", false)) \
					and bool(last.get("italic", false)) == bool(r.get("italic", false)) \
					and bool(last.get("underline", false)) == bool(r.get("underline", false)) \
					and float(last.get("size", 0.0)) == float(r.get("size", 0.0)):
				last["length"] = int(last["length"]) + int(r.get("length", 0))
				continue
		out.append((r as Dictionary).duplicate())
	return out

## Garantiza el editor en línea del contenedor de texto (MultiLineEdit para
## párrafos, TitleEdit para títulos) y el autowrap del párrafo. Los textos
## cargados de un .vectopen / pegados solo traían el DisplayLabel: sin
## extensión VectorRichText, entrar a editar ocultaba el texto sin editor y
## al confirmar el párrafo quedaba como "Texto de párrafo vacío.".
static func ensure_inline_editor(shape: Node2D) -> TextEdit:
	if not is_instance_valid(shape):
		return null
	var is_para := String(shape.get_meta("shape_type", "")) == "text_paragraph"
	var dl := shape.get_node_or_null("DisplayLabel") as Label
	if is_para and dl and dl.autowrap_mode == TextServer.AUTOWRAP_OFF:
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ed_name := "MultiLineEdit" if is_para else "TitleEdit"
	var ed := shape.get_node_or_null(ed_name) as TextEdit
	if ed:
		return ed
	var sz := Vector2(float(shape.get_meta("width", 350.0 if is_para else 250.0)),
			float(shape.get_meta("height", 100.0 if is_para else 40.0)))
	var fs := int(shape.get_meta("font_size", 24))
	ed = TextEdit.new()
	ed.name = ed_name
	ed.visible = false
	ed.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY if is_para else TextEdit.LINE_WRAPPING_NONE
	ed.custom_minimum_size = sz
	ed.size = sz
	ed.text = str(shape.get_meta("text", ""))
	ed.add_theme_color_override("font_color", shape.get_meta("text_color", Color.BLACK))
	ed.add_theme_font_size_override("font_size", fs)
	shape.add_child(ed)
	return ed

## [shape, editor, start, end] del texto EN EDICIÓN con selección no vacía
## (título o párrafo). Vacío si no hay: el estilo va al bloque entero.
static func editing_range(tree: SceneTree) -> Array:
	if tree == null:
		return []
	var canvas = tree.get_first_node_in_group("_vectopen_canvas")
	if canvas == null or not ("current_tool" in canvas):
		return []
	var t = canvas.current_tool
	if t == null:
		return []
	var flag = t.get("is_editing") if t != null else null
	if flag == null or not bool(flag):
		return []
	var shape: Node2D = t.get("current_editing_shape")
	if not is_instance_valid(shape):
		return []
	var ed: TextEdit = shape.get_node_or_null("TitleEdit")
	if ed == null:
		ed = shape.get_node_or_null("MultiLineEdit")
	if ed == null or not ed.visible:
		return []
	var sel = sel_range(ed)
	if sel == null or int(sel["end"]) <= int(sel["start"]):
		return []
	return [shape, ed, int(sel["start"]), int(sel["end"])]

## Rango [start,end) de la selección del editor, en offsets planos. null sin selección.
static func sel_range(ed: TextEdit) -> Variant:
	if ed == null or not ed.has_selection():
		return null
	var a := _flat_off(ed, ed.get_selection_from_line(), ed.get_selection_from_column())
	var b := _flat_off(ed, ed.get_selection_to_line(), ed.get_selection_to_column())
	return {"start": mini(a, b), "end": maxi(a, b)}

static func _flat_off(ed: TextEdit, line: int, column: int) -> int:
	var off := 0
	for l in line:
		off += ed.get_line(l).length() + 1
	return off + column

## Aplica `mutator` al rango y lo guarda en el shape + refresca el label.
## Devuelve true si aplicó algo.
static func apply_range(shape: Node2D, label: Control, ed_text_len: int, start: int, end: int, mutator: Callable) -> bool:
	if not is_instance_valid(shape) or start >= end:
		return false
	var runs := split_runs(runs_of(shape, ed_text_len), [start, end])
	var out: Array = []
	var pos := 0
	for r in runs:
		var len_: int = int(r.get("length", 0))
		if pos >= start and pos < end:
			out.append(mutator.call((r as Dictionary).duplicate()))
		else:
			out.append(r)
		pos += len_
	out = merge_runs(out)
	shape.set_meta("runs", out)
	if label and label.has_method("set_rich_runs"):
		label.set_rich_runs(out)
	return true

## Reajusta `runs` a `new_len` (recorta/extiende por el final).
static func resize_runs(shape: Node2D, new_len: int) -> void:
	var runs: Array = shape.get_meta("runs", [])
	if runs.is_empty():
		return
	var total := 0
	for r in runs:
		total += int(r.get("length", 0))
	if total == new_len:
		return
	var out: Array = []
	var acc := 0
	for r in runs:
		var len_: int = int(r.get("length", 0))
		if acc >= new_len:
			break
		var take: int = mini(len_, new_len - acc)
		if take > 0:
			var nr: Dictionary = (r as Dictionary).duplicate()
			nr["length"] = take
			out.append(nr)
			acc += take
	if acc < new_len and not out.is_empty():
		out[out.size() - 1]["length"] = int(out[out.size() - 1]["length"]) + (new_len - acc)
	shape.set_meta("runs", out)

## Ajusta `runs` a una edición old_text → new_text SEGÚN LA POSICIÓN del
## cambio (prefijo/sufijo común): lo borrado sale de su run y lo insertado
## hereda el estilo del carácter anterior. resize_runs recortaba siempre por
## el final, así que escribir al principio desplazaba toda la negrita/color.
## Devuelve [] si `runs` no cubre exactamente old_text (el llamador decide).
static func edit_runs(runs: Array, old_text: String, new_text: String) -> Array:
	var total := 0
	for r in runs:
		total += int(r.get("length", 0))
	if runs.is_empty() or total != old_text.length():
		return []
	var ol := old_text.length()
	var nl := new_text.length()
	var p := 0
	while p < ol and p < nl and old_text.unicode_at(p) == new_text.unicode_at(p):
		p += 1
	var sfx := 0
	while sfx < ol - p and sfx < nl - p and old_text.unicode_at(ol - 1 - sfx) == new_text.unicode_at(nl - 1 - sfx):
		sfx += 1
	var del_end := ol - sfx
	var ins_len := nl - p - sfx
	# Estilo heredado: el del carácter anterior al cambio (o el primero).
	var acc := 0
	var style: Dictionary = runs[0]
	for r in runs:
		var l := int(r.get("length", 0))
		if l > 0 and (p == 0 or p - 1 < acc + l):
			style = r
			break
		acc += l
	var out: Array = []
	var pos := 0
	var inserted := false
	for r in split_runs(runs, [p, del_end]):
		var l := int(r.get("length", 0))
		if pos == p and not inserted and ins_len > 0:
			var nr: Dictionary = (style as Dictionary).duplicate()
			nr["length"] = ins_len
			out.append(nr)
			inserted = true
		if pos < p or pos >= del_end:
			out.append(r)
		pos += l
	if not inserted and ins_len > 0:
		var nr: Dictionary = (style as Dictionary).duplicate()
		nr["length"] = ins_len
		out.append(nr)
	return merge_runs(out)

## Aplica edit_runs a las metas del shape (con resize_runs de respaldo).
static func apply_text_edit(shape: Node2D, old_text: String, new_text: String) -> void:
	var runs: Array = shape.get_meta("runs", [])
	if runs.is_empty():
		return
	var out := edit_runs(runs, old_text, new_text)
	if out.is_empty() and not new_text.is_empty():
		resize_runs(shape, new_text.length())
	else:
		shape.set_meta("runs", out)

## Foto del estado editable de un texto (para undo de la edición de
## contenido / tamaño). En una cadena de marcos guarda la historia completa.
static func capture_text_state(shape: Node2D) -> Dictionary:
	var st := {
		"text": String(shape.get_meta("text", "")),
		"runs": (shape.get_meta("runs", []) as Array).duplicate(true),
		"font_size": int(shape.get_meta("font_size", 24)),
		"width": shape.get_meta("width", null),
		"height": shape.get_meta("height", null),
	}
	if shape.has_meta("next_paragraph") or shape.has_meta("prev_paragraph"):
		var head := ParagraphThreading.get_chain_head(shape)
		st["story_head"] = weakref(head)
		st["story"] = String(head.get_meta("raw_story_text", head.get_meta("text", "")))
	return st

static func same_text_state(a: Dictionary, b: Dictionary) -> bool:
	return a.get("text") == b.get("text") and a.get("story", "") == b.get("story", "") \
			and a.get("font_size") == b.get("font_size") and var_to_str(a.get("runs")) == var_to_str(b.get("runs"))

## Restaura una foto de capture_text_state en metas, label, editor y VRT.
static func restore_text_state(shape: Node2D, st: Dictionary) -> void:
	if not is_instance_valid(shape):
		return
	var fs := int(st.get("font_size", 24))
	shape.set_meta("font_size", fs)
	shape.set_meta("runs", (st.get("runs", []) as Array).duplicate(true))
	if st.get("width") != null: shape.set_meta("width", st["width"])
	if st.get("height") != null: shape.set_meta("height", st["height"])
	var dl := shape.get_node_or_null("DisplayLabel")
	if dl is WorldTextLabel:
		dl.world_font_size = fs
	var head_ref = st.get("story_head")
	var head: Node2D = head_ref.get_ref() if head_ref is WeakRef else null
	if is_instance_valid(head):
		head.set_meta("raw_story_text", String(st.get("story", "")))
		ParagraphThreading.reflow_chain(head)
	else:
		var t := String(st.get("text", ""))
		shape.set_meta("text", t)
		if dl and "text" in dl:
			dl.text = t
		var vrt = shape.get_node_or_null("VectorRichText")
		if vrt:
			vrt.set_text(t)
	if dl is WorldTextLabel:
		dl.set_rich_runs(shape.get_meta("runs", []))
		if st.get("width") != null and st.get("height") != null:
			dl.set_world_size(Vector2(float(st["width"]), float(st["height"])))
	var sz := Vector2(float(shape.get_meta("width", 0.0)), float(shape.get_meta("height", 0.0)))
	for ed_name in ["MultiLineEdit", "TitleEdit"]:
		var ed := shape.get_node_or_null(ed_name) as TextEdit
		if ed:
			ed.text = String(shape.get_meta("text", ""))
			ed.add_theme_font_size_override("font_size", fs)
			if sz.x > 0.0 and sz.y > 0.0:
				ed.custom_minimum_size = sz
				ed.size = sz
	var ge := shape.get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_method("emit_safe"):
		ge.emit_safe("object_transformed")

## Registra en HistoryManager el paso before → estado actual (si cambió).
## El cambio YA está aplicado (este HistoryManager no ejecuta al commit).
static func register_text_undo(shape: Node2D, before: Dictionary, action_name: String) -> void:
	if not is_instance_valid(shape) or before.is_empty():
		return
	var after := capture_text_state(shape)
	if same_text_state(before, after):
		return
	var hm := shape.get_node_or_null("/root/HistoryManager")
	if hm == null or not hm.has_method("register_action"):
		return
	hm.register_action(action_name)
	hm.add_do(func() -> void: restore_text_state(shape, after))
	hm.add_undo(func() -> void: restore_text_state(shape, before))
	hm.commit()

## ¿Algún run trae tamaño propio? Entonces el bitmap nativo no sirve
## (no sabe tamaños por rango) y manda el overlay, como con proporciones.
func has_sized_runs() -> bool:
	for r in _effective_runs():
		if float(r.get("size", 0.0)) > 0.0:
			return true
	return false

## Tamaño de glifo con factor del run (size absoluta en mundo / base).
func _sized_char_fs(runs: Array, char_idx: int, char_fs: int) -> int:
	if runs.is_empty():
		return char_fs
	var ri := _run_index_for_char(runs, char_idx)
	var rr: Dictionary = runs[ri] if ri < runs.size() else runs[0]
	var sz := float(rr.get("size", 0.0))
	if sz > 0.0:
		return maxi(2, int(round(float(char_fs) * sz / float(maxi(1, base_font_size)))))
	return char_fs

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
	if src and src != self and src.has_meta("runs"):
		var p_runs = src.get_meta("runs")
		if p_runs is Array and not p_runs.is_empty():
			var p_total := 0
			for pr in p_runs:
				p_total += int(pr.get("length", 0))
			if p_total == text.length():
				rich_runs = (p_runs as Array).duplicate(true)
				return rich_runs
	return [{
		"length": text.length(),
		"color": font_color(),
		"stroke_color": stroke_color(),
		"stroke_width": stroke_width(),
		"bold": font_weight() >= 700,
		"italic": font_italic(),
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
	_cached_strokes = []
	_cached_underlines = []
	_polys_baked = false
	return _cached_outline

func _get_stroke_polys() -> Array:
	if not _polys_baked:
		_bake_glyph_data()
	return _cached_strokes

func _get_triangle_polys() -> Array:
	if not _polys_baked:
		_bake_glyph_data()
	return _cached_polys

## Hornea contornos para trazo, mallas trianguladas para relleno y subrayados
## en una única pasada sobre el árbol de glifos.
func _bake_glyph_data() -> void:
	if _polys_baked:
		return
	var outline := _get_outline()
	if outline == null:
		return
	_cached_polys = []
	_cached_strokes = []
	for glyph_node in outline.get_children():
		if not (glyph_node is Node2D):
			continue
		var contours := _outline_polygons(glyph_node)
		if contours.is_empty():
			continue
		var run_idx := int(glyph_node.get_meta("run_index", 0))
		_cached_strokes.append({"contours": contours, "run": run_idx})
		for poly in _triangulate_contours(contours):
			_cached_polys.append({"poly": poly, "run": run_idx})
	_cached_underlines = _build_underlines(outline)
	_polys_baked = true

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
	# Grosor y desplazamiento según el MAYOR tamaño de glifo del segmento
	# (antes fijos a VECTOR_FONT: mal en runs con tamaño propio).
	var cur_run := -1
	var cur_line := 0.0
	var cur_x0 := 0.0
	var cur_x1 := 0.0
	var cur_fs := VECTOR_FONT
	var has_pending := false

	for glyph_node in outline.get_children():
		if not (glyph_node is Node2D):
			continue
		var run_idx := int(glyph_node.get_meta("run_index", 0))
		var line_y := float(glyph_node.get_meta("baseline_y", 0.0))
		var x0 := float(glyph_node.get_meta("x0", 0.0))
		var x1 := float(glyph_node.get_meta("x1", x0))
		var gfs := int(glyph_node.get_meta("char_fs", VECTOR_FONT))
		if has_pending and run_idx == cur_run and is_equal_approx(line_y, cur_line):
			cur_x1 = x1
			cur_fs = maxi(cur_fs, gfs)
			continue
		if has_pending and cur_run >= 0 and cur_run < runs.size() and bool(runs[cur_run].get("underline", false)):
			var thickness: float = maxf(1.0, cur_fs * 0.05)
			var y: float = cur_line + cur_fs * 0.12
			segs.append({
				"rect": Rect2(cur_x0, y, cur_x1 - cur_x0, thickness),
				"color": runs[cur_run].get("color", Color.BLACK),
			})
		cur_run = run_idx
		cur_line = line_y
		cur_x0 = x0
		cur_x1 = x1
		cur_fs = gfs
		has_pending = true
	if has_pending and cur_run >= 0 and cur_run < runs.size() and bool(runs[cur_run].get("underline", false)):
		var thickness: float = maxf(1.0, cur_fs * 0.05)
		var y: float = cur_line + cur_fs * 0.12
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
	# Sangrías (px en escala fs): reducen la columna y desplazan la 1ª línea.
	var iw := indent_world()
	var ind_l := maxf(0.0, iw.x) * font_scale
	var ind_r := maxf(0.0, iw.y) * font_scale
	var ind_f := iw.z * font_scale
	var lines := _wrap_lines(font, fs, wrap_limit, ind_l, ind_r, ind_f)

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
	var ls: float = letter_spacing_world() * font_scale

	# Altura por línea: la manda su run más grande (antes todas medían fs y
	# los tramos con tamaño propio se solapaban con la línea siguiente).
	var sized := has_sized_runs()
	var ls_extra: float = float(get_theme_constant("line_spacing")) * font_scale
	var line_fss: Array[int] = []
	var total_text_h: float = maxf(0.0, float(lines.size() - 1)) * ls_extra
	for line in lines:
		var lf := _line_fs(line, fs) if sized else fs
		line_fss.append(lf)
		total_text_h += font.get_height(lf)
	var y_top := 0.0
	if box_h > total_text_h:
		match vertical_alignment:
			VERTICAL_ALIGNMENT_CENTER:
				y_top = (box_h - total_text_h) * 0.5
			VERTICAL_ALIGNMENT_BOTTOM:
				y_top = box_h - total_text_h

	for li in lines.size():
		var line: Dictionary = lines[li]
		var line_text: String = line["text"]
		var line_start: int = line["start"]
		var y_offset: float = y_top + font.get_ascent(line_fss[li])
		var line_w := 0.0
		if has_prop or sized:
			var rid_measure: RID = _get_rid_for_style(ts, base_bytes, rid_cache, false, false)
			for j in line_text.length():
				var c_idx := line_start + j
				var t_j := float(c_idx) / maxf(1.0, float(total_chars - 1))
				var s_j := _calculate_glyph_scale(prop_mode, t_j, s_start, s_mid, s_mid2, s_end) if has_prop else 1.0
				var c_fs := maxi(2, int(round(fs * s_j)))
				c_fs = _sized_char_fs(runs, c_idx, c_fs)
				var cp := line_text.unicode_at(j)
				var gl := ts.font_get_glyph_index(rid_measure, c_fs, cp, 0)
				var ad := ts.font_get_glyph_advance(rid_measure, c_fs, gl).x
				line_w += (ad if ad > 0.0 else font.get_char_size(cp, c_fs).x) + ls
		else:
			# _measure: fuente SIN la variación de tracking + ls a escala fs
			# (antes el tracking se sumaba dos veces y descentraba la línea).
			line_w = _measure(line_text, fs)
		# Alineación dentro de la columna sangrada; la 1ª línea de cada
		# párrafo suma indent_first (negativa = francesa, sin salir de 0).
		var col_w := box_w
		if box_w > 0.0 and (ind_l > 0.0 or ind_r > 0.0):
			col_w = maxf(0.0, box_w - ind_l - ind_r)
		var cx := ind_l
		if col_w > line_w:
			match horizontal_alignment:
				HORIZONTAL_ALIGNMENT_CENTER:
					cx = ind_l + (col_w - line_w) * 0.5
				HORIZONTAL_ALIGNMENT_RIGHT:
					cx = ind_l + (col_w - line_w)
		if bool(line.get("first", false)):
			cx += ind_f
		cx = maxf(0.0, cx)
		# Justificado (FILL): reparte el sobrante entre los espacios de las
		# líneas envueltas que NO cierran párrafo (el overlay lo ignoraba).
		var just_extra := 0.0
		if horizontal_alignment == HORIZONTAL_ALIGNMENT_FILL and wrap_limit > 0.0 and not bool(line.get("last", true)):
			var spaces := line_text.count(" ")
			var avail := col_w - line_w - (ind_f if bool(line.get("first", false)) else 0.0)
			if spaces > 0 and avail > 0.0:
				just_extra = avail / float(spaces)
		for i in line_text.length():
			var char_idx := line_start + i
			var char_fs := fs
			if has_prop:
				var t := float(char_idx) / maxf(1.0, float(total_chars - 1))
				var s_factor := _calculate_glyph_scale(prop_mode, t, s_start, s_mid, s_mid2, s_end)
				char_fs = maxi(2, int(round(fs * s_factor)))
			char_fs = _sized_char_fs(runs, char_idx, char_fs)
			var run_idx := _run_index_for_char(runs, char_idx)
			var run: Dictionary = runs[run_idx] if run_idx < runs.size() else runs[0]
			var rid: RID = _get_rid_for_style(ts, base_bytes, rid_cache, bool(run.get("bold", false)), bool(run.get("italic", false)))
			var codepoint: int = line_text.unicode_at(i)
			var glyph: int = ts.font_get_glyph_index(rid, char_fs, codepoint, 0)
			var adv: float = ts.font_get_glyph_advance(rid, char_fs, glyph).x
			var char_adv := (adv if adv > 0.0 else font.get_char_size(codepoint, char_fs).x) + ls
			if codepoint == 32:
				char_adv += just_extra
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
				glyph_group.set_meta("char_fs", char_fs)
				_append_glyph_path(ts, rid, char_fs, glyph, glyph_group, cx, y_offset)
				if glyph_group.get_child_count() > 0:
					container.add_child(glyph_group)
				else:
					glyph_group.free()  # nunca entró al árbol: huérfano si no se libera a mano
			else:
				_append_glyph_path(ts, rid, char_fs, glyph, container, cx, y_offset)
			cx = next_cx
		y_top += font.get_height(line_fss[li]) + ls_extra

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

## Altura del contenido con el ancho del marco (determinista: solo depende
## del texto, el ancho y la fuente — sin estado del Control, sin ratchet).
## `src` permite medir el texto del editor mientras se escribe.
## Se mide a fs = base (font_scale 1): mundo == px de fuente.
func wrapped_content_height(src: String = "") -> float:
	var font := get_theme_font("font")
	if font == null:
		return 0.0
	var fs := maxi(1, base_font_size)
	var fw := 0.0
	if has_meta(WORLD_SIZE_META):
		fw = (get_meta(WORLD_SIZE_META) as Vector2).x
	elif _world_size != Vector2.ZERO:
		fw = _world_size.x
	else:
		var p := get_parent()
		if p and p.has_meta("width"):
			fw = float(p.get_meta("width"))
	var iw := indent_world()
	var lines := _wrap_lines(font, fs, fw, maxf(0.0, iw.x), maxf(0.0, iw.y), iw.z, src)
	if lines.is_empty():
		return 0.0
	var ls := float(get_theme_constant("line_spacing"))
	var sized := has_sized_runs() and (src == "" or src == text)
	var h := maxf(0.0, float(lines.size() - 1)) * ls
	for line in lines:
		h += float(font.get_height(_line_fs(line, fs) if sized else fs))
	return h

## Cada línea: {"text", "start", "first"}. `start` = índice del primer carácter
## en el texto ORIGINAL (sin re-envolver) para mapear runs aunque el autowrap
## reparta distinto. `first` = primera línea envuelta del párrafo (sangría).
func _wrap_lines(font: Font, fs: int, wrap_w: float, ind_l: float = 0.0, ind_r: float = 0.0, ind_first: float = 0.0, src: String = "") -> Array:
	var out: Array = []
	var body := src if src != "" else text
	# Los índices de runs solo valen si `body` ES el texto del label (en el
	# threading se envuelve un tramo de la historia, no `text`).
	var runs_apply := body == text
	var raw_lines: PackedStringArray = body.replace("\r\n", "\n").split("\n")
	var raw_start := 0
	for r in raw_lines:
		var eff_w := wrap_w
		if wrap_w > 0.0:
			eff_w = wrap_w - ind_l - ind_r
		if wrap_w <= 0.0 or not font or eff_w <= 0.0:
			out.append({"text": r, "start": raw_start, "first": true, "last": true})
		else:
			var words: PackedStringArray = r.split(" ", true)
			var current := ""
			var current_start := raw_start
			var cursor := raw_start
			var first := true
			for word in words:
				var probe := current + (" " if current.length() > 0 else "") + word
				# Tracking escalado a fs + tamaños por run (antes: la variación
				# de tracking en px de OTRO tamaño y todo a tamaño base).
				var w: float = _measure_span(current_start, probe, fs) if runs_apply else _measure(probe, fs)
				var max_w: float = maxf(0.0, eff_w - ind_first) if first else eff_w
				if w <= max_w or current.length() == 0:
					current = probe
				else:
					out.append({"text": current, "start": current_start, "first": first, "last": false})
					first = false
					current_start = cursor
					current = word
				cursor += word.length() + 1
			out.append({"text": current, "start": current_start, "first": first, "last": true})
		raw_start += r.length() + 1
	return out

func to_svg() -> String:
	var col := font_color()
	# Familia desde la fuente real de las metas (contenedor o label).
	var src := _spec_source()
	var family := String(src.get_meta(META_FAMILY, "sans-serif")) if src else "sans-serif"
	var fs := maxi(1, base_font_size)
	var attrs := ' font-family="%s" font-size="%d" fill="#%s"' % [family.xml_escape(), fs, col.to_html(false)]
	if font_weight() >= 700:
		attrs += ' font-weight="bold"'
	if font_italic():
		attrs += ' font-style="italic"'
	var lsw := letter_spacing_world()
	if absf(lsw) > 0.0001:
		attrs += ' letter-spacing="%s"' % String.num(lsw, 3)
	if has_stroke():
		attrs += ' stroke="#%s" stroke-width="%f" paint-order="stroke fill"' % [stroke_color().to_html(false), stroke_width()]

	# Ancho del marco (mundo) para alineación y envoltura.
	var ws := Vector2.ZERO
	if has_meta(WORLD_SIZE_META):
		ws = get_meta(WORLD_SIZE_META)
	elif _world_size != Vector2.ZERO:
		ws = _world_size
	elif get_parent() and get_parent().has_meta("width"):
		ws = Vector2(float(get_parent().get_meta("width")), float(get_parent().get_meta("height", 0.0)))
	var iw := indent_world()
	var anchor := "start"
	var ax := position.x + maxf(0.0, iw.x)
	match horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			anchor = "middle"
			ax = position.x + maxf(0.0, iw.x) + maxf(0.0, ws.x - maxf(0.0, iw.x) - maxf(0.0, iw.y)) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			anchor = "end"
			ax = position.x + ws.x - maxf(0.0, iw.y)
	if anchor != "start":
		attrs += ' text-anchor="%s"' % anchor

	# Una <tspan> por línea (antes: todo el párrafo en una sola línea).
	var font := get_theme_font("font")
	var wrap_w := ws.x if autowrap_mode != TextServer.AUTOWRAP_OFF else 0.0
	var lines: Array = _wrap_lines(font, fs, wrap_w, maxf(0.0, iw.x), maxf(0.0, iw.y), iw.z) if font \
			else [{"text": text, "start": 0, "first": true}]
	var lh := (font.get_height(fs) if font else fs * 1.2) + float(get_theme_constant("line_spacing"))
	var runs := _effective_runs()
	var rich := runs.size() > 1 or has_rich_runs()
	var body := ""
	for li in lines.size():
		var line: Dictionary = lines[li]
		var lx := ax + (iw.z if anchor == "start" and bool(line.get("first", false)) else 0.0)
		var inner := ""
		if rich:
			inner = _svg_line_runs(runs, int(line["start"]), String(line["text"]))
		else:
			inner = String(line["text"]).xml_escape()
		body += '<tspan x="%f" dy="%f">%s</tspan>' % [lx, 0.0 if li == 0 else lh, inner]
	return '<text x="%f" y="%f" dominant-baseline="hanging"%s>%s</text>' % [position.x, position.y, attrs, body]

## Trozos <tspan> por run dentro de una línea [start, start + len).
func _svg_line_runs(runs: Array, start: int, line_text: String) -> String:
	var out := ""
	var pos := 0
	var end := start + line_text.length()
	for r in runs:
		var l: int = int(r.get("length", 0))
		var a := maxi(pos, start)
		var b := mini(pos + l, end)
		pos += l
		if a >= b:
			continue
		var chunk := line_text.substr(a - start, b - a).xml_escape()
		var extra := ' fill="#%s"' % (r.get("color", font_color()) as Color).to_html(false)
		if bool(r.get("bold", false)): extra += ' font-weight="bold"'
		if bool(r.get("italic", false)): extra += ' font-style="italic"'
		if bool(r.get("underline", false)): extra += ' text-decoration="underline"'
		if float(r.get("size", 0.0)) > 0.0: extra += ' font-size="%d"' % int(r["size"])
		var r_sw := float(r.get("stroke_width", stroke_width()))
		if r_sw > 0.0:
			extra += ' stroke="#%s" stroke-width="%f"' % [(r.get("stroke_color", stroke_color()) as Color).to_html(false), r_sw]
		out += '<tspan%s>%s</tspan>' % [extra, chunk]
	return out

# ── Resaltador en vivo para editores en línea (TitleEdit / MultiLineEdit) ────
class RunHighlighter extends SyntaxHighlighter:
	var _shape_ref: WeakRef = null

	func _init(shape: Node2D = null) -> void:
		if shape:
			_shape_ref = weakref(shape)

	func _get_line_syntax_highlighting(line: int) -> Dictionary:
		var result: Dictionary = {}
		if _shape_ref == null:
			return result
		var shape: Node2D = _shape_ref.get_ref()
		if not is_instance_valid(shape):
			return result
		var te: TextEdit = get_text_edit()
		if te == null or line >= te.get_line_count():
			return result

		var runs: Array = shape.get_meta("runs", [])
		var default_col := Color.BLACK
		var dl: Control = shape.get_node_or_null("DisplayLabel")
		if dl and dl.has_method("font_color"):
			default_col = dl.font_color()
		elif shape.has_meta("text_color"):
			default_col = shape.get_meta("text_color")

		result[0] = {"color": default_col}
		if runs.is_empty():
			return result

		var line_start := 0
		for l in range(line):
			line_start += te.get_line(l).length() + 1
		var line_text := te.get_line(line)
		var line_len := line_text.length()
		var line_end := line_start + line_len

		var pos := 0
		for r in runs:
			if not (r is Dictionary):
				continue
			var r_len: int = int(r.get("length", 0))
			var r_end := pos + r_len
			var col: Color = r.get("color", default_col)

			var o_start := maxi(pos, line_start)
			var o_end := mini(r_end, line_end)
			if o_start < o_end:
				var col_in_line := o_start - line_start
				result[col_in_line] = {"color": col}
				var end_in_line := o_end - line_start
				if end_in_line < line_len and not result.has(end_in_line):
					result[end_in_line] = {"color": default_col}
			pos = r_end

		return result

