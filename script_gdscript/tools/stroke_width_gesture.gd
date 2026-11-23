# =============================================================================
# RUTA: res://script_gdscript/tools/stroke_width_gesture.gd
# Mayús + arrastrar SOBRE un polígono / figura / trazado Bézier SELECCIONADO
# (con las herramientas de figura, Bézier, pluma o nodos) = cambiar su GROSOR
# DE TRAZO en tiempo real, como el pincel: proporcional, derecha / arriba =
# más grueso, izquierda / abajo = más fino. Un solo paso de deshacer al soltar.
# Mayús + arrastrar FUERA de la selección sigue dibujando proporcional.
# =============================================================================
extends RefCounted

const RATE := 1.03
const MAX_W := 500.0
## Herramientas en las que vale el gesto (Mover usa Mayús para restringir).
const TOOLS := ["CircleTool.gd", "PentagonTool.gd", "StarTool.gd", "Star4Tool.gd", "Star5Tool.gd",
	"TriangleTool.gd", "WaterDropTool.gd", "beziertool.gd", "PenTool.gd", "NodeSelectionTool.gd"]

var canvas: Node2D
var active := false
var _start := Vector2.ZERO
var _before := {}   # nodo → grosor inicial
var _label: Label = null

func _init(cv: Node2D) -> void:
	canvas = cv

static func width_for(start: float, d: float) -> float:
	return clampf(maxf(start, 0.5) * pow(RATE, d) + d * 0.05, 0.0, MAX_W)

func _ic() -> Node:
	return canvas.get_node_or_null("/root/InspectorCore")

func _tool_ok() -> bool:
	var t = canvas.current_tool
	return t != null and t.get_script() != null and String(t.get_script().resource_path).get_file() in TOOLS

## Caja global (con margen) de una figura o trazado.
static func grect(n: Node2D, pad: float) -> Rect2:
	var pts := PackedVector2Array()
	if n is Path2D and (n as Path2D).curve:
		pts = (n as Path2D).curve.get_baked_points()
	elif n.has_method("get_effect_points"):
		pts = n.get_effect_points()
	if pts.is_empty():
		return Rect2()
	var r := Rect2(n.global_transform * pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(n.global_transform * q)
	var sw := float(n.get("stroke_width")) if "stroke_width" in n else 0.0
	return r.grow(pad + sw * 0.5 * n.global_transform.get_scale().x)

## true = el evento es del gesto (el lienzo no lo pasa a la herramienta).
func handle(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not active:
			return _try_begin(event)
		if not event.pressed and active:
			_end()
			return true
	elif event is InputEventMouseMotion and active:
		var d: float = (event.position.x - _start.x) + (_start.y - event.position.y)
		var ic := _ic()
		var w_show := 0.0
		for s in _before:
			if is_instance_valid(s):
				var w := width_for(float(_before[s]), d)
				ic._write(s, "stroke_width", w)
				w_show = w
		ic.post_write_live(false)
		_show(event.position, w_show)
		return true
	return false

func _try_begin(event: InputEventMouseButton) -> bool:
	if not _tool_ok():
		return false
	var ic := _ic()
	if ic == null:
		return false
	var gm: Vector2 = canvas.get_canvas_transform().affine_inverse() * event.position
	var zoom: float = maxf(canvas.get_canvas_transform().get_scale().x, 0.001)
	var hit := false
	var cand := {}
	for s in ic.selection():
		if s is Node2D and "stroke_width" in s and not s.has_meta("table"):
			cand[s] = float(s.get("stroke_width"))
			if grect(s, 8.0 / zoom).has_point(gm):
				hit = true
	if not hit:
		return false
	_before = cand
	_start = event.position
	active = true
	Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
	return true

func _end() -> void:
	active = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	var ic := _ic()
	if ic and not _before.is_empty():
		ic.commit_live("stroke_width", _before)
		ic.post_write_live(true)
	_before = {}
	if is_instance_valid(_label):
		_label.get_parent().queue_free()
	_label = null

func _show(at: Vector2, w: float) -> void:
	if not is_instance_valid(_label):
		var layer := CanvasLayer.new()
		layer.layer = 120
		_label = Label.new()
		_label.add_theme_color_override("font_color", Color.WHITE)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.45, 0.95, 0.92)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		_label.add_theme_stylebox_override("normal", sb)
		layer.add_child(_label)
		canvas.add_child(layer)
	_label.text = ("Grosor %s px" % (String.num(w, 2) if w < 10.0 else String.num(w, 1))).replace(".", ",")
	_label.position = at + Vector2(16, -30)
