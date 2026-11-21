# =============================================================================
# FASE B · ENCARGO 23 — Tabla comparativa (modo Pro)
# Foco: tablas, alineación, bordes.
# Comparativa de 3 planes × 7 filas en una página 1200 × 800: cabecera
# oscura, cebreado, ✓ / ✗ centrados, precios alineados a la derecha, primera
# columna más ancha, bordes finos. Añadir una fila desde el menú contextual
# (con una celda seleccionada), editar el texto de una celda a mano, centrar
# la tabla en la página, deshacer, exportar SVG/PDF/PNG, reabrir y seguir
# editando.
#   test/run_e2e.sh proyecto_23_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/23"
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func cell(t: Node, r: int, c: int) -> Node:
	for ch in t.get_children():
		if ch.has_meta("table_cell") and ch.get_meta("table_cell") == [r, c]:
			return ch
	return null

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("professional"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(1200, 800), "Comparativa", Color.WHITE)
	var title = api.add_text(Vector2(80, 50), "Elige tu plan", 44, Color("#2b2d42"))
	title.name = "Título"
	api.set_prop(title, "font_weight", 800)
	var data := [
		["Función", "Básico", "Pro", "Estudio"],
		["Mesas de trabajo", "3", "Ilimitadas", "Ilimitadas"],
		["Exportar PDF", "✓", "✓", "✓"],
		["Pinceles avanzados", "✗", "✓", "✓"],
		["Componentes", "✗", "✓", "✓"],
		["Soporte", "Foro", "Correo", "Prioritario"],
		["Precio / mes", "0 €", "9 €", "29 €"],
	]
	var t = api.add_table(Rect2(80, 140, 1000, 0), 7, 4, data, {
		"col_w": [400.0, 200.0, 200.0, 200.0], "row_h": 64.0, "font_size": 20,
		"align": ["left", "center", "center", "center"]})
	t.name = "Tabla planes"
	await K.frames(4)
	K.check("tabla de 7 × 4 con 28 celdas de texto", t.get_children().filter(func(c) -> bool: return c.has_meta("table_cell")).size() == 28)
	var hdr = cell(t, 0, 1)
	K.check("cabecera en blanco y negrita", hdr != null and int(hdr.get_meta("font_weight", 400)) == 700 and (hdr.get_meta("text_color") as Color).is_equal_approx(Color.WHITE))
	# ✓ centrado en su columna
	var chk = cell(t, 2, 2)
	var col_x0 := 400.0 + 200.0
	var cx: float = chk.position.x + float(chk.get_meta("width")) / 2.0
	K.check("✓ centrado en su columna", absf(cx - (col_x0 + 100.0)) < 3.0, "%.1f vs %.1f" % [cx, col_x0 + 100.0])
	# Bordes: líneas horizontales y verticales
	var hl: int = t.get_children().filter(func(c) -> bool: return String(c.name).begins_with("Línea H")).size()
	var vl: int = t.get_children().filter(func(c) -> bool: return String(c.name).begins_with("Línea V")).size()
	K.check("rejilla de bordes (8 horizontales, 5 verticales)", hl == 8 and vl == 5, "%d / %d" % [hl, vl])
	# Precios a la derecha
	api.table_set(t, {"align": ["left", "right", "right", "right"]})
	var price = cell(t, 6, 3)
	var right_edge: float = price.position.x + float(price.get_meta("width"))
	K.check("precios alineados a la derecha", absf(right_edge - (1000.0 - 12.0)) < 3.0, "%.1f" % right_edge)
	api.undo()
	K.check("deshacer la alineación", String(t.get_meta("table")["align"][3]) == "center")
	# Añadir una fila desde el menú contextual con una celda seleccionada
	var host: Node = null
	for n in root.find_children("*", "", true, false):
		if n.get_script() and String(n.get_script().resource_path).ends_with("smart_menu_extras.gd"):
			host = n.get_parent()
	api.select([cell(t, 3, 0)])
	await K.frames(2)
	if host:
		host.visible = true
		await K.frames(2)
		var b := host.find_child("TableAddRow", true, false) as Control
		K.check("el menú contextual ofrece «Tabla: añadir fila»", b != null and b.visible)
		host.visible = false
		ContextMenuActions.execute("table_add_row", host)
		await K.frames(3)
	K.check("fila añadida debajo de la celda elegida (8 filas)", int(t.get_meta("table")["rows"]) == 8 and String(api.table_data(t)[4][0]) == "")
	# Rellenar la fila nueva
	for c in 4:
		api.table_set_cell(t, 4, c, ["Plantillas", "10", "200", "Todas"][c])
	# Editar el texto de una celda a mano
	var sup = cell(t, 6, 3)
	api.set_prop(sup, "text", "Prioritario 24 h")
	api.table_set(t, {"zebra": true})   # rehace la tabla
	K.check("el texto editado a mano se conserva al rehacer", String(api.table_data(t)[6][3]) == "Prioritario 24 h")
	# Centrar la tabla en la página
	var r: Rect2 = K.ic._mt._global_rect(t)
	api.move(t, Vector2(ab.global_position.x + 600.0 - r.get_center().x, 0))
	var r2: Rect2 = K.ic._mt._global_rect(t)
	K.check("tabla centrada en la página", absf(r2.get_center().x - (ab.global_position.x + 600.0)) < 2.0)
	await K.look_at(ab)
	await K.shot("01_tabla")
	await K.undo_redo(20)
	var ex: Dictionary = await K.export_all(ab, "comparativa")
	if ex.has("svg"):
		var svg := FileAccess.get_file_as_string(ex["svg"])
		K.check("SVG con las filas y la rejilla", svg.count("<path") + svg.count("<rect") >= 20, str(svg.count("<path") + svg.count("<rect")))
	var abs: Array = await K.save_reload("comparativa")
	for a in abs:
		if String(a.name) == "Comparativa":
			var t2: Node = a.find_child("Tabla planes", false, false)
			K.check("reabrir: la tabla y sus datos", t2 != null and String(api.table_data(t2)[4][0]) == "Plantillas" and int(t2.get_meta("table")["rows"]) == 8)
			if t2:
				api.table_insert_col(t2)
				K.check("reabrir: se sigue editando (añadir columna)", int(t2.get_meta("table")["cols"]) == 5)
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
