# =============================================================================
# VECTOPEN — PRUEBAS DE MENÚ CONTEXTUAL MODERN UI (FIGMA & PENPOT STYLE)
# RUTA: res://test/ui/ModernContextMenu_test.gd
# =============================================================================
extends GdUnitTestSuite

const ModernContextMenuScript := preload("res://script_gdscript/ui/modern/modern_context_menu.gd")

func test_modern_context_menu_contains_all_actions() -> void:
	var menu = auto_free(ModernContextMenuScript.new())
	add_child(menu)
	await get_tree().process_frame

	var expected_actions := [
		"copy", "cut", "paste", "duplicate",
		"bring_to_front", "bring_forward", "send_backward", "send_to_back",
		"flip_h", "flip_v",
		"group", "ungroup",
		"rename", "toggle_visibility", "toggle_lock",
		"delete"
	]

	for act in expected_actions:
		assert_bool(menu._items.has(act)).override_failure_message("Falta la acción " + act).is_true()
		var btn: Button = menu._items[act]
		assert_object(btn).is_not_null()

func test_modern_context_menu_emits_action_on_click() -> void:
	var menu = auto_free(ModernContextMenuScript.new())
	add_child(menu)
	await get_tree().process_frame

	var triggered: Array[String] = []
	menu.action_triggered.connect(func(act: String):
		triggered.append(act)
	)

	menu.popup_at(Vector2(100, 100))
	assert_bool(menu.visible).is_true()

	var copy_btn: Button = menu._items["copy"]
	copy_btn.pressed.emit()
	await get_tree().process_frame

	assert_bool(triggered.is_empty()).is_false()
	assert_str(triggered[0]).is_equal("copy")
	assert_bool(menu.visible).is_false() # Se cierra al seleccionar una acción

func test_modern_context_menu_popup_bounds_clamp() -> void:
	var menu = auto_free(ModernContextMenuScript.new())
	add_child(menu)
	await get_tree().process_frame

	# Popup cerca del borde inferior derecho
	var vp: Vector2 = menu.get_viewport_rect().size
	menu.popup_at(vp)
	assert_bool(menu.visible).is_true()
	assert_float(menu.global_position.x).is_less_equal(vp.x)
	assert_float(menu.global_position.y).is_less_equal(vp.y)
