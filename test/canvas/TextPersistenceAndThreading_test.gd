extends GdUnitTestSuite

## Regresiones de la revisión de texto/párrafo (2026-10):
##  1. Editar un marco enlazado NO debe borrar la historia del resto de marcos.
##  2. Los textos recargados traen editor en línea y autowrap (sin VRT).
##  3. El guardado conserva formato de un solo run, trazo por run,
##     proporciones, columnas y el encadenamiento de marcos.
##  5. Cambiar la familia vacía la caché de bytes del overlay vectorial.

const CANVAS := "res://scenes/canvas/canvas.tscn"
const PARA_TOOL := "res://script_gdscript/tools/ParagraphTool.gd"
const CS = preload("res://scripts/canvas/canvas_serializer.gd")

const STORY := "Capítulo Uno: En un lugar de la Mancha, de cuyo nombre no quiero acordarme, no ha mucho tiempo que vivía un hidalgo de los de lanza en astillero, adarga antigua, rocín flaco y galgo corredor."

func _canvas() -> Node2D:
	var scene: Node2D = auto_free(load(CANVAS).instantiate())
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	return scene

func _para_tool(scene: Node2D, artboard: Node2D) -> Node:
	var tool: Node = auto_free((load(PARA_TOOL) as GDScript).new())
	add_child(tool)
	tool.set("target_artboard", artboard)
	tool.set("canvas", scene)
	return tool

func _chain(tool: Node) -> Array:
	var p1: Node2D = tool._create_new_paragraph_at(Vector2(50, 50))
	p1.set_meta("width", 200.0)
	p1.set_meta("height", 50.0)
	p1.set_meta("text", STORY)
	var p2: Node2D = tool._create_new_paragraph_at(Vector2(300, 50))
	p2.set_meta("width", 200.0)
	p2.set_meta("height", 400.0)
	p2.set_meta("text", "")
	assert_bool(ParagraphThreading.link(p1, p2)).is_true()
	return [p1, p2]

# ── 1. threading ─────────────────────────────────────────────────────────────

func test_split_devuelve_subcadenas_exactas() -> void:
	var story := "Uno dos  tres.\n\nCuatro cinco seis siete ocho nueve diez once doce trece catorce."
	var res: Dictionary = ParagraphThreading.split_text_to_fit(story, ThemeDB.fallback_font, 20, 160.0, 40.0)
	var fits: String = res["fits"]
	var over: String = res["overflow"]
	assert_bool(story.begins_with(fits)).is_true()
	assert_bool(story.ends_with(over)).is_true()
	assert_bool(fits.contains("  ")).is_true()          # espacios dobles intactos
	assert_bool(fits.length() + over.length() <= story.length()).is_true()

func test_reflow_guarda_rangos_que_reconstruyen_la_historia() -> void:
	var scene := await _canvas()
	var ab: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var pp := _chain(await _para_tool(scene, ab))
	var r1: Vector2i = pp[0].get_meta("story_range")
	var r2: Vector2i = pp[1].get_meta("story_range")
	assert_int(r1.x).is_equal(0)
	assert_bool(r2.x >= r1.y).is_true()
	assert_str(STORY.substr(r1.x, r1.y - r1.x)).is_equal(String(pp[0].get_meta("text")))
	assert_str(STORY.substr(r2.x, r2.y - r2.x)).is_equal(String(pp[1].get_meta("text")))
	assert_int(r2.y).is_equal(STORY.length())

func test_editar_segundo_marco_conserva_el_primero() -> void:
	var scene := await _canvas()
	var ab: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _para_tool(scene, ab)
	var pp := _chain(tool)
	var p1: Node2D = pp[0]
	var p2: Node2D = pp[1]
	var p1_before := String(p1.get_meta("text"))
	var p2_before := String(p2.get_meta("text"))
	assert_str(p1_before).is_not_empty()

	tool._check_and_trigger_edit_at(p2)
	var ed: TextEdit = p2.get_node("MultiLineEdit")
	ed.text = p2_before + " FIN."
	tool.commit_text_edit(false)

	var story := String(p1.get_meta("raw_story_text"))
	assert_bool(story.begins_with(p1_before)).is_true()
	assert_bool(story.ends_with("galgo corredor. FIN.")).is_true()
	assert_str(String(p1.get_meta("text"))).is_equal(p1_before)

func test_editar_primer_marco_conserva_el_sobrante() -> void:
	var scene := await _canvas()
	var ab: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _para_tool(scene, ab)
	var pp := _chain(tool)
	var p1: Node2D = pp[0]

	tool._check_and_trigger_edit_at(p1)
	var ed: TextEdit = p1.get_node("MultiLineEdit")
	ed.text = "Prólogo. " + String(p1.get_meta("text"))
	tool.commit_text_edit(false)

	var story := String(p1.get_meta("raw_story_text"))
	assert_bool(story.begins_with("Prólogo. Capítulo Uno")).is_true()
	assert_bool(story.ends_with("galgo corredor.")).is_true()

# ── 2. recarga: editor en línea + autowrap ───────────────────────────────────

func _roundtrip(ab: Node2D, scene_b_holder: Array) -> Node2D:
	var cont_a: Node2D = ab.get_parent()
	var data := CS.serialize_container(cont_a)
	var scene_b := await _canvas()
	scene_b_holder.append(scene_b)
	var cont_b: Node2D = scene_b.get_node("ArtboardsContainer")
	CS.rebuild_container(cont_b, data)
	await get_tree().process_frame
	return cont_b.get_child(0)

func test_parrafo_recargado_tiene_editor_autowrap_y_se_edita() -> void:
	var scene := await _canvas()
	var ab: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _para_tool(scene, ab)
	var p: Node2D = tool._create_new_paragraph_at(Vector2(10, 10))
	p.name = "ParrafoX"
	var original := String(p.get_meta("text"))

	var holder: Array = []
	var ab_b := await _roundtrip(ab, holder)
	var pb: Node2D = ab_b.get_node("ParrafoX")
	var dl: Label = pb.get_node("DisplayLabel")
	assert_int(dl.autowrap_mode).is_not_equal(TextServer.AUTOWRAP_OFF)
	assert_object(pb.get_node_or_null("MultiLineEdit")).is_not_null()

	# Entrar y salir de edición sin cambios NO debe vaciar el párrafo.
	var tool_b := await _para_tool(holder[0], ab_b)
	tool_b._check_and_trigger_edit_at(pb)
	tool_b.commit_text_edit(false)
	assert_str(String(pb.get_meta("text"))).is_equal(original)
	assert_bool(dl.visible).is_true()

func test_titulo_recargado_tiene_title_edit() -> void:
	var t := Node2D.new()
	t.set_meta("shape_type", "text_title")
	t.set_meta("text", "Hola")
	auto_free(t)
	var ed := WorldTextLabel.ensure_inline_editor(t)
	assert_object(ed).is_not_null()
	assert_str(String(ed.name)).is_equal("TitleEdit")
	assert_object(WorldTextLabel.ensure_inline_editor(t)).is_same(ed)   # idempotente

# ── 3. guardado de formato y encadenamiento ──────────────────────────────────

func test_roundtrip_run_unico_trazo_proporciones_columnas() -> void:
	var scene := await _canvas()
	var ab: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _para_tool(scene, ab)
	var p: Node2D = tool._create_new_paragraph_at(Vector2(10, 10))
	p.name = "Fmt"
	var n := String(p.get_meta("text")).length()
	p.set_meta("runs", [{"length": n, "color": Color.RED, "bold": true, "italic": false,
		"underline": true, "size": 30.0, "stroke_color": Color.BLUE, "stroke_width": 2.5}])
	p.set_meta("letter_proportions", {"mode": "aAa", "start": 0.8, "mid": 1.4, "end": 0.8})
	p.set_meta("columns", 3)
	p.set_meta("column_gap", 12.0)
	p.set_meta("stroke_width", 1.5)

	var holder: Array = []
	var ab_b := await _roundtrip(ab, holder)
	var pb: Node2D = ab_b.get_node("Fmt")
	var runs: Array = pb.get_meta("runs")
	assert_int(runs.size()).is_equal(1)
	assert_bool(bool(runs[0]["underline"])).is_true()
	assert_bool(bool(runs[0]["bold"])).is_true()
	assert_float(float(runs[0]["size"])).is_equal(30.0)
	assert_float(float(runs[0]["stroke_width"])).is_equal(2.5)
	assert_that(runs[0]["stroke_color"]).is_equal(Color.BLUE)
	assert_str(String(pb.get_meta("letter_proportions")["mode"])).is_equal("aAa")
	assert_int(int(pb.get_meta("columns"))).is_equal(3)
	assert_float(float(pb.get_meta("column_gap"))).is_equal(12.0)
	assert_float(float(pb.get_meta("stroke_width"))).is_equal(1.5)

func test_roundtrip_cadena_de_marcos() -> void:
	var scene := await _canvas()
	var ab: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var pp := _chain(await _para_tool(scene, ab))
	pp[0].name = "M1"
	pp[1].name = "M2"
	# Re-enlazar con los nombres definitivos (las metas guardan la ruta).
	assert_bool(ParagraphThreading.link(pp[0], pp[1])).is_true()

	var holder: Array = []
	var ab_b := await _roundtrip(ab, holder)
	var m1: Node2D = ab_b.get_node("M1")
	var m2: Node2D = ab_b.get_node("M2")
	assert_object(ParagraphThreading.get_next_frame(m1)).is_same(m2)
	assert_object(ParagraphThreading.get_prev_frame(m2)).is_same(m1)
	assert_str(String(m1.get_meta("raw_story_text"))).is_equal(STORY)

# ── 5. caché de fuente del overlay ───────────────────────────────────────────

func test_cambiar_familia_vacia_cache_de_bytes() -> void:
	var l: WorldTextLabel = auto_free(WorldTextLabel.new())
	l.text = "Abc"
	add_child(l)
	await get_tree().process_frame
	assert_bool(l._outline_font_bytes().is_empty()).is_false()
	l.apply_font_from_meta()
	assert_bool(l._outline_bytes_cache.is_empty()).is_true()

# ── 7. runs por posición ─────────────────────────────────────────────────────

func _bold_runs() -> Array:
	# "Hola mundo": "Hola" normal, " mundo" negrita
	return [{"length": 4, "color": Color.BLACK, "bold": false},
		{"length": 6, "color": Color.BLACK, "bold": true}]

func test_edit_runs_insertar_al_inicio_no_desplaza_negrita() -> void:
	var out := WorldTextLabel.edit_runs(_bold_runs(), "Hola mundo", "¡Hola mundo")
	assert_int(out.size()).is_equal(2)
	assert_int(int(out[0]["length"])).is_equal(5)     # "¡Hola" hereda normal
	assert_bool(bool(out[1]["bold"])).is_true()
	assert_int(int(out[1]["length"])).is_equal(6)     # " mundo" sigue en negrita

func test_edit_runs_borrar_en_medio_y_strip() -> void:
	var out := WorldTextLabel.edit_runs(_bold_runs(), "Hola mundo", "Ho mundo")
	assert_int(int(out[0]["length"])).is_equal(2)
	assert_int(int(out[1]["length"])).is_equal(6)
	var runs := [{"length": 2, "bold": false}, {"length": 4, "bold": true}]
	var stripped := WorldTextLabel.edit_runs(runs, "  Hola", "Hola")
	assert_int(stripped.size()).is_equal(1)
	assert_bool(bool(stripped[0]["bold"])).is_true()   # la negrita sigue en "Hola"

# ── 8. tracking ──────────────────────────────────────────────────────────────

func test_tracking_bitmap_escala_con_el_raster_y_no_se_suma_dos_veces() -> void:
	var t := Node2D.new()
	t.set_meta("letter_spacing", 4.5)
	add_child(t)
	auto_free(t)
	var l := WorldTextLabel.new()
	l.base_font_size = 24
	l.text = "Tracking"
	t.add_child(l)
	await get_tree().process_frame
	l.apply_font_from_meta()
	assert_float(l.letter_spacing_world()).is_equal(4.5)   # fracción conservada
	l._update_tracking_spacing(48)
	assert_int(l._tracking_fv.spacing_glyph).is_equal(9)    # 4.5 px mundo a 2x
	var raw := l._untracked_font().get_string_size("Tracking", HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x
	assert_float(l._measure("Tracking", 48)).is_equal_approx(raw + 8.0 * 9.0, 0.01)

# ── 9. justificado e interlineado en el overlay ─────────────────────────────

func test_overlay_justifica_lineas_envueltas() -> void:
	var l: WorldTextLabel = auto_free(WorldTextLabel.new())
	l.base_font_size = 24
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_FILL
	l.text = "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor"
	add_child(l)
	l.set_world_size(Vector2(220, 400))
	await get_tree().process_frame
	var outline := l._build_outline_at(WorldTextLabel.VECTOR_FONT)
	assert_object(outline).is_not_null()
	var first_y := float(outline.get_child(0).get_meta("baseline_y"))
	var max_x1 := 0.0
	for g in outline.get_children():
		if is_equal_approx(float(g.get_meta("baseline_y")), first_y):
			max_x1 = maxf(max_x1, float(g.get_meta("x1")))
	var box_w := 220.0 * float(WorldTextLabel.VECTOR_FONT) / 24.0
	assert_float(max_x1).is_equal_approx(box_w, box_w * 0.03)
	outline.free()

func test_interlineado_invalida_el_overlay() -> void:
	var t := Node2D.new()
	t.set_meta("shape_type", "text_paragraph")
	add_child(t)
	auto_free(t)
	var l := WorldTextLabel.new()
	l.name = "DisplayLabel"
	l.text = "abc"
	t.add_child(l)
	await get_tree().process_frame
	l._outline_dirty = false
	InspectorCore._write_line_spacing(t, 20)
	assert_bool(l._outline_dirty).is_true()

# ── 10. undo de la edición de contenido ─────────────────────────────────────

func test_editar_parrafo_se_puede_deshacer() -> void:
	var scene := await _canvas()
	var ab: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _para_tool(scene, ab)
	var p: Node2D = tool._create_new_paragraph_at(Vector2(10, 10))
	var original := String(p.get_meta("text"))
	tool._check_and_trigger_edit_at(p)
	(p.get_node("MultiLineEdit") as TextEdit).text = "Texto nuevo"
	tool.commit_text_edit(false)
	assert_str(String(p.get_meta("text"))).is_equal("Texto nuevo")
	HistoryManager.undo()
	assert_str(String(p.get_meta("text"))).is_equal(original)
	assert_str((p.get_node("DisplayLabel") as Label).text).is_equal(original)
	HistoryManager.redo()
	assert_str(String(p.get_meta("text"))).is_equal("Texto nuevo")

# ── medios: runs en cadena, enlaces estables, SVG, hit-test ─────────────────

func test_cadena_conserva_formato_por_marco() -> void:
	var scene := await _canvas()
	var ab: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _para_tool(scene, ab)
	var p1: Node2D = tool._create_new_paragraph_at(Vector2(50, 50))
	p1.set_meta("width", 200.0)
	p1.set_meta("height", 50.0)
	p1.set_meta("text", STORY)
	p1.set_meta("runs", [{"length": 12, "color": Color.RED, "bold": true},
		{"length": STORY.length() - 12, "color": Color.BLACK, "bold": false}])
	var p2: Node2D = tool._create_new_paragraph_at(Vector2(300, 50))
	p2.set_meta("width", 200.0)
	p2.set_meta("height", 400.0)
	assert_bool(ParagraphThreading.link(p1, p2)).is_true()
	var r1: Array = p1.get_meta("runs")
	assert_bool(bool(r1[0]["bold"])).is_true()
	assert_int(ParagraphThreading._runs_len(r1)).is_equal(String(p1.get_meta("text")).length())
	var r2: Array = p2.get_meta("runs")
	assert_int(ParagraphThreading._runs_len(r2)).is_equal(String(p2.get_meta("text")).length())

	tool._check_and_trigger_edit_at(p2)
	(p2.get_node("MultiLineEdit") as TextEdit).text = String(p2.get_meta("text")) + " FIN."
	tool.commit_text_edit(false)
	var sr: Array = p1.get_meta("story_runs")
	assert_int(ParagraphThreading._runs_len(sr)).is_equal(String(p1.get_meta("raw_story_text")).length())
	assert_bool(bool((p1.get_meta("runs") as Array)[0]["bold"])).is_true()

func test_enlace_sobrevive_a_renombrar() -> void:
	var scene := await _canvas()
	var ab: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var pp := _chain(await _para_tool(scene, ab))
	pp[1].name = "RenombradoX"
	assert_object(ParagraphThreading.get_next_frame(pp[0])).is_same(pp[1])
	assert_object(ParagraphThreading.get_prev_frame(pp[1])).is_same(pp[0])

func test_svg_parrafo_multilinea_con_familia_del_contenedor() -> void:
	var t := Node2D.new()
	t.set_meta("font_family", "Inter")
	t.set_meta("width", 150.0)
	t.set_meta("height", 300.0)
	add_child(t)
	auto_free(t)
	var l := WorldTextLabel.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = "Una frase lo bastante larga para ocupar varias líneas"
	t.add_child(l)
	await get_tree().process_frame
	var svg := l.to_svg()
	assert_bool(svg.contains('font-family="Inter"')).is_true()
	assert_bool(svg.contains('text-anchor="middle"')).is_true()
	assert_bool(svg.count("<tspan x=") >= 2).is_true()

func test_text_tool_detecta_titulo_rotado() -> void:
	var scene := await _canvas()
	var ab: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool: Node = auto_free((load("res://script_gdscript/tools/TextTool.gd") as GDScript).new())
	add_child(tool)
	tool.set("target_artboard", ab)
	tool.set("canvas", scene)
	var title: Node2D = tool._create_new_title_at(Vector2(200, 200))
	title.rotation = PI / 2.0
	var inside := title.to_global(Vector2(30, 10))
	assert_object(tool._shape_at(inside)).is_same(title)

func test_roundtrip_efectos_de_texto() -> void:
	var scene := await _canvas()
	var ab: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _para_tool(scene, ab)
	var p: Node2D = tool._create_new_paragraph_at(Vector2(10, 10))
	p.name = "ConFx"
	p.set_meta("effects", [{"type": "drop_shadow", "enabled": true, "color": Color(0, 0, 0, 0.5),
		"params": {"offset": Vector2(4, 4), "tint": Color(1, 0, 0)}}])
	var holder: Array = []
	var ab_b := await _roundtrip(ab, holder)
	var fx: Array = ab_b.get_node("ConFx").get_meta("effects", [])
	assert_int(fx.size()).is_equal(1)
	assert_that(fx[0]["color"]).is_equal(Color(0, 0, 0, 0.5))
	assert_that(fx[0]["params"]["offset"]).is_equal(Vector2(4, 4))
	assert_that(fx[0]["params"]["tint"]).is_equal(Color(1, 0, 0))

func test_reflow_no_borra_el_formato_del_marco() -> void:
	var scene := await _canvas()
	var ab: Node2D = scene.get_node("ArtboardsContainer/Artboard")
	var tool := await _para_tool(scene, ab)
	var p: Node2D = tool._create_new_paragraph_at(Vector2(10, 10))
	var n := String(p.get_meta("text")).length()
	p.set_meta("runs", [{"length": 5, "bold": true, "color": Color.RED}, {"length": n - 5, "bold": false, "color": Color.BLACK}])
	ParagraphThreading.reflow_chain(p)   # lo que hacía soltar un redimensionado
	var runs: Array = p.get_meta("runs")
	assert_bool(bool(runs[0]["bold"])).is_true()
	assert_that(runs[0]["color"]).is_equal(Color.RED)
