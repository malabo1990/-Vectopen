# =============================================================================
# VECTOPEN CORE — ADVANCED VECTOR BRUSH ENGINE
# =============================================================================
class_name BrushTool
extends ToolBase

var target_artboard: Node2D = null
var current_line: Line2D = null
# `is_drawing` ya lo declara ToolBase (Fase migración 2026-08-19) — no redeclarar.
var _point_count: int = 0

var raw_points: PackedVector2Array = PackedVector2Array()
var _committed_points: PackedVector2Array = PackedVector2Array()
var _settings = null
var _locked_preset := ""

# Renombradas desde STROKE_COLOR/STROKE_WIDTH: ToolBase ya declara esos nombres
# con otros valores (negro/1.0) — el pincel necesita los suyos propios.
const BRUSH_STROKE_COLOR := Color("#cc44ff")
const BRUSH_STROKE_WIDTH := 4.0
const CENTRIPETAL_ALPHA := 0.5
const _BRUSH_CURSOR := preload("res://assets/generated/brush_cursor.png")

func _refresh_settings() -> void:
	var pm := _find_performance_manager()
	var preset := "balanced"
	if pm and "quality_preset" in pm:
		preset = pm.quality_preset
	_settings = _make_settings(preset)

func _find_performance_manager() -> Node:
	var st := Engine.get_main_loop() as SceneTree
	if st:
		return st.root.get_node_or_null("PerformanceManager")
	return null

func _on_quality_changed(preset: String) -> void:
	if _locked_preset != "":
		return
	_settings = _make_settings(preset)
	if is_drawing and is_instance_valid(current_line):
		_finalizar_trazo_actual()

func set_brush_preset(preset: String) -> void:
	var s := _make_settings(preset)
	if s == _settings:
		return
	_locked_preset = preset
	_settings = s
	if is_drawing and is_instance_valid(current_line):
		_finalizar_trazo_actual()

func unlock_brush_preset() -> void:
	_locked_preset = ""
	_refresh_settings()

func get_brush_preset() -> String:
	if _locked_preset != "":
		return _locked_preset
	var pm := _find_performance_manager()
	if pm and "quality_preset" in pm:
		return pm.quality_preset
	return "balanced"

static func _make_settings(preset: String) -> Dictionary:
	var presets := {
		"potato": {"min_distance_threshold": 0.5, "rdp_epsilon": 0.5, "catmull_segments": 6, "catmull_live_segments": 3, "max_raw_points_per_stroke": 4000, "enable_bezier_fit_on_commit": false},
		"low": {"min_distance_threshold": 0.3, "rdp_epsilon": 0.4, "catmull_segments": 8, "catmull_live_segments": 4, "max_raw_points_per_stroke": 8000, "enable_bezier_fit_on_commit": false},
		"balanced": {"min_distance_threshold": 0.2, "rdp_epsilon": 0.35, "catmull_segments": 10, "catmull_live_segments": 4, "max_raw_points_per_stroke": 16000, "enable_bezier_fit_on_commit": false},
		"high": {"min_distance_threshold": 0.15, "rdp_epsilon": 0.25, "catmull_segments": 12, "catmull_live_segments": 5, "max_raw_points_per_stroke": 30000, "enable_bezier_fit_on_commit": true},
		"ultra": {"min_distance_threshold": 0.1, "rdp_epsilon": 0.2, "catmull_segments": 14, "catmull_live_segments": 5, "max_raw_points_per_stroke": 60000, "enable_bezier_fit_on_commit": true},
	}
	return presets.get(preset, presets["balanced"])

const BRUSH_CURSOR_HOTSPOT := Vector2(16, 16)

func activate() -> void:
	Input.set_custom_mouse_cursor(_BRUSH_CURSOR, Input.CURSOR_ARROW, BRUSH_CURSOR_HOTSPOT)
	is_drawing = false
	_refresh_settings()
	var pm := _find_performance_manager()
	if pm and not pm.quality_changed.is_connected(_on_quality_changed):
		pm.quality_changed.connect(_on_quality_changed)

func deactivate() -> void:
	Input.set_custom_mouse_cursor(null)
	_finalizar_trazo_actual()

func handle_input(event: InputEvent) -> bool:
	if not is_instance_valid(canvas):
		return false

	if event is InputEventMouseMotion and not is_drawing:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# El trazo va al artboard bajo el punto de inicio; si cae fuera de
			# todos, al activo.
			var start_gm: Vector2 = canvas.get_global_mouse_position()
			target_artboard = _artboard_for_point(start_gm)
			if not is_instance_valid(target_artboard) and canvas.artboards_container and canvas.artboards_container.get_child_count() > 0:
				target_artboard = canvas.artboards_container.get_child(0)

			if not is_instance_valid(target_artboard):
				return false

			var local_mouse := target_artboard.to_local(canvas.get_global_mouse_position())

			is_drawing = true
			_point_count = 0
			raw_points.clear()
			_committed_points.clear()
			raw_points.append(local_mouse)

			current_line = Line2D.new()
			current_line.width = BRUSH_STROKE_WIDTH
			current_line.default_color = BRUSH_STROKE_COLOR
			# antialiased=true en Line2D desactiva el batching y añade geometría
			# extra por segmento: con cientos de trazos hunde el pan. El MSAA 2D
			# del viewport suaviza el borde igual.
			current_line.antialiased = false
			current_line.joint_mode = Line2D.LINE_JOINT_ROUND
			current_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			current_line.end_cap_mode = Line2D.LINE_CAP_ROUND

			var drawing_layer = target_artboard.get_node_or_null("VectorDrawingLayer")
			if drawing_layer:
				drawing_layer.add_child(current_line)
			else:
				target_artboard.add_child(current_line)

			current_line.add_point(local_mouse)
			return true
		else:
			if is_drawing:
				_finalizar_trazo_actual()
				return true

	if event is InputEventMouseMotion and is_drawing:
		if is_instance_valid(current_line) and is_instance_valid(target_artboard):
			var target_local_pos := target_artboard.to_local(canvas.get_global_mouse_position())

			if raw_points.size() > 0 and target_local_pos.distance_to(raw_points[raw_points.size() - 1]) < _settings.min_distance_threshold:
				return true

			_on_new_raw_point(target_local_pos)
			return true

	return false

func _on_new_raw_point(local_mouse: Vector2) -> void:
	raw_points.append(local_mouse)
	_point_count += 1

	if _settings and raw_points.size() > _settings.max_raw_points_per_stroke:
		_finalizar_trazo_actual()
		return

	var n := raw_points.size()

	var i := n - 2
	var p0: Vector2
	var p1: Vector2
	var p2: Vector2
	var p3: Vector2

	if n == 3:
		p0 = raw_points[0]
		p1 = raw_points[0]
		p2 = raw_points[1]
		p3 = raw_points[2]
	elif n >= 4:
		p0 = raw_points[i - 2]
		p1 = raw_points[i - 1]
		p2 = raw_points[i]
		p3 = raw_points[i + 1]
	else:
		_update_live_preview()
		return

	var seg: PackedVector2Array = _catmull_segment(p0, p1, p2, p3, _settings.catmull_segments)
	for pt in seg:
		_committed_points.append(pt)

	_update_live_preview()

func _update_live_preview() -> void:
	if not is_instance_valid(current_line):
		return

	var n := raw_points.size()
	var preview: PackedVector2Array = _committed_points.duplicate()

	if n >= 2:
		var start: int = max(n - 4, 0)
		var tail_raw: PackedVector2Array = raw_points.slice(start, n)
		if tail_raw.size() >= 2:
			var tail_smooth: PackedVector2Array = _catmull_rom(tail_raw, _settings.catmull_live_segments)
			preview.append_array(tail_smooth)
		else:
			preview.append(raw_points[n - 1])

	current_line.points = preview

func _finalizar_trazo_actual() -> void:
	if not is_drawing:
		return

	is_drawing = false

	if is_instance_valid(current_line) and raw_points.size() >= 2:
		var final_points := _committed_points.duplicate()
		var n := raw_points.size()
		var tail_start: int = max(n - 4, 0)
		var tail_raw: PackedVector2Array = raw_points.slice(tail_start, n)
		if tail_raw.size() >= 2:
			final_points.append_array(_catmull_rom(tail_raw, _settings.catmull_live_segments))
		elif tail_raw.size() == 1:
			final_points.append(tail_raw[0])
		final_points = _thin_points(final_points, _settings.min_distance_threshold * 0.5)
		current_line.points = final_points

	current_line = null
	raw_points.clear()
	_committed_points.clear()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _thin_points(points: PackedVector2Array, min_spacing: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := PackedVector2Array()
	out.append(points[0])
	var last := points[0]
	for i in range(1, points.size() - 1):
		if points[i].distance_squared_to(last) >= min_spacing * min_spacing:
			out.append(points[i])
			last = points[i]
	out.append(points[points.size() - 1])
	return out

func _rdp_iterative(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	var n := points.size()
	if n < 3:
		return points

	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1

	var stack: Array[int] = [0, n - 1]

	while stack.size() >= 2:
		var end: int = stack.pop_back()
		var start: int = stack.pop_back()

		var dmax := 0.0
		var idx := -1

		for i in range(start + 1, end):
			var d := _dist_sq(points[i], points[start], points[end])
			if d > dmax:
				idx = i
				dmax = d

		if dmax > epsilon * epsilon:
			keep[idx] = 1
			stack.push_back(start)
			stack.push_back(idx)
			stack.push_back(idx)
			stack.push_back(end)

	var result := PackedVector2Array()
	for i in range(n):
		if keep[i]:
			result.append(points[i])
	return result

func _dist_sq(p: Vector2, a: Vector2, b: Vector2) -> float:
	if a.is_equal_approx(b):
		return p.distance_squared_to(a)
	var dx := b.x - a.x
	var dy := b.y - a.y
	var num: float = abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x)
	return num * num / (dx * dx + dy * dy)

func _catmull_rom(points: PackedVector2Array, segs: int) -> PackedVector2Array:
	var n := points.size()
	if n < 2:
		return points
	if n == 2:
		var r := PackedVector2Array()
		for i in range(segs + 1):
			r.append(points[0].lerp(points[1], float(i) / segs))
		return r

	var result := PackedVector2Array()
	var wi := 0
	result.resize((n - 1) * segs + 1)

	for i in range(1, n):
		var p0 := points[max(i - 2, 0)]
		var p1 := points[i - 1]
		var p2 := points[i]
		var p3 := points[min(i + 1, n - 1)]

		var seg_points: PackedVector2Array = _catmull_segment(p0, p1, p2, p3, segs)
		for j in range(segs):
			result[wi] = seg_points[j]
			wi += 1

	result[wi] = points[n - 1]
	return result

func _catmull_segment(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, segs: int) -> PackedVector2Array:
	var t0 := 0.0
	var t1 := t0 + pow(p0.distance_to(p1), CENTRIPETAL_ALPHA)
	var t2 := t1 + pow(p1.distance_to(p2), CENTRIPETAL_ALPHA)
	var t3 := t2 + pow(p2.distance_to(p3), CENTRIPETAL_ALPHA)

	if t1 == t0: t1 = t0 + 0.0001
	if t2 == t1: t2 = t1 + 0.0001
	if t3 == t2: t3 = t2 + 0.0001

	var out := PackedVector2Array()
	out.resize(segs)

	for j in range(segs):
		var t := t1 + (t2 - t1) * (float(j) / segs)

		var a1 := p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
		var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
		var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))

		var b1 := a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
		var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))

		out[j] = b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))

	return out
