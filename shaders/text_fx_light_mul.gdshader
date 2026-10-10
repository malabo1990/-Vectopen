// 3D / Bisel y relieve de texto — pasada "mul" (ver text_fx_light.gdshaderinc).
shader_type canvas_item;
render_mode blend_mul;

#include "res://shaders/fx_gauss_tex.gdshaderinc"
#include "res://shaders/fx_light.gdshaderinc"
#include "res://shaders/text_fx_light.gdshaderinc"

void fragment() {
	vec3 m;
	vec4 s;
	float k;
	fx_text_light(SCREEN_UV, SCREEN_PIXEL_SIZE, m, s, k);
	COLOR = vec4(mix(vec3(1.0), m, k), 1.0);
}
