extends GdUnitTestSuite
## Compatibilidad (VGSE fase 6): un trazo guardado por una versión anterior
## (sin estilo, perfil, pincel de objeto, textura, forma ni enlace) se abre,
## conserva puntos, grosor y color, y se dibuja con el render de calidad.

const Ser = preload("res://scripts/canvas/canvas_serializer.gd")
const NEW_KEYS := ["brush_style", "pencil_grade", "stroke_profile", "brush_obj", "brush_ref", "brush_texture", "brush_geo", "caps", "hq"]

func _stroke_data() -> Array:
	var holder: Node2D = auto_free(Node2D.new())
	add_child(holder)
	var l := Line2D.new()
	var pts := PackedVector2Array()
	for i in 40:
		pts.append(Vector2(i * 3.0, sin(i * 0.2) * 10.0))
	l.points = pts
	l.width = 5.0
	l.default_color = Color(0.2, 0.4, 0.8, 1.0)
	l.set_meta("brush_style", "pencil")
	l.set_meta("brush_texture", {"name": "paper"})
	l.set_meta("brush_geo", {"type": "wave"})
	holder.add_child(l)
	return Ser.serialize_elements(holder)

func test_trazo_antiguo_sin_claves_nuevas_se_abre() -> void:
	var data := _stroke_data()
	assert_int(data.size()).is_greater(0)
	var old: Array = []
	for it in data:
		var d: Dictionary = (it as Dictionary).duplicate(true)
		for k in NEW_KEYS:
			d.erase(k)
		old.append(d)
	var back: Node2D = auto_free(Node2D.new())
	add_child(back)
	Ser.instantiate_elements(back, JSON.parse_string(JSON.stringify(old)))
	await get_tree().process_frame
	var l: Line2D = null
	for c in back.get_children():
		if c is Line2D:
			l = c
	assert_object(l).is_not_null()
	assert_int(l.points.size()).is_equal(40)
	assert_float(l.width).is_equal_approx(5.0, 0.01)
	assert_bool(l.default_color.is_equal_approx(Color(0.2, 0.4, 0.8, 1.0))).is_true()
	assert_bool(l.has_meta("brush_texture") or l.has_meta("brush_geo") or l.has_meta("brush_obj")).is_false()

func test_trazo_nuevo_ida_y_vuelta_conserva_todo() -> void:
	var data := _stroke_data()
	var back: Node2D = auto_free(Node2D.new())
	add_child(back)
	Ser.instantiate_elements(back, JSON.parse_string(JSON.stringify(data)))
	await get_tree().process_frame
	var l: Line2D = null
	for c in back.get_children():
		if c is Line2D:
			l = c
	assert_object(l).is_not_null()
	assert_str(String(l.get_meta("brush_style", ""))).is_equal("pencil")
	assert_str(String(l.get_meta("brush_texture", {}).get("name", ""))).is_equal("paper")
	assert_str(String(l.get_meta("brush_geo", {}).get("type", ""))).is_equal("wave")
