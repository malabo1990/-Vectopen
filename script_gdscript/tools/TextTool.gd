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
## Guarda de reentrancia: rompe el ciclo InspectorCore.changed → aquí →
## GlobalEvents.object_style_changed → InspectorCore._on_event → .changed →
## aquí de nuevo → ... (mismo patrón que ColorCore._applying).
var _is_relaying_style: bool = false

# ── Estados Internos para el Redimensionado Inteligente (CMD+Drag) ────────────
var is_cmd_scaling: bool = false
var scaling_shape: Node2D = null
var scaling_start_mouse_y: float = 0.0
var scaling_start_font_size: int = 24

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
		_finish_editing_and_save()
	_reset_scaling_state()
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
	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false

	_refresh_artboard()
	if not target_artboard:
		return false

	var gm: Vector2 = canvas.get_global_mouse_position()

	# 1. DETECCIÓN DE DOBLE CLIC (Restaurado el comportamiento original directo)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		if is_cmd_scaling: return true 
		var hit: Node2D = _shape_at(gm)
		if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_title":
			var local_pos = target_artboard.to_local(gm)
			_check_and_trigger_edit_at(local_pos)
			return true

	# 2. GESTIÓN DE CLIC DE RATÓN
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# --- NUEVA LÓGICA CON CMD / CTRL + DRAG ---
			if Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_CTRL):
				var hit: Node2D = _shape_at(gm)
				if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_title":
					_start_cmd_scaling(hit, gm.y)
					return true

			# Clic Fuera al Editar para guardar cambios
			if is_editing and is_instance_valid(current_editing_shape):
				var local_pos: Vector2 = current_editing_shape.to_local(gm)
				var size = _get_current_shape_size(current_editing_shape)
				var rect: Rect2 = Rect2(Vector2.ZERO, size)

				if not rect.has_point(local_pos):
					var saved_shape = current_editing_shape
					_finish_editing_and_save()
					_switch_to_move_tool(saved_shape)
					return true 

				return false

			# Clic en vacío -> Crear nuevo Título
			if not (Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_CTRL)):
				var hit: Node2D = _shape_at(gm)
				if not hit:
					var t := _artboard_for_point(gm)
					if is_instance_valid(t):
						target_artboard = t
					_create_new_title_at(target_artboard.to_local(gm))
					return true
		
		else: # Botón Soltado
			if is_cmd_scaling:
				_confirm_cmd_scaling()
				return true

	# 3. MOVIMIENTO DE RATÓN (Procesado del arrastre vertical)
	if event is InputEventMouseMotion and is_cmd_scaling:
		_process_cmd_scaling(gm.y)
		return true

	return false

# ── Métodos para Edición y Creación ──────────────────────────────────────────

func _check_and_trigger_edit_at(local_pos: Vector2) -> void:
	var gm = target_artboard.to_global(local_pos)
	var hit: Node2D = _shape_at(gm)
	
	if hit and hit.has_meta("shape_type") and hit.get_meta("shape_type") == "text_title":
		if is_editing: _finish_editing_and_save()

		is_editing = true
		current_editing_shape = hit
		# Para que el menú contextual (clic derecho) y su panel de tipografía
		# reflejen ESTE texto mientras se edita — antes no se avisaba a
		# SelectionManager y el panel podía seguir mostrando la selección
		# anterior (o ninguna).
		SelectionManager.select(hit)

		var display_label: Control = hit.get_node_or_null("DisplayLabel")
		var title_edit: TextEdit = hit.get_node_or_null("TitleEdit")

		if display_label: display_label.visible = false
		if title_edit:
			title_edit.visible = true
			title_edit.text = hit.get_meta("text") if hit.has_meta("text") else ""

			var fs = hit.get_meta("font_size") if hit.has_meta("font_size") else 24
			title_edit.add_theme_font_size_override("font_size", fs)

			_update_shape_meta_size(hit)
			title_edit.grab_focus()
			title_edit.select_all()

func _finish_editing_and_save() -> void:
	if not is_instance_valid(current_editing_shape):
		_reset_state()
		return
		
	var display_label: Control = current_editing_shape.get_node_or_null("DisplayLabel")
	var title_edit: TextEdit = current_editing_shape.get_node_or_null("TitleEdit")
	
	if title_edit:
		var final_text = title_edit.text.strip_edges()
		if final_text == "": final_text = "Título Nuevo"
		
		current_editing_shape.set_meta("text", final_text)
		_resize_runs_to_length(current_editing_shape, final_text.length())
		if display_label:
			display_label.text = final_text
			if display_label is WorldTextLabel:
				display_label.set_rich_runs(current_editing_shape.get_meta("runs", []))
			display_label.visible = true
			
		# Sincronización instantánea de las cajas de colisión y límites visuales
		_update_shape_meta_size(current_editing_shape)
		
		title_edit.release_focus()
		title_edit.visible = false

	_reset_state()

func _create_new_title_at(local_pos: Vector2) -> void:
	var new_title = Node2D.new()
	new_title.name = NameUtils.unique_child_name(target_artboard, "Texto")
	new_title.set_meta("shape_type", "text_title")
	new_title.set_meta("text", "Título Corporativo")
	new_title.set_meta("font_size", 24)
	
	var label := WorldTextLabel.new()
	label.name = "DisplayLabel"
	label.base_font_size = 24
	label.text = new_title.get_meta("text")
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_font_size_override("font_size", 24)
	
	var edit = TextEdit.new()
	edit.name = "TitleEdit"
	edit.visible = false
	edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	edit.add_theme_color_override("font_color", Color.BLACK)
	edit.add_theme_font_size_override("font_size", 24)

	new_title.add_child(label)
	new_title.add_child(edit)

	target_artboard.add_child(new_title)
	new_title.position = local_pos
	# Recién ahora `label` está en el árbol (_ready() ya resolvió su fuente
	# real vía FontCore) — copiarla antes daría null y TitleEdit se quedaría
	# con la fuente por defecto de Godot en vez de la del texto renderizado.
	_style_title_edit(edit, label)
	
	# Actualización limpia sin retrasos de frames
	_update_shape_meta_size(new_title)
	_switch_to_move_tool(new_title)

# ── Métodos para Escalado Inteligente (CMD + Arrastre) ────────────────────────

func _start_cmd_scaling(shape: Node2D, mouse_y: float) -> void:
	is_cmd_scaling = true
	scaling_shape = shape
	scaling_start_mouse_y = mouse_y
	scaling_start_font_size = shape.get_meta("font_size") if shape.has_meta("font_size") else 24
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
		# get_combined_minimum_size() devuelve el tamaño requerido de forma síncrona inmediata.
		# Si es un WorldTextLabel, el re-rasterizado de zoom infla el mínimo local:
		# pedimos el mínimo EN UNIDADES DE MUNDO (el de diseño).
		var real_size: Vector2 = display_label.get_world_minimum_size() if display_label is WorldTextLabel else display_label.get_combined_minimum_size()
		var safe_size = Vector2(max(real_size.x, 200.0), max(real_size.y, 40.0))
		
		shape.set_meta("width", safe_size.x)
		shape.set_meta("height", safe_size.y)
		
		if display_label is WorldTextLabel:
			display_label.set_world_size(safe_size)
		else:
			display_label.size = safe_size
		if title_edit: title_edit.size = safe_size

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
	if not target_artboard: return null
	for child in target_artboard.get_children():
		if child is Node2D and child.has_meta("shape_type"):
			var size = _get_current_shape_size(child)
			var r = Rect2(child.global_position, size)
			if r.has_point(gpos):
				return child
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
	s.set_content_margin_all(4)
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
	var tm = _tm()
	var accent: Color = tm.get_color(tm.Slot.ACCENT) if tm else Color(0.0, 0.478, 1.0, 1.0)
	edit.add_theme_color_override("caret_color", accent)
	edit.add_theme_color_override("selection_color", _tint(accent, 0.25))
	edit.add_theme_color_override("font_selected_color", label.get_theme_color("font_color"))

## Offset de carácter plano (como en `text`, con "\n" incluidos) para una
## posición (line, column) de TextEdit.
func _flat_offset(title_edit: TextEdit, line: int, column: int) -> int:
	var offset := 0
	for l in line:
		offset += title_edit.get_line(l).length() + 1
	return offset + column

## Rango [start, end) de la selección actual en TitleEdit, en offsets planos.
## null si no hay selección.
func _selection_range(title_edit: TextEdit) -> Variant:
	if not title_edit.has_selection():
		return null
	var a := _flat_offset(title_edit, title_edit.get_selection_from_line(), title_edit.get_selection_from_column())
	var b := _flat_offset(title_edit, title_edit.get_selection_to_line(), title_edit.get_selection_to_column())
	return {"start": mini(a, b), "end": maxi(a, b)}

## Runs actuales de `shape`, o el único run "legacy" derivado de sus metas de
## estilo de bloque si todavía no tiene `runs` propios (compatibilidad).
func _current_runs(shape: Node2D, text_len: int) -> Array:
	var runs: Array = shape.get_meta("runs", [])
	var total := 0
	for r in runs:
		total += int(r.get("length", 0))
	if not runs.is_empty() and total == text_len:
		return runs
	return [{
		"length": text_len,
		"color": shape.get_meta("text_color", Color.BLACK),
		"bold": int(shape.get_meta("font_weight", 400)) >= 700,
		"italic": bool(shape.get_meta("font_italic", false)),
		"underline": false,
	}]

## Divide `runs` de forma que `start` y `end` caigan EXACTAMENTE en un borde
## de run (sin partir un run por la mitad), para poder mutar solo lo que cae
## dentro de [start, end).
func _split_runs_at(runs: Array, cuts: Array) -> Array:
	var out: Array = []
	var pos := 0
	for r in runs:
		var len_: int = int(r.get("length", 0))
		var seg_start := pos
		var seg_end := pos + len_
		var local_cuts: Array = [seg_start, seg_end]
		for c in cuts:
			if c > seg_start and c < seg_end:
				local_cuts.append(c)
		local_cuts.sort()
		for i in range(local_cuts.size() - 1):
			var a: int = local_cuts[i]
			var b: int = local_cuts[i + 1]
			if b > a:
				var nr: Dictionary = r.duplicate()
				nr["length"] = b - a
				out.append(nr)
		pos = seg_end
	return out

## Fusiona runs consecutivos con estilo idéntico (evita que la lista crezca
## sin control tras varias ediciones de formato).
func _merge_equal_runs(runs: Array) -> Array:
	var out: Array = []
	for r in runs:
		if not out.is_empty():
			var last: Dictionary = out[out.size() - 1]
			if last.get("color", Color.BLACK).is_equal_approx(r.get("color", Color.BLACK)) \
					and bool(last.get("bold", false)) == bool(r.get("bold", false)) \
					and bool(last.get("italic", false)) == bool(r.get("italic", false)) \
					and bool(last.get("underline", false)) == bool(r.get("underline", false)):
				last["length"] = int(last["length"]) + int(r.get("length", 0))
				continue
		out.append(r.duplicate())
	return out

## Aplica `mutator` (recibe y devuelve un Dictionary de run) a cada run
## contenido en [start, end) del texto actualmente en edición, y refresca el
## DisplayLabel al instante.
func _apply_style_to_range(shape: Node2D, start: int, end: int, mutator: Callable) -> void:
	var title_edit: TextEdit = shape.get_node_or_null("TitleEdit")
	if not title_edit:
		return
	var text_len := title_edit.text.length()
	var runs := _current_runs(shape, text_len)
	runs = _split_runs_at(runs, [start, end])
	var out: Array = []
	var pos := 0
	for r in runs:
		var len_: int = int(r.get("length", 0))
		if pos >= start and pos < end:
			out.append(mutator.call(r.duplicate()))
		else:
			out.append(r)
		pos += len_
	out = _merge_equal_runs(out)
	shape.set_meta("runs", out)
	var display_label: Control = shape.get_node_or_null("DisplayLabel")
	if display_label is WorldTextLabel:
		display_label.set_rich_runs(out)

## Reajusta `runs` (si existen) para que sumen EXACTAMENTE `new_len`
## caracteres — el texto pudo crecer/encogerse mientras se editaba (escribir,
## borrar, o el strip_edges() final). Se recorta/extiende por el final.
func _resize_runs_to_length(shape: Node2D, new_len: int) -> void:
	var runs: Array = shape.get_meta("runs", [])
	if runs.is_empty():
		return
	var total := 0
	for r in runs:
		total += int(r.get("length", 0))
	if total == new_len:
		return
	var out: Array = []
	var acc := 0
	for r in runs:
		var len_: int = int(r.get("length", 0))
		if acc >= new_len:
			break
		var take: int = mini(len_, new_len - acc)
		if take > 0:
			var nr: Dictionary = r.duplicate()
			nr["length"] = take
			out.append(nr)
			acc += take
	if acc < new_len and not out.is_empty():
		out[out.size() - 1]["length"] = int(out[out.size() - 1]["length"]) + (new_len - acc)
	shape.set_meta("runs", out)

func _on_format_bold_pressed() -> void:
	if not is_instance_valid(current_editing_shape):
		return
	var title_edit: TextEdit = current_editing_shape.get_node_or_null("TitleEdit")
	var sel = _selection_range(title_edit) if title_edit else null
	if sel == null:
		return
	# Toggle real: si TODO el rango ya está en negrita, la quita; si no, la pone.
	var runs := _current_runs(current_editing_shape, title_edit.text.length())
	var all_bold := true
	var pos := 0
	for r in runs:
		var len_: int = int(r.get("length", 0))
		if pos < sel["end"] and pos + len_ > sel["start"] and not bool(r.get("bold", false)):
			all_bold = false
		pos += len_
	var new_bold := not all_bold
	_apply_style_to_range(current_editing_shape, sel["start"], sel["end"], func(r: Dictionary) -> Dictionary:
		r["bold"] = new_bold
		return r)

func _on_format_underline_pressed() -> void:
	if not is_instance_valid(current_editing_shape):
		return
	var title_edit: TextEdit = current_editing_shape.get_node_or_null("TitleEdit")
	var sel = _selection_range(title_edit) if title_edit else null
	if sel == null:
		return
	var runs := _current_runs(current_editing_shape, title_edit.text.length())
	var all_u := true
	var pos := 0
	for r in runs:
		var len_: int = int(r.get("length", 0))
		if pos < sel["end"] and pos + len_ > sel["start"] and not bool(r.get("underline", false)):
			all_u = false
		pos += len_
	var new_u := not all_u
	_apply_style_to_range(current_editing_shape, sel["start"], sel["end"], func(r: Dictionary) -> Dictionary:
		r["underline"] = new_u
		return r)

func _on_format_color_changed(color: Color) -> void:
	if not is_instance_valid(current_editing_shape):
		return
	var title_edit: TextEdit = current_editing_shape.get_node_or_null("TitleEdit")
	var sel = _selection_range(title_edit) if title_edit else null
	if sel == null:
		return
	_apply_style_to_range(current_editing_shape, sel["start"], sel["end"], func(r: Dictionary) -> Dictionary:
		r["color"] = color
		return r)
