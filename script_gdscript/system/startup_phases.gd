# =============================================================================
# VECTOPEN — ARRANQUE EN 3 FASES
# RUTA: res://script_gdscript/system/startup_phases.gd
#
# Fase 1 (lo que trae main.tscn): lienzo, mesa de trabajo, barra de
#   herramientas, capas y reglas → la ventana se ve y se trabaja ~1 s antes.
# Fase 2 (justo después del primer fotograma): contenido de propiedades —
#   inspector acoplado, menú del botón derecho, selector de color, efectos.
# Fase 3: el resto — archivos/exportar, ajustes, barras del modo Modern y la
#   paleta de comandos.
#
# Godot compila todos los scripts de una escena ANTES de mostrarla, así que
# estos paneles ya no están en main.tscn: se compilan en un hilo
# (ResourceLoader.load_threaded_request) y se añaden UNO por fotograma, en su
# sitio y con los mismos ajustes que tenían en main.tscn.
# Sin pantalla (pruebas headless) y para lo que el modo de UI muestra al
# arrancar (Modern), se añaden antes del primer fotograma, como antes.
# =============================================================================
class_name StartupPhases
extends Node

signal panel_added(panel: Control)
signal phase_done(phase: int)
signal all_done

const GROUP := &"vectopen_startup_phases"
## Engine.has_meta(DONE_META) → todas las fases terminaron (lo usan las e2e).
const DONE_META := &"vectopen_startup_done"

## Orden original de los hijos en main.tscn: respeta el orden de dibujo.
const _ORDER := {
	".": ["windows_ recla", "Logo", "tools", "Layout", "tool_in_Mouse", "Cursor_moue",
		"pickr_color_windows", "Panel_PREVIEW", "PanelContainer", "panel__effects",
		"Control2", "PanelContainer2", "keyboard", "Panel_export", "DockedInspector",
		"ModernTopBar", "ModernNavRail", "ModernBottomToolbar", "CommandPalette",
		"AdaptiveUIManager"],
	"windows_ recla": ["regla horizontal", "regla vertical", "Button", "MANAGER WINDWS_REGLA"],
}

## Paneles por fases, con los ajustes que tenían en main.tscn (mismo orden).
## early_modes: modos de UI que los muestran al arrancar → antes del 1er frame.
const PANELS := [
	{"name": "DockedInspector", "phase": 2, "parent": ".", "early_modes": ["modern"],
		"scene": "res://scenes/ui/docked_inspector.tscn",
		"props": [["visible", false], ["layout_mode", 1]]},
	{"name": "tool_in_Mouse", "phase": 2, "parent": ".",
		"scene": "res://scenes/ui/tool_in_mouse.tscn",
		"props": [["layout_mode", 0], ["offset_left", 1045.0], ["offset_top", 128.0],
			["offset_right", 1267.0], ["offset_bottom", 488.0]]},
	{"name": "pickr_color_windows", "phase": 2, "parent": ".",
		"scene": "res://scenes/ui/pickr_color_tool.tscn",
		"props": [["visible", false], ["layout_mode", 1], ["anchors_preset", 1],
			["anchor_left", 1.0], ["anchor_right", 1.0], ["offset_left", -218.0],
			["offset_top", 66.0], ["offset_right", -16.0], ["offset_bottom", 440.0],
			["grow_horizontal", 0]]},
	{"name": "panel__effects", "phase": 2, "parent": ".",
		"scene": "res://scenes/ui/panel__effects.tscn",
		"props": [["visible", false], ["layout_mode", 1]]},
	{"name": "Panel_export", "phase": 3, "parent": ".",
		"scene": "res://scenes/ui/panel_export.tscn",
		"props": [["visible", false], ["z_index", 20], ["z_as_relative", false],
			["layout_mode", 1], ["offset_top", -370.0]]},
	{"name": "MANAGER WINDWS_REGLA", "phase": 3, "parent": "windows_ recla",
		"scene": "res://scenes/ui/panels/manager_windws_regla.tscn",
		"props": [["layout_mode", 1], ["offset_left", 24.0], ["offset_top", 24.0],
			["offset_right", 652.0], ["offset_bottom", 489.0]]},
	{"name": "ModernTopBar", "phase": 3, "parent": ".", "early_modes": ["modern"],
		"scene": "res://scenes/ui/modern/modern_top_bar.tscn",
		"props": [["visible", false], ["layout_mode", 1]]},
	{"name": "ModernNavRail", "phase": 3, "parent": ".", "early_modes": ["modern"],
		"scene": "res://scenes/ui/modern/modern_nav_rail.tscn",
		"props": [["visible", false], ["layout_mode", 1]]},
	{"name": "ModernBottomToolbar", "phase": 3, "parent": ".", "early_modes": ["modern"],
		"scene": "res://scenes/ui/modern/modern_bottom_toolbar.tscn",
		"props": [["visible", false], ["layout_mode", 1]]},
	{"name": "CommandPalette", "phase": 3, "parent": ".",
		"scene": "res://scenes/ui/modern/command_palette.tscn",
		"props": [["visible", false], ["layout_mode", 1]]},
]

var _main: Node = null
var _pending: Array = []      # paneles aún por añadir (fases 2 y 3)
var _requested := {}          # escena → true mientras hay carga en hilo
var _done := false

func _ready() -> void:
	add_to_group(GROUP)
	Engine.remove_meta(DONE_META)
	_main = get_parent()
	# main está montando a sus hijos: no se le puede añadir nada hasta su ready.
	_main.ready.connect(_on_main_ready, CONNECT_ONE_SHOT)

func _on_main_ready() -> void:
	var mode := _ui_mode()
	var all_now := DisplayServer.get_name() == "headless"
	var early: Array = []
	for p in PANELS:
		if _existing(p) != null:
			continue
		if all_now or mode in p.get("early_modes", []):
			early.append(p)
		else:
			_pending.append(p)
	for p in early:
		_add(p)
	if not early.is_empty():
		# El modo de UI se aplicó (AdaptiveUIManager._ready) sin estos paneles.
		var aui := _main.get_node_or_null("AdaptiveUIManager")
		if aui and aui.has_method("apply_ui_mode"):
			aui.apply_ui_mode(mode)
	if _pending.is_empty():
		_finish()
	else:
		_run_phases()

## Fases 2 y 3: compila en un hilo y añade un panel por fotograma.
func _run_phases() -> void:
	await RenderingServer.frame_post_draw   # la ventana ya se ve
	for phase in [2, 3]:
		var list := _pending.filter(func(p: Dictionary) -> bool: return p["phase"] == phase)
		for p in list:
			if _existing(p) == null and ResourceLoader.load_threaded_request(p["scene"]) == OK:
				_requested[p["scene"]] = true
		for p in list:
			while _requested.has(p["scene"]) and ResourceLoader.load_threaded_get_status(p["scene"]) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await get_tree().process_frame
				if not is_inside_tree():
					return
			if _existing(p) == null:
				_add(p)
				await get_tree().process_frame
				if not is_inside_tree():
					return
		phase_done.emit(phase)
	_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	_pending.clear()
	Engine.set_meta(DONE_META, true)
	all_done.emit()

func is_done() -> bool:
	return _done

## Añade YA el panel `panel_name` si aún no está (p. ej. clic derecho en el
## primer segundo). Devuelve el panel o null.
func ensure(panel_name: String) -> Control:
	for p in PANELS:
		if p["name"] == panel_name:
			var e := _existing(p)
			return e if e != null else _add(p)
	return null

## Termina YA todas las fases (bloquea hasta compilar lo que falte).
func ensure_all() -> void:
	for p in _pending.duplicate():
		if _existing(p) == null:
			_add(p)
	_finish()

# El menú del botón derecho escucha en su propio _input: si llega un clic
# derecho antes de la fase 2, se crea ya y se le pasa el evento.
func _input(event: InputEvent) -> void:
	if _done or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		return
	for p in PANELS:
		if p["name"] == "tool_in_Mouse" and _existing(p) == null:
			var menu := _add(p)
			if menu and menu.has_method("_input"):
				menu._input(event)
			return

func _existing(p: Dictionary) -> Control:
	var parent := _main.get_node_or_null(NodePath(p["parent"])) if _main else null
	return parent.get_node_or_null(NodePath(p["name"])) as Control if parent else null

func _add(p: Dictionary) -> Control:
	var parent := _main.get_node_or_null(NodePath(p["parent"])) if _main else null
	if parent == null:
		return null
	var scene_path: String = p["scene"]
	var ps: PackedScene = null
	if _requested.has(scene_path):
		_requested.erase(scene_path)
		ps = ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if ps == null:
		ps = load(scene_path) as PackedScene
	if ps == null:
		push_error("StartupPhases: no se pudo cargar " + scene_path)
		return null
	var node := ps.instantiate() as Control
	node.name = p["name"]
	for kv in p["props"]:
		node.set(kv[0], kv[1])
	parent.add_child(node)
	_place(parent, node, _ORDER.get(p["parent"], []))
	_pending.erase(p)
	panel_added.emit(node)
	return node

## Coloca `node` justo detrás del hermano anterior que ya exista en `order`.
func _place(parent: Node, node: Node, order: Array) -> void:
	var i := order.find(String(node.name))
	if i < 0:
		return
	for j in range(i - 1, -1, -1):
		var prev := parent.get_node_or_null(NodePath(order[j]))
		if prev:
			parent.move_child(node, prev.get_index() + 1)
			return
	parent.move_child(node, 0)

func _ui_mode() -> String:
	var gui := get_node_or_null("/root/GlobalUI")
	return gui.get_ui_mode() if gui and gui.has_method("get_ui_mode") else "smart"
