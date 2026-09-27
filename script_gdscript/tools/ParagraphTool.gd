# =============================================================================
# RUTA: res://script_gdscript/ParagraphTool.gd
# Vectopen — Herramienta de Párrafos (MultiLineEdit) con Texto en Color Negro
# =============================================================================
extends ToolBase

var is_editing: bool = false
var current_editing_shape: Node2D = null
var target_artboard: Node2D = null

# ── Estados para Text Threading (InDesign / Affinity Publisher) ───────────────
var is_dragging_thread: bool = false
var thread_source_frame: Node2D = null
var thread_target_pos: Vector2 = Vector2.ZERO

func activate() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_IBEAM)
	_refresh_artboard()

func deactivate() -> void:
	if is_editing:
		_finish_editing_and_save()
	is_dragging_thread = false
	thread_source_frame = null
	if canvas:
		canvas.queue_redraw()

func handle_input(event: InputEvent) -> bool:
	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false

	_refresh_artboard()
	if not target_artboard:
		return false

	var gm: Vector2 = canvas.get_global_mouse_position()

	# 0. DETECCIÓN DE CLIC EN PUERTO DE ENLACE / DESBORDAMIENTO (THREADING)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var port_hit: Node2D = _find_out_port_at(gm)
			if port_hit:
				is_dragging_thread = true
				thread_source_frame = port_hit
				thread_target_pos = gm
				if canvas:
					canvas.queue_redraw()
				return true
		else:
			if is_dragging_thread:
				_finish_thread_drag(gm)
				return true

	# MOVIMIENTO DE RATÓN PARA THREADING
	if event is InputEventMouseMotion and is_dragging_thread:
		thread_target_pos = gm
		if canvas:
			canvas.queue_redraw()
		return true

	# 1. DETECCIÓN DE DOBLE CLIC: Para editar un párrafo
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		var hit: Node2D = _shape_at(gm)
		if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_paragraph":
			var frame := _edit_frame_for(hit, gm)
			if not is_instance_valid(frame):
				return true
			target_artboard = frame
			_check_and_trigger_edit_at(frame.to_local(gm))
			return true

	# 2. GESTIÓN DE CLIC SIMPLE
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		
		# CASO A: Si ya estamos editando y hacemos clic FUERA del bloque de texto
		if is_editing and is_instance_valid(current_editing_shape):
			var local_pos: Vector2 = current_editing_shape.to_local(gm)
			var w: float = current_editing_shape.get_meta("width") if current_editing_shape.has_meta("width") else 350.0
			var h: float = current_editing_shape.get_meta("height") if current_editing_shape.has_meta("height") else 100.0
			var rect: Rect2 = Rect2(Vector2.ZERO, Vector2(w, h))

			if not rect.has_point(local_pos):
				var saved_shape = current_editing_shape
				_finish_editing_and_save()
				_switch_to_move_tool(saved_shape)
				return true

			return false

		# CASO B: Clic en lienzo vacío -> Crea párrafo estático negro y cambia a MoveTool
		var hit: Node2D = _shape_at(gm)
		if not hit:
			var t := _artboard_for_point(gm)
			if is_instance_valid(t):
				target_artboard = t
			if not is_instance_valid(target_artboard):
				return false
			_create_new_paragraph_at(target_artboard.to_local(gm))
			return true

	return false

func _check_and_trigger_edit_at(pos_or_local = null, explicit_shape: Node2D = null) -> void:
	var hit: Node2D = explicit_shape
	if hit == null:
		if pos_or_local is Node2D:
			hit = pos_or_local
		elif is_instance_valid(target_artboard) and pos_or_local is Vector2:
			var gm: Vector2 = target_artboard.to_global(pos_or_local)
			hit = _shape_at(gm)
		elif pos_or_local is Vector2:
			hit = _shape_at(pos_or_local)
	
	if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_paragraph":
		if is_editing and current_editing_shape != hit:
			_finish_editing_and_save()

		is_editing = true
		current_editing_shape = hit
		
		var sm = get_node_or_null("/root/SelectionManager")
		if is_instance_valid(sm) and sm.has_method("select"):
			sm.select(hit)

		var display_label: Control = hit.get_node_or_null("DisplayLabel")
		var multi_edit: TextEdit = hit.get_node_or_null("MultiLineEdit")
		
		if display_label: display_label.visible = false
		if multi_edit:
			multi_edit.visible = true
			var txt: String = str(hit.get_meta("text", ""))
			multi_edit.text = txt
			var fs: int = int(hit.get_meta("font_size", 24))
			multi_edit.add_theme_font_size_override("font_size", fs)
			multi_edit.add_theme_color_override("font_color", hit.get_meta("text_color", Color.BLACK))
			multi_edit.grab_focus()
			multi_edit.select_all()

func _finish_editing_and_save() -> void:
	if not is_instance_valid(current_editing_shape):
		_reset_state()
		return
		
	var display_label: Control = current_editing_shape.get_node_or_null("DisplayLabel")
	var multi_edit: TextEdit = current_editing_shape.get_node_or_null("MultiLineEdit")
	
	if multi_edit:
		var final_text = multi_edit.text.strip_edges()
		if final_text == "": final_text = "Texto de párrafo vacío."
		
		var is_threaded: bool = current_editing_shape.has_meta("next_paragraph") or current_editing_shape.has_meta("prev_paragraph")
		if is_threaded:
			var head = ParagraphThreading.get_chain_head(current_editing_shape)
			head.set_meta("raw_story_text", final_text)
			ParagraphThreading.reflow_chain(head)
		else:
			current_editing_shape.set_meta("text", final_text)
			if display_label:
				display_label.text = final_text
				display_label.visible = true
				# RE-SINCRONIZAR: el contenido cambió → el tamaño del shape debe
				# recalcularse para que el boundingbox envuelva el texto.
				_update_shape_meta_size(current_editing_shape)
		
		multi_edit.release_focus()
		multi_edit.visible = false

	_reset_state()

## Recalcula width/height del shape a partir del mínimo real del label
## (en unidades de MUNDO), y re-dimensiona label + MultiLineEdit (que es lo
## que muestra el boundingbox de selección de MoveTool).
func _update_shape_meta_size(shape: Node2D) -> void:
	var display_label: Control = shape.get_node_or_null("DisplayLabel")
	var multi_edit: Control = shape.get_node_or_null("MultiLineEdit")
	if not display_label:
		return
	var min_size: Vector2 = display_label.get_world_minimum_size() if display_label is WorldTextLabel else display_label.get_combined_minimum_size()
	var safe_size: Vector2 = Vector2(maxf(min_size.x, 100.0), maxf(min_size.y, 40.0))
	shape.set_meta("width", safe_size.x)
	shape.set_meta("height", safe_size.y)
	if display_label is WorldTextLabel:
		display_label.set_world_size(safe_size)
	else:
		display_label.custom_minimum_size = safe_size
		display_label.size = safe_size
	if multi_edit:
		multi_edit.custom_minimum_size = safe_size
		multi_edit.size = safe_size

func _create_new_paragraph_at(local_pos: Vector2) -> Node2D:
	var new_para = Node2D.new()
	new_para.name = NameUtils.unique_child_name(target_artboard, "Párrafo")
	new_para.set_meta("shape_type", "text_paragraph")
	new_para.set_meta("width", 350.0)
	new_para.set_meta("height", 100.0)
	new_para.set_meta("font_size", 24)
	new_para.set_meta("text_color", Color.BLACK)
	new_para.set_meta("text", "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam nec diam interdum, laoreet lacus id, aliquet magna.")
	
	var label := WorldTextLabel.new()
	label.name = "DisplayLabel"
	label.base_font_size = 24
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(350, 100)
	label.size = Vector2(350, 100)
	label.set_world_size(Vector2(350, 100))
	label.text = new_para.get_meta("text")
	# Forzar color de fuente a negro
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_font_size_override("font_size", 24)
	
	var edit = TextEdit.new()
	edit.name = "MultiLineEdit"
	edit.visible = false
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.custom_minimum_size = Vector2(350, 100)
	edit.size = Vector2(350, 100)
	# Forzar color de fuente a negro en el editor
	edit.add_theme_color_override("font_color", Color.BLACK)
	edit.add_theme_font_size_override("font_size", 24)
	
	new_para.add_child(label)
	new_para.add_child(edit)
	
	target_artboard.add_child(new_para)
	new_para.position = local_pos
	
	# Sincronizar el tamaño del shape con el contenido renderizado del label
	_update_shape_meta_size(new_para)
	
	_switch_to_move_tool(new_para)
	return new_para

func _switch_to_move_tool(shape: Node2D) -> void:
	if is_instance_valid(canvas) and canvas.has_method("change_tool"):
		var move_tool_script = load("res://script_gdscript/tools/MoveTool.gd")
		if move_tool_script:
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
			# Selección vía SelectionManager (única fuente de verdad):
			# MoveTool.activate() reconstruye su espejo desde el Manager,
			# así que el pre-set del espejo de arriba se pierde al activar.
			# Sin esto, el párrafo recién creado quedaba sin seleccionar
			# (TextTool ya usa este mismo patrón).
			var sm := get_node_or_null("/root/SelectionManager")
			if is_instance_valid(sm) and sm.has_method("select"):
				sm.select(shape)

func _reset_state() -> void:
	is_editing = false
	current_editing_shape = null

func _refresh_artboard() -> void:
	var mgr := ArtboardManager.find(get_tree()) if get_tree() else null
	if mgr:
		var act := mgr.get_active_artboard()
		if is_instance_valid(act):
			target_artboard = act
			return
	var container = canvas.get_node_or_null("ArtboardsContainer")
	if container and container.get_child_count() > 0:
		target_artboard = container.get_child(0)

func _shape_at(gpos: Vector2) -> Node2D:
	var artboards: Array = []
	var mgr := ArtboardManager.find(get_tree()) if get_tree() else null
	if mgr:
		artboards = mgr.all_artboards()
	elif is_instance_valid(target_artboard):
		artboards = [target_artboard]
	
	for ab in artboards:
		if not is_instance_valid(ab):
			continue
		var found := _find_shape_in_tree(ab, gpos)
		if found:
			return found
			
	if is_instance_valid(canvas) and "artboards_container" in canvas and is_instance_valid(canvas.artboards_container):
		var found_loose := _find_shape_in_tree(canvas.artboards_container, gpos)
		if found_loose:
			return found_loose
			
	return null

func _find_shape_in_tree(node: Node, gpos: Vector2) -> Node2D:
	for i in range(node.get_child_count() - 1, -1, -1):
		var child = node.get_child(i)
		if not (child is Node2D):
			continue
		if child.name in ["Contorno_Stroke", "ArtboardTitle"]:
			continue
		if child.has_meta("shape_type"):
			var w: float = float(child.get_meta("width", 350.0))
			var h: float = float(child.get_meta("height", 100.0))
			var local_pt: Vector2 = child.to_local(gpos)
			if Rect2(Vector2.ZERO, Vector2(w, h)).has_point(local_pt):
				return child
		var sub := _find_shape_in_tree(child, gpos)
		if sub:
			return sub
	return null

# ── Métodos de Text Threading (InDesign / Affinity Publisher) ─────────────────

func _find_out_port_at(gm: Vector2) -> Node2D:
	var artboards: Array = []
	var mgr := ArtboardManager.find(get_tree()) if get_tree() else null
	if mgr:
		artboards = mgr.all_artboards()
	elif is_instance_valid(target_artboard):
		artboards = [target_artboard]
		
	for ab in artboards:
		if not is_instance_valid(ab):
			continue
		var found := _find_out_port_in_tree(ab, gm)
		if found:
			return found
	return null

func _find_out_port_in_tree(node: Node, gm: Vector2) -> Node2D:
	for i in range(node.get_child_count() - 1, -1, -1):
		var child = node.get_child(i)
		if not (child is Node2D):
			continue
		if child.has_meta("shape_type") and child.get_meta("shape_type") == "text_paragraph":
			if ParagraphThreading.is_point_in_out_port(child, gm):
				return child
		var sub := _find_out_port_in_tree(child, gm)
		if sub:
			return sub
	return null

func _finish_thread_drag(gm: Vector2) -> void:
	is_dragging_thread = false
	if not is_instance_valid(thread_source_frame):
		thread_source_frame = null
		if canvas: canvas.queue_redraw()
		return

	var hit: Node2D = _shape_at(gm)
	if hit and hit != thread_source_frame and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_paragraph":
		ParagraphThreading.link(thread_source_frame, hit)
	else:
		var t := _artboard_for_point(gm)
		if is_instance_valid(t):
			target_artboard = t
		if target_artboard:
			var local_pos = target_artboard.to_local(gm)
			var new_para = _create_new_paragraph_at(local_pos)
			ParagraphThreading.link(thread_source_frame, new_para)

	thread_source_frame = null
	if canvas:
		canvas.queue_redraw()

func _get_paragraph_rect_local(c: Node2D, p: Node2D) -> Rect2:
	var w: float = p.get_meta("width") if p.has_meta("width") else 350.0
	var h: float = p.get_meta("height") if p.has_meta("height") else 100.0
	var tl: Vector2 = c.to_local(p.global_position)
	var br: Vector2 = c.to_local(p.global_position + Vector2(w, h))
	return Rect2(tl, br - tl)

func draw_preview(c: Node2D) -> void:
	if not is_instance_valid(c):
		return

	var vp := c.get_viewport()
	var zoom: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	zoom = maxf(zoom, 0.0002)
	var k: float = 1.0 / zoom
	var font := ThemeDB.fallback_font

	if target_artboard:
		for child in target_artboard.get_children():
			if not (child is Node2D) or not child.has_meta("shape_type") or child.get_meta("shape_type") != "text_paragraph":
				continue

			# 1. Dibujar líneas de enlace entre marcos enlazados (InDesign / Affinity Publisher)
			var nxt := ParagraphThreading.get_next_frame(child)
			if is_instance_valid(nxt):
				var p_src := c.to_local(ParagraphThreading.get_out_port_rect(child).get_center())
				var p_dst := c.to_local(nxt.global_position + Vector2(10, 10))
				c.draw_line(p_src, p_dst, Color(0.2, 0.75, 1.0, 0.75), 1.5 * k)
				c.draw_circle(p_dst, 3.5 * k, Color(0.2, 0.75, 1.0, 0.95))

			# 2. Dibujar el puerto de salida / desbordamiento (Out-Port Handle)
			var port_rect_g := ParagraphThreading.get_out_port_rect(child)
			var port_rect_l := Rect2(c.to_local(port_rect_g.position), port_rect_g.size)
			var is_overflow: bool = child.get_meta("is_overflowing", false)
			var has_next: bool = is_instance_valid(nxt)

			if is_overflow:
				# Rojo: desbordamiento de texto (overset text [+] universal)
				c.draw_rect(port_rect_l, Color(0.95, 0.2, 0.2, 0.95), true)
				c.draw_rect(port_rect_l, Color(1.0, 1.0, 1.0, 0.9), false, 1.0 * k)
				var plus_fs := maxi(9, int(round(11.0 * k)))
				c.draw_string(font, port_rect_l.position + Vector2(2 * k, 10 * k), "+", HORIZONTAL_ALIGNMENT_CENTER, -1, plus_fs, Color.WHITE)
			elif has_next:
				# Cyan: marco enlazado con texto que continúa
				c.draw_rect(port_rect_l, Color(0.15, 0.65, 0.95, 0.95), true)
				c.draw_rect(port_rect_l, Color(1.0, 1.0, 1.0, 0.8), false, 1.0 * k)
				var arrow_fs := maxi(8, int(round(9.0 * k)))
				c.draw_string(font, port_rect_l.position + Vector2(2 * k, 10 * k), "→", HORIZONTAL_ALIGNMENT_CENTER, -1, arrow_fs, Color.WHITE)
			else:
				# Gris/Azul neutro: puerto listo para arrastrar y encadenar
				c.draw_rect(port_rect_l, Color(0.2, 0.25, 0.35, 0.8), true)
				c.draw_rect(port_rect_l, Color(0.5, 0.6, 0.75, 0.7), false, 1.0 * k)

	# 3. Dibujar hilo elástico interactivo mientras se arrastra para encadenar
	if is_dragging_thread and is_instance_valid(thread_source_frame):
		var src_pt := c.to_local(ParagraphThreading.get_out_port_rect(thread_source_frame).get_center())
		var dst_pt := c.to_local(thread_target_pos)

		c.draw_line(src_pt, dst_pt, Color(0.3, 0.8, 1.0, 0.9), 2.0 * k)
		c.draw_circle(dst_pt, 4.0 * k, Color(0.2, 0.85, 1.0, 1.0))

		var hit_target := _shape_at(thread_target_pos)
		var badge_str := ""
		if hit_target and hit_target != thread_source_frame and hit_target.has_meta("shape_type") and hit_target.get_meta("shape_type") == "text_paragraph":
			badge_str = "Enlazar flujo a este párrafo"
			var hit_rect := _get_paragraph_rect_local(c, hit_target)
			c.draw_rect(hit_rect, Color(0.2, 0.8, 1.0, 0.3), false, 2.0 * k)
		else:
			badge_str = "Soltar para crear marco enlazado"

		var b_fs := maxi(10, int(round(12.0 * k)))
		var b_size := font.get_string_size(badge_str, HORIZONTAL_ALIGNMENT_LEFT, -1, b_fs)
		var b_pad := Vector2(8, 4) * k
		var b_pos := dst_pt + Vector2(16, 12) * k
		var b_rect := Rect2(b_pos, b_size + b_pad * 2.0)

		c.draw_rect(b_rect.grow(1.5 * k), Color(0, 0, 0, 0.35), true)
		c.draw_rect(b_rect, Color(0.08, 0.12, 0.18, 0.95), true)
		c.draw_rect(b_rect, Color(0.2, 0.75, 1.0, 0.9), false, 1.2 * k)
		c.draw_string(font, b_pos + b_pad + Vector2(0, b_fs * 0.82), badge_str, HORIZONTAL_ALIGNMENT_LEFT, -1, b_fs, Color.WHITE)
