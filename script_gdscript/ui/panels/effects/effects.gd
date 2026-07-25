extends PanelContainer

const FX_DIR := "res://scenes/ui/panels/effects/fx/"

const EFFECT_ORDER := [
	"Blur", "3D", "Outline", "Inner Shadow", "Drop Shadow",
	"Color Overlay", "Gradient Overlay", "Inner Glow",
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

var _active_effects: Dictionary = {}

func _ready() -> void:
	_add_button.pressed.connect(_on_add_pressed)
	_add_popup.id_pressed.connect(_on_popup_id_pressed)
	_refresh_popup()

func _on_add_pressed() -> void:
	_add_popup.position = _add_button.global_position + Vector2(0, _add_button.size.y)
	_add_popup.popup()

func _refresh_popup() -> void:
	_add_popup.clear()
	for i in EFFECT_ORDER.size():
		var name: String = EFFECT_ORDER[i]
		if not _active_effects.has(name):
			_add_popup.add_item(name, i)

func _on_popup_id_pressed(id: int) -> void:
	_add_effect(EFFECT_ORDER[id])

func _add_effect(effect_name: String) -> void:
	if _active_effects.has(effect_name):
		return
	var instance: EffectFxBase = EFFECT_SCENES[effect_name].instantiate()
	instance.remove_requested.connect(_on_effect_removed)
	_effects_list.add_child(instance)
	_active_effects[effect_name] = instance
	_refresh_popup()
	GlobalEvents.emit_safe("effect_parameter_updated", effect_name, "enabled", true)

func _on_effect_removed(fx_node: EffectFxBase) -> void:
	var effect_name: String = fx_node.effect_name
	_active_effects.erase(effect_name)
	fx_node.queue_free()
	_refresh_popup()
	GlobalEvents.emit_safe("effect_parameter_updated", effect_name, "enabled", false)
