# =============================================================================
# RUTA: res://script_gdscript/system/ps_import.gd
# IMPORTADOR de EPS, AI y PDF → objetos editables de Vectopen.
#
#   · .ai moderno (Illustrator CS en adelante) y .pdf: son PDF. Se leen los
#     objetos (también dentro de flujos de objetos /ObjStm), las páginas y su
#     contenido (FlateDecode), incluidos los XObject de formulario (Do).
#   · .eps y .ai antiguos (Illustrator 3-8): PostScript. Se interpreta el
#     subconjunto de dibujo (moveto/lineto/curveto… y los operadores cortos de
#     Illustrator m l c v y h f F s S b B n k K g G Xa XA w J d q Q).
#     También el EPS «DOS binario» (cabecera C5D0D3C6 con vista previa TIFF).
#
# Se conserva: trazados con curvas Bézier REALES, relleno y trazo (RGB, gris
# y CMYK convertidos a RGB), grosor, extremos, discontinuo, regla par-impar,
# transformaciones (cm / concat / translate / scale / rotate) y gsave/grestore.
# No se importa (queda en `warnings`): texto, imágenes, degradados (se usa un
# color plano), recortes. La salida tiene el MISMO formato que svg_import.gd,
# así que SvgImport.build() crea los mismos VectorPath editables.
# =============================================================================
extends RefCounted

const SvgImport = preload("res://script_gdscript/system/svg_import.gd")
const MAX_OPS := 2_000_000     # tope de seguridad contra archivos patológicos

# ── API ──────────────────────────────────────────────────────────────────────
## {size, items, warnings} desde un archivo .eps / .ai / .pdf / .ps.
static func parse_file(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {"size": Vector2(800, 600), "items": [], "warnings": ["No se pudo leer el archivo."]}
	return parse_bytes(bytes)

static func parse_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() >= 4 and bytes[0] == 0xC5 and bytes[1] == 0xD0 and bytes[2] == 0xD3 and bytes[3] == 0xC6:
		var off := bytes.decode_u32(4)
		var ln := bytes.decode_u32(8)
		bytes = bytes.slice(off, off + ln)          # EPS DOS binario: solo la parte PostScript
	var head := bytes.slice(0, mini(1024, bytes.size())).get_string_from_ascii()
	if head.find("%PDF") >= 0:
		return _Pdf.new(bytes).parse()
	return _Ps.new(_Pdf.PsImport_bytes_to_text(bytes)).parse()


# ── Estado gráfico + construcción de trazados (común a PDF y PostScript) ─────
class _Canvas:
	var items: Array = []
	var warnings := {}
	var ctm := Transform2D.IDENTITY
	var fill := Color.BLACK
	var stroke := Color.BLACK
	var width := 1.0
	var cap := 0
	var dash: Variant = null
	var stack: Array = []
	var b = SvgImport._Builder.new()
	var cur := Vector2.ZERO
	var start := Vector2.ZERO
	var flip := Transform2D.IDENTITY     # PS/PDF (y arriba) → Vectopen (y abajo)
	## PostScript tiene UN color actual para rellenar y trazar (PDF tiene dos).
	var single_color := false
	var ops := 0
	## Degradado de relleno activo ({type, angle, stops}, formato de svg_import)
	## o null. Lo pone «setpattern»; cualquier color plano lo quita.
	var grad: Variant = null

	func save() -> void:
		stack.append([ctm, fill, stroke, width, cap, dash, grad])
	func restore() -> void:
		if stack.is_empty():
			return
		var s: Array = stack.pop_back()
		ctm = s[0]; fill = s[1]; stroke = s[2]; width = s[3]; cap = s[4]; dash = s[5]; grad = s[6]
	func concat(m: Transform2D) -> void:
		ctm = ctm * m
	func _t(p: Vector2) -> Vector2:
		return flip * (ctm * p)
	func move_to(p: Vector2) -> void:
		b.move(_t(p)); cur = p; start = p
	func line_to(p: Vector2) -> void:
		b.line(_t(p)); cur = p
	func curve_to(c1: Vector2, c2: Vector2, p: Vector2) -> void:
		b.cubic(_t(c1), _t(c2), _t(p)); cur = p
	func close_path() -> void:
		b.close(); cur = start
	func rect(x: float, y: float, w: float, h: float) -> void:
		move_to(Vector2(x, y)); line_to(Vector2(x + w, y)); line_to(Vector2(x + w, y + h)); line_to(Vector2(x, y + h)); close_path()
	## Arco PostScript (grados, sentido antihorario) como curvas Bézier.
	func arc(c: Vector2, r: float, a0: float, a1: float, ccw := true) -> void:
		if ccw:
			while a1 < a0: a1 += 360.0
		else:
			while a1 > a0: a1 -= 360.0
		var segs := maxi(1, ceili(absf(a1 - a0) / 90.0))
		var step := deg_to_rad((a1 - a0) / segs)
		var a := deg_to_rad(a0)
		var p0 := c + Vector2(cos(a), sin(a)) * r
		if b.anchors.is_empty():
			move_to(p0)
		else:
			line_to(p0)
		for i in segs:
			var k := 4.0 / 3.0 * tan(step / 4.0)
			var p1 := c + Vector2(cos(a), sin(a)) * r
			var a2 := a + step
			var p2 := c + Vector2(cos(a2), sin(a2)) * r
			curve_to(p1 + Vector2(-sin(a), cos(a)) * r * k, p2 - Vector2(-sin(a2), cos(a2)) * r * k, p2)
			a = a2
	func paint(do_fill: bool, do_stroke: bool, evenodd: bool) -> void:
		b.flush(false)
		var subs: Array = b.subs
		b = SvgImport._Builder.new()
		if subs.is_empty() or not (do_fill or do_stroke):
			return
		var k := sqrt(absf((flip * ctm).determinant()))
		var d: Variant = null
		if dash is Array and (dash as Array).size() >= 1:
			var d0 := float(dash[0])
			var d1 := float(dash[1]) if (dash as Array).size() > 1 else d0
			if d0 > 0.0 or d1 > 0.0:   # [0 hueco] = punteado
				d = [d0 * k, d1 * k]
		items.append({"t": "path", "subs": subs,
			"fill": fill if do_fill else null, "stroke": stroke if do_stroke else null,
			"grad": grad if do_fill else null, "dash": d, "width": maxf(width * k, 0.0) if do_stroke else 0.0,
			"cap": cap, "evenodd": evenodd, "opacity": 1.0,
			"name": "Trazado"})
	func discard() -> void:
		b.flush(false)
		b = SvgImport._Builder.new()
	func warn(w: String) -> void:
		warnings[w] = true

static func _cmyk(c: float, m: float, y: float, k: float) -> Color:
	return Color((1.0 - c) * (1.0 - k), (1.0 - m) * (1.0 - k), (1.0 - y) * (1.0 - k))


# ── Tokenizador común (PostScript y flujos de contenido PDF) ─────────────────
## Devuelve tokens: float | String (operador) | {"name": "/x"} | Array (de [ ]) |
## {"str": true} (cadenas) | {"proc": true} ({ … } se salta entero).
static func _tokens(src: String) -> Array:
	var out: Array = []
	# «[» es una MARCA en PostScript, no una lista que haya que cerrar: Affinity
	# y otros usan «[ … pdfmark» sin «]». Se guarda la posición de cada marca en
	# `out` y «]» recoge lo que hay detrás; una marca sin cerrar no atrapa nada.
	var marks: Array[int] = []
	var i := 0
	var n := src.length()
	while i < n:
		var ch := src[i]
		if ch == "%":
			while i < n and src[i] != "\n" and src[i] != "\r":
				i += 1
			continue
		if ch == " " or ch == "\n" or ch == "\r" or ch == "\t" or ch == "\f" or ch == "\u0000":
			i += 1
			continue
		var tok: Variant = null
		if ch == "(":
			var depth := 1
			i += 1
			while i < n and depth > 0:
				var c2 := src[i]
				if c2 == "\\":
					i += 2
					continue
				if c2 == "(": depth += 1
				elif c2 == ")": depth -= 1
				i += 1
			tok = {"str": true}
		elif ch == "<":
			if i + 1 < n and src[i + 1] == "<":
				i += 2
				tok = "<<"
			else:
				var j := src.find(">", i)
				i = (j + 1) if j >= 0 else n
				tok = {"str": true}
		elif ch == ">" and i + 1 < n and src[i + 1] == ">":
			i += 2
			tok = ">>"
		elif ch == "{":
			var depth2 := 1
			i += 1
			while i < n and depth2 > 0:
				if src[i] == "{": depth2 += 1
				elif src[i] == "}": depth2 -= 1
				elif src[i] == "(":
					var d3 := 1
					i += 1
					while i < n and d3 > 0:
						if src[i] == "\\": i += 1
						elif src[i] == "(": d3 += 1
						elif src[i] == ")": d3 -= 1
						i += 1
					continue
				i += 1
			tok = {"proc": true}
		elif ch == "[":
			marks.append(out.size())
			out.append({"mark": true})
			i += 1
			continue
		elif ch == "]":
			i += 1
			if marks.is_empty():
				continue
			var k: int = marks.pop_back()
			tok = out.slice(k + 1)
			out.resize(k)
		else:
			var j2 := i
			while j2 < n:
				var c3 := src[j2]
				if c3 in " \n\r\t\f()<>[]{}/%" and not (j2 == i and c3 == "/"):
					break
				j2 += 1
			var w := src.substr(i, maxi(1, j2 - i))
			var w0 := i
			i = maxi(j2, i + 1)
			if w == "currentfile" or w == "image" or w == "colorimage" or w == "imagemask":
				i = _skip_inline_data(src, w, w0, i)
			if w.begins_with("/"):
				tok = {"name": w}
			elif w.is_valid_float():
				tok = w.to_float()
			else:
				tok = w
		out.append(tok)
	return out

## Degradado de PostScript (ShadingType 2 = lineal, 3 = radial) al formato de
## svg_import: {type, angle, stops}. Las funciones de tipo 3 (varias de tipo 2
## unidas por /Bounds) dan una parada al principio y otra al final de cada tramo.
static func _ps_gradient(cv: _Canvas, sh: Dictionary) -> Variant:
	var c0: Array = sh.get("/C0", [])
	var c1: Array = sh.get("/C1", [])
	if c0.is_empty() or c0.size() != c1.size():
		return null
	var bounds: Array = sh.get("/Bounds", [])
	var n := c0.size()
	var stops: Array = []
	for i in n:
		var a := 0.0 if i == 0 else (float(bounds[i - 1]) if i - 1 < bounds.size() else float(i) / n)
		var b := 1.0 if i == n - 1 else (float(bounds[i]) if i < bounds.size() else float(i + 1) / n)
		stops.append([a, _components_color(c0[i])])
		stops.append([b, _components_color(c1[i])])
	var radial := int(sh.get("/ShadingType", 2.0)) == 3
	var angle := 0.0
	var co: Array = sh.get("/Coords", [])
	if not radial and co.size() >= 4:
		var p0: Vector2 = cv._t(Vector2(co[0], co[1]))
		var p1: Vector2 = cv._t(Vector2(co[2], co[3]))
		angle = atan2(p1.y - p0.y, p1.x - p0.x)
	return {"type": 1 if radial else 0, "angle": angle, "stops": stops}

## Color desde sus componentes: 1 = gris, 3 = RGB, 4 = CMYK.
static func _components_color(v: Array) -> Color:
	match v.size():
		1: return Color(v[0], v[0], v[0])
		3: return Color(v[0], v[1], v[2])
		4: return _cmyk(v[0], v[1], v[2], v[3])
	return Color.BLACK

## Datos incrustados en el propio archivo, que NO son código PostScript y
## desordenarían el resto de tokens (Affinity, Illustrator, Photoshop):
##   · «currentfile 0 (marca) /SubFileDecode filter …» → hasta la marca (XMP).
##   · «… currentfile /ASCII85Decode filter … image» → hasta «~>».
##   · «… currentfile /ASCIIHexDecode filter … image» → hasta «>».
## Devuelve la posición desde la que seguir leyendo.
static func _skip_inline_data(src: String, w: String, start: int, after: int) -> int:
	if w == "currentfile":
		var rx := RegEx.create_from_string("^currentfile\\s+\\d+\\s+\\(([^)]*)\\)\\s*/SubFileDecode\\s+filter")
		var m := rx.search(src.substr(start, 400))
		if m and m.get_string(1) != "":
			var k := src.find(m.get_string(1), start + m.get_end())
			if k >= 0:
				return k + m.get_string(1).length()
		return after
	# image / colorimage / imagemask: ¿lee sus datos de currentfile?
	var from := maxi(0, start - 1500)
	var back := src.substr(from, start - from)
	var cf := back.rfind("currentfile")
	if cf < 0:
		return after
	var tail := back.substr(cf)
	if tail.find("/ASCII85Decode") >= 0:
		var k := src.find("~>", after)
		return (k + 2) if k >= 0 else after
	if tail.find("/ASCIIHexDecode") >= 0:
		var k := src.find(">", after)
		return (k + 1) if k >= 0 else after
	return after

## Ejecuta operadores de dibujo comunes (PDF y abreviaturas de Illustrator).
## Devuelve true si `op` era de dibujo. `st` = pila de operandos.
const _COLOR_OPS := ["rg", "setrgbcolor", "Xa", "g", "setgray", "k", "setcmykcolor", "sc", "scn", "setcolor", "x"]

static func _draw_op(cv: _Canvas, op: String, st: Array) -> bool:
	if op in _COLOR_OPS:
		cv.grad = null
	var f0 := cv.fill
	var s0 := cv.stroke
	var handled := _draw_op_inner(cv, op, st)
	if cv.single_color:
		if cv.fill != f0:
			cv.stroke = cv.fill
		elif cv.stroke != s0:
			cv.fill = cv.stroke
	return handled

static func _draw_op_inner(cv: _Canvas, op: String, st: Array) -> bool:
	match op:
		"m", "moveto":
			if st.size() >= 2: cv.move_to(Vector2(st[-2], st[-1]))
		"l", "L", "lineto":
			if st.size() >= 2: cv.line_to(Vector2(st[-2], st[-1]))
		"c", "C", "curveto":
			if st.size() >= 6: cv.curve_to(Vector2(st[-6], st[-5]), Vector2(st[-4], st[-3]), Vector2(st[-2], st[-1]))
		"v", "V":   # 1.er control = punto actual
			if st.size() >= 4: cv.curve_to(cv.cur, Vector2(st[-4], st[-3]), Vector2(st[-2], st[-1]))
		"y", "Y":   # 2.º control = punto final
			if st.size() >= 4: cv.curve_to(Vector2(st[-4], st[-3]), Vector2(st[-2], st[-1]), Vector2(st[-2], st[-1]))
		"rmoveto":
			if st.size() >= 2: cv.move_to(cv.cur + Vector2(st[-2], st[-1]))
		"rlineto":
			if st.size() >= 2: cv.line_to(cv.cur + Vector2(st[-2], st[-1]))
		"rcurveto":
			if st.size() >= 6:
				var o := cv.cur
				cv.curve_to(o + Vector2(st[-6], st[-5]), o + Vector2(st[-4], st[-3]), o + Vector2(st[-2], st[-1]))
		"h", "H", "closepath":
			cv.close_path()
		"re":
			if st.size() >= 4: cv.rect(st[-4], st[-3], st[-2], st[-1])
		"arc", "arcn":
			if st.size() >= 5: cv.arc(Vector2(st[-5], st[-4]), st[-3], st[-2], st[-1], op == "arc")
		"f", "F", "fill":
			cv.paint(true, false, false)
		"f*", "eofill":
			cv.paint(true, false, true)
		"S", "stroke":
			cv.paint(false, true, false)
		"s":
			cv.close_path(); cv.paint(false, true, false)
		"B":
			cv.paint(true, true, false)
		"B*":
			cv.paint(true, true, true)
		"b":
			cv.close_path(); cv.paint(true, true, false)
		"b*":
			cv.close_path(); cv.paint(true, true, true)
		"n", "N", "newpath":
			cv.discard()
		"W", "W*", "clip", "eoclip":
			cv.warn("recortes")
		"rg", "setrgbcolor", "Xa":
			if st.size() >= 3: cv.fill = Color(st[-3], st[-2], st[-1])
			if op == "setrgbcolor" and st.size() >= 3: cv.stroke = cv.fill
		"RG", "XA":
			if st.size() >= 3: cv.stroke = Color(st[-3], st[-2], st[-1])
		"g", "setgray":
			if st.size() >= 1: cv.fill = Color(st[-1], st[-1], st[-1])
			if op == "setgray" and st.size() >= 1: cv.stroke = cv.fill
		"G":
			if st.size() >= 1: cv.stroke = Color(st[-1], st[-1], st[-1])
		"k", "setcmykcolor":
			if st.size() >= 4: cv.fill = PsImport_cmyk(st)
			if op == "setcmykcolor" and st.size() >= 4: cv.stroke = cv.fill
		"K":
			if st.size() >= 4: cv.stroke = PsImport_cmyk(st)
		"x", "X":
			# Color personalizado de Illustrator: «c m y k (nombre) tinta x»
			# (tinta 0 = color pleno). Solo en archivos de Illustrator, donde
			# x/X no pueden ser otra cosa.
			if not cv.single_color and st.size() >= 5:
				var tn := 1.0 - clampf(st[-1], 0.0, 1.0)
				var col := _cmyk(st[-5] * tn, st[-4] * tn, st[-3] * tn, st[-2] * tn)
				if op == "x": cv.fill = col
				else: cv.stroke = col
			else:
				return false
		"sc", "scn", "setcolor":   # setcolor: PostScript nivel 2 (Affinity)
			if st.size() == 3: cv.fill = Color(st[0], st[1], st[2])
			elif st.size() == 1: cv.fill = Color(st[0], st[0], st[0])
			elif st.size() == 4: cv.fill = PsImport_cmyk(st)
		"SC", "SCN":
			if st.size() == 3: cv.stroke = Color(st[0], st[1], st[2])
			elif st.size() == 1: cv.stroke = Color(st[0], st[0], st[0])
			elif st.size() == 4: cv.stroke = PsImport_cmyk(st)
		"w", "setlinewidth":
			if st.size() >= 1: cv.width = st[-1]
		"J", "setlinecap":
			if st.size() >= 1: cv.cap = clampi(int(st[-1]), 0, 2)
		"d", "setdash":
			if st.size() >= 2 and st[-2] is Array: cv.dash = st[-2] if not (st[-2] as Array).is_empty() else null
		"q", "gsave":
			cv.save()
		"Q", "grestore":
			cv.restore()
		"cm":
			if st.size() >= 6: cv.concat(Transform2D(Vector2(st[-6], st[-5]), Vector2(st[-4], st[-3]), Vector2(st[-2], st[-1])))
		"concat":
			if st.size() >= 1 and st[-1] is Array and (st[-1] as Array).size() == 6:
				var a: Array = st[-1]
				cv.concat(Transform2D(Vector2(a[0], a[1]), Vector2(a[2], a[3]), Vector2(a[4], a[5])))
		"translate":
			if st.size() >= 2: cv.concat(Transform2D(0.0, Vector2(st[-2], st[-1])))
		"scale":
			if st.size() >= 2: cv.concat(Transform2D(Vector2(st[-2], 0), Vector2(0, st[-1]), Vector2.ZERO))
		"rotate":
			if st.size() >= 1: cv.concat(Transform2D(deg_to_rad(st[-1]), Vector2.ZERO))
		"rectfill", "rectstroke":
			if st.size() >= 4:
				cv.discard(); cv.rect(st[-4], st[-3], st[-2], st[-1]); cv.paint(op == "rectfill", op == "rectstroke", false)
		"Tj", "TJ", "'", "\"", "show", "ashow", "widthshow", "awidthshow", "kshow", "xshow", "yshow", "xyshow", "BT":
			cv.warn("texto")
		"sh", "shfill":
			cv.warn("degradados")
		"BI", "image", "colorimage", "imagemask":
			cv.warn("imágenes")
		_:
			return false
	return true

static func PsImport_cmyk(st: Array) -> Color:
	return _cmyk(st[-4], st[-3], st[-2], st[-1])

static func _numbers(st: Array) -> Array:
	var out: Array = []
	for v in st:
		if v is float or v is Array:
			out.append(v)
	return out


# ── PostScript (EPS, AI antiguo) ─────────────────────────────────────────────
class _Ps:
	var src := ""
	func _init(s: String) -> void:
		src = s
	func parse() -> Dictionary:
		var cv := _Canvas.new()
		# PostScript normal: un solo color. Illustrator define operadores
		# distintos para relleno (k, g, Xa) y trazo (K, G, XA).
		cv.single_color = not (src.find("Adobe Illustrator") >= 0 or src.find("Adobe_Illustrator") >= 0 or src.find("%AI") >= 0)
		var bbox := _bbox()
		cv.flip = Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2(-bbox.position.x, bbox.end.y))
		var st: Array = []
		var sh := {}      # degradado («<</PatternType 2 /Shading …>>») que se está leyendo
		var key := ""     # clave del degradado cuyo valor viene a continuación
		var PI = load("res://script_gdscript/system/ps_import.gd")
		var toks := PsImport_tokens(src)
		for t in toks:
			cv.ops += 1
			if cv.ops > MAX_OPS:
				cv.warn("archivo demasiado grande (se importó una parte)")
				break
			key = _shade(t, sh, key)
			if t is float or t is Array:
				st.append(t)
				continue
			if t is String:
				var op: String = t
				if op == "setpattern":
					var g: Variant = PI._ps_gradient(cv, sh)
					if g is Dictionary:
						cv.grad = g
						var stops: Array = g["stops"]
						cv.fill = (stops[0][1] as Color).lerp(stops[-1][1], 0.5)   # si la forma no admite degradado
					st.clear()
					continue
				if PsImport_draw(cv, op, load("res://script_gdscript/system/ps_import.gd")._numbers(st)):
					st.clear()
				elif op in ["def", "bind", "pop", "exch", "dup", "load", "begin", "end", "showpage", "save", "restore", "cleartomark", "setlinejoin", "j", "setmiterlimit", "M", "i", "D", "u", "U", "*u", "*U", "A", "Ln", "Lb", "LB"]:
					st.clear()
				else:
					st.clear()
			else:
				pass   # nombres literales, procedimientos, cadenas: no dibujan
		var size := bbox.size if bbox.size.x > 0 and bbox.size.y > 0 else Vector2(800, 600)
		return {"size": size, "items": cv.items, "warnings": cv.warnings.keys()}
	## Va leyendo el degradado («<</PatternType 2 …>>»): guarda en `sh` los
	## valores de /ShadingType /Coords /C0 /C1 /Bounds. Entra también en las
	## listas, porque las funciones de color van dentro de «/Functions [ … ]».
	## Devuelve la clave que espera su valor ("" si ninguna).
	func _shade(t: Variant, sh: Dictionary, key: String) -> String:
		if t is Dictionary and t.has("name"):
			var nm: String = t["name"]
			if nm == "/PatternType":
				sh.clear()
				sh["/C0"] = []
				sh["/C1"] = []
			return nm if (sh.has("/C0") and nm in ["/ShadingType", "/Coords", "/C0", "/C1", "/Bounds"]) else ""
		if key != "" and (t is float or t is Array):
			if key == "/C0" or key == "/C1":
				(sh[key] as Array).append(t)
			else:
				sh[key] = t
			return ""
		if t is Array and sh.has("/C0"):
			var k := ""
			for x in t:
				k = _shade(x, sh, k)
		return ""

	func _bbox() -> Rect2:
		for key in ["%%HiResBoundingBox:", "%%BoundingBox:"]:
			var i := src.find(key)
			if i >= 0:
				var line := src.substr(i + key.length(), 200).split("\n")[0].strip_edges()
				var p := line.split(" ", false)
				if p.size() >= 4 and p[0].is_valid_float():
					var r := Rect2(Vector2(p[0].to_float(), p[1].to_float()), Vector2(p[2].to_float() - p[0].to_float(), p[3].to_float() - p[1].to_float()))
					if r.size.x > 0 and r.size.y > 0:
						return r
		return Rect2(0, 0, 612, 792)
	static func PsImport_tokens(s: String) -> Array:
		return load("res://script_gdscript/system/ps_import.gd")._tokens(s)
	static func PsImport_draw(cv, op: String, st: Array) -> bool:
		return load("res://script_gdscript/system/ps_import.gd")._draw_op(cv, op, st)


# ── PDF (AI moderno, PDF) ────────────────────────────────────────────────────
class _Pdf:
	var data: PackedByteArray
	var text := ""
	var objs := {}          # id → {"dict": String, "stream": PackedByteArray}
	func _init(b: PackedByteArray) -> void:
		data = b
		text = PsImport_bytes_to_text(b)

	## Texto con UN carácter por byte (para que las posiciones del texto sirvan
	## en los bytes). get_string_from_ascii() se corta en el primer byte 0, y
	## los PDF tienen ceros dentro de los flujos comprimidos.
	static func PsImport_bytes_to_text(b: PackedByteArray) -> String:
		# Solo se recorren los ceros (búsqueda nativa): byte a byte en GDScript
		# un PDF de 20 MB tardaba segundos.
		var c := b.duplicate()
		var i := c.find(0)
		while i >= 0:
			c[i] = 32
			i = c.find(0, i + 1)
		var s := c.get_string_from_ascii()
		if s.length() != c.size():
			# por si la versión de Godot no da 1 carácter por byte (>127)
			for j in c.size():
				if c[j] > 127:
					c[j] = 46
			s = c.get_string_from_ascii()
		return s

	func parse() -> Dictionary:
		_index_objects()
		_index_object_streams()
		var pages := _pages()
		if pages.is_empty():
			return {"size": Vector2(800, 600), "items": [], "warnings": ["No se encontró ninguna página en el archivo."]}
		var page: Dictionary = pages[0]
		var box: Rect2 = page["box"]
		var cv := _Canvas.new()
		cv.flip = Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2(-box.position.x, box.end.y))
		var content := PackedByteArray()
		for cid in page["contents"]:
			content.append_array(_stream(int(cid)))
			content.append(10)
		_run(cv, content.get_string_from_ascii(), page["res"], 0)
		if pages.size() > 1:
			cv.warn("solo se importó la primera página")
		return {"size": box.size, "items": cv.items, "warnings": cv.warnings.keys()}

	func _run(cv, src: String, res: String, depth: int) -> void:
		var st: Array = []
		var lib = load("res://script_gdscript/system/ps_import.gd")
		var last_name := ""
		for t in lib._tokens(src):
			cv.ops += 1
			if cv.ops > MAX_OPS:
				cv.warn("archivo demasiado grande (se importó una parte)")
				return
			if t is float or t is Array:
				st.append(t)
			elif t is Dictionary and t.has("name"):
				last_name = String(t["name"])
			elif t is String:
				var op: String = t
				if op == "Do" and last_name != "" and depth < 8:
					_do_xobject(cv, last_name, res, depth)
				elif op == "BI":
					cv.warn("imágenes")
				else:
					lib._draw_op(cv, op, lib._numbers(st))
				st.clear()
				last_name = ""

	func _do_xobject(cv, name: String, res: String, depth: int) -> void:
		var xdict := _subdict(res, "/XObject")
		var ref := _ref_after(xdict, name)
		if ref < 0 or not objs.has(ref):
			return
		var d: String = objs[ref]["dict"]
		if d.find("/Subtype /Form") < 0 and d.find("/Subtype/Form") < 0:
			cv.warn("imágenes")
			return
		cv.save()
		var m := _array_after(d, "/Matrix")
		if m.size() == 6:
			cv.concat(Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5])))
		var sub_res := _resources_of(d)
		_run(cv, _stream(ref).get_string_from_ascii(), sub_res if sub_res != "" else res, depth + 1)
		cv.restore()

	# — objetos —
	func _index_objects() -> void:
		var re := RegEx.create_from_string("(\\d+)\\s+(\\d+)\\s+obj\\b")
		var pending: Array = []   # [id, dict, inicio del flujo, fin si no hay /Length]
		for m in re.search_all(text):
			var id := int(m.get_string(1))
			var start := m.get_end()
			var end := text.find("endobj", start)
			if end < 0:
				continue
			var body := text.substr(start, end - start)
			var entry := {"dict": body, "stream": PackedByteArray()}
			var si := body.find("stream")
			if si >= 0 and body.substr(maxi(0, si - 3), 3) != "end":
				var dict_txt := body.substr(0, si)
				entry["dict"] = dict_txt
				var abs_start := start + si + 6
				if abs_start < data.size() and data[abs_start] == 13: abs_start += 1
				if abs_start < data.size() and data[abs_start] == 10: abs_start += 1
				var abs_end := text.find("endstream", abs_start)
				pending.append([id, dict_txt, abs_start, abs_end])
			objs[id] = entry
		# /Length puede ser directo («/Length 331») o una referencia
		# («/Length 5 0 R»): se resuelve cuando ya están todos los objetos.
		for p in pending:
			var dict_txt: String = p[1]
			var abs_start: int = p[2]
			var abs_end: int = p[3]
			var length := _int_after(dict_txt, "/Length")
			var lref := _ref_after(dict_txt, "/Length")
			if lref >= 0 and objs.has(lref):
				var lt := String(objs[lref]["dict"]).strip_edges()
				if lt.is_valid_int():
					length = int(lt)
			var stream := PackedByteArray()
			if length > 0 and abs_start + length <= data.size() and (abs_end < 0 or abs_start + length <= abs_end + 2):
				stream = data.slice(abs_start, abs_start + length)
			elif abs_end > abs_start:
				var e2 := abs_end
				while e2 > abs_start and (data[e2 - 1] == 10 or data[e2 - 1] == 13):
					e2 -= 1
				stream = data.slice(abs_start, e2)
			objs[int(p[0])]["stream"] = stream

	func _index_object_streams() -> void:
		for id in objs.keys():
			var d: String = objs[id]["dict"]
			if d.find("/ObjStm") < 0:
				continue
			var raw := _stream(id)
			var s := raw.get_string_from_ascii()
			var n := _int_after(d, "/N")
			var first := _int_after(d, "/First")
			# Índice «id offset id offset…» separado por espacios O saltos de línea.
			var head := s.substr(0, first).replace("\r", " ").replace("\n", " ").replace("\t", " ").split(" ", false)
			for k in n:
				if 2 * k + 1 >= head.size():
					break
				var oid := int(head[2 * k])
				var off := int(head[2 * k + 1])
				var next := (int(head[2 * k + 3]) if 2 * k + 3 < head.size() else s.length() - first)
				if not objs.has(oid):
					objs[oid] = {"dict": s.substr(first + off, next - off), "stream": PackedByteArray()}

	func _stream(id: int) -> PackedByteArray:
		if not objs.has(id):
			return PackedByteArray()
		var e: Dictionary = objs[id]
		var raw: PackedByteArray = e["stream"]
		var d: String = e["dict"]
		if d.find("/FlateDecode") >= 0 or d.find("/Fl ") >= 0 or d.find("/Fl]") >= 0:
			var out := raw.decompress_dynamic(256 * 1024 * 1024, FileAccess.COMPRESSION_DEFLATE)
			return out
		return raw

	func _pages() -> Array:
		var out: Array = []
		var ids := objs.keys()
		ids.sort()
		for id in ids:
			var d: String = objs[id]["dict"]
			if not (d.find("/Type /Page") >= 0 or d.find("/Type/Page") >= 0):
				continue
			if d.find("/Type /Pages") >= 0 or d.find("/Type/Pages") >= 0:
				continue
			var box := _array_after(d, "/CropBox")
			if box.size() != 4:
				box = _array_after(d, "/MediaBox")
			if box.size() != 4:
				box = _inherited_box(d)
			var rect := Rect2(0, 0, 612, 792)
			if box.size() == 4:
				rect = Rect2(Vector2(box[0], box[1]), Vector2(box[2] - box[0], box[3] - box[1]))
			out.append({"box": rect, "contents": _content_refs(d), "res": _resources_of(d)})
		return out

	func _inherited_box(d: String) -> Array:
		var parent := _ref_after(d, "/Parent")
		var guard := 0
		while parent >= 0 and objs.has(parent) and guard < 16:
			var pd: String = objs[parent]["dict"]
			var b := _array_after(pd, "/MediaBox")
			if b.size() == 4:
				return b
			parent = _ref_after(pd, "/Parent")
			guard += 1
		return []

	func _content_refs(d: String) -> Array:
		var i := d.find("/Contents")
		if i < 0:
			return []
		var rest := d.substr(i + 9, 400).strip_edges()
		var re := RegEx.create_from_string("(\\d+)\\s+\\d+\\s+R")
		if rest.begins_with("["):
			var arr := rest.substr(1, rest.find("]") - 1)
			var out: Array = []
			for m in re.search_all(arr):
				out.append(int(m.get_string(1)))
			return out
		var m1 := re.search(rest)
		if m1 == null:
			return []
		var rid := int(m1.get_string(1))
		# /Contents puede apuntar a un ARRAY indirecto de flujos.
		if objs.has(rid) and (objs[rid]["stream"] as PackedByteArray).is_empty() and String(objs[rid]["dict"]).strip_edges().begins_with("["):
			var out2: Array = []
			for m2 in re.search_all(String(objs[rid]["dict"])):
				out2.append(int(m2.get_string(1)))
			return out2
		return [rid]

	func _resources_of(d: String) -> String:
		var i := d.find("/Resources")
		if i < 0:
			return ""
		var rest := d.substr(i + 10).strip_edges()
		if rest.begins_with("<<"):
			return _balanced_dict(rest)
		var r := _ref_after(d, "/Resources")
		return String(objs[r]["dict"]) if objs.has(r) else ""

	func _subdict(res: String, key: String) -> String:
		var i := res.find(key)
		if i < 0:
			return ""
		var rest := res.substr(i + key.length()).strip_edges()
		if rest.begins_with("<<"):
			return _balanced_dict(rest)
		var r := _ref_after(res, key)
		return String(objs[r]["dict"]) if objs.has(r) else ""

	static func _balanced_dict(s: String) -> String:
		var depth := 0
		var i := 0
		while i < s.length() - 1:
			if s.substr(i, 2) == "<<":
				depth += 1; i += 2; continue
			if s.substr(i, 2) == ">>":
				depth -= 1; i += 2
				if depth == 0:
					return s.substr(0, i)
				continue
			i += 1
		return s

	static func _int_after(d: String, key: String) -> int:
		var re := RegEx.create_from_string(key.replace("/", "\\/") + "\\s+(\\d+)(?!\\d|\\s+\\d+\\s+R)")
		var m := re.search(d)
		return int(m.get_string(1)) if m else -1

	static func _ref_after(d: String, key: String) -> int:
		var re := RegEx.create_from_string(key.replace("/", "\\/") + "\\s+(\\d+)\\s+\\d+\\s+R")
		var m := re.search(d)
		return int(m.get_string(1)) if m else -1

	static func _array_after(d: String, key: String) -> Array:
		var i := d.find(key)
		if i < 0:
			return []
		var a := d.find("[", i)
		var b := d.find("]", a)
		if a < 0 or b < 0 or a - i > key.length() + 3:
			return []
		var out: Array = []
		for p in d.substr(a + 1, b - a - 1).split(" ", false):
			if p.is_valid_float():
				out.append(p.to_float())
		return out
