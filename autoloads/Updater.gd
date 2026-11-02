# =============================================================================
# RUTA: res://autoloads/Updater.gd
# Actualizaciones desde GitHub Releases (malabo1990/-Vectopen).
#
# · Al arrancar (como mucho una vez al día) mira la última release publicada.
#   Si es más nueva que la versión instalada, avisa (cápsula de UserNotices) y
#   emite `update_available`; la ventana del logo enseña «Descargar e instalar».
# · `download_and_install()` baja el paquete de ESTE sistema y lo instala:
#     Linux RPM (/opt/vectopen) → pkexec dnf install · Linux DEB → pkexec apt
#     Windows / macOS / tar.gz  → abre el archivo descargado (instalador, .dmg
#     o carpeta), que el usuario termina con un doble clic.
# · Preferencias en user://updates.cfg: comprobar al arrancar (sí/no).
# Las releases las publica el GitHub Action «Release» al subir una etiqueta v*.
# =============================================================================
extends Node

signal update_available(info: Dictionary)
signal check_finished(info: Dictionary)          # {} = no hay nada nuevo / error
signal download_progress(done: int, total: int)
signal download_finished(path: String)
signal install_finished(ok: bool, message: String)

const REPO := "malabo1990/-Vectopen"
const API_URL := "https://api.github.com/repos/%s/releases?per_page=10" % REPO
const RELEASES_URL := "https://github.com/%s/releases" % REPO
const CFG := "user://updates.cfg"
const CHECK_EVERY_S := 24 * 3600

## Última release más nueva que la instalada ({} si no hay).
var latest: Dictionary = {}
var checking := false
var downloading := false
var _http: HTTPRequest

func _ready() -> void:
	if OS.has_feature("editor") or DisplayServer.get_name() == "headless" or OS.has_environment("VECTOPEN_NO_UPDATE_CHECK"):
		return
	if auto_check_enabled() and Time.get_unix_time_from_system() - _cfg_get("last_check", 0.0) > CHECK_EVERY_S:
		get_tree().create_timer(8.0).timeout.connect(func() -> void: check(false))

# ── versión ──────────────────────────────────────────────────────────────────
static func current_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))

## Compara versiones tipo «v0.2.1», «0.2.0-alpha». >0 si a es más nueva.
## Una versión final gana a su preversión (0.2.0 > 0.2.0-alpha).
static func compare_versions(a: String, b: String) -> int:
	var pa := _parse(a)
	var pb := _parse(b)
	for i in 3:
		if pa[i] != pb[i]:
			return 1 if pa[i] > pb[i] else -1
	var ra: String = pa[3]
	var rb: String = pb[3]
	if ra == rb:
		return 0
	if ra == "":
		return 1
	if rb == "":
		return -1
	return 1 if ra > rb else -1

static func _parse(v: String) -> Array:
	var s := v.strip_edges().trim_prefix("v").trim_prefix("V")
	var pre := ""
	var dash := s.find("-")
	if dash >= 0:
		pre = s.substr(dash + 1)
		s = s.substr(0, dash)
	var nums := s.split(".")
	var out := [0, 0, 0, pre]
	for i in mini(3, nums.size()):
		out[i] = int(nums[i])
	return out

# ── comprobar ────────────────────────────────────────────────────────────────
func auto_check_enabled() -> bool:
	return bool(_cfg_get("auto_check", true))

func set_auto_check(on: bool) -> void:
	_cfg_set("auto_check", on)

## Pide la lista de releases. `manual`: el usuario pulsó «Buscar» (avisa
## también cuando no hay novedades).
func check(manual: bool = true) -> void:
	if checking:
		return
	checking = true
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		checking = false
		_cfg_set("last_check", Time.get_unix_time_from_system())
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			if manual:
				_notice("warning", tr("No se pudo consultar GitHub (sin conexión o límite de peticiones)."))
			check_finished.emit({})
			return
		var info := pick_update(JSON.parse_string(body.get_string_from_utf8()), current_version())
		latest = info
		if info.is_empty():
			if manual:
				_notice("success", tr("Vectopen está al día (%s).") % current_version())
		else:
			_notice("info", tr("Hay una versión nueva: %s. Ábrela desde el logo de Vectopen.") % info["version"])
			update_available.emit(info)
		check_finished.emit(info))
	var err := http.request(API_URL, ["Accept: application/vnd.github+json", "User-Agent: Vectopen/" + current_version()])
	if err != OK:
		http.queue_free()
		checking = false
		check_finished.emit({})

## De la respuesta de la API, la release publicada más nueva que `installed`
## (ignora borradores). {} si no hay ninguna. Público para las pruebas.
static func pick_update(releases: Variant, installed: String) -> Dictionary:
	if not (releases is Array):
		return {}
	var best: Dictionary = {}
	for r in releases:
		if not (r is Dictionary) or bool(r.get("draft", false)):
			continue
		var tag := String(r.get("tag_name", ""))
		if tag == "" or compare_versions(tag, installed) <= 0:
			continue
		if best.is_empty() or compare_versions(tag, best["version"]) > 0:
			var assets: Array = []
			for a in r.get("assets", []):
				assets.append({"name": String(a.get("name", "")), "url": String(a.get("browser_download_url", "")),
					"size": int(a.get("size", 0))})
			best = {"version": tag.trim_prefix("v"), "tag": tag, "name": String(r.get("name", tag)),
				"notes": String(r.get("body", "")), "page": String(r.get("html_url", RELEASES_URL)), "assets": assets}
	return best

# ── descargar e instalar ─────────────────────────────────────────────────────
## Cómo se instala en este sistema: "rpm", "deb", "windows", "macos" o "tar".
static func install_kind() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "macos"
		"Linux", "FreeBSD":
			var exe := OS.get_executable_path()
			if exe.begins_with("/opt/vectopen") or exe.begins_with("/usr/"):
				if FileAccess.file_exists("/usr/bin/rpm") and FileAccess.file_exists("/usr/bin/dnf"):
					return "rpm"
				if FileAccess.file_exists("/usr/bin/dpkg"):
					return "deb"
			return "tar"
	return "tar"

## El archivo de la release que toca para `kind` (o {} si no hay).
static func asset_for(assets: Array, kind: String) -> Dictionary:
	var want := {"rpm": [".rpm"], "deb": [".deb"], "windows": ["windows", ".exe", ".zip"],
		"macos": [".dmg", "macos"], "tar": ["linux", ".tar.gz"]}
	for pattern in want.get(kind, []):
		for a in assets:
			var n := String(a["name"]).to_lower()
			if n.ends_with(".txt") or n.ends_with(".sha256"):
				continue
			if kind == "rpm" and not n.ends_with(".rpm"):
				continue
			if kind == "deb" and not n.ends_with(".deb"):
				continue
			if kind == "tar" and not (n.contains("linux") and n.ends_with(".tar.gz")):
				continue
			if n.contains(pattern):
				return a
	return {}

func download_and_install(info: Dictionary = latest) -> void:
	if downloading or info.is_empty():
		return
	var kind := install_kind()
	var asset := asset_for(info.get("assets", []), kind)
	if asset.is_empty():
		OS.shell_open(String(info.get("page", RELEASES_URL)))
		install_finished.emit(false, tr("No hay paquete para este sistema: se abre la página de descargas."))
		return
	download(asset, func(path: String) -> void: _install(path, kind))

## Descarga `asset` en user://updates/ (con progreso) y llama a `then(ruta)`.
## Emite `download_finished` (ruta vacía si falla).
func download(asset: Dictionary, then: Callable = Callable()) -> void:
	if downloading:
		return
	var dir := OS.get_user_data_dir().path_join("updates")
	DirAccess.make_dir_recursive_absolute(dir)
	var dest := dir.path_join(String(asset["name"]))
	downloading = true
	_http = HTTPRequest.new()
	_http.download_file = dest
	_http.use_threads = true
	_http.max_redirects = 10   # GitHub redirige a su CDN
	add_child(_http)
	var total := int(asset.get("size", 0))
	var timer := Timer.new()
	timer.wait_time = 0.25
	add_child(timer)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(_http):
			download_progress.emit(_http.get_downloaded_bytes(), maxi(total, _http.get_body_size())))
	timer.start()
	_http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		timer.queue_free()
		_http.queue_free()
		downloading = false
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			install_finished.emit(false, tr("La descarga falló (%d).") % code)
			download_finished.emit("")
			return
		download_progress.emit(total, total)
		download_finished.emit(dest)
		if then.is_valid():
			then.call(dest))
	if _http.request(String(asset["url"]), ["User-Agent: Vectopen/" + current_version()]) != OK:
		downloading = false
		install_finished.emit(false, tr("No se pudo iniciar la descarga."))
		download_finished.emit("")

func _install(file: String, kind: String) -> void:
	match kind:
		"rpm", "deb":
			# pkexec muestra la ventana de contraseña del sistema. Hilo aparte:
			# la interfaz no se congela mientras el usuario la escribe.
			var args := ["dnf", "install", "-y", file] if kind == "rpm" else ["apt-get", "install", "-y", file]
			var th := Thread.new()
			th.start(func() -> int: return OS.execute("pkexec", args))
			while th.is_alive():
				await get_tree().create_timer(0.3).timeout
			var code: int = th.wait_to_finish()
			if code == 0:
				install_finished.emit(true, tr("Actualización instalada. Reinicia Vectopen para usarla."))
			else:
				OS.shell_show_in_file_manager(file)
				install_finished.emit(false, tr("No se instaló (¿contraseña cancelada?). El paquete está en la carpeta que se ha abierto."))
		_:
			if kind == "tar":
				OS.shell_show_in_file_manager(file)
			else:
				OS.shell_open(file)
			install_finished.emit(true, tr("Descargado. Termina la instalación en la ventana que se ha abierto."))

## Reinicia la app (tras instalar).
func restart() -> void:
	OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
	get_tree().quit()

# ── preferencias ─────────────────────────────────────────────────────────────
func _cfg_get(k: String, def: Variant) -> Variant:
	var c := ConfigFile.new()
	return c.get_value("updates", k, def) if c.load(CFG) == OK else def

func _cfg_set(k: String, v: Variant) -> void:
	var c := ConfigFile.new()
	c.load(CFG)
	c.set_value("updates", k, v)
	c.save(CFG)

func _notice(level: String, msg: String) -> void:
	var un := get_node_or_null("/root/UserNotices")
	if un and un.has_method("show_notice"):
		un.show_notice(level, msg)
