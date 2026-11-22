extends GdUnitTestSuite
## Mac Intel sin vectorizador IA: mensaje claro para el usuario.

const VP = preload("res://script_gdscript/ui/panels/effects/vectorize_panel.gd")

func test_mac_intel_explica_la_plataforma() -> void:
	var t := VP.unavailable_reason("macOS", "x86_64")
	assert_str(t).contains("Mac con procesador Intel")
	assert_str(t).contains("Apple Silicon")

func test_otros_sistemas_mensaje_general() -> void:
	var t := VP.unavailable_reason("Windows", "x86_64")
	assert_str(t).not_contains("Intel")
	assert_str(t).contains("Reinstala")
	assert_str(VP.unavailable_reason("macOS", "arm64")).not_contains("procesador Intel")

func test_android_explica_que_aun_no_hay_vectorizador_en_movil() -> void:
	var t := VP.unavailable_reason("Android", "arm64")
	assert_str(t).contains("móviles")
	assert_str(t).not_contains("Reinstala")
