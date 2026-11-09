# =============================================================================
# RUTA: res://script_gdscript/ui/about_panel.gd
# Ventana del logo de Vectopen: qué es, versión (la real del proyecto),
# créditos, comunidad (GitHub, Telegram, Reddit) y actualizaciones (buscar,
# descargar e instalar, reiniciar). Mismo lenguaje visual que el panel de
# Capas; sigue el tema claro/oscuro.
# =============================================================================
class_name AboutPanel
extends PanelContainer

const SOCIAL := [
	["github", "GitHub", "res://icon/UI/github-circle.svg", "https://github.com/malabo1990/-Vectopen"],
	["telegram", "Telegram", "res://icon/UI/telegram-circle.svg", "https://t.me/vectopen"],
	["reddit", "Reddit", "res://icon/UI/reddit-circle.svg", "https://www.reddit.com/r/Vectopen_editor/"],
	["x", "X · @malabo_6", "res://icon/UI/x.svg", "https://x.com/malabo_6"],
]
const LOGO := "res://icon/logo/logo_vectopen.png"
## Donaciones: tiempo de desarrollo y Vectopen Web (en el navegador).
const SPONSOR_URL := "https://github.com/sponsors/malabo1990"

## Ventana flotante compartida (Modern / Pro) y los logos que la abren.
static var _floating: AboutPanel
static var _anchor: Control

var _title: Label
var _version: Label
var _desc: Label
var _sections: Array[Label] = []
var _keys: Array[Label] = []
var _vals: Array[Label] = []
var _social: Array[Button] = []
var _seps: Array[HSeparator] = []
var _upd_status: Label
var btn_check: Button
var btn_install: Button
var btn_restart: Button
var chk_auto: CheckBox
var progress: ProgressBar
## Punto de aviso sobre el logo cuando hay versión nueva.
var badge: Panel

func _init() -> void:
	name = "Panel"
	custom_minimum_size = Vector2(300, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	# Cabecera: logo, nombre y versión.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var logo := TextureRect.new()
	logo.texture = load(LOGO)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(34, 34)
	# Logo original (negro) sobre baldosa clara: se ve también en tema oscuro.
	var tile := PanelContainer.new()
	tile.name = "LogoTile"
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color("#f4f5f8")
	tsb.set_corner_radius_all(10)
	tsb.border_color = Color(0, 0, 0, 0.08)
	tsb.set_border_width_all(1)
	tsb.content_margin_left = 5
	tsb.content_margin_right = 5
	tsb.content_margin_top = 4
	tsb.content_margin_bottom = 4
	tile.add_theme_stylebox_override("panel", tsb)
	tile.add_child(logo)
	head.add_child(tile)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hv)
	_title = Label.new()
	_title.text = "Vectopen"
	_title.add_theme_font_size_override("font_size", 17)
	hv.add_child(_title)
	_version = Label.new()
	_version.name = "Version"
	_version.text = tr("Versión %s") % _current_version()
	_version.add_theme_font_size_override("font_size", 11)
	hv.add_child(_version)
	_desc = Label.new()
	_desc.text = tr("Editor vectorial libre y de código abierto, hecho con Godot. Vectopen es tuyo: mejóralo y crea con nosotros.")
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(276, 0)
	_desc.add_theme_font_size_override("font_size", 11)
	v.add_child(_desc)
	_sep(v)
	# Créditos.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for kv in [[tr("Fundador"), "Casimiro Ondo Obiang"], [tr("Desarrollo"), tr("¿Tú? ¡Únete!")], [tr("Licencia"), "MIT"]]:
		var k := Label.new()
		k.text = kv[0]
		k.add_theme_font_size_override("font_size", 11)
		grid.add_child(k)
		_keys.append(k)
		var val := Label.new()
		val.text = kv[1]
		val.add_theme_font_size_override("font_size", 11)
		grid.add_child(val)
		_vals.append(val)
	_sep(v)
	# Comunidad.
	_section(v, tr("COMUNIDAD"))
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	v.add_child(row)
	for s in SOCIAL:
		var b := Button.new()
		b.name = "Social_" + String(s[0])
		b.text = String(s[1])
		b.tooltip_text = String(s[3])
		b.set_meta("icon_path", s[2])
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_constant_override("icon_max_width", 16)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var url := String(s[3])
		b.pressed.connect(func() -> void: OS.shell_open(url))
		row.add_child(b)
		_social.append(b)
	var sp := Button.new()
	sp.name = "Support"
	sp.text = "♥  " + tr("Apoyar Vectopen")
	sp.tooltip_text = tr("Las donaciones pagan tiempo de desarrollo y la versión web de Vectopen.") + "\n" + SPONSOR_URL
	sp.focus_mode = Control.FOCUS_NONE
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.custom_minimum_size = Vector2(0, 30)
	sp.add_theme_font_size_override("font_size", 11)
	sp.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sp.pressed.connect(func() -> void: OS.shell_open(SPONSOR_URL))
	v.add_child(sp)
	_social.append(sp)
	_sep(v)
	# Actualizaciones.
	_section(v, tr("ACTUALIZACIONES"))
	_upd_status = Label.new()
	_upd_status.name = "UpdateStatus"
	_upd_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_upd_status.custom_minimum_size = Vector2(276, 0)
	_upd_status.add_theme_font_size_override("font_size", 11)
	v.add_child(_upd_status)
	progress = ProgressBar.new()
	progress.name = "UpdateProgress"
	progress.custom_minimum_size = Vector2(0, 6)
	progress.show_percentage = false
	progress.visible = false
	v.add_child(progress)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	v.add_child(brow)
	btn_check = _button(brow, "CheckUpdates", tr("Buscar actualizaciones"))
	btn_install = _button(brow, "InstallUpdate", tr("Descargar e instalar"))
	btn_restart = _button(brow, "RestartApp", tr("Reiniciar"))
	chk_auto = CheckBox.new()
	chk_auto.name = "AutoCheck"
	chk_auto.text = tr("Comprobar al iniciar")
	chk_auto.focus_mode = Control.FOCUS_NONE
	chk_auto.add_theme_font_size_override("font_size", 11)
	v.add_child(chk_auto)
	var up := _updater()
	if up:
		chk_auto.button_pressed = up.auto_check_enabled()
		chk_auto.toggled.connect(func(on: bool) -> void: up.set_auto_check(on))
		btn_check.pressed.connect(func() -> void:
			_set_state("checking")
			up.check(true))
		btn_install.pressed.connect(func() -> void:
			_set_state("downloading")
			up.download_and_install())
		btn_restart.pressed.connect(func() -> void: up.restart())
		up.check_finished.connect(func(info: Dictionary) -> void: _set_state("available" if not info.is_empty() else "uptodate"))
		up.download_progress.connect(func(done: int, total: int) -> void:
			progress.max_value = maxi(total, 1)
			progress.value = done
			_upd_status.text = tr("Descargando… %.1f / %.1f MB") % [done / 1048576.0, total / 1048576.0])
		up.install_finished.connect(func(ok: bool, msg: String) -> void:
			_set_state("installed" if ok and up.install_kind() in ["rpm", "deb"] else "available")
			_upd_status.text = msg)
		up.update_available.connect(func(_i: Dictionary) -> void:
			_set_state("available")
			_show_badge(true))
		_set_state("available" if not up.latest.is_empty() else "idle")
		_show_badge.call_deferred(not up.latest.is_empty())
	else:
		_set_state("idle")
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _restyle())
	_restyle()

func _current_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))

# ── abrir desde cualquier logo (Modern, Pro) ─────────────────────────────────
## Hace que `ctrl` (logo o marca) abra esta ventana al pulsarlo y le pone el
## punto de aviso de actualización.
static func register_anchor(ctrl: Control) -> void:
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ctrl.tooltip_text = "Acerca de Vectopen · comunidad · actualizaciones"
	ctrl.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			toggle_at(ctrl)
			ctrl.accept_event())
	_badge_for.call_deferred(ctrl)

static func _badge_for(ctrl: Control) -> void:
	var up := ctrl.get_node_or_null("/root/Updater")
	if up == null:
		return
	var b := _make_badge(ctrl)
	b.visible = not up.latest.is_empty()
	up.update_available.connect(func(_i: Dictionary) -> void:
		if is_instance_valid(b):
			b.visible = true)

static func _make_badge(host: Control) -> Panel:
	var badge := Panel.new()
	badge.name = "UpdateBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size = Vector2(10, 10)
	badge.position = Vector2(maxf(host.size.x, host.custom_minimum_size.x) - 6, -3)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#ff453a")
	sb.set_corner_radius_all(6)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	badge.add_theme_stylebox_override("panel", sb)
	host.add_child(badge)
	return badge

## Abre (o cierra) la ventana flotante bajo `anchor`.
static func toggle_at(anchor: Control) -> void:
	if not is_instance_valid(_floating):
		var layer := CanvasLayer.new()
		layer.name = "AboutLayer"
		layer.layer = 95
		anchor.get_tree().root.add_child(layer)
		_floating = AboutPanel.new()
		_floating.name = "AboutPanel"
		_floating.floating = true
		_floating.visible = false
		layer.add_child(_floating)
	if _floating.visible and _anchor == anchor:
		_floating.visible = false
		return
	_anchor = anchor
	_floating.visible = true
	_floating.reset_size()
	var r := anchor.get_global_rect()
	var vp := anchor.get_viewport_rect().size
	var pos := Vector2(r.position.x, r.end.y + 8)
	pos.x = clampf(pos.x, 8, vp.x - _floating.size.x - 8)
	pos.y = clampf(pos.y, 8, maxf(8, vp.y - _floating.size.y - 8))
	_floating.position = pos

## true = ventana flotante (se cierra al pulsar fuera o con Esc).
var floating := false

func _input(ev: InputEvent) -> void:
	if not floating or not visible:
		return
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.pressed and not get_global_rect().has_point(ev.position):
		if not (is_instance_valid(_anchor) and _anchor.get_global_rect().has_point(ev.position)):
			visible = false

func _show_badge(on: bool) -> void:
	var host := get_parent() as Control
	if host == null:
		return
	if badge == null:
		badge = _make_badge(host)
		badge.position = Vector2(24, -3)
	badge.visible = on

func _updater() -> Node:
	return get_node_or_null("/root/Updater")

## Estado de la sección de actualizaciones.
func _set_state(st: String) -> void:
	var up := _updater()
	btn_check.visible = st in ["idle", "uptodate", "checking"]
	btn_check.disabled = st == "checking"
	btn_install.visible = st == "available"
	btn_restart.visible = st == "installed"
	progress.visible = st == "downloading"
	match st:
		"idle":
			_upd_status.text = tr("Tienes la versión %s.") % _current_version()
		"checking":
			_upd_status.text = tr("Buscando en GitHub…")
		"uptodate":
			_upd_status.text = tr("Vectopen está al día (%s).") % _current_version()
		"available":
			var v: String = String(up.latest.get("version", "")) if up else ""
			_upd_status.text = tr("Nueva versión %s disponible (tienes %s).") % [v, _current_version()]
		"downloading":
			_upd_status.text = tr("Descargando…")
		"installed":
			pass
	_restyle()

func _section(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	parent.add_child(l)
	_sections.append(l)

func _sep(parent: Control) -> void:
	var s := HSeparator.new()
	parent.add_child(s)
	_seps.append(s)

func _button(parent: Control, nm: String, text: String) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 11)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(b)
	return b

func _restyle() -> void:
	var bg := ProUIStyle.col("PANEL_BG")
	var surface := ProUIStyle.col("PANEL_SURFACE")
	var text := ProUIStyle.col("PANEL_TEXT")
	var sec := ProUIStyle.col("TEXT_SECONDARY")
	var border := ProUIStyle.col("BORDER")
	var accent := ProUIStyle.col("ACCENT")
	var sb := ProUIStyle.flat(bg, 12, border, 14, 14)
	sb.shadow_color = Color(0, 0, 0, 0.35 if ProUIStyle.is_dark() else 0.12)
	sb.shadow_size = 14
	add_theme_stylebox_override("panel", sb)
	_title.add_theme_color_override("font_color", text)
	for l in [_version] + _sections + _keys:
		l.add_theme_color_override("font_color", sec)
	for l in [_desc, _upd_status] + _vals:
		l.add_theme_color_override("font_color", text)
	for s in _seps:
		var line := StyleBoxLine.new()
		line.color = border
		line.thickness = 1
		s.add_theme_stylebox_override("separator", line)
	var hover := surface.lerp(text, 0.08)
	for b in _social + [btn_check, btn_restart]:
		_style_button(b, surface, hover, border, text)
		if b.has_meta("icon_path"):
			b.icon = ProUIStyle.icon(String(b.get_meta("icon_path")), text, 32)
	# El botón principal destaca con el color de acento.
	_style_button(btn_install, accent, accent.lightened(0.12), accent, Color.WHITE)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		chk_auto.add_theme_color_override(k, text)
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	fill.set_corner_radius_all(3)
	var track := StyleBoxFlat.new()
	track.bg_color = surface
	track.set_corner_radius_all(3)
	progress.add_theme_stylebox_override("fill", fill)
	progress.add_theme_stylebox_override("background", track)

func _style_button(b: Button, bg: Color, hover: Color, border: Color, fg: Color) -> void:
	b.add_theme_stylebox_override("normal", ProUIStyle.flat(bg, 8, border, 10, 4))
	b.add_theme_stylebox_override("hover", ProUIStyle.flat(hover, 8, border, 10, 4))
	b.add_theme_stylebox_override("pressed", ProUIStyle.flat(hover.darkened(0.08), 8, border, 10, 4))
	b.add_theme_stylebox_override("disabled", ProUIStyle.flat(bg, 8, border, 10, 4))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		b.add_theme_color_override(k, fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.5))
