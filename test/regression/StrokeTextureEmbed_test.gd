extends GdUnitTestSuite

## VGSE fase 4: la textura de imagen de un trazo de pincel va INCRUSTADA en
## el documento (antes solo la ruta: si la imagen se movía, salía «papel»).

const CS = preload("res://scripts/canvas/canvas_serializer.gd")
const ST = preload("res://script_gdscript/shapes/stroke_textures.gd")

func _img_file(name: String, w: int, h: int) -> String:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.4, 0.8))
	var p := ProjectSettings.globalize_path("user://" + name)
	img.save_png(p)
	return p

func _line(meta: Dictionary) -> Line2D:
	var l := Line2D.new()
	l.name = "Trazo"
	l.points = PackedVector2Array([Vector2.ZERO, Vector2(100, 0)])
	l.set_meta("brush_texture", meta)
	return l

func test_incrustar_reduce_y_sobrevive_al_borrado() -> void:
	var p := _img_file("tex_grande.png", 1500, 900)
	var b64 := ST.embed(p)
	assert_str(b64).is_not_empty()
	DirAccess.remove_absolute(p)
	var t: Texture2D = ST.image_texture(p, b64)
	assert_int(t.get_width()).is_equal(512)
	assert_bool(t == ST.get_texture("paper")).is_false()

func test_documento_antiguo_se_incrusta_al_guardar() -> void:
	var p := _img_file("tex_antigua.png", 64, 64)
	var l := _line({"name": "image", "path": p})
	var d: Dictionary = CS._serialize_element(l)
	var bt: Dictionary = d.get("brush_texture", {})
	assert_str(String(bt.get("png", ""))).is_not_empty()
	DirAccess.remove_absolute(p)
	var n: Node2D = CS._element_from(d)
	var bt2: Dictionary = n.get_meta("brush_texture", {})
	var t: Texture2D = ST.image_texture(String(bt2.get("path", "")), String(bt2.get("png", "")))
	assert_int(t.get_width()).is_equal(64)
	assert_bool(t == ST.get_texture("paper")).is_false()
	l.free()
	n.free()

func test_sin_imagen_ni_copia_sale_papel() -> void:
	var t: Texture2D = ST.image_texture("/no/existe.png", "")
	assert_bool(t == ST.get_texture("paper")).is_true()
