# ==========================================
# RUTA: res://test/perf/stress_book.gd
# Benchmark LIBRO / DOCUMENTO GRANDE: N artboards (páginas), cada uno con M
# figuras REALES que PERTENECEN a ese artboard (hijas suyas en el árbol, no
# "todo en el artboard 0 movido visualmente").
#
#   Godot res://test/perf/stress_book.tscn -- --pages 250 --per-page 200
#
# Fases automáticas (sin vsync, para ver el techo):
#   spawn      -> crear N×M figuras
#   verify     -> comprobar pertenencia real (spot-check)
#   idle       -> FPS con el documento quieto
#   pan        -> FPS haciendo pan por las páginas
#   navigate   -> saltar de página en página (set_active + centrar cámara)
#   zoom       -> zoom in/out sobre una página
# Al final imprime RESULT con todas las métricas y cierra.
# ==========================================
extends Node

const CANVAS := "res://scenes/canvas/canvas.tscn"

var pages: int = 100
var per_page: int = 200
var page_size := Vector2(794, 1123)
var page_gap := 260.0

var _scene: Node2D
var _cam: Camera2D
var _container: Node2D
var _mgr: ArtboardManager
var _artboards: Array = []
var _phase := "load"
var _t := 0.0
var _fps: Array[float] = []
var _mark := ""
var _results := {}
var _nav_i := 0
var _nav_t := 0.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--pages" and i + 1 < a.size():
			pages = maxi(1, int(a[i + 1]))
		elif a[i] == "--per-page" and i + 1 < a.size():
			per_page = maxi(0, int(a[i + 1]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_scene = load(CANVAS).instantiate()
	add_child(_scene)
	for _i in 4:
		await get_tree().process_frame
	_cam = _scene.get_node_or_null("Camera2D")
	_container = _scene.get_node_or_null("ArtboardsContainer")
	_mgr = _scene.get_node_or_null("manager_script") as ArtboardManager
	var pm = get_node_or_null("/root/PerformanceManager")
	if pm: pm.set_process(false)  # sin idle-throttle: queremos medir el techo

	await _spawn()
	await _verify()
	await _measure_save_load()
	_begin("idle", 3.0)


const _CS = preload("res://scripts/canvas/canvas_serializer.gd")

func _measure_save_load() -> void:
	# ── ANTES: todo instanciado ──
	_results["ANTES_nodos"] = get_tree().get_node_count()
	_results["ANTES_ram_mb"] = int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)

	# GUARDAR (ruta real: DataRepository → .vtc comprimido gzip)
	var data := _CS.serialize_container(_container)
	var elems_guardados := _contar_elems_en_data(data)
	var path := "user://__book_bench.vtc"
	var t0 := Time.get_ticks_msec()
	DataRepository.save_project(path)   # .vtc = ZIP (manifest + chunk/artboard)
	_results["guardar_ms"] = Time.get_ticks_msec() - t0
	_results["archivo_kb"] = int(FileAccess.get_file_as_bytes(path).size() / 1024.0)
	_results["archivo_kb_sin_gzip"] = int(JSON.stringify(data).length() / 1024.0)

	# ── CARGA DIFERIDA (lee solo el manifest; artboards con fuente perezosa) ──
	t0 = Time.get_ticks_msec()
	DataRepository.load_project(path)
	await get_tree().process_frame
	_results["DESPUES_abrir_ms"] = Time.get_ticks_msec() - t0
	_results["DESPUES_abrir_nodos"] = get_tree().get_node_count()
	_results["DESPUES_abrir_ram_mb"] = int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	var awake := 0
	for ch in _container.get_children():
		if ch is ArtboardEditor and not ch.is_dormant:
			awake += 1
	_results["paginas_materializadas_al_abrir"] = "%d/%d" % [awake, pages]

	_artboards.clear()
	for ch in _container.get_children():
		if ch is ArtboardEditor:
			_artboards.append(ch)

	# ── activar (wake) una página lejana: coste de traerla a memoria ──
	var lejana: ArtboardEditor = _artboards[_artboards.size() / 2]
	if lejana.is_dormant:
		t0 = Time.get_ticks_usec()
		lejana.wake()
		await get_tree().process_frame
		_results["activar_pagina_ms"] = "%.1f" % ((Time.get_ticks_usec() - t0) / 1000.0)

	# ── navegar por varias páginas (streaming despierta/duerme) ──
	for i in 12:
		var idx := (i * 37) % _artboards.size()
		_center_on_page(idx)
		if _cam: _cam.position = _artboards[idx].global_position + _artboards[idx].artboard_size * 0.5
		if _mgr: _mgr.set_active_artboard(_artboards[idx])
		for f in 6:
			await get_tree().process_frame
	_results["DESPUES_navegar_ram_mb"] = int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	awake = 0
	for ch in _container.get_children():
		if ch is ArtboardEditor and not ch.is_dormant:
			awake += 1
	_results["paginas_vivas_tras_navegar"] = awake

	# ── volver a la página 1 ──
	_center_on_page(0)
	if _cam: _cam.position = _artboards[0].global_position + _artboards[0].artboard_size * 0.5
	if _mgr: _mgr.set_active_artboard(_artboards[0])
	for f in 40:
		await get_tree().process_frame
	_results["DESPUES_volver_pag1_ram_mb"] = int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)

	# ── INTEGRIDAD: guardar tras carga perezosa NO pierde figuras ──
	# Ruta REAL de guardado (write_vtc): las páginas que siguen 100 % perezosas
	# se copian byte a byte desde el .vtc de origen (O(1)/página), el resto se
	# re-serializa. Medimos el guardado de disco completo, no solo el dict.
	var path2 := "user://__book_bench_lazy.vtc"
	t0 = Time.get_ticks_msec()
	DataRepository.save_project(path2)
	_results["guardar_tras_lazy_ms"] = Time.get_ticks_msec() - t0
	var elems2 := 0
	var manifest := _CS.read_vtc_manifest(path2)
	for h in manifest.get("artboards", []):
		elems2 += _CS.read_vtc_chunk(path2, h).size()
	_CS.close_reader_cache()
	_results["integridad"] = ("OK %d elems" % elems2) if elems2 == elems_guardados \
		else ("FALLO %d != %d" % [elems2, elems_guardados])

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path2))
	await get_tree().process_frame


func _contar_elems_en_data(d: Dictionary) -> int:
	var n := 0
	for ab in d.get("artboards", []):
		n += ab.get("elements", []).size()
	n += d.get("loose", []).size()
	return n


# ─────────────────────────────────────────────────────────── spawn
func _spawn() -> void:
	var t0 := Time.get_ticks_msec()
	# reutiliza el artboard que trae el .tscn como página 1
	var first := _mgr.all_artboards()[0] if _mgr.all_artboards().size() > 0 else null
	for p in pages:
		var ab: ArtboardEditor
		if p == 0 and first:
			ab = first
		else:
			ab = ArtboardEditor.new()
			ab.artboard_size = page_size
			_container.add_child(ab)
		ab.name = "Pagina_%03d" % (p + 1)
		ab.global_position = Vector2(p * (page_size.x + page_gap), 0)
		ab.artboard_size = page_size
		_artboards.append(ab)
		for e in per_page:
			var c := VectorCircle.new()
			c.size = Vector2.ONE * (16.0 + float(e % 6) * 9.0)
			c.fill_color = Color(0.3 + 0.5 * float(e % 3) / 3.0, 0.5, 0.8, 0.9)
			c.position = Vector2(
				40.0 + fmod(float(e) * 61.0, page_size.x - 80.0),
				40.0 + fmod(float(e) * 97.0, page_size.y - 80.0))
			ab.add_child(c)
		if p % 25 == 0:
			await get_tree().process_frame
	_results["pages"] = pages
	_results["per_page"] = per_page
	_results["total_elems"] = pages * per_page
	_results["spawn_ms"] = Time.get_ticks_msec() - t0
	_results["nodes"] = get_tree().get_node_count()
	_results["mem_mb"] = int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	await get_tree().process_frame


# ─────────────────────────────────────────────────────────── verify ownership
func _verify() -> void:
	var ok := 0
	var checked := 0
	# spot-check: 1 figura de cada página (o cada 10 si hay muchas)
	var step := maxi(1, pages / 40)
	for i in range(0, _artboards.size(), step):
		var ab: ArtboardEditor = _artboards[i]
		for child in ab.get_children():
			if child is VectorCircle:
				checked += 1
				if _mgr.owning_artboard(child) == ab and child.get_parent() == ab:
					ok += 1
				break
	_results["ownership_ok"] = "%d/%d" % [ok, checked]
	await get_tree().process_frame


# ─────────────────────────────────────────────────────────── fases de medida
func _begin(mark: String, _secs: float) -> void:
	_mark = mark
	_t = 0.0
	_fps.clear()
	match mark:
		"idle":
			_center_on_page(0)
		"pan":
			_center_on_page(0)
		"navigate":
			_nav_i = 0
			_nav_t = 0.0
		"zoom":
			_center_on_page(pages / 2)
			if _cam: _cam.zoom = Vector2.ONE


func _center_on_page(idx: int) -> void:
	if not _cam or _artboards.is_empty():
		return
	idx = clampi(idx, 0, _artboards.size() - 1)
	var ab: ArtboardEditor = _artboards[idx]
	_cam.position = ab.global_position + ab.artboard_size * 0.5
	# encuadre: la página ocupa ~80% del alto de viewport
	var vp := get_viewport().get_visible_rect().size
	_cam.zoom = Vector2.ONE * clampf(vp.y * 0.8 / ab.artboard_size.y, 0.05, 4.0)


func _process(delta: float) -> void:
	if _phase != "load":
		return
	_t += delta

	match _mark:
		"idle":
			pass
		"pan":
			_cam.position.x += 1800.0 * delta / maxf(0.05, _cam.zoom.x)
			if _cam.position.x > _artboards[-1].global_position.x:
				_cam.position.x = _artboards[0].global_position.x
		"navigate":
			_nav_t += delta
			if _nav_t >= 0.25:
				_nav_t = 0.0
				_nav_i = (_nav_i + 7) % _artboards.size()   # saltos "lejanos"
				_mgr.set_active_artboard(_artboards[_nav_i])
				_center_on_page(_nav_i)
		"zoom":
			var z: float = _cam.zoom.x
			z *= (1.04 if fmod(_t, 4.0) < 2.0 else 1.0 / 1.04)
			_cam.zoom = Vector2(clampf(z, 0.02, 200.0), clampf(z, 0.02, 200.0))

	if _t > 1.0:
		_fps.append(Engine.get_frames_per_second())

	var dur := 4.0 if _mark == "navigate" else 3.0
	if _t > 1.0 + dur:
		_results["fps_" + _mark] = "%.0f (min %.0f)" % [_avg(_fps), _minv(_fps)]
		_advance()


func _advance() -> void:
	match _mark:
		"idle": _begin("pan", 3.0)
		"pan": _begin("navigate", 4.0)
		"navigate": _begin("zoom", 3.0)
		"zoom":
			_report()
			get_tree().quit()


func _avg(a: Array) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0
	for v in a: s += v
	return s / a.size()

func _minv(a: Array) -> float:
	if a.is_empty(): return 0.0
	var m: float = a[0]
	for v in a: m = minf(m, v)
	return m


func _report() -> void:
	print("[BOOK] RESULT")
	for k in ["pages", "per_page", "total_elems", "ownership_ok", "spawn_ms",
			"guardar_ms", "archivo_kb", "archivo_kb_sin_gzip",
			"ANTES_nodos", "ANTES_ram_mb",
			"DESPUES_abrir_ms", "DESPUES_abrir_nodos", "DESPUES_abrir_ram_mb",
			"paginas_materializadas_al_abrir",
			"activar_pagina_ms",
			"DESPUES_navegar_ram_mb", "paginas_vivas_tras_navegar",
			"DESPUES_volver_pag1_ram_mb",
			"guardar_tras_lazy_ms", "integridad",
			"fps_idle", "fps_pan", "fps_navigate", "fps_zoom"]:
		print("  %-32s = %s" % [k, str(_results.get(k, "?"))])
