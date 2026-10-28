# =============================================================================
# REGRESIÓN: TODAS las figuras se redimensionan con las asas de Mover.
# Bug (2026-10-28, usuario: "estrellas y otros no puede drag para cambiar
# tamaño"): _snapshot() solo guardaba `size` de rectángulo y elipse; la
# estrella no cambiaba de tamaño al arrastrar. Este test recorre además
# TODAS las clases que heredan de VectorShape con `size`, para que una
# figura nueva no vuelva a quedarse fuera.
# =============================================================================
extends GdUnitTestSuite

const DVec2Script = preload("res://script_gdscript/core/DVec2.gd")

## Clases que no son figuras dibujables (o necesitan escena 3D completa).
const SKIP := ["VectorShape", "VectorModel3D", "VectorBoolean", "VectorDrawer", "VectorGeometryCore"]

func _bounds(n: Node2D) -> Vector2:
	var geo: Array = n.get_evaluated_geometry()
	var have := false
	var bb := Rect2()
	for ring in geo:
		for p in (ring as PackedVector2Array):
			var g: Vector2 = n.to_global(p)
			if not have:
				bb = Rect2(g, Vector2.ZERO)
				have = true
			else:
				bb = bb.expand(g)
	return bb.size

## Arrastra el asa inferior derecha +60, +40 (como hace la caja de selección).
func _resize(canvas: Node2D, shape: Node2D) -> void:
	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = canvas
	tool.selected_shapes = [shape]
	tool.resize_handle = "br"
	tool.transform_initial_mouse = Vector2.ZERO
	var b := _bounds(shape)
	var c: Vector2 = shape.global_position
	tool.transform_macro_rect = Rect2(c - b / 2.0, b)
	tool.transform_initial_states = {shape: tool._snapshot(shape)}
	tool._apply_resize(Vector2(60, 40))

func _check_grows(shape: Node2D, label: String) -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	add_child(canvas)
	canvas.add_child(shape)
	if shape is VectorShape:
		shape.set_doc_position(DVec2Script.new(200.0, 200.0))
	await get_tree().process_frame
	var before := _bounds(shape)
	_resize(canvas, shape)
	var after := _bounds(shape)
	assert_float(after.x).override_failure_message("%s no crece en ancho: %s → %s" % [label, before, after]).is_greater(before.x + 20.0)
	assert_float(after.y).override_failure_message("%s no crece en alto: %s → %s" % [label, before, after]).is_greater(before.y + 10.0)

func test_star_resizes() -> void:
	var st: VectorStar = auto_free(VectorStar.new())
	st.size = Vector2(140, 140)
	await _check_grows(st, "Estrella")

func test_rectangle_and_ellipse_resize() -> void:
	var r: VectorRectangle = auto_free(VectorRectangle.new())
	r.size = Vector2(140, 100)
	await _check_grows(r, "Rectángulo")
	var e: VectorCircle = auto_free(VectorCircle.new())
	e.size = Vector2(140, 140)
	await _check_grows(e, "Elipse")

func test_polygon_drop_and_custom_shapes_resize() -> void:
	var p: VectorPolygon = auto_free(VectorPolygon.new())
	p.radius = 70.0
	p.sides = 5
	p.is_regular = true
	await _check_grows(p, "Polígono")
	for id in ["heart", "cloud", "moon"]:
		var cs: VectorPolygon = auto_free(VectorPolygon.new())
		var verts := PackedVector2Array()
		for v in PanelPolygon.custom_points(id):
			verts.append(v * 70.0)
		cs.set_doc_vertices(DVec2Script.array_from_v2(verts))
		await _check_grows(cs, "Forma " + id)

## Red de seguridad: cualquier clase VectorShape con `size`, presente o futura.
func test_every_sized_vector_shape_resizes() -> void:
	var checked := 0
	for info in ProjectSettings.get_global_class_list():
		var cls: String = info["class"]
		if cls in SKIP or not _inherits_vector_shape(cls):
			continue
		var script: Script = load(info["path"])
		if script == null or not script.can_instantiate():
			continue
		var n = script.new()
		if not (n is Node2D) or not ("size" in n):
			if n is Node:
				n.free()
			continue
		auto_free(n)
		n.set("size", Vector2(120, 90))
		await _check_grows(n, cls)
		checked += 1
	# Rectángulo, elipse y estrella como mínimo.
	assert_int(checked).is_greater_equal(3)

func _inherits_vector_shape(cls: String) -> bool:
	var by_name := {}
	for info in ProjectSettings.get_global_class_list():
		by_name[info["class"]] = info["base"]
	var cur := cls
	for i in 12:
		if cur == "VectorShape":
			return true
		if not by_name.has(cur):
			return false
		cur = String(by_name[cur])
	return false
