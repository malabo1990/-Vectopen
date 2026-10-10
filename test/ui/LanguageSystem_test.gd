# =============================================================================
# VECTOPEN — PRUEBAS DEL SISTEMA DE IDIOMAS E INTERNACIONALIZACIÓN (SECCIÓN 11)
# RUTA: res://test/ui/LanguageSystem_test.gd
# =============================================================================
extends GdUnitTestSuite

const ModernContextMenuScript := preload("res://script_gdscript/ui/modern/modern_context_menu.gd")
const ModernBottomToolbarScript := preload("res://script_gdscript/ui/modern/modern_bottom_toolbar.gd")

func test_language_manager_locales() -> void:
	var lm := get_node("/root/LanguageManager")
	assert_object(lm).is_not_null()
	var locales: Array = lm.get_locale_list()
	assert_bool(locales.has("en")).is_true()
	assert_bool(locales.has("es")).is_true()
	assert_bool(locales.has("fr")).is_true()
	assert_bool(locales.has("de")).is_true()
	assert_bool(locales.has("pt")).is_true()
	assert_bool(locales.has("ru")).is_true()
	assert_bool(locales.has("zh")).is_true()
	assert_bool(locales.has("ja")).is_true()
	assert_bool(locales.has("ar")).is_true()
	assert_bool(locales.has("hi")).is_true()

func test_translations_loaded_dynamically() -> void:
	var lm := get_node("/root/LanguageManager")
	assert_object(lm).is_not_null()
	var prev_locale: String = lm.current_locale

	lm.set_locale("es")
	assert_str(tr("Select and Move (V)")).is_equal("Seleccionar y Mover (V)")
	assert_str(tr("Rectangle (R)")).is_equal("Rectángulo (R)")
	assert_str(tr("PAGES & SPREADS")).is_equal("PÁGINAS Y PLIEGOS")
	assert_str(tr("TRANSFORM")).is_equal("TRANSFORMACIÓN")

	lm.set_locale("en")
	assert_str(tr("Select and Move (V)")).is_equal("Select and Move (V)")
	assert_str(tr("Rectangle (R)")).is_equal("Rectangle (R)")
	assert_str(tr("PAGES & SPREADS")).is_equal("PAGES & SPREADS")
	assert_str(tr("TRANSFORM")).is_equal("TRANSFORM")

	lm.set_locale("de")
	assert_str(tr("Select and Move (V)")).is_equal("Auswählen und Bewegen (V)")
	assert_str(tr("Rectangle (R)")).is_equal("Rechteck (R)")

	lm.set_locale(prev_locale)

func test_modern_toolbar_reacts_to_language_change() -> void:
	var lm := get_node("/root/LanguageManager")
	assert_object(lm).is_not_null()
	var prev_locale: String = lm.current_locale

	var toolbar = auto_free(ModernBottomToolbarScript.new())
	add_child(toolbar)
	await get_tree().process_frame

	lm.set_locale("en")
	var btn_select: Button = toolbar._buttons.get("select", null)
	assert_object(btn_select).is_not_null()
	assert_str(btn_select.tooltip_text).is_equal("Select and Move (V)")

	lm.set_locale("es")
	assert_str(btn_select.tooltip_text).is_equal("Seleccionar y Mover (V)")

	lm.set_locale(prev_locale)

func test_modern_context_menu_reacts_to_language_change() -> void:
	var lm := get_node("/root/LanguageManager")
	assert_object(lm).is_not_null()
	var prev_locale: String = lm.current_locale

	var menu = auto_free(ModernContextMenuScript.new())
	add_child(menu)
	await get_tree().process_frame

	lm.set_locale("es")
	var copy_btn: Button = menu._items.get("copy", null)
	assert_object(copy_btn).is_not_null()
	var lbl_es: Label = copy_btn.find_child("Name", true, false) as Label
	assert_str(lbl_es.text).is_equal("Copiar")

	lm.set_locale("en")
	# _build_menu() reconstruye todos los botones en cada language_changed
	# (queue_free diferido de los viejos + hijos nuevos ya en el árbol), así
	# que hay que releer _items después de cada cambio de idioma en vez de
	# reusar la referencia capturada antes del rebuild anterior — si no, se
	# lee un botón que quedó en cola de borrado con el texto del idioma viejo.
	copy_btn = menu._items.get("copy", null)
	assert_object(copy_btn).is_not_null()
	var lbl_en: Label = copy_btn.find_child("Name", true, false) as Label
	assert_str(lbl_en.text).is_equal("Copy")

	lm.set_locale(prev_locale)
