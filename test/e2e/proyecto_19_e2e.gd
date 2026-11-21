# =============================================================================
# FASE B · ENCARGO 19 — Menú de restaurante (modo Smart)
# Foco: párrafos, estilos, exportar PDF.
# Carta A4 de dos páginas (Comida + Bebidas): título, secciones, platos con
# descripción (marcos de párrafo) y precio alineado a la derecha, línea de
# puntos entre plato y precio, estilos de texto con nombre (Sección, Plato,
# Descripción, Precio). Redefinir «Plato» cambia todos los platos; exportar
# las DOS páginas en un solo PDF A4 desde el panel Exportar; reabrir.
#   test/run_e2e.sh proyecto_19_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/19"
const A4 := Vector2(794, 1123)
const INK := Color("#2f2a24")
const ACCENT := Color("#9c2f1f")
var K
var api
var st := {}

func _init() -> void:
	_run.call_deferred()
	create_timer(500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func dish(y: float, name: String, desc: String, price: String) -> Array:
	var t = api.add_text(Vector2(80, y), name, 20, INK)
	t.name = "Plato %s" % name
	api.apply_text_style(st["plato"], [t])
	var p = api.add_text(Vector2(640, y), price, 20, INK)
	p.name = "Precio %s" % name
	api.apply_text_style(st["precio"], [p])
	var tr: Rect2 = K.ic._mt._global_rect(t)
	var pr: Rect2 = K.ic._mt._global_rect(p)
	var ab: Node2D = api.artboard()
	var lead = api.add_path(PackedVector2Array([ab.to_local(Vector2(tr.end.x + 8, tr.end.y - 6)), ab.to_local(Vector2(pr.position.x - 8, tr.end.y - 6))]), false, "Puntos")
	api.set_props(lead, {"stroke_color": Color(INK, 0.5), "stroke_width": 1.5, "stroke_style": 2, "stroke_dash_gap": 4.0})
	var d = api.add_text_box(Rect2(80, y + 30, 520, 44), desc, 13, INK)
	d.name = "Desc %s" % name
	api.apply_text_style(st["desc"], [d])
	return [t, p, lead, d]

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("smart"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	st["seccion"] = api.add_text_style("Sección", {"font_size": 30, "font_weight": 700, "fill_color": ACCENT, "letter_spacing": 2.0})
	st["plato"] = api.add_text_style("Plato", {"font_size": 20, "font_weight": 600, "fill_color": INK})
	st["desc"] = api.add_text_style("Descripción", {"font_size": 13, "font_italic": true, "fill_color": Color("#6b6259"), "line_spacing": 2})
	st["precio"] = api.add_text_style("Precio", {"font_size": 20, "font_weight": 600, "fill_color": INK, "text_align": "right"})
	K.check("4 estilos de texto con nombre", api.text_styles().size() == 4)
	# ── Página 1: comida ─────────────────────────────────────────────────────
	var p1: Node2D = await K.artboard(A4, "Carta", Color("#fbf7f0"))
	var title = api.add_text(Vector2(220, 60), "Casa Malabo", 54, ACCENT)
	title.name = "Título"
	api.set_prop(title, "font_weight", 800)
	var all_dishes: Array = []
	var y := 170.0
	for sec in [["Entrantes", [["Croquetas de yuca", "Yuca, queso fresco y alioli de cilantro.", "8,50 €"], ["Ensalada de mango", "Mango, aguacate, cebolla roja y lima.", "9,00 €"]]],
			["Principales", [["Pescado a la brasa", "Capitán del día con plátano maduro y salsa de tomate.", "18,00 €"], ["Pollo en salsa de cacahuete", "Receta de la abuela, con arroz blanco.", "15,50 €"], ["Ndolé vegetal", "Hojas amargas, cacahuete y gambas opcionales.", "14,00 €"]]],
			["Postres", [["Bizcocho de coco", "Con crema de vainilla de Bioko.", "6,00 €"]]]]:
		var s = api.add_text(Vector2(80, y), sec[0], 30, ACCENT)
		s.name = "Sección %s" % sec[0]
		api.apply_text_style(st["seccion"], [s])
		y += 60
		for dd in sec[1]:
			all_dishes.append(dish(y, dd[0], dd[1], dd[2]))
			y += 100
		y += 20
	K.check("platos con su estilo", all_dishes.all(func(e) -> bool: return api.text_style_of(e[0]) == st["plato"] and api.text_style_of(e[3]) == st["desc"]))
	var prices_right: bool = all_dishes.all(func(e) -> bool: return String(api.get_prop(e[1], "text_align")) == "right")
	K.check("precios alineados a la derecha (estilo Precio)", prices_right)
	var dots: bool = all_dishes.all(func(e) -> bool: return int(api.get_prop(e[2], "stroke_style")) == 2)
	K.check("línea de puntos entre plato y precio", dots)
	# Redefinir «Plato»: todos los platos cambian
	api.update_text_style(st["plato"], {"font_size": 22, "fill_color": Color("#3d2b1f")})
	K.check("redefinir «Plato» cambia los 6 platos",
		all_dishes.all(func(e) -> bool: return is_equal_approx(float(api.get_prop(e[0], "font_size")), 22.0)))
	K.check("y no toca precios ni descripciones",
		all_dishes.all(func(e) -> bool: return is_equal_approx(float(api.get_prop(e[1], "font_size")), 20.0) and is_equal_approx(float(api.get_prop(e[3], "font_size")), 13.0)))
	await K.look_at(p1)
	await K.frames(10)   # que el CullManager haga su barrido
	var doubled := []
	for c in p1.get_children():
		var dl = c.get_node_or_null("DisplayLabel")
		if dl and c.get_node_or_null("VectorRichText") and dl.is_visible_in_tree() and dl.self_modulate.a > 0.01:
			doubled.append(String(c.name))
	K.check("ningún texto pintado dos veces (VAL-49)", doubled.is_empty(), ", ".join(doubled))
	await K.shot("01_carta")
	# ── Página 2: bebidas, con los mismos estilos ────────────────────────────
	var p2: Node2D = await K.artboard(A4, "Bebidas", Color("#fbf7f0"))
	var s2 = api.add_text(Vector2(80, 80), "Bebidas", 30, ACCENT)
	api.apply_text_style(st["seccion"], [s2])
	var drinks: Array = []
	var y2 := 150.0
	for dd in [["Malta Guinness", "Fría, en botella.", "3,00 €"], ["Zumo de baobab", "Natural, sin azúcar añadido.", "4,50 €"], ["Café de Bioko", "Tostado artesanal.", "2,50 €"]]:
		drinks.append(dish(y2, dd[0], dd[1], dd[2]))
		y2 += 100
	K.check("segunda página con los mismos estilos", drinks.all(func(e) -> bool: return is_equal_approx(float(api.get_prop(e[0], "font_size")), 22.0)))
	await K.look_at(p2)
	await K.shot("02_bebidas")
	await K.undo_redo(20)
	# ── PDF de las dos páginas desde el panel Exportar ───────────────────────
	var panel: Node = null
	for n in root.find_children("*", "", true, false):
		if n.has_method("export_pages_pdf"):
			panel = n
			break
	K.check("el panel Exportar ofrece «PDF de todas las páginas»", panel != null and panel.find_child("ExportPagesPdf", true, false) != null)
	if panel:
		panel.dest_dir = ProjectSettings.globalize_path(OUT)
		var pdf_path: String = await panel.export_pages_pdf()
		var raw := FileAccess.get_file_as_bytes(pdf_path).get_string_from_ascii() if pdf_path != "" else ""
		var n_pages := RegEx.create_from_string("/Type /Page[^s]").search_all(raw).size()
		K.check("un PDF con 2 páginas", n_pages == 2, "%d páginas · %s" % [n_pages, pdf_path.get_file()])
		K.check("páginas A4 (595 × 842 pt)", raw.contains("/MediaBox [0 0 595.5 842.25]") or raw.contains("/MediaBox [0 0 595 842]") or RegEx.create_from_string("/MediaBox \\[0 0 59[45](\\.\\d+)? 84[12](\\.\\d+)?\\]").search(raw) != null,
			RegEx.create_from_string("/MediaBox \\[[^\\]]+\\]").search(raw).get_string() if RegEx.create_from_string("/MediaBox \\[[^\\]]+\\]").search(raw) else "-")
		K.check("el PDF trae el contenido de las dos páginas", raw.length() > 20000, "%d bytes" % raw.length())
	var abs: Array = await K.save_reload("menu")
	var names: Array = api.text_styles().map(func(x): return x["name"])
	K.check("reabrir: los 4 estilos", names.size() == 4 and "Plato" in names, str(names))
	for a in abs:
		if String(a.name) == "Carta":
			var linked := 0
			for c in a.get_children():
				if api.text_style_of(c) != "":
					linked += 1
			K.check("reabrir: textos vinculados a sus estilos", linked == 21, str(linked))
			await K.look_at(a)
			await K.shot("03_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
