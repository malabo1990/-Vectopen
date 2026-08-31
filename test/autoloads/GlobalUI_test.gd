extends GdUnitTestSuite

## Regresión: el BoundingBox (Control del lienzo) NO debe contarse como UI.
## Antes, gui_get_hovered_control() devolvía sus Panels (mouse_filter STOP)
## → is_mouse_over_ui=true → sin zoom ni drag dentro del boundingbox.
## Solo los paneles reales (bajo CanvasLayer/Window) bloquean el zoom/drag.

func _nuevo_boundingbox() -> Control:
	var bb: Control = load("res://scenes/canvas/boundingbox.tscn").instantiate()
	return bb

func _nodo_mundo(bb: Control) -> Node2D:
	var mundo := Node2D.new()
	mundo.name = "MundoCanvas"
	mundo.add_child(bb)
	return mundo

func test_boundingbox_en_mundo_no_es_ui() -> void:
	GlobalUI.is_mouse_over_ui = true
	var bb := _nuevo_boundingbox()
	var mundo := _nodo_mundo(bb)
	add_child(mundo)
	# Un Panel/handle del boundingbox (hijo de Control del mundo)
	var handle := bb.get_node("PANEL_BOUNDINGBOX/handle_IA") as Control
	assert_object(handle).is_not_null()

	assert_that(GlobalUI._es_ui_real(handle)).is_false()
	assert_that(GlobalUI._es_ui_real(bb)).is_false()
	mundo.queue_free()

func test_panel_solo_sin_contexto_no_es_ui() -> void:
	var mundo := Node2D.new()
	mundo.name = "MundoCanvas"
	add_child(mundo)
	var panel := Panel.new()
	mundo.add_child(panel)
	assert_that(GlobalUI._es_ui_real(panel)).is_false()
	mundo.queue_free()

func test_panel_bajo_canvas_layer_si_es_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := Panel.new()
	layer.add_child(panel)
	var boton := Button.new()
	panel.add_child(boton)

	assert_that(GlobalUI._es_ui_real(boton)).is_true()
	assert_that(GlobalUI._es_ui_real(panel)).is_true()
	layer.queue_free()

func test_panel_bajo_window_si_es_ui() -> void:
	var win := Window.new()
	var panel := Panel.new()
	win.add_child(panel)
	assert_that(GlobalUI._es_ui_real(panel)).is_true()
	win.queue_free()

func test_null_no_es_ui() -> void:
	assert_that(GlobalUI._es_ui_real(null)).is_false()
