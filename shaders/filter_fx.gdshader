// =============================================================================
// FILTROS (pestaña "Filtros" del panel Efectos) — UN pase por objeto.
// Se aplica como material de un canvas group que contiene el render real del
// objeto (figura, texto, imagen…): `st` es ese render (premultiplicado).
// Todo se ancla en coordenadas LOCALES del objeto (u_s2l / u_l2s), así el
// grano, el pixelado o el semitono no "nadan" al mover / hacer zoom.
// Orden fijo: glitch → pixelado → (semitono | aberración cromática) →
//             duotono → grano → neón (brillo por debajo).
// =============================================================================
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D st : hint_screen_texture, filter_linear_mipmap, repeat_disable;

#include "res://shaders/fx_gauss_tex.gdshaderinc"

// pantalla (px del render) <-> local del objeto
uniform vec2 u_l2s_x = vec2(1.0, 0.0);
uniform vec2 u_l2s_y = vec2(0.0, 1.0);
uniform vec2 u_l2s_o = vec2(0.0);
uniform vec2 u_s2l_x = vec2(1.0, 0.0);
uniform vec2 u_s2l_y = vec2(0.0, 1.0);
uniform vec2 u_s2l_o = vec2(0.0);
uniform float u_zoom = 1.0;

uniform bool u_gl_on = false;
uniform float u_gl_amount = 0.35;
uniform float u_gl_shift = 12.0;
uniform float u_gl_band = 6.0;
uniform float u_gl_seed = 1.0;

uniform bool u_px_on = false;
uniform float u_px_size = 8.0;

uniform bool u_ca_on = false;
uniform float u_ca_amount = 3.0;
uniform float u_ca_angle = 0.0;

uniform bool u_ht_on = false;
uniform float u_ht_cell = 8.0;
uniform float u_ht_angle = 0.785398;
uniform float u_ht_scale = 1.0;

uniform bool u_duo_on = false;
uniform vec4 u_duo_dark : source_color = vec4(0.10, 0.05, 0.35, 1.0);
uniform vec4 u_duo_light : source_color = vec4(1.0, 0.55, 0.35, 1.0);
uniform float u_duo_mix = 1.0;

uniform bool u_gr_on = false;
uniform float u_gr_amount = 0.25;
uniform float u_gr_size = 1.0;
uniform bool u_gr_mono = true;

uniform bool u_neon_on = false;
uniform vec4 u_neon_color : source_color = vec4(0.2, 1.0, 0.9, 1.0);
uniform float u_neon_radius = 10.0;
uniform float u_neon_intensity = 1.2;
uniform float u_neon_tint = 0.6;

vec2 to_local(vec2 sp) { return u_s2l_x * sp.x + u_s2l_y * sp.y + u_s2l_o; }
vec2 to_screen(vec2 lp) { return u_l2s_x * lp.x + u_l2s_y * lp.y + u_l2s_o; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 rot(vec2 v, float a) { float c = cos(a); float s = sin(a); return vec2(c * v.x - s * v.y, s * v.x + c * v.y); }

vec4 fetch(vec2 lp, vec2 px) { return textureLod(st, to_screen(lp) * px, 0.0); }

vec3 unpremul(vec4 c) { return c.a > 0.0001 ? c.rgb / c.a : vec3(0.0); }

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 sp = SCREEN_UV / px;
	vec2 lp = to_local(sp);
	vec2 slp = lp;

	// ── Glitch: franjas horizontales (en local) desplazadas al azar ─────────
	float split = 0.0;
	if (u_gl_on) {
		float band = floor(lp.y / max(u_gl_band, 0.5));
		float h = hash(vec2(band, u_gl_seed));
		if (h < u_gl_amount) {
			float h2 = hash(vec2(band * 1.7 + 3.0, u_gl_seed * 2.3 + 1.0));
			slp.x += (h2 - 0.5) * 2.0 * u_gl_shift;
			split = u_gl_shift * 0.2;
		}
	}
	// ── Pixelado (bloques en unidades del lienzo) ───────────────────────────
	if (u_px_on) {
		float s = max(u_px_size, 0.5);
		slp = (floor(slp / s) + 0.5) * s;
	}

	vec4 c;
	if (u_ht_on) {
		// ── Semitono: puntos en una rejilla girada; tamaño ∝ oscuridad ──────
		// Se evalúan las 4 celdas más cercanas: así los puntos grandes se
		// solapan en círculos en vez de cortarse en rombos por su celda.
		float cell = max(u_ht_cell, 1.0);
		vec2 q = rot(slp, -u_ht_angle) / cell;
		vec2 b0 = floor(q - 0.5);
		float aa = 1.0 / max(cell * u_zoom, 1.0);
		c = vec4(0.0);
		for (int k = 0; k < 4; k++) {
			vec2 cid = b0 + vec2(float(k & 1), float(k >> 1)) + 0.5;
			vec4 cc = fetch(rot(cid * cell, u_ht_angle), px);
			if (cc.a < 0.002) {
				continue;
			}
			vec3 rgb = unpremul(cc);
			float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
			float dark = clamp((1.0 - lum) * 0.85 + 0.15, 0.0, 1.0);
			float r = min(sqrt(dark) * 0.62 * u_ht_scale, 0.95);
			float cov = (1.0 - smoothstep(r - aa, r + aa, length(q - cid))) * cc.a;
			if (cov > c.a) {
				c = vec4(rgb, 1.0) * cov;
			}
		}
	} else {
		float ca = (u_ca_on ? u_ca_amount : 0.0) + split;
		if (ca > 0.0) {
			// ── Aberración cromática: R y B desplazados en sentidos opuestos ─
			vec2 d = vec2(cos(u_ca_angle), sin(u_ca_angle)) * ca;
			vec4 r = fetch(slp + d, px);
			vec4 g = fetch(slp, px);
			vec4 b = fetch(slp - d, px);
			// Cada canal lleva su propia cobertura: donde un canal "falta"
			// se ilumina (como sobre papel claro) → franjas de color también
			// en tinta negra, en vez de copias negras desplazadas.
			float a = max(max(r.a, g.a), b.a);
			c = vec4(r.r + (a - r.a), g.g + (a - g.a), b.b + (a - b.a), a);
		} else {
			c = fetch(slp, px);
		}
	}

	// ── Duotono: luminancia → degradado sombra/luz ──────────────────────────
	if (u_duo_on && c.a > 0.0001) {
		vec3 rgb = c.rgb / c.a;
		float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
		vec3 duo = mix(u_duo_dark.rgb, u_duo_light.rgb, smoothstep(0.0, 1.0, lum));
		c.rgb = mix(rgb, duo, u_duo_mix) * c.a;
	}
	// ── Grano (ruido fijo, anclado al objeto) ───────────────────────────────
	if (u_gr_on && c.a > 0.0001) {
		vec2 cell = floor(lp / max(u_gr_size, 0.25));
		vec3 n;
		if (u_gr_mono) {
			n = vec3(hash(cell) - 0.5);
		} else {
			n = vec3(hash(cell), hash(cell + 17.3), hash(cell + 41.7)) - 0.5;
		}
		c.rgb = clamp(c.rgb + n * u_gr_amount * 2.0 * c.a, vec3(0.0), vec3(c.a));
	}
	// ── Neón: color emisivo + halo (alfa desenfocado con mipmaps) ───────────
	if (u_neon_on) {
		// halo = alfa con desenfoque gaussiano real (σ = radio / 2)
		float rs = max(u_neon_radius * u_zoom, 1.0);
		float g = clamp(fx_gauss_tex(st, SCREEN_UV, px, rs * 0.5).a * 1.6, 0.0, 1.0);
		if (c.a > 0.0001) {
			vec3 rgb = c.rgb / c.a;
			vec3 hot = mix(u_neon_color.rgb, vec3(1.0), 0.35);
			rgb = mix(rgb, hot, u_neon_tint);
			c.rgb = rgb * c.a;
		}
		float halo = clamp(g * u_neon_intensity, 0.0, 1.0) * u_neon_color.a;
		c = c + vec4(u_neon_color.rgb, 1.0) * halo * (1.0 - c.a);
	}

	COLOR = c.a > 0.0001 ? vec4(c.rgb / c.a, c.a) : vec4(0.0);
}
