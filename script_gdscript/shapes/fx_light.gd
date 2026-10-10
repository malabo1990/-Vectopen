# =============================================================================
# RUTA: res://script_gdscript/shapes/fx_light.gd
# Efectos de RELIEVE (separados, como Affinity / Photoshop):
#   · "3D"           — iluminación de la superficie (Affinity "3D"): radio,
#                      profundidad, suavizar, perfil, difuso, especular,
#                      brillo, ambiente, luz (acimut / elevación / color).
#   · "Bevel Emboss" — Bisel y relieve (Photoshop): estilo interior /
#                      exterior / relieve / almohadilla, técnica, dirección,
#                      tamaño, profundidad, suavizar, luz y sombra con color.
#   · "Extrusion"    — volumen extruido hacia fuera (fx_extrude.gd).
# Los "3D" antiguos (depth / bevel / highlight / shadow / extrude) se
# convierten aquí a Extrusión + Bisel y relieve (migrate_list).
# Fuentes: ayuda de Affinity (layerFX 3D), GEGL bevel (bump / chamfer),
# Bisel y relieve de Photoshop (luces en trama, sombras en multiplicar).
# =============================================================================
extends RefCounted

const LIGHT_3D := {
	"radius": 20.0, "relief": 20.0, "link": true, "soften": 2.0, "opacity": 100.0,
	"profile": 0, "sunken": false,
	"diffuse": 100.0, "specular": 47.0, "shininess": 60.0,
	"specular_color": Color(1, 1, 1, 1), "ambient": 0.0, "ambient_color": Color(1, 1, 1, 1),
	"azimuth": 135.0, "elevation": 45.0, "light_color": Color(1, 1, 1, 1),
}

const BEVEL := {
	"style": 0,          # 0 interior, 1 exterior, 2 relieve, 3 almohadilla
	"technique": 0,      # 0 suave, 1 cincel duro, 2 cincel suave
	"up": true, "size": 10.0, "depth": 100.0, "soften": 0.0,
	"azimuth": 120.0, "elevation": 30.0,
	"highlight_color": Color(1, 1, 1, 1), "highlight_opacity": 75.0,
	"shadow_color": Color(0, 0, 0, 1), "shadow_opacity": 75.0,
}

const EXTRUSION := {
	"depth": 12.0, "angle": 45.0, "highlight": 70.0, "shadow": 60.0,
}

static func defaults(kind: String) -> Dictionary:
	match kind:
		"3d": return LIGHT_3D.duplicate(true)
		"bevel_emboss": return BEVEL.duplicate(true)
		"extrusion": return EXTRUSION.duplicate(true)
	return {}

static func canonical(t: String) -> String:
	var n := t.to_lower().strip_edges().replace(" ", "_").replace("/", "_")
	match n:
		"threed": return "3d"
		"bevel", "bevel_and_emboss", "bisel", "bisel_y_relieve", "bevel__emboss": return "bevel_emboss"
		"extrude", "extrusión": return "extrusion"
	return n

## ¿Es un "3D" del formato antiguo (extrusión + bisel)?
static func is_legacy_3d(fx: Dictionary) -> bool:
	return canonical(String(fx.get("type", ""))) == "3d" and not fx.has("radius") \
		and (fx.has("bevel") or fx.has("highlight") or fx.has("extrude") or fx.has("depth"))

## Convierte los "3D" antiguos en Extrusión (si estaba activa) + Bisel y relieve.
static func migrate_list(list: Array) -> Array:
	var changed := false
	for fx in list:
		if fx is Dictionary and is_legacy_3d(fx):
			changed = true
			break
	if not changed:
		return list
	var out: Array = []
	for fx in list:
		if not (fx is Dictionary) or not is_legacy_3d(fx):
			out.append(fx)
			continue
		var en := bool(fx.get("enabled", true))
		if bool(fx.get("extrude", true)):
			out.append({"type": "Extrusion", "enabled": en,
				"depth": float(fx.get("depth", 8.0)), "angle": float(fx.get("angle", 45.0)),
				"highlight": float(fx.get("highlight", 70.0)), "shadow": float(fx.get("shadow", 60.0))})
		var bev := float(fx.get("bevel", 8.0))
		if bev > 0.2:
			var b := BEVEL.duplicate(true)
			b["type"] = "Bevel Emboss"
			b["enabled"] = en
			b["size"] = bev
			# la luz venía del lado contrario a la extrusión
			b["azimuth"] = fposmod(-float(fx.get("angle", 45.0)) + 180.0, 360.0)
			b["highlight_opacity"] = clampf(float(fx.get("highlight", 70.0)) * 0.85, 0.0, 100.0)
			b["shadow_opacity"] = clampf(float(fx.get("shadow", 60.0)) * 0.75, 0.0, 100.0)
			out.append(b)
	return out

static func _num(fx: Dictionary, k: String, d: Dictionary) -> float:
	return float(fx.get(k, d.get(k, 0.0)))

static func _col(v, def: Color) -> Color:
	if v is Color:
		return v
	if v is String:
		return Color.from_string(v, def)
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return def

## Dirección HACIA la luz en el espacio local de `node` (y hacia abajo).
## Acimut en grados, antihorario desde +x (0 = derecha, 90 = arriba), como
## Affinity / Photoshop; la luz no gira con la figura (como en ambos).
static func light_dir(node: CanvasItem, azimuth: float, elevation: float) -> Vector3:
	var az := deg_to_rad(azimuth)
	var el := deg_to_rad(clampf(elevation, 0.0, 90.0))
	var d2 := Vector2(cos(az), -sin(az)) * cos(el)
	if node is Node2D:
		var xf := (node as Node2D).get_global_transform()
		# pasar la dirección del lienzo al espacio local (sin escala)
		d2 = xf.basis_xform_inv(d2)
		if d2.length() > 0.00001:
			d2 = d2.normalized() * cos(el)
	return Vector3(d2.x, d2.y, sin(el))

## Uniforms comunes (fx_light.gdshaderinc + vector_light) de un efecto.
static func set_uniforms(mat: ShaderMaterial, node: CanvasItem, fx: Dictionary) -> void:
	var kind := canonical(String(fx.get("type", "")))
	if kind == "bevel_emboss":
		var d := BEVEL
		mat.set_shader_parameter("u_mode", 1)
		mat.set_shader_parameter("u_style", int(fx.get("style", 0)))
		mat.set_shader_parameter("u_profile", [3, 1, 1][clampi(int(fx.get("technique", 0)), 0, 2)])
		var size := maxf(0.5, _num(fx, "size", d))
		mat.set_shader_parameter("u_size", size)
		var depth := size * _num(fx, "depth", d) / 100.0
		mat.set_shader_parameter("u_relief", depth if bool(fx.get("up", true)) else -depth)
		var soft := _num(fx, "soften", d)
		if int(fx.get("technique", 0)) == 2:
			soft = maxf(soft, size * 0.35)   # cincel suave
		mat.set_shader_parameter("u_soften", soft)
		mat.set_shader_parameter("u_light_dir", light_dir(node, _num(fx, "azimuth", d), _num(fx, "elevation", d)))
		var hc := _col(fx.get("highlight_color"), Color.WHITE)
		var sc := _col(fx.get("shadow_color"), Color.BLACK)
		mat.set_shader_parameter("u_light_color", hc)
		mat.set_shader_parameter("u_ambient_color", sc)
		mat.set_shader_parameter("u_hi_opacity", clampf(_num(fx, "highlight_opacity", d) / 100.0, 0.0, 1.0))
		mat.set_shader_parameter("u_sh_opacity", clampf(_num(fx, "shadow_opacity", d) / 100.0, 0.0, 1.0))
		mat.set_shader_parameter("u_fx_opacity", 1.0)
		mat.set_shader_parameter("u_diffuse", 1.0)
		mat.set_shader_parameter("u_specular", 0.0)
		mat.set_shader_parameter("u_ambient", 0.0)
		return
	var l := LIGHT_3D
	mat.set_shader_parameter("u_mode", 0)
	mat.set_shader_parameter("u_style", 0)
	var radius := maxf(0.5, _num(fx, "radius", l))
	mat.set_shader_parameter("u_size", radius)
	var relief := radius if bool(fx.get("link", true)) else _num(fx, "relief", l)
	mat.set_shader_parameter("u_relief", -relief if bool(fx.get("sunken", false)) else relief)
	mat.set_shader_parameter("u_profile", clampi(int(fx.get("profile", 0)), 0, 2))
	mat.set_shader_parameter("u_soften", maxf(0.0, _num(fx, "soften", l)))
	mat.set_shader_parameter("u_fx_opacity", clampf(_num(fx, "opacity", l) / 100.0, 0.0, 1.0))
	mat.set_shader_parameter("u_diffuse", clampf(_num(fx, "diffuse", l) / 100.0, 0.0, 1.0))
	mat.set_shader_parameter("u_specular", clampf(_num(fx, "specular", l) / 100.0, 0.0, 1.0))
	mat.set_shader_parameter("u_shininess", clampf(_num(fx, "shininess", l) / 100.0, 0.0, 1.0))
	mat.set_shader_parameter("u_specular_color", _col(fx.get("specular_color"), Color.WHITE))
	mat.set_shader_parameter("u_ambient", clampf(_num(fx, "ambient", l) / 100.0, 0.0, 1.0))
	mat.set_shader_parameter("u_ambient_color", _col(fx.get("ambient_color"), Color.WHITE))
	mat.set_shader_parameter("u_light_color", _col(fx.get("light_color"), Color.WHITE))
	mat.set_shader_parameter("u_light_dir", light_dir(node, _num(fx, "azimuth", l), _num(fx, "elevation", l)))
	mat.set_shader_parameter("u_hi_opacity", 1.0)
	mat.set_shader_parameter("u_sh_opacity", 1.0)

## Margen exterior que el efecto necesita (bisel exterior / relieve).
static func outer_margin(fx: Dictionary) -> float:
	if canonical(String(fx.get("type", ""))) == "bevel_emboss" and int(fx.get("style", 0)) != 0:
		return maxf(0.5, _num(fx, "size", BEVEL)) + _num(fx, "soften", BEVEL) + 2.0
	return 2.0
