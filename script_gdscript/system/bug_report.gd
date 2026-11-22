# =============================================================================
# RUTA: res://script_gdscript/system/bug_report.gd
# INFORMES DE ERROR (USR-35/36/37). Decidido: el informe NO se envía solo.
#   · `capture()` lo llama el Logger de ErrorHandler con cada error de la app
#     (traza, archivo:línea); se guardan los últimos.
#   · `build()` arma el informe determinante: versión, sistema, modo de la
#     interfaz, renderizador, errores recientes con su traza y la cola del
#     registro (log).
#   · `save_local()` lo deja en user://bug_reports/ (siempre).
#   · `issue_url()` abre un issue de GitHub PRE-RELLENADO en el navegador: el
#     usuario lo revisa y lo envía él (sin servidor, sin datos a escondidas).
#     La marca <!-- vectopen-report … --> la usa la Action que lo etiqueta
#     (.github/workflows/triage-reports.yml).
# =============================================================================
extends RefCounted

const REPO := "malabo1990/-Vectopen"
const DIR := "user://bug_reports"
const MAX_ERRORS := 30
const MAX_URL_BODY := 6000   # GitHub corta URLs muy largas
const KINDS := {"bug": "Error / fallo", "suggestion": "Sugerencia", "question": "Pregunta / otro"}

static var errors: Array = []        # [{time, text, where, trace}]
static var _mutex := Mutex.new()

## Registra un error (puede llegar desde cualquier hilo).
static func capture(text: String, where: String, trace: String) -> void:
	_mutex.lock()
	errors.append({"time": Time.get_datetime_string_from_system(false, true), "text": text, "where": where, "trace": trace})
	while errors.size() > MAX_ERRORS:
		errors.pop_front()
	_mutex.unlock()

static func recent_errors(n: int = 10) -> Array:
	_mutex.lock()
	var out := errors.slice(maxi(0, errors.size() - n))
	_mutex.unlock()
	return out

static func app_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "?"))

static func _ui_mode() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var g = tree.root.get_node_or_null("GlobalUI") if tree else null
	return g.get_ui_mode() if g and g.has_method("get_ui_mode") else "?"

static func _log_tail(lines: int = 60) -> String:
	var p := "user://logs/godot.log"
	if not FileAccess.file_exists(p):
		return ""
	var t := FileAccess.get_file_as_string(p).split("\n")
	return "\n".join(t.slice(maxi(0, t.size() - lines)))

## Informe completo (Markdown). `kind` ∈ KINDS, `message` = lo que escribe el
## usuario; `with_tech` = adjuntar los datos técnicos.
## Qué librerías nativas (Rust) han cargado: texto, importadores, vectorizador.
## Sin ellas Vectopen funciona con su versión GDScript, más lenta.
static func native_status() -> String:
	var parts: Array = []
	for pair in [["texto", "VectorRichText"], ["importadores", "VectopenIO"], ["vectorizador", "ImageVectorizer"]]:
		parts.append("%s %s" % [pair[0], "sí" if ClassDB.class_exists(pair[1]) else "no"])
	return ", ".join(parts)

static func build(kind: String, message: String, email: String = "", with_tech: bool = true) -> String:
	var t := "<!-- vectopen-report kind=%s version=%s os=%s -->\n" % [kind, app_version(), OS.get_name()]
	t += "## %s\n\n%s\n\n" % [KINDS.get(kind, "Informe"), message.strip_edges() if message.strip_edges() != "" else "_(sin descripción)_"]
	if email.strip_edges() != "":
		t += "**Contacto:** %s\n\n" % email.strip_edges()
	if not with_tech:
		return t
	t += "### Datos técnicos\n\n"
	t += "- Vectopen %s · Godot %s\n" % [app_version(), Engine.get_version_info().get("string", "?")]
	t += "- Sistema: %s %s · %s\n" % [OS.get_name(), OS.get_version(), Engine.get_architecture_name()]
	t += "- Interfaz: %s · renderizador: %s\n" % [_ui_mode(), RenderingServer.get_current_rendering_method()]
	t += "- Vídeo: %s\n" % RenderingServer.get_video_adapter_name()
	t += "- Librerías nativas: %s\n" % native_status()
	var errs := recent_errors(10)
	if not errs.is_empty():
		t += "\n### Errores recientes\n\n```\n"
		for e in errs:
			t += "[%s] %s\n    en %s\n" % [e["time"], e["text"], e["where"]]
			if String(e["trace"]) != "":
				t += "    " + String(e["trace"]).replace("\n", "\n    ") + "\n"
		t += "```\n"
	var tail := _log_tail()
	if tail != "":
		t += "\n<details><summary>Registro (últimas líneas)</summary>\n\n```\n%s\n```\n</details>\n" % tail
	return t

## Guarda el informe en user://bug_reports/<fecha>.md; devuelve la ruta.
static func save_local(report: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	var p := DIR.path_join("informe_%s.md" % stamp)
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(report)
		f.close()
	return p

## URL del issue pre-rellenado (el cuerpo se recorta si es muy largo; el
## informe entero queda en el archivo local).
static func issue_url(kind: String, title: String, report: String) -> String:
	var body := report
	if body.length() > MAX_URL_BODY:
		body = body.substr(0, MAX_URL_BODY) + "\n\n_(informe recortado: el completo está en user://bug_reports/)_"
	var labels: String = {"bug": "bug", "suggestion": "enhancement", "question": "question"}.get(kind, "")
	var t := title.strip_edges() if title.strip_edges() != "" else "[%s] %s" % [KINDS.get(kind, "Informe"), app_version()]
	var url := "https://github.com/%s/issues/new?title=%s&body=%s" % [REPO, t.uri_encode(), body.uri_encode()]
	if labels != "":
		url += "&labels=" + String(labels).uri_encode()
	return url
