## ESTRÉS EXTREMO de las funciones nuevas de la 0.2.4-beta (con ventana):
## iluminación, fusión, componentes, contenedor y esquinas, con cantidades
## muy por encima del uso normal. Imprime «BENCH clave=valor» y comprueba
## umbrales. Una sección: E2E_ENV="STRESS_ONLY=luz|fusion|comp|cont|esq".
extends SceneTree

var K
var api
var only := ""

func _init() -> void:
	only = OS.get_environment("STRESS_ONLY") if OS.has_environment("STRESS_ONLY") else ""
	_run.call_deferred()
	create_timer(1500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func bench(k: String, v) -> void:
	print("BENCH %s=%s" % [k, str(v)])

func ms_since(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0

## fps medios durante `frames` fotogramas llamando a `step` en cada uno.
func fps_while(frames: int, step: Callable = Callable()) -> float:
	var t0 := Time.get_ticks_usec()
	for i in frames:
		if step.is_valid():
			step.call(i)
		await process_frame
	return frames / maxf((Time.get_ticks_usec() - t0) / 1000000.0, 0.0001)

func fresh(title: String, size := Vector2(3000, 2000)) -> Node2D:
	var ab: Node2D = await K.artboard(size, title, Color.WHITE)
	await K.look_at(ab)
	return ab

func clear_page(ab: Node2D) -> void:
	ab.get_parent().remove_child(ab)
	ab.queue_free()
	var hm = root.get_node_or_null("HistoryManager")
	if hm and hm.has_method("clear"):
		hm.clear()
	await K.frames(6)

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://stress_new")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	if only == "" or only == "luz":
		await stress_lights()
	if only == "" or only == "fusion":
		await stress_blend()
	if only == "" or only == "comp":
		await stress_components()
	if only == "" or only == "cont":
		await stress_container()
	if only == "" or only == "esq":
		await stress_corners()
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)

# ── 1. Iluminación: 500 figuras + 6 luces ───────────────────────────────────
func stress_lights() -> void:
	var ab := await fresh("Estrés luz")
	for i in 500:
		var r = api.add_rect(Vector2(60 + (i % 25) * 115, 60 + int(i / 25) * 95), Vector2(70, 50), 6.0, "F%d" % i)
		api.set_props(r, {"fill_color": Color(0.85, 0.85, 0.9)})
	var lights: Array = []
	for t in [["point", Vector2(500, 500)], ["point", Vector2(2400, 1400)], ["spot", Vector2(1500, 300)],
			["spot", Vector2(600, 1600)], ["directional", Vector2(100, 100)], ["ambient", Vector2(200, 100)]]:
		lights.append(api.add_light(t[1], t[0], {"radius": 900.0, "energy": 1.1, "cone": 60.0}))
	await K.frames(30)
	var f_static := await fps_while(90)
	bench("luz_fps_quieto", snappedf(f_static, 0.1))
	var spot = lights[2]
	var f_rot := await fps_while(120, func(i: int) -> void: spot.lamp_angle = float(i * 3 % 360))
	bench("luz_fps_girando_foco", snappedf(f_rot, 0.1))
	var pt = lights[0]
	var f_move := await fps_while(120, func(i: int) -> void: pt.position = Vector2(500 + i * 8, 500 + sin(i * 0.1) * 200))
	bench("luz_fps_moviendo_puntual", snappedf(f_move, 0.1))
	var t0 := Time.get_ticks_usec()
	spot.refresh_occluders()
	bench("luz_rehacer_sombras_ms", snappedf(ms_since(t0), 0.1))
	K.check("luz: 500 figuras + 6 luces, girar un foco va fluido (≥ 20 fps)", f_rot >= 20.0, "%.1f fps" % f_rot)
	K.check("luz: mover una luz va fluido (≥ 20 fps)", f_move >= 20.0, "%.1f fps" % f_move)
	await K.shot("luz")
	await clear_page(ab)

# ── 2. Fusión: cadena de 10 objetos × 100 pasos ─────────────────────────────
func stress_blend() -> void:
	var ab := await fresh("Estrés fusión")
	var keys: Array = []
	for i in 10:
		var n = api.add_ellipse(Vector2(150 + i * 280, 600 + (i % 2) * 400), Vector2(60 + i * 8, 60), "K%d" % i) if i % 2 == 0 \
			else api.add_rect(Vector2(150 + i * 280, 600 + (i % 2) * 400), Vector2(70, 50 + i * 6), 8.0, "K%d" % i)
		api.set_props(n, {"fill_color": Color.from_hsv(i / 10.0, 0.7, 0.9)})
		keys.append(n)
	var t0 := Time.get_ticks_usec()
	var g: Node2D = api.make_blend_chain(keys, {"steps": 100})
	await process_frame
	var t_make := ms_since(t0)
	var BL = load("res://script_gdscript/shapes/blend.gd")
	var n_steps := g.get_children().filter(func(c) -> bool: return c.has_meta("_blend_step")).size()
	bench("fusion_pasos", n_steps)
	bench("fusion_crear_ms", snappedf(t_make, 0.1))
	t0 = Time.get_ticks_usec()
	BL.write_prop(g, "blend_steps", 60.0)
	var t_rebuild := ms_since(t0)
	bench("fusion_cambiar_pasos_ms", snappedf(t_rebuild, 0.1))
	await K.frames(10)
	var f := await fps_while(90)
	bench("fusion_fps_visible", snappedf(f, 0.1))
	K.check("fusión: 900 pasos se crean en < 3 s", t_make < 3000.0, "%.0f ms" % t_make)
	K.check("fusión: cambiar los pasos de 900 → 540 en < 2 s", t_rebuild < 2000.0, "%.0f ms" % t_rebuild)
	K.check("fusión: la vista sigue fluida (≥ 20 fps)", f >= 20.0, "%.1f fps" % f)
	await K.shot("fusion")
	await clear_page(ab)

# ── 3. Componentes: 1 componente × 1000 copias ──────────────────────────────
func stress_components() -> void:
	var ab := await fresh("Estrés componentes")
	var a = api.add_rect(Vector2(50, 50), Vector2(60, 40), 6.0, "Btn")
	var b = api.add_ellipse(Vector2(50, 50), Vector2(16, 16), "Ico")
	var g = api.make_symbol([a, b], "Botón")
	var S = load("res://script_gdscript/shapes/symbols.gd")
	var id: String = S.symbol_of(g)
	var t0 := Time.get_ticks_usec()
	for i in 999:
		api.place_symbol(id, Vector2(50 + (i % 40) * 72, 110 + int(i / 40) * 60))
	var t_place := ms_since(t0)
	bench("comp_copias", S.instances(id).size())
	bench("comp_colocar_999_ms", snappedf(t_place, 0.1))
	await K.frames(10)
	var inner: Node = S.instances(id)[0].find_child("Btn", true, false)
	t0 = Time.get_ticks_usec()
	api.set_props(inner, {"fill_color": Color(0.9, 0.3, 0.2)})
	if S.has_method("sync_now"):
		S.sync_now()
	await process_frame
	var t_sync := ms_since(t0)
	bench("comp_propagar_1000_ms", snappedf(t_sync, 0.1))
	var last: Node = S.instances(id)[-1].find_child("Btn", true, false)
	K.check("componentes: el cambio llega a la copia 1000", last != null and (last.fill_color as Color).r > 0.8, str(last.fill_color if last else "-"))
	var f := await fps_while(90)
	bench("comp_fps_visible", snappedf(f, 0.1))
	K.check("componentes: propagar a 1000 copias en < 3 s", t_sync < 3000.0, "%.0f ms" % t_sync)
	K.check("componentes: la vista sigue fluida (≥ 20 fps)", f >= 20.0, "%.1f fps" % f)
	await K.shot("componentes")
	await clear_page(ab)

# ── 4. Contenedor: rejilla de 1000 elementos ────────────────────────────────
func stress_container() -> void:
	var ab := await fresh("Estrés contenedor")
	var items: Array = []
	for i in 1000:
		items.append(api.add_rect(Vector2(40 + (i % 40) * 70, 40 + int(i / 40) * 60), Vector2(50 + (i % 3) * 6, 40), 4.0, "I%d" % i))
	var t0 := Time.get_ticks_usec()
	var g: Node2D = api.make_layout(items, {"mode": "grid", "columns": 40, "gap": 8.0})
	var t_make := ms_since(t0)
	bench("cont_crear_1000_ms", snappedf(t_make, 0.1))
	var AL = load("res://script_gdscript/shapes/auto_layout.gd")
	t0 = Time.get_ticks_usec()
	for k in 10:
		AL.write_prop(g, "layout_gap", 8.0 + k)
	var t_live := ms_since(t0) / 10.0
	bench("cont_recolocar_ms", snappedf(t_live, 0.1))
	for m in ["row", "wrap", "column", "grid"]:
		t0 = Time.get_ticks_usec()
		AL.write_prop(g, "layout_mode", m)
		bench("cont_modo_%s_ms" % m, snappedf(ms_since(t0), 0.1))
	await K.frames(10)
	var f := await fps_while(90)
	bench("cont_fps_visible", snappedf(f, 0.1))
	K.check("contenedor: recolocar 1000 elementos en < 100 ms (arrastre en vivo)", t_live < 100.0, "%.1f ms" % t_live)
	K.check("contenedor: crear con 1000 elementos en < 5 s", t_make < 5000.0, "%.0f ms" % t_make)
	await K.shot("contenedor")
	await clear_page(ab)

# ── 5. Esquinas: 5000 rectángulos con zigzag / sierra ───────────────────────
func stress_corners() -> void:
	var ab := await fresh("Estrés esquinas", Vector2(6000, 4000))
	var t0 := Time.get_ticks_usec()
	var shapes: Array = []
	for i in 5000:
		var r = api.add_rect(Vector2(40 + (i % 100) * 58, 40 + int(i / 100) * 58), Vector2(48, 30 + (i % 4) * 4), 12.0, "C%d" % i)
		r.corner_style = 4 + (i % 2)
		shapes.append(r)
	var t_make := ms_since(t0)
	bench("esq_crear_5000_ms", snappedf(t_make, 0.1))
	await K.frames(10)
	var f := await fps_while(90)
	bench("esq_fps_todo_visible", snappedf(f, 0.1))
	var cv: Node2D = K.canvas
	var f_pan := await fps_while(90, func(i: int) -> void: cv.position += Vector2(3, 0))
	bench("esq_fps_desplazar", snappedf(f_pan, 0.1))
	t0 = Time.get_ticks_usec()
	for i in 30:
		shapes[i].size = Vector2(48 - i, 34)   # estrechar: esquinas que se pisan
	await process_frame
	bench("esq_redimensionar_30_ms", snappedf(ms_since(t0), 0.1))
	K.check("esquinas: 5000 rectángulos con zigzag/sierra, vista ≥ 10 fps", f >= 10.0, "%.1f fps" % f)
	await K.shot("esquinas")
	await clear_page(ab)
