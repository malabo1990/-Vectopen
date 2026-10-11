# =============================================================================
# RUTA: res://script_gdscript/system/vop_preview.gd
# Capa «render» de un VOP → SVG (para miniaturas y vista previa de archivos).
# =============================================================================
extends RefCounted

static func to_svg(data: Dictionary) -> String:
	var size: Array = data.get("size", [100, 100])
	var r: Dictionary = data["render"]
	var body := PackedStringArray()
	if r.get("background") != null:
		body.append('<rect width="%s" height="%s"%s/>' % [size[0], size[1], _paint("fill", r["background"])])
	for it in r.get("items", []):
		match String(it.get("type", "")):
			"path":
				var d := PackedStringArray()
				for sub in it.get("subpaths", []):
					for o in sub.get("ops", []):
						var nums := PackedStringArray()
						for k in range(1, o.size()):
							nums.append(str(o[k]))
						d.append(String(o[0]) + " ".join(nums))
					if bool(sub.get("closed", false)):
						d.append("Z")
				var fill = it.get("fill")
				if it.get("gradient") is Dictionary and not (it["gradient"]["stops"] as Array).is_empty():
					fill = it["gradient"]["stops"][0][1]
				body.append('<path d="%s"%s%s stroke-width="%s" fill-rule="%s" opacity="%s"/>' % [" ".join(d),
					_paint("fill", fill), _paint("stroke", it.get("stroke")), it.get("stroke_width", 1),
					it.get("fill_rule", "nonzero"), it.get("opacity", 1)])
			"text":
				var t: Array = it.get("transform", [1, 0, 0, 1, 0, 0])
				var spans := ""
				var lines := String(it.get("text", "")).split("\n")
				var sz := float(it.get("size", 16))
				for i in lines.size():
					spans += '<tspan x="0" y="%s">%s</tspan>' % [sz * 0.8 + i * sz * float(it.get("line_height", 1.2)), lines[i].xml_escape()]
				body.append('<text transform="matrix(%s)" font-family="sans-serif" font-size="%s"%s>%s</text>' % [
					" ".join(PackedStringArray(t.map(func(v) -> String: return str(v)))), sz, _paint("fill", it.get("color")), spans])
			"image":
				var t2: Array = it.get("transform", [1, 0, 0, 1, 0, 0])
				body.append('<image width="%s" height="%s" transform="matrix(%s)" href="data:image/png;base64,%s"/>' % [
					it.get("width", 1), it.get("height", 1), " ".join(PackedStringArray(t2.map(func(v) -> String: return str(v)))), it.get("png_base64", "")])
	return '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s">%s</svg>' % [
		size[0], size[1], size[0], size[1], "".join(body)]

static func _paint(attr: String, c: Variant) -> String:
	if c == null:
		return ' %s="none"' % attr
	var h := String(c).trim_prefix("#")
	var a := 1.0
	if h.length() == 8:
		a = h.substr(6, 2).hex_to_int() / 255.0
		h = h.substr(0, 6)
	return ' %s="#%s"%s' % [attr, h, (' %s-opacity="%s"' % [attr, a]) if a < 0.999 else ""]
