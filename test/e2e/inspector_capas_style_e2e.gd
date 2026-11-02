# =============================================================================
# UX-15 — «En el Inspector hay muchas barras gris claro con texto blanco: no es
# la UI de Vectopen como la tiene Capas (la referencia de toda la UI).»
# Recorre TODOS los controles visibles del Inspector de Modern y del lateral de
# Pro, en tema claro y oscuro, con un rectángulo, un texto y un trazado
# seleccionados (y cada pestaña de Pro):
#   · contraste texto / fondo ≥ 4,5:1 (3:1 en textos secundarios pequeños,
#     interruptores apagados y controles desactivados);
#   · los fondos y bordes de campos y botones salen de los colores del tema
#     (los mismos que usa Capas), sin grises fijos;
#   · capturas en user://ux15_inspector/.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/inspector_capas_style_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://ux15_inspector"
const UI_CFG := "user://vectopen_ui.cfg"
const THEME_CFG := "user://vectopen_theme.cfg"

var fails := 0
var _palette: Array = []

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

func contrast(a: Color, b: Color) -> float:
	var la := lum(a)
	var lb := lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

## Mezcla un color semitransparente sobre su fondo (lo que se ve).
func over(top: Color, bottom: Color) -> Color:
	var a := top.a
	return Color(top.r * a + bottom.r * (1.0 - a), top.g * a + bottom.g * (1.0 - a), top.b * a + bottom.b * (1.0 - a), 1.0)

func from_theme(c: Color) -> bool:
	if c.a < 0.05:
		return true
	if c.r == 0.0 and c.g == 0.0 and c.b == 0.0:
		return true
	for p in _palette:
		if absf(p.r - c.r) < 0.02 and absf(p.g - c.g) < 0.02 and absf(p.b - c.b) < 0.02:
			return true
	return false

func is_cls(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls

## Caja que se ve en un control según su estado.
func box_of(ctl: Control) -> StyleBox:
	var st := "normal"
	if ctl is LineEdit:
		st = "normal" if (ctl as LineEdit).editable else "read_only"
	elif ctl is BaseButton and (ctl as BaseButton).disabled:
		st = "disabled"
	elif ctl is BaseButton and (ctl as BaseButton).toggle_mode and (ctl as BaseButton).button_pressed:
		st = "pressed"
	elif ctl is PanelContainer:
		st = "panel"
	if ctl.has_theme_stylebox(st):
		return ctl.get_theme_stylebox(st)
	return null

## Fondo efectivo: compone las cajas de los antepasados hasta el panel.
func bg_of(c: Control, page_bg: Color) -> Color:
	var chain: Array = []
	var n: Node = c
	while n and n is Control:
		chain.push_front(n)
		n = n.get_parent()
	var bg := page_bg
	for ctl in chain:
		var sb := box_of(ctl)
		if sb is StyleBoxFlat and (sb as StyleBoxFlat).draw_center:
			bg = over((sb as StyleBoxFlat).bg_color, bg)
	return bg

func text_of(ctl: Control) -> Array:
	# [texto, color, tamaño, secundario]
	if ctl is LineEdit:
		var le := ctl as LineEdit
		var t := le.text if le.text != "" else le.placeholder_text
		var key := "font_color" if le.editable else "font_uneditable_color"
		if le.text == "":
			key = "font_placeholder_color"
		return [t, le.get_theme_color(key), le.get_theme_font_size("font_size"), not le.editable or le.text == ""]
	if ctl is Label:
		var l := ctl as Label
		return [l.text, l.get_theme_color("font_color"), l.get_theme_font_size("font_size"), l.get_theme_font_size("font_size") <= 10]
	if ctl is Button:
		var b := ctl as Button
		var key := "font_disabled_color" if b.disabled else ("font_pressed_color" if b.toggle_mode and b.button_pressed else "font_color")
		var secondary := b.disabled or (b.toggle_mode and not b.button_pressed)
		return [b.text, b.get_theme_color(key), b.get_theme_font_size("font_size"), secondary]
	return ["", Color.BLACK, 0, false]

func probe(root_ctl: Control, tag: String) -> void:
	var tm := root.get_node("ThemeManager")
	var page_bg: Color = tm.get_color(tm.Slot.PANEL_BG)
	var low: Array = []
	var foreign: Array = []
	var n_checked := 0
	for c in [root_ctl] + root_ctl.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or ctl.get_global_rect().size.x < 2.0:
			continue
		var sb := box_of(ctl)
		# Las muestras de color (botón sin texto ni icono) llevan su color.
		var swatch: bool = ctl is Button and (ctl as Button).text == "" and (ctl as Button).icon == null
		if (ctl is LineEdit or ctl is Button or is_cls(ctl, "NumericField")) and sb is StyleBoxFlat and not swatch:
			var f := sb as StyleBoxFlat
			var bw := f.border_width_left + f.border_width_right + f.border_width_top + f.border_width_bottom
			if (f.draw_center and not from_theme(f.bg_color)) or (bw > 0 and not from_theme(f.border_color)):
				foreign.append("%s(%s) fondo %s borde %s" % [ctl.name, ctl.get_class(), f.bg_color.to_html(), f.border_color.to_html()])
		if not (ctl is LineEdit or ctl is Label or ctl is Button):
			continue
		var tx := text_of(ctl)
		if String(tx[0]).strip_edges() == "":
			continue
		n_checked += 1
		var fc: Color = tx[1]
		var bg := bg_of(ctl, page_bg)
		var shown := over(fc, bg)
		if ctl.modulate.a < 0.99 or ctl.self_modulate.a < 0.99:
			shown = over(Color(fc, fc.a * ctl.modulate.a * ctl.self_modulate.a), bg)
		var need := 3.0 if bool(tx[3]) else 4.5
		var cr := contrast(shown, bg)
		if cr < need:
			low.append("«%s» (%s) %.1f:1 texto %s fondo %s" % [String(tx[0]).left(14), ctl.name, cr, shown.to_html(false), bg.to_html(false)])
	check("%s: %d textos revisados" % [tag, n_checked], n_checked > 5)
	check("%s: se lee (contraste)" % tag, low.is_empty(), "; ".join(low.slice(0, 8)) + (" … +%d" % (low.size() - 8) if low.size() > 8 else ""))
	check("%s: fondos y bordes del tema (como Capas)" % tag, foreign.is_empty(), "; ".join(foreign.slice(0, 8)) + (" … +%d" % (foreign.size() - 8) if foreign.size() > 8 else ""))

func shot(ctl: Control, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var r := Rect2i(ctl.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x > 0 and r.size.y > 0:
		img = img.get_region(r)
	img.save_png(OUT.path_join(name + ".png"))

func panel_for(mode: String) -> Control:
	for n in root.find_children("*", "", true, false):
		var want := "DockedInspector" if mode == "modern" else "ProStudio"
		if is_cls(n, want) and (n as Control).is_visible_in_tree():
			return n
	return null

func _make_objects(ab: Node) -> Array:
	var rect: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.name = "Rect estilo"
	ab.add_child(rect)
	rect.owner = ab
	rect.size = Vector2(200, 140)
	rect.position = Vector2(300, 300)
	var path: Node2D = load("res://script_gdscript/shapes/VectorPath.gd").new()
	path.name = "Trazado estilo"
	var c := Curve2D.new()
	for p in [Vector2(0, 0), Vector2(120, -40), Vector2(240, 30)]:
		c.add_point(p)
	path.curve = c
	ab.add_child(path)
	path.owner = ab
	path.position = Vector2(600, 300)
	var out := [rect, path]
	var cv = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").get("api") if root.has_node("PluginManager") else null
	if api and api.has_method("add_text"):
		var t = api.add_text(Vector2(400, 600), "Texto de prueba")
		if t:
			out.append(t)
	return out

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	var th_backup := FileAccess.get_file_as_string(THEME_CFG) if FileAccess.file_exists(THEME_CFG) else ""
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
	var cv = get_first_node_in_group("_vectopen_canvas")
	var ab = cv.get_node("manager_script").get_active_artboard()
	var objs := _make_objects(ab)
	var only := OS.get_environment("UX15_ONLY")
	for theme in ["light", "dark"]:
		tm.set_mode(theme)
		await frames(12)
		_palette.clear()
		for slot in tm.get_all_slots():
			_palette.append(tm.get_color(slot))
		for mode in ["modern", "professional"]:
			gui.set_ui_mode(mode)
			await frames(30)
			for o in objs:
				var kind: String = String(o.name).split(" ")[0]
				if only != "" and not (kind in only):
					continue
				sm.set_selection([o])
				await frames(12)
				var panel := panel_for(mode)
				if panel == null:
					check("%s/%s: panel visible" % [theme, mode], false)
					continue
				if mode == "modern":
					await probe(panel, "%s/%s/%s" % [theme, mode, kind])
					await shot(panel, "%s_%s_%s" % [theme, mode, kind])
				else:
					for a in 3:
						for b in 3:
							panel._select_tab_a(a)
							panel._select_tab_b(b)
							await frames(6)
							await probe(panel, "%s/pro/%s/a%d-b%d" % [theme, kind, a, b])
							await shot(panel, "%s_pro_%s_a%d_b%d" % [theme, kind, a, b])
	# Ventana flotante de Pro (UX-09/14): barra de título del tema, no la de
	# Godot (gris oscuro con texto blanco).
	for theme in ["light", "dark"]:
		tm.set_mode(theme)
		await frames(10)
		_palette.clear()
		for slot in tm.get_all_slots():
			_palette.append(tm.get_color(slot))
		gui.set_ui_mode("professional")
		await frames(20)
		var pro := panel_for("professional")
		if pro == null:
			check("%s: lateral de Pro" % theme, false)
			continue
		pro.float_tab("b", "Efectos")
		await frames(10)
		var wins := pro.find_children("*", "Window", true, false).filter(func(w): return (w as Window).visible)
		check("%s: hay ventana flotante" % theme, wins.size() > 0)
		for w in wins:
			var sb = (w as Window).get_theme_stylebox("embedded_border")
			var tc := (w as Window).get_theme_color("title_color")
			var bg: Color = (sb as StyleBoxFlat).bg_color if sb is StyleBoxFlat else Color.MAGENTA
			check("%s: barra de título con color del tema" % theme, from_theme(bg), bg.to_html())
			check("%s: título legible" % theme, contrast(tc, bg) >= 4.5, "%.1f:1" % contrast(tc, bg))
			await shot(pro, "%s_pro_float" % theme)
		pro.dock_tab("Efectos")
		await frames(6)
	for o in objs:
		o.queue_free()
	for pair in [[UI_CFG, ui_backup], [THEME_CFG, th_backup]]:
		if pair[1] != "":
			var f := FileAccess.open(pair[0], FileAccess.WRITE)
			f.store_string(pair[1])
			f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
