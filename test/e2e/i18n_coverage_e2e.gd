# =============================================================================
# Traducción de la interfaz en todos los idiomas.
# Para cada idioma: abre Smart con el panel de pincel y Ajustes visibles, y
# Modern y Pro con el inspector; cuenta las etiquetas/botones VISIBLES cuyo
# texto sigue en español (palabras con tilde/ñ o vocabulario español típico)
# y guarda capturas en user://i18n/.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/i18n_coverage_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://i18n"
const LOCALES := ["en", "fr", "de", "pt", "ru", "zh", "ja", "ar", "hi"]
## Palabras que delatan un texto sin traducir (español).
const SPANISH := ["Grosor", "Opacidad", "Suavizado", "Presión", "Estilos de pincel", "Lápiz", "Pincel y estilos",
	"Restablecer", "Capas", "Páginas", "Recursos", "Relleno", "Trazo", "Buscar", "Guardar", "Exportar", "Alinear",
	"Sin selección", "Tamaños", "Página", "Estabilizar", "Curva", "Equilibrado"]

var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(280.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

## En portugués estas palabras se escriben igual (o empiezan igual) que en español.
const SAME_IN_PT := ["Páginas", "Página", "Recursos", "Curva", "Equilibrado", "Estabilizar", "Estilos de pincel", "Exportar", "Opacidad", "Buscar", "Alinear"]

## Textos visibles que siguen en español.
func spanish_left(loc: String = "") -> Array:
	var out: Array = []
	for n in root.find_children("*", "", true, false):
		if not (n is Label or n is Button) or not (n as Control).is_visible_in_tree():
			continue
		var t := String(n.get("text")).strip_edges()
		if t == "" or n.get("auto_translate_mode") == Node.AUTO_TRANSLATE_MODE_DISABLED:
			continue
		var shown := (n as Control).atr(t) if n.can_auto_translate() else t
		if shown.ends_with(" capas") and loc != "es" and loc != "pt":
			out.append(shown)
			continue
		for w in SPANISH:
			if loc == "pt" and w in SAME_IN_PT:
				continue
			if shown.begins_with(w) or shown == w:
				out.append(shown)
				break
	return out

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var lm = root.get_node("LanguageManager")
	var tm = root.get_node("ToolManager")
	for loc in LOCALES:
		lm.set_locale(loc, false)
		await frames(10)
		check("%s: el idioma está cargado" % loc, TranslationServer.translate("Grosor") != "Grosor" or loc == "es", TranslationServer.translate("Grosor"))
		# Smart: pincel + Ajustes.
		root.get_node("GlobalUI").set_ui_mode("smart")
		await frames(20)
		tm.switch_tool("brush", true)
		await frames(10)
		for n in root.find_children("brush", "Control", true, false):
			(n as Control).visible = true
		for n in root.find_children("ThemeConfigPanel", "Control", true, false):
			(n as Control).visible = true
		await frames(10)
		var left := spanish_left(loc)
		check("%s · Smart: sin textos en español a la vista" % loc, left.is_empty(), ", ".join(left.slice(0, 12)))
		await shot("%s_smart" % loc)
		for n in root.find_children("ThemeConfigPanel", "Control", true, false):
			(n as Control).visible = false
		for mode in ["modern", "professional"]:
			root.get_node("GlobalUI").set_ui_mode(mode)
			await frames(25)
			left = spanish_left(loc)
			check("%s · %s: sin textos en español a la vista" % [loc, mode], left.is_empty(), ", ".join(left.slice(0, 12)))
			await shot("%s_%s" % [loc, mode])
	lm.set_locale("es", false)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
