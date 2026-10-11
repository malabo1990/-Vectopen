extends GdUnitTestSuite

## Plugin «Vectopen» para Godot (integrations/godot/addons/vectopen): lee
## un VOP exportado por Vectopen y crea solo nodos NATIVOS (sin scripts).

const CANVAS := "res://scenes/canvas/canvas.tscn"
const Reader = preload("res://integrations/godot/addons/vectopen/vop_reader.gd")

func _scripts_in(n: Node) -> int:
	var c := 1 if n.get_script() != null else 0
	for ch in n.get_children():
		c += _scripts_in(ch)
	return c

func test_vop_a_escena_nativa() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	var api: VectopenAPI = PluginManager.api
	for c in api.shapes():
		c.get_parent().remove_child(c)
		c.queue_free()
	api.add_rect(Vector2(100, 100), Vector2(80, 40), 8)
	var st := api.add_star(Vector2(300, 100), 40)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color.RED, Color.BLUE])
	st.fill_gradient = g
	api.import_svg('<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0 H100 V100 H0 Z M25 25 V75 H75 V25 Z" fill="#00f" fill-rule="evenodd"/></svg>', Vector2(400, 400))
	api.add_text(Vector2(20, 300), "Hola", 30)
	var data: Dictionary = JSON.parse_string(JSON.stringify(ImportExportManager.vop_data(api.artboard())))
	var root: Node2D = auto_free(Reader.build(data, {"name": "prueba", "include_background": false}))
	assert_int(_scripts_in(root)).is_equal(0)
	# el texto llega como curvas (forma exacta de la fuente), no como Label
	assert_int(root.find_children("*", "Label", true, false).size()).is_equal(0)
	var polys := root.find_children("*", "Polygon2D", true, false)
	assert_int(polys.size()).is_greater_equal(4)   # rect, estrella, anillo + letras
	# degradado → textura en el Polygon2D de la estrella
	assert_bool(polys.any(func(p) -> bool: return p.texture is GradientTexture2D)).is_true()
	# anillo con agujero: el centro (450,450) NO está relleno, el borde sí
	var filled_center := false
	var filled_border := false
	for p in polys:
		if Geometry2D.is_point_in_polygon(Vector2(450, 450), p.polygon):
			filled_center = true
		if Geometry2D.is_point_in_polygon(Vector2(410, 450), p.polygon):
			filled_border = true
	assert_bool(filled_border).is_true()
	assert_bool(filled_center).is_false()
	# rechaza archivos que no son VOP
	var bad := ProjectSettings.globalize_path("user://no_vop.vop")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string('{"format": "otro"}')
	f.close()
	assert_object(Reader.load_scene(bad)).is_null()
	DirAccess.remove_absolute(bad)
