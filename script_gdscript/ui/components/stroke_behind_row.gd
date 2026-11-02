# =============================================================================
# VECTOPEN — «TRAZO DETRÁS DEL RELLENO» (UX-18)
# RUTA: res://script_gdscript/ui/components/stroke_behind_row.gd
#
# Como «Draw stroke behind fill» de Affinity: el relleno tapa la mitad
# interior del trazo. Un ÚNICO componente para Smart, Modern y Pro (junto a la
# fila «Unión»). Escribe stroke_behind_fill vía InspectorCore (con deshacer) y
# se oculta si la selección no tiene esa propiedad.
# =============================================================================
class_name StrokeBehindRow
extends HBoxContainer

var label_width := 64.0
var toggle: CheckButton
var _guard := false
var _label: Label

func _init(p_label_width: float = 64.0) -> void:
	label_width = p_label_width
	name = "StrokeBehindRow"

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_label = Label.new()
	_label.text = tr("Orden")
	_label.custom_minimum_size = Vector2(label_width, 0)
	_label.add_theme_font_size_override("font_size", 11)
	add_child(_label)
	toggle = CheckButton.new()
	toggle.name = "BehindFill"
	toggle.text = tr("Trazo detrás del relleno")
	toggle.tooltip_text = tr("El relleno tapa la mitad interior del trazo (como en Affinity)")
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.toggled.connect(_on_toggled)
	add_child(toggle)
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and not ic.changed.is_connected(_on_props):
		ic.changed.connect(_on_props)
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme):
		tm.theme_changed.connect(_on_theme)
	_restyle()
	if ic and ic.has_method("current_props"):
		_on_props(ic.current_props())

func _on_theme(_m = null) -> void:
	_restyle()

func _restyle() -> void:
	if is_instance_valid(_label):
		_label.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))
	if is_instance_valid(toggle):
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			toggle.add_theme_color_override(k, ProUIStyle.col("PANEL_TEXT"))

func _on_toggled(on: bool) -> void:
	if _guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("stroke_behind_fill", on)

func _on_props(props: Dictionary) -> void:
	if not is_instance_valid(self):
		return
	visible = props.has("stroke_behind_fill")
	if not visible:
		return
	_guard = true
	var pv: Dictionary = props["stroke_behind_fill"]
	toggle.set_pressed_no_signal(bool(pv.get("value", false)) and not pv.get("mixed", false))
	_guard = false
