# =============================================================================
# RUTA: res://script_gdscript/text/text_core.gd
# Núcleo de la SESIÓN de edición de texto (título y párrafo): editor en
# línea, rango de selección en offsets planos y undo del contenido.
# El render vive en WorldTextLabel; los runs en TextRuns; el flujo entre
# marcos en ParagraphThreading.
# =============================================================================
# Sin `class_name` a propósito (misma convención que canvas_serializer.gd):
# se referencia con preload() y no depende de la caché de clases globales
# del editor (tests headless / CI / editor abierto).
extends RefCounted

const TextRuns = preload("res://script_gdscript/text/text_runs.gd")
const LetterFx = preload("res://script_gdscript/text/letter_fx.gd")

## Garantiza el editor en línea del contenedor de texto (MultiLineEdit para
## párrafos, TitleEdit para títulos) y el autowrap del párrafo. Los textos
## cargados de un .vectopen / pegados solo traían el DisplayLabel: sin
## extensión VectorRichText, entrar a editar ocultaba el texto sin editor y
## al confirmar el párrafo quedaba como "Texto de párrafo vacío.".
static func ensure_inline_editor(shape: Node2D) -> TextEdit:
	if not is_instance_valid(shape):
		return null
	var is_para := String(shape.get_meta("shape_type", "")) == "text_paragraph"
	var dl := shape.get_node_or_null("DisplayLabel") as Label
	if is_para and dl and dl.autowrap_mode == TextServer.AUTOWRAP_OFF:
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ed_name := "MultiLineEdit" if is_para else "TitleEdit"
	var ed := shape.get_node_or_null(ed_name) as TextEdit
	if ed:
		return ed
	var sz := Vector2(float(shape.get_meta("width", 350.0 if is_para else 250.0)),
			float(shape.get_meta("height", 100.0 if is_para else 40.0)))
	var fs := int(shape.get_meta("font_size", 24))
	ed = TextEdit.new()
	ed.name = ed_name
	ed.visible = false
	ed.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY if is_para else TextEdit.LINE_WRAPPING_NONE
	ed.custom_minimum_size = sz
	ed.size = sz
	ed.text = str(shape.get_meta("text", ""))
	ed.add_theme_color_override("font_color", shape.get_meta("text_color", Color.BLACK))
	ed.add_theme_font_size_override("font_size", fs)
	shape.add_child(ed)
	return ed

## [shape, editor, start, end] del texto EN EDICIÓN con selección no vacía
## (título o párrafo). Vacío si no hay: el estilo va al bloque entero.
static func editing_range(tree: SceneTree) -> Array:
	if tree == null:
		return []
	var canvas = tree.get_first_node_in_group("_vectopen_canvas")
	if canvas == null or not ("current_tool" in canvas):
		return []
	var t = canvas.current_tool
	if t == null:
		return []
	var flag = t.get("is_editing") if t != null else null
	if flag == null or not bool(flag):
		return []
	var shape: Node2D = t.get("current_editing_shape")
	if not is_instance_valid(shape):
		return []
	var ed: TextEdit = shape.get_node_or_null("TitleEdit")
	if ed == null:
		ed = shape.get_node_or_null("MultiLineEdit")
	if ed == null or not ed.visible:
		return []
	var sel = sel_range(ed)
	if sel == null or int(sel["end"]) <= int(sel["start"]):
		return []
	return [shape, ed, int(sel["start"]), int(sel["end"])]

## [shape, editor] del texto EN EDICIÓN (VectorRichText nativo o TextEdit),
## con o sin selección. Vacío si no se está editando.
static func editing_context(tree: SceneTree) -> Array:
	if tree == null:
		return []
	var canvas = tree.get_first_node_in_group("_vectopen_canvas")
	if canvas == null or not ("current_tool" in canvas):
		return []
	var t = canvas.current_tool
	var flag = t.get("is_editing") if t != null else null
	if flag == null or not bool(flag):
		return []
	var shape: Node2D = t.get("current_editing_shape")
	if not is_instance_valid(shape):
		return []
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt and vrt.has_method("is_editing") and vrt.is_editing():
		return [shape, vrt]
	for n in ["TitleEdit", "MultiLineEdit"]:
		var ed := shape.get_node_or_null(n) as TextEdit
		if ed and ed.visible:
			return [shape, ed]
	return []

## Formato de las letras SELECCIONADAS (o junto al cursor) del texto en
## edición: {shape, start, end, size, color, weight, italic, underline,
## stroke_width, stroke_color}. Vacío si no se edita. Es lo que deben
## mostrar los paneles mientras se edita (no el tamaño base del objeto).
static func selection_style(tree: SceneTree) -> Dictionary:
	var ctx := editing_context(tree)
	if ctx.is_empty():
		return {}
	var shape: Node2D = ctx[0]
	var ed = ctx[1]
	var start := 0
	var end := 0
	var runs: Array = []
	if ed.has_method("is_editing"):
		var sr: Vector2i = ed.get_selection_range()
		start = mini(sr.x, sr.y)
		end = maxi(sr.x, sr.y)
		if start == end:
			start = int(ed.get_caret_index())
			end = start
		runs = ed.get_runs_meta()
	else:
		var te := ed as TextEdit
		var sel = sel_range(te)
		if sel != null:
			start = int(sel["start"])
			end = int(sel["end"])
		else:
			start = flat_off(te, te.get_caret_line(), te.get_caret_column())
			end = start
		runs = shape.get_meta("runs", [])
	# Con cursor sin selección manda la letra ANTERIOR (lo que se escribirá).
	var idx := start if end > start else maxi(0, start - 1)
	var base_fs := float(shape.get_meta("font_size", 24))
	var out := {"shape": shape, "start": start, "end": end, "size": base_fs,
		"weight": int(shape.get_meta("font_weight", 400)), "italic": bool(shape.get_meta("font_italic", false)),
		"underline": false}
	var pos := 0
	var run: Dictionary = {}
	for r in runs:
		var ln := int(r.get("length", 0))
		if idx < pos + ln or r == runs[runs.size() - 1]:
			run = r
			break
		pos += ln
	if run.is_empty():
		return out
	var sz := float(run.get("size", 0.0))
	if sz > 0.0:
		out["size"] = sz
	if run.has("color"):
		out["color"] = run["color"]
	out["weight"] = int(TextRuns.run_weight(run, int(out["weight"])))
	out["italic"] = bool(run.get("italic", out["italic"]))
	out["underline"] = bool(run.get("underline", false))
	if run.has("stroke_width"):
		out["stroke_width"] = float(run["stroke_width"])
	if run.has("stroke_color"):
		out["stroke_color"] = run["stroke_color"]
	return out

## Tamaño `sz` a las letras seleccionadas del texto en edición (nativo o
## TextEdit; sin selección en TextEdit = todo el texto). SIN undo: quien
## llama hace capture_text_state antes y register_text_undo al terminar.
## Devuelve la forma editada o null si no se está editando.
static func apply_selection_size(tree: SceneTree, sz: float) -> Node2D:
	var ctx := editing_context(tree)
	if ctx.is_empty():
		return null
	var shape: Node2D = ctx[0]
	var ed = ctx[1]
	sz = clampf(sz, 4.0, 400.0)
	if ed.has_method("is_editing"):
		ed.apply_font_size_to_selection(sz)
		shape.set_meta("runs", ed.get_runs_meta())
		ed.queue_redraw()
	else:
		var te := ed as TextEdit
		var sel = sel_range(te)
		var a := 0
		var b := te.text.length()
		if sel != null and int(sel["end"]) > int(sel["start"]):
			a = int(sel["start"])
			b = int(sel["end"])
		TextRuns.apply_range(shape, shape.get_node_or_null("DisplayLabel"), te.text.length(), a, b, func(r: Dictionary) -> Dictionary:
			r["size"] = sz
			return r)
		if te.syntax_highlighter:
			te.syntax_highlighter.clear_highlighting_cache()
		te.queue_redraw()
	var dl = shape.get_node_or_null("DisplayLabel")
	if dl and dl.has_method("set_rich_runs"):
		dl.set_rich_runs(shape.get_meta("runs", []))
	var canvas = tree.get_first_node_in_group("_vectopen_canvas")
	var t = canvas.current_tool if canvas and ("current_tool" in canvas) else null
	if t and t.has_method("_fit_height_to_text"):
		t._fit_height_to_text(shape, String(ed.get_text() if ed.has_method("is_editing") else ed.text))
	return shape

## Rango [start,end) de la selección del editor, en offsets planos. null sin selección.
static func sel_range(ed: TextEdit) -> Variant:
	if ed == null or not ed.has_selection():
		return null
	var a := flat_off(ed, ed.get_selection_from_line(), ed.get_selection_from_column())
	var b := flat_off(ed, ed.get_selection_to_line(), ed.get_selection_to_column())
	return {"start": mini(a, b), "end": maxi(a, b)}

static func flat_off(ed: TextEdit, line: int, column: int) -> int:
	var off := 0
	for l in line:
		off += ed.get_line(l).length() + 1
	return off + column

## Foto del estado editable de un texto (para undo de la edición de
## contenido / tamaño). En una cadena de marcos guarda la historia completa.
static func capture_text_state(shape: Node2D) -> Dictionary:
	var st := {
		"text": String(shape.get_meta("text", "")),
		"runs": (shape.get_meta("runs", []) as Array).duplicate(true),
		"font_size": int(shape.get_meta("font_size", 24)),
		"width": shape.get_meta("width", null),
		"height": shape.get_meta("height", null),
	}
	if shape.has_meta("next_paragraph") or shape.has_meta("prev_paragraph"):
		var head := ParagraphThreading.get_chain_head(shape)
		st["story_head"] = weakref(head)
		st["story"] = String(head.get_meta("raw_story_text", head.get_meta("text", "")))
	return st

static func same_text_state(a: Dictionary, b: Dictionary) -> bool:
	return a.get("text") == b.get("text") and a.get("story", "") == b.get("story", "") \
			and a.get("font_size") == b.get("font_size") and var_to_str(a.get("runs")) == var_to_str(b.get("runs"))

## Restaura una foto de capture_text_state en metas, label, editor y VRT.
static func restore_text_state(shape: Node2D, st: Dictionary) -> void:
	if not is_instance_valid(shape):
		return
	var fs := int(st.get("font_size", 24))
	shape.set_meta("font_size", fs)
	shape.set_meta("runs", (st.get("runs", []) as Array).duplicate(true))
	if st.get("width") != null: shape.set_meta("width", st["width"])
	if st.get("height") != null: shape.set_meta("height", st["height"])
	var dl := shape.get_node_or_null("DisplayLabel")
	if dl is WorldTextLabel:
		dl.world_font_size = fs
	var head_ref = st.get("story_head")
	var head: Node2D = head_ref.get_ref() if head_ref is WeakRef else null
	if is_instance_valid(head):
		head.set_meta("raw_story_text", String(st.get("story", "")))
		ParagraphThreading.reflow_chain(head)
	else:
		var t := String(st.get("text", ""))
		shape.set_meta("text", t)
		if dl and "text" in dl:
			dl.text = t
		var vrt = shape.get_node_or_null("VectorRichText")
		if vrt:
			vrt.set_text(t)
			# Sin esto, deshacer un formato por letras con el editor nativo
			# abierto dejaba los runs viejos dibujados.
			set_vrt_runs(vrt, shape.get_meta("runs", []))
	if dl is WorldTextLabel:
		dl.set_rich_runs(shape.get_meta("runs", []))
		if st.get("width") != null and st.get("height") != null:
			dl.set_world_size(Vector2(float(st["width"]), float(st["height"])))
	var sz := Vector2(float(shape.get_meta("width", 0.0)), float(shape.get_meta("height", 0.0)))
	for ed_name in ["MultiLineEdit", "TitleEdit"]:
		var ed := shape.get_node_or_null(ed_name) as TextEdit
		if ed:
			ed.text = String(shape.get_meta("text", ""))
			ed.add_theme_font_size_override("font_size", fs)
			if sz.x > 0.0 and sz.y > 0.0:
				ed.custom_minimum_size = sz
				ed.size = sz
	var ge := shape.get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_method("emit_safe"):
		ge.emit_safe("object_transformed")

## Registra en HistoryManager el paso before → estado actual (si cambió).
## El cambio YA está aplicado (este HistoryManager no ejecuta al commit).
static func register_text_undo(shape: Node2D, before: Dictionary, action_name: String) -> void:
	if not is_instance_valid(shape) or before.is_empty():
		return
	var after := capture_text_state(shape)
	if same_text_state(before, after):
		return
	var hm := shape.get_node_or_null("/root/HistoryManager")
	if hm == null or not hm.has_method("register_action"):
		return
	hm.register_action(action_name)
	hm.add_do(func() -> void: restore_text_state(shape, after))
	hm.add_undo(func() -> void: restore_text_state(shape, before))
	hm.commit()

## Fuentes de FontCore al editor nativo VectorRichText: la normal y las
## REALES de negrita / cursiva / negrita+cursiva (Inter-Bold, Inter-Italic…).
## null = la familia no tiene ese archivo → el editor lo sintetiza.
static func apply_vrt_fonts(vrt, shape: Node2D) -> void:
	var st := Engine.get_main_loop() as SceneTree
	var fc = st.root.get_node_or_null("FontCore") if st else null
	if vrt == null or fc == null or not fc.has_method("get_font"):
		return
	var spec: Dictionary = fc.spec_from_node(shape)
	var base: Font = fc.get_font(spec)
	vrt.set_font(base)
	if not vrt.has_method("set_style_fonts"):
		return
	var w := int(spec.get("weight", 400))
	var styled := func(bold: bool, italic: bool) -> Variant:
		var sp := spec.duplicate()
		if bold:
			sp["weight"] = maxi(w, 700)
		if italic:
			sp["italic"] = true
		var f: Font = fc.get_font(sp)
		return f if f != base and not (f is FontVariation and (f as FontVariation).base_font == base) else null
	vrt.set_style_fonts(styled.call(true, false), styled.call(false, true), styled.call(true, true))
	# Fuentes reales por PESO (grosor por run: Ctrl+Alt+. / Ctrl+Alt+,).
	if vrt.has_method("set_weight_fonts"):
		var roman := {}
		var italic := {}
		for wt in range(100, 1000, 100):
			var sp := spec.duplicate()
			sp["weight"] = wt
			sp["italic"] = false
			roman[wt] = fc.get_font(sp)
			sp["italic"] = true
			italic[wt] = fc.get_font(sp)
		vrt.set_weight_fonts(roman, italic, w)

## Grosor con teclado (Ctrl+Alt+. / Ctrl+Alt+,): ±100 sobre la selección del
## editor en línea (runs, vía `apply_range` con undo de la herramienta) o, sin
## selección, sobre el peso de todo el texto (InspectorCore → font_weight).
static func weight_step(tool: Object, shape: Node2D, ed: TextEdit, delta: int) -> void:
	var base_w := int(shape.get_meta("font_weight", 400))
	var sel = sel_range(ed) if ed else null
	if sel != null and int(sel["end"]) > int(sel["start"]):
		var start := int(sel["start"])
		var end := int(sel["end"])
		var runs := TextRuns.runs_of(shape, ed.text.length())
		var nw := clampi(TextRuns.weight_at(runs, start, base_w) + delta, 100, 900)
		tool._apply_style_to_range(shape, start, end, func(r: Dictionary) -> Dictionary:
			r["weight"] = nw
			r["bold"] = nw >= 700
			return r)
		return
	var st := Engine.get_main_loop() as SceneTree
	var ic = st.root.get_node_or_null("InspectorCore") if st else null
	if ic and ic.has_method("apply"):
		ic.apply("font_weight", clampi(base_w + delta, 100, 900))

## Runs al editor nativo. VectorRichText exige Array[Dictionary] tipado y lee
## "size" LITERAL: en GDScript size 0/ausente = "el tamaño base del texto", y
## el nativo lo tomaba como 0 (o su 24 por defecto) → un texto de 64 se veía
## a otro tamaño al reeditarlo o recargarlo. Se rellena con el font_size.
static func set_vrt_runs(vrt, raw_runs, with_fx: bool = true) -> void:
	if vrt == null or raw_runs == null:
		return
	var shape: Node = vrt.get_parent()
	var fs := float(shape.get_meta("font_size", 24)) if shape else 24.0
	# Efectos de letras: al DIBUJAR se materializan en runs por letra. Al
	# editar no (los runs del editor se vuelcan al meta y los hornearían).
	if with_fx and shape and LetterFx.has_fx(shape) and not vrt.is_editing():
		raw_runs = LetterFx.derive_runs(shape, raw_runs if raw_runs is Array else [], String(vrt.get_text()))
	var typed_runs: Array[Dictionary] = []
	if raw_runs is Array:
		for r in raw_runs:
			if r is Dictionary:
				var d: Dictionary = (r as Dictionary).duplicate()
				if float(d.get("size", 0.0)) <= 0.0:
					d["size"] = fs
				typed_runs.append(d)
	vrt.set_runs_meta(typed_runs)

## Vuelve a pintar los efectos de letras del texto (tras cambiarlos, al
## salir de edición o al cargar) y reajusta la caja.
static func refresh_letter_fx(shape: Node2D) -> void:
	if not is_instance_valid(shape):
		return
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		set_vrt_runs(vrt, shape.get_meta("runs", []))
		vrt.queue_redraw()
	var dl = shape.get_node_or_null("DisplayLabel")
	if dl and dl.has_method("invalidate_layout"):
		dl.invalidate_layout()

## Render/editor nativo VectorRichText del texto (si la extensión existe):
## el MISMO motor al crear, editar y RECARGAR. Antes, tras cargar un
## .vectopen se pintaba con WorldTextLabel y el texto cambiaba de posición,
## altura y hasta de corte de línea respecto a como se creó.
static func ensure_vrt(shape: Node2D) -> Object:
	if not is_instance_valid(shape) or not ClassDB.class_exists("VectorRichText"):
		return null
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt == null:
		vrt = ClassDB.instantiate("VectorRichText")
		vrt.name = "VectorRichText"
		vrt.set_is_paragraph(String(shape.get_meta("shape_type", "")) == "text_paragraph")
		shape.add_child(vrt)
	sync_vrt_from_meta(shape, vrt)
	var dl := shape.get_node_or_null("DisplayLabel") as CanvasItem
	if dl:
		dl.self_modulate = Color(1, 1, 1, 0)   # el nativo pinta; la etiqueta queda para medidas
	return vrt

## Estado completo del nativo desde las metas del texto.
static func sync_vrt_from_meta(shape: Node2D, vrt) -> void:
	apply_vrt_fonts(vrt, shape)
	var txt := String(shape.get_meta("text", ""))
	vrt.set_text(txt)
	var sz := Vector2(float(shape.get_meta("width", 0.0)), float(shape.get_meta("height", 0.0)))
	if String(shape.get_meta("shape_type", "")) == "text_paragraph":
		vrt.set_frame_size(Vector2(float(shape.get_meta("width", 350.0)), float(shape.get_meta("height", 100.0))))
	elif sz.x > 0.0 and sz.y > 0.0:
		vrt.custom_minimum_size = sz   # título: misma caja que al crearlo
		vrt.size = sz
	vrt.set_text_color(shape.get_meta("text_color", Color.BLACK))
	vrt.set_font_size(float(shape.get_meta("font_size", 24)))
	if shape.has_meta("text_align") and vrt.has_method("set_paragraph_align"):
		vrt.set_paragraph_align(String(shape.get_meta("text_align")))
	if shape.has_meta("text_valign") and vrt.has_method("set_vertical_alignment"):
		vrt.set_vertical_alignment(String(shape.get_meta("text_valign")))
	if shape.has_meta("line_spacing") and vrt.has_method("set_paragraph_line_spacing"):
		vrt.set_paragraph_line_spacing(float(shape.get_meta("line_spacing")))
	if vrt.has_method("set_paragraph_indents"):
		vrt.set_paragraph_indents(float(shape.get_meta("indent_left", 0.0)),
			float(shape.get_meta("indent_right", 0.0)), float(shape.get_meta("indent_first", 0.0)))
	if shape.has_meta("columns") and vrt.has_method("set_columns"):
		vrt.set_columns(int(shape.get_meta("columns")), float(shape.get_meta("column_gap", 20.0)))
	var runs: Array = shape.get_meta("runs", [])
	if not runs.is_empty() and TextRuns.runs_len(runs) == txt.length():
		set_vrt_runs(vrt, runs)

## Escala el tamaño de CADA run (desde la foto `base_runs`) por `ratio` y lo
## guarda en el meta: así redimensionar con Ctrl conserva tamaños por letra y
## todo el formato (antes vrt.set_font_size(fs) aplanaba todos los runs).
## Runs con size 0 (= tamaño base) se quedan así: siguen al font_size.
static func scale_runs(shape: Node2D, base_runs: Array, ratio: float) -> void:
	if base_runs.is_empty() or ratio <= 0.0:
		return
	var out: Array = []
	for r in base_runs:
		var d: Dictionary = (r as Dictionary).duplicate()
		var sz := float(d.get("size", 0.0))
		if sz > 0.0:
			d["size"] = clampf(sz * ratio, 4.0, 400.0)
		out.append(d)
	shape.set_meta("runs", out)
