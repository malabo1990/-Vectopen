# =============================================================================
# PRUEBA DE UI REAL (clics de ratón): flujo de figuras en Modern y Pro.
# Pedido del usuario: "en dock aparece 3 polígonos (cuadrado, círculo y
# estrella) pero en smart solo 1 y muestra un panel polígonos para elegir...
# en modern debería hacer lo mismo en inspector" y "cuando seleccionado el
# círculo no hay propiedad ni detalles".
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/modern_shapes_flow_e2e.gd
# Capturas en user://modern_shapes_flow/ para revisar a ojo.
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const OUT := "user://modern_shapes_flow"
const DVEC2_PATH := "res://script_gdscript/core/DVec2.gd"

var fails := 0

func _init() -> void:
	_run.call_deferred()
	# Vigilante: si algo se cuelga, cerrar Godot igualmente. Con `timeout`
	# solo moría el lanzador de flatpak y Godot seguía vivo escribiendo el
	# registro (llenó /tmp y dejó una ventana negra en la Huion).
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

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

func move(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	root.push_input(ev)
	await process_frame

func button(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = at
	ev.global_position = at
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(ev)
	await process_frame

## Clic de verdad en el centro del control (falla si algo lo tapa).
func click(c: Control, what: String) -> void:
	if c == null or not c.is_visible_in_tree():
		check("se puede pulsar " + what, false, "no visible")
		return
	var at := c.get_global_rect().get_center()
	await move(at)
	var hit := root.gui_get_hovered_control()
	var reach := hit == c or (hit != null and c.is_ancestor_of(hit))
	check("se puede pulsar " + what, reach, str(hit))
	await button(at, true)
	await button(at, false)
	await frames(6)

## Sin nombres de clase en este script: un -s se compila antes que los
## autoloads y referenciarlas rompía la recarga de PanelPolygon.
func is_cls(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls

func panels(main: Node) -> Dictionary:
	var out := {}
	for n in ["polygon", "text", "Selector", "bezier", "brush"]:
		for c in root.find_children(n, "Control", true, false):
			if (c is PanelContainer or c.get_script() != null) and c.get_parent() and (c.get_parent().name == "Herramientas" or c.get_parent().name == "ToolPanelSlot"):
				out[n] = c
	return out

func visible_panels(p: Dictionary) -> Array:
	var out := []
	for n in p:
		if (p[n] as Control).is_visible_in_tree():
			out.append(n)
	return out

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var main := current_scene.find_child("main", true, false) as Control
	var gui = root.get_node("GlobalUI")
	var vw: float = root.get_visible_rect().size.x

	# ── MODERN ───────────────────────────────────────────────────────────────
	gui.set_ui_mode("modern")
	await frames(30)
	var bar := root.find_children("*", "PanelContainer", true, false).filter(func(n): return is_cls(n, "ModernBottomToolbar"))
	var tb = bar[0] if bar.size() > 0 else null
	check("modern: barra inferior presente", tb != null and tb.is_visible_in_tree())
	if tb == null:
		_finish(ui_backup)
		return
	check("modern: un solo botón de figuras (sin rect/elipse/estrella sueltos)",
		tb._buttons.has("shapes") and not tb._buttons.has("rectangle") and not tb._buttons.has("ellipse") and not tb._buttons.has("star"),
		str(tb._buttons.keys()))
	check("modern: barra inferior con selección de nodos e imagen",
		tb._buttons.has("nodeselection") and tb._buttons.has("image"), str(tb._buttons.keys()))
	var col := main.find_child("Herramientas", true, false) as Control
	check("modern: sin barra de herramientas izquierda (solo la de abajo)",
		col != null and not col.is_visible_in_tree())
	var p := panels(main)
	check("modern: encontrados los 5 paneles", p.size() == 5, str(p.keys()))

	await click(tb._buttons["shapes"], "botón figuras")
	var poly = p.get("polygon")
	check("modern: figuras abre el panel de polígonos", poly != null and poly.is_visible_in_tree())
	check("modern: el panel está en el inspector derecho",
		poly != null and poly.get_global_rect().position.x > vw * 0.75, str(poly.get_global_rect()) if poly else "")
	check("modern: solo un panel visible", visible_panels(p) == ["polygon"], str(visible_panels(p)))
	check("modern: herramienta de figura activa", tb._active_tool == poly.current_tool, tb._active_tool)
	check("modern: botón figuras resaltado", tb._button_of(tb._active_tool) == "shapes", "%s → %s" % [tb._active_tool, tb._button_of(tb._active_tool)])
	if poly:
		var fs: int = poly._btn_create.get_theme_font_size("font_size")
		check("modern: «Crear en el centro» con letra del panel (11)", fs == 11, str(fs))
	await shot("modern_1_figuras")

	# Elegir círculo en el panel: la herramienta pasa a elipse, el panel sigue.
	if poly:
		await click(poly._tabs[3], "pestaña Elipse")
		var ce = get_first_node_in_group("_vectopen_canvas")
		var tool_path: String = ce.current_tool.get_script().resource_path if ce and ce.current_tool else ""
		check("modern: elipse activa la herramienta de círculo", tool_path.get_file().to_lower().contains("circle"), tool_path)
		check("modern: el panel sigue abierto con Elipse", poly.is_visible_in_tree() and poly.kind == 3)
		check("modern: el botón figuras sigue resaltado", tb._button_of(tb._active_tool) == "shapes", tb._active_tool)
		await shot("modern_2_elipse")

		# Crear un círculo y seleccionarlo: el inspector muestra sus propiedades.
		var shape = poly.create_in_center()
		await frames(10)
		check("modern: se crea el círculo", is_instance_valid(shape))
		var ic = root.get_node_or_null("InspectorCore")
		var props: Dictionary = ic.current_props() if ic else {}
		check("modern: el círculo queda seleccionado con propiedades", props.size() > 3, str(props.size()))
		var di := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "DockedInspector"))
		if di.size() > 0:
			var d = di[0]
			check("modern: título del inspector no es «Page»", d.lbl_title.text != "Page" and d.lbl_title.text != tr("Page"), d.lbl_title.text)
			await frames(4)
			check("modern: la geometría de elipse no sale dos veces (panel + sección)",
				not d.sec_parametric_circle.is_visible_in_tree())
			check("modern: «1 objeto seleccionado» en español", d.lbl_selection.text == tr("1 object selected") and d.lbl_selection.text != "1 object selected", d.lbl_selection.text)
			var tp = d.get("transform_panel")
			if tp and "_corners_block" in tp and not tp._corners_block.is_empty():
				check("modern: un círculo no muestra esquinas TL/TR/BL/BR", not tp._corners_block[0].is_visible_in_tree())
		await shot("modern_3_circulo_seleccionado")
		if is_instance_valid(shape):
			var hm = root.get_node_or_null("HistoryManager")
			if hm and hm.has_method("undo"):
				hm.undo()
			await frames(5)

	# Pestaña Formas: corazón, flecha, cruz, luna, rayo, bocadillo, nube.
	if poly:
		await click(tb._buttons["shapes"], "botón figuras (otra vez)")
		await click(poly._tabs[5], "pestaña Formas")
		check("modern: pestaña Formas activa", poly.kind == 5)
		var made := []
		for chip in poly._chips:
			await click(chip, "forma " + chip.tooltip_text)
			var sel: Array = root.get_node("InspectorCore").selection()
			if sel.size() == 1 and String(sel[0].get_meta("shape_kind", "")).begins_with("custom_"):
				made.append(sel[0])
		check("modern: se crean las 8 formas", made.size() == 8, str(made.size()))
		var pw: Dictionary = root.get_node("InspectorCore").current_props()
		check("modern: la forma creada tiene tamaño en el inspector (no 0×0)",
			float(pw.get("width", {}).get("value", 0.0)) > 50.0 and float(pw.get("height", {}).get("value", 0.0)) > 50.0,
			"%s × %s" % [pw.get("width", {}).get("value"), pw.get("height", {}).get("value")])
		var ok_geom := true
		for m in made:
			if m.get_doc_vertices().size() < 4:
				ok_geom = false
		check("modern: cada forma tiene contorno", ok_geom)
		# Repartirlas para verlas en la captura.
		var DV = load(DVEC2_PATH)
		for i in made.size():
			var mm = made[i]
			mm.set_doc_position(DV.from_v2(Vector2(140 + (i % 4) * 170, 300 + (i / 4) * 200)))
		await frames(6)
		await shot("modern_5_formas")
		for m in made:
			if is_instance_valid(m):
				m.queue_free()
		await frames(4)

	# Pincel: cambia el panel (no se apilan).
	await click(tb._buttons["brush"], "botón pincel")
	check("modern: pincel muestra SOLO su panel", visible_panels(p) == ["brush"], str(visible_panels(p)))
	await shot("modern_4_pincel")
	await click(tb._buttons["text"], "botón texto")
	check("modern: texto muestra SOLO su panel", visible_panels(p) == ["text"], str(visible_panels(p)))
	await click(tb._buttons["select"], "botón seleccionar")
	check("modern: seleccionar cierra los paneles de herramienta", visible_panels(p).is_empty(), str(visible_panels(p)))

	# ── PRO: botones de la columna izquierda, un panel a la vez ────────────
	gui.set_ui_mode("professional")
	await frames(30)
	var b_shapes := main.find_child("button_toolbshapes", true, false) as Button
	var b_bez := main.find_child("button_toolbezier", true, false) as Button
	await click(b_shapes, "pro: botón figuras")
	check("pro: polígonos en el lateral derecho", poly != null and poly.is_visible_in_tree() and poly.get_global_rect().position.x > vw * 0.75)
	if poly:
		var fs2: int = poly._btn_create.get_theme_font_size("font_size")
		check("pro: «Crear en el centro» con letra 11", fs2 == 11, str(fs2))
	await shot("pro_1_figuras")
	await click(b_bez, "pro: botón bézier")
	check("pro: bézier sustituye a polígonos", visible_panels(p) == ["bezier"], str(visible_panels(p)))
	await shot("pro_2_bezier")
	for n in p:
		(p[n] as Control).visible = false

	# ── SMART: sigue como estaba (flotante, se pueden abrir a la vez) ──────
	gui.set_ui_mode("smart")
	await frames(30)
	await click(main.find_child("button_toolbshapes", true, false) as Button, "smart: botón figuras")
	check("smart: polígonos flota en Herramientas", poly != null and poly.get_parent().name == "Herramientas" and poly.is_visible_in_tree())
	if poly:
		check("smart: conserva su marco", not (poly.get_theme_stylebox("panel") is StyleBoxEmpty))
	await shot("smart_1_figuras")
	for n in p:
		(p[n] as Control).visible = false
	_finish(ui_backup)

func _finish(ui_backup: String) -> void:
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
