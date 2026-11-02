extends GdUnitTestSuite

## Higiene frente a los avisos del Depurador de Godot (DBG-nn): patrones de
## código que escriben errores en la consola aunque «funcionen».

func _gd_files(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d in ["addons", "test", ".godot"]:
			continue
		_gd_files(dir.path_join(d), out)

## DBG-01: get_meta(clave, null) NO es un valor por defecto en Godot 4: si la
## meta falta, escribe «The object does not have any 'meta' values…».
func test_no_get_meta_with_null_default_unguarded() -> void:
	var files: Array = []
	_gd_files("res://", files)
	var re := RegEx.new()
	re.compile("get_meta\\([^,()]+,\\s*null\\)")
	var bad: Array = []
	for f in files:
		var lines := FileAccess.get_file_as_string(f).split("\n")
		for i in lines.size():
			var l: String = lines[i]
			if re.search(l) and not l.contains("has_meta"):
				bad.append("%s:%d" % [f, i + 1])
	assert_array(bad).is_empty()
