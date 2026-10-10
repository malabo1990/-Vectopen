extends GdUnitTestSuite

## RDP estaba escrito y configurado por preset (rdp_epsilon) pero nunca se
## invocaba en _finalizar_trazo_actual: el pincel solo aplicaba _thin_points
## (umbral de distancia plano), así que trazos casi rectos conservaban todos
## los puntos del muestreo Catmull-Rom. Este test cubre el wiring real.

const BRUSH := "res://script_gdscript/tools/brushtool.gd"

func test_rdp_reduce_puntos_en_tramo_recto_y_conserva_esquina() -> void:
	var tool: Node = auto_free(load(BRUSH).new())

	var points := PackedVector2Array()
	for i in range(21):
		points.append(Vector2(i * 5.0, 0.0))
	points.append(Vector2(100.0, 50.0))

	var simplified: PackedVector2Array = tool._rdp_iterative(points, 0.5)

	assert_int(simplified.size()).is_less(points.size())
	assert_vector(simplified[0]).is_equal(Vector2(0, 0))
	assert_vector(simplified[simplified.size() - 1]).is_equal(Vector2(100, 50))
	assert_bool(simplified.has(Vector2(100.0, 0.0))).is_true()

func test_rdp_epsilon_configurado_por_preset_y_no_vacio() -> void:
	for preset in ["potato", "low", "balanced", "high", "ultra"]:
		var settings: Dictionary = load(BRUSH)._make_settings(preset)
		assert_float(settings.rdp_epsilon).is_greater(0.0)

## _build_width_curve() lee raw_points/raw_pressures/raw_cum directamente
## (mismo patrón que el test de RDP: llenamos el estado interno a mano en vez
## de simular eventos de InputEventMouseMotion, que no llevan presión real
## fuera de un dispositivo físico).

func test_width_curve_con_presion_constante_da_ancho_plano() -> void:
	var tool: Node = auto_free(load(BRUSH).new())
	tool.raw_points = PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
	tool.raw_pressures = PackedFloat32Array([1.0, 1.0, 1.0])
	tool.raw_cum = PackedFloat32Array([0.0, 10.0, 20.0])

	var curve: Curve = tool._build_width_curve()

	assert_float(curve.sample(0.0)).is_equal_approx(1.0, 0.01)
	assert_float(curve.sample(0.5)).is_equal_approx(1.0, 0.01)
	assert_float(curve.sample(1.0)).is_equal_approx(1.0, 0.01)

func test_width_curve_con_presion_variable_va_de_fino_a_grueso() -> void:
	var tool: Node = auto_free(load(BRUSH).new())
	tool.raw_points = PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
	tool.raw_pressures = PackedFloat32Array([0.0, 0.5, 1.0])
	tool.raw_cum = PackedFloat32Array([0.0, 10.0, 20.0])

	var curve: Curve = tool._build_width_curve()

	assert_float(curve.sample(0.0)).is_equal_approx(tool.MIN_PRESSURE_WIDTH_SCALE, 0.01)
	assert_float(curve.sample(1.0)).is_equal_approx(1.0, 0.01)
	assert_bool(curve.sample(1.0) > curve.sample(0.0)).is_true()

func test_width_curve_con_trazo_degenerado_da_ancho_plano_por_defecto() -> void:
	var tool: Node = auto_free(load(BRUSH).new())
	tool.raw_points = PackedVector2Array([Vector2(0, 0)])
	tool.raw_pressures = PackedFloat32Array([0.3])
	tool.raw_cum = PackedFloat32Array([0.0])

	var curve: Curve = tool._build_width_curve()

	assert_float(curve.sample(0.0)).is_equal_approx(1.0, 0.01)
	assert_float(curve.sample(1.0)).is_equal_approx(1.0, 0.01)

## Ajuste de tamaño estilo Krita: Shift+clic-y-arrastre horizontal, sin
## dibujar. handle_input() solo necesita `canvas` válido para este camino
## (no llega a tocar target_artboard/artboards_container), a diferencia del
## flujo normal de dibujo.

func _make_tool_with_canvas() -> Node:
	var tool: Node = auto_free(load(BRUSH).new())
	var canvas: Node2D = auto_free(Node2D.new())
	canvas.name = "Canvas"
	add_child(canvas)
	canvas.add_child(tool)
	tool.canvas = canvas
	return tool

func test_shift_clic_arma_el_gesto_de_resize_sin_empezar_a_dibujar() -> void:
	var tool := _make_tool_with_canvas()

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.shift_pressed = true
	press.position = Vector2(100, 100)

	assert_bool(tool.handle_input(press)).is_true()
	assert_bool(tool._is_resizing).is_true()
	assert_bool(tool.is_drawing).is_false()

func test_arrastrar_a_la_derecha_agranda_el_pincel() -> void:
	var tool := _make_tool_with_canvas()
	var start_width: float = tool.brush_width

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.shift_pressed = true
	press.position = Vector2(100, 100)
	tool.handle_input(press)

	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(150, 100) # +50px derecha
	tool.handle_input(motion)

	var expected: float = start_width + 50.0 * tool.RESIZE_SENSITIVITY
	assert_float(tool.brush_width).is_equal_approx(expected, 0.01)

func test_arrastrar_a_la_izquierda_reduce_y_respeta_el_minimo() -> void:
	var tool := _make_tool_with_canvas()

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.shift_pressed = true
	press.position = Vector2(100, 100)
	tool.handle_input(press)

	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(-500, 100) # muy a la izquierda, debe saturar en el mínimo
	tool.handle_input(motion)

	assert_float(tool.brush_width).is_equal_approx(tool.MIN_BRUSH_WIDTH, 0.01)

func test_soltar_termina_el_gesto_sin_disparar_un_trazo() -> void:
	var tool := _make_tool_with_canvas()

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.shift_pressed = true
	press.position = Vector2(100, 100)
	tool.handle_input(press)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	assert_bool(tool.handle_input(release)).is_true()

	assert_bool(tool._is_resizing).is_false()
	assert_bool(tool.is_drawing).is_false()

func test_brush_styles_presets() -> void:
	var tool := _make_tool_with_canvas()
	tool.apply_brush_style("pencil")
	assert_str(tool.brush_style).is_equal("pencil")
	assert_float(tool.brush_width).is_equal(2.0)
	assert_float(tool.brush_opacity).is_equal(0.8)

	tool.apply_brush_style("marker")
	assert_str(tool.brush_style).is_equal("marker")
	assert_float(tool.brush_width).is_equal(12.0)
	assert_float(tool.brush_opacity).is_equal(0.65)

	tool.apply_brush_style("eraser")
	assert_str(tool.brush_style).is_equal("eraser")
	assert_bool(tool._eraser_mode).is_true()

func test_alt_click_straight_connected_line() -> void:
	var tool: BrushTool = _make_tool_with_canvas()
	var ab: Node2D = auto_free(Node2D.new()) as Node2D
	var container := Node2D.new()
	container.name = "VectorDrawingLayer"
	ab.add_child(container)
	tool.target_artboard = ab

	tool._last_stroke_end_pos = Vector2(50, 50)
	tool._last_stroke_artboard = ab

	var alt_click := InputEventMouseButton.new()
	alt_click.button_index = MOUSE_BUTTON_LEFT
	alt_click.pressed = true
	alt_click.alt_pressed = true
	alt_click.position = Vector2(200, 200)

	var handled: bool = tool.handle_input(alt_click)
	assert_bool(handled).is_true()
	assert_that(tool._last_stroke_end_pos).is_equal(Vector2(200, 200))
	assert_int(container.get_child_count()).is_equal(1)
	var line: Line2D = container.get_child(0) as Line2D
	assert_object(line).is_not_null()
	assert_int(line.points.size()).is_equal(2)
	assert_that(line.points[0]).is_equal(Vector2(50, 50))
	assert_that(line.points[1]).is_equal(Vector2(200, 200))


# ── Presión del lápiz (estilo Krita) ─────────────────────────────────────────
func _motion(pos: Vector2, pressure: float) -> InputEventMouseMotion:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.pressure = pressure
	return m

## Estado de "trazo empezado" sin pasar por el clic (que necesita artboards).
func _tool_drawing() -> Node:
	var tool := _make_tool_with_canvas()
	var ab: Node2D = auto_free(Node2D.new())
	add_child(ab)
	tool.target_artboard = ab
	tool.current_line = auto_free(Line2D.new())
	ab.add_child(tool.current_line)
	tool.is_drawing = true
	tool.raw_points = PackedVector2Array([Vector2.ZERO])
	tool.raw_pressures = PackedFloat32Array([1.0])
	tool.raw_cum = PackedFloat32Array([0.0])
	tool._first_pressure_pending = true
	tool.pressure_smoothing = 0.0
	return tool

func test_el_primer_punto_toma_la_presion_del_primer_movimiento() -> void:
	var tool := _tool_drawing()
	tool._last_pressure = 0.04   # final de un trazo anterior
	tool.handle_input(_motion(Vector2(30, 0), 0.3))
	assert_float(tool.raw_pressures[0]).is_equal_approx(0.3, 0.001)
	assert_bool(tool.pen_detected).is_true()

func test_raton_sin_presion_da_grosor_completo() -> void:
	var tool := _tool_drawing()
	tool.handle_input(_motion(Vector2(30, 0), 0.0))
	tool.handle_input(_motion(Vector2(60, 0), 0.0))
	for p in tool.raw_pressures:
		assert_float(p).is_equal(1.0)
	assert_bool(tool.pen_detected).is_false()

func test_estabilizado_filtra_el_temblor() -> void:
	var tool := _tool_drawing()
	tool.pressure_smoothing = 0.6
	tool.handle_input(_motion(Vector2(30, 0), 0.5))
	tool.handle_input(_motion(Vector2(60, 0), 1.0))   # salto brusco
	var p: float = tool.raw_pressures[tool.raw_pressures.size() - 1]
	assert_bool(p > 0.5 and p < 1.0).is_true()       # amortiguado

func test_curva_y_minimo_de_presion() -> void:
	var tool: Node = auto_free(load(BRUSH).new())
	tool.pressure_min = 0.2
	tool.pressure_gamma = 1.0
	assert_float(tool._pressure_to_scale(0.0)).is_equal_approx(0.2, 0.001)
	assert_float(tool._pressure_to_scale(0.5)).is_equal_approx(0.6, 0.001)
	tool.pressure_gamma = 0.6   # suave: a media presión ya engorda más
	assert_float(tool._pressure_to_scale(0.5)).is_greater(0.6)
	tool.pressure_size_enabled = false
	assert_float(tool._pressure_to_scale(0.1)).is_equal(1.0)

func test_la_presion_se_guarda_como_perfil_y_sobrevive_al_recargar() -> void:
	var tool: Node = auto_free(load(BRUSH).new())
	tool.raw_points = PackedVector2Array([Vector2(0, 0), Vector2(50, 0), Vector2(100, 0)])
	tool.raw_pressures = PackedFloat32Array([0.1, 1.0, 0.1])
	tool.raw_cum = PackedFloat32Array([0.0, 50.0, 100.0])
	var holder: Node2D = auto_free(Node2D.new())
	add_child(holder)
	var l := Line2D.new()
	l.points = tool.raw_points
	l.width = 10.0
	holder.add_child(l)
	l.width_curve = tool._build_width_curve()
	tool._store_pressure_profile(l)
	assert_bool(l.has_meta("stroke_profile")).is_true()
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	var data: Array = Ser.serialize_elements(holder)
	l.free()
	Ser.instantiate_elements(holder, data)
	var back: Line2D = null
	for c in holder.get_children():
		if c is Line2D:
			back = c
	assert_object(back).is_not_null()
	assert_object(back.width_curve).is_not_null()
	assert_float(back.width_curve.sample(0.5)).is_greater(0.9)
	assert_float(back.width_curve.sample(0.0)).is_less(0.4)


# ── Calidad Illustrator: ajuste Bézier + render + degradado 2D (tecla G) ─────
func _noisy_arc(seed_v: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pts := PackedVector2Array()
	for k in 141:
		var a := PI * 0.3 + float(k) / 140.0 * PI * 1.4
		pts.append(Vector2(cos(a), sin(a)) * 120.0 + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2)))
	return pts

func test_ajuste_bezier_pocas_curvas_y_cerca_del_arco_real() -> void:
	var T = load(BRUSH)
	var C = load("res://script_gdscript/shapes/curve_fit.gd")
	var sm: PackedVector2Array = T._gauss_smooth_positions(_noisy_arc(7), 4.4)
	var c: Curve2D = C.fit(sm, 1.1)
	assert_int(c.point_count).is_less(16)          # el temblor no genera nodos
	# la curva queda cerca del arco ideal (radio 120) y sin bucles
	for p in c.tessellate(6, 2.0):
		assert_float(absf(p.length() - 120.0)).is_less(3.0)

func test_ajuste_sin_manejadores_desbocados() -> void:
	var C = load("res://script_gdscript/shapes/curve_fit.gd")
	var c: Curve2D = C.fit(_noisy_arc(3), 1.0)
	for i in c.point_count - 1:
		var chord := c.get_point_position(i).distance_to(c.get_point_position(i + 1))
		assert_float(c.get_point_out(i).length()).is_less_equal(chord + 0.01)
		assert_float(c.get_point_in(i + 1).length()).is_less_equal(chord + 0.01)

func _brush_line() -> Line2D:
	var l: Line2D = auto_free(Line2D.new())
	l.points = PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(200, 40)])
	l.width = 12.0
	l.default_color = Color(0.2, 0.4, 0.9)
	add_child(l)
	return l

func test_render_de_calidad_oculta_el_line2d_y_expone_degradado() -> void:
	var R = load("res://script_gdscript/shapes/brush_stroke_render.gd")
	var l := _brush_line()
	var r = R.attach(l)
	assert_float(l.self_modulate.a).is_equal(0.0)
	assert_bool(r.has_gradient_fill()).is_false()
	r.ensure_default_gradient()
	assert_bool(r.has_gradient_fill()).is_true()
	assert_vector(r.get_gradient_p0_norm()).is_equal_approx(Vector2(0.1, 0.5), Vector2(0.001, 0.001))
	r.set_gradient_points(Vector2(0.2, 0.3), Vector2(0.8, 0.7))
	assert_vector(r.get_gradient_p1_norm()).is_equal_approx(Vector2(0.8, 0.7), Vector2(0.001, 0.001))
	# InspectorCore lo ve como degradado (ColorCore ya no apaga el modo G)
	var paint = InspectorCore._read_fill_paint(l)
	assert_str(String(paint["type"])).is_equal("linear")

func test_degradado_del_pincel_se_guarda_y_carga() -> void:
	var R = load("res://script_gdscript/shapes/brush_stroke_render.gd")
	var holder: Node2D = auto_free(Node2D.new())
	add_child(holder)
	var l := Line2D.new()
	l.points = PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	l.width = 10.0
	holder.add_child(l)
	var r = R.attach(l)
	r.ensure_default_gradient()
	r.fill_gradient_type = 1
	r.set_gradient_points(Vector2(0.25, 0.5), Vector2(0.75, 0.5))
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	var data: Array = Ser.serialize_elements(holder)
	l.free()
	Ser.instantiate_elements(holder, data)
	var back: Line2D = null
	for c in holder.get_children():
		if c is Line2D:
			back = c
	var rb = R.of(back)
	assert_object(rb).is_not_null()
	assert_bool(rb.has_gradient_fill()).is_true()
	assert_int(int(rb.fill_gradient_type)).is_equal(1)
	assert_vector(rb.get_gradient_p0_norm()).is_equal_approx(Vector2(0.25, 0.5), Vector2(0.001, 0.001))


## Precisión: forma conocida (S + bucle pequeño + espiral) con y sin temblor;
## el resultado no se aleja más de 2 px de lo que se quería dibujar (antes,
## con tolerancia fija alta, ~5.6 px) y no ondula.
func _intended_shape() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 120:
		var t := k / 119.0
		pts.append(Vector2(t * 300.0, sin(t * TAU) * 60.0))
	for k in range(1, 40):
		var a := -PI * 0.5 + k / 39.0 * TAU
		pts.append(Vector2(300, 0) + Vector2(cos(a), sin(a) + 1.0) * 12.0)
	for k in range(1, 80):
		var t := k / 79.0
		var r := 40.0 * (1.0 - t * 0.7)
		pts.append(Vector2(300, 0) + Vector2(cos(t * TAU * 1.2) * r + r, sin(t * TAU * 1.2) * r))
	return pts

func _max_dev(ref: PackedVector2Array, poly: PackedVector2Array) -> float:
	var worst := 0.0
	for p in ref:
		var best := INF
		for i in poly.size() - 1:
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[i + 1])))
		worst = maxf(worst, best)
	return worst

func test_ajuste_fiel_a_lo_dibujado_con_y_sin_temblor() -> void:
	var T = load(BRUSH)
	var G = load("res://script_gdscript/shapes/stroke_geom.gd")
	var ideal := _intended_shape()
	for noise in [0.0, 0.8, 1.5]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var noisy := PackedVector2Array()
		for p in ideal:
			noisy.append(p + Vector2(rng.randf_range(-noise, noise), rng.randf_range(-noise, noise)))
		var c: Curve2D = T.adaptive_fit(noisy, 1.0, 1.0)
		var dev := _max_dev(ideal, G.curve_points(c))
		assert_float(dev).override_failure_message("temblor %.1f: desviación %.2f px" % [noise, dev]).is_less(2.0)
		assert_int(c.point_count).is_less(25)

func test_mover_el_degradado_no_reconstruye_la_malla() -> void:
	var R = load("res://script_gdscript/shapes/brush_stroke_render.gd")
	var l := _brush_line()
	var r = R.attach(l)
	r.ensure_default_gradient()
	await get_tree().process_frame
	await get_tree().process_frame
	var draws := [0]
	r.draw.connect(func() -> void: draws[0] += 1)
	for i in 10:
		r.set_gradient_points(Vector2(0.1 + i * 0.02, 0.5), Vector2(0.9, 0.5))
		await get_tree().process_frame
	assert_int(draws[0]).is_equal(0)
	assert_object(r.material).is_not_null()   # lo pinta el shader (GPU)


## BUG real: tras perder el foco con Ctrl / Super pulsado (Super abre las
## actividades de GNOME, un diálogo, un clic que cambia el foco…) Godot no
## recibe el "soltar" y Input.is_key_pressed() se queda en true: el pincel
## solo dibujaba en horizontal / vertical. El bloqueo de eje debe leer los
## modificadores del PROPIO evento del ratón (los manda el SO y no se pegan).
func test_ctrl_pegado_en_el_estado_global_no_bloquea_el_eje() -> void:
	var stuck := InputEventKey.new()
	stuck.keycode = KEY_CTRL
	stuck.physical_keycode = KEY_CTRL
	stuck.pressed = true
	Input.parse_input_event(stuck)          # Ctrl "pegado" (sin soltar)
	Input.flush_buffered_events()
	assert_bool(Input.is_key_pressed(KEY_CTRL)).is_true()
	var tool := _tool_drawing()
	var m := _motion(Vector2(30, 25), 0.0)   # el evento dice: Ctrl NO pulsado
	m.ctrl_pressed = false
	tool.handle_input(m)
	var last: Vector2 = tool.raw_points[tool.raw_points.size() - 1]
	assert_vector(last).is_equal(Vector2(30, 25))   # diagonal: sin bloqueo
	var rel := InputEventKey.new()
	rel.keycode = KEY_CTRL
	rel.physical_keycode = KEY_CTRL
	rel.pressed = false
	Input.parse_input_event(rel)
	Input.flush_buffered_events()

func test_ctrl_del_evento_si_bloquea_el_eje() -> void:
	var tool := _tool_drawing()
	var m := _motion(Vector2(30, 5), 0.0)
	m.ctrl_pressed = true
	tool.handle_input(m)
	var last: Vector2 = tool.raw_points[tool.raw_points.size() - 1]
	assert_float(last.y).is_equal(0.0)   # bloqueado al eje horizontal


## BUG real: al levantar el lápiz llegan muestras con presión 0; se tomaban
## como "ratón" (grosor 100 %) y el trazo acababa en una MANCHA redonda del
## grosor máximo del pincel.
func test_levantar_el_lapiz_no_deja_mancha_al_final() -> void:
	var tool := _tool_drawing()
	var k := 0
	for p in [0.3, 0.35, 0.3, 0.25, 0.2]:
		k += 1
		tool.handle_input(_motion(Vector2(k * 12.0, 0), p))
	# despegue: presión 0 y un pequeño gancho hacia atrás
	tool.handle_input(_motion(Vector2(k * 12.0 + 4, 3), 0.0))
	tool.handle_input(_motion(Vector2(k * 12.0 + 1, 6), 0.0))
	for i in tool.raw_pressures.size():
		assert_float(tool.raw_pressures[i]).override_failure_message("muestra %d" % i).is_less(0.5)
	tool._trim_lift_off()
	var last: Vector2 = tool.raw_points[tool.raw_points.size() - 1]
	assert_float(last.y).is_less(4.0)   # el gancho del despegue se quitó

func test_raton_sigue_con_grosor_completo_aunque_antes_hubo_lapiz() -> void:
	var tool := _tool_drawing()
	tool.pen_detected = true          # se usó el lápiz en un trazo anterior
	tool.handle_input(_motion(Vector2(30, 0), 0.0))
	tool.handle_input(_motion(Vector2(60, 0), 0.0))
	for p in tool.raw_pressures:
		assert_float(p).is_equal(1.0)
