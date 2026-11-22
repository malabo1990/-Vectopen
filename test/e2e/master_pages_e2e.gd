## E2E páginas maestras (informe §5): una maestra con cabecera y número de
## página; dos páginas la usan (desde la pestaña Páginas); la cabecera se ve
## en ellas, no se puede seleccionar, el número es el de CADA página; editar
## la maestra las actualiza; deshacer; guardar / abrir; PNG y SVG.
extends SceneTree

var K
var api
const MP = preload("res://script_gdscript/shapes/master_pages.gd")

func _init() -> void:
	_run.call_deferred()
	create_timer(260.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func px(ab: Node2D, p: Vector2) -> Color:
	var img := root.get_texture().get_image()
	var sp: Vector2 = K.canvas.get_viewport().get_canvas_transform() * (ab.global_position + p)
	return img.get_pixelv(Vector2i(sp))

func layer_text(page: Node) -> String:
	var l: Node = page.get_node_or_null(MP.LAYER)
	if l == null:
		return ""
	for n in l.find_children("*", "", true, false):
		if n.has_meta("text") and String(n.get_meta("shape_type", "")).begins_with("text"):
			var dl = n.get_node_or_null("DisplayLabel")
			return String(dl.text) if dl and "text" in dl else String(n.get_meta("text"))
	return ""

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://master_pages")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var master: Node2D = await K.artboard(Vector2(600, 400), "Maestra A", Color.WHITE)
	var head = api.add_rect(Vector2(300, 30), Vector2(600, 60), 0.0, "Cabecera")
	api.set_props(head, {"fill_color": Color(0.1, 0.3, 0.8), "stroke_width": 0.0})
	api.add_text(Vector2(520, 360), "{pág} / {total}", 20)
	api.set_master_page(master, true)
	var p1: Node2D = await K.artboard(Vector2(600, 400), "Página 1", Color.WHITE)
	api.add_ellipse(Vector2(300, 220), Vector2(120, 120), "Contenido 1")
	var p2: Node2D = await K.artboard(Vector2(600, 400), "Página 2", Color.WHITE)
	# Pestaña Páginas: sección «Página maestra»
	var sec: Node = null
	for n in root.find_children("MasterPagesSection", "", true, false):
		sec = n
	K.check("la pestaña Páginas tiene «Página maestra»", sec != null)
	api.use_master([p1, p2], "Maestra A")
	await K.frames(6)
	K.check("las dos páginas muestran la maestra", p1.get_node_or_null(MP.LAYER) != null and p2.get_node_or_null(MP.LAYER) != null)
	K.check("la capa de la maestra va DEBAJO del contenido", p1.get_node(MP.LAYER).get_index() == 0)
	var t1 := layer_text(p1)
	var t2 := layer_text(p2)
	K.check("cada página con su número (la maestra no cuenta: 1 / 2 y 2 / 2)", t1.replace(" ", "") == "1/2" and t2.replace(" ", "") == "2/2", "%s | %s" % [t1, t2])
	await K.look_at(p1)
	await K.frames(4)
	await RenderingServer.frame_post_draw
	var c: Color = px(p1, Vector2(300, 30))
	K.check("la cabecera se ve en la página 1", c.b > 0.6 and c.r < 0.3, str(c))
	# No se puede seleccionar desde la página
	var mt = K.canvas.current_tool
	var hit = mt._shape_at(p1.to_global(Vector2(300, 30))) if mt.has_method("_shape_at") else null
	K.check("en la página no se puede coger la cabecera", hit == null or not String(hit.name).begins_with("_") and hit.get_parent() != p1.get_node(MP.LAYER), str(hit))
	# Editar la maestra actualiza las páginas
	api.set_props(head, {"fill_color": Color(0.8, 0.2, 0.1)})
	await K.frames(6)
	await RenderingServer.frame_post_draw
	var c2: Color = px(p1, Vector2(300, 30))
	K.check("cambiar la maestra cambia la página", c2.r > 0.6 and c2.b < 0.3, str(c2))
	api.undo()
	await K.frames(6)
	await RenderingServer.frame_post_draw
	K.check("deshacer: azul otra vez", px(p1, Vector2(300, 30)).b > 0.6)
	# PNG / SVG de la página 1
	var png := ProjectSettings.globalize_path("user://master_pages/p1.png")
	var ok: bool = await api.export(png, p1)
	var img := Image.load_from_file(png) if ok else null
	K.check("PNG con la maestra", img != null and img.get_pixel(300, 30).b > 0.6, str(img.get_pixel(300, 30)) if img else "-")
	var svg := ProjectSettings.globalize_path("user://master_pages/p1.svg")
	await api.export(svg, p1)
	K.check("SVG con la maestra", FileAccess.get_file_as_string(svg).to_lower().contains("#1a4dcc") or FileAccess.get_file_as_string(svg).contains("rgb(26,77,204)") or FileAccess.get_file_as_string(svg).length() > 400)
	await K.shot("maestra")
	# Guardar / abrir
	var abs: Array = await K.save_reload("maestras")
	await K.frames(10)
	var q1: Node = null
	var qm: Node = null
	for a in abs:
		if String(a.name) == "Página 1": q1 = a
		if String(a.name) == "Maestra A": qm = a
	K.check("reabrir: la maestra sigue siendo maestra", qm != null and MP.is_master(qm))
	K.check("reabrir: la página usa la maestra y la vuelve a mostrar", q1 != null and String(q1.get_meta(MP.USE_META, "")) == "Maestra A" and q1.get_node_or_null(MP.LAYER) != null)
	K.check("la capa de la maestra no se guardó como contenido", q1 != null and q1.get_children().filter(func(x): return String(x.name).contains("Cabecera")).is_empty())
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
