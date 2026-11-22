## E2E USR-35/36/37: un error de la app se captura (archivo:línea, traza) y
## sale un aviso con «Enviar a técnico»; el diálogo de contacto (motivo,
## email, texto, informe técnico) guarda el informe en user://bug_reports y
## prepara el issue de GitHub pre-rellenado (sin abrir el navegador aquí).
extends SceneTree

var K

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://bug_report")
	if not await K.boot("modern"):
		quit(1)
		return
	var BR = load("res://script_gdscript/system/bug_report.gd")
	var n0: int = BR.errors.size()
	push_error("Fallo de prueba USR-35")
	await K.frames(4)
	var got: Array = BR.errors.filter(func(e): return String(e["text"]).contains("Fallo de prueba USR-35"))
	K.check("el error se captura", got.size() == 1 and BR.errors.size() == n0 + 1)
	K.check("con su archivo:línea", got.size() == 1 and String(got[0]["where"]).contains("bug_report_e2e.gd:"), str(got))
	var un = root.get_node("UserNotices")
	K.check("sale un aviso de error", un.history.any(func(h): return String(h[1]).contains("enviar el informe")))
	# Diálogo de contacto
	var eh = root.get_node("ErrorHandler")
	var w: Window = eh.open_contact("suggestion")
	await K.frames(4)
	K.check("se abre el diálogo de contacto", w != null and w.visible)
	w.dry_run = true
	K.check("con el motivo pedido (sugerencia)", w.kind() == "suggestion")
	w._text.text = "Me gustaría poder\nexportar en AVIF."
	w._text.text_changed.emit()
	w._email.text = "prueba@example.com"
	w._email.text_changed.emit(w._email.text)
	var r: String = w.report()
	K.check("el informe lleva el texto de varias líneas y el email", r.contains("exportar en AVIF") and r.contains("prueba@example.com"))
	K.check("y los datos técnicos (versión, sistema, errores)", r.contains("Vectopen " + BR.app_version()) and r.contains(OS.get_name()) and r.contains("Fallo de prueba USR-35"))
	K.check("con la marca para la Action", r.contains("<!-- vectopen-report kind=suggestion"))
	w._tech.button_pressed = false
	w._tech.toggled.emit(false)
	K.check("sin informe técnico si se desmarca", not w.report().contains("Datos técnicos"))
	w._tech.button_pressed = true
	w.send()
	K.check("guarda una copia en user://bug_reports", w.last_saved.begins_with("user://bug_reports/") and FileAccess.file_exists(w.last_saved))
	K.check("issue de GitHub pre-rellenado", w.last_url.begins_with("https://github.com/malabo1990/-Vectopen/issues/new?title=") and w.last_url.contains("labels=enhancement") and w.last_url.length() < 9000, w.last_url.substr(0, 120))
	await K.shot("contacto")
	w.queue_free()
	# El botón del panel Acerca de
	var found := false
	for n in root.find_children("Contact", "Button", true, false):
		found = true
	K.check("Acerca de tiene «Contactar / informar de un error»", found or ResourceLoader.exists("res://script_gdscript/ui/about_panel.gd"))
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
