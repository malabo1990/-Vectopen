# =============================================================================
# RUTA: res://script_gdscript/text/text_runs.gd
# Motor de RUNS de formato enriquecido (color/negrita/cursiva/subrayado/
# tamaño/trazo por rango de caracteres). Compartido por TextTool,
# ParagraphTool, el panel de párrafo, InspectorCore, el threading y el
# serializador. Un run = {length:int, color, bold, italic, underline,
# size?, stroke_color?, stroke_width?}; la suma de length cubre el texto.
# =============================================================================
# Sin `class_name` a propósito (misma convención que canvas_serializer.gd):
# se referencia con preload() y no depende de la caché de clases globales
# del editor (tests headless / CI / editor abierto).
extends RefCounted

## Motor de runs COMPARTIDO (BBCode avanzado): lo usan TextTool, el panel de
## párrafo e InspectorCore para no triplicar la lógica de rangos.
static func runs_of(shape: Node2D, text_len: int) -> Array:
	var runs: Array = shape.get_meta("runs", [])
	var total := 0
	for r in runs:
		total += int(r.get("length", 0))
	if not runs.is_empty() and total == text_len:
		return runs
	var def_sw: float = float(shape.get_meta("stroke_width", shape.get_meta("text_outline", 0.0)))
	var def_sc: Color = shape.get_meta("stroke_color", shape.get_meta("text_outline_color", Color.BLACK))
	return [{
		"length": text_len,
		"color": shape.get_meta("text_color", Color.BLACK),
		"stroke_color": def_sc,
		"stroke_width": def_sw,
		"bold": int(shape.get_meta("font_weight", 400)) >= 700,
		"italic": bool(shape.get_meta("font_italic", false)),
		"underline": false,
	}]

static func split_runs(runs: Array, cuts: Array) -> Array:
	var out: Array = []
	var pos := 0
	for r in runs:
		var len_: int = int(r.get("length", 0))
		var pts: Array = [pos, pos + len_]
		for c in cuts:
			if c > pos and c < pos + len_:
				pts.append(c)
		pts.sort()
		for i in range(pts.size() - 1):
			if int(pts[i + 1]) > int(pts[i]):
				var nr: Dictionary = (r as Dictionary).duplicate()
				nr["length"] = int(pts[i + 1]) - int(pts[i])
				out.append(nr)
		pos += len_
	return out

static func merge_runs(runs: Array) -> Array:
	var out: Array = []
	for r in runs:
		if not out.is_empty():
			var last: Dictionary = out[out.size() - 1]
			var same_col: bool = (last.get("color", Color.BLACK) as Color).is_equal_approx(r.get("color", Color.BLACK))
			var same_sc: bool = (last.get("stroke_color", Color.BLACK) as Color).is_equal_approx(r.get("stroke_color", Color.BLACK))
			var same_sw: bool = is_equal_approx(float(last.get("stroke_width", 0.0)), float(r.get("stroke_width", 0.0)))
			if same_col and same_sc and same_sw \
					and bool(last.get("bold", false)) == bool(r.get("bold", false)) \
					and bool(last.get("italic", false)) == bool(r.get("italic", false)) \
					and bool(last.get("underline", false)) == bool(r.get("underline", false)) \
					and float(last.get("size", 0.0)) == float(r.get("size", 0.0)):
				last["length"] = int(last["length"]) + int(r.get("length", 0))
				continue
		out.append((r as Dictionary).duplicate())
	return out

## Aplica `mutator` al rango y lo guarda en el shape + refresca el label.
## Devuelve true si aplicó algo.
static func apply_range(shape: Node2D, label: Control, ed_text_len: int, start: int, end: int, mutator: Callable) -> bool:
	if not is_instance_valid(shape) or start >= end:
		return false
	var runs := split_runs(runs_of(shape, ed_text_len), [start, end])
	var out: Array = []
	var pos := 0
	for r in runs:
		var len_: int = int(r.get("length", 0))
		if pos >= start and pos < end:
			out.append(mutator.call((r as Dictionary).duplicate()))
		else:
			out.append(r)
		pos += len_
	out = merge_runs(out)
	shape.set_meta("runs", out)
	if label and label.has_method("set_rich_runs"):
		label.set_rich_runs(out)
	return true

## Reajusta `runs` a `new_len` (recorta/extiende por el final).
static func resize_runs(shape: Node2D, new_len: int) -> void:
	var runs: Array = shape.get_meta("runs", [])
	if runs.is_empty():
		return
	var total := 0
	for r in runs:
		total += int(r.get("length", 0))
	if total == new_len:
		return
	var out: Array = []
	var acc := 0
	for r in runs:
		var len_: int = int(r.get("length", 0))
		if acc >= new_len:
			break
		var take: int = mini(len_, new_len - acc)
		if take > 0:
			var nr: Dictionary = (r as Dictionary).duplicate()
			nr["length"] = take
			out.append(nr)
			acc += take
	if acc < new_len and not out.is_empty():
		out[out.size() - 1]["length"] = int(out[out.size() - 1]["length"]) + (new_len - acc)
	shape.set_meta("runs", out)

## Ajusta `runs` a una edición old_text → new_text SEGÚN LA POSICIÓN del
## cambio (prefijo/sufijo común): lo borrado sale de su run y lo insertado
## hereda el estilo del carácter anterior. resize_runs recortaba siempre por
## el final, así que escribir al principio desplazaba toda la negrita/color.
## Devuelve [] si `runs` no cubre exactamente old_text (el llamador decide).
static func edit_runs(runs: Array, old_text: String, new_text: String) -> Array:
	var total := 0
	for r in runs:
		total += int(r.get("length", 0))
	if runs.is_empty() or total != old_text.length():
		return []
	var ol := old_text.length()
	var nl := new_text.length()
	var p := 0
	while p < ol and p < nl and old_text.unicode_at(p) == new_text.unicode_at(p):
		p += 1
	var sfx := 0
	while sfx < ol - p and sfx < nl - p and old_text.unicode_at(ol - 1 - sfx) == new_text.unicode_at(nl - 1 - sfx):
		sfx += 1
	var del_end := ol - sfx
	var ins_len := nl - p - sfx
	# Estilo heredado: el del carácter anterior al cambio (o el primero).
	var acc := 0
	var style: Dictionary = runs[0]
	for r in runs:
		var l := int(r.get("length", 0))
		if l > 0 and (p == 0 or p - 1 < acc + l):
			style = r
			break
		acc += l
	var out: Array = []
	var pos := 0
	var inserted := false
	for r in split_runs(runs, [p, del_end]):
		var l := int(r.get("length", 0))
		if pos == p and not inserted and ins_len > 0:
			var nr: Dictionary = (style as Dictionary).duplicate()
			nr["length"] = ins_len
			out.append(nr)
			inserted = true
		if pos < p or pos >= del_end:
			out.append(r)
		pos += l
	if not inserted and ins_len > 0:
		var nr: Dictionary = (style as Dictionary).duplicate()
		nr["length"] = ins_len
		out.append(nr)
	return merge_runs(out)

## Aplica edit_runs a las metas del shape (con resize_runs de respaldo).
static func apply_text_edit(shape: Node2D, old_text: String, new_text: String) -> void:
	var runs: Array = shape.get_meta("runs", [])
	if runs.is_empty():
		return
	var out := edit_runs(runs, old_text, new_text)
	if out.is_empty() and not new_text.is_empty():
		resize_runs(shape, new_text.length())
	else:
		shape.set_meta("runs", out)

## Caracteres que cubren los runs (suma de length).
static func runs_len(runs: Array) -> int:
	var t := 0
	for r in runs:
		t += int(r.get("length", 0))
	return t

## Runs del tramo [a, b) (recortados a ese rango).
static func slice_runs(runs: Array, a: int, b: int) -> Array:
	var out: Array = []
	var pos := 0
	for r in split_runs(runs, [a, b]):
		var l := int(r.get("length", 0))
		if pos >= a and pos + l <= b and l > 0:
			out.append(r)
		pos += l
	return out
