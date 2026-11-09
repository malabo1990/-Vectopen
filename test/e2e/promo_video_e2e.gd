# =============================================================================
# VÍDEO PROMOCIONAL (≈25 s de escenas): en un lienzo vacío se construye un
# cartel profesional (ilustración unDraw, tipografía Inter, paleta de marca) y
# Godot graba cada fotograma (Movie Maker: sin tirones aunque la escena pese).
#   1 abrir SVG · 2 recolorear · 3 nodos · 4 pincel · 5 texto en trazado ·
#   6 zoom · 7 patrón de 10 000 piezas · 8 Smart / Modern / Pro
# Imprime «MARK <escena> <fotograma>» para cortar y rotular
# (tools/promo/make_promo.sh). PROMO_LANG=en (por defecto) | es: textos del cartel.
#   E2E_TIMEOUT=900 E2E_ENV="PROMO_LANG=es" \
#   E2E_ARGS="--write-movie $HOME/.cache/vectopen_tests/promo_es/f.png --fixed-fps 30" \
#       test/run_e2e.sh promo_video_e2e
# Ilustraciones: ~/.cache/vectopen_tests/promo_assets/undraw (licencia unDraw:
# uso comercial sin atribución; ver tools/promo/CREDITS.md).
# =============================================================================
extends SceneTree

const Kit = preload("res://test/e2e/lib/campaign_kit.gd")
const CURSOR := "res://assets/cursor/cursor_default.png"
const INK := Color("#1f1d36")
const VIOLET := Color("#5a4bda")
const CORAL := Color("#ff6b6b")
const AMBER := Color("#ffb547")
const TEAL := Color("#20c5b5")
const LAVENDER := Color("#ecebff")

const TEXTS := {
	"es": {"h1": "Diseña", "h2": "sin límites.", "sub": "Editor vectorial libre, gratis y de código abierto", "badge": "VECTOPEN · LIBRE · GRATIS · "},
	"en": {"h1": "Design", "h2": "without limits.", "sub": "Free, open-source vector editor", "badge": "VECTOPEN · FREE · OPEN SOURCE · "},
}

var K
var canvas
var api
var ab: Node2D
var cam: Camera2D
var ic
var _cursor: Sprite2D
var L: Dictionary

func _init() -> void:
	_run.call_deferred()
	create_timer(880.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func frames(n: int = 1) -> void:
	for i in n:
		await process_frame

func mark(name: String) -> void:
	print("MARK %s %d" % [name, Engine.get_frames_drawn()])
	if OS.get_environment("PROMO_DEBUG") == "1":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://promo/dbg_%s.png" % name)

# ── ratón simulado con puntero visible (la grabación no ve el del sistema) ──
func _send(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		var p := (ev as InputEventMouse).position
		Input.warp_mouse(p)
		if _cursor:
			_cursor.position = p
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func move(at: Vector2, held: bool, p: float = 0.8) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.pressure = p if held else 0.0
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_send(mm)
	await process_frame

func btn(at: Vector2, down: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = at
	mb.global_position = at
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = down
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(mb)
	await process_frame

func scr(doc: Vector2) -> Vector2:
	return canvas.get_viewport().get_canvas_transform() * ab.to_global(doc)

func stroke(pts: Array) -> void:
	await move(scr(pts[0]), false)
	await btn(scr(pts[0]), true)
	var n := pts.size()
	for i in n:
		var t := float(i) / maxf(1.0, n - 1.0)
		await move(scr(pts[i]), true, clampf(0.35 + 0.65 * sin(t * PI), 0.15, 1.0))
	await btn(scr(pts[n - 1]), false)

func brush_color(c: Color) -> void:
	var cc := root.get_node_or_null("ColorCore")
	if cc:
		cc.active_target = "stroke"
		cc.stroke_color = c
		cc.fill_color = c

func quiet() -> void:
	var sv := root.get_node_or_null("SaveManager")
	if sv:
		sv.is_modified = false

func clear_selection() -> void:
	root.get_node("SelectionManager").clear()

func select(n: Node) -> void:
	root.get_node("SelectionManager").select(n)

func fit(target: Node2D, margin := 1.12) -> void:
	var vp: Vector2 = canvas.get_viewport().get_visible_rect().size
	var z := minf(vp.x / (target.artboard_size.x * margin), vp.y / (target.artboard_size.y * margin))
	cam.zoom = Vector2(z, z)
	cam.position = target.global_position + target.artboard_size / 2.0

## Smart: el cartel a la IZQUIERDA de los paneles flotantes (Capas, nodos),
## que ocupan la franja derecha de la pantalla.
func fit_left(target: Node2D) -> void:
	var avail := Vector2(1380.0, 940.0)
	var z: float = minf(avail.x / target.artboard_size.x, avail.y / target.artboard_size.y)
	cam.zoom = Vector2(z, z)
	var c: Vector2 = target.global_position + target.artboard_size / 2.0
	cam.position = c + Vector2((960.0 - (40.0 + avail.x * 0.5)) / z, -6.0 / z)

## Modern / Pro: el cartel centrado en el hueco libre entre los paneles
## acoplados (Capas a la izquierda, inspector a la derecha, barras arriba).
func fit_free(target: Node2D) -> void:
	var vp: Vector2 = canvas.get_viewport().get_visible_rect().size
	var x0 := 0.0
	var x1 := vp.x
	var y0 := 0.0
	for n in ["Layout", "DockedInspector", "ProStudio", "ModernTopBar", "ProTopBar", "ModernNavRail"]:
		var c := root.find_child(n, true, false) as Control
		if c == null or not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		if r.size.y > vp.y * 0.5:
			if r.get_center().x < vp.x * 0.5:
				x0 = maxf(x0, r.end.x)
			else:
				x1 = minf(x1, r.position.x)
		elif r.size.x > vp.x * 0.5 and r.position.y < vp.y * 0.3:
			y0 = maxf(y0, r.end.y)
	var avail := Vector2(x1 - x0, vp.y - y0) * 0.9
	var z: float = minf(avail.x / target.artboard_size.x, avail.y / target.artboard_size.y)
	cam.zoom = Vector2(z, z)
	var c2: Vector2 = target.global_position + target.artboard_size / 2.0
	var free_center := Vector2((x0 + x1) * 0.5, (y0 + vp.y) * 0.5)
	cam.position = c2 + (vp * 0.5 - free_center) / z

## El cartel centrado en el rectángulo de pantalla [x0, x1] × [y0, y1].
func fit_rect(target: Node2D, x0: float, x1: float, y0: float, y1: float) -> void:
	var vp: Vector2 = canvas.get_viewport().get_visible_rect().size
	var avail := Vector2(x1 - x0, y1 - y0) * 0.92
	var z: float = minf(avail.x / target.artboard_size.x, avail.y / target.artboard_size.y)
	cam.zoom = Vector2(z, z)
	var c2: Vector2 = target.global_position + target.artboard_size / 2.0
	cam.position = c2 + (vp * 0.5 - Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5)) / z

func hide_tool_panel(panel_name: String) -> void:
	for n in root.find_children(panel_name, "Control", true, false):
		(n as Control).visible = false

func smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

func camera_move(pos0: Vector2, z0: float, pos1: Vector2, z1: float, n: int) -> void:
	for i in n:
		var e := smooth(float(i) / maxf(1.0, n - 1.0))
		var z := exp(lerpf(log(z0), log(z1), e))
		cam.zoom = Vector2(z, z)
		cam.position = pos0.lerp(pos1, e)
		await process_frame

## Aparece con fundido y un leve escalado.
func pop_in(n: CanvasItem, frames_n: int = 14, from_scale := 0.94) -> void:
	var s0: Vector2 = n.scale
	for i in frames_n:
		var e := smooth(float(i + 1) / frames_n)
		n.modulate.a = e
		n.scale = s0 * lerpf(from_scale, 1.0, e)
		await process_frame
	n.modulate.a = 1.0
	n.scale = s0

func text(pos: Vector2, s: String, size: int, col: Color, weight: int) -> Node2D:
	var t: Node2D = api.add_text(pos, s, size, col)
	await frames(2)
	if weight != 400:
		select(t)
		await frames(1)
		ic.apply("font_weight", weight)
		clear_selection()
	return t

func shapes_with_fill(root_n: Node, col: Color) -> Array:
	var out: Array = []
	for n in root_n.find_children("*", "", true, false):
		if "fill_color" in n and (n.fill_color as Color).is_equal_approx(col):
			out.append(n)
	return out

func _run() -> void:
	L = TEXTS.get(OS.get_environment("PROMO_LANG"), TEXTS["en"])
	var assets := OS.get_environment("HOME") + "/.cache/vectopen_tests/promo_assets/undraw/"
	# La interfaz en el idioma del vídeo (sin guardarlo en los ajustes).
	var lm := root.get_node_or_null("LanguageManager")
	if lm:
		lm.set_locale("en" if L == TEXTS["en"] else "es", false)
	K = Kit.new(self, "user://promo")
	if not await K.boot("smart"):
		print("RESULT: FAIL (arranque)")
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	root.get_node("ThemeManager").set_mode("dark")
	canvas = K.canvas
	api = K.api
	ic = root.get_node("InspectorCore")
	cam = canvas.camera
	var layer := CanvasLayer.new()
	layer.layer = 128
	root.add_child(layer)
	_cursor = Sprite2D.new()
	_cursor.texture = load(CURSOR)
	_cursor.centered = false
	layer.add_child(_cursor)
	_cursor.visible = false
	ab = await K.artboard(Vector2(1600, 900), "Vectopen", Color.WHITE)
	await frames(4)
	ab.set("is_selected", false)
	clear_selection()
	quiet()
	fit_left(ab)
	await frames(30)

	# ── 1. Abrir una ilustración SVG ────────────────────────────────────────
	mark("abrir")
	var svg := FileAccess.get_file_as_string(assets + "designer-girl.svg")
	var illus: Node2D = api.import_svg(svg, Vector2(860, 215), "Ilustración")
	illus.scale = Vector2(1.02, 1.02)
	illus.modulate.a = 0.0
	await frames(2)
	await pop_in(illus, 18, 0.9)
	select(illus)
	await frames(50)
	quiet()
	mark("abrir_fin")

	# ── 2. Recolorear con la paleta de la marca ─────────────────────────────
	mark("color")
	var darks := shapes_with_fill(illus, Color("#3f3d56"))
	var sun := shapes_with_fill(illus, Color("#fd6584"))
	for i in 40:
		var e := smooth(float(i + 1) / 40.0)
		for s in darks:
			s.fill_color = Color("#3f3d56").lerp(VIOLET, e)
		for s in sun:
			s.fill_color = Color("#fd6584").lerp(AMBER, e)
		await process_frame
	await frames(40)
	clear_selection()
	quiet()
	mark("color_fin")

	# ── 3. Forma de fondo editada por nodos ─────────────────────────────────
	mark("nodos")
	var blob = K.blob(Vector2(1150, 520), 300.0, 3, 0.18, LAVENDER, "Fondo", 11)
	await frames(1)
	ab.move_child(blob, illus.get_index())
	blob.modulate.a = 0.0
	await pop_in(blob, 10, 0.97)
	select(blob)
	await frames(2)
	canvas.change_tool(canvas._new_tool(load("res://script_gdscript/tools/NodeSelectionTool.gd")))
	await frames(3)
	var nt = canvas.get_current_tool()
	nt.edit_path = blob
	await frames(4)
	var curve: Curve2D = blob.curve
	var pi_idx := 0
	var best := -1e9
	for i in curve.point_count:
		var pp := curve.get_point_position(i)
		var rel := pp - Vector2(1150, 520)
		if rel.x - rel.y > best:   # el nodo de arriba a la derecha
			best = rel.x - rel.y
			pi_idx = i
	var p0: Vector2 = curve.get_point_position(pi_idx)
	var a0: Vector2 = canvas.get_viewport().get_canvas_transform() * blob.to_global(p0)
	var a1: Vector2 = canvas.get_viewport().get_canvas_transform() * blob.to_global(p0 + Vector2(110, -80))
	_cursor.visible = true
	for i in 10:
		await move((a0 + Vector2(60, 50)).lerp(a0, smooth(i / 9.0)), false)
	await btn(a0, true)
	for i in 36:
		await move(a0.lerp(a1, smooth(i / 35.0)), true)
	await btn(a1, false)
	await frames(18)
	quiet()
	mark("nodos_fin")

	# ── 4. Titular y pincel caligráfico ─────────────────────────────────────
	canvas.switch_tool("select")
	clear_selection()
	await frames(1)
	hide_tool_panel("bezier")
	mark("pincel")
	var h1 := await text(Vector2(110, 210), L["h1"], 104, INK, 900)
	var h2 := await text(Vector2(110, 335), L["h2"], 104, VIOLET, 900)
	var sub := await text(Vector2(116, 545), L["sub"], 30, Color("#6b6880"), 400)
	for n in [h1, h2, sub]:
		n.modulate.a = 0.0
	await pop_in(h1, 8, 0.97)
	await pop_in(h2, 8, 0.97)
	await pop_in(sub, 6, 1.0)
	canvas.switch_tool("brush")
	await frames(2)
	var bt = canvas.current_tool
	bt.apply_brush_style("calligraphy")
	bt.brush_width = 16.0
	brush_color(CORAL)
	var sw: Array = []
	for i in 40:
		var t := i / 39.0
		sw.append(Vector2(118 + t * 600, 498 - sin(t * PI) * 20.0 + t * 6.0))
	await stroke(sw)
	await frames(16)
	quiet()
	mark("pincel_fin")

	# ── 5. Sello con texto en trazado ───────────────────────────────────────
	_cursor.visible = false
	canvas.switch_tool("select")
	clear_selection()
	await frames(1)
	hide_tool_panel("brush")
	hide_tool_panel("bezier")
	mark("texto")
	var bc := Vector2(1460, 150)
	var disc = api.add_ellipse(bc, Vector2(116, 116), "Sello")
	api.set_props(disc, {"fill_color": CORAL, "stroke_width": 0.0})
	var star = api.add_star(bc, 30, 5, 0.45, "Estrella")
	api.set_props(star, {"fill_color": Color.WHITE, "stroke_width": 0.0})
	var c := Curve2D.new()
	var r := 84.0
	var segs := 8
	for i in segs + 1:
		var a := -PI * 0.5 + TAU * 0.97 * i / segs
		var tg := Vector2(-sin(a), cos(a)) * r * (TAU * 0.97 / segs) * 0.3642
		c.add_point(bc + Vector2(cos(a), sin(a)) * r, -tg, tg)
	var ring = api.add_curve(c, false, "Aro")
	api.set_props(ring, {"stroke_width": 0.0})
	var tl: Line2D = await K.text_on_path(L["badge"], 19.0, INK, ring, {"align": 0.0})
	for n in [disc, star]:
		n.modulate.a = 0.0
	await pop_in(disc, 8, 0.6)
	await pop_in(star, 6, 0.4)
	if tl:
		select(tl)
		await frames(2)
		ic.apply("font_weight", 700)
		for i in 62:
			ic.apply("path_text_start", 0.25 * smooth(i / 61.0))
			await process_frame
	await frames(10)
	clear_selection()
	quiet()
	mark("texto_fin")

	# ── 6. Zoom a un detalle: siempre nítido ────────────────────────────────
	mark("zoom")
	var start_pos: Vector2 = cam.position
	var z0: float = cam.zoom.x
	var target: Vector2 = ab.to_global(bc + Vector2(6, 4))
	await camera_move(start_pos, z0, target, z0 * 6.5, 70)
	await frames(12)
	mark("zoom_fin")

	# ── 7. Patrón de 10 000 piezas ──────────────────────────────────────────
	var pat: Node2D = api.add_artboard(Vector2(5000, 3200), "Patrón")
	pat.global_position = ab.global_position + Vector2(ab.artboard_size.x + 400, 0)
	if "fill_color" in pat:
		pat.fill_color = Color("#14122b")
	await frames(2)
	var tile := Node2D.new()
	pat.add_child(tile)
	var pal := [VIOLET, CORAL, AMBER, TEAL, Color("#f4f3ff")]
	var made: Array = []
	for j in 5:
		for i in 5:
			var cpos := Vector2(i * 40 + 20, j * 40 + 20)
			var col: Color = pal[(i + j * 2) % pal.size()]
			var n: Node2D
			match (i * 3 + j) % 4:
				0: n = api.add_ellipse(cpos, Vector2(22, 22))
				1: n = api.add_rect(cpos, Vector2(20, 20), 5.0)
				2: n = api.add_polygon(cpos, 13, 3)
				_: n = api.add_star(cpos, 13, 5, 0.5)
			api.set_props(n, {"fill_color": col, "stroke_width": 0.0})
			made.append(n)
	await frames(2)
	for n in made:
		if n.get_parent() != tile:
			n.reparent(tile)
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	var data: Array = Ser.serialize_elements(tile)
	tile.free()
	var holder := Node2D.new()
	holder.name = "Patrón 10 000"
	holder.set_meta("shape_type", "group")
	pat.add_child(holder)
	for ty in 16:
		for tx in 25:
			var b := Node2D.new()
			b.set_meta("shape_type", "group")
			b.position = Vector2(tx * 200, ty * 200)
			holder.add_child(b)
			Ser.instantiate_elements(b, data)
	await frames(10)
	quiet()
	var zf := minf(1920.0 / (pat.artboard_size.x * 1.08), 1080.0 / (pat.artboard_size.y * 1.08))
	var center: Vector2 = pat.global_position + pat.artboard_size / 2.0
	var corner: Vector2 = pat.global_position + Vector2(260, 160)
	cam.zoom = Vector2(2.2, 2.2)
	cam.position = corner
	await frames(4)
	print("DBGPAT pat=%s size=%s holder=%d cam=%s corner=%s center=%s zf=%.3f vis=%s dormant=%s" % [pat.global_position, pat.artboard_size, holder.get_child_count(), cam.position, corner, center, zf, pat.visible, pat.get("is_dormant")])
	mark("muro")
	await camera_move(corner, 2.2, center, zf, 92)
	print("DBGPAT fin cam=%s z=%.3f" % [cam.position, cam.zoom.x])
	await frames(10)
	mark("muro_fin")

	# ── 8. El cartel en Smart · Modern · Pro ────────────────────────────────
	pat.visible = false
	fit_left(ab)
	await frames(6)
	var gui := root.get_node("GlobalUI")
	mark("modos")
	for m in ["smart", "modern", "professional"]:
		gui.set_ui_mode(m)
		await frames(3)
		if m == "smart":
			fit_left(ab)
		elif m == "modern":
			await frames(2)
			fit_rect(ab, 290.0, 1640.0, 70.0, 990.0)   # Capas a la izquierda, inspector a la derecha
		else:
			await frames(2)
			fit_free(ab)
		await frames(37)
	mark("modos_fin")
	await frames(4)
	gui.set_ui_mode("smart")
	print("RESULT: OK")
	quit(0)
