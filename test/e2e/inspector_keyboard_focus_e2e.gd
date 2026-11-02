# =============================================================================
# UX-02 — «El teclado del Inspector se comporta como atajo de herramienta».
# Con un rectángulo seleccionado, en Modern y en Pro, pulsa con el ratón CADA
# campo de texto visible del Inspector (LineEdit / campos numéricos) y escribe
# «t», «v» y «p». Comprueba que:
#   · la herramienta no cambia;
#   · Escape suelta el campo y devuelve el teclado al lienzo;
#   · con el lienzo enfocado, las letras SÍ cambian de herramienta.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/inspector_keyboard_focus_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"

var fails := 0
var sel_rect: Node2D

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func motion(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.warp_mouse(at)
	root.push_input(mm)
	await process_frame

func button(at: Vector2, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = at
	mb.global_position = at
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(mb)
	await process_frame

## Tecla como la manda el sistema: con keycode, físico y carácter.
func key(code: Key, ch := "") -> void:
	for p in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.unicode = ch.unicode_at(0) if ch != "" else 0
		k.pressed = p
		root.push_input(k)
		await process_frame

func is_cls(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls

func canvas() -> Node:
	return get_first_node_in_group("_vectopen_canvas")

func tool_path() -> String:
	var c = canvas()
	return c.current_tool.get_script().resource_path.get_file() if c and c.current_tool else ""

func artboard() -> Node:
	var c = canvas()
	var m = c.get_node_or_null("manager_script") if c else null
	return m.get_active_artboard() if m and m.has_method("get_active_artboard") else null

## Campos de texto visibles dentro de `panel` (el LineEdit de cada campo).
func fields(panel: Node) -> Array:
	var out: Array = []
	for n in panel.find_children("*", "LineEdit", true, false):
		var le := n as LineEdit
		if le.is_visible_in_tree() and le.editable and le.get_global_rect().size.x > 8:
			out.append(le)
	# Campos numéricos: el usuario pulsa el campo, no su LineEdit interno.
	for n in panel.find_children("*", "", true, false):
		if is_cls(n, "NumericField") and (n as Control).is_visible_in_tree():
			out.append(n)
	return out

func field_name(c: Control) -> String:
	var t := c.tooltip_text
	var p := c.get_parent()
	return "%s/%s%s" % [p.name if p else "", c.name, (" «%s»" % t) if t != "" else ""]

## Entra en el campo con un clic real (doble clic en los numéricos: un clic
## suelto en ellos es «arrastrar para cambiar el valor»).
func enter(c: Control) -> void:
	var r := c.get_global_rect()
	var at := r.position + Vector2(minf(r.size.x * 0.5, r.size.x - 6), r.size.y * 0.5)
	await motion(at)
	await button(at, true)
	await button(at, false)
	await frames(3)
	if is_cls(c, "NumericField"):
		var le := c.get("_line_edit") as LineEdit
		if le == null or not le.is_visible_in_tree():
			if c.has_method("_enter_edit"):
				c.call("_enter_edit")
			await frames(3)

func probe(mode: String, panel: Node) -> void:
	var list := fields(panel)
	check("%s: hay campos de texto en el Inspector" % mode, list.size() >= 3, str(list.size()))
	var bad: Array = []
	var tested := 0
	for c in list:
		if not is_instance_valid(c) or not (c as Control).is_visible_in_tree():
			continue
		# Volver a «seleccionar» antes de cada campo.
		canvas().switch_tool("select")
		await frames(2)
		root.get_node("SelectionManager").set_selection([sel_rect])
		await frames(3)
		if not (c as Control).is_visible_in_tree():
			continue
		var t0 := tool_path()
		await enter(c)
		var fo := root.gui_get_focus_owner()
		if OS.has_environment("UX02_DEBUG"):
			print("DBG %s rect=%s hover=%s focus=%s" % [field_name(c), c.get_global_rect(), root.gui_get_hovered_control(), fo])
		if fo == null:
			continue        # el campo no toma foco (solo lectura)
		tested += 1
		for ch in ["t", "v", "p"]:
			await key(OS.find_keycode_from_string(ch.to_upper()), ch)
		await frames(2)
		var t1 := tool_path()
		if t1 != t0:
			bad.append("%s → %s" % [field_name(c), t1])
		await key(KEY_ESCAPE)
		await frames(3)
		# El Escape no deja el texto escrito a medias como valor.
	check("%s: escribir t/v/p en %d campos no cambia de herramienta" % [mode, tested], bad.is_empty(), "; ".join(bad.slice(0, 8)))
	check("%s: se probó un número razonable de campos" % mode, tested >= 3, str(tested))

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var gui = root.get_node("GlobalUI")
	var ab := artboard()
	var rect: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.name = "Rect teclado"
	ab.add_child(rect)
	rect.owner = ab
	rect.size = Vector2(200, 140)
	rect.position = Vector2(300, 300)
	rect.stroke_width = 4.0
	sel_rect = rect
	var name0 := String(rect.name)

	for mode in ["modern", "professional"]:
		gui.set_ui_mode(mode)
		await frames(30)
		root.get_node("SelectionManager").set_selection([rect])
		await frames(10)
		var panel: Node = null
		var cls := "DockedInspector" if mode == "modern" else "ProStudio"
		for n in root.find_children("*", "", true, false):
			if is_cls(n, cls) and (n as Control).is_visible_in_tree():
				panel = n
		check("%s: Inspector visible" % mode, panel != null)
		if panel == null:
			continue
		await probe(mode, panel)

		# Escape devuelve el teclado al lienzo y las letras vuelven a ser atajos.
		var any := fields(panel)
		if not any.is_empty():
			await enter(any[0])
			await key(KEY_ESCAPE)
			await frames(4)
			var fo := root.gui_get_focus_owner()
			check("%s: Escape suelta el campo" % mode,
				fo == null or not (fo is LineEdit or fo is TextEdit or is_cls(fo, "NumericField")), str(fo))
		root.get_node("SelectionManager").set_selection([rect])
		await frames(4)
		canvas().switch_tool("select")
		await frames(2)
		await key(KEY_B, "b")
		await frames(4)
		check("%s: con el lienzo enfocado «b» activa el pincel" % mode, tool_path().to_lower().contains("brush"), tool_path())
		await key(KEY_V, "v")
		await frames(4)
		check("%s: «v» vuelve a seleccionar" % mode, not tool_path().to_lower().contains("brush"), tool_path())
		root.get_node("SelectionManager").set_selection([rect])
		await frames(4)

	check("el rectángulo sigue existiendo", is_instance_valid(rect) and rect.is_inside_tree())
	if is_instance_valid(rect):
		rect.queue_free()
	await frames(4)
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
