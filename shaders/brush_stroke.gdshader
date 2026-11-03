// Trazo de pincel (brush_stroke_render.gd): textura del estilo, degradado 2D
// opcional y ANTIALIAS DEL BORDE. UV.y va de 0 a 1 a lo ancho del trazo (en
// uniones y remates, 0,5 en el centro y 1 en el borde): el borde se funde en
// ~1 px de pantalla a cualquier zoom, sin geometría extra. Sin esto el borde
// salía en escalera (el MSAA 2D, si está, solo da 2 niveles).
shader_type canvas_item;

uniform bool use_grad = false;
uniform sampler2D grad_tex : filter_linear, repeat_disable;
uniform vec2 p0 = vec2(0.0);
uniform vec2 p1 = vec2(100.0, 0.0);
uniform int gtype = 0;   // 0 lineal, 1 radial

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;   // espacio local del trazo (el de p0 / p1)
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	if (use_grad) {
		vec2 ab = p1 - p0;
		float t;
		if (gtype == 1) {
			t = length(local_pos - p0) / max(length(ab), 1e-4);
		} else {
			t = dot(local_pos - p0, ab) / max(dot(ab, ab), 1e-8);
		}
		c *= texture(grad_tex, vec2(clamp(t, 0.0, 1.0), 0.5));
	}
	// 1 en el eje, 0 en el borde. Cobertura del píxel centrada en el borde
	// real (+0,5): el trazo no adelgaza medio píxel por lado.
	float e = 1.0 - abs(2.0 * UV.y - 1.0);
	float w = max(fwidth(e), 1e-6);
	c.a *= clamp(e / w + 0.5, 0.0, 1.0);
	COLOR = c;
}
