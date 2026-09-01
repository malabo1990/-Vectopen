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
	"font_size", "line_spacing", "letter_spacing",
	"font_family", "font_weight", "font_italic",
	"fill_paint", "text_align", "text",
	"corner_tl", "corner_tr", "corner_br", "corner_bl",
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
	# `MoveTool.selected_shapes` es un espejo de `SelectionManager` (única fuente
	# de verdad) que MoveTool mantiene sincronizado — leerlo aquí ya refleja la
	# selección hecha desde el panel de capas. Si no hay MoveTool activo, se cae
	# a `SelectionManager` directamente.
	if _mt and "selected_shapes" in _mt:
		_selection = _mt.selected_shapes.filter(func(s): return is_instance_valid(s))
	else:
		var sm := get_node_or_null("/root/SelectionManager")
		_selection = sm.get_selected() if (sm and sm.has_method("get_selected")) else []
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
			if "size" in shape: return (shape.get("size") as Vector2).x
			if "width" in shape: return float(shape.get("width"))
			return _bounds(shape).x
		"height":
			if _is_text(shape): return float(shape.get_meta("height", 65.0))
			if "size" in shape: return (shape.get("size") as Vector2).y
			if "height" in shape: return float(shape.get("height"))
			return _bounds(shape).y
		"fill_color":
			if _is_text(shape): return _text_label_color(shape, "font_color", Color.BLACK)
			if "fill_color" in shape: return shape.fill_color
			if shape is Polygon2D: return shape.color
			return null
		"stroke_color":
			if _is_text(shape): return _text_label_color(shape, "font_outline_color", Color.BLACK)
			if "stroke_color" in shape: return shape.stroke_color
			if shape is Line2D: return shape.default_color
			return null
		"stroke_width":
			if _is_text(shape): return float(shape.get_meta("text_outline", 0))
			if "stroke_width" in shape: return shape.stroke_width
			if shape is Line2D: return shape.width
			return null
		"text_align":
			if _is_text(shape): return String(shape.get_meta("text_align", "left"))
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
		"font_family":
			if _is_text(shape): return String(shape.get_meta("font_family", "Inter"))
			return null
		"font_weight":
			if _is_text(shape): return int(shape.get_meta("font_weight", 400))
			return null
		"font_italic":
			if _is_text(shape): return bool(shape.get_meta("font_italic", false))
			return null
		"fill_paint":
			return _read_fill_paint(shape)
	return null

## Devuelve el relleno como {type:"solid"|"linear"|"radial", ...}. null si la
## figura no tiene concepto de relleno.
func _read_fill_paint(shape) -> Variant:
	if shape is VectorShape and shape.has_gradient_fill():
		var g: Gradient = shape.fill_gradient
		var stops: Array = []
		for i in g.get_point_count():
			stops.append([g.get_offset(i), g.get_color(i)])
		return {
			"type": "radial" if int(shape.fill_gradient_type) == 1 else "linear",
			"angle": float(shape.fill_gradient_angle),
			"stops": stops,
		}
	if shape is Line2D and shape.gradient is Gradient and shape.gradient.get_point_count() >= 2:
		var lg: Gradient = shape.gradient
		var ls: Array = []
		for i in lg.get_point_count():
			ls.append([lg.get_offset(i), lg.get_color(i)])
		return {"type": "linear", "angle": 0.0, "stops": ls}
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
			elif "stroke_width" in shape: shape.stroke_width = maxf(0.0, float(value))
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
		"text":
			_write_text_content(shape, String(value))
		"font_size":
			_write_font_size(shape, value)
		"line_spacing":
			_write_line_spacing(shape, value)
		"letter_spacing":
			if _is_text(shape):
				shape.set_meta("letter_spacing", int(value))
				var dl2 := _text_label(shape)
				if dl2 and dl2.has_method("apply_font_from_meta"):
					dl2.apply_font_from_meta()
		"font_family", "font_weight", "font_italic":
			_write_font_face(shape, prop, value)
	if shape.has_method("queue_redraw"):
		shape.queue_redraw()

## Familia / peso / itálica de una figura de texto: meta + fuente resuelta por
## FontCore aplicada al DisplayLabel (y al editor inline si existe).
func _write_font_face(shape, prop: String, value) -> void:
	if not _is_text(shape):
		return
	match prop:
		"font_family": shape.set_meta("font_family", String(value))
		"font_weight": shape.set_meta("font_weight", int(value))
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
		if me:
			me.add_theme_font_override("font", f)

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
		if shape is VectorShape and shape.has_gradient_fill():
			shape.clear_fill_gradient()
		elif shape is Line2D and shape.gradient is Gradient:
			shape.gradient = null
		if "fill_color" in shape: shape.fill_color = c
		elif shape is Polygon2D: shape.color = c
		elif shape is Line2D: shape.default_color = c
		return
	# degradado
	var g := Gradient.new()
	var stops: Array = value.get("stops", [[0.0, Color.BLACK], [1.0, Color.WHITE]])
	g.offsets = PackedFloat32Array(stops.map(func(s): return float(s[0])))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	if shape is VectorShape:
		shape.fill_gradient_type = 1 if kind == "radial" else 0
		shape.fill_gradient_angle = float(value.get("angle", 0.0))
		shape.fill_gradient = g
	elif shape is Line2D:
		shape.gradient = g
	elif shape is Polygon2D:
		shape.color = Color.WHITE
		shape.texture = _grad_tex_for(g)

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
	var dl := _text_label(shape)
	if dl:
		dl.add_theme_color_override(theme_key, value)
		dl.queue_redraw()

func _write_text_outline_size(shape, v: float) -> void:
	shape.set_meta("text_outline", int(v))
	var dl := _text_label(shape)
	if dl:
		dl.add_theme_constant_override("outline_size", int(v))
		dl.queue_redraw()

## Contenido de una figura de texto → meta + DisplayLabel + editor inline.
func _write_text_content(shape, txt: String) -> void:
	if not _is_text(shape):
		return
	shape.set_meta("text", txt)
	var dl := _text_label(shape)
	if dl and "text" in dl:
		dl.text = txt
	var me: Node = shape.get_node_or_null("MultiLineEdit")
	if me == null: me = shape.get_node_or_null("LineEdit")
	if me and "text" in me:
		me.text = txt

## Alineación horizontal del texto: "left"|"center"|"right"|"fill".
func _write_text_align(shape, value) -> void:
	if not _is_text(shape):
		return
	var mode := String(value)
	shape.set_meta("text_align", mode)
	var dl := _text_label(shape)
	if dl and "horizontal_alignment" in dl:
		dl.horizontal_alignment = {
			"left": HORIZONTAL_ALIGNMENT_LEFT, "center": HORIZONTAL_ALIGNMENT_CENTER,
			"right": HORIZONTAL_ALIGNMENT_RIGHT, "fill": HORIZONTAL_ALIGNMENT_FILL,
		}.get(mode, HORIZONTAL_ALIGNMENT_LEFT)
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
		dl.queue_redraw()

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
	var me: Control = shape.get_node_or_null("MultiLineEdit")
	if me == null: me = shape.get_node_or_null("LineEdit")
	if me:
		me.add_theme_font_size_override("font_size", fs)

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
