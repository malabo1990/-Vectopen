# =============================================================================
# RUTA: res://script_gdscript/ParagraphTool.gd
# Vectopen — Herramienta de Párrafos (MultiLineEdit) con Texto en Color Negro
# =============================================================================
extends "res://script_gdscript/tools/TextToolBase.gd"

# ── Estados para Text Threading (InDesign / Affinity Publisher) ───────────────
var is_dragging_thread: bool = false
var thread_source_frame: Node2D = null
var thread_target_pos: Vector2 = Vector2.ZERO

func activate() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_IBEAM)
	_refresh_artboard()

func deactivate() -> void:
	if is_editing:
		commit_text_edit(false)
	is_dragging_thread = false
	thread_source_frame = null
	if canvas:
		canvas.queue_redraw()

func handle_input(event: InputEvent) -> bool:
	_refresh_artboard()
	if not target_artboard:
		return false

	var gm: Vector2 = canvas.get_canvas_transform().affine_inverse() * event.position if (is_instance_valid(canvas) and ("position" in event)) else (canvas.get_global_mouse_position() if is_instance_valid(canvas) else Vector2.ZERO)

	var gui := _get_autoload("GlobalUI")
	if is_instance_valid(gui) and "is_mouse_over_ui" in gui and gui.is_mouse_over_ui:
		var hit_ab := _artboard_for_point(gm)
		if not is_instance_valid(hit_ab):
			return false

	if event is InputEventKey and event.pressed:
		if is_editing:
			if event.keycode == KEY_ESCAPE:
				commit_text_edit(true)
				return true
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and event.is_command_or_control_pressed():
				commit_text_edit(true)
				return true

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
		elif hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_title":
			if is_editing:
				commit_text_edit(false)
			if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
				canvas.switch_tool("text")
				if canvas.current_tool and canvas.current_tool.has_method("_check_and_trigger_edit_at"):
					var frame := _edit_frame_for(hit, gm)
					if is_instance_valid(frame):
						canvas.current_tool.target_artboard = frame
						canvas.current_tool._check_and_trigger_edit_at(frame.to_local(gm))
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
				var hit_other: Node2D = _shape_at(gm)
				if hit_other and event.double_click and hit_other.has_meta("shape_type") and hit_other.get_meta("shape_type") == "text_paragraph":
					commit_text_edit(false)
					var frame := _edit_frame_for(hit_other, gm)
					if is_instance_valid(frame):
						target_artboard = frame
						_check_and_trigger_edit_at(frame.to_local(gm))
					return true
				elif hit_other and event.double_click and hit_other.has_meta("shape_type") and hit_other.get_meta("shape_type") == "text_title":
					commit_text_edit(false)
					if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
						canvas.switch_tool("text")
						if canvas.current_tool and canvas.current_tool.has_method("_check_and_trigger_edit_at"):
							var frame := _edit_frame_for(hit_other, gm)
							if is_instance_valid(frame):
								canvas.current_tool.target_artboard = frame
								canvas.current_tool._check_and_trigger_edit_at(frame.to_local(gm))
					return true
				var shape_edited: Node2D = current_editing_shape
				commit_text_edit(true)
				if is_instance_valid(hit_other) and hit_other != shape_edited:
					var sm := _get_autoload("SelectionManager")
					if is_instance_valid(sm):
						sm.select(hit_other)
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
	var click_global: Vector2 = Vector2.ZERO
	if hit == null:
		if pos_or_local is Node2D:
			hit = pos_or_local
		elif is_instance_valid(target_artboard) and pos_or_local is Vector2:
			click_global = target_artboard.to_global(pos_or_local)
			hit = _shape_at(click_global)
		elif pos_or_local is Vector2:
			click_global = pos_or_local
			hit = _shape_at(click_global)
	
	if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_paragraph":
		if is_editing and current_editing_shape != hit:
			commit_text_edit(false)

		is_editing = true
		interaction_state = STATE_EDITING
		current_editing_shape = hit
		_edit_before = TextCore.capture_text_state(hit)
		
		var sm = _get_autoload("SelectionManager")
		if is_instance_valid(sm):
			if sm.has_method("select"):
				sm.select(hit)
			if sm.has_method("set_active_editing_object"):
				sm.set_active_editing_object(hit)

		var display_label: Control = hit.get_node_or_null("DisplayLabel")
		var multi_edit: TextEdit = TextCore.ensure_inline_editor(hit)
		var vrt = hit.get_node_or_null("VectorRichText")
		if vrt == null and ClassDB.class_exists("VectorRichText"):
			vrt = ClassDB.instantiate("VectorRichText")
			vrt.name = "VectorRichText"
			vrt.set_is_paragraph(true)
			TextCore.apply_vrt_fonts(vrt, hit)
			var w_init := float(hit.get_meta("width", 350.0))
			var h_init := float(hit.get_meta("height", 100.0))
			vrt.set_frame_size(Vector2(w_init, h_init))
			vrt.set_text_color(hit.get_meta("text_color", Color.BLACK))
			vrt.set_font_size(float(hit.get_meta("font_size", 24)))
			vrt.set_text(str(hit.get_meta("text", "")))
			if hit.has_meta("runs"):
				_safe_set_runs_meta(vrt, hit.get_meta("runs"))
			hit.add_child(vrt)
			if display_label:
				display_label.visible = false

		if vrt:
			if display_label: display_label.visible = false
			if multi_edit: multi_edit.visible = false
			vrt.visible = true
			var w_init := float(hit.get_meta("width", 350.0))
			var h_init := float(hit.get_meta("height", 100.0))
			vrt.set_frame_size(Vector2(w_init, h_init))
			vrt.set_text_color(hit.get_meta("text_color", Color.BLACK))
			vrt.set_font_size(float(hit.get_meta("font_size", 24)))
			vrt.set_text(str(hit.get_meta("text", "")))
			if hit.has_meta("runs"):
				_safe_set_runs_meta(vrt, hit.get_meta("runs"))
			if not vrt.text_changed.is_connected(_on_vrt_text_changed):
				vrt.text_changed.connect(_on_vrt_text_changed)
			if not vrt.editing_finished.is_connected(_on_vrt_editing_finished):
				vrt.editing_finished.connect(_on_vrt_editing_finished)
			vrt.start_editing()
			if click_global != Vector2.ZERO and vrt.has_method("hit_test") and vrt.has_method("select_word_at"):
				var vrt_pos: Vector2 = hit.to_local(click_global)
				var hit_idx: int = vrt.hit_test(vrt_pos)
				vrt.select_word_at(hit_idx)
			else:
				vrt.select_all()
			return

		if display_label: display_label.visible = false
		if multi_edit:
			multi_edit.visible = true
			var txt: String = str(hit.get_meta("text", ""))
			multi_edit.text = txt
			var fs: int = int(hit.get_meta("font_size", 24))
			multi_edit.add_theme_font_size_override("font_size", fs)
			multi_edit.add_theme_color_override("font_color", hit.get_meta("text_color", Color.BLACK))
			multi_edit.add_theme_color_override("font_selected_color", Color(0, 0, 0, 0))
			if display_label is WorldTextLabel:
				_style_multi_edit(multi_edit, display_label)

			_fit_height_to_text(hit, multi_edit.text)
			if multi_edit.syntax_highlighter:
				multi_edit.syntax_highlighter.clear_highlighting_cache()
			multi_edit.queue_redraw()

			# Crecer EN VIVO mientras se escribe: sin esto el editor quedaba
			# con el tamaño viejo (scroll interno) y al terminar pegaba un
			# salto. Misma medición que al guardar (_update_shape_meta_size).
			if not multi_edit.text_changed.is_connected(_on_edit_text_changed):
				multi_edit.text_changed.connect(_on_edit_text_changed)
			if not multi_edit.gui_input.is_connected(_on_multi_edit_gui_input):
				multi_edit.gui_input.connect(_on_multi_edit_gui_input)
			if multi_edit.has_signal("caret_changed") and not multi_edit.caret_changed.is_connected(_on_multi_edit_caret_changed):
				multi_edit.caret_changed.connect(_on_multi_edit_caret_changed)
			multi_edit.grab_focus()
			multi_edit.select_all()

func _on_vrt_text_changed(new_text: String) -> void:
	if not is_editing or not is_instance_valid(current_editing_shape):
		return
	var vrt = current_editing_shape.get_node_or_null("VectorRichText")
	if vrt == null:
		return
	current_editing_shape.set_meta("text", new_text)
	current_editing_shape.set_meta("runs", vrt.get_runs_meta())
	var display_label: Control = current_editing_shape.get_node_or_null("DisplayLabel")
	if display_label:
		display_label.text = new_text
		if display_label.has_method("set_rich_runs"):
			display_label.set_rich_runs(current_editing_shape.get_meta("runs", []))
	var multi_edit: TextEdit = current_editing_shape.get_node_or_null("MultiLineEdit")
	if multi_edit:
		multi_edit.text = new_text
	_fit_height_to_text(current_editing_shape, new_text)
	var ge := _get_autoload("GlobalEvents")
	if ge and ge.has_method("emit_safe"):
		ge.emit_safe("object_transformed")

func _on_vrt_editing_finished() -> void:
	commit_text_edit(true)

## Texto cambiado mientras se edita: el BB abraza el contenido en vivo
## (la altura solo crece con saltos de línea por el reflow natural).
func _on_edit_text_changed() -> void:
	if not is_editing or not is_instance_valid(current_editing_shape):
		return
	var display_label: Control = current_editing_shape.get_node_or_null("DisplayLabel")
	if display_label == null:
		return
	var multi_edit: TextEdit = current_editing_shape.get_node_or_null("MultiLineEdit")
	if multi_edit == null:
		return
	# Los runs siguen al cambio por POSICIÓN (prev = meta "text", que se
	# mantiene sincronizada en cada tecla).
	TextRuns.apply_text_edit(current_editing_shape, str(current_editing_shape.get_meta("text", "")), multi_edit.text)
	display_label.text = multi_edit.text
	current_editing_shape.set_meta("text", multi_edit.text)
	if display_label.has_method("set_rich_runs"):
		display_label.set_rich_runs(current_editing_shape.get_meta("runs", []))
	if multi_edit.syntax_highlighter:
		multi_edit.syntax_highlighter.clear_highlighting_cache()
	multi_edit.queue_redraw()
	_fit_height_to_text(current_editing_shape, multi_edit.text)
	var ge := _get_autoload("GlobalEvents")
	if ge and ge.has_method("emit_safe"):
		ge.emit_safe("object_transformed")

## El BB abraza SOLO en altura (medición determinista: sin estado del
## Control, imposible el ratchet). El ancho lo controla el usuario
## (resize/panel); si se recalculara aquí, el error de escala se
## multiplicaría en cada tecla (350 → 795 → 1800 → 4000).
func _fit_height_to_text(shape: Node2D, txt: String) -> void:
	# Marco enlazado: tamaño FIJO (el sobrante fluye al siguiente al confirmar).
	if shape.has_meta("next_paragraph") or shape.has_meta("prev_paragraph"):
		return
	var vrt = shape.get_node_or_null("VectorRichText")
	var display_label: Control = shape.get_node_or_null("DisplayLabel")
	var multi_edit: Control = shape.get_node_or_null("MultiLineEdit")
	if display_label == null and vrt == null:
		return
	var w := float(shape.get_meta("width", 350.0))
	var h := 100.0
	if vrt:
		vrt.set_frame_size(Vector2(w, 100000.0))
		var csz: Vector2 = vrt.get_content_size()
		h = maxf(40.0, csz.y)
		vrt.set_frame_size(Vector2(w, h))
		vrt.custom_minimum_size = Vector2(w, h)
		vrt.size = Vector2(w, h)
	elif display_label is WorldTextLabel:
		h = maxf(40.0, display_label.wrapped_content_height(txt))
		display_label.set_world_size(Vector2(w, h))
	else:
		var min_size: Vector2 = display_label.get_combined_minimum_size()
		h = maxf(40.0, min_size.y)
		display_label.custom_minimum_size = Vector2(w, h)
		display_label.size = Vector2(w, h)
	shape.set_meta("height", h)
	if display_label:
		if display_label is WorldTextLabel:
			display_label.set_world_size(Vector2(w, h))
		else:
			display_label.custom_minimum_size = Vector2(w, h)
			display_label.size = Vector2(w, h)
	if multi_edit:
		multi_edit.custom_minimum_size = Vector2(w, h)
		multi_edit.size = Vector2(w, h)

## Editor invisible: igual que el texto renderizado (misma fuente, sin
## fondo ni borde, sin scrollbars) para que entrar a editar no cambie el
## aspecto del texto en el lienzo (igual que TextTool._style_title_edit).
func _style_multi_edit(edit: TextEdit, label: WorldTextLabel) -> void:
	var shape: Node2D = edit.get_parent() as Node2D
	var font := label.get_theme_font("font")
	if font:
		edit.add_theme_font_override("font", font)

	# 1. Tamaño de fuente exacto de la figura o del WorldTextLabel
	var fs: int = 24
	if "world_font_size" in label and label.world_font_size > 0:
		fs = label.world_font_size
	elif "base_font_size" in label and label.base_font_size > 0:
		fs = label.base_font_size
	elif shape and shape.has_meta("font_size"):
		fs = int(shape.get_meta("font_size", 24))
	edit.add_theme_font_size_override("font_size", fs)

	# 2. Interlineado (line_spacing) idéntico al renderizado
	var ls: int = 3
	if shape and shape.has_meta("line_spacing"):
		ls = int(shape.get_meta("line_spacing"))
	elif label.has_theme_constant_override("line_spacing"):
		ls = label.get_theme_constant("line_spacing")
	edit.add_theme_constant_override("line_spacing", ls)

	# 3. Sangrías aplicadas a los márgenes del StyleBox (indent_left, indent_right)
	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color(0, 0, 0, 0)
	transparent.set_content_margin_all(0)
	if shape:
		transparent.content_margin_left = float(shape.get_meta("indent_left", 0.0))
		transparent.content_margin_right = float(shape.get_meta("indent_right", 0.0))
		transparent.content_margin_top = 0.0
		transparent.content_margin_bottom = 0.0
	else:
		transparent.content_margin_left = 0.0
		transparent.content_margin_right = 0.0
		transparent.content_margin_top = 0.0
		transparent.content_margin_bottom = 0.0
	edit.add_theme_stylebox_override("normal", transparent)
	edit.add_theme_stylebox_override("focus", transparent)
	edit.add_theme_stylebox_override("read_only", transparent)

	# 4. Envoltura de texto boundary + smart
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	edit.deselect_on_focus_loss_enabled = false
	if edit.has_method("clear_gutters"):
		edit.clear_gutters()
	edit.scroll_fit_content_height = true
	edit.scroll_past_end_of_file = false

	# 5. Colores de cursor, selección y fuente
	var accent := Color(0.0, 0.478, 1.0, 1.0)
	edit.add_theme_color_override("caret_color", accent)
	edit.add_theme_color_override("selection_color", Color(accent.r, accent.g, accent.b, 0.25))
	var font_col: Color = label.font_color() if label.has_method("font_color") else label.get_theme_color("font_color")
	if font_col.a <= 0.01:
		font_col = Color.BLACK
	edit.add_theme_color_override("font_color", font_col)
	# Alpha 0 en font_selected_color para que Godot use los colores vivos del SyntaxHighlighter bajo la selección
	edit.add_theme_color_override("font_selected_color", Color(0, 0, 0, 0))

	# 6. Syntax highlighter para runs ricos
	if shape and (edit.syntax_highlighter == null or not (edit.syntax_highlighter is WorldTextLabel.RunHighlighter)):
		edit.syntax_highlighter = WorldTextLabel.RunHighlighter.new(shape)

## Canal único centralizado de confirmación y salida de edición (Vectopen Text Engine)
func commit_text_edit(switch_tool: bool = true) -> void:
	if interaction_state == STATE_COMMITTING or not is_editing or not is_instance_valid(current_editing_shape):
		_reset_state()
		return
		
	interaction_state = STATE_COMMITTING
	var shape: Node2D = current_editing_shape
	is_editing = false
	
	var vrt = shape.get_node_or_null("VectorRichText")
	var display_label: Control = shape.get_node_or_null("DisplayLabel")
	var multi_edit: TextEdit = shape.get_node_or_null("MultiLineEdit")
	
	if vrt:
		if vrt.has_signal("editing_finished") and vrt.editing_finished.is_connected(_on_vrt_editing_finished):
			vrt.editing_finished.disconnect(_on_vrt_editing_finished)
		if vrt.has_signal("text_changed") and vrt.text_changed.is_connected(_on_vrt_text_changed):
			vrt.text_changed.disconnect(_on_vrt_text_changed)
	
	var final_text := ""
	if multi_edit and multi_edit.text != "" and multi_edit.text != str(shape.get_meta("text", "")):
		final_text = multi_edit.text.strip_edges()
	elif vrt and vrt.has_method("get_text") and vrt.get_text() != "":
		final_text = vrt.get_text().strip_edges()
	elif multi_edit:
		final_text = multi_edit.text.strip_edges()
	
	var is_threaded: bool = shape.has_meta("next_paragraph") or shape.has_meta("prev_paragraph")
	# En una cadena, vaciar un marco es legítimo (su tramo sale de la historia).
	if final_text == "" and not is_threaded: final_text = "Texto de párrafo vacío."

	if vrt and vrt.has_method("stop_editing"):
		vrt.stop_editing()
		if multi_edit and multi_edit.text != "" and multi_edit.text != vrt.get_text():
			vrt.set_text(final_text)
		shape.set_meta("runs", vrt.get_runs_meta())

	if is_threaded:
		# Solo se sustituye el tramo de ESTE marco dentro de la historia
		# (con sus runs ajustados al texto final para empalmarlos).
		if vrt == null and multi_edit:
			TextRuns.apply_text_edit(shape, multi_edit.text, final_text)
		ParagraphThreading.replace_frame_text(shape, final_text)
		if display_label:
			display_label.visible = true
			if vrt != null:
				display_label.self_modulate = Color(1, 1, 1, 0)
		final_text = str(shape.get_meta("text", final_text))
	else:
		# Historia vieja de una cadena ya deshecha: un enlace posterior la
		# reviviría en lugar del texto recién editado.
		if shape.has_meta("raw_story_text"):
			shape.remove_meta("raw_story_text")
		if shape.has_meta("story_range"):
			shape.remove_meta("story_range")
		if vrt == null:
			# strip_edges puede quitar espacios del PRINCIPIO: diff por posición.
			var pre: String = multi_edit.text if multi_edit else str(shape.get_meta("text", ""))
			TextRuns.apply_text_edit(shape, pre, final_text)
		shape.set_meta("text", final_text)
		if display_label:
			display_label.text = final_text
			if display_label.has_method("set_rich_runs"):
				display_label.set_rich_runs(shape.get_meta("runs", []))
			display_label.visible = true
			if vrt != null:
				display_label.self_modulate = Color(1, 1, 1, 0)
			# RE-SINCRONIZAR: solo altura (el ancho es del marco).
			_fit_height_to_text(shape, final_text)
	
	if multi_edit:
		multi_edit.text = final_text
		if multi_edit.is_inside_tree():
			multi_edit.release_focus()
		multi_edit.visible = false

	TextCore.register_text_undo(shape, _edit_before, "Editar párrafo")
	_edit_before = {}
	_reset_state()
	if switch_tool and is_instance_valid(shape):
		_switch_to_move_tool(shape)

func _toggle_format_key(key: String) -> void:
	if not is_instance_valid(current_editing_shape):
		return
	var multi_edit: TextEdit = current_editing_shape.get_node_or_null("MultiLineEdit")
	if not multi_edit:
		return
	var sel = TextCore.sel_range(multi_edit)
	var start := 0
	var end := multi_edit.text.length()
	if sel != null and int(sel["end"]) > int(sel["start"]):
		start = int(sel["start"])
		end = int(sel["end"])
	if start >= end:
		return
	var runs := TextRuns.runs_of(current_editing_shape, multi_edit.text.length())
	var all := true
	var pos := 0
	for r in runs:
		var len_: int = int(r.get("length", 0))
		if pos < end and pos + len_ > start and not bool(r.get(key, false)):
			all = false
			break
		pos += len_
	var new_v := not all
	_apply_style_to_range(current_editing_shape, start, end, func(r: Dictionary) -> Dictionary:
		r[key] = new_v
		if key == "bold" and not new_v and int(r.get("weight", 400)) >= 700:
			r.erase("weight")   # quitar negrita también baja un grosor >= 700
		return r)

func _on_format_size_step(delta: float) -> void:
	if not is_instance_valid(current_editing_shape):
		return
	var multi_edit: TextEdit = current_editing_shape.get_node_or_null("MultiLineEdit")
	if not multi_edit:
		return
	var sel = TextCore.sel_range(multi_edit)
	if sel != null and int(sel["end"]) > int(sel["start"]):
		var start := int(sel["start"])
		var end := int(sel["end"])
		_apply_style_to_range(current_editing_shape, start, end, func(r: Dictionary) -> Dictionary:
			var cur: float = float(r.get("size", current_editing_shape.get_meta("font_size", 24)))
			r["size"] = clampf(cur + delta, 4.0, 400.0)
			return r)
	else:
		var cur_fs: int = int(current_editing_shape.get_meta("font_size", 24))
		var new_fs = clampi(cur_fs + int(round(delta)), 4, 400)
		current_editing_shape.set_meta("font_size", new_fs)
		multi_edit.add_theme_font_size_override("font_size", new_fs)
		var dl := current_editing_shape.get_node_or_null("DisplayLabel")
		if dl:
			if dl is WorldTextLabel: dl.world_font_size = new_fs
			else: dl.add_theme_font_size_override("font_size", new_fs)
		_fit_height_to_text(current_editing_shape, multi_edit.text)
		_notify_format_changed()

func _apply_style_to_range(shape: Node2D, start: int, end: int, mutator: Callable) -> void:
	var multi_edit: TextEdit = shape.get_node_or_null("MultiLineEdit")
	if not multi_edit:
		return
	var display_label: Control = shape.get_node_or_null("DisplayLabel")
	var before: Array = (shape.get_meta("runs", []) as Array).duplicate(true)
	var do_fn := func() -> void:
		TextRuns.apply_range(shape, display_label, multi_edit.text.length(), start, end, mutator)
		if display_label and display_label.has_method("apply_stroke_meta"):
			display_label.apply_stroke_meta()
		if multi_edit.syntax_highlighter:
			multi_edit.syntax_highlighter.clear_highlighting_cache()
		var vrt = shape.get_node_or_null("VectorRichText")
		if vrt:
			_safe_set_runs_meta(vrt, shape.get_meta("runs", []))
			vrt.queue_redraw()
		_fit_height_to_text(shape, multi_edit.text)
		_notify_format_changed()
	var undo_fn := func() -> void:
		shape.set_meta("runs", before)
		if display_label and display_label.has_method("set_rich_runs"):
			display_label.set_rich_runs(before)
		if display_label and display_label.has_method("apply_stroke_meta"):
			display_label.apply_stroke_meta()
		if multi_edit.syntax_highlighter:
			multi_edit.syntax_highlighter.clear_highlighting_cache()
		multi_edit.queue_redraw()
		var vrt = shape.get_node_or_null("VectorRichText")
		if vrt:
			_safe_set_runs_meta(vrt, before)
			vrt.queue_redraw()
		_fit_height_to_text(shape, multi_edit.text)
		_notify_format_changed()
	var hm := _get_autoload("HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Formato de Párrafo")
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()

func _on_multi_edit_gui_input(event: InputEvent) -> void:
	if not is_editing or not is_instance_valid(current_editing_shape):
		return
	var multi_edit: TextEdit = current_editing_shape.get_node_or_null("MultiLineEdit")
	if not multi_edit:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			commit_text_edit(true)
			multi_edit.accept_event()
			return
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and event.is_command_or_control_pressed():
			commit_text_edit(true)
			multi_edit.accept_event()
			return
		var cmd: bool = event.is_command_or_control_pressed()
		if cmd:
			if event.alt_pressed and event.keycode in [KEY_PERIOD, KEY_COMMA]:
				# Grosor con teclado: Ctrl+Alt+. más grueso / Ctrl+Alt+, más fino.
				TextCore.weight_step(self, current_editing_shape, multi_edit, 100 if event.keycode == KEY_PERIOD else -100)
				multi_edit.accept_event()
			elif event.keycode == KEY_B:
				_toggle_format_key("bold")
				multi_edit.accept_event()
			elif event.keycode == KEY_I:
				_toggle_format_key("italic")
				multi_edit.accept_event()
			elif event.keycode == KEY_U:
				_toggle_format_key("underline")
				multi_edit.accept_event()
			elif event.keycode == KEY_BRACKETRIGHT or (event.shift_pressed and event.keycode == KEY_PERIOD):
				_on_format_size_step(2.0)
				multi_edit.accept_event()
			elif event.keycode == KEY_BRACKETLEFT or (event.shift_pressed and event.keycode == KEY_COMMA):
				_on_format_size_step(-2.0)
				multi_edit.accept_event()

func _on_multi_edit_caret_changed() -> void:
	if not is_editing:
		return
	_notify_format_changed()

## Recalcula width/height del shape a partir del mínimo real del label
## (en unidades de MUNDO), y re-dimensiona label + MultiLineEdit (que es lo
## que muestra el boundingbox de selección de MoveTool).
func _update_shape_meta_size(shape: Node2D) -> void:
	var vrt = shape.get_node_or_null("VectorRichText")
	var display_label: Control = shape.get_node_or_null("DisplayLabel")
	var multi_edit: Control = shape.get_node_or_null("MultiLineEdit")
	if not display_label and not vrt:
		return
	var w: float = float(shape.get_meta("width", 350.0))
	var txt: String = str(shape.get_meta("text", ""))
	var h: float = 100.0
	if vrt:
		vrt.set_frame_size(Vector2(w, 100000.0))
		var csz: Vector2 = vrt.get_content_size()
		h = maxf(40.0, csz.y)
		vrt.set_frame_size(Vector2(w, h))
		vrt.custom_minimum_size = Vector2(w, h)
		vrt.size = Vector2(w, h)
	elif display_label is WorldTextLabel:
		h = maxf(40.0, display_label.wrapped_content_height(txt))
		display_label.set_world_size(Vector2(w, h))
	else:
		var min_size: Vector2 = display_label.get_combined_minimum_size()
		h = maxf(40.0, min_size.y)
		display_label.custom_minimum_size = Vector2(w, h)
		display_label.size = Vector2(w, h)
	shape.set_meta("width", w)
	shape.set_meta("height", h)
	if display_label:
		if display_label is WorldTextLabel:
			display_label.set_world_size(Vector2(w, h))
		else:
			display_label.custom_minimum_size = Vector2(w, h)
			display_label.size = Vector2(w, h)
	if multi_edit:
		multi_edit.custom_minimum_size = Vector2(w, h)
		multi_edit.size = Vector2(w, h)

func create_at_center() -> Node2D:
	_refresh_artboard()
	if not is_instance_valid(target_artboard):
		var mgr := ArtboardManager.find(get_tree()) if get_tree() else null
		if mgr:
			target_artboard = mgr.get_active_artboard()
	if not is_instance_valid(target_artboard):
		var container = canvas.get_node_or_null("ArtboardsContainer") if is_instance_valid(canvas) else null
		if container and container.get_child_count() > 0:
			target_artboard = container.get_child(0)
	if not is_instance_valid(target_artboard):
		return null
	var ab_size: Vector2 = Vector2(800, 600)
	if "artboard_size" in target_artboard:
		ab_size = target_artboard.artboard_size
	var default_size: Vector2 = Vector2(350, 100)
	var local_pos: Vector2 = (ab_size / 2.0) - (default_size / 2.0)
	return _create_new_paragraph_at(local_pos)

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

	if ClassDB.class_exists("VectorRichText"):
		var vrt = ClassDB.instantiate("VectorRichText")
		vrt.name = "VectorRichText"
		vrt.set_is_paragraph(true)
		TextCore.apply_vrt_fonts(vrt, new_para)
		vrt.set_frame_size(Vector2(350, 100))
		vrt.set_text_color(Color.BLACK)
		vrt.set_font_size(24.0)
		vrt.set_text(new_para.get_meta("text"))
		new_para.add_child(vrt)
		label.visible = true
		label.self_modulate = Color(1, 1, 1, 0)
	
	target_artboard.add_child(new_para)
	new_para.position = local_pos
	_style_multi_edit(edit, label)
	
	# Sincronizar el tamaño del shape con el contenido renderizado del label
	_update_shape_meta_size(new_para)
	
	_switch_to_move_tool(new_para)
	return new_para

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
			if ParagraphThreading.is_point_in_out_port(child, gm, _view_zoom()):
				return child
		var sub := _find_out_port_in_tree(child, gm)
		if sub:
			return sub
	return null

## Zoom de la vista: el puerto mide PORT_SIZE px de PANTALLA (sin esto, a
## zoom alto era enorme y a zoom bajo imposible de clicar).
func _view_zoom() -> float:
	if is_instance_valid(canvas):
		return maxf(canvas.get_canvas_transform().get_scale().x, 0.0002)
	return 1.0

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
				var p_src := c.to_local(ParagraphThreading.get_out_port_rect(child, zoom).get_center())
				var p_dst := c.to_local(nxt.global_position + Vector2(10, 10))
				c.draw_line(p_src, p_dst, Color(0.2, 0.75, 1.0, 0.75), 1.5 * k)
				c.draw_circle(p_dst, 3.5 * k, Color(0.2, 0.75, 1.0, 0.95))

			# 2. Dibujar el puerto de salida / desbordamiento (Out-Port Handle)
			var port_rect_g := ParagraphThreading.get_out_port_rect(child, zoom)
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
		var src_pt := c.to_local(ParagraphThreading.get_out_port_rect(thread_source_frame, zoom).get_center())
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
