extends GdUnitTestSuite

## Pestaña Script: módulo Scripts (ejecutar desde el editor, errores en la
## consola, biblioteca) y módulo Complementos (fichas, activar, operadores,
## panel del complemento, instalar).

const CANVAS := "res://scenes/canvas/canvas.tscn"
const ScriptPanel = preload("res://script_gdscript/ui/panels/effects/script_panel.gd")

var _cfg_backup := ""
var _panel: Node = null

func before() -> void:
	if FileAccess.file_exists(PluginManager.CONFIG_PATH):
		_cfg_backup = FileAccess.get_file_as_string(PluginManager.CONFIG_PATH)

func after() -> void:
	if _cfg_backup != "":
		var fa := FileAccess.open(PluginManager.CONFIG_PATH, FileAccess.WRITE)
		fa.store_string(_cfg_backup)
	PluginManager._remove_dir(PluginManager.USER_DIR + "test_panel_gd/")

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	_panel = auto_free(ScriptPanel.new())
	add_child(_panel)
	await get_tree().process_frame
	HistoryManager.clear()

func test_ejecutar_desde_el_editor() -> void:
	var api: VectopenAPI = PluginManager.api
	var n0 := api.shapes().size()
	_panel.set_code("Prueba", "for i in 4:\n\tapi.add_ellipse(Vector2(50 + i * 40, 50), Vector2(30, 30))\nprint('ok panel')\n")
	var res: Dictionary = await _panel.run_current()
	assert_bool(res["ok"]).is_true()
	assert_int(api.shapes().size()).is_equal(n0 + 4)
	assert_str(_panel._console.get_parsed_text()).contains("ok panel")
	HistoryManager.undo()
	assert_int(api.shapes().size()).is_equal(n0)

func test_error_marca_la_linea() -> void:
	_panel.set_code("Malo", "var a = null\nprint(1)\na.x()\n")
	var res: Dictionary = await _panel.run_current()
	assert_bool(res["ok"]).is_false()
	assert_str(_panel._console.get_parsed_text()).contains("Línea 3")
	assert_bool(2 in _panel._errors).is_true()
	assert_int(_panel._code.get_caret_line()).is_equal(2)
	var mon = GdUnitThreadManager.get_current_context().get_execution_context().error_monitor
	for e in mon.log_entries().duplicate():
		mon.erase_log_entry(e)

func test_sintaxis_al_escribir() -> void:
	_panel.set_code("x", "var a := (1 +\n")
	assert_str(_panel._status.text).contains("Línea")
	_panel.set_code("x", "print(1)\n")
	assert_str(_panel._status.text).contains("✓")
	var mon = GdUnitThreadManager.get_current_context().get_execution_context().error_monitor
	for e in mon.log_entries().duplicate():
		mon.erase_log_entry(e)

func test_fichas_de_complementos_y_operadores() -> void:
	PluginManager.enable("repetir")
	PluginManager.disable("hello_world")
	_panel.show_module("addons")
	_panel.refresh_addons()
	var card: Node = _panel._addon_list.get_node("Addon_repetir")
	assert_object(card).is_not_null()
	assert_bool(card.find_child("Enabled", true, false).button_pressed).is_true()
	var ops := card.find_child("Operators", true, false)
	assert_int(ops.get_child_count()).is_equal(2)
	assert_object(card.find_child("AddonPanelHost", true, false)).is_not_null()
	var off: Node = _panel._addon_list.get_node("Addon_hello_world")
	assert_object(off.find_child("Operators", true, false)).is_null()
	# activar desde la casilla
	off.find_child("Enabled", true, false).button_pressed = true
	assert_bool(PluginManager.is_enabled("hello_world")).is_true()
	await get_tree().process_frame
	var on: Node = _panel._addon_list.get_node("Addon_hello_world")
	assert_object(on.find_child("Operators", true, false)).is_not_null()
	PluginManager.disable("hello_world")
	# el panel del complemento sobrevive a reconstruir la lista
	_panel.refresh_addons()
	_panel.refresh_addons()
	var addon: VectopenAddon = PluginManager.get_addon("repetir")
	assert_bool(is_instance_valid(addon.get_panels()[0])).is_true()

func test_filtro_e_instalar() -> void:
	_panel._addon_filter.text = "colores"
	_panel.refresh_addons()
	assert_int(_panel._addon_list.get_child_count()).is_equal(1)
	_panel._addon_filter.text = ""
	var src := "user://test_panel_gd.gd"
	var fa := FileAccess.open(src, FileAccess.WRITE)
	fa.store_string("extends VectopenAddon\nfunc _enable() -> void:\n\tadd_operator(\"Uno\", func() -> void: pass)\n")
	fa.close()
	var res: Dictionary = _panel.install_from(ProjectSettings.globalize_path(src))
	DirAccess.remove_absolute(src)
	assert_bool(res["ok"]).is_true()
	assert_bool(PluginManager.is_enabled("test_panel_gd")).is_true()
	PluginManager.uninstall("test_panel_gd")

func test_autocompletado_api() -> void:
	_panel.set_code("x", "api.add_")
	_panel._code.set_caret_line(0)
	_panel._code.set_caret_column(8)
	_panel._on_completion()
	var opts: Array = _panel._code.get_code_completion_options()
	assert_int(opts.size()).is_greater(5)
	assert_bool(opts.all(func(o) -> bool: return String(o["insert_text"]).begins_with("add"))).is_true()
