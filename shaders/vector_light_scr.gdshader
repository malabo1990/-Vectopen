// 3D / Bisel y relieve de figuras — pasada de LUCES (trama: mezcla premultiplicada hacia el color de la luz).
// Ver vector_light.gdshaderinc y fx_light.gdshaderinc.
shader_type canvas_item;
render_mode blend_premul_alpha;

#include "res://shaders/fx_gauss.gdshaderinc"
#include "res://shaders/fx_light.gdshaderinc"
#include "res://shaders/vector_light.gdshaderinc"

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float pxl = max(length(fwidth(v_local)) * 0.7071, 0.0001);
	vec3 m;
	vec4 s;
	float k;
	fx_shape_light(v_local, pxl, m, s, k);
	if (k <= 0.001) {
		discard;
	}
	float a = clamp(s.a * k, 0.0, 1.0);
	COLOR = vec4(s.rgb * a, a);
}
