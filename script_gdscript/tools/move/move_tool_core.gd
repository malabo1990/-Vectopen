# =============================================================================
# RUTA: res://script_gdscript/tools/move/move_tool_core.gd
# MoveToolCore: estado de la herramienta, geometría (bounding box), hit-testing,
# detección de tiradores, gestión de la selección, snapshots y commit/undo.
# Parte de la herramienta Mover (MoveTool), dividida por capas de herencia:
#   move_tool_core → transform → ops → threading → keyboard → 3d → draw → MoveTool
# El código se movió TAL CUAL desde MoveTool.gd (sin cambios de comportamiento).
# =============================================================================
extends ToolBase

const TextCore = preload("res://script_gdscript/text/text_core.gd")
const TextRuns = preload("res://script_gdscript/text/text_runs.gd")

# ── Referencias ───────────────────────────────────────────────────────────────
var target_artboard: Node2D = null

# ── Selección ─────────────────────────────────────────────────────────────────
## `SelectionManager` (autoload) es la única fuente de verdad de la selección
## viva — ver docs/es/guides/PANEL_DE_CAPAS_PROFESIONAL.md (Fase 1). Este array
## es un ESPEJO local: MoveTool lo escribe y `_emit_selection_changed()` lo
## refleja hacia SelectionManager; cuando la selección cambia desde otra
## superficie (panel de capas, atajo global) `_on_external_selection_changed()`
## la copia de vuelta aquí. Se mantiene como variable real para no romper los
## ~40 puntos de test y las herramientas de texto que lo asignan directamente.
var selected_shapes: Array[Node2D] = []
var _bounding_box: Node = null  # Referencia al bounding box del pool
var _sel_conn: bool = false     # ¿conectado a SelectionManager.changed?
var _pushing_selection: bool = false  # evita el eco al reflejar hacia el manager
var is_gradient_mode: bool = false   # Modo herramienta de degradado (Atajo G / Affinity style)
var active_3d_model: Node2D = null    # Modelo 3D actualmente en modo de edición orbital
var _is_dragging_3d: bool = false     # Arrastre orbital activo en 3D
var _last_3d_mouse: Vector2 = Vector2.ZERO
var is_middle_dragging_3d: bool = false
var _mmb_3d_target: Node2D = null
var _last_mmb_3d_pos: Vector2 = Vector2.ZERO

# ── Estado de arrastre de objetos ─────────────────────────────────────────────
var is_dragging_shape: bool = false
var _alt_drag_duplicated: bool = false
var is_dragging_thread: bool = false
var thread_source_frame: Node2D = null
var thread_target_pos: Vector2 = Vector2.ZERO
## "" | "x" | "y" — cuando el usuario arrastra un handle de eje del bounding box,
## el movimiento se restringe a ese eje.
var _axis_move: String = ""
## "" | "x" | "y" — eje de Shift+arrastrar sobre el CUERPO de la figura (no un
## handle), decidido UNA SOLA VEZ al detectar Shift y fijo el resto del gesto.
## Bug real reportado en vivo ("shift y drag en area de BB... sigue con
## fallos"): antes se recalculaba cada frame comparando abs(delta.x) vs
## abs(delta.y) del delta ACUMULADO desde el inicio del gesto — si el mouse
## titubeaba cerca de la diagonal, el eje "bloqueado" podía cambiar a mitad
## de arrastre, lo que se siente roto (Figma/Affinity deciden el eje una vez
## y no lo sueltan hasta soltar Shift).
var _shift_drag_axis: String = ""
## Candidato a "Shift+clic sobre figura ya seleccionada = quitarla de la
## selección" (comportamiento estándar de multi-selección). BUG REAL
## reportado en vivo ("shift y drag... de repente ha desaparecido
## boundingbox"): antes esto se ejecutaba INMEDIATAMENTE en mouse-DOWN, así
## que el simple gesto de apretar Shift y empezar a arrastrar una figura ya
## seleccionada la deseleccionaba en el acto (el bounding box desaparecía
## antes de que el arrastre llegara a moverla). Ahora el press NO deselecciona
## — solo apunta aquí al candidato — y el release decide: si no hubo
## arrastre real, deselecciona (comportamiento de clic); si sí lo hubo, se
## queda seleccionada y el movimiento con eje ya aplicado se conserva.
var _pending_shift_deselect: Node2D = null
## Unselected shape under the pointer, outlined as a hover preview (a text
## object additionally gets its baseline marked).
var _hover_shape: Node2D = null
const COLOR_HOVER: Color = Color(0.05, 0.55, 0.91, 1.0)

# ── Estado de transformación avanzada ─────────────────────────────────────────
var is_resizing: bool = false
var is_rotating: bool = false
var _is_stroke_adjusting: bool = false
var resize_handle: String = ""
## Estado EN VIVO de la transformación en curso — lo lee el bounding box para
## dibujar una caja estable (que rota/escala con el gesto) en multiselección,
## en vez de recalcular el AABB de las figuras ya rotadas cada frame.
var live_rot_angle: float = 0.0
var live_scale: Vector2 = Vector2.ONE
var live_pivot: Vector2 = Vector2.ZERO
var transform_initial_mouse: Vector2 = Vector2.ZERO
var transform_macro_rect: Rect2 = Rect2()
var transform_initial_states: Dictionary = {}
var initial_macro_center: Vector2 = Vector2.ZERO

# ── Estado marquee ─────────────────────────────────────────────────────────────
var is_marquee: bool = false
var marquee_start: Vector2 = Vector2.ZERO
var marquee_end: Vector2 = Vector2.ZERO

# ── Estado artboard ───────────────────────────────────────────────────────────
var is_dragging_artboard: bool = false
var is_resizing_artboard: bool = false
var artboard_resize_edge: Vector2 = Vector2.ZERO
var artboard_drag_start_mouse: Vector2 = Vector2.ZERO
var artboard_drag_start_pos: Vector2 = Vector2.ZERO

# ── Imán inteligente (líneas guía mientras se arrastra) ────────────────────────
var _snap_guides: Array = []
var _snap_spacing: Array = []

# ── Modos de transformación por teclado ────────────────────────────────────
enum KeyMode { NONE, TRANSLATE, SCALE, ROTATE }
var current_key_mode: KeyMode = KeyMode.NONE

enum AxisLock { NONE, X, Y }
var current_axis: AxisLock = AxisLock.NONE

## Doble-clic PROPIO para texto (el flag del motor exige una ventana del SO
## que a muchos les obliga a triple/cuádruple clic). Ventana generosa solo
## para entrar a editar texto; el resto de figuras sigue con event.double_click.
const OWN_DBLCLICK_MS := 600
const OWN_DBLCLICK_PX := 12.0
var _last_press_time: int = 0
var _last_press_pos := Vector2.ZERO
var _last_press_shape: Node2D = null

# ── Constantes visuales profesionales ─────────────────────────────────────────
const HANDLE_SIZE: float = 8.0
const CLICK_TOLERANCE: float = 12.0
const ROTATE_ZONE: float = 18.0
const STALK_LENGTH: float = 24.0 
const MIN_LINE_PAD: float = 6.0

# Colores de alta fidelidad (estilo profesional y neutro, acento suave)
const COLOR_BBOX: Color = Color(0.35, 0.50, 0.68, 1.0)        # acento neutro y suave (no azul chillón)
const COLOR_HANDLE_F: Color = Color(1.0, 1.0, 1.0, 1.0)      # Fondo tiradores
const COLOR_MARQUEE_F: Color = Color(0.35, 0.50, 0.68, 0.08)  # Relleno marquee suave
const COLOR_MARQUEE_S: Color = Color(0.35, 0.50, 0.68, 0.65)  # Contorno marquee suave
const COLOR_SNAP_GUIDE: Color = Color(1.0, 0.19, 0.42, 0.95)  # magenta: alineación con figuras
const COLOR_SNAP_RULE: Color = Color(0.35, 0.50, 0.68, 0.95)   # enganche a guía de regla con acento suave

func _exit_3d_mode() -> void:
	if is_middle_dragging_3d:
		end_middle_drag_3d()
	if is_instance_valid(active_3d_model):
		if active_3d_model.has_method("end_interactive_orbit"):
			active_3d_model.end_interactive_orbit()
		if active_3d_model.has_method("set_3d_editing"):
			active_3d_model.set_3d_editing(false)
		if active_3d_model.has_method("capture_high_quality"):
			active_3d_model.capture_high_quality()
	active_3d_model = null
	_is_dragging_3d = false
	if is_instance_valid(canvas) and canvas.has_method("pause_canvas_zoom"):
		canvas.pause_canvas_zoom(false)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func end_middle_drag_3d() -> void:
	if is_middle_dragging_3d:
		is_middle_dragging_3d = false
		if is_instance_valid(_mmb_3d_target):
			if _mmb_3d_target.has_method("end_interactive_orbit"):
				_mmb_3d_target.end_interactive_orbit()
			elif _mmb_3d_target.has_method("capture_high_quality"):
				_mmb_3d_target.capture_high_quality()
		_mmb_3d_target = null
		if not is_instance_valid(active_3d_model):
			if is_instance_valid(canvas) and canvas.has_method("pause_canvas_zoom"):
				canvas.pause_canvas_zoom(false)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		if is_instance_valid(canvas):
			canvas.queue_redraw()

## ¿`posible_ancestro` está por encima de `nodo` en el árbol?
func _es_ancestro(posible_ancestro: Node, nodo: Node) -> bool:
	var a: Node = nodo.get_parent() if is_instance_valid(nodo) else null
	while a != null:
		if a == posible_ancestro:
			return true
		a = a.get_parent()
	return false


## Registra (y aplica) UNA acción de undo para una transformación de figuras.
## Captura el estado COMPLETO antes (de transform_initial_states) y después
## (_snapshot fresco) de cada figura + el cambio de padre. `solo_transform`
## true en resize/rotar → no se reparenta (la figura no "se mueve" de artboard).
func _commit_transform(action_name: String, nodes: Array, solo_transform: bool) -> void:
	var mgr := ArtboardManager.find(get_tree()) if is_inside_tree() else null
	var container: Node = canvas.get_node_or_null("ArtboardsContainer") if is_instance_valid(canvas) else null
	var recs: Array = []
	for n in nodes:
		if not is_instance_valid(n) or not is_instance_valid(n.get_parent()):
			continue
		if n is ArtboardEditor or n.name == "ArtboardTitle" or n.name == "Contorno_Stroke":
			continue
		var before: Dictionary = transform_initial_states.get(n, {})
		if before.is_empty():
			continue
		var after: Dictionary = _snapshot(n)
		var old_parent: Node = n.get_parent()
		var new_parent: Node = old_parent
		if not solo_transform and mgr and is_instance_valid(container):
			var owner_ab := mgr.owning_artboard(n)
			var shape_rect := _global_rect(n)
			var shape_center: Vector2 = shape_rect.get_center() if shape_rect.size != Vector2.ZERO else ((n as Node2D).global_position if n is Node2D else Vector2.ZERO)
			var hit_ab := mgr.artboard_at_point(shape_center)
			if hit_ab != null:
				if hit_ab != owner_ab:
					new_parent = hit_ab
			elif is_instance_valid(owner_ab) and mgr.world_rect(owner_ab).intersects(shape_rect):
				new_parent = owner_ab
			elif owner_ab != null:
				new_parent = container
		if _snap_equal(before, after) and new_parent == old_parent:
			continue
		recs.append({
			"n": n, "before": before, "after": after,
			"op": old_parent, "oi": n.get_index(), "np": new_parent, "ni": -1,
		})
	if recs.is_empty():
		return
	HistoryManager.register_action(action_name)
	HistoryManager.add_do(_do_apply_transform.bind(recs, false))
	HistoryManager.add_undo(_do_apply_transform.bind(recs, true))
	HistoryManager.commit()
	_do_apply_transform(recs, false)


## Aplica (redo) o revierte (undo) el conjunto de transformaciones+reparent.
## El índice dentro del padre se restaura en AMBAS direcciones: en undo al
## `oi` original, en redo al `ni` que se memoriza en la primera aplicación —
## así redo deja el z-order idéntico a la operación original, no "al final".
func _do_apply_transform(recs: Array, undo: bool) -> void:
	for r in recs:
		var n: Node2D = r["n"]
		if not is_instance_valid(n):
			continue
		var parent: Node = r["op"] if undo else r["np"]
		if not is_instance_valid(parent):
			_restore_transform(n, r["before"] if undo else r["after"])
			continue
		if n.get_parent() != parent:
			n.reparent(parent, true)
		var idx: int = int(r["oi"]) if undo else int(r.get("ni", -1))
		if idx >= 0:
			parent.move_child(n, clampi(idx, 0, parent.get_child_count() - 1))
		elif not undo:
			r["ni"] = n.get_index()   # primera aplicación: recuerda dónde cae
		_restore_transform(n, r["before"] if undo else r["after"])
	_update_bounding_box()
	if is_instance_valid(canvas):
		canvas.queue_redraw()
	if GlobalEvents:
		GlobalEvents.emit_safe("object_transformed")
		GlobalEvents.emit_safe("object_style_changed")


## ¿Dos snapshots representan el mismo estado (posición/rotación/tamaño)?
func _snap_equal(a: Dictionary, b: Dictionary) -> bool:
	var ap: Vector2 = a.get("gpos", Vector2.ZERO)
	var bp: Vector2 = b.get("gpos", Vector2.ZERO)
	if not ap.is_equal_approx(bp):
		return false
	if not is_equal_approx(a.get("grot", 0.0), b.get("grot", 0.0)):
		return false
	if a.has("size") and b.has("size") and not (a["size"] as Vector2).is_equal_approx(b["size"]):
		return false
	if a.has("w") and b.has("w") and not is_equal_approx(a["w"], b["w"]):
		return false
	if a.has("h") and b.has("h") and not is_equal_approx(a["h"], b["h"]):
		return false
	if a.has("stroke_width") and b.has("stroke_width") and not is_equal_approx(a["stroke_width"], b["stroke_width"]):
		return false
	if a.has("stroke_sides") and b.has("stroke_sides") and not (a["stroke_sides"] as Vector4).is_equal_approx(b["stroke_sides"]):
		return false
	if a.has("scale") and b.has("scale") and not (a["scale"] as Vector2).is_equal_approx(b["scale"]):
		return false
	if not NodeState.equal(a.get("_ns", {}), b.get("_ns", {})):
		return false
	return true


## Escribe de vuelta TODO lo que capturó _snapshot: rotación, posición,
## tamaño/extent, vértices, puntos de línea/path, metas de texto. Inverso
## exacto de _apply_resize / _apply_rotation / la traslación, usado por el
## undo/redo (_do_apply_transform) y por cancelar (Escape) una transformación.
func _restore_transform(shape: Node2D, snap: Dictionary) -> void:
	if not is_instance_valid(shape) or snap.is_empty():
		return
	# 1) rotación (antes de reconstruir puntos: to_local depende de ella).
	#    grot es la verdad de render; doc_rot se re-deriva.
	if snap.has("grot"):
		shape.global_rotation = snap["grot"]
	if shape is VectorShape and snap.has("doc_rot"):
		shape.doc_rotation = snap["doc_rot"]
	# 2) posición — gpos (global) es la autoridad; doc_position se re-sincroniza.
	if snap.has("gpos"):
		shape.global_position = snap["gpos"]
	# 3) tamaño / extent — el `size` nativo es la verdad de render
	if snap.has("size") and "size" in shape:
		shape.set("size", snap["size"])
		if shape is VectorShape and shape.has_doc_extent():
			shape.set_doc_extent(DVec2.from_v2(snap["size"]))
	elif shape is VectorShape and snap.has("doc_extent") and shape.has_doc_extent():
		shape.set_doc_extent(snap["doc_extent"])
	# 4) texto (metas width/height)
	if snap.has("w") and shape.has_meta("shape_type"):
		shape.set_meta("width", snap["w"])
		if snap.has("h"):
			shape.set_meta("height", snap["h"])
		if snap.has("font_size"):
			shape.set_meta("font_size", snap["font_size"])
		if snap.has("runs") and not (snap["runs"] as Array).is_empty():
			shape.set_meta("runs", (snap["runs"] as Array).duplicate(true))
		_update_text_node_sizes(shape, snap["w"], snap.get("h", 80.0), snap.get("font_size", -1))
	elif snap.has("w") and "width" in shape:
		shape.set("width", snap["w"])
		if snap.has("h") and "height" in shape:
			shape.set("height", snap["h"])
	# 5) vértices (guardados en global → volver a local)
	if snap.has("g_verts") and "vertices" in shape:
		var lv := PackedVector2Array()
		for gv in snap["g_verts"]:
			lv.append(shape.to_local(gv))
		shape.set("vertices", lv)
	# 6) Polygon2D
	if snap.has("g_poly_pts") and shape is Polygon2D:
		var lp := PackedVector2Array()
		for gp in snap["g_poly_pts"]:
			lp.append(shape.to_local(gp))
		shape.polygon = lp
		if snap.has("g_stroke_pts"):
			var st = shape.get_node_or_null("Contorno_Stroke")
			if st is Line2D:
				var ls := PackedVector2Array()
				for gs in snap["g_stroke_pts"]:
					ls.append(st.to_local(gs))
				st.points = ls
	# 7) Line2D
	if snap.has("g_pts") and shape is Line2D:
		var lpt := PackedVector2Array()
		for g in snap["g_pts"]:
			lpt.append(shape.to_local(g))
		shape.points = lpt
	# 8) Path2D
	if snap.has("g_path_nodes") and shape is Path2D and shape.curve:
		var cv: Curve2D = shape.curve
		var nd = snap["g_path_nodes"]
		for i in range(mini(cv.point_count, nd.size())):
			var lpp := shape.to_local(nd[i]["node"])
			cv.set_point_position(i, lpp)
			cv.set_point_in(i, shape.to_local(nd[i]["in"]) - lpp)
			cv.set_point_out(i, shape.to_local(nd[i]["out"]) - lpp)
	# 9) estado no-geométrico (visibilidad / bloqueo / recorte / z-order)
	if snap.has("_ns"):
		NodeState.restore(shape, snap["_ns"])
	# 10) grosor de trazo
	if snap.has("stroke_width"):
		_set_shape_stroke_width(shape, float(snap["stroke_width"]))
	if snap.has("stroke_sides") and "stroke_sides" in shape:
		shape.stroke_sides = snap["stroke_sides"]
	# 11) escala de Sprite2D / imágenes
	if snap.has("scale") and shape is Sprite2D:
		shape.scale = snap["scale"]
	_sync_doc_position_from_native(shape)
	if shape.has_method("queue_redraw"):
		shape.queue_redraw()

func _update_text_node_sizes(shape: Node2D, w: float, h: float, fs: int = -1) -> void:
	var display_label: Control = shape.get_node_or_null("DisplayLabel")
	var multi_edit: Control = shape.get_node_or_null("MultiLineEdit")
	if not multi_edit: multi_edit = shape.get_node_or_null("LineEdit")
	if not multi_edit: multi_edit = shape.get_node_or_null("TitleEdit")
	
	if display_label:
		if display_label is WorldTextLabel:
			display_label.set_world_size(Vector2(w, h))
			if fs > 0:
				# Por el setter: salta el throttle, invalida el overlay y
				# repinta en el frame (escribir base_font_size a mano no).
				display_label.world_font_size = fs
				display_label.set_rich_runs(shape.get_meta("runs", []))
		else:
			display_label.custom_minimum_size = Vector2(w, h)
			display_label.size = Vector2(w, h)
			if fs > 0:
				display_label.add_theme_font_size_override("font_size", fs)
	if multi_edit:
		multi_edit.custom_minimum_size = Vector2(w, h)
		multi_edit.size = Vector2(w, h)
		if fs > 0 and multi_edit is Control:
			multi_edit.add_theme_font_size_override("font_size", fs)

	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		vrt.set_frame_size(Vector2(w, h))
		vrt.custom_minimum_size = Vector2(w, h)
		vrt.size = Vector2(w, h)
		if fs > 0:
			# set_font_size() ponía el MISMO tamaño a todos los runs (y con
			# ello se perdían tamaños por letra); con runs se pasan tal cual.
			var runs_now: Array = shape.get_meta("runs", [])
			if not runs_now.is_empty() and TextRuns.runs_len(runs_now) == String(shape.get_meta("text", "")).length():
				TextCore.set_vrt_runs(vrt, runs_now)
			else:
				vrt.set_font_size(float(fs))
		vrt.queue_redraw()

	if shape.has_meta("shape_type") and shape.get_meta("shape_type") == "text_paragraph":
		if shape.has_meta("next_paragraph") or shape.has_meta("prev_paragraph"):
			var head := ParagraphThreading.get_chain_head(shape)
			ParagraphThreading.reflow_chain(head)

# ── Gestión de Selección Avanzada ──────────────────────────────────────────────

func _select(shape: Node2D) -> void:
	if is_instance_valid(shape) and not selected_shapes.has(shape):
		selected_shapes.append(shape)
	_update_macro_rect()
	_emit_selection_changed()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _deselect(shape: Node2D) -> void:
	if selected_shapes.has(shape):
		selected_shapes.erase(shape)
		_update_macro_rect()
		_emit_selection_changed()
		if is_instance_valid(canvas):
			canvas.queue_redraw()

func _clear_selection() -> void:
	if is_instance_valid(active_3d_model):
		_exit_3d_mode()
	var tenia := not selected_shapes.is_empty()
	selected_shapes.clear()
	transform_initial_states.clear()
	_update_macro_rect()  # oculta el bounding box (la selección ahora está vacía)
	if tenia:
		_emit_selection_changed()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

## Refleja el espejo local hacia SelectionManager (única fuente de verdad).
## SelectionManager re-emite `GlobalEvents.selection_changed`, así que
## InspectorCore / bounding_box siguen enterándose igual que antes.
func _emit_selection_changed() -> void:
	if not SelectionManager:
		if GlobalEvents and GlobalEvents.has_signal("selection_changed"):
			GlobalEvents.emit_safe("selection_changed", selected_shapes.duplicate())
		return
	_pushing_selection = true
	SelectionManager.set_selection(selected_shapes)
	# Alinear el espejo con lo que el manager aceptó (p. ej. descarta bloqueados).
	selected_shapes.assign(SelectionManager.get_selected())
	_pushing_selection = false

## La selección cambió desde OTRA superficie (panel de capas, atajo global…).
## Copia al espejo local y reconstruye el bounding box; no reentra.
func _on_external_selection_changed(nueva: Array = []) -> void:
	if _pushing_selection:
		return
	selected_shapes.clear()
	for s in nueva:
		if is_instance_valid(s) and s is Node2D:
			selected_shapes.append(s)
	_update_macro_rect()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

# ── Operaciones sobre la selección — Fase 1 (teclado/portapapeles) ───────────
# Añadido el 19/08/2026 a partir del informe de interacción avanzada del
# usuario. Cablea Eliminar/Copiar/Cortar/Pegar/Duplicar/Seleccionar todo/
# mover con flechas — antes VectopenInput.gd ya declaraba los atajos pero
# ningún código los escuchaba (verificado con grep antes de empezar: cero
# resultados fuera de VectopenInput.gd mismo). Todas registran una acción
# real en HistoryManager, así que también se pueden deshacer con Ctrl+Z —
# primer uso real de HistoryManager.register_action() en toda la app (antes
# solo lo usaba el CRUD de ProjectManager, que no tiene llamador real desde
# la UI, ver §1.6/§1.7 del informe).

const NUDGE_STEP: float = 1.0
const NUDGE_STEP_SHIFT: float = 10.0

## Quita los nodos del árbol SIN liberarlos (mantiene la referencia viva para
## que el undo pueda restaurarlos). Límite conocido y aceptado: si la acción
## se descarta del historial sin deshacerse nunca (más de max_history
## acciones después), el nodo queda huérfano en memoria — igual que el resto
## de callables de deshacer en este proyecto (ver ProjectManager), este
## UndoRedoManager simplificado no tiene un gancho de "acción descartada"
## para liberar en ese caso. Aceptable para el alcance de esta Fase 1.
func _do_remove_nodes(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n) and is_instance_valid(n.get_parent()):
			n.get_parent().remove_child(n)
	_clear_selection()
	if SelectionManager and SelectionManager.has_method("clear"):
		SelectionManager.clear()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _commit_add_nodes(action_name: String, new_nodes: Array) -> void:
	HistoryManager.register_action(action_name)
	HistoryManager.add_do(_do_add_nodes.bind(new_nodes, target_artboard))
	HistoryManager.add_undo(_do_remove_nodes.bind(new_nodes))
	HistoryManager.commit()
	_do_add_nodes(new_nodes, target_artboard)

	selected_shapes.clear()
	for n in new_nodes:
		selected_shapes.append(n)
	_update_macro_rect()
	_emit_selection_changed()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _do_add_nodes(nodes: Array, parent: Node) -> void:
	for n in nodes:
		if is_instance_valid(n) and not n.is_inside_tree():
			parent.add_child(n)

# ── Motor de Hit-Testing e Intersección de Precisión Geométrica ───────────────

func _shape_at(gpos: Vector2) -> Node2D:
	# Busca en TODOS los artboards (no solo el activo) + las figuras sueltas
	# hijas directas del contenedor. Antes solo miraba target_artboard, así
	# que con varios artboards solo se podían seleccionar figuras del primero.
	var mgr := ArtboardManager.find(get_tree()) if is_inside_tree() else null
	var artboards: Array = mgr.all_artboards() if mgr else ([target_artboard] if target_artboard else [])

	for ab in artboards:
		if not is_instance_valid(ab):
			continue
		var hit := _shape_at_in(ab, gpos)
		if hit:
			return hit

	# Figuras sueltas (hijas directas de ArtboardsContainer, fuera de todo artboard)
	var container: Node = canvas.get_node_or_null("ArtboardsContainer") if is_instance_valid(canvas) else null
	if container:
		var loose: Array = container.get_children()
		for i in range(loose.size() - 1, -1, -1):
			var n = loose[i]
			if n is Node2D and not (n is ArtboardEditor) and _node_contains_point(n, gpos):
				return n
	return null

func _shape_at_in(ab: Node2D, gpos: Vector2) -> Node2D:
	# Se prueban las capas de PRIMER nivel (hijas del artboard o de la
	# VectorDrawingLayer). Si una es un GRUPO, se comprueba su rama entera y, si
	# el punto cae dentro, se devuelve el GRUPO (clic sencillo = seleccionar el
	# grupo, como en un editor profesional). Antes solo se miraban los hijos
	# directos → una figura dentro de un grupo no se podía coger y el clic
	# deseleccionaba.
	var dl: Node = ab.get_node_or_null("VectorDrawingLayer")
	if dl:
		var h := _hit_top_level(dl, gpos, [])
		if h:
			return h
	return _hit_top_level(ab, gpos, ["ArtboardTitle", "VectorDrawingLayer"])

## Devuelve la primera capa de PRIMER nivel (hija directa de `raiz`) cuya rama
## contiene `gpos`. Recorre de arriba a abajo en Z (último hijo primero).
func _hit_top_level(raiz: Node, gpos: Vector2, excluir: Array) -> Node2D:
	var hijos: Array = raiz.get_children()
	for i in range(hijos.size() - 1, -1, -1):
		var n = hijos[i]
		if not (n is Node2D) or String(n.name) in excluir or String(n.name) == "Contorno_Stroke":
			continue
		if _es_grupo_movetool(n):
			if _rama_contiene_punto(n, gpos):
				return n
		elif _node_contains_point(n, gpos):
			return n
	return null

## ¿`n` actúa como CONTENEDOR para el hit-test? Sí si:
##  - es un grupo pelado con hijos, o `shape_type == "group"`, o
##  - es una FIGURA que ADEMÁS de su geometría tiene otras figuras anidadas
##    dentro (rectángulo → rectángulo hijo → …). `VectorShape` dibuja por
##    `_draw()` sin nodos hijos de render, así que cualquier `Node2D` hijo
##    (que no sea `Contorno_Stroke`) es una figura del usuario.
func _es_grupo_movetool(n: Node) -> bool:
	if not (n is Node2D):
		return false
	if n.has_meta("shape_type") and String(n.get_meta("shape_type")) == "group":
		return true
	for c in n.get_children():
		if c is Node2D and String(c.name) != "Contorno_Stroke":
			return true
	return false

## ¿`n` tiene geometría propia dibujable (para comprobar su cuerpo en el hit-test)?
func _tiene_cuerpo_propio(n: Node) -> bool:
	return n is VectorShape or n is Line2D or n is Polygon2D or n is Path2D or n is Sprite2D

## Primera figura de `selected_shapes` que sea descendiente de `grupo`, o null.
func _primer_seleccionado_en_rama(grupo: Node) -> Node2D:
	for s in selected_shapes:
		if not is_instance_valid(s):
			continue
		var a: Node = s
		while a != null:
			if a == grupo:
				return s
			a = a.get_parent()
	return null

func _node_contains_point(node: Node2D, gpos: Vector2) -> bool:
	if not is_instance_valid(node):
		return false
	if "size" in node and (node is VectorRectangle or node is VectorCircle or node.has_method("rotate_orbit")):
		var s: Vector2 = node.get("size")
		var lpt: Vector2 = node.to_local(gpos)
		if node is VectorCircle:
			var r: float = s.x * 0.5
			return lpt.length_squared() <= r * r
		return Rect2(-s * 0.5, s).has_point(lpt)
	if node is Polygon2D:
		var poly := node as Polygon2D
		if poly.polygon.size() >= 3:
			return Geometry2D.is_point_in_polygon(poly.to_local(gpos), poly.polygon)
	if node.has_meta("shape_type") and (node.get_meta("shape_type") in ["text_paragraph", "text_title"]):
		var w: float = node.get_meta("width") if node.has_meta("width") else 350.0
		var h: float = node.get_meta("height") if node.has_meta("height") else 65.0
		var lpt: Vector2 = node.to_local(gpos)
		return Rect2(Vector2.ZERO, Vector2(w, h)).has_point(lpt)
	if "vertices" in node:
		var verts: PackedVector2Array = node.get("vertices")
		if verts.size() >= 3:
			return Geometry2D.is_point_in_polygon(node.to_local(gpos), verts)
	if node is Sprite2D and (node as Sprite2D).texture:
		var sp: Sprite2D = node as Sprite2D
		return sp.get_rect().has_point(sp.to_local(gpos))
	return _global_rect(node).has_point(gpos)

func _rama_contiene_punto(nodo: Node, gpos: Vector2) -> bool:
	# El CUERPO propio del nodo cuenta (una figura-contenedor sigue siendo
	# clicable sobre su propio relleno, no solo sobre sus hijos).
	if _tiene_cuerpo_propio(nodo) and _node_contains_point(nodo, gpos):
		return true
	for c in nodo.get_children():
		if not (c is Node2D) or String(c.name) == "Contorno_Stroke":
			continue
		if _es_grupo_movetool(c):
			if _rama_contiene_punto(c, gpos):
				return true
		elif _node_contains_point(c, gpos):
			return true
	return false

# ── Cálculo Dinámico del Bounding Box Pro (Soporte Títulos y Párrafos) ─────────

func _global_rect(node: Node2D) -> Rect2:
	if not is_instance_valid(node): return Rect2()

	if node.has_meta("shape_type") and (node.get_meta("shape_type") in ["text_paragraph", "text_title"]):
		var w: float = float(node.get_meta("width", 350.0))
		var h: float = float(node.get_meta("height", 65.0))
		var vrt = node.get_node_or_null("VectorRichText")
		if vrt:
			var vs: Vector2 = vrt.get_size()
			if vs.x > 0.0 and vs.y > 0.0:
				w = maxf(w, vs.x)
				h = maxf(h, vs.y)
		return Rect2(node.global_position, Vector2(w, h))

	if node is Path2D:
		var curve: Curve2D = (node as Path2D).curve
		var baked = curve.get_baked_points()
		if baked.size() == 0:
			return Rect2(node.global_position - Vector2(10, 10), Vector2(20, 20))
		
		var first_gpt: Vector2 = node.to_global(baked[0])
		var g_mn: Vector2 = first_gpt
		var g_mx: Vector2 = first_gpt
		for p in baked:
			var g_pt: Vector2 = node.to_global(p)
			g_mn.x = min(g_mn.x, g_pt.x)
			g_mn.y = min(g_mn.y, g_pt.y)
			g_mx.x = max(g_mx.x, g_pt.x)
			g_mx.y = max(g_mx.y, g_pt.y)
			
		var pad: float = MIN_LINE_PAD
		var renderer = node.get_node_or_null("Render_Visual")
		if renderer is Line2D:
			pad = max(pad, renderer.width * 0.5)
		return Rect2(g_mn, g_mx - g_mn).grow(pad)

	if node is Polygon2D:
		var poly = node as Polygon2D
		if poly.polygon.size() > 0:
			var first_gpt: Vector2 = poly.to_global(poly.polygon[0])
			var g_mn: Vector2 = first_gpt
			var g_mx: Vector2 = first_gpt
			for p in poly.polygon:
				var g_pt: Vector2 = poly.to_global(p)
				g_mn.x = min(g_mn.x, g_pt.x)
				g_mn.y = min(g_mn.y, g_pt.y)
				g_mx.x = max(g_mx.x, g_pt.x)
				g_mx.y = max(g_mx.y, g_pt.y)
			return Rect2(g_mn, g_mx - g_mn)

	if "size" in node and (node is VectorRectangle or node is VectorCircle or node.has_method("rotate_orbit")):
		var s: Vector2 = node.get("size")
		if is_zero_approx(node.global_rotation):
			return Rect2(node.global_position - s * 0.5, s)
		var corners := [
			node.to_global(-s * 0.5),
			node.to_global(Vector2(s.x * 0.5, -s.y * 0.5)),
			node.to_global(s * 0.5),
			node.to_global(Vector2(-s.x * 0.5, s.y * 0.5))
		]
		var g_mn: Vector2 = corners[0]
		var g_mx: Vector2 = corners[0]
		for p in corners:
			g_mn.x = min(g_mn.x, p.x); g_mn.y = min(g_mn.y, p.y)
			g_mx.x = max(g_mx.x, p.x); g_mx.y = max(g_mx.y, p.y)
		return Rect2(g_mn, g_mx - g_mn)

	if "vertices" in node:
		var verts: PackedVector2Array = node.get("vertices")
		if verts.size() == 0:
			return Rect2(node.global_position - Vector2(10, 10), Vector2(20, 20))
		var first_gpt: Vector2 = node.to_global(verts[0])
		var g_mn: Vector2 = first_gpt
		var g_mx: Vector2 = first_gpt
		for p in verts:
			var g_pt: Vector2 = node.to_global(p)
			g_mn.x = min(g_mn.x, g_pt.x)
			g_mn.y = min(g_mn.y, g_pt.y)
			g_mx.x = max(g_mx.x, g_pt.x)
			g_mx.y = max(g_mx.y, g_pt.y)
		return Rect2(g_mn, g_mx - g_mn)

	if "width" in node and "height" in node:
		var w: float = node.get("width")
		var h: float = node.get("height")
		var size_vec: Vector2 = Vector2(w, h)
		return Rect2(node.global_position - size_vec * 0.5, size_vec)

	if node is Line2D:
		var line: Line2D = node as Line2D
		if line.points.size() == 0:
			return Rect2(line.global_position - Vector2(10, 10), Vector2(20, 20))
		var first_gpt: Vector2 = line.to_global(line.points[0])
		var g_mn: Vector2 = first_gpt
		var g_mx: Vector2 = first_gpt
		for p in line.points:
			var g_pt: Vector2 = line.to_global(p)
			g_mn.x = min(g_mn.x, g_pt.x)
			g_mn.y = min(g_mn.y, g_pt.y)
			g_mx.x = max(g_mx.x, g_pt.x)
			g_mx.y = max(g_mx.y, g_pt.y)
		var pad: float = max(MIN_LINE_PAD, line.width * 0.5)
		return Rect2(g_mn, g_mx - g_mn).grow(pad)

	if node is Sprite2D and (node as Sprite2D).texture:
		var sp: Sprite2D = node as Sprite2D
		var lr: Rect2 = sp.get_rect()   # local, respeta centered/region/hframes
		var corners := [
			sp.to_global(lr.position),
			sp.to_global(Vector2(lr.end.x, lr.position.y)),
			sp.to_global(lr.end),
			sp.to_global(Vector2(lr.position.x, lr.end.y)),
		]
		var g_mn: Vector2 = corners[0]
		var g_mx: Vector2 = corners[0]
		for gp in corners:
			g_mn.x = min(g_mn.x, gp.x); g_mn.y = min(g_mn.y, gp.y)
			g_mx.x = max(g_mx.x, gp.x); g_mx.y = max(g_mx.y, gp.y)
		return Rect2(g_mn, g_mx - g_mn)

	if node.has_method("get_evaluated_geometry"):
		var polys: Array[PackedVector2Array] = node.call("get_evaluated_geometry")
		if not polys.is_empty():
			var first_gp: Vector2 = node.to_global(polys[0][0])
			var g_mn: Vector2 = first_gp
			var g_mx: Vector2 = first_gp
			for poly in polys:
				for p in poly:
					var gp: Vector2 = node.to_global(p)
					g_mn.x = min(g_mn.x, gp.x); g_mn.y = min(g_mn.y, gp.y)
					g_mx.x = max(g_mx.x, gp.x); g_mx.y = max(g_mx.y, gp.y)
			return Rect2(g_mn, g_mx - g_mn)

	# Grupo: caja combinada de los hijos Node2D (recursivo). Cualquier figura con
	# geometría propia ya salió por una rama anterior, así que aquí solo caen
	# contenedores reales.
	if node.get_child_count() > 0:
		var acc: Rect2 = Rect2()
		var got := false
		for ch in node.get_children():
			if ch is Node2D:
				var cr: Rect2 = _global_rect(ch)
				if cr.size == Vector2.ZERO:
					continue
				acc = cr if not got else acc.merge(cr)
				got = true
		if got:
			return acc

	return Rect2(node.global_position - Vector2(20, 20), Vector2(40, 40))

func _get_macro_rect() -> Rect2:
	if selected_shapes.size() == 0: return Rect2()
	var valid_first_rect = false
	var r: Rect2 = Rect2()

	for shape in selected_shapes:
		if is_instance_valid(shape):
			if not valid_first_rect:
				r = _global_rect(shape)
				valid_first_rect = true
			else:
				r = r.merge(_global_rect(shape))
	return r

# ── Snapshot Riguroso de Estructuras Complejas ────────────────────────────────

## Reescribe doc_position (doble precisión) desde la posición nativa (float32)
## tras cualquier escritura directa a shape.global_position en este archivo.
## No toca doc_rotation — cada punto de llamada que cambia rotación decide
## explícitamente si usa set_doc_rotation() (precisión doble real) o debe
## re-sincronizar desde el nativo (ver _apply_rotation/_cancel_key_transform).
func _sync_doc_position_from_native(shape: Node2D) -> void:
	if shape is VectorShape:
		shape.doc_position = DVec2.from_v2(shape.position)

func _get_shape_stroke_width(shape: Node2D) -> float:
	if not is_instance_valid(shape):
		return 1.0
	if "stroke_width" in shape:
		return float(shape.stroke_width)
	if shape is Line2D:
		return float(shape.width)
	if shape.has_meta("stroke_width"):
		return float(shape.get_meta("stroke_width"))
	return 1.0

func _set_shape_stroke_width(shape: Node2D, w: float) -> void:
	if not is_instance_valid(shape):
		return
	if "stroke_width" in shape:
		shape.stroke_width = w
	elif shape is Line2D:
		shape.width = w
	if shape.has_meta("stroke_width"):
		shape.set_meta("stroke_width", w)
	var stroke_line = shape.get_node_or_null("Contorno_Stroke")
	if stroke_line is Line2D:
		stroke_line.width = w
	if shape.has_method("queue_redraw"):
		shape.queue_redraw()

func _snapshot(shape: Node2D) -> Dictionary:
	var snap: Dictionary = {
		"gpos": shape.global_position,
		"grot": shape.global_rotation,
		"stroke_width": _get_shape_stroke_width(shape),
		# Estado NO-geométrico (visibilidad / bloqueo / recorte / z-order). Aditivo:
		# así un undo de transform que ADEMÁS tocó estas props las restaura, y el
		# cancelar (Escape) devuelve el estado completo. Ver NodeState.
		"_ns": NodeState.capture(shape),
	}
	if "stroke_sides" in shape:
		snap["stroke_sides"] = shape.stroke_sides

	# Captura en doble precisión para figuras VectorShape (Rectángulo/Círculo/
	# Polígono). No sustituye la captura "gpos"/"grot" de arriba (se sigue
	# usando para el resto de ramas/figuras), solo añade la fuente exacta que
	# usan las nuevas rutas de traslación/resize/rotación más abajo.
	if shape is VectorShape:
		snap["doc_pos"] = shape.get_doc_position()
		snap["doc_rot"] = shape.get_doc_rotation()
		if shape.has_doc_extent():
			snap["doc_extent"] = shape.get_doc_extent()

	if shape.has_meta("shape_type") and (shape.get_meta("shape_type") in ["text_paragraph", "text_title"]):
		snap["w"] = shape.get_meta("width") if shape.has_meta("width") else 350.0
		snap["h"] = shape.get_meta("height") if shape.has_meta("height") else 65.0
		var cur_fs: int = 16
		if shape.has_meta("font_size"):
			cur_fs = int(shape.get_meta("font_size"))
		else:
			var lbl = shape.get_node_or_null("DisplayLabel")
			if lbl and "font_size" in lbl:
				cur_fs = int(lbl.font_size)
		snap["font_size"] = cur_fs
		# Runs (formato por letra) para escalar con Ctrl SIN aplanarlos y para
		# que el undo los restaure.
		snap["runs"] = (shape.get_meta("runs", []) as Array).duplicate(true)
		return snap
	
	if shape is Path2D:
		var curve: Curve2D = shape.curve
		var nodes_data = []
		for i in range(curve.point_count):
			var n_pos = curve.get_point_position(i)
			nodes_data.append({
				"node": shape.to_global(n_pos),
				"in": shape.to_global(n_pos + curve.get_point_in(i)),
				"out": shape.to_global(n_pos + curve.get_point_out(i))
			})
		snap["g_path_nodes"] = nodes_data
	
	elif shape is Polygon2D:
		var g_poly = PackedVector2Array()
		for p in shape.polygon:
			g_poly.append(shape.to_global(p))
		snap["g_poly_pts"] = g_poly
		
		var stroke = shape.get_node_or_null("Contorno_Stroke")
		if stroke is Line2D:
			var g_stroke = PackedVector2Array()
			for p in stroke.points:
				g_stroke.append(stroke.to_global(p))
			snap["g_stroke_pts"] = g_stroke
	
	elif "size" in shape and (shape is VectorRectangle or shape is VectorCircle or shape.has_method("rotate_orbit")):
		snap["size"] = shape.get("size")

	elif "vertices" in shape:
		var verts: PackedVector2Array = shape.get("vertices")
		var g_verts = PackedVector2Array()
		for v in verts:
			g_verts.append(shape.to_global(v))
		snap["g_verts"] = g_verts

	elif "width" in shape and "height" in shape:
		snap["w"] = shape.get("width")
		snap["h"] = shape.get("height")
		
	elif shape is Line2D:
		var g_pts = PackedVector2Array()
		for p in shape.points:
			g_pts.append(shape.to_global(p))
		snap["g_pts"] = g_pts

	elif shape is Sprite2D:
		snap["scale"] = shape.scale

	return snap

func _refresh_artboard() -> void:
	var mgr := ArtboardManager.find(get_tree()) if is_inside_tree() else null
	if mgr:
		var act := mgr.get_active_artboard()
		if is_instance_valid(act):
			target_artboard = act
			return
	var container: Node = canvas.get_node_or_null("ArtboardsContainer") if is_instance_valid(canvas) else null
	if container:
		for c in container.get_children():
			if c is ArtboardEditor or "artboard_size" in c:
				target_artboard = c
				return
	target_artboard = null

# ── Detección de Handles Basada en Tolerancia de Zoom ────────────────────────

func _handle_at(macro: Rect2, gm: Vector2) -> String:
	var transform_scale: float = canvas.global_transform.get_scale().x
	if transform_scale <= 0.001: transform_scale = 1.0

	var t: float = CLICK_TOLERANCE / transform_scale
	var r_zone: float = ROTATE_ZONE / transform_scale
	var stalk: float = STALK_LENGTH / transform_scale

	var center: Vector2 = macro.get_center()
	var cx: float = center.x
	var cy: float = center.y

	var pt_tl: Vector2 = macro.position
	var pt_tr: Vector2 = Vector2(macro.end.x, macro.position.y)
	var pt_bl: Vector2 = Vector2(macro.position.x, macro.end.y)
	var pt_br: Vector2 = macro.end
	var pt_tc: Vector2 = Vector2(cx, macro.position.y)
	var pt_bc: Vector2 = Vector2(cx, macro.end.y)
	var pt_lc: Vector2 = Vector2(macro.position.x, cy)
	var pt_rc: Vector2 = Vector2(macro.end.x, cy)
	var pt_rot: Vector2 = Vector2(cx, macro.position.y - stalk)

	if gm.distance_to(pt_rot) <= t: return "rot_handle"

	if gm.distance_to(pt_tl) <= r_zone and gm.distance_to(pt_tl) > t: return "rot_tl"
	if gm.distance_to(pt_tr) <= r_zone and gm.distance_to(pt_tr) > t: return "rot_tr"
	if gm.distance_to(pt_bl) <= r_zone and gm.distance_to(pt_bl) > t: return "rot_bl"
	if gm.distance_to(pt_br) <= r_zone and gm.distance_to(pt_br) > t: return "rot_br"

	if gm.distance_to(pt_tl) <= t: return "tl"
	if gm.distance_to(pt_tr) <= t: return "tr"
	if gm.distance_to(pt_bl) <= t: return "bl"
	if gm.distance_to(pt_br) <= t: return "br"
	if gm.distance_to(pt_tc) <= t: return "tc"
	if gm.distance_to(pt_bc) <= t: return "bc"
	if gm.distance_to(pt_lc) <= t: return "lc"
	if gm.distance_to(pt_rc) <= t: return "rc"

	return ""

func _set_cursor(h: String) -> void:
	if is_gradient_mode and h == "":
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
		return

	if not SmartCursor:
		# Fallback al sistema tradicional si SmartCursor no está disponible
		if h.begins_with("rot"):
			Input.set_default_cursor_shape(Input.CURSOR_CROSS)
			return

		match h:
			"tl", "br": Input.set_default_cursor_shape(Input.CURSOR_FDIAGSIZE)
			"tr", "bl": Input.set_default_cursor_shape(Input.CURSOR_BDIAGSIZE)
			"lc", "rc": Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
			"tc", "bc": Input.set_default_cursor_shape(Input.CURSOR_VSIZE)
			_: Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	
	# Usar SmartCursor para manejar los estados
	if h.begins_with("rot"):
		SmartCursor.set_state(CursorStateMachine.CursorState.PRECISION)
		return

	match h:
		"tl", "br": 
			SmartCursor.set_state(CursorStateMachine.CursorState.PRECISION)
		"tr", "bl":
			SmartCursor.set_state(CursorStateMachine.CursorState.PRECISION)
		"lc", "rc":
			SmartCursor.set_state(CursorStateMachine.CursorState.PRECISION)
		"tc", "bc":
			SmartCursor.set_state(CursorStateMachine.CursorState.PRECISION)
		_:
			if selected_shapes.size() > 0:
				SmartCursor.set_state(CursorStateMachine.CursorState.ACTIVE)
			else:
				SmartCursor.set_state(CursorStateMachine.CursorState.NEUTRAL)

func _notificar_cambio_al_overlay() -> void:
	if is_instance_valid(canvas) and "artboards_container" in canvas and is_instance_valid(canvas.artboards_container):
		if canvas.artboards_container.has_method("set_active_tool"):
			canvas.artboards_container.set_active_tool("movetool", self)

func _notificar_limpieza_al_overlay() -> void:
	if is_instance_valid(canvas) and "artboards_container" in canvas and is_instance_valid(canvas.artboards_container):
		if canvas.artboards_container.has_method("set_active_tool"):
			canvas.artboards_container.set_active_tool("other", null)

func _update_macro_rect() -> void:
	if selected_shapes.is_empty():
		transform_macro_rect = Rect2()
		initial_macro_center = Vector2.ZERO
		if _bounding_box:
			_update_bounding_box()
		return

	transform_macro_rect = _get_macro_rect()
	initial_macro_center = transform_macro_rect.get_center()
	
	# Actualizar bounding box
	if _bounding_box:
		_update_bounding_box()

# ==========================================
# POOLING DE OBJETOS
# ==========================================

func _acquire_bounding_box() -> void:
	"""
	Obtiene un bounding box del pool de objetos.
	"""
	if _bounding_box:
		return  # Ya tenemos uno

	if not ObjectPool:
		push_error("MoveTool: ObjectPool no disponible")
		return

	_bounding_box = ObjectPool.acquire("BoundingBox")
	if _bounding_box:
		# Configurar el bounding box
		if "set_target" in _bounding_box:
			_bounding_box.set_target(null)
		if "move_tool_reference" in _bounding_box:
			_bounding_box.move_tool_reference = self
		
		# Reparentear al canvas (el objeto está en Pool_BoundingBox)
		if is_instance_valid(canvas):
			_bounding_box.reparent(canvas)
			
		# Actualizar posición
		_update_bounding_box()
	else:
		push_warning("MoveTool: No se pudo obtener bounding box del pool")


func _release_bounding_box() -> void:
	"""
	Devuelve el bounding box al pool de objetos.
	"""
	if not _bounding_box:
		return
	
	if ObjectPool:
		ObjectPool.release("BoundingBox", _bounding_box)
		_bounding_box = null
	else:
		# Si no hay pool, destruir manualmente
		if is_instance_valid(_bounding_box):
			_bounding_box.queue_free()
		_bounding_box = null


func _update_bounding_box() -> void:
	"""
	Actualiza la posición y tamaño del bounding box.
	"""
	if not _bounding_box or not is_instance_valid(_bounding_box):
		return
	
	if selected_shapes.size() == 0:
		if "hide" in _bounding_box:
			_bounding_box.hide()
		return
	
	# Actualizar el bounding box
	if "_sincronizar_dimensiones_en_canvas" in _bounding_box:
		_bounding_box._sincronizar_dimensiones_en_canvas()
