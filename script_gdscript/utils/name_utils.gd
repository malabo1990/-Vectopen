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
	# Nombres de los hermanos leídos UNA vez: antes cada intento («X 2»,
	# «X 3»…) recorría todos los hijos → O(n²) por nombre, O(n³) al importar.
	var taken := {}
	for c in parent.get_children():
		taken[String(c.name)] = true
	return unique_name_in(taken, b)

## Igual, contra un diccionario de nombres ocupados (que se actualiza). Para
## añadir muchos hijos seguidos sin volver a leer los hermanos.
static func unique_name_in(taken: Dictionary, base: String) -> String:
	var b := base.strip_edges()
	if b == "":
		b = "Capa"
	var n := b
	var i := int(taken.get("/next/" + b, 2))
	if taken.has(n):
		n = "%s %d" % [b, i]
		while taken.has(n):
			i += 1
			n = "%s %d" % [b, i]
		taken["/next/" + b] = i + 1
	taken[n] = true
	return n

static func _sibling_named(parent: Node, n: String) -> bool:
	for c in parent.get_children():
		if String(c.name) == n:
			return true
	return false
