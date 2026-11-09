// Trazo de pincel (brush_stroke_render.gd): textura del estilo, degradado 2D
// opcional y ANTIALIAS DEL BORDE. UV.y va de 0 a 1 a lo ancho del trazo (en
// uniones y remates, 0,5 en el centro y 1 en el borde): el borde se funde en
// ~1 px de pantalla a cualquier zoom, sin geometría extra. Sin esto el borde
// salía en escalera (el MSAA 2D, si está, solo da 2 niveles).
shader_type canvas_item;

uniform bool use_grad = false;
uniform sampler2D grad_tex : filter_linear, repeat_disable;
uniform vec2 p0 = vec2(0.0);
uniform vec2 p1 = vec2(100.0, 0.0);
uniform int gtype = 0;   // 0 lineal, 1 radial
// Estilo del pincel, todo procedural (sin imágenes, nítido a cualquier zoom):
// 0 pluma, 1 lápiz (grano de papel), 2 rotulador (bordes de tinta),
// 3 aerógrafo (caída suave). El caligráfico es geometría (anchura por
// ángulo de la plumilla), no sombreador.
uniform int style = 0;
// Lápiz: dureza (ver PENCIL_GRADES en brush_stroke_render.gd).
uniform float pencil_dark = 0.64;
uniform float pencil_fill = 0.40;
uniform float pencil_soft = 0.10;
// Textura dentro del trazo (VGSE fase 4): «a lo largo» (sigue el trazo) o
// «papel» (fija al lienzo); escala e intensidad.
uniform bool use_tex = false;
uniform sampler2D stroke_tex : repeat_enable, filter_linear_mipmap;
uniform float tex_mode = 0.0;      // 0 a lo largo · 1 papel
uniform float tex_scale = 1.0;
uniform float tex_strength = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

varying vec2 local_pos;
varying vec2 paper_pos;

void vertex() {
	local_pos = VERTEX;   // espacio local del trazo (el de p0 / p1)
	// Espacio del LIENZO: el grano del papel es el mismo para todos los
	// trazos (al cruzarlos, el grafito se queda en los mismos «dientes»).
	paper_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return s / 0.9375;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	if (use_grad) {
		vec2 ab = p1 - p0;
		float t;
		if (gtype == 1) {
			t = length(local_pos - p0) / max(length(ab), 1e-4);
		} else {
			t = dot(local_pos - p0, ab) / max(dot(ab, ab), 1e-8);
		}
		c *= texture(grad_tex, vec2(clamp(t, 0.0, 1.0), 0.5));
	}
	if (use_tex) {
		vec2 tuv = tex_mode < 0.5 ? vec2(UV.x / max(tex_scale, 0.01), UV.y) : paper_pos * (0.02 / max(tex_scale, 0.01));
		vec4 t = texture(stroke_tex, tuv);
		c.rgb = mix(c.rgb, c.rgb * t.rgb, tex_strength);
		c.a *= mix(1.0, t.a, tex_strength);
	}
	// 1 en el eje, 0 en el borde. Cobertura del píxel centrada en el borde
	// real (+0,5): el trazo no adelgaza medio píxel por lado.
	float e = 1.0 - abs(2.0 * UV.y - 1.0);
	float w = max(fwidth(e), 1e-6);
	if (style == 1) {
		// Lápiz de grafito sobre papel con «dientes»:
		//  · relieve del papel (fbm) + motas finas, en espacio del lienzo
		//    (el mismo grano para todos los trazos);
		//  · la mina deja grafito en los picos; con más presión y minas
		//    blandas baja a los valles (parte en los valles en las B);
		//  · tono variable según la profundidad del diente (no un relleno
		//    plano) y vetas finas a lo largo del trazo (UV.x = longitud).
		// Lápiz como el de Krita: trazo casi SÓLIDO, poco grano y borde fino
		// suavizado. La presión da grosor (geometría) y oscuridad (aquí).
		// Todo depende SOLO de la posición en el papel y de la presión (no
		// de la pieza de malla): ver OVERWRITE más abajo.
		float pr = clamp(COLOR.a, 0.0, 1.0);
		// Escala del grano según el zoom: con mucho zoom el grano del lienzo
		// se agrandaba en manchas cuadradas; se pasa a octavas más finas para
		// que mida siempre unos px de pantalla (fundido entre dos escalas,
		// sin saltos al hacer zoom).
		float upx = max(fwidth(paper_pos.x), 1e-6);           // unidades por px
		float lvl = max(0.0, log2(1.0 / (0.9 * upx * 6.0)));
		float l0 = floor(lvl);
		float fr = lvl - l0;
		vec2 pp0 = paper_pos * exp2(l0);
		vec2 pp1 = paper_pos * exp2(l0 + 1.0);
		float paper = mix(fbm(pp0 * 0.9), fbm(pp1 * 0.9 + vec2(13.0, 3.0)), fr);
		float fiber = mix(vnoise(vec2(pp0.x * 0.15 + pp0.y * 0.05, pp0.y * 1.6)),
			vnoise(vec2(pp1.x * 0.15 + pp1.y * 0.05, pp1.y * 1.6)), fr);
		float grain = paper * 0.8 + fiber * 0.2;
		float dens = pencil_dark * mix(0.3, 1.0, pow(pr, 1.1)) * 1.25;
		// Diente del papel visible: rozando se ve bastante papel, apretando
		// menos (sin llegar a liso, que parecía plástico).
		float tooth = smoothstep(0.25, 0.75, grain);
		float speck = mix(vnoise(pp0 * 2.6), vnoise(pp1 * 2.6), fr);
		float tex = tooth * 0.8 + speck * 0.2;
		c.a = clamp(dens * mix(mix(0.35, 0.75, pr), 1.0, tex), 0.0, 1.0);
		// Borde: suavizado de ~1,5 px de pantalla con un poco de diente.
		e += (grain - 0.5) * w * 1.2;
		w *= 1.5;
	} else if (style == 2) {
		// Rotulador: la tinta se acumula en los bordes (más oscuro). Con el
		// color y no con la transparencia: así donde el trazo se pisa a sí
		// mismo (vueltas) no salen manchas; la opacidad la pone el grupo.
		c.rgb *= 1.0 - 0.22 * pow(1.0 - clamp(e, 0.0, 1.0), 3.0);
	} else if (style == 3) {
		// Aerógrafo: caída gaussiana a lo ancho con un poco de pulverizado.
		// Pulverizado por píxel de pantalla (antes en cuadros del lienzo, que
		// con mucho zoom se veían como un damero).
		c.a *= exp(-3.6 * (1.0 - e) * (1.0 - e)) * (0.9 + 0.1 * hash(floor(FRAGCOORD.xy)));
	}
	c.a *= clamp(e / w + 0.5, 0.0, 1.0);
#ifdef OVERWRITE
	// Se escribe sin mezclar dentro del grupo: color PREMULTIPLICADO (el
	// grupo lo compone así; sin premultiplicar, lo tenue salía más oscuro).
	c.rgb *= c.a;
#endif
	COLOR = c;
}
