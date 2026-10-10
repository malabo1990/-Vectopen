// Sombra / brillo INTERIOR de texto en UNA pasada. El CanvasGroup dibuja (en
// mezcla aditiva) la máscara de las letras en el canal ROJO y la máscara
// desplazada en el VERDE. Resultado: color × dentro × (1 − verde desenfocado)
// con desenfoque gaussiano real (σ = u_radius / 2, fx_gauss_tex).
// `u_gain` 2 = brillo interior: pleno en el borde y se apaga hacia dentro.
shader_type canvas_item;
render_mode blend_mix;

#include "res://shaders/fx_gauss_tex.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float u_radius = 4.0;          // px de pantalla
uniform vec4 u_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform float u_gain = 1.0;

void fragment() {
	float inside = textureLod(screen_texture, SCREEN_UV, 0.0).r;
	float m = fx_gauss_tex(screen_texture, SCREEN_UV, SCREEN_PIXEL_SIZE, max(u_radius, 0.5) * 0.5).g;
	float k = clamp((1.0 - clamp(m, 0.0, 1.0)) * u_gain, 0.0, 1.0);
	COLOR = vec4(u_color.rgb, u_color.a * clamp(inside, 0.0, 1.0) * k);
}
