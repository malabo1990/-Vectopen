extends GdUnitTestSuite

func test_main_panel_keyboard_lista_no_vacia() -> void:
	var scene: Node = auto_free(load("res://scenes/ui/main.tscn").instantiate())
	add_child(scene)
	var panel: Node = scene.get_node("keyboard/PanelContainer/MarginContainer/Contenido/Button/Panel_keyboard")
	var ac := panel.find_child("ActionContainer", true, false) as VBoxContainer
	assert_object(ac).is_not_null()
	# Solo las acciones que la app ejecuta de verdad (VectopenInput.DEFAULTS),
	# una fila por acción (los títulos de categoría no cuentan).
	var rows := ac.get_children().filter(func(c): return c.has_meta("action"))
	assert_int(rows.size()).is_equal(VectopenInput.DEFAULTS.size())
	# Pestañas Atajos / Teclado / Ratón.
	for t in ["Tab_list", "Tab_keys", "Tab_mouse"]:
		assert_object(panel.find_child(t, true, false)).is_not_null()

func test_teclado_simulado_estados() -> void:
	var scene: Node = auto_free(load("res://scenes/ui/main.tscn").instantiate())
	add_child(scene)
	var panel = scene.get_node("keyboard/PanelContainer/MarginContainer/Contenido/Button/Panel_keyboard")
	assert_str(panel.key_state(KEY_G, "ctrl")).is_equal("assigned")   # Agrupar
	assert_str(panel.key_state(KEY_J, "")).is_equal("free")
	assert_str(panel.key_state(KEY_LEFT, "")).is_equal("fixed")
	assert_str(panel.key_state(KEY_5, "")).is_equal("assigned")       # zoom; opacidad solo con selección
	assert_str(panel.key_state(KEY_6, "")).is_equal("fixed")
	assert_bool(panel.conflicts().is_empty()).is_true()
	assert_str(panel.key_state(KEY_Y, "ctrl")).is_equal("fixed")
