# =============================================================================
# RUTA: res://script_gdscript/shapes/table.gd
# TABLAS (encargo 23). Una tabla es un GRUPO (meta shape_type = "group") con
# la meta "table" = {
#     rows, cols, data: [[texto…]…], col_w: [px…], row_h: px, header: bool,
#     font_size, align: ["left"|"center"|"right"…] por columna,
#     colors: {header_bg, header_fg, cell_bg, zebra_bg, text, border},
#     border: px
# }
# y su contenido (fondos de celda, líneas y textos) se GENERA a partir de
# esos datos. Editar el texto de una celda a mano funciona: antes de rehacer
# la tabla se releen los textos de sus celdas (sync_from_children).
# Cada operación es un paso de deshacer (se guarda la meta antes/después).
# =============================================================================
extends RefCounted

const META := "table"

static func is_table(n: Node) -> bool:
	return is_instance_valid(n) and n.has_meta(META)

## Tabla que contiene a `n` (o `n`).
static func table_of(n: Node) -> Node2D:
	var p := n
	while p and not ("artboard_size" in p):
		if is_table(p):
			return p
		p = p.get_parent()
	return null

static func default_spec(rows: int, cols: int, width: float) -> Dictionary:
	var data: Array = []
	for r in rows:
		var row: Array = []
		for c in cols:
			row.append("")
		data.append(row)
	var cw: Array = []
	for c in cols:
		cw.append(width / cols)
	var al: Array = []
	for c in cols:
		al.append("left")
	return {"rows": rows, "cols": cols, "data": data, "col_w": cw, "row_h": 44.0, "header": true,
		"font_size": 16, "align": al, "border": 1.0, "zebra": true,
		"colors": {"header_bg": "#2b2d42", "header_fg": "#ffffff", "cell_bg": "#ffffff",
			"zebra_bg": "#f2f4f8", "text": "#2b2d42", "border": "#c9ced8"}}

static func _col(spec: Dictionary, key: String) -> Color:
	return Color.html(String((spec.get("colors", {}) as Dictionary).get(key, "#000000")))

## Rehace el contenido de la tabla a partir de su meta.
static func rebuild(t: Node2D) -> void:
	var spec: Dictionary = t.get_meta(META)
	for ch in t.get_children():
		if ch is Node2D:
			t.remove_child(ch)
			ch.queue_free()
	var rows := int(spec["rows"])
	var cols := int(spec["cols"])
	var cw: Array = spec["col_w"]
	var rh := float(spec["row_h"])
	var total_w := 0.0
	for w in cw:
		total_w += float(w)
	var total_h := rh * rows
	var fs := int(spec.get("font_size", 16))
	var data: Array = spec["data"]
	# Fondos por fila (cabecera, cebreado)
	for r in rows:
		var col: Color
		if r == 0 and bool(spec.get("header", true)):
			col = _col(spec, "header_bg")
		elif bool(spec.get("zebra", true)) and r % 2 == 0:
			col = _col(spec, "zebra_bg")
		else:
			col = _col(spec, "cell_bg")
		var bg := VectorRectangle.new()
		bg.name = "Fila %d" % (r + 1)
		bg.size = Vector2(total_w, rh)
		bg.fill_color = col
		bg.stroke_width = 0.0
		bg.set_doc_position(DVec2.from_v2(Vector2(total_w / 2.0, rh * r + rh / 2.0)))
		t.add_child(bg)
	# Líneas (rejilla)
	var bw := float(spec.get("border", 1.0))
	if bw > 0.0:
		var bc := _col(spec, "border")
		for r in rows + 1:
			_line(t, "Línea H %d" % r, Vector2(0, rh * r), Vector2(total_w, rh * r), bw, bc)
		var x := 0.0
		for c in cols + 1:
			_line(t, "Línea V %d" % c, Vector2(x, 0), Vector2(x, total_h), bw, bc)
			if c < cols:
				x += float(cw[c])
	# Textos
	var pad := 12.0
	var x0 := 0.0
	for c in cols:
		var w := float(cw[c])
		var al := String((spec.get("align", []) as Array)[c] if c < (spec.get("align", []) as Array).size() else "left")
		for r in rows:
			var txt := String(data[r][c]) if r < data.size() and c < (data[r] as Array).size() else ""
			if txt == "":
				continue
			var head: bool = r == 0 and bool(spec.get("header", true))
			var color: Color = _col(spec, "header_fg") if head else _col(spec, "text")
			var n := _text(txt, fs, color, 700 if head else 400)
			n.name = "Celda %d,%d" % [r + 1, c + 1]
			n.set_meta("table_cell", [r, c])
			t.add_child(n)
			var sz := Vector2(float(n.get_meta("width", 100.0)), float(n.get_meta("height", fs * 1.4)))
			var px := x0 + pad
			if al == "center":
				px = x0 + (w - sz.x) / 2.0
			elif al == "right":
				px = x0 + w - pad - sz.x
			n.position = Vector2(px, rh * r + (rh - sz.y) / 2.0)
		x0 += w

static func _line(t: Node2D, nm: String, a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var p := VectorPath.new()
	var cv := Curve2D.new()
	cv.add_point(a)
	cv.add_point(b)
	p.curve = cv
	p.name = nm
	p.closed = false
	p.stroke_width = w
	p.stroke_color = c
	p.fill_color = Color(0, 0, 0, 0)
	p.set_meta("table_line", true)
	t.add_child(p)

static func _text(txt: String, fs: int, color: Color, weight: int) -> Node2D:
	var tree := Engine.get_main_loop() as SceneTree
	var api = tree.root.get_node("PluginManager").api if tree else null
	var t := Node2D.new()
	t.set_meta("shape_type", "text_title")
	t.set_meta("text", txt)
	t.set_meta("font_size", fs)
	t.set_meta("text_color", color)
	t.set_meta("font_weight", weight)
	var label := WorldTextLabel.new()
	label.name = "DisplayLabel"
	label.base_font_size = fs
	label.text = txt
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", fs)
	t.add_child(label)
	if ClassDB.class_exists("VectorRichText"):
		var vrt = ClassDB.instantiate("VectorRichText")
		vrt.name = "VectorRichText"
		vrt.set_is_paragraph(false)
		preload("res://script_gdscript/text/text_core.gd").apply_vrt_fonts(vrt, t)
		vrt.set_text(txt)
		vrt.set_text_color(color)
		vrt.set_font_size(float(fs))
		t.add_child(vrt)
		label.self_modulate = Color(1, 1, 1, 0)
		var csz: Vector2 = vrt.get_content_size()
		t.set_meta("width", maxf(csz.x, 8.0))
		t.set_meta("height", maxf(csz.y, fs * 1.2))
	else:
		var f := label.get_theme_font(&"font")
		var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs) if f else Vector2(txt.length() * fs * 0.6, fs * 1.2)
		t.set_meta("width", sz.x)
		t.set_meta("height", sz.y)
	return t

## Celda [fila, columna] bajo el punto GLOBAL `gm`, o [] si cae fuera.
static func cell_at(t: Node2D, gm: Vector2) -> Array:
	var spec: Dictionary = t.get_meta(META)
	var p := t.to_local(gm)
	var rh := float(spec["row_h"])
	var r := int(floor(p.y / rh))
	if p.y < 0.0 or r >= int(spec["rows"]):
		return []
	var x := 0.0
	var cw: Array = spec["col_w"]
	for c in int(spec["cols"]):
		if p.x >= x and p.x < x + float(cw[c]):
			return [r, c]
		x += float(cw[c])
	return []

## Texto de la celda [r, c] (lo crea, vacío, si la celda no tiene texto).
static func cell_text(t: Node2D, r: int, c: int) -> Node2D:
	for ch in t.get_children():
		if ch.has_meta("table_cell"):
			var rc: Array = ch.get_meta("table_cell")
			if int(rc[0]) == r and int(rc[1]) == c:
				return ch
	var spec: Dictionary = t.get_meta(META)
	var fs := int(spec.get("font_size", 16))
	var head: bool = r == 0 and bool(spec.get("header", true))
	var n := _text(" ", fs, _col(spec, "header_fg") if head else _col(spec, "text"), 700 if head else 400)
	n.name = "Celda %d,%d" % [r + 1, c + 1]
	n.set_meta("table_cell", [r, c])
	var x := 0.0
	var cw: Array = spec["col_w"]
	for i in c:
		x += float(cw[i])
	var rh := float(spec["row_h"])
	n.position = Vector2(x + 12.0, rh * r + (rh - float(n.get_meta("height", fs * 1.4))) / 2.0)
	t.add_child(n)
	return n

## Doble clic en una tabla: escribir en la celda bajo el cursor (como una
## hoja de cálculo; también en las celdas vacías). Queda como celda activa.
static func edit_cell_at(t: Node2D, gm: Vector2, move_tool) -> bool:
	var rc := cell_at(t, gm)
	if rc.is_empty():
		return false
	t.set_meta("_active_cell", rc)
	var n := cell_text(t, int(rc[0]), int(rc[1]))
	var canvas = move_tool.canvas
	if canvas == null or not canvas.has_method("change_tool"):
		return false
	var page: Node = t.get_parent()
	while page and not ("artboard_size" in page):
		page = page.get_parent()
	if page == null:
		return false
	if move_tool.has_method("_clear_selection"):
		move_tool._clear_selection()
	var tt = canvas._new_tool(load("res://script_gdscript/tools/TextTool.gd"))
	canvas.change_tool(tt)
	tt.target_artboard = page
	tt._check_and_trigger_edit_at((page as Node2D).to_local(gm), n)
	return true

## Relee en la meta los textos de las celdas (si se editaron a mano).
static func sync_from_children(t: Node2D) -> void:
	var spec: Dictionary = (t.get_meta(META) as Dictionary).duplicate(true)
	for ch in t.get_children():
		if ch.has_meta("table_cell"):
			var rc: Array = ch.get_meta("table_cell")
			var r := int(rc[0])
			var c := int(rc[1])
			if r < spec["data"].size() and c < spec["data"][r].size():
				spec["data"][r][c] = String(ch.get_meta("text", "")).strip_edges()
	t.set_meta(META, spec)

## Aplica `fn(spec)` a la tabla como UN paso de deshacer.
static func edit(t: Node2D, action: String, fn: Callable, recorder: Callable = Callable()) -> void:
	sync_from_children(t)
	var before: Dictionary = (t.get_meta(META) as Dictionary).duplicate(true)
	var after: Dictionary = before.duplicate(true)
	fn.call(after)
	var do_fn := func() -> void:
		if is_instance_valid(t):
			t.set_meta(META, after.duplicate(true))
			rebuild(t)
	var undo_fn := func() -> void:
		if is_instance_valid(t):
			t.set_meta(META, before.duplicate(true))
			rebuild(t)
	if recorder.is_valid():
		recorder.call(action, do_fn, undo_fn)
	else:
		var hm: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("HistoryManager")
		if hm:
			hm.register_action(action)
			hm.add_do(do_fn)
			hm.add_undo(undo_fn)
			hm.commit()
	do_fn.call()

# ── operaciones sobre spec ───────────────────────────────────────────────────
static func op_set_cell(spec: Dictionary, r: int, c: int, text: String) -> void:
	if r >= 0 and r < int(spec["rows"]) and c >= 0 and c < int(spec["cols"]):
		spec["data"][r][c] = text

static func op_insert_row(spec: Dictionary, at: int) -> void:
	var row: Array = []
	for c in int(spec["cols"]):
		row.append("")
	at = clampi(at, 0, int(spec["rows"]))
	(spec["data"] as Array).insert(at, row)
	spec["rows"] = int(spec["rows"]) + 1

static func op_delete_row(spec: Dictionary, at: int) -> void:
	if int(spec["rows"]) <= 1 or at < 0 or at >= int(spec["rows"]):
		return
	(spec["data"] as Array).remove_at(at)
	spec["rows"] = int(spec["rows"]) - 1

static func op_insert_col(spec: Dictionary, at: int, width: float = 120.0) -> void:
	at = clampi(at, 0, int(spec["cols"]))
	for row in spec["data"]:
		(row as Array).insert(at, "")
	(spec["col_w"] as Array).insert(at, width)
	(spec["align"] as Array).insert(at, "left")
	spec["cols"] = int(spec["cols"]) + 1

static func op_delete_col(spec: Dictionary, at: int) -> void:
	if int(spec["cols"]) <= 1 or at < 0 or at >= int(spec["cols"]):
		return
	for row in spec["data"]:
		(row as Array).remove_at(at)
	(spec["col_w"] as Array).remove_at(at)
	(spec["align"] as Array).remove_at(at)
	spec["cols"] = int(spec["cols"]) - 1
