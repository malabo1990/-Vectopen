# =============================================================================
# VECTOPEN — POPOVER DE COLOR PARA LOS PANELES DE TEXTO
# RUTA: res://script_gdscript/ui/pro/text_color_popover.gd
# Las muestras de color de los paneles Texto y Tipografía abren el selector
# propio de la app (scenes/ui/pickr_color_tool.tscn) en vez del ColorPicker
# genérico de Godot. `attach(muestra, título)` intercepta el clic de un
# ColorPickerButton: al elegir color se asigna a la muestra y se emite su
# `color_changed`, así que cada panel sigue aplicando el color con su propia
# lógica (letras seleccionadas, sincronización y deshacer).
# La instancia del selector va AISLADA de ColorCore: si no, el selector
# aplicaría el color al relleno de la selección por su cuenta (sin respetar
# las letras seleccionadas) y reaccionaría a cambios de color de otros paneles.
# =============================================================================
class_name TextColorPopover
extends PanelContainer

const PICKR := "res://scenes/ui/pickr_color_tool.tscn"
const _GRADIENT_TABS := ["tab_linear", "tab_radial", "tab_conic", "tab_diamond", "tab_box", "tab_spiral", "tab_reflected"]

static var _shared: PanelContainer = null

var _pickr: Control = null
var _title: Label = null
var _target: ColorPickerButton = null
var _opening := false

## Hace que `cp` abra el selector de la app al pulsarlo.
static func attach(cp: ColorPickerButton, title: String) -> void:
	if cp == null or cp.has_meta("text_color_popover"):
		return
	cp.set_meta("text_color_popover", title)
	cp.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			cp.accept_event()   # el ColorPicker de Godot no llega a abrirse
			instance(cp).toggle_for(cp))

## Popover compartido (uno para toda la app), colgado de una capa alta.
static func instance(from: Node) -> PanelContainer:
	if is_instance_valid(_shared):
		return _shared
	var layer := CanvasLayer.new()
	layer.name = "TextColorPopoverLayer"
	layer.layer = 120
	from.get_tree().root.add_child(layer)
	_shared = load("res://script_gdscript/ui/pro/text_color_popover.gd").new()
	layer.add_child(_shared)
	return _shared

func _init() -> void:
	name = "TextColorPopover"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE + 1)
	header.add_child(_title)
	var close := Button.new()
	close.name = "BtnClose"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = tr("Cerrar")
	close.custom_minimum_size = Vector2(22, 22)
	close.icon = ProUIStyle.icon("res://icon/UI/xmark.svg", ProUIStyle.col("TEXT_SECONDARY"), 14) if ResourceLoader.exists("res://icon/UI/xmark.svg") else null
	if close.icon == null:
		close.text = "✕"
	close.pressed.connect(hide_popover)
	header.add_child(close)

	var scene: PackedScene = load(PICKR)
	_pickr = scene.instantiate() as Control
	box.add_child(_pickr)
	_isolate_pickr()
	if _pickr.has_signal("color_actualizado"):
		_pickr.color_actualizado.connect(_on_pickr_color)
	_apply_theme()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: _apply_theme())

## Sin puente a ColorCore ni a los degradados globales: el color solo sale
## por `color_actualizado` hacia la muestra que abrió el popover.
func _isolate_pickr() -> void:
	if "_from_core" in _pickr:
		_pickr.set("_from_core", true)
	var cc := get_node_or_null("/root/ColorCore")
	if cc:
		for sig in ["changed", "paint_changed"]:
			for c in cc.get_signal_connection_list(sig):
				if (c["callable"] as Callable).get_object() == _pickr:
					cc.disconnect(sig, c["callable"])
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge:
		for sig in ["gradient_changed", "gradient_stop_selected"]:
			if ge.has_signal(sig):
				for c in ge.get_signal_connection_list(sig):
					if (c["callable"] as Callable).get_object() == _pickr:
						ge.disconnect(sig, c["callable"])
	# El texto solo admite color sólido: fuera las pestañas de degradado.
	for prop in _GRADIENT_TABS:
		var b = _pickr.get(prop)
		if b is CanvasItem:
			(b as CanvasItem).visible = false
	var ge_ed = _pickr.get("gradient_editor")
	if ge_ed is CanvasItem:
		(ge_ed as CanvasItem).visible = false

func _apply_theme() -> void:
	var sb := ProUIStyle.flat(ProUIStyle.col("PANEL_SURFACE"), 8, ProUIStyle.col("BORDER_STRONG"), 8, 8)
	sb.shadow_color = Color(0, 0, 0, 0.3 if ProUIStyle.is_dark() else 0.14)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", sb)
	if is_instance_valid(_title):
		_title.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))

func current_target() -> ColorPickerButton:
	return _target if visible else null

## Abre junto a `cp` con su color; si ya estaba abierto para `cp`, lo cierra.
func toggle_for(cp: ColorPickerButton) -> void:
	if visible and _target == cp:
		hide_popover()
		return
	_target = cp
	_title.text = tr(String(cp.get_meta("text_color_popover", "Color")))
	_opening = true
	if _pickr.has_method("establecer_color"):
		_pickr.establecer_color(cp.color, true)
	_opening = false
	visible = true
	reset_size()
	await get_tree().process_frame
	_place_near(cp)

func _place_near(cp: Control) -> void:
	if not is_instance_valid(cp):
		return
	var vp := get_viewport_rect().size
	# Junto al PANEL que contiene la muestra (su contenedor más externo que
	# no ocupe media pantalla), no encima de él.
	var r := cp.get_global_rect()
	var n: Node = cp.get_parent()
	while n is Control:
		var cr := (n as Control).get_global_rect()
		if cr.size.x > vp.x * 0.5 or cr.size.y > vp.y * 0.9 or not cr.grow(1.0).encloses(cp.get_global_rect()):
			break   # pantalla completa, o un contenedor que no envuelve el panel (barra)
		if (n as Control).is_visible_in_tree():
			r = Rect2(cr.position.x, r.position.y, cr.size.x, r.size.y)
		n = n.get_parent()
	var s := get_combined_minimum_size()
	# A la izquierda del panel (los paneles viven a la derecha); si no cabe, a la derecha.
	var x := r.position.x - s.x - 12.0
	if x < 8.0:
		x = r.end.x + 12.0
	var y := clampf(r.position.y - 40.0, 8.0, maxf(8.0, vp.y - s.y - 8.0))
	global_position = Vector2(clampf(x, 8.0, maxf(8.0, vp.x - s.x - 8.0)), y)

func hide_popover() -> void:
	visible = false
	_target = null

func _on_pickr_color(c: Color) -> void:
	if _opening or not visible or not is_instance_valid(_target):
		return
	if _target.color.is_equal_approx(c):
		return
	_target.color = c
	_target.color_changed.emit(c)

## Clic fuera (que no sea sobre la propia muestra) o Esc → cerrar.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_popover()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mp: Vector2 = event.global_position if "global_position" in event else get_global_mouse_position()
		if get_global_rect().has_point(mp):
			return
		if is_instance_valid(_target) and _target.get_global_rect().has_point(mp):
			return
		hide_popover()
