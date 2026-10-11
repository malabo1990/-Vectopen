# =============================================================================
# RUTA: res://script_gdscript/system/asset_library.gd
# BIBLIOTECA DE RECURSOS (como los Assets de Affinity o los componentes de
# Penpot): logos, iconos, botones… listos para reutilizar sin buscar carpetas.
#
#   · Categorías → SUBCATEGORÍAS (secciones plegables) → recursos, en el
#     orden que el usuario elige (arrastrar para organizar).
#   · Cada recurso es un VOP (sin pérdidas) + miniatura PNG, en
#     user://recursos/ (index.json + items/).
#   · Paquetes .vopassets = ZIP con manifest.json + .vop + miniaturas.
#     Versión 2 con subcategorías; la 1 (sin ellas) se sigue importando.
#
# Índice: {version: 2, categories: [{id, name, subs: [{id, name, collapsed,
#          items: [{id, name, file, thumb, created}]}]}]}
# =============================================================================
extends RefCounted

const ROOT := "user://recursos/"
const PACKAGE_FORMAT := "vopassets"
const PACKAGE_VERSION := 2
const INDEX_VERSION := 2
const THUMB := 128
const DEFAULT_SUB := "General"

static var _root_override := ""   # tests

static func root() -> String:
	return _root_override if _root_override != "" else ROOT

static func _index_path() -> String:
	return root().path_join("index.json")

# ── índice ───────────────────────────────────────────────────────────────────
static func load_index() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(_index_path())) if FileAccess.file_exists(_index_path()) else null
	var dirty := false
	if not (data is Dictionary) or not (data.get("categories") is Array):
		data = {"version": INDEX_VERSION, "categories": []}
		dirty = true
	if (data["categories"] as Array).is_empty():
		data["categories"].append(_new_cat("General"))
		dirty = true
	# migración v1: los recursos sueltos de la categoría → subcategoría General
	for c in data["categories"]:
		if not (c.get("subs") is Array):
			c["subs"] = []
		if c.has("items"):
			dirty = true
			if not (c["items"] as Array).is_empty():
				c["subs"].insert(0, {"id": _new_id(), "name": DEFAULT_SUB, "collapsed": false, "items": c["items"]})
			c.erase("items")
		if (c["subs"] as Array).is_empty():
			c["subs"].append(_new_sub(DEFAULT_SUB))
			dirty = true
	if int(data.get("version", 0)) != INDEX_VERSION:
		dirty = true
	data["version"] = INDEX_VERSION
	# Lo creado o migrado se GUARDA ya: si no, cada lectura inventaba ids
	# nuevos y una subcategoría o un paquete recién añadidos se perdían.
	if dirty:
		save_index(data)
	return data

static func save_index(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(root())
	var f := FileAccess.open(_index_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))

static var _seq := 0
static func _new_id() -> String:
	_seq += 1
	return "%x%x%03x" % [int(Time.get_unix_time_from_system() * 1000), randi() % 0xfff, _seq % 0xfff]

static func _new_cat(name: String) -> Dictionary:
	return {"id": _new_id(), "name": name, "subs": [_new_sub(DEFAULT_SUB)]}

static func _new_sub(name: String) -> Dictionary:
	return {"id": _new_id(), "name": name, "collapsed": false, "items": []}

# ── categorías ───────────────────────────────────────────────────────────────
static func categories() -> Array:
	return load_index()["categories"]

static func category(id: String) -> Dictionary:
	for c in categories():
		if c["id"] == id:
			return c
	return {}

## Todos los recursos de una categoría (de todas sus subcategorías).
static func category_items(id: String) -> Array:
	var out: Array = []
	for s in category(id).get("subs", []):
		out.append_array(s["items"])
	return out

static func add_category(name: String) -> String:
	var data := load_index()
	var c := _new_cat(_unique_name((data["categories"] as Array).map(func(x) -> String: return x["name"]), name, "Categoría"))
	data["categories"].append(c)
	save_index(data)
	return c["id"]

static func _unique_name(names: Array, name: String, fallback: String) -> String:
	var n := name.strip_edges() if name.strip_edges() != "" else fallback
	if not (n in names):
		return n
	var i := 2
	while ("%s %d" % [n, i]) in names:
		i += 1
	return "%s %d" % [n, i]

static func rename_category(id: String, name: String) -> void:
	var data := load_index()
	for c in data["categories"]:
		if c["id"] == id and name.strip_edges() != "":
			c["name"] = name.strip_edges()
	save_index(data)

## Borra la categoría y sus archivos (si era la última, queda una «General»).
static func remove_category(id: String) -> void:
	var data := load_index()
	for c in data["categories"]:
		if c["id"] == id:
			for s in c["subs"]:
				for it in s["items"]:
					_delete_files(it)
	data["categories"] = (data["categories"] as Array).filter(func(c) -> bool: return c["id"] != id)
	save_index(data)

# ── subcategorías ────────────────────────────────────────────────────────────
static func subcategory(id: String) -> Dictionary:
	for c in categories():
		for s in c["subs"]:
			if s["id"] == id:
				return s
	return {}

## Categoría a la que pertenece una subcategoría.
static func category_of_sub(sub_id: String) -> String:
	for c in categories():
		for s in c["subs"]:
			if s["id"] == sub_id:
				return c["id"]
	return ""

static func add_subcategory(cat_id: String, name: String) -> String:
	var data := load_index()
	for c in data["categories"]:
		if c["id"] == cat_id:
			var s := _new_sub(_unique_name((c["subs"] as Array).map(func(x) -> String: return x["name"]), name, "Sección"))
			c["subs"].append(s)
			save_index(data)
			return s["id"]
	return ""

static func rename_subcategory(sub_id: String, name: String) -> void:
	var data := load_index()
	var s := _find_sub(data, sub_id)
	if not s.is_empty() and name.strip_edges() != "":
		s["name"] = name.strip_edges()
		save_index(data)

static func set_collapsed(sub_id: String, collapsed: bool) -> void:
	var data := load_index()
	var s := _find_sub(data, sub_id)
	if not s.is_empty():
		s["collapsed"] = collapsed
		save_index(data)

## Borra una subcategoría y sus recursos (cada categoría conserva al menos una).
static func remove_subcategory(sub_id: String) -> void:
	var data := load_index()
	for c in data["categories"]:
		for s in c["subs"]:
			if s["id"] == sub_id:
				for it in s["items"]:
					_delete_files(it)
		c["subs"] = (c["subs"] as Array).filter(func(s) -> bool: return s["id"] != sub_id)
		if (c["subs"] as Array).is_empty():
			c["subs"].append(_new_sub(DEFAULT_SUB))
	save_index(data)

## Mueve una subcategoría (con sus recursos) a `to_cat`, en la posición
## `index` (-1 = al final). Sirve para reordenar dentro de la misma.
static func move_subcategory(sub_id: String, to_cat: String, index: int = -1) -> void:
	var data := load_index()
	var moved: Dictionary = {}
	for c in data["categories"]:
		for s in c["subs"]:
			if s["id"] == sub_id:
				moved = s
		c["subs"] = (c["subs"] as Array).filter(func(s) -> bool: return s["id"] != sub_id)
	for c in data["categories"]:
		if c["id"] == to_cat and not moved.is_empty():
			var subs: Array = c["subs"]
			subs.insert(clampi(index, 0, subs.size()) if index >= 0 else subs.size(), moved)
	for c in data["categories"]:
		if (c["subs"] as Array).is_empty():
			c["subs"].append(_new_sub(DEFAULT_SUB))
	save_index(data)

static func _find_sub(data: Dictionary, sub_id: String) -> Dictionary:
	for c in data["categories"]:
		for s in c["subs"]:
			if s["id"] == sub_id:
				return s
	return {}

## Subcategoría donde caen los recursos nuevos de una categoría.
static func _target_sub(data: Dictionary, cat_id: String, sub_id: String) -> Dictionary:
	if sub_id != "":
		var s := _find_sub(data, sub_id)
		if not s.is_empty():
			return s
	for c in data["categories"]:
		if c["id"] == cat_id:
			return c["subs"][0]
	return data["categories"][0]["subs"][0]

# ── recursos ─────────────────────────────────────────────────────────────────
static func vop_path(item: Dictionary) -> String:
	return ProjectSettings.globalize_path(root().path_join(String(item["file"])))

static func thumb_path(item: Dictionary) -> String:
	return ProjectSettings.globalize_path(root().path_join(String(item["thumb"])))

## Guarda `nodes` (de `artboard`) como recurso. Devuelve el item.
static func add_from_nodes(cat_id: String, artboard: Node, nodes: Array, name: String = "", sub_id: String = "") -> Dictionary:
	var iem = Engine.get_main_loop().root.get_node_or_null("ImportExportManager")
	if iem == null or nodes.is_empty():
		return {}
	var vop: Dictionary = iem.vop_data(artboard, nodes)
	var nm := name if name != "" else (String(nodes[0].name) if nodes.size() == 1 else "Selección")
	return add_from_vop(cat_id, vop, nm, sub_id)

static func add_from_vop(cat_id: String, vop: Dictionary, name: String, sub_id: String = "") -> Dictionary:
	var data := load_index()
	var sub := _target_sub(data, cat_id, sub_id)
	var id := _new_id()
	DirAccess.make_dir_recursive_absolute(root().path_join("items"))
	var item := {"id": id, "name": name, "file": "items/%s.vop" % id, "thumb": "items/%s.png" % id,
		"created": Time.get_datetime_string_from_system()}
	var f := FileAccess.open(root().path_join(item["file"]), FileAccess.WRITE)
	if f == null:
		return {}
	f.store_string(JSON.stringify(vop))
	f.close()
	var img := thumbnail(vop)
	if img:
		img.save_png(root().path_join(item["thumb"]))
	sub["items"].append(item)
	save_index(data)
	return item

## Importa un archivo (.vop, .svg, imagen) como recurso. Usar con await.
static func add_from_file(cat_id: String, path: String, sub_id: String = "") -> Dictionary:
	var ext := path.get_extension().to_lower()
	if ext == "vop":
		var vop = JSON.parse_string(FileAccess.get_file_as_string(path))
		if vop is Dictionary and String(vop.get("format", "")) == "vop":
			return add_from_vop(cat_id, vop, path.get_file().get_basename(), sub_id)
		return {}
	var iem = Engine.get_main_loop().root.get_node_or_null("ImportExportManager")
	if iem == null:
		return {}
	var tmp_dir := ProjectSettings.globalize_path("user://recursos_tmp")
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var res: Dictionary = await iem.convert_file(path, "VOP", tmp_dir)
	if not res["ok"]:
		return {}
	var vop2 = JSON.parse_string(FileAccess.get_file_as_string(String(res["path"])))
	DirAccess.remove_absolute(String(res["path"]))
	if not (vop2 is Dictionary):
		return {}
	return add_from_vop(cat_id, vop2, path.get_file().get_basename(), sub_id)

static func find_asset(id: String) -> Dictionary:
	for c in categories():
		for s in c["subs"]:
			for it in s["items"]:
				if it["id"] == id:
					return it
	return {}

## Subcategoría donde está un recurso.
static func sub_of_asset(id: String) -> String:
	for c in categories():
		for s in c["subs"]:
			for it in s["items"]:
				if it["id"] == id:
					return s["id"]
	return ""

static func rename_asset(id: String, name: String) -> void:
	var data := load_index()
	for c in data["categories"]:
		for s in c["subs"]:
			for it in s["items"]:
				if it["id"] == id and name.strip_edges() != "":
					it["name"] = name.strip_edges()
	save_index(data)

static func remove_asset(id: String) -> void:
	var data := load_index()
	for c in data["categories"]:
		for s in c["subs"]:
			for it in s["items"]:
				if it["id"] == id:
					_delete_files(it)
			s["items"] = (s["items"] as Array).filter(func(it) -> bool: return it["id"] != id)
	save_index(data)

## Mueve un recurso a la subcategoría `to_sub` (de cualquier categoría), en
## la posición `index` (-1 = al final). Reordenar = misma subcategoría.
static func move_asset(id: String, to_sub: String, index: int = -1) -> void:
	var data := load_index()
	var target := _find_sub(data, to_sub)
	if target.is_empty():
		# compatibilidad: una CATEGORÍA como destino → su primera subcategoría
		for c in data["categories"]:
			if c["id"] == to_sub:
				target = c["subs"][0]
	if target.is_empty():
		return
	var moved: Dictionary = {}
	var old_index := -1
	var same_sub := false
	for c in data["categories"]:
		for s in c["subs"]:
			var arr: Array = s["items"]
			for i in arr.size():
				if arr[i]["id"] == id:
					moved = arr[i]
					old_index = i
					same_sub = s["id"] == target["id"]
			s["items"] = arr.filter(func(it) -> bool: return it["id"] != id)
	if moved.is_empty():
		return
	var items: Array = target["items"]
	var at := index if index >= 0 else items.size()
	if same_sub and old_index >= 0 and old_index < at:
		at -= 1   # se quitó antes de la posición de destino
	items.insert(clampi(at, 0, items.size()), moved)
	save_index(data)

static func _delete_files(it: Dictionary) -> void:
	for k in ["file", "thumb"]:
		var p := root().path_join(String(it.get(k, "")))
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

## Coloca un recurso en el artboard (centrado en `at`; INF = centro).
static func place(item: Dictionary, artboard: Node2D, at: Vector2 = Vector2.INF) -> Dictionary:
	var iem = Engine.get_main_loop().root.get_node_or_null("ImportExportManager")
	if iem == null:
		return {"ok": false, "error": "Sin exportador"}
	var res: Dictionary = iem.import_any(vop_path(item), artboard, at)
	if res.get("ok", false) and res.get("node") is Node:
		(res["node"] as Node).name = String(item["name"]).validate_node_name()
	return res

static func thumbnail(vop: Dictionary) -> Image:
	if not (vop.get("render") is Dictionary):
		return null
	var svg := VopPreview.to_svg(vop)
	var probe := Image.new()
	if probe.load_svg_from_string(svg, 1.0) != OK:
		return null
	var k := clampf(float(THUMB) / maxf(probe.get_width(), probe.get_height()), 0.02, 16.0)
	var img := Image.new()
	return img if img.load_svg_from_string(svg, k) == OK else null

# ── paquetes .vopassets ──────────────────────────────────────────────────────
## Exporta categorías (todas si `cat_ids` está vacío) a un .vopassets.
static func export_package(path: String, cat_ids: Array = []) -> Error:
	var zp := ZIPPacker.new()
	var err := zp.open(path)
	if err != OK:
		return err
	var manifest := {"format": PACKAGE_FORMAT, "version": PACKAGE_VERSION, "generator": "Vectopen",
		"created": Time.get_datetime_string_from_system(), "categories": []}
	for c in categories():
		if not cat_ids.is_empty() and not (c["id"] in cat_ids):
			continue
		var mc := {"name": c["name"], "subcategories": []}
		for s in c["subs"]:
			var ms := {"name": s["name"], "items": []}
			for it in s["items"]:
				var vop := FileAccess.get_file_as_bytes(root().path_join(String(it["file"])))
				if vop.is_empty():
					continue
				var base := "assets/%s" % it["id"]
				zp.start_file(base + ".vop")
				zp.write_file(vop)
				zp.close_file()
				var th := FileAccess.get_file_as_bytes(root().path_join(String(it["thumb"])))
				if not th.is_empty():
					zp.start_file(base + ".png")
					zp.write_file(th)
					zp.close_file()
				ms["items"].append({"name": it["name"], "file": base + ".vop", "thumb": base + ".png" if not th.is_empty() else ""})
			mc["subcategories"].append(ms)
		manifest["categories"].append(mc)
	zp.start_file("manifest.json")
	zp.write_file(JSON.stringify(manifest, "\t").to_utf8_buffer())
	zp.close_file()
	return zp.close()

## Importa un .vopassets. Categorías y subcategorías con el mismo nombre se
## FUSIONAN. Devuelve {ok, error, categories, items}.
static func import_package(path: String) -> Dictionary:
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		return {"ok": false, "error": "No se pudo abrir el paquete"}
	var manifest = JSON.parse_string(zr.read_file("manifest.json").get_string_from_utf8()) if zr.file_exists("manifest.json") else null
	if not (manifest is Dictionary) or String(manifest.get("format", "")) != PACKAGE_FORMAT:
		zr.close()
		return {"ok": false, "error": "No es un paquete .vopassets"}
	if int(manifest.get("version", 0)) > PACKAGE_VERSION:
		zr.close()
		return {"ok": false, "error": "Paquete de una versión más nueva de Vectopen"}
	var cats := 0
	var items := 0
	for mc in manifest.get("categories", []):
		var cat_id := ""
		for c in categories():
			if c["name"] == String(mc.get("name", "")):
				cat_id = c["id"]
		if cat_id == "":
			cat_id = add_category(String(mc.get("name", "Importado")))
			cats += 1
		# v1: recursos sin subcategoría → «General»
		var subs: Array = mc.get("subcategories", [{"name": DEFAULT_SUB, "items": mc.get("items", [])}])
		for ms in subs:
			var sub_id := ""
			for s in category(cat_id).get("subs", []):
				if s["name"] == String(ms.get("name", DEFAULT_SUB)):
					sub_id = s["id"]
			if sub_id == "":
				sub_id = add_subcategory(cat_id, String(ms.get("name", DEFAULT_SUB)))
			for mi in ms.get("items", []):
				var file := String(mi.get("file", ""))
				if file == "" or ".." in file or not zr.file_exists(file):
					continue
				var vop = JSON.parse_string(zr.read_file(file).get_string_from_utf8())
				if vop is Dictionary and String(vop.get("format", "")) == "vop":
					if not add_from_vop(cat_id, vop, String(mi.get("name", "Recurso")), sub_id).is_empty():
						items += 1
	zr.close()
	return {"ok": true, "error": "", "categories": cats, "items": items}

const VopPreview = preload("res://script_gdscript/system/vop_preview.gd")
