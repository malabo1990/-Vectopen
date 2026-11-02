# =============================================================================
# UX-11 — «En Modern los trazos no se muestran.» Escenarios de uso real que la
# prueba básica (modern_strokes_visible_e2e) no cubría, en Modern y con
# comprobación de PÍXELES en pantalla:
#   A. tema oscuro;
#   B. tras quitar el trazo de una figura (grosor 0) y deseleccionarla;
#   C. tras poner el trazo de una figura transparente;
#   D. tras elegir un color de trazo igual al de la página (blanco).
# En cada uno se dibuja con el pincel y con la Bézier: el trazo nuevo debe
# tener grosor y color visibles y verse en pantalla.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/modern_strokes_scenarios_e2e.gd
# =============================================================================
extends "res://test/e2e/modern_strokes_visible_e2e.gd"

## Las etiquetas son «modern/escenario»: la barra es la de Modern.
func select_tool(mode: String, tool_id: String) -> void:
	await super.select_tool("modern" if mode.begins_with("modern") else mode, tool_id)

func _new_stroke_ok(tag: String, n: Node) -> void:
	if n == null:
		return
	if String(n.name) == "StrokeRender" and n.get_parent():
		n = n.get_parent()   # el trazo es el Line2D; StrokeRender es su render
	var wv = n.get("stroke_width") if "stroke_width" in n else n.get("width")
	var cv = n.get("stroke_color") if "stroke_color" in n else n.get("default_color")
	var info := "%s (%s)" % [n.name, n.get_class()]
	check("%s: grosor del trazo nuevo > 0" % tag, wv != null and float(wv) > 0.0, "%s w=%s" % [info, wv])
	check("%s: color del trazo nuevo visible" % tag, cv is Color and (cv as Color).a > 0.05, "%s c=%s" % [info, cv])
	# Que se vea SOBRE LA PÁGINA (no blanco sobre blanco).
	var bg: Color = artboard().fill_color
	if cv is Color:
		var lum := func(c: Color) -> float:
			var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
			return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)
		var a: float = lum.call(cv)
		var b2: float = lum.call(bg)
		var ratio := (maxf(a, b2) + 0.05) / (minf(a, b2) + 0.05)
		check("%s: el trazo contrasta con la página" % tag, ratio >= 1.3, "%.2f:1 trazo %s página %s" % [ratio, (cv as Color).to_html(false), bg.to_html(false)])

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var gui = root.get_node("GlobalUI")
	var tm = root.get_node("ThemeManager")
	var sm = root.get_node("SelectionManager")
	var ic = root.get_node("InspectorCore")
	gui.set_ui_mode("modern")
	await frames(30)
	var ab = artboard()
	var scenarios := [
		["A tema oscuro", func() -> void: tm.set_mode("dark")],
		["B trazo quitado", func() -> void:
			tm.set_mode("light")
			var r: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
			ab.add_child(r)
			r.owner = ab
			r.size = Vector2(80, 60)
			sm.set_selection([r])
			await frames(6)
			ic.apply("stroke_width", 0.0)
			await frames(4)
			sm.set_selection([])],
		["C trazo transparente", func() -> void:
			var r: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
			ab.add_child(r)
			r.owner = ab
			r.size = Vector2(80, 60)
			sm.set_selection([r])
			await frames(6)
			ic.apply("stroke_color", Color(0, 0, 0, 0))
			await frames(4)
			sm.set_selection([])],
		["D trazo blanco", func() -> void:
			var r: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
			ab.add_child(r)
			r.owner = ab
			r.size = Vector2(80, 60)
			sm.set_selection([r])
			await frames(6)
			ic.apply("stroke_color", Color.WHITE)
			await frames(4)
			sm.set_selection([])],
	]
	for sc in scenarios:
		var tag: String = "modern/" + String(sc[0])
		await (sc[1] as Callable).call()
		await frames(10)
		var b1 := await draw_brush(tag)
		_new_stroke_ok(tag + " pincel", b1)
		var b2 := await draw_bezier(tag)
		_new_stroke_ok(tag + " bézier", b2)
		await select_tool("modern", "select")
		for n in [b1, b2]:
			if n:
				n.queue_free()
		await frames(6)
	tm.set_mode("light")
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
