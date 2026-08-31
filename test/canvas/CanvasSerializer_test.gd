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
	assert_float(r.corner_radius).is_equal_approx(6.0, 0.01)
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
	var lbl := t.get_node_or_null("DisplayLabel") as WorldTextLabel
	assert_object(lbl).is_not_null()
	assert_str(lbl.text).is_equal("Hola Vectopen")

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
