extends GdUnitTestSuite

## Nombres de capa limpios y únicos (estilo profesional): "Base", luego "Base 2"…

func test_nombre_libre_se_devuelve_tal_cual() -> void:
	var p: Node = auto_free(Node.new())
	assert_str(NameUtils.unique_child_name(p, "Rectángulo")).is_equal("Rectángulo")


func test_colision_añade_numero_con_espacio() -> void:
	var p: Node = auto_free(Node.new())
	add_child(p)
	var a := Node.new(); a.name = "Círculo"; p.add_child(a)
	assert_str(NameUtils.unique_child_name(p, "Círculo")).is_equal("Círculo 2")

	var b := Node.new(); b.name = "Círculo 2"; p.add_child(b)
	assert_str(NameUtils.unique_child_name(p, "Círculo")).is_equal("Círculo 3")


func test_sin_padre_no_revienta() -> void:
	assert_str(NameUtils.unique_child_name(null, "Grupo")).is_equal("Grupo")


func test_base_vacia_usa_capa() -> void:
	assert_str(NameUtils.unique_child_name(null, "   ")).is_equal("Capa")
