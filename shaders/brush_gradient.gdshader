// Degradado 2D de los trazos de pincel (brush_stroke_render.gd), en GPU:
// mover los puntos o cambiar las paradas solo actualiza uniformes / la
// textura del degradado; la malla del trazo no se recalcula ni se redibuja.
shader_type canvas_item;

uniform sampler2D grad_tex : filter_linear, repeat_disable;
uniform vec2 p0 = vec2(0.0);
uniform vec2 p1 = vec2(100.0, 0.0);
uniform int gtype = 0;   // 0 lineal, 1 radial

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;   // espacio local del trazo (el de p0 / p1)
}

void fragment() {
	vec2 ab = p1 - p0;
	float t;
	if (gtype == 1) {
		t = length(local_pos - p0) / max(length(ab), 1e-4);
	} else {
		t = dot(local_pos - p0, ab) / max(dot(ab, ab), 1e-8);
	}
	vec4 g = texture(grad_tex, vec2(clamp(t, 0.0, 1.0), 0.5));
	COLOR = g * COLOR;   // COLOR = blanco con la opacidad del pincel (× modulate)
}
