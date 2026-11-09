# =============================================================================
# RUTA: res://script_gdscript/shapes/stroke_textures.gd
# TEXTURAS DE SERIE para rellenar trazos de pincel (VGSE fase 4): se generan
# por código (sin archivos), en mosaico, en escala de grises con alfa.
#   lienzo · papel · rayas · puntos
# =============================================================================
extends RefCounted

const NAMES := ["canvas", "paper", "stripes", "dots"]
const LABELS := {"canvas": "Lienzo", "paper": "Papel", "stripes": "Rayas", "dots": "Puntos"}
const SIZE := 128

static var _cache: Dictionary = {}

static func get_texture(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var v := 1.0
			var a := 1.0
			match name:
				"canvas":
					# trama de tela: hilos horizontales y verticales que se cruzan
					var h := 0.5 + 0.5 * sin(float(y) / SIZE * TAU * 16.0)
					var w := 0.5 + 0.5 * sin(float(x) / SIZE * TAU * 16.0)
					var over := 1.0 if (int(x / 8) + int(y / 8)) % 2 == 0 else 0.0
					v = 0.62 + 0.38 * lerpf(h, w, over)
				"paper":
					var n := _hash(x, y) * 0.5 + _hash(x / 2, y / 2) * 0.3 + _hash(x / 4, y / 4) * 0.2
					v = 0.72 + 0.28 * n
				"stripes":
					# 2 rayas diagonales por tesela (la tesela = 2 grosores de trazo)
					var d := fmod(float(x + y), 64.0)
					a = clampf(1.0 - smoothstep(30.0, 34.0, d) + smoothstep(62.0, 64.0, d), 0.2, 1.0)
				"dots":
					# rejilla de 4×4 puntos por tesela
					var cx := fmod(float(x), 32.0) - 16.0
					var cy := fmod(float(y), 32.0) - 16.0
					a = clampf(1.0 - smoothstep(9.0, 11.0, sqrt(cx * cx + cy * cy)), 0.2, 1.0)
			img.set_pixel(x, y, Color(v, v, v, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[name] = tex
	return tex

static func _hash(x: int, y: int) -> float:
	var h := hash(Vector2i(x % SIZE, y % SIZE))
	return float(h & 0xFFFF) / 65535.0
