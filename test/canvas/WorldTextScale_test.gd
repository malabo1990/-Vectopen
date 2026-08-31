extends GdUnitTestSuite

## REGRESION — RENDIMIENTO texto masivo:
## 1. Zoom alto: el font_size efectivo queda FIJO (no re-raster por tick).
## 2. 100+ textos: culling evita redibujar fuera de vista y el costo de
##    _apply_zoom de todos se mantiene acotado (no bloquea).
## 3. Contornos cacheados 1 sola vez (no se rebakean en cada zoom).
## 4. Geometría de mundo constante sigue intacta con el nuevo throttle.

func _nuevo(base: int = 24, texto: String = "Hola") -> WorldTextLabel:
	var l := WorldTextLabel.new()
	l.base_font_size = base
	l.text = texto
	l.add_theme_font_size_override("font_size", base)
	auto_free(l)
	return l

# 1. A zoom >= ZOOM_VECTOR_MIN el eff no cambia entre ticks de zoom
func test_zoom_alto_eff_fijo_no_reraster() -> void:
	var l := _nuevo(24, "Zoom fijo")
	add_child(l)
	await get_tree().process_frame

	l._apply_zoom(100.0)
	var eff_a: int = l.get_theme_font_size("font_size")
	var scale_a := l.scale
	l._apply_zoom(150.0)
	var eff_b: int = l.get_theme_font_size("font_size")
	var scale_b := l.scale
	# A zoom >=16: eff fijo en VECTOR_FONT y geometría constante
	assert_that(eff_a).is_equal(WorldTextLabel.VECTOR_FONT)
	assert_that(eff_b).is_equal(WorldTextLabel.VECTOR_FONT)
	assert_that(absf(scale_b.x - scale_a.x)).is_less(0.001)
	l.queue_free()

# 2. Geometría de mundo constante incluso a zoom extremo (1 sola letra)
func test_zoom_extremo_letra_gigante_mantiene_mundo() -> void:
	var l := _nuevo(24, "A")
	add_child(l)
	await get_tree().process_frame
	var base_world: Vector2 = l.size * l.scale
	l._apply_zoom(10000.0)
	var zoomed_world: Vector2 = l.size * l.scale
	# El bitmap del Label ya no crece (eff fijo), el escala mantiene mundo
	assert_that(zoomed_world.x).is_less(base_world.x + 5.0)
	assert_that(zoomed_world.y).is_less(base_world.y + 5.0)
	l.queue_free()

# 3. Los contornos son cacheados: build_outline_path no se llama de nuevo
func test_outline_cache_no_rebake() -> void:
	var l := _nuevo(24, "Cache outline")
	add_child(l)
	await get_tree().process_frame
	# Forzar cache
	var outline: Node2D = l._get_outline()
	l._apply_zoom(50.0)
	var outline2: Node2D = l._get_outline()
	assert_that(outline == outline2).is_true()
	# outline es propiedad de l (_cached_outline): lo libera el PREDELETE de l
	# vía auto_free — NO liberarlo aquí (doble free).

# 4. 150 textos: sumar _apply_zoom en todos debe ser rapido (sin bloqueo)
func test_150_textos_zoom_no_demora() -> void:
	var labels: Array[WorldTextLabel] = []
	for i in 150:
		var l := _nuevo(16, "Texto #%d con contenido variado y wrap normal" % i)
		l.position = Vector2(i * 40, i * 30)
		# Este test mide SOLO el coste de _apply_zoom; ocultamos para no
		# disparar el bake del overlay vectorial de 150 labels a la vez
		# (escenario irreal: el culling deja <20 visibles en pantalla).
		l.hide()
		add_child(l)
		labels.append(l)
	await get_tree().process_frame

	var t0 := Time.get_ticks_usec()
	for l in labels:
		l._apply_zoom(2.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	# Medida conservadora: 150 labels deben responder < 120 ms en headless
	assert_that(ms).is_less(120.0)
	# A zoom alto ya no re-rasterizan: el segundo ciclo es casi gratis
	var t1 := Time.get_ticks_usec()
	for l in labels:
		l._apply_zoom(100.0)
	var ms2 := (Time.get_ticks_usec() - t1) / 1000.0
	assert_that(ms2).is_less(120.0)
	# Y el 3ro (zoom ya fijo) es O(1) por label
	var t2 := Time.get_ticks_usec()
	for l in labels:
		l._apply_zoom(250.0)
	var ms3 := (Time.get_ticks_usec() - t2) / 1000.0
	assert_that(ms3).is_less(60.0)
	for l in labels:
		l.queue_free()

# 5. culling: un label fuera del viewport no regenera en _process
func test_culling_ignora_fuera_de_vista() -> void:
	var mundo := Node2D.new()
	mundo.name = "MundoCanvas"
	add_child(mundo)
	var cam := Camera2D.new()
	var node_canvas := Node2D.new()
	# Simulamos CanvasRoot con grupo (la fuente del _find_camera)
	node_canvas.add_to_group("_vectopen_canvas")
	node_canvas.add_child(cam)
	mundo.add_child(node_canvas)

	var visible_l := _nuevo(24, "Visible")
	visible_l.position = Vector2(100, 100)
	node_canvas.add_child(visible_l)
	var invisible_l := _nuevo(24, "Invisible")
	invisible_l.position = Vector2(50000, 50000)  # lejos del viewport
	node_canvas.add_child(invisible_l)

	cam.enabled = true
	cam.make_current()
	cam.position = Vector2(500, 500)
	cam.zoom = Vector2(1, 1)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_that(visible_l._is_visible_in_view()).is_true()
	assert_that(invisible_l._is_visible_in_view()).is_false()

	visible_l.queue_free()
	invisible_l.queue_free()
	mundo.queue_free()
