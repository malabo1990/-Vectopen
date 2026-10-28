# =============================================================================
# PRUEBA: paneles de herramienta acoplados en el inspector (Modern y Pro) y
# flotantes en Smart. Pedido del usuario: "cambiar los paneles de
# herramientas a inspector para UI modern y pro también".
# regression: en Modern los paneles se movían al inspector pero nunca se veían
# (visibility_changed conectado a un método que esperaba 1 argumento) y
# _align_subpanel los volvía a mover junto a Capas, fuera del lateral.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/tool_panels_dock_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const BUTTONS := {"bezier": "button_toolbezier", "brush": "button_toolbrush",
	"polygon": "button_toolbshapes", "text": "button_tooltext"}

var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)  # pantalla Huion completa
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(20)
	var main := current_scene.find_child("main", true, false) as Control
	var gui = root.get_node("GlobalUI")
	var vw: float = root.get_visible_rect().size.x
	for mode in ["modern", "professional", "smart"]:
		gui.set_ui_mode(mode)
		await frames(20)
		for key in BUTTONS:
			var b := main.find_child(BUTTONS[key], true, false) as Button
			var panel := b.target_node as Control if b else null
			if panel == null:
				check("%s: existe el panel %s" % [mode, key], false)
				continue
			if mode == "modern":
				# Modern ya no tiene la barra izquierda: se abre desde la de abajo.
				var tbs := root.find_children("*", "PanelContainer", true, false).filter(func(n): return n.get_script() != null and n.get_script().get_global_name() == "ModernBottomToolbar")
				var bkey: String = {"bezier": "bezier", "brush": "brush", "polygon": "shapes", "text": "text"}[key]
				if tbs.size() > 0:
					tbs[0]._buttons[bkey].pressed.emit()
			elif not panel.visible:
				b.pressed.emit()
			await frames(10)
			var r := panel.get_global_rect()
			var parent_name := String(panel.get_parent().name)
			if mode == "smart":
				check("%s: %s flota en la columna Herramientas" % [mode, key],
					parent_name == "Herramientas" and panel.is_visible_in_tree(), parent_name)
				check("%s: %s conserva su marco flotante" % [mode, key],
					not (panel.get_theme_stylebox("panel") is StyleBoxEmpty))
			else:
				check("%s: %s acoplado en el inspector" % [mode, key],
					panel.get_parent().get_parent() is ToolPanelDock, parent_name)
				check("%s: %s se ve" % [mode, key], panel.is_visible_in_tree())
				check("%s: %s está en el lateral derecho" % [mode, key],
					r.position.x > vw * 0.75 and r.end.x <= vw + 1.0, str(r))
			panel.visible = false
			await frames(5)
		# Sin herramienta abierta, la sección Herramienta no ocupa sitio.
		if mode != "smart":
			var docks := 0
			var any_dock_visible := false
			for d in root.find_children("*", "VBoxContainer", true, false):
				if d is ToolPanelDock:
					docks += 1
					if (d as Control).is_visible_in_tree():
						any_dock_visible = true
			check("%s: existe el dock de herramienta" % mode, docks > 0, str(docks))
			check("%s: sin herramienta abierta la sección se oculta" % mode, not any_dock_visible)
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
