# btn_toggle.gd
extends Node

@export var nodo_disparador: Node # Puede ser un Button, TextureButton, Area2D, etc.
@export var target_nodo: Node     # Puede ser un Label, Panel, Node2D, otra Escena, etc.

func _ready() -> void:
	var me: Variant = self
	if nodo_disparador == null and (me is Button or me is BaseButton):
		nodo_disparador = self
	if target_nodo == null and get_parent():
		# 1) Buscar ThemeConfigPanel o theme_config_panel si existe como hermano
		target_nodo = get_parent().get_node_or_null("ThemeConfigPanel")
		if target_nodo == null:
			target_nodo = get_parent().get_node_or_null("theme_config_panel")
		# 2) Buscar otro hermano que no sea el menú contextual principal (PanelContainer) ni self
		if target_nodo == null:
			for sibling in get_parent().get_children():
				if sibling != self and sibling.name != "PanelContainer" and (sibling is PanelContainer or sibling is Control):
					target_nodo = sibling
					break
		# 3) Fallback si no hay otro hermano
		if target_nodo == null:
			for sibling in get_parent().get_children():
				if sibling != self and (sibling is PanelContainer or sibling is Control):
					target_nodo = sibling
					break
	if nodo_disparador and target_nodo:
		# Buscamos la señal de activación típica de Godot ("pressed" o "input_event")
		if nodo_disparador.has_signal("pressed"):
			if not nodo_disparador.pressed.is_connected(_on_toggle):
				nodo_disparador.pressed.connect(_on_toggle)
		elif nodo_disparador.has_signal("input_event"):
			nodo_disparador.input_event.connect(func(_viewport, _event, _shape_idx): if _event.is_action_pressed("click_izquierdo"): _on_toggle())

func _on_toggle() -> void:
	if target_nodo == null:
		return
	# Cambia la visibilidad de manera segura si el nodo tiene la propiedad
	if "visible" in target_nodo:
		target_nodo.visible = !target_nodo.visible
		if target_nodo.visible and target_nodo is Control:
			_adjust_position(target_nodo as Control)

func _adjust_position(ctrl: Control) -> void:
	var parent_ctrl = ctrl.get_parent() as Control
	if not parent_ctrl:
		return
	var vp_rect = ctrl.get_viewport_rect()
	var vp_w = vp_rect.size.x if vp_rect.size.x > 0 else 1280.0
	var w = ctrl.size.x
	if w <= 0.0:
		w = ctrl.custom_minimum_size.x
	if w <= 0.0:
		w = 300.0

	var menu_w = 222.0
	if parent_ctrl is Control and parent_ctrl.size.x > 0:
		menu_w = parent_ctrl.size.x

	var left_space = parent_ctrl.global_position.x
	var right_space = vp_w - (parent_ctrl.global_position.x + menu_w)

	if left_space >= w + 10.0:
		ctrl.position.x = -(w + 10.0)
	elif right_space >= w + 10.0:
		ctrl.position.x = menu_w + 4.0
	elif right_space > left_space:
		ctrl.position.x = menu_w + 4.0
	else:
		ctrl.position.x = -(w + 10.0)
