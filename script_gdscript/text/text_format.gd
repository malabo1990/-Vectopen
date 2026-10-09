# =============================================================================
# RUTA: res://script_gdscript/text/text_format.gd
# Formato de CARÁCTER del texto (negrita, cursiva, subrayado, color, tamaño,
# trazo), igual desde cualquier panel:
#   · editando con letras seleccionadas → solo esas letras (editor nativo
#     VectorRichText o TextEdit de respaldo), con UN paso de deshacer;
#   · sin edición → el objeto entero vía InspectorCore (con undo).
# Antes esta lógica vivía dentro del panel de la herramienta Texto; el panel
# Tipografía no la tenía y cada uno aplicaba el formato a su manera.
# =============================================================================
extends RefCounted

const TextRuns = preload("res://script_gdscript/text/text_runs.gd")
const TextCore = preload("res://script_gdscript/text/text_core.gd")

## [shape, editor] del texto en edición (nativo o TextEdit). Vacío si no.
static func editing(tree: SceneTree) -> Array:
	return TextCore.editing_context(tree)

static func _ic(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("InspectorCore") if tree else null

static func _fit(tree: SceneTree, shape: Node2D, text: String) -> void:
	var canvas = tree.get_first_node_in_group("_vectopen_canvas") if tree else null
	var t = canvas.current_tool if canvas and ("current_tool" in canvas) else null
	if t and t.has_method("_fit_height_to_text"):
		t._fit_height_to_text(shape, text)

## Avisa a TODOS los paneles (Texto, Tipografía…) con las props al día.
static func notify(tree: SceneTree) -> void:
	var ic := _ic(tree)
	if ic and ic.has_signal("changed"):
		ic._sync_selection()
		ic.changed.emit(ic.current_props())

## Runs en [start, end) del TextEdit, SIN undo (en vivo).
static func apply_to_range(shape: Node2D, ed: TextEdit, start: int, end: int, mutator: Callable) -> void:
	var dl := shape.get_node_or_null("DisplayLabel")
	TextRuns.apply_range(shape, dl, ed.text.length(), start, end, mutator)
	if dl and dl.has_method("apply_stroke_meta"):
		dl.apply_stroke_meta()
	if is_instance_valid(ed) and ed.syntax_highlighter:
		ed.syntax_highlighter.clear_highlighting_cache()
	if is_instance_valid(ed):
		ed.queue_redraw()
	if shape.is_inside_tree():
		_fit(shape.get_tree(), shape, ed.text)

## Runs en [start, end) del TextEdit con UN paso de deshacer.
static func apply_with_undo(shape: Node2D, ed: TextEdit, start: int, end: int, action_name: String, mutator: Callable) -> void:
	var before := TextCore.capture_text_state(shape)
	apply_to_range(shape, ed, start, end, mutator)
	TextCore.register_text_undo(shape, before, action_name)
	if shape.is_inside_tree():
		notify(shape.get_tree())

## Formato sobre la selección del editor NATIVO con UN paso de deshacer.
static func vrt_apply(shape: Node2D, ed, action_name: String, fn: Callable) -> void:
	var before := TextCore.capture_text_state(shape)
	fn.call()
	shape.set_meta("runs", ed.get_runs_meta())
	ed.queue_redraw()
	var dl = shape.get_node_or_null("DisplayLabel")
	if dl and dl.has_method("set_rich_runs"):
		dl.set_rich_runs(shape.get_meta("runs", []))
	var tree := shape.get_tree()
	_fit(tree, shape, ed.get_text())
	TextCore.register_text_undo(shape, before, action_name)
	notify(tree)

## [start, end) de la selección del TextEdit; sin selección → todo el texto.
static func _te_range(ed: TextEdit, whole_if_empty: bool = true) -> Vector2i:
	var sel = TextCore.sel_range(ed)
	if sel != null and int(sel["end"]) > int(sel["start"]):
		return Vector2i(int(sel["start"]), int(sel["end"]))
	return Vector2i(0, ed.text.length()) if whole_if_empty else Vector2i(-1, -1)

# ── negrita / cursiva / subrayado ────────────────────────────────────────────

## Estado actual (true = activado) de `key` en la selección / objeto.
static func is_on(tree: SceneTree, key: String) -> bool:
	var st := TextCore.selection_style(tree)
	if not st.is_empty():
		match key:
			"bold": return int(st.get("weight", 400)) >= 700
			"italic": return bool(st.get("italic", false))
			_: return bool(st.get("underline", false))
	var ic := _ic(tree)
	if ic == null:
		return false
	var p: Dictionary = ic.current_props()
	match key:
		"bold":
			return p.has("font_weight") and not bool(p["font_weight"].get("mixed", false)) and int(p["font_weight"].get("value", 400)) >= 700
		"italic":
			return p.has("font_italic") and not bool(p["font_italic"].get("mixed", false)) and bool(p["font_italic"].get("value", false))
	for s in ic.selection():
		if is_instance_valid(s) and String(s.get_meta("shape_type", "")).begins_with("text_"):
			var runs: Array = s.get_meta("runs", [])
			if runs.is_empty():
				return false
			for r in runs:
				if not bool(r.get("underline", false)):
					return false
			return true
	return false

## Alterna negrita / cursiva / subrayado. Devuelve el nuevo estado.
static func toggle(tree: SceneTree, key: String) -> bool:
	var on := not is_on(tree, key)
	var ctx := editing(tree)
	if not ctx.is_empty():
		var shape: Node2D = ctx[0]
		var ed = ctx[1]
		if ed.has_method("is_editing"):
			var fn := func() -> void:
				if key == "bold":
					ed.apply_bold_to_selection(on)
				elif key == "italic":
					ed.apply_italic_to_selection(on)
				else:
					ed.apply_underline_to_selection(on)
			vrt_apply(shape, ed, "Texto · %s (selección)" % key, fn)
			return on
		var rg := _te_range(ed as TextEdit)
		if rg.y > rg.x:
			apply_with_undo(shape, ed, rg.x, rg.y, "Texto · %s (selección)" % key, func(r: Dictionary) -> Dictionary:
				r[key] = on
				if key == "bold" and not on and int(r.get("weight", 400)) >= 700:
					r.erase("weight")
				return r)
		return on
	var ic := _ic(tree)
	if ic == null:
		return on
	if key == "bold":
		ic.apply("font_weight", 700 if on else 400)
	elif key == "italic":
		ic.apply("font_italic", on)
	else:
		_underline_objects(ic, on)
	return on

static func _underline_objects(ic: Node, on: bool) -> void:
	for s in ic.selection():
		if not (is_instance_valid(s) and String(s.get_meta("shape_type", "")).begins_with("text_")):
			continue
		var before := TextCore.capture_text_state(s)
		var tlen := String(s.get_meta("text", "")).length()
		# Copia profunda: runs_of devuelve el array del meta.
		var runs := TextRuns.runs_of(s, tlen).duplicate(true)
		for r in runs:
			r["underline"] = on
		s.set_meta("runs", runs)
		var dl = s.get_node_or_null("DisplayLabel")
		if dl and dl.has_method("set_rich_runs"):
			dl.set_rich_runs(runs)
		var vrt = s.get_node_or_null("VectorRichText")
		if vrt:
			TextCore.set_vrt_runs(vrt, runs)
			vrt.queue_redraw()
		TextCore.register_text_undo(s, before, "Texto · subrayado")
	notify(ic.get_tree())

# ── color / tamaño / trazo ───────────────────────────────────────────────────

## `prop` ∈ fill_color, font_size, stroke_color, stroke_width.
static func set_prop(tree: SceneTree, prop: String, value: Variant) -> void:
	var ctx := editing(tree)
	if ctx.is_empty():
		var ic := _ic(tree)
		if ic:
			ic.apply(prop, value)
		return
	var shape: Node2D = ctx[0]
	var ed = ctx[1]
	var label: String = {"fill_color": "color", "font_size": "tamaño", "stroke_color": "color de trazo", "stroke_width": "grosor de trazo"}.get(prop, prop)
	if ed.has_method("is_editing"):
		var fn: Callable
		match prop:
			"fill_color": fn = func() -> void: ed.apply_color_to_selection(value)
			"font_size": fn = func() -> void: ed.apply_font_size_to_selection(clampf(float(value), 4.0, 400.0))
			"stroke_color": fn = func() -> void: ed.apply_stroke_to_selection(value, float(ed.get_stroke_width()))
			_: fn = func() -> void: ed.apply_stroke_to_selection(ed.get_stroke_color(), maxf(0.0, float(value)))
		vrt_apply(shape, ed, "Texto · %s (selección)" % label, fn)
		return
	var rg := _te_range(ed as TextEdit)
	var key: String = {"fill_color": "color", "font_size": "size", "stroke_color": "stroke_color", "stroke_width": "stroke_width"}.get(prop, prop)
	var val = value
	if prop == "font_size":
		val = clampf(float(value), 4.0, 400.0)
	elif prop == "stroke_width":
		val = maxf(0.0, float(value))
	apply_with_undo(shape, ed, rg.x, rg.y, "Texto · %s (selección)" % label, func(r: Dictionary) -> Dictionary:
		r[key] = val
		return r)

# ── arrastre en vivo (tamaño / grosor) sobre letras seleccionadas ───────────
static var _live: Dictionary = {}   # prop -> {shape, before, start, end}

## Aplica en vivo SIN undo; `commit_live` registra UN paso al soltar.
## Devuelve false si no se está editando (el llamante usa InspectorCore).
static func live(tree: SceneTree, prop: String, v: float) -> bool:
	var ctx := editing(tree)
	if ctx.is_empty():
		return false
	var shape: Node2D = ctx[0]
	var ed = ctx[1]
	if not _live.has(prop):
		var rec := {"shape": shape, "before": TextCore.capture_text_state(shape), "start": 0, "end": 0}
		if ed is TextEdit:
			var rg := _te_range(ed as TextEdit)
			rec["start"] = rg.x
			rec["end"] = rg.y
		_live[prop] = rec
	var r: Dictionary = _live[prop]
	if ed.has_method("is_editing"):
		if prop == "font_size":
			ed.apply_font_size_to_selection(clampf(v, 4.0, 400.0))
		else:
			ed.apply_stroke_to_selection(ed.get_stroke_color(), maxf(0.0, v))
		shape.set_meta("runs", ed.get_runs_meta())
		ed.queue_redraw()
		var dl = shape.get_node_or_null("DisplayLabel")
		if dl and dl.has_method("set_rich_runs"):
			dl.set_rich_runs(shape.get_meta("runs", []))
		_fit(tree, shape, ed.get_text())
	else:
		var key := "size" if prop == "font_size" else "stroke_width"
		var val := clampf(v, 4.0, 400.0) if prop == "font_size" else maxf(0.0, v)
		apply_to_range(shape, ed, int(r["start"]), int(r["end"]), func(run: Dictionary) -> Dictionary:
			run[key] = val
			return run)
	notify(tree)
	return true

static func commit_live(prop: String) -> bool:
	if not _live.has(prop):
		return false
	var r: Dictionary = _live[prop]
	_live.erase(prop)
	if is_instance_valid(r["shape"]):
		TextCore.register_text_undo(r["shape"], r["before"], "Texto · %s (selección)" % ("tamaño" if prop == "font_size" else "grosor de trazo"))
	return true
