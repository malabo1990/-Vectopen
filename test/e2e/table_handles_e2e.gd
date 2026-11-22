## E2E tablas v2 (VAL-56): tiradores en el lienzo. Arrastrar la línea de una
## columna cambia su ancho; el borde inferior, el alto de las filas. En vivo,
## un paso de deshacer y el texto de las celdas se conserva. Ratón real.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func scr(g: Vector2) -> Vector2:
	return K.canvas.get_viewport().get_canvas_transform() * g

func drag(a_g: Vector2, b_g: Vector2) -> float:
	var a := scr(a_g)
	var b := scr(b_g)
	var m0 := InputEventMouseMotion.new()
	m0.position = a
	m0.global_position = a
	_send(m0)
	await K.frames(2)
	var d := InputEventMouseButton.new()
	d.position = a
	d.global_position = a
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(d)
	await K.frames(2)
	var mid := -1.0
	for i in range(1, 11):
		var m := InputEventMouseMotion.new()
		m.position = a.lerp(b, i / 10.0)
		m.global_position = m.position
		m.relative = (b - a) / 10.0
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(m)
		await process_frame
		if i == 5:
			mid = float((_t.get_meta("table")["col_w"] as Array)[0])
	var u := InputEventMouseButton.new()
	u.position = b
	u.global_position = b
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	_send(u)
	await K.frames(4)
	return mid

var _t: Node2D

func spec() -> Dictionary:
	return _t.get_meta("table")

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://table_handles")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(900, 600), "Tablas", Color.WHITE)
	_t = api.add_table(Rect2(100, 100, 600, 0), 4, 3, [["Mes", "Ventas", "Total"], ["Ene", "10", "100"], ["Feb", "12", "120"], ["Mar", "9", "90"]])
	await K.look_at(ab)
	if K.canvas.has_method("switch_tool"):
		K.canvas.switch_tool("move")
	api.select([_t])
	await K.frames(6)
	var w0 := float((spec()["col_w"] as Array)[0])
	var w1 := float((spec()["col_w"] as Array)[1])
	var rh0 := float(spec()["row_h"])
	K.check("tabla de 3 columnas de 200", absf(w0 - 200.0) < 0.5, str(w0))
	# Línea de la columna 1 (x = 200 desde la esquina) → +60
	var line_g: Vector2 = _t.to_global(Vector2(w0, rh0 * 1.5))
	var mid: float = await drag(line_g, line_g + Vector2(60, 0))
	var w0b := float((spec()["col_w"] as Array)[0])
	K.check("arrastrar la línea ensancha la columna 1 (+60)", absf(w0b - (w0 + 60.0)) < 1.5, "%.1f → %.1f" % [w0, w0b])
	K.check("en vivo: a mitad del gesto ya había cambiado", mid > w0 + 10.0 and mid < w0b, str(mid))
	K.check("la columna 2 no cambia", absf(float((spec()["col_w"] as Array)[1]) - w1) < 0.5)
	K.check("el texto de las celdas se conserva", String(api.table_data(_t)[1][0]) == "Ene" and String(api.table_data(_t)[0][2]) == "Total")
	K.check("la selección sigue en la tabla", api.selection() == [_t])
	api.undo()
	await K.frames(3)
	K.check("UN Ctrl+Z devuelve el ancho", absf(float((spec()["col_w"] as Array)[0]) - w0) < 0.5, str((spec()["col_w"] as Array)[0]))
	api.redo()
	await K.frames(3)
	K.check("rehacer vuelve a ensanchar", absf(float((spec()["col_w"] as Array)[0]) - (w0 + 60.0)) < 1.5)
	# Borde inferior: +40 px → cada una de 4 filas +10
	api.select([_t])
	await K.frames(4)
	var tw := 0.0
	for c in spec()["col_w"]:
		tw += float(c)
	var bottom_g: Vector2 = _t.to_global(Vector2(tw * 0.25, rh0 * 4))
	await drag(bottom_g, bottom_g + Vector2(0, 40))
	K.check("el borde inferior sube el alto de las filas (+10 cada una)", absf(float(spec()["row_h"]) - (rh0 + 10.0)) < 1.0, str(spec()["row_h"]))
	await K.shot("tabla")
	# Arrastrar el CUERPO de la tabla sigue moviéndola (no es un tirador)
	var p0: Vector2 = _t.global_position
	await drag(_t.to_global(Vector2(100, rh0 * 2.5)), _t.to_global(Vector2(130, rh0 * 2.5)))
	K.check("arrastrar dentro de una celda mueve la tabla", _t.global_position.distance_to(p0 + Vector2(30, 0)) < 2.0, str(_t.global_position - p0))
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
