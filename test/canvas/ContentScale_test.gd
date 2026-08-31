extends GdUnitTestSuite

## STRESS — Sistema de gestión de contenido masivo.
## 1. 1.000 labels: creación + un frame (sin render pesado) acotada.
## 2. Culling global: con la cámara mirando un área, los labels fuera
##    quedan con visible=false y process=false (no pagan frame).
## 3. Costo por frame escaneando 1.000 objetos < 30ms.
## 4. Edición (cambiar texto de 1 label) NO toca el resto (cache por label).

const CONTENT_COUNT := 1000

func _hacer_label(i: int, pos: Vector2) -> WorldTextLabel:
	var l := WorldTextLabel.new()
	l.base_font_size = 14
	l.text = "Texto de contenido #%d con algunas palabras de relleno para el bloque de pruebas de escalado masivo" % i
	l.add_theme_font_size_override("font_size", 14)
	l.name = "Texto_%d" % i
	l.position = pos
	return l

func test_1000_labels_creacion_rapida() -> void:
	var t0 := Time.get_ticks_usec()
	for i in CONTENT_COUNT:
		var l := _hacer_label(i, Vector2(i * 12, i * 9))
		add_child(l)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("STRESS crear %d labels: %.1f ms" % [CONTENT_COUNT, ms])
	# En headless la creación pura debe ser corta (el draw es lo que pesa)
	assert_that(ms).is_less(2000.0)
	for child in get_children():
		if child is WorldTextLabel:
			child.queue_free()

func test_culling_global_apaga_fuera_de_vista() -> void:
	# Escenario: 500 labels en una fila; la cámara mira un trozo.
	var mundo := Node2D.new()
	mundo.name = "MundoCanvas"
	add_child(mundo)
	var cam := Camera2D.new()
	mundo.add_child(cam)
	for i in 500:
		var l := _hacer_label(i, Vector2(i * 300, 0))
		mundo.add_child(l)
	cam.enabled = true
	cam.make_current()
	cam.position = Vector2(1000, 0)
	cam.zoom = Vector2(1, 1)
	await get_tree().process_frame
	await get_tree().process_frame

	var manager := CullManager.new()
	manager.camera = cam
	manager.cull_margin = 200.0
	mundo.add_child(manager)
	# Un par de frames para que el CullManager procese
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var visibles := 0
	var total := 0
	for child in mundo.get_children():
		if child is WorldTextLabel:
			total += 1
			if child.visible:
				visibles += 1
	# Vista: x de 960-200 .. 1040+200 -> ~4 labels visibles de 500
	assert_that(visibles).is_less(20)
	assert_that(visibles).is_greater(0)
	assert_that(total).is_equal(500)
	cam.queue_free()
	mundo.queue_free()

func test_escaneo_1000_objetos_rapido() -> void:
	var mundo := Node2D.new()
	mundo.name = "MundoCanvas"
	add_child(mundo)
	var cam := Camera2D.new()
	mundo.add_child(cam)
	for i in 1000:
		mundo.add_child(_hacer_label(i, Vector2(i * 300, 0)))
	cam.enabled = true
	cam.make_current()
	cam.position = Vector2(0, 0)
	await get_tree().process_frame
	await get_tree().process_frame

	var manager := CullManager.new()
	manager.camera = cam
	mundo.add_child(manager)
	await get_tree().process_frame

	var t0 := Time.get_ticks_usec()
	for f in 6:
		manager._process(0.01)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 6.0
	print("STRESS scan 1000 objects: %.2f ms/frame" % ms)
	assert_that(ms).is_less(30.0)
	cam.queue_free()
	mundo.queue_free()

# 5. OBJETIVO 10.000 elementos (paridad con Inkscape): el escaneo global de
#    culling debe seguir acotado por frame y dejar solo lo visible activo.
func test_escaneo_10000_objetos_acotado() -> void:
	var mundo := Node2D.new()
	mundo.name = "MundoCanvas"
	add_child(mundo)
	auto_free(mundo)
	var cam := Camera2D.new()
	mundo.add_child(cam)
	# Rejilla 100x100 = 10.000 labels repartidos en un lienzo grande.
	for i in 10000:
		var col: int = i % 100
		var row: int = i / 100
		var l := _hacer_label(i, Vector2(col * 320, row * 90))
		l.set_process(false)  # arrancan apagados: el CullManager los enciende
		mundo.add_child(l)
	cam.enabled = true
	cam.make_current()
	cam.position = Vector2(1600, 450)
	cam.zoom = Vector2(1, 1)
	await get_tree().process_frame
	await get_tree().process_frame

	var manager := CullManager.new()
	manager.camera = cam
	manager.cull_margin = 300.0
	mundo.add_child(manager)
	await get_tree().process_frame

	# Coste puro del barrido de 10.000 objetos (2 frames = 1 escaneo real).
	var t0 := Time.get_ticks_usec()
	for f in 8:
		manager._process(0.016)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 8.0
	print("STRESS scan 10000 objects: %.2f ms/frame" % ms)
	# Presupuesto generoso en headless; en juego real esto es <1ms.
	assert_that(ms).is_less(60.0)

	var activos := 0
	var visibles := 0
	for child in mundo.get_children():
		if child is WorldTextLabel:
			if child.visible:
				visibles += 1
			if child.is_processing():
				activos += 1
	print("STRESS 10000: visibles=%d activos=%d" % [visibles, activos])
	# Solo lo que cabe en el viewport (+margen) queda vivo — el 98%+ de los
	# 10.000 no paga frame ni _draw.
	assert_that(visibles).is_less(250)
	assert_that(visibles).is_greater(0)
	assert_that(activos).is_equal(visibles)
	cam.queue_free()

# 6. LOD SUB-PIXEL: alejar el zoom hasta que TODOS los 10.000 caben en pantalla
#    pero cada label es un borrón < min_screen_px → el CullManager los apaga
#    igualmente (texto ilegible = no se dibuja). Es lo que evita el bajón a
#    ~20 FPS al alejar del todo.
func test_lod_subpixel_apaga_texto_ilegible() -> void:
	var mundo := Node2D.new()
	mundo.name = "MundoCanvas"
	add_child(mundo)
	auto_free(mundo)
	var cam := Camera2D.new()
	mundo.add_child(cam)
	for i in 4000:
		var col: int = i % 80
		var row: int = i / 80
		var l := _hacer_label(i, Vector2(col * 300, row * 80))
		l.set_process(false)
		mundo.add_child(l)
	cam.enabled = true
	cam.make_current()

	var manager := CullManager.new()
	manager.camera = cam
	mundo.add_child(manager)

	# a) zoom normal centrado en la rejilla: hay labels visibles
	cam.position = Vector2(80 * 300, 50 * 80) * 0.5
	cam.zoom = Vector2(1, 1)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var vis_normal := 0
	for c in mundo.get_children():
		if c is WorldTextLabel and c.visible:
			vis_normal += 1
	print("LOD: visibles a zoom 1x = %d" % vis_normal)
	assert_that(vis_normal).is_greater(0)

	# b) zoom MUY alejado: toda la rejilla entra pero cada label mide < 1px
	cam.zoom = Vector2(0.02, 0.02)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var vis_lejos := 0
	for c in mundo.get_children():
		if c is WorldTextLabel and c.visible:
			vis_lejos += 1
	print("LOD: visibles a zoom 0.02x = %d (de 4000)" % vis_lejos)
	# El LOD sub-pixel debe dejar (casi) nada encendido.
	assert_that(vis_lejos).is_less(30)
	cam.queue_free()
