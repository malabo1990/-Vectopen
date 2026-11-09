extends BoxContainer
## Configuración ▸ Ventana: pensado para usarse SIN teclado (tableta):
##  · Tamaño de la interfaz: botones grandes − / + , la lista de tamaños y Auto.
##  · Modo de ventana: Ventana · Pantalla completa · Sin bordes (uno a elegir).
##  · Tamaño de ventana: tamaños listos y «Escritorio».
##  · Maximizar al iniciar (sí / no).
## Antes eran interruptores sueltos; varios («Escala de interfaz», «Tamaño de
## ventana», «Ancho × Alto»…) no hacían nada.

const CONFIG_PATH := "user://vectopen_window.cfg"
const UIScale = preload("res://script_gdscript/system/ui_scale.gd")
const TOUCH_H := 34.0
const MODES := [["windowed", "Ventana"], ["fullscreen", "Pantalla completa"], ["borderless", "Sin bordes"]]
const SIZES := [[Vector2i(1280, 720), "1280 × 720"], [Vector2i(1600, 900), "1600 × 900"], [Vector2i(1920, 1080), "1920 × 1080"], [Vector2i.ZERO, "Escritorio"]]

var _mode := "windowed"
var _maximize := false
var _size_idx := -1
var _scale_opt: OptionButton
var _mode_btns: Dictionary = {}
var _size_btns: Array = []
var _max_check: CheckButton

func _ready() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	add_theme_constant_override("separation", 8)
	_load_config()
	_build()
	_apply_loaded_mode()
	visibility_changed.connect(_restyle)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _restyle.call_deferred())

# ── construcción ─────────────────────────────────────────────────────────────
func _section(title: String) -> void:
	var l := Label.new()
	l.text = tr(title)
	l.name = "Sec_" + title.replace(" ", "_")
	add_child(l)

func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 4)
	add_child(r)
	return r

func _button(text: String, tip: String = "") -> Button:
	var b := Button.new()
	b.text = tr(text)
	b.tooltip_text = tr(tip)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(TOUCH_H, TOUCH_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

func _build() -> void:
	# Tamaño de la interfaz
	_section("Tamaño de la interfaz")
	var svc := UIScale.service(get_tree())
	var r := _row()
	var minus := _button("−", "Interfaz más pequeña")
	minus.name = "UIScaleMinus"
	minus.size_flags_horizontal = Control.SIZE_FILL
	minus.custom_minimum_size = Vector2(TOUCH_H * 1.4, TOUCH_H)
	minus.add_theme_font_size_override("font_size", 18)
	minus.pressed.connect(func() -> void:
		if svc:
			svc.step(-1))
	r.add_child(minus)
	_scale_opt = OptionButton.new()
	_scale_opt.name = "UIScaleList"
	_scale_opt.focus_mode = Control.FOCUS_NONE
	_scale_opt.custom_minimum_size = Vector2(0, TOUCH_H)
	_scale_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_opt.item_selected.connect(func(idx: int) -> void:
		if svc:
			svc.set_scale(0.0 if idx == 0 else float(UIScale.STEPS[idx - 1])))
	r.add_child(_scale_opt)
	var plus := _button("+", "Interfaz más grande")
	plus.name = "UIScalePlus"
	plus.size_flags_horizontal = Control.SIZE_FILL
	plus.custom_minimum_size = Vector2(TOUCH_H * 1.4, TOUCH_H)
	plus.add_theme_font_size_override("font_size", 18)
	plus.pressed.connect(func() -> void:
		if svc:
			svc.step(1))
	r.add_child(plus)
	var auto := _button("Auto", "Tamaño automático según la pantalla")
	auto.name = "UIScaleAuto"
	auto.size_flags_horizontal = Control.SIZE_FILL
	auto.custom_minimum_size = Vector2(TOUCH_H * 1.8, TOUCH_H)
	auto.pressed.connect(func() -> void:
		if svc:
			svc.set_scale(0.0))
	r.add_child(auto)
	_fill_scale_list()
	if svc and svc.has_signal("changed"):
		svc.changed.connect(func(_s: float) -> void: _fill_scale_list())
	add_child(HSeparator.new())

	# Modo de ventana
	_section("Modo de ventana")
	var rm := _row()
	for m in MODES:
		var b := _button(String(m[1]))
		b.name = "Mode_" + String(m[0])
		b.toggle_mode = true
		var key: String = m[0]
		b.pressed.connect(func() -> void: _pick_window_mode(key))
		rm.add_child(b)
		_mode_btns[key] = b

	# Tamaño de ventana
	_section("Tamaño de ventana")
	var rs := _row()
	for i in SIZES.size():
		var b := _button(String(SIZES[i][1]))
		b.name = "Size_%d" % i
		b.toggle_mode = true
		var idx := i
		b.pressed.connect(func() -> void: _pick_window_size(idx))
		rs.add_child(b)
		_size_btns.append(b)
	add_child(HSeparator.new())

	# Maximizar al iniciar
	var rx := _row()
	var lx := Label.new()
	lx.text = tr("Maximizar al iniciar")
	lx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rx.add_child(lx)
	_max_check = CheckButton.new()
	_max_check.name = "MaximizeOnStart"
	_max_check.focus_mode = Control.FOCUS_NONE
	_max_check.button_pressed = _maximize
	_max_check.toggled.connect(func(on: bool) -> void:
		_maximize = on
		ProjectSettings.set_setting("display/window/size/mode", 2 if on else 0)
		_save_config())
	rx.add_child(_max_check)
	_restyle()

func _fill_scale_list() -> void:
	if _scale_opt == null:
		return
	var svc := UIScale.service(get_tree())
	_scale_opt.clear()
	var auto_pct := int(round(svc.auto_scale() * 100.0)) if svc else 100
	_scale_opt.add_item(tr("Automático (%d %%)") % auto_pct, 0)
	for i in UIScale.STEPS.size():
		_scale_opt.add_item("%d %%" % int(round(float(UIScale.STEPS[i]) * 100.0)), i + 1)
	var sel := 0
	if svc and not svc.is_auto():
		for i in UIScale.STEPS.size():
			if absf(float(UIScale.STEPS[i]) - float(svc.user_scale)) < 0.01:
				sel = i + 1
	_scale_opt.select(sel)

## Estilo: el botón elegido de cada grupo se marca (como pestañas).
func _restyle() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null:
		return
	var S = tm.Slot
	var boxes := {
		"norm": _box(tm.get_color(S.BUTTON_BG), tm.get_color(S.BORDER)),
		"hov": _box(tm.get_color(S.BUTTON_HOVER), tm.get_color(S.BORDER)),
		"act": _box(tm.get_color(S.SURFACE_RAISED), tm.get_color(S.ACCENT), 2),
	}
	var text_col: Color = tm.get_color(S.PANEL_TEXT)
	var text_sec: Color = tm.get_color(S.TEXT_SECONDARY)
	for k in _mode_btns:
		_style_choice(_mode_btns[k], k == _mode, boxes, text_col, text_sec)
	for i in _size_btns.size():
		_style_choice(_size_btns[i], i == _size_idx, boxes, text_col, text_sec)
	for n in ["UIScaleMinus", "UIScalePlus", "UIScaleAuto"]:
		var b := find_child(n, true, false) as Button
		if b:
			_style_choice(b, false, boxes, text_col, text_col)
			b.add_theme_font_size_override("font_size", 16 if n != "UIScaleAuto" else 12)
	if _scale_opt:
		_scale_opt.add_theme_font_size_override("font_size", 12)

func _box(bg: Color, border: Color, bw: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	return sb

## Opción de un grupo (como las pestañas de arriba): la elegida con borde de
## acento y texto principal; las demás, texto secundario.
func _style_choice(b: Button, on: bool, boxes: Dictionary, text_col: Color, text_sec: Color) -> void:
	b.set_pressed_no_signal(on)
	b.add_theme_stylebox_override("normal", boxes["act"] if on else boxes["norm"])
	b.add_theme_stylebox_override("hover", boxes["act"] if on else boxes["hov"])
	b.add_theme_stylebox_override("pressed", boxes["act"])
	b.add_theme_stylebox_override("hover_pressed", boxes["act"])
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, text_col if (on or c != "font_color") else text_sec)
	b.add_theme_font_size_override("font_size", 12)

# ── acciones ─────────────────────────────────────────────────────────────────
func _pick_window_mode(key: String) -> void:
	_mode = key
	match key:
		"fullscreen": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"borderless": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_restyle()
	_save_config()

func _pick_window_size(idx: int) -> void:
	_size_idx = idx
	_mode = "windowed"
	var sz: Vector2i = SIZES[idx][0]
	var screen := DisplayServer.window_get_current_screen()
	var rect := DisplayServer.screen_get_usable_rect(screen)
	if sz == Vector2i.ZERO:
		sz = rect.size
	sz = Vector2i(mini(sz.x, rect.size.x), mini(sz.y, rect.size.y))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(sz)
	DisplayServer.window_set_position(rect.position + (rect.size - sz) / 2)
	_restyle()
	_save_config()

# ── guardar / cargar ─────────────────────────────────────────────────────────
func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	_maximize = bool(cfg.get_value("window", "maximize", false))
	if bool(cfg.get_value("window", "fullscreen", false)):
		_mode = "fullscreen"
	elif bool(cfg.get_value("window", "borderless", false)):
		_mode = "borderless"
	else:
		_mode = "windowed"
	_size_idx = int(cfg.get_value("window", "size_preset", -1))

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("window", "maximize", _maximize)
	cfg.set_value("window", "windowed", _mode == "windowed")
	cfg.set_value("window", "fullscreen", _mode == "fullscreen")
	cfg.set_value("window", "borderless", _mode == "borderless")
	cfg.set_value("window", "size_preset", _size_idx)
	cfg.save(CONFIG_PATH)

func _apply_loaded_mode() -> void:
	match _mode:
		"fullscreen": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"borderless": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
