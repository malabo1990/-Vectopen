extends GdUnitTestSuite

const _GridClass = preload("res://script_gdscript/ui/PaletteSaveGrid.gd")

func _grid() -> GridContainer:
	return auto_free(_GridClass.new())

func _scene(color: Color) -> Array:
	var root: Node2D = auto_free(Node2D.new())
	var box: BoxContainer = BoxContainer.new()
	box.name = "BoxContainer"
	var cr: ColorRect = ColorRect.new()
	cr.name = "ColorRect_fill"
	cr.color = color
	box.add_child(cr)

	var sb: BoxContainer = BoxContainer.new()
	sb.name = "save_color"
	var grid: GridContainer = _grid()
	var btn: Button = Button.new()
	btn.text = "+"
	grid.add_child(btn)
	sb.add_child(grid)

	var ob: BoxContainer = BoxContainer.new()
	ob.name = "BoxContainer"
	ob.add_child(box)
	ob.add_child(sb)

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "MarginContainer"
	margin.add_child(ob)

	root.add_child(margin)
	add_child(root)
	grid._find_add_button()
	return [grid, cr]

func test_find_add_button_with_button() -> void:
	var grid: GridContainer = _grid()
	var btn: Button = Button.new()
	btn.text = "+"
	grid.add_child(btn)

	grid._find_add_button()

	assert_object(grid.add_button).is_not_null()
	assert_object(grid.add_button).is_same(btn)

func test_find_add_button_without_button() -> void:
	var grid: GridContainer = _grid()
	var label: Label = Label.new()
	grid.add_child(label)

	grid._find_add_button()

	assert_object(grid.add_button).is_null()

func test_on_add_pressed_appends_color() -> void:
	DirAccess.remove_absolute("user://vectopen_palette.cfg")
	var r = _scene(Color.RED)
	var grid: GridContainer = r[0]

	assert_int(grid.saved_colors.size()).is_equal(0)
	grid._on_add_pressed()
	assert_int(grid.saved_colors.size()).is_equal(1)
	assert_that(grid.saved_colors[0]).is_equal(Color.RED)

func test_on_add_pressed_persists_to_file() -> void:
	DirAccess.remove_absolute("user://vectopen_palette.cfg")
	var r = _scene(Color.GREEN)
	var grid: GridContainer = r[0]

	grid._on_add_pressed()
	grid._on_add_pressed()

	var cfg: ConfigFile = ConfigFile.new()
	assert_that(cfg.load("user://vectopen_palette.cfg")).is_equal(OK)
	var arr = cfg.get_value("palette", "colors", [])
	assert_int(arr.size()).is_equal(2)
	assert_that(arr[0]).is_equal(Color.GREEN)
	assert_that(arr[1]).is_equal(Color.GREEN)

func test_refresh_replaces_swatches() -> void:
	DirAccess.remove_absolute("user://vectopen_palette.cfg")
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("palette", "colors", [Color.RED, Color.BLUE])
	cfg.save("user://vectopen_palette.cfg")

	var grid: GridContainer = _grid()
	var btn: Button = Button.new()
	btn.text = "+"
	grid.add_child(btn)

	grid._load_colors()
	grid._refresh()

	var colors_found := 0
	for child in grid.get_children():
		if child is ColorRect and child != btn:
			var cr := child as ColorRect
			if cr.color == Color.RED or cr.color == Color.BLUE:
				colors_found += 1
	assert_int(colors_found).is_equal(2)

func test_refresh_creates_swatches() -> void:
	DirAccess.remove_absolute("user://vectopen_palette.cfg")
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("palette", "colors", [Color.YELLOW, Color.CYAN])
	cfg.save("user://vectopen_palette.cfg")

	var grid: GridContainer = _grid()
	var btn: Button = Button.new()
	btn.text = "+"
	grid.add_child(btn)

	grid._load_colors()
	grid._refresh()

	var swatches := 0
	for child in grid.get_children():
		if child is ColorRect and child != btn:
			swatches += 1
	assert_int(swatches).is_equal(2)

func test_load_colors_restores_saved() -> void:
	DirAccess.remove_absolute("user://vectopen_palette.cfg")
	var grid: GridContainer = _grid()

	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("palette", "colors", [Color.AQUA, Color(0.0, 0.0, 0.5, 1.0)])
	cfg.save("user://vectopen_palette.cfg")

	grid._load_colors()

	assert_int(grid.saved_colors.size()).is_equal(2)
	assert_that(grid.saved_colors[0]).is_equal(Color.AQUA)
	assert_that(grid.saved_colors[1]).is_equal(Color(0.0, 0.0, 0.5, 1.0))

func test_load_colors_empty_file() -> void:
	DirAccess.remove_absolute("user://vectopen_palette.cfg")
	var grid: GridContainer = _grid()

	grid._load_colors()

	assert_array(grid.saved_colors).is_empty()

func test_on_swatch_clicked_updates_color_rect() -> void:
	var r = _scene(Color.WHITE)
	var grid: GridContainer = r[0]
	var cr: ColorRect = r[1]

	var swatch: ColorRect = ColorRect.new()
	swatch.color = Color.TEAL

	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true

	grid._on_swatch_clicked(event, swatch)

	assert_that(cr.color).is_equal(Color.TEAL)
