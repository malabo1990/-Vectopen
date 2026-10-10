// =============================================================================
// DESENFOQUE GAUSSIANO 2D DE UNA TEXTURA CON MIPMAPS (canvas groups de los
// efectos de texto, filtros neón / cristal). Rejilla de 9×9 muestras con
// pesos gaussianos sobre el nivel de mip en el que σ ≈ 1,5 texels: la
// separación entre muestras (0,75σ) es ~1 texel → resultado continuo, sin
// las "copias" / anillos sólidos de las 12–32 muestras en espiral o anillo
// de antes. Cubre ±3σ.
// =============================================================================

vec4 fx_gauss_tex(sampler2D tex, vec2 uv, vec2 px, float sigma_px) {
	if (sigma_px < 0.3) {
		return textureLod(tex, uv, 0.0);
	}
	float lod = max(0.0, log2(sigma_px / 1.5));
	vec2 step_uv = px * (0.75 * sigma_px);  // 0,75σ entre muestras
	vec4 acc = vec4(0.0);
	float wsum = 0.0;
	for (int j = -4; j <= 4; j++) {
		for (int i = -4; i <= 4; i++) {
			vec2 o = vec2(float(i), float(j));
			float w = exp(-0.28125 * dot(o, o));   // exp(-½·(0,75·|o|)²)
			acc += textureLod(tex, uv + o * step_uv, lod) * w;
			wsum += w;
		}
	}
	return acc / wsum;
}

// Alfa desenfocado (gaussiano σ px) y su GRADIENTE (por px) en una sola
// pasada: pesos de la derivada de la gaussiana. Devuelve (A, dA/dx, dA/dy).
vec3 fx_gauss_tex_grad(sampler2D tex, vec2 uv, vec2 px, float sigma_px) {
	float sg = max(sigma_px, 0.5);
	float lod = max(0.0, log2(sg / 1.5));
	// (nombres con prefijo: este archivo se incluye en shaders con sus
	// propias uniformes, p.ej. `st` en filter_fx)
	float fxg_step = 0.75 * sg;              // px entre muestras
	vec2 step_uv = px * fxg_step;
	float acc = 0.0;
	vec2 gacc = vec2(0.0);
	float wsum = 0.0;
	for (int j = -4; j <= 4; j++) {
		for (int i = -4; i <= 4; i++) {
			vec2 o = vec2(float(i), float(j));
			float w = exp(-0.28125 * dot(o, o));
			float a = textureLod(tex, uv + o * step_uv, lod).a;
			acc += a * w;
			gacc += a * w * (o * fxg_step) / (sg * sg);
			wsum += w;
		}
	}
	return vec3(acc, gacc) / wsum;
}
