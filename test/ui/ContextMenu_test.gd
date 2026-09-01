extends GdUnitTestSuite

## Menú contextual del botón derecho (tool_in_Mouse.tscn): sus botones
## Copy/Paste/Duplicate/Remove deben estar CONECTADOS a acciones reales de
## MoveTool. Antes no hacían nada.

const TOOL_IN_MOUSE := "res://scenes/ui/tool_in_mouse.tscn"
const _MENU := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/PanelContainer/VBoxContainer"

func test_botones_del_menu_contextual_estan_conectados() -> void:
	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	add_child(panel)
	await get_tree().process_frame

	for nombre in ["Paste", "Copy", "Duplicate", "Remove"]:
		var b := panel.get_node_or_null(_MENU + "/" + nombre) as Button
		assert_object(b).override_failure_message("falta botón " + nombre).is_not_null()
		# el script raíz (clickrigth_nodo.gd) conecta pressed → _on_accion
		assert_int(b.pressed.get_connections().size()) \
			.override_failure_message(nombre + " sin conexiones").is_greater(0)


func test_remove_llama_a_delete_selected_de_move_tool() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	get_tree().current_scene = s
	await get_tree().process_frame

	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	s.add_child(panel)
	await get_tree().process_frame

	var mgr := s.get_node("manager_script") as ArtboardManager
	var ab := mgr.get_active_artboard()
	var r := VectorRectangle.new()
	r.size = Vector2(40, 40)
	ab.add_child(r)
	r.global_position = Vector2(200, 200)
	await get_tree().process_frame

	var t = s.current_tool
	t.selected_shapes.assign([r])
	HistoryManager.clear()

	var remove_btn := panel.get_node(_MENU + "/Remove") as Button
	remove_btn.pressed.emit()
	await get_tree().process_frame

	assert_bool(is_instance_valid(r) and r.is_inside_tree()).is_false()
	assert_bool(HistoryManager.can_undo()).is_true()   # con undo
	assert_bool(panel.visible).is_false()              # el menú se cierra
	HistoryManager.clear()
	if is_instance_valid(r): r.free()


## El panel de trazos (Panel_trazos) aplica grosor y color a la selección
## vía InspectorCore, con undo.
const _TRAZOS := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_trazos"

func test_panel_de_trazos_aplica_grosor_y_color_con_undo() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame

	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	s.add_child(panel)
	await get_tree().process_frame

	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var r := VectorRectangle.new()
	r.size = Vector2(40, 40)
	r.stroke_width = 2.0
	r.stroke_color = Color.BLACK
	ab.add_child(r)
	r.global_position = Vector2(200, 200)
	await get_tree().process_frame

	s.current_tool.selected_shapes.assign([r])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	var sb := panel.get_node(_TRAZOS + "/MarginContainer/BoxContainer/BoxContainer2/SpinBox")
	sb.value_changed.emit(9.0)
	assert_float(r.stroke_width).is_equal_approx(9.0, 0.01)
	assert_bool(HistoryManager.can_undo()).is_true()

	var cp := panel.get_node(_TRAZOS + "/MarginContainer/BoxContainer/BoxContainer/ColorPickerButton") as ColorPickerButton
	cp.color_changed.emit(Color.RED)
	assert_that(r.stroke_color).is_equal(Color.RED)

	HistoryManager.undo(); await get_tree().process_frame
	assert_that(r.stroke_color).is_equal(Color.BLACK)
	HistoryManager.undo(); await get_tree().process_frame
	assert_float(r.stroke_width).is_equal_approx(2.0, 0.01)
	HistoryManager.clear()


## El panel de texto (Panel_tooltext) — el slider horizontal aplica font_size a
## la selección de texto vía InspectorCore, con undo.
const _TOOLTEXT := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_tooltext"

func test_panel_de_texto_slider_aplica_font_size() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame

	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	s.add_child(panel)
	await get_tree().process_frame

	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var txt := Node2D.new()
	txt.set_meta("shape_type", "text_title")
	txt.set_meta("font_size", 24)
	var dl := Label.new(); dl.name = "DisplayLabel"
	txt.add_child(dl)
	ab.add_child(txt)
	txt.global_position = Vector2(150, 150)
	await get_tree().process_frame

	s.current_tool.selected_shapes.assign([txt])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	var slider := panel.get_node(_TOOLTEXT + "/BoxContainer/Panel/Label/HSlider") as Slider
	assert_object(slider).is_not_null()
	slider.value = 72.0   # cambio discreto → apply inmediato
	await get_tree().process_frame

	assert_int(int(txt.get_meta("font_size"))).is_equal(72)
	assert_bool(HistoryManager.can_undo()).is_true()
	HistoryManager.undo(); await get_tree().process_frame
	assert_int(int(txt.get_meta("font_size"))).is_equal(24)
	HistoryManager.clear()


## El navegador de fuentes del panel de texto: lista real (FontCore) + al elegir
## una familia la aplica a la selección de texto.
const _FONT_LIST := _TOOLTEXT + "/BoxContainer/Panel/BoxContainer/Button_font/Panel_font/MarginContainer/BoxContainer/GridContainer/ScrollContainer/BoxContainer"
const _FONT_SEARCH := _TOOLTEXT + "/BoxContainer/Panel/BoxContainer/Button_font/Panel_font/MarginContainer/BoxContainer/BoxContainer/LineEdit"
const _FONT_BTN := _TOOLTEXT + "/BoxContainer/Panel/BoxContainer/Button_font"

func test_navegador_de_fuentes_lista_y_aplica() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame
	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	s.add_child(panel)
	await get_tree().process_frame

	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var txt := Node2D.new()
	txt.set_meta("shape_type", "text_title"); txt.set_meta("font_size", 24)
	txt.set_meta("font_family", "__previa__")   # distinta de "Inter" para ver el cambio
	var dl := WorldTextLabel.new(); dl.name = "DisplayLabel"; dl.text = "Aa"
	txt.add_child(dl)
	ab.add_child(txt)
	await get_tree().process_frame

	s.current_tool.selected_shapes.assign([txt])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	var list := panel.get_node_or_null(_FONT_LIST)
	assert_object(list).is_not_null()
	assert_int(list.get_child_count()).is_greater(0)   # poblada desde FontCore

	# fila "Inter" (la empaquetada siempre está)
	var fila_inter: Button = null
	for c in list.get_children():
		if c is Button and c.text == "Inter":
			fila_inter = c
	assert_object(fila_inter).is_not_null()

	fila_inter.pressed.emit()
	await get_tree().process_frame
	assert_str(str(txt.get_meta("font_family"))).is_equal("Inter")
	assert_str((panel.get_node(_FONT_BTN) as Button).text).is_equal("Inter")

	# búsqueda: filtra la lista
	var le := panel.get_node(_FONT_SEARCH) as LineEdit
	le.text = "inter"
	le.text_changed.emit("inter")
	await get_tree().process_frame
	for c in list.get_children():
		assert_str(c.text.to_lower()).contains("inter")


## Botones de alineación y estilo del panel de texto → InspectorCore / FontCore.
func test_panel_de_texto_alineacion_y_estilo() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame
	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	s.add_child(panel)
	await get_tree().process_frame

	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var txt := Node2D.new()
	txt.set_meta("shape_type", "text_title"); txt.set_meta("font_size", 24)
	txt.set_meta("text", "abc")
	var dl := Label.new(); dl.name = "DisplayLabel"; dl.text = "abc"
	txt.add_child(dl)
	ab.add_child(txt)
	await get_tree().process_frame
	s.current_tool.selected_shapes.assign([txt]); InspectorCore._sync_selection()
	HistoryManager.clear()

	var base := _TOOLTEXT + "/BoxContainer/Panel/VBoxContainer"
	# alinear al centro
	(panel.get_node(base + "/BoxContainer2/Button4") as Button).pressed.emit()
	assert_int(dl.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	# MAYÚSCULAS
	(panel.get_node(base + "/BoxContainer4/Button") as Button).pressed.emit()
	assert_str(String(txt.get_meta("text"))).is_equal("ABC")

	# estilo → Bold
	var opt := panel.get_node(_TOOLTEXT + "/BoxContainer/Panel/BoxContainer/OptionButton") as OptionButton
	for i in opt.item_count:
		if opt.get_item_text(i) == "Bold":
			opt.item_selected.emit(i)
			break
	assert_int(int(txt.get_meta("font_weight"))).is_equal(700)
	HistoryManager.clear()
