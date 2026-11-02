# =============================================================================
# VECTOPEN — SECCIÓN «PÁGINA» (sin selección) — UX-05
# RUTA: res://script_gdscript/ui/components/page_section.gd
#
# Pro no tenía panel de página (sin selección mostraba el color y la
# transformación de nada) y en Modern estaba roto: el color emitía una señal
# que nadie escuchaba y el tamaño era un texto fijo «1920 × 1080 px».
# Un ÚNICO componente para Modern y Pro, sobre la página ACTIVA:
#   · color de fondo (selector de Vectopen), con deshacer;
#   · ancho y alto reales, editables, con deshacer;
#   · girar (vertical ↔ horizontal) y «Tamaños…» (panel de UX-22).
# =============================================================================
class_name PageSection
extends VBoxContainer

const PRESETS_SCENE := "res://scenes/ui/panel_config_windows_element.tscn"

var swatch: ColorPickerButton
var field_w: NumericField
var field_h: NumericField
var btn_rotate: Button
var btn_sizes: Button
var _hex: Label
var _title: Label
var _guard := false
var _tick := 0
var _presets: Control = null
## Pro: se muestra solo sin selección (en Modern lo decide su Inspector).
var auto_hide := false
var show_title := true

func _init(p_auto_hide: bool = false, p_show_title: bool = true) -> void:
	name = "PageSection"
	auto_hide = p_auto_hide
	show_title = p_show_title

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_title = Label.new()
	_title.text = tr("PÁGINA")
	_title.add_theme_font_size_override("font_size", 10)
	_title.visible = show_title
	add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	swatch = ColorPickerButton.new()
	swatch.name = "PageColor"
	swatch.tooltip_text = tr("Color de la página")
	swatch.custom_minimum_size = Vector2(28, 24)
	swatch.focus_mode = Control.FOCUS_NONE
	swatch.color_changed.connect(_on_color)
	row.add_child(swatch)
	_hex = Label.new()
	_hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hex.add_theme_font_size_override("font_size", 11)
	row.add_child(_hex)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	add_child(row2)
	field_w = NumericField.new("W", " px", 1.0, 20000.0, 1.0)
	field_w.name = "PageW"
	field_w.decimals = 0
	field_w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_w.value_changed.connect(func(v: float) -> void: _set_page_size(Vector2(v, field_h.value)))
	row2.add_child(field_w)
	field_h = NumericField.new("H", " px", 1.0, 20000.0, 1.0)
	field_h.name = "PageH"
	field_h.decimals = 0
	field_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_h.value_changed.connect(func(v: float) -> void: _set_page_size(Vector2(field_w.value, v)))
	row2.add_child(field_h)
	btn_rotate = Button.new()
	btn_rotate.name = "PageRotate"
	btn_rotate.tooltip_text = tr("Girar la página (vertical ↔ horizontal)")
	btn_rotate.focus_mode = Control.FOCUS_NONE
	btn_rotate.custom_minimum_size = Vector2(28, 24)
	btn_rotate.pressed.connect(func() -> void:
		var ab := artboard()
		if ab:
			var s: Vector2 = ab.get("artboard_size")
			_set_page_size(Vector2(s.y, s.x)))
	row2.add_child(btn_rotate)
	btn_sizes = Button.new()
	btn_sizes.name = "PageSizes"
	btn_sizes.text = tr("Tamaños…")
	btn_sizes.tooltip_text = tr("Tamaños de página (papel, pantallas, redes sociales…)")
	btn_sizes.focus_mode = Control.FOCUS_NONE
	btn_sizes.add_theme_font_size_override("font_size", 11)
	btn_sizes.pressed.connect(_toggle_presets)
	add_child(btn_sizes)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _restyle())
	_restyle()
	refresh()

func _restyle() -> void:
	_title.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
	_hex.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
	btn_rotate.icon = ProUIStyle.icon("res://icon/UI/rotate-cw.svg", ProUIStyle.col("ICON_PRIMARY"), 14)

## Página activa (la del gestor de artboards del lienzo).
func artboard() -> Node2D:
	var cv = get_tree().get_first_node_in_group("_vectopen_canvas") if is_inside_tree() else null
	var m = cv.get_node_or_null("manager_script") if cv else null
	if m and m.has_method("get_active_artboard"):
		return m.get_active_artboard()
	return null

## Lee la página activa (color y tamaño reales).
func refresh() -> void:
	var ab := artboard()
	if ab == null:
		return
	_guard = true
	var c: Color = ab.get("fill_color")
	swatch.color = c
	_hex.text = "#" + c.to_html(false).to_upper()
	var s: Vector2 = ab.get("artboard_size")
	field_w.set_value_silent(s.x)
	field_h.set_value_silent(s.y)
	_guard = false

func _process(_d: float) -> void:
	# La página activa puede cambiar (otra página, deshacer): releer de vez en cuando.
	_tick += 1
	if _tick % 15 != 0:
		return
	if auto_hide:
		var ic := get_node_or_null("/root/InspectorCore")
		visible = ic != null and ic.has_method("selection") and (ic.selection() as Array).is_empty()
	if is_visible_in_tree():
		refresh()

func _on_color(c: Color) -> void:
	if _guard:
		return
	var ab := artboard()
	if ab == null:
		return
	var before: Color = ab.get("fill_color")
	if before.is_equal_approx(c):
		return
	_commit("Color de página", func() -> void: ab.set("fill_color", c), func() -> void: ab.set("fill_color", before))
	_hex.text = "#" + c.to_html(false).to_upper()

func _set_page_size(s: Vector2) -> void:
	if _guard:
		return
	var ab := artboard()
	if ab == null:
		return
	var before: Vector2 = ab.get("artboard_size")
	s = Vector2(maxf(1.0, roundf(s.x)), maxf(1.0, roundf(s.y)))
	if before.is_equal_approx(s):
		return
	_commit("Tamaño de página", func() -> void: ab.set("artboard_size", s), func() -> void: ab.set("artboard_size", before))
	refresh()

func _commit(action: String, do_fn: Callable, undo_fn: Callable) -> void:
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action(action)
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()

## «Tamaños…»: el panel de cuadrícula (UX-22), aplicado solo a la página.
func _toggle_presets() -> void:
	if not is_instance_valid(_presets):
		_presets = (load(PRESETS_SCENE) as PackedScene).instantiate()
		add_child(_presets)
		_presets.visible = false
		if "target_mode" in _presets:
			_presets.target_mode = 2   # solo página
		if _presets.has_signal("size_applied"):
			_presets.size_applied.connect(func(_w, _h, _n) -> void: refresh.call_deferred())
		if _presets.has_signal("closed"):
			_presets.closed.connect(func() -> void: _presets.visible = false)
	_presets.visible = not _presets.visible
	if _presets.visible:
		_presets.top_level = true
		_presets.z_index = 30
		var vp := get_viewport_rect()
		var sz: Vector2 = _presets.get_combined_minimum_size().max(_presets.size)
		var r := get_global_rect()
		var x := r.position.x - sz.x - 8.0
		if x < 28.0:
			x = r.end.x + 8.0
		x = clampf(x, 28.0, maxf(28.0, vp.size.x - sz.x - 8.0))
		var y := clampf(r.position.y, 28.0, maxf(28.0, vp.size.y - sz.y - 8.0))
		_presets.global_position = Vector2(x, y)
