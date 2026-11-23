## E2E: la tabla funciona como una tabla DE VERDAD (Modern y Smart):
##   · un clic en cualquier celda selecciona la TABLA (no sus piezas);
##   · el editor de nodos no muestra tiradores Bézier en su rejilla;
##   · doble clic en una celda (también vacía) entra a escribir en ella y la
##     deja como celda activa;
##   · panel «Tabla»: filas / columnas, insertar arriba / abajo / izquierda /
##     derecha, borrar, alto de fila, ancho de columna, igualar, cabecera,
##     alineación; cada cosa con un paso de deshacer.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func click(at: Vector2, dbl: bool = false) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	_send(mm)
	await K.frames(2)
	for down in [true, false]:
		var b := InputEventMouseButton.new()
		b.position = at
		b.global_position = at
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = down
		b.double_click = dbl and down
		b.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		_send(b)
		await K.frames(2)

func panel() -> Control:
	for c in root.find_children("table", "PanelContainer", true, false):
		if (c as Control).is_visible_in_tree() and c.get_script() and String(c.get_script().resource_path).ends_with("panel_table.gd"):
			return c
	return null

func spec(t: Node) -> Dictionary:
	return t.get_meta("table")

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://table_real")
	var T = load("res://script_gdscript/shapes/table.gd")
	for mode in ["modern", "smart"]:
		if not await K.boot(mode):
			quit(1)
			return
		api = K.api
		var ab: Node2D = await K.artboard(Vector2(900, 600), "Tabla " + mode, Color.WHITE)
		await K.look_at(ab)
		var t: Node2D = api.add_table(Rect2(80, 80, 480, 180), 4, 3, [["Nombre", "Edad", "Ciudad"], ["Ana", "31", "Lima"]])
		await K.frames(6)
		var tf: Transform2D = K.canvas.get_viewport().get_canvas_transform()
		var cell_screen := func(r: int, c: int) -> Vector2:
			var s: Dictionary = t.get_meta("table")
			var x := 0.0
			for i in c:
				x += float(s["col_w"][i])
			var local := Vector2(x + float(s["col_w"][c]) * 0.5, float(s["row_h"]) * (r + 0.5))
			return tf * t.to_global(local)
		# 1. clic en una celda → la tabla entera
		K.canvas.switch_tool("move")
		await K.frames(3)
		api.select([])
		await K.frames(2)
		await click(cell_screen.call(1, 1))
		var sel: Array = root.get_node("InspectorCore").selection()
		K.check("%s: un clic en una celda selecciona la TABLA" % mode, sel.size() == 1 and sel[0] == t, str(sel))
		# 2. panel Tabla
		await K.frames(6)
		var p := panel()
		K.check("%s: al seleccionar la tabla se abre su panel" % mode, p != null)
		# 3. editor de nodos: sin tiradores en la rejilla
		K.canvas.switch_tool("nodeselection")
		await K.frames(3)
		var nt = K.canvas.current_tool
		var line_at: Vector2 = tf * t.to_global(Vector2(160, float(spec(t)["row_h"])))   # sobre una línea H
		var found = nt._find_path_at_global(t.to_global(Vector2(160, float(spec(t)["row_h"])))) if nt.has_method("_find_path_at_global") else null
		K.check("%s: el editor de nodos no coge las líneas de la tabla" % mode, found == null or T.table_of(found) == null, str(found))
		K.canvas.switch_tool("move")
		await K.frames(3)
		# 4. doble clic en una celda VACÍA → escribir en ella
		await click(cell_screen.call(3, 2))
		await click(cell_screen.call(3, 2), true)
		await K.frames(6)
		var tool = K.canvas.current_tool
		var editing: Node = tool.get("current_editing_shape") if tool and "current_editing_shape" in tool else null
		K.check("%s: doble clic en una celda vacía entra a escribir en ESA celda" % mode, editing != null and editing.has_meta("table_cell") and Array(editing.get_meta("table_cell")) == [3, 2], str(editing.get_meta("table_cell") if editing and editing.has_meta("table_cell") else editing))
		K.check("%s: queda como celda activa" % mode, Array(t.get_meta("_active_cell", [])) == [3, 2])
		if tool and tool.has_method("commit_text_edit"):
			tool.commit_text_edit(false)
		await K.frames(3)
		var c32 = T.cell_text(t, 3, 2)
		K.check("%s: confirmar una celda vacía la deja VACÍA (no «Título Nuevo»)" % mode, String(c32.get_meta("text", "")).strip_edges() == "", String(c32.get_meta("text", "")))
		K.canvas.switch_tool("move")
		await K.frames(3)
		api.select([t])
		await K.frames(6)
		p = panel()
		if p == null:
			continue
		# 5. estructura con la celda activa (3,2)
		t.set_meta("_active_cell", [1, 1])
		(p.find_child("RowBelow", true, false) as Button).pressed.emit()
		await K.frames(4)
		K.check("%s: «Fila abajo» → 5 filas" % mode, int(spec(t)["rows"]) == 5)
		K.check("%s: la fila nueva va debajo de la activa (Ana sube a la 2)" % mode, String(spec(t)["data"][1][0]) == "Ana" and String(spec(t)["data"][2][0]) == "")
		api.undo()
		await K.frames(4)
		K.check("%s: deshacer → 4 filas" % mode, int(spec(t)["rows"]) == 4)
		(p.find_child("ColRight", true, false) as Button).pressed.emit()
		await K.frames(4)
		K.check("%s: «Col. derecha» → 4 columnas" % mode, int(spec(t)["cols"]) == 4)
		var rows_f: Control = p.find_child("Table_rows", true, false)
		rows_f.value_changed.emit(7.0)
		await K.frames(4)
		K.check("%s: Filas = 7" % mode, int(spec(t)["rows"]) == 7)
		var cw_f: Control = p.find_child("Table_col_w", true, false)
		cw_f.value_changed.emit(220.0)
		await K.frames(4)
		var ac := int(Array(t.get_meta("_active_cell", [0, 0]))[1])
		K.check("%s: ancho de la columna activa = 220" % mode, is_equal_approx(float(spec(t)["col_w"][ac]), 220.0), str(spec(t)["col_w"]))
		(p.find_child("EqualCols", true, false) as Button).pressed.emit()
		await K.frames(4)
		var cws: Array = spec(t)["col_w"]
		K.check("%s: «Igualar columnas»" % mode, cws.all(func(w) -> bool: return is_equal_approx(float(w), float(cws[0]))), str(cws))
		(p.find_child("DelCol", true, false) as Button).pressed.emit()
		await K.frames(4)
		K.check("%s: «Borrar columna» → 3 columnas" % mode, int(spec(t)["cols"]) == 3)
		(p.find_child("Table_header", true, false) as CheckButton).toggled.emit(false)
		await K.frames(4)
		K.check("%s: cabecera desactivada" % mode, not bool(spec(t)["header"]))
		(p.find_child("Align_center", true, false) as Button).pressed.emit()
		await K.frames(4)
		K.check("%s: alineación centrada" % mode, Array(spec(t)["align"]).all(func(a) -> bool: return String(a) == "center"))
		await K.frames(4)
		var pr: Rect2 = p.get_global_rect()
		K.check("%s: el panel Tabla no llega al borde inferior" % mode, pr.end.y <= root.get_visible_rect().size.y - 12.0, str(pr))
		var others := 0
		for nm in ["bezier", "polygon", "brush", "light", "blend", "layout"]:
			for c in root.find_children(nm, "Control", true, false):
				if (c as Control).is_visible_in_tree() and c.get_parent() and (c.get_parent().name == "Herramientas" or c.get_parent().name == "ToolPanelSlot"):
					others += 1
		K.check("%s: ningún otro panel de herramienta encima" % mode, others == 0, str(others))
		# Capas: la tabla es UN objeto (sin sus piezas internas)
		var piezas := false
		for tr_ in root.find_children("*", "Tree", true, false):
			if not (tr_ as Control).is_visible_in_tree():
				continue
			var stack: Array = [(tr_ as Tree).get_root()]
			while not stack.is_empty():
				var it: TreeItem = stack.pop_back()
				if it == null:
					continue
				var tx := it.get_text(0)
				if tx.begins_with("Celda ") or tx.begins_with("Línea H") or tx.begins_with("Fila "):
					piezas = true
				for ch in it.get_children():
					stack.append(ch)
		K.check("%s: en Capas no salen las piezas internas de la tabla" % mode, not piezas)
		await K.shot("tabla_" + mode)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
