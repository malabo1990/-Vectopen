# =============================================================================
# REGRESIÓN: el teclado no depende de dónde esté el ratón.
# Bug (2026-10-28): todas las herramientas hacían
#     if GlobalUI.is_mouse_over_ui: return false
# ANTES de mirar el teclado. Con el puntero quieto sobre un panel (inspector,
# capas…) Esc no salía de la edición de texto y Supr, flechas, voltear o los
# atajos de texto no hacían nada. La guarda solo vale para eventos de RATÓN.
# =============================================================================
extends GdUnitTestSuite

const TOOLS_DIR := "res://script_gdscript/tools/"

## Toda herramienta que mire is_mouse_over_ui debe limitarlo a eventos de ratón
## en la MISMA condición (cubre también herramientas nuevas).
func test_mouse_over_ui_guard_only_applies_to_mouse_events() -> void:
	var offenders: Array[String] = []
	var scanned := 0
	for f in DirAccess.get_files_at(TOOLS_DIR):
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(TOOLS_DIR + f)
		var lines := src.split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("#") or not line.begins_with("if ") or not line.contains("is_mouse_over_ui"):
				continue
			scanned += 1
			if not line.contains("InputEventMouse"):
				offenders.append("%s:%d  %s" % [f, i + 1, line])
	assert_int(scanned).is_greater(0)
	assert_array(offenders).override_failure_message(
		"Estas herramientas bloquean el TECLADO cuando el ratón está sobre un panel:\n" + "\n".join(offenders)).is_empty()
