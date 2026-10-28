# =============================================================================
# AUDITORÍA VISUAL: los 3 modos de UI (Smart, Modern, Pro) con cada panel de
# herramienta abierto (Selector, Bézier, Pincel, Polígono, Texto). Guarda una
# captura por combinación en user://ui_modes_shot/ y restaura el modo del
# usuario al terminar. No es una prueba (no falla): sirve para revisar a ojo.
#   flatpak run --command=godot org.godotengine.Godot --path . \
#       -s res://test/e2e/ui_modes_shot.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const OUT := "user://ui_modes_shot"
const TOOL_BUTTONS := {
	"selector": "Button2",
	"bezier": "button_toolbezier",
	"brush": "button_toolbrush",
	"polygon": "button_toolbshapes",
	"text": "button_tooltext",
}

func _init() -> void:
	_run.call_deferred()

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))
	print("SHOT ", name)

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var main := current_scene.find_child("main", true, false) as Control
	var gui = root.get_node("GlobalUI")
	var modes := ["smart", "modern", "professional"]
	if OS.has_environment("VECTOPEN_SHOT_MODES"):
		modes = Array(OS.get_environment("VECTOPEN_SHOT_MODES").split(","))
	for mode in modes:
		gui.set_ui_mode(mode)
		await frames(30)
		await shot("%s_00_none" % mode)
		for key in TOOL_BUTTONS:
			var b := main.find_child(TOOL_BUTTONS[key], true, false) as Button
			if b == null:
				print("NOBUTTON ", key)
				continue
			var target: Control = b.target_node as Control if "target_node" in b else null
			if target and not target.visible:
				b.pressed.emit()
			elif target == null:
				b.pressed.emit()
			await frames(20)
			print("PANEL %s/%s visible=%s in_tree=%s parent=%s rect=%s" % [mode, key,
				target.visible if target else "-", target.is_visible_in_tree() if target else "-",
				String(target.get_parent().name) if target else "-",
				target.get_global_rect() if target else "-"])
			if target and target.visible and not target.is_visible_in_tree():
				var hidden := []
				var n: Node = target
				while n:
					if n is CanvasItem and not (n as CanvasItem).visible:
						hidden.append(String(n.name))
					n = n.get_parent()
				print("HIDDEN_ANCESTORS ", key, " ", hidden)
			await shot("%s_%s" % [mode, key])
			if target and target.visible:
				target.visible = false
			await frames(5)
	# Restaurar el modo del usuario.
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("DONE")
	quit(0)
