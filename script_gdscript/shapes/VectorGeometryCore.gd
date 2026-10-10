# =============================================================================
# VECTOPEN — VECTOR GEOMETRY CORE
# RUTA: res://script_gdscript/shapes/VectorGeometryCore.gd
# Núcleo geométrico compartido para Boolean no destructivo, Shape Builder y Máscaras.
# =============================================================================
class_name VectorGeometryCore
extends RefCounted

## Extrae la geometría evaluada de cualquier nodo geométrico en coordenadas locales
static func get_evaluated_geometry(node: Node) -> Array[PackedVector2Array]:
	if not is_instance_valid(node):
		return []
	if node.has_method("get_evaluated_geometry"):
		return node.get_evaluated_geometry()
	if node.has_method("get_effect_points"):
		var pts: PackedVector2Array = node.get_effect_points()
		return [pts] if not pts.is_empty() else []
	if "curve" in node and node.curve != null:
		var pts = node.curve.get_baked_points()
		return [pts] if not pts.is_empty() else []
	if "polygon" in node:
		var pts = node.polygon
		return [pts] if not pts.is_empty() else []
	return []

## Transforma un conjunto de polígonos usando una Transform2D dada
static func transform_polygons(polys: Array[PackedVector2Array], xform: Transform2D) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for poly in polys:
		var transformed := PackedVector2Array()
		for pt in poly:
			transformed.append(xform * pt)
		if transformed.size() >= 3:
			result.append(transformed)
	return result

## Operación booleana binaria entre dos listas de polígonos
static func boolean_operation(op: String, polys_a: Array[PackedVector2Array], polys_b: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	if polys_a.is_empty() and polys_b.is_empty():
		return []
	var norm_op := op.to_lower().strip_edges()
	match norm_op:
		"union":
			var result := polys_a.duplicate()
			for b in polys_b:
				if b.size() < 3: continue
				if result.is_empty():
					result.append(b)
					continue
				var merged_any := false
				var next_res: Array[PackedVector2Array] = []
				for r in result:
					var m := Geometry2D.merge_polygons(r, b)
					if m.size() == 1 and not m.is_empty():
						# Se fusionaron en un solo polígono
						next_res.append(m[0])
						merged_any = true
					elif m.size() > 1:
						next_res.append_array(m)
						merged_any = true
					else:
						next_res.append(r)
				if not merged_any:
					next_res.append(b)
				result = next_res
			return result

		"subtract", "difference":
			var result := polys_a.duplicate()
			for b in polys_b:
				if b.size() < 3: continue
				var next_res: Array[PackedVector2Array] = []
				for r in result:
					var clipped := Geometry2D.clip_polygons(r, b)
					next_res.append_array(clipped)
				result = next_res
			return result

		"intersect", "intersection":
			var result: Array[PackedVector2Array] = []
			for a in polys_a:
				if a.size() < 3: continue
				for b in polys_b:
					if b.size() < 3: continue
					var inter := Geometry2D.intersect_polygons(a, b)
					result.append_array(inter)
			return result

		"exclude", "xor":
			var result := polys_a.duplicate()
			for b in polys_b:
				if b.size() < 3: continue
				var next_res: Array[PackedVector2Array] = []
				for r in result:
					var excl := Geometry2D.exclude_polygons(r, b)
					next_res.append_array(excl)
				result = next_res
			return result

		_:
			return polys_a

## Combina múltiples figuras secuencialmente con una operación booleana
static func compute_multi_boolean(op: String, shapes: Array, target_xform_inv: Transform2D = Transform2D.IDENTITY) -> Array[PackedVector2Array]:
	if shapes.is_empty():
		return []

	var valid_shapes: Array = []
	for s in shapes:
		if is_instance_valid(s) and (s is CanvasItem):
			valid_shapes.append(s)

	if valid_shapes.is_empty():
		return []

	# Obtener polígonos del primer nodo en el espacio de coordenadas objetivo
	var first = valid_shapes[0]
	var to_target: Transform2D = target_xform_inv * first.global_transform
	var accum := transform_polygons(get_evaluated_geometry(first), to_target)

	for i in range(1, valid_shapes.size()):
		var shape = valid_shapes[i]
		var xf: Transform2D = target_xform_inv * shape.global_transform
		var cur_polys := transform_polygons(get_evaluated_geometry(shape), xf)
		accum = boolean_operation(op, accum, cur_polys)

	return accum

## Particiona un conjunto de polígonos superpuestos en regiones atómicas disjuntas
## para la herramienta Shape Builder / Smart Fusion.
## Cada región es un diccionario: { "id": int, "polygon": PackedVector2Array, "centroid": Vector2, "sources": Array[int] }
static func compute_atomic_regions(input_polygons: Array[PackedVector2Array]) -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	var region_counter: int = 0

	for p_idx in range(input_polygons.size()):
		var cur_poly := input_polygons[p_idx]
		if cur_poly.size() < 3 or absf(_polygon_area(cur_poly)) < 1.0:
			continue

		if regions.is_empty():
			regions.append({
				"id": region_counter,
				"polygon": cur_poly,
				"centroid": _calc_centroid(cur_poly),
				"sources": [p_idx]
			})
			region_counter += 1
			continue

		var new_regions: Array[Dictionary] = []
		var remainder_parts: Array[PackedVector2Array] = [cur_poly]

		for reg in regions:
			var reg_poly: PackedVector2Array = reg["polygon"]
			var inter_polys := Geometry2D.intersect_polygons(reg_poly, cur_poly)

			if not inter_polys.is_empty():
				# Región intersectada: pertenece a los sources originales + el actual
				for ip in inter_polys:
					if ip.size() >= 3 and absf(_polygon_area(ip)) >= 1.0:
						var new_src: Array = (reg["sources"] as Array).duplicate()
						if not new_src.has(p_idx):
							new_src.append(p_idx)
						new_regions.append({
							"id": region_counter,
							"polygon": ip,
							"centroid": _calc_centroid(ip),
							"sources": new_src
						})
						region_counter += 1

				# Resto del polígono existente que NO cae en cur_poly
				var diff_polys := Geometry2D.clip_polygons(reg_poly, cur_poly)
				for dp in diff_polys:
					if dp.size() >= 3 and absf(_polygon_area(dp)) >= 1.0:
						new_regions.append({
							"id": region_counter,
							"polygon": dp,
							"centroid": _calc_centroid(dp),
							"sources": (reg["sources"] as Array).duplicate()
						})
						region_counter += 1
			else:
				# No hubo intersección, conservar la región previa tal cual
				new_regions.append(reg)

			# Restar la región existente del remainder de cur_poly
			var next_rem: Array[PackedVector2Array] = []
			for rem in remainder_parts:
				var clipped := Geometry2D.clip_polygons(rem, reg_poly)
				next_rem.append_array(clipped)
			remainder_parts = next_rem

		# Agregar partes restantes de cur_poly que no intersectaron con ninguna región anterior
		for rem in remainder_parts:
			if rem.size() >= 3 and absf(_polygon_area(rem)) >= 1.0:
				new_regions.append({
					"id": region_counter,
					"polygon": rem,
					"centroid": _calc_centroid(rem),
					"sources": [p_idx]
				})
				region_counter += 1

		regions = new_regions

	return regions

static func _calc_centroid(pts: PackedVector2Array) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in pts:
		sum += p
	return sum / float(pts.size())

static func _polygon_area(pts: PackedVector2Array) -> float:
	var n: int = pts.size()
	if n < 3:
		return 0.0
	var area: float = 0.0
	for i in range(n):
		var j := (i + 1) % n
		area += pts[i].x * pts[j].y
		area -= pts[j].x * pts[i].y
	return area * 0.5
