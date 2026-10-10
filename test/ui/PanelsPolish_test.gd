# =============================================================================
# VECTOPEN — Context panel polish: text copy style, eyedropper, swatches,
# letter-proportion reset, hover highlight and compact transform width.
# RUTA: res://test/ui/PanelsPolish_test.gd
# =============================================================================
extends GdUnitTestSuite

func _make_text(root: Node) -> Node2D:
	var container := Node2D.new()
	container.set_meta("shape_type", "text_title")
	container.set_meta("letter_proportions", {"mode": "Aaa", "start": 1.6, "mid": 1.2, "mid2": 0.8, "end": 0.4})
	container.set_meta("runs", [{"length": 3, "color": Color.RED, "bold": true, "italic": false, "underline": false}])
	var dl := WorldTextLabel.new()
	dl.name = "DisplayLabel"
	dl.text = "Abc"
	container.add_child(dl)
	root.add_child(container)
	return container

func test_duplicated_text_keeps_proportions_and_runs() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var original := _make_text(root)
	await get_tree().process_frame
	# Copy / paste / Ctrl+D all go through Node.duplicate()
	var copy: Node2D = original.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	root.add_child(copy)
	await get_tree().process_frame
	var dl: WorldTextLabel = copy.get_node("DisplayLabel")
	assert_bool(dl.has_letter_proportions()).is_true()
	assert_str(String(dl.letter_proportions.get("mode", ""))).is_equal("Aaa")
	assert_int(dl.rich_runs.size()).is_equal(1)
	assert_bool(bool(dl.rich_runs[0]["bold"])).is_true()

func test_swatch_grid_is_grey_ramp_plus_three_rows_per_hue() -> void:
	var grid = auto_free(load("res://script_gdscript/ui/ListaColor.gd").new())
	var colors: Array = grid.palette_colors()
	assert_int(colors.size()).is_equal(grid.HUES * 4)
	assert_that((colors[0] as Color).is_equal_approx(Color.BLACK)).is_true()
	assert_that((colors[grid.HUES - 1] as Color).is_equal_approx(Color.WHITE)).is_true()

func test_eyedropper_applies_sampled_color() -> void:
	var picker = auto_free(load("res://scenes/ui/pickr_color_tool.tscn").instantiate())
	add_child(picker)
	await get_tree().process_frame
	assert_object(picker._btn_eyedropper).is_not_null()
	picker._set_eyedropper_active(true)
	assert_bool(picker._eyedropper_active).is_true()
	picker.apply_sampled_color(Color(0.2, 0.6, 0.3))
	assert_that(picker.obtener_color().is_equal_approx(Color(0.2, 0.6, 0.3))).is_true()
	picker._set_eyedropper_active(false)
	assert_bool(picker._eyedropper_active).is_false()

func test_letter_proportions_reset_button() -> void:
	var panel = auto_free(load("res://scenes/ui/panel_tooltext.tscn").instantiate())
	add_child(panel)
	await get_tree().process_frame
	var box = panel.get_node("BoxContainer")
	assert_object(box._btn_prop_reset).is_not_null()
	box._on_prop_button_pressed("Aaa")
	assert_str(box._current_prop_mode).is_equal("Aaa")
	box.reset_letter_proportions()
	assert_str(box._current_prop_mode).is_equal("")
	for s in box._prop_sliders.values():
		assert_float((s as Slider).value).is_equal_approx(1.0, 0.001)

func test_hover_highlights_unselected_shape_only() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var artboard: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(artboard)
	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	artboard.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(80, 60)
	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = root
	tool.target_artboard = artboard
	tool._update_hover_shape(Vector2(100, 100))
	assert_object(tool._hover_shape).is_same(shape)
	tool._update_hover_shape(Vector2(900, 900))
	assert_object(tool._hover_shape).is_null()
	tool.selected_shapes = [shape]
	tool._update_hover_shape(Vector2(100, 100))
	assert_object(tool._hover_shape).is_null()

func test_transform_fields_fit_compact_panel() -> void:
	var tp: TransformPanel = auto_free(TransformPanel.new())
	add_child(tp)
	await get_tree().process_frame
	# Three corner fields + spacing must fit the 220px context panel
	assert_float(tp.get_combined_minimum_size().x).is_less_equal(206.0)

func test_transform_corners_are_a_2x2_grid_above_rotation() -> void:
	var tp: TransformPanel = auto_free(TransformPanel.new())
	add_child(tp)
	await get_tree().process_frame
	var grid := tp._corners["corner_tl"].get_parent() as GridContainer
	assert_object(grid).is_not_null()
	assert_int(grid.columns).is_equal(2)
	for k in ["corner_tl", "corner_tr", "corner_bl", "corner_br"]:
		assert_object(tp._corners[k].get_parent()).is_same(grid)
	# Rotation row comes after the corners block
	assert_bool(tp._rot.get_parent().get_index() > grid.get_index()).is_true()

func test_rotate_90_is_relative_per_shape_and_undoable() -> void:
	var sc: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(sc)
	await get_tree().process_frame
	if not (sc.current_tool and sc.current_tool.get_class_name() == "MoveTool"):
		sc.switch_tool("move")
	var ab := (sc.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var a := VectorRectangle.new()
	var b := VectorRectangle.new()
	ab.add_child(a)
	ab.add_child(b)
	a.set_doc_rotation(deg_to_rad(10.0))
	b.set_doc_rotation(deg_to_rad(30.0))
	sc.current_tool.selected_shapes.assign([a, b])
	SelectionManager.set_selection([a, b])
	HistoryManager.clear()
	ContextMenuActions.rotate_by(sc, 90.0)
	# Each shape turns from its own angle (a multi-selection is not flattened)
	assert_float(fposmod(rad_to_deg(a.get_doc_rotation()), 360.0)).is_equal_approx(100.0, 0.05)
	assert_float(fposmod(rad_to_deg(b.get_doc_rotation()), 360.0)).is_equal_approx(120.0, 0.05)
	HistoryManager.undo()
	assert_float(fposmod(rad_to_deg(a.get_doc_rotation()), 360.0)).is_equal_approx(10.0, 0.05)
	assert_float(fposmod(rad_to_deg(b.get_doc_rotation()), 360.0)).is_equal_approx(30.0, 0.05)
	SelectionManager.clear()

func test_input_hud_shows_key_combo() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var pc := PanelContainer.new()
	pc.name = "PanelContainer"
	host.add_child(pc)
	var mc := MarginContainer.new()
	mc.name = "MarginContainer"
	pc.add_child(mc)
	var content := HBoxContainer.new()
	content.name = "Contenido"
	mc.add_child(content)
	for n in ["Label2", "Label"]:
		var l := Label.new()
		l.name = n
		content.add_child(l)
	var hud := InputHud.new()
	host.add_child(hud)
	await get_tree().process_frame
	var ev := InputEventKey.new()
	ev.keycode = KEY_S
	ev.ctrl_pressed = true
	ev.pressed = true
	hud.show_key_event(ev)
	assert_str((content.get_node("Label2") as Label).text).is_equal("Ctrl")
	assert_str((content.get_node("Label") as Label).text).is_equal("S")

## ContextMenuActions must APPLY the change: the project's UndoRedoManager only
## records it on commit (this regression made flip/arrange/lock do nothing).
func test_context_actions_apply_flip_arrange_lock_and_undo() -> void:
	var sc: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(sc)
	await get_tree().process_frame
	var ab := (sc.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var a := VectorRectangle.new()
	var b := VectorRectangle.new()
	ab.add_child(a)
	ab.add_child(b)
	SelectionManager.set_selection([a])
	HistoryManager.clear()
	ContextMenuActions.execute("flip_h", sc)
	assert_float(a.scale.x).is_equal(-1.0)
	HistoryManager.undo()
	assert_float(a.scale.x).is_equal(1.0)
	var idx_before := a.get_index()
	ContextMenuActions.execute("bring_to_front", sc)
	assert_int(a.get_index()).is_equal(ab.get_child_count() - 1)
	HistoryManager.undo()
	assert_int(a.get_index()).is_equal(idx_before)
	ContextMenuActions.execute("toggle_lock", sc)
	assert_bool(bool(a.get_meta("locked", false))).is_true()
	HistoryManager.undo()
	assert_bool(bool(a.get_meta("locked", false))).is_false()
	SelectionManager.clear()
