# =============================================================================
# RUTA: res://script_gdscript/tools/move/light_handles.gd
# TIRADORES DE LA LUZ seleccionada (herramienta Mover):
#   ● «reach»: en la punta del alcance (puntual / foco) o de la flecha
#     (direccional): arrastrar = alcance Y dirección a la vez;
#   ◆ «cone» (solo foco): en el borde del cono: arrastrar = apertura.
# En vivo y UN paso de deshacer al soltar. Misma forma que table_handles.gd.
# =============================================================================
extends RefCounted

const GRAB_PX := 9.0
const DIR_LEN := 60.0     # largo de la flecha de la luz direccional

var light: Node2D = null
var hover := ""
var drag := ""
var _before := {}

static func target(sel: Array) -> Node2D:
	if sel.size() != 1 or not is_instance_valid(sel[0]):
		return null
	return sel[0] if String(sel[0].get_meta("shape_type", "")) == "light" else null

func _dir() -> Vector2:
	return Vector2.from_angle(deg_to_rad(float(light.lamp_angle)))

## Posiciones globales de los tiradores que tiene este tipo de luz.
func points() -> Dictionary:
	var out := {}
	if not is_instance_valid(light):
		return out
	var c := light.global_position
	var k := light.global_transform.get_scale().x
	match String(light.lamp_type):
		"point", "spot":
			out["reach"] = c + _dir() * float(light.lamp_radius) * k
			if String(light.lamp_type) == "spot":
				out["cone"] = c + _dir().rotated(deg_to_rad(float(light.lamp_cone)) * 0.5) * float(light.lamp_radius) * k * 0.6
		"directional":
			out["reach"] = c + _dir() * DIR_LEN * k
	return out

func hit(gm: Vector2, zoom: float) -> String:
	var tol := GRAB_PX / maxf(zoom, 0.0001)
	var pts := points()
	for key in ["cone", "reach"]:
		if pts.has(key) and gm.distance_to(pts[key]) <= tol:
			return key
	return ""

func begin(key: String) -> void:
	drag = key
	_before = {"lamp_radius": light.lamp_radius, "lamp_angle": light.lamp_angle, "lamp_cone": light.lamp_cone}

func update(gm: Vector2) -> void:
	if drag == "" or not is_instance_valid(light):
		return
	var c := light.global_position
	var d := gm - c
	var k := maxf(light.global_transform.get_scale().x, 0.0001)
	if drag == "reach":
		light.lamp_angle = rad_to_deg(d.angle())
		if String(light.lamp_type) != "directional":
			light.lamp_radius = maxf(d.length() / k, 4.0)
	elif drag == "cone":
		light.lamp_cone = clampf(absf(rad_to_deg(_dir().angle_to(d))) * 2.0, 5.0, 170.0)
	light.queue_redraw()

func finish() -> void:
	if drag == "" or not is_instance_valid(light):
		drag = ""
		return
	var after := {"lamp_radius": light.lamp_radius, "lamp_angle": light.lamp_angle, "lamp_cone": light.lamp_cone}
	var before := _before.duplicate()
	var l := light
	drag = ""
	if var_to_str(after) == var_to_str(before):
		return
	var hm: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("HistoryManager")
	if hm:
		hm.register_action("Luz · alcance y dirección")
		hm.add_do(func() -> void:
			if is_instance_valid(l):
				for k2 in after: l.set(k2, after[k2]))
		hm.add_undo(func() -> void:
			if is_instance_valid(l):
				for k2 in before: l.set(k2, before[k2]))
		hm.commit()

func cancel() -> void:
	if drag != "" and is_instance_valid(light):
		for k2 in _before:
			light.set(k2, _before[k2])
	drag = ""

## Tiradores en el lienzo (mismo azul que los de la caja de selección).
func draw(c: Node2D, zoom: float) -> void:
	if not is_instance_valid(light):
		return
	var k := 1.0 / maxf(zoom, 0.0002)
	var acc := Color(0.05, 0.55, 0.91, 1.0)
	var center := c.to_local(light.global_position)
	for key in points():
		var p: Vector2 = c.to_local(points()[key])
		var on: bool = hover == key or drag == key
		c.draw_line(center, p, Color(acc, 0.6), 1.0 * k)
		if key == "cone":
			var pts := PackedVector2Array([p + Vector2(0, -6) * k, p + Vector2(6, 0) * k, p + Vector2(0, 6) * k, p + Vector2(-6, 0) * k])
			c.draw_colored_polygon(pts, Color.WHITE)
			c.draw_polyline(pts + PackedVector2Array([pts[0]]), acc, (2.0 if on else 1.4) * k)
		else:
			c.draw_circle(p, (7.0 if on else 5.5) * k, Color.WHITE)
			c.draw_arc(p, (7.0 if on else 5.5) * k, 0.0, TAU, 24, acc, 1.6 * k)
