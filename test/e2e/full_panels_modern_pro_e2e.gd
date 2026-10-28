# =============================================================================
# PRUEBA DE UI REAL: en Modern y Pro TODO está en el panel derecho.
# Pedidos del usuario:
#  - "en modern y pro falta: filtro, effects, script, vectorizar, texto completo"
#  - "nuevas herramientas en la barra no tiene sentido: el inspector ya tiene
#    texto, efectos, trazo… añadir filtro y vectorizar" / "en pro quitar el
#    panel inspector de Smart: todo en el panel derecho, estilo Figma
#    (Modern) y Affinity (Pro)".
#  - "fallos de color de texto para temas" (panel acoplado ilegible en claro).
# Comprueba, con clics reales y en tema claro y oscuro:
#  - la barra superior ya no tiene Efectos/Tipografía (solo Vista previa…);
#  - texto → tipografía COMPLETA en el lateral; filas reducidas ocultas;
#  - figura → lista COMPLETA de efectos + sección Filtros (plegable);
#  - imagen → sección Vectorizar (solo con imagen);
#  - no se abre ningún panel flotante de Smart;
#  - textos legibles en los paneles acoplados (contraste con el fondo).
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/full_panels_modern_pro_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const THEME_CFG := "user://vectopen_theme.cfg"
const OUT := "user://full_panels"
const EXPECTED_CHECKS := 80
var fails := 0
var checks := 0
var api = null
var made: Array = []
var theme_tag := ""

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(theme_tag + "_" + name + ".png"))

func push_mouse(at: Vector2, pressed: Variant = null) -> void:
	var ev: InputEvent
	if pressed == null:
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.global_position = at
		ev = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.position = at
		mb.global_position = at
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev = mb
	root.push_input(ev)
	await process_frame

func click(c: Control, what: String) -> void:
	if c == null or not c.is_visible_in_tree():
		check("se ve y se puede pulsar: " + what, false, "no visible")
		return
	var at := c.get_global_rect().get_center()
	await push_mouse(at)
	var hit := root.gui_get_hovered_control()
	check("se puede pulsar: " + what, hit == c or (hit != null and c.is_ancestor_of(hit)), str(hit))
	await push_mouse(at, true)
	await push_mouse(at, false)
	await frames(8)

func is_cls(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls

func node(name: String) -> Control:
	return root.find_child(name, true, false) as Control

func select(n: Node) -> void:
	root.get_node("SelectionManager").set_selection([n])
	await frames(10)

## Ningún panel flotante de Smart abierto (todo va en el lateral).
func no_smart_floating(mode: String) -> void:
	for n in ["panel__effects", "tool_in_Mouse"]:
		var p := node(n)
		var tgt: Control = p.get("target_node") if p and p.get("target_node") is Control else p
		check("%s: no se abre el panel flotante de Smart %s" % [mode, n], tgt == null or not tgt.visible)

## Contraste del texto de las etiquetas visibles de `area` con `bg`.
func readable(mode: String, what: String, area: Control, bg: Color) -> void:
	var worst := 99.0
	var worst_txt := ""
	for l in area.find_children("*", "Label", true, false):
		var lab := l as Label
		if not lab.is_visible_in_tree() or lab.text.strip_edges() == "":
			continue
		var c: Color = lab.get_theme_color("font_color") * lab.modulate
		var d := absf(c.get_luminance() - bg.get_luminance())
		if d < worst:
			worst = d
			worst_txt = "%s %s" % [lab.text.substr(0, 20), c]
	check("%s: textos legibles en %s" % [mode, what], worst >= 0.3, "peor contraste %.2f: %s" % [worst, worst_txt])

func run_mode(mode: String, bar: Control, side: Control, text: Node2D, rect: Node2D, img: Node2D) -> void:
	var gui = root.get_node("GlobalUI")
	gui.set_ui_mode(mode)
	await frames(30)
	check("%s: la barra ya no tiene botón de Efectos" % mode, bar.find_child("BtnEffects", true, false) == null)
	check("%s: la barra ya no tiene botón de Tipografía" % mode, bar.find_child("BtnTypography", true, false) == null)
	check("%s: la barra conserva Vista previa" % mode, bar.find_child("BtnPreview", true, false) != null)

	# TEXTO → tipografía completa en el lateral.
	await select(text)
	if mode == "professional":
		side._select_tab_b(1)
		await frames(6)
	var ft := side.find_child("FullTypography", true, false) as Control
	check("%s: texto → tipografía COMPLETA en el lateral" % mode, ft != null and ft.is_visible_in_tree())
	if ft:
		check("%s: dentro del lateral derecho" % mode, side.get_global_rect().encloses(ft.get_global_rect().grow(-1)) or side.is_ancestor_of(ft))
		var legacy := ft.get_parent().get_node_or_null("LegacyHidden") as Control
		check("%s: las filas reducidas de antes no se ven" % mode, legacy == null or not legacy.is_visible_in_tree())
		var dup := false
		for l in ft.find_children("*", "Label", true, false):
			if (l as Label).is_visible_in_tree() and (l as Label).text.contains("TIPOGRAF"):
				dup = true
		check("%s: sin título repetido «TIPOGRAFÍA / TEXT»" % mode, not dup)
	await shot("%s_texto" % mode)

	# FIGURA → efectos completos + filtros plegables.
	await select(rect)
	if mode == "professional":
		side._select_tab_b(2)
		await frames(6)
	if mode == "modern":
		check("modern: texto → figura refresca el inspector (no sigue «Texto»)", side.lbl_title.text != "Texto" and side.lbl_title.text != tr("Text"), side.lbl_title.text)
		var fh := side.sec_fill.get_child(0).get_child(0) as Label
		check("modern: con una figura el título vuelve a «Relleno»", fh.text == tr("FILL"), fh.text)
		check("modern: la tipografía no sale con una figura", not side.sec_typography.is_visible_in_tree())
	var fe := side.find_child("FullEffects", true, false) as Control
	check("%s: figura → lista COMPLETA de efectos en el lateral" % mode, fe != null and fe.is_visible_in_tree())
	var sf := side.find_child("SecFilters", true, false) as Control
	check("%s: sección Filtros visible con selección" % mode, sf != null and sf.is_visible_in_tree())
	var sv := side.find_child("SecVectorize", true, false) as Control
	check("%s: Vectorizar oculto si no hay imagen" % mode, sv != null and not sv.is_visible_in_tree())
	if sf:
		if not sf.is_open():
			await click(sf.get_node("Header") as Control, "%s: desplegar Filtros" % mode)
		var fc := sf.find_child("FiltersContent", true, false) as Control
		check("%s: Filtros desplegado muestra su contenido" % mode, fc != null and fc.is_visible_in_tree() and fc.size.y > 40)
		await shot("%s_efectos_filtros" % mode)
		await click(sf.get_node("Header") as Control, "%s: plegar Filtros" % mode)
		check("%s: Filtros se pliega" % mode, fc == null or not fc.is_visible_in_tree())
	no_smart_floating(mode)

	# IMAGEN → Vectorizar.
	if img:
		await select(img)
		if mode == "professional":
			side._select_tab_b(2)
			await frames(6)
		sv = side.find_child("SecVectorize", true, false) as Control
		check("%s: imagen → sección Vectorizar visible" % mode, sv != null and sv.is_visible_in_tree())
		var vc := sv.find_child("VectorizeContent", true, false) as Control if sv else null
		check("%s: Vectorizar abierto con su contenido" % mode, vc != null and vc.is_visible_in_tree())
		await shot("%s_vectorizar" % mode)

	# Pestaña Páginas (Sangrado / Márgenes): legible con el tema actual.
	var ls := node("LayersSystem")
	if ls and ls.has_method("_switch_left_tab"):
		ls._switch_left_tab("paginas")
		await frames(6)
		var pp = ls.get("_paginas_panel")
		var tm0 = root.get_node("ThemeManager")
		if pp:
			readable(mode, "pestaña Páginas", pp, tm0.get_color(tm0.Slot.PANEL_SURFACE))
		ls._switch_left_tab("capas")
		await frames(4)
	# Panel Bézier acoplado: legible con el tema actual.
	root.get_node("SelectionManager").set_selection([])
	root.get_node("GlobalEvents").emit_safe("request_tool_panel", "bezier")
	await frames(8)
	var bez := node("bezier")
	var tm = root.get_node("ThemeManager")
	if bez and bez.is_visible_in_tree():
		readable(mode, "panel Bézier acoplado", bez, tm.get_color(tm.Slot.PANEL_SURFACE))
		await shot("%s_bezier" % mode)
	else:
		check("%s: panel Bézier acoplado visible" % mode, false)
	root.get_node("GlobalEvents").emit_safe("request_tool_panel", "")
	await frames(4)

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	var theme_backup := FileAccess.get_file_as_string(THEME_CFG) if FileAccess.file_exists(THEME_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	api = load("res://script_gdscript/api/vectopen_api.gd").new(root)
	var text: Node2D = api.add_text(Vector2(120, 200), "Hola mundo", 32)
	var rect: Node2D = api.add_rect(Vector2(400, 500), Vector2(160, 110))
	var im := Image.create(64, 48, false, Image.FORMAT_RGBA8)
	im.fill(Color(0.2, 0.5, 0.9))
	var img: Node2D = api.add_image(im, Vector2(400, 750))
	made = [text, rect, img]
	check("se crean texto, figura e imagen", text != null and rect != null, "%s %s %s" % [text, rect, img])

	var tm = root.get_node("ThemeManager")
	var themes := ["light", "dark"]
	for th in themes:
		theme_tag = th
		if th != "":
			tm.set_mode(th)
			await frames(20)
		root.get_node("GlobalUI").set_ui_mode("modern")
		await run_mode("modern", node("ModernTopBar"), node("DockedInspector"), text, rect, img)
		await run_mode("professional", node("ProTopBar"), node("ProStudio"), text, rect, img)

	for n in made:
		if is_instance_valid(n):
			n.queue_free()
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	if theme_backup != "":
		var f2 := FileAccess.open(THEME_CFG, FileAccess.WRITE)
		f2.store_string(theme_backup)
		f2.close()
	if checks < EXPECTED_CHECKS:
		check("el test hizo todas sus comprobaciones", false, "%d de %d" % [checks, EXPECTED_CHECKS])
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
