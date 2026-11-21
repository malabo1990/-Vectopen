extends GdUnitTestSuite

## Componentes vinculados (VAL-23): crear, copias (colocar y duplicar),
## editar una copia actualiza las demás, posición propia, retoques locales
## con «Sincronizar» apagado, deshacer, desvincular y guardar/abrir.

const CANVAS := "res://scenes/canvas/canvas.tscn"
const SY = preload("res://script_gdscript/shapes/symbols.gd")
const CS = preload("res://scripts/canvas/canvas_serializer.gd")

var _api: VectopenAPI = null

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api
	SY.from_data(SY.container(), {})
	SY.sync_enabled = true
	HistoryManager.clear()

func after_test() -> void:
	SY.sync_enabled = true

func _button(y: float) -> Array:
	var bg := _api.add_rect(Vector2(100, y), Vector2(160, 40), 8.0, "Fondo")
	_api.set_fill(bg, Color("#3355ff"))
	var tx := _api.add_text(Vector2(60, y - 10), "Continuar", 16, Color.WHITE)
	tx.name = "Etiqueta"
	return [bg, tx]

func _fill(root: Node) -> Color:
	return root.find_child("Fondo*", true, false).fill_color

func _settle() -> void:
	SY.sync_now()
	await get_tree().process_frame

func test_crear_y_editar_una_copia_actualiza_las_demas() -> void:
	var b := _button(100)
	var g := _api.make_symbol(b, "Botón")
	assert_object(g).is_not_null()
	var id := _api.symbol_of(g)
	assert_str(id).is_not_empty()
	var c1 := _api.place_symbol(id, Vector2(300, 300))
	var c2 := _api.duplicate(g, Vector2(0, 200))
	assert_int(_api.symbols()[0]["count"]).is_equal(3)
	assert_str(_api.symbol_of(c2)).is_equal(id)
	# Editar el fondo de c1 → g y c2 cambian
	_api.set_fill(c1.find_child("Fondo*", true, false), Color("#e23d6b"))
	await _settle()
	assert_bool(_fill(g).is_equal_approx(Color("#e23d6b"))).is_true()
	assert_bool(_fill(c2).is_equal_approx(Color("#e23d6b"))).is_true()
	# Cada copia conserva su posición
	assert_bool(c1.position.distance_to(g.position) > 50.0).is_true()
	# Mover la copia entera no afecta a las demás
	var p2 := c2.position
	_api.move(c1, Vector2(40, 0))
	await _settle()
	assert_bool(c2.position.is_equal_approx(p2)).is_true()

func test_deshacer_vuelve_a_propagar() -> void:
	var g := _api.make_symbol(_button(100), "Botón")
	var c1 := _api.place_symbol(_api.symbol_of(g), Vector2(300, 300))
	await _settle()
	_api.set_fill(g.find_child("Fondo*", true, false), Color.RED)
	await _settle()
	assert_bool(_fill(c1).is_equal_approx(Color.RED)).is_true()
	_api.undo()
	await _settle()
	assert_bool(_fill(c1).is_equal_approx(Color("#3355ff"))).is_true()
	assert_bool(_fill(g).is_equal_approx(Color("#3355ff"))).is_true()

func test_retoques_locales_sin_sincronizar() -> void:
	var g := _api.make_symbol(_button(100), "Botón")
	var c1 := _api.place_symbol(_api.symbol_of(g), Vector2(300, 300))
	await _settle()
	_api.set_symbol_sync(false)
	_api.set_prop(c1.find_child("Etiqueta*", true, false), "text", "Cancelar")
	await _settle()
	assert_str(String(_api.get_prop(g.find_child("Etiqueta*", true, false), "text"))).is_equal("Continuar")
	_api.set_symbol_sync(true)
	# Cambiar el color en g: c1 lo recibe y conserva su texto retocado
	_api.set_fill(g.find_child("Fondo*", true, false), Color.GREEN)
	await _settle()
	assert_bool(_fill(c1).is_equal_approx(Color.GREEN)).is_true()
	assert_str(String(_api.get_prop(c1.find_child("Etiqueta*", true, false), "text"))).is_equal("Cancelar")

func test_desvincular() -> void:
	var g := _api.make_symbol(_button(100), "Botón")
	var c1 := _api.place_symbol(_api.symbol_of(g), Vector2(300, 300))
	await _settle()
	assert_bool(_api.detach_symbol(c1)).is_true()
	_api.set_fill(c1.find_child("Fondo*", true, false), Color.BLACK)
	await _settle()
	assert_bool(_fill(g).is_equal_approx(Color("#3355ff"))).is_true()
	assert_str(_api.symbol_of(c1)).is_empty()

func test_guardar_y_abrir() -> void:
	var g := _api.make_symbol(_button(100), "Botón")
	var id := _api.symbol_of(g)
	_api.place_symbol(id, Vector2(300, 300))
	await _settle()
	var path := "user://test_symbols.vtp"
	var c := SY.container()
	assert_bool(CS.write_vtc(path, c)).is_true()
	SY.from_data(c, {})
	CS.rebuild_from_vtc(c, path)
	await get_tree().process_frame
	await get_tree().process_frame
	var inst := SY.instances(id)
	assert_int(inst.size()).is_equal(2)
	assert_str(String(_api.symbols()[0]["name"])).is_equal("Botón")
	# Abrir no propaga nada; editar sí
	assert_int(SY.sync_now()).is_equal(0)
	_api.set_fill(inst[0].find_child("Fondo*", true, false), Color.ORANGE)
	await _settle()
	assert_bool(_fill(inst[1]).is_equal_approx(Color.ORANGE)).is_true()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
