# =============================================================================
# RUTA: res://script_gdscript/system/svg_import.gd
# IMPORTADOR SVG completo (archivos de Figma, Illustrator, Inkscape, la web
# y los que exporta Vectopen) → objetos editables de Vectopen.
#
#   · <path> con TODA la gramática: M L H V C S Q T A Z, absolutos y
#     relativos, repeticiones implícitas; los arcos se pasan a Bézier.
#   · <rect rx ry> <circle> <ellipse> <line> <polyline> <polygon>
#   · <g> anidados con transform (matrix, translate, scale, rotate, skewX/Y),
#     viewBox, opacity heredada.
#   · Estilo por atributos y por style="…": fill, stroke, stroke-width,
#     opacity, fill-opacity, stroke-opacity, fill-rule, stroke-linecap,
#     display/visibility. Colores #rgb #rrggbb #rrggbbaa rgb() rgba() y
#     nombres. Degradados: color del primer stop.
#   · <text>/<tspan> → texto de Vectopen; <image> con data URI → imagen.
#
# Cada figura es un VectorPath (Bézier reales; agujeros con subpaths par-
# impar). parse() no toca la escena: devuelve una lista de "objetos" que
# build() convierte en nodos.
# =============================================================================
extends RefCounted

const K := 0.5522847498
const NAMED := {"black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#008000",
	"blue": "#0000ff", "yellow": "#ffff00", "cyan": "#00ffff", "magenta": "#ff00ff", "gray": "#808080",
	"grey": "#808080", "orange": "#ffa500", "purple": "#800080", "pink": "#ffc0cb", "brown": "#a52a2a",
	"silver": "#c0c0c0", "navy": "#000080", "teal": "#008080", "lime": "#00ff00", "maroon": "#800000",
	"olive": "#808000", "aqua": "#00ffff", "fuchsia": "#ff00ff", "transparent": "#00000000"}

## {size: Vector2, items: [...]} — items: {t:"path", subs:[{anchors,ins,outs,closed}],
## fill, stroke, width, cap, evenodd, opacity, name, grad, dash} | {t:"text"…} | {t:"image"…}
## El documento se lee primero como ÁRBOL: <use>, <style> y los degradados
## pueden apuntar a elementos de cualquier parte del archivo.
static func parse(svg_text: String) -> Dictionary:
	var out := {"size": Vector2(800, 600), "items": []}
	var dom := _dom(svg_text)
	if dom.is_empty():
		return out
	var ctx := {"ids": {}, "css": [], "grads": {}}
	_index(dom, ctx)
	_resolve_gradients(ctx)
	var root_attrs: Dictionary = dom["attrs"]
	var vb := String(root_attrs.get("viewBox", "")).replace(",", " ").split(" ", false)
	var w := _len(root_attrs.get("width", ""), 0.0)
	var h := _len(root_attrs.get("height", ""), 0.0)
	var xf := Transform2D.IDENTITY
	if vb.size() == 4:
		var vbr := Rect2(float(vb[0]), float(vb[1]), float(vb[2]), float(vb[3]))
		if w <= 0.0: w = vbr.size.x
		if h <= 0.0: h = vbr.size.y
		xf = Transform2D(0.0, Vector2(w / maxf(vbr.size.x, 0.001), h / maxf(vbr.size.y, 0.001)), 0.0, Vector2.ZERO) * Transform2D(0.0, -vbr.position)
	out["size"] = Vector2(w if w > 0 else 800.0, h if h > 0 else 600.0)
	var style := _merge_style({"fill": "#000000"}, root_attrs, _css_for(dom, ctx))
	for c in dom["children"]:
		_walk(c, xf, style, 1.0, ctx, out, 0)
	return out

# ── árbol XML ────────────────────────────────────────────────────────────────
static func _dom(svg_text: String) -> Dictionary:
	var xp := XMLParser.new()
	if xp.open_buffer(svg_text.to_utf8_buffer()) != OK:
		return {}
	var root := {}
	var stack: Array = []
	while xp.read() == OK:
		match xp.get_node_type():
			XMLParser.NODE_ELEMENT:
				var a := {}
				for i in xp.get_attribute_count():
					a[xp.get_attribute_name(i)] = xp.get_attribute_value(i)
				var n := {"tag": xp.get_node_name(), "attrs": a, "children": [], "text": ""}
				if stack.is_empty():
					if n["tag"] != "svg":
						continue
					root = n
				else:
					stack.back()["children"].append(n)
				if not xp.is_empty():
					stack.append(n)
			XMLParser.NODE_ELEMENT_END:
				if not stack.is_empty():
					stack.pop_back()
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				if not stack.is_empty():
					var cur: Dictionary = stack.back()
					cur["text"] = String(cur["text"]) + xp.get_node_data()
					# el texto también cuenta como hijo, en orden (texto y tspans mezclados)
					cur["children"].append({"tag": "#text", "attrs": {}, "children": [], "text": xp.get_node_data()})
	return root

## ids, reglas CSS de <style> y degradados.
static func _index(n: Dictionary, ctx: Dictionary) -> void:
	var a: Dictionary = n["attrs"]
	if a.has("id"):
		ctx["ids"][String(a["id"])] = n
	if n["tag"] == "style":
		ctx["css"].append_array(_parse_css(String(n["text"])))
	if n["tag"] in ["linearGradient", "radialGradient"] and a.has("id"):
		var stops: Array = []
		for c in n["children"]:
			if c["tag"] == "stop":
				var st := _merge_style({}, c["attrs"], [])
				var off := String(c["attrs"].get("offset", "0"))
				var o := float(off.trim_suffix("%")) / (100.0 if off.ends_with("%") else 1.0)
				stops.append([clampf(o, 0, 1), _color(String(st.get("stop-color", "#000000")), float(st.get("stop-opacity", "1")))])
		ctx["grads"][String(a["id"])] = {"type": "radial" if n["tag"] == "radialGradient" else "linear",
			"stops": stops, "attrs": a, "href": String(a.get("href", a.get("xlink:href", ""))).trim_prefix("#")}
	for c in n["children"]:
		_index(c, ctx)

## Degradados que heredan las paradas de otro (href).
static func _resolve_gradients(ctx: Dictionary) -> void:
	for id in ctx["grads"]:
		var g: Dictionary = ctx["grads"][id]
		var guard := 0
		var ref := String(g["href"])
		while (g["stops"] as Array).is_empty() and ref != "" and ctx["grads"].has(ref) and guard < 8:
			g["stops"] = ctx["grads"][ref]["stops"]
			ref = String(ctx["grads"][ref]["href"])
			guard += 1

## CSS de <style>: selectores simples (tag, .clase, #id, tag.clase, *),
## varios separados por comas. Los compuestos (descendientes, :hover…) se ignoran.
static func _parse_css(css: String) -> Array:
	var rules: Array = []
	var re_c := RegEx.new()
	re_c.compile("/\\*[\\s\\S]*?\\*/")
	css = re_c.sub(css, "", true)
	var re := RegEx.new()
	re.compile("([^{}]+)\\{([^}]*)\\}")
	for m in re.search_all(css):
		var decls := {}
		for d in m.get_string(2).split(";", false):
			var kv := d.split(":", false, 1)
			if kv.size() == 2:
				decls[kv[0].strip_edges()] = kv[1].strip_edges().trim_suffix("!important").strip_edges()
		for sel in m.get_string(1).split(","):
			var sl := sel.strip_edges()
			if sl != "" and not (" " in sl) and not (">" in sl) and not (":" in sl):
				rules.append([sl, decls])
	return rules

static func _css_for(n: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var a: Dictionary = n["attrs"]
	var classes := String(a.get("class", "")).split(" ", false)
	var id := String(a.get("id", ""))
	for r in ctx["css"]:
		var sel: String = r[0]
		var ok := false
		if sel == "*" or sel == n["tag"]:
			ok = true
		elif sel.begins_with("#"):
			ok = sel.substr(1) == id
		elif "." in sel:
			var parts := sel.split(".")
			ok = (parts[0] == "" or parts[0] == n["tag"])
			for k in range(1, parts.size()):
				ok = ok and parts[k] in classes
		if ok:
			out.append(r[1])
	return out

# ── recorrido ────────────────────────────────────────────────────────────────
const SKIP_TAGS := ["defs", "clipPath", "mask", "symbol", "pattern", "marker", "style", "title", "desc",
	"metadata", "linearGradient", "radialGradient", "filter", "script", "#text"]

static func _walk(n: Dictionary, parent_xf: Transform2D, parent_style: Dictionary, parent_op: float, ctx: Dictionary, out: Dictionary, depth: int) -> void:
	var tag: String = n["tag"]
	if tag in SKIP_TAGS or depth > 32:
		return
	var a: Dictionary = n["attrs"]
	var style := _merge_style(parent_style, a, _css_for(n, ctx))
	if String(style.get("display", "")) == "none":
		return
	var xf: Transform2D = parent_xf * _parse_transform(String(a.get("transform", "")))
	var op: float = parent_op * float(style.get("opacity", "1"))
	var hidden := String(style.get("visibility", "")) == "hidden"
	match tag:
		"g", "a", "switch":
			for c in n["children"]:
				_walk(c, xf, style, op, ctx, out, depth + 1)
		"svg":   # SVG anidado: posición + viewBox propios
			var inner := xf * Transform2D(0.0, Vector2(_len(a.get("x", "0"), 0), _len(a.get("y", "0"), 0)))
			inner = inner * _viewbox_xf(a)
			for c in n["children"]:
				_walk(c, inner, style, op, ctx, out, depth + 1)
		"use":
			var ref := String(a.get("href", a.get("xlink:href", ""))).trim_prefix("#")
			if ctx["ids"].has(ref):
				var target: Dictionary = ctx["ids"][ref]
				var uxf := xf * Transform2D(0.0, Vector2(_len(a.get("x", "0"), 0), _len(a.get("y", "0"), 0)))
				if target["tag"] == "symbol":
					uxf = uxf * _viewbox_xf(target["attrs"], a)
					var sstyle := _merge_style(style, target["attrs"], _css_for(target, ctx))
					for c in target["children"]:
						_walk(c, uxf, sstyle, op, ctx, out, depth + 1)
				else:
					_walk(target, uxf, style, op, ctx, out, depth + 1)
		"path", "rect", "circle", "ellipse", "line", "polyline", "polygon":
			# El fondo que pone el propio exportador de Vectopen no es una figura.
			if not hidden and String(a.get("data-vectopen", "")) != "background":
				var subs := _geometry(tag, a)
				if not subs.is_empty():
					out["items"].append(_path_item(subs, xf, style, op, ctx["grads"], String(a.get("id", "")), tag))
		"text":
			if not hidden:
				_text_items(n, xf, style, op, ctx, out)
		"image":
			if not hidden:
				var href := String(a.get("href", a.get("xlink:href", "")))
				var img := _data_image(href)
				if img:
					var w := _len(a.get("width", ""), img.get_width())
					var h := _len(a.get("height", ""), img.get_height())
					var ixf := xf * Transform2D(0.0, Vector2(_len(a.get("x", "0"), 0), _len(a.get("y", "0"), 0))) \
						* Transform2D(0.0, Vector2(w / img.get_width(), h / img.get_height()), 0.0, Vector2.ZERO)
					out["items"].append({"t": "image", "image": img, "xf": ixf, "opacity": op})

## viewBox → escala/desplazamiento (preserveAspectRatio xMidYMid meet).
static func _viewbox_xf(a: Dictionary, size_from: Dictionary = {}) -> Transform2D:
	var vb := String(a.get("viewBox", "")).replace(",", " ").split(" ", false)
	if vb.size() != 4:
		return Transform2D.IDENTITY
	var r := Rect2(float(vb[0]), float(vb[1]), float(vb[2]), float(vb[3]))
	var src: Dictionary = size_from if size_from.has("width") else a
	var w := _len(src.get("width", ""), r.size.x)
	var h := _len(src.get("height", ""), r.size.y)
	var k := minf(w / maxf(r.size.x, 0.001), h / maxf(r.size.y, 0.001))
	var off := Vector2(w - r.size.x * k, h - r.size.y * k) / 2.0
	return Transform2D(0.0, Vector2(k, k), 0.0, off) * Transform2D(0.0, -r.position)

## <text> con <tspan>: cada trozo con x/y/dy propios es un texto en su sitio.
static func _text_items(n: Dictionary, xf: Transform2D, style: Dictionary, op: float, ctx: Dictionary, out: Dictionary) -> void:
	var a: Dictionary = n["attrs"]
	var size := _len(style.get("font-size", "16"), 16.0)
	var pos := Vector2(_len(a.get("x", "0"), 0), _len(a.get("y", "0"), 0))
	var runs: Array = []   # [pos, texto, estilo]
	for c in n["children"]:
		if c["tag"] == "#text":
			var t := String(c["text"]).strip_edges()
			if t != "":
				runs.append([pos, t, style])
		elif c["tag"] == "tspan":
			var ta: Dictionary = c["attrs"]
			var tst := _merge_style(style, ta, _css_for(c, ctx))
			var tsize := _len(tst.get("font-size", "16"), size)
			if ta.has("x"): pos.x = _len(ta["x"], pos.x)
			if ta.has("y"): pos.y = _len(ta["y"], pos.y)
			if ta.has("dx"): pos.x += _em(ta["dx"], tsize)
			if ta.has("dy"): pos.y += _em(ta["dy"], tsize)
			var tt := String(c["text"]).strip_edges()
			if tt != "":
				runs.append([pos, tt, tst])
	for r in runs:
		var st: Dictionary = r[2]
		var sz := _len(st.get("font-size", "16"), size)
		var fam := String(st.get("font-family", "sans-serif")).get_slice(",", 0).strip_edges().trim_prefix("'").trim_suffix("'").trim_prefix("\"").trim_suffix("\"")
		var weight := String(st.get("font-weight", "normal"))
		out["items"].append({"t": "text", "text": r[1],
			# (x,y) de SVG es la línea base: la caja empieza ~0,8·tamaño más arriba
			"xf": xf * Transform2D(0.0, r[0] + Vector2(0, -sz * 0.8)),
			"size": sz, "color": _paint(st, "fill", ctx["grads"]), "family": fam,
			"bold": weight == "bold" or (weight.is_valid_int() and int(weight) >= 600),
			"opacity": op})

static func _em(v: Variant, size: float) -> float:
	var s := String(v).strip_edges()
	if s.ends_with("em"):
		return float(s.trim_suffix("em")) * size
	return _len(s, 0.0)

# ── estilo ───────────────────────────────────────────────────────────────────
const STYLE_KEYS := ["fill", "stroke", "stroke-width", "fill-opacity", "stroke-opacity", "fill-rule",
	"stroke-linecap", "stroke-dasharray", "font-size", "font-family", "font-weight", "stop-color", "stop-opacity",
	"display", "visibility", "color"]

## Estilo heredado + atributos de presentación < reglas CSS < style="".
static func _merge_style(parent: Dictionary, a: Dictionary, css: Array = []) -> Dictionary:
	var s := parent.duplicate()
	s.erase("opacity")   # la opacidad se multiplica aparte, no se hereda como valor
	s.erase("display")
	for k in STYLE_KEYS + ["opacity"]:
		if a.has(k):
			s[k] = String(a[k]).strip_edges()
	for decls in css:
		for k in decls:
			s[k] = decls[k]
	for decl in String(a.get("style", "")).split(";", false):
		var kv := decl.split(":", false, 1)
		if kv.size() == 2:
			s[kv[0].strip_edges()] = kv[1].strip_edges()
	return s

static func _url_id(v: String) -> String:
	return v.trim_prefix("url(").get_slice(")", 0).trim_prefix("'").trim_suffix("'").trim_prefix("\"").trim_suffix("\"").trim_prefix("#")

## Color de relleno/trazo. Un degradado da su PRIMER color (el degradado
## completo va aparte, en _path_item → "grad").
static func _paint(st: Dictionary, key: String, grads: Dictionary) -> Variant:
	var v := String(st.get(key, "#000000" if key == "fill" else "none"))
	if v == "none" or v == "":
		return null
	var op := float(st.get(key + "-opacity", "1"))
	if v.begins_with("url("):
		var g: Dictionary = grads.get(_url_id(v), {})
		var stops: Array = g.get("stops", [])
		var c: Color = stops[0][1] if not stops.is_empty() else Color(0.5, 0.5, 0.5)
		c.a *= op
		return c
	if v == "currentColor":
		v = String(st.get("color", "#000000"))
	return _color(v, op)

## Degradado del relleno en el formato de VectorShape (o null).
static func _fill_gradient(st: Dictionary, grads: Dictionary) -> Variant:
	var v := String(st.get("fill", ""))
	if not v.begins_with("url("):
		return null
	var g: Dictionary = grads.get(_url_id(v), {})
	var stops: Array = g.get("stops", [])
	if stops.size() < 2:
		return null
	var a: Dictionary = g["attrs"]
	var angle := 0.0
	if g["type"] == "linear":
		var x1 := _frac(a.get("x1", "0%"), 0.0)
		var y1 := _frac(a.get("y1", "0%"), 0.0)
		var x2 := _frac(a.get("x2", "100%"), 1.0)
		var y2 := _frac(a.get("y2", "0%"), 0.0)
		angle = atan2(y2 - y1, x2 - x1)
	return {"type": 1 if g["type"] == "radial" else 0, "angle": angle, "stops": stops}

static func _frac(v: Variant, fallback: float) -> float:
	var t := String(v).strip_edges()
	if t == "":
		return fallback
	return float(t.trim_suffix("%")) / 100.0 if t.ends_with("%") else float(t)

static func _color(v: String, opacity: float = 1.0) -> Color:
	var s := v.strip_edges().to_lower()
	if NAMED.has(s):
		s = NAMED[s]
	var c := Color.BLACK
	if s.begins_with("#"):
		var h := s.substr(1)
		if h.length() == 3 or h.length() == 4:
			var e := ""
			for ch in h:
				e += ch + ch
			h = e
		c = Color.html(h) if Color.html_is_valid(h) else Color.BLACK
	elif s.begins_with("rgb"):
		var nums := s.get_slice("(", 1).trim_suffix(")").replace("/", ",").split(",", false)
		var ch: Array = []
		for i in nums.size():
			var t := nums[i].strip_edges()
			var f := float(t.trim_suffix("%"))
			ch.append(f / 100.0 if t.ends_with("%") else (f / 255.0 if i < 3 else f))
		if ch.size() >= 3:
			c = Color(ch[0], ch[1], ch[2], ch[3] if ch.size() > 3 else 1.0)
	c.a *= opacity
	return c

static func _len(v: Variant, fallback: float) -> float:
	var s := String(v).strip_edges()
	if s == "" or s.ends_with("%"):
		return fallback
	var n := float(s.rstrip("abcdefghijklmnopqrstuvwxyz"))
	if s.ends_with("pt"): n *= 1.3333
	elif s.ends_with("mm"): n *= 3.7795
	elif s.ends_with("cm"): n *= 37.795
	elif s.ends_with("in"): n *= 96.0
	return n

static func _path_item(subs: Array, xf: Transform2D, st: Dictionary, op: float, grads: Dictionary, id: String, tag: String) -> Dictionary:
	var baked: Array = []
	for sub in subs:
		var anchors := PackedVector2Array()
		var ins := PackedVector2Array()
		var outs := PackedVector2Array()
		for i in (sub["anchors"] as PackedVector2Array).size():
			var p: Vector2 = sub["anchors"][i]
			anchors.append(xf * p)
			ins.append(xf.basis_xform(sub["ins"][i]))
			outs.append(xf.basis_xform(sub["outs"][i]))
		baked.append({"anchors": anchors, "ins": ins, "outs": outs, "closed": sub["closed"]})
	var cap := String(st.get("stroke-linecap", "butt"))
	var k := sqrt(absf(xf.determinant()))
	var dash: Variant = null
	var da := String(st.get("stroke-dasharray", "none")).replace(",", " ").split(" ", false)
	if da.size() >= 1 and da[0] != "none" and float(da[0]) > 0.0:
		dash = [float(da[0]) * k, (float(da[1]) if da.size() > 1 else float(da[0])) * k]
	return {"t": "path", "subs": baked, "fill": _paint(st, "fill", grads), "stroke": _paint(st, "stroke", grads),
		"grad": _fill_gradient(st, grads), "dash": dash,
		"width": _len(st.get("stroke-width", "1"), 1.0) * k,
		"cap": 1 if cap == "round" else (2 if cap == "square" else 0),
		"evenodd": String(st.get("fill-rule", "")) == "evenodd", "opacity": op,
		"name": id if id != "" else {"rect": "Rectángulo", "circle": "Círculo", "ellipse": "Elipse",
			"line": "Línea", "polyline": "Trazado", "polygon": "Polígono"}.get(tag, "Trazado")}

static func _parse_transform(s: String) -> Transform2D:
	var xf := Transform2D.IDENTITY
	var re := RegEx.new()
	re.compile("(matrix|translate|scale|rotate|skewX|skewY)\\s*\\(([^)]*)\\)")
	for m in re.search_all(s):
		var n: Array = []
		for t in m.get_string(2).replace(",", " ").split(" ", false):
			n.append(float(t))
		var t := Transform2D.IDENTITY
		match m.get_string(1):
			"matrix":
				if n.size() == 6:
					t = Transform2D(Vector2(n[0], n[1]), Vector2(n[2], n[3]), Vector2(n[4], n[5]))
			"translate":
				t = Transform2D(0.0, Vector2(n[0] if n.size() > 0 else 0.0, n[1] if n.size() > 1 else 0.0))
			"scale":
				var sx: float = n[0] if n.size() > 0 else 1.0
				t = Transform2D(0.0, Vector2(sx, n[1] if n.size() > 1 else sx), 0.0, Vector2.ZERO)
			"rotate":
				var r := deg_to_rad(n[0] if n.size() > 0 else 0.0)
				if n.size() >= 3:
					var c := Vector2(n[1], n[2])
					t = Transform2D(0.0, c) * Transform2D(r, Vector2.ZERO) * Transform2D(0.0, -c)
				else:
					t = Transform2D(r, Vector2.ZERO)
			"skewX":
				t = Transform2D(Vector2(1, 0), Vector2(tan(deg_to_rad(n[0])), 1), Vector2.ZERO)
			"skewY":
				t = Transform2D(Vector2(1, tan(deg_to_rad(n[0]))), Vector2(0, 1), Vector2.ZERO)
		xf = xf * t
	return xf

static func _data_image(href: String) -> Image:
	if not href.begins_with("data:image/"):
		return null
	var comma := href.find(",")
	if comma < 0 or not href.substr(0, comma).ends_with(";base64"):
		return null
	var raw := Marshalls.base64_to_raw(href.substr(comma + 1).strip_edges())
	var img := Image.new()
	if img.load_png_from_buffer(raw) != OK and img.load_jpg_from_buffer(raw) != OK and img.load_webp_from_buffer(raw) != OK:
		return null
	return img

# ── geometría ────────────────────────────────────────────────────────────────
static func _geometry(tag: String, a: Dictionary) -> Array:
	match tag:
		"path":
			return path_d(String(a.get("d", "")))
		"rect":
			var x := _len(a.get("x", "0"), 0)
			var y := _len(a.get("y", "0"), 0)
			var w := _len(a.get("width", "0"), 0)
			var h := _len(a.get("height", "0"), 0)
			if w <= 0 or h <= 0:
				return []
			var rx := _len(a.get("rx", a.get("ry", "0")), 0)
			var ry := _len(a.get("ry", a.get("rx", "0")), 0)
			rx = minf(rx, w / 2)
			ry = minf(ry, h / 2)
			if rx <= 0 and ry <= 0:
				return [_poly([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)], true)]
			var b := _Builder.new()
			b.move(Vector2(x + rx, y))
			b.line(Vector2(x + w - rx, y))
			b.cubic(Vector2(x + w - rx + rx * K, y), Vector2(x + w, y + ry - ry * K), Vector2(x + w, y + ry))
			b.line(Vector2(x + w, y + h - ry))
			b.cubic(Vector2(x + w, y + h - ry + ry * K), Vector2(x + w - rx + rx * K, y + h), Vector2(x + w - rx, y + h))
			b.line(Vector2(x + rx, y + h))
			b.cubic(Vector2(x + rx - rx * K, y + h), Vector2(x, y + h - ry + ry * K), Vector2(x, y + h - ry))
			b.line(Vector2(x, y + ry))
			b.cubic(Vector2(x, y + ry - ry * K), Vector2(x + rx - rx * K, y), Vector2(x + rx, y))
			b.close()
			return b.subs
		"circle", "ellipse":
			var c := Vector2(_len(a.get("cx", "0"), 0), _len(a.get("cy", "0"), 0))
			var r := Vector2(_len(a.get("r", a.get("rx", "0")), 0), _len(a.get("r", a.get("ry", "0")), 0))
			if r.x <= 0 or r.y <= 0:
				return []
			var b := _Builder.new()
			b.move(c + Vector2(r.x, 0))
			b.cubic(c + Vector2(r.x, r.y * K), c + Vector2(r.x * K, r.y), c + Vector2(0, r.y))
			b.cubic(c + Vector2(-r.x * K, r.y), c + Vector2(-r.x, r.y * K), c + Vector2(-r.x, 0))
			b.cubic(c + Vector2(-r.x, -r.y * K), c + Vector2(-r.x * K, -r.y), c + Vector2(0, -r.y))
			b.cubic(c + Vector2(r.x * K, -r.y), c + Vector2(r.x, -r.y * K), c + Vector2(r.x, 0))
			b.close()
			return b.subs
		"line":
			return [_poly([Vector2(_len(a.get("x1", "0"), 0), _len(a.get("y1", "0"), 0)),
				Vector2(_len(a.get("x2", "0"), 0), _len(a.get("y2", "0"), 0))], false)]
		"polyline", "polygon":
			var nums := String(a.get("points", "")).replace(",", " ").split(" ", false)
			var pts: Array = []
			for i in range(0, nums.size() - 1, 2):
				pts.append(Vector2(float(nums[i]), float(nums[i + 1])))
			return [_poly(pts, tag == "polygon")] if pts.size() >= 2 else []
	return []

static func _poly(pts: Array, closed: bool) -> Dictionary:
	var b := _Builder.new()
	b.move(pts[0])
	for i in range(1, pts.size()):
		b.line(pts[i])
	if closed:
		b.close()
	else:
		b.flush(false)
	return b.subs[0]

## Gramática completa de <path d>. Devuelve [{anchors, ins, outs, closed}].
static func path_d(d: String) -> Array:
	var re := RegEx.new()
	re.compile("[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
	var tok: Array = []
	for m in re.search_all(d):
		tok.append(m.get_string())
	var b := _Builder.new()
	var i := 0
	var cmd := ""
	var cur := Vector2.ZERO
	var start := Vector2.ZERO
	var last_c := Vector2.ZERO    # último control (S/T)
	var last_cmd := ""
	while i < tok.size():
		var t: String = tok[i]
		if t.length() == 1 and t.to_upper() in ["M", "L", "H", "V", "C", "S", "Q", "T", "A", "Z"] and not t.is_valid_float():
			cmd = t
			i += 1
			if cmd.to_upper() == "Z":
				b.close()
				cur = start
				last_cmd = "Z"
				continue
		elif cmd == "":
			i += 1
			continue
		var rel := cmd == cmd.to_lower()
		var o := cur if rel else Vector2.ZERO
		var need: int = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7}.get(cmd.to_upper(), 0)
		if i + need > tok.size():
			break
		var n: Array = []
		for k in need:
			n.append(float(tok[i + k]))
		i += need
		match cmd.to_upper():
			"M":
				cur = o + Vector2(n[0], n[1])
				b.move(cur)
				start = cur
				cmd = "l" if rel else "L"   # pares siguientes = lineto
			"L":
				cur = o + Vector2(n[0], n[1])
				b.line(cur)
			"H":
				cur = Vector2((cur.x if rel else 0.0) + n[0], cur.y)
				b.line(cur)
			"V":
				cur = Vector2(cur.x, (cur.y if rel else 0.0) + n[0])
				b.line(cur)
			"C":
				var c1 := o + Vector2(n[0], n[1])
				var c2 := o + Vector2(n[2], n[3])
				cur = o + Vector2(n[4], n[5])
				b.cubic(c1, c2, cur)
				last_c = c2
			"S":
				var c1 := cur * 2.0 - last_c if last_cmd in ["C", "S"] else cur
				var c2 := o + Vector2(n[0], n[1])
				var e := o + Vector2(n[2], n[3])
				b.cubic(c1, c2, e)
				last_c = c2
				cur = e
			"Q", "T":
				var q := (cur * 2.0 - last_c if last_cmd in ["Q", "T"] else cur) if cmd.to_upper() == "T" else o + Vector2(n[0], n[1])
				var e := o + (Vector2(n[0], n[1]) if cmd.to_upper() == "T" else Vector2(n[2], n[3]))
				b.cubic(cur + (q - cur) * 2.0 / 3.0, e + (q - e) * 2.0 / 3.0, e)
				last_c = q
				cur = e
			"A":
				var e := o + Vector2(n[5], n[6])
				_arc(b, cur, Vector2(absf(n[0]), absf(n[1])), deg_to_rad(n[2]), n[3] != 0.0, n[4] != 0.0, e)
				cur = e
		last_cmd = cmd.to_upper()
	b.flush(false)
	return b.subs

## Arco elíptico SVG → Bézier (algoritmo de la especificación, F.6).
static func _arc(b: _Builder, p0: Vector2, r: Vector2, phi: float, large: bool, sweep: bool, p1: Vector2) -> void:
	if r.x < 1e-6 or r.y < 1e-6 or p0.is_equal_approx(p1):
		b.line(p1)
		return
	var cp := cos(phi)
	var sp := sin(phi)
	var d := (p0 - p1) / 2.0
	var x1 := cp * d.x + sp * d.y
	var y1 := -sp * d.x + cp * d.y
	var lam := (x1 * x1) / (r.x * r.x) + (y1 * y1) / (r.y * r.y)
	if lam > 1.0:
		r *= sqrt(lam)
	var num := r.x * r.x * r.y * r.y - r.x * r.x * y1 * y1 - r.y * r.y * x1 * x1
	var den := r.x * r.x * y1 * y1 + r.y * r.y * x1 * x1
	var co := sqrt(maxf(0.0, num / den)) * (-1.0 if large == sweep else 1.0)
	var cx1 := co * r.x * y1 / r.y
	var cy1 := -co * r.y * x1 / r.x
	var c := Vector2(cp * cx1 - sp * cy1, sp * cx1 + cp * cy1) + (p0 + p1) / 2.0
	var a1 := Vector2((x1 - cx1) / r.x, (y1 - cy1) / r.y).angle()
	var da := Vector2((x1 - cx1) / r.x, (y1 - cy1) / r.y).angle_to(Vector2((-x1 - cx1) / r.x, (-y1 - cy1) / r.y))
	if not sweep and da > 0: da -= TAU
	elif sweep and da < 0: da += TAU
	var segs := ceili(absf(da) / (PI / 2.0))
	var step := da / segs
	var kk := 4.0 / 3.0 * tan(step / 4.0)
	for s in segs:
		var t0 := a1 + s * step
		var t1 := t0 + step
		var e0 := Vector2(cos(t0), sin(t0))
		var e1 := Vector2(cos(t1), sin(t1))
		var q1 := e0 + Vector2(-e0.y, e0.x) * kk
		var q2 := e1 - Vector2(-e1.y, e1.x) * kk
		b.cubic(c + _rot(q1 * r, cp, sp), c + _rot(q2 * r, cp, sp), c + _rot(e1 * r, cp, sp) if s < segs - 1 else p1)

## Gira `v` el ángulo phi del arco (cp = cos, sp = sin).
static func _rot(v: Vector2, cp: float, sp: float) -> Vector2:
	return Vector2(cp * v.x - sp * v.y, sp * v.x + cp * v.y)

class _Builder:
	var subs: Array = []
	var anchors := PackedVector2Array()
	var ins := PackedVector2Array()
	var outs := PackedVector2Array()
	func move(p: Vector2) -> void:
		flush(false)
		anchors.append(p); ins.append(Vector2.ZERO); outs.append(Vector2.ZERO)
	func line(p: Vector2) -> void:
		if anchors.is_empty():
			move(p)
			return
		anchors.append(p); ins.append(Vector2.ZERO); outs.append(Vector2.ZERO)
	func cubic(c1: Vector2, c2: Vector2, p: Vector2) -> void:
		if anchors.is_empty():
			move(c1)
		var last := anchors.size() - 1
		outs[last] = c1 - anchors[last]
		anchors.append(p); ins.append(c2 - p); outs.append(Vector2.ZERO)
	func close() -> void:
		# Si el último punto repite el primero, se funden (cierre limpio).
		if anchors.size() >= 2 and anchors[anchors.size() - 1].is_equal_approx(anchors[0]):
			ins[0] = ins[anchors.size() - 1]
			anchors.remove_at(anchors.size() - 1)
			ins.remove_at(ins.size() - 1)
			outs.remove_at(outs.size() - 1)
		flush(true)
	func flush(closed: bool) -> void:
		if anchors.size() >= 2:
			subs.append({"anchors": anchors, "ins": ins, "outs": outs, "closed": closed})
		anchors = PackedVector2Array()
		ins = PackedVector2Array()
		outs = PackedVector2Array()

# ── construir nodos ──────────────────────────────────────────────────────────
## Crea los objetos de Vectopen como hijos de un grupo nuevo (sin añadirlo a
## la escena). `offset`: se suma a todo (posición de destino).
static func build(data: Dictionary, group_name: String = "SVG") -> Node2D:
	var g := Node2D.new()
	g.name = group_name
	g.set_meta("shape_type", "group")
	for it in data["items"]:
		var n: Node2D = null
		match it["t"]:
			"path":
				n = _vector_path(it)
			"text":
				n = _text_node(it)
			"image":
				var sp := Sprite2D.new()
				sp.name = "Imagen"
				sp.texture = ImageTexture.create_from_image(it["image"])
				sp.centered = false
				sp.transform = it["xf"]
				n = sp
		if n:
			if float(it.get("opacity", 1.0)) < 0.999:
				n.modulate.a = float(it["opacity"])
			n.name = NameUtils.unique_child_name(g, String(n.name))
			g.add_child(n)
	return g

static func _vector_path(it: Dictionary) -> Node2D:
	var subs: Array = it["subs"]
	var first: Dictionary = subs[0]
	# Relleno con DEGRADADO (una sola forma cerrada): VectorPolygon, que sí
	# tiene degradados editables; los contornos curvos se aproximan con puntos.
	if it.get("grad") is Dictionary and subs.size() == 1 and bool(first["closed"]):
		var poly := _gradient_polygon(it, first)
		if poly:
			return poly
	var p := Path2D.new()
	p.set_script(load("res://script_gdscript/shapes/VectorPath.gd"))
	p.name = String(it.get("name", "Trazado"))
	p.curve = _curve(first)
	var closed: bool = first["closed"] or (it["fill"] != null and subs.size() == 1 and (first["anchors"] as PackedVector2Array).size() > 2)
	p.closed = closed
	var extra: Array[Curve2D] = []
	for i in range(1, subs.size()):
		extra.append(_curve(subs[i]))
	if not extra.is_empty():
		p.subpaths = extra
	p.fill_color = it["fill"] if it["fill"] != null else Color(0, 0, 0, 0)
	p.stroke_color = it["stroke"] if it["stroke"] != null else Color(0, 0, 0, 0)
	p.stroke_width = float(it["width"]) if it["stroke"] != null else 0.0
	p.stroke_cap_start = int(it["cap"])
	p.stroke_cap_end = int(it["cap"])
	if it.get("dash") is Array:
		p.stroke_style = 1   # discontinuo
		p.stroke_dash_len = float(it["dash"][0])
		p.stroke_dash_gap = float(it["dash"][1])
	return p

static func _gradient_polygon(it: Dictionary, sub: Dictionary) -> Node2D:
	var pts := _curve(sub).tessellate(5, 3.0)
	if pts.size() >= 2 and pts[0].is_equal_approx(pts[pts.size() - 1]):
		pts.remove_at(pts.size() - 1)
	if pts.size() < 3:
		return null
	var c := Vector2.ZERO
	for v in pts:
		c += v
	c /= pts.size()
	var local := PackedVector2Array()
	for v in pts:
		local.append(v - c)
	var poly := VectorPolygon.new()
	poly.name = String(it.get("name", "Forma"))
	poly.is_regular = false
	poly.set_doc_position(DVec2.from_v2(c))
	poly.set_doc_vertices(DVec2.array_from_v2(local))
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for st in it["grad"]["stops"]:
		offs.append(float(st[0]))
		cols.append(st[1])
	g.offsets = offs
	g.colors = cols
	poly.fill_gradient = g
	poly.fill_gradient_type = int(it["grad"]["type"])
	poly.fill_gradient_angle = float(it["grad"]["angle"])
	poly.stroke_color = it["stroke"] if it["stroke"] != null else Color(0, 0, 0, 0)
	poly.stroke_width = float(it["width"]) if it["stroke"] != null else 0.0
	return poly

static func _curve(sub: Dictionary) -> Curve2D:
	var c := Curve2D.new()
	for i in (sub["anchors"] as PackedVector2Array).size():
		c.add_point(sub["anchors"][i], sub["ins"][i], sub["outs"][i])
	return c

static func _text_node(it: Dictionary) -> Node2D:
	var t := Node2D.new()
	t.name = "Texto"
	t.set_meta("shape_type", "text_title")
	t.set_meta("text", it["text"])
	t.set_meta("font_size", int(round(float(it["size"]))))
	var col: Variant = it["color"]
	t.set_meta("text_color", col if col != null else Color.BLACK)
	if String(it["family"]) != "" and String(it["family"]) != "sans-serif":
		t.set_meta("font_family", String(it["family"]))
	t.transform = it["xf"]
	var label := WorldTextLabel.new()
	label.name = "DisplayLabel"
	label.base_font_size = int(round(float(it["size"])))
	label.text = it["text"]
	label.add_theme_color_override("font_color", t.get_meta("text_color"))
	label.add_theme_font_size_override("font_size", label.base_font_size)
	t.add_child(label)
	var edit := TextEdit.new()
	edit.name = "TitleEdit"
	edit.visible = false
	t.add_child(edit)
	if ClassDB.class_exists("VectorRichText"):
		var vrt = ClassDB.instantiate("VectorRichText")
		vrt.name = "VectorRichText"
		vrt.set_is_paragraph(false)
		TextCore.apply_vrt_fonts(vrt, t)
		# set_text() reinicia el formato: primero el texto (si no, 24 px negro).
		vrt.set_text(String(it["text"]))
		vrt.set_text_color(t.get_meta("text_color"))
		vrt.set_font_size(float(label.base_font_size))
		t.add_child(vrt)
		label.visible = false
	return t

const TextCore = preload("res://script_gdscript/text/text_core.gd")
