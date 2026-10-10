// 3D / Bisel y relieve de figuras — pasada de SOMBRAS (multiplicar).
// Ver vector_light.gdshaderinc y fx_light.gdshaderinc.
shader_type canvas_item;
render_mode blend_mul;

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
	COLOR = vec4(mix(vec3(1.0), m, k), 1.0);
}
