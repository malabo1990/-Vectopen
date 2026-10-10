// 3D / Bisel y relieve de TEXTO (canvas group con la máscara de las letras).
// Altura desde el alfa desenfocado: perfil "Suave" del 3D = el propio alfa
// gaussiano (σ = radio/10); el resto usa la distancia al borde recuperada
// invirtiendo el gaussiano (d = −σ·Φ⁻¹(A), exacta en bordes rectos).
// Trabaja en px de pantalla: u_px_per_unit = zoom (px por unidad del texto).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float u_px_per_unit = 1.0;

// Distancia con signo (px, < 0 dentro) y su gradiente a partir del alfa
// desenfocado: Φ(z) ≈ ½(1 + tanh(0,7979 z)) → d = −σ·atanh(2A−1)/0,7979.
vec3 fx_text_dist(vec3 ag, float sig) {
	float A = clamp(ag.x, 0.0005, 0.9995);
	float y = 2.0 * A - 1.0;
	float d = -sig * atanh(y) / 0.7978846;
	vec2 dd = -sig * (2.0 / (0.7978846 * max(1.0 - y * y, 0.002))) * ag.yz;
	return vec3(d, dd);
}

void fx_text_light(vec2 uv, vec2 px, out vec3 m, out vec4 s, out float k) {
	float zoom = max(u_px_per_unit, 0.0001);
	float sz_px = max(u_size * zoom, 0.5);
	float inside = textureLod(screen_texture, uv, 0.0).a;
	m = vec3(1.0);
	s = vec4(0.0);
	k = 0.0;
	float sig;
	bool bump = (u_mode == 0 && u_profile == 0);
	sig = bump ? sz_px / 10.0 : sz_px * 0.5;   // ver vector_light (Affinity)
	vec3 ag = fx_gauss_tex_grad(screen_texture, uv, px, sig);
	float A = clamp(ag.x, 0.0005, 0.9995);
	vec2 dh;   // gradiente de la altura por px
	float d_px;
	if (bump) {
		dh = 0.3 * ag.yz;   // misma escala que en figuras (vector_light)
		d_px = -sig * atanh(2.0 * A - 1.0) / 0.7978846;
	} else {
		// Distancia al borde a DOS escalas: la fina (1,5 px, exacta junto al
		// borde y en trazos finos, que con σ grande ni llegan al 50 %) y la
		// del tamaño (σ = tamaño/2, para distancias grandes).
		vec3 d_l = fx_text_dist(ag, sig);
		vec3 d_s = fx_text_dist(fx_gauss_tex_grad(screen_texture, uv, px, 1.5), 1.5);
		// Mezcla SUAVE por fiabilidad (un cambio brusco dejaba costuras): la
		// escala fina es exacta hasta ~4 px del borde y se satura a ~6 px;
		// más allá manda la grande (en trazos finos nunca se llega ahí).
		float w = 1.0 - smoothstep(3.5, 5.5, abs(d_s.x));
		vec3 dsel = mix(d_l, d_s, w);
		if (inside > 0.5) {
			dsel.x = min(dsel.x, 0.0);
		} else {
			dsel.x = max(dsel.x, 0.0);
		}
		d_px = dsel.x;
		vec2 dd = dsel.yz;
		float dpu = d_px / zoom;           // a unidades del texto para el estilo
		float t = fx_style_t(dpu);
		vec2 pr = fx_profile(t);
		float sz = max(u_size, 0.001);
		int st = u_mode == 1 ? u_style : 0;
		float dtdd;
		if (st == 2) {
			dtdd = -0.5 / sz;
		} else if (st == 3) {
			dtdd = sign(dpu) / sz;
		} else {
			dtdd = -1.0 / sz;
		}
		float active = (t > 0.0 && t < 1.0) ? 1.0 : 0.0;
		dh = pr.y * dtdd * active * dd / zoom;   // dd está en px/px
	}
	// máscara: dentro de las letras, fuera, o ambos (estilo de bisel)
	int sty = u_mode == 1 ? u_style : 0;
	if (sty == 1) {
		k = 1.0 - inside;
		k *= step(d_px, sz_px + u_soften * zoom + 2.0);
	} else if (sty >= 2) {
		k = 1.0;
	} else {
		k = inside;
	}
	k *= u_fx_opacity;
	if (k <= 0.001) {
		return;
	}
	// suavizar: aplana la pendiente (equivale a un gradiente más ancho)
	float soft = 1.0 / (1.0 + u_soften * zoom / max(sz_px, 1.0));
	// gradiente por unidad del texto = por px × zoom
	vec3 N = normalize(vec3(-u_relief * dh * zoom * soft, 1.0));
	if (u_mode == 1) {
		fx_bevel_eval(N, m, s);
	} else {
		fx_light_eval(N, m, s);
	}
}
