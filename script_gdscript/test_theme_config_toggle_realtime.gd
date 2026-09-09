# =============================================================================
# RUTA: res://script_gdscript/test_theme_config_toggle_realtime.gd
# Verificación en vivo de Button_configuration conmutando ThemeConfigPanel
# =============================================================================
extends Control

const ARTIFACT_DIR := "C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686"
const SCREENSHOT_PATH := ARTIFACT_DIR + "/realtime_theme_config_toggle_test.png"

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.92, 0.93, 0.95, 1.0)
	add_child(bg)

	var header := Label.new()
	header.text = "VERIFICACION EN TIEMPO REAL: TOGGLE BUTTON_CONFIGURATION -> THEME_CONFIG_PANEL"
	header.position = Vector2(40, 30)
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.12, 0.12, 0.16))
	add_child(header)

	var subheader := Label.new()
	subheader.text = "Menu Contextual (tool_in_mouse) + Panel de Preferencias y Tema (ThemeConfigPanel conmutado)"
	subheader.position = Vector2(40, 56)
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color(0.35, 0.38, 0.45))
	add_child(subheader)

	# Contenedor para ubicar el menú en el lienzo
	var mouse_menu = load("res://scenes/ui/tool_in_mouse.tscn").instantiate() as Control
	mouse_menu.position = Vector2(420, 110)
	add_child(mouse_menu)

	await get_tree().process_frame
	await get_tree().process_frame

	# Hacer visible el menú contextual completo
	mouse_menu.visible = true
	var main_panel = mouse_menu.get_node_or_null("PanelContainer") as Control
	if main_panel:
		main_panel.visible = true

	# Buscar Button_configuration y ThemeConfigPanel
	var cfg_btn = mouse_menu.get_node_or_null("Button_configuration") as Button
	var tcp = mouse_menu.get_node_or_null("ThemeConfigPanel") as Control

	if cfg_btn and tcp:
		print("ThemeConfigPanel inicial visible: ", tcp.visible)
		# Conmutar con el botón
		cfg_btn.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		print("ThemeConfigPanel tras toggle visible: ", tcp.visible)

	for i in range(8):
		await get_tree().process_frame

	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	img.save_png(SCREENSHOT_PATH)
	print("Captura guardada en: ", SCREENSHOT_PATH)

	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0)
