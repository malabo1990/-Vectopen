 # =============================================================================
# RUTA: res://script_gdscript/TextTool.gd
# Vectopen — Herramienta de Títulos Avanzada (Edición Síncrona Reparada)
# Soporta: Saltos de línea, Color Negro, Doble Clic Robusto para editar.
# CONTROL INTELIGENTE: CMD (o CTRL) + Arrastre Vertical para escalar fuente.
# =============================================================================
extends ToolBase

# ── Estados Internos de Edición ──────────────────────────────────────────────
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

## Foto del texto al entrar a editar / empezar Cmd+arrastre → undo al confirmar.
var _edit_before: Dictionary = {}
## Texto del editor tras la última pulsación (los runs están sincronizados
## con él): base del diff por posición de apply_text_edit.
var _prev_edit_text: String = ""

## Guarda de reentrancia: rompe el ciclo InspectorCore.changed → aquí →
## GlobalEvents.object_style_changed → InspectorCore._on_event → .changed →
## aquí de nuevo → ... (mismo patrón que ColorCore._applying).
var _is_relaying_style: bool = false

# ── Estados Internos para el Redimensionado Inteligente (CMD+Drag) ────────────
var is_cmd_scaling: bool = false
var scaling_shape: Node2D = null
var scaling_start_mouse_y: float = 0.0
var scaling_start_font_size: int = 24

# ── Estados para Creación con Arrastre estilo Affinity (Medida en Vivo) ───────
var is_drag_creating: bool = false
var drag_start_gpos: Vector2 = Vector2.ZERO
var drag_current_gpos: Vector2 = Vector2.ZERO
var drag_font_size: int = 24

# Configuración del redimensionado
const MIN_FONT_SIZE: int = 8
const MAX_FONT_SIZE: int = 300
const SCALING_SENSITIVITY: float = 0.5

# ── Formato enriquecido por rango (color/negrita/subrayado de una selección) ──
# LIMITACIÓN CONOCIDA v1: los runs se indexan por posición de carácter, no por
# "ancla" que siga el texto. Aplicar formato y LUEGO seguir escribiendo en otro
# punto puede desalinear el rango formateado — cubre bien el caso normal de
# "escribir, seleccionar, dar formato" pero no ediciones entrelazadas complejas.

func activate() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_IBEAM)
	_refresh_artboard()
	if not InspectorCore.changed.is_connected(_on_inspector_changed):
		InspectorCore.changed.connect(_on_inspector_changed)

func deactivate() -> void:
	if is_editing:
		commit_text_edit(false)
	_reset_scaling_state()
	_hover_text = null
	is_drag_creating = false
	if canvas:
		canvas.queue_redraw()
	if InspectorCore.changed.is_connected(_on_inspector_changed):
		InspectorCore.changed.disconnect(_on_inspector_changed)

## El panel de tipografía (clic derecho) escribe en el shape vía InspectorCore
## sin saber que TitleEdit existe — sin esto, cambiar tamaño/familia/color
## mientras se edita no se veía hasta salir y volver a entrar al texto.
func _on_inspector_changed(_props: Dictionary) -> void:
	if _is_relaying_style:
		return   # reentrada desde nuestro propio emit_safe() más abajo — cortar aquí
	if not is_editing or not is_instance_valid(current_editing_shape):
		return
	var title_edit: TextEdit = current_editing_shape.get_node_or_null("TitleEdit")
	var display_label: WorldTextLabel = current_editing_shape.get_node_or_null("DisplayLabel")
	if not title_edit or not display_label:
		return
	var fs: int = int(current_editing_shape.get_meta("font_size", 24))
	title_edit.add_theme_font_size_override("font_size", fs)
	title_edit.add_theme_color_override("font_color", current_editing_shape.get_meta("text_color", Color.BLACK))
	_style_title_edit(title_edit, display_label)
	_update_shape_meta_size(current_editing_shape)
	# InspectorCore ya emitió object_style_changed ANTES de esto (con el meta
	# width/height todavía viejo) — el BoundingBox se sincronizó con el tamaño
	# desactualizado. Lo repetimos ahora que _update_shape_meta_size ya escribió
	# el tamaño real, si no el contorno de selección se queda "congelado" hasta
	# deseleccionar y volver a seleccionar. object_style_changed también rebota
	# de vuelta a InspectorCore._on_event → cambiado.emit() → aquí otra vez: la
	# guarda de arriba corta esa reentrada.
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_method("emit_safe"):
		_is_relaying_style = true
		ge.emit_safe("object_style_changed")
		_is_relaying_style = false

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
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and (event.is_command_or_control_pressed() or not event.shift_pressed):
				commit_text_edit(true)
				return true

	# Hover preview: outline + baseline of the text frame under the pointer
	if event is InputEventMouseMotion and not is_drag_creating and not is_cmd_scaling:
		var hov: Node2D = _shape_at(gm)
		if hov and not String(hov.get_meta("shape_type", "")).begins_with("text"):
			hov = null
		if hov == current_editing_shape:
			hov = null
		if hov != _hover_text:
			_hover_text = hov
			canvas.queue_redraw()

	# 1. DETECCIÓN DE DOBLE CLIC (Restaurado el comportamiento original directo)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		if is_cmd_scaling or is_drag_creating: return true 
		var hit: Node2D = _shape_at(gm)
		if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_title":
			var frame := _edit_frame_for(hit, gm)
			if not is_instance_valid(frame):
				return true
			target_artboard = frame
			_check_and_trigger_edit_at(frame.to_local(gm))
			return true
		elif hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_paragraph":
			if is_editing:
				commit_text_edit(false)
			if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
				canvas.switch_tool("paragraph")
				if canvas.current_tool and canvas.current_tool.has_method("_check_and_trigger_edit_at"):
					var frame := _edit_frame_for(hit, gm)
					if is_instance_valid(frame):
						canvas.current_tool.target_artboard = frame
						canvas.current_tool._check_and_trigger_edit_at(frame.to_local(gm))
			return true

	# 2. GESTIÓN DE CLIC DE RATÓN
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# --- LÓGICA CON CMD / CTRL + DRAG ---
			if Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_CTRL):
				var hit: Node2D = _shape_at(gm)
				if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_title":
					_start_cmd_scaling(hit, gm.y)
					return true

			# Clic Fuera al Editar para guardar cambios y retornar a MoveTool
			if is_editing and is_instance_valid(current_editing_shape):
				var local_pos: Vector2 = current_editing_shape.to_local(gm)
				var size = _get_current_shape_size(current_editing_shape)
				var rect: Rect2 = Rect2(Vector2.ZERO, size)

				if not rect.has_point(local_pos):
					var hit_other: Node2D = _shape_at(gm)
					if hit_other and event.double_click and hit_other.has_meta("shape_type") and hit_other.get_meta("shape_type") == "text_title":
						commit_text_edit(false)
						var frame := _edit_frame_for(hit_other, gm)
						if is_instance_valid(frame):
							target_artboard = frame
							_check_and_trigger_edit_at(frame.to_local(gm))
						return true
					elif hit_other and event.double_click and hit_other.has_meta("shape_type") and hit_other.get_meta("shape_type") == "text_paragraph":
						commit_text_edit(false)
						if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
							canvas.switch_tool("paragraph")
							if canvas.current_tool and canvas.current_tool.has_method("_check_and_trigger_edit_at"):
								var frame := _edit_frame_for(hit_other, gm)
								if is_instance_valid(frame):
									canvas.current_tool.target_artboard = frame
									canvas.current_tool._check_and_trigger_edit_at(frame.to_local(gm))
						return true
					
					var shape_edited: Node2D = current_editing_shape
					commit_text_edit(true)
					if is_instance_valid(hit_other) and hit_other != shape_edited:
						SelectionManager.select(hit_other)
					return true 

				return false

			# Clic en vacío -> Iniciar arrastre estilo Affinity para definir tamaño de fuente interactivo
			if not (Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_CTRL)):
				var hit: Node2D = _shape_at(gm)
				if not hit:
					var t := _artboard_for_point(gm)
					if is_instance_valid(t):
						target_artboard = t
					_start_drag_creation(gm)
					return true
		
		else: # Botón Soltado
			if is_cmd_scaling:
				_confirm_cmd_scaling()
				return true
			if is_drag_creating:
				_finish_drag_creation(gm)
				return true

	# 3. MOVIMIENTO DE RATÓN
	if event is InputEventMouseMotion:
		if is_cmd_scaling:
			_process_cmd_scaling(gm.y)
			return true
		if is_drag_creating:
			_process_drag_creation(gm)
			return true

	return false

# ── Métodos para Edición y Creación ──────────────────────────────────────────

func _check_and_trigger_edit_at(local_pos: Vector2) -> void:
	var gm = target_artboard.to_global(local_pos)
	var hit: Node2D = _shape_at(gm)
	
	if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_title":
		if is_editing:
			commit_text_edit(false)

		is_editing = true
		interaction_state = STATE_EDITING
		current_editing_shape = hit
		_edit_before = WorldTextLabel.capture_text_state(hit)
		SelectionManager.set_active_editing_object(hit)
		# Para que el menú contextual (clic derecho) y su panel de tipografía
		# reflejen ESTE texto mientras se edita — antes no se avisaba a
		# SelectionManager y el panel podía seguir mostrando la selección
		# anterior (o ninguna).
		SelectionManager.select(hit)

		var display_label: Control = hit.get_node_or_null("DisplayLabel")
		var title_edit: TextEdit = WorldTextLabel.ensure_inline_editor(hit)

		if display_label: display_label.visible = false
		if title_edit:
			title_edit.visible = true
			title_edit.text = hit.get_meta("text") if hit.has_meta("text") else ""
			_prev_edit_text = title_edit.text

			var fs = hit.get_meta("font_size") if hit.has_meta("font_size") else 24
			title_edit.add_theme_font_size_override("font_size", fs)

			if display_label is WorldTextLabel:
				_style_title_edit(title_edit, display_label)

			_update_shape_meta_size(hit)
			if title_edit.syntax_highlighter:
				title_edit.syntax_highlighter.clear_highlighting_cache()
			title_edit.queue_redraw()

			# Crecer EN VIVO mientras se escribe (igual que párrafos).
			if not title_edit.text_changed.is_connected(_on_edit_text_changed):
				title_edit.text_changed.connect(_on_edit_text_changed)
			if not title_edit.gui_input.is_connected(_on_title_edit_gui_input):
				title_edit.gui_input.connect(_on_title_edit_gui_input)
			if title_edit.has_signal("caret_changed") and not title_edit.caret_changed.is_connected(_on_title_edit_caret_changed):
				title_edit.caret_changed.connect(_on_title_edit_caret_changed)
			title_edit.grab_focus()
			title_edit.select_all()

		var vrt = hit.get_node_or_null("VectorRichText")
		if vrt == null and ClassDB.class_exists("VectorRichText"):
			vrt = ClassDB.instantiate("VectorRichText")
			vrt.name = "VectorRichText"
			vrt.set_is_paragraph(false)
			var fc = get_node_or_null("/root/FontCore")
			if fc and fc.has_method("get_font"):
				vrt.set_font(fc.get_font(fc.spec_from_node(hit)))
			vrt.set_text_color(hit.get_meta("text_color", Color.BLACK))
			vrt.set_font_size(float(hit.get_meta("font_size", 24)))
			vrt.set_text(hit.get_meta("text", "Título Corporativo"))
			hit.add_child(vrt)
		if vrt:
			vrt.start_editing()
			vrt.select_all()
			if not vrt.text_changed.is_connected(_on_vrt_text_changed):
				vrt.text_changed.connect(_on_vrt_text_changed)
			if not vrt.editing_finished.is_connected(_on_vrt_editing_finished):
				vrt.editing_finished.connect(_on_vrt_editing_finished)

func _on_vrt_editing_finished() -> void:
	commit_text_edit(true)

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
	var title_edit: TextEdit = current_editing_shape.get_node_or_null("TitleEdit")
	if title_edit:
		title_edit.text = new_text
	_update_shape_meta_size(current_editing_shape)
	var ge := _get_autoload("GlobalEvents")
	if ge and ge.has_method("emit_safe"):
		ge.emit_safe("object_transformed")

## Texto cambiado mientras se edita: el BB abraza el contenido en vivo.
func _on_edit_text_changed() -> void:
	if not is_editing or not is_instance_valid(current_editing_shape):
		return
	var display_label: Control = current_editing_shape.get_node_or_null("DisplayLabel")
	var title_edit: TextEdit = current_editing_shape.get_node_or_null("TitleEdit")
	if display_label == null or title_edit == null:
		return
	display_label.text = title_edit.text
	# Runs por POSICIÓN del cambio (no recortando siempre por el final).
	WorldTextLabel.apply_text_edit(current_editing_shape, _prev_edit_text, title_edit.text)
	_prev_edit_text = title_edit.text
	if title_edit.syntax_highlighter:
		title_edit.syntax_highlighter.clear_highlighting_cache()
	title_edit.queue_redraw()
	_update_shape_meta_size(current_editing_shape)
	var ge := _get_autoload("GlobalEvents")
	if ge and ge.has_method("emit_safe"):
		ge.emit_safe("object_transformed")

## Canal único centralizado de confirmación y salida de edición (Vectopen Text Engine)
func commit_text_edit(switch_tool: bool = true) -> void:
	if interaction_state == STATE_COMMITTING or not is_editing or not is_instance_valid(current_editing_shape):
		_reset_state()
		return
		
	interaction_state = STATE_COMMITTING
	var shape: Node2D = current_editing_shape
	is_editing = false

	var display_label: Control = shape.get_node_or_null("DisplayLabel")
	var title_edit: TextEdit = shape.get_node_or_null("TitleEdit")
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt:
		if vrt.has_signal("text_changed") and vrt.text_changed.is_connected(_on_vrt_text_changed):
			vrt.text_changed.disconnect(_on_vrt_text_changed)
		if vrt.has_signal("editing_finished") and vrt.editing_finished.is_connected(_on_vrt_editing_finished):
			vrt.editing_finished.disconnect(_on_vrt_editing_finished)
		vrt.stop_editing()
	
	if title_edit or vrt:
		var final_text = ""
		if title_edit and title_edit.text != "" and title_edit.text != shape.get_meta("text", ""):
			final_text = title_edit.text.strip_edges()
		elif vrt and vrt.has_method("get_text") and vrt.get_text() != "":
			final_text = vrt.get_text().strip_edges()
		elif title_edit:
			final_text = title_edit.text.strip_edges()
		if final_text == "": final_text = "Título Nuevo"
		
		var pre: String = title_edit.text if title_edit and vrt == null else str(shape.get_meta("text", final_text))
		WorldTextLabel.apply_text_edit(shape, pre, final_text)
		shape.set_meta("text", final_text)
		if vrt:
			vrt.set_text(final_text)
			_safe_set_runs_meta(vrt, shape.get_meta("runs", []))
		if display_label:
			display_label.text = final_text
			if display_label is WorldTextLabel:
				display_label.set_rich_runs(shape.get_meta("runs", []))
			display_label.visible = true
			if vrt != null:
				display_label.self_modulate = Color(1, 1, 1, 0)
			
		# Sincronización instantánea de las cajas de colisión y límites visuales
		_update_shape_meta_size(shape)
		
		if title_edit:
			title_edit.release_focus()
			title_edit.visible = false

	WorldTextLabel.register_text_undo(shape, _edit_before, "Editar texto")
	_edit_before = {}
	_reset_state()
	if switch_tool and is_instance_valid(shape):
		_switch_to_move_tool(shape)

func _finish_editing_and_save() -> void:
	commit_text_edit(false)

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
	var local_pos: Vector2 = (ab_size / 2.0) - Vector2(100, 20)
	return _create_new_title_at(local_pos)

func _create_new_title_at(local_pos: Vector2, font_size: int = 24) -> Node2D:
	var new_title = Node2D.new()
	new_title.name = NameUtils.unique_child_name(target_artboard, "Texto")
	new_title.set_meta("shape_type", "text_title")
	new_title.set_meta("text", "Título Corporativo")
	new_title.set_meta("font_size", font_size)
	new_title.set_meta("text_color", Color.BLACK)
	
	var label := WorldTextLabel.new()
	label.name = "DisplayLabel"
	label.base_font_size = font_size
	label.text = new_title.get_meta("text")
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_font_size_override("font_size", font_size)
	
	var edit = TextEdit.new()
	edit.name = "TitleEdit"
	edit.visible = false
	edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	edit.add_theme_color_override("font_color", Color.BLACK)
	edit.add_theme_font_size_override("font_size", font_size)

	new_title.add_child(label)
	new_title.add_child(edit)

	if ClassDB.class_exists("VectorRichText"):
		var vrt = ClassDB.instantiate("VectorRichText")
		vrt.name = "VectorRichText"
		vrt.set_is_paragraph(false)
		var fc = get_node_or_null("/root/FontCore")
		if fc and fc.has_method("get_font"):
			vrt.set_font(fc.get_font(fc.spec_from_node(new_title)))
		vrt.set_text_color(Color.BLACK)
		vrt.set_font_size(float(font_size))
		vrt.set_text(new_title.get_meta("text"))
		new_title.add_child(vrt)
		label.visible = false

	target_artboard.add_child(new_title)
	new_title.position = local_pos
	# Recién ahora `label` está en el árbol (_ready() ya resolvió su fuente
	# real vía FontCore) — copiarla antes daría null y TitleEdit se quedaría
	# con la fuente por defecto de Godot en vez de la del texto renderizado.
	_style_title_edit(edit, label)
	
	# Actualización limpia sin retrasos de frames
	_update_shape_meta_size(new_title)
	_switch_to_move_tool(new_title)
	return new_title

# ── Métodos de Creación por Arrastre estilo Affinity ─────────────────────────

func _start_drag_creation(gm: Vector2) -> void:
	is_drag_creating = true
	drag_start_gpos = gm
	drag_current_gpos = gm
	drag_font_size = 24
	if canvas:
		canvas.queue_redraw()

func _process_drag_creation(gm: Vector2) -> void:
	drag_current_gpos = gm
	var delta: Vector2 = drag_current_gpos - drag_start_gpos
	var drag_dist: float = maxf(absf(delta.y), delta.length() * 0.75)
	drag_font_size = clampi(int(round(drag_dist)), MIN_FONT_SIZE, MAX_FONT_SIZE)
	if canvas:
		canvas.queue_redraw()

func _finish_drag_creation(gm: Vector2) -> void:
	is_drag_creating = false
	var delta: Vector2 = gm - drag_start_gpos
	var final_fs: int = 24
	if delta.length() >= 5.0:
		final_fs = drag_font_size

	var t := _artboard_for_point(drag_start_gpos)
	if is_instance_valid(t):
		target_artboard = t
	if target_artboard:
		var local_pos = target_artboard.to_local(drag_start_gpos)
		_create_new_title_at(local_pos, final_fs)
	if canvas:
		canvas.queue_redraw()

var _hover_text: Node2D = null

func draw_preview(c: Node2D) -> void:
	if not is_instance_valid(c):
		return

	if is_instance_valid(_hover_text) and not is_drag_creating:
		var vp0 := c.get_viewport()
		var z0: float = vp0.get_canvas_transform().get_scale().x if vp0 else 1.0
		var w0: float = 1.5 / maxf(z0, 0.0002)
		var sz: Vector2 = _get_current_shape_size(_hover_text)
		var r := Rect2(c.to_local(_hover_text.global_position), sz)
		var hover_col := Color(0.05, 0.55, 0.91, 1.0)
		c.draw_rect(r, hover_col, false, w0)
		c.draw_line(Vector2(r.position.x, r.end.y), r.end, hover_col, w0 * 2.0)

	if is_drag_creating:
		var vp := c.get_viewport()
		var zoom: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
		zoom = maxf(zoom, 0.0002)
		var k: float = 1.0 / zoom
		var font := ThemeDB.fallback_font

		var start_local := c.to_local(drag_start_gpos)
		var cur_local := c.to_local(drag_current_gpos)

		# 1. Línea base guía elástica estilo Affinity
		var baseline_col := Color(0.2, 0.6, 1.0, 0.85)
		c.draw_line(start_local, Vector2(cur_local.x, start_local.y), baseline_col, 1.5 * k)
		c.draw_line(start_local, cur_local, Color(0.2, 0.6, 1.0, 0.3), 1.0 * k)

		# 2. Previsualización del texto a la medida actual
		var preview_str := "Texto %d pt" % drag_font_size
		var preview_fs := maxi(8, drag_font_size)
		c.draw_string(font, start_local + Vector2(0, preview_fs * 0.9), preview_str, HORIZONTAL_ALIGNMENT_LEFT, -1, preview_fs, Color(0.1, 0.15, 0.2, 0.5))

		# 3. Badge flotante con la medida exacta y definitiva (HUD profesional estilo Affinity)
		var badge_text := "%d pt  (%d px)" % [drag_font_size, int(round(drag_font_size * 1.333))]
		var badge_fs := maxi(10, int(round(12.0 * k)))
		var badge_size := font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_fs)
		var badge_pad := Vector2(8, 4) * k
		var badge_pos := cur_local + Vector2(16, 12) * k
		var badge_rect := Rect2(badge_pos, badge_size + badge_pad * 2.0)

		# Fondo con sombra y borde estilizado
		c.draw_rect(badge_rect.grow(1.5 * k), Color(0, 0, 0, 0.35), true)
		c.draw_rect(badge_rect, Color(0.08, 0.11, 0.16, 0.95), true)
		c.draw_rect(badge_rect, Color(0.25, 0.65, 1.0, 0.9), false, 1.2 * k)

		# Texto del badge
		var text_offset := badge_pos + badge_pad + Vector2(0, badge_fs * 0.82)
		c.draw_string(font, text_offset, badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_fs, Color(0.9, 0.95, 1.0, 1.0))

# ── Métodos para Escalado Inteligente (CMD + Arrastre) ────────────────────────

func _start_cmd_scaling(shape: Node2D, mouse_y: float) -> void:
	is_cmd_scaling = true
	scaling_shape = shape
	scaling_start_mouse_y = mouse_y
	scaling_start_font_size = shape.get_meta("font_size") if shape.has_meta("font_size") else 24
	if not is_editing:   # editando, el undo de la edición ya cubre el tamaño
		_edit_before = WorldTextLabel.capture_text_state(shape)
	Input.set_default_cursor_shape(Input.CURSOR_VSIZE)

func _process_cmd_scaling(current_mouse_y: float) -> void:
	if not is_instance_valid(scaling_shape): 
		_reset_scaling_state()
		return
		
	var delta_y = scaling_start_mouse_y - current_mouse_y
	var font_size_delta = int(delta_y * SCALING_SENSITIVITY)
	var new_font_size = clamp(scaling_start_font_size + font_size_delta, MIN_FONT_SIZE, MAX_FONT_SIZE)
	
	var display_label: Control = scaling_shape.get_node_or_null("DisplayLabel")
	var title_edit: TextEdit = scaling_shape.get_node_or_null("TitleEdit")
	
	if display_label:
		var font_changed: bool = display_label.world_font_size != new_font_size if display_label is WorldTextLabel else display_label.get_theme_font_size("font_size") != new_font_size
		if font_changed:
			if display_label is WorldTextLabel:
				display_label.world_font_size = new_font_size
			else:
				display_label.add_theme_font_size_override("font_size", new_font_size)
			if title_edit: title_edit.add_theme_font_size_override("font_size", new_font_size)
			_update_shape_meta_size(scaling_shape)

func _confirm_cmd_scaling() -> void:
	if is_instance_valid(scaling_shape):
		var display_label: Control = scaling_shape.get_node_or_null("DisplayLabel")
		if display_label:
			var final_fs = display_label.world_font_size if display_label is WorldTextLabel else display_label.get_theme_font_size("font_size")
			scaling_shape.set_meta("font_size", final_fs)
			_update_shape_meta_size(scaling_shape)
		if not is_editing:
			WorldTextLabel.register_text_undo(scaling_shape, _edit_before, "Escalar texto")
			_edit_before = {}
	_reset_scaling_state()

func _reset_scaling_state() -> void:
	is_cmd_scaling = false
	scaling_shape = null
	Input.set_default_cursor_shape(Input.CURSOR_IBEAM)

# ── Utilidades de Cálculo Inmediato ───────────────────────────────────────────

func _update_shape_meta_size(shape: Node2D) -> void:
	var display_label: Control = shape.get_node_or_null("DisplayLabel")
	var title_edit: TextEdit = shape.get_node_or_null("TitleEdit")
	
	if display_label:
		var current_text := ""
		if title_edit and title_edit.visible:
			current_text = title_edit.text
		elif display_label is WorldTextLabel:
			current_text = display_label.text
		elif "text" in display_label:
			current_text = display_label.text
		elif shape.has_meta("text"):
			current_text = str(shape.get_meta("text"))

		var real_size: Vector2 = Vector2.ZERO
		if display_label is WorldTextLabel:
			real_size = display_label.get_world_minimum_size(current_text)
		else:
			real_size = display_label.get_combined_minimum_size()

		# Margen de seguridad para que el cursor y los glifos nunca se corten
		var safe_w: float = maxf(real_size.x + 24.0, 120.0)
		var safe_h: float = maxf(real_size.y + 6.0, 36.0)
		var safe_size := Vector2(safe_w, safe_h)
		
		shape.set_meta("width", safe_size.x)
		shape.set_meta("height", safe_size.y)
		
		if display_label is WorldTextLabel:
			display_label.set_world_size(safe_size)
		else:
			display_label.custom_minimum_size = safe_size
			display_label.size = safe_size
		if title_edit:
			title_edit.custom_minimum_size = safe_size
			title_edit.size = safe_size
			title_edit.scroll_horizontal = 0
		var vrt = shape.get_node_or_null("VectorRichText")
		if vrt:
			vrt.custom_minimum_size = safe_size
			vrt.size = safe_size

func _get_current_shape_size(shape: Node2D) -> Vector2:
	var w: float = shape.get_meta("width") if shape.has_meta("width") else 250.0
	var h: float = shape.get_meta("height") if shape.has_meta("height") else 40.0
	return Vector2(w, h)

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

			# Mutar `selected_shapes` de MoveTool a mano NO avisa a
			# SelectionManager (eso solo pasa por MoveTool._emit_selection_changed,
			# que aquí no se llama) — sin esto, el panel de tipografía/Inspector
			# (clic derecho) podía seguir mostrando la selección anterior en vez
			# de la figura de texto recién creada.
			canvas.change_tool(move_tool)
			# Después de change_tool(): activar MoveTool reconstruye su estado
			# desde SelectionManager y lo deja vacío si se hace antes.
			SelectionManager.select(shape)

func _reset_state() -> void:
	is_editing = false
	current_editing_shape = null
	interaction_state = STATE_IDLE
	SelectionManager.set_active_editing_object(null)

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

## Figura bajo el punto en TODOS los artboards, con rotación/escala (to_local)
## y dentro de grupos — antes solo hijos directos del artboard activo y sin
## transformar, así que un título rotado no se podía editar con doble clic.
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
	return null

func _find_shape_in_tree(node: Node, gpos: Vector2) -> Node2D:
	for i in range(node.get_child_count() - 1, -1, -1):
		var child = node.get_child(i)
		if not (child is Node2D) or child.name in ["Contorno_Stroke", "ArtboardTitle"]:
			continue
		if child.has_meta("shape_type"):
			if Rect2(Vector2.ZERO, _get_current_shape_size(child)).has_point(child.to_local(gpos)):
				return child
		var sub := _find_shape_in_tree(child, gpos)
		if sub:
			return sub
	return null

# ── Formato enriquecido por rango ─────────────────────────────────────────────

## ThemeManager autoload (paleta/tokens de diseño de toda la app).
func _tm():
	var st := Engine.get_main_loop() as SceneTree
	return st.root.get_node_or_null("ThemeManager") if st else null

## Mismo color, a la opacidad `a` — para tintes suaves (relleno de selección,
## fondos de chip) consistentes con el resto de la interfaz.
func _tint(color: Color, a: float) -> Color:
	return Color(color.r, color.g, color.b, a)

func _flat_solid(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(0)
	s.content_margin_left = 0
	s.content_margin_top = 0
	s.content_margin_right = 0
	s.content_margin_bottom = 0
	return s

## Iguala el TextEdit de edición al aspecto REAL del texto ya renderizado
## (misma fuente, sin fondo/borde propio, cursor y selección con los mismos
## tokens de color que el resto de la interfaz — panel de capas incluido)
## para que entrar a editar no cambie el aspecto del texto en el lienzo.
func _style_title_edit(edit: TextEdit, label: WorldTextLabel) -> void:
	var font := label.get_theme_font("font")
	if font:
		edit.add_theme_font_override("font", font)
	var transparent := _flat_solid(Color(0, 0, 0, 0), 0)
	edit.add_theme_stylebox_override("normal", transparent)
	edit.add_theme_stylebox_override("focus", transparent)
	edit.add_theme_stylebox_override("read_only", transparent)
	edit.deselect_on_focus_loss_enabled = false
	if edit.has_method("clear_gutters"):
		edit.clear_gutters()
	edit.scroll_fit_content_height = true
	edit.scroll_past_end_of_file = false
	var tm = _tm()
	var accent: Color = tm.get_color(tm.Slot.ACCENT) if tm else Color(0.0, 0.478, 1.0, 1.0)
	edit.add_theme_color_override("caret_color", accent)
	edit.add_theme_color_override("selection_color", _tint(accent, 0.25))
	var font_col: Color = label.font_color() if label.has_method("font_color") else label.get_theme_color("font_color")
	if font_col.a <= 0.01:
		font_col = Color.BLACK
	edit.add_theme_color_override("font_color", font_col)
	# Alpha 0 en font_selected_color para que Godot use los colores vivos del SyntaxHighlighter bajo la selección
	edit.add_theme_color_override("font_selected_color", Color(0, 0, 0, 0))
	var shape: Node2D = edit.get_parent() as Node2D
	if shape and (edit.syntax_highlighter == null or not (edit.syntax_highlighter is WorldTextLabel.RunHighlighter)):
		edit.syntax_highlighter = WorldTextLabel.RunHighlighter.new(shape)

## Rango [start, end) de la selección actual en TitleEdit, en offsets planos.
## null si no hay selección. Motor centralizado en WorldTextLabel.
func _selection_range(title_edit: TextEdit) -> Variant:
	return WorldTextLabel.sel_range(title_edit)

## Motor de runs centralizado en WorldTextLabel (wrappers de compatibilidad).
func _current_runs(shape: Node2D, text_len: int) -> Array:
	return WorldTextLabel.runs_of(shape, text_len)

func _split_runs_at(runs: Array, cuts: Array) -> Array:
	return WorldTextLabel.split_runs(runs, cuts)

func _merge_equal_runs(runs: Array) -> Array:
	return WorldTextLabel.merge_runs(runs)

func _apply_style_to_range(shape: Node2D, start: int, end: int, mutator: Callable) -> void:
	var title_edit: TextEdit = shape.get_node_or_null("TitleEdit")
	if not title_edit:
		return
	var display_label: Control = shape.get_node_or_null("DisplayLabel")
	var before: Array = (shape.get_meta("runs", []) as Array).duplicate(true)
	var do_fn := func() -> void:
		WorldTextLabel.apply_range(shape, display_label, title_edit.text.length(), start, end, mutator)
		if display_label and display_label.has_method("apply_stroke_meta"):
			display_label.apply_stroke_meta()
		if title_edit.syntax_highlighter:
			title_edit.syntax_highlighter.clear_highlighting_cache()
		title_edit.queue_redraw()
		_update_shape_meta_size(shape)
		_notify_format_changed()
	var undo_fn := func() -> void:
		shape.set_meta("runs", before)
		if display_label and display_label.has_method("set_rich_runs"):
			display_label.set_rich_runs(before)
		if display_label and display_label.has_method("apply_stroke_meta"):
			display_label.apply_stroke_meta()
		if title_edit.syntax_highlighter:
			title_edit.syntax_highlighter.clear_highlighting_cache()
		title_edit.queue_redraw()
		_update_shape_meta_size(shape)
		_notify_format_changed()
	var hm := _get_autoload("HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Formato de Texto")
		hm.add_do(do_fn)
		hm.add_undo(undo_fn)
		hm.commit()
	do_fn.call()

func _resize_runs_to_length(shape: Node2D, new_len: int) -> void:
	WorldTextLabel.resize_runs(shape, new_len)

func _toggle_format_key(key: String) -> void:
	if not is_instance_valid(current_editing_shape):
		return
	var title_edit: TextEdit = current_editing_shape.get_node_or_null("TitleEdit")
	if not title_edit:
		return
	var sel = _selection_range(title_edit)
	var start := 0
	var end := title_edit.text.length()
	if sel != null and int(sel["end"]) > int(sel["start"]):
		start = int(sel["start"])
		end = int(sel["end"])
	if start >= end:
		return
	var runs := _current_runs(current_editing_shape, title_edit.text.length())
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
		return r)

func _on_format_bold_pressed() -> void:
	_toggle_format_key("bold")

func _on_format_italic_pressed() -> void:
	_toggle_format_key("italic")

func _on_format_underline_pressed() -> void:
	_toggle_format_key("underline")

func _on_format_size_step(delta: float) -> void:
	if not is_instance_valid(current_editing_shape):
		return
	var title_edit: TextEdit = current_editing_shape.get_node_or_null("TitleEdit")
	if not title_edit:
		return
	var sel = _selection_range(title_edit)
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
		title_edit.add_theme_font_size_override("font_size", new_fs)
		var dl := current_editing_shape.get_node_or_null("DisplayLabel")
		if dl:
			if dl is WorldTextLabel: dl.world_font_size = new_fs
			else: dl.add_theme_font_size_override("font_size", new_fs)
		_update_shape_meta_size(current_editing_shape)
		_notify_format_changed()

func _on_format_color_changed(color: Color) -> void:
	if not is_instance_valid(current_editing_shape):
		return
	var title_edit: TextEdit = current_editing_shape.get_node_or_null("TitleEdit")
	var sel = _selection_range(title_edit) if title_edit else null
	var start := 0
	var end := title_edit.text.length() if title_edit else 0
	if sel != null and int(sel["end"]) > int(sel["start"]):
		start = int(sel["start"])
		end = int(sel["end"])
	if start >= end:
		return
	_apply_style_to_range(current_editing_shape, start, end, func(r: Dictionary) -> Dictionary:
		r["color"] = color
		return r)

func _on_title_edit_gui_input(event: InputEvent) -> void:
	if not is_editing or not is_instance_valid(current_editing_shape):
		return
	var title_edit: TextEdit = current_editing_shape.get_node_or_null("TitleEdit")
	if not title_edit:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			commit_text_edit(true)
			title_edit.accept_event()
			return
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and (event.is_command_or_control_pressed() or not event.shift_pressed):
			commit_text_edit(true)
			title_edit.accept_event()
			return
		var cmd: bool = event.is_command_or_control_pressed()
		if cmd:
			if event.keycode == KEY_B:
				_on_format_bold_pressed()
				title_edit.accept_event()
			elif event.keycode == KEY_I:
				_on_format_italic_pressed()
				title_edit.accept_event()
			elif event.keycode == KEY_U:
				_on_format_underline_pressed()
				title_edit.accept_event()
			elif event.keycode == KEY_BRACKETRIGHT or (event.shift_pressed and event.keycode == KEY_PERIOD):
				_on_format_size_step(2.0)
				title_edit.accept_event()
			elif event.keycode == KEY_BRACKETLEFT or (event.shift_pressed and event.keycode == KEY_COMMA):
				_on_format_size_step(-2.0)
				title_edit.accept_event()

func _on_title_edit_caret_changed() -> void:
	if not is_editing:
		return
	_notify_format_changed()

func _notify_format_changed() -> void:
	var ic := _get_autoload("InspectorCore")
	if ic and ic.has_signal("changed"):
		ic.changed.emit(ic.current_props())

static func _get_autoload(autoload_name: String) -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	if ml and ml.root:
		return ml.root.get_node_or_null(autoload_name)
	return null

static func _safe_set_runs_meta(vrt, raw_runs) -> void:
	if vrt == null or raw_runs == null:
		return
	var typed_runs: Array[Dictionary] = []
	if raw_runs is Array:
		for r in raw_runs:
			if r is Dictionary:
				typed_runs.append(r)
	vrt.set_runs_meta(typed_runs)
