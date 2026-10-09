# ==========================================
# RUTA: res://autoloads/FontCore.gd
# AUTOLOAD (Singleton) — Sistema CORE de tipografía.
# ==========================================
extends Node
## Capa central entre las fuentes disponibles (las del SISTEMA OPERATIVO del
## usuario + las empaquetadas con el proyecto) y cualquier UI o figura de texto.
##
## Responsabilidades:
##  · Enumerar familias tipográficas (SO + bundled), buscar por nombre.
##  · Resolver una "spec" {family, weight, italic} a un recurso `Font` cacheado
##    — `SystemFont` para las del SO, `FontFile`/`FontVariation` para bundled.
##  · Mantener el pool de RID de TextServer con los BYTES de cada fuente, para
##    los contornos Bézier (text-to-shape) — liberado al salir (sin fugas).
##  · Texto de muestra estándar para las previsualizaciones.
##
## Una figura de texto guarda la spec como META (`font_family`/`font_weight`/
## `font_italic`); InspectorCore la lee/escribe y WorldTextLabel la aplica.

signal families_changed()

## Fuentes empaquetadas (siempre disponibles, offline). Clave = nombre de familia.
const BUNDLED := {
	"Inter": "res://assets/fonts/Inter-Regular.ttf",
}
## Pesos/cursivas ESTÁTICOS de las familias empaquetadas (archivos oficiales
## de Inter, con los solapes de contorno eliminados). Sustituyen a la negrita
## y cursiva SINTÉTICAS: el emboldening — y también las fuentes VARIABLES, que
## conservan solapes por diseño — dejan muescas blancas con MSDF (limitación
## documentada de Godot: MSDF no dibuja bien contornos solapados).
const BUNDLED_STATIC := {
	"Inter": {
		"roman": {300: "Inter-Light", 400: "Inter-Regular", 500: "Inter-Medium", 600: "Inter-SemiBold",
			700: "Inter-Bold", 800: "Inter-ExtraBold", 900: "Inter-Black"},
		"italic": {300: "Inter-LightItalic", 400: "Inter-Italic", 500: "Inter-MediumItalic", 600: "Inter-SemiBoldItalic",
			700: "Inter-BoldItalic", 800: "Inter-ExtraBoldItalic", 900: "Inter-BlackItalic"},
	},
}
const FONTS_DIR := "res://assets/fonts/"
const DEFAULT_FAMILY := "Inter"
const DEFAULT_WEIGHT := 400
const _SAMPLE := "The quick brown fox jumps 0123456789"

var _families: PackedStringArray = PackedStringArray()
var _font_cache: Dictionary = {}   # spec_key -> Font
var _system_scanned: bool = false

func _ready() -> void:
	# Carga inicial inmediata de fuentes empaquetadas (inicio instantáneo en < 1ms)
	_families = PackedStringArray(BUNDLED.keys())
	# Escaneo en segundo plano sin congelar el hilo principal del editor
	WorkerThreadPool.add_task(_async_scan_system_fonts)

func _async_scan_system_fonts() -> void:
	var seen := {}
	for f in BUNDLED:
		seen[f] = true
	for f in OS.get_system_fonts():
		var fam_name := String(f).strip_edges()
		if fam_name != "":
			seen[fam_name] = true
	var arr: Array = seen.keys()
	arr.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
	call_deferred("_apply_scanned_families", PackedStringArray(arr))

func _apply_scanned_families(scanned: PackedStringArray) -> void:
	_families = scanned
	_system_scanned = true
	families_changed.emit()

# ── enumeración ──────────────────────────────────────────────────────────────
func refresh_families() -> void:
	var seen := {}
	for f in BUNDLED:
		seen[f] = true
	for f in OS.get_system_fonts():
		var fam_name := String(f).strip_edges()
		if fam_name != "":
			seen[fam_name] = true
	var arr: Array = seen.keys()
	arr.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
	_families = PackedStringArray(arr)
	_system_scanned = true
	families_changed.emit()

func list_families() -> PackedStringArray:
	if not _system_scanned:
		refresh_families()
	return _families

## Filtro por subcadena (case-insensitive). "" → todas.
func search(query: String) -> PackedStringArray:
	var q := query.strip_edges().to_lower()
	if q == "":
		return list_families()
	var out := PackedStringArray()
	for f in list_families():
		if String(f).to_lower().contains(q):
			out.append(f)
	return out

func has_family(family: String) -> bool:
	return family in list_families()

func is_bundled(family: String) -> bool:
	return BUNDLED.has(family)

func sample_text() -> String:
	return _SAMPLE

# ── spec ─────────────────────────────────────────────────────────────────────
## Normaliza y devuelve {family, weight, italic}.
func make_spec(family: String = DEFAULT_FAMILY, weight: int = DEFAULT_WEIGHT, italic: bool = false) -> Dictionary:
	var fam := family.strip_edges()
	if fam == "":
		fam = DEFAULT_FAMILY
	return {"family": fam, "weight": clampi(weight, 100, 900), "italic": italic}

func spec_from_node(node: Object) -> Dictionary:
	return make_spec(
		String(node.get_meta("font_family", DEFAULT_FAMILY)),
		int(node.get_meta("font_weight", DEFAULT_WEIGHT)),
		bool(node.get_meta("font_italic", false)))

func spec_key(spec: Dictionary) -> String:
	return "%s|%d|%d" % [
		spec.get("family", DEFAULT_FAMILY),
		int(spec.get("weight", DEFAULT_WEIGHT)),
		1 if spec.get("italic", false) else 0]

## "Inter · Regular" / "Arial · Bold Italic" — para etiquetas de UI.
func describe(spec: Dictionary) -> String:
	var w := int(spec.get("weight", DEFAULT_WEIGHT))
	var it: bool = spec.get("italic", false)
	var style: String = _WEIGHT_NAMES.get(w, str(w))
	if it:
		style = "Regular Italic" if style == "Regular" else style + " Italic"
	return "%s · %s" % [spec.get("family", DEFAULT_FAMILY), style]

const _WEIGHT_NAMES := {
	100: "Thin", 200: "ExtraLight", 300: "Light", 400: "Regular",
	500: "Medium", 600: "SemiBold", 700: "Bold", 800: "ExtraBold", 900: "Black",
}
const STYLE_PRESETS := ["Regular", "Medium", "SemiBold", "Bold", "Italic", "Bold Italic"]

func style_to_spec_parts(style: String) -> Dictionary:
	var s := style.to_lower()
	var italic := s.contains("italic") or s.contains("oblique")
	var weight := DEFAULT_WEIGHT
	for w in _WEIGHT_NAMES:
		if s.contains(String(_WEIGHT_NAMES[w]).to_lower()):
			weight = w
	if s.begins_with("bold"):
		weight = 700
	return {"weight": weight, "italic": italic}

# ── recurso Font ─────────────────────────────────────────────────────────────
func get_font(spec: Dictionary) -> Font:
	var key := spec_key(spec)
	var cached = _font_cache.get(key)
	if cached is Font:
		return cached

	var fam := String(spec.get("family", DEFAULT_FAMILY))
	var weight := int(spec.get("weight", DEFAULT_WEIGHT))
	var italic: bool = spec.get("italic", false)
	var font: Font = null

	var stf := _static_font(fam, weight, italic)
	if stf:
		_font_cache[key] = stf
		return stf

	if BUNDLED.has(fam):
		var base = load(BUNDLED[fam])
		if base is FontFile:
			base.multichannel_signed_distance_field = true
			base.msdf_pixel_range = 16
			base.msdf_size = 64
			base.antialiasing = TextServer.FONT_ANTIALIASING_LCD
			base.generate_mipmaps = true
		if base is Font:
			if weight != DEFAULT_WEIGHT:
				var fv := FontVariation.new()
				fv.base_font = base
				# Inter-Regular no es variable: se emula el grosor engordando el
				# contorno limpiamente sin auto-intersecciones ni agujeros.
				fv.variation_embolden = clampf((weight - DEFAULT_WEIGHT) / 1000.0, -0.2, 0.5)
				font = fv
			else:
				font = base
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([fam])
		sf.font_weight = weight
		sf.font_italic = italic
		sf.multichannel_signed_distance_field = true
		sf.msdf_pixel_range = 16
		sf.msdf_size = 64
		sf.antialiasing = TextServer.FONT_ANTIALIASING_LCD
		sf.generate_mipmaps = true
		# fallback legible si el SO no encuentra la familia
		sf.allow_system_fallback = true
		font = sf

	if font == null:
		font = load(BUNDLED[DEFAULT_FAMILY]) as Font
		if font is FontFile:
			font.multichannel_signed_distance_field = true
			font.msdf_pixel_range = 16
			font.msdf_size = 64
			font.antialiasing = TextServer.FONT_ANTIALIASING_LCD
			font.generate_mipmaps = true
	_font_cache[key] = font
	return font

## Ruta del archivo estático de la familia más cercano a `weight` (y cursiva).
func static_font_path(fam: String, weight: int, italic: bool) -> String:
	var styles: Dictionary = BUNDLED_STATIC.get(fam, {})
	var table: Dictionary = styles.get("italic" if italic else "roman", {})
	if table.is_empty():
		return ""
	var best := -1
	for w in table:
		if best < 0 or absi(int(w) - weight) < absi(best - weight) \
				or (absi(int(w) - weight) == absi(best - weight) and int(w) > best):
			best = int(w)
	var path := FONTS_DIR + String(table[best]) + ".ttf"
	return path if ResourceLoader.exists(path) or FileAccess.file_exists(path) else ""

func _static_font(fam: String, weight: int, italic: bool) -> Font:
	var path := static_font_path(fam, weight, italic)
	return _load_font_file(path) if not path.is_empty() else null

var _file_cache: Dictionary = {}   # ruta -> FontFile

## Carga un .ttf empaquetado: recurso importado si existe; si aún no se
## importó (archivo recién añadido, tests headless), directo del archivo.
func _load_font_file(path: String) -> FontFile:
	if _file_cache.has(path):
		return _file_cache[path]
	var f: FontFile = null
	if ResourceLoader.exists(path):
		f = load(path) as FontFile
	elif FileAccess.file_exists(path):
		f = FontFile.new()
		if f.load_dynamic_font(path) != OK:
			f = null
	if f:
		f.multichannel_signed_distance_field = true
		f.msdf_pixel_range = 16
		f.msdf_size = 64
		f.antialiasing = TextServer.FONT_ANTIALIASING_LCD
		f.generate_mipmaps = true
	_file_cache[path] = f
	return f

func default_font() -> Font:
	return get_font(make_spec())

# ── bytes de la fuente (para los contornos Bézier / text-to-shape) ────────────
## Se devuelven los BYTES, no un RID: quien los use crea su propio RID de
## TextServer y lo libera (evita fugas de RID al cerrar).
func font_bytes(spec: Dictionary) -> PackedByteArray:
	var fam := String(spec.get("family", DEFAULT_FAMILY))
	# Bytes desde el FontFile (recurso importado): en un juego EXPORTADO el
	# .ttf original no se empaqueta y FileAccess devolvía vacío → el overlay
	# vectorial se quedaba sin contornos.
	var spath := static_font_path(fam, int(spec.get("weight", DEFAULT_WEIGHT)), bool(spec.get("italic", false)))
	if not spath.is_empty():
		var sf := _load_font_file(spath)
		if sf and not sf.data.is_empty():
			return sf.data
	if BUNDLED.has(fam):
		var bf := _load_font_file(BUNDLED[fam])
		if bf and not bf.data.is_empty():
			return bf.data
		return FileAccess.get_file_as_bytes(BUNDLED[fam])
	var path := system_font_path(spec)
	if path.is_empty():
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)

func system_font_path(spec: Dictionary) -> String:
	var fam := String(spec.get("family", DEFAULT_FAMILY))
	if BUNDLED.has(fam):
		return ProjectSettings.globalize_path(BUNDLED[fam])
	# stretch 100 = normal
	return OS.get_system_font_path(fam, int(spec.get("weight", DEFAULT_WEIGHT)), 100,
		bool(spec.get("italic", false)))
