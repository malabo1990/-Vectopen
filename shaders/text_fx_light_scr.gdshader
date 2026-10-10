// 3D / Bisel y relieve de texto — pasada "scr" (ver text_fx_light.gdshaderinc).
shader_type canvas_item;
render_mode blend_premul_alpha;

#include "res://shaders/fx_gauss_tex.gdshaderinc"
#include "res://shaders/fx_light.gdshaderinc"
#include "res://shaders/text_fx_light.gdshaderinc"

void fragment() {
	vec3 m;
	vec4 s;
	float k;
	fx_text_light(SCREEN_UV, SCREEN_PIXEL_SIZE, m, s, k);
	float a = clamp(s.a * k, 0.0, 1.0);
	COLOR = vec4(s.rgb * a, a);
}
