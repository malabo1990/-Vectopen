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
