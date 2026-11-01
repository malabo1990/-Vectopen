# Prueba de importación con archivos REALES (lista: CORPUS_LIST o ~/.cache/vectopen_tests/corpus.txt).
# Uso: flatpak run --command=godot org.godotengine.Godot --headless --path . -s res://tools/import_corpus.gd
# VECTOPEN_IO=gdscript fuerza el importador GDScript (para comparar con el nativo).
extends SceneTree
func _count(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		c += 1 + _count(ch)
	return c
func _initialize() -> void:
	create_timer(900).timeout.connect(func(): print("WATCHDOG"); quit(2))
	await process_frame
	var SI = load("res://script_gdscript/system/svg_import.gd")
	var PI = load("res://script_gdscript/system/ps_import.gd")
	var IG = load("res://script_gdscript/system/io_guard.gd")
	var NI = load("res://script_gdscript/system/native_io.gd")
	print("MOTOR\t", "nativo " + NI.native().version() if NI.is_native() else "gdscript")
	var lp := OS.get_environment("CORPUS_LIST")
	var list := FileAccess.get_file_as_string(lp if lp != "" else OS.get_environment("HOME") + "/.cache/vectopen_tests/corpus.txt").split("\n", false)
	for p in list:
		print("FILE\t", p)
		var ext := p.get_extension().to_lower()
		var chk: Dictionary = IG.check_import(p)
		if not chk["ok"]:
			print("RES\t%s\tRECHAZADO\t%s" % [ext, chk["error"]])
			continue
		var t0 := Time.get_ticks_usec()
		var data: Dictionary = NI.parse_file(p)
		var t1 := Time.get_ticks_usec()
		var items: Array = data.get("items", [])
		var nodes := 0
		var t2 := t1
		if not items.is_empty():
			var g: Node2D = SI.build(data, p.get_file().get_basename())
			root.add_child(g)
			nodes = _count(g)
			t2 = Time.get_ticks_usec()
			g.free()
		var kinds := {}
		for it in items:
			kinds[it.get("t", "?")] = int(kinds.get(it.get("t", "?"), 0)) + 1
		print("RES\t%s\t%s\tparse=%dms\tbuild=%dms\tsize=%s\titems=%d\tnodes=%d\t%s\twarn=%s\t%s" % [ext, "VACIO" if items.is_empty() else "OK",
			(t1 - t0) / 1000, (t2 - t1) / 1000, data.get("size"), items.size(), nodes, kinds, data.get("warnings", []), data.get("engine", "")])
	print("DONE")
	quit(0)
