# =============================================================================
# VECTOPEN — SHAPE BUILDER TOOL (SMART FUSION PRO)
# RUTA: res://script_gdscript/tools/ShapeBuilderTool.gd
# Herramienta constructiva profesional al estilo Figma, Affinity e Inkscape.
# Soporta:
#  - Fusión interactiva (Clic / Arrastre continuo atravesando regiones)
#  - Sustracción interactiva (Alt + Clic / Alt + Arrastre)
#  - Selección rápida por recuadro marquesina en el lienzo (arrastrar en vacío)
#  - Control/Shift para sumar figuras participantes
#  - Feedback visual táctil: rayado diagonal (hatching), trazo de arrastre, cursor dinámico (+/-)
# =============================================================================
class_name ShapeBuilderTool
extends ToolBase

const _GeomCore = preload("res://script_gdscript/shapes/VectorGeometryCore.gd")
const VectorPathScript = preload("res://script_gdscript/shapes/VectorPath.gd")

var participant_shapes: Array[CanvasItem] = []
var _atomic_regions: Array[Dictionary] = [] # { id, polygon, centroid, sources }
var _hovered_region_id: int = -1
var _selected_region_ids: Array[int] = []

var _is_mouse_down: bool = false
var _is_alt_pressed: bool = false
var _is_ctrl_pressed: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

## Trazo continuo del arrastre que cruza regiones
var _drag_trail: PackedVector2Array = []

## Marquesina de selección en lienzo
var _is_marquee: bool = false
var _marquee_start: Vector2 = Vector2.ZERO
var _marquee_current: Vector2 = Vector2.ZERO

func get_class_name() -> String:
	return "ShapeBuilderTool"

func activate() -> void:
	super.activate()
	_update_cursor()
	_gather_participant_shapes()
	_recalculate_regions()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func deactivate() -> void:
	super.deactivate()
	_atomic_regions.clear()
	_selected_region_ids.clear()
	_drag_trail.clear()
	_hovered_region_id = -1
	_is_mouse_down = false
	_is_marquee = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _update_cursor() -> void:
	if _is_alt_pressed:
		Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)

func _gather_participant_shapes() -> void:
	participant_shapes.clear()
	var sm = get_node_or_null("/root/SelectionManager")
	if is_instance_valid(sm) and sm.has_method("get_selected"):
		for s in sm.get_selected():
			if is_instance_valid(s) and (s is CanvasItem):
				participant_shapes.append(s)

	if participant_shapes.is_empty() and is_instance_valid(canvas) and "current_tool" in canvas and canvas.current_tool:
		var ct = canvas.current_tool
		if "selected_shapes" in ct and ct.selected_shapes is Array:
			for s in ct.selected_shapes:
				if is_instance_valid(s) and (s is CanvasItem):
					participant_shapes.append(s)

	# Si no hay selección previa, buscar figuras en el artboard activo
	if participant_shapes.size() < 2:
		_refresh_dependencies()
		if is_instance_valid(artboard):
			for child in artboard.get_children():
				if is_instance_valid(child) and (child is VectorShape or child is VectorPath):
					if not participant_shapes.has(child):
						participant_shapes.append(child)

func _recalculate_regions() -> void:
	_atomic_regions.clear()
	_selected_region_ids.clear()
	_hovered_region_id = -1

	if participant_shapes.size() < 2:
		return

	var input_polys: Array[PackedVector2Array] = []
	for shape in participant_shapes:
		if not is_instance_valid(shape):
			continue
		var geoms := _GeomCore.get_evaluated_geometry(shape)
		for g in geoms:
			var transformed := PackedVector2Array()
			for pt in g:
				transformed.append(shape.global_transform * pt)
			if transformed.size() >= 3:
				input_polys.append(transformed)

	_atomic_regions = _GeomCore.compute_atomic_regions(input_polys)

func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var old_alt := _is_alt_pressed
		_is_alt_pressed = event.alt_pressed
		_is_ctrl_pressed = event.ctrl_pressed
		if old_alt != _is_alt_pressed:
			_update_cursor()
			if is_instance_valid(canvas):
				canvas.queue_redraw()

		if event.pressed and event.keycode == KEY_ESCAPE:
			_cancel()
			return true
		if event.pressed and event.keycode == KEY_ENTER:
			if _is_alt_pressed:
				_commit_subtracted_regions()
			else:
				_commit_merged_shape()
			return true

	if event is InputEventMouseMotion:
		_is_alt_pressed = event.alt_pressed
		_is_ctrl_pressed = event.ctrl_pressed
		_update_cursor()

		var mouse_pos: Vector2 = canvas.get_global_mouse_position() if is_instance_valid(canvas) else event.position
		_last_mouse_pos = mouse_pos

		if _is_mouse_down:
			if _is_marquee:
				_marquee_current = mouse_pos
			else:
				_drag_trail.append(mouse_pos)
				_select_regions_intersecting_segment(_last_mouse_pos, mouse_pos)
		else:
			_update_hovered_region(mouse_pos)

		if is_instance_valid(canvas):
			canvas.queue_redraw()
		return true

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_is_alt_pressed = event.alt_pressed
		_is_ctrl_pressed = event.ctrl_pressed
		_update_cursor()

		var mouse_pos: Vector2 = canvas.get_global_mouse_position() if is_instance_valid(canvas) else event.position
		_last_mouse_pos = mouse_pos

		if event.pressed:
			_is_mouse_down = true
			_drag_trail.clear()
			_update_hovered_region(mouse_pos)

			if _hovered_region_id != -1:
				# Inicia arrastre a través de regiones
				_is_marquee = false
				_drag_trail.append(mouse_pos)
				_selected_region_ids = [_hovered_region_id]
			else:
				# Clic en vacío: inicia marquesina de selección en el lienzo
				_is_marquee = true
				_marquee_start = mouse_pos
				_marquee_current = mouse_pos
				_selected_region_ids.clear()

			if is_instance_valid(canvas):
				canvas.queue_redraw()
			return true
		else:
			# Soltar clic izquierdo
			_is_mouse_down = false
			if _is_marquee:
				_is_marquee = false
				_apply_marquee_selection()
			else:
				if not _selected_region_ids.is_empty():
					if _is_alt_pressed:
						_commit_subtracted_regions()
					else:
						_commit_merged_shape()
				_drag_trail.clear()
				_selected_region_ids.clear()

			if is_instance_valid(canvas):
				canvas.queue_redraw()
			return true

	return false

func _update_hovered_region(global_pos: Vector2) -> void:
	_hovered_region_id = -1
	for reg in _atomic_regions:
		var poly: PackedVector2Array = reg["polygon"]
		if Geometry2D.is_point_in_polygon(global_pos, poly):
			_hovered_region_id = int(reg["id"])
			break

func _select_regions_intersecting_segment(p1: Vector2, p2: Vector2) -> void:
	for reg in _atomic_regions:
		var reg_id: int = int(reg["id"])
		var poly: PackedVector2Array = reg["polygon"]
		if _check_segment_intersects_polygon(p1, p2, poly):
			if not _selected_region_ids.has(reg_id):
				_selected_region_ids.append(reg_id)

func _check_segment_intersects_polygon(p1: Vector2, p2: Vector2, poly: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(p2, poly) or Geometry2D.is_point_in_polygon(p1, poly):
		return true
	var n: int = poly.size()
	for i in range(n):
		var j := (i + 1) % n
		var inter = Geometry2D.segment_intersects_segment(p1, p2, poly[i], poly[j])
		if inter != null:
			return true
	return false

func _apply_marquee_selection() -> void:
	var rect := Rect2(_marquee_start, _marquee_current - _marquee_start).abs()
	if rect.size.x < 4.0 and rect.size.y < 4.0:
		return

	if is_inside_tree():
		_refresh_dependencies()
	var container: Node = artboard if is_instance_valid(artboard) else (canvas if is_instance_valid(canvas) else null)
	if not is_instance_valid(container) and not participant_shapes.is_empty():
		container = participant_shapes[0].get_parent()
	if not is_instance_valid(container):
		return

	for child in container.get_children():
		if is_instance_valid(child) and (child is CanvasItem):
			if child.has_method("get_evaluated_geometry") or child is VectorShape or child is VectorPath:
				var shape_geoms := _GeomCore.get_evaluated_geometry(child)
				var hit := false
				for g in shape_geoms:
					for pt in g:
						var gpt = child.global_transform * pt
						if rect.has_point(gpt):
							hit = true
							break
					if hit: break
				if hit:
					if _is_alt_pressed:
						participant_shapes.erase(child)
					elif not participant_shapes.has(child):
						participant_shapes.append(child)

	_recalculate_regions()

# ── RENDERIZADO VISUAL PROFESIONAL (FIGMA / AFFINITY STYLE) ──

func draw_preview(c: Node2D) -> void:
	if not is_instance_valid(c):
		return

	# 1. Dibujar regiones atómicas con resaltado y rayado táctil
	for reg in _atomic_regions:
		var poly: PackedVector2Array = reg["polygon"]
		var id: int = int(reg["id"])
		var is_sel: bool = _selected_region_ids.has(id)
		var is_hov: bool = (_hovered_region_id == id)

		if poly.size() < 3:
			continue

		var local_pts := PackedVector2Array()
		for p in poly:
			local_pts.append(c.to_local(p))

		if Geometry2D.triangulate_polygon(local_pts).is_empty():
			continue

		var fill_col: Color
		var border_col: Color
		var hatch_col: Color
		var draw_hatch := false

		if is_sel or is_hov:
			draw_hatch = true
			if _is_alt_pressed:
				# Modo Sustracción: Rojo carmesí traslúcido
				fill_col = Color(1.0, 0.20, 0.20, 0.38)
				border_col = Color(1.0, 0.15, 0.15, 0.95)
				hatch_col = Color(1.0, 0.35, 0.35, 0.65)
			else:
				# Modo Unión: Azul cian brillante traslúcido
				fill_col = Color(0.15, 0.65, 1.0, 0.40)
				border_col = Color(0.10, 0.75, 1.0, 0.95)
				hatch_col = Color(0.30, 0.85, 1.0, 0.70)
		else:
			fill_col = Color(0.2, 0.4, 0.8, 0.05)
			border_col = Color(0.3, 0.5, 0.8, 0.35)

		# Relleno del polígono
		c.draw_colored_polygon(local_pts, fill_col)

		# Patrón de rayado diagonal interior (Figma / Affinity hatching)
		if draw_hatch:
			_draw_polygon_hatching(c, poly, hatch_col)

		# Borde exterior de la región
		var ring := PackedVector2Array(local_pts)
		ring.append(local_pts[0])
		var stroke_w := 2.0 if (is_sel or is_hov) else 1.2
		c.draw_polyline(ring, border_col, stroke_w, false)

	# 2. Dibujar trazo continuo de arrastre entre regiones
	if _drag_trail.size() >= 2 and not _is_marquee:
		var trail_local := PackedVector2Array()
		for p in _drag_trail:
			trail_local.append(c.to_local(p))
		var trail_col := Color(1.0, 0.3, 0.3, 0.9) if _is_alt_pressed else Color(0.2, 0.8, 1.0, 0.9)
		c.draw_polyline(trail_local, trail_col, 3.0, false)

	# 3. Dibujar marquesina de selección en lienzo
	if _is_marquee:
		var m_p1: Vector2 = c.to_local(_marquee_start)
		var m_p2: Vector2 = c.to_local(_marquee_current)
		var m_r := Rect2(m_p1, m_p2 - m_p1).abs()
		c.draw_rect(m_r, Color(0.2, 0.6, 1.0, 0.15), true)
		c.draw_rect(m_r, Color(0.2, 0.6, 1.0, 0.85), false, 1.5)

	# 4. Indicador flotante (+ / -) junto al cursor
	if _is_mouse_down or _hovered_region_id != -1:
		_draw_mode_badge(c, c.to_local(_last_mouse_pos))

func _draw_polygon_hatching(c: Node2D, global_poly: PackedVector2Array, hatch_color: Color) -> void:
	var aabb := _calc_poly_aabb(global_poly)
	var step := 12.0
	var d := aabb.position.x - aabb.size.y
	var end_d := aabb.end.x + aabb.size.y

	while d < end_d:
		var p1 := Vector2(d, aabb.position.y)
		var p2 := Vector2(d + aabb.size.y, aabb.end.y)
		var clipped_lines = Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([p1, p2]), global_poly)
		for seg in clipped_lines:
			if seg.size() >= 2:
				c.draw_line(c.to_local(seg[0]), c.to_local(seg[1]), hatch_color, 1.2)
		d += step

func _draw_mode_badge(c: Node2D, local_pos: Vector2) -> void:
	var badge_pos := local_pos + Vector2(16, 16)
	var badge_col := Color(0.9, 0.2, 0.2, 0.9) if _is_alt_pressed else Color(0.1, 0.6, 1.0, 0.9)
	c.draw_circle(badge_pos, 7.0, badge_col)
	c.draw_circle(badge_pos, 7.0, Color.WHITE, false, 1.0)
	if _is_alt_pressed:
		# Signo '-'
		c.draw_line(badge_pos + Vector2(-3.5, 0), badge_pos + Vector2(3.5, 0), Color.WHITE, 1.8)
	else:
		# Signo '+'
		c.draw_line(badge_pos + Vector2(-3.5, 0), badge_pos + Vector2(3.5, 0), Color.WHITE, 1.8)
		c.draw_line(badge_pos + Vector2(0, -3.5), badge_pos + Vector2(0, 3.5), Color.WHITE, 1.8)

func _calc_poly_aabb(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var mn := poly[0]
	var mx := poly[0]
	for p in poly:
		mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
		mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
	return Rect2(mn, mx - mn)

# ── COMMITS: FUSIÓN (ADD) Y RECORTE (SUBTRACT) ──

func _resolve_target_parent() -> Node:
	if is_inside_tree():
		_refresh_dependencies()

	var mgr := _artboard_manager()

	# 1. Si las figuras participantes pertenecen a un artboard (o capa de artboard), usar ese contenedor
	for shape in participant_shapes:
		if is_instance_valid(shape):
			var p = shape.get_parent()
			if mgr:
				var owner_ab = mgr.owning_artboard(shape)
				if is_instance_valid(owner_ab):
					if is_instance_valid(p) and (p == owner_ab or owner_ab.is_ancestor_of(p)):
						return p
					return owner_ab
			elif is_instance_valid(p) and not (p is Viewport) and p.name != "ArtboardsContainer":
				return p

	# 2. Artboard activo de ArtboardManager
	if mgr:
		var act = mgr.get_active_artboard()
		if is_instance_valid(act):
			return act

	# 3. self.artboard
	if is_instance_valid(artboard):
		return artboard

	# 4. Primer Artboard real de ArtboardsContainer
	if is_instance_valid(canvas):
		var container = canvas.get_node_or_null("ArtboardsContainer")
		if container:
			for ch in container.get_children():
				if ch is ArtboardEditor or (ch is Node2D and "artboard_size" in ch):
					return ch

	# 5. Padre de la primera figura participante si es válido
	if not participant_shapes.is_empty() and is_instance_valid(participant_shapes[0]):
		return participant_shapes[0].get_parent()

	return canvas if is_instance_valid(canvas) else null

func _sync_layers_system() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if not tree:
		return
	var ls = tree.get_first_node_in_group("layers_system")
	if ls == null and tree.current_scene:
		ls = tree.current_scene.find_child("LayersSystem", true, false)
	if is_instance_valid(ls) and ls.has_method("sincronizar_arbol_completo"):
		ls.sincronizar_arbol_completo()

func _commit_merged_shape() -> void:
	if _selected_region_ids.is_empty():
		return

	var polys_to_merge: Array[PackedVector2Array] = []
	for reg in _atomic_regions:
		if _selected_region_ids.has(int(reg["id"])):
			polys_to_merge.append(reg["polygon"])

	if polys_to_merge.is_empty():
		return

	# Fusionar polígonos seleccionados con unión booleana completa
	var merged: Array[PackedVector2Array] = [polys_to_merge[0]]
	for i in range(1, polys_to_merge.size()):
		merged = _GeomCore.boolean_operation("union", merged, [polys_to_merge[i]])

	if merged.is_empty() or merged[0].size() < 3:
		return

	var target_parent: Node = _resolve_target_parent()
	if not is_instance_valid(target_parent):
		return

	# Asignar color azul distintivo como antes al añadir/crear regiones con Shape Builder
	var primary_shape: CanvasItem = participant_shapes[0] if not participant_shapes.is_empty() else null
	var new_path: VectorPath = VectorPathScript.new() as VectorPath
	new_path.name = "ShapeBuilder_Result"
	new_path.closed = true
	new_path.fill_color = Color(0.2, 0.55, 0.9, 1.0)

	if primary_shape and "stroke_color" in primary_shape:
		new_path.stroke_color = primary_shape.stroke_color
		new_path.stroke_width = primary_shape.stroke_width
	else:
		new_path.stroke_color = Color(0.1, 0.1, 0.1, 1.0)
		new_path.stroke_width = 2.0

	var target_xform_inv: Transform2D = (target_parent as CanvasItem).global_transform.affine_inverse() if (target_parent is CanvasItem) else Transform2D.IDENTITY
	var curve := Curve2D.new()
	var main_poly := merged[0]
	for p in main_poly:
		curve.add_point(target_xform_inv * p)
	new_path.curve = curve
	new_path.set_meta("evaluated_geometry", merged)

	target_parent.add_child(new_path)

	# Registrar en Undo/Redo
	var hm = get_node_or_null("/root/HistoryManager") if is_inside_tree() else null
	if is_instance_valid(hm) and hm.has_method("register_action"):
		hm.register_action("Shape Builder Crear Unión")
		hm.add_do(target_parent.add_child.bind(new_path))
		hm.add_undo(target_parent.remove_child.bind(new_path))
		hm.commit()

	# Sincronizar selección y refrescar regiones para poder seguir editando
	_select_shapes([new_path])
	participant_shapes.append(new_path)
	_sync_layers_system()
	_recalculate_regions()

func _commit_subtracted_regions() -> void:
	if _selected_region_ids.is_empty():
		return

	var sub_polys: Array[PackedVector2Array] = []
	for reg in _atomic_regions:
		if _selected_region_ids.has(int(reg["id"])):
			sub_polys.append(reg["polygon"])

	if sub_polys.is_empty():
		return

	# Unión de todas las regiones a restar
	var sub_union: Array[PackedVector2Array] = [sub_polys[0]]
	for i in range(1, sub_polys.size()):
		sub_union = _GeomCore.boolean_operation("union", sub_union, [sub_polys[i]])

	var target_parent: Node = _resolve_target_parent()
	if not is_instance_valid(target_parent):
		return

	var target_inv: Transform2D = (target_parent as CanvasItem).global_transform.affine_inverse() if (target_parent is CanvasItem) else Transform2D.IDENTITY
	var created_paths: Array[CanvasItem] = []
	var replaced_shapes: Array[CanvasItem] = []

	for shape in participant_shapes:
		if not is_instance_valid(shape):
			continue
		var s_polys := _GeomCore.transform_polygons(_GeomCore.get_evaluated_geometry(shape), shape.global_transform)
		var clipped := _GeomCore.boolean_operation("subtract", s_polys, sub_union)

		if clipped.is_empty():
			# La figura fue eliminada por completo
			shape.visible = false
			replaced_shapes.append(shape)
		elif clipped.size() != s_polys.size() or _polygons_differ(s_polys, clipped):
			# La figura fue recortada: crear el nuevo VectorPath recortado
			var np: VectorPath = VectorPathScript.new() as VectorPath
			np.name = shape.name + "_Trimmed"
			np.closed = true
			if "fill_color" in shape: np.fill_color = shape.fill_color
			if "stroke_color" in shape: np.stroke_color = shape.stroke_color
			if "stroke_width" in shape: np.stroke_width = shape.stroke_width

			var p_node := shape.get_parent() if is_instance_valid(shape.get_parent()) else target_parent
			var p_inv: Transform2D = (p_node as CanvasItem).global_transform.affine_inverse() if (p_node is CanvasItem) else target_inv
			var curve := Curve2D.new()
			for pt in clipped[0]:
				curve.add_point(p_inv * pt)
			np.curve = curve
			p_node.add_child(np)
			created_paths.append(np)
			shape.visible = false
			replaced_shapes.append(shape)

	# Actualizar lista de figuras participantes
	for r in replaced_shapes:
		participant_shapes.erase(r)
	for np in created_paths:
		participant_shapes.append(np)

	# Registrar en Undo/Redo
	var hm = get_node_or_null("/root/HistoryManager") if is_inside_tree() else null
	if is_instance_valid(hm) and hm.has_method("register_action"):
		hm.register_action("Shape Builder Sustracción")
		hm.add_do(Callable(self, "_do_apply_subtract").bind(created_paths, replaced_shapes, target_parent))
		hm.add_undo(Callable(self, "_undo_apply_subtract").bind(created_paths, replaced_shapes, target_parent))
		hm.commit()

	_recalculate_regions()
	_sync_layers_system()

func _do_apply_subtract(created: Array[CanvasItem], replaced: Array[CanvasItem], parent: Node) -> void:
	for r in replaced:
		if is_instance_valid(r): r.visible = false
	for c in created:
		if is_instance_valid(c) and c.get_parent() != parent:
			parent.add_child(c)
	_select_shapes(created)
	_sync_layers_system()

func _undo_apply_subtract(created: Array[CanvasItem], replaced: Array[CanvasItem], parent: Node) -> void:
	for c in created:
		if is_instance_valid(c) and c.get_parent() == parent:
			parent.remove_child(c)
	for r in replaced:
		if is_instance_valid(r): r.visible = true
	_select_shapes(replaced)
	_sync_layers_system()

func _polygons_differ(a: Array[PackedVector2Array], b: Array[PackedVector2Array]) -> bool:
	if a.size() != b.size():
		return true
	for i in range(a.size()):
		if a[i].size() != b[i].size():
			return true
	return false

func _select_shapes(shapes: Array) -> void:
	var sm = get_node_or_null("/root/SelectionManager") if is_inside_tree() else null
	if is_instance_valid(sm) and sm.has_method("set_selection"):
		sm.set_selection(shapes)
	var ge = get_node_or_null("/root/GlobalEvents") if is_inside_tree() else null
	if is_instance_valid(ge) and ge.has_signal("selection_changed"):
		ge.selection_changed.emit(shapes)

func _cancel() -> void:
	_atomic_regions.clear()
	_selected_region_ids.clear()
	_drag_trail.clear()
	_hovered_region_id = -1
	if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
		canvas.switch_tool("move")

