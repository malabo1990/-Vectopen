## E2E combinación de datos e índice (informe §5): plantilla (tarjeta con
## {nombre} y {precio}) + CSV de 5 productos → fichas en páginas «Catálogo»
## con los textos reales; un Ctrl+Z lo quita todo; índice de páginas.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func texts_under(n: Node) -> Array:
	var out: Array = []
	for t in [n] + n.find_children("*", "Node2D", true, false):
		if t.has_meta("text") and String(t.get_meta("shape_type", "")).begins_with("text"):
			out.append(String(t.get_meta("text")))
	return out

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://data_merge")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(600, 400), "Plantilla", Color.WHITE)
	var card = api.add_rect(Vector2(100, 70), Vector2(180, 120), 0.0, "Tarjeta")
	api.set_props(card, {"fill_color": Color(0.95, 0.95, 1.0)})
	var t1 = api.add_text(Vector2(20, 20), "{nombre}", 18)
	var t2 = api.add_text(Vector2(20, 80), "{precio}", 16)
	var tpl = api.group([card, t1, t2], "Ficha")
	await K.look_at(ab)
	api.select([tpl])
	await K.frames(3)
	var CMA = load("res://script_gdscript/ui/context_menu_actions.gd")
	K.check("la plantilla ofrece «Combinar datos (CSV)…»", CMA.can_data_merge(root))
	var n_pages0: int = api.artboards().size()
	var pages: Array = api.data_merge(tpl, ProjectSettings.globalize_path("res://test/fixtures/data_merge/productos.csv"))
	await K.frames(6)
	K.check("se crean páginas «Catálogo»", pages.size() >= 1 and String(pages[0].name).begins_with("Catálogo"))
	var fichas: Array = []
	for p in pages:
		for c in p.get_children():
			if String(c.name).begins_with("Ficha"):
				fichas.append(c)
	K.check("una ficha por producto (5)", fichas.size() == 5, str(fichas.size()))
	var all_txt: Array = []
	for f in fichas:
		all_txt.append_array(texts_under(f))
	K.check("con los textos reales (nombre y precio)", all_txt.has("Silla Nórdica") and all_txt.has("149 €") and all_txt.has("Lámpara \"Luna\""), str(all_txt))
	K.check("sin marcadores sin rellenar", not all_txt.any(func(t): return String(t).contains("{nombre}") or String(t).contains("{precio}")))
	K.check("la plantilla no cambia", texts_under(tpl).has("{nombre}"))
	var b0: Rect2 = load("res://script_gdscript/shapes/auto_layout.gd").box(fichas[0])
	var b1: Rect2 = load("res://script_gdscript/shapes/auto_layout.gd").box(fichas[1])
	K.check("en rejilla (la 2.ª a la derecha de la 1.ª)", b1.position.x > b0.end.x and absf(b1.position.y - b0.position.y) < 1.0, "%s %s" % [b0, b1])
	if not pages.is_empty():
		await K.look_at(pages[0])
		await K.frames(4)
		await K.shot("catalogo")
	api.undo()
	await K.frames(4)
	K.check("un Ctrl+Z quita todo lo combinado", api.artboards().size() == n_pages0, "%d vs %d" % [api.artboards().size(), n_pages0])
	# Índice
	api.redo()
	await K.frames(4)
	api.set_active_artboard(ab)
	var toc = api.make_toc()
	await K.frames(3)
	var tt: String = String(toc.get_meta("text", "")) if toc else ""
	K.check("índice con las páginas y sus números", tt.contains("Plantilla") and tt.contains("Catálogo 1") and tt.contains("\t"), tt)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
