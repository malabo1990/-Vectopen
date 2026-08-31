extends GdUnitTestSuite

## REGRESION — WorldTextLabel (Label base SIEMPRE visible + overlay vectorial):
## 1. Geometria en EL MUNDO constante a cualquier zoom (_apply_zoom).
## 2. get_world_minimum_size refleja el contenido y NO se infla con el zoom.
## 3. set_world_size mantiene el rect de mundo estable con autowrap.
## 4. El parent Node2D nunca se escala (no rompe drag & drop).
## 5. build_outline_path produce Path2D validos (o null nunca-crasha).
## 6. El titulo del artboard es WorldTextLabel.

func _nuevo_label(base: int = 24, texto: String = "Hola") -> WorldTextLabel:
	var l := WorldTextLabel.new()
	l.base_font_size = base
	l.text = texto
	l.add_theme_font_size_override("font_size", base)
	auto_free(l)
	return l

func _con_camara(mundo: Node2D, zoom: float, cam: Camera2D) -> void:
	cam.enabled = true
	cam.make_current()
	cam.zoom = Vector2(zoom, zoom)
	await get_tree().process_frame
	await get_tree().process_frame

# 1. Rect en mundo constante al zoomear (2x, 3x) con camara real
func test_world_label_geometria_mundo_constante() -> void:
	var mundo := Node2D.new()
	mundo.name = "MundoCanvas"
	add_child(mundo)
	var cam := Camera2D.new()
	mundo.add_child(cam)
	var l := _nuevo_label(24, "Texto de prueba de geometria con varias palabras")
	l.add_theme_font_size_override("font_size", 24)
	mundo.add_child(l)
	l.set_process(false)  # el _process leería el viewport (zoom 1), lo silenciamos
	await get_tree().process_frame
	await get_tree().process_frame

	var base_world: Vector2 = l.size * l.scale

	# El runtime llama _apply_zoom cuando la camara del CanvasRoot cambia;
	# en el test lo forzamos con el zoom objetivo (mismo efecto).
	l._apply_zoom(2.0)
	await get_tree().process_frame
	assert_that(absf(l.get_theme_font_size("font_size") - 48)).is_less(1.0)
	assert_that(absf(l.scale.x - 0.5)).is_less(0.01)
	var s2: Vector2 = l.size * l.scale
	assert_that(base_world.distance_to(s2)).is_less(3.0)

	l._apply_zoom(3.0)
	await get_tree().process_frame
	var s3: Vector2 = l.size * l.scale
	assert_that(base_world.distance_to(s3)).is_less(3.0)

	cam.queue_free()
	mundo.queue_free()

# 2. Minimo en mundo estable (no inflado por el zoom)
func test_world_minimum_size_estable() -> void:
	var l := _nuevo_label(24, "Lorem ipsum dolor sit amet")
	add_child(l)
	await get_tree().process_frame

	var base_min := l.get_world_minimum_size()
	assert_that(base_min.x).is_greater(0.0)
	l._apply_zoom(2.0)
	var zoomed_min := l.get_world_minimum_size()
	assert_that(base_min.distance_to(zoomed_min)).is_less(6.0)
	l._apply_zoom(1.0)
	l.queue_free()

# 3. set_world_size + autowrap: el rect de mundo envuelve el contenido y
#    no se encoge al cambiar el zoom (crece si el contenido lo requiere).
func test_world_size_autowrap_estable() -> void:
	var l := _nuevo_label(24, "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam nec diam.")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	await get_tree().process_frame
	l.set_world_size(Vector2(350, 100))
	await get_tree().process_frame
	var antes: Vector2 = l.size * l.scale
	l._apply_zoom(2.0)
	var despues: Vector2 = l.size * l.scale
	# Con wrap correcto el ancho en mundo nunca baja de 350 y la altura
	# cubre las lineas (>= antes) — sin saltos de orden de magnitud.
	assert_that(despues.x).is_greater_equal(antes.x - 1.0)
	assert_that(despues.y).is_greater_equal(antes.y - 1.0)
	assert_that(despues.x).is_less(600.0)
	assert_that(despues.y).is_less(300.0)
	l.queue_free()

# 4. El parent Node2D nunca se escala
func test_world_label_no_escala_parent() -> void:
	var parent := Node2D.new()
	add_child(parent)
	var l := _nuevo_label(24, "Solo el label")
	parent.add_child(l)
	await get_tree().process_frame
	l._apply_zoom(5.0)
	assert_that(parent.scale).is_equal(Vector2.ONE)
	assert_that(parent.position).is_equal(Vector2.ZERO)
	parent.queue_free()

# 5. build_outline_path nunca crashea (null si fuente no registrada)
func test_build_outline_nunca_crashea() -> void:
	var l := _nuevo_label(24, "AaBbCc")
	add_child(l)
	await get_tree().process_frame
	var out: Node2D = l.build_outline_path()
	if out != null:
		var paths := 0
		for child in out.get_children():
			if child is Path2D and child.curve and child.curve.point_count >= 2:
				paths += 1
		assert_that(paths).is_greater(0)
	if out != null:
		out.free()  # Node2D desacoplado (fuera del árbol): free() directo

# 6. El titulo del artboard es WorldTextLabel (regresion del bug del titulo)
func test_artboard_titulo_es_world_text_label() -> void:
	var scene: Node2D = load("res://scenes/canvas/canvas.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var artboard := scene.get_node_or_null("ArtboardsContainer/Artboard")
	assert_object(artboard).is_not_null()
	var label := artboard.get_node_or_null("ArtboardTitle")
	assert_object(label).is_not_null()
	assert_that(label is WorldTextLabel).is_true()
	scene.queue_free()
