# ==========================================
# RUTA: res://autoloads/ColorCore.gd
# AUTOLOAD (Singleton) — Sistema CORE de color y relleno ("paint").
# ==========================================
extends Node
## Capa central entre CUALQUIER selector de color / editor de degradado y la
## SELECCIÓN del canvas. Mismo papel para el relleno que InspectorCore para las
## propiedades y FontCore para la tipografía.
##
## Responsabilidades:
##  · Color activo de relleno / trazo + objetivo activo ("fill"/"stroke").
##  · Modelo de "paint" unificado: sólido | degradado lineal | degradado radial.
##  · Aplicar a la selección vía InspectorCore (undo, multiselección, mixed).
##  · Colores recientes + paleta guardada (persistidos en user://).
##  · Utilidades avanzadas: hex, armonías, tintes/sombras, contraste WCAG,
##    mezcla, cuentagotas (muestreo del viewport).

signal changed(fill: Color, stroke: Color, target: String)
signal paint_changed(paint: Dictionary)   # paint del objetivo activo
signal recents_changed()
signal palette_changed()

const _STATE_PATH := "user://color_state.cfg"
const _LEGACY_PALETTE := "user://vectopen_palette.cfg"
const MAX_RECENTS := 18

## paint.type: "solid" | "linear" | "radial"
enum { LINEAR, RADIAL }

var fill_color: Color = Color(0.2, 0.4, 0.9, 1.0)
var stroke_color: Color = Color(0.1, 0.1, 0.1, 1.0)
var active_target: String = "fill"

var _fill_paint: Dictionary = {"type": "solid", "color": fill_color}
var _stroke_paint: Dictionary = {"type": "solid", "color": stroke_color}
## Objetivo que eligió el usuario; el automático (líneas abiertas → trazo) no
## lo pisa: al seleccionar otra cosa se vuelve a él.
var _user_target: String = "fill"
var recents: Array[Color] = []
var palette: Array[Color] = []

var _sync_guard: bool = false
## Puesto mientras ColorCore aplica a la selección: rompe el ciclo
## ColorCore → InspectorCore.apply → object_style_changed → InspectorCore.changed
## → ColorCore._on_inspector_changed.
var _applying: bool = false
var _notifying: bool = false

func _ready() -> void:
	_load_state()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_on_inspector_changed):
		ic.changed.connect(_on_inspector_changed)

# ── objetivo activo ──────────────────────────────────────────────────────────
func set_target(t: String) -> void:
	if t == active_target or not (t in ["fill", "stroke"]):
		return
	active_target = t
	_user_target = t
	changed.emit(fill_color, stroke_color, active_target)
	paint_changed.emit(active_paint())

func active_color() -> Color:
	return fill_color if active_target == "fill" else stroke_color

func active_paint() -> Dictionary:
	if active_target == "fill":
		return _fill_paint.duplicate(true)
	return _stroke_paint.duplicate(true)

## Líneas abiertas (trazos Bézier / pluma sin cerrar) no tienen relleno que
## se vea: elegir un color o un degradado cambiaba ese relleno invisible y
## "el trazo no cogía color". Con solo líneas abiertas seleccionadas, el
## objetivo pasa solo a Trazo.
static func is_open_line(n: Node) -> bool:
	if n is Line2D:
		return false   # pincel/pluma Line2D: su color ES el cuerpo (relleno)
	if n is Path2D and "closed" in n:
		return not bool(n.closed)
	return false

func _auto_target(sel: Array) -> void:
	var all_open := not sel.is_empty()
	for n in sel:
		if not (is_instance_valid(n) and is_open_line(n)):
			all_open = false
			break
	var want := "stroke" if all_open else _user_target
	if want != active_target:
		active_target = want

# ── color sólido ─────────────────────────────────────────────────────────────
## Fija el color del objetivo activo, lo registra en recientes y lo aplica a la
## selección (o queda como color por defecto para figuras nuevas).
func set_color(c: Color, target: String = "") -> void:
	if _sync_guard or _notifying:
		return
	var tgt := target if target != "" else active_target
	if tgt == "fill":
		fill_color = c
		_fill_paint = {"type": "solid", "color": c}
	else:
		stroke_color = c
		_stroke_paint = {"type": "solid", "color": c}
	_add_recent(c)
	_apply_to_selection(tgt)
	# Mientras se avisa, un selector que reenvía el color no vuelve a entrar.
	_notifying = true
	changed.emit(fill_color, stroke_color, active_target)
	paint_changed.emit(active_paint())
	_notifying = false

## Fija un paint completo (sólido o degradado) sobre el relleno de la selección.
func set_paint(paint: Dictionary, target: String = "") -> void:
	if _sync_guard:
		return
	var tgt := target if target != "" else active_target
	if tgt != "fill":
		_set_stroke_paint(paint)
		return
	var new_paint := paint.duplicate(true)
	if new_paint.get("type", "solid") != "solid":
		if not new_paint.has("p0") and _fill_paint.has("p0") and _fill_paint["p0"] != Vector2(-1, -1):
			new_paint["p0"] = _fill_paint["p0"]
		if not new_paint.has("p1") and _fill_paint.has("p1") and _fill_paint["p1"] != Vector2(-1, -1):
			new_paint["p1"] = _fill_paint["p1"]
		if not new_paint.has("angle") and _fill_paint.has("angle"):
			new_paint["angle"] = _fill_paint["angle"]
	_fill_paint = new_paint
	if paint.get("type", "solid") == "solid":
		fill_color = paint.get("color", fill_color)
		_add_recent(fill_color)
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		_applying = true
		ic.apply("fill_paint", _fill_paint)
		_applying = false
	changed.emit(fill_color, stroke_color, active_target)
	paint_changed.emit(_fill_paint)

## Degradado (o color) en el trazo de la selección.
func _set_stroke_paint(paint: Dictionary) -> void:
	_stroke_paint = paint.duplicate(true)
	if paint.get("type", "solid") == "solid":
		stroke_color = paint.get("color", stroke_color)
		_add_recent(stroke_color)
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		_applying = true
		ic.apply("stroke_paint", _stroke_paint)
		_applying = false
	changed.emit(fill_color, stroke_color, active_target)
	paint_changed.emit(_stroke_paint)

func apply_color(c: Color) -> void:
	set_color(c)

func apply_fill(c: Color) -> void:
	set_color(c, "fill")

func apply_stroke(c: Color) -> void:
	set_color(c, "stroke")

## Sólido / lineal / radial sobre el objetivo activo (relleno o trazo).
func set_fill_mode(mode: String) -> void:
	var tgt := active_target
	var base: Color = fill_color if tgt == "fill" else stroke_color
	if mode == "solid":
		set_color(base, tgt)
	elif mode == "linear":
		var stops = [[0.0, base], [1.0, base.darkened(0.3) if base.get_luminance() > 0.25 else base.lightened(0.6)]]
		set_paint(make_linear(stops), tgt)
	elif mode == "radial":
		var stops = [[0.0, base], [1.0, base.darkened(0.3) if base.get_luminance() > 0.25 else base.lightened(0.6)]]
		set_paint(make_radial(stops), tgt)

func _apply_to_selection(tgt: String) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null or not ic.has_method("apply"):
		return
	_applying = true
	if tgt == "fill":
		ic.apply("fill_paint", _fill_paint)
		ic.apply("fill_color", fill_color)
	else:
		ic.apply("stroke_color", stroke_color)
	_applying = false

func _on_inspector_changed(props: Dictionary) -> void:
	if _applying or not (props is Dictionary):
		return
	_sync_guard = true
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("selection"):
		_auto_target(ic.selection())
	if props.has("stroke_paint") and not props["stroke_paint"]["mixed"] and props["stroke_paint"]["value"] is Dictionary:
		_stroke_paint = (props["stroke_paint"]["value"] as Dictionary).duplicate(true)
	elif props.has("stroke_color") and not props["stroke_color"]["mixed"]:
		_stroke_paint = {"type": "solid", "color": props["stroke_color"]["value"]}
	if props.has("fill_color") and not props["fill_color"]["mixed"]:
		fill_color = props["fill_color"]["value"]
	if props.has("stroke_color") and not props["stroke_color"]["mixed"]:
		stroke_color = props["stroke_color"]["value"]
	if props.has("fill_paint") and not props["fill_paint"]["mixed"]:
		_fill_paint = (props["fill_paint"]["value"] as Dictionary).duplicate(true)
		if _fill_paint.get("type", "solid") == "solid":
			fill_color = _fill_paint.get("color", fill_color)
	elif props.has("fill_color") and not props["fill_color"]["mixed"]:
		_fill_paint = {"type": "solid", "color": fill_color}
	_sync_guard = false
	changed.emit(fill_color, stroke_color, active_target)
	paint_changed.emit(active_paint())

# ── modelo de paint ──────────────────────────────────────────────────────────
func make_solid(c: Color) -> Dictionary:
	return {"type": "solid", "color": c}

func make_linear(stops, angle_rad: float = 0.0, p0: Vector2 = Vector2(-1, -1), p1: Vector2 = Vector2(-1, -1)) -> Dictionary:
	var d := {"type": "linear", "angle": angle_rad, "stops": _norm_stops(stops)}
	if p0 != Vector2(-1, -1): d["p0"] = p0
	if p1 != Vector2(-1, -1): d["p1"] = p1
	return d

func make_radial(stops, center := Vector2(0.5, 0.5), radius: float = 0.5, p0: Vector2 = Vector2(-1, -1), p1: Vector2 = Vector2(-1, -1)) -> Dictionary:
	var d := {"type": "radial", "center": center, "radius": radius, "stops": _norm_stops(stops)}
	if p0 != Vector2(-1, -1): d["p0"] = p0
	if p1 != Vector2(-1, -1): d["p1"] = p1
	return d

func make_conic(stops, center := Vector2(0.5, 0.5), angle_rad: float = 0.0, p0: Vector2 = Vector2(-1, -1), p1: Vector2 = Vector2(-1, -1)) -> Dictionary:
	var d := {"type": "conic", "center": center, "angle": angle_rad, "stops": _norm_stops(stops)}
	if p0 != Vector2(-1, -1): d["p0"] = p0
	if p1 != Vector2(-1, -1): d["p1"] = p1
	return d

func make_diamond(stops, center := Vector2(0.5, 0.5), angle_rad: float = 0.0, p0: Vector2 = Vector2(-1, -1), p1: Vector2 = Vector2(-1, -1)) -> Dictionary:
	var d := {"type": "diamond", "center": center, "angle": angle_rad, "stops": _norm_stops(stops)}
	if p0 != Vector2(-1, -1): d["p0"] = p0
	if p1 != Vector2(-1, -1): d["p1"] = p1
	return d

func make_box(stops, center := Vector2(0.5, 0.5), angle_rad: float = 0.0, p0: Vector2 = Vector2(-1, -1), p1: Vector2 = Vector2(-1, -1)) -> Dictionary:
	var d := {"type": "box", "center": center, "angle": angle_rad, "stops": _norm_stops(stops)}
	if p0 != Vector2(-1, -1): d["p0"] = p0
	if p1 != Vector2(-1, -1): d["p1"] = p1
	return d

func make_spiral(stops, center := Vector2(0.5, 0.5), angle_rad: float = 0.0, p0: Vector2 = Vector2(-1, -1), p1: Vector2 = Vector2(-1, -1)) -> Dictionary:
	var d := {"type": "spiral", "center": center, "angle": angle_rad, "stops": _norm_stops(stops)}
	if p0 != Vector2(-1, -1): d["p0"] = p0
	if p1 != Vector2(-1, -1): d["p1"] = p1
	return d

func make_reflected(stops, center := Vector2(0.5, 0.5), angle_rad: float = 0.0, p0: Vector2 = Vector2(-1, -1), p1: Vector2 = Vector2(-1, -1)) -> Dictionary:
	var d := {"type": "reflected", "center": center, "angle": angle_rad, "stops": _norm_stops(stops)}
	if p0 != Vector2(-1, -1): d["p0"] = p0
	if p1 != Vector2(-1, -1): d["p1"] = p1
	return d

var _clipboard_gradient_style: Dictionary = {}

func copy_gradient_style(shape: Node2D) -> void:
	if not is_instance_valid(shape) or not ("fill_gradient" in shape) or shape.fill_gradient == null:
		return
	_clipboard_gradient_style = {
		"type": shape.fill_gradient_type,
		"gradient": shape.fill_gradient.duplicate(),
		"angle": shape.fill_gradient_angle,
		"p0": shape.fill_gradient_p0,
		"p1": shape.fill_gradient_p1
	}

func paste_gradient_style(shape: Node2D) -> bool:
	if _clipboard_gradient_style.is_empty() or not is_instance_valid(shape) or not ("fill_gradient" in shape):
		return false
	shape.fill_gradient = (_clipboard_gradient_style["gradient"] as Gradient).duplicate()
	shape.fill_gradient_type = int(_clipboard_gradient_style["type"])
	shape.fill_gradient_p0 = _clipboard_gradient_style["p0"]
	shape.fill_gradient_p1 = _clipboard_gradient_style["p1"]
	shape._internal_point_update = true
	shape.fill_gradient_angle = float(_clipboard_gradient_style["angle"])
	shape._internal_point_update = false
	shape.queue_redraw()
	if GlobalEvents.has_signal("object_style_changed"):
		GlobalEvents.object_style_changed.emit()
	if GlobalEvents.has_signal("gradient_changed"):
		GlobalEvents.gradient_changed.emit(shape.fill_gradient)
	return true

## stops: Gradient | Array[[offset, Color]] | Array[Color] → [[offset, Color], ...]
func _norm_stops(stops) -> Array:
	var out: Array = []
	if stops is Gradient:
		for i in stops.get_point_count():
			out.append([stops.get_offset(i), stops.get_color(i)])
	elif stops is Array:
		for i in stops.size():
			var s = stops[i]
			if s is Array and s.size() >= 2:
				out.append([float(s[0]), s[1]])
			elif s is Color:
				var off := 0.0 if stops.size() < 2 else float(i) / float(stops.size() - 1)
				out.append([off, s])
	if out.is_empty():
		out = [[0.0, Color.BLACK], [1.0, Color.WHITE]]
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out

func gradient_from_paint(paint: Dictionary) -> Gradient:
	var g := Gradient.new()
	var stops: Array = paint.get("stops", [[0.0, Color.BLACK], [1.0, Color.WHITE]])
	g.offsets = PackedFloat32Array(stops.map(func(s): return s[0]))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	return g

func _paint_representative_color(paint: Dictionary) -> Color:
	if paint.get("type", "solid") == "solid":
		return paint.get("color", Color.WHITE)
	var stops: Array = paint.get("stops", [])
	return stops[0][1] if not stops.is_empty() else Color.WHITE

# ── utilidades avanzadas ─────────────────────────────────────────────────────
func hex(c: Color, with_alpha: bool = false) -> String:
	return "#" + c.to_html(with_alpha).to_upper()

func parse(s: String) -> Color:
	var t := s.strip_edges()
	if t == "":
		return active_color()
	return Color.from_string(t, active_color())

## mode: "complementary" | "analogous" | "triadic" | "tetradic" |
##       "split" | "monochromatic"
func harmony(c: Color, mode: String) -> Array[Color]:
	var h := c.h
	var s := c.s
	var v := c.v
	var out: Array[Color] = [c]
	match mode:
		"complementary":
			out.append(Color.from_hsv(fposmod(h + 0.5, 1.0), s, v, c.a))
		"analogous":
			out = [Color.from_hsv(fposmod(h - 1.0 / 12.0, 1.0), s, v, c.a), c,
				Color.from_hsv(fposmod(h + 1.0 / 12.0, 1.0), s, v, c.a)]
		"triadic":
			out.append(Color.from_hsv(fposmod(h + 1.0 / 3.0, 1.0), s, v, c.a))
			out.append(Color.from_hsv(fposmod(h + 2.0 / 3.0, 1.0), s, v, c.a))
		"tetradic":
			for k in [0.25, 0.5, 0.75]:
				out.append(Color.from_hsv(fposmod(h + k, 1.0), s, v, c.a))
		"split":
			out.append(Color.from_hsv(fposmod(h + 0.5 - 1.0 / 12.0, 1.0), s, v, c.a))
			out.append(Color.from_hsv(fposmod(h + 0.5 + 1.0 / 12.0, 1.0), s, v, c.a))
		"monochromatic":
			out = [Color.from_hsv(h, s, clampf(v * 0.55, 0, 1), c.a),
				Color.from_hsv(h, s, clampf(v * 0.78, 0, 1), c.a), c,
				Color.from_hsv(h, clampf(s * 0.6, 0, 1), clampf(v * 1.1, 0, 1), c.a),
				Color.from_hsv(h, clampf(s * 0.3, 0, 1), clampf(v * 1.2, 0, 1), c.a)]
	return out

func shades(c: Color, n: int = 5) -> Array[Color]:
	var out: Array[Color] = []
	for i in n:
		var t := float(i + 1) / float(n + 1)
		out.append(c.lerp(Color(0, 0, 0, c.a), t))
	return out

func tints(c: Color, n: int = 5) -> Array[Color]:
	var out: Array[Color] = []
	for i in n:
		var t := float(i + 1) / float(n + 1)
		out.append(c.lerp(Color(1, 1, 1, c.a), t))
	return out

func mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))

## Luminancia relativa (WCAG 2.1).
func luminance(c: Color) -> float:
	var f := func(x: float) -> float:
		return x / 12.92 if x <= 0.04045 else pow((x + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

## Ratio de contraste WCAG entre 1.0 y 21.0.
func contrast_ratio(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)

## Color de texto legible (negro o blanco) sobre `bg`.
func best_text_on(bg: Color) -> Color:
	return Color.BLACK if contrast_ratio(bg, Color.BLACK) >= contrast_ratio(bg, Color.WHITE) else Color.WHITE

## Composición alpha "over".
func blend(base: Color, over: Color) -> Color:
	var a := over.a + base.a * (1.0 - over.a)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	return Color(
		(over.r * over.a + base.r * base.a * (1.0 - over.a)) / a,
		(over.g * over.a + base.g * base.a * (1.0 - over.a)) / a,
		(over.b * over.a + base.b * base.a * (1.0 - over.a)) / a, a)

# ── cuentagotas ─────────────────────────────────────────────────────────────
## Muestrea el color del viewport en coordenadas de pantalla.
func sample_screen(viewport: Viewport, screen_pos: Vector2) -> Color:
	if viewport == null:
		return active_color()
	var tex := viewport.get_texture()
	if tex == null:
		return active_color()
	var img := tex.get_image()
	if img == null:
		return active_color()
	var p := Vector2i(clampi(int(screen_pos.x), 0, img.get_width() - 1),
		clampi(int(screen_pos.y), 0, img.get_height() - 1))
	return img.get_pixelv(p)

# ── recientes + paleta ──────────────────────────────────────────────────────
func _add_recent(c: Color) -> void:
	for i in range(recents.size() - 1, -1, -1):
		if recents[i].is_equal_approx(c):
			recents.remove_at(i)
	recents.push_front(c)
	while recents.size() > MAX_RECENTS:
		recents.pop_back()
	_save_state()
	recents_changed.emit()

func add_swatch(c: Color) -> void:
	for existing in palette:
		if existing.is_equal_approx(c):
			return
	palette.append(c)
	_save_state()
	palette_changed.emit()

func remove_swatch(index: int) -> void:
	if index >= 0 and index < palette.size():
		palette.remove_at(index)
		_save_state()
		palette_changed.emit()

func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_STATE_PATH) == OK:
		for c in cfg.get_value("color", "recents", []):
			if c is Color: recents.append(c)
		for c in cfg.get_value("color", "palette", []):
			if c is Color: palette.append(c)
	# migración best-effort de la paleta antigua
	if palette.is_empty():
		var old := ConfigFile.new()
		if old.load(_LEGACY_PALETTE) == OK:
			for c in old.get_value("palette", "colors", []):
				if c is Color: palette.append(c)

func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("color", "recents", recents)
	cfg.set_value("color", "palette", palette)
	cfg.save(_STATE_PATH)

## 9.3 Paleta del documento: colores utilizados actualmente en figuras del canvas
func get_document_palette() -> Array[Color]:
	var colors: Array[Color] = []
	var canvas := get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if not is_instance_valid(canvas):
		return colors

	var nodes_to_check: Array[Node] = [canvas]
	while not nodes_to_check.is_empty():
		var n: Node = nodes_to_check.pop_back()
		if is_instance_valid(n):
			for child in n.get_children():
				nodes_to_check.append(child)
			if n is Node2D and n.name != "Contorno_Stroke":
				if "fill_color" in n and n.fill_color is Color:
					_append_unique_color(colors, n.fill_color)
				elif n.has_meta("fill_color") and n.get_meta("fill_color") is Color:
					_append_unique_color(colors, n.get_meta("fill_color"))
				if "stroke_color" in n and n.stroke_color is Color:
					_append_unique_color(colors, n.stroke_color)
				elif n.has_meta("stroke_color") and n.get_meta("stroke_color") is Color:
					_append_unique_color(colors, n.get_meta("stroke_color"))
	return colors

func _append_unique_color(arr: Array[Color], c: Color) -> void:
	if c.a <= 0.001:
		return
	for existing in arr:
		if existing.is_equal_approx(c):
			return
	arr.append(c)

## 9.3 Exportación e Importación de paletas estándar (JSON y GPL)
func export_palette_json(path: String) -> bool:
	var list: Array[String] = []
	for c in palette:
		list.append(c.to_html(c.a < 1.0))
	var json_str := JSON.stringify(list, "  ")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(json_str)
		f.close()
		return true
	return false

func import_palette_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Array:
		for item in parsed:
			var c := Color.from_string(str(item), Color.BLACK)
			add_swatch(c)
		return true
	return false

func export_palette_gpl(path: String, palette_name: String = "Vectopen Palette") -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return false
	f.store_line("GIMP Palette")
	f.store_line("Name: " + palette_name)
	f.store_line("Columns: 8")
	f.store_line("#")
	for c in palette:
		var r := int(round(c.r * 255.0))
		var g := int(round(c.g * 255.0))
		var b := int(round(c.b * 255.0))
		f.store_line("%3d %3d %3d\t#%s" % [r, g, b, c.to_html(false).to_upper()])
	f.close()
	return true

func import_palette_gpl(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with("GIMP") or line.begins_with("Name:") or line.begins_with("Columns:"):
			continue
		var parts := line.split(" ", false)
		if parts.size() >= 3 and parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int():
			var r := float(parts[0].to_int()) / 255.0
			var g := float(parts[1].to_int()) / 255.0
			var b := float(parts[2].to_int()) / 255.0
			add_swatch(Color(r, g, b, 1.0))
	f.close()
	return true
