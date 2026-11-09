# =============================================================================
# RUTA: res://script_gdscript/system/ui_scale.gd
# TAMAÑO DE LA INTERFAZ (toda la UI y sus letras), para monitores 4K y
# pantallas pequeñas. Lo instala GlobalUI al arrancar (nodo «UIScaleService»).
#
# · Automático: escala del sistema (Wayland/macOS), DPI y tamaño físico:
#   4K → 150–200 %; portátil pequeño (< 11–12") o poca resolución → 85–90 %.
# · El usuario elige en Ajustes ▸ Interfaz (80 %… 200 % o Automático) o con
#   Ctrl+Alt+= / Ctrl+Alt+- (Ctrl+Alt+0 = automático). Ctrl +/- solos siguen
#   siendo el zoom del lienzo.
# · Escala TODO a la vez (paneles, iconos y letras): muchos textos fijan su
#   tamaño a mano, así que un «tamaño de texto» aparte quedaría a medias.
# · Se guarda en user://ui_scale.cfg.
# =============================================================================
extends Node

signal changed(scale: float)

const CFG := "user://ui_scale.cfg"
const STEPS := [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
const MIN_SCALE := 0.75
const MAX_SCALE := 2.5

## 0 = automático; si no, la escala elegida.
var user_scale := 0.0
var _toast: Label = null
var _toast_timer: SceneTreeTimer = null

static func install(tree: SceneTree) -> Node:
	var existing := tree.root.get_node_or_null("UIScaleService")
	if existing:
		return existing
	var s = load("res://script_gdscript/system/ui_scale.gd").new()
	s.name = "UIScaleService"
	tree.root.add_child.call_deferred(s)
	return s

static func service(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("UIScaleService") if tree else null

func _ready() -> void:
	_load()
	apply()

## Escala automática para la pantalla donde está la ventana.
static func auto_scale() -> float:
	var scr := DisplayServer.window_get_current_screen()
	return scale_for(Vector2(DisplayServer.screen_get_size(scr)),
		float(DisplayServer.screen_get_dpi(scr)), DisplayServer.screen_get_scale(scr))

## Interfaz pensada para al menos 1280 × 720 puntos útiles.
const MIN_LOGICAL := Vector2(1280, 720)

## Escala para una pantalla de `px` píxeles, `dpi` y escala del sistema `sys`.
static func scale_for(px: Vector2, dpi: float, sys: float = 1.0) -> float:
	var s := 1.0
	if sys > 1.01:
		s = sys   # el sistema ya dice cuánto ampliar (Wayland / macOS)
	elif dpi >= 200.0 or px.x >= 3800.0:
		s = 2.0
	elif dpi >= 150.0 or px.x >= 3000.0:
		s = 1.5
	elif dpi >= 120.0 or px.x >= 2500.0:
		s = 1.25
	# Tabletas y móviles muy densos: ampliar lo que pida el DPI pero sin que
	# los paneles dejen de caber (antes la regla de «pantalla pequeña» de
	# abajo los dejaba al 85 %, ilegibles en una tableta de 440 ppp).
	var fit := minf(px.x / MIN_LOGICAL.x, px.y / MIN_LOGICAL.y)
	if s > fit:
		s = maxf(fit, 1.0)
	# Pantalla pequeña o con poca resolución útil (sin ampliar): algo más
	# compacta para que quepan los paneles (sin bajar de 85 %).
	if s <= 1.0:
		var diag_in := px.length() / maxf(dpi, 1.0)
		if px.x < 1400.0 or (diag_in > 1.0 and diag_in < 12.0):
			s = minf(s, 0.9 if px.x >= 1200.0 else 0.85)
	return clampf(floorf(s / 0.05 + 0.001) * 0.05, MIN_SCALE, MAX_SCALE)

func current_scale() -> float:
	# VECTOPEN_UI_SCALE fija la escala (pruebas, o forzarla desde fuera)
	if OS.has_environment("VECTOPEN_UI_SCALE"):
		return clampf(float(OS.get_environment("VECTOPEN_UI_SCALE")), MIN_SCALE, MAX_SCALE)
	return user_scale if user_scale > 0.0 else auto_scale()

func is_auto() -> bool:
	return user_scale <= 0.0

## Aplica la escala a toda la ventana.
func apply() -> void:
	get_tree().root.content_scale_factor = current_scale()
	changed.emit(current_scale())

func set_scale(s: float, show_toast := true) -> void:
	user_scale = 0.0 if s <= 0.0 else clampf(s, MIN_SCALE, MAX_SCALE)
	_save()
	apply()
	if show_toast:
		_show_toast()

## Siguiente / anterior tamaño de la lista (Ctrl+Alt+= / Ctrl+Alt+-).
func step(dir: int) -> void:
	var cur := current_scale()
	var target := cur
	if dir > 0:
		for v in STEPS:
			if v > cur + 0.01:
				target = v
				break
	else:
		for i in range(STEPS.size() - 1, -1, -1):
			if STEPS[i] < cur - 0.01:
				target = STEPS[i]
				break
	set_scale(target)

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if not (k.ctrl_pressed and k.alt_pressed) or k.shift_pressed:
		return
	match k.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			step(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			step(-1)
		KEY_0, KEY_KP_0:
			set_scale(0.0)
		_:
			return
	get_viewport().set_input_as_handled()

## Aviso discreto abajo en el centro: «Interfaz 125 %».
func _show_toast() -> void:
	if _toast == null:
		var layer := CanvasLayer.new()
		layer.layer = 125
		add_child(layer)
		_toast = Label.new()
		_toast.name = "UIScaleToast"
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.add_theme_font_size_override("font_size", 14)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.1, 0.12, 0.88)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		_toast.add_theme_stylebox_override("normal", sb)
		_toast.add_theme_color_override("font_color", Color(0.95, 0.95, 0.96))
		layer.add_child(_toast)
	var txt := tr("Interfaz %d %%") % int(round(current_scale() * 100.0))
	if is_auto():
		txt += " · " + tr("automático")
	_toast.text = txt
	_toast.visible = true
	_toast.reset_size()
	var vs := get_viewport().get_visible_rect().size
	_toast.position = Vector2((vs.x - _toast.size.x) / 2.0, vs.y - _toast.size.y - 48.0)
	_toast_timer = get_tree().create_timer(1.6)
	var my_timer := _toast_timer
	my_timer.timeout.connect(func() -> void:
		if my_timer == _toast_timer and is_instance_valid(_toast):
			_toast.visible = false)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		user_scale = float(cfg.get_value("ui", "scale", 0.0))

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "scale", user_scale)
	cfg.save(CFG)
