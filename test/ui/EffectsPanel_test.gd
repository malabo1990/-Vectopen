extends GdUnitTestSuite

## Suite de pruebas para el Sistema de Efectos (Figma / Affinity Designer standard)
## Verifica renderizado en figuras, sincronización con InspectorCore, Undo/Redo en HistoryManager,
## serialización y exportación SVG.

const CANVAS := "res://scenes/canvas/canvas.tscn"
const PANEL_EFFECTS := "res://scenes/ui/panel__effects.tscn"

func _scene() -> Node2D:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s); get_tree().current_scene = s; auto_free(s)
	return s

func _tool(s: Node2D):
	var t = s.current_tool
	if not (t and t.get_class_name() == "MoveTool"):
		s.switch_tool("move"); t = s.current_tool
	return t

func _rect(parent: Node) -> VectorRectangle:
	var r := VectorRectangle.new()
	r.size = Vector2(100, 80)
	parent.add_child(r)
	r.set_doc_position(DVec2.new(150, 100))
	r.set_doc_extent(DVec2.from_v2(r.size))
	return r

func _ab(s: Node2D) -> ArtboardEditor:
	return (s.get_node("manager_script") as ArtboardManager).get_active_artboard()


func test_shape_effects_state_and_svg_filter() -> void:
	var r: VectorRectangle = auto_free(VectorRectangle.new())
	r.size = Vector2(120, 80)
	var shadow: Dictionary = {
		"type": "Drop Shadow",
		"enabled": true,
		"offset_x": 6.0,
		"offset_y": 6.0,
		"blur": 8.0,
		"color": Color(0.0, 0.0, 0.0, 0.5)
	}
	r.effects = [shadow]

	var state: Dictionary = r.get_state()
	assert_bool(state.has("effects")).is_true()
	var fx_arr: Array = state["effects"]
	assert_int(fx_arr.size()).is_equal(1)
	assert_str(fx_arr[0]["type"]).is_equal("Drop Shadow")

	var filter_attr: String = r.get_svg_filter_attr()
	assert_bool(filter_attr.contains("filter: drop-shadow")).is_true()
	assert_bool(filter_attr.contains("6.0px")).is_true()

	var svg: String = r.to_svg()
	assert_bool(svg.contains("filter: drop-shadow")).is_true()


func test_inspector_core_effects_read_write_undo_redo() -> void:
	var s: Node2D = _scene(); await get_tree().process_frame
	var t: Variant = _tool(s)
	var r: VectorRectangle = _rect(_ab(s))
	await get_tree().process_frame

	t.selected_shapes.assign([r]); InspectorCore._sync_selection()
	InspectorCore.changed.emit(InspectorCore.current_props())
	await get_tree().process_frame

	# Inicialmente sin efectos
	var props: Dictionary = InspectorCore.current_props()
	assert_bool(props.has("effects")).is_true()
	assert_int((props["effects"]["value"] as Array).size()).is_equal(0)

	# Aplicar un Drop Shadow mediante InspectorCore
	var new_effects: Array = [{
		"type": "Drop Shadow",
		"enabled": true,
		"offset_x": 4.0,
		"offset_y": 4.0,
		"blur": 6.0,
		"color": Color(0.1, 0.1, 0.1, 0.6)
	}]
	InspectorCore.apply("effects", new_effects)
	await get_tree().process_frame

	# Comprobar que la figura se actualizó
	assert_int(r.effects.size()).is_equal(1)
	assert_str(r.effects[0]["type"]).is_equal("Drop Shadow")
	assert_float(r.effects[0]["blur"]).is_equal(6.0)

	# Deshacer con HistoryManager
	HistoryManager.undo()
	await get_tree().process_frame
	assert_int(r.effects.size()).is_equal(0)

	# Rehacer con HistoryManager
	HistoryManager.redo()
	await get_tree().process_frame
	assert_int(r.effects.size()).is_equal(1)
	assert_str(r.effects[0]["type"]).is_equal("Drop Shadow")


func test_effects_panel_ui_binding_and_toggle() -> void:
	var s: Node2D = _scene(); await get_tree().process_frame
	var t: Variant = _tool(s)
	var r: VectorRectangle = _rect(_ab(s))
	await get_tree().process_frame

	var panel_root: Node = auto_free(load(PANEL_EFFECTS).instantiate())
	add_child(panel_root)
	await get_tree().process_frame

	var effects_panel: Variant = panel_root.get_node("PanelContainer/VBoxContainer/VBoxContainer/effects")
	assert_bool(effects_panel != null).is_true()

	# Con selección activa
	t.selected_shapes.assign([r]); InspectorCore._sync_selection()
	InspectorCore.changed.emit(InspectorCore.current_props())
	await get_tree().process_frame

	# Añadir efecto directamente desde el panel
	effects_panel._add_new_effect("Drop Shadow")
	await get_tree().process_frame

	assert_int(r.effects.size()).is_equal(1)
	assert_str(r.effects[0]["type"]).is_equal("Drop Shadow")

	# Añadir un segundo efecto: Outline
	effects_panel._add_new_effect("Outline")
	await get_tree().process_frame

	assert_int(r.effects.size()).is_equal(2)
	assert_str(r.effects[1]["type"]).is_equal("Outline")

	# Undo debe revertir a 1 efecto
	HistoryManager.undo()
	await get_tree().process_frame
	assert_int(r.effects.size()).is_equal(1)

	# Redo debe restaurar 2 efectos
	HistoryManager.redo()
	await get_tree().process_frame
	assert_int(r.effects.size()).is_equal(2)
	assert_str(r.effects[0]["type"]).is_equal("Drop Shadow")
	assert_str(r.effects[1]["type"]).is_equal("Outline")

	# Probar reordenación mediante botones mover arriba/abajo
	var fx_nodes = effects_panel._effects_list.get_children()
	assert_int(fx_nodes.size()).is_equal(2)
	var outline_fx = fx_nodes[1]
	effects_panel._on_effect_move_up(outline_fx)
	await get_tree().process_frame
	assert_str(r.effects[0]["type"]).is_equal("Outline")
	assert_str(r.effects[1]["type"]).is_equal("Drop Shadow")


func test_serializer_roundtrip_effects() -> void:
	var r: VectorRectangle = auto_free(VectorRectangle.new())
	r.size = Vector2(100, 100)
	r.effects = [
		{"type": "Drop Shadow", "enabled": true, "offset_x": 5.0, "offset_y": 5.0, "blur": 8.0, "color": Color.BLACK},
		{"type": "Inner Shadow", "enabled": true, "offset_x": 2.0, "offset_y": 2.0, "blur": 4.0, "color": Color(0, 0, 0, 0.5)}
	]

	var SerializerClass: Variant = load("res://scripts/canvas/canvas_serializer.gd")
	var dict: Dictionary = {}
	SerializerClass._add_style(dict, r)

	assert_bool(dict.has("fx")).is_true()
	assert_int((dict["fx"] as Array).size()).is_equal(2)

	var r2: VectorRectangle = auto_free(VectorRectangle.new())
	r2.size = Vector2(100, 100)
	SerializerClass._read_style(r2, dict)

	assert_int(r2.effects.size()).is_equal(2)
	assert_str(r2.effects[0]["type"]).is_equal("Drop Shadow")
	assert_str(r2.effects[1]["type"]).is_equal("Inner Shadow")


func test_three_d_effect_and_inner_shadow_pipeline() -> void:
	var r: VectorRectangle = auto_free(VectorRectangle.new())
	r.size = Vector2(100, 100)
	r.effects = [
		{"type": "3D", "enabled": true, "depth": 10.0, "bevel": 6.0, "angle": 45.0, "highlight": 80.0, "shadow": 60.0},
		{"type": "Inner Shadow", "enabled": true, "offset_x": 3.0, "offset_y": 3.0, "blur": 5.0, "spread": 2.0, "color": Color(0, 0, 0, 0.6)},
		{"type": "Drop Shadow", "enabled": true, "offset_x": 4.0, "offset_y": 4.0, "blur": 6.0, "spread": -1.0, "color": Color(0, 0, 0, 0.4)},
		{"type": "Blur", "enabled": true, "radius": 4.0, "preserve_alpha": false}
	]

	# Verificar que el estado captura los efectos con sus parámetros extendidos (spread, bevel, etc.)
	var state: Dictionary = r.get_state()
	assert_int((state["effects"] as Array).size()).is_equal(4)
	assert_str(state["effects"][0]["type"]).is_equal("3D")
	assert_float(state["effects"][0]["depth"]).is_equal(10.0)
	assert_float(state["effects"][0]["bevel"]).is_equal(6.0)
	assert_float(state["effects"][0]["highlight"]).is_equal(80.0)
	assert_float(state["effects"][0]["shadow"]).is_equal(60.0)
	assert_float(state["effects"][0]["angle"]).is_equal(45.0)

	assert_str(state["effects"][1]["type"]).is_equal("Inner Shadow")
	assert_float(state["effects"][1]["spread"]).is_equal(2.0)

	assert_str(state["effects"][2]["type"]).is_equal("Drop Shadow")
	assert_float(state["effects"][2]["spread"]).is_equal(-1.0)

	# Verificar simulación de renderizado sin excepciones en VectorRectangle y VectorPath
	add_child(r)
	r.queue_redraw()
	await get_tree().process_frame

	var VP := load("res://script_gdscript/shapes/VectorPath.gd")
	var p = auto_free(VP.new())
	p.closed = true
	p.curve = Curve2D.new()
	p.curve.add_point(Vector2(0, 0))
	p.curve.add_point(Vector2(50, 0))
	p.curve.add_point(Vector2(50, 50))
	p.curve.add_point(Vector2(0, 50))
	p.effects = r.effects.duplicate(true)
	add_child(p)
	p.queue_redraw()
	await get_tree().process_frame

	assert_bool(p.effects.size() == 4).is_true()


func test_fx_row_controls_spread_and_3d_params() -> void:
	var ds_scene: PackedScene = load("res://scenes/ui/panels/effects/fx/drop_shadow.tscn")
	var ds: Control = auto_free(ds_scene.instantiate())
	add_child(ds)
	ds.set_params({"offset_x": 5.0, "offset_y": 7.0, "blur": 10.0, "spread": 3.0, "color": Color.BLACK})
	var ds_p: Dictionary = ds.get_params()
	assert_float(ds_p["spread"]).is_equal(3.0)

	var is_scene: PackedScene = load("res://scenes/ui/panels/effects/fx/inner_shadow.tscn")
	var is_fx: Control = auto_free(is_scene.instantiate())
	add_child(is_fx)
	is_fx.set_params({"offset_x": 2.0, "offset_y": 4.0, "blur": 8.0, "spread": -2.0, "color": Color.BLACK})
	var is_p: Dictionary = is_fx.get_params()
	assert_float(is_p["spread"]).is_equal(-2.0)

	var td_scene: PackedScene = load("res://scenes/ui/panels/effects/fx/three_d.tscn")
	var td: Control = auto_free(td_scene.instantiate())
	add_child(td)
	td.set_params({"depth": 12.0, "bevel": 7.0, "angle": 90.0, "highlight": 85.0, "shadow": 45.0})
	var td_p: Dictionary = td.get_params()
	assert_float(td_p["depth"]).is_equal(12.0)
	assert_float(td_p["bevel"]).is_equal(7.0)
	assert_float(td_p["angle"]).is_equal(90.0)
	assert_float(td_p["highlight"]).is_equal(85.0)
	assert_float(td_p["shadow"]).is_equal(45.0)

