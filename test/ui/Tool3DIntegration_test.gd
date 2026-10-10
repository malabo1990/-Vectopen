extends GdUnitTestSuite

func test_tool_scene_has_3d_button() -> void:
	var tool_scene: PackedScene = load("res://scenes/ui/tool.tscn")
	assert_object(tool_scene).is_not_null()

	var instance: Node = auto_free(tool_scene.instantiate())
	assert_object(instance).is_not_null()

	var btn_3d: Button = instance.find_child("button_tool3d", true, false) as Button
	assert_object(btn_3d).is_not_null()
	assert_str(String(btn_3d.get("tool_name"))).is_equal("3d")
	assert_object(btn_3d.icon).is_not_null()

func test_import_export_manager_drag_and_drop_glb() -> void:
	var iem = get_node_or_null("/root/ImportExportManager")
	assert_object(iem).is_not_null()
	assert_bool(iem.has_method("_on_window_files_dropped")).is_true()
	assert_bool(iem.has_method("import_3d_model")).is_true()

	# Simular un archivo temporal .glb
	var temp_path := "user://test_drag_drop_sample.glb"
	var f := FileAccess.open(temp_path, FileAccess.WRITE)
	f.store_string("SAMPLE_GLB_DATA")
	f.close()

	var real_path := ProjectSettings.globalize_path(temp_path)
	var created_model: Node2D = iem._do_import_3d_model(real_path, Vector2(150, 250))
	assert_object(created_model).is_not_null()
	assert_bool(created_model is VectorModel3D).is_true()
	assert_str(created_model.model_path).is_equal(real_path)

	# Limpiar
	if is_instance_valid(created_model):
		created_model.free()
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(real_path)

func test_export_panel_internal_drop_glb() -> void:
	var ep_script = load("res://scenes/ui/ExportPanel.gd")
	assert_object(ep_script).is_not_null()
	var ep = auto_free(Panel.new())
	ep.set_script(ep_script)

	var temp_path := "user://test_internal_drop_sample.glb"
	var f := FileAccess.open(temp_path, FileAccess.WRITE)
	f.store_string("SAMPLE_INTERNAL_GLB")
	f.close()

	var real_path := ProjectSettings.globalize_path(temp_path)
	ep._on_element_dropped_internally(real_path, Vector2(100, 100))

	# Limpiar modelos creados en la raíz
	if get_tree() and get_tree().root:
		for child in get_tree().root.find_children("*", "VectorModel3D", true, false):
			child.free()

	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(real_path)
