# =============================================================================
# PRUEBA DE UI REAL: cada modo tiene SUS paneles.
# Pedido del usuario: "pickr color de smart en pro y modern se ve tapado con
# barra de regla... si uno está activado y quiere cambiar a otro UI, éste
# debe desactivarse porque ya no es su parte".
# - Abrir en Smart (con sus botones) color, efectos y vista previa, y el panel
#   del clic derecho; pasar a Pro / Modern → todos cerrados, botones sin pulsar.
# - La ventana de Configuración (desde la que se cambia de modo) sigue abierta.
# - Configuración › Panels no ofrece los paneles de Smart en Modern / Pro.
# - De vuelta a Smart, el selector de color se abre en su sitio de siempre.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/mode_switch_panels_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const EXPECTED_CHECKS := 28
const SMART_PANELS := ["pickr_color_windows", "panel__effects", "Panel_PREVIEW"]
var fails := 0
var checks := 0
var main: Control

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func push_mouse(at: Vector2, pressed: Variant = null, btn: int = MOUSE_BUTTON_LEFT) -> void:
	var ev: InputEvent
	if pressed == null:
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.global_position = at
		ev = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.position = at
		mb.global_position = at
		mb.button_index = btn
		mb.pressed = pressed
		ev = mb
	root.push_input(ev)
	await process_frame

func click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	await push_mouse(at)
	await push_mouse(at, true)
	await push_mouse(at, false)
	await frames(6)

func button_for(panel_name: String) -> BaseButton:
	for b in main.find_children("*", "BaseButton", true, false):
		var t = b.get("target_panel") if "target_panel" in b else null
		if t is Control and String((t as Control).name) == panel_name:
			return b
		if "target_panel_path" in b and String(b.target_panel_path).ends_with(panel_name):
			return b
	return null

func node(n: String) -> Control:
	return main.find_child(n, true, false) as Control

func open_smart_panels() -> void:
	for n in SMART_PANELS:
		var b := button_for(n)
		if b and b.is_visible_in_tree():
			await click(b)
	# Panel del clic derecho de Smart, sobre el lienzo vacío.
	var spot := Vector2(main.size.x * 0.45, main.size.y * 0.6)
	await push_mouse(spot)
	await push_mouse(spot, true, MOUSE_BUTTON_RIGHT)
	await push_mouse(spot, false, MOUSE_BUTTON_RIGHT)
	await frames(6)

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	main = current_scene.find_child("main", true, false) as Control
	var gui = root.get_node("GlobalUI")
	gui.set_ui_mode("smart")
	await frames(20)
	var vw: float = root.get_visible_rect().size.x
	var pick := node("pickr_color_windows")
	var smart_rect_before := Rect2()

	for target in ["professional", "modern"]:
		gui.set_ui_mode("smart")
		await frames(20)
		await open_smart_panels()
		for n in SMART_PANELS:
			check("smart: se abre %s con su botón" % n, node(n) != null and node(n).visible)
		var tim := node("tool_in_Mouse")
		var tim_target: Control = tim.get("target_node") if tim else null
		check("smart: se abre el panel del clic derecho", tim_target != null and tim_target.visible)
		if smart_rect_before == Rect2() and pick:
			smart_rect_before = pick.get_global_rect()
		# Configuración abierta durante el cambio (se cambia de modo desde ahí).
		root.get_node("GlobalEvents").request_settings_dialog.emit()
		await frames(6)
		var settings := node("MANAGER WINDWS_REGLA")
		gui.set_ui_mode(target)
		await frames(25)
		for n in SMART_PANELS:
			check("%s: %s de Smart queda cerrado" % [target, n], node(n) == null or not node(n).visible)
			var b := button_for(n)
			check("%s: su botón deja de estar pulsado" % [target], b == null or not b.button_pressed, n)
		check("%s: el panel del clic derecho de Smart queda cerrado" % target, tim_target == null or not tim_target.visible)
		check("%s: Configuración sigue abierta" % target, settings != null and settings.visible)
		# Configuración › Panels no ofrece los paneles de Smart.
		var pv: Node = null
		for c in main.find_children("*", "BoxContainer", true, false):
			if c.get_script() and String(c.get_script().resource_path).ends_with("PanelVisibility.gd"):
				pv = c
		if pv:
			var any_row := false
			for i in mini(pv.get_child_count(), 5):
				var r := pv.get_child(i) as Control
				if r and r.name != "OnlySmartNote" and r.visible:
					any_row = true
			check("%s: Configuración › Panels no ofrece paneles de Smart" % target, not any_row)
		if settings:
			settings.visible = false

	# De vuelta a Smart: el selector de color en su sitio de siempre.
	gui.set_ui_mode("smart")
	await frames(20)
	var bp := button_for("pickr_color_windows")
	if bp:
		await click(bp)
	check("smart: el selector de color vuelve a abrirse", pick != null and pick.visible)
	if pick:
		check("smart: y en su sitio de siempre", pick.get_global_rect().position.distance_to(smart_rect_before.position) < 3.0,
			"%s vs %s" % [pick.get_global_rect(), smart_rect_before])
		pick.visible = false
		if bp:
			bp.set_pressed_no_signal(false)

	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	if checks < EXPECTED_CHECKS:
		check("el test hizo todas sus comprobaciones", false, "%d de %d" % [checks, EXPECTED_CHECKS])
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
