// =============================================================================
// SOMBRA INTERIOR / BRILLO INTERIOR de figuras: dentro de la figura,
// 1 − (figura desplazada y encogida por `spread`, con desenfoque gaussiano
// REAL de fx_gauss). σ = blur / 2. Sin cortes ni anillos.
// =============================================================================
shader_type canvas_item;
render_mode blend_mix;

#include "res://shaders/fx_gauss.gdshaderinc"

uniform vec2 u_offset = vec2(2.0, 2.0);
uniform float u_blur = 4.0;
uniform float u_spread = 0.0;
uniform vec4 u_shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);

varying vec2 v_shape_pos;

void vertex() {
	v_shape_pos = VERTEX;
}

void fragment() {
	float pxl = max(length(fwidth(v_shape_pos)) * 0.7071, 0.0001);
	// figura original (los polígonos llegan encogidos u_poly_pregrow = −spread)
	float d_shape = fx_sd_orig(v_shape_pos);
	float inside = 1.0 - smoothstep(-pxl, pxl, d_shape);
	if (inside <= 0.001) {
		discard;
	}
	float sigma = max(u_blur * 0.5, pxl * 0.5);
	float caster = fx_cover(v_shape_pos - u_offset, sigma, -u_spread);
	float a = (1.0 - caster) * inside * u_shadow_color.a;
	if (a <= 0.002) {
		discard;
	}
	COLOR = vec4(u_shadow_color.rgb, a);
}
