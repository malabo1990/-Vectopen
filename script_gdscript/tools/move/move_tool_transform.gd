# =============================================================================
# RUTA: res://script_gdscript/tools/move/move_tool_transform.gd
# Transformaciones: redimensionado (vectores, texto, imágenes), rotación e imán
# inteligente (guías de alineación).
# Parte de la herramienta Mover (MoveTool), dividida por capas de herencia:
#   move_tool_core → transform → ops → threading → keyboard → 3d → draw → MoveTool
# El código se movió TAL CUAL desde MoveTool.gd (sin cambios de comportamiento).
# =============================================================================
extends "res://script_gdscript/tools/move/move_tool_core.gd"


# ── Redimensionado Geométrico Avanzado de Vectores y Texto ────────────────────

func _apply_resize(gm: Vector2, mods: Dictionary = {}) -> void:
	var shift: bool = mods.get("shift", Input.is_key_pressed(KEY_SHIFT))
	var alt: bool = mods.get("alt", Input.is_key_pressed(KEY_ALT))
	var ctrl: bool = mods.get("ctrl", Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META))
	var delta: Vector2 = gm - transform_initial_mouse
	var ow: float = transform_macro_rect.size.x
	var oh: float = transform_macro_rect.size.y
	if ow < 1.0: ow = 1.0
	if oh < 1.0: oh = 1.0

	var rect_pos: Vector2 = transform_macro_rect.position
	var rect_end: Vector2 = transform_macro_rect.end
	var rect_center: Vector2 = transform_macro_rect.get_center()

	var pivot: Vector2 = rect_center
	var sx: float = 1.0
	var sy: float = 1.0

	match resize_handle:
		"rc":
			sx = (ow + delta.x) / ow
			pivot = Vector2(rect_pos.x, rect_center.y)
		"lc":
			sx = (ow - delta.x) / ow
			pivot = Vector2(rect_end.x, rect_center.y)
		"bc":
			sy = (oh + delta.y) / oh
			pivot = Vector2(rect_center.x, rect_pos.y)
		"tc":
			sy = (oh - delta.y) / oh
			pivot = Vector2(rect_center.x, rect_end.y)
		"br":
			sx = (ow + delta.x) / ow
			sy = (oh + delta.y) / oh
			pivot = rect_pos
		"bl":
			sx = (ow - delta.x) / ow
			sy = (oh + delta.y) / oh
			pivot = Vector2(rect_end.x, rect_pos.y)
		"tr":
			sx = (ow + delta.x) / ow
			sy = (oh - delta.y) / oh
			pivot = Vector2(rect_pos.x, rect_end.y)
		"tl":
			sx = (ow - delta.x) / ow
			sy = (oh - delta.y) / oh
			pivot = rect_end

	if alt:
		pivot = rect_center
		if resize_handle in ["rc", "lc", "br", "bl", "tr", "tl"]:
			sx = (ow + (delta.x if resize_handle in ["rc", "br", "tr"] else -delta.x) * 2.0) / ow
		if resize_handle in ["bc", "tc", "br", "bl", "tr", "tl"]:
			sy = (oh + (delta.y if resize_handle in ["bc", "br", "bl"] else -delta.y) * 2.0) / oh

	# 13.2 Shift + Arrastrar borde: ajustar grosor de trazo de forma contextual
	if shift and resize_handle in ["rc", "lc", "bc", "tc"]:
		_is_stroke_adjusting = true
		# Signo igual que sx/sy más arriba (rc/bc suman delta, lc/tc lo restan):
		# "arrastrar el handle hacia afuera del centro = engrosar" debe sentirse
		# igual en los 4 bordes. Sin este flip, lc/tc quedaban invertidos (tirar
		# hacia afuera adelgazaba en vez de engrosar) — bug real reportado por
		# el usuario ("shift con drag para grosor no funciona bien").
		var raw_delta: float = delta.x if resize_handle in ["rc", "lc"] else delta.y
		var dir_sign: float = 1.0 if resize_handle in ["rc", "bc"] else -1.0
		var stroke_delta: float = raw_delta * dir_sign * 0.15
		# Shift = only the dragged side (shapes with per-side strokes);
		# Shift+Alt = the four sides together.
		var side_idx: int = {"tc": 0, "rc": 1, "bc": 2, "lc": 3}[resize_handle]
		for shape in selected_shapes:
			if not is_instance_valid(shape):
				continue
			var snap_s: Dictionary = transform_initial_states.get(shape, {})
			var init_w: float = float(snap_s["stroke_width"]) if snap_s.has("stroke_width") else _get_shape_stroke_width(shape)
			if not alt and shape.has_method("set_side_width"):
				var sides: Vector4 = snap_s.get("stroke_sides", Vector4(-1, -1, -1, -1))
				for i in 4:
					if sides[i] < 0.0:
						sides[i] = init_w
				sides[side_idx] = maxf(0.0, sides[side_idx] + stroke_delta)
				shape.stroke_sides = sides
				continue
			var new_w: float = maxf(0.5, init_w + stroke_delta)
			_set_shape_stroke_width(shape, new_w)
			if shape.has_method("clear_side_strokes"):
				shape.clear_side_strokes()
		_update_bounding_box()
		canvas.queue_redraw()
		return

	if shift and resize_handle not in ["rc", "lc", "bc", "tc"]:
		var uniform_scale: float = max(abs(sx), abs(sy))
		sx = uniform_scale * sign(sx)
		sy = uniform_scale * sign(sy)

	# Regla de escalado para imágenes (Sprite2D):
	# - Sin Control: escala exactamente proporcional sin estirar nada la imagen.
	# - Con Control: permite estirar libremente en anchura o altura.
	var is_image_only: bool = _is_image_only_selection()
	if is_image_only and not ctrl:
		var u: float = 1.0
		if resize_handle in ["rc", "lc"]:
			u = abs(sx)
		elif resize_handle in ["bc", "tc"]:
			u = abs(sy)
		else:
			u = max(abs(sx), abs(sy))
		sx = u * sign(sx if abs(sx) > 0.001 else 1.0)
		sy = u * sign(sy if abs(sy) > 0.001 else 1.0)

	if abs(sx) < 0.01: sx = 0.01 * sign(sx)
	if abs(sy) < 0.01: sy = 0.01 * sign(sy)

	var scale_vec: Vector2 = Vector2(sx, sy)
	live_scale = scale_vec
	live_pivot = pivot

	for shape in selected_shapes:
		if not is_instance_valid(shape) or not transform_initial_states.has(shape):
			continue
		var snap: Dictionary = transform_initial_states[shape]

		if shape.has_meta("shape_type") and (shape.get_meta("shape_type") in ["text_paragraph", "text_title"]):
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			
			var calculated_width: float = max(40.0, snap["w"] * abs(sx))
			var calculated_height: float = max(20.0, snap["h"] * abs(sy))
			
			shape.set_meta("width", calculated_width)
			shape.set_meta("height", calculated_height)

			# La fuente SOLO cambia con Ctrl+arrastre (título y párrafo,
			# por ratio de ancho). Sin Ctrl el resize solo refluye:
			# el párrafo nunca cambia de tamaño solo. El undo lo cubre
			# el snapshot (font_size via _restore_transform).
			var new_font_size: int = -1
			var st: String = str(shape.get_meta("shape_type"))
			var is_corner_handle: bool = resize_handle in ["tl", "tr", "bl", "br"]
			if ctrl or (st == "text_title" and is_corner_handle):
				var w_ratio: float = abs(sx)
				if st == "text_title" and is_corner_handle and not ctrl:
					w_ratio = (abs(sx) + abs(sy)) * 0.5
				if absf(w_ratio - 1.0) > 0.0001:
					var orig_fs: int = int(snap.get("font_size", 16))
					new_font_size = clampi(int(round(float(orig_fs) * w_ratio)), 6, 400)
					shape.set_meta("font_size", new_font_size)
					# Tamaño de CADA run a la misma escala, desde la foto inicial
					# (no acumulativo frame a frame) — conserva todo el formato.
					TextCore.scale_runs(shape, snap.get("runs", []), float(new_font_size) / float(maxi(1, orig_fs)))
			
			_update_text_node_sizes(shape, calculated_width, calculated_height, new_font_size)
			continue

		if shape is Path2D and snap.has("g_path_nodes"):
			var curve: Curve2D = shape.curve
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			
			var data_nodes: Array = snap["g_path_nodes"]
			for i in range(curve.point_count):
				var node_data = data_nodes[i]
				var new_g_pos: Vector2 = pivot + (node_data["node"] - pivot) * scale_vec
				curve.set_point_position(i, shape.to_local(new_g_pos))
				
				var new_g_in: Vector2 = pivot + (node_data["in"] - pivot) * scale_vec
				var new_g_out: Vector2 = pivot + (node_data["out"] - pivot) * scale_vec
				
				curve.set_point_in(i, shape.to_local(new_g_in) - curve.get_point_position(i))
				curve.set_point_out(i, shape.to_local(new_g_out) - curve.get_point_position(i))
				
			var renderer = shape.get_node_or_null("Render_Visual")
			if renderer is Line2D:
				renderer.points = curve.get_baked_points()
			shape.queue_redraw()

		elif shape is Polygon2D and snap.has("g_poly_pts"):
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			
			var orig_g_poly: PackedVector2Array = snap["g_poly_pts"]
			var new_poly_pts = PackedVector2Array()
			for g_pt in orig_g_poly:
				var new_g_pt: Vector2 = pivot + (g_pt - pivot) * scale_vec
				new_poly_pts.append(shape.to_local(new_g_pt))
			shape.polygon = new_poly_pts
			
			if snap.has("g_stroke_pts"):
				var stroke = shape.get_node_or_null("Contorno_Stroke")
				if stroke is Line2D:
					var orig_g_stroke: PackedVector2Array = snap["g_stroke_pts"]
					var new_stroke_pts = PackedVector2Array()
					for g_pt in orig_g_stroke:
						var new_g_pt: Vector2 = pivot + (g_pt - pivot) * scale_vec
						new_stroke_pts.append(shape.to_local(new_g_pt))
					stroke.points = new_stroke_pts
			
			var l_min = new_poly_pts[0]
			var l_max = new_poly_pts[0]
			for p in new_poly_pts:
				l_min.x = min(l_min.x, p.x)
				l_min.y = min(l_min.y, p.y)
				l_max.x = max(l_max.x, p.x)
				l_max.y = max(l_max.y, p.y)
			shape.set_meta("size", l_max - l_min)
			shape.queue_redraw()

		elif snap.has("w") and snap.has("h") and not shape.has_meta("shape_type"):
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			shape.set("width", max(2.0, snap["w"] * abs(sx)))
			shape.set("height", max(2.0, snap["h"] * abs(sy)))
			shape.queue_redraw()

		elif snap.has("size"):
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			_sync_doc_position_from_native(shape)
			if shape is VectorShape and snap.has("doc_extent"):
				# Precisión doble real: el nuevo tamaño se calcula desde el valor
				# EXACTO capturado en _snapshot(), no desde el Vector2 float32 que
				# quedó guardado en .size tras el resize anterior — así el error
				# no se acumula operación tras operación.
				var orig_extent: DVec2 = snap["doc_extent"]
				var new_extent := DVec2.new(
					max(2.0, orig_extent.x * absf(sx)),
					max(2.0, orig_extent.y * absf(sy))
				)
				shape.set_doc_extent(new_extent)
			else:
				var new_size: Vector2 = Vector2(
					max(2.0, snap["size"].x * abs(sx)),
					max(2.0, snap["size"].y * abs(sy))
				)
				shape.set("size", new_size)
			shape.queue_redraw()

		elif snap.has("g_verts"):
			var orig_g_verts: PackedVector2Array = snap["g_verts"]
			var new_verts: PackedVector2Array = PackedVector2Array()
			for g_pt in orig_g_verts:
				var new_g_pt: Vector2 = pivot + (g_pt - pivot) * scale_vec
				new_verts.append(shape.to_local(new_g_pt))
			if shape is VectorShape and shape.has_doc_vertices():
				shape.set_doc_vertices(DVec2.array_from_v2(new_verts))
			else:
				shape.set("vertices", new_verts)
			shape.queue_redraw()

		elif shape is Line2D and snap.has("g_pts"):
			var orig_g_pts: PackedVector2Array = snap["g_pts"]
			var new_pts: PackedVector2Array = PackedVector2Array()
			for g_pt in orig_g_pts:
				var new_g_pt: Vector2 = pivot + (g_pt - pivot) * scale_vec
				new_pts.append(shape.to_local(new_g_pt))
			shape.points = new_pts
			shape.queue_redraw()

		elif shape is Sprite2D and snap.has("scale"):
			var orig_gpos: Vector2 = snap["gpos"]
			var orig_scale: Vector2 = snap["scale"]
			var s_vec: Vector2 = scale_vec
			if not ctrl and not is_image_only:
				var u: float = 1.0
				if resize_handle in ["rc", "lc"]:
					u = abs(s_vec.x)
				elif resize_handle in ["bc", "tc"]:
					u = abs(s_vec.y)
				else:
					u = max(abs(s_vec.x), abs(s_vec.y))
				s_vec = Vector2(u * sign(s_vec.x if abs(s_vec.x) > 0.001 else 1.0), u * sign(s_vec.y if abs(s_vec.y) > 0.001 else 1.0))
			shape.global_position = pivot + (orig_gpos - pivot) * s_vec
			shape.scale = orig_scale * s_vec
			shape.queue_redraw()

# ── Lógica de Rotación Pro ──────────────────────────────────────────────────

func _apply_rotation(gm: Vector2, mods: Dictionary = {}) -> void:
	var shift: bool = mods.get("shift", Input.is_key_pressed(KEY_SHIFT))
	var ctrl: bool = mods.get("ctrl", Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META))
	var angle_current: float = initial_macro_center.angle_to_point(gm)
	var angle_initial: float = initial_macro_center.angle_to_point(transform_initial_mouse)
	var angle_delta: float = angle_current - angle_initial

	if shift:
		var snap_step: float = deg_to_rad(15.0)
		angle_delta = round(angle_delta / snap_step) * snap_step
	elif ctrl:
		# Redondeo a grado entero (sin Shift) — mismo par de modificadores de
		# rotación que IHTML (bounding-box.js _onRotationStart: shift=snap a
		# 15°, ctrl=snap a 1°), Vectopen solo tenía el primero.
		angle_delta = round(rad_to_deg(angle_delta)) * (PI / 180.0)

	live_rot_angle = angle_delta
	live_pivot = initial_macro_center

	for shape in selected_shapes:
		if not is_instance_valid(shape) or not transform_initial_states.has(shape):
			continue
		var snap: Dictionary = transform_initial_states[shape]

		var orig_gpos: Vector2 = snap["gpos"]
		var offset: Vector2 = orig_gpos - initial_macro_center
		shape.global_position = initial_macro_center + offset.rotated(angle_delta)
		_sync_doc_position_from_native(shape)
		if shape is VectorShape and snap.has("doc_rot"):
			# Precisión doble real: el ángulo nuevo se acumula sobre el valor
			# EXACTO capturado en _snapshot(), no sobre el float32 que dejó
			# guardado la rotación anterior — evita que el error se acumule
			# rotación tras rotación (solo válido si el padre no está rotado,
			# caso habitual en este proyecto; ver nota de alcance del plan).
			shape.set_doc_rotation(snap["doc_rot"] + angle_delta)
		else:
			shape.global_rotation = snap["grot"] + angle_delta

		if shape is Path2D:
			var renderer = shape.get_node_or_null("Render_Visual")
			if renderer is Line2D:
				renderer.points = shape.curve.get_baked_points()
		shape.queue_redraw()

# ── Imán inteligente ─────────────────────────────────────────────────────────

func _snap_manager() -> Node:
	var st := Engine.get_main_loop() as SceneTree
	return st.root.get_node_or_null("SnapManager") if st else null

func _viewport_zoom() -> float:
	if not is_instance_valid(canvas):
		return 1.0
	var vp := canvas.get_viewport()
	return vp.get_canvas_transform().get_scale().x if vp else 1.0

## Rect global de la selección en el instante en que empezó el arrastre
## (`transform_initial_states[s]["gpos"]` + tamaño actual). Sirve de base para
## calcular el ajuste del imán sin depender de las posiciones ya movidas.
func _macro_rect_inicial() -> Rect2:
	var r: Rect2 = Rect2()
	var got := false
	for s in selected_shapes:
		if is_instance_valid(s) and transform_initial_states.has(s):
			var rr := Rect2(transform_initial_states[s]["gpos"], _global_rect(s).size)
			r = rr if not got else r.merge(rr)
			got = true
	return r if got else Rect2()

## Rects (mundo) contra los que imanta la selección: los artboards que la
## contienen + sus capas de primer nivel (sin la propia selección ni sus
## ancestros/descendientes).
func _snap_candidates() -> Array:
	var out: Array = []
	var mgr := ArtboardManager.find(get_tree()) if is_inside_tree() else null
	if mgr == null:
		return out
	var vistos := {}
	for s in selected_shapes:
		if not is_instance_valid(s):
			continue
		var ab := mgr.owning_artboard(s)
		if ab == null or vistos.has(ab):
			continue
		vistos[ab] = true
		out.append(mgr.world_rect(ab))
		var dl: Node = ab.get_node_or_null("VectorDrawingLayer")
		var raiz: Node = dl if dl else ab
		for ch in raiz.get_children():
			if not (ch is Node2D):
				continue
			var nm := String(ch.name)
			if nm in ["Contorno_Stroke", "ArtboardTitle", "VectorDrawingLayer"]:
				continue
			if _es_seleccion_o_pariente(ch):
				continue
			var cr: Rect2 = _global_rect(ch)
			if cr.size != Vector2.ZERO:
				out.append(cr)
			if out.size() > 240:
				return out
	return out

func _es_seleccion_o_pariente(n: Node) -> bool:
	for s in selected_shapes:
		if not is_instance_valid(s):
			continue
		if s == n or _es_ancestro(n, s) or _es_ancestro(s, n):
			return true
	return false

func _is_image_only_selection() -> bool:
	if selected_shapes.is_empty():
		return false
	for s in selected_shapes:
		if not is_instance_valid(s) or not (s is Sprite2D):
			return false
	return true
