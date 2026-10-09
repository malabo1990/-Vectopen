# =============================================================================
# RUTA: res://script_gdscript/tools/TextToolBase.gd
# Base común de TextTool (títulos) y ParagraphTool (párrafos): estado de
# edición, hit-test de figuras, salida a MoveTool y utilidades compartidas.
# La lógica de texto en sí vive en TextCore / TextRuns / WorldTextLabel.
# =============================================================================
# Sin `class_name` a propósito (misma convención que canvas_serializer.gd):
# se referencia con preload() y no depende de la caché de clases globales
# del editor (tests headless / CI / editor abierto).
extends ToolBase
const TextRuns = preload("res://script_gdscript/text/text_runs.gd")
const TextCore = preload("res://script_gdscript/text/text_core.gd")


# ── Estado de edición ─────────────────────────────────────────────────────────
var is_editing: bool = false
var current_editing_shape: Node2D = null
var target_artboard: Node2D = null

# ── Máquina de Estados de Interacción (Vectopen Text Engine) ───────────────────
const STATE_IDLE = "idle"
const STATE_SELECTED = "selected"
const STATE_EDITING = "editing"
const STATE_SELECTING = "selecting"
const STATE_DRAGGING = "dragging"
const STATE_TRANSFORMING = "transforming"
const STATE_COMMITTING = "committing"

var interaction_state: String = STATE_IDLE

## Foto del texto al ENTRAR a editar: al confirmar se registra el undo
## before → after (TextCore.register_text_undo).
var _edit_before: Dictionary = {}

## Tamaño supuesto de una figura sin metas width/height (hit-test).
func _default_shape_size() -> Vector2:
	return Vector2(350, 100)

func _shape_size(shape: Node2D) -> Vector2:
	var d := _default_shape_size()
	return Vector2(float(shape.get_meta("width", d.x)), float(shape.get_meta("height", d.y)))

func _finish_editing_and_save() -> void:
	commit_text_edit(false)

## Lo implementa cada herramienta.
func commit_text_edit(_switch_tool: bool = true) -> void:
	pass

## Reajusta `runs` a `new_len` (recorte por el final; para ediciones usar
## TextRuns.apply_text_edit, que respeta la posición del cambio).
func _resize_runs_to_length(shape: Node2D, new_len: int) -> void:
	TextRuns.resize_runs(shape, new_len)

func _notify_format_changed() -> void:
	var ic := _get_autoload("InspectorCore")
	if ic and ic.has_signal("changed"):
		ic.changed.emit(ic.current_props())

static func _get_autoload(autoload_name: String) -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	if ml and ml.root:
		return ml.root.get_node_or_null(autoload_name)
	return null

## Delegado → TextCore.set_vrt_runs (tipado + tamaño base en los runs).
static func _safe_set_runs_meta(vrt, raw_runs) -> void:
	TextCore.set_vrt_runs(vrt, raw_runs)

func _switch_to_move_tool(shape: Node2D) -> void:
	if not (is_instance_valid(canvas) and canvas.has_method("change_tool")):
		return
	var move_tool_script = load("res://script_gdscript/tools/MoveTool.gd")
	if move_tool_script == null:
		return
	var move_tool = canvas._new_tool(move_tool_script)
	move_tool.target_artboard = target_artboard
	if "selected_shapes" in move_tool:
		if move_tool.selected_shapes is Array:
			move_tool.selected_shapes.clear()
			move_tool.selected_shapes.append(shape)
		else:
			move_tool.selected_shapes = shape
	elif "selection" in move_tool:
		if move_tool.selection is Array:
			move_tool.selection.clear()
			move_tool.selection.append(shape)
		else:
			move_tool.selection = shape
	elif "selected_shape" in move_tool:
		move_tool.selected_shape = shape
	canvas.change_tool(move_tool)
	# Después de change_tool(): MoveTool.activate() reconstruye su espejo de
	# selección desde SelectionManager (única fuente de verdad) y lo deja
	# vacío si se selecciona antes. Sin esto el texto recién creado/editado
	# quedaba sin seleccionar y el panel de tipografía mostraba otra cosa.
	var sm := _get_autoload("SelectionManager")
	if is_instance_valid(sm) and sm.has_method("select"):
		sm.select(shape)

func _reset_state() -> void:
	is_editing = false
	current_editing_shape = null
	interaction_state = STATE_IDLE
	var sm := _get_autoload("SelectionManager")
	if is_instance_valid(sm) and sm.has_method("set_active_editing_object"):
		sm.set_active_editing_object(null)

func _refresh_artboard() -> void:
	var mgr := ArtboardManager.find(get_tree()) if get_tree() else null
	if mgr:
		var act := mgr.get_active_artboard()
		if is_instance_valid(act):
			target_artboard = act
			return
	if not is_instance_valid(canvas):
		return
	var container = canvas.get_node_or_null("ArtboardsContainer")
	if container and container.get_child_count() > 0:
		target_artboard = container.get_child(0)

## Figura bajo el punto en TODOS los artboards, con rotación/escala
## (to_local) y dentro de grupos; también figuras sueltas fuera de artboards.
func _shape_at(gpos: Vector2) -> Node2D:
	var artboards: Array = []
	var mgr := ArtboardManager.find(get_tree()) if get_tree() else null
	if mgr:
		artboards = mgr.all_artboards()
	elif is_instance_valid(target_artboard):
		artboards = [target_artboard]
	for ab in artboards:
		if is_instance_valid(ab):
			var found := _find_shape_in_tree(ab, gpos)
			if found:
				return found
	if is_instance_valid(canvas) and "artboards_container" in canvas and is_instance_valid(canvas.artboards_container):
		return _find_shape_in_tree(canvas.artboards_container, gpos)
	return null

func _find_shape_in_tree(node: Node, gpos: Vector2) -> Node2D:
	for i in range(node.get_child_count() - 1, -1, -1):
		var child = node.get_child(i)
		if not (child is Node2D) or child.name in ["Contorno_Stroke", "ArtboardTitle"]:
			continue
		if child.has_meta("shape_type"):
			if Rect2(Vector2.ZERO, _shape_size(child)).has_point(child.to_local(gpos)):
				return child
		var sub := _find_shape_in_tree(child, gpos)
		if sub:
			return sub
	return null

## Avisa object_transformed SOLO si la caja del texto cambió de tamaño: al
## teclear se emitía en CADA tecla y el refresco que dispara (panel de capas,
## caja de selección…) dominaba el coste de escribir.
func _notify_if_resized(shape: Node2D, before: Vector2) -> void:
	var now := Vector2(float(shape.get_meta("width", 0.0)), float(shape.get_meta("height", 0.0)))
	if now.is_equal_approx(before):
		return
	var ge := _get_autoload("GlobalEvents")
	if ge and ge.has_method("emit_safe"):
		ge.emit_safe("object_transformed")

static func _meta_size(shape: Node2D) -> Vector2:
	return Vector2(float(shape.get_meta("width", 0.0)), float(shape.get_meta("height", 0.0)))
