extends Node

signal project_saved(path: String)
signal project_loaded(path: String)
signal save_state_changed(is_modified: bool)

var current_path: String = ""
var is_modified: bool = false
var _active_file_dialog: FileDialog = null

# ── Guardado automático, aviso al salir e historial (USR-10/11/12) ───────────
## Preferencias de archivos (Ajustes ▸ Archivos).
const IoGuard = preload("res://script_gdscript/system/io_guard.gd")
const PREFS_PATH := "user://vectopen_files.cfg"
## Un .vtp con nombre se guarda solo, AUTOSAVE_DELAY s después del último
## cambio (como Figma / Penpot); uno sin nombre deja una copia en Recuperar.
const AUTOSAVE_DELAY := 2.0
const DEFAULT_UNDO_STEPS := 1000
var autosave_enabled := true
var undo_steps := DEFAULT_UNDO_STEPS
var _autosave_timer: Timer = null
var _quiet_frames := 0          # abrir / nuevo: el historial se vacía, no es un cambio
var _quit_dialog: ConfirmationDialog = null
var _quit_after_save := false

func _ready() -> void:
	load_prefs()
	_autosave_timer = Timer.new()
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DELAY
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)
	# Salir con la X, Alt+F4, cerrar sesión o apagar: primero se pregunta.
	get_tree().set_auto_accept_quit(false)
	var hm := get_node_or_null("/root/HistoryManager")
	if hm:
		hm.history_changed.connect(_on_history_changed)
		apply_undo_steps.call_deferred()

func _process(_d: float) -> void:
	if _quiet_frames > 0:
		_quiet_frames -= 1

func load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) == OK:
		autosave_enabled = bool(cfg.get_value("files", "autosave", true))
		undo_steps = clampi(int(cfg.get_value("files", "undo_steps", DEFAULT_UNDO_STEPS)), 10, 5000)

func save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PREFS_PATH)
	cfg.set_value("files", "autosave", autosave_enabled)
	cfg.set_value("files", "undo_steps", undo_steps)
	cfg.save(PREFS_PATH)

func set_autosave(on: bool) -> void:
	autosave_enabled = on
	save_prefs()
	if on and is_modified:
		_autosave_timer.start()

func set_undo_steps(n: int) -> void:
	undo_steps = clampi(n, 10, 5000)
	save_prefs()
	apply_undo_steps()

func apply_undo_steps() -> void:
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.get("_undo_redo"):
		hm._undo_redo.max_history = undo_steps

func _on_history_changed(_u: bool, _r: bool, _un: String, _rn: String) -> void:
	if _quiet_frames > 0:
		return
	mark_modified()

func _on_autosave_timeout() -> void:
	if not is_modified or not autosave_enabled:
		return
	# Con el ratón pulsado (arrastrando, dibujando) se espera a que suelte.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_autosave_timer.start(0.5)
		return
	autosave_now()

## Guarda ya (sin diálogos): en su .vtp si tiene nombre; si no, una copia en
## Recuperar. Devuelve la ruta escrita o "".
func autosave_now() -> String:
	if current_path != "" and current_path.get_extension().to_lower() in ["vtp", "vtc"]:
		_save_to_path(current_path, true)
		return current_path if not is_modified else ""
	return IoGuard.snapshot_if_unsaved(get_tree(), "autoguardado")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()

## Salir de la app: sin cambios → sale. Con cambios: si el documento tiene
## nombre y el guardado automático está activo se guarda y sale; si no,
## pregunta Guardar / No guardar / Cancelar. Antes de preguntar deja una copia
## en Recuperar por si el sistema cierra la app de golpe (apagado).
func request_quit() -> void:
	if not is_modified:
		get_tree().quit()
		return
	if autosave_enabled and current_path != "":
		_save_to_path(current_path, true)
		if not is_modified:
			get_tree().quit()
			return
	IoGuard.snapshot_if_unsaved(get_tree(), "salir", true)
	_show_quit_dialog()

func _show_quit_dialog() -> void:
	if is_instance_valid(_quit_dialog):
		_quit_dialog.popup_centered()
		return
	var d := ConfirmationDialog.new()
	d.name = "QuitDialog"
	d.title = tr("Cambios sin guardar")
	d.dialog_text = tr("«%s» tiene cambios sin guardar. ¿Guardar antes de salir?") % (current_path.get_file() if current_path != "" else tr("Sin título"))
	d.ok_button_text = tr("Guardar")
	d.cancel_button_text = tr("Cancelar")
	d.add_button(tr("No guardar"), true, "discard")
	d.confirmed.connect(func() -> void:
		if current_path != "":
			_save_to_path(current_path)
			if not is_modified:
				get_tree().quit()
		else:
			_quit_after_save = true
			save_as())
	d.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			get_tree().quit())
	add_child(d)
	_quit_dialog = d
	d.popup_centered()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save"):
		save()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("new_project"):
		new_project()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_N and not event.shift_pressed and not event.alt_pressed:
			new_project()
			get_viewport().set_input_as_handled()

func save() -> void:
	if current_path.is_empty():
		save_as()
		return
	_save_to_path(current_path)

func save_as() -> void:
	if is_instance_valid(_active_file_dialog):
		_active_file_dialog.queue_free()
		_active_file_dialog = null

	var fd := FileDialog.new()
	_active_file_dialog = fd
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "Guardar proyecto"
	fd.add_filter("*.vtp", "Vectopen Project")
	fd.add_filter("*.json", "JSON Backup")
	fd.file_selected.connect(func(path: String):
		_on_save_as_selected(path)
		if is_instance_valid(fd):
			fd.queue_free()
	)
	fd.canceled.connect(func():
		if is_instance_valid(fd):
			fd.queue_free()
	)
	add_child(fd)
	fd.popup_centered(Vector2i(800, 600))

func _on_save_as_selected(path: String) -> void:
	current_path = path
	_save_to_path(path)

func _save_to_path(path: String, quiet := false) -> void:
	if not DataRepository:
		push_error("SaveManager: DataRepository no disponible")
		return
	# Si el guardado falla (disco lleno, sin permiso, página ilegible…) el
	# documento NO se marca como guardado: antes decía «Guardado» igualmente.
	var saved: String = DataRepository.save_project(path)
	if saved.is_empty():
		var ge := get_node_or_null("/root/GlobalEvents")
		if ge and ge.has_signal("user_notice"):
			ge.user_notice.emit("error", "No se pudo guardar «%s». El documento sigue con cambios sin guardar." % path.get_file())
		return
	current_path = saved
	is_modified = false
	if _autosave_timer:
		_autosave_timer.stop()
	save_state_changed.emit(false)
	project_saved.emit(path)
	if not quiet:
		RecentFilesManager.add_file(path)
	if _quit_after_save:
		get_tree().quit()

func open(path: String) -> void:
	if not DataRepository:
		push_error("SaveManager: DataRepository no disponible")
		return
	if not DataRepository.load_project(path):
		var ge := get_node_or_null("/root/GlobalEvents")
		if ge and ge.has_signal("user_notice"):
			ge.user_notice.emit("error", "No se pudo abrir «%s»: el archivo no existe o está dañado." % path.get_file())
		return
	current_path = path
	is_modified = false
	_quiet_frames = 3
	save_state_changed.emit(false)
	project_loaded.emit(path)
	RecentFilesManager.add_file(path)

func new_project(project_name: String = "Sin título") -> void:
	if not DataRepository:
		return
	DataRepository.new_project(project_name)
	current_path = ""
	is_modified = false
	_quiet_frames = 3
	save_state_changed.emit(false)
	_clean_canvas_for_new_project()

func _clean_canvas_for_new_project() -> void:
	var tree := get_tree()
	if not tree:
		return
	var sm = tree.root.get_node_or_null("SelectionManager")
	if sm and sm.has_method("clear_selection"):
		sm.clear_selection()

	var canvas = tree.get_first_node_in_group("_vectopen_canvas")
	var container: Node = null
	if canvas:
		container = canvas.get_node_or_null("ArtboardsContainer")
	if not container and tree.current_scene:
		container = tree.current_scene.find_child("ArtboardsContainer", true, false)

	if container:
		var artboards: Array[Node] = []
		for child in container.get_children():
			if child is ArtboardEditor:
				artboards.append(child)
			else:
				child.queue_free()

		if artboards.is_empty():
			var default_ab = ArtboardEditor.new()
			default_ab.name = "Artboard_1"
			default_ab.position = Vector2(100, 100)
			default_ab.artboard_size = Vector2(1920, 1080)
			container.add_child(default_ab)
		else:
			var first_ab = artboards[0] as ArtboardEditor
			first_ab.position = Vector2(100, 100)
			first_ab.artboard_size = Vector2(1920, 1080)
			for child in first_ab.get_children():
				if child is Node2D and String(child.name) not in ["ArtboardTitle", "Contorno_Stroke"]:
					child.queue_free()
			first_ab.queue_redraw()

			for i in range(1, artboards.size()):
				artboards[i].queue_free()

	var layers = tree.root.find_child("LayersSystem", true, false)
	if not layers and tree.current_scene:
		layers = tree.current_scene.find_child("LayersSystem", true, false)
	if layers and layers.has_method("sincronizar_arbol_completo"):
		layers.sincronizar_arbol_completo()

	if canvas and canvas.has_method("queue_redraw"):
		canvas.queue_redraw()

func mark_modified() -> void:
	is_modified = true
	save_state_changed.emit(true)
	if autosave_enabled and _autosave_timer and _autosave_timer.is_inside_tree():
		_autosave_timer.start(AUTOSAVE_DELAY)
