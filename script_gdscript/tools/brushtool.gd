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
var _settings = _make_settings("balanced")
var _locked_preset := ""

# Presión del lápiz por punto crudo (índice a índice con raw_points) y su
# longitud acumulada, para construir el width_curve del trazo — ver
# _build_width_curve(). InputEventMouseMotion.pressure NO existe en
# InputEventMouseButton (confirmado contra ClassDB), así que el primer punto
# del trazo (que llega por click, no por motion) no trae presión propia y
# reusa _last_pressure.
var raw_pressures: PackedFloat32Array = PackedFloat32Array()
var raw_cum: PackedFloat32Array = PackedFloat32Array()
var _last_pressure: float = 1.0

const StrokeProfile = preload("res://script_gdscript/shapes/stroke_profile.gd")
const CurveFit = preload("res://script_gdscript/shapes/curve_fit.gd")
const BrushStrokeRender = preload("res://script_gdscript/shapes/brush_stroke_render.gd")
const StrokeGeom = preload("res://script_gdscript/shapes/stroke_geom.gd")
const ObjectBrush = preload("res://script_gdscript/shapes/object_brush.gd")

# ── Presión del lápiz (estilo Krita, sensor "Tamaño ← Presión") ─────────────
## El grosor sigue la presión del lápiz.
var pressure_size_enabled := true
## Grosor con presión 0 (fracción del grosor del pincel).
var pressure_min := MIN_PRESSURE_WIDTH_SCALE
## Curva de respuesta: <1 suave (poca fuerza ya engorda), 1 lineal, >1 firme.
var pressure_gamma := 1.0
## Estabilizado de la presión (0 = crudo, 0.9 = muy suave): filtra el
## temblor del lápiz para que el grosor no "vibre".
var pressure_smoothing := 0.45
## Sin lápiz: la velocidad del ratón simula la presión (rápido = fino).
var speed_pressure := false

## Para el medidor del panel: presión cruda más reciente y si hay lápiz.
var live_pressure := 0.0
var pen_detected := false
var _smoothed_p := 1.0
var _first_pressure_pending := false
## Este trazo viene de un lápiz (alguna muestra con presión intermedia,
## inclinación o goma). Por TRAZO: un trazo con ratón tras usar el lápiz
## sigue con grosor completo.
var _stroke_is_pen := false
## 1 = muestra de despegue (presión 0 en un trazo de lápiz), por índice.
var _lift_flags := PackedByteArray()
var _prev_accumulated := true
const PRESSURE_CFG := "user://brush_pressure.cfg"

# Renombradas desde STROKE_COLOR/STROKE_WIDTH: ToolBase ya declara esos nombres
# con otros valores (negro/1.0) — el pincel necesita los suyos propios.
const BRUSH_STROKE_COLOR := Color("#cc44ff")
const BRUSH_STROKE_WIDTH := 4.0
const CENTRIPETAL_ALPHA := 0.5

var brush_opacity: float = 1.0
var brush_style: String = "pen"
## Dureza del lápiz (2H … 8B), como las minas de verdad.
## Pincel de OBJETO (VGSE fase 2): figuras que se estampan a lo largo del
## trazo (vacío = estrella de serie) y sus parámetros (object_brush.gd).
var object_source: Array = []
var object_params: Dictionary = ObjectBrush.DEFAULTS.duplicate()

var pencil_grade: String = "HB":
	set(v):
		if v != pencil_grade:
			_settings_dirty = true
		pencil_grade = v
var _last_stroke_end_pos: Vector2 = Vector2.INF
var _last_stroke_artboard: Node2D = null

const _ColorCoreScript = preload("res://autoloads/ColorCore.gd")

func _get_brush_color() -> Color:
	var col := BRUSH_STROKE_COLOR
	var cc := get_node_or_null("/root/ColorCore")
	if is_instance_valid(cc):
		if cc.active_target == "stroke":
			col = cc.stroke_color
		else:
			col = cc.fill_color
	# UX-11: nunca un trazo invisible sobre la página (p. ej. blanco heredado
	# de una figura con relleno blanco).
	if is_instance_valid(target_artboard) and "fill_color" in target_artboard:
		col = _ColorCoreScript.visible_on(col, target_artboard.fill_color)
	# La opacidad del trazo es SOLO la del pincel (campo Opacidad del panel).
	# Antes se multiplicaba por el alfa del selector de color, que al
	# seleccionar el trazo recién dibujado tomaba su alfa: cada trazo nuevo
	# salía más transparente que el anterior (0,8 → 0,64 → 0,51…).
	col.a = clampf(brush_opacity, 0.05, 1.0)
	return col

## Cambia el ESTILO (opacidad, suavizado, goma…) sin tocar el GROSOR: el
## grosor lo elige el usuario y se mantiene al cambiar de estilo (antes cada
## estilo ponía el suyo: de 1 px al lápiz y luego a la pluma saltaba a 3,5).
func apply_brush_style(style_id: String) -> void:
	_settings_dirty = true
	brush_style = style_id
	match style_id:
		"pencil":
			set_eraser_mode(false)
			brush_opacity = 1.0   # la transparencia la da la presión
			set_brush_preset("low")
		"pen":
			set_eraser_mode(false)
			brush_opacity = 1.0
			set_brush_preset("balanced")
		"marker":
			set_eraser_mode(false)
			brush_opacity = 0.65
			set_brush_preset("balanced")
		"calligraphy":
			set_eraser_mode(false)
			brush_opacity = 1.0
			set_brush_preset("high")
		"airbrush":
			set_eraser_mode(false)
			brush_opacity = 0.35
			set_brush_preset("ultra")
		"object":
			set_eraser_mode(false)
			brush_opacity = 1.0
			set_brush_preset("balanced")
		"eraser":
			set_eraser_mode(true)
			brush_opacity = 1.0
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _apply_line_style(line: Line2D) -> void:
	# Remates y uniones redondas con más segmentos (8 por defecto: en trazos
	# gruesos se veían poligonales).
	line.round_precision = 32
	if not is_instance_valid(line):
		return
	line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	line.set_meta("brush_style", brush_style)
	if brush_style == "pencil":
		line.set_meta("pencil_grade", pencil_grade)
	if brush_style == "object":
		var prm := object_params.duplicate()
		prm["seed"] = randi() % 1000000
		var src := object_source if not object_source.is_empty() else ObjectBrush.preset("star")
		line.set_meta("brush_obj", {"src": ObjectBrush.to_data(src), "params": prm})
	match brush_style:
		"pencil":
			line.texture = null   # lo pinta el sombreador (brush_stroke.gdshader)
			line.texture_mode = Line2D.LINE_TEXTURE_TILE
			line.joint_mode = Line2D.LINE_JOINT_ROUND
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
		"marker":
			line.texture = null   # lo pinta el sombreador (brush_stroke.gdshader)
			line.texture_mode = Line2D.LINE_TEXTURE_TILE
			line.joint_mode = Line2D.LINE_JOINT_SHARP
			line.begin_cap_mode = Line2D.LINE_CAP_BOX
			line.end_cap_mode = Line2D.LINE_CAP_BOX
		"airbrush":
			line.texture = null   # lo pinta el sombreador (brush_stroke.gdshader)
			line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
			line.joint_mode = Line2D.LINE_JOINT_ROUND
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
		"calligraphy":
			line.texture = null   # plumilla plana: geometría (brush_stroke_render.centerline)
			line.texture_mode = Line2D.LINE_TEXTURE_NONE
			line.joint_mode = Line2D.LINE_JOINT_ROUND
			line.begin_cap_mode = Line2D.LINE_CAP_NONE
			line.end_cap_mode = Line2D.LINE_CAP_NONE
		_:
			line.texture = null
			line.texture_mode = Line2D.LINE_TEXTURE_NONE
			line.joint_mode = Line2D.LINE_JOINT_ROUND
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND

# Ancho mínimo (como fracción de BRUSH_STROKE_WIDTH) en el punto de menor
# presión del trazo; con ratón sin tableta la presión siempre cae a 1.0
# (ver _last_pressure) así que el trazo sale con ancho constante como antes.
const MIN_PRESSURE_WIDTH_SCALE := 0.15
const _BRUSH_CURSOR := preload("res://assets/generated/brush_cursor.png")

# ── Ajuste de tamaño estilo Krita: Shift + clic-y-arrastre horizontal ───────
# Reemplaza al const BRUSH_STROKE_WIDTH como ancho "activo" del pincel —
# BRUSH_STROKE_WIDTH sigue siendo el valor inicial por defecto.
var brush_width: float = BRUSH_STROKE_WIDTH:
	set(v):
		if not is_equal_approx(v, brush_width):
			_settings_dirty = true
		brush_width = v
## Grosor, estilo o dureza cambiados y aún sin guardar (ver save_pressure_settings).
var _settings_dirty := false
var _is_resizing: bool = false
var _resize_start_x: float = 0.0
var _resize_start_width: float = 0.0
# px de viewport arrastrados horizontalmente por unidad de ancho — en espacio
# de pantalla, no del artboard, para que el gesto se sienta igual sin importar
# el zoom del canvas (igual que en Krita/Photoshop/Clip Studio).
const RESIZE_SENSITIVITY := 0.2
const MIN_BRUSH_WIDTH := 0.005   # antes 0,5: con mucho zoom no se podía pintar más fino
const MAX_BRUSH_WIDTH := 100.0

var _cursor_world: Vector2 = Vector2.INF
var _eraser_mode: bool = false

func set_eraser_mode(enabled: bool) -> void:
	_eraser_mode = enabled

func _is_eraser_active(event: InputEvent = null) -> bool:
	if _eraser_mode:
		return true
	if event is InputEventMouseMotion and event.pen_inverted:
		return true
	return false

func _erase_at_position(local_pos: Vector2) -> void:
	if not is_instance_valid(target_artboard):
		var start_gm: Vector2 = canvas.get_global_mouse_position() if is_instance_valid(canvas) else Vector2.ZERO
		target_artboard = _artboard_for_point(start_gm)
		if not is_instance_valid(target_artboard) and canvas and canvas.artboards_container and canvas.artboards_container.get_child_count() > 0:
			target_artboard = canvas.artboards_container.get_child(0)
	if not is_instance_valid(target_artboard):
		return

	var container: Node = target_artboard.get_node_or_null("VectorDrawingLayer")
	if not container:
		container = target_artboard

	var erase_radius: float = maxf(brush_width * 1.5, 12.0)
	for child in container.get_children():
		if child is Line2D:
			for pt in child.points:
				if pt.distance_to(local_pos) <= erase_radius:
					child.queue_free()
					break

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
		"potato": {"min_distance_threshold": 0.5, "rdp_epsilon": 0.5, "catmull_segments": 6, "catmull_live_segments": 3, "max_raw_points_per_stroke": 4000, "enable_bezier_fit_on_commit": true, "fit_factor": 1.3},
		"low": {"min_distance_threshold": 0.3, "rdp_epsilon": 0.4, "catmull_segments": 8, "catmull_live_segments": 4, "max_raw_points_per_stroke": 8000, "enable_bezier_fit_on_commit": true, "fit_factor": 1.15},
		"balanced": {"min_distance_threshold": 0.2, "rdp_epsilon": 0.35, "catmull_segments": 10, "catmull_live_segments": 4, "max_raw_points_per_stroke": 16000, "enable_bezier_fit_on_commit": true, "fit_factor": 1.0},
		"high": {"min_distance_threshold": 0.15, "rdp_epsilon": 0.25, "catmull_segments": 12, "catmull_live_segments": 5, "max_raw_points_per_stroke": 30000, "enable_bezier_fit_on_commit": true, "fit_factor": 0.8},
		"ultra": {"min_distance_threshold": 0.1, "rdp_epsilon": 0.2, "catmull_segments": 14, "catmull_live_segments": 5, "max_raw_points_per_stroke": 60000, "enable_bezier_fit_on_commit": true, "fit_factor": 1.6},
	}
	return presets.get(preset, presets["balanced"])

const BRUSH_CURSOR_HOTSPOT := Vector2(16, 16)

func activate() -> void:
	_load_pressure_settings()
	# El panel puede haberse mostrado ANTES de que esta herramienta cargara
	# los ajustes (estilo, grosor…): que vuelva a leerlos.
	_sync_panels.call_deferred()
	# Cada muestra del lápiz cuenta (Godot juntaba todos los movimientos de un
	# frame en uno y se perdían posiciones y presiones).
	_prev_accumulated = Input.use_accumulated_input
	Input.use_accumulated_input = false
	Input.set_custom_mouse_cursor(_BRUSH_CURSOR, Input.CURSOR_ARROW, BRUSH_CURSOR_HOTSPOT)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	is_drawing = false
	_refresh_settings()
	var pm := _find_performance_manager()
	if pm and not pm.quality_changed.is_connected(_on_quality_changed):
		pm.quality_changed.connect(_on_quality_changed)

func _sync_panels() -> void:
	if is_inside_tree():
		get_tree().call_group("brush_panel", "_sync_from_tool")

func deactivate() -> void:
	if _settings_dirty:
		save_pressure_settings()
	Input.use_accumulated_input = _prev_accumulated
	Input.set_custom_mouse_cursor(null)
	_cursor_world = Vector2.INF
	_last_stroke_end_pos = Vector2.INF
	_last_stroke_artboard = null
	if is_instance_valid(canvas):
		canvas.queue_redraw()
	_finalizar_trazo_actual()

func _get_event_gm(event: InputEvent) -> Vector2:
	if is_instance_valid(canvas) and ("position" in event):
		return canvas.get_canvas_transform().affine_inverse() * event.position
	elif is_instance_valid(canvas):
		return canvas.get_global_mouse_position()
	return Vector2.ZERO

func handle_input(event: InputEvent) -> bool:
	if not is_instance_valid(canvas):
		return false

	if event is InputEventKey:
		if event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			canvas.queue_redraw()

	if event is InputEventMouseMotion and _is_resizing:
		var delta_x: float = event.position.x - _resize_start_x
		brush_width = clampf(_resize_start_width + delta_x * RESIZE_SENSITIVITY, MIN_BRUSH_WIDTH, MAX_BRUSH_WIDTH)
		canvas.queue_redraw()
		return true

	if event is InputEventMouseMotion:
		var motion_gm := _get_event_gm(event)
		_cursor_world = motion_gm
		_track_pen(event)
		if event.pressure > 0.0:
			_last_pressure = event.pressure
		if _is_eraser_active(event):
			Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				if not is_instance_valid(target_artboard):
					target_artboard = _artboard_for_point(motion_gm)
				if is_instance_valid(target_artboard):
					_erase_at_position(target_artboard.to_local(motion_gm))
			canvas.queue_redraw()
			return true
		elif not is_drawing and not _is_resizing:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		canvas.queue_redraw()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var press_gm := _get_event_gm(event)
			if _is_eraser_active(event):
				target_artboard = _artboard_for_point(press_gm)
				if not is_instance_valid(target_artboard) and canvas.artboards_container and canvas.artboards_container.get_child_count() > 0:
					target_artboard = canvas.artboards_container.get_child(0)
				if is_instance_valid(target_artboard):
					_erase_at_position(target_artboard.to_local(press_gm))
				return true

			# Capturar la presión más reciente registrada de la tableta (Wacom / Huion / XP-Pen)
			if has_meta("pen_pressure"):
				var p = get_meta("pen_pressure")
				if p is float and p > 0.0:
					_last_pressure = p

			if event.shift_pressed and not is_drawing:
				# Ajuste de tamaño estilo Krita: Shift+clic no dibuja, arma el
				# gesto de arrastre horizontal que cambia brush_width.
				_is_resizing = true
				_resize_start_x = event.position.x
				_resize_start_width = brush_width
				Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
				canvas.queue_redraw()
				return true

			# El trazo va al artboard bajo el punto de inicio; si cae fuera de
			# todos, al activo.
			var found_ab: Node2D = _artboard_for_point(press_gm)
			if is_instance_valid(found_ab):
				target_artboard = found_ab
			elif not is_instance_valid(target_artboard):
				if "artboards_container" in canvas and canvas.artboards_container and canvas.artboards_container.get_child_count() > 0:
					target_artboard = canvas.artboards_container.get_child(0)

			if not is_instance_valid(target_artboard):
				return false

			var local_mouse := target_artboard.to_local(press_gm)
			var drawing_layer = target_artboard.get_node_or_null("VectorDrawingLayer")
			var container_parent: Node = drawing_layer if drawing_layer else target_artboard

			# Gesto Alt + Click: trazar línea recta continua desde el punto anterior
			if event.alt_pressed and _last_stroke_end_pos != Vector2.INF and is_instance_valid(_last_stroke_artboard) and _last_stroke_artboard == target_artboard:
				var local_start := _last_stroke_end_pos
				var local_end := local_mouse
				is_drawing = true
				_point_count = 0
				raw_points.clear()
				raw_pressures.clear()
				raw_cum.clear()
				_committed_points.clear()
				raw_points.append(local_start)
				raw_pressures.append(1.0)
				raw_cum.append(0.0)
				raw_points.append(local_end)
				raw_pressures.append(1.0)
				raw_cum.append(local_start.distance_to(local_end))

				current_line = Line2D.new()
				current_line.name = NameUtils.unique_child_name(container_parent, "Dibujo")
				current_line.width = brush_width
				current_line.default_color = _get_brush_color()
				current_line.antialiased = false
				_apply_line_style(current_line)
				if drawing_layer:
					drawing_layer.add_child(current_line)
				else:
					target_artboard.add_child(current_line)
				current_line.points = PackedVector2Array([local_start, local_end])
				_finalizar_trazo_actual()
				_last_stroke_end_pos = local_end
				_last_stroke_artboard = target_artboard
				if is_instance_valid(canvas):
					canvas.queue_redraw()
				return true

			is_drawing = true
			_point_count = 0
			raw_points.clear()
			raw_pressures.clear()
			raw_cum.clear()
			_committed_points.clear()
			raw_points.append(local_mouse)
			# La presión del primer punto la trae el PRIMER movimiento del lápiz
			# (el clic no tiene presión; antes se usaba la del final del trazo
			# anterior, casi 0 → arranques raros).
			_first_pressure_pending = true
			_stroke_is_pen = false
			_lift_flags = PackedByteArray([0])
			_smoothed_p = 1.0
			raw_pressures.append(1.0)
			raw_cum.append(0.0)

			current_line = Line2D.new()
			current_line.name = NameUtils.unique_child_name(container_parent, "Dibujo")
			current_line.width = brush_width
			current_line.default_color = _get_brush_color()
			# antialiased=true en Line2D desactiva el batching y añade geometría
			# extra por segmento: con cientos de trazos hunde el pan. El MSAA 2D
			# del viewport suaviza el borde igual.
			current_line.antialiased = false
			_apply_line_style(current_line)
			# Vista previa con el MISMO render que el trazo final (borde liso
			# con antialias): antes se veía el Line2D festoneado y el trazo
			# «cambiaba» al soltar el lápiz.
			BrushStrokeRender.attach(current_line)

			if drawing_layer:
				drawing_layer.add_child(current_line)
			else:
				target_artboard.add_child(current_line)

			current_line.add_point(local_mouse)
			return true
		else:
			if _is_resizing:
				_is_resizing = false
				if _settings_dirty:
					save_pressure_settings()
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				canvas.queue_redraw()
				return true
			if is_drawing:
				_finalizar_trazo_actual()
				return true

	if event is InputEventMouseMotion and is_drawing:
		if is_instance_valid(current_line) and is_instance_valid(target_artboard):
			var motion_gm := _get_event_gm(event)
			var target_local_pos := target_artboard.to_local(motion_gm)

			# Bloqueo de ejes horizontal / vertical con Ctrl
			# Modificadores DEL EVENTO (los manda el SO con cada movimiento), no
			# Input.is_key_pressed(): si la ventana pierde el foco con Ctrl o
			# Super pulsado, Godot no recibe el "soltar", el estado global se
			# queda pegado y el pincel solo dibujaba en horizontal / vertical.
			if event.is_command_or_control_pressed() and raw_points.size() > 0:
				var origin := raw_points[0]
				var delta := target_local_pos - origin
				if absf(delta.x) >= absf(delta.y):
					target_local_pos.y = origin.y
				else:
					target_local_pos.x = origin.x

			# Umbral en px de PANTALLA: en unidades del lienzo, con mucho zoom
			# se descartaban muestras a 10+ px y el trazo salía poligonal.
			if raw_points.size() > 0 and target_local_pos.distance_to(raw_points[raw_points.size() - 1]) < _settings.min_distance_threshold * _px_world():
				return true

			var p := _sample_pressure(event, target_local_pos)
			if _first_pressure_pending:
				_first_pressure_pending = false
				_smoothed_p = p
				raw_pressures[0] = p
			else:
				# Estabilizado exponencial: filtra el temblor sin retrasar mucho.
				_smoothed_p = lerpf(p, _smoothed_p, clampf(pressure_smoothing, 0.0, 0.95))
			_on_new_raw_point(target_local_pos, _smoothed_p)
			while _lift_flags.size() < raw_points.size() - 1:
				_lift_flags.append(0)
			if _lift_flags.size() < raw_points.size():
				_lift_flags.append(1 if (_stroke_is_pen and event.pressure <= 0.0) else 0)
			return true

	return false

## Brush outline that follows the pointer at the real stroke diameter, at any
## zoom. Two-tone ring (dark + light) so it reads on any artwork; while the
## Shift+drag resize gesture is active it uses the brush color.
func draw_preview(c: Node2D) -> void:
	if not is_instance_valid(c) or _cursor_world == Vector2.INF:
		return
	var vp := c.get_viewport()
	var zoom: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	var px: float = 1.0 / maxf(zoom, 0.0001)
	var pos: Vector2 = c.to_local(_cursor_world)
	# Never smaller than 3 screen px so thin brushes still show a ring
	var radius: float = maxf(brush_width * 0.5, 3.0 * px)
	var brush_col := _get_brush_color()
	if _is_resizing:
		c.draw_arc(pos, radius, 0.0, TAU, 48, brush_col, 1.5 * px, true)
	else:
		c.draw_arc(pos, radius + 0.5 * px, 0.0, TAU, 48, Color(0, 0, 0, 0.55), 1.5 * px, true)
		c.draw_arc(pos, radius - 0.5 * px, 0.0, TAU, 48, Color(1, 1, 1, 0.9), 1.0 * px, true)
	c.draw_circle(pos, 1.2 * px, brush_col)
	# Mientras se dibuja: disco del grosor REAL según la presión actual
	# (el anillo es el grosor máximo, como en Krita).
	if is_drawing and pressure_size_enabled and (pen_detected or speed_pressure):
		var r_now: float = maxf(brush_width * 0.5 * _pressure_to_scale(_smoothed_p), 1.0 * px)
		c.draw_circle(pos, r_now, Color(brush_col, 0.35))

	# HUD de grosor numérico al pulsar Shift o al redimensionar
	if Input.is_key_pressed(KEY_SHIFT) or _is_resizing:
		var txt := "%d px" % int(round(brush_width))
		var font: Font = ThemeDB.fallback_font
		var f_size: int = int(clampf(12.0 * px, 10.0, 24.0))
		var str_sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size)
		var badge_origin := pos + Vector2(radius + 8.0 * px, -radius * 0.4)
		var pad := 4.0 * px
		var rect := Rect2(badge_origin.x - pad, badge_origin.y - str_sz.y - pad * 0.3, str_sz.x + pad * 2.0, str_sz.y + pad * 1.5)
		c.draw_rect(rect, Color(0.1, 0.1, 0.14, 0.9), true)
		c.draw_rect(rect, Color(1.0, 1.0, 1.0, 0.25), false, px)
		c.draw_string(font, badge_origin, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size, Color.WHITE)

func _on_new_raw_point(local_mouse: Vector2, pressure: float) -> void:
	var prev := raw_points[raw_points.size() - 1]
	raw_points.append(local_mouse)
	raw_pressures.append(pressure)
	raw_cum.append(raw_cum[raw_cum.size() - 1] + prev.distance_to(local_mouse))
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
	if preview.size() >= 2:
		current_line.width_curve = _build_width_curve_smooth() if is_wysiwyg_style() else _build_width_curve()

## Lápiz, aerógrafo, rotulador y caligráfico: lo que se ve al dibujar es lo
## que queda al soltar (como un lápiz de verdad). Antes, al soltar, el trazo
## se reajustaba con Bézier, se filtraba otra vez la presión y se recortaba
## la punta: cambiaban la forma, el grano y la transparencia.
func is_wysiwyg_style() -> bool:
	return brush_style in ["pencil", "airbrush", "marker", "calligraphy", "object"]

## Usa las figuras seleccionadas como pincel de objeto. `combine`: todas
## juntas como una sola estampa; si no, cada figura por separado
## (multiobjeto: se alternan o se eligen al azar). false si no hay nada.
func use_selection_as_object(combine: bool = true) -> bool:
	var sm = get_node_or_null("/root/SelectionManager") if is_inside_tree() else null
	if sm == null:
		return false
	# Primero lo que estaba seleccionado al ELEGIR el pincel (seleccionar con
	# Mover → botón del pincel → «Selección»); al entrar en el pincel la
	# selección puede cambiar (p. ej. vuelve el último trazo dibujado).
	var sel: Array = []
	if is_instance_valid(canvas) and "selection_before_tool_change" in canvas:
		sel = canvas.selection_before_tool_change.filter(func(n) -> bool: return is_instance_valid(n) and n.is_inside_tree())
	if sel.is_empty():
		sel = sm.get_selected()
	var src: Array = ObjectBrush.from_shapes(sel, combine)
	if src.is_empty():
		return false
	object_source = src
	_settings_dirty = true
	return true

func set_object_preset(name: String) -> void:
	object_source = ObjectBrush.preset(name)
	_settings_dirty = true

func set_object_param(key: String, value) -> void:
	object_params[key] = value
	_settings_dirty = true

func _finalizar_trazo_actual() -> void:
	if not is_drawing:
		return

	is_drawing = false

	if is_instance_valid(current_line) and raw_points.size() >= 1:
		var final_points := _committed_points.duplicate()
		var n := raw_points.size()
		if n >= 2:
			var tail_start: int = max(n - 4, 0)
			var tail_raw: PackedVector2Array = raw_points.slice(tail_start, n)
			if tail_raw.size() >= 2:
				final_points.append_array(_catmull_rom(tail_raw, _settings.catmull_live_segments))
			elif tail_raw.size() == 1:
				final_points.append(tail_raw[0])
			if is_wysiwyg_style():
				# Mismos puntos y misma presión que la vista previa.
				current_line.width_curve = _build_width_curve_smooth()
			else:
				_trim_lift_off()
			if is_wysiwyg_style():
				pass
			elif bool(_settings.get("enable_bezier_fit_on_commit", false)):
				# Calidad Illustrator: cúbicas ajustadas a las muestras REALES del
				# lápiz (se quita el temblor de la mano) y troceadas por ángulo.
				var fitted_pts := _fit_smooth_points(raw_points)
				if fitted_pts.size() >= 2:
					final_points = fitted_pts
				current_line.width_curve = _build_width_curve_smooth(final_points)
			else:
				final_points = _thin_points(final_points, _settings.min_distance_threshold * 0.5 * _px_world())
				final_points = _rdp_iterative(final_points, _settings.rdp_epsilon * _px_world())
				current_line.width_curve = _build_width_curve()
			_store_pressure_profile(current_line)
		# Trazo sin textura (pluma…): render de calidad (borde liso con la
		# presión y degradado 2D con la G). Los de textura siguen con Line2D.
		# Todos los estilos con el render de calidad (los de textura salían
		# con el Line2D festoneado y los puntos crudos).
		BrushStrokeRender.attach(current_line)
		current_line.points = final_points

		# Registrar en HistoryManager para soporte de Ctrl+Z
		var line_node := current_line
		var parent_node := current_line.get_parent()
		var hm = get_node_or_null("/root/HistoryManager") if is_inside_tree() else null
		if is_instance_valid(hm) and hm.has_method("register_action") and is_instance_valid(parent_node):
			hm.register_action("Dibujar Trazo")
			hm.add_do(func(): if is_instance_valid(parent_node) and is_instance_valid(line_node) and line_node.get_parent() == null: parent_node.add_child(line_node))
			hm.add_undo(func(): if is_instance_valid(parent_node) and is_instance_valid(line_node) and line_node.get_parent() == parent_node: parent_node.remove_child(line_node))
			hm.commit()

		var sm = get_node_or_null("/root/SelectionManager")
		if is_instance_valid(sm) and sm.has_method("set_selection"):
			sm.set_selection([current_line])

	if _settings_dirty:
		save_pressure_settings()
	if raw_points.size() > 0:
		_last_stroke_end_pos = raw_points[raw_points.size() - 1]
		_last_stroke_artboard = target_artboard

	current_line = null
	raw_points.clear()
	raw_pressures.clear()
	raw_cum.clear()
	_committed_points.clear()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

## Quita las muestras de DESPEGUE del final (presión 0 en un trazo de lápiz),
## dejando solo la primera: al levantar el lápiz rápido la punta sigue
## moviéndose y dibujaba un gancho que acababa en mancha.
func _trim_lift_off() -> void:
	var n := raw_points.size()
	if n < 3 or _lift_flags.size() < n:
		return
	var last_keep := n - 1
	while last_keep > 1 and _lift_flags[last_keep] == 1 and _lift_flags[last_keep - 1] == 1:
		last_keep -= 1
	if last_keep == n - 1:
		return
	raw_points.resize(last_keep + 1)
	raw_pressures.resize(last_keep + 1)
	raw_cum.resize(last_keep + 1)
	_lift_flags.resize(last_keep + 1)

## Px de pantalla → unidades del lienzo (el mismo pulso da el mismo trazo a
## cualquier zoom).
func _px_world() -> float:
	var zoom := 1.0
	if is_instance_valid(canvas) and canvas.get_viewport():
		zoom = maxf(canvas.get_viewport().get_canvas_transform().get_scale().x, 0.0001)
	return 1.0 / zoom

## Compatibilidad: tolerancia base en unidades del lienzo.
func _fit_error_world() -> float:
	return float(_settings.get("fit_factor", 1.0)) * _px_world()

## Muestras del lápiz → Bézier cúbicas (Schneider) → puntos densos por ángulo.
func _fit_smooth_points(samples: PackedVector2Array) -> PackedVector2Array:
	if samples.size() < 3:
		return samples
	var fitted: Curve2D = adaptive_fit(samples, _px_world(), float(_settings.get("fit_factor", 1.0)))
	if fitted.point_count < 2:
		return samples
	var pts := StrokeGeom.curve_points(fitted)
	return pts if pts.size() >= 2 else samples

## Ajuste ADAPTATIVO (medido con una forma conocida + temblor: ver
## BrushTool_test): se estima el temblor de ESTE trazo (residuo frente a un
## suavizado ligero) y con él la tolerancia y el estabilizador:
##   sin temblor → tolerancia 1 px, sigma 2.5 px: fiel a lo dibujado (antes
##   un valor fijo alto se desviaba ~5 px de la forma, redondeando detalles);
##   mucho temblor → algo más de suavizado para que no ondule.
## `px` = unidades del lienzo por px de pantalla; `factor` = preset del panel.
static func adaptive_fit(samples: PackedVector2Array, px: float, factor: float = 1.0) -> Curve2D:
	var light := _gauss_smooth_positions(samples, 2.5 * px)
	var acc := 0.0
	for i in samples.size():
		acc += samples[i].distance_squared_to(light[i])
	var rms_px := sqrt(acc / maxf(1.0, float(samples.size()))) / px
	var err_px := (1.0 + 0.3 * rms_px) * factor
	var sigma_px := err_px * (2.5 + 0.8 * rms_px)
	var smoothed := _gauss_smooth_positions(samples, sigma_px * px)
	return CurveFit.fit(smoothed, err_px * px)

static func _gauss_smooth_positions(p: PackedVector2Array, sigma: float) -> PackedVector2Array:
	var n := p.size()
	if n < 3 or sigma <= 0.0:
		return p
	var cum := PackedFloat32Array()
	cum.resize(n)
	for i in range(1, n):
		cum[i] = cum[i - 1] + p[i].distance_to(p[i - 1])
	var out := PackedVector2Array()
	out.resize(n)
	var reach := sigma * 2.5
	for i in n:
		# la ventana se estrecha junto a los extremos para no acortarlos
		var r := minf(reach, minf(cum[i], cum[n - 1] - cum[i]))
		if r <= 0.0001:
			out[i] = p[i]
			continue
		var s2 := maxf((r / 2.5) * (r / 2.5), 0.0001)
		var acc := Vector2.ZERO
		var wsum := 0.0
		var j := i
		while j >= 0 and cum[i] - cum[j] <= r:
			var w := exp(-0.5 * pow(cum[i] - cum[j], 2.0) / s2)
			acc += p[j] * w
			wsum += w
			j -= 1
		j = i + 1
		while j < n and cum[j] - cum[i] <= r:
			var w2 := exp(-0.5 * pow(cum[j] - cum[i], 2.0) / s2)
			acc += p[j] * w2
			wsum += w2
			j += 1
		out[i] = acc / wsum
	return out

## Grosor por presión SUAVIZADO a lo largo del trazo (filtro gaussiano por
## longitud): sin escalones ni "bultos" aunque la presión llegue a saltos.
## Los extremos conservan su valor (las salidas afiladas siguen afiladas).
##
## `path` = trazado final (p. ej. el ajustado con Bézier): la presión se
## reparte según dónde cae cada muestra SOBRE ese trazado. Medirla con la
## longitud de las muestras crudas desplazaba los engordes, porque el
## temblor de la mano alarga los tramos temblorosos (VGSE fase 1).
func _build_width_curve_smooth(path: PackedVector2Array = PackedVector2Array()) -> Curve:
	var n := raw_points.size()
	if n < 2 or raw_cum[n - 1] <= 0.001:
		return _build_width_curve()
	var cum: PackedFloat32Array = raw_cum   # se sustituye si hay trazado
	if path.size() >= 2:
		var on_path := arc_on_path(raw_points, path)
		if on_path.size() == n and on_path[n - 1] > 0.001:
			cum = on_path
	var total: float = cum[n - 1]
	var samples := 128
	var vals := PackedFloat32Array()
	vals.resize(samples + 1)
	var j := 0
	for k in samples + 1:
		var d := total * float(k) / float(samples)
		while j < n - 2 and cum[j + 1] < d:
			j += 1
		var seg := maxf(cum[j + 1] - cum[j], 0.000001)
		var f := clampf((d - cum[j]) / seg, 0.0, 1.0)
		vals[k] = _pressure_to_scale(lerpf(raw_pressures[j], raw_pressures[j + 1], f))
	var sigma := maxf(brush_width * 0.6, total / 200.0) / (total / float(samples))
	var radius := int(ceil(sigma * 2.5))
	var curve := Curve.new()
	curve.bake_resolution = 512
	for k in samples + 1:
		var acc := 0.0
		var wsum := 0.0
		# ventana que se estrecha en los extremos: los conserva
		var r := mini(radius, mini(k, samples - k))
		for q in range(-r, r + 1):
			var w := exp(-0.5 * float(q * q) / maxf(sigma * sigma, 0.0001))
			acc += vals[k + q] * w
			wsum += w
		curve.add_point(Vector2(float(k) / float(samples), acc / wsum), 0.0, 0.0,
			Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve

## Longitud de arco sobre `path` (desde su inicio) de la proyección de cada
## muestra. Avanza siempre hacia delante y busca solo un poco por delante:
## en un bucle o un cruce no salta a la otra pasada. Extremos fijados al
## principio y al final del trazado.
static func arc_on_path(samples: PackedVector2Array, path: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := samples.size()
	var m := path.size()
	if n == 0 or m < 2:
		return out
	var pc := PackedFloat32Array()
	pc.resize(m)
	for k in range(1, m):
		pc[k] = pc[k - 1] + path[k].distance_to(path[k - 1])
	var total := pc[m - 1]
	out.resize(n)
	var seg := 0
	var last := 0.0
	for i in n:
		var q := samples[i]
		# Ventana: hasta la distancia recorrida por las muestras desde la
		# anterior (×3) más un margen; nunca hacia atrás.
		var step := q.distance_to(samples[i - 1]) if i > 0 else 0.0
		var reach := last + step * 3.0 + total * 0.02 + 1.0
		var best_d := INF
		var best_s := last
		var best_seg := seg
		var k := seg
		while k < m - 1 and pc[k] <= reach:
			var a := path[k]
			var ab := path[k + 1] - a
			var l2 := ab.length_squared()
			var f := clampf((q - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
			var d := q.distance_squared_to(a + ab * f)
			if d < best_d:
				best_d = d
				best_s = pc[k] + sqrt(l2) * f
				best_seg = k
			k += 1
		last = maxf(last, best_s)
		seg = best_seg
		out[i] = last
	out[0] = 0.0
	out[n - 1] = total
	for i in range(n - 2, 0, -1):
		out[i] = minf(out[i], out[i + 1])
	return out

## La presión queda como perfil de grosor del trazo (meta "stroke_profile"):
## se GUARDA en el archivo (antes width_curve se perdía al recargar) y el
## panel Trazos la muestra y permite retocarla. Uniforme = sin meta.
func _store_pressure_profile(line: Line2D) -> void:
	var c := line.width_curve
	if c == null:
		return
	var prof := PackedVector2Array()
	var varies := false
	for i in c.point_count:
		var q := c.get_point_position(i)
		prof.append(q)
		if absf(q.y - 1.0) > 0.01:
			varies = true
	if varies:
		line.set_meta("stroke_profile", StrokeProfile.normalize(prof))
	elif line.has_meta("stroke_profile"):
		line.remove_meta("stroke_profile")

## Ancho variable por presión del lápiz: un punto de control por cada tramo
## de longitud del trazo según la presión de la pluma.
func _build_width_curve() -> Curve:
	var curve := Curve.new()
	var n := raw_points.size()
	if n < 2 or raw_cum[n - 1] <= 0.001:
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 1.0))
		return curve

	# Puntos repartidos por LONGITUD (Line2D muestrea width_curve por
	# distancia) y más resolución que antes (64 en vez de 32).
	var total: float = raw_cum[n - 1]
	curve.bake_resolution = 256
	var max_ctrl := 64
	var step_len := total / float(max_ctrl)
	var next_t := 0.0
	for i in n:
		if raw_cum[i] + 0.0001 < next_t and i < n - 1:
			continue
		next_t = raw_cum[i] + step_len
		curve.add_point(Vector2(raw_cum[i] / total, _pressure_to_scale(raw_pressures[i])),
			0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	if curve.point_count == 1:
		curve.add_point(Vector2(1.0, _pressure_to_scale(raw_pressures[n - 1])))
	return curve

## Presión (0..1) → grosor relativo según mínimo y curva de respuesta.
func _pressure_to_scale(p: float) -> float:
	if not pressure_size_enabled:
		return 1.0
	if brush_style == "pencil":
		# Lápiz: la presión va entera al tono (rozar = casi transparente,
		# apretar = casi negro); el grosor mínimo no hace de suelo aquí.
		return pow(clampf(p, 0.0, 1.0), maxf(pressure_gamma, 0.05))
	return lerpf(clampf(pressure_min, 0.0, 1.0), 1.0, pow(clampf(p, 0.0, 1.0), maxf(pressure_gamma, 0.05)))

## Presión de esta muestra: la del lápiz si la hay; si no, simulada por la
## velocidad (si está activado) o 1.
func _sample_pressure(event: InputEventMouseMotion, local_pos: Vector2) -> float:
	_track_pen(event)
	var p := event.pressure
	if (p > 0.0 and p < 0.999) or event.tilt != Vector2.ZERO or event.pen_inverted:
		_stroke_is_pen = true
	if _stroke_is_pen:
		# Lápiz: presión 0 = el lápiz se está despegando → grosor MÍNIMO. Antes
		# caía en el caso "ratón" (grosor completo) y el trazo acababa en una
		# mancha redonda, sobre todo al dibujar rápido.
		_last_pressure = p
		return clampf(p, 0.0, 1.0)
	if p > 0.0 and p < 0.999:
		_last_pressure = p
		return p
	if speed_pressure and raw_points.size() > 0:
		var zoom := 1.0
		if is_instance_valid(canvas) and canvas.get_viewport():
			zoom = canvas.get_viewport().get_canvas_transform().get_scale().x
		var screen_px := local_pos.distance_to(raw_points[raw_points.size() - 1]) * zoom
		return clampf(1.15 - screen_px / 45.0, 0.25, 1.0)
	return 1.0

## ¿Hay lápiz? (presión intermedia, inclinación o goma = lápiz real; un
## ratón da 0 o 1). Alimenta el medidor de presión del panel.
func _track_pen(event: InputEventMouseMotion) -> void:
	var p := event.pressure
	if (p > 0.0 and p < 0.999) or event.tilt != Vector2.ZERO or event.pen_inverted:
		pen_detected = true
	live_pressure = p

func save_pressure_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("pressure", "size", pressure_size_enabled)
	cfg.set_value("pressure", "min", pressure_min)
	cfg.set_value("pressure", "gamma", pressure_gamma)
	cfg.set_value("pressure", "smoothing", pressure_smoothing)
	cfg.set_value("pressure", "speed", speed_pressure)
	# El pincel recuerda grosor, estilo y dureza (antes, al volver a elegir el
	# pincel, todo volvía a los valores de fábrica).
	cfg.set_value("brush", "width", brush_width)
	cfg.set_value("brush", "style", brush_style)
	cfg.set_value("brush", "grade", pencil_grade)
	cfg.set_value("brush", "object", JSON.stringify(ObjectBrush.to_data(object_source)))
	cfg.set_value("brush", "object_params", object_params)
	cfg.save(PRESSURE_CFG)
	_settings_dirty = false

func _load_pressure_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PRESSURE_CFG) != OK:
		return
	pressure_size_enabled = bool(cfg.get_value("pressure", "size", pressure_size_enabled))
	pressure_min = float(cfg.get_value("pressure", "min", pressure_min))
	pressure_gamma = float(cfg.get_value("pressure", "gamma", pressure_gamma))
	pressure_smoothing = float(cfg.get_value("pressure", "smoothing", pressure_smoothing))
	speed_pressure = bool(cfg.get_value("pressure", "speed", speed_pressure))
	if cfg.has_section("brush"):
		var st := String(cfg.get_value("brush", "style", brush_style))
		if st != "" and st != "eraser":
			apply_brush_style(st)
		pencil_grade = String(cfg.get_value("brush", "grade", pencil_grade))
		object_source = ObjectBrush.from_data(JSON.parse_string(String(cfg.get_value("brush", "object", "[]"))))
		var op = cfg.get_value("brush", "object_params", {})
		if op is Dictionary:
			object_params.merge(op, true)
		brush_width = clampf(float(cfg.get_value("brush", "width", brush_width)), MIN_BRUSH_WIDTH, MAX_BRUSH_WIDTH)
		_settings_dirty = false

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
