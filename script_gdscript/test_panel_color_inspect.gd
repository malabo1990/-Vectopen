# =============================================================================
# Renderizar Tab 0 (Selector) y Tab 1 (Muestras) de Panel_color en tool_in_mouse.tscn
# =============================================================================
extends Control

const ARTIFACT_DIR := "C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686"
const SCREENSHOT_PATH := ARTIFACT_DIR + "/realtime_panel_color_tabs_test.png"

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.93, 0.94, 0.96, 1.0)
	add_child(bg)

	var header := Label.new()
	header.text = "INSPECCION UI: PANEL_COLOR SUB-TABS (SELECTOR Y MUESTRAS) + MARGENES DE BOTONES"
	header.position = Vector2(40, 20)
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.12, 0.12, 0.16))
	add_child(header)

	# 1. Panel 1: Modo Círculo
	var lbl_1 := Label.new()
	lbl_1.text = "Modo: Círculo"
	lbl_1.position = Vector2(40, 50)
	lbl_1.add_theme_font_size_override("font_size", 12)
	lbl_1.add_theme_color_override("font_color", Color(0.25, 0.28, 0.35))
	add_child(lbl_1)

	var menu_1 = load("res://scenes/ui/tool_in_mouse.tscn").instantiate() as Control
	menu_1.position = Vector2(40, 75)
	add_child(menu_1)

	# 2. Panel 2: Modo Triángulo
	var lbl_2 := Label.new()
	lbl_2.text = "Modo: Triángulo"
	lbl_2.position = Vector2(280, 50)
	lbl_2.add_theme_font_size_override("font_size", 12)
	lbl_2.add_theme_color_override("font_color", Color(0.25, 0.28, 0.35))
	add_child(lbl_2)

	var menu_2 = load("res://scenes/ui/tool_in_mouse.tscn").instantiate() as Control
	menu_2.position = Vector2(280, 75)
	add_child(menu_2)

	# 3. Panel 3: Modo Cuadrado (Figma)
	var lbl_3 := Label.new()
	lbl_3.text = "Modo: Cuadrado"
	lbl_3.position = Vector2(520, 50)
	lbl_3.add_theme_font_size_override("font_size", 12)
	lbl_3.add_theme_color_override("font_color", Color(0.25, 0.28, 0.35))
	add_child(lbl_3)

	var menu_3 = load("res://scenes/ui/tool_in_mouse.tscn").instantiate() as Control
	menu_3.position = Vector2(520, 75)
	add_child(menu_3)

	# 4. Panel 4: Sub-Tab Muestras
	var lbl_4 := Label.new()
	lbl_4.text = "Sub-Tab: Muestras (Grid)"
	lbl_4.position = Vector2(760, 50)
	lbl_4.add_theme_font_size_override("font_size", 12)
	lbl_4.add_theme_color_override("font_color", Color(0.25, 0.28, 0.35))
	add_child(lbl_4)

	var menu_4 = load("res://scenes/ui/tool_in_mouse.tscn").instantiate() as Control
	menu_4.position = Vector2(760, 75)
	add_child(menu_4)

	# 5. Panel 5: Trazo / Stroke
	var lbl_5 := Label.new()
	lbl_5.text = "Trazo / Stroke"
	lbl_5.position = Vector2(40, 520)
	lbl_5.add_theme_font_size_override("font_size", 12)
	lbl_5.add_theme_color_override("font_color", Color(0.25, 0.28, 0.35))
	add_child(lbl_5)

	var menu_5 = load("res://scenes/ui/tool_in_mouse.tscn").instantiate() as Control
	menu_5.position = Vector2(40, 545)
	add_child(menu_5)

	# 6. Panel 6: Transformación
	var lbl_6 := Label.new()
	lbl_6.text = "Transformación"
	lbl_6.position = Vector2(280, 520)
	lbl_6.add_theme_font_size_override("font_size", 12)
	lbl_6.add_theme_color_override("font_color", Color(0.25, 0.28, 0.35))
	add_child(lbl_6)

	var menu_6 = load("res://scenes/ui/tool_in_mouse.tscn").instantiate() as Control
	menu_6.position = Vector2(280, 545)
	add_child(menu_6)

	# 7. Panel 7: Tipografía
	var lbl_7 := Label.new()
	lbl_7.text = "Tipografía"
	lbl_7.position = Vector2(520, 520)
	lbl_7.add_theme_font_size_override("font_size", 12)
	lbl_7.add_theme_color_override("font_color", Color(0.25, 0.28, 0.35))
	add_child(lbl_7)

	var menu_7 = load("res://scenes/ui/tool_in_mouse.tscn").instantiate() as Control
	menu_7.position = Vector2(520, 545)
	add_child(menu_7)

	# 8. Panel Palette Flyout
	var lbl_pal := Label.new()
	lbl_pal.text = "Paleta Dinámica Flyout"
	lbl_pal.position = Vector2(1150, 50)
	lbl_pal.add_theme_font_size_override("font_size", 11)
	lbl_pal.add_theme_color_override("font_color", Color(0.25, 0.28, 0.35))
	add_child(lbl_pal)

	var menu_pal = load("res://scenes/ui/tool_in_mouse.tscn").instantiate() as Control
	menu_pal.position = Vector2(1650, 75)
	add_child(menu_pal)

	# 9. Panel 8: Inspector con Degradado Lineal activo
	var lbl_8 := Label.new()
	lbl_8.text = "Color: Modo Degradado Lineal"
	lbl_8.position = Vector2(760, 520)
	lbl_8.add_theme_font_size_override("font_size", 12)
	lbl_8.add_theme_color_override("font_color", Color(0.25, 0.28, 0.35))
	add_child(lbl_8)

	var menu_8 = load("res://scenes/ui/tool_in_mouse.tscn").instantiate() as Control
	menu_8.position = Vector2(760, 545)
	add_child(menu_8)

	# 10. Control Standalone Gradient
	var lbl_9 := Label.new()
	lbl_9.text = "Editor Degradado (Stops Arrastrables)"
	lbl_9.position = Vector2(1000, 520)
	lbl_9.add_theme_font_size_override("font_size", 12)
	lbl_9.add_theme_color_override("font_color", Color(0.25, 0.28, 0.35))
	add_child(lbl_9)

	var p_grad = load("res://scenes/ui/gradient.tscn").instantiate() as Control
	p_grad.custom_minimum_size = Vector2(240, 70)
	p_grad.position = Vector2(1000, 545)
	add_child(p_grad)

	# 11. Panel Tipografía (Clickeado: Center y Middle)
	var lbl_7b := Label.new()
	lbl_7b.text = "Tipografía: Center + Middle Clickeados"
	lbl_7b.position = Vector2(1300, 520)
	lbl_7b.add_theme_font_size_override("font_size", 12)
	lbl_7b.add_theme_color_override("font_color", Color(0.25, 0.28, 0.35))
	add_child(lbl_7b)

	var menu_7b = load("res://scenes/ui/tool_in_mouse.tscn").instantiate() as Control
	menu_7b.position = Vector2(1300, 545)
	add_child(menu_7b)

	await get_tree().process_frame
	await get_tree().process_frame

	for m in [menu_1, menu_2, menu_3, menu_4]:
		m.visible = true
		var tab_list = m.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer")
		if tab_list and tab_list.has_method("_update_control_b_visibility"):
			tab_list._update_control_b_visibility(3)

	# Configurar modos
	var p2 = menu_2.find_child("pickr", true, false)
	if p2 and p2.has_method("_on_mode_pressed"):
		p2._on_mode_pressed(1)

	var p3 = menu_3.find_child("pickr", true, false)
	if p3 and p3.has_method("_on_mode_pressed"):
		p3._on_mode_pressed(2)

	var tabs_4 = menu_4.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_color/TabsBar")
	if tabs_4 and tabs_4.has_method("_update_control_b_visibility"):
		tabs_4._update_control_b_visibility(1)

	menu_5.visible = true
	var tl5 = menu_5.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer")
	if tl5 and tl5.has_method("_update_control_b_visibility"):
		tl5._update_control_b_visibility(5)

	menu_6.visible = true
	var tl6 = menu_6.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer")
	if tl6 and tl6.has_method("_update_control_b_visibility"):
		tl6._update_control_b_visibility(2)

	menu_7.visible = true
	var tl7 = menu_7.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer")
	if tl7 and tl7.has_method("_update_control_b_visibility"):
		tl7._update_control_b_visibility(4)

	menu_7b.visible = true
	var tl7b = menu_7b.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer")
	if tl7b and tl7b.has_method("_update_control_b_visibility"):
		tl7b._update_control_b_visibility(4)

	# Simular clic en Center (Button4) y Middle (BtnVMiddle) en menu_7b
	var b_center = menu_7b.find_child("Button4", true, false)
	if b_center and b_center is Button:
		b_center.emit_signal("pressed")
	var b_vmid = menu_7b.find_child("BtnVMiddle", true, false)
	if b_vmid and b_vmid is Button:
		b_vmid.emit_signal("pressed")

	var b_right = menu_7b.find_child("Button3", true, false)
	var b_just = menu_7b.find_child("Button2", true, false)
	print("TEST VERIFY: Right button visible = ", b_right.visible if b_right else false)
	print("TEST VERIFY: Justify button visible = ", b_just.visible if b_just else false)

	menu_pal.visible = true
	var tl_pal = menu_pal.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer")
	if tl_pal and tl_pal.has_method("_update_control_b_visibility"):
		tl_pal._update_control_b_visibility(3)
	var pal = menu_pal.find_child("palleteColor", true, false)
	if pal:
		pal.visible = true

	menu_8.visible = true
	var tl8 = menu_8.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer")
	if tl8 and tl8.has_method("_update_control_b_visibility"):
		tl8._update_control_b_visibility(3)
	var gc8 = menu_8.find_child("pickr", true, false)
	if gc8 and gc8.has_method("_on_tab_pressed"):
		gc8._on_tab_pressed("linear")

	for i in range(12):
		await get_tree().process_frame

	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	img.save_png(SCREENSHOT_PATH)
	print("Captura guardada en: ", SCREENSHOT_PATH)

	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0)
