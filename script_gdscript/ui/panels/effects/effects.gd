extends PanelContainer

const FX_DIR := "res://scenes/ui/panels/effects/fx/"

const EFFECT_ORDER := [
	"Drop Shadow", "Inner Shadow", "Outline", "Blur",
	"Color Overlay", "Gradient Overlay", "Inner Glow", "3D",
]

const EFFECT_SCENES := {
	"Blur": preload(FX_DIR + "blur.tscn"),
	"3D": preload(FX_DIR + "three_d.tscn"),
	"Outline": preload(FX_DIR + "outline.tscn"),
	"Inner Shadow": preload(FX_DIR + "inner_shadow.tscn"),
	"Drop Shadow": preload(FX_DIR + "drop_shadow.tscn"),
	"Color Overlay": preload(FX_DIR + "color_overlay.tscn"),
	"Gradient Overlay": preload(FX_DIR + "gradient_overlay.tscn"),
	"Inner Glow": preload(FX_DIR + "inner_glow.tscn"),
}

@onready var _add_button: Button = %AddEffect
@onready var _add_popup: PopupMenu = %AddEffectPopup
@onready var _effects_list: VBoxContainer = %EffectsList

var _is_syncing: bool = false
var _empty_label: Label = null

func _ready() -> void:
	_setup_empty_label()
	_add_button.pressed.connect(_on_add_pressed)
	_add_popup.id_pressed.connect(_on_popup_id_pressed)
	_setup_popup()

	var ic = _get_inspector_core()
	if ic and ic.has_signal("changed"):
		if not ic.changed.is_connected(_on_inspector_changed):
			ic.changed.connect(_on_inspector_changed)

	_sync_from_inspector()

func _setup_empty_label() -> void:
	_empty_label = Label.new()
	_empty_label.name = "EmptyLabel"
	_empty_label.text = "No selection\nSelect an object to edit effects"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65, 1.0))
	_empty_label.add_theme_font_size_override("font_size", 12)
	if _effects_list and _effects_list.get_parent():
		_effects_list.get_parent().add_child(_empty_label)

func _get_inspector_core() -> Node:
	return get_node_or_null("/root/InspectorCore")

func _setup_popup() -> void:
	_add_popup.clear()
	for i in range(EFFECT_ORDER.size()):
		_add_popup.add_item(EFFECT_ORDER[i], i)

func _on_add_pressed() -> void:
	_add_popup.position = Vector2i(_add_button.global_position + Vector2(0, _add_button.size.y))
	_add_popup.popup()

func _on_popup_id_pressed(id: int) -> void:
	if id < 0 or id >= EFFECT_ORDER.size():
		return
	var effect_name: String = EFFECT_ORDER[id]
	_add_new_effect(effect_name)

func _add_new_effect(effect_name: String) -> void:
	var new_fx := {
		"type": effect_name,
		"enabled": true,
	}
	match effect_name:
		"Drop Shadow":
			new_fx["offset_x"] = 4.0
			new_fx["offset_y"] = 4.0
			new_fx["blur"] = 6.0
			new_fx["color"] = Color(0.0, 0.0, 0.0, 0.4)
		"Inner Shadow":
			new_fx["offset_x"] = 2.0
			new_fx["offset_y"] = 2.0
			new_fx["blur"] = 4.0
			new_fx["color"] = Color(0.0, 0.0, 0.0, 0.5)
		"Outline":
			new_fx["width"] = 2.0
			new_fx["color"] = Color(0.0, 0.0, 0.0, 1.0)
		"Blur":
			new_fx["radius"] = 5.0
			new_fx["preserve_alpha"] = false
		"Color Overlay":
			new_fx["color"] = Color(1.0, 0.0, 0.0, 1.0)
			new_fx["opacity"] = 1.0
		"Gradient Overlay":
			new_fx["opacity"] = 1.0
		"Inner Glow":
			new_fx["color"] = Color.WHITE
			new_fx["intensity"] = 1.0
		"3D":
			new_fx["depth"] = 4.0

	var list := _collect_effects_from_ui()
	list.append(new_fx)
	_apply_effects_to_selection(list)

func _on_inspector_changed(_props: Dictionary = {}) -> void:
	if _is_syncing:
		return
	_sync_from_inspector()

func _sync_from_inspector() -> void:
	var ic = _get_inspector_core()
	var sel: Array = ic.selection() if ic else []
	if sel.is_empty():
		_add_button.disabled = true
		if _empty_label:
			_empty_label.visible = true
		_clear_effects_list()
		return

	_add_button.disabled = false
	if _empty_label:
		_empty_label.visible = false

	var first_shape = sel[0]
	var current_fx: Array = []
	if "effects" in first_shape and first_shape.effects is Array:
		current_fx = first_shape.effects
	elif first_shape.has_meta("effects") and first_shape.get_meta("effects") is Array:
		current_fx = first_shape.get_meta("effects")

	_rebuild_or_update_ui(current_fx)

func _clear_effects_list() -> void:
	for c in _effects_list.get_children():
		c.queue_free()

func _rebuild_or_update_ui(fx_list: Array) -> void:
	_is_syncing = true
	var children := _effects_list.get_children()

	var needs_rebuild := false
	if children.size() != fx_list.size():
		needs_rebuild = true
	else:
		for i in range(fx_list.size()):
			var fx = fx_list[i]
			var child = children[i]
			var type_name: String = fx.get("type", "") if (fx is Dictionary) else ""
			if not (child is EffectFxBase) or child.effect_name != type_name:
				needs_rebuild = true
				break

	if needs_rebuild:
		_clear_effects_list()
		for fx in fx_list:
			if not (fx is Dictionary):
				continue
			var type_name: String = fx.get("type", "")
			if not EFFECT_SCENES.has(type_name):
				continue
			var instance: EffectFxBase = EFFECT_SCENES[type_name].instantiate()
			instance.remove_requested.connect(_on_effect_removed)
			if instance.has_signal("param_changed"):
				instance.param_changed.connect(_on_fx_param_changed)
			_effects_list.add_child(instance)
			instance.set_params(fx)
	else:
		for i in range(fx_list.size()):
			var child = children[i]
			if child is EffectFxBase:
				child.set_params(fx_list[i])

	_is_syncing = false

func _on_fx_param_changed(_fx_node: Node, _prop: String, _val: Variant) -> void:
	if _is_syncing:
		return
	var updated := _collect_effects_from_ui()
	_apply_effects_to_selection(updated)

func _on_effect_removed(fx_node: EffectFxBase) -> void:
	fx_node.queue_free()
	call_deferred("_after_effect_removed")

func _after_effect_removed() -> void:
	var updated := _collect_effects_from_ui()
	_apply_effects_to_selection(updated)

func _collect_effects_from_ui() -> Array:
	var result: Array = []
	for c in _effects_list.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is EffectFxBase and c.has_method("get_params"):
			result.append(c.get_params())
	return result

func _apply_effects_to_selection(effects_array: Array) -> void:
	var ic = _get_inspector_core()
	if ic and ic.has_method("apply"):
		ic.apply("effects", effects_array)
	else:
		var sel = ic.selection() if ic else []
		for s in sel:
			if "effects" in s:
				s.effects = effects_array.duplicate(true)
			if s.has_method("queue_redraw"):
				s.queue_redraw()
