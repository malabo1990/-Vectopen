extends GdUnitTestSuite

## Pestaña Vectorizar: imagen (Sprite2D) → trazados Bézier editables
## (VectorPath) alineados con la imagen, con deshacer. Usa el GDExtension
## nativo de verdad (vtracer); la imagen se genera aquí (sin archivos).

const VecPanel = preload("res://script_gdscript/ui/panels/effects/vectorize_panel.gd")

## 160×120: círculo rojo (centro 50,60 r 35) + rectángulo azul (100..150, 20..100).
func _test_image() -> Image:
	var img := Image.create(160, 120, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 120:
		for x in 160:
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(50, 60)) <= 35.0:
				img.set_pixel(x, y, Color(0.9, 0.1, 0.1))
			elif x >= 100 and x < 150 and y >= 20 and y < 100:
				img.set_pixel(x, y, Color(0.1, 0.2, 0.9))
	return img

func _sprite(holder: Node2D) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = ImageTexture.create_from_image(_test_image())
	sp.position = Vector2(300, 200)
	sp.scale = Vector2(2, 2)
	holder.add_child(sp)
	return sp

## Trazados (en global) que contienen el punto global `gp`.
func _paths_at(group: Node2D, gp: Vector2) -> Array:
	var out: Array = []
	for p in group.get_children():
		if p is Path2D and p.curve and p.curve.point_count >= 3:
			var poly: PackedVector2Array = p.global_transform * p.curve.tessellate(5, 4.0)
			if Geometry2D.is_point_in_polygon(gp, poly):
				out.append(p)
	return out

func test_imagen_a_trazados_bezier_alineados_y_con_deshacer() -> void:
	assert_bool(ClassDB.class_exists("ImageVectorizer")).override_failure_message("GDExtension no cargado").is_true()
	var holder: Node2D = auto_free(Node2D.new())
	add_child(holder)
	var sp := _sprite(holder)
	var panel: Node = auto_free(VecPanel.new())
	add_child(panel)
	get_tree().root.get_node("SelectionManager").set_selection([sp])
	InspectorCore._sync_selection()
	HistoryManager.clear()
	var group: Node2D = await panel.vectorize_selection()
	assert_object(group).is_not_null()
	assert_int(group.get_child_count()).is_greater(0)
	# Bézier de verdad: VectorPath con manejadores de curva
	var handles := 0
	for p in group.get_children():
		assert_bool(p is Path2D and p.get_script() != null).is_true()
		for i in p.curve.point_count:
			if p.curve.get_point_in(i).length() > 0.01 or p.curve.get_point_out(i).length() > 0.01:
				handles += 1
	assert_int(handles).override_failure_message("sin curvas Bézier").is_greater(4)
	# Alineado con la imagen: píxel de imagen → global por la transform del sprite
	var tl := -sp.texture.get_size() * 0.5
	var to_global := func(px: Vector2) -> Vector2: return sp.global_transform * (tl + px)
	var in_circle: Array = _paths_at(group, to_global.call(Vector2(50, 60)))
	assert_bool(in_circle.size() > 0).override_failure_message("el centro del círculo no está cubierto").is_true()
	var top: Path2D = in_circle[in_circle.size() - 1]
	var col: Color = top.get("fill_color")
	assert_bool(col.r > 0.6 and col.b < 0.4).override_failure_message("color %s" % col).is_true()
	assert_bool(_paths_at(group, to_global.call(Vector2(125, 60))).size() > 0).is_true()   # rectángulo
	assert_int(_paths_at(group, to_global.call(Vector2(5, 5))).size()).is_equal(0)      # fondo vacío
	assert_bool(sp.visible).is_false()   # original oculta (opción por defecto)
	# deshacer: se quita el grupo y vuelve la imagen
	HistoryManager.undo()
	assert_object(group.get_parent()).is_null()
	assert_bool(sp.visible).is_true()
	group.free()
	HistoryManager.clear()

func test_modo_blanco_y_negro_y_poligonos() -> void:
	var holder: Node2D = auto_free(Node2D.new())
	add_child(holder)
	var sp := _sprite(holder)
	var panel: Node = auto_free(VecPanel.new())
	add_child(panel)
	get_tree().root.get_node("SelectionManager").set_selection([sp])
	InspectorCore._sync_selection()
	panel._chk_bw.button_pressed = true
	panel._opt_mode.select(1)   # polígonos
	var opts: Dictionary = panel.options()
	assert_str(String(opts["color_mode"])).is_equal("binary")
	assert_str(String(opts["mode"])).is_equal("polygon")
	var group: Node2D = await panel.vectorize_selection()
	assert_object(group).is_not_null()
	assert_int(group.get_child_count()).is_greater(0)
	HistoryManager.clear()


## Un <path> con agujero (una "O": dos subtrazados) es UN VectorPath con
## `subpaths`, relleno par-impar: el centro queda HUECO (antes cada
## subtrazado era una forma rellena aparte que tapaba el interior).
func test_svg_con_agujero_es_un_trazado_con_hueco() -> void:
	var svg := '<svg><path d="M0 0 L100 0 L100 100 L0 100 Z M30 30 L70 30 L70 70 L30 70 Z" fill="#ff0000"/></svg>'
	var holder: Node2D = auto_free(Node2D.new())
	add_child(holder)
	var created: Array = SvgImportService.build_from_svg(svg, holder)
	assert_int(created.size()).is_equal(1)
	var vp: Path2D = created[0]
	assert_int((vp.get("subpaths") as Array).size()).is_equal(1)
	var G = load("res://script_gdscript/shapes/stroke_geom.gd")
	var rings: Array = [G.curve_points(vp.curve), G.curve_points(vp.get("subpaths")[0])]
	var polys: Array = G.evenodd_fill(rings)
	var covered := func(p: Vector2) -> bool:
		for poly in polys:
			if Geometry2D.is_point_in_polygon(p, poly):
				return true
		return false
	assert_bool(covered.call(Vector2(10, 60))).is_true()    # el aro
	assert_bool(covered.call(Vector2(50, 50))).is_false()   # el hueco
	# se guarda y se carga con su hueco
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	var data: Array = Ser.serialize_elements(holder)
	vp.free()
	Ser.instantiate_elements(holder, data)
	var back: Node = holder.get_child(holder.get_child_count() - 1)
	assert_int((back.get("subpaths") as Array).size()).is_equal(1)
