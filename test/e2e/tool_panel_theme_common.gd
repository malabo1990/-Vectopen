# =============================================================================
# Base de las pruebas UX-06 (Pincel) y UX-07 (Bézier): el panel de herramienta
# en tema CLARO y OSCURO, en Smart, Modern y Pro. Comprueba:
#   · el script y la escena del panel no tienen colores escritos a mano;
#   · cada fondo / borde / texto que se ve sale de un color del tema actual;
#   · se lee: contraste de cada texto con su fondo (≥ 4,5:1; secundarios ≥ 3:1);
#   · estructura como Capas: letra ≤ 13 px, cabeceras de sección en versalitas.
# Captura cada combinación en user://<OUT>/.
# Las pruebas concretas solo dicen qué panel y qué herramienta.
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const THEME_CFG := "user://vectopen_theme.cfg"

var PANEL_NAME := ""          # nombre del nodo del panel ("brush", "bezier")
var TOOL_ID := ""             # herramienta que lo abre
var SCRIPT_PATH := ""
var SCENE_PATH := ""
var OUT := ""

var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(220.0).timeout.connect(func() -> void:
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

func lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

func contrast(a: Color, b: Color) -> float:
	var la := lum(a)
	var lb := lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

## Colores del tema actual (todos los huecos).
func theme_colors() -> Array:
	var tm := root.get_node("ThemeManager")
	var out: Array = []
	for slot in tm.get_all_slots():
		out.append(tm.get_color(slot))
	return out

func from_theme(c: Color, palette: Array) -> bool:
	if c.a == 0.0:
		return true
	if c.r == 0.0 and c.g == 0.0 and c.b == 0.0:
		return true                       # sombras (negro con alfa)
	for p in palette:
		if absf(p.r - c.r) < 0.02 and absf(p.g - c.g) < 0.02 and absf(p.b - c.b) < 0.02:
			return true
	return false

## Fondo efectivo de un control: el del primer antepasado con caja plana.
func bg_of(c: Control, fallback: Color) -> Color:
	var n: Node = c
	while n and n is Control:
		var ctl := n as Control
		for st in ["panel", "normal"]:
			if ctl.has_theme_stylebox_override(st):
				var sb := ctl.get_theme_stylebox(st)
				if sb is StyleBoxFlat and (sb as StyleBoxFlat).bg_color.a > 0.5:
					return (sb as StyleBoxFlat).bg_color
		n = n.get_parent()
	return fallback

func find_panel() -> Control:
	for c in root.find_children(PANEL_NAME, "Control", true, false):
		if c.get_script() and String(c.get_script().resource_path) == SCRIPT_PATH:
			return c
	return null

func open_tool(mode: String) -> void:
	var cv = get_first_node_in_group("_vectopen_canvas")
	if mode == "modern":
		var bar := root.find_children("*", "PanelContainer", true, false).filter(func(n): return n.get_script() and n.get_script().get_global_name() == "ModernBottomToolbar")
		if bar.size() > 0:
			bar[0]._buttons[TOOL_ID].pressed.emit()
	else:
		var b := current_scene.find_child("button_tool" + TOOL_ID, true, false) as Button
		if b:
			b.pressed.emit()
	await frames(10)
	if cv and cv.current_tool == null:
		cv.switch_tool(TOOL_ID)

func probe(theme: String, mode: String) -> void:
	var p := find_panel()
	check("%s/%s: panel visible" % [theme, mode], p != null and p.is_visible_in_tree())
	if p == null or not p.is_visible_in_tree():
		return
	var palette := theme_colors()
	var page_bg: Color = root.get_node("ThemeManager").get_color(root.get_node("ThemeManager").Slot.PANEL_BG)
	var not_theme: Array = []
	var low: Array = []
	var big: Array = []
	for c in [p] + p.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree():
			continue
		for st in ["panel", "normal", "hover", "pressed"]:
			if ctl.has_theme_stylebox_override(st):
				var sb := ctl.get_theme_stylebox(st)
				if sb is StyleBoxFlat:
					var f := sb as StyleBoxFlat
					var bw := f.border_width_left + f.border_width_right + f.border_width_top + f.border_width_bottom
					if not from_theme(f.bg_color, palette) or (bw > 0 and not from_theme(f.border_color, palette)):
						not_theme.append("%s.%s %s/%s" % [ctl.name, st, f.bg_color, f.border_color])
		if ctl is Label or ctl is Button or ctl is CheckBox:
			var txt := (ctl as Label).text if ctl is Label else (ctl as Button).text
			if txt.strip_edges() == "":
				continue
			var fc := ctl.get_theme_color("font_color")
			if ctl.modulate != Color.WHITE:
				not_theme.append("%s modulate %s" % [ctl.name, ctl.modulate])
			if ctl.has_theme_color_override("font_color") and not from_theme(fc, palette):
				not_theme.append("%s texto %s" % [ctl.name, fc])
			var bg := bg_of(ctl, page_bg)
			var need := 3.0 if (ctl is Label and ctl.get_theme_font_size("font_size") <= 10) or (ctl is Button and ctl.toggle_mode and not (ctl as Button).button_pressed) else 4.5
			var cr := contrast(fc, bg)
			if cr < need:
				low.append("«%s» %.1f:1" % [txt.left(18), cr])
			if ctl.get_theme_font_size("font_size") > 13:
				big.append("«%s» %d px" % [txt.left(18), ctl.get_theme_font_size("font_size")])
	check("%s/%s: todos los colores salen del tema" % [theme, mode], not_theme.is_empty(), "; ".join(not_theme.slice(0, 6)))
	check("%s/%s: se lee (contraste)" % [theme, mode], low.is_empty(), "; ".join(low.slice(0, 6)))
	check("%s/%s: letra como Capas (≤ 13 px)" % [theme, mode], big.is_empty(), "; ".join(big.slice(0, 6)))
	await extra_checks(p, theme, mode)
	await shot("%s_%s" % [theme, mode])

## Comprobaciones propias de cada panel (las pruebas concretas las añaden).
func extra_checks(_panel: Control, _theme: String, _mode: String) -> void:
	pass

## Sin emojis en el código del panel (iconos SVG o dibujados del tema).
func no_emoji(path: String) -> void:
	var src := FileAccess.get_file_as_string(path)
	var found := []
	for i in src.length():
		var cp := src.unicode_at(i)
		if (cp >= 0x1F300 and cp <= 0x1FAFF) or (cp >= 0x2600 and cp <= 0x27BF):
			found.append(src.substr(i, 1))
	check("sin emojis en %s" % path.get_file(), found.is_empty(), " ".join(found.slice(0, 10)))

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	var th_backup := FileAccess.get_file_as_string(THEME_CFG) if FileAccess.file_exists(THEME_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# Sin colores escritos a mano en el código ni en la escena del panel.
	for path in [SCRIPT_PATH, SCENE_PATH]:
		var src := FileAccess.get_file_as_string(path)
		var n := src.count("Color(")
		check("sin colores literales en %s" % path.get_file(), n == 0, "%d «Color(»" % n)
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
	for theme in ["light", "dark"]:
		tm.set_mode(theme)
		await frames(10)
		for mode in ["smart", "modern", "professional"]:
			gui.set_ui_mode(mode)
			await frames(30)
			await open_tool(mode)
			await frames(6)
			await probe(theme, mode)
	if th_backup != "":
		var f0 := FileAccess.open(THEME_CFG, FileAccess.WRITE)
		f0.store_string(th_backup)
		f0.close()
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
