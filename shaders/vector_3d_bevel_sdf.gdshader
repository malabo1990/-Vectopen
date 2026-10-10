shader_type canvas_item;
render_mode blend_mix;

// Tipos de forma soportados:
// 0 = Rectángulo / Rectángulo redondeado
// 1 = Círculo / Elipse
// 2 = Polígono / Estrella / Trazo Bézier
uniform int u_shape_type : hint_range(0, 2) = 0;

// Parámetros de rectángulo
uniform vec2 u_rect_size = vec2(100.0, 100.0);
uniform vec4 u_corner_radii = vec4(0.0);

// Parámetros de elipse/círculo
uniform vec2 u_radii = vec2(50.0, 50.0);

// Parámetros de polígono (hasta 64 vértices en espacio local centrado)
uniform vec2 u_poly_points[64];
uniform int u_poly_count = 0;

// Parámetros de Bisel 3D
uniform float u_depth = 8.0;          // Profundidad / elevación (0 - 100)
uniform float u_bevel = 8.0;          // Ancho del bisel en px (0.5 - 50)
uniform float u_angle = 45.0;         // Dirección de la luz en grados (0 - 360)
uniform float u_highlight = 70.0;     // Intensidad de resplandor especular % (0 - 100)
uniform float u_shadow = 60.0;        // Intensidad de sombra de pendiente % (0 - 100)
// Curva de contorno (Gloss Contour estilo Photoshop):
// 0 = Curvo (Half Round)
// 1 = Lineal (Chisel Hard)
// 2 = Suave (Gaussian)
// 3 = Anillo (Ring / Double Bevel)
// 4 = Profundo (Cone)
uniform int u_contour : hint_range(0, 4) = 0;

varying vec2 v_shape_pos;

void vertex() {
	v_shape_pos = VERTEX;
}

float sd_rounded_box(vec2 p, vec2 b, vec4 r) {
	float rad = (p.x < 0.0) ? 
		((p.y < 0.0) ? r.x : r.w) : 
		((p.y < 0.0) ? r.y : r.z);
	rad = min(rad, min(b.x, b.y));
	vec2 q = abs(p) - b + vec2(rad);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - rad;
}

float sd_ellipse(vec2 p, vec2 r) {
	if (abs(r.x - r.y) < 0.001) {
		return length(p) - r.x;
	}
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	return k0 * (k0 - 1.0) / max(k1, 0.00001);
}

float sd_polygon(vec2 p, int count) {
	if (count < 3) return 10000.0;
	float d = dot(p - u_poly_points[0], p - u_poly_points[0]);
	float s = 1.0;
	for (int i = 0, j = count - 1; i < count; j = i, i++) {
		vec2 e = u_poly_points[j] - u_poly_points[i];
		vec2 w = p - u_poly_points[i];
		vec2 b = w - e * clamp(dot(w, e) / max(dot(e, e), 0.00001), 0.0, 1.0);
		d = min(d, dot(b, b));
		bvec3 c = bvec3(p.y >= u_poly_points[i].y, p.y < u_poly_points[j].y, e.x * w.y > e.y * w.x);
		if (all(c) || all(not(c))) s = -s;
	}
	return s * sqrt(d);
}

float eval_shape_distance(vec2 p) {
	if (u_shape_type == 0) {
		return sd_rounded_box(p, u_rect_size * 0.5, u_corner_radii);
	} else if (u_shape_type == 1) {
		return sd_ellipse(p, u_radii);
	} else {
		return sd_polygon(p, u_poly_count);
	}
}

// Retorna la pendiente dZ/du según la curva de contorno elegida
float get_contour_slope(float u, int contour_type) {
	if (contour_type == 1) {

		// Lineal (Chisel): pendiente constante
		return 1.0;
	} else if (contour_type == 2) {
		// Suave (Gaussian / Smoothstep)
		return 6.0 * u * (1.0 - u);
	} else if (contour_type == 3) {
		// Anillo (Ring / Double Bevel)
		return sin(u * 2.0 * PI);
	} else if (contour_type == 4) {
		// Profundo (Cone)
		return 0.5 / max(sqrt(max(u, 0.001)), 0.05);
	}
	// Default 0: Curvo (Half Round)
	return cos(u * 0.5 * PI);
}

void fragment() {
	float d_shape = eval_shape_distance(v_shape_pos);
	float aa = max(fwidth(d_shape), 0.001);

	// Máscara interior anti-aliasing estricta
	float inside_mask = 1.0 - smoothstep(-aa, aa, d_shape);
	if (inside_mask <= 0.001) {
		discard;
	}

	float bevel_px = max(u_bevel, 0.5);
	float dist_in = -d_shape;

	// Si estamos más allá del ancho del bisel hacia el centro plano:
	if (dist_in > bevel_px + aa) {
		discard;
	}

	// Normal 2D del campo de distancias por diferencias finitas
	float eps = max(aa * 1.5, 0.5);
	vec2 grad = vec2(
		eval_shape_distance(v_shape_pos + vec2(eps, 0.0)) - eval_shape_distance(v_shape_pos - vec2(eps, 0.0)),
		eval_shape_distance(v_shape_pos + vec2(0.0, eps)) - eval_shape_distance(v_shape_pos - vec2(0.0, eps))
	);
	vec2 n_2d = normalize(grad + vec2(1e-5));

	// Posición normalizada en el bisel (0 = borde exterior, 1 = cima interior)
	float u = clamp(dist_in / bevel_px, 0.0, 1.0);
	float slope = get_contour_slope(u, u_contour);

	// Transición suave al plateau interior (u -> 1)
	float plateau_fade = 1.0 - smoothstep(bevel_px - aa * 2.0, bevel_px, dist_in);

	// Vector normal 3D continuo de la superficie
	float z_scale = (u_depth * 0.4) / bevel_px;
	vec3 normal_3d = normalize(vec3(-n_2d * slope * z_scale, 1.0));

	// Dirección de la luz en coordenadas 3D
	float rad = radians(u_angle);
	vec3 light_dir = normalize(vec3(cos(rad), sin(rad), 1.2));
	vec3 view_dir = vec3(0.0, 0.0, 1.0);
	vec3 half_dir = normalize(light_dir + view_dir);

	// Difusa direccional
	float ndotl = dot(normal_3d, light_dir);

	// Especular (crest shine)
	float ndoth = max(dot(normal_3d, half_dir), 0.0);
	float spec = pow(ndoth, 24.0);

	// Cálculo de intensidades de iluminación y sombra
	float hl_diff = max(ndotl, 0.0);
	float sh_diff = max(-ndotl, 0.0);

	float hl_factor = (hl_diff * 0.7 + spec * 1.1) * (u_highlight / 100.0);
	float sh_factor = (sh_diff * 0.85) * (u_shadow / 100.0);

	hl_factor = clamp(hl_factor * plateau_fade * inside_mask, 0.0, 1.0);
	sh_factor = clamp(sh_factor * plateau_fade * inside_mask, 0.0, 1.0);

	// Salida de color compuesta: highlight blanco o sombra negra translúcida
	vec3 final_rgb = mix(vec3(0.0), vec3(1.0), hl_factor / max(hl_factor + sh_factor, 0.0001));
	float final_alpha = max(hl_factor, sh_factor);

	if (final_alpha <= 0.002) {
		discard;
	}

	COLOR = vec4(final_rgb, final_alpha);
}
