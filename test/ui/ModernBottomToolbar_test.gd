extends GdUnitTestSuite

const ModernBottomToolbarClass = preload("res://script_gdscript/ui/modern/modern_bottom_toolbar.gd")

## _create_tool_button cargaba los iconos con load() directo: los SVG de
## icon/UI/ traen stroke #000000 fijo, y _sync_active_tool tiñe con
## btn.modulate (multiplica) — negro × cualquier color sigue dando negro, así
## que los iconos de la barra inferior (seleccionar/rectángulo/elipse/
## estrella/pluma/texto) no se adaptaban al tema. Mismo bug que
## layers_system.gd, mismo arreglo: _icon_blanco fuerza los píxeles opacos a
## blanco para que el modulate sí pueda teñirlos.

func test_icon_blanco_convierte_pixeles_opacos_a_blanco_preservando_alfa() -> void:
	var tex: Texture2D = ModernBottomToolbarClass._icon_blanco("res://icon/UI/square.svg")
	assert_object(tex).is_not_null()

	var img := tex.get_image()
	assert_object(img).is_not_null()

	var vio_algun_pixel_opaco := false
	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			if px.a > 0.0:
				vio_algun_pixel_opaco = true
				assert_float(px.r).is_equal_approx(1.0, 0.01)
				assert_float(px.g).is_equal_approx(1.0, 0.01)
				assert_float(px.b).is_equal_approx(1.0, 0.01)
	assert_bool(vio_algun_pixel_opaco).is_true()

func test_boton_de_herramienta_usa_el_icono_blanqueado() -> void:
	var toolbar = auto_free(ModernBottomToolbarClass.new())
	add_child(toolbar)
	await get_tree().process_frame

	var btn: Button = toolbar._buttons.get("rectangle")
	assert_object(btn).is_not_null()
	assert_object(btn.icon).is_not_null()

	var img := btn.icon.get_image()
	var found_opaque := false
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				found_opaque = true
				assert_bool(img.get_pixel(x, y).is_equal_approx(Color(1, 1, 1, img.get_pixel(x, y).a))).is_true()
	assert_bool(found_opaque).is_true()
