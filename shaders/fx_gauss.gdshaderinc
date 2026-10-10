// =============================================================================
// DESENFOQUE GAUSSIANO EXACTO DE UNA FIGURA (efectos de figuras y trazados)
// fx_cover(p, σ, grow) = ∫ G_σ(p − q) · dentro(q) dq  — la convolución real de
// la figura con una gaussiana 2D (como feGaussianBlur / Figma / Photoshop):
//   · rectángulo sin esquinas: forma cerrada (producto de dos erf);
//   · rectángulo redondeado / elipse / polígono: integración por filas en y
//     (regla del punto medio dentro de la figura) y, en cada fila, la
//     gaussiana en x de forma exacta con erf (intervalos o cruces).
// Antes: una curva sobre la distancia al borde, cortada a 2σ → el núcleo
// seguía sólido con radios grandes y el halo acababa en un corte.
// La figura va centrada en el origen (espacio local).
// =============================================================================

uniform int u_shape_type : hint_range(0, 2) = 0;   // 0 rect, 1 elipse, 2 polígono
uniform vec2 u_rect_size = vec2(100.0, 100.0);
uniform vec4 u_corner_radii = vec4(0.0);            // TL, TR, BR, BL
uniform vec2 u_radii = vec2(50.0, 50.0);
uniform vec2 u_poly_points[64];
uniform int u_poly_count = 0;
uniform vec4 u_poly_bounds = vec4(0.0);             // xmin, ymin, xmax, ymax
// Polígonos: los puntos ya vienen crecidos (offset en CPU) esta cantidad.
uniform float u_poly_pregrow = 0.0;
// Polígono ORIGINAL (sin crecer): recortes exactos de sombra / interior.
uniform vec2 u_orig_points[64];
uniform int u_orig_count = 0;

float fx_erf(float x) {
	// Abramowitz-Stegun 7.1.26 (error < 1.5e-7)
	float s = sign(x);
	float a = abs(x);
	float t = 1.0 / (1.0 + 0.3275911 * a);
	float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-a * a);
	return s * y;
}

// Función de distribución normal estándar Φ(z)
float fx_ncdf(float z) {
	return 0.5 + 0.5 * fx_erf(z * 0.70710678);
}

float fx_sd_rbox(vec2 p, vec2 b, vec4 r) {
	float rad = (p.x < 0.0) ? ((p.y < 0.0) ? r.x : r.w) : ((p.y < 0.0) ? r.y : r.z);
	rad = min(rad, min(b.x, b.y));
	vec2 q = abs(p) - b + vec2(rad);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - rad;
}

float fx_sd_ellipse(vec2 p, vec2 r) {
	if (abs(r.x - r.y) < 0.001) {
		return length(p) - r.x;
	}
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	return k0 * (k0 - 1.0) / max(k1, 0.00001);
}

float fx_sd_poly(vec2 p) {
	if (u_poly_count < 3) return 10000.0;
	float d = dot(p - u_poly_points[0], p - u_poly_points[0]);
	float s = 1.0;
	for (int i = 0, j = u_poly_count - 1; i < u_poly_count; j = i, i++) {
		vec2 e = u_poly_points[j] - u_poly_points[i];
		vec2 w = p - u_poly_points[i];
		vec2 b = w - e * clamp(dot(w, e) / max(dot(e, e), 0.00001), 0.0, 1.0);
		d = min(d, dot(b, b));
		bvec3 c = bvec3(p.y >= u_poly_points[i].y, p.y < u_poly_points[j].y, e.x * w.y > e.y * w.x);
		if (all(c) || all(not(c))) s = -s;
	}
	return s * sqrt(d);
}

vec4 fx_grown_radii(float grow) {
	// Las esquinas redondeadas crecen con la figura; las rectas siguen rectas.
	return vec4(
		u_corner_radii.x > 0.0 ? max(u_corner_radii.x + grow, 0.0) : 0.0,
		u_corner_radii.y > 0.0 ? max(u_corner_radii.y + grow, 0.0) : 0.0,
		u_corner_radii.z > 0.0 ? max(u_corner_radii.z + grow, 0.0) : 0.0,
		u_corner_radii.w > 0.0 ? max(u_corner_radii.w + grow, 0.0) : 0.0);
}

// Distancia con signo a la figura crecida `grow` (<0 dentro).
float fx_sd(vec2 p, float grow) {
	if (u_shape_type == 0) {
		vec2 h = max(u_rect_size * 0.5 + grow, vec2(0.0001));
		return fx_sd_rbox(p, h, fx_grown_radii(grow));
	} else if (u_shape_type == 1) {
		return fx_sd_ellipse(p, max(u_radii + grow, vec2(0.0001)));
	}
	return fx_sd_poly(p) + u_poly_pregrow - grow;
}

// Distancia con signo a la figura ORIGINAL (recortes "dentro / fuera").
float fx_sd_orig(vec2 p) {
	if (u_shape_type != 2 || u_orig_count < 3) {
		return fx_sd(p, u_shape_type == 2 ? u_poly_pregrow : 0.0);
	}
	float d = dot(p - u_orig_points[0], p - u_orig_points[0]);
	float s = 1.0;
	for (int i = 0, j = u_orig_count - 1; i < u_orig_count; j = i, i++) {
		vec2 e = u_orig_points[j] - u_orig_points[i];
		vec2 w = p - u_orig_points[i];
		vec2 b = w - e * clamp(dot(w, e) / max(dot(e, e), 0.00001), 0.0, 1.0);
		d = min(d, dot(b, b));
		bvec3 c = bvec3(p.y >= u_orig_points[i].y, p.y < u_orig_points[j].y, e.x * w.y > e.y * w.x);
		if (all(c) || all(not(c))) s = -s;
	}
	return s * sqrt(d);
}

// Intervalo [x0, x1] de la fila y dentro de rect redondeado / elipse.
vec2 fx_span(float y, float grow) {
	if (u_shape_type == 0) {
		vec2 h = u_rect_size * 0.5 + grow;
		if (h.x <= 0.0 || h.y <= 0.0 || abs(y) >= h.y) return vec2(1.0, -1.0);
		vec4 r = fx_grown_radii(grow);
		float lim = min(h.x, h.y);
		float rl = min(y < 0.0 ? r.x : r.w, lim);
		float rr = min(y < 0.0 ? r.y : r.z, lim);
		float ay = abs(y);
		float xl = -h.x;
		float dl = ay - (h.y - rl);
		if (dl > 0.0) xl = -h.x + rl - sqrt(max(rl * rl - dl * dl, 0.0));
		float xr = h.x;
		float dr = ay - (h.y - rr);
		if (dr > 0.0) xr = h.x - rr + sqrt(max(rr * rr - dr * dr, 0.0));
		return vec2(xl, xr);
	}
	vec2 R = u_radii + grow;
	if (R.x <= 0.0 || R.y <= 0.0 || abs(y) >= R.y) return vec2(1.0, -1.0);
	float w = R.x * sqrt(max(1.0 - (y * y) / (R.y * R.y), 0.0));
	return vec2(-w, w);
}

// Fila de un polígono desenfocada en x: Σ dir · Φ((x − xi)/σ) sobre los
// cruces (número de vueltas suavizado; sin ordenar los cruces).
float fx_poly_row(float y, float px, float is) {
	float s = 0.0;
	for (int i = 0, j = u_poly_count - 1; i < u_poly_count; j = i, i++) {
		vec2 A = u_poly_points[j];
		vec2 B = u_poly_points[i];
		if ((A.y <= y) != (B.y <= y)) {
			float x = A.x + (y - A.y) * (B.x - A.x) / (B.y - A.y);
			s += (B.y > A.y ? 1.0 : -1.0) * fx_ncdf((px - x) * is);
		}
	}
	return abs(s);
}

// Cobertura gaussiana (0..1) de la figura crecida `grow` en el punto p.
// `sd` = fx_sd(p, grow) ya calculada (atajos lejos del borde).
float fx_cover_sd(vec2 p, float sigma, float grow, float sd) {
	float s = max(sigma, 0.05);
	if (sd > 4.5 * s) return 0.0;
	float is = 1.0 / s;
	if (u_shape_type == 0 && all(lessThanEqual(u_corner_radii, vec4(0.0)))) {
		vec2 h = u_rect_size * 0.5 + grow;
		if (h.x <= 0.0 || h.y <= 0.0) return 0.0;
		float ax = fx_ncdf((h.x - p.x) * is) - fx_ncdf((-h.x - p.x) * is);
		float ay = fx_ncdf((h.y - p.y) * is) - fx_ncdf((-h.y - p.y) * is);
		return clamp(ax * ay, 0.0, 1.0);
	}
	if (sd < -4.5 * s) return 1.0;
	float y0;
	float y1;
	if (u_shape_type == 0) {
		float hy = u_rect_size.y * 0.5 + grow;
		y0 = -hy;
		y1 = hy;
	} else if (u_shape_type == 1) {
		float ry = u_radii.y + grow;
		y0 = -ry;
		y1 = ry;
	} else {
		y0 = u_poly_bounds.y;
		y1 = u_poly_bounds.w;
	}
	float a = max(y0, p.y - 4.5 * s);
	float b = min(y1, p.y + 4.5 * s);
	if (b <= a) return 0.0;
	if (u_shape_type == 2) {
		// Polígonos: filas FIJAS en el espacio de la figura (cada 0,45σ).
		// Sus filas tienen saltos (aristas horizontales); con nodos que se
		// mueven con el píxel aparecían líneas duras en el halo. Con nodos
		// fijos el resultado es continuo (suma de gaussianas suaves).
		float hs = 0.45 * s;
		int k0 = int(floor((a - y0) / hs));
		int k1 = min(int(ceil((b - y0) / hs)), k0 + 24);
		float accp = 0.0;
		for (int k = k0; k < k1; k++) {
			float y = y0 + (float(k) + 0.5) * hs;
			if (y > y1) {
				break;
			}
			float t = (y - p.y) * is;
			accp += exp(-0.5 * t * t) * fx_poly_row(y, p.x, is);
		}
		return clamp(accp * hs * is * 0.39894228, 0.0, 1.0);
	}
	int n = 24;
	float dy = (b - a) / float(n);
	float acc = 0.0;
	for (int k = 0; k < n; k++) {
		float y = a + (float(k) + 0.5) * dy;
		float t = (y - p.y) * is;
		float g = exp(-0.5 * t * t);
		vec2 sp = fx_span(y, grow);
		float row = sp.y > sp.x ? fx_ncdf((sp.y - p.x) * is) - fx_ncdf((sp.x - p.x) * is) : 0.0;
		acc += g * row;
	}
	return clamp(acc * dy * is * 0.39894228, 0.0, 1.0);
}

float fx_cover(vec2 p, float sigma, float grow) {
	return fx_cover_sd(p, sigma, grow, fx_sd(p, grow));
}
