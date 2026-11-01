extends GdUnitTestSuite

## Los avisos al usuario (UserNotices) se muestran: user_notice y los errores
## de exportar / importar, que antes nadie enseñaba en pantalla.

func test_user_notice_y_errores_de_exportar_importar_se_muestran() -> void:
	var un = get_tree().root.get_node("UserNotices")
	var before: int = un.history.size()
	GlobalEvents.user_notice.emit("error", "prueba de aviso")
	GlobalEvents.emit_safe("export_error", "PDF", "disco lleno")
	GlobalEvents.emit_safe("import_error", "SVG", "archivo vacío")
	await get_tree().process_frame
	assert_int(un.history.size() - before).is_equal(3)
	assert_str(String(un.history[-3][1])).is_equal("prueba de aviso")
	assert_str(String(un.history[-2][1])).contains("PDF").contains("disco lleno")
	assert_str(String(un.history[-1][1])).contains("SVG")
	var box: Node = un.get_node("Notices")
	assert_int(box.get_child_count()).is_greater(0)
	assert_int(box.get_child_count()).is_equal(1)   # una cápsula cada vez (Dynamic Island)


## El idioma elegido se guarda en la carpeta del usuario (no en project.godot,
## que en la app instalada no se puede escribir y el idioma se perdía).
func test_idioma_se_recuerda_en_user_y_no_toca_project_godot() -> void:
	var lm = get_tree().root.get_node("LanguageManager")
	var before: String = lm.current_locale
	var proj_before := FileAccess.get_file_as_string("res://project.godot")
	lm.set_locale("fr")
	var cfg := ConfigFile.new()
	assert_int(cfg.load(lm.CONFIG_PATH)).is_equal(OK)
	assert_str(String(cfg.get_value("ui", "locale", ""))).is_equal("fr")
	assert_str(lm._initial_locale()).is_equal("fr")
	assert_str(FileAccess.get_file_as_string("res://project.godot")).is_equal(proj_before)
	lm.set_locale(before)
