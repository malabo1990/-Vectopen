// Contorno EXTERIOR de texto. La forma ya llega DILATADA desde la CPU
// (offset geométrico exacto de los glifos con esquinas redondeadas): aquí el
// grupo solo aplana los solapes entre letras y aplica el color. Antes: máximo
// del alfa en 3 anillos de 32 direcciones → con anchos grandes se veían los
// anillos y festones.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float u_radius = 0.0;
uniform vec4 u_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	float m = textureLod(screen_texture, SCREEN_UV, 0.0).a;
	COLOR = vec4(u_color.rgb, u_color.a * m);
}
