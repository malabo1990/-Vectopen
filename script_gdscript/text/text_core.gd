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
