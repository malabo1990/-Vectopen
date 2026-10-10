// =============================================================================
// SOMBRA PROYECTADA de figuras: la figura desplazada, crecida por `spread`
// y con desenfoque gaussiano REAL (fx_gauss). σ = blur / 2, halo hasta 3σ.
// Antes: curva sobre la distancia al borde con un corte a 2,8σ (anillo duro
// con valores altos y núcleo sólido aunque el desenfoque fuera enorme).
// =============================================================================
shader_type canvas_item;
render_mode blend_mix;

#include "res://shaders/fx_gauss.gdshaderinc"

uniform vec2 u_shadow_offset = vec2(0.0, 0.0);
uniform float u_blur = 10.0;
uniform float u_spread = 0.0;
uniform vec4 u_shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
// La sombra exterior no se dibuja dentro de la figura (como Figma / CSS).
uniform bool u_clip_inside = true;

varying vec2 v_shadow_pos;
varying vec2 v_shape_pos;

void vertex() {
	v_shadow_pos = VERTEX - u_shadow_offset;
	v_shape_pos = VERTEX;
}

void fragment() {
	float pxl = max(length(fwidth(v_shape_pos)) * 0.7071, 0.0001);
	float sigma = max(u_blur * 0.5, pxl * 0.5);
	float alpha = fx_cover(v_shadow_pos, sigma, u_spread);
	if (u_clip_inside) {
		// figura original (los polígonos llegan crecidos u_poly_pregrow)
		float d_shape = fx_sd_orig(v_shape_pos);
		alpha *= smoothstep(-pxl, pxl, d_shape);
	}
	if (alpha <= 0.002) {
		discard;
	}
	COLOR = vec4(u_shadow_color.rgb, u_shadow_color.a * alpha);
}
