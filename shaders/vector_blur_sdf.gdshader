// =============================================================================
// EFECTO "DESENFOQUE" de figuras: desenfoque gaussiano REAL de la figura
// (relleno + trazo) con fx_gauss (integral exacta). σ = radio / 2 y el halo
// llega hasta 3σ (el quad se dibuja con ese margen: nada se corta).
// Direccionales (movimiento / radial / giro): media de la cobertura a lo
// largo de la trayectoria con 48 muestras y cada muestra suavizada al
// espaciado entre muestras (filtro tienda) → sin copias visibles.
// =============================================================================
shader_type canvas_item;
render_mode blend_mix;

#include "res://shaders/fx_gauss.gdshaderinc"

uniform float u_blur_radius = 10.0;
// Tipo: 0 gaussiano, 1 movimiento (u_motion_dir), 2 radial / zoom desde
// u_center, 3 giratorio alrededor de u_center (u_blur_radius = grados).
uniform int u_blur_type = 0;
uniform vec2 u_motion_dir = vec2(1.0, 0.0);
uniform vec2 u_center = vec2(0.0, 0.0);
uniform bool u_preserve_alpha = false;
uniform vec4 u_fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 u_stroke_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float u_stroke_width = 0.0;

varying vec2 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

float directional_alpha(vec2 p, float aa) {
	const int N = 48;
	float acc = 0.0;
	// separación entre muestras (unidades locales) → borde de cada muestra
	float span;
	if (u_blur_type == 1) {
		span = 2.0 * u_blur_radius;
	} else if (u_blur_type == 2) {
		span = length(p - u_center) * u_blur_radius / 50.0;
	} else {
		span = length(p - u_center) * radians(u_blur_radius);
	}
	float soft = max(aa, span / float(N));
	for (int i = 0; i < N; i++) {
		float t = (float(i) + 0.5) / float(N) - 0.5;
		vec2 q = p;
		if (u_blur_type == 1) {
			q = p - u_motion_dir * (t * 2.0 * u_blur_radius);
		} else if (u_blur_type == 2) {
			q = u_center + (p - u_center) * (1.0 + t * u_blur_radius / 50.0);
		} else {
			float a = t * radians(u_blur_radius);
			vec2 r = p - u_center;
			q = u_center + vec2(r.x * cos(a) - r.y * sin(a), r.x * sin(a) + r.y * cos(a));
		}
		acc += 1.0 - smoothstep(-soft, soft, fx_sd(q, 0.0));
	}
	return acc / float(N);
}

void fragment() {
	vec2 p = v_local_pos;
	// tamaño de un píxel de pantalla en unidades locales (suavizado mínimo)
	float pxl = max(length(fwidth(p)) * 0.7071, 0.0001);
	float hw = u_stroke_width > 0.0 && u_stroke_color.a > 0.0 ? u_stroke_width * 0.5 : 0.0;
	float d_outer = fx_sd(p, hw);
	float sharp_outer = 1.0 - smoothstep(-pxl, pxl, d_outer);

	vec4 outc;
	if (u_blur_type > 0 && u_blur_radius > 0.5) {
		float da = directional_alpha(p, pxl);
		outc = vec4(u_fill_color.rgb, u_fill_color.a * da);
	} else {
		float sigma = max(u_blur_radius * 0.5, pxl * 0.5);
		float fa = u_fill_color.a;
		float sa = hw > 0.0 ? u_stroke_color.a : 0.0;
		vec3 pm;
		float a;
		if (hw > 0.0 && u_shape_type < 2) {
			// relleno dentro del borde interior, trazo en el anillo, y bajo la
			// mitad interior del trazo el relleno (si el trazo es translúcido)
			float a_out = fx_cover_sd(p, sigma, hw, d_outer);
			float a_mid = fx_cover(p, sigma, 0.0);
			float a_in = fx_cover(p, sigma, -hw);
			float ring = max(a_out - a_in, 0.0);
			float under = max(a_mid - a_in, 0.0) * (1.0 - sa);
			pm = u_fill_color.rgb * fa * (a_in + under) + u_stroke_color.rgb * sa * ring;
			a = fa * (a_in + under) + sa * ring;
		} else {
			float c = fx_cover(p, sigma, 0.0);
			vec3 col = u_fill_color.rgb;
			if (sa > 0.0) {
				// polígonos: el trazo tiñe el borde según su "masa"
				float k = exp(-0.5 * pow(fx_sd(p, 0.0) / max(sigma, hw), 2.0));
				float mass = clamp(u_stroke_width / (u_stroke_width + sigma * 1.5), 0.0, 1.0);
				col = mix(col, u_stroke_color.rgb, k * sa * mass);
			}
			pm = col * fa * c;
			a = fa * c;
		}
		if (u_preserve_alpha) {
			pm *= sharp_outer;
			a *= sharp_outer;
		}
		outc = a > 0.0001 ? vec4(pm / a, a) : vec4(0.0);
	}
	if (outc.a <= 0.002) {
		discard;
	}
	COLOR = outc;
}
