# =============================================================================
# RUTA: res://script_gdscript/shapes/blend_modes.gd
# MODOS DE FUSIÓN de una capa (panel Capas ▸ Normal / Multiplicar / Pantalla /
# Superponer / Aclarar / Oscurecer / Diferencia). Antes el panel llamaba a
# InspectorCore.apply("blend_mode") y esa propiedad no existía: no hacían nada.
#
# · Multiplicar → CanvasItemMaterial (BLEND_MODE_MUL, nativo y barato).
# · El resto → sombreador que lee lo que hay DETRÁS (hint_screen_texture) y
#   aplica la fórmula estándar (W3C Compositing): resultado = fusión(fondo,
#   color) y se compone con el alfa del objeto.
# · Grupos y textos no se dibujan a sí mismos: el material va en el nodo y sus
#   hijos lo heredan (use_parent_material).
# · Se guarda como meta "blend_mode" (normal, multiply, screen, overlay,
#   lighten, darken, difference) y se rehace al abrir.
# · Si el objeto ya usa un material propio (desenfoque, shader del usuario),
#   ese gana: no se pisa.
# =============================================================================
extends RefCounted

const META := "blend_mode"
const MAT_TAG := "_vectopen_blend"
const LABELS := {"normal": "Normal", "multiply": "Multiplicar", "screen": "Pantalla",
	"overlay": "Superponer", "lighten": "Aclarar", "darken": "Oscurecer", "difference": "Diferencia"}
const SHADER_MODES := {"screen": 1, "overlay": 2, "lighten": 3, "darken": 4, "difference": 5}

const SHADER_CODE := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 1;
vec3 blend(vec3 b, vec3 s) {
	if (mode == 1) { return b + s - b * s; }                                   // pantalla
	if (mode == 2) {                                                           // superponer
		return mix(2.0 * b * s, 1.0 - 2.0 * (1.0 - b) * (1.0 - s), step(0.5, b));
	}
	if (mode == 3) { return max(b, s); }                                       // aclarar
	if (mode == 4) { return min(b, s); }                                       // oscurecer
	return abs(b - s);                                                         // diferencia
}
void fragment() {
	vec4 src = COLOR;
	vec3 dst = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	COLOR = vec4(blend(dst, src.rgb), src.a);
}
"""

static var _shader: Shader = null

static func _shared_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader

## Clave interna a partir de la etiqueta del panel o de la clave.
static func key_of(v: Variant) -> String:
	var s := String(v).strip_edges()
	for k in LABELS:
		if s.to_lower() == k or s == LABELS[k]:
			return k
	return "normal"

static func label_of(node: Node) -> String:
	return LABELS[String(node.get_meta(META, "normal"))] if is_instance_valid(node) else "Normal"

static func _is_container(n: Node) -> bool:
	return not (n is VectorShape or n is Line2D or n is Polygon2D or n is Sprite2D or n is Path2D)

static func _ours(m: Material) -> bool:
	return m != null and m.has_meta(MAT_TAG)

## Aplica el modo (sin historial: InspectorCore se encarga del deshacer).
static func apply(node: Node, mode: Variant) -> void:
	if not (node is CanvasItem):
		return
	var ci := node as CanvasItem
	var k := key_of(mode)
	if ci.material != null and not _ours(ci.material):
		# Desenfoque / shader del usuario: no se pisa (se guarda la intención).
		if k == "normal":
			if ci.has_meta(META):
				ci.remove_meta(META)
		else:
			ci.set_meta(META, k)
		return
	if k == "normal":
		if _ours(ci.material):
			ci.material = null
		if ci.has_meta(META):
			ci.remove_meta(META)
		_inherit(ci, false)
		ci.queue_redraw()
		return
	var mat: Material
	if k == "multiply":
		var cm := CanvasItemMaterial.new()
		cm.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		mat = cm
	else:
		var sm := ShaderMaterial.new()
		sm.shader = _shared_shader()
		sm.set_shader_parameter("mode", SHADER_MODES[k])
		mat = sm
	mat.set_meta(MAT_TAG, true)
	ci.material = mat
	ci.set_meta(META, k)
	_inherit(ci, _is_container(ci))
	ci.queue_redraw()

## Hijos de grupos y textos: heredan el material del padre (y lo sueltan).
static func _inherit(ci: CanvasItem, on: bool) -> void:
	for ch in ci.get_children():
		if not (ch is CanvasItem):
			continue
		var c := ch as CanvasItem
		if on:
			if c.material == null and not c.use_parent_material:
				c.use_parent_material = true
				c.set_meta("_blend_inherit", true)
		elif c.has_meta("_blend_inherit"):
			c.use_parent_material = false
			c.remove_meta("_blend_inherit")
		if _is_container(c) and not (c.has_meta(META)):
			_inherit(c, on)

## ¿El material de este nodo es el del modo de fusión? (el serializador no
## lo guarda como material: guarda la meta y se rehace al abrir).
static func is_blend_material(node: Node) -> bool:
	return node is CanvasItem and _ours((node as CanvasItem).material)
