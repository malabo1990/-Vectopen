# =============================================================================
# RUTA: res://script_gdscript/tools/move/move_tool_threading.gd
# Encadenamiento de marcos de texto (text threading) desde la selección.
# Parte de la herramienta Mover (MoveTool), dividida por capas de herencia:
#   move_tool_core → transform → ops → threading → keyboard → 3d → draw → MoveTool
# El código se movió TAL CUAL desde MoveTool.gd (sin cambios de comportamiento).
# =============================================================================
extends "res://script_gdscript/tools/move/move_tool_ops.gd"


# ── Encadenamiento de Marcos de Texto (Text Threading) ───────────────────────

func start_threading_drag(source: Node2D, start_gpos: Vector2) -> void:
	if not is_instance_valid(source):
		return
	is_dragging_thread = true
	thread_source_frame = source
	thread_target_pos = start_gpos
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _finish_thread_drag(gm: Vector2) -> void:
	if not is_dragging_thread or not is_instance_valid(thread_source_frame):
		is_dragging_thread = false
		thread_source_frame = null
		if is_instance_valid(canvas):
			canvas.queue_redraw()
		return

	var source: Node2D = thread_source_frame
	is_dragging_thread = false
	thread_source_frame = null

	var target_shape: Node2D = _shape_at(gm)
	var linked: bool = false
	var target_frame: Node2D = null

	if is_instance_valid(target_shape) and target_shape != source and target_shape.has_meta("shape_type") and str(target_shape.get_meta("shape_type")) == "text_paragraph":
		target_frame = target_shape
		linked = ParagraphThreading.link(source, target_frame)
	else:
		var t := _artboard_for_point(gm)
		if is_instance_valid(t):
			target_artboard = t
		if is_instance_valid(target_artboard):
			var local_pos: Vector2 = target_artboard.to_local(gm)
			var w: float = float(source.get_meta("width", 350.0))
			var h: float = float(source.get_meta("height", 100.0))
			var fs: int = int(source.get_meta("font_size", 24))
			var tc: Color = source.get_meta("text_color", Color.BLACK)
			
			var new_para := Node2D.new()
			new_para.name = NameUtils.unique_child_name(target_artboard, "Párrafo")
			new_para.set_meta("shape_type", "text_paragraph")
			new_para.set_meta("width", w)
			new_para.set_meta("height", h)
			new_para.set_meta("font_size", fs)
			new_para.set_meta("text_color", tc)
			new_para.set_meta("text", "")
			
			var label := WorldTextLabel.new()
			label.name = "DisplayLabel"
			label.base_font_size = fs
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size = Vector2(w, h)
			label.size = Vector2(w, h)
			label.set_world_size(Vector2(w, h))
			label.add_theme_color_override("font_color", tc)
			label.add_theme_font_size_override("font_size", fs)
			
			var edit := TextEdit.new()
			edit.name = "MultiLineEdit"
			edit.visible = false
			edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			edit.custom_minimum_size = Vector2(w, h)
			edit.size = Vector2(w, h)
			edit.add_theme_color_override("font_color", tc)
			edit.add_theme_font_size_override("font_size", fs)
			
			new_para.add_child(label)
			new_para.add_child(edit)
			target_artboard.add_child(new_para)
			new_para.position = local_pos
			
			target_frame = new_para
			linked = ParagraphThreading.link(source, target_frame)

	if linked and is_instance_valid(target_frame):
		_register_threading_undo(source, target_frame)
		_clear_selection()
		_select(target_frame)

	_update_bounding_box()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _register_threading_undo(source: Node2D, target: Node2D) -> void:
	if not HistoryManager:
		return
	HistoryManager.register_action("Enlazar marcos de texto")
	HistoryManager.add_do(func():
		if is_instance_valid(source) and is_instance_valid(target):
			ParagraphThreading.link(source, target)
			_update_bounding_box()
			if is_instance_valid(canvas): canvas.queue_redraw()
	)
	HistoryManager.add_undo(func():
		if is_instance_valid(source):
			ParagraphThreading.unlink_next(source)
			_update_bounding_box()
			if is_instance_valid(canvas): canvas.queue_redraw()
	)
	HistoryManager.commit()
