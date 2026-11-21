# =============================================================================
# FASE B · ENCARGO 22 — Historieta de 4 viñetas (modo Modern)
# Foco: máscaras, capas, exportar por página.
# Dos páginas de 1200 × 900 con 4 viñetas cada una. Cada viñeta = grupo
# «Viñeta N» con un marco (rectángulo redondeado) que RECORTA su contenido
# (fondo, personaje que se sale del marco, bocadillo), bocadillo con cola y
# texto, onomatopeya con contorno. Capas: ocultar una viñeta, reordenar,
# bloquear el fondo. Exportar cada página a PNG por separado (panel Exportar,
# ámbito Artboards) y las dos en un PDF, reabrir.
#   test/run_e2e.sh proyecto_22_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/22"
const PAGE := Vector2(1200, 900)
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(560.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func balloon(c: Vector2, text: String) -> Array:
	var b = api.add_ellipse(c, Vector2(220, 110), "Bocadillo")
	api.set_props(b, {"fill_color": Color.WHITE, "stroke_color": Color.BLACK, "stroke_width": 3.0})
	var tail = api.add_shape(PackedVector2Array([c + Vector2(-20, 45), c + Vector2(20, 45), c + Vector2(-50, 110)]), "Cola")
	api.set_props(tail, {"fill_color": Color.WHITE, "stroke_color": Color.BLACK, "stroke_width": 3.0})
	var t = api.add_text(c + Vector2(-80, -18), text, 22, Color.BLACK)
	t.name = "Diálogo"
	return [tail, b, t]

func panel(i: int, origin: Vector2, size: Vector2, bg: Color, line: String) -> Node2D:
	var c := origin + size / 2.0
	var back = api.add_rect(c, size, 0.0, "Fondo %d" % i)
	api.set_props(back, {"fill_color": bg, "stroke_width": 0.0})
	# Personaje: se sale del marco por abajo (el recorte lo corta)
	var body = api.add_ellipse(c + Vector2(-60, size.y * 0.35), Vector2(160, 260), "Cuerpo")
	api.set_props(body, {"fill_color": Color("#457b9d"), "stroke_width": 0.0})
	var head = api.add_ellipse(c + Vector2(-60, size.y * 0.02), Vector2(110, 110), "Cabeza")
	api.set_props(head, {"fill_color": Color("#f4a261"), "stroke_width": 0.0})
	var bal := balloon(c + Vector2(90, -size.y * 0.25), line)
	var frame = api.add_rect(c, size, 18.0, "Marco %d" % i)
	api.set_props(frame, {"fill_color": Color(1, 1, 1, 0), "stroke_color": Color.BLACK, "stroke_width": 6.0})
	var content: Array = [back, body, head] + bal
	var ok: bool = api.make_mask(frame, content)
	K.check("viñeta %d: el marco recorta su contenido" % i, ok and frame.clip_children != 0)
	return api.group([frame], "Viñeta %d" % i)

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("modern"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var lines := [["¿Has visto eso?", "¡Una nave!", "Viene hacia aquí…", "¡CORRE!"],
		["¿Se ha ido?", "Creo que sí.", "Espera…", "¡¡FIUUU!!"]]
	var colors := [Color("#e9f5db"), Color("#cfe1b9"), Color("#b5c99a"), Color("#fefae0")]
	var pages: Array = []
	var all_panels: Array = []
	for p in 2:
		var ab: Node2D = await K.artboard(PAGE, "Página %d" % (p + 1), Color.WHITE)
		pages.append(ab)
		var panels: Array = []
		for i in 4:
			var o := Vector2(40 + (i % 2) * 570, 40 + (i / 2) * 420)
			panels.append(panel(p * 4 + i + 1, o, Vector2(550, 400), colors[i], lines[p][i]))
		all_panels.append(panels)
		# Onomatopeya con contorno en la última viñeta
		var sfx = api.add_text(Vector2(700, 600), "¡ZAS!" if p == 0 else "¡BUM!", 90, Color("#e63946"))
		sfx.name = "Onomatopeya"
		api.set_props(sfx, {"font_weight": 900, "stroke_color": Color.BLACK, "stroke_width": 4.0})
		api.set_prop(sfx, "rotation", -12.0)
	K.check("8 viñetas en 2 páginas", all_panels[0].size() == 4 and all_panels[1].size() == 4)
	# Capas: ocultar, reordenar, bloquear
	var v3: Node2D = all_panels[0][2]
	api.set_prop(v3, "visible", false)
	await K.frames(2)
	K.check("ocultar la viñeta 3 entera", not v3.is_visible_in_tree())
	api.set_prop(v3, "visible", true)
	var idx0 := v3.get_index()
	api.arrange(v3, "front")
	K.check("traer la viñeta 3 al frente", v3.get_index() > idx0)
	var bg1: Node = (all_panels[0][0] as Node).find_child("Fondo 1", true, false)
	api.set_prop(bg1, "locked", true)
	K.check("bloquear el fondo de la viñeta 1", bool(bg1.get_meta("locked", false)))
	for ab in pages:
		await K.look_at(ab)
		await K.shot("0%d_%s" % [pages.find(ab) + 1, String(ab.name).replace(" ", "_")])
	await K.undo_redo(20)
	# Exportar cada página a PNG desde el panel Exportar
	var panel_ex: Node = null
	for n in root.find_children("*", "", true, false):
		if n.has_method("export_pages_pdf") and n.has_method("export_rows_to"):
			panel_ex = n
			break
	K.check("panel Exportar disponible", panel_ex != null)
	if panel_ex:
		panel_ex.set_scope("artboards")
		await K.frames(4)
		var rows: Array = panel_ex.rows()
		for r in rows:
			r.format = "PNG"
		var dir := ProjectSettings.globalize_path(OUT.path_join("paginas"))
		DirAccess.make_dir_recursive_absolute(dir)
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))   # sin restos de otras ejecuciones
		var written: PackedStringArray = await panel_ex.export_rows_to(rows, dir)
		var pngs: int = Array(written).filter(func(p) -> bool: return String(p).ends_with(".png")).size()
		K.check("un PNG por página (≥ 2)", pngs >= 2, "%d · %s" % [pngs, ", ".join(Array(written).map(func(p): return String(p).get_file()))])
		# VAL-54: dentro de cada viñeta se ve su fondo (el marco sin relleno recorta por su área)
		var p1png := ""
		for pth in written:
			if String(pth).get_file() == "Página 1.png" or (p1png == "" and String(pth).get_file().begins_with("Página 1")):
				p1png = pth
		var im1 := Image.load_from_file(p1png) if p1png != "" else null
		if im1:
			var inside := im1.get_pixel(100, 120)   # dentro de la viñeta 1, sobre su fondo
			K.check("el fondo de la viñeta se ve dentro del marco (VAL-54)", inside.is_equal_approx(Color("#e9f5db")) or (inside - Color("#e9f5db")).v < 0.04, str(inside))
		for pth in written:
			var img := Image.load_from_file(pth) if String(pth).ends_with(".png") else null
			if img and String(pth).get_file().begins_with("P"):
				K.check("PNG de %s a 1200 × 900" % String(pth).get_file(), img.get_size() == Vector2i(1200, 900), str(img.get_size()))
		panel_ex.dest_dir = ProjectSettings.globalize_path(OUT)
		var pdf: String = await panel_ex.export_pages_pdf()
		var raw := FileAccess.get_file_as_bytes(pdf).get_string_from_ascii() if pdf != "" else ""
		var np := RegEx.create_from_string("/Type /Page[^s]").search_all(raw).size()
		K.check("PDF con las páginas del documento (≥ 2)", np >= 2, str(np))
		K.check("PDF con los recortes de las viñetas", raw.count(" W n") >= 8, str(raw.count(" W n")))
	var abs: Array = await K.save_reload("historieta")
	var masks := 0
	for a in abs:
		for n in a.find_children("Marco*", "", true, false):
			if int(n.get("clip_children")) != 0:
				masks += 1
	K.check("reabrir: las 8 viñetas siguen recortando", masks == 8, str(masks))
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
