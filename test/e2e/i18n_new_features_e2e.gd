## E2E idiomas de las funciones nuevas (0.2.4-beta): iluminación, fusión,
## contenedor, componentes, esquinas, contacto, páginas maestras y menús.
## En cada idioma, cada texto nuevo tiene traducción (no se queda en
## español) y los paneles se ven traducidos (capturas en user://i18n_new/).
extends SceneTree

var K
var api
const KEYS := ["Iluminación", "TIPO DE LUZ", "Proyectar sombras", "Fusión", "Pasos fijos", "Orientar con la guía",
	"Contenedor", "Separación", "Margen interior", "Tamaño automático", "Quitar contenedor", "COMPONENTES",
	"Colocar una copia", "Tipo de esquina", "Redondeado inverso", "Dientes de sierra", "Contactar con el técnico",
	"PÁGINA MAESTRA", "Crear fusión (Blend)", "Convertir en contenedor (Auto Layout)", "Pieza de esquina",
	"Altura de la luz", "Colores del documento"]

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://i18n_new")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(800, 500), "Idiomas", Color.WHITE)
	await K.look_at(ab)
	var L = api.add_light(Vector2(300, 250), "spot", {})
	for loc in ["en", "fr", "de", "pt", "ru", "zh", "ja", "ar", "hi"]:
		TranslationServer.set_locale(loc)
		await K.frames(3)
		var missing: Array = []
		var tobj: Translation = TranslationServer.get_translation_object(loc)
		for k in KEYS:
			# en la tabla del idioma (en portugués «COMPONENTES» se escribe igual)
			if tobj == null or String(tobj.get_message(k)) == "":
				missing.append(k)
		K.check("%s: todos los textos nuevos traducidos" % loc, missing.is_empty(), ", ".join(missing))
	# capturas en inglés y japonés con el panel de Iluminación abierto
	for loc in ["en", "ja"]:
		TranslationServer.set_locale(loc)
		api.select([L])
		await K.frames(10)
		var pl: Control = null
		for c in root.find_children("light", "PanelContainer", true, false):
			if (c as Control).is_visible_in_tree():
				pl = c
		var txt := ""
		if pl:
			for l in pl.find_children("*", "Label", true, false):
				if (l as Label).text == "Iluminación":
					txt = (l as Label).atr((l as Label).text)
		K.check("%s: el panel Iluminación se ve traducido" % loc, txt != "" and txt != "Iluminación", txt)
		await K.shot("iluminacion_" + loc)
	TranslationServer.set_locale("es")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
