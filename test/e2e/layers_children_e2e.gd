# =============================================================================
# PRUEBA DE UI REAL: las SUBCAPAS (hijos) siempre se ven en Capas.
# Pedido del usuario: "capas hay fallos para subcapas como hijos no visible
# en capas, revisa bien".
# Comprobación de fondo: TODAS las capas reales de la escena (recorriendo los
# artboards) tienen su fila en el árbol, colgando del padre correcto, tras
# cada camino que usa el usuario:
#   agrupar (botón / Ctrl+G), grupo dentro de grupo, figura dentro de figura,
#   deshacer / rehacer, duplicar un grupo, desagrupar, abrir un documento.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/layers_children_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://layers_children"
const EXPECTED_CHECKS := 20
const SAMPLE_DOC := "res://leon.vtc"
var fails := 0
var checks := 0
var ls = null
var ContextMenuActionsScript = load("res://script_gdscript/ui/context_menu_actions.gd")

func _init() -> void:
	_run.call_deferred()
	create_timer(220.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra.substr(0, 400) + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

## Capas reales bajo `n` (lo que el usuario espera ver en el panel).
func real_layers(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Node2D and ls._es_capa(c):
			out.append(c)
			real_layers(c, out)

## Toda capa real tiene fila, y su fila cuelga de la fila de su padre.
func tree_matches(what: String) -> void:
	await frames(8)
	var cont = ls.get("artboard_container")
	var layers: Array = []
	for ab in cont.get_children():
		if ls._es_artboard(ab):
			real_layers(ab, layers)
	var map: Dictionary = ls.get("_node_to_item_map")
	var missing: Array = []
	var wrong_parent: Array = []
	for n in layers:
		var it: TreeItem = map.get(n)
		if it == null or not is_instance_valid(it):
			missing.append(String(n.name))
			continue
		var pit: TreeItem = map.get(n.get_parent())
		if pit != null and it.get_parent() != pit:
			wrong_parent.append(String(n.name))
	check("%s: todas las subcapas tienen fila en Capas (%d capas)" % [what, layers.size()], missing.is_empty(), "faltan: %s" % [missing.slice(0, 12)])
	check("%s: cada subcapa cuelga de su padre" % what, wrong_parent.is_empty(), "mal colgadas: %s" % [wrong_parent.slice(0, 12)])

func _run() -> void:
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	ls = root.find_child("LayersSystem", true, false)
	var api = load("res://script_gdscript/api/vectopen_api.gd").new(root)
	var sm = root.get_node("SelectionManager")
	var hm = root.get_node("HistoryManager")

	# 1) Agrupar desde el menú contextual (como el usuario: clic derecho › Agrupar).
	var a: Node2D = api.add_rect(Vector2(200, 200), Vector2(80, 60), 0.0, "RectA")
	var b: Node2D = api.add_ellipse(Vector2(320, 200), Vector2(60, 60), "ElipseB")
	var c: Node2D = api.add_star(Vector2(200, 400), 40, 5, 0.5, "EstrellaC")
	await frames(6)
	sm.set_selection([a, b])
	await frames(4)
	ContextMenuActionsScript.execute("group", ls)
	await tree_matches("agrupar (botón)")
	# 2) Grupo dentro de grupo.
	var g1: Node = a.get_parent()
	sm.set_selection([g1, c])
	await frames(4)
	ContextMenuActionsScript.execute("group", ls)
	await tree_matches("grupo dentro de grupo")
	await shot("1_grupos")
	# 3) Deshacer / rehacer.
	hm.undo()
	await tree_matches("deshacer")
	hm.redo()
	await tree_matches("rehacer")
	# 4) Figura dentro de figura (arrastrar una capa sobre otra en el panel).
	var marco: Node2D = api.add_rect(Vector2(500, 500), Vector2(200, 150), 0.0, "Marco")
	var dentro: Node2D = api.add_ellipse(Vector2(500, 500), Vector2(40, 40), "Dentro")
	await frames(4)
	if ls.has_method("_reparent_with_undo"):
		ls._reparent_with_undo(dentro, marco)
	else:
		dentro.reparent(marco)
	await tree_matches("figura dentro de figura")
	var mit: TreeItem = ls.get("_node_to_item_map").get(marco)
	check("una figura con hijos NO se muestra como carpeta de grupo", mit != null and str(mit.get_metadata(0)) != "group", str(mit.get_metadata(0)) if mit else "-")
	# 5) Duplicar un grupo (Ctrl+D).
	sm.set_selection([a.get_parent().get_parent()])
	await frames(4)
	get_first_node_in_group("_vectopen_canvas").switch_tool("move")
	await frames(4)
	sm.set_selection([a.get_parent().get_parent()])
	await frames(4)
	var count_before := a.get_parent().get_parent().get_parent().get_child_count()
	ContextMenuActionsScript.execute("duplicate", ls)
	await frames(10)
	check("duplicar crea una copia del grupo", a.get_parent().get_parent().get_parent().get_child_count() > count_before)
	await tree_matches("duplicar un grupo")
	# 6) Desagrupar.
	sm.set_selection([a.get_parent()])
	await frames(4)
	ContextMenuActionsScript.execute("ungroup", ls)
	await tree_matches("desagrupar")
	await shot("2_tras_ops")
	# 7) Abrir un documento real con grupos (vectorizado del león).
	if FileAccess.file_exists(SAMPLE_DOC):
		# Directo (sin SaveManager): no toca la lista de recientes del usuario.
		root.get_node("DataRepository").load_project(ProjectSettings.globalize_path(SAMPLE_DOC))
		await frames(40)
		await tree_matches("abrir leon.vtc")
		await shot("3_leon")
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
