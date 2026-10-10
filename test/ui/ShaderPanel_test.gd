extends GdUnitTestSuite

## Pestaña Shader: biblioteca (user://shaders), validación con línea de error,
## aplicar con deshacer, guardado en el archivo y capa sobre los filtros.

const Lib = preload("res://script_gdscript/shapes/shader_library.gd")
const TEST_NAME := "__test_shader__"

func after_test() -> void:
	for it in Lib.list():
		if String(it["name"]).begins_with(TEST_NAME):
			Lib.remove(it["path"])

func test_plantillas_compilan_y_los_errores_dan_su_linea() -> void:
	for n in Lib.TEMPLATES:
		assert_array(Lib.validate(Lib.template_code(n))).override_failure_message(n).is_empty()
	var errs: Array = Lib.validate("shader_type canvas_item;\nvoid fragment() {\n\tCOLOR = vec4(1.0)\n}\n")
	assert_int(errs.size()).is_greater(0)
	assert_int(int(errs[0]["line"])).is_equal(4)

func test_biblioteca_guardar_listar_renombrar_eliminar() -> void:
	var code := Lib.template_code("Invertir")
	var p := Lib.save(TEST_NAME, code)
	assert_bool(FileAccess.file_exists(p)).is_true()
	var names: Array = Lib.list().map(func(it): return it["name"])
	assert_array(names).contains([TEST_NAME])
	assert_str(Lib.load_code(p)).is_equal(code)
	var p2 := Lib.rename(p, TEST_NAME + " 2")
	assert_bool(FileAccess.file_exists(p)).is_false()
	assert_str(Lib.load_code(p2)).is_equal(code)
	assert_str(Lib.unique_name(TEST_NAME + " 2")).is_equal(TEST_NAME + " 2 2")
	Lib.remove(p2)
	assert_bool(FileAccess.file_exists(p2)).is_false()

func test_margen_declarado_en_el_codigo() -> void:
	assert_float(Lib.margin_of(Lib.template_code("Onda"))).is_equal(24.0)
	assert_float(Lib.margin_of(Lib.template_code("Invertir"))).is_equal(0.0)

func test_aplicar_con_deshacer_y_guardar_en_el_archivo() -> void:
	var holder: Node2D = auto_free(Node2D.new())
	add_child(holder)
	var r := VectorRectangle.new()
	r.size = Vector2(50, 40)
	holder.add_child(r)
	var sm = get_tree().root.get_node("SelectionManager")
	sm.set_selection([r])
	InspectorCore._sync_selection()
	HistoryManager.clear()
	var val := {"name": "Inv", "code": Lib.template_code("Invertir"), "margin": 0.0, "params": {}, "enabled": true}
	InspectorCore.apply("custom_shader", val)
	await get_tree().process_frame
	assert_bool(r.has_meta("custom_shader")).is_true()
	assert_object(r.get_node_or_null("FilterFx")).is_not_null()   # motor instalado
	# guardar / cargar
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	var data: Array = Ser.serialize_elements(holder)
	assert_bool(data[0].has("custom_shader")).is_true()
	# deshacer quita el shader
	HistoryManager.undo()
	await get_tree().process_frame
	assert_bool(r.has_meta("custom_shader")).is_false()
	sm.set_selection([])
	HistoryManager.clear()

func test_shader_y_filtros_juntos_no_rompen() -> void:
	var holder: Node2D = auto_free(Node2D.new())
	add_child(holder)
	var r := VectorRectangle.new()
	r.size = Vector2(50, 40)
	holder.add_child(r)
	var FilterFx = load("res://script_gdscript/shapes/filter_fx.gd")
	r.set_meta("filters", [FilterFx.make("grain")])
	r.set_meta("custom_shader", {"name": "G", "code": Lib.template_code("Escala de grises"), "enabled": true})
	FilterFx.sync(r)
	await get_tree().process_frame
	var fx = r.get_node("FilterFx")
	assert_bool(fx._cgroup.is_valid()).is_true()
	assert_bool(fx._group.is_valid()).is_true()
	# quitar el shader deja los filtros
	r.remove_meta("custom_shader")
	FilterFx.sync(r)
	await get_tree().process_frame
	assert_bool(fx._cgroup.is_valid()).is_false()
	assert_bool(fx._group.is_valid()).is_true()
