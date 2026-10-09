// Contorno EXTERIOR de texto por dilatación de la máscara de las letras:
// máximo del alfa en un disco de radio u_radius (px). Esquinas redondeadas
// limpias y los huecos de las letras se respetan (antes: líneas gruesas con
// picos en las uniones agudas).
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float u_radius = 2.0;
uniform vec4 u_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	float m = textureLod(screen_texture, SCREEN_UV, 0.0).a;
	const int DIRS = 32;
	for (int ring = 1; ring <= 3; ring++) {
		float r = u_radius * float(ring) / 3.0;
		for (int i = 0; i < DIRS; i++) {
			float a = float(i) * 6.28318530718 / float(DIRS);
			vec2 o = vec2(cos(a), sin(a)) * r * SCREEN_PIXEL_SIZE;
			m = max(m, textureLod(screen_texture, SCREEN_UV + o, 0.0).a);
		}
	}
	COLOR = vec4(u_color.rgb, u_color.a * m);
}
