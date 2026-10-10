# =============================================================================
# VECTOPEN — PROFESSIONAL CONTEXT MENU
# RUTA: res://script_gdscript/ui/pro/pro_context_menu.gd
# Compact desktop-style right-click menu for Professional mode: native
# PopupMenu with cascading submenus, shortcut hints and disabled states.
# Only lists actions that actually do something (ContextMenuActions).
# =============================================================================
class_name ProContextMenu
extends PopupMenu

signal action_triggered(action_id: String)

var _ids: Array[String] = []
var _sub_arrange: PopupMenu
var _sub_align: PopupMenu
var _sub_transform: PopupMenu

func _ready() -> void:
	name = "ProContextMenu"
	hide_on_checkable_item_selection = true
	id_pressed.connect(func(i: int): _on_id(self, i))
	_sub_arrange = _make_submenu("SubArrange")
	_sub_align = _make_submenu("SubAlign")
	_sub_transform = _make_submenu("SubTransform")
	_apply_style()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m): _apply_style())

func _make_submenu(node_name: String) -> PopupMenu:
	var sub := PopupMenu.new()
	sub.name = node_name
	add_child(sub)
	sub.id_pressed.connect(func(i: int): _on_id(sub, i))
	return sub

func _apply_style() -> void:
	for p in [self, _sub_arrange, _sub_align, _sub_transform]:
		if is_instance_valid(p):
			ProUIStyle.style_popup(p)

## Rebuilds the items for the current selection and opens at `pos` (screen/canvas coords).
func popup_at(pos: Vector2) -> void:
	rebuild()
	reset_size()
	var vp := get_parent().get_viewport() if get_parent() else get_viewport()
	var vp_size := Vector2(vp.get_visible_rect().size) if vp else Vector2(1920, 1080)
	var p := Vector2i(
		int(clampf(pos.x, 0.0, maxf(0.0, vp_size.x - size.x))),
		int(clampf(pos.y, 0.0, maxf(0.0, vp_size.y - size.y))))
	popup(Rect2i(p, Vector2i.ZERO))

func rebuild() -> void:
	_ids.clear()
	clear()
	for sub in [_sub_arrange, _sub_align, _sub_transform]:
		sub.clear()
	var kind := ContextMenuActions.selected_kind(self)

	# Object-specific actions first, like desktop editors do.
	match kind:
		"text":
			_add(self, "align_text_left", "Alinear texto a la izquierda")
			_add(self, "align_text_center", "Centrar texto")
			_add(self, "align_text_right", "Alinear texto a la derecha")
			add_separator()
		"shape":
			_add(self, "invert_fill_stroke", "Intercambiar relleno y trazo", KEY_X | KEY_MASK_SHIFT)
			add_separator()
		"group":
			_add(self, "ungroup", "Desagrupar", KEY_G | KEY_MASK_CTRL | KEY_MASK_SHIFT)
			add_separator()

	_add(self, "cut", "Cortar", KEY_X | KEY_MASK_CTRL)
	_add(self, "copy", "Copiar", KEY_C | KEY_MASK_CTRL)
	_add(self, "paste", "Pegar", KEY_V | KEY_MASK_CTRL)
	_add(self, "duplicate", "Duplicar", KEY_D | KEY_MASK_CTRL)
	_add(self, "delete", "Eliminar", KEY_DELETE)
	add_separator()

	_add(_sub_arrange, "bring_to_front", "Traer al frente", KEY_BRACKETRIGHT | KEY_MASK_CTRL | KEY_MASK_SHIFT)
	_add(_sub_arrange, "bring_forward", "Avanzar", KEY_BRACKETRIGHT | KEY_MASK_CTRL)
	_add(_sub_arrange, "send_backward", "Retroceder", KEY_BRACKETLEFT | KEY_MASK_CTRL)
	_add(_sub_arrange, "send_to_back", "Enviar al fondo", KEY_BRACKETLEFT | KEY_MASK_CTRL | KEY_MASK_SHIFT)
	_add_submenu("Organizar", _sub_arrange, kind != "none")

	_add(_sub_align, "align_left", "Izquierda")
	_add(_sub_align, "align_center_h", "Centro horizontal")
	_add(_sub_align, "align_right", "Derecha")
	_sub_align.add_separator()
	_add(_sub_align, "align_top", "Arriba")
	_add(_sub_align, "align_middle", "Centro vertical")
	_add(_sub_align, "align_bottom", "Abajo")
	_sub_align.add_separator()
	_add(_sub_align, "dist_h", "Distribuir horizontalmente")
	_add(_sub_align, "dist_v", "Distribuir verticalmente")
	_add_submenu("Alinear", _sub_align, kind != "none")

	_add(_sub_transform, "flip_h", "Voltear horizontal", KEY_H | KEY_MASK_SHIFT)
	_add(_sub_transform, "flip_v", "Voltear vertical", KEY_V | KEY_MASK_SHIFT)
	_add_submenu("Transformar", _sub_transform, kind != "none")
	add_separator()

	_add(self, "group", "Agrupar", KEY_G | KEY_MASK_CTRL)
	if kind != "group":
		_add(self, "ungroup", "Desagrupar", KEY_G | KEY_MASK_CTRL | KEY_MASK_SHIFT)
	add_separator()

	_add(self, "toggle_visibility", "Mostrar / Ocultar", KEY_H | KEY_MASK_CTRL | KEY_MASK_SHIFT)
	_add(self, "toggle_lock", "Bloquear", KEY_L | KEY_MASK_CTRL | KEY_MASK_SHIFT)
	_add(self, "rename", "Renombrar…", KEY_F2)

func _add(menu: PopupMenu, action_id: String, text: String, accel: int = 0) -> void:
	var idx := _ids.size()
	_ids.append(action_id)
	menu.add_item(tr(text), idx, accel)
	var item := menu.get_item_index(idx)
	menu.set_item_disabled(item, not ContextMenuActions.is_enabled(action_id, self))

func _add_submenu(text: String, sub: PopupMenu, enabled: bool) -> void:
	add_submenu_node_item(tr(text), sub)
	set_item_disabled(item_count - 1, not enabled)

func _on_id(_menu: PopupMenu, idx: int) -> void:
	if idx < 0 or idx >= _ids.size():
		return
	var action_id := _ids[idx]
	hide()
	action_triggered.emit(action_id)
	# The popup is its own Window; run actions from the canvas-layer parent so
	# helpers like the inline rename field are drawn in the main viewport.
	var host: Node = get_parent() if get_parent() is CanvasItem else self
	ContextMenuActions.execute(action_id, host)

## Action id bound to a visible item, for tests and tooling.
func get_action_ids() -> Array[String]:
	return _ids.duplicate()
