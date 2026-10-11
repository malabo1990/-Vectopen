extends GdUnitTestSuite

## Exportación: SVG/PDF/EPS desde la geometría real (grupos, Bézier,
## transformaciones, colores válidos), escenas de Godot reales, VOP sin
## pérdidas (ida y vuelta) y formatos de imagen.

const CANVAS := "res://scenes/canvas/canvas.tscn"
const VX = preload("res://script_gdscript/system/vector_export.gd")

var _api: VectopenAPI
var _ab: Node2D
var _dir := ""

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api
	_ab = _api.artboard()
	for c in _api.shapes():
		c.get_parent().remove_child(c)
		c.queue_free()
	_dir = ProjectSettings.globalize_path("user://export_test")
	DirAccess.make_dir_recursive_absolute(_dir)

func after_test() -> void:
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))

## Documento con un poco de todo.
func _doc() -> Dictionary:
	var r := _api.add_rect(Vector2(100, 100), Vector2(80, 40), 8)
	r.fill_color = Color(1, 0, 0)
	_api.set_rotation(r, 90)
	var e := _api.add_ellipse(Vector2(250, 100), Vector2(60, 40))
	e.fill_color = Color(0, 0.5, 1, 0.5)
	var st := _api.add_star(Vector2(400, 100), 40, 5)
	var c := Curve2D.new()
	c.add_point(Vector2(0, 0), Vector2.ZERO, Vector2(30, -40))
	c.add_point(Vector2(100, 0), Vector2(-30, -40), Vector2.ZERO)
	var path := _api.add_curve(c, false, "Curva")
	var g1 := _api.add_rect(Vector2(0, 0), Vector2(20, 20))
	var grp := _api.group([g1], "Grupo")
	grp.position = Vector2(500, 300)
	var t := _api.add_text(Vector2(40, 400), "Hola\nMundo ñ", 30)
	var img := Image.create(4, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 1, 0, 0.5))
	var sp := _api.add_image(img, Vector2(300, 300))
	return {"rect": r, "ellipse": e, "star": st, "path": path, "grouped": g1, "text": t, "image": sp}

func test_svg_geometria_real() -> void:
	_doc()
	var data := VX.collect(_ab)
	var paths := (data["items"] as Array).filter(func(i) -> bool: return i["t"] == "path")
	assert_int(paths.size()).is_equal(5)   # rect, elipse, estrella, curva, rect del grupo
	var svg := VX.to_svg(data)
	# XML válido
	var xp := XMLParser.new()
	assert_int(xp.open_buffer(svg.to_utf8_buffer())).is_equal(OK)
	var tags := {}
	while xp.read() == OK:
		if xp.get_node_type() == XMLParser.NODE_ELEMENT:
			tags[xp.get_node_name()] = int(tags.get(xp.get_node_name(), 0)) + 1
			for i in xp.get_attribute_count():
				if xp.get_attribute_name(i) in ["fill", "stroke"]:
					var v := xp.get_attribute_value(i)
					assert_bool(v == "none" or v.begins_with("#") or v.begins_with("url(")).override_failure_message("color no válido: " + v).is_true()
	assert_int(int(tags.get("path", 0))).is_equal(5)
	assert_int(int(tags.get("text", 0))).is_equal(1)
	assert_int(int(tags.get("image", 0))).is_equal(1)
	assert_str(svg).contains('fill="#ff0000"')
	assert_str(svg).contains('fill-opacity="0.5"')
	assert_str(svg).contains("Mundo ñ")

func _bounds(subs: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for sub in subs:
		for o in sub["ops"]:
			for k in range(1, o.size()):
				if first:
					r = Rect2(o[k], Vector2.ZERO)
					first = false
				else:
					r = r.expand(o[k])
	return r

func test_transformaciones_rotacion_y_grupos() -> void:
	var d := _doc()
	var items: Array = VX.collect(_ab)["items"]
	var by_bounds := items.filter(func(i) -> bool: return i["t"] == "path").map(func(i) -> Rect2: return _bounds(i["subs"]))
	# rect 80x40 girado 90° → 40 de ancho, 80 de alto, centrado en (100,100)
	assert_bool(by_bounds.any(func(b: Rect2) -> bool:
		return b.size.is_equal_approx(Vector2(40, 80)) and b.get_center().is_equal_approx(Vector2(100, 100)))).is_true()
	# rect dentro del grupo desplazado a (500,300)
	assert_bool(by_bounds.any(func(b: Rect2) -> bool:
		return b.size.is_equal_approx(Vector2(20, 20)) and b.get_center().is_equal_approx(Vector2(500, 300)))).is_true()
	# la curva conserva sus Bézier
	var curve_item: Dictionary = items.filter(func(i) -> bool: return i["t"] == "path" and (i["subs"][0]["ops"] as Array).any(func(o) -> bool: return o[0] == "C"))[0]
	assert_object(curve_item).is_not_null()

func test_pdf_valido_con_xref() -> void:
	_doc()
	var pdf := VX.to_pdf(VX.collect(_ab))
	var txt := pdf.get_string_from_ascii()
	assert_str(txt.substr(0, 8)).is_equal("%PDF-1.4")
	assert_str(pdf.slice(pdf.size() - 6).get_string_from_ascii()).is_equal("%%EOF\n")
	# cada entrada de la tabla xref apunta a "N 0 obj"
	var xref_at := int(txt.substr(txt.rfind("startxref") + 10).strip_edges().get_slice("\n", 0))
	var lines := pdf.slice(xref_at).get_string_from_ascii().split("\n")
	var count := int(lines[1].get_slice(" ", 1))
	for i in range(1, count):
		var off := int(lines[2 + i].get_slice(" ", 0))
		assert_str(pdf.slice(off, off + 12).get_string_from_ascii()).starts_with("%d 0 obj" % i)
	assert_str(txt).contains("/Im1 Do")
	assert_bool(txt.contains(" Tj")).is_false()   # texto como curvas (tu fuente)

func test_eps() -> void:
	_doc()
	var eps := VX.to_eps(VX.collect(_ab))
	assert_str(eps).starts_with("%!PS-Adobe-3.0 EPSF-3.0")
	var sz := _api.artboard_size()
	assert_str(eps).contains("%%%%BoundingBox: 0 0 %d %d" % [ceili(sz.x), ceili(sz.y)])
	assert_str(eps).contains("curveto")
	assert_str(eps).contains("colorimage")

func test_avisa_de_lo_que_solo_existe_en_imagen() -> void:
	var r := _api.add_rect(Vector2(100, 100), Vector2(50, 50))
	assert_array(VX.collect(_ab)["warnings"]).is_empty()
	_api.add_filter(r, "grain")
	assert_bool("filtros" in VX.collect(_ab)["warnings"]).is_true()

func test_vop_ida_y_vuelta_sin_perdidas() -> void:
	var d := _doc()
	d["star"].points_count = 7
	_api.add_effect(d["rect"], "Drop Shadow", {"blur": 9.0})
	var path := _dir.path_join("doc.vop")
	assert_bool(await _api.export(path)).is_true()
	var json = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_str(String(json["format"])).is_equal("vop")
	var n := (json["elements"] as Array).size()
	assert_int(n).is_equal(_api.shapes().size())
	# importar en un artboard nuevo
	var ab2 := _api.add_artboard(Vector2(800, 600), "Destino")
	ImportExportManager.import_file(path, ImportExportManager.ImportFormat.VOP, ab2)
	assert_int(_api.shapes(ab2).size()).is_equal(n)
	var star2 = _api.shapes(ab2).filter(func(s) -> bool: return s is VectorStar)[0]
	assert_int(star2.points_count).is_equal(7)
	var rect2 = _api.shapes(ab2).filter(func(s) -> bool: return s is VectorRectangle and s.size == Vector2(80, 40))[0]
	assert_float(float(rect2.effects[0]["blur"])).is_equal(9.0)

## TSCN/SCN PORTABLES: solo nodos nativos de Godot, ningún script de
## Vectopen → se ven en cualquier proyecto.
func _scripts_in(n: Node) -> int:
	var c := 1 if n.get_script() != null else 0
	for ch in n.get_children():
		c += _scripts_in(ch)
	return c

func test_escena_godot_portable_sin_scripts() -> void:
	var d := _doc()
	for ext in ["tscn", "scn"]:
		var path := _dir.path_join("doc." + ext)
		assert_bool(await _api.export(path)).override_failure_message(ext).is_true()
		if ext == "tscn":
			var txt := FileAccess.get_file_as_string(path)
			assert_bool(txt.contains("res://scripts") or txt.contains("res://script_gdscript")).override_failure_message("la escena referencia scripts de Vectopen").is_false()
		var ps := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var inst: Node = auto_free(ps.instantiate())
		assert_int(_scripts_in(inst)).is_equal(0)
		assert_int(inst.find_children("*", "Polygon2D", true, false).size()).is_greater(4)
		assert_int(inst.find_children("*", "Line2D", true, false).size()).is_greater(0)
		assert_int(inst.find_children("*", "Label", true, false).size()).is_equal(1)
		assert_int(inst.find_children("*", "Sprite2D", true, false).size()).is_equal(1)
	# un elemento suelto: recortado a su caja (empieza cerca de 0,0)
	var p2 := _dir.path_join("estrella.tscn")
	assert_int(await ImportExportManager.export_nodes(_ab, [d["star"]], "TSCN", p2)).is_equal(OK)
	var inst2: Node = auto_free((ResourceLoader.load(p2, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate())
	var poly: Polygon2D = inst2.find_children("*", "Polygon2D", true, false)[0]
	var mn := Vector2(INF, INF)
	for v in poly.polygon:
		mn = mn.min(v)
	assert_float(mn.x).is_between(-0.5, 3.0)
	assert_float(mn.y).is_between(-0.5, 3.0)

## VOP de una SELECCIÓN: el tamaño es el de la selección y se coloca con
## la selección como eje (no con la página).
func test_vop_de_seleccion_tamano_exacto_y_eje() -> void:
	var d := _doc()
	var star: Node2D = d["star"]
	var before := VX.bounds(VX.collect(_ab, true, [star]))
	var path := _dir.path_join("estrella.vop")
	assert_int(await ImportExportManager.export_nodes(_ab, [star], "VOP", path)).is_equal(OK)
	var json = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_float(float(json["size"][0])).is_equal_approx(before.size.x, 0.01)
	assert_float(float(json["size"][1])).is_equal_approx(before.size.y, 0.01)
	assert_float(float(json["anchor"][0])).is_equal_approx(before.position.x, 0.01)
	# importar soltándolo en (500, 600): la estrella queda centrada ahí, mismo tamaño
	var res := ImportExportManager.import_any(path, _ab, Vector2(500, 600))
	assert_bool(res["ok"]).is_true()
	var g: Node2D = res["node"]
	var after := VX.bounds(VX.collect(_ab, true, [g]))
	assert_vector(after.size).is_equal_approx(before.size, Vector2(0.05, 0.05))
	assert_vector(after.get_center()).is_equal_approx(Vector2(500, 600), Vector2(0.05, 0.05))
	# sin punto de destino: centrada en el artboard
	var res2 := ImportExportManager.import_any(path, _ab)
	var after2 := VX.bounds(VX.collect(_ab, true, [res2["node"]]))
	assert_vector(after2.get_center()).is_equal_approx(_api.artboard_size() / 2.0, Vector2(0.05, 0.05))

func test_svg_pdf_eps_a_disco_y_jpegxl_no_soportado() -> void:
	_doc()
	for ext in ["svg", "pdf", "eps"]:
		var path := _dir.path_join("doc." + ext)
		assert_bool(await _api.export(path)).override_failure_message(ext).is_true()
		assert_int(FileAccess.get_file_as_bytes(path).size()).is_greater(200)
	var err: Error = await ImportExportManager.export_artboard(_ab, ImportExportManager.ExportFormat.JPEG_XL, _dir.path_join("x.jxl"))
	assert_int(err).is_equal(ERR_UNAVAILABLE)
	assert_bool(FileAccess.file_exists(_dir.path_join("x.jxl"))).is_false()
	var mon = GdUnitThreadManager.get_current_context().get_execution_context().error_monitor
	for e in mon.log_entries().duplicate():
		mon.erase_log_entry(e)

## La capa "render" de VOP es JSON neutro: lo puede leer cualquier programa.
func test_vop_capa_render_para_otros_lectores() -> void:
	var d := _doc()
	var data := ImportExportManager.vop_data(_ab)
	var render: Dictionary = data["render"]
	assert_str(String(render["origin"])).is_equal("top-left")
	var types := (render["items"] as Array).map(func(i) -> String: return i["type"])
	assert_int(types.count("path")).is_equal(6)   # 5 figuras + el texto como curvas
	assert_int(types.count("text")).is_equal(0)
	assert_int(types.count("image")).is_equal(1)
	var red: Dictionary = (render["items"] as Array).filter(func(i) -> bool: return i["type"] == "path" and i["fill"] == "#ff0000ff")[0]
	assert_str(String(red["subpaths"][0]["ops"][0][0])).is_equal("M")
	# todo serializable a JSON y de vuelta
	var back = JSON.parse_string(JSON.stringify(data))
	assert_int((back["render"]["items"] as Array).size()).is_equal((render["items"] as Array).size())
	# VOP de una selección: solo esos objetos
	var sel := ImportExportManager.vop_data(_ab, [d["star"]])
	assert_int((sel["elements"] as Array).size()).is_equal(1)
	assert_int((sel["render"]["items"] as Array).size()).is_equal(1)

# ── importar / convertir / elementos ────────────────────────────────────────
const SvgImp = preload("res://script_gdscript/system/svg_import.gd")

## SVG "de otro programa": relativos, H/V, S, Q, arco, grupos con transform,
## style="", colores con nombre y rgb(), rect redondeado, círculo, texto.
const FOREIGN_SVG := """<?xml version="1.0"?>
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 400 200">
  <defs><linearGradient id="gr"><stop offset="0" stop-color="#00ff00"/><stop offset="1" stop-color="blue"/></linearGradient></defs>
  <g transform="translate(10,10)" style="fill:red;stroke:rgb(0,0,255);stroke-width:4">
    <path d="m10 10 h50 v50 h-50 z"/>
    <path d="M100 10 c20 0 40 20 40 40 s-20 40 -40 40 Q80 90 80 50 T100 10 Z" fill-opacity="0.5"/>
    <path d="M200 50 a40 40 0 1 0 80 0 a40 40 0 1 0 -80 0" fill="url(#gr)"/>
  </g>
  <rect x="300" y="120" width="60" height="40" rx="10" fill="navy"/>
  <circle cx="50" cy="150" r="20" fill="#f80" opacity="0.5"/>
  <text x="120" y="170" font-size="24" fill="black">Hola<tspan x="120" dy="1.2em">SVG</tspan></text>
  <rect width="10" height="10" style="display:none"/>
</svg>"""

func test_svg_externo_completo() -> void:
	var data := SvgImp.parse(FOREIGN_SVG)
	assert_vector(data["size"]).is_equal(Vector2(200, 100))
	var items: Array = data["items"]
	var paths := items.filter(func(i) -> bool: return i["t"] == "path")
	assert_int(paths.size()).is_equal(5)   # 3 del grupo + rect + círculo (el oculto no)
	# cuadrado relativo: viewBox escala 0,5 y el grupo traslada 10 → (10+10)*0,5 = 10
	var sq: Dictionary = paths[0]
	assert_vector(sq["subs"][0]["anchors"][0]).is_equal_approx(Vector2(10, 10), Vector2(0.01, 0.01))
	assert_vector(sq["subs"][0]["anchors"][1]).is_equal_approx(Vector2(35, 10), Vector2(0.01, 0.01))
	assert_object(sq["fill"]).is_equal(Color(1, 0, 0))
	assert_float((sq["stroke"] as Color).b).is_equal(1.0)
	assert_float(float(sq["width"])).is_equal_approx(2.0, 0.01)   # 4 × escala 0,5
	assert_float((paths[1]["fill"] as Color).a).is_equal_approx(0.5, 0.01)
	# arco → círculo de radio 40 (×0,5 = 20): todos los puntos a 20 del centro
	var circ: Dictionary = paths[2]
	var c := Vector2((240 + 10) * 0.5, (50 + 10) * 0.5)
	for p in circ["subs"][0]["anchors"]:
		assert_float((p as Vector2).distance_to(c)).is_equal_approx(20.0, 0.05)
	assert_object(circ["fill"]).is_equal(Color(0, 1, 0))   # degradado → 1er stop
	assert_float(float(paths[4]["opacity"])).is_equal_approx(0.5, 0.01)
	# cada <tspan> con posición propia es un texto en su sitio
	var txts: Array = items.filter(func(i) -> bool: return i["t"] == "text")
	assert_int(txts.size()).is_equal(2)
	assert_str(String(txts[0]["text"])).is_equal("Hola")
	assert_str(String(txts[1]["text"])).is_equal("SVG")

func test_importar_svg_y_deshacer() -> void:
	var path := _dir.path_join("ext.svg")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(FOREIGN_SVG)
	f.close()
	HistoryManager.clear()
	var n0 := _api.shapes().size()
	var res := ImportExportManager.import_any(path, _ab, Vector2(300, 300))
	assert_bool(res["ok"]).is_true()
	assert_int(_api.shapes().size()).is_equal(n0 + 1)
	assert_int((res["node"] as Node).get_child_count()).is_equal(7)   # 5 formas + 2 textos
	HistoryManager.undo()
	assert_int(_api.shapes().size()).is_equal(n0)

func test_svg_ida_y_vuelta() -> void:
	_doc()
	var svg := VX.to_svg(VX.collect(_ab))
	var data := SvgImp.parse(svg)
	var a := (VX.collect(_ab)["items"] as Array).filter(func(i) -> bool: return i["t"] == "path").size()
	assert_int((data["items"] as Array).filter(func(i) -> bool: return i["t"] == "path").size()).is_equal(a)
	assert_int((data["items"] as Array).filter(func(i) -> bool: return i["t"] == "image").size()).is_equal(1)

func test_exportar_un_elemento_recortado() -> void:
	var d := _doc()
	var path := _dir.path_join("estrella.svg")
	assert_int(await ImportExportManager.export_nodes(_ab, [d["star"]], "SVG", path)).is_equal(OK)
	var data := SvgImp.parse(FileAccess.get_file_as_string(path))
	assert_int((data["items"] as Array).size()).is_equal(1)
	var sz: Vector2 = data["size"]
	assert_float(sz.x).is_between(70.0, 90.0)   # estrella de radio 40 (+ trazo)
	assert_float(sz.y).is_between(65.0, 90.0)
	assert_str(ImportExportManager.unique_path(_dir, "estrella", "svg").get_file()).is_equal("estrella (2).svg")

func test_convertir_archivos() -> void:
	var src := _dir.path_join("in.svg")
	var f := FileAccess.open(src, FileAccess.WRITE)
	f.store_string(FOREIGN_SVG)
	f.close()
	var n0 := _api.shapes().size()
	var undo0 := HistoryManager.get_undo_name()
	for fmt in ["PDF", "EPS", "VOP"]:
		var r: Dictionary = await ImportExportManager.convert_file(src, fmt)
		assert_bool(r["ok"]).override_failure_message("%s: %s" % [fmt, r["error"]]).is_true()
		assert_bool(FileAccess.file_exists(r["path"])).is_true()
	assert_int(_api.shapes().size()).is_equal(n0)   # el documento no cambia
	assert_str(HistoryManager.get_undo_name()).is_equal(undo0)

## PDF/EPS: el texto va como CURVAS con la fuente real (ningún lector PDF
## tiene tu fuente). SVG solo si se pide.
func test_texto_a_curvas_en_pdf_eps() -> void:
	_api.add_text(Vector2(40, 40), "Hola ñ", 40)
	var data := VX.collect(_ab)
	var curved := VX.texts_to_curves(data)
	assert_int((curved["items"] as Array).filter(func(i) -> bool: return i["t"] == "text").size()).is_equal(0)
	var glyphs: Dictionary = (curved["items"] as Array).filter(func(i) -> bool: return i["t"] == "path")[0]
	assert_int((glyphs["subs"] as Array).size()).is_greater(6)   # H o l a ñ (+ agujeros)
	var box := VX.bounds(curved)
	assert_float(box.position.x).is_between(38.0, 50.0)
	assert_float(box.size.y).is_between(25.0, 55.0)
	var pdf := VX.to_pdf(data).get_string_from_ascii()
	assert_bool(pdf.contains(" Tj")).is_false()
	assert_str(VX.to_eps(data)).not_contains(" show ")
	assert_str(VX.to_svg(data)).contains("<text")
	assert_str(VX.to_svg(VX.texts_to_curves(data))).not_contains("<text")

## SVG de herramientas reales: <style> CSS, <use>/<symbol>, degradado real,
## discontinuas, SVG anidado y tspan con dy.
const ADVANCED_SVG := """<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="300" height="200">
  <style>
    .rojo { fill: #ff0000; stroke: none }
    #azul, .otro { fill: rgb(0,0,255) }
    rect.borde { stroke: #00ff00; stroke-width: 6; stroke-dasharray: 10 5 }
  </style>
  <defs>
    <linearGradient id="base"><stop offset="0%" stop-color="#ffcc00"/><stop offset="100%" stop-color="#ff0066"/></linearGradient>
    <linearGradient id="g" xlink:href="#base" x1="0" y1="0" x2="0" y2="1"/>
    <symbol id="punto" viewBox="0 0 10 10"><circle cx="5" cy="5" r="5"/></symbol>
  </defs>
  <circle class="rojo" cx="20" cy="20" r="10"/>
  <circle id="azul" cx="60" cy="20" r="10"/>
  <rect class="borde" x="100" y="10" width="40" height="20" fill="none"/>
  <rect x="160" y="10" width="40" height="40" fill="url(#g)"/>
  <use xlink:href="#punto" x="220" y="10" width="20" height="20" fill="#123456"/>
  <svg x="0" y="100" width="100" height="50" viewBox="0 0 10 5"><rect width="10" height="5" fill="#0f0"/></svg>
  <text x="10" y="180" font-size="20">Uno<tspan x="10" dy="1.2em">Dos</tspan></text>
</svg>"""

func test_svg_avanzado_css_use_degradado() -> void:
	var data := SvgImp.parse(ADVANCED_SVG)
	var paths: Array = (data["items"] as Array).filter(func(i) -> bool: return i["t"] == "path")
	assert_int(paths.size()).is_equal(6)
	assert_object(paths[0]["fill"]).is_equal(Color(1, 0, 0))
	assert_object(paths[0]["stroke"]).is_null()
	assert_object(paths[1]["fill"]).is_equal(Color(0, 0, 1))
	assert_object(paths[2]["fill"]).is_null()
	assert_array(paths[2]["dash"]).is_equal([10.0, 5.0])
	assert_float(float(paths[2]["width"])).is_equal(6.0)
	var g: Dictionary = paths[3]["grad"]
	assert_int((g["stops"] as Array).size()).is_equal(2)         # heredadas de #base
	assert_float(float(g["angle"])).is_equal_approx(PI / 2.0, 0.001)   # vertical
	assert_object(paths[4]["fill"]).is_equal(Color.html("123456"))  # <use> → símbolo, hereda fill
	var sym_box := _bounds_subs(paths[4]["subs"])
	assert_vector(sym_box.size).is_equal_approx(Vector2(20, 20), Vector2(0.1, 0.1))
	var nested := _bounds_subs(paths[5]["subs"])
	assert_vector(nested.position).is_equal_approx(Vector2(0, 100), Vector2(0.1, 0.1))
	assert_vector(nested.size).is_equal_approx(Vector2(100, 50), Vector2(0.1, 0.1))
	var texts: Array = (data["items"] as Array).filter(func(i) -> bool: return i["t"] == "text")
	assert_int(texts.size()).is_equal(2)
	assert_float((texts[1]["xf"] as Transform2D).origin.y - (texts[0]["xf"] as Transform2D).origin.y).is_equal_approx(24.0, 0.1)
	# nodos: el degradado se conserva como degradado editable, la discontinua también
	var grp: Node2D = auto_free(SvgImp.build(data))
	var poly: VectorPolygon = grp.get_children().filter(func(n) -> bool: return n is VectorPolygon)[0]
	assert_object(poly.fill_gradient).is_not_null()
	var dashed = grp.get_children().filter(func(n) -> bool: return n is Path2D and n.stroke_style == 1)
	assert_int(dashed.size()).is_equal(1)

func _bounds_subs(subs: Array) -> Rect2:
	var r := Rect2(subs[0]["anchors"][0], Vector2.ZERO)
	for sub in subs:
		for p in sub["anchors"]:
			r = r.expand(p)
	return r
