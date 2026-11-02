# =============================================================================
# VECTOPEN — RETÍCULA DE PÁGINA (márgenes, columnas, medianil, sangrado) VAL-06
# RUTA: res://script_gdscript/ui/components/page_layout_section.gd
#
# En la pestaña Páginas había «Sangrado» y «Márgenes» que no estaban conectados
# a nada. Ahora editan la retícula de la página activa (o de todas, como el
# «Configurar documento» de InDesign), con deshacer; las guías se dibujan en la
# página y no se imprimen ni se exportan. Medidas en milímetros (96 ppp).
# =============================================================================
class_name PageLayoutSection
extends VBoxContainer

const PX_PER_MM := 96.0 / 25.4

var f_margin: NumericField
var f_columns: NumericField
var f_gutter: NumericField
var f_bleed: NumericField
var chk_all: CheckBox
var _title: Label
var _labels: Array[Label] = []
var _guard := false
var _tick := 0

func _init() -> void:
	name = "PageLayoutSection"

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_title = Label.new()
	_title.text = tr("RETÍCULA")
	_title.add_theme_font_size_override("font_size", 10)
	add_child(_title)
	f_margin = _row(tr("Márgenes"), " mm", 0.0, 200.0, 1.0, "LayoutMargin")
	f_columns = _row(tr("Columnas"), "", 1.0, 24.0, 1.0, "LayoutColumns")
	f_columns.decimals = 0
	f_gutter = _row(tr("Medianil"), " mm", 0.0, 50.0, 0.5, "LayoutGutter")
	f_bleed = _row(tr("Sangrado"), " mm", 0.0, 50.0, 0.5, "LayoutBleed")
	chk_all = CheckBox.new()
	chk_all.name = "LayoutAllPages"
	chk_all.text = tr("Aplicar a todas las páginas")
	chk_all.button_pressed = true
	chk_all.focus_mode = Control.FOCUS_NONE
	chk_all.add_theme_font_size_override("font_size", 11)
	add_child(chk_all)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _restyle())
	_restyle()
	refresh()

func _row(text: String, suffix: String, mn: float, mx: float, step: float, nm: String) -> NumericField:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 11)
	row.add_child(l)
	_labels.append(l)
	var f := NumericField.new("", suffix, mn, mx, step)
	f.name = nm
	f.decimals = 1
	f.custom_minimum_size = Vector2(84, 24)
	f.value_changed.connect(func(_v: float) -> void: _apply())
	row.add_child(f)
	return f

func _restyle() -> void:
	_title.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
	for l in _labels:
		l.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		chk_all.add_theme_color_override(k, ProUIStyle.col("PANEL_TEXT"))

func _active() -> Node:
	var cv = get_tree().get_first_node_in_group("_vectopen_canvas") if is_inside_tree() else null
	var m = cv.get_node_or_null("manager_script") if cv else null
	return m.get_active_artboard() if m and m.has_method("get_active_artboard") else null

func _targets() -> Array:
	if chk_all.button_pressed:
		return get_tree().get_nodes_in_group("artboards").filter(func(a): return "layout_margin" in a)
	var a := _active()
	return [a] if a else []

func refresh() -> void:
	var a := _active()
	if a == null or not ("layout_margin" in a):
		return
	_guard = true
	f_margin.set_value_silent(a.layout_margin / PX_PER_MM)
	f_columns.set_value_silent(a.layout_columns)
	f_gutter.set_value_silent(a.layout_gutter / PX_PER_MM)
	f_bleed.set_value_silent(a.bleed / PX_PER_MM)
	_guard = false

func _process(_d: float) -> void:
	_tick += 1
	if _tick % 20 == 0 and is_visible_in_tree():
		refresh()

func _apply() -> void:
	if _guard:
		return
	var want := {"layout_margin": f_margin.value * PX_PER_MM, "layout_columns": int(f_columns.value),
		"layout_gutter": f_gutter.value * PX_PER_MM, "bleed": f_bleed.value * PX_PER_MM}
	var targets := _targets()
	var before: Array = []
	for a in targets:
		var b := {}
		for k in want:
			b[k] = a.get(k)
		before.append(b)
	var do_fn := func() -> void:
		for a in targets:
			if is_instance_valid(a):
				for k in want:
					a.set(k, want[k])
	var undo_fn := func() -> void:
		for i in targets.size():
			if is_instance_valid(targets[i]):
				for k in before[i]:
					targets[i].set(k, before[i][k])
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Retícula de página")
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()
