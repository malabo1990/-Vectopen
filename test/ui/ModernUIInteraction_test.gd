# =============================================================================
# VECTOPEN — PRUEBAS DE INTERACCIÓN, REGLAS Y CONFLICTOS DE UI (MODERN UI)
# RUTA: res://test/ui/ModernUIInteraction_test.gd
# =============================================================================
extends GdUnitTestSuite

const ManagerWindowsRegla = preload("res://script_gdscript/ui/ManagerWindowsRegla.gd")

func test_modern_mode_no_conflicts_and_proper_layout() -> void:
	GlobalUI.set_ui_mode("modern")
	var canvas_scene = load("res://scenes/canvas/canvas.tscn").instantiate()
	add_child(canvas_scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var main_ui = canvas_scene.get_node("CanvasLayer/main")
	assert_that(main_ui).is_not_null()

	var adapt_mgr = main_ui.get_node("AdaptiveUIManager") as AdaptiveUIManager
	assert_that(adapt_mgr).is_not_null()

	var top_bar = main_ui.get_node("ModernTopBar") as ModernTopBar
	var nav_rail = main_ui.get_node("ModernNavRail") as ModernNavRail
	var bottom_bar = main_ui.get_node("ModernBottomToolbar") as ModernBottomToolbar
	var inspector = main_ui.get_node("DockedInspector") as DockedInspector
	var layout = main_ui.get_node("Layout")
	var logo = main_ui.get_node("Logo")
	var keyboard = main_ui.get_node("keyboard")
	var windows_regla = main_ui.get_node("windows_ recla")
	var regla_h = windows_regla.get_node("regla horizontal") as Control
	var barra_visual = adapt_mgr.barra_visual_panel

	# 1. En Modern Mode, los componentes principales de Modern UI deben ser visibles
	assert_that(top_bar.visible).is_true()
	assert_that(nav_rail.visible).is_false() # side rail removed: settings live in the top bar
	assert_that(bottom_bar.visible).is_true()
	assert_that(inspector.visible).is_true()

	# 2. Logo oficial de Vectopen en ModernTopBar
	assert_object(top_bar.logo_rect).is_not_null()
	assert_object(top_bar.logo_rect.texture).is_not_null()

	# 3. Elementos de Smart UI deben estar ocultos (Logo antiguo y chip de teclado abajo izquierda)
	assert_that(logo.visible).is_false()
	assert_that(keyboard.visible).is_false()
	if barra_visual:
		assert_that(barra_visual.visible).is_false()

	# 4. Reglas ajustadas: no se superponen con ModernTopBar ni con el inspector a la derecha
	# y acompañan al panel de capas acoplado al borde (260)
	var regla_v = windows_regla.get_node("regla vertical") as Control
	assert_that(windows_regla.offset_top).is_equal(36.0)
	assert_that(regla_h.offset_right).is_equal(-268.0)
	assert_that(regla_v.offset_left).is_equal(260.0)
	assert_that(regla_h.offset_left).is_equal(284.0)
	# The ruler-corner settings button duplicated the top-bar one
	assert_that((windows_regla.get_node("Button") as Control).visible).is_false()

	# 5. Layout no debe tener offsets negativos que lo manden fuera de pantalla
	assert_that(layout.offset_left).is_equal(0.0)
	var inner_panel = layout.get_node("PanelContainer") as Control
	assert_that(inner_panel.offset_left).is_equal(0.0)
	assert_that(inner_panel.anchor_left).is_equal(0.0)

	# 6. Herramientas verticales: visibles en Modern (acopladas a la izquierda)
	var vert_tools = inner_panel.find_child("Herramientas", true, false) as Control
	assert_that(vert_tools.visible).is_true()

	# 7. Capas en modo moderno: sin radios las esquinas (corner_radius = 0)
	var inner_sb = inner_panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_that(inner_sb).is_not_null()
	assert_that(inner_sb.corner_radius_top_left).is_equal(0)
	assert_that(inner_sb.corner_radius_top_right).is_equal(0)
	assert_that(inner_sb.corner_radius_bottom_left).is_equal(0)
	assert_that(inner_sb.corner_radius_bottom_right).is_equal(0)
	assert_that(inner_sb.border_width_right).is_equal(1)

	var layers_panel = inner_panel.find_child("Panel", true, false) as Panel
	if layers_panel:
		var lsb = layers_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if lsb:
			assert_that(lsb.corner_radius_top_left).is_equal(0)
			assert_that(lsb.corner_radius_top_right).is_equal(0)
			assert_that(lsb.corner_radius_bottom_left).is_equal(0)
			assert_that(lsb.corner_radius_bottom_right).is_equal(0)

	# 8. Controles de Zoom en ModernBottomToolbar (+, -, label 100%)
	bottom_bar.btn_zoom_in.emit_signal("pressed")
	await get_tree().process_frame
	assert_that(bottom_bar.lbl_zoom.text).is_not_equal("0%")

	bottom_bar.btn_zoom_out.emit_signal("pressed")
	await get_tree().process_frame

	bottom_bar.set_zoom_percentage(100.0)
	assert_that(bottom_bar.lbl_zoom.text).is_equal("100%")

	# 9. Seleccion de herramienta desde ModernBottomToolbar
	var rect_btn = bottom_bar._buttons.get("rectangle") as Button
	assert_that(rect_btn).is_not_null()
	rect_btn.emit_signal("pressed")
	await get_tree().process_frame
	assert_that(bottom_bar._active_tool).is_equal("rectangle")

	# 10. Diálogo de Configuración: apertura y cierre con botón ✕ y toggle
	var settings_dialog = windows_regla.get_node("MANAGER WINDWS_REGLA") as ManagerWindowsRegla
	assert_that(settings_dialog).is_not_null()
	assert_that(settings_dialog.visible).is_false()

	# Abrir vía GlobalEvents (botón ⚙ de ModernTopBar)
	GlobalEvents.emit_safe("request_settings_dialog")
	await get_tree().process_frame
	assert_that(settings_dialog.visible).is_true()

	# Cerrar con el botón ✕ en el encabezado
	assert_that(settings_dialog.btn_close).is_not_null()
	settings_dialog.btn_close.emit_signal("pressed")
	await get_tree().process_frame
	assert_that(settings_dialog.visible).is_false()

	# Abrir nuevamente y cerrar vía método de cierre / toggle
	GlobalEvents.emit_safe("request_settings_dialog")
	await get_tree().process_frame
	assert_that(settings_dialog.visible).is_true()
	settings_dialog.close_settings()
	assert_that(settings_dialog.visible).is_false()

	# 11. Restauracion fiel a Smart Mode
	GlobalUI.set_ui_mode("smart")
	await get_tree().process_frame
	assert_that(top_bar.visible).is_false()
	assert_that(nav_rail.visible).is_false()
	assert_that(bottom_bar.visible).is_false()
	assert_that(inspector.visible).is_false()
	assert_that(logo.visible).is_true()
	assert_that(keyboard.visible).is_true()
	if barra_visual:
		assert_that(barra_visual.visible).is_true()
	assert_that(windows_regla.offset_top).is_equal(0.0)
	assert_that(regla_v.offset_left).is_equal(0.0)
	assert_that(regla_h.offset_right).is_equal(0.0)
	assert_that(regla_h.offset_left).is_equal(0.0)
	assert_that(layout.offset_left).is_equal(-106.0)
	assert_that(inner_panel.offset_left).is_equal(-476.0)
	assert_that(vert_tools.visible).is_true()

	var restored_inner_sb = inner_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if restored_inner_sb:
		assert_that(restored_inner_sb.corner_radius_top_left).is_equal(10)

	canvas_scene.queue_free()

