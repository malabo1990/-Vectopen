# ==========================================
# RUTA: res://autoloads/InspectorCore.gd
# AUTOLOAD (Singleton)
# ==========================================
extends Node
const TextRuns = preload("res://script_gdscript/text/text_runs.gd")
const TextCore = preload("res://script_gdscript/text/text_core.gd")

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
	"font_size", "line_spacing", "letter_spacing",
	"indent_left", "indent_right", "indent_first",
	"columns", "column_gap",
	"font_family", "font_weight", "font_italic",
	"fill_paint", "text_align", "text_valign", "text",
	"corner_tl", "corner_tr", "corner_br", "corner_bl",
	"stroke_cap_start", "stroke_cap_end", "stroke_style",
	"stroke_pointer_start", "stroke_pointer_end", "stroke_align",
	"stroke_dash_len", "stroke_dash_gap",
	"letter_proportions",
	"effects",
	"shape_mode", "start_angle_deg", "end_angle_deg", "inner_radius_ratio", "points_count",
	"sides", "is_regular",
	"model_path", "model_rotation_x", "model_rotation_y", "model_rotation_z", "camera_distance", "camera_fov", "light_energy", "light_rotation_x", "light_rotation_y",
]

## Propiedades de texto: se leen/escriben como meta del contenedor + se aplican
## a la etiqueta de display (DisplayLabel). Defaults del proyecto.
const _TEXT_META_DEFAULT := {"font_size": 24, "line_spacing": 0}

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
	if not is_inside_tree():
		return   # app shutting down: listeners and autoloads are leaving the tree
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
	_mt = _get_move_tool()   # solo para helpers de geometría (_global_rect, …)
	var prev := _selection.size()
	# FUENTE DE VERDAD: SelectionManager. `MoveTool.selected_shapes` es únicamente
	# un espejo que la herramienta mantiene; leerlo antes acoplaba el Inspector a
	# la herramienta activa y podía mostrar una selección desincronizada. Se lee
	# el manager directamente; el espejo de MoveTool queda solo como red de
	# seguridad para el caso (no real) de que el autoload no esté disponible.
	var sm := get_node_or_null("/root/SelectionManager")
	var sm_sel: Array = sm.get_selected() if (sm and sm.has_method("get_selected")) else []
	var mt_sel: Array = _mt.selected_shapes if (_mt and "selected_shapes" in _mt) else []
	if not sm_sel.is_empty() or mt_sel.is_empty():
		_selection = sm_sel.filter(func(s): return is_instance_valid(s))
	else:
		_selection = mt_sel.filter(func(s): return is_instance_valid(s))
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

func _text_label(shape) -> Node:
	return shape.get_node_or_null("DisplayLabel")

## Color de una figura de texto: primero la meta (persistida), si no el override
## de tema del DisplayLabel, si no el default.
func _text_label_color(shape, theme_key: String, def: Color) -> Color:
	var meta_key := "text_color" if theme_key == "font_color" else "text_outline_color"
	if shape.has_meta(meta_key):
		return shape.get_meta(meta_key)
	var dl := _text_label(shape)
	if dl and dl.has_theme_color_override(theme_key):
		return dl.get_theme_color(theme_key)
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		if theme_key == "font_color":
			return vrt.get_text_color()
		else:
			return vrt.get_stroke_color()
	return def

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
			if "artboard_size" in shape: return (shape.artboard_size as Vector2).x
			if "size" in shape: return (shape.get("size") as Vector2).x
			if "width" in shape: return float(shape.get("width"))
			return _bounds(shape).x
		"height":
			if _is_text(shape): return float(shape.get_meta("height", 65.0))
			if "artboard_size" in shape: return (shape.artboard_size as Vector2).y
			if "size" in shape: return (shape.get("size") as Vector2).y
			if "height" in shape: return float(shape.get("height"))
			return _bounds(shape).y
		"fill_color":
			if _is_text(shape): return _text_label_color(shape, "font_color", Color.BLACK)
			if "fill_color" in shape: return shape.fill_color
			if shape is Polygon2D: return shape.color
			if shape is Line2D: return shape.default_color
			return null
		"stroke_color":
			if _is_text(shape):
				if shape.has_meta("stroke_color"): return shape.get_meta("stroke_color")
				return _text_label_color(shape, "font_outline_color", Color.BLACK)
			if "stroke_color" in shape: return shape.stroke_color
			if shape is Line2D: return shape.default_color
			return null
		"stroke_width":
			if _is_text(shape):
				if shape.has_meta("stroke_width"): return float(shape.get_meta("stroke_width"))
				return float(shape.get_meta("text_outline", 0))
			if "stroke_width" in shape: return shape.stroke_width
			if shape is Line2D: return shape.width
			return null
		"text_align":
			if _is_text(shape): return String(shape.get_meta("text_align", "left"))
			return null
		"text_valign":
			if _is_text(shape): return String(shape.get_meta("text_valign", "top"))
			return null
		"text":
			if _is_text(shape): return String(shape.get_meta("text", ""))
			return null
		"corner_radius":
			if "corner_radius" in shape: return shape.corner_radius
			return null
		"corner_tl":
			if "corner_tl" in shape: return shape.corner_tl
			return null
		"corner_tr":
			if "corner_tr" in shape: return shape.corner_tr
			return null
		"corner_br":
			if "corner_br" in shape: return shape.corner_br
			return null
		"corner_bl":
			if "corner_bl" in shape: return shape.corner_bl
			return null
		"font_size":
			if _is_text(shape): return float(shape.get_meta("font_size", 24))
			return null
		"line_spacing":
			if _is_text(shape): return float(shape.get_meta("line_spacing", 0))
			return null
		"letter_spacing":
			if _is_text(shape): return float(shape.get_meta("letter_spacing", 0))
			return null
		"indent_left":
			if _is_text(shape): return float(shape.get_meta("indent_left", 0))
			return null
		"indent_right":
			if _is_text(shape): return float(shape.get_meta("indent_right", 0))
			return null
		"indent_first":
			if _is_text(shape): return float(shape.get_meta("indent_first", 0))
			return null
		"columns":
			if _is_text(shape): return int(shape.get_meta("columns", 1))
			return null
		"column_gap":
			if _is_text(shape): return float(shape.get_meta("column_gap", 20.0))
			return null
		"font_family":
			if _is_text(shape): return String(shape.get_meta("font_family", "Inter"))
			return null
		"font_weight":
			if _is_text(shape): return int(shape.get_meta("font_weight", 400))
			return null
		"font_italic":
			if _is_text(shape): return bool(shape.get_meta("font_italic", false))
			return null
		"letter_proportions":
			if _is_text(shape):
				return shape.get_meta("letter_proportions", {})
			return null
		"fill_paint":
			return _read_fill_paint(shape)
		"stroke_cap_start":
			if "stroke_cap_start" in shape: return int(shape.stroke_cap_start)
			if shape is Line2D: return int(shape.begin_cap_mode)
			if shape.has_meta("stroke_cap_start"): return int(shape.get_meta("stroke_cap_start"))
			return 0
		"stroke_cap_end":
			if "stroke_cap_end" in shape: return int(shape.stroke_cap_end)
			if shape is Line2D: return int(shape.end_cap_mode)
			if shape.has_meta("stroke_cap_end"): return int(shape.get_meta("stroke_cap_end"))
			return 0
		"stroke_style":
			if "stroke_style" in shape: return int(shape.stroke_style)
			if shape.has_meta("stroke_style"): return int(shape.get_meta("stroke_style"))
			return 0
		"stroke_pointer_start":
			if "stroke_pointer_start" in shape: return int(shape.stroke_pointer_start)
			if shape.has_meta("stroke_pointer_start"): return int(shape.get_meta("stroke_pointer_start"))
			return 0
		"stroke_pointer_end":
			if "stroke_pointer_end" in shape: return int(shape.stroke_pointer_end)
			if shape.has_meta("stroke_pointer_end"): return int(shape.get_meta("stroke_pointer_end"))
			return 0
		"stroke_align":
			if "stroke_align" in shape: return int(shape.stroke_align)
			if shape.has_meta("stroke_align"): return int(shape.get_meta("stroke_align"))
			return 0
		"stroke_dash_len":
			if "stroke_dash_len" in shape: return float(shape.stroke_dash_len)
			if shape.has_meta("stroke_dash_len"): return float(shape.get_meta("stroke_dash_len"))
			return 12.0
		"stroke_dash_gap":
			if "stroke_dash_gap" in shape: return float(shape.stroke_dash_gap)
			if shape.has_meta("stroke_dash_gap"): return float(shape.get_meta("stroke_dash_gap"))
			return 8.0
		"effects":
			if "effects" in shape and shape.effects is Array:
				return shape.effects.duplicate(true)
			if shape.has_meta("effects") and shape.get_meta("effects") is Array:
				return shape.get_meta("effects").duplicate(true)
			return []
		"shape_mode":
			if "shape_mode" in shape: return String(shape.shape_mode)
			return null
		"start_angle_deg":
			if "start_angle_deg" in shape: return float(shape.start_angle_deg)
			return null
		"end_angle_deg":
			if "end_angle_deg" in shape: return float(shape.end_angle_deg)
			return null
		"inner_radius_ratio":
			if "inner_radius_ratio" in shape: return float(shape.inner_radius_ratio)
			return null
		"points_count":
			if "points_count" in shape: return int(shape.points_count)
			return null
		"sides":
			if "sides" in shape: return int(shape.sides)
			return null
		"is_regular":
			if "is_regular" in shape: return bool(shape.is_regular)
			return null
		"model_path":
			if "model_path" in shape: return String(shape.model_path)
			return null
		"model_rotation_x":
			if "model_rotation" in shape: return float(shape.model_rotation.x)
			return null
		"model_rotation_y":
			if "model_rotation" in shape: return float(shape.model_rotation.y)
			return null
		"model_rotation_z":
			if "model_rotation" in shape: return float(shape.model_rotation.z)
			return null
		"camera_distance":
			if "camera_distance" in shape: return float(shape.camera_distance)
			return null
		"camera_fov":
			if "camera_fov" in shape: return float(shape.camera_fov)
			return null
		"light_energy":
			if "light_energy" in shape: return float(shape.light_energy)
			return null
		"light_rotation_x":
			if "light_rotation" in shape: return float(shape.light_rotation.x)
			return null
		"light_rotation_y":
			if "light_rotation" in shape: return float(shape.light_rotation.y)
			return null
	return null

## Devuelve el relleno como {type:"solid"|"linear"|"radial", ...}. null si la
## figura no tiene concepto de relleno.
func _read_fill_paint(shape) -> Variant:
	if shape is VectorShape and shape.has_gradient_fill():
		var g: Gradient = shape.fill_gradient
		var stops: Array = []
		for i in g.get_point_count():
			stops.append([g.get_offset(i), g.get_color(i)])
		var g_kind := "linear"
		if int(shape.fill_gradient_type) == 1:
			g_kind = "radial"
		elif int(shape.fill_gradient_type) == 2:
			g_kind = "conic"
		elif int(shape.fill_gradient_type) == 3:
			g_kind = "diamond"
		elif int(shape.fill_gradient_type) == 4:
			g_kind = "box"
		elif int(shape.fill_gradient_type) == 5:
			g_kind = "spiral"
		elif int(shape.fill_gradient_type) == 6:
			g_kind = "reflected"
		return {
			"type": g_kind,
			"angle": float(shape.fill_gradient_angle),
			"p0": shape.get_gradient_p0_norm(),
			"p1": shape.get_gradient_p1_norm(),
			"stops": stops,
		}
	if shape is Line2D and shape.gradient is Gradient and shape.gradient.get_point_count() >= 2:
		var lg: Gradient = shape.gradient
		var ls: Array = []
		for i in lg.get_point_count():
			ls.append([lg.get_offset(i), lg.get_color(i)])
		return {"type": "linear", "angle": 0.0, "stops": ls}
	if _is_text(shape):
		return {"type": "solid", "color": _text_label_color(shape, "font_color", Color.BLACK)}
	if "fill_color" in shape:
		return {"type": "solid", "color": shape.fill_color}
	if shape is Polygon2D:
		return {"type": "solid", "color": shape.color}
	if shape is Line2D:
		return {"type": "solid", "color": shape.default_color}
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
	if a is Array and b is Array: return a == b
	if a is Dictionary and b is Dictionary: return a == b
	return a == b

# ── escritura (con undo) ─────────────────────────────────────────────────────
## Aplica `value` a `prop` en TODAS las figuras seleccionadas, en UNA acción de
## undo. No hace nada si el valor no cambia.
## [shape, editor, start, end] del texto EN EDICIÓN con selección no vacía.
## Vacío si no hay (entonces color/tamaño van al bloque entero, como siempre).
func _editing_text_range() -> Array:
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if canvas == null or not ("current_tool" in canvas):
		return []
	var t = canvas.current_tool
	# OJO: bool(null) no existe como constructor: null-check explícito.
	var _ed_flag = t.get("is_editing") if t != null else null
	if t == null or _ed_flag == null or not bool(_ed_flag):
		return []
	var shape: Node2D = t.get("current_editing_shape")
	if not is_instance_valid(shape):
		return []
	var ed: TextEdit = shape.get_node_or_null("TitleEdit")
	if ed == null:
		ed = shape.get_node_or_null("MultiLineEdit")
	if ed == null or not ed.visible:
		return []
	var sel = TextCore.sel_range(ed)
	if sel == null or int(sel["end"]) <= int(sel["start"]):
		return []
	return [shape, ed, int(sel["start"]), int(sel["end"])]

## Color/tamaño sobre la PALABRA seleccionada (runs, con undo propio).
## Devuelve true si lo enrutó (apply() entonces no toca el bloque).
func apply_text_range(prop: String, value) -> bool:
	if not (prop in ["fill_color", "font_size", "stroke_color", "stroke_width"]):
		return false
	var ctx := _editing_text_range()
	if ctx.is_empty():
		return false
	var shape: Node2D = ctx[0]
	var ed: TextEdit = ctx[1]
	var start: int = ctx[2]
	var end: int = ctx[3]
	var before: Array = (shape.get_meta("runs", []) as Array).duplicate(true)
	var mutator: Callable
	if prop == "fill_color":
		var c := value as Color
		mutator = func(r: Dictionary) -> Dictionary:
			r["color"] = c
			return r
	elif prop == "font_size":
		var sz := clampf(float(value), 4.0, 400.0)
		mutator = func(r: Dictionary) -> Dictionary:
			r["size"] = sz
			return r
	elif prop == "stroke_color":
		var c := value as Color
		mutator = func(r: Dictionary) -> Dictionary:
			r["stroke_color"] = c
			return r
	elif prop == "stroke_width":
		var w := maxf(0.0, float(value))
		mutator = func(r: Dictionary) -> Dictionary:
			r["stroke_width"] = w
			return r
	var dl := shape.get_node_or_null("DisplayLabel")
	var sync_tool_size := func() -> void:
		if ed.syntax_highlighter:
			ed.syntax_highlighter.clear_highlighting_cache()
		ed.queue_redraw()
		var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
		var t = canvas.current_tool if canvas and ("current_tool" in canvas) else null
		if t:
			if t.has_method("_update_shape_meta_size"):
				t._update_shape_meta_size(shape)
			elif t.has_method("_fit_height_to_text"):
				t._fit_height_to_text(shape, ed.text)
	var do_fn := func() -> void:
		TextRuns.apply_range(shape, dl, ed.text.length(), start, end, mutator)
		if dl and dl.has_method("apply_stroke_meta"):
			dl.apply_stroke_meta()
		sync_tool_size.call()
		_post_write()
	var undo_fn := func() -> void:
		shape.set_meta("runs", before)
		if dl and dl.has_method("set_rich_runs"):
			dl.set_rich_runs(before)
		if dl and dl.has_method("apply_stroke_meta"):
			dl.apply_stroke_meta()
		sync_tool_size.call()
		_post_write()
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Inspector · %s (selección)" % prop)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()
	return true

func apply(prop: String, value) -> void:
	if apply_text_range(prop, value):
		return
	_sync_selection()
	if _selection.is_empty() or not (prop in PROPS):
		return
	var recs := []
	for s in _selection:
		var before = _read(s, prop)
		if before == null:
			continue
		var has_grad: bool = (s is VectorShape and s.has_gradient_fill()) or (s is Line2D and s.gradient is Gradient)
		if not (prop == "fill_color" and has_grad):
			if _approx_eq(before, value):
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

## Aplica un conjunto de propiedades en UNA sola acción de undo.
func apply_multi(props_values: Dictionary, action_name: String = "Inspector · transform") -> void:
	_sync_selection()
	if _selection.is_empty() or props_values.is_empty():
		return
	var recs := []
	for p in props_values:
		if not (p in PROPS):
			continue
		var val = props_values[p]
		for s in _selection:
			var before = _read(s, p)
			if before == null:
				continue
			var has_grad: bool = (s is VectorShape and s.has_gradient_fill()) or (s is Line2D and s.gradient is Gradient)
			if not (p == "fill_color" and has_grad):
				if _approx_eq(before, val):
					continue
			recs.append({"s": s, "prop": p, "before": before, "after": val})
	if recs.is_empty():
		return
	var do_fn := func() -> void:
		for r in recs:
			_write(r["s"], r["prop"], r["after"])
		_post_write()
	var undo_fn := func() -> void:
		for r in recs:
			_write(r["s"], r["prop"], r["before"])
		_post_write()
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action(action_name)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()

## Registra UNA acción de undo para un cambio de propiedad YA aplicado en vivo
## (p.ej. arrastrar un dial). `before`: {figura: valor_previo}. El "after" se lee
## de cada figura ahora mismo. No re-ejecuta la escritura (ya está hecha).
func commit_live(prop: String, before: Dictionary) -> void:
	if not (prop in PROPS):
		return
	var recs := []
	for s in before:
		if not is_instance_valid(s):
			continue
		var aft = _read(s, prop)
		if aft == null or _approx_eq(before[s], aft):
			continue
		recs.append({"s": s, "before": before[s], "after": aft})
	if recs.is_empty():
		return
	var do_fn := func() -> void:
		for r in recs:
			_write(r["s"], prop, r["after"])
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

## Registra UNA acción de undo conjunta para múltiples propiedades YA aplicadas en vivo.
## `props_before`: {prop_name: {figura: valor_previo}}
func commit_live_multi(props_before: Dictionary, action_name: String = "Inspector · transform") -> void:
	var recs := []
	for p in props_before:
		if not (p in PROPS):
			continue
		var before: Dictionary = props_before[p]
		for s in before:
			if not is_instance_valid(s):
				continue
			var aft = _read(s, p)
			if aft == null or _approx_eq(before[s], aft):
				continue
			recs.append({"s": s, "prop": p, "before": before[s], "after": aft})
	if recs.is_empty():
		return
	var do_fn := func() -> void:
		for r in recs:
			_write(r["s"], r["prop"], r["after"])
		_post_write()
	var undo_fn := func() -> void:
		for r in recs:
			_write(r["s"], r["prop"], r["before"])
		_post_write()
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action(action_name)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()

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
			if _is_text(shape):
				_write_text_color(shape, "font_color", value)
			else:
				# Elegir un color plano quita el degradado.
				if shape is VectorShape and shape.has_gradient_fill():
					shape.clear_fill_gradient()
				elif shape is Line2D and shape.gradient is Gradient:
					shape.gradient = null
				if "fill_color" in shape: shape.fill_color = value
				elif shape is Polygon2D: shape.color = value
				elif shape is Line2D: shape.default_color = value
		"stroke_color":
			if _is_text(shape):
				_write_text_color(shape, "font_outline_color", value)
			elif "stroke_color" in shape: shape.stroke_color = value
			elif shape is Line2D: shape.default_color = value
		"stroke_width":
			if _is_text(shape):
				_write_text_outline_size(shape, maxf(0.0, float(value)))
			elif "stroke_width" in shape:
				shape.stroke_width = maxf(0.0, float(value))
				# A uniform width from the inspector replaces any per-side widths
				if shape.has_method("clear_side_strokes"):
					shape.clear_side_strokes()
			elif shape is Line2D: shape.width = maxf(0.1, float(value))
		"corner_radius":
			if "corner_radius" in shape: shape.corner_radius = maxf(0.0, float(value))
		"corner_tl":
			if "corner_tl" in shape: shape.corner_tl = maxf(0.0, float(value))
		"corner_tr":
			if "corner_tr" in shape: shape.corner_tr = maxf(0.0, float(value))
		"corner_br":
			if "corner_br" in shape: shape.corner_br = maxf(0.0, float(value))
		"corner_bl":
			if "corner_bl" in shape: shape.corner_bl = maxf(0.0, float(value))
		"fill_paint":
			_write_fill_paint(shape, value)
		"text_align":
			_write_text_align(shape, value)
		"text_valign":
			_write_text_valign(shape, value)
		"text":
			_write_text_content(shape, String(value))
		"font_size":
			_write_font_size(shape, value)
		"line_spacing":
			_write_line_spacing(shape, value)
		"letter_spacing":
			if _is_text(shape):
				shape.set_meta("letter_spacing", float(value))   # admite 0.5 px (antes int → se perdía)
				var dl2 := _text_label(shape)
				if dl2 and dl2.has_method("apply_font_from_meta"):
					dl2.apply_font_from_meta()
		"font_family", "font_weight", "font_italic":
			_write_font_face(shape, prop, value)
		"letter_proportions":
			_write_letter_proportions(shape, value)
		"indent_left", "indent_right", "indent_first":
			_write_indent(shape, prop, value)
		"columns", "column_gap":
			_write_columns(shape, prop, value)
		"stroke_cap_start":
			var ival := int(value)
			if "stroke_cap_start" in shape: shape.stroke_cap_start = ival
			elif shape is Line2D: shape.begin_cap_mode = clampi(ival, 0, 2) as Line2D.LineCapMode
			shape.set_meta("stroke_cap_start", ival)
		"stroke_cap_end":
			var ival := int(value)
			if "stroke_cap_end" in shape: shape.stroke_cap_end = ival
			elif shape is Line2D: shape.end_cap_mode = clampi(ival, 0, 2) as Line2D.LineCapMode
			shape.set_meta("stroke_cap_end", ival)
		"stroke_style":
			var ival := int(value)
			if "stroke_style" in shape: shape.stroke_style = ival
			shape.set_meta("stroke_style", ival)
		"stroke_pointer_start":
			var ival := int(value)
			if "stroke_pointer_start" in shape: shape.stroke_pointer_start = ival
			shape.set_meta("stroke_pointer_start", ival)
		"stroke_pointer_end":
			var ival := int(value)
			if "stroke_pointer_end" in shape: shape.stroke_pointer_end = ival
			shape.set_meta("stroke_pointer_end", ival)
		"stroke_align":
			var ival := int(value)
			if "stroke_align" in shape: shape.stroke_align = ival
			shape.set_meta("stroke_align", ival)
		"stroke_dash_len":
			var fval := maxf(1.0, float(value))
			if "stroke_dash_len" in shape: shape.stroke_dash_len = fval
			shape.set_meta("stroke_dash_len", fval)
		"stroke_dash_gap":
			var fval := maxf(1.0, float(value))
			if "stroke_dash_gap" in shape: shape.stroke_dash_gap = fval
			shape.set_meta("stroke_dash_gap", fval)
		"effects":
			var eff_arr: Array = value if value is Array else []
			if "effects" in shape:
				shape.effects = eff_arr.duplicate(true)
			shape.set_meta("effects", eff_arr.duplicate(true))
		"shape_mode":
			if "shape_mode" in shape: shape.shape_mode = String(value)
		"start_angle_deg":
			if "start_angle_deg" in shape: shape.start_angle_deg = float(value)
		"end_angle_deg":
			if "end_angle_deg" in shape: shape.end_angle_deg = float(value)
		"inner_radius_ratio":
			if "inner_radius_ratio" in shape: shape.inner_radius_ratio = clampf(float(value), 0.01, 0.95)
		"points_count":
			if "points_count" in shape: shape.points_count = maxi(3, int(value))
		"sides":
			if "sides" in shape:
				shape.is_regular = true
				shape.sides = maxi(3, int(value))
		"is_regular":
			if "is_regular" in shape: shape.is_regular = bool(value)
		"model_path":
			if "model_path" in shape:
				shape.model_path = String(value)
				if shape.has_method("load_model") and not String(value).is_empty():
					shape.load_model(String(value))
		"model_rotation_x":
			if "model_rotation" in shape:
				var mr: Vector3 = shape.model_rotation
				shape.model_rotation = Vector3(float(value), mr.y, mr.z)
		"model_rotation_y":
			if "model_rotation" in shape:
				var mr: Vector3 = shape.model_rotation
				shape.model_rotation = Vector3(mr.x, float(value), mr.z)
		"model_rotation_z":
			if "model_rotation" in shape:
				var mr: Vector3 = shape.model_rotation
				shape.model_rotation = Vector3(mr.x, mr.y, float(value))
		"camera_distance":
			if "camera_distance" in shape:
				shape.camera_distance = float(value)
		"camera_fov":
			if "camera_fov" in shape:
				shape.camera_fov = float(value)
		"light_energy":
			if "light_energy" in shape:
				shape.light_energy = float(value)
		"light_rotation_x":
			if "light_rotation" in shape:
				var lr: Vector3 = shape.light_rotation
				shape.light_rotation = Vector3(float(value), lr.y, lr.z)
		"light_rotation_y":
			if "light_rotation" in shape:
				var lr: Vector3 = shape.light_rotation
				shape.light_rotation = Vector3(lr.x, float(value), lr.z)
	if shape.has_method("request_render_update"):
		shape.request_render_update()
	if shape.has_method("queue_redraw"):
		shape.queue_redraw()

## Familia / peso / itálica de una figura de texto: meta + fuente resuelta por
## FontCore aplicada al DisplayLabel (y al editor inline si existe).
func _write_font_face(shape, prop: String, value) -> void:
	if not _is_text(shape):
		return
	match prop:
		"font_family": shape.set_meta("font_family", String(value))
		"font_weight":
			var w := 400
			if value is int or value is float:
				w = int(value)
			elif value is String:
				match value.to_lower():
					"medium": w = 500
					"bold": w = 700
					"black": w = 900
					"light": w = 300
					_: w = int(value) if value.is_valid_int() else 400
			shape.set_meta("font_weight", w)
		"font_italic": shape.set_meta("font_italic", bool(value))
	var fc := get_node_or_null("/root/FontCore")
	if fc == null:
		return
	var f: Font = fc.get_font(fc.spec_from_node(shape))
	var dl: Control = shape.get_node_or_null("DisplayLabel")
	if dl:
		if dl.has_method("apply_font_from_meta"):
			dl.apply_font_from_meta()
		elif f:
			dl.add_theme_font_override("font", f)
		dl.queue_redraw()
	if f:
		var me: Control = shape.get_node_or_null("MultiLineEdit")
		if me == null: me = shape.get_node_or_null("LineEdit")
		if me == null: me = shape.get_node_or_null("TitleEdit")
		if me:
			me.add_theme_font_override("font", f)
		var vrt = shape.get_node_or_null("VectorRichText")
		if vrt:
			TextCore.apply_vrt_fonts(vrt, shape)
			vrt.add_theme_font_override("font", f)
			if prop == "font_weight":
				var fw: int = int(shape.get_meta("font_weight", 400))
				vrt.apply_bold_to_selection(fw >= 700)
			elif prop == "font_italic":
				vrt.apply_italic_to_selection(bool(value))
			vrt.queue_redraw()
	_refit_text_shape(shape)

## Aplica un paint {type, ...} al relleno de la figura.
##  · solid  → fill_color (y quita el degradado)
##  · linear/radial → fill_gradient + tipo + ángulo (VectorShape); Line2D usa
##    su `gradient` nativo.
func _write_fill_paint(shape, value) -> void:
	if not (value is Dictionary):
		return
	var kind := String(value.get("type", "solid"))
	if kind == "solid":
		var c: Color = value.get("color", Color.WHITE)
		if _is_text(shape):
			_write_text_color(shape, "font_color", c)
			return
		if shape is VectorShape and shape.has_gradient_fill():
			shape.clear_fill_gradient()
		elif shape is Line2D and shape.gradient is Gradient:
			shape.gradient = null
		if "fill_color" in shape: shape.fill_color = c
		elif shape is Polygon2D: shape.color = c
		elif shape is Line2D: shape.default_color = c
		if shape.has_method("queue_redraw"):
			shape.queue_redraw()
		return
	# degradado
	var g := Gradient.new()
	var stops_val = value.get("stops", [])
	if stops_val is Gradient:
		g = stops_val
	elif stops_val is Array and not stops_val.is_empty():
		var offsets: Array[float] = []
		var colors: Array[Color] = []
		for i in range(stops_val.size()):
			var s = stops_val[i]
			if s is Array and s.size() >= 2:
				offsets.append(float(s[0]))
				colors.append(s[1] if s[1] is Color else Color.WHITE)
			elif s is Dictionary:
				offsets.append(float(s.get("offset", 0.0)))
				colors.append(s.get("color", Color.WHITE) if s.get("color") is Color else Color.WHITE)
			elif s is Color:
				offsets.append(0.0 if stops_val.size() < 2 else float(i) / float(stops_val.size() - 1))
				colors.append(s)
		if offsets.size() >= 2:
			g.offsets = PackedFloat32Array(offsets)
			g.colors = PackedColorArray(colors)
	if shape is VectorShape:
		if kind == "radial":
			shape.fill_gradient_type = 1
		elif kind in ["conic", "angular", "sweep"]:
			shape.fill_gradient_type = 2
		elif kind == "diamond":
			shape.fill_gradient_type = 3
		elif kind in ["box", "square"]:
			shape.fill_gradient_type = 4
		elif kind == "spiral":
			shape.fill_gradient_type = 5
		elif kind in ["reflected", "reflexionado", "mirror"]:
			shape.fill_gradient_type = 6
		else:
			shape.fill_gradient_type = 0
		if value.has("p0") and value["p0"] is Vector2 and value["p0"] != Vector2(-1, -1):
			shape.fill_gradient_p0 = value["p0"]
		if value.has("p1") and value["p1"] is Vector2 and value["p1"] != Vector2(-1, -1):
			shape.fill_gradient_p1 = value["p1"]
		if value.has("angle"):
			shape._internal_point_update = true
			shape.fill_gradient_angle = float(value["angle"])
			shape._internal_point_update = false
		shape.fill_gradient = g
	elif shape is Line2D:
		shape.gradient = g
	elif shape is Polygon2D:
		shape.color = Color.WHITE
		shape.texture = _grad_tex_for(g)
	if shape.has_method("queue_redraw"):
		shape.queue_redraw()

func _grad_tex_for(g: Gradient) -> GradientTexture2D:
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 1
	return t

## Color de relleno / contorno de una figura de texto → override de tema del
## DisplayLabel + meta persistida.
func _write_text_color(shape, theme_key: String, value: Color) -> void:
	var meta_key := "text_color" if theme_key == "font_color" else "text_outline_color"
	shape.set_meta(meta_key, value)
	if theme_key == "font_outline_color":
		shape.set_meta("stroke_color", value)
	var dl := _text_label(shape)
	if dl:
		dl.add_theme_color_override(theme_key, value)
		if dl.has_method("apply_stroke_meta"):
			dl.apply_stroke_meta()
		else:
			dl.queue_redraw()
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		if theme_key == "font_color":
			vrt.set_text_color(value)
		else:
			var sw: float = float(shape.get_meta("stroke_width", 0.0))
			vrt.set_stroke_color(value)
			vrt.set_stroke_width(sw)
		vrt.queue_redraw()
	var ed: Control = shape.get_node_or_null("MultiLineEdit")
	if ed == null:
		ed = shape.get_node_or_null("TitleEdit")
	if ed and ed is TextEdit:
		if theme_key == "font_color":
			ed.add_theme_color_override("font_color", value)
		if ed.syntax_highlighter:
			ed.syntax_highlighter.clear_highlighting_cache()
		ed.queue_redraw()

func _write_text_outline_size(shape, v: float) -> void:
	shape.set_meta("text_outline", int(v))
	shape.set_meta("stroke_width", maxf(0.0, float(v)))
	var dl := _text_label(shape)
	if dl:
		dl.add_theme_constant_override("outline_size", int(v))
		if dl.has_method("apply_stroke_meta"):
			dl.apply_stroke_meta()
		else:
			dl.queue_redraw()
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		var sc: Color = shape.get_meta("stroke_color", Color.BLACK)
		vrt.set_stroke_color(sc)
		vrt.set_stroke_width(maxf(0.0, float(v)))
		vrt.queue_redraw()

## Contenido de una figura de texto → meta + DisplayLabel + editor inline.
func _write_text_content(shape, txt: String) -> void:
	if not _is_text(shape):
		return
	shape.set_meta("text", txt)
	var dl := _text_label(shape)
	if dl and "text" in dl:
		dl.text = txt
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		vrt.set_text(txt)
		vrt.queue_redraw()
	var me: Node = shape.get_node_or_null("MultiLineEdit")
	if me == null: me = shape.get_node_or_null("LineEdit")
	if me == null: me = shape.get_node_or_null("TitleEdit")
	if me and "text" in me:
		me.text = txt
	_refit_text_shape(shape)

## Alineación horizontal del texto: "left"|"center"|"right"|"fill".
func _write_text_align(shape, value) -> void:
	if not _is_text(shape):
		return
	var mode := String(value)
	shape.set_meta("text_align", mode)
	var dl := _text_label(shape)
	if dl and "horizontal_alignment" in dl:
		var ha: HorizontalAlignment = {
			"left": HORIZONTAL_ALIGNMENT_LEFT, "center": HORIZONTAL_ALIGNMENT_CENTER,
			"right": HORIZONTAL_ALIGNMENT_RIGHT, "fill": HORIZONTAL_ALIGNMENT_FILL,
		}.get(mode, HORIZONTAL_ALIGNMENT_LEFT)
		dl.horizontal_alignment = ha
		if dl is WorldTextLabel:
			dl._outline_dirty = true
			dl._polys_baked = false
			dl._refresh_local_rect()
		dl.queue_redraw()
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		vrt.set_paragraph_align(mode)
		vrt.queue_redraw()

## Alineación vertical del texto: "top"|"middle"|"bottom".
func _write_text_valign(shape, value) -> void:
	if not _is_text(shape):
		return
	var mode := String(value)
	shape.set_meta("text_valign", mode)
	var dl := _text_label(shape)
	if dl and "vertical_alignment" in dl:
		var va: VerticalAlignment = {
			"top": VERTICAL_ALIGNMENT_TOP, "middle": VERTICAL_ALIGNMENT_CENTER,
			"bottom": VERTICAL_ALIGNMENT_BOTTOM,
		}.get(mode, VERTICAL_ALIGNMENT_TOP)
		dl.vertical_alignment = va
		if dl is WorldTextLabel:
			dl._outline_dirty = true
			dl._polys_baked = false
			dl._refresh_local_rect()
		dl.queue_redraw()

## Interlineado de una figura de texto: meta + constante de tema en la etiqueta
## de display (Label soporta la constante "line_spacing").
func _write_line_spacing(shape, value) -> void:
	if not _is_text(shape):
		return
	var ls := int(clampf(float(value), -100.0, 400.0))
	shape.set_meta("line_spacing", ls)
	var dl: Control = shape.get_node_or_null("DisplayLabel")
	if dl and dl is Label:
		dl.add_theme_constant_override("line_spacing", ls)
		# El overlay vectorial (zoom alto / runs / trazo) cachea la geometría.
		if dl.has_method("invalidate_layout"):
			dl.invalidate_layout()
		dl.queue_redraw()
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		vrt.set_paragraph_line_spacing(float(ls))
		vrt.queue_redraw()
	var me: Control = shape.get_node_or_null("MultiLineEdit")
	if me and me is TextEdit:
		me.add_theme_constant_override("line_spacing", ls)
		me.queue_redraw()
	_refit_text_shape(shape)

## Tamaño de fuente de una figura de texto: meta + etiqueta de display
## (WorldTextLabel.world_font_size o theme override) + editor inline.
func _write_font_size(shape, value) -> void:
	if not _is_text(shape):
		return
	var fs := int(clampf(float(value), 4.0, 400.0))
	shape.set_meta("font_size", fs)
	var dl: Control = shape.get_node_or_null("DisplayLabel")
	if dl:
		if "world_font_size" in dl:
			dl.world_font_size = fs
		else:
			dl.add_theme_font_size_override("font_size", fs)
		dl.queue_redraw()
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		vrt.set_font_size(float(fs))
		vrt.queue_redraw()
	var me: Control = shape.get_node_or_null("MultiLineEdit")
	if me == null: me = shape.get_node_or_null("LineEdit")
	if me == null: me = shape.get_node_or_null("TitleEdit")
	if me:
		me.add_theme_font_size_override("font_size", fs)
		if me.has_method("queue_redraw"):
			me.queue_redraw()
	_refit_text_shape(shape)

func _write_letter_proportions(shape, value) -> void:
	if not _is_text(shape):
		return
	if value == null or (value is Dictionary and value.is_empty()):
		if shape.has_meta("letter_proportions"):
			shape.remove_meta("letter_proportions")
	elif value is Dictionary:
		shape.set_meta("letter_proportions", value)
	var dl: Control = shape.get_node_or_null("DisplayLabel")
	if dl:
		if dl.has_method("set_letter_proportions"):
			dl.set_letter_proportions(value if value is Dictionary else {})
		elif dl.has_method("queue_redraw"):
			dl.queue_redraw()

## Sangrías Publisher (unidades de mundo): left/right 0..500,
## first -500..500 (negativa = francesa). Meta + re-bake del overlay.
func _write_indent(shape, prop: String, value) -> void:
	if not _is_text(shape):
		return
	var v := float(value)
	if prop == "indent_first":
		v = clampf(v, -500.0, 500.0)
	else:
		v = clampf(v, 0.0, 500.0)
	shape.set_meta(prop, v)
	var dl: Control = shape.get_node_or_null("DisplayLabel")
	if dl:
		if dl.has_method("apply_indent_meta"):
			dl.apply_indent_meta()
		elif dl.has_method("queue_redraw"):
			dl.queue_redraw()
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		var il = float(shape.get_meta("indent_left", 0.0))
		var ir = float(shape.get_meta("indent_right", 0.0))
		var fi = float(shape.get_meta("indent_first", 0.0))
		vrt.set_paragraph_indents(il, ir, fi)
		vrt.queue_redraw()
	var me: Control = shape.get_node_or_null("MultiLineEdit")
	if me and me is TextEdit:
		var sb := me.get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			if prop == "indent_left":
				sb.content_margin_left = v
			elif prop == "indent_right":
				sb.content_margin_right = v
			me.queue_redraw()
	_refit_text_shape(shape)

func _write_columns(shape: Node2D, prop: String, value: Variant) -> void:
	if not _is_text(shape):
		return
	if prop == "columns":
		shape.set_meta("columns", clampi(int(value), 1, 16))
	elif prop == "column_gap":
		shape.set_meta("column_gap", maxf(0.0, float(value)))
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		var cols = int(shape.get_meta("columns", 1))
		var gap = float(shape.get_meta("column_gap", 20.0))
		vrt.set_columns(cols, gap)
		vrt.queue_redraw()

func _refit_text_shape(shape: Node2D) -> void:
	if not is_instance_valid(shape) or not _is_text(shape):
		return
	var vrt = shape.get_node_or_null("VectorRichText")
	var dl: Control = shape.get_node_or_null("DisplayLabel")
	var me: Control = shape.get_node_or_null("MultiLineEdit")
	if me == null: me = shape.get_node_or_null("TitleEdit")
	var st := String(shape.get_meta("shape_type", ""))
	if st == "text_paragraph":
		var w := float(shape.get_meta("width", 350.0))
		var h := 100.0
		if vrt:
			vrt.set_frame_size(Vector2(w, 100000.0))
			var csz: Vector2 = vrt.get_content_size()
			h = maxf(40.0, csz.y)
			vrt.set_frame_size(Vector2(w, h))
			vrt.custom_minimum_size = Vector2(w, h)
			vrt.size = Vector2(w, h)
		elif dl is WorldTextLabel:
			h = maxf(40.0, dl.wrapped_content_height(str(shape.get_meta("text", ""))))
		shape.set_meta("height", h)
		if dl:
			dl.custom_minimum_size = Vector2(w, h)
			dl.size = Vector2(w, h)
		if me:
			me.custom_minimum_size = Vector2(w, h)
			me.size = Vector2(w, h)
	elif st == "text_title":
		var sz := Vector2(250.0, 40.0)
		if vrt:
			var csz: Vector2 = vrt.get_content_size()
			sz = Vector2(maxf(csz.x + 24.0, 120.0), maxf(csz.y + 6.0, 36.0))
			vrt.custom_minimum_size = sz
			vrt.size = sz
		elif dl is WorldTextLabel:
			var rsz = dl.get_world_minimum_size(str(shape.get_meta("text", "")))
			sz = Vector2(maxf(rsz.x + 24.0, 120.0), maxf(rsz.y + 6.0, 36.0))
		shape.set_meta("width", sz.x)
		shape.set_meta("height", sz.y)
		if dl:
			dl.custom_minimum_size = sz
			dl.size = sz
		if me:
			me.custom_minimum_size = sz
			me.size = sz

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
		else:
			var dl: Control = shape.get_node_or_null("DisplayLabel")
			var me: Control = shape.get_node_or_null("MultiLineEdit")
			if not me: me = shape.get_node_or_null("LineEdit")
			if not me: me = shape.get_node_or_null("TitleEdit")
			if dl:
				if dl is WorldTextLabel:
					dl.set_world_size(Vector2(w, h))
				else:
					dl.custom_minimum_size = Vector2(w, h)
					dl.size = Vector2(w, h)
			if me:
				me.custom_minimum_size = Vector2(w, h)
				me.size = Vector2(w, h)
			var vrt: Control = shape.get_node_or_null("VectorRichText")
			if vrt:
				vrt.set_frame_size(Vector2(w, h))
				vrt.custom_minimum_size = Vector2(w, h)
				vrt.size = Vector2(w, h)
		return
	if "artboard_size" in shape:
		var sz: Vector2 = shape.artboard_size
		if prop == "width": sz.x = v
		else: sz.y = v
		shape.artboard_size = sz
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
	# Figuras basadas en una lista de puntos locales: polígono (`vertices`),
	# Line2D (`points`), Polygon2D (`polygon`). Se escala la lista sobre el
	# centro de su caja local (misma idea que MoveTool al redimensionar por
	# vértices).
	var pts_field := ""
	for campo in ["vertices", "points", "polygon"]:
		if campo in shape:
			pts_field = campo
			break
	if pts_field != "":
		var verts: PackedVector2Array = shape.get(pts_field)
		if verts.is_empty():
			return
		var lb := _local_bounds(verts)
		var f := _extent_factor(lb.size, prop, v)
		var c := lb.get_center()
		var nv := PackedVector2Array()
		for p in verts:
			nv.append(c + (p - c) * f)
		if pts_field == "vertices" and shape is VectorShape and shape.has_doc_vertices():
			shape.set_doc_vertices(DVec2.array_from_v2(nv))
		else:
			shape.set(pts_field, nv)
		return

	# Trazo Bézier (Path2D): escala puntos y tiradores sobre el centro del
	# bounding box local de la curva horneada.
	if shape is Path2D and shape.curve:
		var cv: Curve2D = shape.curve
		if cv.point_count == 0:
			return
		var f := _extent_factor(_local_bounds(cv.get_baked_points()).size, prop, v)
		var c := _local_bounds(cv.get_baked_points()).get_center()
		for i in cv.point_count:
			cv.set_point_position(i, c + (cv.get_point_position(i) - c) * f)
			cv.set_point_in(i, cv.get_point_in(i) * f)
			cv.set_point_out(i, cv.get_point_out(i) * f)
		return

	if prop == "width" and "width" in shape:
		shape.set("width", v)
		return
	elif prop == "height" and "height" in shape:
		shape.set("height", v)
		return

	# Último recurso — Sprite2D (imagen): no tiene geometría propia, se escala el
	# nodo para alcanzar el ancho/alto pedido, medido en su caja global actual
	# (get_rect() + to_global ya es escala-consciente).
	# Los grupos Node2D quedan pendientes: _global_rect de una figura hija no
	# tiene en cuenta la escala del padre, así que el factor saldría mal.
	if shape is Sprite2D:
		var gb := _bounds(shape)
		var axis := gb.x if prop == "width" else gb.y
		if axis > 0.001:
			var factor := v / axis
			var sc: Vector2 = shape.scale
			shape.scale = (Vector2(sc.x * factor, sc.y) if prop == "width"
				else Vector2(sc.x, sc.y * factor))

## Factor de escala por eje: solo cambia el eje que se edita, el otro se mantiene.
func _extent_factor(current: Vector2, prop: String, v: float) -> Vector2:
	return Vector2(
		v / current.x if prop == "width" and current.x > 0.001 else 1.0,
		v / current.y if prop == "height" and current.y > 0.001 else 1.0)

func _local_bounds(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for i in range(1, pts.size()):
		r = r.expand(pts[i])
	return r

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
	if "full_rect" in lista or "full_size" in lista:
		_align_full_rect(ref)
		return
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

func _align_full_rect(ref: Rect2) -> void:
	var recs := []
	for s in _selection:
		if not is_instance_valid(s):
			continue
		var before_pos: Vector2 = s.global_position
		var before_size: Vector2 = Vector2.ZERO
		if "size" in s:
			before_size = s.size
		elif s is VectorShape and s.has_doc_extent():
			before_size = s.get_doc_extent().to_v2()
		var before_meta = s.get_meta("anchor_preset", "")
		var after_pos: Vector2 = ref.position
		var after_size: Vector2 = ref.size
		recs.append({
			"s": s,
			"before_pos": before_pos, "after_pos": after_pos,
			"before_size": before_size, "after_size": after_size,
			"before_meta": before_meta, "after_meta": "full_rect"
		})
	if recs.is_empty():
		return
	var apply_rec := func(r: Dictionary, is_after: bool) -> void:
		var s = r["s"]
		if not is_instance_valid(s):
			return
		var pos: Vector2 = r["after_pos"] if is_after else r["before_pos"]
		var sz: Vector2 = r["after_size"] if is_after else r["before_size"]
		var meta: String = r["after_meta"] if is_after else r["before_meta"]
		s.global_position = pos
		if meta != "":
			s.set_meta("anchor_preset", meta)
		elif s.has_meta("anchor_preset"):
			s.remove_meta("anchor_preset")
		if sz != Vector2.ZERO:
			_write_extent(s, "width", sz.x)
			_write_extent(s, "height", sz.y)
		_sync_doc(s)
	var do_fn := func() -> void:
		for r in recs:
			apply_rec.call(r, true)
		_post_write()
	var undo_fn := func() -> void:
		for r in recs:
			apply_rec.call(r, false)
		_post_write()
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Alinear Todo Tamaño")
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()


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
