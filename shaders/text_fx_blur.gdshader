// Desenfoque de un CanvasGroup (efectos de texto: sombra, brillo, desenfoque).
// El grupo dibuja los glifos; aquí se promedian 32 muestras en espiral
// (ángulo áureo) dentro de `u_radius` píxeles de pantalla. Con `u_tint` el
// resultado toma ese color (sombra / brillo); sin él, conserva los colores.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
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
	if (u_type > 0 && (u_radius >= 0.5 || u_type >= 2)) {
		const int M = 32;
		vec2 px = SCREEN_PIXEL_SIZE;
		// Separación entre muestras (px) → mip para que no se vean copias.
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
	} else if (u_radius < 0.5) {
		acc = textureLod(screen_texture, SCREEN_UV, 0.0);
	} else {
		float total = 0.0;
		const int N = 32;
		float lod = max(0.0, log2(u_radius / 5.0));
		for (int i = 0; i < N; i++) {
			float t = (float(i) + 0.5) / float(N);
			float r = sqrt(t) * u_radius;
			float a = float(i) * 2.39996323;
			vec2 o = vec2(cos(a), sin(a)) * r * SCREEN_PIXEL_SIZE;
			// Peso gaussiano aproximado: el centro pesa más.
			float w = exp(-2.0 * t);
			// Mip acorde a la separación entre muestras: con radios grandes
			// se muestrea una versión ya suavizada (sin grano).
			acc += textureLod(screen_texture, SCREEN_UV + o, lod) * w;
			total += w;
		}
		acc /= total;
	}
	if (u_use_tint) {
		COLOR = vec4(u_tint.rgb, acc.a * u_tint.a);
	} else {
		COLOR = acc;
	}
}
