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

	var sb := panel.get_node_or_null(_TRAZOS + "/MarginContainer/BoxContainer/RowGrosor/SpinBox")
	if sb == null:
		sb = panel.find_child("SpinBox", true, false)
	sb.value_changed.emit(9.0)
	assert_float(r.stroke_width).is_equal_approx(9.0, 0.01)
	assert_bool(HistoryManager.can_undo()).is_true()

	var cp := panel.get_node_or_null(_TRAZOS + "/MarginContainer/BoxContainer/RowColor/ColorPickerButton") as ColorPickerButton
	if cp == null:
		cp = panel.find_child("ColorPickerButton", true, false) as ColorPickerButton
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


## ── Pruebas de Inicio y Alineación Mejorados ──────────────────────────────
const _TAB_BAR_PATH := "PanelContainer/MarginContainer/VBoxContainer/button_tab_tools2"
const _ALINEACION_BASE := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/TOOLS ALINEACION/VBoxContainer"

func test_panel_inicio_iconos_y_estilos() -> void:
	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())

	var remove_btn := panel.get_node(_MENU + "/Remove") as Button
	assert_object(remove_btn).is_not_null()
	assert_object(remove_btn.icon).is_not_null()
	assert_str(remove_btn.icon.resource_path).contains("trash.svg")
	assert_str(remove_btn.icon.resource_path).not_contains("dribbble.svg")

	var dup_btn := panel.get_node(_MENU + "/Duplicate") as Button
	assert_object(dup_btn).is_not_null()
	assert_object(dup_btn.icon).is_not_null()
	assert_str(dup_btn.icon.resource_path).contains("copy.svg")
	assert_str(dup_btn.icon.resource_path).not_contains("dribbble.svg")

	var name_btn := panel.get_node(_MENU + "/name") as Button
	assert_str(name_btn.text.strip_edges()).is_equal("Name")

	var rename_btn := panel.get_node(_MENU + "/Button6") as Button
	assert_str(rename_btn.text.strip_edges()).is_equal("Rename")
	assert_object(rename_btn.icon).is_not_null()
	assert_str(rename_btn.icon.resource_path).contains("pencil")

	# Verificar que entra al árbol e inicializa correctamente
	add_child(panel)
	await get_tree().process_frame
	assert_object(remove_btn.icon).is_not_null()


func test_panel_alineacion_botones_y_operaciones() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame

	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	s.add_child(panel)
	await get_tree().process_frame

	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var r1 := VectorRectangle.new()
	r1.size = Vector2(40, 40)
	ab.add_child(r1)
	r1.global_position = Vector2(100, 100)

	var r2 := VectorRectangle.new()
	r2.size = Vector2(40, 40)
	ab.add_child(r2)
	r2.global_position = Vector2(250, 200)
	await get_tree().process_frame

	s.current_tool.selected_shapes.assign([r1, r2])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	# Probar Alinear Izquierda desde HBoxContainer4/Button
	var btn_left := panel.get_node(_ALINEACION_BASE + "/HBoxContainer4/Button") as Button
	assert_object(btn_left).is_not_null()
	assert_int(btn_left.pressed.get_connections().size()).is_greater(0)
	btn_left.pressed.emit()
	await get_tree().process_frame

	# En multiselección, ambos se alinean al borde izquierdo del bounding box (x=100)
	assert_float(r1.global_position.x).is_equal_approx(100.0, 0.5)
	assert_float(r2.global_position.x).is_equal_approx(100.0, 0.5)
	assert_bool(HistoryManager.can_undo()).is_true()

	HistoryManager.undo()
	await get_tree().process_frame
	assert_float(r2.global_position.x).is_equal_approx(250.0, 0.5)

	# Probar Alinear Arriba desde HBoxContainer5/Button
	var btn_top := panel.get_node(_ALINEACION_BASE + "/HBoxContainer5/Button") as Button
	assert_object(btn_top).is_not_null()
	assert_int(btn_top.pressed.get_connections().size()).is_greater(0)
	btn_top.pressed.emit()
	await get_tree().process_frame

	assert_float(r1.global_position.y).is_equal_approx(100.0, 0.5)
	assert_float(r2.global_position.y).is_equal_approx(100.0, 0.5)

	# Probar matriz 4x4 elegante: Botón esquina superior izquierda (Button)
	var grid_btn := panel.get_node(_ALINEACION_BASE + "/BoxContainer/GridContainer/Button") as Button
	assert_object(grid_btn).is_not_null()
	assert_int(grid_btn.pressed.get_connections().size()).is_greater(0)
	assert_object(grid_btn.get_node_or_null("ColorRect")).is_not_null()

	# Botón esquina inferior derecha: Alinear a Todo Tamaño (Button17)
	var btn_full := panel.get_node(_ALINEACION_BASE + "/BoxContainer/GridContainer/Button17") as Button
	assert_object(btn_full).is_not_null()
	assert_int(btn_full.pressed.get_connections().size()).is_greater(0)
	btn_full.pressed.emit()
	await get_tree().process_frame

	assert_bool(r1.has_meta("anchor_preset")).is_true()
	assert_str(r1.get_meta("anchor_preset")).is_equal("full_rect")

	HistoryManager.clear()


func test_tab_bar_iconos_y_cambio_de_pestana() -> void:
	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	add_child(panel)
	await get_tree().process_frame

	var tab_align := panel.get_node(_TAB_BAR_PATH + "/Button2") as Button
	assert_object(tab_align).is_not_null()
	assert_str(tab_align.icon.resource_path).contains("align_center_h_pro.svg")
	assert_str(tab_align.icon.resource_path).not_contains("exclude.svg")


## ── Pruebas de Proporción de Letras (Aaa, aAa, aaA, AaA y sliders) ───────────
const _PROP_BOX := _TOOLTEXT + "/BoxContainer/Panel/VBoxContainer/BoxContainer5"
const _PROP_SLIDERS_BOX := _TOOLTEXT + "/BoxContainer/Panel/VBoxContainer/HBoxContainer"

func test_panel_tipografia_botones_proporcion_y_sliders() -> void:
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
	txt.set_meta("text", "Vectopen")
	var dl := WorldTextLabel.new()
	dl.name = "DisplayLabel"
	dl.text = "Vectopen"
	txt.add_child(dl)
	ab.add_child(txt)
	await get_tree().process_frame

	s.current_tool.selected_shapes.assign([txt])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	# 1. Verificar botones de proporción
	var btn_aaa := panel.get_node(_PROP_BOX + "/Button") as Button
	var btn_aaa_mid := panel.get_node(_PROP_BOX + "/Button4") as Button
	assert_object(btn_aaa).is_not_null()
	assert_object(btn_aaa_mid).is_not_null()
	assert_str(btn_aaa.text).is_equal("Aaa")
	assert_str(btn_aaa_mid.text).is_equal("aAa")

	# Pulsar Aaa (decreciente)
	btn_aaa.pressed.emit()
	await get_tree().process_frame

	assert_bool(txt.has_meta("letter_proportions")).is_true()
	var prop_dict: Dictionary = txt.get_meta("letter_proportions")
	assert_str(str(prop_dict.get("mode", ""))).is_equal("Aaa")
	assert_float(float(prop_dict.get("start", 0.0))).is_equal_approx(1.6, 0.01)
	assert_float(float(prop_dict.get("end", 0.0))).is_equal_approx(0.4, 0.01)
	assert_bool(dl.has_letter_proportions()).is_true()

	# 2. Verificar 4 sliders vinculados
	var slider_start := panel.get_node(_PROP_SLIDERS_BOX + "/HSlider") as Slider
	var slider_mid := panel.get_node(_PROP_SLIDERS_BOX + "/HSlider2") as Slider
	var slider_mid2 := panel.get_node(_PROP_SLIDERS_BOX + "/HSlider3") as Slider
	var slider_end := panel.get_node(_PROP_SLIDERS_BOX + "/HSlider4") as Slider
	assert_object(slider_start).is_not_null()
	assert_object(slider_mid).is_not_null()
	assert_object(slider_mid2).is_not_null()
	assert_object(slider_end).is_not_null()
	assert_float(slider_start.value).is_equal_approx(1.6, 0.01)

	# Cambiar slider de inicio a 1.8
	slider_start.value = 1.8
	await get_tree().process_frame
	var prop_updated: Dictionary = txt.get_meta("letter_proportions")
	assert_float(float(prop_updated.get("start", 0.0))).is_equal_approx(1.8, 0.01)

	# Pulsar aAa (medio grande, extremos pequeños)
	btn_aaa_mid.pressed.emit()
	await get_tree().process_frame
	var prop_mid: Dictionary = txt.get_meta("letter_proportions")
	assert_str(str(prop_mid.get("mode", ""))).is_equal("aAa")
	assert_float(float(prop_mid.get("mid", 0.0))).is_equal_approx(1.4, 0.01)

	# Probar Undo
	assert_bool(HistoryManager.can_undo()).is_true()
	HistoryManager.undo()
	await get_tree().process_frame
	var prop_undo: Dictionary = txt.get_meta("letter_proportions")
	assert_str(str(prop_undo.get("mode", ""))).is_equal("Aaa")

	HistoryManager.clear()

func test_world_text_label_proporciones_escalado() -> void:
	var l := WorldTextLabel.new()
	l.base_font_size = 24
	l.text = "ABCDEFG"
	add_child(l)
	auto_free(l)
	await get_tree().process_frame

	l.set_letter_proportions({"mode": "Aaa", "start": 1.5, "mid": 0.8, "end": 0.4})
	assert_bool(l.has_letter_proportions()).is_true()
	assert_float(l.visible_ratio).is_equal_approx(0.0, 0.01)

	var out: Node2D = l.build_outline_path()
	if out != null:
		assert_int(out.get_child_count()).is_greater(0)
		out.free()

	# Desactivar proporciones
	l.set_letter_proportions({})
	assert_bool(l.has_letter_proportions()).is_false()
	assert_float(l.visible_ratio).is_equal_approx(1.0, 0.01)


func test_button_configuration_toggles_theme_config_panel() -> void:
	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	add_child(panel)
	await get_tree().process_frame

	var cfg_btn := panel.get_node_or_null("Button_configuration") as Button
	assert_object(cfg_btn).override_failure_message("Falta Button_configuration en tool_in_mouse").is_not_null()

	var tcp := panel.get_node_or_null("ThemeConfigPanel") as Control
	assert_object(tcp).override_failure_message("Falta ThemeConfigPanel en tool_in_mouse").is_not_null()

	# Estado inicial: oculto
	assert_bool(tcp.visible).is_false()

	# Primer toggle: se abre
	cfg_btn.pressed.emit()
	assert_bool(tcp.visible).is_true()

	# Segundo toggle: se cierra
	cfg_btn.pressed.emit()
	assert_bool(tcp.visible).is_false()

	# Probar cierre con el botón ✕ del panel
	cfg_btn.pressed.emit()
	assert_bool(tcp.visible).is_true()
	var close_btn := tcp.get_node_or_null("MarginContainer/VBoxContainer/Header/ButtonClose") as Button
	if close_btn:
		close_btn.pressed.emit()
		assert_bool(tcp.visible).is_false()


## Verifica que Panel_color contenga pickr Y el grid de muestras Colorpack (32 muestras),
## y que al pulsar una muestra se aplique el color a la selección vía ColorCore/InspectorCore.
func test_grid_color_muestras_y_panel_color() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame

	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	s.add_child(panel)
	await get_tree().process_frame

	var panel_color := panel.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_color")
	assert_object(panel_color).override_failure_message("Falta Panel_color en tool_in_mouse").is_not_null()

	var pickr := panel_color.get_node_or_null("VBoxContainer/pickr")
	assert_object(pickr).override_failure_message("Falta pickr dentro de Panel_color").is_not_null()

	var colorpack := panel_color.get_node_or_null("VBoxContainer/Colorpack")
	assert_object(colorpack).override_failure_message("Falta Colorpack (Grid Color) dentro de Panel_color").is_not_null()

	var flow := colorpack.get_node_or_null("VBoxContainer/VBoxContainer/FlowContainer")
	assert_object(flow).override_failure_message("Falta FlowContainer con ListaColor.gd en Colorpack").is_not_null()
	assert_int(flow.get_child_count()).is_equal(32)

	# Crear un rectángulo en el artboard para probar la aplicación directa de una muestra
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var rect := VectorRectangle.new()
	rect.size = Vector2(80, 80)
	rect.fill_color = Color.BLACK
	ab.add_child(rect)
	await get_tree().process_frame

	s.current_tool.selected_shapes.assign([rect])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	# Clic en una muestra de color de Colorpack
	var muestra: ColorRect = flow.get_child(0) as ColorRect
	assert_object(muestra).is_not_null()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	muestra.gui_input.emit(ev)
	await get_tree().process_frame

	assert_that(rect.fill_color).is_equal(muestra.color)
	assert_bool(HistoryManager.can_undo()).is_true()

	HistoryManager.undo()
	await get_tree().process_frame
	assert_that(rect.fill_color).is_equal(Color.BLACK)
	HistoryManager.clear()


## Verifica que al conmutar a degradado Lineal o Radial desde pickr, se aplique
## automáticamente a la selección sin bucles infinitos ni salidas/cuelgues (0 errores/salidas).
func test_degradado_automatico_sin_salida() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame

	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	s.add_child(panel)
	await get_tree().process_frame

	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var rect := VectorRectangle.new()
	rect.size = Vector2(100, 100)
	rect.fill_color = Color.RED
	ab.add_child(rect)
	await get_tree().process_frame

	s.current_tool.selected_shapes.assign([rect])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	var pickr := panel.get_node("PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_color/VBoxContainer/pickr") as GestorColor
	assert_object(pickr).is_not_null()

	# Conmutar a degradado Lineal
	pickr.tab_linear.pressed.emit()
	await get_tree().process_frame

	assert_str(pickr.current_tab).is_equal("linear")
	assert_bool(rect.has_gradient_fill()).is_true()
	assert_int(rect.fill_gradient_type).is_equal(0)
	assert_bool(pickr.gradient_editor.visible).is_true()

	# Conmutar a degradado Radial
	pickr.tab_radial.pressed.emit()
	await get_tree().process_frame

	assert_str(pickr.current_tab).is_equal("radial")
	assert_bool(rect.has_gradient_fill()).is_true()
	assert_int(rect.fill_gradient_type).is_equal(1)

	# Conmutar de vuelta a Sólido
	pickr.tab_solid.pressed.emit()
	await get_tree().process_frame

	assert_str(pickr.current_tab).is_equal("solid")
	assert_bool(rect.has_gradient_fill()).is_false()
	assert_bool(pickr.gradient_editor.visible).is_false()

	HistoryManager.clear()


## Verifica que al cambiar el color del picker mientras se edita un degradado,
## se actualice la parada del degradado y NO salte abruptamente a modo sólido.
func test_color_picker_en_degradado_no_salta_a_solido() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame

	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	s.add_child(panel)
	await get_tree().process_frame

	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var rect := VectorRectangle.new()
	rect.size = Vector2(100, 100)
	rect.fill_color = Color.RED
	ab.add_child(rect)
	await get_tree().process_frame

	s.current_tool.selected_shapes.assign([rect])
	InspectorCore._sync_selection()
	HistoryManager.clear()

	var pickr := panel.get_node("PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_color/VBoxContainer/pickr") as GestorColor
	assert_object(pickr).is_not_null()

	# Conmutar a degradado Lineal
	pickr.tab_linear.pressed.emit()
	await get_tree().process_frame
	assert_str(pickr.current_tab).is_equal("linear")

	# Simular selección de color en el picker panel
	if is_instance_valid(pickr.picker_panel):
		pickr.picker_panel.color_changed.emit(Color(0.2, 0.4, 0.8, 1.0))
		await get_tree().process_frame

	# Debe permanecer en modo lineal y mantener el degradado activo
	assert_str(pickr.current_tab).is_equal("linear")
	assert_bool(rect.has_gradient_fill()).is_true()
	assert_bool(pickr.gradient_editor.visible).is_true()

	HistoryManager.clear()


## Verifica que Panel_color tenga sub-pestañas "Selector" y "Muestras" y conmute entre pickr y Colorpack.
func test_panel_color_sub_tabs_toggle() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame

	var panel: Control = auto_free(load(TOOL_IN_MOUSE).instantiate())
	s.add_child(panel)
	await get_tree().process_frame

	var panel_color := panel.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_color")
	assert_object(panel_color).is_not_null()

	var tabs_bar := panel_color.get_node_or_null("TabsBar")
	assert_object(tabs_bar).override_failure_message("Falta TabsBar en Panel_color").is_not_null()

	var btn_picker := tabs_bar.get_node_or_null("BtnPicker") as Button
	var btn_grid := tabs_bar.get_node_or_null("BtnGrid") as Button
	assert_object(btn_picker).is_not_null()
	assert_object(btn_grid).is_not_null()

	var pickr := panel_color.get_node_or_null("VBoxContainer/pickr")
	var colorpack := panel_color.get_node_or_null("VBoxContainer/Colorpack")
	assert_object(pickr).is_not_null()
	assert_object(colorpack).is_not_null()

	# Al inicio, Selector está visible y Muestras oculto
	assert_bool(pickr.visible).is_true()
	assert_bool(colorpack.visible).is_false()

	# Clic en Muestras
	btn_grid.pressed.emit()
	await get_tree().process_frame
	assert_bool(pickr.visible).is_false()
	assert_bool(colorpack.visible).is_true()

	# Clic en Selector
	btn_picker.pressed.emit()
	await get_tree().process_frame
	assert_bool(pickr.visible).is_true()
	assert_bool(colorpack.visible).is_false()


## Verifica que los botones de alineación horizontal y vertical en panel_tooltext
## NO desaparezcan al hacer clic y que los iconos de alineación vertical sean los de texto tipo Figma/Penpot.
func test_panel_tooltext_align_buttons_remain_visible_on_click() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame

	var panel: Control = auto_free(load("res://scenes/ui/panel_tooltext.tscn").instantiate())
	s.add_child(panel)
	await get_tree().process_frame

	# 1. Comprobar botones horizontales
	var h_container := panel.get_node_or_null("BoxContainer/Panel/VBoxContainer/BoxContainer2")
	assert_object(h_container).override_failure_message("Falta BoxContainer2 en panel_tooltext").is_not_null()
	var h_buttons: Array[Button] = []
	for child in h_container.get_children():
		if child is Button:
			h_buttons.append(child)
	assert_int(h_buttons.size()).is_equal(4)

	# Probar clic en cada botón horizontal y asegurar que TODOS siguen visibles
	for btn in h_buttons:
		btn.pressed.emit()
		await get_tree().process_frame
		for check_btn in h_buttons:
			assert_bool(check_btn.visible).override_failure_message("El botón %s desapareció tras pulsar %s" % [check_btn.name, btn.name]).is_true()

	# 2. Comprobar botones verticales
	var v_container := panel.get_node_or_null("BoxContainer/Panel/VBoxContainer/BoxContainer_Valign")
	assert_object(v_container).override_failure_message("Falta BoxContainer_Valign en panel_tooltext").is_not_null()
	var v_buttons: Array[Button] = []
	for child in v_container.get_children():
		if child is Button:
			v_buttons.append(child)
	assert_int(v_buttons.size()).is_equal(3)

	# Probar clic en cada botón vertical y asegurar que TODOS siguen visibles
	for btn in v_buttons:
		assert_object(btn.icon).override_failure_message("Botón %s no tiene icono asignado" % btn.name).is_not_null()
		btn.pressed.emit()
		await get_tree().process_frame
		for check_btn in v_buttons:
			assert_bool(check_btn.visible).override_failure_message("El botón vertical %s desapareció tras pulsar %s" % [check_btn.name, btn.name]).is_true()

	# 3. Comprobar iconos de alineación vertical estilo Figma/Penpot (text_valign_*)
	var btn_top := panel.get_node("BoxContainer/Panel/VBoxContainer/BoxContainer_Valign/BtnVTop") as Button
	var btn_mid := panel.get_node("BoxContainer/Panel/VBoxContainer/BoxContainer_Valign/BtnVMiddle") as Button
	var btn_bot := panel.get_node("BoxContainer/Panel/VBoxContainer/BoxContainer_Valign/BtnVBottom") as Button
	assert_str(btn_top.icon.resource_path).contains("text_valign_top")
	assert_str(btn_mid.icon.resource_path).contains("text_valign_middle")
	assert_str(btn_bot.icon.resource_path).contains("text_valign_bottom")



