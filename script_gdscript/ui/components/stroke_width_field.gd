# =============================================================================
# RUTA: res://script_gdscript/ui/components/stroke_width_field.gd
# Campo de GROSOR DE TRAZO al estilo Affinity (USR-39), común a los modos:
#   · arrastrar el número (horizontal o vertical) cambia el grosor EN VIVO y
#     al soltar queda UN solo paso de deshacer (antes, en Pro, uno por píxel);
#     Mayús / Ctrl = rápido, Alt = fino; clic = escribir (admite «2pt», «0,5 mm»…);
#   · menú ▾ con grosores predefinidos y la UNIDAD (px, pt, mm) en que se
#     muestra; el documento sigue guardando px (96 ppp).
# Habla con InspectorCore: no necesita manejadores en el panel que lo usa.
# La unidad se guarda en user://vectopen_files.cfg, sección "stroke".
# =============================================================================
extends HBoxContainer

const _NumField = preload("res://script_gdscript/ui/pro/pro_num_field.gd")
const PREFS_PATH := "user://vectopen_files.cfg"
const UNITS := {"px": 1.0, "pt": 0.75, "mm": 25.4 / 96.0}   # unidades por px
const PRESETS := [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0, 24.0]
const MAX_PX := 500.0

static var _unit := ""
static var _all: Array = []   # WeakRef de cada campo, para cambiar la unidad en todos

var num: Control = null
var menu_btn: MenuButton = null
var _before := {}
var _px := 1.0
var _skip_change := false

func _init(glyph: String = "≡") -> void:
	name = "StrokeWidthField"
	add_theme_constant_override("separation", 2)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	num = _NumField.new("", glyph, tr("Grosor del trazo: arrastra para ajustar (Mayús rápido, Alt fino) o escribe; ▾ grosores y unidad"))
	num.name = "WidthNum"
	num.min_value = 0.0
	num.max_value = MAX_PX * factor()
	num.step = 0.5
	num.adaptive_step = true   # hasta 0,005 (mucho zoom)
	num.suffix = unit()
	num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	num.value_changed.connect(_on_value_changed)
	num.scrub_changed.connect(_on_scrub)
	num.scrub_ended.connect(_on_scrub_end)
	num.unit_parser = parse_with_unit
	add_child(num)
	menu_btn = MenuButton.new()
	menu_btn.name = "WidthMenu"
	menu_btn.text = "▾"
	menu_btn.flat = true
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.custom_minimum_size = Vector2(18, 24)
	menu_btn.tooltip_text = tr("Grosores predefinidos y unidad")
	menu_btn.about_to_popup.connect(_fill_menu)
	menu_btn.get_popup().id_pressed.connect(_on_menu)
	add_child(menu_btn)
	_all.append(weakref(self))

# ── Unidad ───────────────────────────────────────────────────────────────────

static func unit() -> String:
	if _unit == "":
		var cfg := ConfigFile.new()
		_unit = "px"
		if cfg.load(PREFS_PATH) == OK:
			_unit = String(cfg.get_value("stroke", "unit", "px"))
		if not UNITS.has(_unit):
			_unit = "px"
	return _unit

static func factor() -> float:
	return float(UNITS[unit()])

static func set_unit(u: String) -> void:
	if not UNITS.has(u):
		return
	_unit = u
	var cfg := ConfigFile.new()
	cfg.load(PREFS_PATH)
	cfg.set_value("stroke", "unit", u)
	cfg.save(PREFS_PATH)
	for w in _all:
		var f = w.get_ref()
		if f != null:
			f._refresh_unit()
	_all = _all.filter(func(w) -> bool: return w.get_ref() != null)

func _refresh_unit() -> void:
	num.suffix = unit()
	num.max_value = MAX_PX * factor()
	if not num.is_mixed():
		num.set_value_no_signal(_px * factor())

## «2pt», «0.5mm», «3 px» → valor en la unidad que se muestra; null si no
## lleva unidad.
static func parse_with_unit(t: String) -> Variant:
	var s := t.strip_edges().to_lower().replace(",", ".")
	for u in UNITS:
		if s.ends_with(u):
			var n := s.trim_suffix(u).strip_edges()
			if n.is_valid_float():
				return n.to_float() / float(UNITS[u]) * factor()
	return null

# ── API para los paneles ─────────────────────────────────────────────────────

## Grosor en px (sin emitir nada).
func set_value_no_signal(px: float) -> void:
	_px = px
	num.set_value_no_signal(px * factor())

func set_mixed(mixed: bool, placeholder: String = "Mixto") -> void:
	num.set_mixed(mixed, placeholder)

func value_px() -> float:
	return _px

func apply_theme() -> void:
	if num.has_method("apply_theme"):
		num.apply_theme()

# ── Hacia InspectorCore ──────────────────────────────────────────────────────

func _ic() -> Node:
	return get_node_or_null("/root/InspectorCore") if is_inside_tree() else null

func _on_scrub(v: float) -> void:
	var ic := _ic()
	if ic == null or not ic.has_method("_write"):
		return
	_px = v / factor()
	if _before.is_empty():
		for s in ic.selection():
			var b = ic._read(s, "stroke_width")
			if b != null:
				_before[s] = b
	for s in _before:
		if is_instance_valid(s):
			ic._write(s, "stroke_width", _px)
	# Sin resincronizar TODOS los paneles en cada movimiento (con 500 trazos
	# seleccionados eran ~200 ms por fotograma): lo hacen al soltar.
	ic.post_write_live(false)

func _on_scrub_end(_v: float) -> void:
	var ic := _ic()
	if ic and not _before.is_empty():
		ic.commit_live("stroke_width", _before)
	_before = {}
	_skip_change = true   # el value_changed que sigue al soltar ya está guardado

func _on_value_changed(v: float) -> void:
	if _skip_change:
		_skip_change = false
		return
	_px = v / factor()
	var ic := _ic()
	if ic and ic.has_method("apply"):
		ic.apply("stroke_width", _px)

# ── Menú ▾ ───────────────────────────────────────────────────────────────────

func _fill_menu() -> void:
	var pm := menu_btn.get_popup()
	pm.clear()
	var u := unit()
	for i in PRESETS.size():
		var v: float = PRESETS[i]
		pm.add_item(("%s %s" % [String.num(v, 2).trim_suffix(".00"), u]).replace(".", ","), i)
	pm.add_separator(tr("Unidad"))
	var k := 0
	for name_u in UNITS:
		pm.add_radio_check_item(String(name_u), 100 + k)
		pm.set_item_checked(pm.get_item_index(100 + k), name_u == u)
		k += 1

func _on_menu(id: int) -> void:
	if id >= 100:
		set_unit(String(UNITS.keys()[id - 100]))
		return
	if id >= 0 and id < PRESETS.size():
		var disp: float = PRESETS[id]
		num.set_value_no_signal(disp)
		_px = disp / factor()
		var ic := _ic()
		if ic and ic.has_method("apply"):
			ic.apply("stroke_width", _px)

## Pruebas / atajos: elegir un preajuste por índice.
func pick_preset(i: int) -> void:
	_on_menu(i)
