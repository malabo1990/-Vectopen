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

enum PickerMode { CIRCLE, TRIANGLE, SQUARE }
var current_mode: int = PickerMode.CIRCLE:
	set(v):
		current_mode = v
		_recalc_geometry()
		queue_redraw()

var _outer_r: float = 100.0
var _ring_w: float = 16.0
var _sq: Rect2
var center: Vector2

# Geometría para Triángulo HSV
var _tri_v0: Vector2
var _tri_v1: Vector2
var _tri_v2: Vector2

# Geometría para Cuadrado Figma
var _figma_sv_rect: Rect2
var _figma_hue_rect: Rect2
var _figma_alpha_rect: Rect2

enum DragTarget { NONE, RING, SQUARE, TRIANGLE, FIGMA_SV, FIGMA_HUE, FIGMA_ALPHA }
var _drag: int = DragTarget.NONE
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
	if cc and cc.has_method("active_color"):
		set_color(cc.active_color())
	else:
		_emit()

# ── geometría ────────────────────────────────────────────────────────────────
func _recalc_geometry() -> void:
	center = size * 0.5
	_outer_r = minf(size.x, size.y) * 0.5 - 2.0
	_ring_w = clampf(_outer_r * 0.16, 10.0, 22.0)
	var inner := _outer_r - _ring_w - 6.0

	# 1. Cuadro inscrito en el círculo (Modo Círculo)
	var s := inner * sqrt(2.0)
	_sq = Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s))

	# 2. Triángulo equilátero interior (Modo Triángulo)
	var r_tri := inner - 2.0
	var a0 := current_h * TAU - PI / 2.0
	_tri_v0 = center + Vector2(cos(a0), sin(a0)) * r_tri
	_tri_v1 = center + Vector2(cos(a0 + TAU / 3.0), sin(a0 + TAU / 3.0)) * r_tri
	_tri_v2 = center + Vector2(cos(a0 + 2.0 * TAU / 3.0), sin(a0 + 2.0 * TAU / 3.0)) * r_tri

	# 3. Cuadrado y barras estilo Figma (Modo Cuadrado) - Completa Ancho
	var bar_h := 12.0
	var spacing := 8.0
	var pad_x := 1.0
	var pad_y := 2.0
	var full_w := size.x - pad_x * 2.0
	var sv_h := maxf(100.0, size.y - (bar_h * 2.0 + spacing * 2.0 + pad_y * 2.0 + 4.0))
	_figma_sv_rect = Rect2(Vector2(pad_x, pad_y), Vector2(full_w, sv_h))
	var bar_y := _figma_sv_rect.end.y + spacing
	_figma_hue_rect = Rect2(Vector2(pad_x, bar_y), Vector2(full_w, bar_h))
	_figma_alpha_rect = Rect2(Vector2(pad_x, bar_y + bar_h + spacing), Vector2(full_w, bar_h))

	queue_redraw()

# ── dibujo ───────────────────────────────────────────────────────────────────
func _draw() -> void:
	if size.x < 10.0 or size.y < 10.0:
		return
	# Fondo blanco puro absoluto para todo el lienzo del selector
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
	match current_mode:
		PickerMode.CIRCLE:
			_draw_mode_circle()
		PickerMode.TRIANGLE:
			_draw_mode_triangle()
		PickerMode.SQUARE:
			_draw_mode_square_figma()

func _draw_mode_circle() -> void:
	# Fondo blanco puro dentro y fuera del anillo
	var inner_r := _outer_r - _ring_w
	draw_circle(center, _outer_r + 2.0, Color.WHITE)
	draw_circle(center, inner_r, Color.WHITE)

	_draw_hue_ring()

	# Cuadro SV interior
	var quad := PackedVector2Array([
		_sq.position, Vector2(_sq.end.x, _sq.position.y), _sq.end, Vector2(_sq.position.x, _sq.end.y)])
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var hue_c := Color.from_hsv(current_h, 1.0, 1.0)
	draw_colored_polygon(quad, Color.WHITE, uv, _gt(Color.WHITE, hue_c, false))
	draw_colored_polygon(quad, Color.WHITE, uv, _gt(Color(0, 0, 0, 0), Color(0, 0, 0, 1), true))

	_draw_ring_marker()

	# Marcador SV en el cuadrado
	var sp := _sq.position + Vector2(current_s * _sq.size.x, (1.0 - current_v) * _sq.size.y)
	draw_circle(sp, 6.0, Color(0, 0, 0, 0.35))
	draw_circle(sp, 5.0, Color.WHITE)
	draw_circle(sp, 3.5, _final_color())

func _draw_mode_triangle() -> void:
	# 1. Fondo blanco puro absoluto para todo el disco y el interior
	var inner_r := _outer_r - _ring_w
	draw_circle(center, _outer_r + 2.0, Color.WHITE)
	draw_circle(center, inner_r, Color.WHITE)

	# 2. Anillo exterior de matiz (Hue) y marcador
	_draw_hue_ring()
	_draw_ring_marker()

	# 3. Vértices del triángulo: V0 = Hue puro, V1 = Blanco, V2 = Negro
	var a0 := current_h * TAU - PI / 2.0
	var inner := inner_r - 4.0
	_tri_v0 = center + Vector2(cos(a0), sin(a0)) * inner
	_tri_v1 = center + Vector2(cos(a0 + TAU / 3.0), sin(a0 + TAU / 3.0)) * inner
	_tri_v2 = center + Vector2(cos(a0 + 2.0 * TAU / 3.0), sin(a0 + 2.0 * TAU / 3.0)) * inner

	var hue_c := Color.from_hsv(current_h, 1.0, 1.0)
	# Dibujar triángulo interpolado suave
	draw_polygon(
		PackedVector2Array([_tri_v0, _tri_v1, _tri_v2]),
		PackedColorArray([hue_c, Color.WHITE, Color.BLACK])
	)
	draw_polyline(PackedVector2Array([_tri_v0, _tri_v1, _tri_v2, _tri_v0]), Color(0.75, 0.75, 0.80, 1.0), 1.5)

	# 4. Marcador del triángulo baricéntrico
	var w2 := 1.0 - current_v
	var w0 := current_s * current_v
	var w1 := 1.0 - w0 - w2
	var tp := _tri_v0 * w0 + _tri_v1 * w1 + _tri_v2 * w2
	draw_circle(tp, 6.0, Color(0, 0, 0, 0.35))
	draw_circle(tp, 5.0, Color.WHITE)
	draw_circle(tp, 3.5, _final_color())

func _draw_mode_square_figma() -> void:
	# 1. Cuadro principal Saturación x Valor
	var quad := PackedVector2Array([
		_figma_sv_rect.position,
		Vector2(_figma_sv_rect.end.x, _figma_sv_rect.position.y),
		_figma_sv_rect.end,
		Vector2(_figma_sv_rect.position.x, _figma_sv_rect.end.y)
	])
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var hue_c := Color.from_hsv(current_h, 1.0, 1.0)
	draw_colored_polygon(quad, Color.WHITE, uv, _gt(Color.WHITE, hue_c, false))
	draw_colored_polygon(quad, Color.WHITE, uv, _gt(Color(0, 0, 0, 0), Color(0, 0, 0, 1), true))
	# Borde sutil del cuadro SV
	draw_rect(_figma_sv_rect, Color(0, 0, 0, 0.15), false, 1.0)

	# Marcador SV en el cuadro Figma
	var sp := _figma_sv_rect.position + Vector2(current_s * _figma_sv_rect.size.x, (1.0 - current_v) * _figma_sv_rect.size.y)
	draw_circle(sp, 6.0, Color(0, 0, 0, 0.35))
	draw_circle(sp, 5.0, Color.WHITE)
	draw_circle(sp, 3.5, _final_color())

	# 2. Barra horizontal de Tono (Hue)
	_draw_hue_bar(_figma_hue_rect)
	# Marcador de Hue
	var hx := _figma_hue_rect.position.x + current_h * _figma_hue_rect.size.x
	var hy := _figma_hue_rect.get_center().y
	draw_circle(Vector2(hx, hy), 7.0, Color(0, 0, 0, 0.35))
	draw_circle(Vector2(hx, hy), 6.0, Color.WHITE)
	draw_circle(Vector2(hx, hy), 4.5, Color.from_hsv(current_h, 1.0, 1.0))

	# 3. Barra horizontal de Opacidad (Alpha)
	_draw_alpha_bar(_figma_alpha_rect)
	# Marcador de Alpha
	var ax := _figma_alpha_rect.position.x + current_a * _figma_alpha_rect.size.x
	var ay := _figma_alpha_rect.get_center().y
	draw_circle(Vector2(ax, ay), 7.0, Color(0, 0, 0, 0.35))
	draw_circle(Vector2(ax, ay), 6.0, Color.WHITE)
	draw_circle(Vector2(ax, ay), 4.5, _final_color())

func _draw_hue_ring() -> void:
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

func _draw_ring_marker() -> void:
	var r_in := _outer_r - _ring_w
	var ma := current_h * TAU - PI / 2.0
	var mp := center + Vector2(cos(ma), sin(ma)) * (r_in + _ring_w * 0.5)
	draw_arc(mp, _ring_w * 0.5, 0, TAU, 16, Color(0, 0, 0, 0.5), 2.0)
	draw_arc(mp, _ring_w * 0.5 - 1.0, 0, TAU, 16, Color.WHITE, 2.0)

func _draw_hue_bar(rect: Rect2) -> void:
	var seg := 24
	var w := rect.size.x / seg
	for i in seg:
		var x1 := rect.position.x + i * w
		var c1 := Color.from_hsv(float(i) / seg, 1.0, 1.0)
		var c2 := Color.from_hsv(float(i + 1) / seg, 1.0, 1.0)
		var poly := PackedVector2Array([
			Vector2(x1, rect.position.y),
			Vector2(x1 + w, rect.position.y),
			Vector2(x1 + w, rect.end.y),
			Vector2(x1, rect.end.y)
		])
		draw_polygon(poly, PackedColorArray([c1, c2, c2, c1]))
	draw_rect(rect, Color(0, 0, 0, 0.2), false, 1.0)

func _draw_alpha_bar(rect: Rect2) -> void:
	# Fondo ajedrezado (checkerboard) para previsualización de transparencia
	var check_size := 6.0
	var cols := int(ceil(rect.size.x / check_size))
	var rows := int(ceil(rect.size.y / check_size))
	for r in range(rows):
		for c in range(cols):
			var tile_pos := rect.position + Vector2(c * check_size, r * check_size)
			var tile_size := Vector2(minf(check_size, rect.end.x - tile_pos.x), minf(check_size, rect.end.y - tile_pos.y))
			var col := Color(0.9, 0.9, 0.9, 1.0) if ((r + c) % 2 == 0) else Color.WHITE
			draw_rect(Rect2(tile_pos, tile_size), col)

	var c_solid := Color.from_hsv(current_h, current_s, current_v, 1.0)
	var c_trans := Color.from_hsv(current_h, current_s, current_v, 0.0)
	var poly := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	])
	draw_polygon(poly, PackedColorArray([c_trans, c_solid, c_solid, c_trans]))
	draw_rect(rect, Color(0, 0, 0, 0.15), false, 1.0)

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
			match current_mode:
				PickerMode.CIRCLE:
					var d: float = lp.distance_to(center)
					if d <= _outer_r and d >= _outer_r - _ring_w:
						_drag = DragTarget.RING
						_pick_ring(lp)
					elif _sq.has_point(lp):
						_drag = DragTarget.SQUARE
						_pick_square(lp)
				PickerMode.TRIANGLE:
					var d: float = lp.distance_to(center)
					if d <= _outer_r and d >= _outer_r - _ring_w:
						_drag = DragTarget.RING
						_pick_ring(lp)
					elif _is_point_in_triangle(lp, _tri_v0, _tri_v1, _tri_v2):
						_drag = DragTarget.TRIANGLE
						_pick_triangle(lp)
				PickerMode.SQUARE:
					if _figma_sv_rect.has_point(lp):
						_drag = DragTarget.FIGMA_SV
						_pick_figma_sv(lp)
					elif _figma_hue_rect.has_point(lp):
						_drag = DragTarget.FIGMA_HUE
						_pick_figma_hue(lp)
					elif _figma_alpha_rect.has_point(lp):
						_drag = DragTarget.FIGMA_ALPHA
						_pick_figma_alpha(lp)
		else:
			_drag = DragTarget.NONE
	elif event is InputEventMouseMotion and _drag != DragTarget.NONE:
		var mm := event as InputEventMouseMotion
		match _drag:
			DragTarget.RING:
				_pick_ring(mm.position)
			DragTarget.SQUARE:
				_pick_square(mm.position)
			DragTarget.TRIANGLE:
				_pick_triangle(mm.position)
			DragTarget.FIGMA_SV:
				_pick_figma_sv(mm.position)
			DragTarget.FIGMA_HUE:
				_pick_figma_hue(mm.position)
			DragTarget.FIGMA_ALPHA:
				_pick_figma_alpha(mm.position)

func _pick_ring(p: Vector2) -> void:
	current_h = fposmod((p - center).angle() + PI / 2.0, TAU) / TAU
	_emit()

func _pick_square(p: Vector2) -> void:
	current_s = clampf((p.x - _sq.position.x) / _sq.size.x, 0.0, 1.0)
	current_v = clampf(1.0 - (p.y - _sq.position.y) / _sq.size.y, 0.0, 1.0)
	_emit()

func _pick_figma_sv(p: Vector2) -> void:
	current_s = clampf((p.x - _figma_sv_rect.position.x) / _figma_sv_rect.size.x, 0.0, 1.0)
	current_v = clampf(1.0 - (p.y - _figma_sv_rect.position.y) / _figma_sv_rect.size.y, 0.0, 1.0)
	_emit()

func _pick_figma_hue(p: Vector2) -> void:
	current_h = clampf((p.x - _figma_hue_rect.position.x) / _figma_hue_rect.size.x, 0.0, 1.0)
	_emit()

func _pick_figma_alpha(p: Vector2) -> void:
	current_a = clampf((p.x - _figma_alpha_rect.position.x) / _figma_alpha_rect.size.x, 0.0, 1.0)
	_emit()

func _pick_triangle(p: Vector2) -> void:
	var b := _barycentric(p, _tri_v0, _tri_v1, _tri_v2)
	# Limitar al triángulo
	var w0: float = clampf(b.x, 0.0, 1.0)
	var w1: float = clampf(b.y, 0.0, 1.0)
	var w2: float = clampf(b.z, 0.0, 1.0)
	var sum := w0 + w1 + w2
	if sum > 0.0001:
		w0 /= sum; w1 /= sum; w2 /= sum
	current_v = clampf(1.0 - w2, 0.0, 1.0)
	current_s = clampf(w0 / current_v if current_v > 0.0001 else 0.0, 0.0, 1.0)
	_emit()

func _is_point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var bar := _barycentric(p, a, b, c)
	return bar.x >= -0.05 and bar.y >= -0.05 and bar.z >= -0.05

func _barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denom := d00 * d11 - d01 * d01
	if absf(denom) < 0.000001:
		return Vector3(1, 0, 0)
	var v := (d11 * d20 - d01 * d21) / denom
	var w := (d00 * d21 - d01 * d20) / denom
	var u := 1.0 - v - w
	return Vector3(u, v, w)


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

func set_picker_mode(mode: int) -> void:
	current_mode = clamp(mode, 0, 2)

func get_picker_mode() -> int:
	return current_mode

