# =============================================================================
# RUTA: res://script_gdscript/tools/brush_presets.gd
# «MIS PINCELES» (VGSE fase 6, pinceles personalizados): pinceles guardados
# por el usuario con nombre — estilo, grosor, opacidad, dureza, presión y,
# en el pincel de objeto, su figura y opciones. user://brush_presets.cfg.
# =============================================================================
extends RefCounted

const CFG := "user://brush_presets.cfg"
const ObjectBrush = preload("res://script_gdscript/shapes/object_brush.gd")

static func list() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(CFG) != OK:
		return []
	var v = JSON.parse_string(String(cfg.get_value("presets", "list", "[]")))
	return v if v is Array else []

static func _save(arr: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("presets", "list", JSON.stringify(arr))
	cfg.save(CFG)

## Guarda (o sustituye, si ya existe ese nombre) el pincel actual de `tool`.
static func add(name: String, tool: Object) -> void:
	var n := name.strip_edges()
	if n == "" or tool == null:
		return
	var arr := list().filter(func(p) -> bool: return String(p.get("name", "")) != n)
	arr.append(capture(n, tool))
	_save(arr)

static func remove(name: String) -> void:
	_save(list().filter(func(p) -> bool: return String(p.get("name", "")) != name))

static func capture(name: String, t: Object) -> Dictionary:
	return {
		"name": name,
		"style": String(t.brush_style),
		"width": float(t.brush_width),
		"opacity": float(t.brush_opacity),
		"grade": String(t.pencil_grade),
		"pressure": {"size": bool(t.pressure_size_enabled), "min": float(t.pressure_min),
			"gamma": float(t.pressure_gamma), "smoothing": float(t.pressure_smoothing)},
		"object": ObjectBrush.to_data(t.object_source),
		"object_params": (t.object_params as Dictionary).duplicate(true),
	}

## Aplica un pincel guardado a `t` (la herramienta pincel).
static func apply(p: Dictionary, t: Object) -> void:
	if t == null or p.is_empty():
		return
	t.apply_brush_style(String(p.get("style", "pen")))
	t.brush_width = float(p.get("width", t.brush_width))
	t.brush_opacity = float(p.get("opacity", t.brush_opacity))
	t.pencil_grade = String(p.get("grade", t.pencil_grade))
	var pr: Dictionary = p.get("pressure", {})
	if not pr.is_empty():
		t.pressure_size_enabled = bool(pr.get("size", true))
		t.pressure_min = float(pr.get("min", 0.0))
		t.pressure_gamma = float(pr.get("gamma", 1.0))
		t.pressure_smoothing = float(pr.get("smoothing", 0.0))
	t.object_source = ObjectBrush.from_data(p.get("object", []))
	var op = p.get("object_params", {})
	if op is Dictionary:
		t.object_params = ObjectBrush.DEFAULTS.duplicate()
		t.object_params.merge(op, true)
	if t.has_method("save_pressure_settings"):
		t.save_pressure_settings()
