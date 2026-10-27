# =============================================================================
# PRUEBA DE INTERFAZ REAL del panel Exportar: trabajo en LOTE y ajustes por
# formato.
#   · «Todo» marca / desmarca todas las filas; contador «n de m»;
#   · «Formato para todas» pone el mismo formato a todas (o a las marcadas);
#   · el botón dice cuántas va a exportar y las exporta de una vez;
#   · calidad de JPEG: el archivo cambia de verdad; WEBP «Sin pérdida»;
#   · los ajustes de cada formato se guardan (vectopen_export.cfg).
#   flatpak run --command=godot org.godotengine.Godot --path . \
#       -s res://test/e2e/export_bulk_e2e.gd
# =============================================================================
extends SceneTree

var fails := 0
var _mouse := Vector2.ZERO

func _init() -> void:
	_run.call_deferred()

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _send(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		Input.warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	_send(m)
	await process_frame
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		e.global_position = at
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		_send(e)
		await process_frame
	await frames(2)

func _run() -> void:
	Input.use_accumulated_input = false
	var cfg_path := "user://vectopen_export.cfg"
	var cfg_backup := FileAccess.get_file_as_string(cfg_path) if FileAccess.file_exists(cfg_path) else ""
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await frames(20)
	var api = root.get_node("PluginManager").api
	for c in api.shapes():
		c.get_parent().remove_child(c)
		c.queue_free()
	var cen: Vector2 = api.artboard_size() / 2.0
	for i in 3:
		var r: Node2D = api.add_rect(cen + Vector2(-200 + i * 200, 0), Vector2(150, 150))
		api.set_fill(r, Color.from_hsv(i / 3.0, 0.7, 0.9))
	var main := current_scene.find_child("main", true, false)
	(main.get_node("Panel_export") as Control).visible = true
	await frames(6)
	var panel = get_first_node_in_group("vectopen_export_rows")
	panel.set_scope("layers")
	await frames(4)
	check("3 filas (una por capa)", panel.rows().size() == 3, str(panel.rows().size()))

	# «Todo» con clic real
	var all_chk: CheckBox = panel.find_child("CheckAll", true, false)
	await click(all_chk)
	var n_checked: int = panel.rows().filter(func(r) -> bool: return r.checked).size()
	check("«Todo» marca todas las filas", n_checked == 3, str(n_checked))
	check("contador «3 de 3»", String(panel.find_child("Count", true, false).text) == "3 de 3", panel.find_child("Count", true, false).text)
	check("el botón dice cuántas exporta", String(panel._export_btn.text).begins_with("Exportar 3 marcados"), panel._export_btn.text)

	# Formato para todas
	var bulk: OptionButton = panel.find_child("BulkFormat", true, false)
	bulk.select(panel.FORMATS.find("JPEG") + 1)
	bulk.item_selected.emit(panel.FORMATS.find("JPEG") + 1)
	await frames(2)
	var fmts: Array = panel.rows().map(func(r) -> String: return r.format)
	check("«Formato para todas» → JPEG en las 3", fmts == ["JPEG", "JPEG", "JPEG"], str(fmts))

	# Calidad de JPEG: cambia el archivo
	var out := ProjectSettings.globalize_path("user://export_bulk_test")
	DirAccess.make_dir_recursive_absolute(out)
	for f in DirAccess.get_files_at(out):
		DirAccess.remove_absolute(out.path_join(f))
	panel.set_fmt_value("JPEG", "quality", 20.0)
	var low: PackedStringArray = await panel.export_rows_to([panel.rows()[0]], out)
	panel.set_fmt_value("JPEG", "quality", 98.0)
	var high: PackedStringArray = await panel.export_rows_to([panel.rows()[0]], out)
	var sz_low := FileAccess.get_file_as_bytes(low[0]).size() if low.size() == 1 else 0
	var sz_high := FileAccess.get_file_as_bytes(high[0]).size() if high.size() == 1 else 0
	check("calidad JPEG 98 % da un archivo mayor que 20 %", sz_low > 0 and sz_high > sz_low, "%d → %d bytes" % [sz_low, sz_high])

	# Exportar todas de una vez (las 3 marcadas)
	for f in DirAccess.get_files_at(out):
		DirAccess.remove_absolute(out.path_join(f))
	panel.dest_dir = out
	var all_out: PackedStringArray = await panel.export_checked()
	check("exportar marcados escribe las 3 de una vez", all_out.size() == 3 and DirAccess.get_files_at(out).size() == 3, "%d archivos" % all_out.size())

	# Ajustes de formato en la interfaz: fichas y controles propios de cada formato
	var toggle: Button = panel.find_child("FormatSettingsToggle", true, false)
	await click(toggle)
	var sec: Control = panel.find_child("FormatSettings", true, false)
	check("«Ajustes de formato» se despliega", sec.visible)
	panel.show_format_settings("WEBP")
	await frames(2)
	check("WEBP: calidad + sin pérdida + sin fondo", sec.find_child("Quality", true, false) != null
		and sec.find_child("lossless", true, false) != null and sec.find_child("transparent", true, false) != null)
	panel.show_format_settings("SVG")
	await frames(2)
	check("SVG: sin calidad, con texto a curvas", sec.find_child("Quality", true, false) == null and sec.find_child("text_curves", true, false) != null)
	# WEBP sin pérdida: se aplica al exportar
	panel.set_fmt_value("WEBP", "lossless", true)
	check("WEBP sin pérdida llega al exportador", bool(panel.settings_for(_row_as(panel, "WEBP"))["lossless"]))
	# Se guarda por formato
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)
	var saved = cfg.get_value("formats", "JPEG", {})
	check("ajustes por formato guardados", saved is Dictionary and is_equal_approx(float(saved.get("quality", 0)), 98.0), str(saved))

	# Desmarcar todo
	await click(all_chk)
	check("«Todo» otra vez desmarca", panel.rows().filter(func(r) -> bool: return r.checked).is_empty())

	if cfg_backup != "":
		var f := FileAccess.open(cfg_path, FileAccess.WRITE)
		f.store_string(cfg_backup)
		f.close()
	print("RESULT %s (%d fallos)" % ["OK" if fails == 0 else "FALLOS", fails])
	quit(1 if fails > 0 else 0)

## Una fila con el formato `fmt` (la primera, cambiada).
func _row_as(panel, fmt: String):
	var r = panel.rows()[0]
	r.set_format(fmt)
	return r
