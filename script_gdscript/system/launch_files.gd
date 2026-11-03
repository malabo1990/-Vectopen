# =============================================================================
# RUTA: res://script_gdscript/system/launch_files.gd
# Archivos con los que se abre Vectopen (doble clic, «Abrir con», arrastrar al
# icono, `vectopen dibujo.svg`): el sistema los pasa como argumentos y antes
# se ignoraban. Al terminar el arranque se abren: un .vtp como documento, el
# resto (SVG, EPS, AI, PDF, Affinity, imágenes…) importado en el documento.
# =============================================================================
class_name LaunchFiles
extends RefCounted

## Rutas de archivos que Vectopen sabe abrir, sacadas de los argumentos
## (se ignoran las opciones de Godot y lo que no existe). Admite file:// URI.
static func from_args(args: PackedStringArray, exists: Callable = Callable()) -> PackedStringArray:
	var out := PackedStringArray()
	var skip_next := false
	for a in args:
		if skip_next:
			skip_next = false
			continue
		if a.begins_with("-"):
			# Opciones de Godot con valor aparte (--path dir, -s script…).
			skip_next = a in ["--path", "-s", "--script", "--main-pack", "--screen", "--position", "--resolution", "--rendering-driver", "--display-driver", "--log-file"]
			continue
		var p := a
		if p.begins_with("file://"):
			p = p.trim_prefix("file://").uri_decode()
		if p.begins_with("res://") or p.ends_with(".gd") or p.ends_with(".godot") or p.ends_with(".pck"):
			continue
		if not (p.get_extension().to_lower() in ImportExportManagerScript.IMPORT_EXTS):
			continue
		var ok: bool = exists.call(p) if exists.is_valid() else FileAccess.file_exists(p)
		if ok and not (p in out):
			out.append(p)
	return out

const ImportExportManagerScript = preload("res://script_gdscript/system/ImportExportManager.gd")

## Abre los archivos del arranque. Un documento (.vtp) primero, luego lo demás
## importado en él. Devuelve cuántos se abrieron.
static func open_startup_files(tree: SceneTree) -> int:
	var files := from_args(OS.get_cmdline_args() + OS.get_cmdline_user_args())
	if files.is_empty():
		return 0
	var iem := tree.root.get_node_or_null("ImportExportManager")
	if iem == null:
		return 0
	var docs: Array = []
	var rest: Array = []
	for f in files:
		(docs if f.get_extension().to_lower() in ["vtp", "vtc", "vectopen"] else rest).append(f)
	var opened := 0
	if not docs.is_empty():
		iem.import_any(docs[0], null)
		opened += 1
		print("Vectopen: abierto desde el sistema: ", docs[0])
	for f in rest:
		var mgr := ArtboardManager.find(tree)
		var ab: Node2D = mgr.get_active_artboard() if mgr else null
		var res: Dictionary = iem.import_any(f, ab)
		if res.get("ok", false):
			opened += 1
			print("Vectopen: abierto desde el sistema: ", f)
		else:
			GlobalEvents.emit_safe("user_notice", "error", "No se pudo abrir «%s»: %s" % [f.get_file(), String(res.get("error", ""))])
	# Recién abierto desde el sistema: nada que guardar todavía.
	var sm := tree.root.get_node_or_null("SaveManager")
	if sm and docs.is_empty() and not rest.is_empty():
		sm.is_modified = false
	return opened
