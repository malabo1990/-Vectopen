# =============================================================================
# REGRESIÓN: el menú contextual solo llama a funciones que EXISTEN.
# Bug (2026-10-28): «Agrupar» y «Desagrupar» llamaban a
# _on_btn_group_selected / _on_btn_ungroup, que no existían; como la
# llamada iba tras `has_method(...)`, fallaba en silencio y no hacía nada.
# Este test lee context_menu_actions.gd y comprueba cada `xx.has_method("f")`
# contra el script del objeto al que se le llama.
# =============================================================================
extends GdUnitTestSuite

const SRC := "res://script_gdscript/ui/context_menu_actions.gd"
## Variable del menú → script que la implementa.
const TARGETS := {
	"ls": "res://script_gdscript/ui/layers_system.gd",
	"mt": "res://script_gdscript/tools/MoveTool.gd",
}

func _script_has(path: String, method: String) -> bool:
	var sc: Script = load(path)
	while sc:
		for m in sc.get_script_method_list():
			if m["name"] == method:
				return true
		sc = sc.get_base_script()
	return false

func test_every_called_method_exists() -> void:
	var src := FileAccess.get_file_as_string(SRC)
	var re := RegEx.new()
	re.compile("\\b(ls|mt)\\.has_method\\(\"([A-Za-z0-9_]+)\"\\)")
	var missing: Array[String] = []
	var seen := 0
	for m in re.search_all(src):
		seen += 1
		var who := m.get_string(1)
		var method := m.get_string(2)
		if not _script_has(TARGETS[who], method):
			missing.append("%s.%s" % [who, method])
	assert_int(seen).is_greater(5)
	assert_array(missing).override_failure_message(
		"El menú contextual llama a funciones que no existen (no harían nada): %s" % [missing]).is_empty()
