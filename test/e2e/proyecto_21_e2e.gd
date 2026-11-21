# =============================================================================
# FASE B · ENCARGO 21 — Póster tipográfico (modo Pro)
# Foco: solo texto, interlineado, tracking.
# Póster 1000 × 1414 solo con tipografía: titular enorme con tracking negativo
# y otro con tracking abierto, texto girado 90°, bloque justificado en dos
# columnas con interlineado amplio, cifras grandes con rampa de tracking,
# un titular convertido a curvas. Medir que el tracking cambia el ANCHO, el
# interlineado el ALTO, la justificación, deshacer, exportar SVG con el texto
# en curvas y PDF, reabrir sin cambios de medida.
#   test/run_e2e.sh proyecto_21_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/21"
const INK := Color("#111111")
const RED := Color("#e63946")
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func w(n: Node) -> float:
	return K.ic._mt._global_rect(n).size.x

func h(n: Node) -> float:
	return float(api.get_prop(n, "height"))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("professional"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(1000, 1414), "Póster", Color("#f1faee"))
	# Titular con tracking
	var big = api.add_text(Vector2(60, 80), "TIPOS", 260, INK)
	big.name = "Titular"
	api.set_prop(big, "font_weight", 900)
	await K.frames(6)
	var w0 := w(big)
	api.set_prop(big, "letter_spacing", -12.0)
	await K.frames(6)
	var w1 := w(big)
	K.check("tracking negativo estrecha el titular", w1 < w0 - 20.0, "%.0f → %.0f" % [w0, w1])
	var open = api.add_text(Vector2(70, 400), "MÓVILES", 60, RED)
	open.name = "Subtítulo"
	await K.frames(4)
	var wo0 := w(open)
	api.set_prop(open, "letter_spacing", 24.0)
	await K.frames(6)
	K.check("tracking abierto ensancha el subtítulo", w(open) > wo0 + 100.0, "%.0f → %.0f" % [wo0, w(open)])
	api.undo()
	await K.frames(4)
	K.check("deshacer el tracking", absf(w(open) - wo0) < 2.0, "%.0f vs %.0f" % [w(open), wo0])
	api.redo()
	# Texto girado 90°
	var side = api.add_text(Vector2(900, 700), "EDICIÓN 2026", 36, INK)
	side.name = "Lateral"
	api.set_prop(side, "rotation", 90.0)
	await K.frames(4)
	K.check("texto girado 90°", is_equal_approx(float(api.get_prop(side, "rotation")), 90.0) and absf(side.global_rotation - PI / 2.0) < 0.01, str(api.get_prop(side, "rotation")))
	# Bloque en dos columnas, justificado, con interlineado
	var body_txt := "La tipografía es la voz visible del lenguaje. Cada letra lleva un ritmo, cada espacio una pausa. ".repeat(6)
	var body = api.add_text_box(Rect2(60, 560, 760, 300), body_txt, 18, INK, 2, 40.0, "Cuerpo")
	await K.frames(10)
	var hb0 := h(body)
	api.set_prop(body, "line_spacing", 14)
	await K.frames(10)
	var hb1 := h(body)
	K.check("más interlineado = bloque más alto", hb1 > hb0 + 20.0, "%.0f → %.0f" % [hb0, hb1])
	api.set_prop(body, "text_align", "fill")
	await K.frames(4)
	K.check("bloque justificado", String(api.get_prop(body, "text_align")) == "fill")
	K.check("en dos columnas", int(api.get_prop(body, "columns")) == 2)
	K.check("columnas equilibradas: el marco no mide más que media columna única", hb1 < 600.0, "%.0f" % hb1)
	# Cifras con rampa de tracking (letras avanzadas)
	var nums = api.add_text(Vector2(60, 1000), "2026", 220, RED)
	nums.name = "Cifras"
	api.set_prop(nums, "font_weight", 800)
	await K.frames(4)
	var wn0 := w(nums)
	api.set_prop(nums, "letter_tracking_ramp", {"start": 0.0, "end": 40.0})
	await K.frames(8)
	var ramp = api.get_prop(nums, "letter_tracking_ramp")
	K.check("rampa de tracking en las cifras (ensancha)", ramp is Dictionary and float(ramp.get("end", 0.0)) == 40.0 and w(nums) > wn0 + 30.0, "%s · %.0f → %.0f" % [str(ramp), wn0, w(nums)])
	# Un titular convertido a curvas
	var cred = api.add_text(Vector2(60, 1300), "VECTOPEN · MALABO", 40, INK)
	cred.name = "Créditos"
	await K.frames(4)
	var curves = api.text_to_curves(cred)
	K.check("créditos convertidos a curvas (grupo de letras)", curves != null and curves.get_child_count() >= 14, str(curves.get_child_count()) if curves else "-")
	await K.look_at(ab)
	await K.shot("01_poster")
	var w_before := {"Titular": w(big), "Cuerpo": h(body)}
	await K.undo_redo(20)
	# Exportar: SVG con texto en curvas y PDF
	var svg_p := ProjectSettings.globalize_path(OUT.path_join("poster_curvas.svg"))
	var ok: bool = await api.export(svg_p, ab, {"text_curves": true})
	var svg := FileAccess.get_file_as_string(svg_p) if ok else ""
	K.check("SVG con el texto en curvas (sin <text>)", ok and not svg.contains("<text") and svg.count("<path") >= 20, "%d paths" % svg.count("<path"))
	var ex: Dictionary = await K.export_all(ab, "poster")
	var abs: Array = await K.save_reload("poster")
	for a in abs:
		if String(a.name) == "Póster":
			var t2: Node = a.find_child("Titular", true, false)
			var b2: Node = a.find_child("Cuerpo", true, false)
			await K.frames(10)
			K.check("reabrir: el titular mide lo mismo (tracking)", t2 != null and absf(w(t2) - float(w_before["Titular"])) < 3.0, "%.0f vs %.0f" % [w(t2) if t2 else -1.0, w_before["Titular"]])
			K.check("reabrir: el bloque mide lo mismo (interlineado)", b2 != null and absf(h(b2) - float(w_before["Cuerpo"])) < 3.0, "%.0f vs %.0f" % [h(b2) if b2 else -1.0, w_before["Cuerpo"]])
			K.check("reabrir: justificado y en dos columnas", b2 != null and String(api.get_prop(b2, "text_align")) == "fill" and int(api.get_prop(b2, "columns")) == 2)
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
