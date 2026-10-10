// =============================================================================
// 3D / BISEL Y RELIEVE de FIGURAS y TRAZADOS: altura analítica (fx_gauss:
// gaussiano exacto o distancia euclídea exacta), normal por diferencias
// centrales (el paso crece con "suavizar") y luz de fx_light.
// Requiere fx_gauss.gdshaderinc y fx_light.gdshaderinc incluidos antes.
// =============================================================================

float fx_height(vec2 p) {
	if (u_mode == 0 && u_profile == 0) {
		// Suave (Affinity / GIMP "Bump"): la figura desenfocada. σ = radio/10:
		// calibrado con Affinity (radio 100 en una figura de 92 px → la
		// pendiente ocupa ~20 % del ancho y el centro queda plano).
		// Altura × 0,3: con profundidad = radio la pendiente máxima ronda los
		// 50° (lado de la luz blanco hasta el borde, el contrario negro).
		return 0.3 * fx_cover(p, max(u_size / 10.0, 0.3), 0.0);
	}
	return fx_profile(fx_style_t(fx_sd_orig(p))).x;
}

// m: color para multiplicar · s: color de la luz + cantidad · k: máscara
void fx_shape_light(vec2 p, float pxl, out vec3 m, out vec4 s, out float k) {
	float d = fx_sd_orig(p);
	k = fx_style_mask(d, pxl) * u_fx_opacity;
	m = vec3(1.0);
	s = vec4(0.0);
	if (k <= 0.001) {
		return;
	}
	float e = max(pxl * 0.75, u_soften * 0.5);
	vec2 g = vec2(fx_height(p + vec2(e, 0.0)) - fx_height(p - vec2(e, 0.0)),
			fx_height(p + vec2(0.0, e)) - fx_height(p - vec2(0.0, e))) / (2.0 * e);
	vec3 N = normalize(vec3(-u_relief * g, 1.0));
	if (u_mode == 1) {
		fx_bevel_eval(N, m, s);
	} else {
		fx_light_eval(N, m, s);
	}
}
