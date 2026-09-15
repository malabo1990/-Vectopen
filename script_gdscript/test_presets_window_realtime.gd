# =============================================================================
# RUTA: res://script_gdscript/test_presets_window_realtime.gd
# Verificación en vivo de TransformPanel + Panel_config_windows_element
# (Módulos: papel, dispositivos, red social, logo, icono + orientación + búsqueda)
# =============================================================================
extends Control

const ARTIFACT_DIR := "C:/Users/User/.gemini/antigravity/brain/cbfb9fe4-aad3-4125-96d1-b9b83ad17733"

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.12, 0.13, 0.16, 1.0)
	add_child(bg)

	var header := Label.new()
	header.text = "VERIFICACIÓN EN TIEMPO REAL: PANEL DE CONFIGURACIÓN DE TAMAÑO (PRESETS)"
	header.position = Vector2(40, 20)
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	add_child(header)

	var subheader := Label.new()
	subheader.text = "TransformPanel -> Panel_config_windows_element: Papel, Dispositivos, Red social, Logo, Icono"
	subheader.position = Vector2(40, 46)
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	add_child(subheader)

	# Instanciar TransformPanel
	var panel = load("res://scenes/ui/transform_panel.tscn").instantiate() as Control
	panel.position = Vector2(50, 90)
	add_child(panel)

	await get_tree().process_frame
	await get_tree().process_frame

	# Conectar y abrir la ventana de configuración
	if panel.has_method("_toggle_presets_window"):
		panel._toggle_presets_window()
	elif panel._btn_presets:
		panel._btn_presets.pressed.emit()

	await get_tree().process_frame
	await get_tree().process_frame

	var win: PanelConfigWindowsElement = panel._config_window
	if win:
		win.global_position = Vector2(340, 90)

	# 1. Captura Módulo Papel
	for i in range(5): await get_tree().process_frame
	_capture("step1_transform_presets_paper_module.png")

	# 2. Captura Módulo Dispositivos
	if win:
		win.switch_module("dispositivos")
	for i in range(5): await get_tree().process_frame
	_capture("step2_transform_presets_devices_module.png")

	# 3. Captura Módulo Red Social
	if win:
		win.switch_module("red_social")
	for i in range(5): await get_tree().process_frame
	_capture("step3_transform_presets_social_module.png")

	# 4. Captura Módulo Logo
	if win:
		win.switch_module("logo")
	for i in range(5): await get_tree().process_frame
	_capture("step4_transform_presets_logo_module.png")

	# 5. Captura Módulo Icono
	if win:
		win.switch_module("icono")
	for i in range(5): await get_tree().process_frame
	_capture("step5_transform_presets_icon_module.png")

	# 6. Captura con Búsqueda y Orientación Horizontal
	if win:
		win.switch_module("red_social")
		win.toggle_orientation()
		win.search_edit.text = "Instagram"
		win._on_search_changed("Instagram")
	for i in range(5): await get_tree().process_frame
	_capture("step6_transform_presets_search_and_orientation.png")

	print("Todas las capturas se han generado correctamente.")
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)

func _capture(file_name: String) -> void:
	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	var full_path := ARTIFACT_DIR + "/" + file_name
	img.save_png(full_path)
	print("Captura guardada: ", full_path)
