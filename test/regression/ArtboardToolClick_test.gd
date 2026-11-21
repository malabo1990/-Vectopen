extends GdUnitTestSuite

## VAL-42: con una página seleccionada, solo Mover / Página pueden arrastrarla;
## con el pincel (u otra herramienta de dibujo) el clic es para dibujar.

const CANVAS := "res://scenes/canvas/canvas.tscn"
var _canvas: Node = null

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_canvas = get_tree().get_first_node_in_group("_vectopen_canvas")

func test_solo_mover_arrastra_la_pagina_seleccionada() -> void:
	var ab = PluginManager.api.artboard()
	assert_object(ab).is_not_null()
	ab.is_selected = true
	_canvas.switch_tool("brush")
	await get_tree().process_frame
	assert_bool(ab._is_selection_tool()).is_false()
	_canvas.switch_tool("pen")
	await get_tree().process_frame
	assert_bool(ab._is_selection_tool()).is_false()
	_canvas.switch_tool("move")
	await get_tree().process_frame
	assert_bool(ab._is_selection_tool()).is_true()
