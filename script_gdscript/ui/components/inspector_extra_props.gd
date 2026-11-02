# =============================================================================
# VECTOPEN — PROPIEDADES QUE FALTABAN EN EL INSPECTOR (Modern y Pro)
# RUTA: res://script_gdscript/ui/components/inspector_extra_props.gd
#
# UX-06: el modelo (InspectorCore.PROPS) tenía propiedades sin control en el
# inspector de Modern o de Pro: nombre, visibilidad, radios de esquina,
# parámetros de polígono / estrella / elipse / gota, columnas de texto y los
# detalles del trazo (puntas, extremos, guiones, perfil). Este componente los
# muestra a partir de una tabla, para que modelo y panel no diverjan; cada
# host elige cuáles le faltan. Todo pasa por InspectorCore (con deshacer; al
# arrastrar un valor se ve en vivo y queda UN paso de deshacer).
# =============================================================================
extends VBoxContainer

const StrokePopover = preload("res://script_gdscript/ui/pro/stroke_popover.gd")

## prop: [etiqueta, tipo, min, max, paso, sufijo, escala]
## tipo: num | check | text | option | stroke (botones del desplegable de trazo)
const SPECS := {
	"name": ["Nombre", "text"],
	"opacity": ["Opacidad", "num", 0, 100, 1, "%", 100.0],
	"visible": ["Visible", "check"],
	"corner_radius": ["Redondeo", "num", 0, 5000, 0.5, " px", 1.0],
	"corner_tl": ["Esquina ↖", "num", 0, 5000, 0.5, " px", 1.0],
	"corner_tr": ["Esquina ↗", "num", 0, 5000, 0.5, " px", 1.0],
	"corner_br": ["Esquina ↘", "num", 0, 5000, 0.5, " px", 1.0],
	"corner_bl": ["Esquina ↙", "num", 0, 5000, 0.5, " px", 1.0],
	"sides": ["Lados", "num", 3, 64, 1, "", 1.0],
	"is_regular": ["Regular", "check"],
	"poly_angle": ["Giro", "num", -360, 360, 0.5, "°", 1.0],
	"poly_aspect": ["Proporción", "num", 5, 500, 1, "%", 100.0],
	"points_count": ["Puntas", "num", 3, 64, 1, "", 1.0],
	"inner_radius_ratio": ["Radio interior", "num", 1, 95, 1, "%", 100.0],
	"inner_corner_radius": ["Redondeo valles", "num", -1, 500, 0.5, " px", 1.0],
	"star_angle": ["Giro", "num", -360, 360, 0.5, "°", 1.0],
	"shape_mode": ["Forma", "option", [["whole", "Elipse completa"], ["donut", "Anillo"], ["pie", "Tarta / sector"], ["arc", "Arco abierto"], ["chord", "Cuerda"]]],
	"start_angle_deg": ["Ángulo inicio", "num", -360, 360, 1, "°", 1.0],
	"end_angle_deg": ["Ángulo fin", "num", -360, 360, 1, "°", 1.0],
	"drop_curvature": ["Curvatura", "num", 0, 100, 1, "%", 100.0],
	"text_align": ["Alineación", "option", [["left", "Izquierda"], ["center", "Centro"], ["right", "Derecha"], ["fill", "Justificado"]]],
	"text_valign": ["Vertical", "option", [["top", "Arriba"], ["middle", "Centro"], ["bottom", "Abajo"]]],
	"indent_left": ["Sangría izq.", "num", 0, 1000, 1, " px", 1.0],
	"indent_right": ["Sangría der.", "num", 0, 1000, 1, " px", 1.0],
	"indent_first": ["1.ª línea", "num", -1000, 1000, 1, " px", 1.0],
	"columns": ["Columnas", "num", 1, 12, 1, "", 1.0],
	"column_gap": ["Separación", "num", 0, 500, 1, " px", 1.0],
	"stroke_details": ["Trazo", "stroke"],
	"model_rotation_x": ["Giro X", "num", -360, 360, 1, "°", 1.0],
	"model_rotation_y": ["Giro Y", "num", -360, 360, 1, "°", 1.0],
	"model_rotation_z": ["Giro Z", "num", -360, 360, 1, "°", 1.0],
	"camera_distance": ["Distancia", "num", 0.2, 50, 0.1, "", 1.0],
	"camera_fov": ["Campo visión", "num", 10, 120, 1, "°", 1.0],
	"camera_ortho": ["Ortográfica", "check"],
	"light_preset": ["Luces", "presets"],
	"light_energy": ["Luz", "num", 0, 10, 0.1, "", 1.0],
	"light_rotation_x": ["Luz: altura", "num", -180, 180, 1, "°", 1.0],
	"light_rotation_y": ["Luz: giro", "num", -180, 180, 1, "°", 1.0],
	"light_color": ["Color de luz", "color"],
	"ambient_energy": ["Ambiente", "num", 0, 4, 0.1, "", 1.0],
	"model_shadows": ["Sombras", "check"],
}
const STROKE_MODES := [["start", "Inicio", "Punta y remate del inicio"], ["end", "Fin", "Punta y remate del final"],
	["style", "Estilo", "Sólido, discontinuo, punteado, doble; guion y hueco"], ["profile", "Perfil", "Perfil de grosor del trazo"]]

var props: Array = []
var _rows := {}        # prop -> HBoxContainer
var _ctrls := {}       # prop -> control
var _labels: Array[Label] = []
var _syncing := false
var _live_before := {}

static func create(prop_list: Array, node_name: String) -> Control:
	var c = load("res://script_gdscript/ui/components/inspector_extra_props.gd").new()
	c.props = prop_list
	c.name = node_name
	return c

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in props:
		if SPECS.has(p):
			_build_row(String(p))
	var ic := _ic()
	if ic and ic.has_signal("changed"):
		ic.changed.connect(_sync)
		_sync(ic.current_props())
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _apply_theme())
	_apply_theme()

func _ic() -> Node:
	return get_node_or_null("/root/InspectorCore")

func _build_row(prop: String) -> void:
	var spec: Array = SPECS[prop]
	var row := HBoxContainer.new()
	row.name = "Row_" + prop
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	_rows[prop] = row
	var lbl := Label.new()
	lbl.text = tr(String(spec[0]))
	lbl.custom_minimum_size.x = 92
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.clip_text = true
	row.add_child(lbl)
	_labels.append(lbl)
	match String(spec[1]):
		"num":
			var f := NumericField.new("", String(spec[5]), float(spec[2]), float(spec[3]), float(spec[4]))
			f.name = "Field_" + prop
			f.decimals = 0 if float(spec[4]) >= 1.0 else 1
			f.custom_minimum_size = Vector2(70, 24)
			f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			f.tooltip_text = tr(String(spec[0]))
			var sc: float = float(spec[6])
			f.drag_started.connect(func() -> void:
				var ic := _ic()
				if ic == null:
					return
				var before := {}
				for s in ic.selection():
					before[s] = ic._read(s, prop)
				_live_before[prop] = before)
			f.value_changed.connect(func(v: float) -> void:
				if _syncing:
					return
				var ic := _ic()
				if ic == null:
					return
				var val: Variant = _to_value(prop, v / sc)
				if _live_before.has(prop):
					for s in ic.selection():
						ic._write(s, prop, val)
					ic.post_write_live()
				else:
					ic.apply(prop, val))
			f.drag_ended.connect(func() -> void:
				var ic := _ic()
				if ic and _live_before.has(prop):
					ic.commit_live(prop, _live_before[prop])
				_live_before.erase(prop))
			row.add_child(f)
			_ctrls[prop] = f
		"check":
			var cb := CheckBox.new()
			cb.name = "Check_" + prop
			cb.focus_mode = Control.FOCUS_NONE
			cb.toggled.connect(func(on: bool) -> void:
				if not _syncing and _ic():
					_ic().apply(prop, on))
			row.add_child(cb)
			_ctrls[prop] = cb
		"text":
			var le := LineEdit.new()
			le.name = "Text_" + prop
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.custom_minimum_size = Vector2(70, 24)
			le.add_theme_font_size_override("font_size", 11)
			var commit := func(t: String) -> void:
				if not _syncing and _ic() and t.strip_edges() != "":
					_ic().apply(prop, t.strip_edges())
			le.text_submitted.connect(commit)
			le.focus_exited.connect(func() -> void: commit.call(le.text))
			row.add_child(le)
			_ctrls[prop] = le
		"option":
			var ob := OptionButton.new()
			ob.name = "Option_" + prop
			ob.focus_mode = Control.FOCUS_NONE
			ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ob.add_theme_font_size_override("font_size", 11)
			for it in spec[2]:
				ob.add_item(tr(String(it[1])))
				ob.set_item_metadata(ob.item_count - 1, it[0])
			ob.item_selected.connect(func(i: int) -> void:
				if not _syncing and _ic():
					_ic().apply(prop, ob.get_item_metadata(i)))
			row.add_child(ob)
			_ctrls[prop] = ob
		"presets":
			var ob := OptionButton.new()
			ob.name = "Option_" + prop
			ob.focus_mode = Control.FOCUS_NONE
			ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ob.add_theme_font_size_override("font_size", 11)
			for k in VectorModel3D.LIGHT_PRESETS.keys():
				ob.add_item(String(k))
				ob.set_item_metadata(ob.item_count - 1, String(k))
			ob.item_selected.connect(func(i: int) -> void:
				if not _syncing and _ic():
					_ic().apply(prop, ob.get_item_metadata(i)))
			row.add_child(ob)
			_ctrls[prop] = ob
		"color":
			var cp := ColorPickerButton.new()
			cp.name = "Color_" + prop
			cp.focus_mode = Control.FOCUS_NONE
			cp.custom_minimum_size = Vector2(40, 24)
			cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cp.color_changed.connect(func(col: Color) -> void:
				if not _syncing and _ic():
					_ic().apply(prop, col))
			row.add_child(cp)
			_ctrls[prop] = cp
		"stroke":
			for m in STROKE_MODES:
				var b := Button.new()
				b.name = "Stroke_" + String(m[0])
				b.text = tr(String(m[1]))
				b.tooltip_text = tr(String(m[2]))
				b.focus_mode = Control.FOCUS_NONE
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				b.add_theme_font_size_override("font_size", 11)
				b.pressed.connect(func() -> void: StrokePopover.toggle(self, String(m[0]), b))
				row.add_child(b)

func _to_value(prop: String, v: float) -> Variant:
	if prop in ["sides", "points_count", "columns"]:
		return int(roundf(v))
	return v

## Solo se ven las filas de propiedades que tiene la selección.
func _sync(cur: Dictionary) -> void:
	_syncing = true
	var any := false
	var mode := String(cur["shape_mode"]["value"]) if cur.has("shape_mode") else ""
	for prop in _rows:
		var show := cur.has(prop)
		if prop == "corner_radius":
			show = show and not cur.has("corner_tl")   # el rectángulo usa las 4 esquinas
		elif prop == "stroke_details":
			show = cur.has("stroke_cap_start") or cur.has("stroke_pointer_start")
		elif prop in ["start_angle_deg", "end_angle_deg"] and mode != "":
			show = show and mode in ["arc", "pie", "chord"]
		elif prop == "inner_radius_ratio" and mode != "":
			show = show and mode == "donut"
		_rows[prop].visible = show
		any = any or show
		if not show or not _ctrls.has(prop) or _live_before.has(prop):
			continue
		var v = cur[prop]["value"]
		var c = _ctrls[prop]
		if c is NumericField:
			if not c.get("_is_editing"):
				c.set_value_silent(float(v) * float(SPECS[prop][6]))
		elif c is ColorPickerButton:
			(c as ColorPickerButton).color = v
		elif c is CheckBox:
			(c as CheckBox).set_pressed_no_signal(bool(v))
		elif c is LineEdit:
			if not (c as LineEdit).has_focus():
				(c as LineEdit).text = str(v)
		elif c is OptionButton:
			var ob := c as OptionButton
			for i in ob.item_count:
				if str(ob.get_item_metadata(i)) == str(v):
					ob.select(i)
	visible = any
	_syncing = false

func _apply_theme() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var muted: Color = tm.get_color(S.TEXT_SECONDARY) if (tm and S) else Color(0.6, 0.6, 0.65)
	for l in _labels:
		if is_instance_valid(l):
			l.add_theme_color_override("font_color", muted)
