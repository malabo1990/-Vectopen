extends GdUnitTestSuite
## USR-07/10/11/12: abrir el archivo del arranque, app predeterminada, aviso
## al salir, guardado automático e historial de 1000 pasos.
const CANVAS := "res://scenes/canvas/canvas.tscn"
var _prefs_backup := ""

func before() -> void:
	if FileAccess.file_exists(SaveManager.PREFS_PATH):
		_prefs_backup = FileAccess.get_file_as_string(SaveManager.PREFS_PATH)

func after() -> void:
	if _prefs_backup != "":
		var f := FileAccess.open(SaveManager.PREFS_PATH, FileAccess.WRITE)
		f.store_string(_prefs_backup)
	elif FileAccess.file_exists(SaveManager.PREFS_PATH):
		DirAccess.remove_absolute(SaveManager.PREFS_PATH)

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	HistoryManager.clear()
	SaveManager.current_path = ""
	SaveManager.is_modified = false
	SaveManager._quiet_frames = 0
	SaveManager._quit_after_save = false

func after_test() -> void:
	if is_instance_valid(SaveManager._quit_dialog):
		SaveManager._quit_dialog.queue_free()
	SaveManager._quit_dialog = null
	SaveManager.current_path = ""
	SaveManager.is_modified = false
	SaveManager.autosave_enabled = true
	HistoryManager.clear()

func test_archivos_del_arranque() -> void:
	var exists := func(p: String) -> bool: return not p.contains("noexiste")
	var got := LaunchFiles.from_args(PackedStringArray([
		"--path", "/proyecto", "-s", "res://test/x.gd", "--screen", "1",
		"/home/u/logo.svg", "file:///home/u/mi%20dibujo.vtp", "/home/u/plano.pdf",
		"/home/u/foto.afdesign", "/home/u/noexiste.svg", "/home/u/notas.txt", "/home/u/logo.svg"]), exists)
	assert_array(Array(got)).contains_exactly(["/home/u/logo.svg", "/home/u/mi dibujo.vtp", "/home/u/plano.pdf", "/home/u/foto.afdesign"])

func test_lanzador_linux_con_tipos_y_preferencia() -> void:
	var d := DefaultApp.desktop_entry("/opt/x/Vectopen.AppImage")
	assert_str(d).contains("Exec=\"/opt/x/Vectopen.AppImage\" %F")
	assert_str(d).contains("application/x-vectopen;")
	assert_str(d).contains("image/svg+xml;")
	assert_str(d).contains("application/x-affinity-designer;")
	assert_str(d).contains("InitialPreference=9")
	# PDF e imágenes: en «Abrir con», pero no se imponen por defecto.
	assert_bool("application/pdf" in DefaultApp.DEFAULT_MIMES).is_false()

func test_registro_windows() -> void:
	var cmds := DefaultApp.windows_commands("C:\\Apps\\Vectopen\\Vectopen.exe")
	var joined := "\n".join(PackedStringArray(cmds.map(func(c): return " ".join(PackedStringArray(c)))))
	assert_str(joined).contains("HKCU\\Software\\Classes\\Vectopen.Document\\shell\\open\\command /ve /d \"C:\\Apps\\Vectopen\\Vectopen.exe\" \"%1\"")
	assert_str(joined).contains("HKCU\\Software\\Classes\\.svg\\OpenWithProgids /v Vectopen.Document")
	assert_str(joined).contains("HKCU\\Software\\Classes\\.vtp /ve /d Vectopen.Document")

func test_historial_de_1000_pasos() -> void:
	assert_int(HistoryManager._undo_redo.max_history).is_equal(SaveManager.undo_steps)
	assert_int(SaveManager.DEFAULT_UNDO_STEPS).is_equal(1000)

func test_un_cambio_marca_el_documento() -> void:
	assert_bool(SaveManager.is_modified).is_false()
	PluginManager.api.add_rect(Vector2(10, 10), Vector2(40, 40))
	assert_bool(SaveManager.is_modified).is_true()

func test_abrir_no_cuenta_como_cambio() -> void:
	SaveManager._quiet_frames = 3
	HistoryManager.clear()
	assert_bool(SaveManager.is_modified).is_false()

func test_guardado_automatico_en_su_vtp() -> void:
	var path := ProjectSettings.globalize_path("user://test_autosave.vtp")
	DirAccess.remove_absolute(path)
	SaveManager.current_path = path
	SaveManager.autosave_enabled = true
	PluginManager.api.add_rect(Vector2(10, 10), Vector2(40, 40))
	assert_bool(SaveManager.is_modified).is_true()
	assert_bool(SaveManager._autosave_timer.is_stopped()).is_false()   # programado
	SaveManager._on_autosave_timeout()
	assert_bool(FileAccess.file_exists(path)).is_true()
	assert_bool(SaveManager.is_modified).is_false()
	DirAccess.remove_absolute(path)

func test_salir_sin_nombre_pregunta() -> void:
	PluginManager.api.add_rect(Vector2(10, 10), Vector2(40, 40))
	SaveManager.request_quit()
	assert_object(SaveManager._quit_dialog).is_not_null()
	assert_bool(SaveManager._quit_dialog.visible).is_true()
	assert_str(SaveManager._quit_dialog.ok_button_text).is_equal("Guardar")
