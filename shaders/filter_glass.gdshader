// =============================================================================
// FILTRO "CRISTAL ESMERILADO" (glassmorphism): desenfoca LO QUE HAY DETRÁS
// del objeto dentro de su silueta, lo tiñe y le añade escarcha. Se dibuja
// justo antes del objeto, tras una copia del fondo (copy_to_backbuffer).
// =============================================================================
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D st : hint_screen_texture, filter_linear_mipmap, repeat_disable;

#include "res://shaders/fx_gauss_tex.gdshaderinc"
uniform float u_blur_px = 12.0;        // radio en px de pantalla
uniform vec4 u_tint : source_color = vec4(1.0, 1.0, 1.0, 0.18);
uniform float u_frost = 0.15;
uniform float u_saturation = 1.2;
uniform float u_grain_cell = 1.0;      // unidades locales por grano

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	// fondo con desenfoque gaussiano real (σ = desenfoque / 2)
	vec3 acc = fx_gauss_tex(st, SCREEN_UV, px, max(u_blur_px, 0.0) * 0.5).rgb;
	float lum = dot(acc, vec3(0.299, 0.587, 0.114));
	acc = mix(vec3(lum), acc, u_saturation);
	vec3 col = mix(acc, u_tint.rgb, u_tint.a);
	float n = hash(floor(v_local / max(u_grain_cell, 0.25))) - 0.5;
	col = clamp(col + n * u_frost, vec3(0.0), vec3(1.0));
	COLOR = vec4(col, COLOR.a);
}
