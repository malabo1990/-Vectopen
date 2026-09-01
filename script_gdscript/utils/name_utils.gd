# =============================================================================
# RUTA: res://script_gdscript/utils/name_utils.gd
# Nombres de capa limpios y únicos (estilo editor vectorial).
# =============================================================================
class_name NameUtils

## Devuelve un nombre limpio y ÚNICO entre los hijos de `parent`:
##   "Rectángulo"  → si libre
##   "Rectángulo 2", "Rectángulo 3"… → si ya hay hermanos con ese nombre
## Sin números inventados (timestamps): el número solo aparece para evitar
## duplicados, como en cualquier editor profesional.
static func unique_child_name(parent: Node, base: String) -> String:
	var b := base.strip_edges()
	if b == "":
		b = "Capa"
	if not is_instance_valid(parent):
		return b
	if not _sibling_named(parent, b):
		return b
	var i := 2
	while _sibling_named(parent, "%s %d" % [b, i]):
		i += 1
	return "%s %d" % [b, i]

static func _sibling_named(parent: Node, n: String) -> bool:
	for c in parent.get_children():
		if String(c.name) == n:
			return true
	return false
