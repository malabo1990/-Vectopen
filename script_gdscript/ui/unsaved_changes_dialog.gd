# =============================================================================
# RUTA: res://script_gdscript/ui/unsaved_changes_dialog.gd
# Diálogo «Cambios sin guardar» con el estilo de Vectopen (antes, el
# ConfirmationDialog de Godot: barra de título del sistema y botones grises).
#
# · Tarjeta con los colores del TEMA (claro / oscuro), esquinas redondeadas,
#   sombra y fondo atenuado detrás.
# · Botones con COLOR CON SIGNIFICADO (accesible: color + texto + posición):
#     Guardar = verde (principal, Intro) · Cancelar = amarillo (Esc) ·
#     No guardar = rojo, separado a la izquierda (pierde los cambios).
#   Texto con contraste suficiente sobre cada color.
# =============================================================================
extends CanvasLayer

signal save_chosen
signal discard_chosen
signal cancel_chosen

const GREEN := Color("1e7d45")   # blanco encima: contraste 5,2 (WCAG AA)
const AMBER := Color("d99a00")
const AMBER_BORDER := Color("d99a00")
const RED := Color("c53030")     # blanco encima: contraste 5,5

var _card: PanelContainer
var _title: Label
var _msg: Label

func _init() -> void:
	layer = 120
	name = "UnsavedChangesDialog"

## Muestra el diálogo para el documento `doc_name`.
func open(doc_name: String) -> void:
	if _card == null:
		_build()
	_title.text = tr("¿Guardar los cambios?")
	_msg.text = tr("«%s» tiene cambios sin guardar. Si sales sin guardar, se perderán.") % doc_name
	_apply_theme()
	visible = true
	var b := find_child("BtnSave", true, false) as Button
	if b:
		b.grab_focus.call_deferred()

func close() -> void:
	visible = false

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.custom_minimum_size = Vector2(440, 0)
	center.add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	_card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	var icon := _WarnIcon.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 6)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(texts)
	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_font_size_override("font_size", 15)
	texts.add_child(_title)
	_msg = Label.new()
	_msg.name = "Message"
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(340, 0)
	_msg.add_theme_font_size_override("font_size", 13)
	texts.add_child(_msg)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var discard := _button("BtnDiscard", tr("No guardar"))
	discard.tooltip_text = tr("Salir y perder los cambios")
	discard.pressed.connect(func() -> void:
		close()
		discard_chosen.emit())
	row.add_child(discard)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var cancel := _button("BtnCancel", tr("Cancelar"))
	cancel.tooltip_text = tr("Volver al documento (Esc)")
	cancel.pressed.connect(func() -> void:
		close()
		cancel_chosen.emit())
	row.add_child(cancel)
	var save := _button("BtnSave", tr("Guardar"))
	save.tooltip_text = tr("Guardar y salir (Intro)")
	save.pressed.connect(func() -> void:
		close()
		save_chosen.emit())
	row.add_child(save)

func _button(n: String, text: String) -> Button:
	var b := Button.new()
	b.name = n
	b.text = text
	b.custom_minimum_size = Vector2(104, 32)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 13)
	return b

## Estilo sobrio (como Figma, Adobe o macOS): el color dice qué hace cada
## botón sin gritar. Guardar = verde sólido (principal) · Cancelar = neutro
## con borde ámbar · No guardar = rojo solo en texto y borde (destructivo).
func _style_button(b: Button, fill: Color, border: Color, fg: Color, solid: bool) -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		sb.bg_color = fill
		sb.border_color = border
		sb.set_border_width_all(0 if solid else 1)
		match st:
			"hover":
				sb.bg_color = fill.lightened(0.08) if solid else Color(border, 0.10)
			"pressed":
				sb.bg_color = fill.darkened(0.12) if solid else Color(border, 0.18)
			"focus":
				sb.draw_center = false
				sb.border_color = Color(border if not solid else fill, 0.55)
				sb.set_border_width_all(2)
				for side in ["expand_margin_left", "expand_margin_right", "expand_margin_top", "expand_margin_bottom"]:
					sb.set(side, 3)
		b.add_theme_stylebox_override(st, sb)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, fg)

func _apply_theme() -> void:
	var bg := ProUIStyle.col("PANEL_BG")
	var text := ProUIStyle.col("PANEL_TEXT")
	var dark := bg.get_luminance() < 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.border_color = ProUIStyle.col("BORDER")
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 28
	sb.shadow_offset = Vector2(0, 10)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 22
	sb.content_margin_bottom = 20
	_card.add_theme_stylebox_override("panel", sb)
	_title.add_theme_color_override("font_color", text)
	_msg.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
	(get_node("Dim") as ColorRect).color = Color(0, 0, 0, 0.40)
	var red := RED.lightened(0.35) if dark else RED   # texto rojo legible sobre fondo oscuro
	_style_button(find_child("BtnSave", true, false), GREEN, GREEN, Color.WHITE, true)
	_style_button(find_child("BtnCancel", true, false), Color(0, 0, 0, 0), AMBER_BORDER, text, false)
	_style_button(find_child("BtnDiscard", true, false), Color(0, 0, 0, 0), red, red, false)
	var icon := find_child("Icon", true, false)
	icon.set("tint", AMBER)
	icon.queue_redraw()

## Icono de aviso dibujado (nítido a cualquier escala): círculo suave ámbar
## con el signo de exclamación.
class _WarnIcon extends Control:
	var tint := Color("d99a00")
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, Color(tint, 0.16))
		draw_arc(c, r - 0.5, 0.0, TAU, 48, Color(tint, 0.55), 1.0, true)
		draw_line(c + Vector2(0, -r * 0.42), c + Vector2(0, r * 0.12), tint, maxf(2.2, r * 0.14), true)
		draw_circle(c + Vector2(0, r * 0.38), maxf(1.4, r * 0.09), tint)

func _input(event: InputEvent) -> void:   # modal: con prioridad sobre el lienzo y los paneles
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		cancel_chosen.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not (get_viewport().gui_get_focus_owner() is Button):
		close()
		save_chosen.emit()
		get_viewport().set_input_as_handled()
