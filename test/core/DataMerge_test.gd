extends GdUnitTestSuite
## Combinación de datos (informe §5): leer CSV y sustituir {campo}.

const DM = preload("res://script_gdscript/shapes/data_merge.gd")

func test_csv_punto_y_coma_con_comillas() -> void:
	var rows := DM.parse_csv(FileAccess.get_file_as_string("res://test/fixtures/data_merge/productos.csv"))
	assert_int(rows.size()).is_equal(5)
	assert_str(String(rows[0]["nombre"])).is_equal("Silla Nórdica")
	assert_str(String(rows[2]["nombre"])).is_equal("Lámpara \"Luna\"")
	assert_str(String(rows[1]["precio"])).is_equal("149 €")

func test_csv_coma_y_campos_que_faltan() -> void:
	var rows := DM.parse_csv("a,b\n1,2\n3\n")
	assert_int(rows.size()).is_equal(2)
	assert_str(String(rows[1]["b"])).is_equal("")

func test_rellenar_sin_tocar_numeros_de_pagina() -> void:
	var t := DM.fill("{nombre} — {precio} · pág. {pág} / {total} · {otro}", {"nombre": "Mesa", "precio": "149 €"})
	assert_str(t).is_equal("Mesa — 149 € · pág. {pág} / {total} · {otro}")
	assert_array(Array(DM.fields_in("{nombre} {pág} {precio}"))).is_equal(["nombre", "precio"])
