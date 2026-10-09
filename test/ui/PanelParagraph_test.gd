# =============================================================================
# VECTOPEN — PRUEBAS DE PANEL DE PÁRRAFO Y CARÁCTER (FASE 2)
# RUTA: res://test/ui/PanelParagraph_test.gd
# =============================================================================
extends GdUnitTestSuite

const PanelParagraphScript := preload("res://script_gdscript/ui/panel_paragraph.gd")

const TextFormat := preload("res://script_gdscript/text/text_format.gd")

## Panel Texto = solo PÁRRAFO y MARCO (el carácter vive en Tipografía).
func test_panel_paragraph_widgets_initialization() -> void:
	var panel = auto_free(PanelParagraphScript.new())
	add_child(panel)
	await get_tree().process_frame

	assert_int(panel._align_btns.size()).is_equal(4)
	assert_int(panel._valign_btns.size()).is_equal(3)
	for prop in ["indent_left", "indent_right", "indent_first", "width", "height", "columns", "column_gap"]:
		assert_bool(panel._fields.has(prop)).override_failure_message("falta %s" % prop).is_true()
	# Nada de carácter: no se repite con el panel Tipografía
	for prop in ["font_size", "line_spacing", "letter_spacing", "font_family", "fill_color"]:
		assert_bool(panel._fields.has(prop)).override_failure_message("%s no debe estar en el panel Texto" % prop).is_false()
	assert_bool("_btn_bold" in panel).is_false()

func test_panel_paragraph_sync_from_props() -> void:
	var panel = auto_free(PanelParagraphScript.new())
	add_child(panel)
	await get_tree().process_frame

	var mock_props := {
		"text_align": {"value": "center", "mixed": false},
		"text_valign": {"value": "middle", "mixed": false},
		"columns": {"value": 3.0, "mixed": false},
		"column_gap": {"value": 25.0, "mixed": false},
		"indent_left": {"value": 12.0, "mixed": false},
		"width": {"value": 300.0, "mixed": true},
	}
	panel._sync(mock_props)

	assert_bool(panel._align_btns[1].button_pressed).is_true() # center
	assert_bool(panel._valign_btns[1].button_pressed).is_true() # middle
	assert_float(panel._fields["columns"].value).is_equal_approx(3.0, 0.01)
	assert_float(panel._fields["column_gap"].value).is_equal_approx(25.0, 0.01)
	assert_float(panel._fields["indent_left"].value).is_equal_approx(12.0, 0.01)
	assert_bool(panel._fields["width"].is_mixed()).is_true()
	assert_bool(panel._fields["height"].is_mixed()).is_true()   # sin dato → "—"

func test_text_format_range_with_mock_editing() -> void:
	var shape := Node2D.new()
	shape.set_meta("shape_type", "text_paragraph")
	shape.set_meta("text", "Hola Mundo")
	add_child(shape)
	auto_free(shape)

	var dl := WorldTextLabel.new()
	dl.name = "DisplayLabel"
	dl.text = "Hola Mundo"
	shape.add_child(dl)

	var ed := TextEdit.new()
	ed.name = "MultiLineEdit"
	ed.text = "Hola Mundo"
	shape.add_child(ed)
	ed.syntax_highlighter = WorldTextLabel.RunHighlighter.new(shape)

	# Aplicar formato a un rango (índices 0..4 = "Hola")
	TextFormat.apply_to_range(shape, ed, 0, 4, func(r: Dictionary) -> Dictionary:
		r["color"] = Color.BLUE
		r["bold"] = true
		r["stroke_width"] = 2.0
		r["stroke_color"] = Color.YELLOW
		return r)

	var runs: Array = shape.get_meta("runs", [])
	assert_int(runs.size()).is_equal(2)

	# Run 1: "Hola" (longitud 4)
	assert_int(int(runs[0]["length"])).is_equal(4)
	assert_object(runs[0]["color"]).is_equal(Color.BLUE)
	assert_bool(bool(runs[0]["bold"])).is_true()
	assert_float(float(runs[0]["stroke_width"])).is_equal_approx(2.0, 0.01)
	assert_object(runs[0]["stroke_color"]).is_equal(Color.YELLOW)

	# Run 2: " Mundo" (longitud 6)
	assert_int(int(runs[1]["length"])).is_equal(6)
	assert_bool(bool(runs[1]["bold"])).is_false()

	# El SyntaxHighlighter del TextEdit refleja los colores en vivo
	var hl_dict: Dictionary = ed.syntax_highlighter.get_line_syntax_highlighting(0)
	assert_bool(hl_dict.has(0)).is_true()
	assert_object(hl_dict[0]["color"]).is_equal(Color.BLUE)
	assert_bool(hl_dict.has(4)).is_true()
	assert_object(hl_dict[4]["color"]).is_equal(Color.BLACK)

func test_panel_text_scene_contains_paragraph_config() -> void:
	var p_scene = auto_free(load("res://scenes/ui/panels/panel_text.tscn").instantiate())
	add_child(p_scene)
	await get_tree().process_frame

	var cfg = PanelParagraphScript.find_in(p_scene)
	assert_object(cfg).is_not_null()
	assert_bool(cfg.visible).is_true()

func test_inspector_core_columns_and_gap_syncs_vrt() -> void:
	if not ClassDB.class_exists("VectorRichText"):
		return
	var ic = get_node_or_null("/root/InspectorCore")
	if not ic:
		return
	
	var shape := Node2D.new()
	shape.set_meta("shape_type", "text_paragraph")
	shape.set_meta("text", "Col 1 text. Col 2 text.")
	add_child(shape)
	auto_free(shape)
	
	var vrt = ClassDB.instantiate("VectorRichText")
	vrt.name = "VectorRichText"
	vrt.set_is_paragraph(true)
	vrt.set_frame_size(Vector2(400, 100))
	shape.add_child(vrt)
	
	var sm = get_node_or_null("/root/SelectionManager")
	if sm and sm.has_method("select"):
		sm.select(shape)
	
	ic.apply("columns", 3)
	assert_int(int(shape.get_meta("columns", 1))).is_equal(3)
	assert_int(vrt.get_columns()).is_equal(3)
	
	ic.apply("column_gap", 24.0)
	assert_float(float(shape.get_meta("column_gap", 0.0))).is_equal_approx(24.0, 0.01)
	assert_float(vrt.get_column_gap()).is_equal_approx(24.0, 0.01)


