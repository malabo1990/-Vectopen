# =============================================================================
# RUTA: res://script_gdscript/tools/LightTool.gd
# HERRAMIENTA LUZ (barra de herramientas ▸ ☀): clic = coloca una luz del tipo
# elegido en el panel Iluminación; arrastrar = alcance (distancia) y dirección
# (ángulo) a la vez. Al soltar, la luz queda seleccionada (herramienta Mover)
# para seguir ajustándola en el panel o en el inspector.
# Los ajustes para las luces NUEVAS viven en `settings` (los cambia el panel).
# =============================================================================
extends ToolBase

const LightScript = preload("res://script_gdscript/shapes/vector_light.gd")

## Ajustes de la próxima luz (tipo y parámetros), compartidos con el panel.
static var settings := {"type": "point", "color": Color(1.0, 0.92, 0.75), "energy": 1.2,
	"radius": 300.0, "angle": 45.0, "cone": 45.0, "falloff": 0.0, "mode": "add",
	"shadows": true, "shadow_color": Color(0, 0, 0, 0.85), "shadow_soft": 0.3}

var start_pos := Vector2.ZERO
var current_pos := Vector2.ZERO
const MIN_DRAG := 12.0

func activate() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	is_drawing = false
	var ge = get_node_or_null("/root/GlobalEvents") if is_inside_tree() else null
	if ge and ge.has_signal("request_tool_panel"):
		ge.emit_safe("request_tool_panel", "light")

func deactivate() -> void:
	is_drawing = false
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouse and "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false
	# posición del PROPIO evento (con la tableta llegan seguidos y la del
	# ratón del sistema va un paso por detrás)
	var gm: Vector2 = canvas.get_global_mouse_position()
	if event is InputEventMouse:
		gm = canvas.get_canvas_transform().affine_inverse() * (event as InputEventMouse).position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_drawing = true
			start_pos = gm
			current_pos = gm
			canvas.queue_redraw()
			return true
		elif is_drawing:
			is_drawing = false
			current_pos = gm
			place(start_pos, current_pos)
			return true
	if event is InputEventMouseMotion and is_drawing:
		current_pos = gm
		canvas.queue_redraw()
		return true
	return false

## Crea la luz en `a` (global); si se arrastró hasta `b`, alcance = distancia y
## dirección = ángulo del arrastre. Devuelve la luz.
func place(a: Vector2, b: Vector2) -> Node2D:
	var pm := get_node_or_null("/root/PluginManager")
	if pm == null or pm.api == null:
		return null
	var api = pm.api
	var ab: Node2D = api.artboard()
	var local := ab.to_local(a) if ab else a
	var p: Dictionary = settings.duplicate()
	var d := b - a
	if d.length() >= MIN_DRAG:
		p["radius"] = d.length() / maxf(ab.global_transform.get_scale().x if ab else 1.0, 0.0001)
		p["angle"] = rad_to_deg(d.angle())
	var t := String(p["type"])
	p.erase("type")
	var l: Node2D = api.add_light(local, t, p)
	if l:
		api.select([l])
		var mt = canvas._new_tool(canvas.MoveTool_Script) if canvas.MoveTool_Script else null
		if mt:
			canvas.call_deferred("change_tool", mt)
	return l

func draw_preview(c: Node2D) -> void:
	if not is_drawing:
		return
	var a := c.to_local(start_pos)
	var b := c.to_local(current_pos)
	var col := Color(1.0, 0.75, 0.1, 0.9)
	var vp := c.get_viewport()
	var k := 1.0 / maxf(vp.get_canvas_transform().get_scale().x if vp else 1.0, 0.0001)
	c.draw_circle(a, 5.0 * k, col)
	var t := String(settings["type"])
	if t == "point" or t == "spot":
		c.draw_arc(a, a.distance_to(b), 0.0, TAU, 96, Color(col, 0.5), 1.0 * k)
	if t != "ambient":
		c.draw_line(a, b, col, 1.5 * k)
