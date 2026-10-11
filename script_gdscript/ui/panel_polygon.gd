# =============================================================================
# VECTOPEN — PANEL DE POLÍGONOS Y ESTRELLAS
# RUTA: res://script_gdscript/ui/panel_polygon.gd
#
# Cinco figuras paramétricas, cada una UNA sola cosa:
#   · Polígono: de 3 lados (triángulo) a "∞" (64+): cuadrado, rombo,
#     pentágono… son preajustes del MISMO polígono regular (lados, giro,
#     proporción, redondeo).
#   · Estrella: puntas, profundidad, redondeo de puntas y de valles, giro
#     (antes "estrella 4" y "estrella 5" eran dos botones).
#   · Rectángulo (radio o 4 esquinas), Elipse (anillo / tarta / arco), Gota.
#
# Edición EN VIVO sobre la selección: arrastrar un campo cambia la figura al
# momento y deja UN paso de deshacer al soltar (antes cada paso del
# deslizador era una entrada del historial y el panel se reconstruía entero
# con cada cambio, rompiendo el arrastre). La sincronización con la
# selección solo actualiza valores: nunca reconstruye los controles.
# =============================================================================
class_name PanelPolygon
extends PanelContainer

const NumField = preload("res://script_gdscript/ui/pro/pro_num_field.gd")
const CornerRound = preload("res://script_gdscript/shapes/corner_round.gd")

## Icono dibujado de una figura (contorno normalizado). Se pinta con el color
## del tema y queda nítido a cualquier escala; cada preajuste muestra SU
## geometría real (antes eran nombres de texto).
class ShapeIcon extends Control:
	var pts := PackedVector2Array()
	var color := Color.WHITE
	var fill_alpha := 0.18
	func _init(points: PackedVector2Array) -> void:
		pts = PanelPolygon._normalized(points)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
	func _draw() -> void:
		if pts.size() < 3:
			return
		var r := minf(size.x, size.y) * 0.36
		var c := size / 2.0
		var out := PackedVector2Array()
		for p in pts:
			out.append(c + p * r)
		if Geometry2D.triangulate_polygon(out).size() > 0:
			draw_colored_polygon(out, Color(color, fill_alpha))
		out.append(out[0])
		draw_polyline(out, color, 1.4, true)

signal shape_created(shape: Node)
signal closed

enum Kind { POLYGON, STAR, RECTANGLE, ELLIPSE, DROP }

## Contornos de los iconos de pestaña y preajustes.
static func _normalized(points: PackedVector2Array) -> PackedVector2Array:
	if points.is_empty():
		return points
	var bb := Rect2(points[0], Vector2.ZERO)
	for p in points:
		bb = bb.expand(p)
	var k := 2.0 / maxf(bb.size.x, bb.size.y)
	var out := PackedVector2Array()
	for p in points:
		out.append((p - bb.get_center()) * k)
	return out

static func poly_points(sides: int, angle_deg: float = 0.0, aspect: float = 1.0, round_px: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * i / sides - PI / 2.0 + deg_to_rad(angle_deg)
		pts.append(Vector2(cos(a) * aspect, sin(a)) * 40.0)
	return CornerRound.round(pts, PackedFloat32Array([round_px])) if round_px > 0.0 else pts

static func star_points(n: int, ratio: float, round_out: float = 0.0, round_in: float = -1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n * 2:
		var a := PI * i / n - PI / 2.0
		pts.append(Vector2(cos(a), sin(a)) * (40.0 if i % 2 == 0 else 40.0 * ratio))
	if round_out <= 0.0 and round_in <= 0.0:
		return pts
	return CornerRound.round(pts, _alt_radii(n, round_out, round_in if round_in >= 0.0 else round_out))

static func _alt_radii(n: int, a: float, b: float) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	for i in n * 2:
		r.append(a if i % 2 == 0 else b)
	return r

static func kind_icon(k: int) -> PackedVector2Array:
	match k:
		Kind.POLYGON: return poly_points(5)
		Kind.STAR: return star_points(5, 0.45)
		Kind.RECTANGLE: return CornerRound.round(PackedVector2Array([Vector2(-48, -34), Vector2(48, -34), Vector2(48, 34), Vector2(-48, 34)]), PackedFloat32Array([10.0]))
		Kind.ELLIPSE: return poly_points(48)
		Kind.DROP: return WaterDropTool.drop_points(40.0, 0.0, 0.5)
	return PackedVector2Array()

const KIND_INFO := {
	Kind.POLYGON: {"label": "Polígono", "tip": "Polígono regular: de 3 lados a ∞"},
	Kind.STAR: {"label": "Estrella", "tip": "Estrella: puntas, profundidad y redondeo"},
	Kind.RECTANGLE: {"label": "Rectángulo", "tip": "Rectángulo / cuadrado con esquinas redondeadas"},
	Kind.ELLIPSE: {"label": "Elipse", "tip": "Elipse, anillo, tarta o arco"},
	Kind.DROP: {"label": "Gota", "tip": "Gota / lágrima"},
}

## Preajustes de polígono: [nombre, lados, giro°, proporción]
const POLY_PRESETS := [
	["Triángulo", 3, 0.0, 1.0], ["Cuadrado", 4, 45.0, 1.0], ["Rombo", 4, 0.0, 0.7],
	["Pentágono", 5, 0.0, 1.0], ["Hexágono", 6, 0.0, 1.0], ["Octógono", 8, 22.5, 1.0],
	["Dodecágono", 12, 0.0, 1.0], ["∞", 64, 0.0, 1.0],
]
## Preajustes de estrella: [nombre, puntas, profundidad, redondeo puntas, redondeo valles]
const STAR_PRESETS := [
	["Clásica", 5, 0.382, 0.0, -1.0], ["4 puntas", 4, 0.3, 0.0, -1.0], ["6 puntas", 6, 0.5, 0.0, -1.0],
	["Redondeada", 5, 0.45, 8.0, -1.0], ["Flor", 8, 0.62, 30.0, 0.0], ["Explosión", 16, 0.7, 0.0, -1.0],
	["Sello", 24, 0.86, 2.0, -1.0], ["Brillo", 4, 0.18, 0.0, 6.0],
]

var kind: Kind = Kind.POLYGON
## Valores actuales (para crear figuras nuevas y mostrar).
var values := {
	"sides": 5, "corner_radius": 0.0, "poly_angle": 0.0, "poly_aspect": 1.0,
	"points_count": 5, "inner_radius_ratio": 0.382, "star_radius": 0.0, "inner_corner_radius": -1.0, "star_angle": 0.0,
	"rect_radius": 0.0, "independent": false, "corner_tl": 0.0, "corner_tr": 0.0, "corner_br": 0.0, "corner_bl": 0.0,
	"shape_mode": "whole", "ring_ratio": 0.5, "start_angle_deg": 0.0, "end_angle_deg": 360.0,
	"drop_curvature": 0.5,
}

## Valores del último panel abierto: las herramientas de dibujo (arrastrar
## en el lienzo) crean las figuras con ellos.
static var shared: Dictionary = {}

static func setting(key: String, def: Variant) -> Variant:
	return shared.get(key, def)

## Herramienta de dibujo de cada pestaña.
const KIND_TOOL := {Kind.POLYGON: "pentagon", Kind.STAR: "star", Kind.RECTANGLE: "rectangle",
	Kind.ELLIPSE: "ellipse", Kind.DROP: "waterdrop"}

var _title: Label = null
var _tabs: Dictionary = {}          # Kind -> Button
var _params: VBoxContainer = null
var _fields: Dictionary = {}        # clave de values -> control
var _status: Label = null
var _btn_create: Button = null
var _labels: Array[Label] = []
var _chips: Array[Button] = []
var _syncing := false
var _live_before: Dictionary = {}   # prop -> {figura: valor}

func _init() -> void:
	shared = values

func _ready() -> void:
	_build()
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed"):
		ic.changed.connect(_on_inspector_changed)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _apply_theme())
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_dock.call_deferred()
			_on_inspector_changed({}))
	resized.connect(_dock)
	_apply_theme()
	_on_inspector_changed({})

## Separado 10 px de la barra de herramientas: el ancho real depende del
## contenido, así que el borde derecho se recoloca cada vez que cambia.
const DOCK_GAP := 10.0

func _dock() -> void:
	# Regla común de la interfaz: 10 px del BORDE EXTERIOR del panel de capas,
	# a su izquierda (Smart) o a su derecha (Modern / Professional).
	var adaptive := get_tree().root.find_child("AdaptiveUIManager", true, false) if is_inside_tree() else null
	if adaptive and adaptive.has_method("_align_subpanel"):
		adaptive._align_subpanel(self)
		return
	var bar := get_parent().get_node_or_null("PanelContainer") as Control if get_parent() else null
	if bar == null or bar == self:
		return
	var x := bar.position.x - DOCK_GAP - size.x
	if not is_equal_approx(position.x, x):
		position.x = x

# ── construcción ─────────────────────────────────────────────────────────────
func _build() -> void:
	for c in get_children():
		c.queue_free()
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	_title = Label.new()
	_title.text = "POLÍGONOS Y ESTRELLAS"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 12)
	header.add_child(_title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	header.add_child(close)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	root.add_child(tabs)
	for k in KIND_INFO:
		var info: Dictionary = KIND_INFO[k]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = info["tip"]
		b.tooltip_text = "%s — %s" % [info["label"], info["tip"]]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 34)
		var ic := ShapeIcon.new(kind_icon(k))
		ic.name = "Icon"
		b.add_child(ic)
		b.pressed.connect(_on_tab.bind(k))
		tabs.add_child(b)
		_tabs[k] = b

	_params = VBoxContainer.new()
	_params.add_theme_constant_override("separation", 6)
	root.add_child(_params)

	root.add_child(HSeparator.new())
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 10)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(300, 0)
	root.add_child(_status)
	_btn_create = Button.new()
	_btn_create.text = "+ Crear en el centro"
	_btn_create.focus_mode = Control.FOCUS_NONE
	_btn_create.custom_minimum_size = Vector2(0, 28)
	_btn_create.pressed.connect(create_in_center)
	root.add_child(_btn_create)
	_build_params()

## Pestaña pulsada: cambia de figura y activa su herramienta de dibujo.
func _on_tab(k: Kind) -> void:
	set_kind(k)
	var ce = get_tree().get_first_node_in_group("_vectopen_canvas") if is_inside_tree() else null
	if ce and ce.has_method("switch_tool"):
		ce.switch_tool(String(KIND_TOOL[k]))

## Cambia de figura. Solo aquí (y al cambiar de tipo de selección) se
## reconstruyen los controles.
func set_kind(k: Kind) -> void:
	if k == kind and not _fields.is_empty():
		return
	_commit_live()
	kind = k
	_build_params()
	_apply_theme()
	_refresh_status()

func _build_params() -> void:
	for c in _params.get_children():
		_params.remove_child(c)
		c.queue_free()
	_fields.clear()
	_chips.clear()
	match kind:
		Kind.POLYGON:
			_presets(POLY_PRESETS, func(p: Array) -> PackedVector2Array:
				return poly_points(mini(int(p[1]), 48), float(p[2]), float(p[3])), func(p: Array) -> void:
				_apply_values({"sides": p[1], "poly_angle": p[2], "poly_aspect": p[3]}))
			_field("sides", "Lados", 3, 1000, 1, "", "▲")
			_field("corner_radius", "Redondeo", 0, 500, 0.5, "px", "◜")
			_field("poly_angle", "Giro", -360, 360, 0.5, "°", "↻")
			_field("poly_aspect", "Proporción", 5, 500, 1, "%", "↔", 100.0)
		Kind.STAR:
			_presets(STAR_PRESETS, func(p: Array) -> PackedVector2Array:
				return star_points(int(p[1]), float(p[2]), float(p[3]) * 0.5, float(p[4]) * 0.5 if float(p[4]) >= 0.0 else -1.0), func(p: Array) -> void:
				_apply_values({"points_count": p[1], "inner_radius_ratio": p[2], "star_radius": p[3], "inner_corner_radius": p[4]}))
			_field("points_count", "Puntas", 3, 500, 1, "", "✦")
			_field("inner_radius_ratio", "Profundidad", 5, 95, 1, "%", "◇", 100.0)
			_field("star_radius", "Redondeo puntas", 0, 500, 0.5, "px", "◜")
			_field("inner_corner_radius", "Redondeo valles", -1, 500, 0.5, "px", "◡")
			_field("star_angle", "Giro", -360, 360, 0.5, "°", "↻")
			_hint("Redondeo valles -1 = igual que las puntas")
		Kind.RECTANGLE:
			_field("rect_radius", "Redondeo", 0, 1000, 0.5, "px", "◜")
			var chk := CheckBox.new()
			chk.text = "Esquinas independientes"
			chk.focus_mode = Control.FOCUS_NONE
			chk.button_pressed = bool(values["independent"])
			chk.toggled.connect(func(on: bool) -> void:
				if _syncing:
					return
				values["independent"] = on
				_build_params()
				_apply_theme())
			_params.add_child(chk)
			_fields["independent"] = chk
			if bool(values["independent"]):
				for c in [["corner_tl", "Arriba izq."], ["corner_tr", "Arriba der."], ["corner_br", "Abajo der."], ["corner_bl", "Abajo izq."]]:
					_field(c[0], c[1], 0, 1000, 0.5, "px", "◜")
		Kind.ELLIPSE:
			var row := _row("Forma")
			var opt := OptionButton.new()
			for it in [["whole", "Elipse completa"], ["donut", "Anillo"], ["pie", "Tarta / sector"], ["arc", "Arco abierto"]]:
				opt.add_item(it[1])
				opt.set_item_metadata(opt.item_count - 1, it[0])
			opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			opt.item_selected.connect(func(i: int) -> void:
				if not _syncing:
					_apply_values({"shape_mode": String(opt.get_item_metadata(i))}))
			row.add_child(opt)
			_fields["shape_mode"] = opt
			_field("ring_ratio", "Hueco del anillo", 5, 95, 1, "%", "◎", 100.0)
			_field("start_angle_deg", "Ángulo inicio", -360, 360, 1, "°", "∠")
			_field("end_angle_deg", "Ángulo fin", -360, 360, 1, "°", "∠")
		Kind.DROP:
			_field("drop_curvature", "Curvatura", 0, 100, 1, "%", "◠", 100.0)
			_hint("0 % = lados rectos · 50 % = gota clásica · 100 % = muy redonda")
	_sync_fields()

func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_params.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(110, 0)
	l.add_theme_font_size_override("font_size", 11)
	_labels.append(l)
	row.add_child(l)
	return row

func _hint(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_font_size_override("font_size", 10)
	l.set_meta("hint", true)
	_labels.append(l)
	_params.add_child(l)

## Campo con arrastre (ProNumField): en vivo al arrastrar, un deshacer al
## soltar; escribir un número aplica con un deshacer. `scale` = factor de
## visualización (proporciones en %).
func _field(key: String, text: String, lo: float, hi: float, step: float, suffix: String, glyph: String, scale: float = 1.0) -> void:
	var row := _row(text)
	var f: Control = NumField.new("", glyph, text)
	f.min_value = lo
	f.max_value = hi
	f.step = step
	f.suffix = suffix
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.set_meta("scale", scale)
	f.scrub_changed.connect(func(v: float) -> void: _live(key, v / scale))
	f.scrub_ended.connect(func(_v: float) -> void: _commit_live())
	f.value_changed.connect(func(v: float) -> void:
		if not _syncing and _live_before.is_empty():
			_apply_values({key: v / scale}))
	row.add_child(f)
	_fields[key] = f

func _presets(list: Array, icon_of: Callable, apply: Callable) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	_params.add_child(flow)
	for p in list:
		var b := Button.new()
		b.tooltip_text = String(p[0])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(34, 34)
		var ic := ShapeIcon.new(icon_of.call(p))
		ic.name = "Icon"
		b.add_child(ic)
		b.pressed.connect(func() -> void: apply.call(p))
		flow.add_child(b)
		_chips.append(b)

# ── propiedades de la figura ─────────────────────────────────────────────────
## Clave del panel → propiedad de InspectorCore (en esta figura).
func _prop_of(key: String) -> String:
	match key:
		"star_radius", "rect_radius":
			return "corner_radius"
		"ring_ratio":
			return "inner_radius_ratio"
	return key

## Figuras de la selección que este panel edita según la pestaña.
func targets() -> Array:
	var ic := get_node_or_null("/root/InspectorCore")
	var sel: Array = ic.selection() if ic and ic.has_method("selection") else []
	var out: Array = []
	for s in sel:
		if is_instance_valid(s) and kind_of(s) == kind:
			out.append(s)
	return out

static func kind_of(s: Node) -> int:
	if s is VectorStar:
		return Kind.STAR
	if s is VectorRectangle:
		return Kind.RECTANGLE
	if s is VectorCircle:
		return Kind.ELLIPSE
	if s is VectorPolygon:
		return Kind.DROP if String(s.get_meta("shape_kind", "")) == "drop" else Kind.POLYGON
	return -1

## Aplica varios valores con UN paso de deshacer (y los guarda para crear).
func _apply_values(d: Dictionary) -> void:
	for k in d:
		values[k] = d[k]
	_sync_fields()
	var ts := targets()
	if ts.is_empty():
		_refresh_status()
		return
	var props := {}
	for k in d:
		props[_prop_of(k)] = d[k]
	var ic := get_node_or_null("/root/InspectorCore")
	_syncing = true
	if ic and ic.has_method("apply_multi"):
		ic.apply_multi(props, "Figura · %s" % String(KIND_INFO[kind]["label"]).to_lower())
	_syncing = false
	_refresh_status()

func _live(key: String, v: float) -> void:
	values[key] = v
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null or not ic.has_method("_write"):
		return
	var prop := _prop_of(key)
	if not _live_before.has(prop):
		var before := {}
		for s in targets():
			var b = ic._read(s, prop)
			if b != null:
				before[s] = b
		_live_before[prop] = before
	_syncing = true
	for s in (_live_before[prop] as Dictionary):
		if is_instance_valid(s):
			ic._write(s, prop, v)
	ic.post_write_live()
	_syncing = false

func _commit_live() -> void:
	if _live_before.is_empty():
		return
	var ic := get_node_or_null("/root/InspectorCore")
	var before := _live_before
	_live_before = {}
	if ic and ic.has_method("commit_live_multi"):
		_syncing = true
		ic.commit_live_multi(before, "Figura · %s" % String(KIND_INFO[kind]["label"]).to_lower())
		_syncing = false
	_refresh_status()

# ── sincronización con la selección ──────────────────────────────────────────
func _on_inspector_changed(_props: Dictionary = {}) -> void:
	if _syncing or not is_inside_tree() or not _live_before.is_empty():
		return
	var ic := get_node_or_null("/root/InspectorCore")
	var sel: Array = ic.selection() if ic and ic.has_method("selection") else []
	var first: Node = null
	for s in sel:
		if is_instance_valid(s) and kind_of(s) >= 0:
			first = s
			break
	if first:
		var k: int = kind_of(first)
		if k != kind:
			kind = k as Kind
			_build_params()
			_apply_theme()
		_read_from(first)
	_refresh_status()

func _read_from(s: Node) -> void:
	match kind:
		Kind.POLYGON:
			values["sides"] = int(s.sides) if s.is_regular else (s.base_vertices.size() if not s.base_vertices.is_empty() else int(s.sides))
			values["corner_radius"] = float(s.corner_radius)
			values["poly_angle"] = float(s.poly_angle)
			values["poly_aspect"] = float(s.poly_aspect)
		Kind.STAR:
			values["points_count"] = int(s.points_count)
			values["inner_radius_ratio"] = float(s.inner_radius_ratio)
			values["star_radius"] = float(s.corner_radius)
			values["inner_corner_radius"] = float(s.inner_corner_radius)
			values["star_angle"] = float(s.star_angle)
		Kind.RECTANGLE:
			var c: Vector4 = s.get_corner_radii()
			values["rect_radius"] = float(s.corner_radius)
			values["corner_tl"] = c.x
			values["corner_tr"] = c.y
			values["corner_br"] = c.z
			values["corner_bl"] = c.w
			var indep := not (is_equal_approx(c.x, c.y) and is_equal_approx(c.y, c.z) and is_equal_approx(c.z, c.w))
			if indep and not bool(values["independent"]):
				values["independent"] = true
				_build_params()
				_apply_theme()
		Kind.ELLIPSE:
			values["shape_mode"] = String(s.shape_mode)
			values["ring_ratio"] = float(s.inner_radius_ratio)
			values["start_angle_deg"] = float(s.start_angle_deg)
			values["end_angle_deg"] = float(s.end_angle_deg)
		Kind.DROP:
			values["drop_curvature"] = float(s.get_meta("drop_curvature", 0.5))
	_sync_fields()

## Pone los valores en los controles SIN emitir ni reconstruir.
func _sync_fields() -> void:
	_syncing = true
	for k in _fields:
		var f = _fields[k]
		if not is_instance_valid(f):
			continue
		if f is CheckBox:
			f.set_pressed_no_signal(bool(values[k]))
		elif f is OptionButton:
			for i in f.item_count:
				if String(f.get_item_metadata(i)) == String(values.get(k, "")):
					f.select(i)
		elif f.has_method("set_value_no_signal"):
			f.set_value_no_signal(float(values[k]) * float(f.get_meta("scale", 1.0)))
	_syncing = false
	for b in _tabs:
		_style_tab(_tabs[b], b == kind)

func _refresh_status() -> void:
	if not is_instance_valid(_status):
		return
	var n := targets().size()
	var label: String = String(KIND_INFO[kind]["label"]).to_lower()
	_status.text = ("Editando en vivo: %d %s%s" % [n, label, "s" if n != 1 else ""]) if n > 0 \
		else "Los cambios se aplican en vivo a las figuras de este tipo seleccionadas."

# ── crear ────────────────────────────────────────────────────────────────────
func create_in_center() -> Node:
	var artboard := _get_active_artboard()
	if artboard == null:
		return null
	var ab_size: Vector2 = artboard.artboard_size if "artboard_size" in artboard else Vector2(800, 600)
	var center := ab_size / 2.0
	var node: Node2D = null
	match kind:
		Kind.POLYGON:
			var p := VectorPolygon.new()
			var sides := int(values["sides"])
			p.name = NameUtils.unique_child_name(artboard, _poly_name(sides))
			p.set_doc_position(DVec2.from_v2(center))
			p.radius = 70.0
			p.poly_angle = float(values["poly_angle"])
			p.poly_aspect = float(values["poly_aspect"])
			p.corner_radius = float(values["corner_radius"])
			p.sides = sides
			p.is_regular = true
			node = p
		Kind.STAR:
			var st := VectorStar.new()
			st.name = NameUtils.unique_child_name(artboard, "Estrella")
			st.size = Vector2(140, 140)
			st.points_count = int(values["points_count"])
			st.inner_radius_ratio = float(values["inner_radius_ratio"])
			st.corner_radius = float(values["star_radius"])
			st.inner_corner_radius = float(values["inner_corner_radius"])
			st.star_angle = float(values["star_angle"])
			st.set_doc_position(DVec2.from_v2(center))
			node = st
		Kind.RECTANGLE:
			var r := VectorRectangle.new()
			r.name = NameUtils.unique_child_name(artboard, "Rectángulo")
			r.size = Vector2(140, 100)
			r.set_doc_position(DVec2.from_v2(center))
			r.corner_radius = float(values["rect_radius"])
			if bool(values["independent"]):
				r.set_corner_radii(Vector4(values["corner_tl"], values["corner_tr"], values["corner_br"], values["corner_bl"]))
			node = r
		Kind.ELLIPSE:
			var c := VectorCircle.new()
			c.name = NameUtils.unique_child_name(artboard, "Elipse")
			c.size = Vector2(140, 140)
			c.set_doc_position(DVec2.from_v2(center))
			c.shape_mode = String(values["shape_mode"])
			c.inner_radius_ratio = float(values["ring_ratio"])
			c.start_angle_deg = float(values["start_angle_deg"])
			c.end_angle_deg = float(values["end_angle_deg"])
			node = c
		Kind.DROP:
			var d := VectorPolygon.new()
			d.name = NameUtils.unique_child_name(artboard, "Gota")
			d.set_doc_position(DVec2.from_v2(center))
			d.set_meta("shape_kind", "drop")
			d.set_meta("drop_radius", 50.0)
			d.set_meta("drop_rotation", 0.0)
			d.set_meta("drop_curvature", float(values["drop_curvature"]))
			d.set_doc_vertices(DVec2.array_from_v2(WaterDropTool.drop_points(50.0, 0.0, float(values["drop_curvature"]))))
			node = d
	var dp := get_node_or_null("/root/DrawPreferences")
	if "fill_color" in node:
		node.fill_color = dp.fill_color if dp else Color(0.88, 0.88, 0.88)
		node.stroke_color = dp.stroke_color if dp else Color(0.1, 0.1, 0.1)
		node.stroke_width = float(dp.get("stroke_width")) if dp and dp.get("stroke_width") != null else 2.0
	artboard.add_child(node)
	node.owner = artboard
	shape_created.emit(node)
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("record_create"):
		hm.record_create(node)
	var sm := get_node_or_null("/root/SelectionManager")
	if sm and sm.has_method("set_selection"):
		sm.set_selection([node])
	return node

static func _poly_name(sides: int) -> String:
	match sides:
		3: return "Triángulo"
		4: return "Cuadrilátero"
		5: return "Pentágono"
		6: return "Hexágono"
		8: return "Octógono"
	return "Polígono %d" % sides

func _get_active_artboard() -> Node:
	var canvas = get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if canvas:
		var m = canvas.get_node_or_null("manager_script")
		if m and m.has_method("get_active_artboard"):
			return m.get_active_artboard()
	return null

# ── tema ─────────────────────────────────────────────────────────────────────
func _apply_theme() -> void:
	add_theme_stylebox_override("panel", ProUIStyle.flat(ProUIStyle.col("PANEL_SURFACE"), 10, ProUIStyle.col("BORDER"), 0, 0))
	if is_instance_valid(_title):
		_title.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
	for l in _labels:
		if is_instance_valid(l):
			l.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY") if l.has_meta("hint") else ProUIStyle.col("PANEL_TEXT"))
	if is_instance_valid(_status):
		_status.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
	for k in _tabs:
		_style_tab(_tabs[k], k == kind)
	for b in _chips:
		if is_instance_valid(b):
			b.add_theme_stylebox_override("normal", ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 4, ProUIStyle.col("INPUT_BORDER"), 6, 0))
			b.add_theme_stylebox_override("hover", ProUIStyle.flat(ProUIStyle.col("BUTTON_HOVER"), 4, ProUIStyle.col("BORDER_STRONG"), 6, 0))
			b.add_theme_stylebox_override("pressed", ProUIStyle.flat(ProUIStyle.col("BUTTON_PRESSED"), 4, ProUIStyle.col("ACCENT"), 6, 0))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			_tint(b, ProUIStyle.col("PANEL_TEXT"))
	for f in _fields.values():
		if not is_instance_valid(f):
			continue
		if f.has_method("apply_theme"):
			f.apply_theme()
		elif f is CheckBox:
			ProUIStyle.style_check(f)
			f.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
		elif f is OptionButton:
			ProUIStyle.style_option(f)
	if is_instance_valid(_btn_create):
		var acc := ProUIStyle.col("ACCENT")
		_btn_create.add_theme_stylebox_override("normal", ProUIStyle.flat(acc, 5, acc, 8, 0))
		_btn_create.add_theme_stylebox_override("hover", ProUIStyle.flat(acc.lightened(0.1), 5, acc, 8, 0))
		_btn_create.add_theme_stylebox_override("pressed", ProUIStyle.flat(acc.darkened(0.1), 5, acc, 8, 0))
		_btn_create.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_btn_create.add_theme_color_override("font_color", Color.WHITE)

func _style_tab(b: Button, on: bool) -> void:
	if not is_instance_valid(b):
		return
	var tm := get_node_or_null("/root/ThemeManager")
	var act: Color = tm.get_interactive_color() if tm and tm.has_method("get_interactive_color") else ProUIStyle.col("ACCENT")
	var sb := ProUIStyle.flat(ProUIStyle.col("SURFACE_RAISED") if on else ProUIStyle.col("BUTTON_BG"), 5,
		act if on else ProUIStyle.col("BORDER"), 6, 2)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_tint(b, act if on else ProUIStyle.col("TEXT_SECONDARY"))

func _tint(b: Button, c: Color) -> void:
	var ic := b.get_node_or_null("Icon") as ShapeIcon
	if ic:
		ic.color = c
		ic.queue_redraw()
