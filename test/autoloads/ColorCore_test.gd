extends GdUnitTestSuite

## Sistema core de color: utilidades avanzadas, modelo de paint, recientes y
## el puente a InspectorCore (aplicar a la selección con undo).

const CANVAS := "res://scenes/canvas/canvas.tscn"

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
	r.size = Vector2(80, 60)
	r.fill_color = Color.WHITE
	parent.add_child(r)
	r.set_doc_position(DVec2.new(100, 100))
	r.set_doc_extent(DVec2.from_v2(r.size))
	return r

func _ab(s: Node2D) -> ArtboardEditor:
	return (s.get_node("manager_script") as ArtboardManager).get_active_artboard()


# ── utilidades ──────────────────────────────────────────────────────────────
func test_hex_y_parse() -> void:
	assert_str(ColorCore.hex(Color.RED)).is_equal("#FF0000")
	assert_that(ColorCore.parse("#00FF00")).is_equal(Color.GREEN)


func test_contraste_wcag() -> void:
	# negro sobre blanco = 21:1
	assert_float(ColorCore.contrast_ratio(Color.BLACK, Color.WHITE)).is_equal_approx(21.0, 0.1)
	assert_that(ColorCore.best_text_on(Color.WHITE)).is_equal(Color.BLACK)
	assert_that(ColorCore.best_text_on(Color(0.1, 0.1, 0.1))).is_equal(Color.WHITE)


func test_armonia_complementaria_y_triada() -> void:
	var base := Color.from_hsv(0.0, 1.0, 1.0)   # rojo
	var comp: Array = ColorCore.harmony(base, "complementary")
	assert_float(comp[1].h).is_equal_approx(0.5, 0.001)   # cian
	var tri: Array = ColorCore.harmony(base, "triadic")
	assert_int(tri.size()).is_equal(3)
	assert_float(tri[1].h).is_equal_approx(1.0 / 3.0, 0.001)


func test_shades_y_tints() -> void:
	var s: Array = ColorCore.shades(Color.RED, 3)
	assert_int(s.size()).is_equal(3)
	assert_bool(s[2].v < s[0].v).is_true()          # más oscuro al final
	var t: Array = ColorCore.tints(Color.RED, 3)
	assert_bool(t[2].s < t[0].s).is_true()          # más pálido al final


# ── modelo de paint ─────────────────────────────────────────────────────────
func test_make_linear_normaliza_stops() -> void:
	var p := ColorCore.make_linear([Color.RED, Color.BLUE], deg_to_rad(90))
	assert_str(p["type"]).is_equal("linear")
	assert_float(p["angle"]).is_equal_approx(deg_to_rad(90), 0.001)
	assert_int(p["stops"].size()).is_equal(2)
	assert_float(p["stops"][0][0]).is_equal(0.0)
	assert_float(p["stops"][1][0]).is_equal(1.0)


# ── puente a la selección ───────────────────────────────────────────────────
func test_set_color_aplica_a_la_seleccion_con_undo() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var r := _rect(_ab(s))
	await get_tree().process_frame
	t.selected_shapes.assign([r]); InspectorCore._sync_selection()
	HistoryManager.clear()

	ColorCore.set_color(Color.RED, "fill")
	assert_that(r.fill_color).is_equal(Color.RED)
	assert_bool(HistoryManager.can_undo()).is_true()
	assert_bool(ColorCore.recents.has(Color.RED)).is_true()

	HistoryManager.undo(); await get_tree().process_frame
	assert_that(r.fill_color).is_equal(Color.WHITE)
	HistoryManager.clear()


func test_set_paint_degradado_aplica_fill_gradient() -> void:
	var s := _scene(); await get_tree().process_frame
	var t = _tool(s)
	var r := _rect(_ab(s))
	await get_tree().process_frame
	t.selected_shapes.assign([r]); InspectorCore._sync_selection()
	HistoryManager.clear()

	ColorCore.set_paint(ColorCore.make_linear([Color.RED, Color.BLUE], 0.0), "fill")
	assert_bool(r.has_gradient_fill()).is_true()
	assert_int(r.fill_gradient.get_point_count()).is_equal(2)
	assert_that(r.fill_gradient.get_color(0)).is_equal(Color.RED)

	# elegir un color plano quita el degradado
	ColorCore.set_color(Color.GREEN, "fill")
	assert_bool(r.has_gradient_fill()).is_false()
	assert_that(r.fill_color).is_equal(Color.GREEN)
	HistoryManager.clear()
