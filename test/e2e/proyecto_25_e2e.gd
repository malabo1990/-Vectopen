# =============================================================================
# FASE B · ENCARGO 25 — Manual de marca de 12 páginas (modo Pro)
# Foco: pliegos, muestras de color, paleta.
# 12 páginas A4 apaisadas creadas desde el panel Páginas; vista Pliegos (el
# lienzo se ordena en pliegos enfrentados); 5 COLORES GLOBALES creados con
# «+» de «Colores del documento» (Recursos); páginas de logo (componente),
# paleta (muestras vinculadas + rótulo con su código), tipografía (estilos),
# usos correctos… Cambiar el azul de marca en la muestra global cambia TODO
# el manual; PDF de las 12 páginas; reabrir con colores, vínculos y orden.
#   test/run_e2e.sh proyecto_25_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/25"
const PAGE := Vector2(1123, 794)
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(580.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func find_node_with(method: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.has_method(method):
			return n
	return null

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("professional"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var first: Node2D = await K.artboard(PAGE, "Portada", Color.WHITE)
	# Panel Páginas: 11 páginas más (mismo tamaño que la anterior)
	var pp := find_node_with("set_view_mode")
	K.check("panel Páginas disponible", pp != null)
	if pp == null:
		quit(1)
		return
	for i in 11:
		pp.add_page()
		await K.frames(1)
	var pages: Array = pp.pages()
	K.check("12 páginas", pages.size() == 12, str(pages.size()))
	K.check("todas A4 apaisadas", pages.all(func(p) -> bool: return (p.artboard_size as Vector2).is_equal_approx(PAGE)))
	var names := ["Portada", "Índice", "Historia", "Logo", "Área de respeto", "Paleta", "Tipografía", "Iconos", "Fotografía", "Aplicaciones", "Usos incorrectos", "Contacto"]
	for i in 12:
		pages[i].name = names[i]
	# Vista Pliegos: el lienzo se ordena en pliegos enfrentados
	pp.set_view_mode(1)
	await K.frames(6)
	var p1: Node2D = pages[1]
	var p2: Node2D = pages[2]
	K.check("pliegos: páginas 2 y 3 enfrentadas (misma fila, sin hueco)", absf(p1.global_position.y - p2.global_position.y) < 0.5 and absf(p1.global_position.x + PAGE.x - p2.global_position.x) < 0.5,
		"%s / %s" % [p1.global_position, p2.global_position])
	K.check("pliegos: la portada sola en su fila", absf(first.global_position.y - p1.global_position.y) > PAGE.y * 0.5)
	# Colores globales con «+» de «Colores del documento»
	var row: Node = find_node_with("add_from_selection")
	K.check("«Colores del documento» en Recursos", row != null)
	var palette := [["Azul marca", Color("#1d3557")], ["Rojo acento", Color("#e63946")], ["Arena", Color("#f1faee")], ["Cielo", Color("#a8dadc")], ["Medianoche", Color("#0b1320")]]
	var gids: Array = []
	api.set_active_artboard(pages[5])
	for i in palette.size():
		var sw = api.add_rect(Vector2(150 + i * 200, 330), Vector2(170, 170), 12.0, "Muestra %s" % palette[i][0])
		api.set_props(sw, {"fill_color": palette[i][1], "stroke_width": 0.0})
		api.select([sw])
		await K.frames(2)
		var gid: String = row.add_from_selection() if row else ""
		api.rename_global_color(gid, palette[i][0])
		gids.append(gid)
		var lab = api.add_text(Vector2(75 + i * 200, 430), "%s\n#%s" % [palette[i][0], (palette[i][1] as Color).to_html(false).to_upper()], 16, Color("#1d3557"))
		lab.name = "Rótulo %s" % palette[i][0]
	K.check("5 colores globales con nombre", api.global_colors().size() == 5 and api.global_colors()[0]["name"] == "Azul marca")
	# Logo como componente en portada, logo y aplicaciones
	api.set_active_artboard(pages[3])
	var mark = api.add_ellipse(Vector2(560, 360), Vector2(180, 180), "Isotipo")
	api.set_prop(mark, "stroke_width", 0.0)
	var word = api.add_text(Vector2(480, 470), "BIOKO", 54, Color.BLACK)
	word.name = "Logotipo"
	api.set_prop(word, "font_weight", 800)
	api.apply_global_color(gids[0], [mark, word])
	var logo = api.make_symbol([mark, word], "Logo")
	api.set_active_artboard(pages[0])
	var logo_cover = api.place_symbol(api.symbol_of(logo), PAGE / 2.0)
	api.set_active_artboard(pages[9])
	var logo_app = api.place_symbol(api.symbol_of(logo), Vector2(300, 300))
	# Títulos de página con el azul global
	var titles: Array = []
	for i in range(1, 12):
		api.set_active_artboard(pages[i])
		var t = api.add_text(Vector2(60, 50), names[i], 40, Color.BLACK)
		t.name = "Título página"
		titles.append(t)
	api.apply_global_color(gids[0], titles)
	await K.frames(4)
	# Cambiar el azul de marca: todo el manual
	var n_changed: int = api.set_global_color("Azul marca", Color("#264653"))
	api.sync_symbols()
	await K.frames(4)
	K.check("cambiar «Azul marca» actualiza muestra, logo y 11 títulos", n_changed >= 14, str(n_changed))
	var cover_mark: Node = logo_cover.find_child("Isotipo*", true, false)
	K.check("…también el logo colocado en la portada", cover_mark != null and (cover_mark.fill_color as Color).is_equal_approx(Color("#264653")))
	K.check("…y los títulos", titles.all(func(t) -> bool: return (api.get_prop(t, "fill_color") as Color).is_equal_approx(Color("#264653"))))
	api.undo()
	await K.frames(2)
	K.check("deshacer el cambio de color global", titles.all(func(t) -> bool: return (api.get_prop(t, "fill_color") as Color).is_equal_approx(Color("#1d3557"))))
	api.redo()
	await K.look_at(pages[5])
	await K.shot("01_paleta")
	# PDF de las 12 páginas
	var panel_ex := find_node_with("export_pages_pdf")
	if panel_ex:
		panel_ex.dest_dir = ProjectSettings.globalize_path(OUT)
		var pdf: String = await panel_ex.export_pages_pdf()
		var raw := FileAccess.get_file_as_bytes(pdf).get_string_from_ascii() if pdf != "" else ""
		var np := RegEx.create_from_string("/Type /Page[^s]").search_all(raw).size()
		K.check("PDF con las 12 páginas", np == 12, str(np))
	await K.frames(10)
	var abs: Array = await K.save_reload("manual")
	K.check("reabrir: 12 páginas en orden", abs.size() == 12 and String(abs[5].name) == "Paleta", str(abs.map(func(a): return a.name)))
	var gcs: Array = api.global_colors()
	K.check("reabrir: 5 colores globales, azul cambiado", gcs.size() == 5 and (gcs[0]["color"] as Color).is_equal_approx(Color("#264653")))
	if abs.size() == 12:
		var n2: int = api.set_global_color("Rojo acento", Color("#d00000"))
		K.check("reabrir: los vínculos siguen (cambiar «Rojo acento»)", n2 >= 1, str(n2))
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
