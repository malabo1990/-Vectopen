extends GdUnitTestSuite

## Tamaño automático de la interfaz según la pantalla (ui_scale.scale_for).

const UIScale = preload("res://script_gdscript/system/ui_scale.gd")

func test_monitores_de_escritorio_sin_cambios() -> void:
	# Huion Kamvas 20 / monitor Full HD normal: 100 %
	assert_float(UIScale.scale_for(Vector2(1920, 1080), 110.0)).is_equal_approx(1.0, 0.001)
	# 27" 2560 × 1440: 125 %
	assert_float(UIScale.scale_for(Vector2(2560, 1440), 109.0)).is_equal_approx(1.25, 0.001)
	# 4K (27" o 15"): 200 %
	assert_float(UIScale.scale_for(Vector2(3840, 2160), 163.0)).is_equal_approx(2.0, 0.001)
	assert_float(UIScale.scale_for(Vector2(3840, 2160), 290.0)).is_equal_approx(2.0, 0.001)

func test_portatil_pequeno_algo_mas_compacto() -> void:
	assert_float(UIScale.scale_for(Vector2(1366, 768), 108.0)).is_equal_approx(0.9, 0.001)
	assert_float(UIScale.scale_for(Vector2(1024, 600), 118.0)).is_equal_approx(0.85, 0.001)

## Antes: una tableta o móvil de 440 ppp quedaba al 85 % (ilegible) porque la
## regla de «pantalla pequeña» anulaba la del DPI.
func test_tableta_densa_amplia_sin_salirse() -> void:
	var s := UIScale.scale_for(Vector2(2340, 1080), 440.0)
	assert_float(s).is_equal_approx(1.5, 0.001)
	assert_bool(2340.0 / s >= 1280.0 and 1080.0 / s >= 720.0).is_true()
	# Tableta de 10" 2000 × 1200 a 240 ppp
	var t := UIScale.scale_for(Vector2(2000, 1200), 240.0)
	assert_float(t).is_greater_equal(1.5)
	assert_bool(2000.0 / t >= 1280.0 and 1200.0 / t >= 720.0).is_true()

## Escala del sistema (Wayland / macOS) en un portátil Full HD al 150 %:
## antes bajaba al 85 %.
func test_escala_del_sistema_se_respeta_si_cabe() -> void:
	assert_float(UIScale.scale_for(Vector2(1920, 1080), 157.0, 1.5)).is_equal_approx(1.5, 0.001)
	assert_float(UIScale.scale_for(Vector2(2880, 1800), 220.0, 2.0)).is_equal_approx(2.0, 0.001)
