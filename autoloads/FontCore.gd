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
const DEFAULT_FAMILY := "Inter"
const DEFAULT_WEIGHT := 400
const _SAMPLE := "The quick brown fox jumps 0123456789"

var _families: PackedStringArray = PackedStringArray()
var _font_cache: Dictionary = {}   # spec_key -> Font

func _ready() -> void:
	refresh_families()

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
	families_changed.emit()

func list_families() -> PackedStringArray:
	if _families.is_empty():
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

	if BUNDLED.has(fam):
		var base = load(BUNDLED[fam])
		if base is Font:
			if weight != DEFAULT_WEIGHT:
				var fv := FontVariation.new()
				fv.base_font = base
				# Inter-Regular no es variable: se emula el grosor engordando el
				# contorno (aprox. -0.25 .. +1.0).
				fv.variation_embolden = clampf((weight - DEFAULT_WEIGHT) / 300.0, -0.25, 1.0)
				font = fv
			else:
				font = base
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([fam])
		sf.font_weight = weight
		sf.font_italic = italic
		# fallback legible si el SO no encuentra la familia
		sf.allow_system_fallback = true
		font = sf

	if font == null:
		font = load(BUNDLED[DEFAULT_FAMILY]) as Font
	_font_cache[key] = font
	return font

func default_font() -> Font:
	return get_font(make_spec())

# ── bytes de la fuente (para los contornos Bézier / text-to-shape) ────────────
## Se devuelven los BYTES, no un RID: quien los use crea su propio RID de
## TextServer y lo libera (evita fugas de RID al cerrar).
func font_bytes(spec: Dictionary) -> PackedByteArray:
	var fam := String(spec.get("family", DEFAULT_FAMILY))
	if BUNDLED.has(fam):
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
