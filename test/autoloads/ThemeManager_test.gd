extends GdUnitTestSuite

const TM := preload("res://script_gdscript/system/ThemeManager.gd")

func test_theme_manager_aplica_tokens() -> void:
	var tm := get_node("/root/ThemeManager")
	assert_object(tm).is_not_null()
	tm.reset_all_custom_colors()

	tm.set_mode("dark")
	var theme := tm.get_tree().root.theme
	assert_object(theme).is_not_null()
	assert_object(theme.get_stylebox("normal", "AffirmativeButton")).is_not_null()
	assert_object(theme.get_stylebox("normal", "NegativeButton")).is_not_null()
	assert_that(tm.get_color(TM.Slot.AFFIRMATIVE).is_equal_approx(Color(0.188, 0.82, 0.345))).is_true()
	assert_that(tm.get_color(TM.Slot.NEGATIVE).is_equal_approx(Color(1.0, 0.271, 0.227))).is_true()

	tm.set_mode("light")
	assert_that(tm.get_color(TM.Slot.AFFIRMATIVE).is_equal_approx(Color(0.204, 0.78, 0.349))).is_true()
	assert_that(tm.get_color(TM.Slot.PANEL_TEXT).is_equal_approx(Color(0.11, 0.11, 0.118))).is_true()

	tm.set_mode("dark")
