extends GdUnitTestSuite

## Suite de pruebas para Boolean no destructivo, Shape Builder y Mask/Clip (GeometryProvider)
## Verifica operaciones booleanas, actualización dinámica al mover hijos,
## detección de regiones atómicas en Shape Builder, máscaras sin convertir a curvas,
## y curvas de bisel 3D (Photoshop Bevel Contour).

const VectorGeometryCore = preload("res://script_gdscript/shapes/VectorGeometryCore.gd")
const VectorBooleanScript = preload("res://script_gdscript/shapes/VectorBoolean.gd")
const ShapeBuilderToolScript = preload("res://script_gdscript/tools/ShapeBuilderTool.gd")
const BooleanCoreScript = preload("res://autoloads/BooleanCore.gd")

func test_boolean_operations_union_subtract_intersect_exclude() -> void:
	# Crear dos rectángulos superpuestos:
	# Rect A: de (0, 0) a (100, 100)
	var r1: VectorRectangle = auto_free(VectorRectangle.new())
	r1.size = Vector2(100, 100)
	r1.position = Vector2(50, 50)

	# Rect B: de (50, 0) a (150, 100)
	var r2: VectorRectangle = auto_free(VectorRectangle.new())
	r2.size = Vector2(100, 100)
	r2.position = Vector2(100, 50)

	var vb: VectorShape = auto_free(VectorBooleanScript.new())
	add_child(vb)
	vb.add_child(r1)
	vb.add_child(r2)

	# 1. Unión
	vb.set("operation", "union")
	var union_polys = vb.get_evaluated_geometry()
	assert_bool(union_polys.size() >= 1).is_true()
	var union_pts: PackedVector2Array = union_polys[0]
	assert_bool(union_pts.size() >= 4).is_true()

	# 2. Sustracción (R1 menos R2)
	vb.set("operation", "subtract")
	var sub_polys = vb.get_evaluated_geometry()
	assert_bool(sub_polys.size() >= 1).is_true()

	# 3. Intersección (Zona de solapamiento 50x100)
	vb.set("operation", "intersect")
	var inter_polys = vb.get_evaluated_geometry()
	assert_bool(inter_polys.size() >= 1).is_true()
	var inter_box: Rect2 = vb.get_local_bounding_box(inter_polys[0])
	assert_float(inter_box.size.x).is_equal_approx(50.0, 1.0)
	assert_float(inter_box.size.y).is_equal_approx(100.0, 1.0)

	# 4. Exclusión / XOR
	vb.set("operation", "exclude")
	var excl_polys = vb.get_evaluated_geometry()
	assert_bool(excl_polys.size() >= 2).is_true()


func test_boolean_dynamic_update_non_destructive() -> void:
	var r1: VectorRectangle = auto_free(VectorRectangle.new())
	r1.size = Vector2(100, 100)
	r1.position = Vector2(50, 50)

	var r2: VectorRectangle = auto_free(VectorRectangle.new())
	r2.size = Vector2(100, 100)
	r2.position = Vector2(100, 50)

	var vb: VectorShape = auto_free(VectorBooleanScript.new())
	add_child(vb)
	vb.add_child(r1)
	vb.add_child(r2)
	vb.set("operation", "intersect")

	var initial_inter = vb.get_evaluated_geometry()
	assert_bool(initial_inter.size() >= 1).is_true()
	var initial_box = vb.get_local_bounding_box(initial_inter[0])
	assert_float(initial_box.size.x).is_equal_approx(50.0, 1.0)

	# Mover el rectángulo original R2 hacia la derecha (solapamiento se reduce a 20px)
	r2.position = Vector2(130, 50)
	vb.call("invalidate_cache")

	var updated_inter = vb.get_evaluated_geometry()
	assert_bool(updated_inter.size() >= 1).is_true()
	var updated_box = vb.get_local_bounding_box(updated_inter[0])
	assert_float(updated_box.size.x).is_equal_approx(20.0, 1.0)

	# Los objetos originales siguen intactos como hijos de VectorBoolean
	assert_int(vb.call("get_source_shapes").size()).is_equal(2)
	assert_object(vb.call("get_source_shapes")[0]).is_equal(r1)
	assert_object(vb.call("get_source_shapes")[1]).is_equal(r2)


func test_boolean_as_mask_without_conversion() -> void:
	# Probar que un VectorBoolean puede funcionar directamente como máscara (clip_children)
	var vb: VectorShape = auto_free(VectorBooleanScript.new())
	add_child(vb)

	var c: VectorCircle = auto_free(VectorCircle.new())
	c.size = Vector2(80, 80)
	var r: VectorRectangle = auto_free(VectorRectangle.new())
	r.size = Vector2(80, 80)
	vb.add_child(c)
	vb.add_child(r)
	vb.set("operation", "union")

	# Activar modo de máscara de recorte de CanvasItem
	vb.clip_children = CanvasItem.CLIP_CHILDREN_ONLY

	# Verificar que cumple la interfaz GeometryProvider
	assert_bool(vb.has_method("get_evaluated_geometry")).is_true()
	var eval_geom = vb.get_evaluated_geometry()
	assert_bool(eval_geom.size() >= 1).is_true()

	# Añadir una imagen o contenido secundario como hijo recortado
	var sprite: Sprite2D = auto_free(Sprite2D.new())
	vb.add_child(sprite)
	assert_object(sprite.get_parent()).is_equal(vb)


func test_shape_builder_atomic_regions_and_creation() -> void:
	# Crear 2 polígonos simples superpuestos en espacio 2D
	var poly_a := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)
	])
	var poly_b := PackedVector2Array([
		Vector2(50, 0), Vector2(150, 0), Vector2(150, 100), Vector2(50, 100)
	])

	# El núcleo debe descomponerlos en 3 regiones atómicas: A-sola, Intersección, B-sola
	var regions = VectorGeometryCore.compute_atomic_regions([poly_a, poly_b])
	assert_int(regions.size()).is_equal(3)

	# Verificar que cada región tiene id, polígono y lista de fuentes
	for reg in regions:
		assert_bool(reg.has("id")).is_true()
		assert_bool(reg.has("polygon")).is_true()
		assert_bool((reg["polygon"] as PackedVector2Array).size() >= 3).is_true()
		assert_bool(reg.has("sources")).is_true()

	# Fusionar regiones 0 y 1 para construir una nueva forma compuesta
	var p0: PackedVector2Array = regions[0]["polygon"]
	var p1: PackedVector2Array = regions[1]["polygon"]
	var merged := Geometry2D.merge_polygons(p0, p1)
	assert_int(merged.size()).is_equal(1)

	# Construir el VectorPath resultante
	var vp: VectorPath = auto_free(VectorPath.new())
	vp.closed = true
	var curve := Curve2D.new()
	for pt in merged[0]:
		curve.add_point(pt)
	vp.curve = curve

	add_child(vp)
	vp.queue_redraw()
	await get_tree().process_frame

	# VectorPath implementa GeometryProvider
	assert_bool(vp.has_method("get_evaluated_geometry")).is_true()
	var vp_geom = vp.get_evaluated_geometry()
	assert_int(vp_geom.size()).is_equal(1)
	assert_bool(vp_geom[0].size() >= 4).is_true()

	# Probar ShapeBuilderTool sustracción interactiva con Alt
	var r1: VectorRectangle = auto_free(VectorRectangle.new())
	r1.size = Vector2(100, 100)
	add_child(r1)
	var r2: VectorRectangle = auto_free(VectorRectangle.new())
	r2.size = Vector2(100, 100)
	r2.position = Vector2(50, 0)
	add_child(r2)

	var sbt: ShapeBuilderTool = auto_free(ShapeBuilderTool.new())
	sbt.participant_shapes = [r1, r2]
	sbt.call("_recalculate_regions")
	assert_int(sbt._atomic_regions.size()).is_equal(3)

	# Simular seleccionar la región 1 (la intersección central) con Alt y sustraer
	sbt._selected_region_ids = [1]
	sbt._is_alt_pressed = true
	sbt.call("_commit_subtracted_regions")
	assert_int(sbt.participant_shapes.size()).is_equal(2)

	# Simular crear y fusionar regiones añadiendo el color azul distintivo
	var sbt_add: ShapeBuilderTool = auto_free(ShapeBuilderTool.new())
	var a1: VectorRectangle = auto_free(VectorRectangle.new())
	a1.size = Vector2(100, 100)
	add_child(a1)
	var a2: VectorRectangle = auto_free(VectorRectangle.new())
	a2.size = Vector2(100, 100)
	a2.position = Vector2(50, 0)
	add_child(a2)
	sbt_add.participant_shapes = [a1, a2]
	sbt_add.call("_recalculate_regions")
	sbt_add._selected_region_ids = [0, 1]
	sbt_add._is_alt_pressed = false
	sbt_add.call("_commit_merged_shape")
	assert_int(sbt_add.participant_shapes.size()).is_equal(3)
	var created_path = sbt_add.participant_shapes[2]
	assert_bool(created_path is VectorPath).is_true()
	assert_that((created_path as VectorPath).fill_color).is_equal(Color(0.2, 0.55, 0.9, 1.0))



func test_three_d_contour_curve_options() -> void:
	var r: VectorRectangle = auto_free(VectorRectangle.new())
	r.size = Vector2(100, 100)
	# Configurar 3D con curva de contorno estilo Photoshop (Chisel = 1, Gaussian = 2, Ring = 3, Cone = 4)
	var td_fx: Dictionary = {
		"type": "3D",
		"enabled": true,
		"depth": 12.0,
		"bevel": 10.0,
		"angle": 60.0,
		"highlight": 75.0,
		"shadow": 50.0,
		"contour": 3 # Ring / Double Bevel
	}
	r.effects = [td_fx]

	var state: Dictionary = r.get_state()
	var fx_list: Array = state["effects"]
	assert_int(fx_list.size()).is_equal(1)
	assert_int(fx_list[0]["contour"]).is_equal(3)

	add_child(r)
	r.queue_redraw()
	await get_tree().process_frame

	# Probar UI de three_d.tscn con Contour
	var td_scene: PackedScene = load("res://scenes/ui/panels/effects/fx/three_d.tscn")
	var td_ui: Control = auto_free(td_scene.instantiate())
	add_child(td_ui)
	td_ui.set_params(td_fx)
	var params: Dictionary = td_ui.get_params()
	assert_int(params["contour"]).is_equal(3)

	assert_float(params["depth"]).is_equal(12.0)
 
 
func test_boolean_core_lifecycle() -> void:
	var bc: Node = auto_free(BooleanCoreScript.new())
	add_child(bc)

	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)

	var r1: VectorRectangle = auto_free(VectorRectangle.new())
	r1.size = Vector2(100, 100)
	r1.position = Vector2(0, 0)
	parent.add_child(r1)

	var r2: VectorRectangle = auto_free(VectorRectangle.new())
	r2.size = Vector2(100, 100)
	r2.position = Vector2(50, 0)
	parent.add_child(r2)

	# 1. Validación de can_perform_boolean
	assert_bool(bc.call("can_perform_boolean", [r1, r2])).is_true()

	# 2. Aplicar Unión
	var vb: VectorShape = auto_free(bc.call("apply_operation", "union", [r1, r2]))
	assert_object(vb).is_not_null()
	assert_bool(bc.call("is_boolean", vb)).is_true()
	assert_str(bc.call("get_boolean_operation", vb)).is_equal("union")
	assert_int(vb.get_parent().get_instance_id()).is_equal(parent.get_instance_id())

	# 3. Cambiar operación viva mediante apply_operation
	bc.call("apply_operation", "subtract", [vb])
	assert_str(bc.call("get_boolean_operation", vb)).is_equal("subtract")

	# 4. Flatten / Convertir a Curvas Bézier
	var new_path: VectorPath = auto_free(bc.call("flatten_boolean", vb))
	assert_object(new_path).is_not_null()
	assert_bool(new_path is VectorPath).is_true()
	assert_bool(new_path.closed).is_true()
	assert_int(new_path.get_parent().get_instance_id()).is_equal(parent.get_instance_id())

	# 5. Probar Release sobre un nuevo booleano
	var r3: VectorRectangle = auto_free(VectorRectangle.new())
	r3.size = Vector2(80, 80)
	parent.add_child(r3)
	var r4: VectorRectangle = auto_free(VectorRectangle.new())
	r4.size = Vector2(80, 80)
	parent.add_child(r4)

	var vb2: VectorShape = auto_free(bc.call("apply_operation", "intersect", [r3, r4]))
	assert_object(vb2).is_not_null()
	assert_bool(r3.visible).is_false()

	var released = bc.call("release_boolean", vb2)
	assert_int(released.size()).is_equal(2)
	assert_bool(r3.visible).is_true()
	assert_bool(r4.visible).is_true()
	assert_int(r3.get_parent().get_instance_id()).is_equal(parent.get_instance_id())

	# 6. Probar Release llamando con un HIJO del booleano (debe resolver automáticamente al padre)
	var vb3: VectorShape = auto_free(bc.call("apply_operation", "union", [r3, r4]))
	assert_object(vb3).is_not_null()
	var released_via_child = bc.call("release_boolean", r3)
	assert_int(released_via_child.size()).is_equal(2)
	assert_bool(r3.visible).is_true()

	# 7. Probar Flatten directo sobre 2 figuras normales (Figma/Affinity style)
	var r5: VectorRectangle = auto_free(VectorRectangle.new())
	r5.size = Vector2(60, 60)
	parent.add_child(r5)
	var r6: VectorRectangle = auto_free(VectorRectangle.new())
	r6.size = Vector2(60, 60)
	r6.position = Vector2(30, 0)
	parent.add_child(r6)

	var flattened_multi: VectorPath = auto_free(bc.call("flatten_boolean", null))
	# O llamando pasando el primer elemento con get_selection preparado
	var sel_flat: VectorPath = auto_free(bc.call("apply_operation", "flatten", [r5, r6]))
	assert_object(sel_flat).is_not_null()
	assert_bool(sel_flat is VectorPath).is_true()
	assert_bool(sel_flat.closed).is_true()

