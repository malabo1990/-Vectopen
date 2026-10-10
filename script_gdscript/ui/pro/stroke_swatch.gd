# =============================================================================
# RUTA: res://script_gdscript/ui/pro/stroke_swatch.gd
# Muestra dibujada de una opción de trazo (punta, remate, estilo o perfil).
# La usan los chips del panel Trazos y las listas de su panel desplegable:
# se dibuja con el mismo código que el lienzo (StrokeMarkers / StrokeProfile),
# así lo que se ve en la lista es lo que sale en el trazo.
# =============================================================================
extends Control
const StrokeProfile = preload("res://script_gdscript/shapes/stroke_profile.gd")
const StrokeMarkers = preload("res://script_gdscript/shapes/stroke_markers.gd")
const StrokeGeom = preload("res://script_gdscript/shapes/stroke_geom.gd")

## "marker" | "cap" | "style" | "profile"
var kind := "marker"
var value: Variant = 0
## La punta / el remate va a la IZQUIERDA (extremo de inicio).
var at_start := false
var color_override := Color(0, 0, 0, 0)

func _init(k: String = "marker", v: Variant = 0, start: bool = false) -> void:
	kind = k
	value = v
	at_start = start
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(28, 18)

func set_value(v: Variant) -> void:
	value = v
	queue_redraw()

func _col() -> Color:
	return color_override if color_override.a > 0.0 else ProUIStyle.col("PANEL_TEXT")

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-3.0)
	if r.size.x <= 2.0 or r.size.y <= 2.0:
		return
	var col := _col()
	var cy := r.get_center().y
	match kind:
		"marker":
			var t := int(value)
			var sz := minf(r.size.y * 0.9, 14.0)
			var lw := maxf(1.5, sz * 0.16)
			var tip := Vector2(r.position.x + 1.0, cy) if at_start else Vector2(r.end.x - 1.0, cy)
			var other := Vector2(r.end.x, cy) if at_start else Vector2(r.position.x, cy)
			var dir := (tip - other).normalized()
			var body := PackedVector2Array([other, tip])
			body = StrokeMarkers.trim_points(body, StrokeMarkers.trim(t, sz, lw), false)
			draw_line(body[0], body[body.size() - 1], col, lw, true)
			StrokeMarkers.draw(self, tip, dir, t, sz, col, lw)
		"cap":
			# Línea gruesa que acaba en el centro + guía fina del final real.
			var c := int(value)
			var w := minf(r.size.y * 0.6, 10.0)
			var end_x := r.get_center().x
			var from := Vector2(r.end.x if at_start else r.position.x, cy)
			var to := Vector2(end_x, cy)
			draw_line(from, to, col, w, false)
			var d := (to - from).normalized()
			if c == 1:
				draw_circle(to, w * 0.5, col)
			elif c == 2:
				var n := Vector2(-d.y, d.x) * w * 0.5
				draw_colored_polygon(PackedVector2Array([to + n, to - n, to - n + d * w * 0.5, to + n + d * w * 0.5]), col)
			var guide := Color(ProUIStyle.col("ACCENT"), 0.9)
			draw_line(Vector2(end_x, r.position.y), Vector2(end_x, r.end.y), guide, 1.0)
		"style":
			# La misma geometría que el lienzo, a escala de la muestra.
			var w := clampf(r.size.y * 0.55, 3.0, 9.0)
			var line := PackedVector2Array([Vector2(r.position.x + w * 0.5, cy), Vector2(r.end.x - w * 0.5, cy)])
			var m := StrokeGeom.build(line, false, int(value), w, 0, 0, PackedVector2Array(), w * 2.2, w * 1.1)
			if not (m["indices"] as PackedInt32Array).is_empty():
				RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), m["indices"], m["points"], PackedColorArray([col]))
		"profile":
			StrokeProfile.draw_thumbnail(self, r, value, col)
