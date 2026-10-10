# =============================================================================
# VECTOPEN CORE — CORE SYSTEM ENGINE
# RUTA: res://scripts/canvas/canvas.gd
# =============================================================================
extends Node2D
class_name CanvasEditor

# --- REFERENCIAS A NODOS ---
@export_group("Required Nodes")
@export var camera: Camera2D
@export var artboards_container: Node2D

# --- REFERENCIA A UI EXTERNA ---
var toolbar_ui: Control 

# --- CONFIGURACIÓN DE NAVEGACIÓN ---
@export_group("Camera Settings")
@export var zoom_speed: float = 0.05
@export var zoom_min: float = 0.05
## 50000.0 (5.000.000%) — a pedido explícito, por encima del techo de un editor profesional
## (256/25600%). camera.zoom sigue siendo float32 (como todo en Godot sin
## build de doble precisión), así que a este nivel el propio Transform2D de
## la cámara puede perder precisión visible en coordenadas grandes — es el
## mismo tipo de problema que resolvimos para la posición/tamaño de las
## figuras, pero aquí no tiene arreglo sin tocar la cámara a fondo.
@export var zoom_max: float = 50000.0
@export var pan_speed: float = 1.0

# --- CONFIGURACIÓN DE ZOOM CON TECLA Z ---
@export_group("Z-Zoom Settings")
@export var z_drag_sensitivity: float = 0.01
## Zoom con arrastre estilo Krita: factor = e^(-px · velocidad) por movimiento
## (suave y simétrico: subir y bajar lo mismo vuelve al zoom inicial).
@export var zoom_drag_speed: float = 0.008
@export var z_drag_max_factor: float = 0.15

# --- EXPORTACIÓN DE PORCENTAJE DE ZOOM ---
@export_group("Zoom Output")
@export var zoom_percentage: float = 100.0:
	set(v):
		zoom_percentage = clamp(v, zoom_min * 100.0, zoom_max * 100.0)
		if is_instance_valid(camera):
			var target_zoom: float = zoom_percentage / 100.0
			camera.zoom = Vector2(target_zoom, target_zoom)
			# Marcar todo el viewport como sucio al cambiar el zoom
			mark_region_dirty(Rect2(Vector2.ZERO, get_viewport_rect().size))

# --- SCRIPTS DE HERRAMIENTAS (Inspector) ---
@export_group("Tool Scripts")
@export var MoveTool_Script: Script
@export var BrushTool_Script: Script
@export var RectangleTool_Script: Script
@export var PenTool_Script: Script
@export var ArtboardTool_Script: Script = preload("res://script_gdscript/tools/ArtboardTool.gd")
@export var CircleTool_Script: Script
@export var TriangleTool_Script: Script
@export var PentagonTool_Script: Script
@export var Star4Tool_Script: Script
@export var Star5Tool_Script: Script
@export var WaterDropTool_Script: Script
@export var BezierTool_Script: Script
@export var BrushTool_Script2: Script

@export_group("Text Tools")
@export var TextTool_Script: Script
@export var ParagraphTool_Script: Script

# --- ESTADO INTERNO ---
var current_tool        = null
var dragging: bool      = false
var is_space_pressed: bool = false
var is_ctrl_pressed: bool  = false
var is_cmd_pressed: bool   = false
var is_z_pressed: bool     = false

var _zoom_anchor: Vector2  = Vector2.ZERO
## Gesto de zoom con arrastre (Ctrl + botón central / Ctrl + Espacio) activo.
var _zoom_drag: bool       = false
var _eraser_active: bool   = false
var _tool_before_eraser    = null
var _dirty_regions: Array[Rect2] = []  # Regiones que necesitan redibujarse

## Single-letter, no-modifier tool switching, clustered on Q-W-E-R-T / A-S-D-F
## so the hand never has to leave typing position — explicit user request
## after noticing I/P/M were too far away. `G` is left OUT of this cluster
## because bare G is already a real, active shortcut (toggle gradient, see
## MoveTool._handle_key_shortcuts) — putting a tool there would have broken
## it. For the same reason, Shift+letter is reserved for the transform verbs
## (Shift+G move, Shift+R rotate, Shift+S scale, see MoveTool.gd), so this
## dictionary only fires without Shift/Ctrl/Alt/Meta. Before this, NO letter
## switched tools from the keyboard at all — not even V or B — only clicking
## the icon or the command palette worked.
const TOOL_SWITCH_KEYS: Dictionary = {
	KEY_V: "select",
	KEY_B: "brush",
	KEY_W: "hand",
	KEY_E: "ellipse",
	KEY_R: "rectangle",
	KEY_T: "text",
	KEY_P: "paragraph",
	KEY_A: "artboard",
	KEY_S: "star",
	KEY_D: "bezier",
}

# --- Smart Cursor ---
@onready var smart_cursor = get_node("/root/SmartCursor")
var _cursor_material: ShaderMaterial = null
var _cursor_position: Vector2 = Vector2.ZERO

# Diccionario global para el registro dinámico de herramientas
var _herramientas_registradas: Dictionary = {}

# ── Ciclo de Vida del Canvas ─────────────────────────────────────────────────

func _ready() -> void:
	if not get_node_or_null("/root/MCPRuntime"):
		var mcp_scr = load("res://addons/godot_mcp/runtime/mcp_runtime.gd")
		if mcp_scr:
			var mcp_inst = mcp_scr.new()
			mcp_inst.name = "MCPRuntime"
			get_tree().root.add_child.call_deferred(mcp_inst)

	if not is_instance_valid(camera):
		print("[Vectopen Error]: Camera2D no asignada en el nodo Canvas.")
		return
	
	_inicializar_escena()
	_get_tool_overlay()
	_registrar_herramientas_iniciales()
	_initialize_smart_cursor()

func _inicializar_escena() -> void:
	if is_instance_valid(artboards_container) and artboards_container.get_child_count() > 0:
		var first_artboard = artboards_container.get_child(0)
		if "position" in first_artboard:
			first_artboard.position = Vector2(100, 100)
	_reset_camera()

func _registrar_herramientas_iniciales() -> void:
	if MoveTool_Script:
		registrar_herramienta("v", MoveTool_Script)
		change_tool(_new_tool(MoveTool_Script))

	if BrushTool_Script:     registrar_herramienta("b", BrushTool_Script)
	if RectangleTool_Script: registrar_herramienta("m", RectangleTool_Script)
	# "p" abre la Pluma Bézier profesional (nodos + handles simétricos/libres,
	# cierre de trazo), no PenTool_Script (solo polilínea recta sin curvas) —
	# alineado con el atajo "P" de editor vectorial que pidió el usuario.
	if BezierTool_Script:    registrar_herramienta("p", BezierTool_Script)
	if ArtboardTool_Script:  registrar_herramienta("a", ArtboardTool_Script)
	if TextTool_Script:      registrar_herramienta("t", TextTool_Script)

# --- API PÚBLICA DE GESTIÓN DINÁMICA ---

func registrar_herramienta(tecla_acceso: String, script_herramienta: Script) -> void:
	var tecla: String = tecla_acceso.to_lower().strip_edges()
	if tecla != "":
		_herramientas_registradas[tecla] = script_herramienta

## Libera una herramienta ToolBase (Node) que ya no está en uso.
## Las herramientas `Tool` (RefCounted) no lo necesitan — se liberan solas
## por conteo de referencias. Las `ToolBase` (Node) SÍ entran al árbol de
## escena desde change_tool() (necesitan get_tree()); al cambiar de herramienta
## hay que sacarlas y liberarlas o se acumulan como "leaked ObjectDB instances".
## Usa queue_free(), NO free(): algunas herramientas (p.ej. TextTool en
## _create_new_title_at → _switch_to_move_tool) cambian de herramienta desde
## dentro de su propio handle_input(), así que change_tool() puede llamar a
## esto mientras la herramienta vieja sigue en medio de su propia pila de
## llamadas — free() inmediato falla ahí con "Object is locked and can't be
## freed" (encontrado el 19/08/2026 al arreglar el bug de los botones de
## Texto/Párrafo, ver informe). queue_free() difiere la liberación real al
## final del frame, que es justo lo que hace falta en ese caso.
func _free_orphan_tool(tool) -> void:
	if tool is Node:
		if tool.is_inside_tree() and is_instance_valid(tool.get_parent()):
			tool.get_parent().remove_child(tool)
		tool.queue_free()

func _exit_tree() -> void:
	_free_orphan_tool(current_tool)

func _new_tool(script: Script):
	if not script:
		return null
	if script.get_instance_base_type() == "RefCounted":
		return script.new(self)
	var tool = script.new()
	if "canvas" in tool:
		tool.canvas = self
	return tool

func change_tool(new_tool) -> void:
	# Cambiar a la MISMA herramienta no hace nada: si no, _free_orphan_tool la
	# liberaba y quedaba asignada ya liberada (p.ej. al salir del modo borrador
	# del lápiz con _tool_before_eraser == current_tool) → todo el lienzo y los
	# paneles fallaban con "previously freed instance".
	if new_tool != null and new_tool == current_tool:
		return
	if current_tool and current_tool.has_method("deactivate"):
		current_tool.deactivate()

	_free_orphan_tool(current_tool)
	current_tool = new_tool

	# La herramienta ToolBase (Node) DEBE entrar al árbol de escena: si no,
	# get_tree() es null dentro de ella y TODO lo que depende de él queda muerto
	# — sobre todo ArtboardManager.find(get_tree()), así que la resolución
	# multi-artboard se caía SIEMPRE al fallback container.get_child(0) (el
	# primer artboard). Por eso "no se podía seleccionar ni arrastrar el 2º
	# artboard" ni reparentar figuras entre artboards en la app real (los tests
	# sí pasaban porque añaden la herramienta al árbol a mano).
	# Las `Tool` (RefCounted) legacy no son Node → no aplica.
	if new_tool is Node and not new_tool.is_inside_tree():
		add_child(new_tool)

	if current_tool:
		print("==================================================")
		print("CANVAS NOTIFICACIÓN: ¡Herramienta Cambiada con Éxito!")
		print("==================================================")

	if current_tool and current_tool.has_method("activate"):
		current_tool.activate()
	else:
		_actualizar_cursor_navegacion()
	
	# ── NOTIFICACIÓN AL CONTENEDOR DEL LIENZO (OVERLAY CONTROL) ──
	if is_instance_valid(artboards_container) and artboards_container.has_method("set_active_tool"):
		if current_tool and current_tool.has_method("get_class_name") and current_tool.get_class_name() == "MoveTool":
			artboards_container.set_active_tool("movetool", current_tool)
		else:
			artboards_container.set_active_tool("other", null)
	
	_sincronizar_ui_toolbar()
	# Marcar todo el viewport como sucio al cambiar de herramienta
	mark_region_dirty(Rect2(Vector2.ZERO, get_viewport_rect().size))

func switch_tool(tool_type: String) -> void:
	var tool_manager = get_node_or_null("/root/ToolManager")
	match tool_type.to_lower():
		"move":
			if MoveTool_Script: change_tool(_new_tool(MoveTool_Script))
		"nodeselection", "node", "direct_select":
			var node_tool_script = preload("res://script_gdscript/tools/NodeSelectionTool.gd")
			if node_tool_script: change_tool(_new_tool(node_tool_script))
		"brush":
			if BrushTool_Script: change_tool(_new_tool(BrushTool_Script))
		"pen":
			if PenTool_Script: change_tool(_new_tool(PenTool_Script))
		"rectangle":
			if RectangleTool_Script: change_tool(_new_tool(RectangleTool_Script))
		"ellipse":
			if CircleTool_Script: change_tool(_new_tool(CircleTool_Script))
		"triangle":
			if TriangleTool_Script: change_tool(_new_tool(TriangleTool_Script))
		"pentagon":
			if PentagonTool_Script: change_tool(_new_tool(PentagonTool_Script))
		"star":
			var star_script = preload("res://script_gdscript/tools/StarTool.gd")
			if star_script: change_tool(_new_tool(star_script))
		"star4":
			if Star4Tool_Script: change_tool(_new_tool(Star4Tool_Script))
		"star5":
			if Star5Tool_Script: change_tool(_new_tool(Star5Tool_Script))
		"waterdrop":
			if WaterDropTool_Script: change_tool(_new_tool(WaterDropTool_Script))
		"bezier":
			if BezierTool_Script: change_tool(_new_tool(BezierTool_Script))
		"select":
			if MoveTool_Script: change_tool(_new_tool(MoveTool_Script))
		"text":
			if TextTool_Script: change_tool(_new_tool(TextTool_Script))
		"paragraph":
			if ParagraphTool_Script: change_tool(_new_tool(ParagraphTool_Script))
		"hand":
			pass
		"artboard":
			if ArtboardTool_Script: change_tool(_new_tool(ArtboardTool_Script))
		"shape_builder", "shapebuilder":
			var sb_script = preload("res://script_gdscript/tools/ShapeBuilderTool.gd")
			if sb_script: change_tool(_new_tool(sb_script))
		"3d", "model3d":
			var im = get_node_or_null("/root/ImportExportManager")
			if is_instance_valid(im) and im.has_method("import_3d_model"):
				im.import_3d_model()

	# ToolManager (Sistema A) no tiene registradas todas las herramientas que
	# sí maneja el match de arriba (Sistema B) — p.ej. "paragraph"/"artboard"
	# no tienen escena en tools/. Sin este guard, tool_manager.switch_tool()
	# lanzaba un push_error real ("Herramienta no encontrada") cada vez que
	# se activaban esas herramientas, aunque el cambio real (arriba) ya
	# hubiera funcionado — encontrado el 19/08/2026 al probar el tipo Párrafo.
	if tool_manager and tool_manager.has_method("switch_tool") and tool_manager.has_method("get_available_tools") and tool_manager.get_available_tools().has(tool_type.to_lower()):
		tool_manager.switch_tool(tool_type)

# ── Procesamiento de Entrada Centralizado ────────────────────────────────────

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_keyboard(event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		print("[CanvasEditor] _unhandled_input MB pos=%s current_tool=%s" % [event.position, current_tool.get_script().resource_path if current_tool else "null"])
	if event is InputEventKey:
		_handle_keyboard(event)
		return

	# Procesamiento preliminar de tableta digitalizadora (Wacom, Huion, XP-Pen)
	if event is InputEventMouseMotion:
		if event.pressure > 0.0 and current_tool:
			current_tool.set_meta("pen_pressure", event.pressure)
		if event.tilt != Vector2.ZERO and current_tool:
			current_tool.set_meta("pen_tilt", event.tilt)

		if event.pen_inverted:
			if not _eraser_active:
				_eraser_active = true
				_tool_before_eraser = current_tool
				if current_tool and current_tool.has_method("set_eraser_mode"):
					current_tool.set_eraser_mode(true)
		else:
			if _eraser_active:
				_eraser_active = false
				if current_tool and current_tool.has_method("set_eraser_mode"):
					current_tool.set_eraser_mode(false)
				elif is_instance_valid(_tool_before_eraser):
					change_tool(_tool_before_eraser)
				_tool_before_eraser = null

	# Si la barra espaciadora o la tecla Z están presionadas, la navegación de lienzo tiene prioridad
	var en_modo_navegacion_forzada: bool = is_space_pressed or is_z_pressed
	# El botón central (rueda / botón 2 del lápiz) SIEMPRE navega, con
	# cualquier herramienta (pincel, pluma…): ninguna puede quedárselo.
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE) \
			or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE)) \
			or _zoom_drag:
		en_modo_navegacion_forzada = true
	
	if current_tool and not en_modo_navegacion_forzada:
		if current_tool.has_method("handle_input"):
			if current_tool.handle_input(event):
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMagnifyGesture:
		if not is_canvas_zoom_paused():
			zoom_at_point(event.factor, get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		if not is_canvas_zoom_paused():
			_handle_trackpad_pan(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

# ── Gestión de Teclado y Atajos de Teclas Cortas ────────────────────────────

## Digit keys set the opacity of the selection: 1 = 10% ... 9 = 90%, 0 = 100%.
## Two digits typed quickly give an exact value (4 then 5 = 45%). Only with a
## selection, so bare 5 keeps resetting the zoom otherwise.
const OPACITY_DIGIT_WINDOW_MS := 600
var _opacity_digit_first: int = -1
var _opacity_digit_time: int = 0

func _handle_opacity_digit(event: InputEventKey) -> bool:
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed or event.echo:
		return false
	var digit := -1
	if event.keycode >= KEY_0 and event.keycode <= KEY_9:
		digit = event.keycode - KEY_0
	elif event.keycode >= KEY_KP_0 and event.keycode <= KEY_KP_9:
		digit = event.keycode - KEY_KP_0
	if digit < 0:
		return false
	# La opacidad se aplica vía InspectorCore (que opera sobre el Manager):
	# comprobar el espejo aquí perdía el atajo cuando diferían.
	var sm := get_node_or_null("/root/SelectionManager")
	if sm == null or not sm.has_method("is_empty") or sm.is_empty():
		return false
	var now := Time.get_ticks_msec()
	var percent: int
	if _opacity_digit_first >= 0 and now - _opacity_digit_time <= OPACITY_DIGIT_WINDOW_MS:
		percent = _opacity_digit_first * 10 + digit
		if percent == 0:
			percent = 100
		_opacity_digit_first = -1
	else:
		percent = 100 if digit == 0 else digit * 10
		_opacity_digit_first = digit
		_opacity_digit_time = now
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("opacity", clampf(percent / 100.0, 0.0, 1.0))
	return true

## Al perder el foco la ventana no recibe los "soltar" de las teclas que
## estuvieran pulsadas: Espacio / Z (que no viajan en los eventos del ratón)
## y Ctrl / Super se dan por soltadas. Si no, se quedaban pegadas (Espacio =
## arrastrar desplaza en vez de dibujar, Z = arrastrar hace zoom…).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		var was_nav := is_space_pressed or is_z_pressed or dragging
		is_space_pressed = false
		is_z_pressed = false
		is_ctrl_pressed = false
		is_cmd_pressed = false
		dragging = false
		_zoom_drag = false
		if was_nav and is_inside_tree():
			_actualizar_cursor_navegacion()

func _handle_keyboard(event: InputEventKey) -> void:
	match event.keycode:
		KEY_SPACE: is_space_pressed = event.pressed; _actualizar_cursor_navegacion()
		KEY_CTRL:  is_ctrl_pressed  = event.pressed
		KEY_META:  is_cmd_pressed   = event.pressed
		KEY_Z:     is_z_pressed     = event.pressed; _actualizar_cursor_navegacion()

	if not event.pressed: return
	# Antes bloqueaba TODOS los atajos globales si CUALQUIER Control tenía el
	# foco de teclado — no solo campos de texto, también botones normales
	# (Button.focus_mode es FOCUS_ALL por defecto en Godot, y nada lo soltaba
	# tras el clic). En la práctica esto rompía Ctrl+Z/zoom/Fase 1 completos
	# en cuanto el usuario tocaba cualquier icono de la barra de herramientas
	# — encontrado el 19/08/2026 verificando en vivo por qué ningún atajo de
	# teclado hacía nada tras crear una forma con la herramienta de Texto.
	# Restringido a los controles donde SÍ tiene sentido que el atajo global
	# no interfiera (el usuario está escribiendo), que es la intención
	# original del guard.
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner and (focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is SpinBox or focus_owner is CodeEdit):
		return
	# Editor de texto NATIVO (VectorRichText es un Control, no un TextEdit) o
	# cualquier edición de texto en curso: sin esto, Ctrl+B mientras se
	# editaba caía al atajo de letra "b" de abajo → herramienta Pincel →
	# se confirmaba y CERRABA la edición (la negrita solo funcionaba una vez).
	if focus_owner and focus_owner.has_method("is_editing") and focus_owner.is_editing():
		return
	var sm_edit := get_node_or_null("/root/SelectionManager")
	if sm_edit and sm_edit.has_method("has_active_text_edit") and sm_edit.has_active_text_edit():
		return

	if _handle_opacity_digit(event):
		get_viewport().set_input_as_handled()
		return

	if VectopenInput.is_action_triggered(event, "canvas_reset_zoom"):
		_reset_camera()
		get_viewport().set_input_as_handled()
		return

	if VectopenInput.is_action_triggered(event, "canvas_zoom_in"):
		if not is_canvas_zoom_paused():
			zoom_at_point(1.2, get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	if VectopenInput.is_action_triggered(event, "canvas_zoom_out"):
		if not is_canvas_zoom_paused():
			zoom_at_point(0.8, get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	if VectopenInput.is_action_triggered(event, "redo"):
		if HistoryManager:
			HistoryManager.redo()
		get_viewport().set_input_as_handled()
		return

	if VectopenInput.is_action_triggered(event, "undo"):
		if HistoryManager:
			HistoryManager.undo()
		get_viewport().set_input_as_handled()
		return

	# Grosor del texto seleccionado con teclado (como Figma): Ctrl+Alt+. más
	# grueso, Ctrl+Alt+, más fino (100..900). Editando, lo gestiona el editor.
	if event.ctrl_pressed and event.alt_pressed and event.keycode in [KEY_PERIOD, KEY_COMMA]:
		var ic_w := get_node_or_null("/root/InspectorCore")
		if ic_w and ic_w.has_method("current_props"):
			var props_w: Dictionary = ic_w.current_props()
			if props_w.has("font_weight") and not bool(props_w["font_weight"].get("mixed", false)):
				var cur_w := int(props_w["font_weight"].get("value", 400))
				ic_w.apply("font_weight", clampi(cur_w + (100 if event.keycode == KEY_PERIOD else -100), 100, 900))
				get_viewport().set_input_as_handled()
				return

	# Single-letter tool switching (see TOOL_SWITCH_KEYS). Suppressed while a
	# modal keyboard transform is active (Shift+G/R/S in MoveTool) — otherwise
	# typing "D" or "F" mid Shift+G-move would switch tools instead of letting
	# MoveTool process that frame of the gesture. "current_key_mode" is duck-
	# typed (0 == NONE) instead of checking `is MoveTool`, to avoid coupling
	# canvas.gd to one specific tool.
	if not event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		var in_modal_transform: bool = current_tool and "current_key_mode" in current_tool and current_tool.current_key_mode != 0
		if not in_modal_transform and TOOL_SWITCH_KEYS.has(event.keycode):
			switch_tool(TOOL_SWITCH_KEYS[event.keycode])
			get_viewport().set_input_as_handled()
			return

	# Permitir que la herramienta activa procese atajos específicos (ej. G para degradado en MoveTool, o Delete en stops)
	if current_tool and current_tool.has_method("handle_input"):
		if current_tool.handle_input(event):
			get_viewport().set_input_as_handled()
			return

	# ── Fase 1 del informe de interacción avanzada (19/08/2026) ────────────
	# Eliminar/Copiar/Cortar/Pegar/Duplicar/Seleccionar todo/mover con flechas.
	var kc_del: int = event.keycode if event.keycode != 0 else event.physical_keycode
	var is_del: bool = (kc_del in [KEY_DELETE, KEY_BACKSPACE, KEY_X]) and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed
	if VectopenInput.is_action_triggered(event, "delete") or is_del:
		var deleted_any := false
		if current_tool and current_tool.has_method("delete_selected"):
			current_tool.delete_selected()
			deleted_any = true
		elif current_tool and current_tool.has_method("delete_selected_nodes"):
			current_tool.delete_selected_nodes()
			deleted_any = true
		if SelectionManager and SelectionManager.has_method("get_selected"):
			var sel: Array = SelectionManager.get_selected()
			if not sel.is_empty():
				_delete_selected_shapes(sel)
				deleted_any = true
		if deleted_any:
			get_viewport().set_input_as_handled()
			return

	if current_tool and current_tool.has_method("get_class_name") and current_tool.get_class_name() == "MoveTool":
		if VectopenInput.is_action_triggered(event, "copy"):
			current_tool.copy_selected()
			get_viewport().set_input_as_handled()
			return
		if VectopenInput.is_action_triggered(event, "cut"):
			current_tool.cut_selected()
			get_viewport().set_input_as_handled()
			return
		if VectopenInput.is_action_triggered(event, "paste"):
			# Si el portapapeles del SISTEMA (no el interno de formas) tiene una
			# imagen — copiada de un navegador, un visor de imágenes, etc. — se
			# importa directamente; si no, cae al pegado normal de formas.
			if not ClipboardImageService.try_paste_into(self):
				current_tool.paste_clipboard()
			get_viewport().set_input_as_handled()
			return
		if VectopenInput.is_action_triggered(event, "duplicate"):
			current_tool.duplicate_selected()
			get_viewport().set_input_as_handled()
			return
		if VectopenInput.is_action_triggered(event, "select_all"):
			current_tool.select_all()
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			var direction: Vector2 = Vector2.ZERO
			match event.keycode:
				KEY_LEFT:  direction = Vector2.LEFT
				KEY_RIGHT: direction = Vector2.RIGHT
				KEY_UP:    direction = Vector2.UP
				KEY_DOWN:  direction = Vector2.DOWN
			current_tool.nudge_selected(direction, event.shift_pressed)
			get_viewport().set_input_as_handled()
			return

	# Atajo de letra SOLO sin modificadores (misma regla que TOOL_SWITCH_KEYS):
	# antes Ctrl+B se leía como "b" y cambiaba a la herramienta Pincel.
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	var unicode_val = event.unicode if event.unicode != 0 else event.keycode
	var t_char: String = char(unicode_val).to_lower()
	if _herramientas_registradas.has(t_char):
		var script_target = _herramientas_registradas[t_char]
		change_tool(_new_tool(script_target))
		get_viewport().set_input_as_handled()

# ── Procesamiento de Clicks y Rueda del Ratón ─────────────────────────────────

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if (event.button_index == MOUSE_BUTTON_LEFT and is_space_pressed) or event.button_index == MOUSE_BUTTON_MIDDLE:
		if is_canvas_zoom_paused():
			get_viewport().set_input_as_handled()
			return
		dragging = event.pressed
		# Zoom con arrastre estilo Krita: anclado en el punto donde empieza.
		_zoom_drag = false
		if event.pressed:
			_zoom_anchor = get_global_mouse_position()
		if not dragging: 
			_actualizar_cursor_navegacion()
		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_LEFT and is_z_pressed:
		dragging = event.pressed
		if event.pressed: 
			_zoom_anchor = get_global_mouse_position()
		else: 
			_actualizar_cursor_navegacion()
		get_viewport().set_input_as_handled()
		return

	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if GlobalUI and GlobalUI.is_mouse_over_ui:
			return
		var gm := get_global_mouse_position()
		# Si la rueda no está presionada (evento de liberación), ignorar para evitar doble cómputo
		if not event.pressed:
			if is_canvas_zoom_paused(gm):
				get_viewport().set_input_as_handled()
			return
		# Si el zoom de canvas está en pausa (modo 3D activo o cursor sobre modelo 3D), delegar y pausar zoom del editor
		if is_canvas_zoom_paused(gm) or (current_tool and current_tool.has_method("handle_wheel_3d") and current_tool.handle_wheel_3d(event, gm)):
			if current_tool and current_tool.has_method("handle_wheel_3d"):
				current_tool.handle_wheel_3d(event, gm)
			get_viewport().set_input_as_handled()
			return
		# Modificadores DEL EVENTO (ver _handle_mouse_motion).
		var fast := event.ctrl_pressed or event.meta_pressed
		var f: float = 1.0 + (zoom_speed * (2.0 if fast else 1.0))
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			f = 1.0 - (zoom_speed * (2.0 if fast else 1.0))
		zoom_at_point(f, gm)
		get_viewport().set_input_as_handled()

# ── Procesamiento del Desplazamiento y Presión del Lápiz ──────────────────────

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if event.pen_inverted:
		if not _eraser_active:
			_eraser_active = true
			_tool_before_eraser = current_tool
	else:
		if _eraser_active:
			_eraser_active = false
			if is_instance_valid(_tool_before_eraser):
				change_tool(_tool_before_eraser)
			elif MoveTool_Script:
				change_tool(_new_tool(MoveTool_Script))
			_tool_before_eraser = null

	if current_tool and event.pressure > 0.0:
		current_tool.set_meta("pen_pressure", event.pressure)

	# Botones y modificadores se leen DEL EVENTO (button_mask, meta_pressed),
	# no del estado global: si la ventana pierde el foco con una tecla pulsada
	# (Super abre las actividades de GNOME) nunca llega el "soltar", el estado
	# global se queda pegado y el botón central del lápiz (botón 2) hacía
	# ZOOM en vez de desplazar la vista.
	var mask: int = event.button_mask
	if is_z_pressed and (mask & MOUSE_BUTTON_MASK_LEFT):
		var f: float = 1.0 - event.relative.y * z_drag_sensitivity
		f = clamp(f, 1.0 - z_drag_max_factor, 1.0 + z_drag_max_factor)
		zoom_at_point(f, _zoom_anchor)
		get_viewport().set_input_as_handled()
		return

	# Zoom con ARRASTRE (como Krita): Ctrl + botón central (botón 2 del lápiz)
	# o Ctrl + Espacio + clic. Arriba acerca, abajo aleja; el punto donde
	# empezó el gesto se queda quieto bajo el cursor. Super (Cmd en macOS)
	# también vale.
	var mid := (mask & MOUSE_BUTTON_MASK_MIDDLE) != 0
	var space_left := is_space_pressed and (mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if (event.ctrl_pressed or event.meta_pressed) and (mid or space_left):
		if is_canvas_zoom_paused():
			return
		if not _zoom_drag:
			_zoom_drag = true
			_zoom_anchor = get_global_mouse_position()
		var f: float = clampf(exp(-event.relative.y * zoom_drag_speed), 0.7, 1.4)
		zoom_at_point(f, _zoom_anchor)
		get_viewport().set_input_as_handled()
		return
	if _zoom_drag and not (mid or space_left):
		_zoom_drag = false

	if dragging and (is_space_pressed or (mask & MOUSE_BUTTON_MASK_MIDDLE)):
		if is_canvas_zoom_paused():
			dragging = false
			return
		if is_instance_valid(camera) and camera.zoom.x > 0.0:
			camera.position -= event.relative * pan_speed / camera.zoom.x
			get_viewport().set_input_as_handled()
		return

func _handle_trackpad_pan(event: InputEventPanGesture) -> void:
	if event.meta_pressed or event.ctrl_pressed:
		zoom_at_point(1.0 - event.delta.y * zoom_speed * 0.5, get_global_mouse_position())
	else:
		if is_instance_valid(camera) and camera.zoom.x > 0.0:
			camera.position -= event.delta * pan_speed / camera.zoom.x

# ── Control de Puntero UI ─────────────────────────────────────────────────────

func _actualizar_cursor_navegacion() -> void:
	if is_space_pressed: 
		Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	elif is_z_pressed:   
		Input.set_default_cursor_shape(Input.CURSOR_BDIAGSIZE)
	else:
		if current_tool and current_tool.has_method("activate"):
			current_tool.activate()
		else:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)

# ── Motor Gráfico (Vista previa de herramientas) ──────────────────────────────

var _tool_overlay: Node2D = null

func _get_tool_overlay() -> Node2D:
	if not is_instance_valid(_tool_overlay):
		_tool_overlay = Node2D.new()
		_tool_overlay.name = "ToolOverlay"
		_tool_overlay.z_index = 4096
		_tool_overlay.z_as_relative = false
		_tool_overlay.draw.connect(_on_tool_overlay_draw)
		add_child(_tool_overlay)
	return _tool_overlay

func _on_tool_overlay_draw() -> void:
	if is_instance_valid(current_tool) and current_tool.has_method("draw_preview"):
		current_tool.draw_preview(_tool_overlay)

func _draw() -> void:
	# El redibujado de herramientas se procesa en _tool_overlay (z_index=4096)
	# para que los nodos, tiradores Bézier y contornos nunca queden cubiertos
	# por el relleno opaco de las figuras ni por los artboards hijos.
	var ov := _get_tool_overlay()
	if is_instance_valid(ov):
		ov.queue_redraw()

# ── API Pública para Redraw Regional ───────────────────────────────────────

func mark_region_dirty(region: Rect2) -> void:
	"""
	Marca una región como 'sucia' para redibujado parcial.
	La región debe estar en coordenadas globales.
	"""
	if region.has_area():
		_dirty_regions.append(region)
		_combine_dirty_regions()
		queue_redraw()
		if is_instance_valid(_tool_overlay):
			_tool_overlay.queue_redraw()


func mark_point_dirty(_point_position: Vector2, radius: float = 10.0) -> void:
	"""
	Marca un punto y su área circundante como 'sucia'.
	Útil para cambios pequeños como selección o manipulación de nodos.
	"""
	var region = Rect2(
		global_position - Vector2(radius, radius),
		Vector2(radius * 2, radius * 2)
	)
	mark_region_dirty(region)


func _combine_dirty_regions() -> void:
	"""
	Combina regiones sucias que se superponen para reducir la cantidad de redibujos.
	"""
	if _dirty_regions.size() <= 1:
		return
	
	var combined_regions: Array[Rect2] = []
	var processed = []
	processed.resize(_dirty_regions.size())
	processed.fill(false)
	
	for i in _dirty_regions.size():
		if processed[i]:
			continue
			
		var current = _dirty_regions[i]
		var merged = current
		processed[i] = true
		
		for j in range(i + 1, _dirty_regions.size()):
			if processed[j]:
				continue
				
			if merged.intersects(_dirty_regions[j]):
				merged = merged.merge(_dirty_regions[j])
				processed[j] = true
			
		combined_regions.append(merged)
	
	_dirty_regions = combined_regions


# ==========================================
# SMART CURSOR SYSTEM
# ==========================================

func _initialize_smart_cursor() -> void:
	"""
	Inicializa el sistema de cursor inteligente.
	"""
	if not smart_cursor:
		push_error("SmartCursor: Sistema de cursor inteligente no disponible")
		return
	
	# Crear material para el cursor
	_cursor_material = ShaderMaterial.new()
	var shader = load("res://shaders/smart_cursor.gdshader")
	if shader:
		_cursor_material.shader = shader
	else:
		push_error("SmartCursor: No se pudo cargar el shader del cursor")
		return
	
	# Conectar señal de cambio de cursor
	smart_cursor.cursor_changed.connect(_on_cursor_changed)
	
	# Configurar cursor inicial
	_update_cursor_material()
	
	# Conectar señal de movimiento del mouse (diferido para evitar Window sin gui_input)
	call_deferred("_connect_gui_input")


func _on_cursor_changed(_shape: int, _color: Color, _animation: int, _size: float) -> void:
	"""
	Maneja el cambio de estado del cursor.
	"""
	_update_cursor_material()
	queue_redraw()


func _update_cursor_material() -> void:
	"""
	Actualiza el material del cursor con los parámetros actuales.
	"""
	if not _cursor_material or not smart_cursor:
		return
	
	# Obtener estado actual del cursor
	var _state = smart_cursor.get_current_state()
	var color = smart_cursor.get_current_color()
	
	# Configurar parámetros del shader
	_cursor_material.set_shader_parameter("shape", smart_cursor.get_current_shape())
	_cursor_material.set_shader_parameter("color", color)
	_cursor_material.set_shader_parameter("size", smart_cursor.get_current_size())
	_cursor_material.set_shader_parameter("pulse_factor", smart_cursor.get_pulse_factor())
	_cursor_material.set_shader_parameter("halo_factor", smart_cursor.get_halo_factor())
	_cursor_material.set_shader_parameter("rotation_angle", smart_cursor.get_rotation_angle())
	_cursor_material.set_shader_parameter("accessibility_mode", false)


func _on_gui_input(event: InputEvent) -> void:
	"""
	Actualiza la posición del cursor.
	"""
	if event is InputEventMouseMotion:
		_cursor_position = event.global_position
		queue_redraw()


func _connect_gui_input() -> void:
	var vp = get_viewport()
	if vp and vp.has_signal("gui_input"):
		vp.gui_input.connect(_on_gui_input)

# ── Métodos de Cámara y Sincronización ────────────────────────────────────────

## Control de pausa de navegación y zoom del canvas (prioridad a objetos 3D)
var _canvas_zoom_paused: bool = false

func pause_canvas_zoom(pause: bool = true) -> void:
	_canvas_zoom_paused = pause

func is_canvas_zoom_paused(at_pos: Vector2 = Vector2.INF) -> bool:
	if _canvas_zoom_paused:
		return true
	var p: Vector2 = at_pos if at_pos != Vector2.INF else get_global_mouse_position()
	if current_tool:
		if current_tool.has_method("is_3d_focused"):
			if current_tool.is_3d_focused(p):
				return true
		if "active_3d_model" in current_tool and is_instance_valid(current_tool.active_3d_model):
			return true
		if "is_middle_dragging_3d" in current_tool and current_tool.is_middle_dragging_3d:
			return true
		if "_is_dragging_3d" in current_tool and current_tool._is_dragging_3d:
			return true
	return false

func zoom_at_point(factor: float, world_point: Vector2) -> void:
	if not is_instance_valid(camera):
		return
	if is_canvas_zoom_paused(world_point):
		return
		
	var old_zoom: float = camera.zoom.x
	var new_zoom: float = clamp(old_zoom * factor, zoom_min, zoom_max)
	if is_equal_approx(new_zoom, old_zoom): 
		return
		
	# Calcular la región afectada por el zoom
	var viewport_size = get_viewport_rect().size
	var region = Rect2(camera.position - (viewport_size / (2 * old_zoom)), 
					  viewport_size / old_zoom)
	
	# Zoom centrado en el puntero: el punto del mundo bajo el cursor permanece fijo
	camera.zoom = Vector2(new_zoom, new_zoom)
	camera.position = world_point + (camera.position - world_point) * (old_zoom / new_zoom)
	
	zoom_percentage = new_zoom * 100.0
	mark_region_dirty(region)

func _reset_camera() -> void:
	if not is_instance_valid(camera):
		return
		
	# Marcar todo el viewport como sucio
	var viewport_size = get_viewport_rect().size
	mark_region_dirty(Rect2(Vector2.ZERO, viewport_size))
	
	if is_instance_valid(artboards_container) and artboards_container.get_child_count() > 0:
		var ab = artboards_container.get_child(0)
		var ab_size = ab.get("artboard_size") if ab.get("artboard_size") else Vector2(800, 600)
		if "position" in ab:
			camera.position = ab.position + ab_size / 2.0
	else:
		camera.position = Vector2.ZERO
		
	camera.zoom = Vector2.ONE
	zoom_percentage = 100.0

func get_current_tool():
	return current_tool

func _sincronizar_ui_toolbar() -> void:
	if is_instance_valid(toolbar_ui) and toolbar_ui.has_method("actualizar_botones_visuales"):
		toolbar_ui.call("actualizar_botones_visuales", current_tool)
		# Marcar solo la región de la toolbar como sucia
		if toolbar_ui:
			var toolbar_rect = toolbar_ui.get_global_rect()
			mark_region_dirty(toolbar_rect)

func _delete_selected_shapes(shapes: Array) -> void:
	if shapes.is_empty():
		return
	var nodes: Array = shapes.duplicate()
	var parents: Array = []
	var indices: Array = []
	for n in nodes:
		if is_instance_valid(n):
			parents.append(n.get_parent())
			indices.append(n.get_index())
		else:
			parents.append(null)
			indices.append(-1)

	if HistoryManager:
		HistoryManager.register_action("Eliminar selección")
		HistoryManager.add_do(_do_remove_nodes.bind(nodes))
		HistoryManager.add_undo(_do_restore_nodes.bind(nodes, parents, indices))
		HistoryManager.commit()
	_do_remove_nodes(nodes)

func _do_remove_nodes(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n) and is_instance_valid(n.get_parent()):
			n.get_parent().remove_child(n)
	if SelectionManager and SelectionManager.has_method("clear"):
		SelectionManager.clear()
	if current_tool and current_tool.has_method("_clear_selection"):
		current_tool._clear_selection()
	queue_redraw()

func _do_restore_nodes(nodes: Array, parents: Array, indices: Array) -> void:
	for i in range(nodes.size()):
		var n = nodes[i]
		var p = parents[i]
		if is_instance_valid(n) and is_instance_valid(p) and not n.is_inside_tree():
			p.add_child(n)
			p.move_child(n, mini(indices[i], p.get_child_count() - 1))
	if SelectionManager and SelectionManager.has_method("set_selection"):
		SelectionManager.set_selection(nodes)
	queue_redraw()
