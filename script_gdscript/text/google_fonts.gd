# =============================================================================
# RUTA: res://script_gdscript/text/google_fonts.gd
# Catálogo de 30 familias de Google Fonts (OFL / Apache) que se DESCARGAN
# bajo demanda la primera vez que se eligen y quedan en caché en
# user://fonts/google/<Familia>/ (sin engordar el proyecto ni el ejecutable).
#
# Por familia se piden las caras estáticas regular y negrita, con sus
# cursivas si existen (Google omite las que no hay). FontCore las usa como
# las estáticas de Inter: peso más cercano, sin negrita sintética.
#
# Vive como hijo de FontCore (necesita nodos HTTPRequest).
# =============================================================================
extends Node

signal installed(family: String)
signal failed(family: String, reason: String)

const CACHE_DIR := "user://fonts/google/"
const CSS_URL := "https://fonts.googleapis.com/css2?family=%s:ital,wght@0,400;0,700;1,400;1,700&display=swap"

## Las 30 elegidas, por categoría (el orden es el de la lista).
const CATALOG := {
	"Roboto": "sans", "Open Sans": "sans", "Montserrat": "sans", "Lato": "sans",
	"Poppins": "sans", "Raleway": "sans", "Nunito": "sans", "Rubik": "sans",
	"Work Sans": "sans", "DM Sans": "sans", "Manrope": "sans", "Outfit": "sans",
	"Plus Jakarta Sans": "sans", "Space Grotesk": "sans", "Figtree": "sans",
	"Josefin Sans": "sans",
	"Playfair Display": "serif", "Merriweather": "serif", "Lora": "serif",
	"Libre Baskerville": "serif", "EB Garamond": "serif", "Cormorant Garamond": "serif",
	"Oswald": "display", "Bebas Neue": "display", "Abril Fatface": "display",
	"Lobster": "script", "Pacifico": "script", "Caveat": "script",
	"JetBrains Mono": "mono", "Fira Code": "mono",
}

var _busy: Dictionary = {}   # familia -> true mientras se descarga

func families() -> PackedStringArray:
	return PackedStringArray(CATALOG.keys())

func has(family: String) -> bool:
	return CATALOG.has(family)

func category(family: String) -> String:
	return String(CATALOG.get(family, ""))

func is_downloading(family: String) -> bool:
	return _busy.has(family)

func dir_for(family: String) -> String:
	return CACHE_DIR + family.replace(" ", "_") + "/"

## Archivo de una cara: "<peso>.ttf" o "<peso>i.ttf" (cursiva).
static func face_file(weight: int, italic: bool) -> String:
	return "%d%s.ttf" % [weight, "i" if italic else ""]

## Caras descargadas: {"roman": {400: ruta, …}, "italic": {…}}.
func cached_faces(family: String) -> Dictionary:
	var out := {"roman": {}, "italic": {}}
	var dir := dir_for(family)
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if not f.ends_with(".ttf"):
			continue
		var stem := f.get_basename()
		var italic := stem.ends_with("i")
		var w := int(stem.trim_suffix("i"))
		if w > 0:
			out["italic" if italic else "roman"][w] = dir + f
	return out

func is_cached(family: String) -> bool:
	return not (cached_faces(family)["roman"] as Dictionary).is_empty()

## Descarga la familia (si no está ya o en curso). Emite installed / failed.
func download(family: String) -> void:
	if not has(family) or _busy.has(family) or is_cached(family):
		return
	_busy[family] = true
	_run(family)

func _run(family: String) -> void:
	var css := await _get_text(CSS_URL % family.uri_encode())
	if css.is_empty():
		_fail(family, "no se pudo contactar con Google Fonts")
		return
	# @font-face { font-style: italic; font-weight: 700; … src: url(…ttf) }
	var re := RegEx.new()
	re.compile("font-style:\\s*(\\w+);\\s*font-weight:\\s*(\\d+);[^}]*?src:\\s*url\\(([^)]+)\\)")
	var faces: Array = []
	for m in re.search_all(css):
		faces.append({"italic": m.get_string(1) == "italic", "weight": int(m.get_string(2)), "url": m.get_string(3)})
	if faces.is_empty():
		_fail(family, "respuesta sin fuentes")
		return
	# Se descarga a "<Familia>.part/" y se renombra al final: así la familia
	# no cuenta como descargada (is_cached) con la mitad de las caras.
	var dir := dir_for(family)
	var part := dir.trim_suffix("/") + ".part/"
	_clear_dir(part)
	DirAccess.make_dir_recursive_absolute(part)
	var ok := 0
	for f in faces:
		var bytes := PackedByteArray()
		for attempt in 3:
			bytes = await _get_bytes(String(f["url"]))
			if bytes.size() >= 1000:   # error o respuesta vacía → reintento
				break
		if bytes.size() < 1000:
			continue
		var fa := FileAccess.open(part + face_file(int(f["weight"]), bool(f["italic"])), FileAccess.WRITE)
		if fa:
			fa.store_buffer(bytes)
			fa.close()
			ok += 1
	_busy.erase(family)
	if ok < faces.size():
		_clear_dir(part)
		_fail(family, "%d de %d caras descargadas" % [ok, faces.size()])
		return
	_clear_dir(dir)
	if DirAccess.rename_absolute(part, dir) != OK:
		_fail(family, "no se pudo guardar en caché")
		return
	installed.emit(family)

static func _clear_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + f)
	DirAccess.remove_absolute(path)

func _fail(family: String, reason: String) -> void:
	_busy.erase(family)
	push_warning("Google Fonts: %s — %s" % [family, reason])
	failed.emit(family, reason)

func _get_text(url: String) -> String:
	var body := await _get_bytes(url)
	return body.get_string_from_utf8()

func _get_bytes(url: String) -> PackedByteArray:
	var req := HTTPRequest.new()
	req.timeout = 30.0
	add_child(req)
	# Sin User-Agent de navegador Google devuelve TTF (no WOFF2).
	if req.request(url, PackedStringArray(["User-Agent: Vectopen"])) != OK:
		req.queue_free()
		return PackedByteArray()
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return PackedByteArray()
	return res[3]
