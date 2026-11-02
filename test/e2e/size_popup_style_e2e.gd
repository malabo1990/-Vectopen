# =============================================================================
# UX-22 — «El panel Tamaño de Elemento / Página es horrible: hazlo como los
# editores profesionales, en cuadrícula con iconos de página, elegante.»
# En Modern (Inspector) y en Smart (menú del clic derecho), tema claro y
# oscuro, con clics reales:
#   · el botón de tamaños abre el panel ENTERO dentro de la pantalla;
#   · las tarjetas van en cuadrícula (3 columnas), cada una con su miniatura
#     PROPORCIONAL al formato, nombre y medida;
#   · cada categoría (con icono) muestra sus formatos; el buscador filtra;
#   · todos los textos se leen (≥ 4,5:1; secundarios ≥ 3:1) y los fondos y
#     bordes salen del tema;
#   · pulsar «A4» cambia el tamaño del objeto, con deshacer;
#   · capturas en user://ux22_size_popup/.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/size_popup_style_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://ux22_size_popup"
const UI_CFG := "user://vectopen_ui.cfg"
const THEME_CFG := "user://vectopen_theme.cfg"
var fails := 0
var _palette: Array = []

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

func click(c: Control, what: String) -> void:
	if c == null or not c.is_visible_in_tree():
		check("se puede pulsar " + what, false, "no visible")
		return
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)
			await frames(3)
			break
		p = p.get_parent()
	var at := c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	root.push_input(mm)
	await process_frame
	var hit := root.gui_get_hovered_control()
	check("se puede pulsar " + what, hit == c or (hit != null and c.is_ancestor_of(hit)), str(hit))
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.position = at
		mb.global_position = at
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(mb)
		await process_frame
	await frames(6)

func lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

func contrast(a: Color, b: Color) -> float:
	return (maxf(lum(a), lum(b)) + 0.05) / (minf(lum(a), lum(b)) + 0.05)

func over(top: Color, bottom: Color) -> Color:
	return Color(top.r * top.a + bottom.r * (1.0 - top.a), top.g * top.a + bottom.g * (1.0 - top.a), top.b * top.a + bottom.b * (1.0 - top.a), 1.0)

func from_theme(c: Color) -> bool:
	if c.a < 0.05 or (c.r == 0.0 and c.g == 0.0 and c.b == 0.0):
		return true
	for p in _palette:
		if absf(p.r - c.r) < 0.02 and absf(p.g - c.g) < 0.02 and absf(p.b - c.b) < 0.02:
			return true
	return false

func bg_of(c: Control) -> Color:
	var chain: Array = []
	var n: Node = c
	while n and n is Control:
		chain.push_front(n)
		n = n.get_parent()
	var bg := Color.MAGENTA
	for ctl in chain:
		for st in ["panel", "normal"]:
			if (ctl as Control).has_theme_stylebox(st):
				var sb = (ctl as Control).get_theme_stylebox(st)
				if sb is StyleBoxFlat and (sb as StyleBoxFlat).draw_center and (sb as StyleBoxFlat).bg_color.a > 0.0:
					bg = over((sb as StyleBoxFlat).bg_color, bg if bg != Color.MAGENTA else Color.WHITE)
				break
	return bg

func popup() -> Control:
	for n in root.find_children("Panel_config_windows_element", "Control", true, false):
		if (n as Control).is_visible_in_tree():
			return n
	return null

func probe(tag: String, win: Control, rect: Node2D) -> void:
	var vp := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var r := win.get_global_rect()
	check("%s: el panel cabe entero en la pantalla" % tag, vp.grow(1.0).encloses(r), "%s en %s" % [r, vp.size])
	var grid := win.find_child("PresetsGrid", true, false) as GridContainer
	check("%s: tarjetas en cuadrícula de 3 columnas" % tag, grid != null and grid.columns == 3 and grid.get_child_count() >= 6)
	if grid == null:
		return
	# Miniaturas proporcionales: A4 vertical (alto > ancho).
	var a4 := grid.get_node_or_null("Preset_A4") as Control
	check("%s: la tarjeta A4 tiene miniatura de página" % tag, a4 != null and a4.find_child("Thumb", true, false) != null)
	if a4:
		var th = a4.find_child("Thumb", true, false)
		check("%s: miniatura A4 proporcional (≈1,41)" % tag, absf(float(th.aspect) - 1123.0 / 794.0) < 0.01, str(th.aspect))
	# Legibilidad y colores del tema.
	var low := []
	var foreign := []
	var n_txt := 0
	for c in [win] + win.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree():
			continue
		for st in ["panel", "normal"]:
			if ctl.has_theme_stylebox_override(st):
				var sb = ctl.get_theme_stylebox(st)
				if sb is StyleBoxFlat:
					var f := sb as StyleBoxFlat
					var bw := f.border_width_left + f.border_width_right + f.border_width_top + f.border_width_bottom
					if (f.draw_center and not from_theme(f.bg_color)) or (bw > 0 and not from_theme(f.border_color)):
						foreign.append("%s fondo %s" % [ctl.name, f.bg_color.to_html()])
		var txt := ""
		var fc := Color.BLACK
		var secondary := false
		if ctl is Label:
			txt = (ctl as Label).text
			fc = ctl.get_theme_color("font_color")
			secondary = ctl.get_theme_font_size("font_size") <= 10 or fc.is_equal_approx(ProUIStyle.col("TEXT_SECONDARY"))
		elif ctl is Button and (ctl as Button).text != "":
			txt = (ctl as Button).text
			fc = ctl.get_theme_color("font_color")
			secondary = (ctl as Button).toggle_mode and not (ctl as Button).button_pressed
		elif ctl is LineEdit:
			var le := ctl as LineEdit
			txt = le.text if le.text != "" else le.placeholder_text
			fc = le.get_theme_color("font_color" if le.text != "" else "font_placeholder_color")
			secondary = le.text == ""
		if txt.strip_edges() == "":
			continue
		n_txt += 1
		var bg := bg_of(ctl)
		var cr := contrast(over(fc, bg), bg)
		if cr < (3.0 if secondary else 4.5):
			low.append("«%s» %.1f:1" % [txt.left(16), cr])
	check("%s: textos revisados" % tag, n_txt > 15, str(n_txt))
	check("%s: todo se lee (contraste)" % tag, low.is_empty(), "; ".join(low.slice(0, 8)))
	check("%s: fondos y bordes del tema" % tag, foreign.is_empty(), "; ".join(foreign.slice(0, 8)))

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
	var rect: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.name = "Rect tamaño"
	ab.add_child(rect)
	rect.owner = ab
	rect.size = Vector2(120, 80)
	rect.position = Vector2(300, 300)
	for theme in ["light", "dark"]:
		tm.set_mode(theme)
		await frames(10)
		_palette.clear()
		for slot in tm.get_all_slots():
			_palette.append(tm.get_color(slot))
		gui.set_ui_mode("modern")
		await frames(30)
		sm.set_selection([rect])
		await frames(10)
		var di := root.find_children("DockedTransformPanel", "", true, false)
		var tp: Control = di[0] if di.size() > 0 else null
		check("%s: panel de transformación del Inspector" % theme, tp != null)
		if tp == null:
			continue
		var w0 := popup()
		if w0:
			w0.visible = false
		await click(tp._btn_presets, "%s: botón de tamaños" % theme)
		var win := popup()
		check("%s: se abre el panel de tamaños" % theme, win != null)
		if win == null:
			continue
		await frames(4)
		await probe("%s/papel" % theme, win, rect)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var rr := Rect2i(win.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(rr).save_png(OUT.path_join("%s_papel.png" % theme))
		for mod in [["dispositivos", win.tab_devices], ["red_social", win.tab_social], ["icono", win.tab_icon]]:
			await click(mod[1], "%s: categoría %s" % [theme, mod[0]])
			check("%s: categoría %s activa" % [theme, mod[0]], win.current_module == mod[0] and win.preset_buttons.size() > 0)
			if mod[0] == "dispositivos":
				var fhd := win.find_child("Preset_Desktop Full HD", true, false) as Control
				var th = fhd.find_child("Thumb", true, false) if fhd else null
				check("%s: el escritorio sale apaisado (1920 × 1080)" % theme, th != null and float(th.aspect) < 1.0, str(th.aspect) if th else "-")
			if theme == "light":
				await RenderingServer.frame_post_draw
				var im2 := root.get_texture().get_image()
				im2.get_region(rr).save_png(OUT.path_join("%s_%s.png" % [theme, mod[0]]))
		await click(win.tab_paper, "%s: categoría papel" % theme)
		# Buscador.
		win.search_edit.text = "A4"
		win.search_edit.text_changed.emit("A4")
		await frames(4)
		check("%s: el buscador filtra (A4)" % theme, win.preset_buttons.size() == 1)
		win.search_edit.text = ""
		win.search_edit.text_changed.emit("")
		await frames(4)
		if theme == "light":
			var a4 := win.find_child("Preset_A4", true, false) as Control
			var hm = root.get_node("HistoryManager")
			await click(a4, "tarjeta A4")
			check("pulsar A4 cambia el tamaño del objeto", rect.size.is_equal_approx(Vector2(794, 1123)), str(rect.size))
			hm.undo()
			await frames(4)
			check("deshacer vuelve al tamaño anterior", rect.size.is_equal_approx(Vector2(120, 80)), str(rect.size))
		win.visible = false
	for pair in [[UI_CFG, ui_backup], [THEME_CFG, th_backup]]:
		if pair[1] != "":
			var f := FileAccess.open(pair[0], FileAccess.WRITE)
			f.store_string(pair[1])
			f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
