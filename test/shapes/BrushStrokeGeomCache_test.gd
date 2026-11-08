extends GdUnitTestSuite
## VGSE fase 1 — modelo / geometría derivada / caché: cambiar la PINTURA
## (color, opacidad, degradado) no recalcula la forma del trazo; cambiar lo
## que la define (puntos, grosor, presión, remates, estilo) sí.

const Render = preload("res://script_gdscript/shapes/brush_stroke_render.gd")

func _stroke(style: String = "") -> Array:
	var holder: Node2D = auto_free(Node2D.new())
	add_child(holder)
	var l := Line2D.new()
	var pts := PackedVector2Array()
	for i in 200:
		pts.append(Vector2(i * 3.0, sin(i * 0.1) * 40.0))
	l.points = pts
	l.width = 12.0
	if style != "":
		l.set_meta("brush_style", style)
	var c := Curve.new()
	c.add_point(Vector2(0, 0.2))
	c.add_point(Vector2(0.5, 1.0))
	c.add_point(Vector2(1, 0.2))
	l.width_curve = c
	holder.add_child(l)
	var r: Node2D = Render.attach(l)
	r._draw()
	return [l, r]

func test_cambiar_la_pintura_no_recalcula_la_geometria() -> void:
	for style in ["", "pencil", "airbrush", "calligraphy"]:
		var lr := _stroke(style)
		var l: Line2D = lr[0]
		var r: Node2D = lr[1]
		var b0: int = r.geom_builds
		assert_int(b0).is_equal(1)
		l.default_color = Color(0.9, 0.1, 0.2, 1.0)
		r._draw()
		l.default_color = Color(0.2, 0.3, 0.9, 0.5)   # opacidad
		r._draw()
		var g := Gradient.new()
		l.gradient = g
		r._draw()
		assert_int(r.geom_builds).override_failure_message("estilo «%s»: la pintura recalculó la forma" % style).is_equal(b0)

func test_cambiar_la_forma_si_recalcula() -> void:
	var lr := _stroke()
	var l: Line2D = lr[0]
	var r: Node2D = lr[1]
	var b := int(r.geom_builds)
	var pts := l.points
	pts[10] += Vector2(0, 5)
	l.points = pts
	r._draw()
	assert_int(r.geom_builds).is_equal(b + 1)
	l.width = 20.0
	r._draw()
	assert_int(r.geom_builds).is_equal(b + 2)
	l.width_curve.set_point_value(1, 0.5)   # presión editada en el sitio
	r._draw()
	assert_int(r.geom_builds).is_equal(b + 3)
	l.end_cap_mode = Line2D.LINE_CAP_BOX
	r._draw()
	assert_int(r.geom_builds).is_equal(b + 4)
	l.set_meta("brush_style", "pencil")
	r._draw()
	assert_int(r.geom_builds).is_equal(b + 5)
	r._draw()   # sin cambios: nada que recalcular
	assert_int(r.geom_builds).is_equal(b + 5)

## Lo ya dibujado no se mueve al seguir dibujando: el eje suavizado de un
## trazo y el del mismo trazo con más puntos coinciden salvo en el final.
func test_el_eje_no_se_mueve_al_seguir_dibujando() -> void:
	var pts := PackedVector2Array()
	for i in 300:
		pts.append(Vector2(i * 1.7, sin(i * 0.2) * 25.0 + (i % 3) * 0.8))
	var a: PackedVector2Array = Render._smooth_axis(pts.slice(0, 200), 5.0)
	var b: PackedVector2Array = Render._smooth_axis(pts, 5.0)
	var moved := 0
	for k in a.size() - 4:
		if a[k].distance_to(b[k]) > 0.001:
			moved += 1
	assert_int(moved).is_equal(0)
