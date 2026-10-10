# =============================================================================
# RUTA: res://script_gdscript/api/script_library.gd
# BIBLIOTECA DE SCRIPTS del usuario (pestaña Script → Scripts):
# guardar / listar / renombrar / borrar en user://scripts/ + plantillas.
# Mismo formato que la biblioteca de shaders: la 1.ª línea guarda el nombre.
# =============================================================================
extends RefCounted

const DIR := "user://scripts/"
const EXT := ".gd"
const NAME_TAG := "# vectopen-script: "

## Plantillas (nombre → código). Todas se prueban en ScriptPanel_test.
const TEMPLATES := {
	"Nuevo script": """# Modo rápido: escribe directamente; `api` es Vectopen.
# Ctrl+Intro ejecuta · Ctrl+S guarda · Ctrl+Z deshace el script entero.
var centro := api.artboard_size() / 2.0
var s := api.add_star(centro, 80, 5, 0.45)
api.set_fill(s, Color.GOLD)
print("Creada: ", s.name)
""",
	"Cuadrícula de círculos": """extends VectopenScript

const COLUMNAS := 6
const FILAS := 4
const PASO := 70.0

func run() -> void:
	var origen := api.artboard_size() / 2.0 - Vector2(COLUMNAS - 1, FILAS - 1) * PASO / 2.0
	for y in FILAS:
		for x in COLUMNAS:
			var c := api.add_ellipse(origen + Vector2(x, y) * PASO, Vector2(50, 50))
			api.set_fill(c, Color.from_hsv(float(x + y * COLUMNAS) / (COLUMNAS * FILAS), 0.6, 0.95))
	print("%d círculos" % (COLUMNAS * FILAS))
""",
	"Colores aleatorios": """extends VectopenScript

# Rellena cada objeto seleccionado con un color distinto.
func run() -> void:
	var sel := api.selection()
	if sel.is_empty():
		api.warn("Selecciona uno o más objetos")
		return
	for s in sel:
		api.set_fill(s, Color.from_hsv(randf(), 0.55, 0.95))
""",
	"Espiral de estrellas": """extends VectopenScript

func run() -> void:
	var centro := api.artboard_size() / 2.0
	for i in 36:
		var a := i * 0.5
		var r := 12.0 + i * 7.0
		var s := api.add_star(centro + Vector2(cos(a), sin(a)) * r, 6.0 + i * 0.6, 5, 0.45)
		api.set_fill(s, Color.from_hsv(i / 36.0, 0.7, 1.0))
		api.set_rotation(s, rad_to_deg(a))
""",
	"Repartir en círculo": """extends VectopenScript

# Coloca la selección en un círculo alrededor de su centro.
const RADIO := 160.0

func run() -> void:
	var sel := api.selection()
	if sel.size() < 2:
		api.warn("Selecciona 2 objetos o más")
		return
	var centro := Vector2.ZERO
	for s in sel:
		centro += api.get_position(s)
	centro /= sel.size()
	for i in sel.size():
		var a := TAU * i / sel.size() - PI / 2.0
		api.set_position(sel[i], centro + Vector2(cos(a), sin(a)) * RADIO)
""",
	"Onda Bézier": """extends VectopenScript

func run() -> void:
	var w := api.artboard_size().x
	var y := api.artboard_size().y / 2.0
	var curva := Curve2D.new()
	var paso := w / 8.0
	for i in 9:
		var p := Vector2(i * paso, y + (60.0 if i % 2 else -60.0))
		curva.add_point(p, Vector2(-paso * 0.4, 0), Vector2(paso * 0.4, 0))
	var onda := api.add_curve(curva, false, "Onda")
	api.set_stroke(onda, Color(0.1, 0.45, 0.9), 6.0)
""",
	"Polígonos 3 → 12": """extends VectopenScript

func run() -> void:
	var size := api.artboard_size()
	for lados in range(3, 13):
		var i := lados - 3
		var p := api.add_polygon(Vector2(size.x * (0.1 + 0.2 * (i % 5)), size.y * (0.35 + 0.3 * (i / 5))), 45, lados)
		api.set_fill(p, Color.from_hsv(i / 10.0, 0.5, 0.95))
""",
	"Renombrar selección": """extends VectopenScript

const PREFIJO := "Elemento"

func run() -> void:
	var n := 1
	for s in api.selection():
		api.set_prop(s, "name", "%s %02d" % [PREFIJO, n])
		n += 1
""",
	"Agrupar por tipo": """extends VectopenScript

# Agrupa los objetos del artboard según su tipo (rectángulos, estrellas…).
func run() -> void:
	var por_tipo := {}
	for s in api.shapes():
		var k := api.kind_of(s)
		if k == "group":
			continue
		if not por_tipo.has(k):
			por_tipo[k] = []
		por_tipo[k].append(s)
	for k in por_tipo:
		if por_tipo[k].size() > 1:
			api.group(por_tipo[k], k.capitalize())
""",
}

static func template_code(name: String) -> String:
	return String(TEMPLATES.get(name, TEMPLATES["Nuevo script"]))

# ── biblioteca en disco ──────────────────────────────────────────────────────
static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)

static func _file_for(name: String) -> String:
	var safe := name.strip_edges().validate_filename().replace(" ", "_")
	if safe.is_empty():
		safe = "script"
	return DIR + safe + EXT

## [{name, path, modified}] — el más reciente primero.
static func list() -> Array:
	_ensure_dir()
	var out: Array = []
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(EXT):
			continue
		var path := DIR + f
		out.append({"name": _read_name(path), "path": path,
			"modified": FileAccess.get_modified_time(path)})
	out.sort_custom(func(a, b): return int(a["modified"]) > int(b["modified"]))
	return out

static func _read_name(path: String) -> String:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa:
		var first := fa.get_line()
		if first.begins_with(NAME_TAG):
			return first.substr(NAME_TAG.length()).strip_edges()
	return path.get_file().get_basename().replace("_", " ")

static func exists(name: String) -> bool:
	return FileAccess.file_exists(_file_for(name))

## Guarda (o sobrescribe) `name`. Devuelve la ruta.
static func save(name: String, code: String) -> String:
	_ensure_dir()
	var path := _file_for(name)
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return ""
	fa.store_string(NAME_TAG + name.strip_edges() + "\n" + strip_name_tag(code))
	fa.close()
	return path

static func load_code(path: String) -> String:
	return strip_name_tag(FileAccess.get_file_as_string(path))

static func strip_name_tag(code: String) -> String:
	if code.begins_with(NAME_TAG):
		var nl := code.find("\n")
		return code.substr(nl + 1) if nl >= 0 else ""
	return code

static func remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

static func rename(path: String, new_name: String) -> String:
	var code := load_code(path)
	var np := save(new_name, code)
	if np != "" and np != path:
		remove(path)
	return np

## Nombre libre: "Nombre", "Nombre 2", "Nombre 3"…
static func unique_name(base: String) -> String:
	var n := base.strip_edges()
	if n.is_empty():
		n = "Script"
	if not exists(n):
		return n
	var i := 2
	while exists("%s %d" % [n, i]):
		i += 1
	return "%s %d" % [n, i]
