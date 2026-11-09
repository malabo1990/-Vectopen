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
	# Godot ya guarda los hijos en una tabla por nombre: has_node() es O(1).
	# Antes se leían los nombres de TODOS los hermanos en cada llamada y crear
	# 10 000 figuras por script costaba ~85 s. Se recuerda además el último
	# número usado de cada nombre base (si no, «X 2», «X 3»… se volvían a
	# probar desde 2 cada vez).
	if b.validate_node_name() != b:
		var taken := {}
		for c in parent.get_children():
			taken[String(c.name)] = true
		return unique_name_in(taken, b)
	if not parent.has_node(NodePath(b)):
		return b
	var key := parent.get_instance_id()
	if not _next.has(key):
		if _next.size() > 512:
			_next.clear()
		_next[key] = {}
	var per: Dictionary = _next[key]
	var i := int(per.get(b, 2))
	var n := "%s %d" % [b, i]
	while parent.has_node(NodePath(n)):
		i += 1
		n = "%s %d" % [b, i]
	per[b] = i   # punto de partida de la próxima vez (sin añadir, mismo nombre)
	return n

## Último número usado por (padre, nombre base). Solo acelera: si un número
## quedase libre (se borró esa capa) simplemente no se reutiliza.
static var _next: Dictionary = {}

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
