# =============================================================================
# PRUEBA DE INTERFAZ REAL: abrir cada panel con CLICS de ratón simulados
# (como el usuario), tras el arranque por fases (StartupPhases):
#   - botones de la barra (selector de color, efectos, exportar, ajustes)
#   - las 5 pestañas de Efectos (Efectos, Filtros, Vectorizar, Shader, Script)
#   - menú del botón derecho sobre el lienzo
#   - modo Modern: inspector acoplado y barras
#   flatpak run --command=godot org.godotengine.Godot --path . \
#       -s res://test/e2e/panels_open_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"

var fails := 0
var _mouse := Vector2.ZERO
var main: Control

func _init() -> void:
	_run.call_deferred()

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func move(to: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = to - _mouse
	_mouse = to
	_send(ev)
	await process_frame

func button(at: Vector2, pressed: bool, btn: int = MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = at
	ev.global_position = at
	ev.button_index = btn
	ev.pressed = pressed
	ev.button_mask = (MOUSE_BUTTON_MASK_LEFT if btn == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	_send(ev)
	await process_frame

## Clic real en el centro de `c`. Devuelve false si otro control lo tapa.
func click(c: Control, btn: int = MOUSE_BUTTON_LEFT) -> bool:
	var at := c.get_global_rect().get_center()
	await move(at)
	await frames(1)
	var hovered := root.gui_get_hovered_control()
	var reachable := hovered == c or (hovered != null and c.is_ancestor_of(hovered))
	await button(at, true, btn)
	await button(at, false, btn)
	await frames(3)
	return reachable

func _toggle_button_for(panel_name: String) -> Button:
	for b in main.find_children("*", "Button", true, false):
		if "target_panel_path" in b and String(b.target_panel_path).ends_with(panel_name):
			return b
		if "target_panel" in b and b.target_panel and String(b.target_panel.name) == panel_name:
			return b
	return null

func _run() -> void:
	Input.use_accumulated_input = false
	# Guardar el modo de UI del usuario: la prueba pasa por Modern y vuelve.
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)  # pantalla Huion completa
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await frames(20)
	main = current_scene.find_child("main", true, false) as Control
	check("arranque por fases completo", Engine.has_meta(&"vectopen_startup_done"))
	var gui = root.get_node("GlobalUI")
	if gui.get_ui_mode() != "smart":
		gui.set_ui_mode("smart")
		await frames(10)

	# 1. Botones de la barra que abren paneles (antes del arreglo: color y
	#    efectos no se abrían con el arranque por fases).
	for panel_name in ["pickr_color_windows", "panel__effects", "Panel_export", "MANAGER WINDWS_REGLA"]:
		var b := _toggle_button_for(panel_name)
		check("existe botón para " + panel_name, b != null)
		if b == null or not b.is_visible_in_tree():
			check("botón visible para " + panel_name, false)
			continue
		var reachable := await click(b)
		var panel := b.target_panel as Control
		check("clic abre " + panel_name, reachable and panel != null and panel.is_visible_in_tree(),
			"alcanzable=%s panel=%s" % [reachable, panel])
		if panel:
			# Exportar tapa su botón al abrirse: se cierra con su ✕ (BtnClose).
			var closer: Control = panel.find_child("BtnClose", true, false) if panel_name == "Panel_export" else b
			await click(closer)
			check(("✕ cierra " if closer != b else "segundo clic cierra ") + panel_name, not panel.visible)
			panel.visible = false

	# 2. Pestañas de Efectos: cada botón muestra su pestaña con contenido.
	var fx_panel := main.get_node("panel__effects") as Control
	fx_panel.visible = true
	await frames(5)
	var header := fx_panel.find_child("HBoxContainer", true, false) as HBoxContainer
	var content := fx_panel.get_node("PanelContainer/VBoxContainer/VBoxContainer") as Container
	var tabs := {
		"ButtonEffects": ["effects", ""],
		"ButtonFilters": ["Filters", ""],
		"ButtonVectorize": ["Vectorizar", "VectorizePanel"],
		"ButtonShader": ["Shader", "ShaderPanel"],
		"ButtonScript": ["Script", "ScriptPanel"],
	}
	for btn_name in tabs:
		var tb := header.get_node_or_null(btn_name) as Button
		var host := content.get_node_or_null(tabs[btn_name][0]) as Control
		if tb == null or host == null:
			check("pestaña " + btn_name + " existe", false, "botón=%s anfitrión=%s" % [tb, host])
			continue
		var reachable := await click(tb)
		await frames(5)
		var inner: String = tabs[btn_name][1]
		var has_content := inner == "" or host.find_child(inner, true, false) != null
		var sz := host.size
		check("pestaña " + tabs[btn_name][0] + " se abre con contenido",
			reachable and host.is_visible_in_tree() and has_content and sz.x > 50 and sz.y > 50,
			"alcanzable=%s visible=%s contenido=%s tamaño=%s" % [reachable, host.is_visible_in_tree(), has_content, sz])
	# Ancho por pestaña: Shader ancho y al volver a Efectos vuelve a compacto.
	await click(header.get_node("ButtonShader"))
	await frames(4)
	var w_shader := fx_panel.size.x
	await click(header.get_node("ButtonEffects"))
	await frames(4)
	var w_fx := fx_panel.size.x
	check("Shader ensancha el panel y Efectos lo vuelve a encoger", w_shader >= 700.0 and w_fx <= 400.0,
		"shader=%.0f efectos=%.0f" % [w_shader, w_fx])
	check("el panel sigue pegado a la derecha", absf(fx_panel.get_global_rect().end.x - (main.size.x - 16.0)) < 2.0, str(fx_panel.get_global_rect()))
	fx_panel.visible = false
	await frames(3)

	# 3. Menú del botón derecho sobre el lienzo vacío.
	var menu := main.get_node("tool_in_Mouse") as Control
	var spot := Vector2(main.size.x * 0.5, main.size.y * 0.55)
	await move(spot)
	await button(spot, true, MOUSE_BUTTON_RIGHT)
	await button(spot, false, MOUSE_BUTTON_RIGHT)
	await frames(5)
	check("clic derecho abre el menú contextual", menu.visible, "sobre UI=%s" % gui.is_mouse_over_ui)
	menu.visible = false

	# 4. Diálogo de ajustes por evento global (menú / atajo).
	var settings := main.find_child("MANAGER WINDWS_REGLA", true, false) as Control
	root.get_node("GlobalEvents").request_settings_dialog.emit()
	await frames(5)
	check("ajustes se abren por evento", settings != null and settings.visible)
	if settings:
		settings.visible = false

	# 5. Modo Modern: inspector acoplado y barras modernas visibles.
	gui.set_ui_mode("modern")
	await frames(15)
	for n in ["DockedInspector", "ModernTopBar", "ModernBottomToolbar"]:
		var c := main.get_node_or_null(n) as Control
		check("Modern muestra " + n, c != null and c.is_visible_in_tree())
	# El raíl lateral se quitó de Modern a propósito (ajustes en la barra superior).
	check("Modern oculta ModernNavRail", not (main.get_node("ModernNavRail") as Control).visible)
	gui.set_ui_mode("smart")
	await frames(10)
	check("Smart oculta el inspector acoplado", not (main.get_node("DockedInspector") as Control).visible)

	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT %s (%d fallos)" % ["OK" if fails == 0 else "FALLOS", fails])
	quit(1 if fails > 0 else 0)
