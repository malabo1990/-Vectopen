// =============================================================================
// EFECTO "3D" (como Affinity "3D" / Photoshop "Bisel y relieve"):
// la figura es un RELIEVE (mapa de alturas) iluminado con Blinn-Phong.
//   · altura h ∈ [0,1] según el PERFIL:
//       0 Suave      — gaussiano de la figura (Affinity / GIMP "Bump")
//       1 Cincel     — distancia al borde lineal (Photoshop "Cincel duro")
//       2 Redondeado — cuarto de círculo sobre la distancia ("Suave" de PS)
//   · normal N = normalize(−profundidad·∇h, 1) (hundido: −profundidad);
//   · luz: acimut / elevación (ya pasada al espacio local de la figura);
//   · difuso normalizado (zona plana = sin cambio), ambiente, especular con
//     brillo; composición de Photoshop: SOMBRAS en multiplicar y LUCES en
//     trama (dos pasadas: FX_SCREEN definido o no).
// =============================================================================

uniform vec3 u_light_dir = vec3(0.5, -0.5, 0.707);   // hacia la luz (local, y abajo)
uniform vec4 u_light_color : source_color = vec4(1.0);
uniform float u_relief = 12.0;        // profundidad (unidades locales); < 0 hundido
uniform float u_diffuse = 1.0;        // 0..1
uniform float u_specular = 0.47;      // 0..1
uniform float u_shininess = 0.6;      // 0..1
uniform vec4 u_specular_color : source_color = vec4(1.0);
uniform float u_ambient = 0.0;        // 0..1
uniform vec4 u_ambient_color : source_color = vec4(1.0);
uniform float u_fx_opacity = 1.0;
uniform int u_profile = 0;          // 0 gaussiano, 1 lineal, 2 círculo, 3 seno
uniform int u_mode = 0;             // 0 = 3D (Affinity), 1 = bisel y relieve
uniform int u_style = 0;            // bisel: 0 interior, 1 exterior, 2 relieve, 3 almohadilla
uniform float u_size = 20.0;        // radio / tamaño (unidades locales)
uniform float u_soften = 0.0;
uniform float u_hi_opacity = 1.0;   // bisel: opacidad de la luz
uniform float u_sh_opacity = 1.0;   // bisel: opacidad de la sombra

// Perfil aplicado a t (0 borde → 1 dentro): altura y su derivada dh/dt.
vec2 fx_profile(float t) {
	t = clamp(t, 0.0, 1.0);
	if (u_profile == 2) {
		float u = 1.0 - t;
		float r = sqrt(max(1.0 - u * u, 0.0));
		return vec2(r, u / max(r, 0.08));
	}
	if (u_profile == 3) {
		return vec2(sin(t * 1.5707963), 1.5707963 * cos(t * 1.5707963));
	}
	return vec2(t, 1.0);
}

// t (0..1) del estilo de bisel / 3D a partir de la distancia con signo d
// (< 0 dentro) y del tamaño.
float fx_style_t(float d) {
	float sz = max(u_size, 0.001);
	int st = u_mode == 1 ? u_style : 0;
	if (st == 1) return clamp(1.0 - d / sz, 0.0, 1.0);             // exterior
	if (st == 2) return clamp(0.5 - d / (2.0 * sz), 0.0, 1.0);     // relieve
	if (st == 3) return clamp(abs(d) / sz, 0.0, 1.0);              // almohadilla
	return clamp(-d / sz, 0.0, 1.0);                                // interior
}

// Máscara de la zona donde actúa el estilo (antes del suavizado de borde).
float fx_style_mask(float d, float pxl) {
	float inside = 1.0 - smoothstep(-pxl, pxl, d);
	int st = u_mode == 1 ? u_style : 0;
	if (st == 1) return 1.0 - inside;
	if (st >= 2) return 1.0;
	return inside;
}

// Bisel y relieve (Photoshop): luz en trama y sombra en multiplicar según
// cuánto se acerca / aleja la normal de la luz respecto a la zona plana.
void fx_bevel_eval(vec3 N, out vec3 m, out vec4 s) {
	vec3 L = normalize(u_light_dir);
	float lz = max(L.z, 0.02);
	float ndl = dot(N, L);
	float sh = clamp((lz - ndl) / lz, 0.0, 1.0) * u_sh_opacity;
	float hi = clamp((ndl - lz) / max(1.0 - lz, 0.02), 0.0, 1.0) * u_hi_opacity;
	m = mix(vec3(1.0), u_ambient_color.rgb, sh);
	s = vec4(u_light_color.rgb, hi);
}

// Sombra (multiplicar, rgb) y luz (trama: rgb + cantidad) para la normal N.
// Devuelve: mul en .rgb de `m`, color de luz en .rgb de `s` y cantidad en s.a
void fx_light_eval(vec3 N, out vec3 m, out vec4 s) {
	vec3 L = normalize(u_light_dir);
	float lz = max(L.z, 0.05);
	float ndl = max(dot(N, L), 0.0);
	// difuso relativo a la zona plana (N = z → sin cambio): hacia la luz
	// aclara hasta el color de la luz (plena cara a la luz), en contra oscurece
	float shade = mix(1.0, clamp(ndl / lz, 0.0, 1.0), u_diffuse);
	float hi = clamp((ndl - lz) / max(1.0 - lz, 0.05), 0.0, 1.0) * 0.85 * u_diffuse;
	// ambiente: rellena las sombras con su color
	// ambiente: luz que llega a todo por igual → rellena las sombras (100 %
	// = sin sombras) con su color
	m = mix(vec3(shade), u_ambient_color.rgb, u_ambient);
	// especular (Blinn-Phong); se resta el de la zona plana
	vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
	// exponente del brillo calibrado con Affinity (97 % sigue siendo un reflejo
	// amplio y suave, no un punto)
	float e = mix(1.5, 48.0, u_shininess * u_shininess);
	float sp0 = pow(max(H.z, 0.0), e);
	float sp = max(pow(max(dot(N, H), 0.0), e) - sp0, 0.0) / max(1.0 - sp0, 0.001);
	float spec = sp * u_specular;
	float amount = clamp(hi + spec, 0.0, 1.0);
	vec3 col = (hi * u_light_color.rgb + spec * u_specular_color.rgb * u_light_color.rgb) / max(hi + spec, 0.0001);
	s = vec4(col, amount);
}
