# =============================================================================
# RUTA: res://script_gdscript/system/default_app.gd
# «Hacer Vectopen la app predeterminada» (Ajustes ▸ Archivos): que el doble
# clic en un .vtp, .svg, .eps, .ai o Affinity abra Vectopen y que salga el
# PRIMERO en «Abrir con» (por encima de Inkscape y los demás).
#   · Linux: registra el lanzador y los tipos de archivo del usuario
#     (~/.local/share) y los asocia con xdg-mime (vale para KDE, GNOME, XFCE…).
#   · Windows: registra Vectopen en «Abrir con» (HKCU) y lo pone para .vtp.
#     Windows no deja que una app se imponga para .svg/.pdf: se elige una vez
#     en «Abrir con ▸ Elegir otra aplicación ▸ Vectopen ▸ Siempre».
#   · macOS: los tipos van en el Info.plist; se elige en Finder ▸ Obtener
#     información ▸ Abrir con ▸ Cambiar todo.
# PDF e imágenes no se cambian por defecto (el visor de PDF / fotos del
# usuario sigue igual); Vectopen sí aparece en su «Abrir con».
# =============================================================================
class_name DefaultApp
extends RefCounted

## Tipos que Vectopen pasa a abrir por defecto.
const DEFAULT_MIMES := ["application/x-vectopen", "image/svg+xml", "image/svg+xml-compressed",
	"application/postscript", "image/x-eps", "application/eps", "application/illustrator",
	"application/x-affinity-designer", "application/x-affinity-photo", "application/x-affinity-publisher"]
## Además aparece en «Abrir con» de estos.
const OPEN_WITH_MIMES := ["application/pdf", "image/png", "image/jpeg", "image/webp"]
const WIN_EXTS := [".vtp", ".vtc", ".svg", ".svgz", ".eps", ".ai", ".ps", ".pdf", ".afdesign", ".afphoto", ".afpub", ".af", ".png", ".jpg", ".jpeg", ".webp"]
const PROG_ID := "Vectopen.Document"

const MIME_XML := """<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-vectopen">
    <comment>Vectopen project</comment>
    <comment xml:lang="es">Proyecto de Vectopen</comment>
    <icon name="vectopen"/>
    <glob pattern="*.vtp"/>
    <glob pattern="*.vtc"/>
  </mime-type>
  <mime-type type="application/x-affinity-designer"><comment>Affinity Designer document</comment><glob pattern="*.afdesign"/><glob pattern="*.af"/></mime-type>
  <mime-type type="application/x-affinity-photo"><comment>Affinity Photo document</comment><glob pattern="*.afphoto"/></mime-type>
  <mime-type type="application/x-affinity-publisher"><comment>Affinity Publisher document</comment><glob pattern="*.afpub"/></mime-type>
</mime-info>
"""

## Texto del lanzador .desktop para `exe` (ruta del ejecutable o AppImage).
static func desktop_entry(exe: String) -> String:
	return "\n".join(PackedStringArray([
		"[Desktop Entry]", "Type=Application", "Name=Vectopen", "GenericName=Editor vectorial",
		"Comment=Editor de gráficos vectoriales",
		"Exec=\"%s\" %%F" % exe, "Icon=vectopen", "Terminal=false",
		"Categories=Graphics;VectorGraphics;", "StartupWMClass=Vectopen",
		"MimeType=" + ";".join(PackedStringArray(DEFAULT_MIMES + OPEN_WITH_MIMES)) + ";",
		"InitialPreference=9", ""]))

## Hace Vectopen la app predeterminada. {ok, message}.
static func make_default() -> Dictionary:
	match OS.get_name():
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return _linux()
		"Windows":
			return _windows()
		"macOS":
			return {"ok": false, "message": TranslationServer.translate("En macOS: clic derecho en un archivo ▸ Obtener información ▸ Abrir con ▸ Vectopen ▸ Cambiar todo.")}
	return {"ok": false, "message": TranslationServer.translate("Este sistema no permite cambiar la app predeterminada desde Vectopen.")}

static func _linux() -> Dictionary:
	var home := OS.get_environment("HOME")
	if home == "":
		return {"ok": false, "message": "HOME"}
	var data := OS.get_environment("XDG_DATA_HOME")
	if data == "":
		data = home.path_join(".local/share")
	var desktop_name := "vectopen.desktop"
	# Instalado con el paquete (.deb / .rpm): ya hay lanzador del sistema.
	if not FileAccess.file_exists("/usr/share/applications/vectopen.desktop"):
		var exe := OS.get_environment("APPIMAGE")
		if exe == "":
			exe = OS.get_executable_path()
		var apps := data.path_join("applications")
		DirAccess.make_dir_recursive_absolute(apps)
		var f := FileAccess.open(apps.path_join(desktop_name), FileAccess.WRITE)
		if f == null:
			return {"ok": false, "message": TranslationServer.translate("No se pudo escribir el lanzador de Vectopen.")}
		f.store_string(desktop_entry(exe))
		f.close()
		_write_icon(data.path_join("icons/hicolor/256x256/apps/vectopen.png"))
		OS.execute("update-desktop-database", [apps])
	var mime := data.path_join("mime")
	DirAccess.make_dir_recursive_absolute(mime.path_join("packages"))
	var mf := FileAccess.open(mime.path_join("packages/vectopen.xml"), FileAccess.WRITE)
	if mf:
		mf.store_string(MIME_XML)
		mf.close()
		OS.execute("update-mime-database", [mime])
	var out: Array = []
	var code := OS.execute("xdg-mime", PackedStringArray(["default", desktop_name] + DEFAULT_MIMES), out, true)
	if code != 0:
		return {"ok": false, "message": TranslationServer.translate("No se pudo asociar los archivos (falta xdg-mime).")}
	return {"ok": true, "message": TranslationServer.translate("Listo: los .vtp, SVG, EPS, AI y Affinity se abren con Vectopen al hacer doble clic, y Vectopen sale el primero en «Abrir con».")}

static func _write_icon(path: String) -> void:
	if FileAccess.file_exists(path):
		return
	var tex := load("res://icon/app/vectopen_app_icon.png") as Texture2D
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)

## Órdenes de registro de Windows (separadas para poder probarlas).
static func windows_commands(exe: String) -> Array:
	var base := "HKCU\\Software\\Classes\\"
	var cmds: Array = [
		["add", base + PROG_ID, "/ve", "/d", "Vectopen", "/f"],
		["add", base + PROG_ID + "\\DefaultIcon", "/ve", "/d", "\"%s\",0" % exe, "/f"],
		["add", base + PROG_ID + "\\shell\\open\\command", "/ve", "/d", "\"%s\" \"%%1\"" % exe, "/f"],
		["add", base + "Applications\\" + exe.get_file() + "\\shell\\open\\command", "/ve", "/d", "\"%s\" \"%%1\"" % exe, "/f"],
	]
	for ext in WIN_EXTS:
		cmds.append(["add", base + ext + "\\OpenWithProgids", "/v", PROG_ID, "/t", "REG_NONE", "/f"])
		cmds.append(["add", base + "Applications\\" + exe.get_file() + "\\SupportedTypes", "/v", ext, "/t", "REG_SZ", "/d", "", "/f"])
	# Los documentos propios sí se abren por defecto con Vectopen.
	for ext in [".vtp", ".vtc"]:
		cmds.append(["add", base + ext, "/ve", "/d", PROG_ID, "/f"])
	return cmds

static func _windows() -> Dictionary:
	var exe := OS.get_executable_path().replace("/", "\\")
	for c in windows_commands(exe):
		if OS.execute("reg", PackedStringArray(c)) != 0:
			return {"ok": false, "message": TranslationServer.translate("No se pudo registrar Vectopen en Windows.")}
	return {"ok": true, "message": TranslationServer.translate("Vectopen ya está en «Abrir con». Para que el doble clic en SVG o PDF lo abra siempre: Abrir con ▸ Elegir otra aplicación ▸ Vectopen ▸ Siempre.")}
