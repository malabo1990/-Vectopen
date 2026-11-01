# =============================================================================
# RUTA: res://script_gdscript/system/io_guard.gd
# Comprobaciones ANTES de importar o exportar, para fallar pronto con un aviso
# claro en vez de a medias:
#   · importar: el archivo existe, no está vacío, no es enorme y su contenido
#     corresponde a su extensión (un .pdf que no es PDF no llega al lector).
#   · exportar: nombre válido, carpeta que se puede crear y escribir, espacio
#     libre, tamaño de imagen que el formato admite, y nunca encima del
#     documento abierto.
#   · copia de seguridad: antes de una operación con riesgo, si hay cambios
#     sin guardar, se escribe una copia en user://recovery (pestaña Recuperar).
# Devuelven {ok: bool, error: String, warnings: Array[String]}.
# =============================================================================
extends RefCounted

const MAX_IMPORT_BYTES := 512 * 1024 * 1024     # más que esto: no se intenta
const SLOW_IMPORT_BYTES := 40 * 1024 * 1024     # más que esto: avisar de que tarda
## Lado máximo de imagen por formato (WEBP lo limita su especificación; el
## resto, el tamaño de textura que garantiza la GPU al renderizar).
const MAX_SIDE := {"PNG": 16384, "JPEG": 16384, "WEBP": 16383}
const RECOVERY_DIR := "user://recovery"
const MAX_SNAPSHOTS := 10
const SNAPSHOT_MIN_GAP_MS := 120000   # como mucho una copia cada 2 minutos

static var _last_snapshot_ms := -SNAPSHOT_MIN_GAP_MS

static func _result(error := "", warnings: Array = []) -> Dictionary:
	return {"ok": error == "", "error": error, "warnings": warnings}

# ── importar ─────────────────────────────────────────────────────────────────
static func check_import(path: String) -> Dictionary:
	if path.strip_edges() == "":
		return _result("no se indicó ningún archivo")
	if not FileAccess.file_exists(path):
		return _result("el archivo «%s» no existe" % path.get_file())
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _result("no se puede leer «%s» (%s)" % [path.get_file(), error_string(FileAccess.get_open_error())])
	var size := f.get_length()
	var head := f.get_buffer(mini(size, 4096))
	f.close()
	if size == 0:
		return _result("«%s» está vacío" % path.get_file())
	if size > MAX_IMPORT_BYTES:
		return _result("«%s» ocupa %s; el máximo es %s" % [path.get_file(), String.humanize_size(size), String.humanize_size(MAX_IMPORT_BYTES)])
	var ext := path.get_extension().to_lower()
	var kind := sniff(head)
	var expected: Array = {
		"svg": ["svg"], "pdf": ["pdf"], "eps": ["ps", "eps_dos"], "ps": ["ps", "eps_dos"],
		"ai": ["pdf", "ps", "eps_dos"], "png": ["png"], "jpg": ["jpg"], "jpeg": ["jpg"],
		"webp": ["webp"], "vop": ["json"], "gltf": ["json"], "glb": ["glb"],
		"vtp": ["vtc"], "vtc": ["vtc"], "vectopen": ["vtc", "json"],
	}.get(ext, [])
	if not expected.is_empty() and not (kind in expected):
		var what := (" (parece %s)" % kind.to_upper()) if kind != "" else ""
		return _result("«%s» no es un archivo .%s válido%s o está dañado" % [path.get_file(), ext, what])
	var warns: Array = []
	if size > SLOW_IMPORT_BYTES:
		warns.append("«%s» ocupa %s: puede tardar" % [path.get_file(), String.humanize_size(size)])
	return _result("", warns)

## Tipo real por los primeros bytes: svg, pdf, ps, eps_dos, png, jpg, webp,
## json, glb, vtc o "" si no se reconoce.
static func sniff(head: PackedByteArray) -> String:
	var n := head.size()
	if n >= 4 and head[0] == 0xC5 and head[1] == 0xD0 and head[2] == 0xD3 and head[3] == 0xC6:
		return "eps_dos"
	if n >= 8 and head.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		return "png"
	if n >= 3 and head[0] == 0xFF and head[1] == 0xD8 and head[2] == 0xFF:
		return "jpg"
	var txt := head.slice(0, mini(n, 4096))
	for i in txt.size():   # solo 4 KB: los ceros cortarían el texto
		if txt[i] == 0:
			txt[i] = 32
	var s := txt.get_string_from_ascii()
	if s.begins_with("RIFF") and s.substr(8, 4) == "WEBP":
		return "webp"
	if s.begins_with("glTF"):
		return "glb"
	if s.begins_with("VTC"):
		return "vtc"
	# PDF puede llevar basura antes de la cabecera (lo permite la norma)
	if s.find("%PDF-") >= 0:
		return "pdf"
	var t := s.strip_edges(true, false).trim_prefix("﻿").trim_prefix("ï»¿").strip_edges(true, false)
	if t.begins_with("%!"):
		return "ps"
	if t.begins_with("{") or t.begins_with("["):
		return "json"
	if s.findn("<svg") >= 0 or (t.begins_with("<?xml") or t.begins_with("<!DOCTYPE svg")):
		return "svg"
	return ""

# ── exportar ─────────────────────────────────────────────────────────────────
## `pixel_size`: tamaño final en píxeles para formatos de imagen (ZERO si no aplica).
static func check_export(path: String, format: String, pixel_size: Vector2 = Vector2.ZERO, open_document := "") -> Dictionary:
	var fmt := format.to_upper()
	if path.strip_edges() == "":
		return _result("no se indicó dónde guardar")
	var name := path.get_file()
	if name.get_basename().strip_edges() == "" or name.validate_filename() != name:
		return _result("el nombre «%s» no es válido (no uses \\ / : * ? \" < > |)" % name)
	var p := ProjectSettings.globalize_path(path).simplify_path()
	if open_document != "" and p == ProjectSettings.globalize_path(open_document).simplify_path():
		return _result("«%s» es el documento abierto; elige otro nombre para no sobrescribirlo" % name)
	var dir := p.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			return _result("no se puede crear la carpeta «%s» (%s)" % [dir, error_string(mk)])
	# ¿Se puede escribir ahí? (permisos, unidad de solo lectura, USB quitado)
	var probe := dir.path_join(".vectopen_write_test")
	var pf := FileAccess.open(probe, FileAccess.WRITE)
	if pf == null:
		return _result("no se puede escribir en «%s» (%s)" % [dir, error_string(FileAccess.get_open_error())])
	pf.close()
	DirAccess.remove_absolute(probe)
	var warns: Array = []
	if fmt in MAX_SIDE and pixel_size != Vector2.ZERO:
		var w := int(ceil(pixel_size.x))
		var h := int(ceil(pixel_size.y))
		var lim: int = MAX_SIDE[fmt]
		if w < 1 or h < 1:
			return _result("la imagen saldría vacía (%d×%d px)" % [w, h])
		if w > lim or h > lim:
			return _result("la imagen saldría de %d×%d px y %s admite como máximo %d px por lado; baja la escala" % [w, h, fmt, lim])
	var need := estimate_bytes(fmt, pixel_size)
	var da := DirAccess.open(dir)
	if da:
		var free := da.get_space_left()
		if free > 0 and need > 0 and free < need * 2:
			return _result("no hay espacio suficiente en «%s» (libre %s)" % [dir, String.humanize_size(free)])
	if FileAccess.file_exists(p):
		warns.append("«%s» ya existía y se ha reemplazado" % name)
	return _result("", warns)

static func estimate_bytes(fmt: String, pixel_size: Vector2) -> int:
	if fmt in MAX_SIDE and pixel_size != Vector2.ZERO:
		return int(pixel_size.x * pixel_size.y * 4.0)   # peor caso sin comprimir
	return 1024 * 1024

# ── copia de seguridad antes de operar ───────────────────────────────────────
## Si hay cambios sin guardar, guarda una copia del documento en
## user://recovery (como mucho una cada 2 min; se conservan las 10 últimas).
## Devuelve la ruta de la copia o "".
static func snapshot_if_unsaved(tree: SceneTree, reason: String, force := false) -> String:
	if tree == null:
		return ""
	var sm := tree.root.get_node_or_null("SaveManager")
	if sm == null or not bool(sm.get("is_modified")):
		return ""
	var now := Time.get_ticks_msec()
	if not force and now - _last_snapshot_ms < SNAPSHOT_MIN_GAP_MS:
		return ""
	var canvas := tree.get_first_node_in_group("_vectopen_canvas")
	var container: Node = canvas.get_node_or_null("ArtboardsContainer") if canvas else null
	if container == null:
		return ""
	DirAccess.make_dir_recursive_absolute(RECOVERY_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := RECOVERY_DIR.path_join("%s_antes-de-%s.vtp" % [stamp, reason.validate_filename()])
	var CS = load("res://scripts/canvas/canvas_serializer.gd")
	# false: las páginas sin cargar siguen apuntando al documento, no a la copia
	if not CS.write_vtc(path, container, {}, false):
		return ""
	_last_snapshot_ms = now
	_prune_snapshots()
	return path

static func _prune_snapshots() -> void:
	var d := DirAccess.open(RECOVERY_DIR)
	if d == null:
		return
	var snaps: Array = []
	for f in d.get_files():
		if f.contains("_antes-de-") and f.ends_with(".vtp"):
			snaps.append(f)
	snaps.sort()   # la fecha va en el nombre: orden alfabético = cronológico
	while snaps.size() > MAX_SNAPSHOTS:
		DirAccess.remove_absolute(RECOVERY_DIR.path_join(snaps.pop_front()))
