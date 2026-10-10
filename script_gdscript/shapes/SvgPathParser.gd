# =============================================================================
# RUTA: res://script_gdscript/shapes/SvgPathParser.gd
#
# Parser mínimo del SVG que produce el GDExtension vtracer (ver
# rust/vectopen_vectorizer): <path d="M.. C.. Z " fill="#RRGGBB"
# transform="translate(tx,ty)"/>. NO es un parser SVG genérico — solo cubre
# los comandos M/L/C/Z en absoluto que vtracer realmente emite (confirmado
# contra el código fuente de visioncortex::path::spline::to_svg_string y
# contra salida real del extension). No soporta arcos (A), curvas
# cuadráticas (Q/T), comandos relativos reales, ni repetición implícita de
# comando tras el primero.
# =============================================================================
class_name SvgPathParser
extends RefCounted

## Un elemento <path> del documento -> lista de subtrazados listos para
## Curve2D.add_point(anchor, in, out). "translate" es el transform embebido
## por vtracer (las coordenadas del "d" son relativas a él).
static func parse_document(svg_text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tag_re := RegEx.create_from_string("<path\\b[^>]*?/>")
	for m in tag_re.search_all(svg_text):
		var tag: String = m.get_string()
		var d := _extract_attr(tag, "d")
		if d.is_empty():
			continue
		var fill_str := _extract_attr(tag, "fill")
		var fill := Color(fill_str) if fill_str != "" and fill_str != "none" else Color(0, 0, 0, 0)
		out.append({
			"d": d,
			"fill": fill,
			"translate": _extract_translate(tag),
			"subpaths": d_to_subpaths(d),
		})
	return out

## Convierte un atributo "d" en subtrazados independientes (un "M...Z" cada
## uno). Cada subtrazado: {anchors, ins, outs: PackedVector2Array, closed: bool}.
static func d_to_subpaths(d: String) -> Array[Dictionary]:
	var tokens := _tokenize(d)
	var subpaths: Array[Dictionary] = []
	var anchors := PackedVector2Array()
	var ins := PackedVector2Array()
	var outs := PackedVector2Array()

	var i := 0
	var n := tokens.size()
	while i < n:
		var tok: String = tokens[i]
		match tok:
			"M":
				_flush(subpaths, anchors, ins, outs, false)
				anchors = PackedVector2Array()
				ins = PackedVector2Array()
				outs = PackedVector2Array()
				anchors.append(Vector2(float(tokens[i + 1]), float(tokens[i + 2])))
				ins.append(Vector2.ZERO)
				outs.append(Vector2.ZERO)
				i += 3
			"L":
				if anchors.is_empty():
					anchors.append(Vector2.ZERO)
					ins.append(Vector2.ZERO)
					outs.append(Vector2.ZERO)
				anchors.append(Vector2(float(tokens[i + 1]), float(tokens[i + 2])))
				ins.append(Vector2.ZERO)
				outs.append(Vector2.ZERO)
				i += 3
			"C":
				if anchors.is_empty():
					anchors.append(Vector2.ZERO)
					ins.append(Vector2.ZERO)
					outs.append(Vector2.ZERO)
				var c1 := Vector2(float(tokens[i + 1]), float(tokens[i + 2]))
				var c2 := Vector2(float(tokens[i + 3]), float(tokens[i + 4]))
				var end := Vector2(float(tokens[i + 5]), float(tokens[i + 6]))
				var last := anchors.size() - 1
				outs[last] = c1 - anchors[last]
				anchors.append(end)
				ins.append(c2 - end)
				outs.append(Vector2.ZERO)
				i += 7
			"Z":
				_flush(subpaths, anchors, ins, outs, true)
				anchors = PackedVector2Array()
				ins = PackedVector2Array()
				outs = PackedVector2Array()
				i += 1
			_:
				# Token numérico sin comando reconocido delante: se descarta
				# en vez de colgar el parser con un índice fuera de rango.
				i += 1

	_flush(subpaths, anchors, ins, outs, false)
	return subpaths

static func _flush(subpaths: Array[Dictionary], anchors: PackedVector2Array, ins: PackedVector2Array, outs: PackedVector2Array, closed: bool) -> void:
	if anchors.size() < 2:
		return
	subpaths.append({"anchors": anchors, "ins": ins, "outs": outs, "closed": closed})

static func _tokenize(d: String) -> Array[String]:
	var re := RegEx.create_from_string("[MLCZmlcz]|-?\\d+\\.?\\d*(?:[eE][-+]?\\d+)?")
	var out: Array[String] = []
	for m in re.search_all(d):
		out.append(m.get_string().to_upper())
	return out

static func _extract_attr(tag: String, attr_name: String) -> String:
	var re := RegEx.create_from_string(attr_name + "=\"([^\"]*)\"")
	var m := re.search(tag)
	return m.get_string(1) if m else ""

static func _extract_translate(tag: String) -> Vector2:
	var re := RegEx.create_from_string("translate\\(([^,]+),([^)]+)\\)")
	var m := re.search(tag)
	if not m:
		return Vector2.ZERO
	return Vector2(float(m.get_string(1)), float(m.get_string(2)))
