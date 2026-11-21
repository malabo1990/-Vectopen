# =============================================================================
# FASE B · ENCARGO 26 — Presentación de 10 diapositivas (modo Pro)
# Foco: rejilla, exportar por página.
# Diapositiva maestra 1920 × 1080 con retícula (márgenes 80, 12 columnas,
# medianil 24): título con estilo, número de diapositiva «{pág} / {total}»,
# banda de color global. Duplicarla 9 veces desde el panel Páginas, vista
# Rejilla. Un arrastre REAL con el ratón engancha un bloque al borde de una
# columna (imán de la retícula, VAL-58). Cambiar cada título, exportar las
# 10 diapositivas a PNG por separado y en un PDF, reabrir con los números
# de página recalculados.
#   test/run_e2e.sh proyecto_26_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/26"
const SLIDE := Vector2(1920, 1080)
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(600.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func drag(a_g: Vector2, b_g: Vector2) -> void:
	var xf: Transform2D = K.canvas.get_viewport().get_canvas_transform()
	var a := xf * a_g
	var b := xf * b_g
	var mm := InputEventMouseMotion.new()
	mm.position = a
	mm.global_position = a
	_send(mm)
	await K.frames(2)
	var mb := InputEventMouseButton.new()
	mb.position = a
	mb.global_position = a
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(mb)
	await K.frames(2)
	if OS.has_environment("DBG26"):
		var abn: Node2D = K.api.artboard()
		print("DBG tras pulsar: sel=", K.sm.get_selected(), " ab=", abn.name, " ab.sel=", abn.is_selected, " mode=", abn._mode, " shape_at=", K.canvas.current_tool._shape_at(a_g), " gm=", abn.get_global_mouse_position(), " a_g=", a_g)
	for i in range(1, 13):
		var m2 := InputEventMouseMotion.new()
		m2.position = a.lerp(b, i / 12.0)
		m2.global_position = m2.position
		m2.relative = (b - a) / 12.0
		m2.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(m2)
		await process_frame
	var up := InputEventMouseButton.new()
	up.position = b
	up.global_position = b
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	_send(up)
	await K.frames(4)

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
	var master: Node2D = await K.artboard(SLIDE, "Diapositiva", Color.WHITE)
	master.layout_margin = 80.0
	master.layout_columns = 12
	master.layout_gutter = 24.0
	K.check("retícula de 12 columnas", master.column_rects().size() == 12)
	var brand: String = api.add_global_color("Marca", Color("#3a0ca3"))
	var band = api.add_rect(Vector2(SLIDE.x / 2.0, 20), Vector2(SLIDE.x, 40), 0.0, "Banda")
	api.set_prop(band, "stroke_width", 0.0)
	api.apply_global_color(brand, [band])
	var tstyle: String = api.add_text_style("Título diapositiva", {"font_size": 72, "font_weight": 800, "fill_color": Color("#1b1b1b")})
	var title = api.add_text(Vector2(80, 120), "Título", 72, Color.BLACK)
	title.name = "Título"
	api.apply_text_style(tstyle, [title])
	var num = api.add_text(Vector2(1700, 1000), "{pág} / {total}", 24, Color("#666666"))
	num.name = "Número"
	# Duplicar 9 veces desde el panel Páginas
	var pp := find_node_with("duplicate_selected")
	K.check("panel Páginas disponible", pp != null)
	var mgr = K.canvas.get_node("manager_script")
	for i in 9:
		var pages: Array = pp.pages()
		mgr.set_active_artboard(pages[pages.size() - 1])
		await K.frames(1)
		pp.duplicate_selected()
		await K.frames(2)
	var slides: Array = pp.pages()
	K.check("10 diapositivas", slides.size() == 10, str(slides.size()))
	pp.set_view_mode(2)   # rejilla
	await K.frames(6)
	# Títulos propios
	var topics := ["Portada", "Problema", "Solución", "Mercado", "Producto", "Modelo", "Tracción", "Equipo", "Hoja de ruta", "Gracias"]
	for i in slides.size():
		var t: Node = slides[i].find_child("Título*", false, false)
		if t:
			api.set_prop(t, "text", topics[i])
	var nums_ok := true
	await K.frames(25)   # los números se recalculan cada 20 fotogramas
	var last: Node = slides[9].find_child("Número*", false, false)
	if last:
		var vr = last.get_node_or_null("VectorRichText")
		var shown := String(vr.get_text()) if vr else String(last.get_node("DisplayLabel").text)
		nums_ok = shown.contains("10 / 10")
		K.check("número de la última diapositiva: «10 / 10»", nums_ok, shown)
	K.check("cada diapositiva conserva la retícula", slides.all(func(s) -> bool: return int(s.layout_columns) == 12))
	# Imán de la retícula: arrastrar un bloque cerca del borde de la columna 4
	api.set_active_artboard(slides[2])
	var blk = api.add_rect(Vector2(1300, 600), Vector2(300, 200), 8.0, "Bloque")   # lejos: arrastre largo
	api.set_props(blk, {"fill_color": Color("#f72585"), "stroke_width": 0.0})
	await K.look_at(slides[2], 0.5)
	api.clear_selection()
	await K.frames(4)
	var col4: Rect2 = slides[2].column_rects()[3]
	var target_x: float = slides[2].global_position.x + col4.position.x
	var r0: Rect2 = K.ic._mt._global_rect(blk)
	var z: float = K.canvas.camera.zoom.x
	var from := r0.get_center()
	await drag(from, from + Vector2(target_x - r0.position.x + 3.0 / z, 0))
	var r1: Rect2 = K.ic._mt._global_rect(blk)
	if OS.has_environment("DBG26"):
		print("DBG ab=", slides[2].global_position, " r0=", r0, " r1=", r1, " target=", target_x, " z=", z)
		for cr in slides[2].column_rects().slice(2, 6):
			print("DBG col ", slides[2].global_transform * (cr as Rect2))
	K.check("imán de la retícula: el bloque se engancha a la columna 4 (VAL-58)", absf(r1.position.x - target_x) < 0.6, "%.2f vs %.2f" % [r1.position.x, target_x])
	await K.shot("01_diapositiva")
	await K.undo_redo(20)
	# Exportar cada diapositiva a PNG y todas en un PDF
	var panel_ex := find_node_with("export_pages_pdf")
	if panel_ex:
		panel_ex.set_scope("artboards")
		await K.frames(4)
		var rows: Array = panel_ex.rows()
		for r in rows:
			r.format = "PNG"
		var dir := ProjectSettings.globalize_path(OUT.path_join("png"))
		DirAccess.make_dir_recursive_absolute(dir)
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		var written: PackedStringArray = await panel_ex.export_rows_to(rows, dir)
		K.check("10 PNG, uno por diapositiva", written.size() == 10, str(written.size()))
		var img := Image.load_from_file(written[0]) if written.size() > 0 else null
		K.check("PNG a 1920 × 1080", img != null and img.get_size() == Vector2i(1920, 1080), str(img.get_size()) if img else "-")
		panel_ex.dest_dir = ProjectSettings.globalize_path(OUT)
		var pdf: String = await panel_ex.export_pages_pdf()
		var raw := FileAccess.get_file_as_bytes(pdf).get_string_from_ascii() if pdf != "" else ""
		var np := RegEx.create_from_string("/Type /Page[^s]").search_all(raw).size()
		K.check("PDF de 10 páginas", np == 10, str(np))
	await K.frames(10)
	var abs: Array = await K.save_reload("presentacion")
	K.check("reabrir: 10 diapositivas con retícula", abs.size() == 10 and abs.all(func(a) -> bool: return int(a.layout_columns) == 12))
	if abs.size() == 10:
		var n10: Node = abs[9].find_child("Número*", false, false)
		await K.frames(25)
		var vr2 = n10.get_node_or_null("VectorRichText") if n10 else null
		var txt2 := String(vr2.get_text()) if vr2 else ""
		K.check("reabrir: números de página recalculados (lo que se pinta)", txt2.contains("10 / 10"), txt2)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
