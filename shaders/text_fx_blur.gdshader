// Desenfoque de un CanvasGroup (efectos de texto: sombra, desenfoque).
// Gaussiano: σ = u_radius / 2 con fx_gauss_tex (rejilla 9×9 sobre mipmaps,
// sin copias ni anillos). Direccionales: 48 muestras con el mip acorde a la
// separación. Con `u_tint` el resultado toma ese color (sombra); sin él,
// conserva los colores.
shader_type canvas_item;
render_mode blend_mix;

#include "res://shaders/fx_gauss_tex.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float u_radius = 0.0;          // px de pantalla
uniform bool u_use_tint = true;
uniform vec4 u_tint : source_color = vec4(0.0, 0.0, 0.0, 0.5);
// Tipo: 0 gaussiano, 1 movimiento (u_dir), 2 radial / zoom desde u_center,
// 3 giratorio alrededor de u_center (u_spin = radianes totales).
uniform int u_type = 0;
uniform vec2 u_dir = vec2(1.0, 0.0);
uniform vec2 u_center = vec2(0.5, 0.5);   // en UV de pantalla
uniform float u_zoom_k = 0.1;             // radial: fracción del radio
uniform float u_spin = 0.2;

void fragment() {
	vec4 acc = vec4(0.0);
	vec2 px = SCREEN_PIXEL_SIZE;
	if (u_type > 0 && (u_radius >= 0.5 || u_type >= 2)) {
		const int M = 48;
		float span_px = u_type == 1 ? (2.0 * u_radius) : (u_type == 2 ? length((SCREEN_UV - u_center) / px) * u_zoom_k : length((SCREEN_UV - u_center) / px) * u_spin);
		float lodd = max(0.0, log2(span_px / float(M) * 1.5));
		vec2 aspect = vec2(px.y / px.x, 1.0);
		for (int i = 0; i < M; i++) {
			float t = (float(i) + 0.5) / float(M) - 0.5;
			vec2 uv = SCREEN_UV;
			if (u_type == 1) {
				uv = SCREEN_UV + u_dir * (t * 2.0 * u_radius) * px;
			} else if (u_type == 2) {
				uv = u_center + (SCREEN_UV - u_center) * (1.0 + t * u_zoom_k);
			} else {
				vec2 r = (SCREEN_UV - u_center) / aspect;
				float a = t * u_spin;
				r = vec2(r.x * cos(a) - r.y * sin(a), r.x * sin(a) + r.y * cos(a));
				uv = u_center + r * aspect;
			}
			acc += textureLod(screen_texture, uv, lodd);
		}
		acc /= float(M);
	} else {
		acc = fx_gauss_tex(screen_texture, SCREEN_UV, px, u_radius * 0.5);
	}
	if (u_use_tint) {
		COLOR = vec4(u_tint.rgb, acc.a * u_tint.a);
	} else {
		// el grupo está premultiplicado
		COLOR = acc.a > 0.0001 ? vec4(acc.rgb / acc.a, acc.a) : vec4(0.0);
	}
}
