# =============================================================================
# RUTA: res://script_gdscript/ui/components/master_pages_section.gd
# Pestaña Páginas ▸ «PÁGINA MAESTRA» (informe §5): marcar la página activa
# como maestra y elegir la maestra que usa (o todas, con la casilla «Todas
# las páginas»). Con deshacer (master_pages.gd).
# =============================================================================
extends VBoxContainer

const MP = preload("res://script_gdscript/shapes/master_pages.gd")

var _title: Label
var chk_master: CheckBox
var opt_use: OptionButton
var chk_all: CheckBox
var _guard := false
var _tick := 0

func _init() -> void:
	name = "MasterPagesSection"

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_title = Label.new()
	_title.text = tr("PÁGINA MAESTRA")
	_title.add_theme_font_size_override("font_size", 10)
	add_child(_title)
	chk_master = CheckBox.new()
	chk_master.name = "IsMaster"
	chk_master.text = tr("Esta página es maestra")
	chk_master.tooltip_text = tr("Lo que pongas aquí (cabecera, pie, número de página…) aparece debajo de las páginas que la usen")
	chk_master.add_theme_font_size_override("font_size", 11)
	chk_master.toggled.connect(func(on: bool) -> void:
		if _guard: return
		var a := _active()
		if a: MP.set_is_master(a, on)
		refresh())
	add_child(chk_master)
	var row := HBoxContainer.new()
	add_child(row)
	var l := Label.new()
	l.text = tr("Usar maestra")
	l.add_theme_font_size_override("font_size", 11)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	opt_use = OptionButton.new()
	opt_use.name = "UseMaster"
	opt_use.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_use.item_selected.connect(func(i: int) -> void:
		if _guard: return
		MP.set_master(_targets(), String(opt_use.get_item_metadata(i)))
		refresh())
	row.add_child(opt_use)
	chk_all = CheckBox.new()
	chk_all.name = "MasterAllPages"
	chk_all.text = tr("Todas las páginas")
	chk_all.add_theme_font_size_override("font_size", 11)
	add_child(chk_all)
	_labels = [l]
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _restyle())
	_restyle()
	refresh()

var _labels: Array = []

## Colores del tema (claro / oscuro), como la sección Retícula. Antes el
## título salía blanco sobre fondo claro (ilegible en el tema claro).
func _restyle() -> void:
	_title.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
	for lb in _labels:
		(lb as Label).add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
	for cb in [chk_master, chk_all]:
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			(cb as CheckBox).add_theme_color_override(k, ProUIStyle.col("PANEL_TEXT"))

func _active() -> Node:
	var cv = get_tree().get_first_node_in_group("_vectopen_canvas") if is_inside_tree() else null
	var m = cv.get_node_or_null("manager_script") if cv else null
	return m.get_active_artboard() if m and m.has_method("get_active_artboard") else null

func _targets() -> Array:
	if chk_all.button_pressed:
		return MP.pages(get_tree()).filter(func(p) -> bool: return not MP.is_master(p))
	var a := _active()
	return [a] if a and not MP.is_master(a) else []

func refresh() -> void:
	if not is_inside_tree() or opt_use == null:
		return
	_guard = true
	var a := _active()
	chk_master.set_pressed_no_signal(a != null and MP.is_master(a))
	opt_use.clear()
	opt_use.add_item(tr("Ninguna"))
	opt_use.set_item_metadata(0, "")
	var cur := String(a.get_meta(MP.USE_META, "")) if a else ""
	for m in MP.masters(get_tree()):
		opt_use.add_item(String(m.name))
		opt_use.set_item_metadata(opt_use.item_count - 1, String(m.name))
		if String(m.name) == cur:
			opt_use.select(opt_use.item_count - 1)
	if cur == "":
		opt_use.select(0)
	opt_use.disabled = a == null or MP.is_master(a)
	_guard = false

func _process(_d: float) -> void:
	_tick += 1
	if _tick % 30 == 0 and is_visible_in_tree():
		refresh()
