# ==========================================
# RUTA: res://autoloads/InspectorCore.gd
# AUTOLOAD (Singleton)
# ==========================================
extends Node
## SISTEMA CORE del Inspector — capa central entre la SELECCIÓN del canvas y
## CUALQUIER UI de propiedades (el panel contextual tool_in_Mouse, un panel
## lateral, los campos X/Y del bounding box, etc.).
##
## Responsabilidades:
##  · Sigue la selección viva (MoveTool.selected_shapes) vía GlobalEvents.
##  · Abstrae los distintos tipos de figura (VectorRectangle/Circle/Polygon/
##    Path/Line2D/Polygon2D/texto/Sprite2D/grupo) tras UN modelo de propiedades.
##  · Toda escritura pasa por HistoryManager → una acción = un undo.
##  · Multiselección: valor común, o `mixed = true`.
##  · Alineación / distribución de la selección.
##  · Emite `changed(props)` cuando cambia la selección o una propiedad, para
##    que la UI se re-sincronice sin acoplarse a la lógica.
##
## Invariante: el Inspector, el bounding box y el modelo muestran SIEMPRE los
## mismos valores para la selección actual.

signal changed(props: Dictionary)
signal selection_size_changed(count: int)

## Propiedades expuestas. Cada una: {value, mixed, editable}.
const PROPS := [
	"name", "pos_x", "pos_y", "width", "height", "rotation",
	"fill_color", "stroke_color", "stroke_width", "opacity", "corner_radius", "visible",
]

var _selection: Array = []
var _canvas: Node = null
var _mt = null

func _ready() -> void:
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge:
		for sig in ["selection_changed", "object_transformed", "object_style_changed", "data_selection_cleared", "object_deleted"]:
			if ge.has_signal(sig) and not ge.is_connected(sig, _on_event):
				ge.connect(sig, _on_event)

func _on_event(_a = null, _b = null) -> void:
	_sync_selection()
	changed.emit(current_props())

# ── selección ────────────────────────────────────────────────────────────────
func _get_move_tool():
	if not is_instance_valid(_canvas):
		_canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if is_instance_valid(_canvas) and _canvas.has_method("get_current_tool"):
		var t = _canvas.get_current_tool()
		if t and t.has_method("get_class_name") and t.get_class_name() == "MoveTool":
			return t
	return null

func _sync_selection() -> void:
	_mt = _get_move_tool()
	var prev := _selection.size()
	if _mt and "selected_shapes" in _mt:
		_selection = _mt.selected_shapes.filter(func(s): return is_instance_valid(s))
	else:
		_selection = []
	if _selection.size() != prev:
		selection_size_changed.emit(_selection.size())

func selection() -> Array:
	_sync_selection()
	return _selection

# ── lectura ──────────────────────────────────────────────────────────────────
func _bounds(shape) -> Vector2:
	if _mt and _mt.has_method("_global_rect"):
		return _mt._global_rect(shape).size
	return Vector2.ZERO

func _is_text(shape) -> bool:
	return shape.has_meta("shape_type") and String(shape.get_meta("shape_type")).begins_with("text_")

func _read(shape, prop):
	if not is_instance_valid(shape):
		return null
	match prop:
		"name":       return String(shape.name)
		"pos_x":
			# doc-space para VectorShape (misma fuente que los campos X/Y del
			# bounding box) → invariante: inspector y caja muestran lo mismo.
			return shape.get_doc_position().x if shape is VectorShape else shape.global_position.x
		"pos_y":
			return shape.get_doc_position().y if shape is VectorShape else shape.global_position.y
		"rotation":
			return snappedf(rad_to_deg(shape.get_doc_rotation() if shape is VectorShape else shape.global_rotation), 0.01)
		"opacity":    return shape.modulate.a
		"visible":    return shape.visible
		"width":
			if _is_text(shape): return float(shape.get_meta("width", 350.0))
			if "size" in shape: return (shape.get("size") as Vector2).x
			if "width" in shape: return float(shape.get("width"))
			return _bounds(shape).x
		"height":
			if _is_text(shape): return float(shape.get_meta("height", 65.0))
			if "size" in shape: return (shape.get("size") as Vector2).y
			if "height" in shape: return float(shape.get("height"))
			return _bounds(shape).y
		"fill_color":
			if "fill_color" in shape: return shape.fill_color
			if shape is Polygon2D: return shape.color
			return null
		"stroke_color":
			if "stroke_color" in shape: return shape.stroke_color
			if shape is Line2D: return shape.default_color
			return null
		"stroke_width":
			if "stroke_width" in shape: return shape.stroke_width
			if shape is Line2D: return shape.width
			return null
		"corner_radius":
			if "corner_radius" in shape: return shape.corner_radius
			return null
	return null

## {prop: {value, mixed}} para la selección actual. {} si no hay selección.
func current_props() -> Dictionary:
	var out := {}
	if _selection.is_empty():
		return out
	for prop in PROPS:
		var vals := []
		for s in _selection:
			var v = _read(s, prop)
			if v != null:
				vals.append(v)
		if vals.is_empty():
			continue
		var mixed := false
		for v in vals:
			if not _approx_eq(v, vals[0]):
				mixed = true
				break
		# nombre solo tiene sentido con selección única
		if prop == "name" and _selection.size() > 1:
			continue
		out[prop] = {"value": vals[0], "mixed": mixed}
	return out

func _approx_eq(a, b) -> bool:
	if a is float and b is float: return is_equal_approx(a, b)
	if a is int and b is int: return a == b
	if a is Vector2 and b is Vector2: return a.is_equal_approx(b)
	if a is Color and b is Color: return a.is_equal_approx(b)
	return a == b

# ── escritura (con undo) ─────────────────────────────────────────────────────
## Aplica `value` a `prop` en TODAS las figuras seleccionadas, en UNA acción de
## undo. No hace nada si el valor no cambia.
func apply(prop: String, value) -> void:
	_sync_selection()
	if _selection.is_empty() or not (prop in PROPS):
		return
	var recs := []
	for s in _selection:
		var before = _read(s, prop)
		if before == null or _approx_eq(before, value):
			continue
		recs.append({"s": s, "before": before})
	if recs.is_empty():
		return
	var do_fn := func() -> void:
		for r in recs:
			_write(r["s"], prop, value)
		_post_write()
	var undo_fn := func() -> void:
		for r in recs:
			_write(r["s"], prop, r["before"])
		_post_write()
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Inspector · %s" % prop)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()

func _write(shape, prop, value) -> void:
	if not is_instance_valid(shape):
		return
	match prop:
		"name":
			var t := String(value).strip_edges()
			if t != "":
				shape.name = t
		"pos_x":
			if shape is VectorShape:
				shape.set_doc_position(DVec2.new(float(value), shape.get_doc_position().y))
			else:
				shape.global_position = Vector2(float(value), shape.global_position.y)
		"pos_y":
			if shape is VectorShape:
				shape.set_doc_position(DVec2.new(shape.get_doc_position().x, float(value)))
			else:
				shape.global_position = Vector2(shape.global_position.x, float(value))
		"rotation":
			if shape is VectorShape:
				shape.set_doc_rotation(deg_to_rad(float(value)))
			else:
				shape.global_rotation = deg_to_rad(float(value))
		"opacity":
			shape.modulate.a = clampf(float(value), 0.0, 1.0)
		"visible":
			shape.visible = bool(value)
		"width", "height":
			_write_extent(shape, prop, maxf(1.0, float(value)))
		"fill_color":
			if "fill_color" in shape: shape.fill_color = value
			elif shape is Polygon2D: shape.color = value
		"stroke_color":
			if "stroke_color" in shape: shape.stroke_color = value
			elif shape is Line2D: shape.default_color = value
		"stroke_width":
			if "stroke_width" in shape: shape.stroke_width = maxf(0.0, float(value))
			elif shape is Line2D: shape.width = maxf(0.1, float(value))
		"corner_radius":
			if "corner_radius" in shape: shape.corner_radius = maxf(0.0, float(value))
	if shape.has_method("queue_redraw"):
		shape.queue_redraw()

func _write_extent(shape, prop: String, v: float) -> void:
	if _is_text(shape):
		var w := float(shape.get_meta("width", 350.0))
		var h := float(shape.get_meta("height", 65.0))
		if prop == "width": w = v
		else: h = v
		shape.set_meta("width", w)
		shape.set_meta("height", h)
		if _mt and _mt.has_method("_update_text_node_sizes"):
			_mt._update_text_node_sizes(shape, w, h)
		return
	if "size" in shape:
		var sz: Vector2 = shape.get("size")
		if prop == "width": sz.x = v
		else: sz.y = v
		if shape is VectorShape and shape.has_doc_extent():
			shape.set_doc_extent(DVec2.from_v2(sz))
		else:
			shape.set("size", sz)
		return
	if prop == "width" and "width" in shape:
		shape.set("width", v)
	elif prop == "height" and "height" in shape:
		shape.set("height", v)

func _sync_doc(shape) -> void:
	if shape is VectorShape:
		shape.doc_position = DVec2.from_v2(shape.position)

func _post_write() -> void:
	if _mt and _mt.has_method("_update_bounding_box"):
		_mt._update_bounding_box()
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge:
		ge.emit_safe("object_style_changed")
	changed.emit(current_props())

# ── alineación / distribución ────────────────────────────────────────────────
## mode: left | center_h | right | top | middle | bottom
## `modes`: un String ("left") o un Array (["left","top"]) para alinear en los
## dos ejes a la vez. Referencia: caja combinada de la selección (2+) o el
## artboard que la contiene (1). Una sola acción de undo.
func align(modes) -> void:
	_sync_selection()
	if _selection.is_empty():
		return
	var ref := _align_reference()
	if ref.size == Vector2.ZERO:
		return
	var lista: Array = modes if modes is Array else [modes]
	var moves := []
	for s in _selection:
		var r: Rect2 = _mt._global_rect(s)
		var d := Vector2.ZERO
		for mode in lista:
			match mode:
				"left":     d.x = ref.position.x - r.position.x
				"center_h": d.x = ref.get_center().x - r.get_center().x
				"right":    d.x = ref.end.x - r.end.x
				"top":      d.y = ref.position.y - r.position.y
				"middle":   d.y = ref.get_center().y - r.get_center().y
				"bottom":   d.y = ref.end.y - r.end.y
		if d != Vector2.ZERO:
			moves.append({"s": s, "before": s.global_position, "after": s.global_position + d})
	_commit_moves("Alinear " + "+".join(lista), moves)

## axis: h | v — espaciado uniforme entre bordes (necesita 3+ figuras).
func distribute(axis: String) -> void:
	_sync_selection()
	if _selection.size() < 3:
		return
	var items := []
	for s in _selection:
		items.append({"s": s, "r": _mt._global_rect(s)})
	items.sort_custom(func(a, b):
		var ka: float = a["r"].get_center().x if axis == "h" else a["r"].get_center().y
		var kb: float = b["r"].get_center().x if axis == "h" else b["r"].get_center().y
		return ka < kb)
	var first_r: Rect2 = items[0]["r"]
	var last_r: Rect2 = items[items.size() - 1]["r"]
	var span: float
	var sum_sizes := 0.0
	if axis == "h":
		span = last_r.end.x - first_r.position.x
		for it in items: sum_sizes += it["r"].size.x
	else:
		span = last_r.end.y - first_r.position.y
		for it in items: sum_sizes += it["r"].size.y
	var gap := (span - sum_sizes) / float(items.size() - 1)
	var cursor: float = first_r.position.x if axis == "h" else first_r.position.y
	var moves := []
	for it in items:
		var s = it["s"]
		var r: Rect2 = it["r"]
		var d := Vector2.ZERO
		if axis == "h":
			d.x = cursor - r.position.x
			cursor += r.size.x + gap
		else:
			d.y = cursor - r.position.y
			cursor += r.size.y + gap
		if d != Vector2.ZERO:
			moves.append({"s": s, "before": s.global_position, "after": s.global_position + d})
	_commit_moves("Distribuir " + axis, moves)

func _align_reference() -> Rect2:
	if _selection.size() >= 2 and _mt and _mt.has_method("_get_macro_rect"):
		return _mt._get_macro_rect()
	# selección única → el artboard que la contiene
	var mgr := get_tree().get_first_node_in_group("artboard_manager") if get_tree() else null
	if mgr and mgr.has_method("owning_artboard"):
		var ab = mgr.owning_artboard(_selection[0])
		if is_instance_valid(ab):
			return Rect2(ab.global_position, ab.artboard_size)
	return Rect2()

func _commit_moves(accion: String, moves: Array) -> void:
	if moves.is_empty():
		return
	var do_fn := func() -> void:
		for m in moves:
			if is_instance_valid(m["s"]):
				m["s"].global_position = m["after"]
				_sync_doc(m["s"])
		_post_write()
	var undo_fn := func() -> void:
		for m in moves:
			if is_instance_valid(m["s"]):
				m["s"].global_position = m["before"]
				_sync_doc(m["s"])
		_post_write()
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action(accion)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()
