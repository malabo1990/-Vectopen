extends GdUnitTestSuite

func test_main_panel_keyboard_lista_no_vacia() -> void:
	var scene: Node = auto_free(load("res://scenes/ui/main.tscn").instantiate())
	add_child(scene)
	var ac: VBoxContainer = scene.get_node("keyboard/PanelContainer/MarginContainer/Contenido/Button/Panel_keyboard/MarginContainer/BoxContainer/ScrollContainer/MarginContainer/ActionContainer")
	print("DEBUG ac children: ", ac.get_child_count())
	assert_int(ac.get_child_count()).is_greater_equal(50)
