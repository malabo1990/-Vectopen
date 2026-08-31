extends GdUnitTestSuite

func test_spin_en_tema_directo() -> void:
	var tema: Node = auto_free(load("res://scenes/ui/theme_config_panel.tscn").instantiate())
	add_child(tema)
	await get_tree().process_frame
	var tspin: Node = tema.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/RowTextSize/SpinTextSize")
	print("DEBUG directo: ", tspin, " script=", tspin.get_script() if tspin else "-", " value=", "value" in tspin)
