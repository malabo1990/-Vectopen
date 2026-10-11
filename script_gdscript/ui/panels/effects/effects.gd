extends PanelContainer

const FX_DIR := "res://scenes/ui/panels/effects/fx/"

const EFFECT_ORDER := [
	"Drop Shadow", "Inner Shadow", "Outline", "Blur",
	"Color Overlay", "Gradient Overlay", "Inner Glow",
	"3D", "Bevel Emboss", "Extrusion",
]

## Tarjetas construidas por código (sin .tscn): 3D (iluminación, Affinity),
## Bisel y relieve (Photoshop) y Extrusión.
const CODE_CARD := preload("res://script_gdscript/ui/panels/effects/fx/fx_code_card.gd")
const CODE_CARDS := ["3D", "Bevel Emboss", "Extrusion"]
const FxLight = preload("res://script_gdscript/shapes/fx_light.gd")

const EFFECT_SCENES := {
	"Blur": preload(FX_DIR + "blur.tscn"),
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
## Edición EN VIVO de parámetros: se escribe al momento y UN paso de deshacer
## se registra al terminar el gesto (sin cambios durante 0,45 s). Antes cada
## valor de un arrastre era una acción de deshacer + un aviso completo.
var _live_before: Dictionary = {}   # figura -> efectos antes del gesto
var _commit_timer: Timer = null

func _ready() -> void:
	_commit_timer = Timer.new()
	_commit_timer.one_shot = true
	_commit_timer.timeout.connect(_commit_live)
	add_child(_commit_timer)
	_setup_empty_label()
	_add_button.pressed.connect(_on_add_pressed)
	_add_popup.id_pressed.connect(_on_popup_id_pressed)
	_setup_popup()

	var ic = _get_inspector_core()
	if ic and ic.has_signal("changed"):
		if not ic.changed.is_connected(_on_inspector_changed):
			ic.changed.connect(_on_inspector_changed)

	_sync_from_inspector()
	# Pestaña "Filters" (grano, duotono, neón, glitch…): se crea por código.
	(func() -> void: load("res://script_gdscript/ui/panels/effects/filters_panel.gd").install(self)).call_deferred()
	# Pestañas "Shader" (código + biblioteca), "Vectorizar" (imagen → Bézier)
	# y "Script" (GDScript con la API + complementos). ARRANQUE RÁPIDO: se
	# montan la PRIMERA VEZ que se muestran (antes, ~190 ms al abrir Vectopen
	# aunque nadie las mirase). install() es idempotente.
	_install_tab_lazily("Shader", "shader_panel")
	_install_tab_lazily("Vectorizar", "vectorize_panel")
	_install_tab_lazily("Script", "script_panel")
	_restyle()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m: String) -> void: _restyle())

## Monta la pestaña `host_name` con `<script_file>.gd` cuando su anfitrión
## se vuelve visible por primera vez (o ya, si se ve al arrancar).
func _install_tab_lazily(host_name: String, script_file: String) -> void:
	var install := func() -> void:
		load("res://script_gdscript/ui/panels/effects/%s.gd" % script_file).install(self)
	var content := get_parent()
	var host := content.get_node_or_null(host_name) as Control if content else null
	if host == null or host.is_visible_in_tree():
		install.call_deferred()
		return
	var done := [false]
	host.visibility_changed.connect(func() -> void:
		if not done[0] and host.is_visible_in_tree():
			done[0] = true
			install.call())

## Diseño común con la pestaña Filtros, con los colores del tema actual.
func _restyle() -> void:
	var ui = load("res://script_gdscript/ui/panels/effects/fx_ui.gd")
	ui.style_panel_bg(self)
	var title := get_node_or_null("MarginContainer/VBoxContainer/Toolbar/Label") as Label
	if title:
		ui.style_title(title)
	_add_button.text = ui.t("+ Add effect")
	ui.style_add_button(_add_button)
	ProUIStyle.style_popup(_add_popup)
	if _empty_label:
		_empty_label.text = ui.t("No selection\nSelect an object to edit effects")
		ui.style_empty(_empty_label)
	var sc := _effects_list.get_parent() as ScrollContainer
	if sc:
		ui.style_scroll(sc)
	_effects_list.add_theme_constant_override("separation", 4)
	for c in _effects_list.get_children():
		if c.has_method("dress"):
			c.dress()
	var content := get_parent()
	if content and content.owner is Control:
		ui.style_window(content.owner as Control)
		ui.restyle_tabs(content.get_parent().get_node_or_null("MarginContainer/HBoxContainer") as Container)

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
	var ui = load("res://script_gdscript/ui/panels/effects/fx_ui.gd")
	for i in range(EFFECT_ORDER.size()):
		var nm: String = EFFECT_ORDER[i]
		_add_popup.add_item(ui.t(nm) if nm in CODE_CARDS else nm, i)

func _on_add_pressed() -> void:
	_add_popup.position = Vector2i(_add_button.global_position + Vector2(0, _add_button.size.y))
	_add_popup.popup()

func _on_popup_id_pressed(id: int) -> void:
	if id < 0 or id >= EFFECT_ORDER.size():
		return
	var effect_name: String = EFFECT_ORDER[id]
	_add_new_effect(effect_name)

## Efecto nuevo con sus valores por defecto (también lo usa VectopenAPI).
static func default_effect(effect_name: String) -> Dictionary:
	var new_fx := {
		"type": effect_name,
		"enabled": true,
	}
	match effect_name:
		"Drop Shadow":
			new_fx["offset_x"] = 4.0
			new_fx["offset_y"] = 4.0
			new_fx["blur"] = 6.0
			new_fx["spread"] = 0.0
			new_fx["color"] = Color(0.0, 0.0, 0.0, 0.4)
		"Inner Shadow":
			new_fx["offset_x"] = 2.0
			new_fx["offset_y"] = 2.0
			new_fx["blur"] = 4.0
			new_fx["spread"] = 0.0
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
			new_fx["angle"] = 0.0
			new_fx["colors"] = [Color(0.95, 0.3, 0.2), Color(0.25, 0.3, 0.95)]
			new_fx["offsets"] = [0.0, 1.0]
		"Inner Glow":
			# Lo que el panel edita y el dibujo lee (antes "intensity", que
			# ningún control tenía).
			new_fx["color"] = Color.WHITE
			new_fx["radius"] = 8.0
			new_fx["opacity"] = 1.0
		"3D", "Bevel Emboss", "Extrusion":
			new_fx.merge(FxLight.defaults(FxLight.canonical(effect_name)), true)
	return new_fx

func _add_new_effect(effect_name: String) -> void:
	var new_fx := default_effect(effect_name)
	var list := _collect_effects_from_ui()
	list.append(new_fx)
	_apply_effects_to_selection(list)

func _on_inspector_changed(_props: Dictionary = {}) -> void:
	if _is_syncing or not _live_before.is_empty():
		return   # durante un gesto el panel ya muestra lo que se edita
	_sync_from_inspector()

func _sync_from_inspector() -> void:
	if not is_inside_tree():
		return
	var ic = _get_inspector_core()
	var sel: Array = ic.selection() if ic else []
	if sel.is_empty():
		_add_button.disabled = true
		_add_button.visible = false
		if _empty_label:
			_empty_label.visible = true
		_clear_effects_list()
		return

	_add_button.disabled = false
	_add_button.visible = true
	if _empty_label:
		_empty_label.visible = false

	var first_shape = sel[0]
	var current_fx: Array = []
	if "effects" in first_shape and first_shape.effects is Array:
		current_fx = first_shape.effects
	elif first_shape.has_meta("effects") and first_shape.get_meta("effects") is Array:
		current_fx = first_shape.get_meta("effects")

	# "3D" antiguo → Extrusión + Bisel y relieve (se guarda así al editar)
	_rebuild_or_update_ui(FxLight.migrate_list(current_fx))

func _clear_effects_list() -> void:
	for c in _effects_list.get_children():
		c.queue_free()

func _canonical_type(fx_name: String) -> String:
	var norm := fx_name.to_lower().replace(" ", "_")
	match norm:
		"drop_shadow": return "Drop Shadow"
		"inner_shadow": return "Inner Shadow"
		"outline": return "Outline"
		"blur": return "Blur"
		"color_overlay": return "Color Overlay"
		"gradient_overlay": return "Gradient Overlay"
		"inner_glow": return "Inner Glow"
		"3d", "threed": return "3D"
		"bevel_emboss", "bevel", "bevel_and_emboss": return "Bevel Emboss"
		"extrusion", "extrude": return "Extrusion"
		_: return fx_name   # (antes devolvía `name`: el nombre del NODO del panel)

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
			var type_name: String = _canonical_type(fx.get("type", "")) if (fx is Dictionary) else ""
			if not (child is EffectFxBase) or child.effect_name != type_name:
				needs_rebuild = true
				break

	if needs_rebuild:
		_clear_effects_list()
		for fx in fx_list:
			if not (fx is Dictionary):
				continue
			var type_name: String = _canonical_type(fx.get("type", ""))
			var instance: EffectFxBase = null
			if type_name in CODE_CARDS:
				instance = CODE_CARD.new(type_name)
			elif EFFECT_SCENES.has(type_name):
				instance = EFFECT_SCENES[type_name].instantiate()
			else:
				continue
			instance.remove_requested.connect(_on_effect_removed)
			if instance.has_signal("move_up_requested"):
				instance.move_up_requested.connect(_on_effect_move_up)
			if instance.has_signal("move_down_requested"):
				instance.move_down_requested.connect(_on_effect_move_down)
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

func _on_effect_move_up(fx_node: EffectFxBase) -> void:
	var idx = fx_node.get_index()
	if idx > 0:
		_effects_list.move_child(fx_node, idx - 1)
		var updated := _collect_effects_from_ui()
		_apply_effects_to_selection(updated)

func _on_effect_move_down(fx_node: EffectFxBase) -> void:
	var idx = fx_node.get_index()
	if idx < _effects_list.get_child_count() - 1:
		_effects_list.move_child(fx_node, idx + 1)
		var updated := _collect_effects_from_ui()
		_apply_effects_to_selection(updated)

func _on_fx_param_changed(_fx_node: Node, _prop: String, _val: Variant) -> void:
	if _is_syncing:
		return
	_apply_live(_collect_effects_from_ui())

func _apply_live(effects_array: Array) -> void:
	var ic = _get_inspector_core()
	if ic == null or not ic.has_method("_write"):
		_apply_effects_to_selection(effects_array)
		return
	if _live_before.is_empty():
		for s in ic.selection():
			var b = ic._read(s, "effects")
			if b != null:
				_live_before[s] = b
	for s in _live_before:
		if is_instance_valid(s):
			ic._write(s, "effects", effects_array.duplicate(true))
	if ic.has_method("post_write_live"):
		ic.post_write_live()
	_commit_timer.start(0.45)

func _commit_live() -> void:
	if _live_before.is_empty():
		return
	var before := _live_before
	_live_before = {}
	var ic = _get_inspector_core()
	if ic and ic.has_method("commit_live"):
		ic.commit_live("effects", before)

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
	# Añadir / quitar / reordenar: primero cerrar el gesto en vivo pendiente.
	if not _live_before.is_empty():
		_commit_timer.stop()
		_commit_live()
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
