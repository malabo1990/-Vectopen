# =============================================================================
# RUTA: res://script_gdscript/tools/ParagraphThreading.gd
# Vectopen — Motor de Encadenamiento de Marcos de Texto (Text Threading)
# Inspirado en InDesign y Affinity Publisher: permite que textos largos
# fluyan continuamente a través de múltiples marcos o columnas.
# =============================================================================
class_name ParagraphThreading
extends RefCounted
const TextRuns = preload("res://script_gdscript/text/text_runs.gd")
const TextCore = preload("res://script_gdscript/text/text_core.gd")


const PORT_SIZE: float = 14.0
const PORT_MARGIN: float = 4.0

## Divide un texto en dos partes:
## - "fits": el texto que cabe dentro de las dimensiones (width, height)
## - "overflow": el texto sobrante que debe fluir al siguiente marco enlazado
## Ambas son SUBCADENAS EXACTAS del original (fits + separador + overflow ==
## full_text): no se insertan saltos de línea duros en los cortes ni se
## colapsan espacios/líneas en blanco — el label re-envuelve por su cuenta.
static func split_text_to_fit(
	full_text: String,
	font: Font,
	font_size: int,
	width: float,
	height: float,
	line_spacing: int = 3
) -> Dictionary:
	if full_text.strip_edges().is_empty():
		return {"fits": full_text, "overflow": ""}
	var cut := fit_length(full_text, font, font_size, width, height, line_spacing)
	return {
		"fits": _rstrip_ws(full_text.substr(0, cut)),
		"overflow": full_text.substr(cut),
	}

## Nº de caracteres de `text` (desde el inicio) que caben en el marco.
## Con `label` (WorldTextLabel) se usa SU envoltura (_wrap_lines, con
## sangrías) e interlineado, así el corte coincide con lo que se dibuja.
static func fit_length(
	text: String,
	font: Font,
	font_size: int,
	width: float,
	height: float,
	line_spacing: int = 3,
	label: Control = null
) -> int:
	if text.is_empty():
		return 0
	if font == null:
		font = ThemeDB.fallback_font
	var lines: Array = []
	if label is WorldTextLabel:
		var wl := label as WorldTextLabel
		var iw := wl.indent_world()
		lines = wl._wrap_lines(font, font_size, width, maxf(0.0, iw.x), maxf(0.0, iw.y), iw.z, text)
	else:
		lines = _wrap_line_starts(text, font, font_size, width)
	var line_h: float = font.get_height(font_size) + line_spacing
	if line_h <= 0.0:
		line_h = 20.0
	var max_lines: int = maxi(1, int(floor((height + line_spacing) / line_h)))
	if lines.size() <= max_lines:
		return text.length()
	return int(lines[max_lines]["start"])

## Envoltura simple por palabras (misma regla que WorldTextLabel._wrap_lines
## sin sangrías): solo devuelve el inicio de cada línea en el texto original.
static func _wrap_line_starts(text: String, font: Font, font_size: int, width: float) -> Array:
	var out: Array = []
	var raw_start := 0
	for para in text.split("\n", true):
		out.append({"start": raw_start})
		if width > 0.0:
			var current := ""
			var cursor := raw_start
			for word in para.split(" ", true):
				var probe := current + (" " if current.length() > 0 else "") + word
				if current.length() == 0 or font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
					current = probe
				else:
					out.append({"start": cursor})
					current = word
				cursor += word.length() + 1
		raw_start += para.length() + 1
	return out

static func _rstrip_ws(s: String) -> String:
	var e := s.length()
	while e > 0 and s[e - 1] in [" ", "\n", "\t", "\r"]:
		e -= 1
	return s.substr(0, e)

static func _skip_ws(s: String, from: int) -> int:
	var i := from
	while i < s.length() and s[i] in [" ", "\n", "\t", "\r"]:
		i += 1
	return i

## Sustituye el tramo de la historia que muestra `frame` por `new_text` y
## re-fluye la cadena. Es la ÚNICA forma correcta de confirmar la edición de
## un marco enlazado: escribir `new_text` como historia completa borraba el
## texto de los demás marcos y el sobrante.
static func replace_frame_text(frame: Node2D, new_text: String) -> void:
	if not is_instance_valid(frame):
		return
	var head := get_chain_head(frame)
	if not frame.has_meta("story_range"):
		reflow_chain(head)
	var story: String = str(head.get_meta("raw_story_text", head.get_meta("text", "")))
	var r: Vector2i = frame.get_meta("story_range", Vector2i(story.length(), story.length()))
	var s := clampi(r.x, 0, story.length())
	var e := clampi(r.y, s, story.length())
	var ins := new_text
	var sep := ""
	# Marco vacío al final de la historia: separar del texto anterior.
	if s == e and s > 0 and not ins.is_empty() and not (story[s - 1] in [" ", "\n"]):
		sep = "\n"
	var new_story := story.substr(0, s) + sep + ins + story.substr(e)
	# Formato de la historia: el tramo del marco se sustituye por los runs
	# del marco (ya ajustados al texto editado); si no cuadran, diff por
	# posición sobre la historia entera.
	var sr: Array = head.get_meta("story_runs", [])
	if _runs_len(sr) == story.length() and not sr.is_empty():
		var fr: Array = frame.get_meta("runs", [])
		var mid: Array = []
		if _runs_len(fr) == ins.length() and not fr.is_empty():
			mid = fr.duplicate(true)
			if not sep.is_empty():
				var sep_run: Dictionary = (fr[0] as Dictionary).duplicate()
				sep_run["length"] = sep.length()
				mid.push_front(sep_run)
			head.set_meta("story_runs", TextRuns.merge_runs(slice_runs(sr, 0, s) + mid + slice_runs(sr, e, story.length())))
		else:
			var er := TextRuns.edit_runs(sr, story, new_story)
			if er.is_empty():
				head.remove_meta("story_runs")
			else:
				head.set_meta("story_runs", er)
	head.set_meta("raw_story_text", new_story)
	reflow_chain(head)

## Enlaza source -> target en una cadena de texto
static func link(source: Node2D, target: Node2D) -> bool:
	if not is_instance_valid(source) or not is_instance_valid(target) or source == target:
		return false

	# Evitar bucles circulares
	var cur: Node2D = target
	while is_instance_valid(cur):
		if cur == source:
			return false
		cur = get_next_frame(cur)

	# Si source ya tenía un next, desasociarlo
	var old_next = get_next_frame(source)
	if is_instance_valid(old_next) and old_next != target:
		_clear_link(old_next, "prev_paragraph")

	# Si target ya tenía un prev, desasociarlo
	var old_prev = get_prev_frame(target)
	if is_instance_valid(old_prev) and old_prev != source:
		_clear_link(old_prev, "next_paragraph")

	# Runs de la historia: si la cabeza traía formato que cubre su texto
	# entero, pasa a ser el formato de TODA la historia.
	var head := get_chain_head(source)
	if not head.has_meta("story_runs"):
		var story := str(head.get_meta("raw_story_text", head.get_meta("text", "")))
		var hr: Array = head.get_meta("runs", [])
		if _runs_len(hr) == story.length() and not hr.is_empty():
			head.set_meta("story_runs", hr.duplicate(true))

	source.set_meta("next_paragraph", str(target.get_path()))
	source.set_meta("next_paragraph_id", frame_id(target))
	target.set_meta("prev_paragraph", str(source.get_path()))
	target.set_meta("prev_paragraph_id", frame_id(source))

	# El texto original se preserva en la cabeza de la cadena
	reflow_chain(head)
	return true

## Rompe el enlace posterior de un marco
static func unlink_next(node: Node2D) -> void:
	if not is_instance_valid(node):
		return
	var nxt := get_next_frame(node)
	if is_instance_valid(nxt):
		_clear_link(nxt, "prev_paragraph")
	_clear_link(node, "next_paragraph")
	var head := get_chain_head(node)
	reflow_chain(head)

static func _clear_link(node: Node2D, key: String) -> void:
	for k in [key, key + "_id"]:
		if node.has_meta(k):
			node.remove_meta(k)

## Identificador estable del marco (sobrevive a renombrar/mover/recargar;
## la ruta guardada en "next_paragraph" se rompía al renombrar).
static func frame_id(node: Node2D) -> String:
	if not node.has_meta("frame_id"):
		node.set_meta("frame_id", "f%d" % ResourceUID.create_id())
	return String(node.get_meta("frame_id"))

static var _id_cache: Dictionary = {}   # frame_id -> WeakRef

static func _find_by_id(from: Node, id: String) -> Node2D:
	if id.is_empty():
		return null
	var cached = _id_cache.get(id)
	if cached is WeakRef:
		var c = cached.get_ref()
		if is_instance_valid(c) and c.is_inside_tree() and String(c.get_meta("frame_id", "")) == id:
			return c
	# Búsqueda desde el contenedor de artboards (o la raíz de la escena).
	var root: Node = from
	while root.get_parent() and String(root.name) != "ArtboardsContainer":
		root = root.get_parent()
	for n in root.find_children("*", "Node2D", true, false):
		if String(n.get_meta("frame_id", "")) == id:
			_id_cache[id] = weakref(n)
			return n
	return null

## Resuelve el enlace `key` ("next_paragraph"/"prev_paragraph"): ruta
## guardada (rápido) validada por id, luego hermano por nombre, luego id.
static func _resolve(node: Node2D, key: String) -> Node2D:
	if not is_instance_valid(node) or not node.has_meta(key):
		return null
	var id := String(node.get_meta(key + "_id", ""))
	var p_str := str(node.get_meta(key))
	var n: Node = null
	if not p_str.is_empty():
		n = node.get_node_or_null(NodePath(p_str))
		if not is_instance_valid(n) and node.get_parent():
			n = node.get_parent().get_node_or_null(NodePath(p_str.get_file()))
	if is_instance_valid(n) and n is Node2D and (id.is_empty() or String(n.get_meta("frame_id", "")) == id):
		return n
	if not id.is_empty() and node.is_inside_tree():
		var found := _find_by_id(node, id)
		if found:
			node.set_meta(key, str(found.get_path()))   # refresca la ruta
			return found
	return null

## Obtiene el marco anterior en la cadena
static func get_prev_frame(node: Node2D) -> Node2D:
	return _resolve(node, "prev_paragraph")

## Obtiene el marco siguiente en la cadena
static func get_next_frame(node: Node2D) -> Node2D:
	return _resolve(node, "next_paragraph")

static func _runs_len(runs: Array) -> int:
	return TextRuns.runs_len(runs)

static func slice_runs(runs: Array, a: int, b: int) -> Array:
	return TextRuns.slice_runs(runs, a, b)

## Encuentra la cabeza (primer marco) de la cadena
static func get_chain_head(node: Node2D) -> Node2D:
	if not is_instance_valid(node):
		return null
	var cur := node
	var visited := {}
	while true:
		visited[cur] = true
		var prev := get_prev_frame(cur)
		if not is_instance_valid(prev) or prev in visited:
			break
		cur = prev
	return cur

## Obtiene toda la lista ordenada de marcos de la cadena
static func get_chain(node: Node2D) -> Array[Node2D]:
	var head := get_chain_head(node)
	var chain: Array[Node2D] = []
	var cur := head
	var visited := {}
	while is_instance_valid(cur) and not (cur in visited):
		visited[cur] = true
		chain.append(cur)
		cur = get_next_frame(cur)
	return chain

## Recalcula el flujo de texto (reflow) a lo largo de toda la cadena
static func reflow_chain(head: Node2D) -> void:
	if not is_instance_valid(head):
		return

	# Obtener el texto maestro (story text)
	var story_text: String = ""
	if head.has_meta("raw_story_text"):
		story_text = str(head.get_meta("raw_story_text"))
	elif head.has_meta("text"):
		story_text = str(head.get_meta("text"))
		head.set_meta("raw_story_text", story_text)

	var chain := get_chain(head)
	var story_runs: Array = head.get_meta("story_runs", [])
	if _runs_len(story_runs) != story_text.length():
		story_runs = []
	# Cursor sobre la historia: cada marco recibe un tramo EXACTO
	# [start, end) que se guarda en "story_range" (replace_frame_text lo usa
	# para confirmar la edición de ese marco sin tocar el resto).
	var pos := 0

	for i in range(chain.size()):
		var frame := chain[i]

		var w: float = frame.get_meta("width") if frame.has_meta("width") else 350.0
		var h: float = frame.get_meta("height") if frame.has_meta("height") else 100.0

		var font: Font = null
		var font_size: int = 24
		var line_spacing: int = int(frame.get_meta("line_spacing", 3))
		var display_label = frame.get_node_or_null("DisplayLabel")
		if display_label:
			if "base_font_size" in display_label:
				font_size = display_label.base_font_size
			elif display_label.has_theme_font_size_override("font_size"):
				font_size = display_label.get_theme_font_size("font_size")
			if display_label.has_theme_font_override("font"):
				font = display_label.get_theme_font("font")
			if display_label.has_theme_constant_override("line_spacing"):
				line_spacing = display_label.get_theme_constant("line_spacing")
		if font == null:
			font = ThemeDB.fallback_font

		var start := _skip_ws(story_text, pos)
		var remaining_text := story_text.substr(start)
		if remaining_text.is_empty():
			frame.set_meta("text", "")
			frame.set_meta("story_range", Vector2i(story_text.length(), story_text.length()))
			frame.set_meta("is_overflowing", false)
			frame.set_meta("overflow_text", "")
			_sync_frame_label(frame, "", w, h)
			pos = story_text.length()
			continue

		var cut := fit_length(remaining_text, font, font_size, w, h, line_spacing, display_label)
		var fits_text := _rstrip_ws(remaining_text.substr(0, cut))
		var overflow_text := remaining_text.substr(cut)

		frame.set_meta("text", fits_text)
		frame.set_meta("story_range", Vector2i(start, start + fits_text.length()))
		if not story_runs.is_empty():
			var fr := slice_runs(story_runs, start, start + fits_text.length())
			frame.set_meta("runs", fr)
			if display_label and display_label.has_method("set_rich_runs"):
				display_label.text = fits_text
				display_label.set_rich_runs(fr)
		frame.set_meta("is_overflowing", not overflow_text.strip_edges().is_empty())
		frame.set_meta("overflow_text", overflow_text)
		_sync_frame_label(frame, fits_text, w, h)
		pos = start + cut

## Sincroniza el DisplayLabel y MultiLineEdit del marco sin alterar su bbox fijo
static func _sync_frame_label(frame: Node2D, text: String, w: float, h: float) -> void:
	var display_label: Control = frame.get_node_or_null("DisplayLabel")
	var multi_edit: Control = frame.get_node_or_null("MultiLineEdit")

	if display_label:
		display_label.text = text
		if display_label is WorldTextLabel:
			display_label.set_world_size(Vector2(w, h))
		else:
			display_label.custom_minimum_size = Vector2(w, h)
			display_label.size = Vector2(w, h)
		display_label.queue_redraw()

	if multi_edit:
		multi_edit.custom_minimum_size = Vector2(w, h)
		multi_edit.size = Vector2(w, h)

	var vrt = frame.get_node_or_null("VectorRichText")
	if vrt:
		vrt.set_frame_size(Vector2(w, h))
		# set_text REINICIA el formato del nativo (colores, negritas, tamaños,
		# trazo): solo si el texto cambió, y luego se reaplican los runs del
		# marco. Antes, redimensionar un párrafo (que re-fluye) borraba todo
		# su formato.
		if String(vrt.get_text()) != text:
			vrt.set_text(text)
		var fr: Array = frame.get_meta("runs", [])
		if not fr.is_empty() and TextRuns.runs_len(fr) == text.length():
			TextCore.set_vrt_runs(vrt, fr)
		vrt.queue_redraw()

## Rectángulo global del puerto de enlace/desbordamiento (esquina inferior derecha)
static func get_out_port_rect(frame: Node2D, zoom: float = 1.0) -> Rect2:
	var k: float = 1.0 / maxf(zoom, 0.0002)
	var sz: float = PORT_SIZE * k
	var margin: float = PORT_MARGIN * k
	var w: float = frame.get_meta("width") if frame.has_meta("width") else 350.0
	var h: float = frame.get_meta("height") if frame.has_meta("height") else 100.0
	var local_pos := Vector2(w - sz - margin, h - sz - margin)
	var global_pos := frame.to_global(local_pos)
	return Rect2(global_pos, Vector2(sz, sz))

## Determina si un punto global está dentro del puerto de enlace
static func is_point_in_out_port(frame: Node2D, gpos: Vector2, zoom: float = 1.0) -> bool:
	return get_out_port_rect(frame, zoom).has_point(gpos)
