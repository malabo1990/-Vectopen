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

## VAL-59: duplicar «Diapositiva 2» da «Diapositiva 3», no «Diapositiva 2 2».
func test_duplicar_nombre_numerado_sigue_la_serie() -> void:
	var p := Node.new()
	for nm in ["Diapositiva", "Diapositiva 2"]:
		var c := Node.new()
		c.name = nm
		p.add_child(c)
	assert_str(NameUtils.unique_child_name(p, "Diapositiva 2")).is_equal("Diapositiva 3")
	assert_str(NameUtils.unique_name_in({"Rect 2": true}, "Rect 2")).is_equal("Rect 3")
	p.free()
