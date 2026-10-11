extends GdUnitTestSuite

## Recursos (biblioteca reutilizable) y paquetes .vopassets.

const CANVAS := "res://scenes/canvas/canvas.tscn"
const Lib = preload("res://script_gdscript/system/asset_library.gd")
var _api: VectopenAPI
var _dir := ""

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api
	for c in _api.shapes():
		c.get_parent().remove_child(c)
		c.queue_free()
	_dir = ProjectSettings.globalize_path("user://assets_test")
	PluginManager._remove_dir(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	Lib._root_override = _dir.path_join("lib")

func after_test() -> void:
	Lib._root_override = ""
	PluginManager._remove_dir(_dir)

func test_categorias() -> void:
	assert_str(String(Lib.categories()[0]["name"])).is_equal("General")
	var id := Lib.add_category("Logos")
	assert_str(String(Lib.category(id)["name"])).is_equal("Logos")
	assert_str(String(Lib.category(Lib.add_category("Logos"))["name"])).is_equal("Logos 2")
	Lib.rename_category(id, "Marcas")
	assert_str(String(Lib.category(id)["name"])).is_equal("Marcas")
	Lib.remove_category(id)
	assert_dict(Lib.category(id)).is_empty()

func test_guardar_y_colocar_recurso() -> void:
	var cat := Lib.add_category("Logos")
	var a := _api.add_star(Vector2(100, 100), 40)
	var b := _api.add_rect(Vector2(200, 100), Vector2(60, 40))
	var it := Lib.add_from_nodes(cat, _api.artboard(), [a, b], "Mi logo")
	assert_str(String(it["name"])).is_equal("Mi logo")
	assert_bool(FileAccess.file_exists(Lib.vop_path(it))).is_true()
	assert_bool(FileAccess.file_exists(Lib.thumb_path(it))).is_true()
	assert_int(Lib.category_items(cat).size()).is_equal(1)
	var n0 := _api.shapes().size()
	var res := Lib.place(it, _api.artboard(), Vector2(400, 400))
	assert_bool(res["ok"]).is_true()
	assert_int(_api.shapes().size()).is_equal(n0 + 1)
	assert_str(String(res["node"].name)).is_equal("Mi logo")
	assert_int((res["node"] as Node).get_child_count()).is_equal(2)
	Lib.rename_asset(it["id"], "Logo final")
	assert_str(String(Lib.find_asset(it["id"])["name"])).is_equal("Logo final")
	var other := Lib.add_category("Otros")
	Lib.move_asset(it["id"], other)   # una categoría como destino → su 1.ª sección
	assert_int(Lib.category_items(other).size()).is_equal(1)
	Lib.remove_asset(it["id"])
	assert_bool(FileAccess.file_exists(Lib.vop_path(it))).is_false()

func test_paquete_vopassets_ida_y_vuelta() -> void:
	var cat := Lib.add_category("Iconos")
	Lib.add_from_nodes(cat, _api.artboard(), [_api.add_star(Vector2(50, 50), 20)], "Estrella")
	Lib.add_from_nodes(cat, _api.artboard(), [_api.add_ellipse(Vector2(50, 50), Vector2(30, 30))], "Círculo")
	var pkg := _dir.path_join("iconos.vopassets")
	assert_int(Lib.export_package(pkg, [cat])).is_equal(OK)
	# otra biblioteca vacía (otro usuario)
	Lib._root_override = _dir.path_join("lib2")
	var r := Lib.import_package(pkg)
	assert_bool(r["ok"]).is_true()
	assert_int(int(r["items"])).is_equal(2)
	var imported: Array = Lib.categories().filter(func(c) -> bool: return c["name"] == "Iconos")
	assert_int(imported.size()).is_equal(1)
	assert_int(Lib.category_items(imported[0]["id"]).size()).is_equal(2)
	# volver a importar FUSIONA en la misma categoría
	Lib.import_package(pkg)
	assert_int(Lib.categories().filter(func(c) -> bool: return c["name"] == "Iconos").size()).is_equal(1)
	assert_int(Lib.category_items(Lib.categories().filter(func(c) -> bool: return c["name"] == "Iconos")[0]["id"]).size()).is_equal(4)
	# lo importado se puede colocar
	var it: Dictionary = Lib.category_items(imported[0]["id"])[0]
	assert_bool(Lib.place(Lib.find_asset(it["id"]), _api.artboard())["ok"]).is_true()

func test_paquete_invalido() -> void:
	var bad := _dir.path_join("malo.vopassets")
	var zp := ZIPPacker.new()
	zp.open(bad)
	zp.start_file("manifest.json")
	zp.write_file('{"format": "otro"}'.to_utf8_buffer())
	zp.close_file()
	zp.close()
	assert_bool(Lib.import_package(bad)["ok"]).is_false()
	assert_bool(Lib.import_package(_dir.path_join("no_existe.vopassets"))["ok"]).is_false()

func test_recurso_desde_archivo_svg() -> void:
	var svg := _dir.path_join("icono.svg")
	var f := FileAccess.open(svg, FileAccess.WRITE)
	f.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><circle cx="20" cy="20" r="15" fill="#0a0"/></svg>')
	f.close()
	var it: Dictionary = await Lib.add_from_file(Lib.categories()[0]["id"], svg)
	assert_str(String(it.get("name", ""))).is_equal("icono")
	assert_bool(FileAccess.file_exists(Lib.thumb_path(it))).is_true()

# ── subcategorías y organizar ────────────────────────────────────────────────
func test_subcategorias_y_orden() -> void:
	var cat := Lib.add_category("Logos")
	var general: String = Lib.category(cat)["subs"][0]["id"]
	var clientes := Lib.add_subcategory(cat, "Clientes")
	var propios := Lib.add_subcategory(cat, "Propios")
	assert_array((Lib.category(cat)["subs"] as Array).map(func(s) -> String: return s["name"])).is_equal(["General", "Clientes", "Propios"])
	var a := Lib.add_from_nodes(cat, _api.artboard(), [_api.add_star(Vector2(50, 50), 20)], "A", clientes)
	var b := Lib.add_from_nodes(cat, _api.artboard(), [_api.add_star(Vector2(50, 50), 20)], "B", clientes)
	var c := Lib.add_from_nodes(cat, _api.artboard(), [_api.add_star(Vector2(50, 50), 20)], "C", clientes)
	var names := func(sub: String) -> Array: return (Lib.subcategory(sub)["items"] as Array).map(func(i) -> String: return i["name"])
	assert_array(names.call(clientes)).is_equal(["A", "B", "C"])
	# reordenar dentro de la sección: C delante de A
	Lib.move_asset(c["id"], clientes, 0)
	assert_array(names.call(clientes)).is_equal(["C", "A", "B"])
	# A al final (insertar después de quitarlo)
	Lib.move_asset(a["id"], clientes, 3)
	assert_array(names.call(clientes)).is_equal(["C", "B", "A"])
	# mover a otra sección, en posición
	Lib.move_asset(b["id"], propios, 0)
	assert_array(names.call(propios)).is_equal(["B"])
	assert_str(Lib.sub_of_asset(b["id"])).is_equal(propios)
	# reordenar secciones: Propios al principio
	Lib.move_subcategory(propios, cat, 0)
	assert_array((Lib.category(cat)["subs"] as Array).map(func(s) -> String: return s["name"])).is_equal(["Propios", "General", "Clientes"])
	# mover sección a otra categoría
	var otra := Lib.add_category("Otra")
	Lib.move_subcategory(clientes, otra)
	assert_str(Lib.category_of_sub(clientes)).is_equal(otra)
	# plegar se recuerda
	Lib.set_collapsed(general, true)
	assert_bool(Lib.subcategory(general)["collapsed"]).is_true()
	# borrar sección borra sus recursos; la categoría conserva al menos una
	Lib.remove_subcategory(propios)
	assert_bool(FileAccess.file_exists(Lib.vop_path(b))).is_false()
	Lib.remove_subcategory(general)
	assert_int((Lib.category(cat)["subs"] as Array).size()).is_equal(1)

func test_migracion_de_biblioteca_v1() -> void:
	DirAccess.make_dir_recursive_absolute(Lib.root())
	var f := FileAccess.open(Lib.root().path_join("index.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "categories": [{"id": "c1", "name": "Viejos", "items": [{"id": "i1", "name": "Uno", "file": "items/i1.vop", "thumb": "items/i1.png"}]}]}))
	f.close()
	var cat := Lib.category("c1")
	assert_int((cat["subs"] as Array).size()).is_equal(1)
	assert_str(String(cat["subs"][0]["name"])).is_equal("General")
	assert_str(String(cat["subs"][0]["items"][0]["name"])).is_equal("Uno")
	assert_bool(cat.has("items")).is_false()

func test_paquete_conserva_subcategorias() -> void:
	var cat := Lib.add_category("Iconos")
	var flechas := Lib.add_subcategory(cat, "Flechas")
	Lib.add_from_nodes(cat, _api.artboard(), [_api.add_star(Vector2(50, 50), 20)], "Flecha", flechas)
	var pkg := _dir.path_join("subs.vopassets")
	Lib.export_package(pkg, [cat])
	Lib._root_override = _dir.path_join("lib3")
	assert_bool(Lib.import_package(pkg)["ok"]).is_true()
	var ic: Dictionary = Lib.categories().filter(func(c) -> bool: return c["name"] == "Iconos")[0]
	var fl: Array = (ic["subs"] as Array).filter(func(s) -> bool: return s["name"] == "Flechas")
	assert_int(fl.size()).is_equal(1)
	assert_str(String(fl[0]["items"][0]["name"])).is_equal("Flecha")
