extends GdUnitTestSuite

## Puente con la extensión nativa vectopen_io: usa Rust cuando puede, cae a
## GDScript cuando no, y un archivo roto nunca tumba la app.

const NativeIO = preload("res://script_gdscript/system/native_io.gd")
const SvgImport = preload("res://script_gdscript/system/svg_import.gd")
const FIX := "res://test/fixtures/import/"

var _dir := ""

func before_test() -> void:
	_dir = ProjectSettings.globalize_path("user://native_io_test")
	DirAccess.make_dir_recursive_absolute(_dir)

func after_test() -> void:
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)

func _write(name: String, text: String) -> String:
	var p := _dir.path_join(name)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return p

func test_la_extension_nativa_carga() -> void:
	assert_bool(NativeIO.is_native()).override_failure_message("vectopen_io no cargó (¿falta compilar rust/build_linux.sh?)").is_true()
	assert_bool("svg" in NativeIO.native().import_extensions()).is_true()

func test_svg_nativo_igual_que_gdscript() -> void:
	var nat := NativeIO.parse_file(FIX + "sample.svg")
	var gd := SvgImport.parse(FileAccess.get_file_as_string(FIX + "sample.svg"))
	assert_str(String(nat["engine"])).is_equal("nativo")
	assert_int((nat["items"] as Array).size()).is_equal((gd["items"] as Array).size())
	assert_vector(Vector2(nat["size"])).is_equal_approx(Vector2(gd["size"]), Vector2(0.01, 0.01))
	# Los nodos editables se construyen igual con los dos motores.
	var g := SvgImport.build(nat, "x")
	assert_int(g.get_child_count()).is_equal((nat["items"] as Array).size())
	g.free()

func test_formato_aun_no_nativo_usa_gdscript() -> void:
	var d := NativeIO.parse_file(FIX + "sample.eps")
	assert_str(String(d["engine"])).is_equal("gdscript")
	assert_bool((d["items"] as Array).is_empty()).is_false()

func test_svg_roto_no_tumba_y_explica() -> void:
	var d := NativeIO.parse_file(_write("roto.svg", "<svg><g><<<"))
	assert_bool((d["items"] as Array).is_empty()).is_true()
	assert_str(String(d.get("error", ""))).is_not_empty()

func test_svg_con_imagen_incrustada_y_degradado() -> void:
	# PNG 1×1 rojo incrustado + rectángulo con degradado.
	var png := "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
	var p := _write("mix.svg", """<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10">
		<linearGradient id="g"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#fff"/></linearGradient>
		<rect width="10" height="10" fill="url(#g)"/>
		<image x="10" width="10" height="10" href="data:image/png;base64,%s"/></svg>""" % png)
	var d := NativeIO.parse_file(p)
	var kinds := (d["items"] as Array).map(func(it): return it["t"])
	assert_array(kinds).contains_exactly(["path", "image"])
	assert_bool(d["items"][0]["grad"] is Dictionary).is_true()
	var img: Image = d["items"][1]["image"]
	assert_vector(Vector2(img.get_size())).is_equal(Vector2(1, 1))
	assert_vector(Transform2D(d["items"][1]["xf"]) * Vector2(1, 1)).is_equal_approx(Vector2(20, 10), Vector2(0.01, 0.01))
