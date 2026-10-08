# =============================================================================
# VECTOPEN — PRUEBAS DE FORMATEO INTERACTIVO Y ATAJOS EN EL LIENZO (FASE 3)
# RUTA: res://test/tools/TextInteractiveFormatting_test.gd
# =============================================================================
extends GdUnitTestSuite

const TextToolScript := preload("res://script_gdscript/tools/TextTool.gd")
const ParagraphToolScript := preload("res://script_gdscript/tools/ParagraphTool.gd")

func test_text_tool_live_shortcuts() -> void:
	var tool_instance = auto_free(TextToolScript.new())
	
	# Crear figura de prueba
	var shape := Node2D.new()
	shape.set_meta("shape_type", "text_title")
	shape.set_meta("text", "Vectopen Vector")
	shape.set_meta("font_size", 24)
	add_child(shape)
	auto_free(shape)

	var dl := WorldTextLabel.new()
	dl.name = "DisplayLabel"
	dl.text = "Vectopen Vector"
	shape.add_child(dl)

	var ed := TextEdit.new()
	ed.name = "TitleEdit"
	ed.text = "Vectopen Vector"
	shape.add_child(ed)

	tool_instance.is_editing = true
	tool_instance.current_editing_shape = shape

	# Seleccionar la palabra "Vectopen" (0..8)
	ed.select(0, 0, 0, 8)

	# Simular atajo Ctrl+B (Negrita)
	var ev_b := InputEventKey.new()
	ev_b.pressed = true
	ev_b.keycode = KEY_B
	ev_b.ctrl_pressed = true
	tool_instance._on_title_edit_gui_input(ev_b)

	var runs: Array = shape.get_meta("runs", [])
	assert_int(runs.size()).is_equal(2)
	assert_int(int(runs[0]["length"])).is_equal(8)
	assert_bool(bool(runs[0]["bold"])).is_true()
	assert_bool(bool(runs[1]["bold"])).is_false()

	# Simular atajo Ctrl+I (Cursiva) sobre el mismo rango
	var ev_i := InputEventKey.new()
	ev_i.pressed = true
	ev_i.keycode = KEY_I
	ev_i.ctrl_pressed = true
	tool_instance._on_title_edit_gui_input(ev_i)

	runs = shape.get_meta("runs", [])
	assert_bool(bool(runs[0]["italic"])).is_true()

	# Simular atajo Ctrl+U (Subrayado) sobre el mismo rango
	var ev_u := InputEventKey.new()
	ev_u.pressed = true
	ev_u.keycode = KEY_U
	ev_u.ctrl_pressed = true
	tool_instance._on_title_edit_gui_input(ev_u)

	runs = shape.get_meta("runs", [])
	assert_bool(bool(runs[0]["underline"])).is_true()

	# Simular paso de tamaño de fuente (+4 pt)
	tool_instance._on_format_size_step(4.0)
	runs = shape.get_meta("runs", [])
	assert_float(float(runs[0]["size"])).is_equal_approx(28.0, 0.01)

func test_paragraph_tool_live_shortcuts() -> void:
	var tool_instance = auto_free(ParagraphToolScript.new())
	
	var shape := Node2D.new()
	shape.set_meta("shape_type", "text_paragraph")
	shape.set_meta("text", "Parrafo de Prueba")
	shape.set_meta("font_size", 20)
	add_child(shape)
	auto_free(shape)

	var dl := WorldTextLabel.new()
	dl.name = "DisplayLabel"
	dl.text = "Parrafo de Prueba"
	shape.add_child(dl)

	var ed := TextEdit.new()
	ed.name = "MultiLineEdit"
	ed.text = "Parrafo de Prueba"
	shape.add_child(ed)

	tool_instance.is_editing = true
	tool_instance.current_editing_shape = shape

	# Seleccionar la palabra "Parrafo" (0..7)
	ed.select(0, 0, 0, 7)

	# Simular atajo Ctrl+B
	var ev_b := InputEventKey.new()
	ev_b.pressed = true
	ev_b.keycode = KEY_B
	ev_b.ctrl_pressed = true
	tool_instance._on_multi_edit_gui_input(ev_b)

	var runs: Array = shape.get_meta("runs", [])
	assert_int(runs.size()).is_equal(2)
	assert_int(int(runs[0]["length"])).is_equal(7)
	assert_bool(bool(runs[0]["bold"])).is_true()
	assert_bool(bool(runs[1]["bold"])).is_false()

	# Simular atajo Ctrl+U
	var ev_u := InputEventKey.new()
	ev_u.pressed = true
	ev_u.keycode = KEY_U
	ev_u.ctrl_pressed = true
	tool_instance._on_multi_edit_gui_input(ev_u)

	runs = shape.get_meta("runs", [])
	assert_bool(bool(runs[0]["underline"])).is_true()

func test_caret_changed_signal_connection() -> void:
	var text_tool = auto_free(TextToolScript.new())
	var para_tool = auto_free(ParagraphToolScript.new())
	
	var t_edit = auto_free(TextEdit.new())
	var p_edit = auto_free(TextEdit.new())
	
	assert_bool(t_edit.has_signal("caret_changed")).is_true()
	assert_bool(p_edit.has_signal("caret_changed")).is_true()
	
	t_edit.caret_changed.connect(text_tool._on_title_edit_caret_changed)
	p_edit.caret_changed.connect(para_tool._on_multi_edit_caret_changed)
	
	t_edit.emit_signal("caret_changed")
	p_edit.emit_signal("caret_changed")

func test_inline_editor_expansion_and_highlighter() -> void:
	var tool_instance = auto_free(TextToolScript.new())
	
	var shape := Node2D.new()
	shape.set_meta("shape_type", "text_title")
	shape.set_meta("text", "Título Inicial")
	shape.set_meta("font_size", 24)
	add_child(shape)
	auto_free(shape)

	var dl := WorldTextLabel.new()
	dl.name = "DisplayLabel"
	dl.base_font_size = 24
	dl.text = "Título Inicial"
	shape.add_child(dl)

	var ed := TextEdit.new()
	ed.name = "TitleEdit"
	ed.text = "Título Inicial"
	shape.add_child(ed)

	tool_instance._style_title_edit(ed, dl)
	var sb := ed.get_theme_stylebox("normal") as StyleBoxFlat
	assert_object(sb).is_not_null()
	assert_float(sb.content_margin_left).is_equal(0.0)
	assert_float(sb.content_margin_right).is_equal(0.0)

	tool_instance.is_editing = true
	tool_instance.current_editing_shape = shape

	# Escribir texto largo: debe expandir el ancho dinámicamente sin topar en 200px
	var texto_muy_largo := "Este es un título corporativo sumamente largo para verificar que ninguna letra se corta jamás"
	ed.text = texto_muy_largo
	tool_instance._on_edit_text_changed()

	assert_that(ed.size.x).is_greater(400.0)
	assert_that(shape.get_meta("width")).is_equal(ed.size.x)

	# Aplicar color a un rango (0..10) y validar que el SyntaxHighlighter coloree
	ed.select(0, 0, 0, 10)
	tool_instance._on_format_color_changed(Color.RED)

	assert_object(ed.syntax_highlighter).is_not_null()
	var hl_data: Dictionary = ed.syntax_highlighter.get_line_syntax_highlighting(0)
	assert_bool(hl_data.has(0)).is_true()
	assert_that(hl_data[0]["color"]).is_equal(Color.RED)

