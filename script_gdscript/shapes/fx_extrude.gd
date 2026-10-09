# =============================================================================
# RUTA: res://script_gdscript/shapes/fx_extrude.gd
# Extrusión 3D del efecto "3D" (figuras y texto) como UNA malla con colores
# por vértice:
#   · paredes laterales iluminadas por una luz fija (arriba-izquierda) según
#     su orientación (Lambert), con los parámetros "highlight" / "shadow";
#   · degradado de profundidad: más claras junto a la cara frontal y más
#     oscuras al fondo (lo que da sensación de volumen);
#   · solo las paredes visibles (las que miran hacia la extrusión), pintadas
#     de la más lejana a la más cercana, más la tapa trasera.
# Antes: paredes con luz opuesta a la extrusión (todas casi igual de oscuras)
# y en el texto copias oscuras apiladas → parecía una sombra, no un volumen.
# =============================================================================
extends RefCounted


static func _signed_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var j := (i + 1) % pts.size()
		a += pts[i].x * pts[j].y - pts[j].x * pts[i].y
	return a * 0.5

## Malla de la extrusión. `contours`: anillos cerrados (exteriores y huecos)
## en el espacio donde se dibuja; `caps`: polígonos simples para la tapa
## trasera (p.ej. los glifos ya triangulables o la propia figura).
static func build(contours: Array, caps: Array, fx: Dictionary, base: Color) -> ArrayMesh:
	var depth := maxf(0.0, float(fx.get("depth", 8.0)))
	if depth < 0.25 or contours.is_empty():
		return null
	var ang := deg_to_rad(float(fx.get("angle", 45.0)))
	var dir := Vector2(cos(ang), sin(ang))
	var off := dir * depth
	var hi := clampf(float(fx.get("highlight", 70.0)) / 100.0, 0.0, 1.0)
	var sh := clampf(float(fx.get("shadow", 60.0)) / 100.0, 0.0, 1.0)
	# Base visible aunque el relleno sea muy oscuro (texto negro): las caras
	# laterales de un objeto negro se leen como grises con luz.
	var b := base
	if b.get_luminance() < 0.12:
		b = b.lerp(Color(0.55, 0.56, 0.6, b.a), 0.7)
	var lit := b.lightened(0.45 * hi)
	var dark := b.darkened(0.65 * sh)
	var far_k := 0.35 + 0.4 * sh
	# Luz desde el lado de la extrusión (girada 50°): así las paredes VISIBLES
	# tienen luces y sombras. Con una luz fija arriba-izquierda y extrusión
	# hacia abajo-derecha, todas las paredes visibles quedaban en penumbra
	# (casi negras) y el 3D del texto parecía una sombra.
	var L := dir.rotated(deg_to_rad(-50.0)).normalized()

	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	# 1. Tapa trasera (la más oscura)
	var back_col := dark.darkened(0.25)
	back_col.a = base.a
	for cap in caps:
		var poly := PackedVector2Array(cap)
		if poly.size() < 3:
			continue
		var moved := PackedVector2Array()
		for p in poly:
			moved.append(p + off)
		var idx := Geometry2D.triangulate_polygon(moved)
		for k in idx:
			verts.append(moved[k])
			cols.append(back_col)
	# 2. Paredes visibles, de la más lejana a la más cercana
	var walls: Array = []
	var rings: Array = []
	for c in contours:
		rings.append(PackedVector2Array(c))
	for ri in rings.size():
		var ring: PackedVector2Array = rings[ri]
		var n := ring.size()
		if n < 2:
			continue
		var ccw := _signed_area(ring) > 0.0
		# Hueco (la "o", la "a"…): dentro de un número impar de anillos. Su
		# pared mira HACIA el hueco: normal invertida respecto a un exterior.
		var depth_in := 0
		for rj in rings.size():
			if rj != ri and (rings[rj] as PackedVector2Array).size() >= 3 and Geometry2D.is_point_in_polygon(ring[0], rings[rj]):
				depth_in += 1
		if depth_in % 2 == 1:
			ccw = not ccw
		for i in n:
			var a: Vector2 = ring[i]
			var e: Vector2 = ring[(i + 1) % n]
			var edge := e - a
			if edge.length_squared() < 1e-6:
				continue
			# Normal EXTERIOR (en y-abajo: CCW de área positiva → derecha)
			var nrm := Vector2(edge.y, -edge.x).normalized() if ccw else Vector2(-edge.y, edge.x).normalized()
			if nrm.dot(dir) <= 0.0:
				continue   # mira hacia atrás: la tapa la cubre
			walls.append([(a + e) * 0.5, a, e, nrm])
	walls.sort_custom(func(p, q): return p[0].dot(dir) > q[0].dot(dir))
	for w in walls:
		var a: Vector2 = w[1]
		var e: Vector2 = w[2]
		var nrm: Vector2 = w[3]
		var lambert := clampf(nrm.dot(L) * 0.5 + 0.5, 0.0, 1.0)
		var near := dark.lerp(lit, lambert)
		near.a = base.a
		var far := near.darkened(far_k)
		far.a = base.a
		# dos triángulos: a, e, e+off / a, e+off, a+off
		verts.append_array(PackedVector2Array([a, e, e + off, a, e + off, a + off]))
		cols.append_array(PackedColorArray([near, near, far, near, far, far]))
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
