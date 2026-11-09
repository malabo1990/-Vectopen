# =============================================================================
# SONDA DE MEMORIA: cuánto ocupa Vectopen vacío (por partes) y cuánto cuesta
# cada tipo de elemento. Salida: líneas «MEM clave=valor».
#   E2E_TIMEOUT=600 test/run_e2e.sh memory_probe_e2e
#   MEM_N=1000 (elementos por tipo) · MEM_TREE=1 (nodos por rama de la UI)
# =============================================================================
extends SceneTree

var N := 1000

func _init() -> void:
	N = int(OS.get_environment("MEM_N")) if OS.has_environment("MEM_N") else 1000
	_run.call_deferred()
	create_timer(560.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

## Memoria residente real del proceso (MB), no solo la que cuenta Godot.
func rss_mb() -> float:
	# /proc no tiene tamaño: leer línea a línea
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return -1.0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmRSS:"):
			return float(line.split(":")[1].strip_edges().split(" ")[0]) / 1024.0
	return -1.0

func snap(tag: String) -> Dictionary:
	await frames(20)
	var d := {
		"rss": snappedf(rss_mb(), 0.1),
		"static": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"tex_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"vid_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
	}
	var parts: Array = []
	for k in d:
		parts.append("%s=%s" % [k, str(d[k])])
	print("MEM %s %s" % [tag, " ".join(parts)])
	return d

## RSS por archivo mapeado (bibliotecas, controlador gráfico) y anónimo (montón).
func smaps_report(tag: String) -> void:
	var f := FileAccess.open("/proc/self/smaps", FileAccess.READ)
	if f == null:
		return
	var by := {}
	var cur := "[anon]"
	var head := RegEx.create_from_string("^[0-9a-f]+-[0-9a-f]+ ")
	while not f.eof_reached():
		var line := f.get_line()
		if head.search(line):
			var cols := line.split(" ", false)
			cur = cols[5].get_file() if cols.size() >= 6 else "[anon]"
		elif line.begins_with("Rss:"):
			var kb := int(line.split(":")[1].strip_edges().split(" ")[0])
			by[cur] = int(by.get(cur, 0)) + kb
	var arr: Array = []
	for k in by:
		arr.append([by[k], k])
	arr.sort_custom(func(a, b) -> bool: return a[0] > b[0])
	for i in mini(18, arr.size()):
		print("SMAPS %s %s %.1f MB" % [tag, arr[i][1], arr[i][0] / 1024.0])

func count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children(true):
		c += count_nodes(ch)
	return c

func tree_report(n: Node, depth: int, max_depth: int, min_nodes: int, prefix: String) -> void:
	var kids: Array = []
	for ch in n.get_children(true):
		kids.append([count_nodes(ch), ch])
	kids.sort_custom(func(a, b) -> bool: return a[0] > b[0])
	for k in kids:
		if k[0] < min_nodes:
			break
		print("TREE %s%s (%s) %d" % [prefix, k[1].name, k[1].get_class(), k[0]])
		if depth < max_depth:
			tree_report(k[1], depth + 1, max_depth, min_nodes, prefix + "  ")

func _run() -> void:
	DisplayServer.window_set_current_screen(mini(1, DisplayServer.get_screen_count() - 1))
	await snap("motor_y_autoloads")
	smaps_report("motor")
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(60)
	var gui = root.get_node("GlobalUI")
	var base := await snap("arranque_%s" % str(gui.get("ui_mode")))
	smaps_report("arranque")
	if OS.get_environment("MEM_QUICK") == "1":
		print("RESULT: OK")
		quit(0)
		return
	if OS.get_environment("MEM_TREE") == "1":
		tree_report(root, 0, 3, 150, "")
	for m in ["smart", "modern", "professional", "smart"]:
		gui.set_ui_mode(m)
		await frames(30)
		await snap("modo_" + m)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").api
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var kinds := {
		"rect": func(i: int): return api.add_rect(Vector2((i % 40) * 30, (i / 40) * 30), Vector2(22, 16)),
		"star": func(i: int): return api.add_star(Vector2((i % 40) * 30, (i / 40) * 30), 11, 5),
		"text": func(i: int): return api.add_text(Vector2((i % 40) * 40, (i / 40) * 30), "Txt%d" % i, 12, Color.BLACK),
		"brush": func(i: int):
			var l := Line2D.new()
			var pts := PackedVector2Array()
			for k in 24:
				pts.append(Vector2((i % 40) * 30 + k * 1.1, (i / 40) * 30 + sin(k * 0.5) * 6.0))
			l.points = pts
			l.width = 3.0
			l.set_meta("brush_style", "pen")
			ab.add_child(l)
			load("res://script_gdscript/shapes/brush_stroke_render.gd").attach(l)
			return l,
	}
	if OS.get_environment("MEM_MICRO") == "1":
		await _micro(ab)
		print("RESULT: OK")
		quit(0)
		return
	var prev := await snap("antes_de_elementos")
	for kind in kinds:
		var made: Array = []
		for i in N:
			made.append(kinds[kind].call(i))
			if i % 200 == 199:
				await process_frame
		var now := await snap("con_%d_%s" % [N, kind])
		print("MEM por_%s kb=%.1f nodos=%.2f objetos=%.2f" % [kind,
			(now["rss"] - prev["rss"]) * 1024.0 / N,
			float(now["nodes"] - prev["nodes"]) / N,
			float(now["objects"] - prev["objects"]) / N])
		for n in made:
			if is_instance_valid(n):
				n.get_parent().remove_child(n)
				n.free()
		prev = await snap("sin_%s" % kind)
	# Mismos tipos al ABRIR un documento (sin historial de deshacer)
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	for kind in kinds:
		var tpl := Node2D.new()
		ab.add_child(tpl)
		var one = kinds[kind].call(0)
		await frames(4)
		if one.get_parent() != tpl:
			one.reparent(tpl)
		var data: Array = Ser.serialize_elements(tpl)
		tpl.free()
		var before := await snap("abrir_antes_%s" % kind)
		var holder := Node2D.new()
		ab.add_child(holder)
		for i in N:
			Ser.instantiate_elements(holder, data)
			if i % 200 == 199:
				await process_frame
		var after := await snap("abrir_%d_%s" % [N, kind])
		print("MEM abrir_por_%s kb_static=%.1f kb_rss=%.1f nodos=%.2f objetos=%.2f" % [kind,
			(after["static"] - before["static"]) * 1024.0 / N,
			(after["rss"] - before["rss"]) * 1024.0 / N,
			float(after["nodes"] - before["nodes"]) / N,
			float(after["objects"] - before["objects"]) / N])
		holder.free()
	# Coste de cada panel: liberarlo y medir (destructivo, al final)
	var main_ui: Node = canvas.get_parent().find_child("main", true, false) if canvas else null
	if main_ui == null:
		main_ui = root.find_child("main", true, false)
	if main_ui:
		for pname in ["keyboard", "ProStudio", "DockedInspector", "tool_in_Mouse", "windows_ recla", "panel__effects", "Panel_export", "Layout"]:
			var n := main_ui.get_node_or_null(NodePath(pname))
			if n == null:
				continue
			var nn := count_nodes(n)
			var b := await snap("panel_antes_" + pname.replace(" ", "_"))
			n.get_parent().remove_child(n)
			n.free()
			var a := await snap("panel_sin_" + pname.replace(" ", "_"))
			print("MEM panel_%s nodos=%d mb_static=%.1f mb_rss=%.1f" % [pname.replace(" ", "_"), nn, b["static"] - a["static"], b["rss"] - a["rss"]])
	print("MEM arranque_vs_motor rss=%.1f" % (base["rss"]))
	print("RESULT: OK")
	quit(0)

var _group_node: Node2D = null
func _grp(ab: Node2D) -> Node2D:
	if not is_instance_valid(_group_node):
		_group_node = Node2D.new()
		_group_node.name = "GrupoSonda"
		_group_node.set_meta("shape_type", "group")
		ab.add_child(_group_node)
	return _group_node

## Desglose del coste de UNA figura: nodo vacío, objeto sin árbol, en el
## árbol (dibujada), con estilo.
func _micro(ab: Node2D) -> void:
	var M := 2000
	var steps := [
		["node2d", func(): var n := Node2D.new(); ab.add_child(n); return n],
		["rect_sin_arbol", func(): var r := VectorRectangle.new(); r.size = Vector2(22, 16); return r],
		["rect_en_arbol", func(): var r := VectorRectangle.new(); r.size = Vector2(22, 16); ab.add_child(r); return r],
		["rect_sin_trazo", func(): var r := VectorRectangle.new(); r.size = Vector2(22, 16); r.stroke_width = 0.0; ab.add_child(r); return r],
		["rect_oculto", func(): var r := VectorRectangle.new(); r.size = Vector2(22, 16); r.visible = false; ab.add_child(r); return r],
		["rect_oculto_en_grupo", func(): var r := VectorRectangle.new(); r.size = Vector2(22, 16); r.visible = false; _grp(ab).add_child(r); return r],
		["node2d_en_grupo", func(): var n := Node2D.new(); _grp(ab).add_child(n); return n],
		["node2d_grupo_fino", func(): var n := Node2D.new(); _grp(ab).add_child(n); n.add_to_group("vo_thin_stroke"); return n],
		["rect_grupo_trazo", func(): var r := VectorRectangle.new(); r.size = Vector2(22, 16); _grp(ab).add_child(r); return r],
		["rect_grupo_trazo_grueso", func(): var r := VectorRectangle.new(); r.size = Vector2(22, 16); r.stroke_width = 6.0; _grp(ab).add_child(r); return r],
		["rect_grupo_sin_trazo", func(): var r := VectorRectangle.new(); r.size = Vector2(22, 16); r.stroke_width = 0.0; _grp(ab).add_child(r); return r],
	]
	var src := """extends Node2D
var mode := 0
func _draw():
	var r := Rect2(-11, -8, 22, 16)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	match mode:
		0: draw_rect(r, Color.RED)
		1: draw_colored_polygon(pts, Color.RED)
		2: draw_rect(r, Color.BLACK, false, 2.0)
		3:
			draw_rect(Rect2(r.position.x - 1, r.position.y - 1, r.size.x + 2, 2), Color.BLACK)
			draw_rect(Rect2(r.position.x - 1, r.end.y - 1, r.size.x + 2, 2), Color.BLACK)
			draw_rect(Rect2(r.position.x - 1, r.position.y + 1, 2, r.size.y - 2), Color.BLACK)
			draw_rect(Rect2(r.end.x - 1, r.position.y + 1, 2, r.size.y - 2), Color.BLACK)
		4: RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array([0,1,2,0,2,3]), pts, PackedColorArray([Color.RED]))
"""
	var sc := GDScript.new()
	sc.source_code = src
	sc.reload()
	for m in 5:
		var mm: int = m
		steps.append(["prim_%d" % m, func(): var n := Node2D.new(); n.set_script(sc); n.set("mode", mm); ab.add_child(n); return n])
	if OS.get_environment("MEM_PRIM") == "1":
		steps = steps.slice(5)
	for st in steps:
		var b := await snap("micro_antes_" + st[0])
		var keep: Array = []
		for i in M:
			keep.append(st[1].call())
		await frames(10)
		var a := await snap("micro_" + st[0])
		print("MEM micro_%s kb_static=%.2f objetos=%.2f" % [st[0], (a["static"] - b["static"]) * 1024.0 / M, float(a["objects"] - b["objects"]) / M])
		for n in keep:
			if is_instance_valid(n):
				if n.get_parent():
					n.get_parent().remove_child(n)
				n.free()
		await frames(5)
