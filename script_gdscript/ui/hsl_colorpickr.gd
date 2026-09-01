extends Panel
## Selector de color HSV avanzado: anillo de tono + cuadro Saturación×Valor
## dentro, marcadores para ambos, y canal alfa. Sincroniza en dos vías con
## ColorCore (que lo aplica a la selección con undo) y publica `color_changed`.
##
## Antes: solo un anillo de TONO + un slider raro de "luz" — sin saturación.

@export var color_rect: ColorRect         # muestra el color resultante
@export var line_edit: LineEdit           # hex
@export var light_slider: Slider          # (legacy — el cuadro SV ya cubre el Valor)
@export var alpha_slider: Slider

signal color_changed(new_color: Color)

# Estado (fuente de verdad) — el color nunca se pierde en los extremos.
var current_h: float = 0.0
var current_s: float = 1.0
var current_v: float = 1.0
var current_a: float = 1.0

var _outer_r: float = 100.0
var _ring_w: float = 16.0
var _sq: Rect2
var center: Vector2

enum { NONE, RING, SQUARE }
var _drag := NONE
var _sync_guard := false

func _ready() -> void:
	if alpha_slider:
		alpha_slider.min_value = 0.0
		alpha_slider.max_value = 1.0
		alpha_slider.step = 0.001
		alpha_slider.value_changed.connect(_on_alpha_slider)
	if line_edit:
		line_edit.text_submitted.connect(_on_hex_submitted)

	resized.connect(_recalc_geometry)
	_recalc_geometry()

	var cc := get_node_or_null("/root/ColorCore")
	if cc:
		if cc.has_signal("changed") and not cc.changed.is_connected(_on_colorcore_changed):
			cc.changed.connect(_on_colorcore_changed)
		set_color(cc.active_color())
	else:
		_emit()

# ── geometría ────────────────────────────────────────────────────────────────
func _recalc_geometry() -> void:
	center = size * 0.5
	_outer_r = minf(size.x, size.y) * 0.5 - 2.0
	_ring_w = clampf(_outer_r * 0.16, 10.0, 22.0)
	var inner := _outer_r - _ring_w - 6.0
	var s := inner * sqrt(2.0)   # cuadrado inscrito en el círculo interior
	_sq = Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s))
	queue_redraw()

# ── dibujo ───────────────────────────────────────────────────────────────────
func _draw() -> void:
	# Anillo de tono
	var seg := 72
	var r_in := _outer_r - _ring_w
	for i in seg:
		var a1 := TAU * i / seg - PI / 2.0
		var a2 := TAU * (i + 1) / seg - PI / 2.0
		var c1 := Color.from_hsv(float(i) / seg, 1.0, 1.0)
		var c2 := Color.from_hsv(float(i + 1) / seg, 1.0, 1.0)
		draw_polygon(
			PackedVector2Array([
				center + Vector2(cos(a1), sin(a1)) * r_in,
				center + Vector2(cos(a1), sin(a1)) * _outer_r,
				center + Vector2(cos(a2), sin(a2)) * _outer_r,
				center + Vector2(cos(a2), sin(a2)) * r_in,
			]),
			PackedColorArray([c1, c1, c2, c2]))

	# Cuadro Saturación (x) × Valor (y) del tono actual:
	#  · capa 1: gradiente horizontal blanco → tono
	#  · capa 2: gradiente vertical transparente → negro (oscurece hacia abajo)
	var quad := PackedVector2Array([
		_sq.position, Vector2(_sq.end.x, _sq.position.y), _sq.end, Vector2(_sq.position.x, _sq.end.y)])
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var hue_c := Color.from_hsv(current_h, 1.0, 1.0)
	draw_colored_polygon(quad, Color.WHITE, uv, _gt(Color.WHITE, hue_c, false))
	draw_colored_polygon(quad, Color.WHITE, uv, _gt(Color(0, 0, 0, 0), Color(0, 0, 0, 1), true))

	# Marcador del anillo
	var ma := current_h * TAU - PI / 2.0
	var mp := center + Vector2(cos(ma), sin(ma)) * (r_in + _ring_w * 0.5)
	draw_arc(mp, _ring_w * 0.5, 0, TAU, 16, Color(0, 0, 0, 0.5), 2.0)
	draw_arc(mp, _ring_w * 0.5 - 1.0, 0, TAU, 16, Color.WHITE, 2.0)

	# Marcador del cuadro SV
	var sp := _sq.position + Vector2(current_s * _sq.size.x, (1.0 - current_v) * _sq.size.y)
	draw_circle(sp, 6.0, Color(0, 0, 0, 0.35))
	draw_circle(sp, 5.0, Color.WHITE)
	draw_circle(sp, 3.5, _final_color())

var _grad_cache := {}
func _gt(a: Color, b: Color, vertical: bool) -> GradientTexture2D:
	var key := "%s|%s|%d" % [a, b, 1 if vertical else 0]
	if _grad_cache.has(key):
		return _grad_cache[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([a, b])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64 if not vertical else 1
	t.height = 1 if not vertical else 64
	t.fill_from = Vector2.ZERO
	t.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	_grad_cache[key] = t
	return t

# ── interacción ──────────────────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			var lp: Vector2 = mb.position
			var d: float = lp.distance_to(center)
			if d <= _outer_r and d >= _outer_r - _ring_w:
				_drag = RING
				_pick_ring(lp)
			elif _sq.has_point(lp):
				_drag = SQUARE
				_pick_square(lp)
		else:
			_drag = NONE
	elif event is InputEventMouseMotion and _drag != NONE:
		var mm := event as InputEventMouseMotion
		if _drag == RING:
			_pick_ring(mm.position)
		else:
			_pick_square(mm.position)

func _pick_ring(p: Vector2) -> void:
	current_h = fposmod((p - center).angle() + PI / 2.0, TAU) / TAU
	_emit()

func _pick_square(p: Vector2) -> void:
	current_s = clampf((p.x - _sq.position.x) / _sq.size.x, 0.0, 1.0)
	current_v = clampf(1.0 - (p.y - _sq.position.y) / _sq.size.y, 0.0, 1.0)
	_emit()

func _on_alpha_slider(v: float) -> void:
	if _sync_guard: return
	current_a = v
	_emit()

func _on_hex_submitted(txt: String) -> void:
	set_color(Color.from_string(txt.strip_edges(), _final_color()))
	_emit()

# ── sincronización ───────────────────────────────────────────────────────────
func _final_color() -> Color:
	return Color.from_hsv(current_h, current_s, current_v, current_a)

## Fija el color mostrado SIN volver a aplicarlo a la selección.
func set_color(c: Color) -> void:
	current_h = c.h
	current_s = c.s
	current_v = c.v
	current_a = c.a
	_sync_ui()

func _sync_ui() -> void:
	var fc := _final_color()
	_sync_guard = true
	if color_rect: color_rect.color = fc
	if alpha_slider: alpha_slider.set_value_no_signal(current_a)
	if line_edit and not line_edit.has_focus():
		line_edit.text = "#" + fc.to_html(current_a < 1.0).to_upper()
	_sync_guard = false
	queue_redraw()

func _emit() -> void:
	if _sync_guard:
		return
	var fc := _final_color()
	_sync_ui()
	color_changed.emit(fc)
	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_method("set_color"):
		cc.set_color(fc)

func _on_colorcore_changed(_fill: Color, _stroke: Color, _target: String) -> void:
	var cc := get_node_or_null("/root/ColorCore")
	if cc:
		set_color(cc.active_color())
