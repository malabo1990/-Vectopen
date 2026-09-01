# =============================================================================
# RUTA: res://script_gdscript/MoveTool.gd
# Vectopen — Selección y transformación general de figuras (estilo profesional + Key)
# Versión Pro Avanzada con soporte geométrico de precisión para vectores y texto.
# Migrado de `Tool` (RefCounted) a `ToolBase` (Node) el 19/08/2026 — última de
# las 8 herramientas del informe §1.1/§1.5. Construir con `canvas._new_tool(script)`
# (o `MoveTool.new()` + `tool.canvas = ...`), NO con `MoveTool.new(canvas)`.
# =============================================================================
class_name MoveTool
extends ToolBase

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

# ── Estado de arrastre de objetos ─────────────────────────────────────────────
var is_dragging_shape: bool = false
## "" | "x" | "y" — cuando el usuario arrastra un handle de eje del bounding box,
## el movimiento se restringe a ese eje.
var _axis_move: String = ""

# ── Estado de transformación avanzada ─────────────────────────────────────────
var is_resizing: bool = false
var is_rotating: bool = false
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

# ── Modos de transformación por teclado ────────────────────────────────────
enum KeyMode { NONE, TRANSLATE, SCALE, ROTATE }
var current_key_mode: KeyMode = KeyMode.NONE

enum AxisLock { NONE, X, Y }
var current_axis: AxisLock = AxisLock.NONE

# ── Constantes visuales profesionales ─────────────────────────────────────────
const HANDLE_SIZE: float = 8.0
const CLICK_TOLERANCE: float = 12.0
const ROTATE_ZONE: float = 18.0
const STALK_LENGTH: float = 24.0 
const MIN_LINE_PAD: float = 6.0

# Colores de alta fidelidad (estilo profesional)
const COLOR_BBOX: Color = Color(0.05, 0.55, 0.91, 1.0)        # azul de acento
const COLOR_HANDLE_F: Color = Color(1.0, 1.0, 1.0, 1.0)      # Fondo tiradores
const COLOR_MARQUEE_F: Color = Color(0.05, 0.55, 0.91, 0.07)  # Relleno marquee
const COLOR_MARQUEE_S: Color = Color(0.05, 0.55, 0.91, 0.60)  # Contorno marquee

# ── Métodos del Ciclo de Vida ────────────────────────────────────────────────

func get_class_name() -> String:
	return "MoveTool"

func activate() -> void:
	# Actualizar estado del cursor inteligente
	if SmartCursor:
		SmartCursor.set_state(CursorStateMachine.CursorState.ACTIVE)
	
	_clear_key_transform()
	_notificar_cambio_al_overlay()
	_acquire_bounding_box()
	# Reflejar en el bounding box la selección que ya viva en SelectionManager
	# (p. ej. hecha desde el panel de capas con otra herramienta activa).
	if SelectionManager and not _sel_conn:
		SelectionManager.changed.connect(_on_external_selection_changed)
		_sel_conn = true
	_update_macro_rect()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

	var _dc := get_node_or_null("/root/DebugConsola")
	if _dc and _dc.has_method("registrar_movetool"):
		_dc.registrar_movetool(self)
		if is_instance_valid(_bounding_box) and _dc.has_method("registrar_bbox"):
			_dc.registrar_bbox(_bounding_box)

## Red de seguridad: si un gesto (arrastre/resize/rotación/marquee) se quedó
## "abierto" porque la SUELTA del ratón no llegó a `handle_input` (la comió un
## Control que se movió bajo el cursor — típico del gizmo del bounding box),
## lo cerramos aquí cada frame. Sin esto, `is_dragging_shape` atascado hace que
## `_on_motion` consuma TODO evento y bloquea el editor entero.
func _process(_delta: float) -> void:
	_heal_stuck_gesture()

func deactivate() -> void:
	if SelectionManager and _sel_conn:
		SelectionManager.changed.disconnect(_on_external_selection_changed)
		_sel_conn = false
	_clear_selection()
	_clear_key_transform()
	is_dragging_shape = false
	is_resizing = false
	is_rotating = false
	is_marquee = false
	is_dragging_artboard = false
	is_resizing_artboard = false
	_release_bounding_box()
	_notificar_limpieza_al_overlay()
	
	# Restaurar estado del cursor
	if SmartCursor:
		SmartCursor.set_state(CursorStateMachine.CursorState.NEUTRAL)
	
	if is_instance_valid(canvas):
		canvas.queue_redraw()

# ── Entrada Principal ──────────────────────────────────────────────────────────

func handle_input(event: InputEvent) -> bool:
	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false

	_refresh_artboard()
	if not target_artboard:
		return false

	var gm: Vector2 = canvas.get_global_mouse_position()

	# Atajos de Teclado por teclado (G, S, R, X, Y, ESC)
	if event is InputEventKey and event.pressed:
		if _handle_key_shortcuts(event.keycode):
			return true

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if current_key_mode != KeyMode.NONE:
				_confirm_key_transform()
				return true
				
			if event.double_click:
				return _on_double_click(gm)
			return _on_press(gm)
		else:
			return _on_release(gm)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if current_key_mode != KeyMode.NONE:
			_cancel_key_transform()
			return true

	if event is InputEventMouseMotion:
		return _on_motion(gm)

	return false

# ── LÓGICA DE ATAJO POR TECLADO (G, S, R, X, Y) ──────────────────────────────────

func _handle_key_shortcuts(keycode: int) -> bool:
	var focus_owner = canvas.get_viewport().gui_get_focus_owner()
	if focus_owner is TextEdit or focus_owner is LineEdit:
		return false

	if selected_shapes.size() == 0:
		return false

	match keycode:
		KEY_G:
			_start_key_mode(KeyMode.TRANSLATE)
			return true
		KEY_S:
			_start_key_mode(KeyMode.SCALE)
			return true
		KEY_R:
			_start_key_mode(KeyMode.ROTATE)
			return true
		KEY_X:
			if current_key_mode != KeyMode.NONE:
				current_axis = AxisLock.X if current_axis != AxisLock.X else AxisLock.NONE
				canvas.queue_redraw()
				return true
		KEY_Y:
			if current_key_mode != KeyMode.NONE:
				current_axis = AxisLock.Y if current_axis != AxisLock.Y else AxisLock.NONE
				canvas.queue_redraw()
				return true
		KEY_ESCAPE:
			if current_key_mode != KeyMode.NONE:
				_cancel_key_transform()
				return true
	return false

func _start_key_mode(mode: KeyMode) -> void:
	current_key_mode = mode
	current_axis = AxisLock.NONE
	transform_initial_mouse = canvas.get_global_mouse_position()
	transform_macro_rect = _get_macro_rect()
	initial_macro_center = transform_macro_rect.get_center()
	transform_initial_states.clear()

	for shape in selected_shapes:
		if is_instance_valid(shape):
			transform_initial_states[shape] = _snapshot(shape)

func _confirm_key_transform() -> void:
	# G / S / R (modo por teclado) también son transformaciones reales → undo.
	var accion := "Transformar"
	match current_key_mode:
		KeyMode.TRANSLATE: accion = "Mover selección"
		KeyMode.SCALE: accion = "Redimensionar"
		KeyMode.ROTATE: accion = "Rotar"
	if not selected_shapes.is_empty():
		_commit_transform(accion, selected_shapes.duplicate(),
			current_key_mode != KeyMode.TRANSLATE)
	transform_initial_states.clear()
	_clear_key_transform()

func _cancel_key_transform() -> void:
	# Restaura el estado COMPLETO (posición/rotación/tamaño/vértices/…), no solo
	# posición+rotación+texto como antes — cancelar un escalado dejaba la figura
	# a medio transformar.
	for shape in selected_shapes:
		if is_instance_valid(shape) and transform_initial_states.has(shape):
			_restore_transform(shape, transform_initial_states[shape])
	_clear_key_transform()
	_update_bounding_box()
	canvas.queue_redraw()

func _clear_key_transform() -> void:
	current_key_mode = KeyMode.NONE
	current_axis = AxisLock.NONE

# ── LÓGICA DE DOBLE CLIC ──────────────────────────────────────────────────────

func _on_double_click(gm: Vector2) -> bool:
	var hit: Node2D = _shape_at(gm)
	# Usamos is_instance_valid para mayor seguridad de memoria en Godot 4
	if not is_instance_valid(hit) or not canvas.has_method("change_tool"): 
		return false
	
	if hit.has_meta("shape_type"):
		var type = hit.get_meta("shape_type")
		
		# 1. BLINDAJE PARA PÁRRAFOS DE TEXTO
		if type == "text_paragraph":
			_clear_selection()
			var script_para = load("res://script_gdscript/tools/ParagraphTool.gd")
			if script_para == null:
				push_error("Vectopen Error: No se pudo cargar 'ParagraphTool.gd'. Revisa su sintaxis interna o ruta.")
				return false
				
			var para_tool = canvas._new_tool(script_para)
			canvas.change_tool(para_tool)
			
			var local_pos = target_artboard.to_local(gm)
			para_tool._check_and_trigger_edit_at(local_pos)
			return true
			
		# 2. BLINDAJE PARA TÍTULOS DE TEXTO
		elif type == "text_title":
			_clear_selection()
			var script_text = load("res://script_gdscript/tools/TextTool.gd")
			if script_text == null:
				push_error("Vectopen Error: No se pudo cargar 'TextTool.gd'. Revisa su sintaxis interna o ruta.")
				return false
				
			var title_tool = canvas._new_tool(script_text)
			canvas.change_tool(title_tool)
			
			if title_tool.has_method("_check_and_trigger_edit_at"):
				var local_pos = target_artboard.to_local(gm)
				title_tool._check_and_trigger_edit_at(local_pos)
			return true
			
	# 3. BLINDAJE PARA EDICIÓN DE NODOS COLES (VECTORES Y CURVAS BEZIER)
	if hit is Path2D or hit is Line2D or hit is Polygon2D or hit.has_meta("curve") or hit.name.contains("Bezier"):
		_clear_selection()
		var script_nodes = load("res://script_gdscript/tools/NodeSelectionTool.gd")
		if script_nodes == null:
			push_error("Vectopen Error: No se pudo cargar 'NodeSelectionTool.gd'. Revisa su sintaxis interna o ruta.")
			return false
			
		var herramienta_nodos = canvas._new_tool(script_nodes)
		if hit is Path2D:
			herramienta_nodos.edit_path = hit
		else:
			var parent = hit.get_parent()
			if parent is Path2D:
				herramienta_nodos.edit_path = parent
				
		canvas.change_tool(herramienta_nodos)
		return true

	# 4. ENTRAR A LA FIGURA HIJA bajo el cursor (estilo Affinity):
	#    - doble clic normal  → baja UN nivel (salta, salta, salta…)
	#    - Alt + doble clic    → salta DIRECTO a la figura más profunda que hay
	#                            bajo el ratón (atajo "ir directo al elemento")
	#    Sin límite de profundidad. Un clic sencillo sigue seleccionando el
	#    contenedor de primer nivel.
	if Input.is_key_pressed(KEY_ALT):
		if _entrar_hasta_hoja(gm):
			return true
	elif _entrar_en_hijo(gm):
		return true

	return false

## Alt+doble clic: selecciona directamente la figura MÁS PROFUNDA bajo `gm`
## (sin ir nivel a nivel). Devuelve true si seleccionó algo por debajo del
## contenedor de primer nivel.
func _entrar_hasta_hoja(gm: Vector2) -> bool:
	var top: Node2D = _shape_at(gm)
	if not is_instance_valid(top):
		return false
	var actual: Node2D = top
	while true:
		var h: Node2D = _hijo_bajo_punto(actual, gm)
		if not is_instance_valid(h) or h == actual:
			break
		actual = h
	if actual == top:
		return false
	_clear_selection()
	_select(actual)
	_update_bounding_box()
	if is_instance_valid(canvas):
		canvas.queue_redraw()
	return true

## Selecciona el hijo directo (del nodo ya seleccionado en esta rama, o del
## contenedor de primer nivel) cuyo cuerpo/rama contiene `gm`. Devuelve true si
## de verdad bajó un nivel.
func _entrar_en_hijo(gm: Vector2) -> bool:
	var top: Node2D = _shape_at(gm)
	if not is_instance_valid(top) or not _es_grupo_movetool(top):
		return false
	var actual: Node = top
	for s in selected_shapes:
		if is_instance_valid(s) and (s == top or _es_ancestro(top, s)):
			actual = s
			break
	var siguiente: Node2D = _hijo_bajo_punto(actual, gm)
	if not is_instance_valid(siguiente) or siguiente == actual:
		return false
	_clear_selection()
	_select(siguiente)
	_update_bounding_box()
	if is_instance_valid(canvas):
		canvas.queue_redraw()
	return true

## Hijo DIRECTO de `padre` (arriba→abajo en Z) cuyo cuerpo o rama contiene `gm`.
func _hijo_bajo_punto(padre: Node, gm: Vector2) -> Node2D:
	if not is_instance_valid(padre):
		return null
	for i in range(padre.get_child_count() - 1, -1, -1):
		var c = padre.get_child(i)
		if not (c is Node2D) or String(c.name) == "Contorno_Stroke":
			continue
		if _es_grupo_movetool(c):
			if _rama_contiene_punto(c, gm):
				return c
		elif _global_rect(c).has_point(gm):
			return c
	return null

## ¿`posible_ancestro` está por encima de `nodo` en el árbol?
func _es_ancestro(posible_ancestro: Node, nodo: Node) -> bool:
	var a: Node = nodo.get_parent() if is_instance_valid(nodo) else null
	while a != null:
		if a == posible_ancestro:
			return true
		a = a.get_parent()
	return false

# ── Press ──────────────────────────────────────────────────────────────────────

func _on_press(gm: Vector2) -> bool:
	# El artboard sobre el que se pulsa (multi-artboard). Si el clic cae fuera
	# de todos, seguimos con el activo para el marquee de "espacio vacío".
	var mgr := ArtboardManager.find(get_tree()) if get_tree() else null
	var clicked_ab: Node2D = mgr.artboard_at_point(gm) if mgr else null
	if is_instance_valid(clicked_ab):
		target_artboard = clicked_ab
		if mgr and mgr.active_artboard != clicked_ab and _shape_at(gm) == null:
			# clic en el cuerpo de OTRO artboard → activarlo
			mgr.set_active_artboard(clicked_ab)

	var ab_local: Vector2 = target_artboard.to_local(gm)
	var ab_rect: Rect2 = Rect2(Vector2.ZERO, target_artboard.artboard_size)

	if target_artboard.is_selected and target_artboard.is_on_handle(ab_local):
		var edge: Vector2 = target_artboard.get_resize_edge(ab_local)
		if edge != Vector2.ZERO:
			is_resizing_artboard = true
			artboard_resize_edge = edge
			return true

	# NOTA: El inicio de resize/rotate ya no se detecta aquí por hit-testing manual.
	# Lo dispara boundingbox.gd al pulsar uno de sus handles reales, vía start_handle_transform().

	var hit: Node2D = _shape_at(gm)
	if hit:
		# `_shape_at` devuelve el GRUPO de primer nivel. Pero si ya hay una
		# figura seleccionada DENTRO de esa rama (elegida en el panel de capas),
		# se arrastra esa figura — sin cambiar la selección al grupo. Antes el
		# clic en el relleno de un hijo lo deseleccionaba.
		if _es_grupo_movetool(hit):
			var sel_dentro := _primer_seleccionado_en_rama(hit)
			if sel_dentro != null:
				hit = sel_dentro
		if selected_shapes.has(hit):
			if Input.is_key_pressed(KEY_SHIFT):
				_deselect(hit)
				return true
		else:
			if not Input.is_key_pressed(KEY_SHIFT):
				_clear_selection()
			_select(hit)

		is_dragging_shape = true
		transform_initial_mouse = gm
		transform_initial_states.clear()
		
		for s in selected_shapes:
			if is_instance_valid(s):
				transform_initial_states[s] = _snapshot(s)
		
		canvas.queue_redraw()
		return true

	if ab_rect.has_point(ab_local) and target_artboard.is_selected:
		_force_text_loss_focus()
		_clear_selection()
		is_dragging_artboard = true
		artboard_drag_start_mouse = gm
		artboard_drag_start_pos = target_artboard.global_position
		return true

	# Clic en espacio vacío, tanto dentro como fuera del artboard, inicia marquee.
	# Antes, un clic en vacío DENTRO del artboard (con este no seleccionado)
	# entraba al "if ab_rect.has_point(...)" de arriba, hacía _clear_selection()
	# y devolvía false sin nunca activar is_marquee — por eso el drag-select
	# solo funcionaba fuera del artboard. Encontrado el 19/08/2026 a partir del
	# reporte del usuario ("fuera de artboard funciona, dentro no").
	_force_text_loss_focus()
	# Shift/Alt mantienen la selección actual para sumar o restar con el marquee;
	# sin modificador, el marquee reemplaza la selección como antes.
	if not Input.is_key_pressed(KEY_SHIFT) and not Input.is_key_pressed(KEY_ALT):
		_clear_selection()
	is_marquee = true
	marquee_start = gm
	marquee_end = gm
	canvas.queue_redraw()
	return true

# ── Release ────────────────────────────────────────────────────────────────────

func _on_release(_gm: Vector2) -> bool:
	if is_marquee:
		is_marquee = false
		_apply_marquee()

	# GlobalEvents.object_transformed existía en la señal pero nada la
	# emitía nunca — LayerSystem la usa para refrescar el indicador de
	# "fuera del artboard" tras soltar un arrastre, y bounding_box.gd ya
	# tenía un listener muerto para ella. Solo se dispara si de verdad hubo
	# una transformación real (no en un simple clic o un marquee vacío).
	var shape_transform: bool = is_dragging_shape or is_resizing or is_rotating
	var hubo_transformacion: bool = shape_transform or is_dragging_artboard or is_resizing_artboard

	# CUALQUIER transformación de figuras (mover / redimensionar / rotar / eje)
	# registra UNA acción de undo con el estado completo antes/después + el
	# cambio de padre (mover libre reparenta al artboard bajo la figura; resize/
	# rotar no). Antes solo nudge/borrar/duplicar/pegar tenían undo real — un
	# resize o una rotación con el ratón NO se podían deshacer.
	if shape_transform and not selected_shapes.is_empty():
		var _accion := "Mover selección"
		if is_resizing: _accion = "Redimensionar"
		elif is_rotating: _accion = "Rotar"
		elif _axis_move != "": _accion = "Mover en eje"
		_commit_transform(_accion, selected_shapes.duplicate(), is_resizing or is_rotating)

	is_dragging_shape = false
	is_resizing = false
	is_rotating = false
	is_dragging_artboard = false
	is_resizing_artboard = false
	resize_handle = ""
	_axis_move = ""
	live_rot_angle = 0.0
	live_scale = Vector2.ONE
	artboard_resize_edge = Vector2.ZERO
	transform_initial_states.clear()

	if hubo_transformacion and GlobalEvents:
		GlobalEvents.emit_safe("object_transformed")

	canvas.queue_redraw()
	return true


## Registra (y aplica) UNA acción de undo para una transformación de figuras.
## Captura el estado COMPLETO antes (de transform_initial_states) y después
## (_snapshot fresco) de cada figura + el cambio de padre. `solo_transform`
## true en resize/rotar → no se reparenta (la figura no "se mueve" de artboard).
func _commit_transform(action_name: String, nodes: Array, solo_transform: bool) -> void:
	var mgr := ArtboardManager.find(get_tree()) if get_tree() else null
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
			var hit_ab := mgr.artboard_at_point(n.global_position)
			if hit_ab != owner_ab:
				new_parent = hit_ab if hit_ab != null else container
		if _snap_equal(before, after) and new_parent == old_parent:
			continue
		recs.append({
			"n": n, "before": before, "after": after,
			"op": old_parent, "oi": n.get_index(), "np": new_parent,
		})
	if recs.is_empty():
		return
	HistoryManager.register_action(action_name)
	HistoryManager.add_do(_do_apply_transform.bind(recs, false))
	HistoryManager.add_undo(_do_apply_transform.bind(recs, true))
	HistoryManager.commit()
	_do_apply_transform(recs, false)


func _do_apply_transform(recs: Array, undo: bool) -> void:
	for r in recs:
		var n: Node2D = r["n"]
		if not is_instance_valid(n):
			continue
		var parent: Node = r["op"] if undo else r["np"]
		if is_instance_valid(parent) and n.get_parent() != parent:
			n.reparent(parent, true)
			if undo:
				parent.move_child(n, mini(int(r["oi"]), parent.get_child_count() - 1))
		_restore_transform(n, r["before"] if undo else r["after"])
	_update_bounding_box()
	if is_instance_valid(canvas):
		canvas.queue_redraw()
	if GlobalEvents:
		GlobalEvents.emit_safe("object_transformed")


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
		_update_text_node_sizes(shape, snap["w"], snap.get("h", 80.0))
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
	_sync_doc_position_from_native(shape)
	if shape.has_method("queue_redraw"):
		shape.queue_redraw()

# ── Motion ─────────────────────────────────────────────────────────────────────

## Autocuración de estado de arrastre atascado. `bounding_box._on_drag_panel_gui_input`
## pone `is_dragging_shape = true` al pulsar sobre el interior del gizmo; si el
## panel se aleja bajo el cursor (persigue a la figura) la SUELTA nunca llega a
## ese `gui_input` y `is_dragging_shape` se queda en `true` para siempre → cada
## motion arrastra la selección y NADA más responde (ni panel de capas ni
## arrastre de artboard). Si el botón izquierdo NO está pulsado de verdad,
## cancelamos cualquier gesto en curso. Barato (una llamada nativa por evento).
func _heal_stuck_gesture() -> void:
	if not (is_dragging_shape or is_marquee or is_dragging_artboard \
			or is_resizing_artboard or is_resizing or is_rotating):
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	# El ratón no está pulsado pero seguimos "en gesto" → estado zombi. Cerramos.
	is_dragging_shape = false
	is_marquee = false
	is_dragging_artboard = false
	is_resizing_artboard = false
	is_resizing = false
	is_rotating = false
	resize_handle = ""
	_axis_move = ""
	artboard_resize_edge = Vector2.ZERO
	transform_initial_states.clear()
	if is_instance_valid(_bounding_box) and "_is_dragging_canvas_area" in _bounding_box:
		_bounding_box._is_dragging_canvas_area = false
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _on_motion(gm: Vector2) -> bool:
	if is_marquee:
		marquee_end = gm
		canvas.queue_redraw()
		return true

	if current_key_mode != KeyMode.NONE and selected_shapes.size() > 0:
		_process_key_motion(gm)
		return true

	# Detectar elementos interactivos
	var interactive_element = false
	if selected_shapes.size() > 0 and not is_resizing and not is_rotating and not is_dragging_shape:
		var macro: Rect2 = _get_macro_rect()
		var h: String = _handle_at(macro, gm)
		_set_cursor(h)
		
		# Detectar si el cursor está sobre un handle
		interactive_element = h != ""
	
	# Actualizar estado del cursor inteligente
	if SmartCursor:
		if interactive_element:
			SmartCursor.set_interactive_element(true)
		else:
			SmartCursor.set_interactive_element(false)
			
			# Cambiar estado según el modo actual
			if is_resizing or is_rotating:
				SmartCursor.set_state(CursorStateMachine.CursorState.PRECISION)
			elif selected_shapes.size() > 0:
				SmartCursor.set_state(CursorStateMachine.CursorState.ACTIVE)
			else:
				SmartCursor.set_state(CursorStateMachine.CursorState.NEUTRAL)

	if is_resizing and selected_shapes.size() > 0:
		_apply_resize(gm)
		_update_bounding_box()
		canvas.queue_redraw()
		return true

	if is_rotating and selected_shapes.size() > 0:
		_apply_rotation(gm)
		_update_bounding_box()
		canvas.queue_redraw()
		return true

	if is_dragging_shape:
		var delta: Vector2 = gm - transform_initial_mouse
		# Handles de eje del bounding box: mover SOLO en horizontal / vertical.
		if _axis_move == "x":
			delta.y = 0.0
		elif _axis_move == "y":
			delta.x = 0.0
		elif Input.is_key_pressed(KEY_SHIFT):
			if abs(delta.x) > abs(delta.y):
				delta.y = 0.0
			else:
				delta.x = 0.0

		for s in selected_shapes:
			if is_instance_valid(s) and transform_initial_states.has(s):
				var snap: Dictionary = transform_initial_states[s]
				var _skip = null
				var new_pos: Vector2 = snap["gpos"] + delta
				var st := Engine.get_main_loop() as SceneTree
				if st:
					var sm := st.root.get_node_or_null("SnapManager")
					if sm and sm.has_method("snap_position"):
						new_pos = sm.snap_position(new_pos)
				s.global_position = new_pos
				_sync_doc_position_from_native(s)
		_update_bounding_box()  # el bounding box debe seguir a las figuras mientras se arrastran
		canvas.queue_redraw()
		return true

	if is_resizing_artboard and is_instance_valid(target_artboard):
		target_artboard.call("_apply_resize", artboard_resize_edge, gm)
		return true

	if is_dragging_artboard and is_instance_valid(target_artboard):
		target_artboard.global_position = artboard_drag_start_pos + (gm - artboard_drag_start_mouse)
		return true

	return false

func _process_key_motion(gm: Vector2) -> void:
	var delta: Vector2 = gm - transform_initial_mouse
	match current_key_mode:
		KeyMode.TRANSLATE:
			if current_axis == AxisLock.X:
				delta.y = 0.0
			elif current_axis == AxisLock.Y:
				delta.x = 0.0
			for s in selected_shapes:
				if is_instance_valid(s) and transform_initial_states.has(s):
					var new_pos: Vector2 = transform_initial_states[s]["gpos"] + delta
					var st := Engine.get_main_loop() as SceneTree
					if st:
						var sm := st.root.get_node_or_null("SnapManager")
						if sm and sm.has_method("snap_position"):
							new_pos = sm.snap_position(new_pos)
					s.global_position = new_pos
					_sync_doc_position_from_native(s)
			var factor_x: float = 1.0 + (delta.x / 200.0)
			var factor_y: float = 1.0 + (delta.y / 200.0)
			for s in selected_shapes:
				if is_instance_valid(s) and transform_initial_states.has(s):
					var snap = transform_initial_states[s]
					if s.has_meta("shape_type"):
						var nw = max(40.0, snap["w"] * (factor_x if current_axis != AxisLock.Y else 1.0))
						var nh = max(20.0, snap["h"] * (factor_y if current_axis != AxisLock.X else 1.0))
						s.set_meta("width", nw)
						s.set_meta("height", nh)
						_update_text_node_sizes(s, nw, nh)
					elif "width" in s and "height" in s:
						s.set("width", max(2.0, snap["w"] * factor_x))
						s.set("height", max(2.0, snap["h"] * factor_y))
					elif s is VectorShape and snap.has("doc_extent"):
						var orig_extent: DVec2 = snap["doc_extent"]
						var nx: float = max(2.0, orig_extent.x * (factor_x if current_axis != AxisLock.Y else 1.0))
						var ny: float = max(2.0, orig_extent.y * (factor_y if current_axis != AxisLock.X else 1.0))
						s.set_doc_extent(DVec2.new(nx, ny))

		KeyMode.ROTATE:
			var angle_offset = delta.x * 0.01
			for s in selected_shapes:
				if is_instance_valid(s) and transform_initial_states.has(s):
					var snap = transform_initial_states[s]
					s.global_rotation = snap["grot"] + angle_offset

	_update_bounding_box()
	canvas.queue_redraw()

# ── Redimensionado Geométrico Avanzado de Vectores y Texto ────────────────────

func _apply_resize(gm: Vector2) -> void:
	var delta: Vector2 = gm - transform_initial_mouse
	var ow: float = transform_macro_rect.size.x
	var oh: float = transform_macro_rect.size.y
	if ow < 1.0: ow = 1.0
	if oh < 1.0: oh = 1.0

	var rect_pos: Vector2 = transform_macro_rect.position
	var rect_end: Vector2 = transform_macro_rect.end
	var rect_center: Vector2 = transform_macro_rect.get_center()

	var pivot: Vector2 = rect_center
	var sx: float = 1.0
	var sy: float = 1.0

	match resize_handle:
		"rc":
			sx = (ow + delta.x) / ow
			pivot = Vector2(rect_pos.x, rect_center.y)
		"lc":
			sx = (ow - delta.x) / ow
			pivot = Vector2(rect_end.x, rect_center.y)
		"bc":
			sy = (oh + delta.y) / oh
			pivot = Vector2(rect_center.x, rect_pos.y)
		"tc":
			sy = (oh - delta.y) / oh
			pivot = Vector2(rect_center.x, rect_end.y)
		"br":
			sx = (ow + delta.x) / ow
			sy = (oh + delta.y) / oh
			pivot = rect_pos
		"bl":
			sx = (ow - delta.x) / ow
			sy = (oh + delta.y) / oh
			pivot = Vector2(rect_end.x, rect_pos.y)
		"tr":
			sx = (ow + delta.x) / ow
			sy = (oh - delta.y) / oh
			pivot = Vector2(rect_pos.x, rect_end.y)
		"tl":
			sx = (ow - delta.x) / ow
			sy = (oh - delta.y) / oh
			pivot = rect_end

	if Input.is_key_pressed(KEY_ALT):
		pivot = rect_center
		if resize_handle in ["rc", "lc", "br", "bl", "tr", "tl"]:
			sx = (ow + (delta.x if resize_handle in ["rc", "br", "tr"] else -delta.x) * 2.0) / ow
		if resize_handle in ["bc", "tc", "br", "bl", "tr", "tl"]:
			sy = (oh + (delta.y if resize_handle in ["bc", "br", "bl"] else -delta.y) * 2.0) / oh

	if Input.is_key_pressed(KEY_SHIFT) and resize_handle not in ["rc", "lc", "bc", "tc"]:
		var uniform_scale: float = max(abs(sx), abs(sy))
		sx = uniform_scale * sign(sx)
		sy = uniform_scale * sign(sy)

	if abs(sx) < 0.01: sx = 0.01 * sign(sx)
	if abs(sy) < 0.01: sy = 0.01 * sign(sy)

	var scale_vec: Vector2 = Vector2(sx, sy)
	live_scale = scale_vec
	live_pivot = pivot

	for shape in selected_shapes:
		if not is_instance_valid(shape) or not transform_initial_states.has(shape):
			continue
		var snap: Dictionary = transform_initial_states[shape]

		if shape.has_meta("shape_type") and (shape.get_meta("shape_type") in ["text_paragraph", "text_title"]):
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			
			var calculated_width: float = max(40.0, snap["w"] * abs(sx))
			var calculated_height: float = max(20.0, snap["h"] * abs(sy))
			
			shape.set_meta("width", calculated_width)
			shape.set_meta("height", calculated_height)
			
			_update_text_node_sizes(shape, calculated_width, calculated_height)
			continue

		if shape is Path2D and snap.has("g_path_nodes"):
			var curve: Curve2D = shape.curve
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			
			var data_nodes: Array = snap["g_path_nodes"]
			for i in range(curve.point_count):
				var node_data = data_nodes[i]
				var new_g_pos: Vector2 = pivot + (node_data["node"] - pivot) * scale_vec
				curve.set_point_position(i, shape.to_local(new_g_pos))
				
				var new_g_in: Vector2 = pivot + (node_data["in"] - pivot) * scale_vec
				var new_g_out: Vector2 = pivot + (node_data["out"] - pivot) * scale_vec
				
				curve.set_point_in(i, shape.to_local(new_g_in) - curve.get_point_position(i))
				curve.set_point_out(i, shape.to_local(new_g_out) - curve.get_point_position(i))
				
			var renderer = shape.get_node_or_null("Render_Visual")
			if renderer is Line2D:
				renderer.points = curve.get_baked_points()
			shape.queue_redraw()

		elif shape is Polygon2D and snap.has("g_poly_pts"):
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			
			var orig_g_poly: PackedVector2Array = snap["g_poly_pts"]
			var new_poly_pts = PackedVector2Array()
			for g_pt in orig_g_poly:
				var new_g_pt: Vector2 = pivot + (g_pt - pivot) * scale_vec
				new_poly_pts.append(shape.to_local(new_g_pt))
			shape.polygon = new_poly_pts
			
			if snap.has("g_stroke_pts"):
				var stroke = shape.get_node_or_null("Contorno_Stroke")
				if stroke is Line2D:
					var orig_g_stroke: PackedVector2Array = snap["g_stroke_pts"]
					var new_stroke_pts = PackedVector2Array()
					for g_pt in orig_g_stroke:
						var new_g_pt: Vector2 = pivot + (g_pt - pivot) * scale_vec
						new_stroke_pts.append(shape.to_local(new_g_pt))
					stroke.points = new_stroke_pts
			
			var l_min = new_poly_pts[0]
			var l_max = new_poly_pts[0]
			for p in new_poly_pts:
				l_min.x = min(l_min.x, p.x)
				l_min.y = min(l_min.y, p.y)
				l_max.x = max(l_max.x, p.x)
				l_max.y = max(l_max.y, p.y)
			shape.set_meta("size", l_max - l_min)
			shape.queue_redraw()

		elif snap.has("w") and snap.has("h") and not shape.has_meta("shape_type"):
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			shape.set("width", max(2.0, snap["w"] * abs(sx)))
			shape.set("height", max(2.0, snap["h"] * abs(sy)))
			shape.queue_redraw()

		elif snap.has("size"):
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			_sync_doc_position_from_native(shape)
			if shape is VectorShape and snap.has("doc_extent"):
				# Precisión doble real: el nuevo tamaño se calcula desde el valor
				# EXACTO capturado en _snapshot(), no desde el Vector2 float32 que
				# quedó guardado en .size tras el resize anterior — así el error
				# no se acumula operación tras operación.
				var orig_extent: DVec2 = snap["doc_extent"]
				var new_extent := DVec2.new(
					max(2.0, orig_extent.x * absf(sx)),
					max(2.0, orig_extent.y * absf(sy))
				)
				shape.set_doc_extent(new_extent)
			else:
				var new_size: Vector2 = Vector2(
					max(2.0, snap["size"].x * abs(sx)),
					max(2.0, snap["size"].y * abs(sy))
				)
				shape.set("size", new_size)
			shape.queue_redraw()

		elif snap.has("g_verts"):
			var orig_g_verts: PackedVector2Array = snap["g_verts"]
			var new_verts: PackedVector2Array = PackedVector2Array()
			for g_pt in orig_g_verts:
				var new_g_pt: Vector2 = pivot + (g_pt - pivot) * scale_vec
				new_verts.append(shape.to_local(new_g_pt))
			if shape is VectorShape and shape.has_doc_vertices():
				shape.set_doc_vertices(DVec2.array_from_v2(new_verts))
			else:
				shape.set("vertices", new_verts)
			shape.queue_redraw()

		elif shape is Line2D and snap.has("g_pts"):
			var orig_g_pts: PackedVector2Array = snap["g_pts"]
			var new_pts: PackedVector2Array = PackedVector2Array()
			for g_pt in orig_g_pts:
				var new_g_pt: Vector2 = pivot + (g_pt - pivot) * scale_vec
				new_pts.append(shape.to_local(new_g_pt))
			shape.points = new_pts
			shape.queue_redraw()

func _update_text_node_sizes(shape: Node2D, w: float, h: float) -> void:
	var display_label: Control = shape.get_node_or_null("DisplayLabel")
	var multi_edit: Control = shape.get_node_or_null("MultiLineEdit")
	if not multi_edit: multi_edit = shape.get_node_or_null("LineEdit")
	
	if display_label:
		display_label.custom_minimum_size = Vector2(w, h)
		display_label.size = Vector2(w, h)
	if multi_edit:
		multi_edit.custom_minimum_size = Vector2(w, h)
		multi_edit.size = Vector2(w, h)

# ── Lógica de Rotación Pro ──────────────────────────────────────────────────

func _apply_rotation(gm: Vector2) -> void:
	var angle_current: float = initial_macro_center.angle_to_point(gm)
	var angle_initial: float = initial_macro_center.angle_to_point(transform_initial_mouse)
	var angle_delta: float = angle_current - angle_initial

	if Input.is_key_pressed(KEY_SHIFT):
		var snap_step: float = deg_to_rad(15.0)
		angle_delta = round(angle_delta / snap_step) * snap_step

	live_rot_angle = angle_delta
	live_pivot = initial_macro_center

	for shape in selected_shapes:
		if not is_instance_valid(shape) or not transform_initial_states.has(shape):
			continue
		var snap: Dictionary = transform_initial_states[shape]

		var orig_gpos: Vector2 = snap["gpos"]
		var offset: Vector2 = orig_gpos - initial_macro_center
		shape.global_position = initial_macro_center + offset.rotated(angle_delta)
		_sync_doc_position_from_native(shape)
		if shape is VectorShape and snap.has("doc_rot"):
			# Precisión doble real: el ángulo nuevo se acumula sobre el valor
			# EXACTO capturado en _snapshot(), no sobre el float32 que dejó
			# guardado la rotación anterior — evita que el error se acumule
			# rotación tras rotación (solo válido si el padre no está rotado,
			# caso habitual en este proyecto; ver nota de alcance del plan).
			shape.set_doc_rotation(snap["doc_rot"] + angle_delta)
		else:
			shape.global_rotation = snap["grot"] + angle_delta

		if shape is Path2D:
			var renderer = shape.get_node_or_null("Render_Visual")
			if renderer is Line2D:
				renderer.points = shape.curve.get_baked_points()
		shape.queue_redraw()

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
	selected_shapes.assign(nueva.filter(func(s): return is_instance_valid(s)))
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

func select_all() -> void:
	_refresh_artboard()
	if not target_artboard:
		return
	selected_shapes.clear()
	var dl: Node = target_artboard.get_node_or_null("VectorDrawingLayer")
	if dl:
		for v_node in dl.get_children():
			if v_node is Node2D:
				selected_shapes.append(v_node)
	for node in target_artboard.get_children():
		if not (node is Node2D) or node.name in ["ArtboardTitle", "VectorDrawingLayer"]:
			continue
		selected_shapes.append(node)
	_update_macro_rect()
	_emit_selection_changed()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func delete_selected() -> void:
	if selected_shapes.is_empty():
		return
	var nodes: Array = selected_shapes.duplicate()
	var parents: Array = []
	var indices: Array = []
	for n in nodes:
		parents.append(n.get_parent())
		indices.append(n.get_index())

	HistoryManager.register_action("Eliminar selección")
	HistoryManager.add_do(_do_remove_nodes.bind(nodes))
	HistoryManager.add_undo(_do_restore_nodes.bind(nodes, parents, indices))
	HistoryManager.commit()
	_do_remove_nodes(nodes)

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

func _do_restore_nodes(nodes: Array, parents: Array, indices: Array) -> void:
	for i in range(nodes.size()):
		var n = nodes[i]
		var p = parents[i]
		if is_instance_valid(n) and is_instance_valid(p) and not n.is_inside_tree():
			p.add_child(n)
			p.move_child(n, mini(indices[i], p.get_child_count() - 1))
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func copy_selected() -> void:
	if selected_shapes.is_empty() or not SessionManager:
		return
	var clones: Array = []
	for s in selected_shapes:
		if is_instance_valid(s):
			# Los clones del portapapeles no entran en ningún árbol todavía —
			# el nombre no necesita ser único aquí, solo cuando de verdad se
			# inserten (paste_clipboard, contra target_artboard).
			clones.append(s.duplicate(DUPLICATE_SIGNALS | DUPLICATE_GROUPS | DUPLICATE_SCRIPTS))
	SessionManager.session.clipboard_shapes = clones

func cut_selected() -> void:
	copy_selected()
	delete_selected()

func paste_clipboard() -> void:
	if not SessionManager or not target_artboard:
		return
	var clipboard: Array = SessionManager.session.clipboard_shapes
	if clipboard.is_empty():
		return

	var new_nodes: Array = []
	for original in clipboard:
		if is_instance_valid(original):
			var clone: Node2D = original.duplicate(DUPLICATE_SIGNALS | DUPLICATE_GROUPS | DUPLICATE_SCRIPTS)
			clone.name = _unique_sibling_name(original.name, target_artboard)
			clone.position = original.position + Vector2(20, 20)
			new_nodes.append(clone)
	if new_nodes.is_empty():
		return

	_commit_add_nodes("Pegar", new_nodes)

## Node.duplicate() ya conserva el `.name` original (verificado con un print
## de depuración) — el problema real aparece después, en add_child(): cuando
## el nombre del clon COLISIONA con un hermano existente, la resolución
## automática de Godot para un nombre "heredado" de duplicate() no cae en el
## sufijo esperado ("TextTitle_Container_2") sino en un nombre anónimo tipo
## "@Node2D@599" — encontrado el 19/08/2026 verificando Ctrl+D en vivo varias
## veces. Se evita calculando aquí un nombre único ANTES de add_child(), sin
## depender de cómo Godot resuelva la colisión internamente.
## IMPORTANTE: `insert_parent` debe ser el padre donde el clon se va a
## insertar DE VERDAD (normalmente `target_artboard`), NO `original.get_parent()`
## a ciegas — si `original` es a su vez un clon todavía fuera de árbol (como
## los del portapapeles en paste_clipboard), `original.get_parent()` es null
## y la comprobación de unicidad no serviría de nada.
func _duplicate_named(original: Node2D, insert_parent: Node) -> Node2D:
	var clone: Node2D = original.duplicate(DUPLICATE_SIGNALS | DUPLICATE_GROUPS | DUPLICATE_SCRIPTS)
	clone.name = _unique_sibling_name(original.name, insert_parent)
	return clone

func _unique_sibling_name(base_name: String, parent: Node) -> String:
	# Nombre limpio "Base 2", "Base 3"… (estilo profesional), quitando un sufijo previo.
	var b := base_name
	var re := RegEx.new()
	re.compile("^(.*?)[ _]\\d+$")
	var m := re.search(b)
	if m:
		b = m.get_string(1)
	return NameUtils.unique_child_name(parent, b)

func duplicate_selected() -> void:
	if selected_shapes.is_empty() or not target_artboard:
		return
	var new_nodes: Array = []
	for s in selected_shapes:
		if is_instance_valid(s):
			var clone = _duplicate_named(s, target_artboard)
			clone.position = s.position + Vector2(20, 20)
			new_nodes.append(clone)
	if new_nodes.is_empty():
		return

	_commit_add_nodes("Duplicar selección", new_nodes)

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

func nudge_selected(direction: Vector2, big_step: bool = false) -> void:
	if selected_shapes.is_empty():
		return
	var delta: Vector2 = direction * (NUDGE_STEP_SHIFT if big_step else NUDGE_STEP)
	var nodes: Array = selected_shapes.duplicate()

	HistoryManager.register_action("Mover con teclado")
	HistoryManager.add_do(_do_nudge.bind(nodes, delta))
	HistoryManager.add_undo(_do_nudge.bind(nodes, -delta))
	HistoryManager.commit()
	_do_nudge(nodes, delta)

func _do_nudge(nodes: Array, delta: Vector2) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.global_position += delta
			_sync_doc_position_from_native(n)
	_update_bounding_box()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _force_text_loss_focus() -> void:
	var focus_owner = canvas.get_viewport().gui_get_focus_owner()
	if focus_owner and (focus_owner is TextEdit or focus_owner is LineEdit):
		focus_owner.release_focus()

func _apply_marquee() -> void:
	var mr: Rect2 = Rect2(marquee_start, marquee_end - marquee_start).abs()
	if not target_artboard:
		return

	# Alt resta del marquee (quita de la selección lo que toca el rectángulo);
	# sin Alt, suma (comportamiento normal / con Shift, ver _on_press).
	var subtract: bool = Input.is_key_pressed(KEY_ALT)

	var dl: Node = target_artboard.get_node_or_null("VectorDrawingLayer")
	if dl:
		for v_node in dl.get_children():
			if v_node is Node2D and mr.intersects(_global_rect(v_node)):
				if subtract:
					selected_shapes.erase(v_node)
				elif not selected_shapes.has(v_node):
					selected_shapes.append(v_node)

	for node in target_artboard.get_children():
		if not (node is Node2D) or node.name in ["ArtboardTitle", "VectorDrawingLayer"]:
			continue
		if mr.intersects(_global_rect(node)):
			if subtract:
				selected_shapes.erase(node)
			elif not selected_shapes.has(node):
				selected_shapes.append(node)

	_update_macro_rect()
	_emit_selection_changed()   # un solo cambio para todo el marquee
	canvas.queue_redraw()

# ── Motor de Hit-Testing e Intersección de Precisión Geométrica ───────────────

func _shape_at(gpos: Vector2) -> Node2D:
	# Busca en TODOS los artboards (no solo el activo) + las figuras sueltas
	# hijas directas del contenedor. Antes solo miraba target_artboard, así
	# que con varios artboards solo se podían seleccionar figuras del primero.
	var mgr := ArtboardManager.find(get_tree()) if get_tree() else null
	var artboards: Array = mgr.all_artboards() if mgr else ([target_artboard] if target_artboard else [])

	for ab in artboards:
		if not is_instance_valid(ab):
			continue
		var hit := _shape_at_in(ab, gpos)
		if hit:
			return hit

	# Figuras sueltas (hijas directas de ArtboardsContainer, fuera de todo artboard)
	var container: Node = canvas.get_node_or_null("ArtboardsContainer")
	if container:
		var loose: Array = container.get_children()
		for i in range(loose.size() - 1, -1, -1):
			var n = loose[i]
			if n is Node2D and not (n is ArtboardEditor) and _global_rect(n).has_point(gpos):
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
		elif _global_rect(n).has_point(gpos):
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

func _rama_contiene_punto(nodo: Node, gpos: Vector2) -> bool:
	# El CUERPO propio del nodo cuenta (una figura-contenedor sigue siendo
	# clicable sobre su propio relleno, no solo sobre sus hijos).
	if _tiene_cuerpo_propio(nodo) and _global_rect(nodo).has_point(gpos):
		return true
	for c in nodo.get_children():
		if not (c is Node2D) or String(c.name) == "Contorno_Stroke":
			continue
		if _es_grupo_movetool(c):
			if _rama_contiene_punto(c, gpos):
				return true
		elif _global_rect(c).has_point(gpos):
			return true
	return false

# ── Cálculo Dinámico del Bounding Box Pro (Soporte Títulos y Párrafos) ─────────

func _global_rect(node: Node2D) -> Rect2:
	if not is_instance_valid(node): return Rect2()

	if node.has_meta("shape_type") and (node.get_meta("shape_type") in ["text_paragraph", "text_title"]):
		var w: float = node.get_meta("width") if node.has_meta("width") else 350.0
		var h: float = node.get_meta("height") if node.has_meta("height") else 65.0
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

	if "size" in node and (node is VectorRectangle or node is VectorCircle):
		var s: Vector2 = node.get("size")
		return Rect2(node.global_position - s * 0.5, s)

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

# ── Renderizado del Bounding Box Pro (estilo profesional) ─────────────────────────

func draw_preview(c: Node2D) -> void:
	if not is_instance_valid(c):
		return

	if is_marquee:
		var sl: Vector2 = c.to_local(marquee_start)
		var el: Vector2 = c.to_local(marquee_end)
		var r: Rect2 = Rect2(sl, el - sl)
		c.draw_rect(r, COLOR_MARQUEE_F, true)
		c.draw_rect(r, COLOR_MARQUEE_S, false, 1.0)
		return

	# NOTA: El recuadro principal + handles de resize/rotate ya no se dibujan aquí.
	# Los renderiza boundingbox.tscn (instancia real del pool), ver bounding_box.gd.
	if selected_shapes.size() > 1:
		# Grosor CONSTANTE en pantalla (≈1.25 px) a cualquier zoom — como un editor profesional /
		# editor profesional. El zoom REAL es el del viewport (la cámara no escala el nodo
		# Canvas, escala el viewport).
		var vp := c.get_viewport()
		var zsc: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
		var outline_width: float = 1.25 / maxf(zsc, 0.0002)
		for shape in selected_shapes:
			if is_instance_valid(shape):
				var s_rect: Rect2 = _global_rect(shape)
				var s_lrect: Rect2 = Rect2(c.to_local(s_rect.position), c.to_local(s_rect.end) - c.to_local(s_rect.position))
				c.draw_rect(s_lrect, Color(COLOR_BBOX.r, COLOR_BBOX.g, COLOR_BBOX.b, 0.3), false, outline_width)

# ── Snapshot Riguroso de Estructuras Complejas ────────────────────────────────

## Reescribe doc_position (doble precisión) desde la posición nativa (float32)
## tras cualquier escritura directa a shape.global_position en este archivo.
## No toca doc_rotation — cada punto de llamada que cambia rotación decide
## explícitamente si usa set_doc_rotation() (precisión doble real) o debe
## re-sincronizar desde el nativo (ver _apply_rotation/_cancel_key_transform).
func _sync_doc_position_from_native(shape: Node2D) -> void:
	if shape is VectorShape:
		shape.doc_position = DVec2.from_v2(shape.position)

func _snapshot(shape: Node2D) -> Dictionary:
	var snap: Dictionary = {
		"gpos": shape.global_position,
		"grot": shape.global_rotation
	}

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
	
	elif "size" in shape and (shape is VectorRectangle or shape is VectorCircle):
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
		
	return snap

func _refresh_artboard() -> void:
	var mgr := ArtboardManager.find(get_tree()) if get_tree() else null
	if mgr:
		var act := mgr.get_active_artboard()
		if is_instance_valid(act):
			target_artboard = act
			return
	var container: Node = canvas.get_node_or_null("ArtboardsContainer")
	if container and container.get_child_count() > 0:
		target_artboard = container.get_child(0)

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
	if is_instance_valid(canvas) and is_instance_valid(canvas.artboards_container):
		if canvas.artboards_container.has_method("set_active_tool"):
			canvas.artboards_container.set_active_tool("movetool", self)

func _notificar_limpieza_al_overlay() -> void:
	if is_instance_valid(canvas) and is_instance_valid(canvas.artboards_container):
		if canvas.artboards_container.has_method("set_active_tool"):
			canvas.artboards_container.set_active_tool("other", null)

func _update_macro_rect() -> void:
	if selected_shapes.is_empty():
		transform_macro_rect = Rect2()
		if _bounding_box:
			_update_bounding_box()
		return

	# 1. Inicializar dimensiones con el primer elemento seleccionado
	var first_shape = selected_shapes[0]
	var rect: Rect2
	
	if first_shape.has_method("get_global_rect"):
		rect = first_shape.get_global_rect()
	elif "size" in first_shape:
		rect = Rect2(first_shape.global_position, first_shape.size)
	else:
		rect = Rect2(first_shape.global_position, Vector2(100, 100))

	var min_x = rect.position.x
	var min_y = rect.position.y
	var max_x = rect.position.x + rect.size.x
	var max_y = rect.position.y + rect.size.y

	# 2. Envolver el resto de figuras en caso de selección múltiple
	for i in range(1, selected_shapes.size()):
		var s = selected_shapes[i]
		if not is_instance_valid(s): 
			continue
			
		var r: Rect2
		if s.has_method("get_global_rect"):
			r = s.get_global_rect()
		elif "size" in s:
			r = Rect2(s.global_position, s.size)
		else:
			r = Rect2(s.global_position, Vector2(100, 100))
			
		min_x = min(min_x, r.position.x)
		min_y = min(min_y, r.position.y)
		max_x = max(max_x, r.position.x + r.size.x)
		max_y = max(max_y, r.position.y + r.size.y)

	# 3. Guardar estado macro vectorial puro
	transform_macro_rect = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
	initial_macro_center = transform_macro_rect.position + transform_macro_rect.size / 2.0
	
	# Actualizar bounding box
	if _bounding_box:
		_update_bounding_box()


# ==========================================
# TRANSFORMACIÓN INICIADA DESDE LOS HANDLES REALES (boundingbox.tscn)
# ==========================================

func start_handle_transform(handle_code: String) -> bool:
	"""
	Llamado por bounding_box.gd cuando el usuario presiona uno de sus
	Panels de handle (resize o rotate). Reemplaza el hit-testing manual
	que antes hacía _on_press()/_handle_at().
	"""
	if selected_shapes.size() == 0:
		return false

	var gm: Vector2 = canvas.get_global_mouse_position()
	var macro: Rect2 = _get_macro_rect()

	_axis_move = ""
	live_rot_angle = 0.0
	live_scale = Vector2.ONE
	if handle_code == "move_x" or handle_code == "move_y":
		# Handle de eje: mover la selección SOLO en horizontal / vertical.
		_axis_move = "x" if handle_code == "move_x" else "y"
		is_dragging_shape = true
	elif handle_code.begins_with("rot"):
		is_rotating = true
	else:
		is_resizing = true
	resize_handle = handle_code

	transform_initial_mouse = gm
	transform_macro_rect = macro
	initial_macro_center = macro.get_center()
	live_pivot = initial_macro_center
	transform_initial_states.clear()

	for shape in selected_shapes:
		if is_instance_valid(shape):
			transform_initial_states[shape] = _snapshot(shape)

	canvas.queue_redraw()
	return true

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
