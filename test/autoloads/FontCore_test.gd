extends GdUnitTestSuite

## Sistema core de tipografía: enumeración (SO + bundled), búsqueda, resolución
## de spec → Font, y pool de RID sin fugas.

func test_familias_incluye_la_empaquetada() -> void:
	var fams: PackedStringArray = FontCore.list_families()
	assert_bool(fams.has("Inter")).is_true()
	assert_bool(fams.size() >= 1).is_true()


func test_busqueda_filtra_por_subcadena() -> void:
	var hit: PackedStringArray = FontCore.search("inter")
	assert_bool(hit.has("Inter")).is_true()
	var none: PackedStringArray = FontCore.search("__no_existe_xyz__")
	assert_bool(none.is_empty()).is_true()
	var all: PackedStringArray = FontCore.search("")
	assert_int(all.size()).is_equal(FontCore.list_families().size())


func test_get_font_bundled_y_variacion_de_peso() -> void:
	var regular: Font = FontCore.get_font(FontCore.make_spec("Inter", 400, false))
	assert_object(regular).is_instanceof(FontFile)

	var bold: Font = FontCore.get_font(FontCore.make_spec("Inter", 700, false))
	assert_object(bold).is_instanceof(FontVariation)
	# cacheado: misma spec → mismo recurso
	assert_object(FontCore.get_font(FontCore.make_spec("Inter", 700, false))).is_same(bold)


func test_get_font_familia_desconocida_cae_en_default() -> void:
	var f: Font = FontCore.get_font(FontCore.make_spec("__NoSuchFamily__", 400, false))
	assert_object(f).is_not_null()   # SystemFont con allow_system_fallback


func test_spec_from_node_lee_metas() -> void:
	var n: Node2D = auto_free(Node2D.new())
	n.set_meta("font_family", "Inter")
	n.set_meta("font_weight", 600)
	n.set_meta("font_italic", true)
	var spec: Dictionary = FontCore.spec_from_node(n)
	assert_str(spec["family"]).is_equal("Inter")
	assert_int(spec["weight"]).is_equal(600)
	assert_bool(spec["italic"]).is_true()


func test_font_bytes_de_bundled_no_vacio() -> void:
	var spec: Dictionary = FontCore.make_spec("Inter", 400, false)
	var bytes: PackedByteArray = FontCore.font_bytes(spec)
	assert_int(bytes.size()).is_greater(1000)   # el .ttf de Inter


func test_system_font_path_de_bundled_apunta_al_ttf() -> void:
	var p: String = FontCore.system_font_path(FontCore.make_spec("Inter", 400, false))
	assert_str(p).ends_with("Inter-Regular.ttf")


func test_describe_texto_legible() -> void:
	assert_str(FontCore.describe(FontCore.make_spec("Inter", 400, false))).is_equal("Inter · Regular")
	assert_str(FontCore.describe(FontCore.make_spec("Arial", 700, true))).is_equal("Arial · Bold Italic")
