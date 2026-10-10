# =============================================================================
# RUTA: res://script_gdscript/shapes/shader_library.gd
# BIBLIOTECA DE SHADERS del usuario (pestaña Shader del panel Efectos):
#   · guardar / listar / renombrar / borrar en user://shaders/ (sirven en
#     todos los proyectos; el que se aplica a un objeto se guarda además
#     dentro del .vectopen, con el objeto);
#   · plantillas de ejemplo;
#   · validate(): compila y devuelve los errores con su línea (el compilador
#     de Godot los manda al log: se capturan con un Logger).
#
# Convención (la de los filtros): canvas_item que lee el render del objeto
# con un sampler hint_screen_texture; objeto(uv) da el color SIN
# premultiplicar y COLOR se escribe sin premultiplicar.
# Comentario opcional "// margen: N" = px de lienzo de margen alrededor del
# objeto para efectos que se salen (ondas, halos).
# =============================================================================
extends RefCounted

const DIR := "user://shaders/"
const EXT := ".gdshader"
const NAME_TAG := "// vectopen-shader: "

const HEADER := """shader_type canvas_item;
render_mode unshaded;

// Render del objeto (figura, texto, trazo, imagen…).
uniform sampler2D st : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// Color del objeto en `uv` (pantalla), sin premultiplicar.
vec4 objeto(vec2 uv) {
	vec4 c = textureLod(st, uv, 0.0);
	return c.a > 0.0001 ? vec4(c.rgb / c.a, c.a) : vec4(0.0);
}
"""

## Plantillas (nombre → cuerpo; se les antepone HEADER).
const TEMPLATES := {
	"Nuevo shader": """
uniform vec4 tinte : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float mezcla : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 c = objeto(SCREEN_UV);
	c.rgb = mix(c.rgb, tinte.rgb, mezcla);
	COLOR = c;
}
""",
	"Invertir": """
void fragment() {
	vec4 c = objeto(SCREEN_UV);
	COLOR = vec4(1.0 - c.rgb, c.a);
}
""",
	"Escala de grises": """
uniform float intensidad : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 c = objeto(SCREEN_UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c.rgb, vec3(g), intensidad), c.a);
}
""",
	"Onda": """// margen: 24
uniform float amplitud = 6.0;      // px de pantalla
uniform float frecuencia = 0.05;
uniform float velocidad = 3.0;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 sp = SCREEN_UV / px;
	sp.x += sin(sp.y * frecuencia + TIME * velocidad) * amplitud;
	COLOR = objeto(sp * px);
}
""",
	"Pixelado": """
uniform float bloque = 8.0;        // px de pantalla

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 sp = (floor(SCREEN_UV / px / bloque) + 0.5) * bloque;
	COLOR = objeto(sp * px);
}
""",
	"Holograma": """
uniform vec4 color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float lineas = 3.0;        // px entre líneas

void fragment() {
	vec4 c = objeto(SCREEN_UV);
	float y = SCREEN_UV.y / SCREEN_PIXEL_SIZE.y;
	float scan = 0.65 + 0.35 * step(0.5, fract(y / lineas));
	float flick = 0.9 + 0.1 * sin(TIME * 23.0);
	COLOR = vec4(color.rgb * scan * flick, c.a * 0.85);
}
""",
	"Brillo de borde": """// margen: 16
uniform vec4 color : source_color = vec4(1.0, 0.3, 0.8, 1.0);
uniform float radio = 6.0;         // px de pantalla

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec4 c = objeto(SCREEN_UV);
	float a = 0.0;
	for (int i = 0; i < 16; i++) {
		float ang = float(i) / 16.0 * 6.2831853;
		a += objeto(SCREEN_UV + vec2(cos(ang), sin(ang)) * radio * px).a;
	}
	float halo = clamp(a / 16.0 * 1.5, 0.0, 1.0) * (1.0 - c.a);
	COLOR = vec4(mix(color.rgb, c.rgb, c.a), max(c.a, halo * color.a));
}
""",
	"Arcoíris animado": """
uniform float velocidad = 0.3;
uniform float escala = 0.004;

vec3 hsv(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	vec4 c = objeto(SCREEN_UV);
	vec2 sp = SCREEN_UV / SCREEN_PIXEL_SIZE;
	COLOR = vec4(hsv(fract((sp.x + sp.y) * escala + TIME * velocidad)), c.a);
}
""",
	"Desenfoque": """// margen: 12
uniform float radio = 4.0;         // px de pantalla

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec4 acc = vec4(0.0);
	float w = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float k = exp(-float(x * x + y * y) / 8.0);
			acc += textureLod(st, SCREEN_UV + vec2(float(x), float(y)) * radio / 3.0 * px, 0.0) * k;
			w += k;
		}
	}
	acc /= w;
	COLOR = acc.a > 0.0001 ? vec4(acc.rgb / acc.a, acc.a) : vec4(0.0);
}
""",
}

static func template_code(name: String) -> String:
	return HEADER + String(TEMPLATES.get(name, TEMPLATES["Nuevo shader"]))

## Margen declarado en el código ("// margen: N"), 0 si no hay.
static func margin_of(code: String) -> float:
	var re := RegEx.new()
	re.compile("//\\s*marg(?:en|in)\\s*:\\s*([0-9.]+)")
	var m := re.search(code)
	return float(m.get_string(1)) if m else 0.0

# ── biblioteca en disco ──────────────────────────────────────────────────────
static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)

static func _file_for(name: String) -> String:
	var safe := name.strip_edges().validate_filename().replace(" ", "_")
	if safe.is_empty():
		safe = "shader"
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
		n = "Shader"
	if not exists(n):
		return n
	var i := 2
	while exists("%s %d" % [n, i]):
		i += 1
	return "%s %d" % [n, i]

# ── validación ───────────────────────────────────────────────────────────────
class _ShaderErrors extends Logger:
	var errors: Array = []
	func _log_error(_function: String, _file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_SHADER:
			errors.append({"line": line, "msg": code if rationale.is_empty() else rationale})

## Compila `code` y devuelve [{line, msg}] (vacío = correcto).
static func validate(code: String) -> Array:
	var cap := _ShaderErrors.new()
	OS.add_logger(cap)
	var sh := Shader.new()
	sh.code = code
	sh.get_shader_uniform_list()   # fuerza la compilación (síncrona)
	OS.remove_logger(cap)
	# El mismo error puede llegar dos veces (parseo + servidor de render).
	var seen := {}
	var out: Array = []
	for e in cap.errors:
		var k := "%d|%s" % [e["line"], e["msg"]]
		if not seen.has(k):
			seen[k] = true
			out.append(e)
	return out
