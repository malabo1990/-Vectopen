extends Button

@export var target_panel: Control:
	set(value):
		if is_instance_valid(target_panel) and target_panel.visibility_changed.is_connected(_on_target_visibility_changed):
			target_panel.visibility_changed.disconnect(_on_target_visibility_changed)
		target_panel = value
		if is_instance_valid(target_panel):
			if not target_panel.visibility_changed.is_connected(_on_target_visibility_changed):
				target_panel.visibility_changed.connect(_on_target_visibility_changed)
			_sync_state()

## Ruta al panel cuando este se crea DESPUÉS (arranque por fases,
## StartupPhases): se resuelve en cuanto el panel entra en el árbol.
@export var target_panel_path: NodePath

func _ready() -> void:
	if not target_panel and not target_panel_path.is_empty():
		target_panel = _resolve_path_target()
		if not target_panel:
			get_tree().node_added.connect(_on_tree_node_added)
			_connect_pressed()
			return
	if not target_panel:
		target_panel = get_node_or_null("Panel_keyboard") as Control
		if not target_panel:
			for child in get_children():
				if child is Control and child != self:
					target_panel = child
					break

	_connect_pressed()

	if is_instance_valid(target_panel):
		if not target_panel.visibility_changed.is_connected(_on_target_visibility_changed):
			target_panel.visibility_changed.connect(_on_target_visibility_changed)
		_sync_state()

func _connect_pressed() -> void:
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

## La ruta o, si no casa, el primer ancestro con un hijo de ese nombre
## (rutas antiguas guardadas con un "../" de menos).
func _resolve_path_target() -> Control:
	var panel := get_node_or_null(target_panel_path) as Control
	if panel:
		return panel
	var target_name := _path_target_name()
	var n := get_parent()
	while n:
		var c := n.get_node_or_null(NodePath(target_name)) as Control
		if c:
			return c
		n = n.get_parent()
	return null

func _path_target_name() -> String:
	return String(target_panel_path.get_name(target_panel_path.get_name_count() - 1))

func _on_tree_node_added(node: Node) -> void:
	if String(node.name) != _path_target_name():
		return
	var panel := _resolve_path_target()
	if panel:
		get_tree().node_added.disconnect(_on_tree_node_added)
		target_panel = panel   # el setter conecta visibility_changed y sincroniza

func _sync_state() -> void:
	if toggle_mode and is_instance_valid(target_panel):
		set_pressed_no_signal(target_panel.visible)

func _on_target_visibility_changed() -> void:
	_sync_state()

func _on_pressed() -> void:
	if not is_instance_valid(target_panel) and not target_panel_path.is_empty():
		# Pulsado antes de que su fase lo cree: crearlo ya.
		var phases := get_tree().get_first_node_in_group(StartupPhases.GROUP)
		if phases:
			phases.ensure(_path_target_name())
		if not is_instance_valid(target_panel):
			target_panel = _resolve_path_target()
	if is_instance_valid(target_panel):
		target_panel.visible = not target_panel.visible

		if target_panel.visible:
			target_panel.move_to_front()
			var p: Node = get_parent()
			while is_instance_valid(p) and p.get_parent() != target_panel.get_parent():
				p = p.get_parent()
			if is_instance_valid(p) and p is CanvasItem:
				(p as CanvasItem).move_to_front()

		_sync_state()
