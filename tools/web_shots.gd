# =============================================================================
# Capturas para la web: monta un diseño de ejemplo con la API de scripts y
# guarda una captura de cada interfaz (Smart, Modern, Pro) en user://web_shots/.
# Restaura el modo de UI del usuario al terminar. No toca el documento real
# (el diseño vive solo en esta sesión y no se guarda).
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://tools/web_shots.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const OUT := "user://web_shots"

func _init() -> void:
	create_timer(150.0).timeout.connect(func(): print("WATCHDOG"); quit(2))
	_run.call_deferred()

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))
	print("SHOT ", name)

func grad(colors: Array, offsets: Array = []) -> Gradient:
	var g := Gradient.new()
	var off := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		cols.append(colors[i])
		off.append(offsets[i] if i < offsets.size() else float(i) / max(1, colors.size() - 1))
	g.offsets = off
	g.colors = cols
	return g

func set_grad(n: Node, g: Gradient, type: int = 0, angle: float = 90.0) -> void:
	if n and "fill_gradient" in n:
		n.fill_gradient = g
		n.fill_gradient_type = type
		n.fill_gradient_angle = angle
		if n.has_method("queue_redraw"):
			n.queue_redraw()

func no_stroke(api, n: Node) -> void:
	api.set_props(n, {"stroke_width": 0.0})

func build(api) -> Node2D:
	var S: Vector2 = api.artboard_size()
	var c := S / 2.0
	# Fondo: degradado noche → violeta
	var bg = api.add_rect(c, S, 0.0, "Fondo")
	no_stroke(api, bg)
	set_grad(bg, grad([Color("#141a3a"), Color("#3b1d63"), Color("#c2456b")]), 0, 90.0)
	# Sol con resplandor
	var sun = api.add_ellipse(Vector2(c.x, S.y * 0.40), Vector2(S.x * 0.52, S.x * 0.52), "Sol")
	no_stroke(api, sun)
	set_grad(sun, grad([Color("#ffd36b"), Color("#ff7a59"), Color("#ff3d77")]), 0, 90.0)
	# Montañas
	var w := S.x
	var y0 := S.y * 0.62
	var back = api.add_shape(PackedVector2Array([Vector2(0, y0), Vector2(w * 0.22, y0 - S.y * 0.14), Vector2(w * 0.42, y0 - S.y * 0.04), Vector2(w * 0.66, y0 - S.y * 0.19), Vector2(w, y0 - S.y * 0.06), Vector2(w, S.y), Vector2(0, S.y)]), "Montañas lejanas")
	no_stroke(api, back)
	set_grad(back, grad([Color("#5b2a86"), Color("#24163f")]), 0, 90.0)
	var front = api.add_shape(PackedVector2Array([Vector2(0, y0 + S.y * 0.08), Vector2(w * 0.3, y0 - S.y * 0.02), Vector2(w * 0.55, y0 + S.y * 0.07), Vector2(w * 0.8, y0 - S.y * 0.01), Vector2(w, y0 + S.y * 0.05), Vector2(w, S.y), Vector2(0, S.y)]), "Montañas")
	no_stroke(api, front)
	set_grad(front, grad([Color("#2b1b4d"), Color("#0d0b1e")]), 0, 90.0)
	# Onda Bézier con trazo en degradado
	var cv := Curve2D.new()
	cv.add_point(Vector2(w * 0.08, S.y * 0.70), Vector2.ZERO, Vector2(w * 0.14, -S.y * 0.07))
	cv.add_point(Vector2(w * 0.5, S.y * 0.70), Vector2(-w * 0.14, S.y * 0.07), Vector2(w * 0.14, -S.y * 0.07))
	cv.add_point(Vector2(w * 0.92, S.y * 0.70), Vector2(-w * 0.14, S.y * 0.07), Vector2.ZERO)
	var wave = api.add_curve(cv, false, "Onda")
	api.set_stroke(wave, Color("#ffd36b"), 6.0)
	if wave and "stroke_gradient" in wave:
		wave.stroke_gradient = grad([Color("#4fd1ff"), Color("#ffd36b"), Color("#ff3d77")])
		wave.queue_redraw()
	# Estrellas
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 6:
		var p := Vector2(rng.randf_range(0.08, 0.92) * w, rng.randf_range(0.05, 0.24) * S.y)
		var st = api.add_star(p, rng.randf_range(6.0, 14.0), 5 if i % 2 == 0 else 4, 0.45, "Estrella %d" % (i + 1))
		no_stroke(api, st)
		api.set_fill(st, Color(1, 0.95, 0.8, 0.9))
	# Texto
	var t = api.add_text(Vector2(w * 0.1, S.y * 0.76), "Vectopen", int(S.x * 0.11), Color.WHITE)
	var t2 = api.add_text(Vector2(w * 0.1, S.y * 0.76 + S.x * 0.14), "open-source vector editor", int(S.x * 0.035), Color(1, 1, 1, 0.75))
	api.add_effect(t, "Drop Shadow", {})
	api.group([back, front], "Paisaje")
	return t

func fit_camera(canvas: Node, ab_size: Vector2) -> void:
	if canvas == null or not canvas.has_method("_reset_camera"):
		return
	var vp := root.get_visible_rect().size
	var z := minf(vp.y * 0.74 / ab_size.y, vp.x * 0.42 / ab_size.x)
	canvas._reset_camera(z)

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var api = load("res://script_gdscript/api/vectopen_api.gd").new(root)
	var canvas: Node = get_first_node_in_group("_vectopen_canvas")
	var focus = build(api)
	await frames(20)
	var gui = root.get_node("GlobalUI")
	var modes := ["smart", "modern", "professional"]
	if OS.has_environment("VECTOPEN_SHOT_MODES"):
		modes = Array(OS.get_environment("VECTOPEN_SHOT_MODES").split(","))
	var themes := ["light", "dark"]
	var tm = root.get_node_or_null("ThemeManager")
	for theme in themes:
		if tm and tm.has_method("set_mode"):
			tm.set_mode(theme)
		for mode in modes:
			gui.set_ui_mode(mode)
			await frames(30)
			fit_camera(canvas, api.artboard_size())
			api.select([focus])
			await frames(30)
			await shot("%s_%s" % [mode, theme])
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("DONE")
	quit(0)
