extends GdUnitTestSuite

## API de scripts y complementos (VectopenAPI), ejecución de scripts
## (ScriptRunner) y gestor de complementos (PluginManager) sobre el canvas
## real: crear figuras, propiedades, un paso de deshacer por script,
## errores con su línea, plantillas, instalar/activar/desinstalar.

const CANVAS := "res://scenes/canvas/canvas.tscn"
const Runner = preload("res://script_gdscript/api/script_runner.gd")
const ScriptLib = preload("res://script_gdscript/api/script_library.gd")

var _cfg_backup := ""
var _api: VectopenAPI = null
var _ab: Node2D = null

func before() -> void:
	if FileAccess.file_exists(PluginManager.CONFIG_PATH):
		_cfg_backup = FileAccess.get_file_as_string(PluginManager.CONFIG_PATH)

func after() -> void:
	if _cfg_backup != "":
		var fa := FileAccess.open(PluginManager.CONFIG_PATH, FileAccess.WRITE)
		fa.store_string(_cfg_backup)
	elif FileAccess.file_exists(PluginManager.CONFIG_PATH):
		DirAccess.remove_absolute(PluginManager.CONFIG_PATH)
	for id in ["test_addon_zip", "test_addon_gd", "test_roto"]:
		PluginManager._remove_dir(PluginManager.USER_DIR + id + "/")

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api
	_ab = _api.artboard()
	HistoryManager.clear()

## Los errores de estos casos son a propósito (el script del usuario falla):
## se quitan del monitor de gdUnit como hace assert_error().
func _consume_expected_errors() -> void:
	var mon = GdUnitThreadManager.get_current_context().get_execution_context().error_monitor
	for e in mon.log_entries().duplicate():
		mon.erase_log_entry(e)

func _count() -> int:
	return _api.shapes().size()

# ── API ──────────────────────────────────────────────────────────────────────
func test_crea_cada_tipo_en_el_artboard_activo() -> void:
	assert_object(_ab).is_not_null()
	var n0 := _count()
	var r := _api.add_rect(Vector2(100, 100), Vector2(80, 40), 6)
	var e := _api.add_ellipse(Vector2(200, 100), Vector2(50, 50))
	var p := _api.add_polygon(Vector2(300, 100), 40, 6)
	var st := _api.add_star(Vector2(400, 100), 40, 7, 0.4)
	var path := _api.add_path(PackedVector2Array([Vector2(10, 10), Vector2(90, 40), Vector2(30, 80)]), true)
	var sh := _api.add_shape(PackedVector2Array([Vector2(0, 0), Vector2(60, 0), Vector2(30, 50)]))
	var t := _api.add_text(Vector2(20, 300), "Hola", 30)
	assert_int(_count()).is_equal(n0 + 7)
	assert_str(_api.kind_of(r)).is_equal("rectangle")
	assert_str(_api.kind_of(e)).is_equal("ellipse")
	assert_str(_api.kind_of(p)).is_equal("polygon")
	assert_str(_api.kind_of(st)).is_equal("star")
	assert_str(_api.kind_of(path)).is_equal("path")
	assert_str(_api.kind_of(sh)).is_equal("polygon")
	assert_str(_api.kind_of(t)).is_equal("text")
	assert_int(st.points_count).is_equal(7)
	assert_int(p.sides).is_equal(6)
	# colocación por el centro, en coordenadas del artboard
	assert_vector(_api.get_position(r)).is_equal_approx(Vector2(100, 100), Vector2(0.01, 0.01))
	assert_vector(_api.get_position(sh)).is_equal_approx(Vector2(30, 50.0 / 3.0), Vector2(0.01, 0.01))
	assert_str(String(_api.get_prop(t, "text"))).is_equal("Hola")

func test_transaccion_es_un_solo_paso_de_deshacer() -> void:
	var n0 := _count()
	_api.begin("Lote")
	for i in 5:
		var c := _api.add_ellipse(Vector2(50 + i * 60, 200), Vector2(40, 40))
		_api.set_fill(c, Color.RED)
	_api.end()
	assert_int(_count()).is_equal(n0 + 5)
	assert_str(HistoryManager.get_undo_name()).is_equal("Lote")
	HistoryManager.undo()
	assert_int(_count()).is_equal(n0)
	assert_bool(HistoryManager.can_undo()).is_false()
	HistoryManager.redo()
	assert_int(_count()).is_equal(n0 + 5)
	for s in _api.shapes().slice(n0):
		assert_object(s.fill_color).is_equal(Color.RED)

func test_propiedades_con_deshacer_y_fallback() -> void:
	var r := _api.add_rect(Vector2(100, 100), Vector2(80, 40))
	HistoryManager.clear()
	assert_bool(_api.set_prop(r, "width", 200.0)).is_true()
	assert_float(float(_api.get_prop(r, "width"))).is_equal_approx(200.0, 0.01)
	assert_bool(_api.set_prop(r, "modulate", Color(1, 1, 1, 0.5))).is_true()   # propiedad del nodo
	assert_bool(_api.set_prop(r, "no_existe", 1)).is_false()
	_api.set_position(r, Vector2(300, 250))
	assert_vector(_api.get_position(r)).is_equal_approx(Vector2(300, 250), Vector2(0.01, 0.01))
	HistoryManager.undo()   # posición
	HistoryManager.undo()   # modulate
	HistoryManager.undo()   # width
	assert_float(float(_api.get_prop(r, "width"))).is_equal_approx(80.0, 0.01)
	assert_vector(_api.get_position(r)).is_equal_approx(Vector2(100, 100), Vector2(0.01, 0.01))
	assert_float(r.modulate.a).is_equal_approx(1.0, 0.001)

func test_borrar_duplicar_agrupar_con_deshacer() -> void:
	var a := _api.add_rect(Vector2(100, 100), Vector2(40, 40))
	var b := _api.add_star(Vector2(200, 100), 30)
	var n0 := _count()
	var c := _api.duplicate(a, Vector2(10, 0))
	assert_int(_count()).is_equal(n0 + 1)
	assert_vector(_api.get_position(c)).is_equal_approx(Vector2(110, 100), Vector2(0.01, 0.01))
	var g := _api.group([a, b])
	assert_object(a.get_parent()).is_same(g)
	assert_int(_count()).is_equal(n0)    # a y b dentro del grupo, + grupo, + copia
	HistoryManager.undo()
	assert_object(a.get_parent()).is_same(_ab)
	_api.delete([a, b])
	assert_object(a.get_parent()).is_null()
	HistoryManager.undo()
	assert_object(a.get_parent()).is_same(_ab)
	assert_object(b.get_parent()).is_same(_ab)

# ── scripts ──────────────────────────────────────────────────────────────────
func test_script_rapido_un_paso_de_deshacer_y_salida() -> void:
	var n0 := _count()
	var res: Dictionary = await Runner.run("for i in 3:\n\tapi.add_rect(Vector2(60 + i * 70, 80), Vector2(50, 50))\nprint('listo ', 3)\n", _api, "Mi script")
	assert_bool(res["ok"]).override_failure_message(str(res["errors"])).is_true()
	assert_int(_count()).is_equal(n0 + 3)
	assert_bool("listo 3" in res["output"]).override_failure_message(str(res["output"])).is_true()
	assert_str(HistoryManager.get_undo_name()).is_equal("Mi script")
	HistoryManager.undo()
	assert_int(_count()).is_equal(n0)

func test_error_de_sintaxis_con_la_linea_del_usuario() -> void:
	var errs := Runner.check("var a := 1\nvar b := (a +\n")
	assert_int(errs.size()).is_greater(0)
	assert_int(int(errs[0]["line"])).is_between(2, 3)
	errs = Runner.check("extends VectopenScript\nfunc run() -> void:\n\tvar x: int = \"txt\"\n")
	assert_int(int(errs[0]["line"])).is_equal(3)
	assert_array(Runner.check("api.info('ok')\n")).is_empty()
	_consume_expected_errors()

func test_error_en_ejecucion_deshace_lo_hecho() -> void:
	var n0 := _count()
	var code := "extends VectopenScript\nfunc run() -> void:\n\tapi.add_rect(Vector2(50, 50), Vector2(20, 20))\n\tvar n = null\n\tn.foo()\n"
	var res: Dictionary = await Runner.run(code, _api)
	assert_bool(res["ok"]).is_false()
	assert_int(int(res["errors"][0]["line"])).is_equal(5)
	assert_int(_count()).is_equal(n0)          # el rectángulo se deshizo
	assert_bool(HistoryManager.can_undo()).is_false()
	assert_bool(_api.in_transaction()).is_false()
	_consume_expected_errors()

func test_script_con_await() -> void:
	var res: Dictionary = await Runner.run("extends VectopenScript\nfunc run() -> void:\n\tawait api.wait(0.05)\n\tapi.add_ellipse(Vector2(90, 90), Vector2(30, 30))\n", _api)
	assert_bool(res["ok"]).is_true()
	assert_str(_api.kind_of(_api.shapes()[-1])).is_equal("ellipse")

func test_todas_las_plantillas_compilan_y_corren() -> void:
	for tname in ScriptLib.TEMPLATES:
		assert_array(Runner.check(ScriptLib.template_code(tname))).override_failure_message(tname).is_empty()
	var sel := [_api.add_rect(Vector2(100, 100), Vector2(40, 40)),
		_api.add_star(Vector2(200, 150), 30), _api.add_ellipse(Vector2(300, 100), Vector2(40, 40))]
	for tname in ScriptLib.TEMPLATES:
		_api.select(sel)
		InspectorCore._sync_selection()
		var res: Dictionary = await Runner.run(ScriptLib.template_code(tname), _api, tname)
		assert_bool(res["ok"]).override_failure_message("%s: %s" % [tname, res["errors"]]).is_true()

func test_biblioteca_guardar_renombrar_borrar() -> void:
	var nm := ScriptLib.unique_name("Prueba API")
	var path := ScriptLib.save(nm, "print(1)\n")
	assert_bool(ScriptLib.list().any(func(it) -> bool: return it["name"] == nm)).is_true()
	assert_str(ScriptLib.load_code(path)).is_equal("print(1)\n")
	var p2 := ScriptLib.rename(path, nm + " B")
	assert_bool(FileAccess.file_exists(path)).is_false()
	ScriptLib.remove(p2)
	assert_bool(ScriptLib.list().any(func(it) -> bool: return it["name"].begins_with(nm))).is_false()

# ── complementos ─────────────────────────────────────────────────────────────
func test_complementos_incluidos_se_descubren() -> void:
	var ids := PluginManager.list_addons().map(func(a) -> String: return a["id"])
	for id in ["hello_world", "repetir", "colores"]:
		assert_bool(id in ids).override_failure_message(str(ids)).is_true()
	assert_bool(PluginManager.get_info("repetir")["builtin"]).is_true()

func test_activar_operador_y_desactivar() -> void:
	PluginManager.disable("colores")
	assert_array(_api.operators("colores")).is_empty()
	assert_str(PluginManager.enable("colores")).is_empty()
	assert_int(_api.operators("colores").size()).is_equal(4)
	var shapes := []
	for i in 4:
		shapes.append(_api.add_rect(Vector2(60 + i * 60, 60), Vector2(40, 40)))
	_api.select(shapes)
	HistoryManager.clear()
	assert_bool(_api.run_operator("colores.random")).is_true()
	assert_str(HistoryManager.get_undo_name()).is_equal("Aleatorios")
	var c0: Color = shapes[0].fill_color
	assert_bool(c0 != shapes[1].fill_color).is_true()
	HistoryManager.undo()
	assert_bool(HistoryManager.can_undo()).is_false()   # 4 colores = 1 paso
	PluginManager.disable("colores")
	assert_array(_api.operators("colores")).is_empty()
	assert_bool(_api.run_operator("colores.random")).is_false()
	PluginManager.enable("colores")

func test_repetir_cuadricula_un_paso() -> void:
	PluginManager.enable("repetir")
	var addon: VectopenAddon = PluginManager.get_addon("repetir")
	addon.set_setting("columnas", 3)
	addon.set_setting("filas", 2)
	var r := _api.add_rect(Vector2(100, 100), Vector2(40, 40))
	_api.select([r])
	var n0 := _count()
	HistoryManager.clear()
	assert_bool(_api.run_operator("repetir.grid")).is_true()
	assert_int(_count()).is_equal(n0 + 5)
	HistoryManager.undo()
	assert_int(_count()).is_equal(n0)
	assert_int(addon.get_panels().size()).is_equal(1)

func _zip_addon(zip_path: String, folder: String, main_code: String) -> void:
	var zp := ZIPPacker.new()
	zp.open(zip_path)
	zp.start_file(folder + "/addon.cfg")
	zp.write_file("[addon]\nname=\"Test Zip\"\nversion=\"2.0\"\napi=\"1.0\"\nmain=\"main.gd\"\n".to_utf8_buffer())
	zp.close_file()
	zp.start_file(folder + "/main.gd")
	zp.write_file(main_code.to_utf8_buffer())
	zp.close_file()
	zp.close()

func test_instalar_zip_activar_y_desinstalar() -> void:
	var zip := ProjectSettings.globalize_path("user://test_addon_zip.zip")
	_zip_addon(zip, "test_addon_zip", "extends VectopenAddon\nfunc _enable() -> void:\n\tadd_operator(\"Hacer\", func() -> void: api.add_star(Vector2(50, 50), 20), \"\", \"do\")\n")
	var res := PluginManager.install(zip)
	DirAccess.remove_absolute(zip)
	assert_bool(res["ok"]).override_failure_message(str(res)).is_true()
	assert_str(res["id"]).is_equal("test_addon_zip")
	var info := PluginManager.get_info("test_addon_zip")
	assert_str(info["name"]).is_equal("Test Zip")
	assert_bool(info["builtin"]).is_false()
	assert_str(PluginManager.enable("test_addon_zip")).is_empty()
	var n0 := _count()
	assert_bool(_api.run_operator("test_addon_zip.do")).is_true()
	assert_int(_count()).is_equal(n0 + 1)
	assert_bool(PluginManager.uninstall("test_addon_zip")).is_true()
	assert_bool(DirAccess.dir_exists_absolute(PluginManager.USER_DIR + "test_addon_zip")).is_false()
	assert_dict(PluginManager.get_info("test_addon_zip")).is_empty()
	assert_bool(PluginManager.uninstall("repetir")).is_false()   # incluido: no se borra

func test_instalar_gd_suelto() -> void:
	var src := "user://test_addon_gd.gd"
	var fa := FileAccess.open(src, FileAccess.WRITE)
	fa.store_string("extends VectopenAddon\nfunc _enable() -> void:\n\tadd_operator(\"X\", func() -> void: pass)\n")
	fa.close()
	var res := PluginManager.install(ProjectSettings.globalize_path(src))
	DirAccess.remove_absolute(src)
	assert_bool(res["ok"]).is_true()
	assert_str(PluginManager.enable("test_addon_gd")).is_empty()
	assert_int(_api.operators("test_addon_gd").size()).is_equal(1)
	PluginManager.uninstall("test_addon_gd")

func test_complemento_roto_queda_desactivado_con_error() -> void:
	var zip := ProjectSettings.globalize_path("user://test_roto.zip")
	_zip_addon(zip, "test_roto", "extends VectopenAddon\nfunc _enable() -> void:\n\tvar n = null\n\tn.boom()\n")
	PluginManager.install(zip)
	DirAccess.remove_absolute(zip)
	var err := PluginManager.enable("test_roto")
	assert_str(err).is_not_empty()
	assert_bool(PluginManager.is_enabled("test_roto")).is_false()
	assert_str(PluginManager.get_info("test_roto")["error"]).contains("boom")
	_consume_expected_errors()
	PluginManager.uninstall("test_roto")

## La referencia (ayuda + autocompletado) y el código no se separan.
func test_referencia_coincide_con_los_metodos() -> void:
	var documented := {}
	for e in VectopenAPI.REFERENCE:
		var m := VectopenAPI.reference_method(e)
		documented[m] = true
		assert_bool(_api.has_method(m)).override_failure_message("documentado y no existe: " + m).is_true()
	for m in (_api.get_script() as Script).get_script_method_list():
		var n := String(m["name"])
		if n.begins_with("_") or n == "reference_method":
			continue
		assert_bool(documented.has(n)).override_failure_message("sin documentar: " + n).is_true()

# ── API ampliada ─────────────────────────────────────────────────────────────
const SHADER_OK := "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0, 0.0, 0.0, 1.0); }\n"

func test_shaders_biblioteca_y_aplicar_en_un_paso() -> void:
	var nm := "API test shader"
	assert_array(_api.save_shader(nm, SHADER_OK)).is_empty()
	assert_bool(nm in _api.shaders()).is_true()
	assert_bool(_api.shader_templates().size() > 0).is_true()
	var a := _api.add_star(Vector2(100, 100), 30)
	var b := _api.add_rect(Vector2(200, 100), Vector2(40, 40))
	HistoryManager.clear()
	assert_bool(_api.apply_shader([a, b], nm)).is_true()
	assert_str(String(_api.get_shader(a).get("name", ""))).is_equal(nm)
	assert_str(String(_api.get_shader(b).get("code", ""))).contains("fragment")
	HistoryManager.undo()
	assert_dict(_api.get_shader(a)).is_empty()
	assert_bool(HistoryManager.can_undo()).is_false()
	# plantilla por nombre y código directo
	assert_bool(_api.apply_shader(a, _api.shader_templates()[0])).is_true()
	assert_bool(_api.apply_shader(a, SHADER_OK)).is_true()
	_api.remove_shader(a)
	assert_dict(_api.get_shader(a)).is_empty()
	# no compila → false y nada cambia
	assert_bool(_api.apply_shader(a, "shader_type canvas_item;\nvoid fragment() { COLOR = ; }")).is_false()
	assert_bool(_api.apply_shader(a, "no existe")).is_false()
	for it in ShaderLibT.list():
		if it["name"] == nm:
			ShaderLibT.remove(it["path"])
	_consume_expected_errors()

const ShaderLibT = preload("res://script_gdscript/shapes/shader_library.gd")

func test_efectos_y_filtros() -> void:
	var r := _api.add_rect(Vector2(100, 100), Vector2(60, 60))
	assert_bool("Drop Shadow" in _api.effect_types()).is_true()
	var fx := _api.add_effect(r, "Drop Shadow", {"blur": 12.0})
	assert_float(float(fx["blur"])).is_equal(12.0)
	assert_int((_api.get_prop(r, "effects") as Array).size()).is_equal(1)
	_api.add_filter(r, "grain", {"amount": 50.0})
	assert_int((_api.get_prop(r, "filters") as Array).size()).is_equal(1)
	_api.clear_effects(r)
	_api.clear_filters(r)
	assert_array(_api.get_prop(r, "effects")).is_empty()
	assert_array(_api.get_prop(r, "filters")).is_empty()

func test_orden_alinear_booleana_un_paso() -> void:
	var a := _api.add_rect(Vector2(100, 100), Vector2(80, 80))
	var b := _api.add_rect(Vector2(140, 160), Vector2(80, 80))
	_api.arrange(a, "front")
	assert_int(a.get_index()).is_greater(b.get_index())
	HistoryManager.clear()
	_api.begin("Lote mixto")
	_api.align([a, b], "left")
	var res := _api.boolean("union", [a, b])
	_api.end()
	assert_object(res).is_not_null()
	assert_str(HistoryManager.get_undo_name()).is_equal("Lote mixto")
	HistoryManager.undo()
	assert_bool(HistoryManager.can_undo()).is_false()
	assert_object(a.get_parent()).is_same(_ab)
	assert_float(_api.get_position(b).x).is_equal_approx(140.0, 0.01)

func test_artboard_imagen_exportar() -> void:
	var n0 := _api.artboards().size()
	var ab := _api.add_artboard(Vector2(400, 300), "Extra")
	assert_int(_api.artboards().size()).is_equal(n0 + 1)
	assert_object(_api.artboard()).is_same(ab)
	_api.add_ellipse(Vector2(200, 150), Vector2(100, 100))
	var img := Image.create(20, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var sp := _api.add_image(img, Vector2(50, 50))
	assert_str(_api.kind_of(sp)).is_equal("image")
	assert_vector(sp.position).is_equal(Vector2(40, 45))
	var path := ProjectSettings.globalize_path("user://api_export_test.svg")
	assert_bool(await _api.export(path)).is_true()
	assert_str(FileAccess.get_file_as_string(path)).contains("<svg")
	DirAccess.remove_absolute(path)
	HistoryManager.undo(); HistoryManager.undo(); HistoryManager.undo()
	assert_int(_api.artboards().size()).is_equal(n0)

func test_vectorizar_imagen() -> void:
	if not ClassDB.class_exists("VectorizerJob"):
		return
	var img := Image.create(80, 60, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(10, 10, 40, 30), Color(0.1, 0.3, 0.9))
	var sp := _api.add_image(img, Vector2(200, 200))
	var g := await _api.vectorize(sp, "Logo / icono")
	assert_object(g).is_not_null()
	assert_int(g.get_child_count()).is_greater(0)
	assert_bool(sp.visible).is_false()
	HistoryManager.undo()
	assert_object(g.get_parent()).is_null()
	assert_bool(sp.visible).is_true()
