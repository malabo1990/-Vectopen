extends GdUnitTestSuite

func test_vector_rich_text_extension_registered() -> void:
	assert_bool(ClassDB.class_exists("VectorRichText")).is_true()
	var v = ClassDB.instantiate("VectorRichText")
	assert_object(v).is_not_null()
	assert_str(v.ping()).is_equal("VectopenText GDExtension v0.1.0")
	v.free()

func test_text_manipulation() -> void:
	var v = ClassDB.instantiate("VectorRichText")
	v.set_text("Hello Vectopen Publishing")
	assert_str(v.get_text()).is_equal("Hello Vectopen Publishing")
	assert_int(v.get_char_count()).is_equal(25)
	
	v.set_text("")
	assert_str(v.get_text()).is_equal("")
	assert_int(v.get_char_count()).is_equal(0)
	v.free()

func test_frame_and_paragraph_mode() -> void:
	var v = ClassDB.instantiate("VectorRichText")
	v.set_is_paragraph(true)
	assert_bool(v.get_is_paragraph()).is_true()
	
	v.set_frame_size(Vector2(300, 150))
	assert_vector(v.get_frame_size()).is_equal(Vector2(300, 150))
	
	v.set_is_paragraph(false)
	assert_bool(v.get_is_paragraph()).is_false()
	v.free()

func test_selection_and_caret() -> void:
	var v = ClassDB.instantiate("VectorRichText")
	v.set_text("Vector Typography Engine")
	
	v.start_editing()
	assert_bool(v.is_editing()).is_true()
	
	v.set_caret_index(6)
	assert_int(v.get_caret_index()).is_equal(6)
	
	v.set_selection_range(0, 6)
	assert_str(v.get_selected_text()).is_equal("Vector")
	
	v.set_selection_range(7, 17)
	assert_str(v.get_selected_text()).is_equal("Typography")
	
	v.select_all()
	assert_str(v.get_selected_text()).is_equal("Vector Typography Engine")
	
	v.deselect()
	assert_str(v.get_selected_text()).is_equal("")
	
	v.stop_editing()
	assert_bool(v.is_editing()).is_false()
	v.free()

func test_styling_and_runs_roundtrip() -> void:
	var v = ClassDB.instantiate("VectorRichText")
	v.set_text("Rust Power")
	
	# Apply red bold to "Rust"
	v.set_selection_range(0, 4)
	v.apply_bold_to_selection(true)
	v.apply_color_to_selection(Color(1, 0, 0, 1))
	
	# Apply green italic to "Power"
	v.set_selection_range(5, 10)
	v.apply_italic_to_selection(true)
	v.apply_color_to_selection(Color(0, 1, 0, 1))
	
	var runs: Array = v.get_runs_meta()
	assert_int(runs.size()).is_greater_equal(2)
	
	# Verify serialization roundtrip on a fresh instance
	var v2 = ClassDB.instantiate("VectorRichText")
	v2.set_text("Rust Power")
	v2.set_runs_meta(runs)
	var runs2: Array = v2.get_runs_meta()
	assert_int(runs2.size()).is_equal(runs.size())
	
	v.free()
	v2.free()

func test_paragraph_styling() -> void:
	var v = ClassDB.instantiate("VectorRichText")
	v.set_text("Paragraph alignment and leading test.")
	
	v.set_paragraph_align("center")
	assert_str(v.get_paragraph_align()).is_equal("center")
	
	v.set_paragraph_align("right")
	assert_str(v.get_paragraph_align()).is_equal("right")
	
	v.set_paragraph_align("justify")
	assert_str(v.get_paragraph_align()).is_equal("justify")
	
	v.set_paragraph_align("left")
	assert_str(v.get_paragraph_align()).is_equal("left")
	
	v.set_paragraph_line_spacing(12.5)
	v.set_paragraph_indents(15.0, 15.0, 30.0)
	
	v.free()

func test_overset_detection() -> void:
	var v = ClassDB.instantiate("VectorRichText")
	v.set_is_paragraph(true)
	v.set_frame_size(Vector2(50, 20))
	v.set_text("This is a very long text that definitely will exceed the tiny fifty by twenty pixel box.")
	# Overset should be true because text exceeds frame bounds
	assert_bool(v.is_overset()).is_true()
	
	# Enlarge frame: should not be overset
	v.set_frame_size(Vector2(1000, 1000))
	assert_bool(v.is_overset()).is_false()
	v.free()

# ------------------------------------------------------------------ INTEGRACIÓN
func _canvas_real() -> Node2D:
	var scene: Node2D = load("res://scenes/canvas/canvas.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	return scene

func _tool(path: String, scene: Node2D, artboard: Node2D) -> Node:
	var tool: Node = (load(path) as GDScript).new()
	add_child(tool)
	tool.set("target_artboard", artboard)
	tool.set("canvas", scene)
	return tool

func _find_shape(artboard: Node2D, prefix: String) -> Node2D:
	for child in artboard.get_children():
		if child is Node2D and child.name.begins_with(prefix):
			return child
	return null

func test_paragraph_tool_integration_attaches_and_syncs_vrt() -> void:
	var scene := await _canvas_real()
	var artboard: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _tool("res://script_gdscript/tools/ParagraphTool.gd", scene, artboard)

	tool._create_new_paragraph_at(Vector2(150, 150))
	await get_tree().process_frame

	var shape := _find_shape(artboard, "Párrafo")
	assert_object(shape).is_not_null()

	var vrt = shape.get_node_or_null("VectorRichText")
	assert_object(vrt).is_not_null()
	assert_bool(vrt.get_is_paragraph()).is_true()
	assert_str(vrt.get_text()).is_equal(shape.get_meta("text"))
	assert_object(shape.get_meta("text_color")).is_equal(Color.BLACK)
	assert_object(vrt.get_text_color()).is_equal(Color.BLACK)

	# Trigger edit
	tool._check_and_trigger_edit_at(Vector2(160, 160))
	assert_bool(vrt.is_editing()).is_true()

	# Finish edit with updated text
	vrt.set_text("Texto editado con VectorRichText")
	tool._finish_editing_and_save()
	assert_bool(vrt.is_editing()).is_false()
	assert_str(shape.get_meta("text")).is_equal("Texto editado con VectorRichText")

	scene.queue_free()

func test_text_tool_integration_attaches_and_syncs_vrt() -> void:
	var scene := await _canvas_real()
	var artboard: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _tool("res://script_gdscript/tools/TextTool.gd", scene, artboard)

	tool._create_new_title_at(Vector2(150, 150))
	await get_tree().process_frame

	var shape := _find_shape(artboard, "Texto")
	assert_object(shape).is_not_null()

	var vrt = shape.get_node_or_null("VectorRichText")
	assert_object(vrt).is_not_null()
	assert_bool(vrt.get_is_paragraph()).is_false()
	assert_str(vrt.get_text()).is_equal(shape.get_meta("text"))
	assert_object(shape.get_meta("text_color")).is_equal(Color.BLACK)
	assert_object(vrt.get_text_color()).is_equal(Color.BLACK)

	scene.queue_free()

func test_single_character_color_assignment() -> void:
	var v = ClassDB.instantiate("VectorRichText")
	v.set_text("ABC")
	
	# Select only the first character 'A' (range 0 to 1)
	v.set_selection_range(0, 1)
	v.apply_color_to_selection(Color(1, 0, 0, 1))
	
	var runs: Array = v.get_runs_meta()
	assert_int(runs.size()).is_equal(2)
	assert_int(int(runs[0]["length"])).is_equal(1)
	assert_object(runs[0]["color"]).is_equal(Color(1, 0, 0, 1))
	assert_int(int(runs[1]["length"])).is_equal(2)
	assert_object(runs[1]["color"]).is_equal(Color(0, 0, 0, 1))
	v.free()

func test_escape_signal_exits_editing_and_switches_to_move_tool() -> void:
	var scene := await _canvas_real()
	var artboard: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _tool("res://script_gdscript/tools/ParagraphTool.gd", scene, artboard)

	tool._create_new_paragraph_at(Vector2(100, 100))
	await get_tree().process_frame

	var shape := _find_shape(artboard, "Párrafo")
	assert_object(shape).is_not_null()
	var vrt = shape.get_node_or_null("VectorRichText")
	assert_object(vrt).is_not_null()

	tool._check_and_trigger_edit_at(Vector2(110, 110))
	assert_bool(tool.is_editing).is_true()
	assert_bool(vrt.is_editing()).is_true()

	# Emit editing_finished (e.g. user pressed Escape or Ctrl+Enter)
	vrt.editing_finished.emit()
	await get_tree().process_frame

	assert_bool(tool.is_editing).is_false()
	assert_bool(vrt.is_editing()).is_false()

	scene.queue_free()

func test_text_frame_extended_features() -> void:
	var v = ClassDB.instantiate("VectorRichText")
	v.set_is_paragraph(true)
	v.set_frame_size(Vector2(400, 200))
	
	# Test padding
	v.set_frame_padding(10.0, 15.0, 10.0, 15.0)
	var pad: Rect2 = v.get_frame_padding()
	assert_float(pad.position.x).is_equal(10.0)
	assert_float(pad.position.y).is_equal(15.0)
	assert_float(pad.size.x).is_equal(10.0)
	assert_float(pad.size.y).is_equal(15.0)
	
	# Test columns
	v.set_columns(2, 20.0)
	assert_int(v.get_columns()).is_equal(2)
	assert_float(v.get_column_gap()).is_equal(20.0)
	
	# Test vertical alignment
	v.set_vertical_alignment("center")
	assert_str(v.get_vertical_alignment()).is_equal("center")
	v.set_vertical_alignment("bottom")
	assert_str(v.get_vertical_alignment()).is_equal("bottom")
	v.set_vertical_alignment("top")
	assert_str(v.get_vertical_alignment()).is_equal("top")
	
	# Test overflow mode
	v.set_overflow_mode("visible")
	assert_str(v.get_overflow_mode()).is_equal("visible")
	v.set_overflow_mode("clip")
	assert_str(v.get_overflow_mode()).is_equal("clip")
	
	# Test FrameBounds vs ContentBounds
	var fb: Vector2 = v.get_frame_bounds()
	assert_vector(fb).is_equal(Vector2(400, 200))
	var cb: Vector2 = v.get_content_bounds()
	assert_float(cb.x).is_greater(0.0)
	assert_float(cb.y).is_greater(0.0)
	
	# Test interaction state
	assert_str(v.get_interaction_state()).is_equal("idle")
	v.start_editing()
	assert_str(v.get_interaction_state()).is_equal("editing")
	v.stop_editing()
	assert_str(v.get_interaction_state()).is_equal("idle")
	
	v.free()

func test_extended_character_styling() -> void:
	var v = ClassDB.instantiate("VectorRichText")
	v.set_text("Typography")
	
	# Select "Typo" (0..4) and apply opacity + strikethrough + baseline shift
	v.set_selection_range(0, 4)
	v.apply_opacity_to_selection(0.5)
	v.apply_strikethrough_to_selection(true)
	v.apply_baseline_shift_to_selection(2.5)
	v.apply_letter_spacing_to_selection(1.2)
	
	var runs: Array = v.get_runs_meta()
	assert_int(runs.size()).is_equal(2)
	assert_float(float(runs[0]["opacity"])).is_equal_approx(0.5, 0.01)
	assert_bool(bool(runs[0]["strikethrough"])).is_true()
	assert_float(float(runs[0]["baseline_shift"])).is_equal_approx(2.5, 0.01)
	assert_float(float(runs[0]["letter_spacing"])).is_equal_approx(1.2, 0.01)
	
	# Second run "graphy" should have default opacity 1.0 and no strikethrough
	assert_float(float(runs[1]["opacity"])).is_equal_approx(1.0, 0.01)
	assert_bool(bool(runs[1]["strikethrough"])).is_false()
	
	v.free()

func test_paragraph_tool_commit_text_edit_safe() -> void:
	var pt = load("res://script_gdscript/tools/ParagraphTool.gd").new()
	assert_str(pt.interaction_state).is_equal("idle")
	assert_bool(pt.is_editing).is_false()
	pt.commit_text_edit(false)
	assert_str(pt.interaction_state).is_equal("idle")
	pt.free()

func test_multi_click_and_word_paragraph_selection() -> void:
	var v = ClassDB.instantiate("VectorRichText")
	v.set_is_paragraph(true)
	v.set_frame_size(Vector2(400, 300))
	v.set_text("Primer párrafo.\nSegundo párrafo con palabras.\nTercer párrafo.")
	
	# Test word selection via select_word_at
	v.start_editing()
	v.select_word_at(0)
	assert_str(v.get_selected_text()).is_equal("Primer")
	
	v.select_word_at(7)
	assert_str(v.get_selected_text()).is_equal("párrafo")
	
	# Test paragraph selection via select_paragraph_at
	v.select_paragraph_at(5)
	assert_str(v.get_selected_text()).is_equal("Primer párrafo.")
	
	v.select_paragraph_at(20)
	assert_str(v.get_selected_text()).is_equal("Segundo párrafo con palabras.")
	
	# Test word navigation
	v.set_caret_index(0)
	v.move_by_word(true, false)
	assert_int(v.get_caret_index()).is_equal(6) # end of "Primer"
	
	# Test hit_test
	var char_at_origin: int = v.hit_test(Vector2(5, 5))
	assert_int(char_at_origin).is_greater_equal(0)
	
	v.free()

func test_insert_delete_replace_range_api() -> void:
	var v = ClassDB.instantiate("VectorRichText")
	v.set_text("Alpha Gamma")
	
	# Replace "Gamma" with "Beta"
	v.replace_range(6, 11, "Beta")
	assert_str(v.get_text()).is_equal("Alpha Beta")
	
	# Insert " Super" at index 5
	v.set_caret_index(5)
	v.insert_text(" Super")
	assert_str(v.get_text()).is_equal("Alpha Super Beta")
	
	# Delete " Super"
	v.delete_range(5, 11)
	assert_str(v.get_text()).is_equal("Alpha Beta")
	
	# Test selection alias
	v.set_selection(0, 5)
	var sel: Vector2i = v.get_selection()
	assert_int(sel.x).is_equal(0)
	assert_int(sel.y).is_equal(5)
	assert_str(v.get_selected_text()).is_equal("Alpha")
	
	# Test commit and cancel aliases
	v.start_editing()
	assert_bool(v.is_editing()).is_true()
	v.commit_editing()
	assert_bool(v.is_editing()).is_false()
	
	v.start_editing()
	assert_bool(v.is_editing()).is_true()
	v.cancel_editing()
	assert_bool(v.is_editing()).is_false()
	
	v.free()

func test_multi_column_reflow_and_hit_test() -> void:
	if not ClassDB.class_exists("VectorRichText"):
		return
	var v = ClassDB.instantiate("VectorRichText")
	v.set_is_paragraph(true)
	v.set_font_size(16.0)
	v.set_frame_size(Vector2(400, 100))
	v.set_columns(2, 20.0)
	
	v.set_text("First column text that wraps nicely. More words here to fill the first column completely. Second column starts here and continues with more content across the column.")
	
	assert_int(v.get_columns()).is_equal(2)
	assert_float(v.get_column_gap()).is_equal(20.0)
	assert_int(v.get_line_count()).is_greater(2)
	
	var r0: Rect2 = v.get_line_rect(0)
	assert_float(r0.position.x).is_less(100.0)
	
	var found_col2: bool = false
	for i in range(v.get_line_count()):
		var r: Rect2 = v.get_line_rect(i)
		if r.position.x >= 180.0:
			found_col2 = true
			break
	assert_bool(found_col2).is_true()
	
	var idx1: int = v.hit_test(Vector2(50, 10))
	var idx2: int = v.hit_test(Vector2(250, 10))
	assert_int(idx2).is_greater(idx1)
	
	v.set_frame_size(Vector2(400, 30))
	assert_bool(v.is_overset()).is_true()
	
	v.set_frame_size(Vector2(400, 1000))
	assert_bool(v.is_overset()).is_false()
	
	v.free()




