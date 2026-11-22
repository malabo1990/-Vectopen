## E2E VTP Preview fase 1: abrir un .vtp de 2 páginas en el visor de solo
## lectura; páginas, navegación, ajuste y zoom; el editor no ve las páginas
## del visor y el documento abierto no cambia; modo seguro (el shader del
## archivo no se compila en el visor).
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://vtp_preview")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab1: Node2D = await K.artboard(Vector2(800, 600), "Portada", Color.WHITE)
	var r = api.add_rect(Vector2(400, 300), Vector2(300, 200), 0.0, "Caja")
	api.set_props(r, {"fill_color": Color(0.9, 0.2, 0.2)})
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ COLOR = vec4(0.0, 1.0, 0.0, 1.0); }"
	sm.shader = sh
	r.material = sm
	var ab2: Node2D = await K.artboard(Vector2(600, 400), "Interior", Color(0.95, 0.95, 1.0))
	api.add_ellipse(Vector2(300, 200), Vector2(200, 200), "Círculo")
	var path := ProjectSettings.globalize_path("user://vtp_preview/doc.vtc")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	for old in DirAccess.get_files_at(path.get_base_dir()):
		if old.get_extension() in ["vtc", "vtp"]:
			DirAccess.remove_absolute(path.get_base_dir().path_join(old))
	K.check("guardar el documento", K.CS.write_vtc(path, K.cont))
	var main_abs := get_nodes_in_group("artboards").size()
	var main_children: int = K.cont.get_child_count()
	var w: Window = api.preview_document(path)
	await K.frames(10)
	K.check("se abre la ventana del visor", w != null and is_instance_valid(w))
	K.check("el visor tiene las 2 páginas", w.pages.size() == 2, str(w.pages.size()))
	K.check("con su contenido", w.pages[0].find_child("Caja", true, false) != null and w.pages[1].find_child("Círculo", true, false) != null)
	K.check("el editor no ve las páginas del visor", get_nodes_in_group("artboards").size() == main_abs, "%d vs %d" % [get_nodes_in_group("artboards").size(), main_abs])
	K.check("el documento abierto no cambia", K.cont.get_child_count() == main_children)
	var caja: Node = w.pages[0].find_child("Caja", true, false)
	K.check("modo seguro: el shader del archivo NO se compila en el visor", caja != null and not (caja.material is ShaderMaterial and (caja.material as ShaderMaterial).shader != null))
	K.check("pero en el editor el objeto conserva su shader", r.material is ShaderMaterial)
	w.go_page(1)
	await K.frames(3)
	K.check("página siguiente", w.page_i == 1 and String(w._lbl_page.text).contains("Interior"), w._lbl_page.text)
	var z0: float = w._cam.zoom.x
	w.zoom_by(2.0)
	K.check("zoom ×2", absf(w._cam.zoom.x - z0 * 2.0) < 0.001)
	w.fit_all()
	K.check("ajustar todo cabe las dos páginas", w._cam.zoom.x < z0 * 2.0)
	w.cycle_background()
	w.cycle_background()
	K.check("fondo de cuadros", w._checker.visible)
	K.check("panel de información con las páginas", String(w._info.text).contains("2"))
	await K.frames(4)
	await K.shot("visor")
	# Explorador (fase 2): la carpeta del documento, con sus metadatos
	K.check("el explorador lista la carpeta del documento", w.folder == path.get_base_dir() and w.docs.any(func(d): return String(d["name"]) == "doc.vtc"))
	var p2 := ProjectSettings.globalize_path("user://vtp_preview/otro.vtc")
	K.check("guardar otro documento", K.CS.write_vtc(p2, K.cont))
	w.set_folder(path.get_base_dir())
	K.check("con los dos documentos", w._list.item_count == 2, str(w._list.item_count))
	w._filter.text = "otro"
	w._filter.text_changed.emit("otro")
	K.check("el filtro deja solo «otro»", w._list.item_count == 1 and String(w._list.get_item_metadata(0)).ends_with("otro.vtc"))
	w._list.select(0)
	w._list.item_selected.emit(0)
	await K.frames(4)
	K.check("clic en la lista abre ese documento", w.path.ends_with("otro.vtc") and w.pages.size() == 2)
	w._filter.text = ""
	w._filter.text_changed.emit("")
	# Miniaturas (fase 3): se generan en segundo plano y quedan en caché
	for _i in 120:
		if w.thumbs.size() >= 2:
			break
		await process_frame
	K.check("miniaturas de los dos documentos", w.thumbs.size() == 2, str(w.thumbs.size()))
	var d0: Dictionary = w.docs[0]
	K.check("la miniatura queda en la caché", FileAccess.file_exists(w.thumb_path(d0)))
	var timg: Image = (w.thumbs[d0["path"]] as Texture2D).get_image()
	var ink := 0
	for y in range(0, timg.get_height(), 4):
		for x in range(0, timg.get_width(), 4):
			if timg.get_pixel(x, y).a > 0.5:
				ink += 1
	K.check("la miniatura tiene contenido (la página)", ink > 50, str(ink))
	var made0: int = w.thumbs_made
	w.thumbs.clear()
	w.set_folder(path.get_base_dir())
	for _i in 120:
		if w.thumbs.size() >= 2:
			break
		await process_frame
	K.check("segunda vez: salen de la caché (no se renderizan)", w.thumbs.size() == 2 and w.thumbs_made == made0, "%d → %d" % [made0, w.thumbs_made])
	# Fase 4: capas de la página y datos del objeto
	w.load_file(path)
	await K.frames(4)
	w.go_page(0)
	await K.frames(3)
	var names: Array = []
	var it: TreeItem = w._layers.get_root().get_first_child() if w._layers.get_root() else null
	while it:
		names.append(it.get_text(0))
		it = it.get_next()
	K.check("árbol de capas de la página (sin nodos internos)", names.has("Caja") and not names.has("ArtboardTitle"), str(names))
	var caja2: Node = w.pages[0].find_child("Caja", true, false)
	var c_doc: Vector2 = w._box(caja2).get_center()
	K.check("clic en el objeto lo encuentra", w.object_at(c_doc) == caja2)
	w.pick(caja2)
	K.check("datos del objeto (tipo, tamaño, relleno)", String(w._obj_info.text).contains("Caja") and String(w._obj_info.text).contains("300 × 200") and String(w._obj_info.text).contains("250, 200") and String(w._obj_info.text).contains("#e63333"), w._obj_info.text)
	K.check("fuera de los objetos no elige nada", w.object_at(c_doc + Vector2(5000, 5000)) == null)
	# Un archivo que no es un documento
	var bad := ProjectSettings.globalize_path("user://vtp_preview/malo.vtc")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("esto no es un documento")
	f.close()
	K.check("archivo dañado: se avisa sin romper nada", not w.load_file(bad) and w.pages.is_empty())
	w.queue_free()
	await K.frames(3)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
