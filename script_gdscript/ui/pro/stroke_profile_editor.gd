# =============================================================================
# RUTA: res://script_gdscript/ui/pro/stroke_profile_editor.gd
# Editor del PERFIL DE GROSOR (sustituye al editor de curva genérico que el
# panel Trazos mostraba sin conectar a nada). Se ve la silueta real del
# trazo; los nodos se arrastran (los de los extremos solo en vertical),
# clic en vacío añade un nodo y doble clic / clic derecho lo quita.
#   changed_live(profile) mientras se arrastra · committed(profile) al soltar.
# =============================================================================
extends Control
const StrokeProfile = preload("res://script_gdscript/shapes/stroke_profile.gd")

signal changed_live(profile: PackedVector2Array)
signal committed(profile: PackedVector2Array)

const R := 4.5        # radio del nodo
const PAD := 8.0

var profile := PackedVector2Array([Vector2(0, 1), Vector2(1, 1)])
var _drag := -1
var _hover := -1

func _init() -> void:
	custom_minimum_size = Vector2(0, 92)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

## Uniforme se edita como dos nodos a w = 1.
func set_profile(p) -> void:
	var n := StrokeProfile.normalize(p)
	profile = n if n.size() >= 2 else PackedVector2Array([Vector2(0, 1), Vector2(1, 1)])
	queue_redraw()

func _area() -> Rect2:
	return Rect2(Vector2.ZERO, size).grow(-PAD)

func _to_px(p: Vector2) -> Vector2:
	var a := _area()
	# w = 1 arriba del todo; el trazo es simétrico: se dibuja la mitad de arriba
	return Vector2(a.position.x + p.x * a.size.x, a.get_center().y - p.y * a.size.y * 0.5)

func _to_norm(px: Vector2) -> Vector2:
	var a := _area()
	return Vector2(clampf((px.x - a.position.x) / a.size.x, 0.0, 1.0),
		clampf((a.get_center().y - px.y) / (a.size.y * 0.5), 0.0, 1.0))

func _hit(px: Vector2) -> int:
	for i in profile.size():
		if _to_px(profile[i]).distance_to(px) <= R + 4.0:
			return i
	return -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag >= 0:
			var q := _to_norm(event.position)
			var last := profile.size() - 1
			if _drag == 0:
				q.x = 0.0
			elif _drag == last:
				q.x = 1.0
			else:
				q.x = clampf(q.x, profile[_drag - 1].x + 0.02, profile[_drag + 1].x - 0.02)
			profile[_drag] = q
			queue_redraw()
			changed_live.emit(profile)
		else:
			var h := _hit(event.position)
			if h != _hover:
				_hover = h
				queue_redraw()
		accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var i := _hit(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mb.double_click and i > 0 and i < profile.size() - 1:
				_remove(i)
			elif i >= 0:
				_drag = i
			else:
				var q := _to_norm(mb.position)
				var arr := Array(profile)
				arr.append(q)
				arr.sort_custom(func(a, b): return a.x < b.x)
				profile = PackedVector2Array(arr)
				_drag = profile.find(q)
				changed_live.emit(profile)
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _drag >= 0:
			_drag = -1
			committed.emit(profile)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and i > 0 and i < profile.size() - 1:
			_remove(i)
		accept_event()

func _remove(i: int) -> void:
	profile.remove_at(i)
	_drag = -1
	_hover = -1
	queue_redraw()
	changed_live.emit(profile)
	committed.emit(profile)

func _draw() -> void:
	var a := _area()
	var bg := ProUIStyle.col("INPUT_BG")
	draw_style_box(ProUIStyle.flat(bg, 4, ProUIStyle.col("INPUT_BORDER")), Rect2(Vector2.ZERO, size))
	var grid := Color(ProUIStyle.col("BORDER"), 0.8)
	for k in range(1, 4):
		var x := a.position.x + a.size.x * k / 4.0
		draw_line(Vector2(x, a.position.y), Vector2(x, a.end.y), grid, 1.0)
	draw_line(Vector2(a.position.x, a.get_center().y), Vector2(a.end.x, a.get_center().y), grid, 1.0)
	# Silueta del trazo (las dos mitades)
	var accent := ProUIStyle.col("ACCENT")
	StrokeProfile.draw_thumbnail(self, a, profile, Color(accent, 0.22))
	var top := PackedVector2Array()
	for k in 61:
		var t := float(k) / 60.0
		top.append(_to_px(Vector2(t, StrokeProfile.sample(profile, t))))
	draw_polyline(top, accent, 1.5, true)
	for i in profile.size():
		var p := _to_px(profile[i])
		var on := i == _drag or i == _hover
		draw_circle(p, R + (1.0 if on else 0.0), ProUIStyle.col("PANEL_SURFACE"))
		draw_arc(p, R + (1.0 if on else 0.0), 0.0, TAU, 20, accent, 1.5, true)
		if on:
			draw_circle(p, R - 1.5, accent)
