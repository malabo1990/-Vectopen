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

func test_modern_context_menu_two_levels_and_contextual_items() -> void:
	var menu = auto_free(ModernContextMenuScript.new())
	menu.show_quick_bar = true
	add_child(menu)
	menu._build_menu()
	await get_tree().process_frame

	# Nivel 1: acciones rápidas de alineación y distribución presentes
	var quick_actions := ["align_left", "align_center_h", "align_right", "align_top", "align_middle", "align_bottom", "dist_h", "dist_v"]
	for act in quick_actions:
		assert_bool(menu._items.has(act)).override_failure_message("Falta la acción rápida " + act).is_true()

	# Nivel 2: contextual según tipo de objeto — solo acciones que funcionan
	menu._build_level_2_contextual_items("shape")
	assert_bool(menu._items.has("invert_fill_stroke")).is_true()
	menu._build_level_2_contextual_items("text")
	assert_bool(menu._items.has("align_text_left")).is_true()
	assert_bool(menu._items.has("align_text_center")).is_true()
	assert_bool(menu._items.has("align_text_right")).is_true()
	menu._build_level_2_contextual_items("group")
	assert_bool(menu._items.has("ungroup_all")).is_true()
	menu._build_level_2_contextual_items("multi")
	assert_bool(menu._items.has("distribute_horizontal")).is_true()
	assert_bool(menu._items.has("distribute_vertical")).is_true()
	# Placeholders with no implementation are no longer offered
	for dead in ["convert_to_curves", "simplify_nodes", "vectorize_autotrace", "crop_image",
			"replace_image", "extract_palette", "enter_group", "isolate_group",
			"boolean_union", "boolean_difference", "boolean_intersection"]:
		assert_bool(menu._items.has(dead)).override_failure_message("Acción sin implementar: " + dead).is_false()

func test_modern_context_menu_items_are_monochrome_icons_with_right_shortcut() -> void:
	var menu = auto_free(ModernContextMenuScript.new())
	add_child(menu)
	await get_tree().process_frame
	var copy_btn: Button = menu._items["copy"]
	var icon_rect := copy_btn.find_children("", "TextureRect", true, false)
	assert_int(icon_rect.size()).is_equal(1)
	assert_object((icon_rect[0] as TextureRect).texture).is_not_null()
	var shortcut := copy_btn.find_child("Shortcut", true, false) as Label
	assert_object(shortcut).is_not_null()
	assert_int(shortcut.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_RIGHT)
	# Shortcut is the last element of the row: pushed to the far right
	assert_bool(shortcut.get_index() == shortcut.get_parent().get_child_count() - 1).is_true()

func test_modern_context_menu_theme_switcher() -> void:
	var menu = auto_free(ModernContextMenuScript.new())
	add_child(menu)
	await get_tree().process_frame

	assert_bool(menu._items.has("toggle_theme")).override_failure_message("Falta toggle_theme").is_true()
	var toggle_btn: Button = menu._items["toggle_theme"]
	assert_object(toggle_btn).is_not_null()
