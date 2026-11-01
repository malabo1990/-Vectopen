# =============================================================================
# RUTA: res://script_gdscript/system/native_io.gd
# Puente con la extensión NATIVA de importación/exportación (rust/vectopen_io,
# clase «VectopenIO»). Windows, macOS y Linux.
#
#   · Si la extensión está cargada y sabe leer el formato, se usa (más rápida,
#     más completa y aislada: un archivo dañado no puede colgar la app).
#   · Si no está, o falla con ese archivo, se usan los importadores GDScript
#     de siempre (svg_import.gd / ps_import.gd). Nunca te quedas sin importar.
#   · VECTOPEN_IO=gdscript en el entorno fuerza GDScript (para comparar).
#
# Devuelve el mismo formato que svg_import.gd: {size, items, warnings}, más
# «engine» ("nativo" | "gdscript") y «error» si no se pudo leer nada.
# =============================================================================
extends RefCounted

const SvgImport = preload("res://script_gdscript/system/svg_import.gd")
const PsImport = preload("res://script_gdscript/system/ps_import.gd")

static var _io: Object = null
static var _checked := false

## Instancia de VectopenIO, o null si la librería nativa no cargó.
static func native() -> Object:
	if not _checked:
		_checked = true
		if OS.get_environment("VECTOPEN_IO") != "gdscript" and ClassDB.class_exists("VectopenIO"):
			_io = ClassDB.instantiate("VectopenIO")
	return _io

static func is_native() -> bool:
	return native() != null

## Importa un archivo vectorial (svg, eps, ai, pdf, ps).
static func parse_file(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	var io := native()
	var native_error := ""
	if io and ext in io.import_extensions():
		var r: Dictionary = io.import_file(ProjectSettings.globalize_path(path))
		if bool(r.get("ok", false)):
			r["engine"] = "nativo"
			return r
		native_error = String(r.get("error", ""))
		push_warning("vectopen_io: %s → se usa el importador GDScript" % native_error)
	var d: Dictionary
	match ext:
		"svg":
			d = SvgImport.parse(FileAccess.get_file_as_string(path))
		"eps", "ai", "pdf", "ps":
			d = PsImport.parse_file(path)
		"af", "afdesign", "afphoto", "afpub", "aftemplate":
			# Affinity solo tiene lector nativo (formato cerrado).
			d = {"size": Vector2(800, 600), "items": [], "warnings": []}
			if native_error == "":
				native_error = "para abrir archivos de Affinity hace falta la extensión nativa vectopen_io"
		_:
			d = {"size": Vector2(800, 600), "items": [], "warnings": []}
	d["engine"] = "gdscript"
	if native_error != "" and (d.get("items", []) as Array).is_empty():
		d["error"] = native_error
	return d

## Convierte cualquier formato que el importador nativo lea (p. ej. Affinity)
## a SVG estándar. Devuelve "" si salió bien o el mensaje de error.
static func convert_to_svg(src: String, dst: String) -> String:
	var io := native()
	if io == null:
		return "falta la extensión nativa vectopen_io"
	return String(io.convert_to_svg(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst)))

## Imagen que Godot no sabe leer (p. ej. JPEG CMYK) → Image, o null.
static func load_image(path: String) -> Image:
	var io := native()
	if io == null:
		return null
	var png: PackedByteArray = io.image_to_png(FileAccess.get_file_as_bytes(path))
	if png.is_empty():
		return null
	var img := Image.new()
	return img if img.load_png_from_buffer(png) == OK else null
