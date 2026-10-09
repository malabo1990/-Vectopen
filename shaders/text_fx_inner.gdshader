// Sombra / brillo INTERIOR de texto en UNA pasada. El CanvasGroup dibuja (en
// mezcla aditiva) la máscara de las letras en el canal ROJO y la máscara
// desplazada en el VERDE. Resultado: color × dentro × (1 − verde desenfocado).
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float u_radius = 4.0;          // px de pantalla
uniform vec4 u_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);

void fragment() {
	float inside = textureLod(screen_texture, SCREEN_UV, 0.0).r;
	float m = 0.0;
	float total = 0.0;
	const int N = 24;
	float lod = max(0.0, log2(u_radius / 5.0));
	for (int i = 0; i < N; i++) {
		float t = (float(i) + 0.5) / float(N);
		float r = sqrt(t) * max(u_radius, 0.0);
		float a = float(i) * 2.39996323;
		vec2 o = vec2(cos(a), sin(a)) * r * SCREEN_PIXEL_SIZE;
		float w = exp(-2.0 * t);
		m += textureLod(screen_texture, SCREEN_UV + o, lod).g * w;
		total += w;
	}
	m /= total;
	COLOR = vec4(u_color.rgb, u_color.a * clamp(inside, 0.0, 1.0) * (1.0 - clamp(m, 0.0, 1.0)));
}
