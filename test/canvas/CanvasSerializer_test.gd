extends GdUnitTestSuite

## Round-trip del CONTENIDO DEL LIENZO: dibujar figuras → serializar → borrar →
## reconstruir → mismas figuras con las mismas propiedades.
## Cierra el bug "guardas y se pierde todo lo dibujado".

const CANVAS := "res://scenes/canvas/canvas.tscn"
const CS = preload("res://scripts/canvas/canvas_serializer.gd")

func _container() -> Node2D:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	auto_free(s)
	return s.get_node("ArtboardsContainer") as Node2D


func _poblar(ab: ArtboardEditor) -> void:
	var c := VectorCircle.new()
	c.name = "C1"; c.size = Vector2(60, 60); c.fill_color = Color(1, 0, 0, 0.8)
	c.stroke_width = 3.0
	ab.add_child(c); c.position = Vector2(100, 100)

	var r := VectorRectangle.new()
	r.name = "R1"; r.size = Vector2(80, 40); r.corner_radius = 6.0
	r.set_corner_radii(Vector4(10, 2, 8, 0))   # radios independientes
	r.fill_color = Color(0, 0.5, 1, 1)
	ab.add_child(r); r.position = Vector2(200, 150); r.rotation = 0.3

	var p := VectorPolygon.new()
	p.name = "P1"; p.vertices = PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(10, 20)])
	p.closed = true
	ab.add_child(p); p.position = Vector2(300, 200)

	var line := Line2D.new()
	line.name = "L1"; line.points = PackedVector2Array([Vector2(0, 0), Vector2(50, 10), Vector2(90, 60)])
	line.width = 4.0; line.default_color = Color(0.1, 0.1, 0.1)
	ab.add_child(line); line.position = Vector2(50, 300)

	var txt := Node2D.new()
	txt.name = "T1"; txt.set_meta("shape_type", "text_title")
	txt.set_meta("text", "Hola Vectopen"); txt.set_meta("font_size", 28)
	txt.set_meta("line_spacing", 12)
	txt.set_meta("font_family", "Inter"); txt.set_meta("font_weight", 700)
	txt.set_meta("text_color", Color(0.9, 0.2, 0.1)); txt.set_meta("text_align", "center")
	txt.set_meta("text_outline_color", Color.BLACK); txt.set_meta("text_outline", 2)
	var lbl := WorldTextLabel.new(); lbl.name = "DisplayLabel"; lbl.text = "Hola Vectopen"
	txt.add_child(lbl)
	ab.add_child(txt); txt.position = Vector2(120, 400)


func test_roundtrip_contenido_lienzo() -> void:
	var cont_a := _container()
	await get_tree().process_frame
	var ab_a: ArtboardEditor = cont_a.get_child(0)
	ab_a.position = Vector2(10, 20)
	ab_a.artboard_size = Vector2(600, 800)
	_poblar(ab_a)

	# segundo artboard con una figura suelta al lado
	var ab2 := ArtboardEditor.new()
	ab2.artboard_size = Vector2(400, 400)
	cont_a.add_child(ab2); ab2.position = Vector2(1000, 0); ab2.name = "AB2"
	var solo := VectorCircle.new(); solo.name = "Solo"; solo.size = Vector2(30, 30)
	ab2.add_child(solo); solo.position = Vector2(50, 50)
	await get_tree().process_frame

	var data := CS.serialize_container(cont_a)
	assert_int(data["artboards"].size()).is_equal(2)
	assert_int(data["artboards"][0]["elements"].size()).is_equal(5)

	# reconstruir en un contenedor FRESCO
	var cont_b := _container()
	await get_tree().process_frame
	CS.rebuild_container(cont_b, data)
	await get_tree().process_frame

	assert_int(cont_b.get_child_count()).is_equal(2)  # 2 artboards
	var ab_b: ArtboardEditor = cont_b.get_child(0)
	assert_vector(ab_b.position).is_equal(Vector2(10, 20))
	assert_vector(ab_b.artboard_size).is_equal(Vector2(600, 800))

	var by_name := {}
	for ch in ab_b.get_children():
		by_name[String(ch.name)] = ch

	# círculo
	var c: VectorCircle = by_name.get("C1")
	assert_object(c).is_not_null()
	assert_vector(c.size).is_equal(Vector2(60, 60))
	assert_that(c.fill_color.r8).is_equal(255)
	assert_float(c.stroke_width).is_equal_approx(3.0, 0.01)
	assert_vector(c.position).is_equal(Vector2(100, 100))

	# rectángulo (con rotación y esquina)
	var r: VectorRectangle = by_name.get("R1")
	assert_object(r).is_not_null()
	assert_vector(r.size).is_equal(Vector2(80, 40))
	var rr: Vector4 = r.get_corner_radii()
	assert_float(rr.x).is_equal_approx(10.0, 0.01)
	assert_float(rr.y).is_equal_approx(2.0, 0.01)
	assert_float(rr.z).is_equal_approx(8.0, 0.01)
	assert_float(rr.w).is_equal_approx(0.0, 0.01)
	assert_float(r.rotation).is_equal_approx(0.3, 0.001)

	# polígono
	var p: VectorPolygon = by_name.get("P1")
	assert_object(p).is_not_null()
	assert_int(p.vertices.size()).is_equal(3)

	# línea de pincel
	var l: Line2D = by_name.get("L1")
	assert_object(l).is_not_null()
	assert_int(l.points.size()).is_equal(3)
	assert_float(l.width).is_equal_approx(4.0, 0.01)

	# texto
	var t: Node2D = by_name.get("T1")
	assert_object(t).is_not_null()
	assert_str(String(t.get_meta("text"))).is_equal("Hola Vectopen")
	assert_int(int(t.get_meta("line_spacing"))).is_equal(12)
	assert_str(String(t.get_meta("font_family"))).is_equal("Inter")
	assert_int(int(t.get_meta("font_weight"))).is_equal(700)
	assert_str(String(t.get_meta("text_align"))).is_equal("center")
	assert_that(t.get_meta("text_color")).is_equal(Color(0.9, 0.2, 0.1))
	var lbl := t.get_node_or_null("DisplayLabel") as WorldTextLabel
	assert_object(lbl).is_not_null()
	assert_str(lbl.text).is_equal("Hola Vectopen")
	assert_int(lbl.get_theme_constant("line_spacing")).is_equal(12)
	assert_int(lbl.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	assert_that(lbl.get_theme_color("font_color")).is_equal(Color(0.9, 0.2, 0.1))
	assert_int(lbl.get_theme_constant("outline_size")).is_equal(2)
	# la fuente resuelta debe ser la variación de peso 700 de Inter
	assert_object(lbl.get_theme_font("font")).is_same(FontCore.get_font(FontCore.spec_from_node(t)))

	# 2º artboard + figura
	var ab2_b: ArtboardEditor = cont_b.get_child(1)
	assert_str(String(ab2_b.name)).is_equal("AB2")
	assert_int(ab2_b.get_children().filter(func(n): return n is VectorCircle).size()).is_equal(1)


func test_save_project_ahora_incluye_las_figuras() -> void:
	var cont := _container()
	await get_tree().process_frame
	_poblar(cont.get_child(0))
	await get_tree().process_frame

	var path := "user://__test_cs_roundtrip.vtc"
	DataRepository.save_project(path)

	# .vtc = contenedor plano VTC2: manifest + un chunk por artboard
	var manifest := CS.read_vtc_manifest(path)
	assert_bool(manifest.is_empty()).is_false()
	assert_int(manifest["artboards"].size()).is_equal(1)
	var chunk0 := JSON.stringify(CS.read_vtc_chunk(path, manifest["artboards"][0]))
	assert_bool(chunk0.contains("Hola Vectopen")).is_true()   # el texto dibujado está en el chunk
	assert_bool(chunk0.contains("circle")).is_true()
	CS.close_reader_cache()

	# Ciclo completo: cargar el archivo -> el lienzo vivo se reconstruye (lazy)
	DataRepository.load_project(path)
	for f in 8:
		await get_tree().process_frame
	var ab: ArtboardEditor = cont.get_child(0)
	var n_figuras := ab.get_children().filter(func(x):
		return x is VectorShape or x is Line2D or (x is Node2D and x.has_meta("shape_type"))
	).size()
	assert_int(n_figuras).is_equal(5)

	CS.close_reader_cache()   # soltar el handle antes de borrar el archivo
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_roundtrip_grupos_e_imagenes() -> void:
	var cont_a := _container()
	await get_tree().process_frame
	var ab: ArtboardEditor = cont_a.get_child(0)

	# grupo con 2 figuras dentro
	var grupo := Node2D.new()
	grupo.name = "MiGrupo"
	var g1 := VectorCircle.new(); g1.name = "G1"; g1.size = Vector2(10, 10)
	var g2 := VectorRectangle.new(); g2.name = "G2"; g2.size = Vector2(15, 15)
	grupo.add_child(g1); g1.position = Vector2(5, 5)
	grupo.add_child(g2); g2.position = Vector2(20, 20)
	ab.add_child(grupo); grupo.position = Vector2(100, 100)

	# imagen embebida
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 0.9, 1))
	var sp := Sprite2D.new()
	sp.name = "Img1"
	sp.texture = ImageTexture.create_from_image(img)
	ab.add_child(sp); sp.position = Vector2(300, 300)
	await get_tree().process_frame

	var data := CS.serialize_container(cont_a)
	var elems: Array = data["artboards"][0]["elements"]
	var kinds := elems.map(func(e): return e.get("kind"))
	assert_bool(kinds.has("group")).is_true()
	assert_bool(kinds.has("image")).is_true()

	var cont_b := _container()
	await get_tree().process_frame
	CS.rebuild_container(cont_b, data)
	await get_tree().process_frame
	var ab_b: ArtboardEditor = cont_b.get_child(0)

	var g := ab_b.get_node_or_null("MiGrupo")
	assert_object(g).is_not_null()
	assert_int(g.get_children().filter(func(x): return x is VectorShape).size()).is_equal(2)
	assert_vector(g.position).is_equal(Vector2(100, 100))

	var i := ab_b.get_node_or_null("Img1") as Sprite2D
	assert_object(i).is_not_null()
	assert_object(i.texture).is_not_null()
	assert_vector(Vector2(i.texture.get_width(), i.texture.get_height())).is_equal(Vector2(8, 8))


## SHADERS / CLIPPING / MÁSCARAS: el estado visual de CanvasItem sobrevive al
## round-trip (material shader + params, clip_children, light_mask, modulate,
## y las metas que Effect.gd escribe para sombra/glow).
func test_roundtrip_shaders_clipping_mascaras() -> void:
	var cont_a := _container()
	await get_tree().process_frame
	var ab: ArtboardEditor = cont_a.get_child(0)

	# figura con ShaderMaterial (código embebido) + parámetros
	var c := VectorCircle.new()
	c.name = "ConShader"; c.size = Vector2(40, 40)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform vec4 tint : source_color;\nuniform float amount;\nvoid fragment(){ COLOR = tint * amount; }"
	sm.shader = sh
	sm.set_shader_parameter("tint", Color(0.1, 0.2, 0.3, 1.0))
	sm.set_shader_parameter("amount", 0.75)
	c.material = sm
	c.modulate = Color(1, 0.5, 0.5, 0.9)
	c.light_mask = 5
	c.set_meta("shadow_enabled", true)
	c.set_meta("shadow_offset", Vector2(4, 4))
	ab.add_child(c); c.position = Vector2(60, 60)

	# grupo que RECORTA a sus hijos (máscara)
	var grupo := Node2D.new()
	grupo.name = "GrupoRecorte"
	grupo.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var gc := VectorRectangle.new(); gc.name = "Hijo"; gc.size = Vector2(20, 20)
	grupo.add_child(gc)
	ab.add_child(grupo); grupo.position = Vector2(200, 200)
	await get_tree().process_frame

	var data := CS.serialize_container(cont_a)

	var cont_b := _container()
	await get_tree().process_frame
	CS.rebuild_container(cont_b, data)
	await get_tree().process_frame
	var ab_b: ArtboardEditor = cont_b.get_child(0)

	var c_b := ab_b.get_node_or_null("ConShader")
	assert_object(c_b).is_not_null()
	assert_bool(c_b.material is ShaderMaterial).is_true()
	assert_object(c_b.material.shader).is_not_null()
	assert_that(c_b.material.get_shader_parameter("tint")).is_equal(Color(0.1, 0.2, 0.3, 1.0))
	assert_float(c_b.material.get_shader_parameter("amount")).is_equal_approx(0.75, 0.001)
	assert_int(c_b.light_mask).is_equal(5)
	assert_that(c_b.modulate.a8).is_equal(230)
	assert_bool(bool(c_b.get_meta("shadow_enabled"))).is_true()
	assert_vector(c_b.get_meta("shadow_offset")).is_equal(Vector2(4, 4))

	var g_b := ab_b.get_node_or_null("GrupoRecorte")
	assert_object(g_b).is_not_null()
	assert_int(int(g_b.clip_children)).is_equal(int(CanvasItem.CLIP_CHILDREN_AND_DRAW))


## Una FIGURA con figuras ANIDADAS dentro (rect > rect > círculo) y un TEXTO con
## una figura hija sobreviven al round-trip. Antes el serializador salía antes en
## cada `kind` y los hijos se perdían.
func test_roundtrip_figuras_anidadas_y_texto_con_hijo() -> void:
	var cont_a := _container()
	await get_tree().process_frame
	var ab: ArtboardEditor = cont_a.get_child(0)

	var padre := VectorRectangle.new(); padre.name = "Padre"; padre.size = Vector2(200, 200)
	ab.add_child(padre); padre.position = Vector2(100, 100)
	var hijo := VectorRectangle.new(); hijo.name = "Hijo"; hijo.size = Vector2(100, 100)
	padre.add_child(hijo); hijo.position = Vector2(20, 20)
	var nieto := VectorCircle.new(); nieto.name = "Nieto"; nieto.size = Vector2(40, 40)
	hijo.add_child(nieto); nieto.position = Vector2(10, 10)

	var txt := Node2D.new(); txt.name = "Titulo"
	txt.set_meta("shape_type", "text_title"); txt.set_meta("text", "Hola")
	txt.set_meta("width", 150.0); txt.set_meta("height", 40.0)
	ab.add_child(txt); txt.position = Vector2(400, 100)
	var deco := VectorCircle.new(); deco.name = "Deco"; deco.size = Vector2(30, 30)
	txt.add_child(deco); deco.position = Vector2(5, 5)
	await get_tree().process_frame

	var data := CS.serialize_container(cont_a)
	var cont_b := _container()
	await get_tree().process_frame
	CS.rebuild_container(cont_b, data)
	await get_tree().process_frame
	var ab_b: ArtboardEditor = cont_b.get_child(0)

	var padre_b := ab_b.get_node_or_null("Padre")
	assert_object(padre_b).is_not_null()
	var hijo_b := padre_b.get_node_or_null("Hijo")
	assert_object(hijo_b).is_not_null()
	assert_object(hijo_b.get_node_or_null("Nieto")).is_not_null()

	var txt_b := ab_b.get_node_or_null("Titulo")
	assert_object(txt_b).is_not_null()
	assert_object(txt_b.get_node_or_null("Deco")).is_not_null()


## Un TRAZO BÉZIER conserva su estilo editable (fill/stroke/grosor/closed) al
## guardar y recargar — antes el path se dibujaba con constantes fijas.
func test_roundtrip_trazo_bezier_con_estilo() -> void:
	var cont_a := _container()
	await get_tree().process_frame
	var ab: ArtboardEditor = cont_a.get_child(0)

	var vp := Path2D.new()
	vp.set_script(load("res://script_gdscript/shapes/VectorPath.gd"))
	vp.name = "Bezier1"
	var cu := Curve2D.new()
	cu.add_point(Vector2(0, 0), Vector2.ZERO, Vector2(20, 0))
	cu.add_point(Vector2(60, 40), Vector2(-20, 0), Vector2.ZERO)
	vp.curve = cu
	vp.set("stroke_color", Color(0.9, 0.1, 0.2, 1))
	vp.set("stroke_width", 7.5)
	vp.set("fill_color", Color(0.1, 0.9, 0.3, 0.4))
	vp.set("closed", true)
	ab.add_child(vp); vp.position = Vector2(120, 120)
	await get_tree().process_frame

	var data := CS.serialize_container(cont_a)
	var cont_b := _container()
	await get_tree().process_frame
	CS.rebuild_container(cont_b, data)
	await get_tree().process_frame

	var vp_b := (cont_b.get_child(0) as ArtboardEditor).get_node_or_null("Bezier1")
	assert_object(vp_b).is_not_null()
	assert_that(vp_b.get("stroke_color")).is_equal(Color(0.9, 0.1, 0.2, 1))
	assert_float(vp_b.get("stroke_width")).is_equal_approx(7.5, 0.01)
	assert_that(vp_b.get("fill_color")).is_equal(Color(0.1, 0.9, 0.3, 0.4))
	assert_bool(bool(vp_b.get("closed"))).is_true()
	assert_int(vp_b.curve.point_count).is_equal(2)


## Relleno con degradado (lineal en un rect, radial en un círculo) sobrevive al
## round-trip: stops, tipo y ángulo.
func test_roundtrip_relleno_degradado() -> void:
	var cont_a := _container()
	await get_tree().process_frame
	var ab: ArtboardEditor = cont_a.get_child(0)

	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color.RED, Color.YELLOW, Color.BLUE])
	var r := VectorRectangle.new()
	r.name = "GradRect"; r.size = Vector2(80, 40)
	r.fill_gradient_type = 0
	r.fill_gradient_angle = deg_to_rad(30)
	r.fill_gradient = g
	ab.add_child(r); r.position = Vector2(150, 150)

	var g2 := Gradient.new()
	g2.offsets = PackedFloat32Array([0.0, 1.0])
	g2.colors = PackedColorArray([Color.WHITE, Color.BLACK])
	var c := VectorCircle.new()
	c.name = "GradCircle"; c.size = Vector2(50, 50)
	c.fill_gradient_type = 1
	c.fill_gradient = g2
	ab.add_child(c); c.position = Vector2(300, 150)
	await get_tree().process_frame

	var data := CS.serialize_container(cont_a)
	var cont_b := _container()
	await get_tree().process_frame
	CS.rebuild_container(cont_b, data)
	await get_tree().process_frame
	var ab_b: ArtboardEditor = cont_b.get_child(0)

	var r_b := ab_b.get_node_or_null("GradRect") as VectorRectangle
	assert_object(r_b).is_not_null()
	assert_bool(r_b.has_gradient_fill()).is_true()
	assert_int(r_b.fill_gradient.get_point_count()).is_equal(3)
	assert_that(r_b.fill_gradient.get_color(1)).is_equal(Color.YELLOW)
	assert_float(r_b.fill_gradient_angle).is_equal_approx(deg_to_rad(30), 0.001)

	var c_b := ab_b.get_node_or_null("GradCircle") as VectorCircle
	assert_object(c_b).is_not_null()
	assert_bool(c_b.has_gradient_fill()).is_true()
	assert_int(int(c_b.fill_gradient_type)).is_equal(1)
