@tool
extends EditorImportPlugin
## .vop → PackedScene (.scn) en la carpeta .godot/imported: arrastra el .vop
## al editor 2D como cualquier escena; al cambiar el .vop se reimporta solo.

const Reader = preload("vop_reader.gd")

func _get_importer_name() -> String:
	return "vectopen.vop"

func _get_visible_name() -> String:
	return "Escena 2D (Vectopen VOP)"

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["vop"])

func _get_save_extension() -> String:
	return "scn"

func _get_resource_type() -> String:
	return "PackedScene"

func _get_priority() -> float:
	return 1.0

func _get_import_order() -> int:
	return 0

func _get_preset_count() -> int:
	return 1

func _get_preset_name(_preset_index: int) -> String:
	return "Predeterminado"

func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return [
		{"name": "include_background", "default_value": true},
		{"name": "curve_detail", "default_value": 1.0, "property_hint": PROPERTY_HINT_RANGE, "hint_string": "0.25,4,0.05"},
		{"name": "antialiased", "default_value": true},
	]

func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true

func _import(source_file: String, save_path: String, options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var data = Reader.read_file(source_file)
	if not (data is Dictionary):
		push_error("Vectopen: «%s» no es un archivo VOP válido" % source_file)
		return ERR_PARSE_ERROR
	var root := Reader.build(data, {
		"include_background": bool(options.get("include_background", true)),
		"curve_detail": float(options.get("curve_detail", 1.0)),
		"antialiased": bool(options.get("antialiased", true)),
		"name": source_file.get_file().get_basename()})
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		return err
	return ResourceSaver.save(packed, "%s.%s" % [save_path, _get_save_extension()])
