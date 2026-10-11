# =============================================================================
# RUTA: res://script_gdscript/MoveTool.gd
# Vectopen — Selección y transformación general de figuras (estilo profesional + Key)
# Versión Pro Avanzada con soporte geométrico de precisión para vectores y texto.
# Migrado de `Tool` (RefCounted) a `ToolBase` (Node) el 19/08/2026 — última de
# las 8 herramientas del informe §1.1/§1.5. Construir con `canvas._new_tool(script)`
# (o `MoveTool.new()` + `tool.canvas = ...`), NO con `MoveTool.new(canvas)`.
# =============================================================================
class_name MoveTool
extends "res://script_gdscript/tools/move/move_tool_draw.gd"
# Herramienta Mover. Dividida en módulos (script_gdscript/tools/move/):
#   move_tool_core → transform → ops → threading → keyboard → 3d → draw → MoveTool
# Aquí quedan el ciclo de vida, la entrada (ratón/teclado) y el doble clic.


# ── Métodos del Ciclo de Vida ────────────────────────────────────────────────

func get_class_name() -> String:
	return "MoveTool"

func activate() -> void:
	# Actualizar estado del cursor inteligente
	if SmartCursor:
		SmartCursor.set_state(CursorStateMachine.CursorState.ACTIVE)
	
	is_gradient_mode = false
	_clear_key_transform()
	_notificar_cambio_al_overlay()
	_acquire_bounding_box()
	if is_instance_valid(_bounding_box):
		_bounding_box.is_gradient_tool_active = false
		if _bounding_box.has_method("deactivate_gradient_mode"):
			_bounding_box.deactivate_gradient_mode()
		_bounding_box.queue_redraw()
	# Reflejar en el bounding box la selección que ya viva en SelectionManager
	# (p. ej. hecha desde el panel de capas con otra herramienta activa).
	if SelectionManager:
		if not _sel_conn:
			SelectionManager.changed.connect(_on_external_selection_changed)
			_sel_conn = true
		_on_external_selection_changed(SelectionManager.get_selected())
	else:
		_update_macro_rect()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

	var _dc := get_node_or_null("/root/DebugConsola")
	if _dc and _dc.has_method("registrar_movetool"):
		_dc.registrar_movetool(self)
		if is_instance_valid(_bounding_box) and _dc.has_method("registrar_bbox"):
			_dc.registrar_bbox(_bounding_box)

	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_signal("paint_changed") and not cc.paint_changed.is_connected(_on_colorcore_paint_changed):
		cc.paint_changed.connect(_on_colorcore_paint_changed)

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
	_hover_shape = null
	_clear_selection()
	_clear_key_transform()
	is_dragging_shape = false
	is_resizing = false
	is_rotating = false
	is_marquee = false
	is_gradient_mode = false
	_exit_3d_mode()
	is_dragging_artboard = false
	is_resizing_artboard = false
	_release_bounding_box()
	var cc := get_node_or_null("/root/ColorCore") if is_inside_tree() else null
	if cc and cc.has_signal("paint_changed") and cc.paint_changed.is_connected(_on_colorcore_paint_changed):
		cc.paint_changed.disconnect(_on_colorcore_paint_changed)
	_notificar_limpieza_al_overlay()
	
	# Restaurar estado del cursor
	if SmartCursor:
		SmartCursor.set_state(CursorStateMachine.CursorState.NEUTRAL)
	
	if is_instance_valid(canvas):
		canvas.queue_redraw()

# ── Entrada Principal ──────────────────────────────────────────────────────────

func handle_input(event: InputEvent) -> bool:
	# 1. Si el bounding box está en medio de un arrastre activo (p.ej. de un punto de degradado),
	# procesar siempre el evento para no perder el movimiento ni el soltado del ratón.
	if is_instance_valid(_bounding_box) and _bounding_box.has_method("has_gradient_annotator") and _bounding_box.has_gradient_annotator():
		if "_annotator_drag_mode" in _bounding_box and _bounding_box._annotator_drag_mode != "":
			if _bounding_box.has_method("handle_annotator_input") and _bounding_box.handle_annotator_input(event):
				return true

	# Teclas del modo 3D (vistas, F, Inicio, Esc): ANTES de mirar si el ratón
	# está sobre la interfaz — con el ratón sobre el recuadro del modelo esa
	# comprobación las descartaba y los números acababan cambiando la opacidad.
	if event is InputEventKey and is_instance_valid(active_3d_model):
		if event.pressed and event.keycode == KEY_ESCAPE:
			_exit_3d_mode()
			return true
		if handle_key_3d(event):
			return true

	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		var gm_check: Vector2 = canvas.get_canvas_transform().affine_inverse() * event.position if (is_instance_valid(canvas) and ("position" in event)) else (canvas.get_global_mouse_position() if is_instance_valid(canvas) else Vector2.ZERO)
		var hit_ab := _artboard_for_point(gm_check)
		if not is_instance_valid(hit_ab):
			return false

	# ── Modo Edición 3D activo (rotación orbital y zoom de cámara) ──
	if is_instance_valid(active_3d_model):
		var gm3d: Vector2 = canvas.get_canvas_transform().affine_inverse() * event.position if (is_instance_valid(canvas) and ("position" in event)) else (canvas.get_global_mouse_position() if is_instance_valid(canvas) else Vector2.ZERO)

		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_exit_3d_mode()
			return true
		if event is InputEventKey and handle_key_3d(event):
			return true

		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				if handle_wheel_3d(event, gm3d):
					return true
			elif event.button_index == MOUSE_BUTTON_MIDDLE:
				if handle_middle_click_3d(event, gm3d):
					return true
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					# clic en el gizmo de ejes → vista (como Godot / Blender)
					if active_3d_model.has_method("gizmo_hit"):
						var view_name: String = active_3d_model.gizmo_hit(active_3d_model.to_local(gm3d))
						if view_name != "":
							active_3d_model.set_view(view_name)
							return true
					if _node_contains_point(active_3d_model, gm3d):
						_is_dragging_3d = true
						_last_3d_mouse = gm3d
						if active_3d_model.has_method("begin_interactive_orbit"):
							active_3d_model.begin_interactive_orbit()
						return true
					else:
						# Clic fuera de la bounding box del modelo 3D -> salir inmediatamente
						_exit_3d_mode()
				else:
					if _is_dragging_3d:
						_is_dragging_3d = false
						if active_3d_model.has_method("end_interactive_orbit"):
							active_3d_model.end_interactive_orbit()
						elif active_3d_model.has_method("capture_high_quality"):
							active_3d_model.capture_high_quality()
						return true

		if event is InputEventMouseMotion:
			if is_middle_dragging_3d:
				if handle_middle_motion_3d(gm3d):
					return true
			elif _is_dragging_3d:
				var delta: Vector2 = gm3d - _last_3d_mouse
				_last_3d_mouse = gm3d
				navigate_3d(active_3d_model, _screen_delta(delta))
				return true

	# Soporte MMB (rueda/clic medio) y Wheel estilo Blender para modelos 3D fuera de modo explícito
	if event is InputEventMouseButton:
		var gmm: Vector2 = canvas.get_canvas_transform().affine_inverse() * event.position if (is_instance_valid(canvas) and ("position" in event)) else (canvas.get_global_mouse_position() if is_instance_valid(canvas) else Vector2.ZERO)
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if handle_middle_click_3d(event, gmm):
				return true
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if handle_wheel_3d(event, gmm):
				return true
	elif event is InputEventMouseMotion and is_middle_dragging_3d:
		var gmm: Vector2 = canvas.get_canvas_transform().affine_inverse() * event.position if (is_instance_valid(canvas) and ("position" in event)) else (canvas.get_global_mouse_position() if is_instance_valid(canvas) else Vector2.ZERO)
		if handle_middle_motion_3d(gmm):
			return true

	# 2. Permitir que el anotador de degradado procese clics o pulsaciones antes de descartar por artboard
	if is_instance_valid(_bounding_box) and _bounding_box.has_method("has_gradient_annotator") and _bounding_box.has_gradient_annotator():
		if _bounding_box.has_method("handle_annotator_input") and _bounding_box.handle_annotator_input(event):
			return true

	_refresh_artboard()
	if not target_artboard:
		return false

	var gm: Vector2 = canvas.get_global_mouse_position()
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		gm = canvas.get_canvas_transform().affine_inverse() * event.position

	# Atajos de Teclado por teclado (G, S, R, X, Y, ESC)
	if event is InputEventKey:
		if event.keycode in [KEY_ALT, KEY_META, KEY_CTRL, KEY_SHIFT]:
			if is_instance_valid(canvas):
				canvas.queue_redraw()
		if event.pressed and event.keycode == KEY_ESCAPE and is_dragging_thread:
			is_dragging_thread = false
			thread_source_frame = null
			if is_instance_valid(canvas):
				canvas.queue_redraw()
			return true
		if event.pressed and _handle_key_shortcuts(event.keycode, event.shift_pressed):
			return true

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if current_key_mode != KeyMode.NONE:
				_confirm_key_transform()
				return true
				
			if event.double_click:
				_last_press_time = 0
				return _on_double_click(gm)
			if _is_own_text_double_click(gm):
				_last_press_time = 0
				return _on_double_click(gm)
			return _on_press(gm)
		else:
			if is_dragging_thread:
				_finish_thread_drag(gm)
				return true
			return _on_release(gm)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if current_key_mode != KeyMode.NONE:
			_cancel_key_transform()
			return true

	if event is InputEventMouseMotion:
		if is_dragging_thread:
			thread_target_pos = gm
			if is_instance_valid(canvas):
				canvas.queue_redraw()
			return true
		# Modificadores LEIDOS DEL PROPIO EVENTO, no SOLO de Input.is_key_pressed()
		# (estado global sondeado en un stream aparte de keydown/keyup): igual
		# que documenta IHTML en js/workspace/bounding-box.js _onHandleDown —
		# sondear el estado global desincroniza si se aprieta/suelta un
		# modificador a mitad de un arrastre (keydown y mousemove llegan en
		# cuadros distintos), y esa desincro es justo lo que causaba
		# "parpadeo" entre redimensionado proporcional y libre allá. El
		# INPUT_EVENT_MOUSE_MOTION de Godot trae shift_pressed/alt_pressed/
		# ctrl_pressed ya resueltos para ESTE cuadro exacto.
		#
		# OR con el estado global (no un reemplazo por él): confirmado en vivo
		# que Godot 4.7 puede entregar un InputEventMouseMotion sintético
		# (inyectado por MCP vía Input.parse_input_event(), sin evento de
		# teclado real de por medio) con shift_pressed=false aunque el
		# descriptor pedía shift=true — el motor no siempre respeta el campo
		# tal cual se construyó en el evento. Combinar ambas fuentes con OR
		# es estrictamente más permisivo que cualquiera de las dos solas: para
		# un usuario real, event.shift_pressed ya es preciso y esto no cambia
		# nada; para un evento sintético cuyo campo se pierda, el fallback al
		# estado global (que si refleja lo que se despachó) lo rescata.
		return _on_motion(gm, {
			"shift": event.shift_pressed or Input.is_key_pressed(KEY_SHIFT),
			"alt": event.alt_pressed or Input.is_key_pressed(KEY_ALT),
			"ctrl": event.ctrl_pressed or event.meta_pressed or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META),
		})

	if event is InputEventScreenTouch:
		if event.pressed:
			if current_key_mode != KeyMode.NONE:
				_confirm_key_transform()
				return true
			return _on_press(gm)
		else:
			return _on_release(gm)

	if event is InputEventScreenDrag:
		return _on_motion(gm)

	return false

# ── LÓGICA DE DOBLE CLIC ──────────────────────────────────────────────────────

## Segundo clic en el MISMO texto dentro de la ventana → doble-clic aunque
## el motor no lo marque. Registra cada press para comparar el siguiente.
func _is_own_text_double_click(gm: Vector2) -> bool:
	var now := Time.get_ticks_msec()
	var hit := _shape_at(gm)
	var ok := _last_press_time > 0 \
		and now - _last_press_time <= OWN_DBLCLICK_MS \
		and gm.distance_to(_last_press_pos) <= OWN_DBLCLICK_PX \
		and is_instance_valid(hit) and hit == _last_press_shape \
		and hit.has_meta("shape_type") \
		and str(hit.get_meta("shape_type")) in ["text_paragraph", "text_title"]
	_last_press_time = now
	_last_press_pos = gm
	_last_press_shape = hit
	return ok

func _on_double_click(gm: Vector2) -> bool:
	var hit: Node2D = _shape_at(gm)
	# Usamos is_instance_valid para mayor seguridad de memoria en Godot 4
	if not is_instance_valid(hit): 
		return false
	
	# Soporte para Modo Edición 3D (rotación y zoom orbital)
	if hit.has_method("set_3d_editing"):
		_enter_3d_mode(hit)
		return true

	if not canvas.has_method("change_tool"): 
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
				
			var frame := _edit_frame_for(hit, gm)
			if not is_instance_valid(frame):
				return false
			target_artboard = frame
			var para_tool = canvas._new_tool(script_para)
			canvas.change_tool(para_tool)
			para_tool.target_artboard = frame
			para_tool._check_and_trigger_edit_at(frame.to_local(gm))
			return true
			
		# 2. BLINDAJE PARA TÍTULOS DE TEXTO
		elif type == "text_title":
			_clear_selection()
			var script_text = load("res://script_gdscript/tools/TextTool.gd")
			if script_text == null:
				push_error("Vectopen Error: No se pudo cargar 'TextTool.gd'. Revisa su sintaxis interna o ruta.")
				return false
				
			var frame := _edit_frame_for(hit, gm)
			if not is_instance_valid(frame):
				return false
			target_artboard = frame
			var title_tool = canvas._new_tool(script_text)
			canvas.change_tool(title_tool)
			title_tool.target_artboard = frame

			if title_tool.has_method("_check_and_trigger_edit_at"):
				title_tool._check_and_trigger_edit_at(frame.to_local(gm))
			return true
			
	# 3. BLINDAJE PARA EDICIÓN DE NODOS COLES (VECTORES Y CURVAS BEZIER)
	if hit is Path2D or hit is Line2D or hit is Polygon2D or hit.has_meta("curve") or hit.name.contains("Bezier"):
		_clear_selection()
		var script_nodes = load("res://script_gdscript/tools/NodeSelectionTool.gd")
		if script_nodes == null:
			push_error("Vectopen Error: No se pudo cargar 'NodeSelectionTool.gd'. Revisa su sintaxis interna o ruta.")
			return false
			
		var herramienta_nodos = canvas._new_tool(script_nodes)
		var target_path: Path2D = hit if (hit is Path2D) else (hit.get_parent() as Path2D)
		if is_instance_valid(target_path):
			herramienta_nodos.edit_path = target_path
			var p_local = target_path.to_local(gm)
			var closest_idx := -1
			var min_d := 24.0
			if is_instance_valid(target_path.curve):
				for idx in range(target_path.curve.point_count):
					var d := p_local.distance_to(target_path.curve.get_point_position(idx))
					if d < min_d:
						min_d = d
						closest_idx = idx
			if closest_idx != -1:
				herramienta_nodos.selected_nodes.assign([closest_idx])
			else:
				herramienta_nodos.selected_nodes.clear()
				
		canvas.change_tool(herramienta_nodos)
		var ge = get_node_or_null("/root/GlobalEvents")
		if ge and ge.has_signal("request_bezier_panel"):
			ge.emit_safe("request_bezier_panel")
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
		elif _node_contains_point(c, gm):
			return c
	return null

# ── Press ──────────────────────────────────────────────────────────────────────

func _on_press(gm: Vector2) -> bool:
	# El artboard sobre el que se pulsa (multi-artboard). Si el clic cae fuera
	# de todos, seguimos con el activo para el marquee de "espacio vacío".
	var mgr := ArtboardManager.find(get_tree()) if is_inside_tree() else null
	var clicked_ab: Node2D = mgr.artboard_at_point(gm) if mgr else null
	if is_instance_valid(clicked_ab):
		target_artboard = clicked_ab
		if mgr and mgr.active_artboard != clicked_ab and _shape_at(gm) == null:
			# clic en el cuerpo de OTRO artboard → activarlo
			mgr.set_active_artboard(clicked_ab)

	var ab_local: Vector2 = target_artboard.to_local(gm) if is_instance_valid(target_artboard) else gm
	var ab_rect: Rect2 = Rect2(Vector2.ZERO, target_artboard.artboard_size) if (is_instance_valid(target_artboard) and "artboard_size" in target_artboard) else Rect2()

	if is_instance_valid(target_artboard) and "is_selected" in target_artboard and target_artboard.is_selected and target_artboard.has_method("is_on_handle") and target_artboard.is_on_handle(ab_local):
		var edge: Vector2 = target_artboard.get_resize_edge(ab_local)
		if edge != Vector2.ZERO:
			is_resizing_artboard = true
			artboard_resize_edge = edge
			return true

	# NOTA: El inicio de resize/rotate ya no se detecta aquí por hit-testing manual.
	# Lo dispara boundingbox.gd al pulsar uno de sus handles reales, vía start_handle_transform().

	var hit: Node2D = _shape_at(gm)
	if hit:
		# 13.2 Cmd/Ctrl + Clic: selección directa de objeto dentro de un grupo (deep select)
		if (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)) and _es_grupo_movetool(hit):
			var actual: Node2D = hit
			while true:
				var h: Node2D = _hijo_bajo_punto(actual, gm)
				if not is_instance_valid(h) or h == actual:
					break
				actual = h
			hit = actual
		elif _es_grupo_movetool(hit):
			var sel_dentro := _primer_seleccionado_en_rama(hit)
			if sel_dentro != null:
				hit = sel_dentro
		_pending_shift_deselect = null
		if selected_shapes.has(hit):
			if Input.is_key_pressed(KEY_SHIFT):
				# No deseleccionar todavía — podría ser el inicio de un
				# Shift+arrastre (mover en eje). Se decide en _on_release
				# según si hubo arrastre real o fue un clic quieto.
				_pending_shift_deselect = hit
		else:
			if not Input.is_key_pressed(KEY_SHIFT):
				_clear_selection()
			_select(hit)

		_alt_drag_duplicated = false
		_shift_drag_axis = ""
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

func _on_release(gm: Vector2) -> bool:
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
		if _is_stroke_adjusting:
			_accion = "Ajustar grosor de trazo"
		elif is_resizing:
			_accion = "Redimensionar"
		elif is_rotating: _accion = "Rotar"
		_commit_transform(_accion, selected_shapes.duplicate(), is_resizing or is_rotating or _is_stroke_adjusting)
		for s in selected_shapes:
			if is_instance_valid(s):
				if s.has_method("capture_high_quality"):
					s.capture_high_quality()
				# Re-fluir SOLO cadenas enlazadas: en un párrafo suelto el reflow
				# re-escribía su texto en el editor nativo y borraba su formato.
				if is_resizing and s.has_meta("shape_type") and s.get_meta("shape_type") == "text_paragraph" \
						and (s.has_meta("next_paragraph") or s.has_meta("prev_paragraph")):
					var head := ParagraphThreading.get_chain_head(s)
					ParagraphThreading.reflow_chain(head)

	# Shift+clic sobre una figura ya seleccionada SIN arrastre real (el mouse
	# no se movió, o casi) = deselecciónala ahora — ver el comentario grande
	# en _pending_shift_deselect. Mismo umbral que el gesto de duplicar con Alt.
	if is_instance_valid(_pending_shift_deselect) and (gm - transform_initial_mouse).length() <= 3.0:
		_deselect(_pending_shift_deselect)
	_pending_shift_deselect = null

	is_dragging_shape = false
	_alt_drag_duplicated = false
	_shift_drag_axis = ""
	is_resizing = false
	is_rotating = false
	_is_stroke_adjusting = false
	is_dragging_artboard = false
	is_resizing_artboard = false
	resize_handle = ""
	_axis_move = ""
	live_rot_angle = 0.0
	live_scale = Vector2.ONE
	artboard_resize_edge = Vector2.ZERO
	transform_initial_states.clear()
	_snap_guides.clear()
	_snap_spacing.clear()

	_update_bounding_box()

	if hubo_transformacion and GlobalEvents:
		GlobalEvents.emit_safe("object_transformed")

	canvas.queue_redraw()
	return true

# ── Motion ─────────────────────────────────────────────────────────────────────

## Autocuración de estado de arrastre atascado. `bounding_box._on_drag_panel_gui_input`
## pone `is_dragging_shape = true` al pulsar sobre el interior del gizmo; si el
## panel se aleja bajo el cursor (persigue a la figura) la SUELTA nunca llega a
## ese `gui_input` y `is_dragging_shape` se queda en `true` para siempre → cada
## motion arrastra la selección y NADA más responde (ni panel de capas ni
## arrastre de artboard). Si el botón izquierdo NO está pulsado de verdad,
## cancelamos cualquier gesto en curso. Barato (una llamada nativa por evento).
func _heal_stuck_gesture() -> void:
	if is_middle_dragging_3d and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		end_middle_drag_3d()
	if _is_dragging_3d and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_is_dragging_3d = false
		if is_instance_valid(active_3d_model) and active_3d_model.has_method("end_interactive_orbit"):
			active_3d_model.end_interactive_orbit()

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
	_is_stroke_adjusting = false
	_alt_drag_duplicated = false
	_shift_drag_axis = ""
	_pending_shift_deselect = null
	resize_handle = ""
	_axis_move = ""
	artboard_resize_edge = Vector2.ZERO
	transform_initial_states.clear()
	_snap_guides.clear()
	_snap_spacing.clear()
	if is_instance_valid(_bounding_box) and "_is_dragging_canvas_area" in _bounding_box:
		_bounding_box._is_dragging_canvas_area = false
	if is_instance_valid(canvas):
		canvas.queue_redraw()

## `mods`: {"shift","alt","ctrl": bool} leídos del InputEventMouseMotion real
## cuando lo hay (ver handle_input); {} (touch/InputEventScreenDrag, que no
## trae estos campos) cae a Input.is_key_pressed() dentro de _apply_resize/
## _apply_rotation — mismo comportamiento que antes para ese caso.
func _on_motion(gm: Vector2, mods: Dictionary = {}) -> bool:
	if is_marquee:
		marquee_end = gm
		canvas.queue_redraw()
		return true

	if current_key_mode != KeyMode.NONE and selected_shapes.size() > 0:
		_process_key_motion(gm)
		return true

	_update_hover_shape(gm)

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
		_apply_resize(gm, mods)
		_update_bounding_box()
		canvas.queue_redraw()
		return true

	if is_rotating and selected_shapes.size() > 0:
		_apply_rotation(gm, mods)
		_update_bounding_box()
		canvas.queue_redraw()
		return true

	if is_dragging_shape:
		# Mismo criterio que _apply_resize/_apply_rotation (ver comentario
		# grande en handle_input): modificadores del dict `mods` —armado con
		# los campos reales del InputEventMouseMotion— en vez de
		# Input.is_key_pressed() sondeado aparte, para no desincronizar si
		# Alt/Shift/Ctrl cambian a mitad del arrastre.
		var drag_alt: bool = mods.get("alt", Input.is_key_pressed(KEY_ALT))
		var drag_shift: bool = mods.get("shift", Input.is_key_pressed(KEY_SHIFT))
		var drag_ctrl: bool = mods.get("ctrl", Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META))

		# 13.2 Alt/Option + Arrastrar: duplicar selección inmediatamente
		if drag_alt and not _alt_drag_duplicated and (gm - transform_initial_mouse).length() > 3.0:
			_perform_alt_drag_duplication(gm)

		var delta: Vector2 = gm - transform_initial_mouse

		# Shift+drag on the box body = stroke width on all four sides (drag
		# right or up = thicker). The figure does not move.
		if drag_shift and _axis_move == "" and not drag_alt:
			if delta.length() > 2.0 or _is_stroke_adjusting:
				_is_stroke_adjusting = true
				_apply_body_stroke_drag(delta)
				_update_bounding_box()
				canvas.queue_redraw()
			return true

		# Handles de eje del bounding box: mover SOLO en horizontal / vertical.
		# Ctrl+drag locks to the dominant axis (Shift is taken by stroke width).
		if _axis_move == "x":
			delta.y = 0.0
		elif _axis_move == "y":
			delta.x = 0.0
		elif drag_ctrl:
			# Decidir el eje UNA SOLA VEZ (con una pequeña zona muerta para no
			# fijarlo con ruido de 1px al empezar) y mantenerlo fijo el resto
			# del gesto — no recalcularlo cada frame contra el delta
			# acumulado, que podía "soltar" el eje si el mouse titubeaba
			# cerca de la diagonal. Ver comentario en la declaración de
			# _shift_drag_axis.
			if _shift_drag_axis == "" and delta.length() > 2.0:
				_shift_drag_axis = "x" if abs(delta.x) > abs(delta.y) else "y"
			if _shift_drag_axis == "x":
				delta.y = 0.0
			elif _shift_drag_axis == "y":
				delta.x = 0.0
		else:
			_shift_drag_axis = ""

		# ── Imán inteligente: alinear con bordes/centros de otras figuras ──
		_snap_guides.clear()
		_snap_spacing.clear()
		var _sm := _snap_manager()
		if _sm and _sm.has_method("smart_snap") and (_sm.snap_to_objects or _sm.snap_to_guides) \
				and not _sm.grid_enabled and _axis_move == "" \
				and not drag_shift and not drag_alt and not drag_ctrl:
			var start_union: Rect2 = _macro_rect_inicial()
			if start_union.size != Vector2.ZERO:
				var moving_now := Rect2(start_union.position + delta, start_union.size)
				var snap_res: Dictionary = _sm.smart_snap(moving_now, _snap_candidates(), _viewport_zoom())
				delta += snap_res["offset"] as Vector2
				_snap_guides = snap_res["guides"]
				_snap_spacing = snap_res.get("spacing", [])

		for s in selected_shapes:
			if is_instance_valid(s) and transform_initial_states.has(s):
				var snap: Dictionary = transform_initial_states[s]
				var _skip = null
				var new_pos: Vector2 = snap["gpos"] + delta
				var st := Engine.get_main_loop() as SceneTree
				if st:
					var sm := st.root.get_node_or_null("SnapManager")
					if sm and drag_ctrl and "grid_size" in sm and sm.grid_size > 0:
						# Ctrl = axis lock; the grid pull only acts on the moving axis
						# Ctrl FUERZA el snap a grilla aunque el toggle
						# permanente (SnapManager.grid_enabled, Ajustes) esté
						# apagado — igual que IHTML (drag.js: "const
						# snapToGrid = e.ctrlKey || settings.grid.snap").
						# Antes Ctrl+arrastrar no hacía nada en este bloque
						# (solo apagaba el imán inteligente de la línea de
						# arriba); pedido explícito del usuario tras probarlo
						# en vivo y ver que no pasaba nada.
						if _shift_drag_axis != "y":
							new_pos.x = round(new_pos.x / sm.grid_size) * sm.grid_size
						if _shift_drag_axis != "x":
							new_pos.y = round(new_pos.y / sm.grid_size) * sm.grid_size
					elif sm and sm.has_method("snap_position"):
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

func _update_hover_shape(gm: Vector2) -> void:
	var busy := is_resizing or is_rotating or is_dragging_shape or is_marquee or current_key_mode != KeyMode.NONE
	var hit: Node2D = null if busy else _shape_at(gm)
	if hit and selected_shapes.has(hit):
		hit = null
	if hit != _hover_shape:
		_hover_shape = hit
		if is_instance_valid(canvas):
			canvas.queue_redraw()

## Uniform stroke width from a Shift+drag on the selection body.
func _apply_body_stroke_drag(delta: Vector2) -> void:
	var stroke_delta: float = (delta.x - delta.y) * 0.15
	for shape in selected_shapes:
		if not is_instance_valid(shape):
			continue
		var snap_s: Dictionary = transform_initial_states.get(shape, {})
		var init_w: float = float(snap_s["stroke_width"]) if snap_s.has("stroke_width") else _get_shape_stroke_width(shape)
		_set_shape_stroke_width(shape, maxf(0.0, init_w + stroke_delta))
		if shape.has_method("clear_side_strokes"):
			shape.clear_side_strokes()

func _update_transform_logic(gm: Vector2) -> void:
	_on_motion(gm)

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
