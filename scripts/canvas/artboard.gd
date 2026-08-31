# ==========================================
# RUTA: res://scripts/canvas/artboard.gd
# ==========================================
extends Node2D
class_name ArtboardEditor

@export var artboard_size := Vector2(794, 1123):  # A4 a 96dpi
	set(v):
		artboard_size = v
		queue_redraw()

var is_selected := false:
	set(v):
		is_selected = v
		queue_redraw()

const BORDER_MARGIN := 12.0
const HANDLE_SIZE   := 8.0

const COLOR_BG_SHEET      := Color(1, 1, 1, 1)
const COLOR_BORDER_NORMAL := Color(0.71, 0.71, 0.71, 0.5)
const COLOR_BORDER_ACTIVE := Color(0.61, 0.61, 0.61, 1.0)
const COLOR_HANDLE_FILL   := Color(1, 1, 1, 1)
const COLOR_GUIDE_LINES   := Color(0.61, 0.61, 0.61, 0.7)
const COLOR_PILL_BG       := Color(0.14, 0.16, 0.18, 0.85)

# Estados de control interno
var _mode: String            = ""
var _resize_edge: Vector2    = Vector2.ZERO
var _drag_start_mouse: Vector2
var _drag_start_pos: Vector2

# ── STREAMING: dormir/despertar ──────────────────────────────────────────────
# Un artboard DORMIDO no tiene sus figuras instanciadas: las guarda como datos
# (formato de CanvasSerializer). Ahorra memoria y hace la carga O(páginas).
# El ArtboardStreamer las despierta al acercarse el viewport.
const _CS = preload("res://scripts/canvas/canvas_serializer.gd")
## Figuras instanciadas por frame al despertar (amortiza el tirón: 100 figuras
## de golpe = ~110 ms; a WAKE_BUDGET/frame se reparte en varios frames).
const WAKE_BUDGET := 20
var is_dormant: bool = false
var _dormant: Array = []
## Fuente perezosa a nivel de archivo: {"vtc": ruta, "off", "len", "rlen"}. El
## contenido de la página no se lee del .vtc hasta que despierta.
var _lazy_src: Dictionary = {}
var _waking_queue: Array = []
var _is_edited: bool = false   # tocado desde la última carga (ver streaming/undo)
var _restoring: bool = false   # true mientras wake()/set_dormant reconstruye

func _ready() -> void:
	add_to_group("artboards")
	_verificar_y_crear_titulo()
	# Cualquier alta/baja de figura marca la página como editada (salvo durante
	# wake/sleep). Sirve para no dormirla mientras su undo siga vivo.
	child_entered_tree.connect(_on_content_changed)
	child_exiting_tree.connect(_on_content_changed)
	queue_redraw()

func _on_content_changed(nodo: Node) -> void:
	if _restoring or nodo.name == "ArtboardTitle":
		return
	_is_edited = true

## Rect del artboard en coordenadas de mundo (sin escala ni rotación).
func world_rect() -> Rect2:
	return Rect2(global_position, artboard_size)

# ── API de streaming ────────────────────────────────────────────────────────
func dormant_content() -> Array:
	if _dormant.is_empty() and not _lazy_src.is_empty():
		_resolve_lazy()
	return _dormant

func has_pending_wake() -> bool:
	return not _waking_queue.is_empty()

func pending_wake_data() -> Array:
	return _waking_queue

## Marca el artboard como dormido con este contenido (usado al CARGAR).
func set_dormant_content(elements: Array) -> void:
	_dormant = elements
	_lazy_src = {}
	is_dormant = true

## Marca el artboard como dormido con una fuente perezosa en el .vtc.
## `loc` = {off, len, rlen}: posición del chunk en la región de datos del .vtc.
func set_lazy_source(vtc_path: String, loc: Dictionary) -> void:
	_lazy_src = {"vtc": vtc_path, "off": int(loc.get("off", 0)),
		"len": int(loc.get("len", 0)), "rlen": int(loc.get("rlen", 0))}
	_dormant = []
	is_dormant = true

## Fuente perezosa actual ({} si ya se resolvió o nunca la hubo). CanvasSerializer
## la usa para copiar el chunk byte a byte al guardar si la página nunca despertó.
func get_lazy_source() -> Dictionary:
	return _lazy_src

## Lee (una vez) el contenido de la fuente perezosa a `_dormant`. Un seek directo
## en el .vtc (handle de lectura cacheado por documento) → O(1).
func _resolve_lazy() -> void:
	if _lazy_src.is_empty():
		return
	var raw := _CS.read_vtc_chunk_raw(_lazy_src.get("vtc", ""), _lazy_src.get("off", 0),
		_lazy_src.get("len", 0), _lazy_src.get("rlen", 0))
	if not raw.is_empty():
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Array:
			_dormant = parsed
	_lazy_src = {}

func mark_edited() -> void:
	_is_edited = true

func is_edited() -> bool:
	return _is_edited

func clear_edited() -> void:
	_is_edited = false

## Serializa las figuras, las libera y pasa a dormido. No duerme si ya está
## dormido, si está seleccionado, o si alguna figura suya está seleccionada
## (evita liberar un nodo al que MoveTool tiene una referencia viva).
func sleep() -> void:
	if is_dormant or is_selected or _tiene_figura_seleccionada():
		return
	# Si esta página fue editada y todavía hay historial de undo, sus nodos
	# están referenciados por callables de HistoryManager → no dormir (dejaría
	# el undo sin efecto). Al cargar/limpiar historial, can_undo() pasa a false
	# y la página puede dormir de nuevo.
	if _is_edited:
		var h := get_node_or_null("/root/HistoryManager")
		if h and h.has_method("can_undo") and h.can_undo():
			return
	# Contenido = figuras instanciadas + las que aún estaban en cola de wake.
	_dormant = _CS.serialize_elements(self)
	if not _waking_queue.is_empty():
		_dormant.append_array(_waking_queue)
		_waking_queue = []
		set_process(false)
	# Detach inmediato + free diferido: el árbol queda limpio ya (sin choques
	# de nombres al despertar) y la memoria se libera al final del frame.
	for child in get_children():
		if child.name == "ArtboardTitle" or child.name == "Contorno_Stroke":
			continue
		remove_child(child)
		child.queue_free()
	is_dormant = true
	queue_redraw()

func _tiene_figura_seleccionada() -> bool:
	for child in get_children():
		if child.get("is_selected") == true:
			return true
	return false

## Reinstancia las figuras guardadas (repartido en varios frames) y pasa a
## despierto. `immediate = true` las crea todas de golpe (guardado, tests).
func wake(immediate: bool = false) -> void:
	if not is_dormant:
		return
	if _dormant.is_empty() and not _lazy_src.is_empty():
		_resolve_lazy()   # leer el chunk del .vtc
	is_dormant = false
	if not has_node("ArtboardTitle"):
		_verificar_y_crear_titulo()
	if immediate or _dormant.size() <= WAKE_BUDGET:
		_restoring = true
		_CS.instantiate_elements(self, _dormant)
		_restoring = false
		_dormant = []
		queue_redraw()
		return
	# Amortizado: encolar y drenar en _process
	_waking_queue = _dormant
	_dormant = []
	set_process(true)

## Fuerza la materialización total AHORA (p.ej. antes de serializar para guardar,
## o al seleccionar contenido de la página).
func wake_now() -> void:
	if is_dormant:
		wake(true)
	elif not _waking_queue.is_empty():
		_restoring = true
		_CS.instantiate_elements(self, _waking_queue)
		_restoring = false
		_waking_queue = []
		set_process(false)
		queue_redraw()

func _process(_delta: float) -> void:
	if _waking_queue.is_empty():
		set_process(false)
		return
	var batch: Array = _waking_queue.slice(0, WAKE_BUDGET)
	_waking_queue = _waking_queue.slice(WAKE_BUDGET)
	_restoring = true
	_CS.instantiate_elements(self, batch)
	_restoring = false
	queue_redraw()
	if _waking_queue.is_empty():
		set_process(false)

func _is_selection_tool() -> bool:
	var scene := get_tree().current_scene if get_tree() else null
	var canvas := scene.find_child("Canvas", true, false) if scene else null
	if not canvas or canvas.current_tool == null:
		return true
	var path: String = canvas.current_tool.get_script().resource_path.get_file().to_lower()
	return "move_tool" in path or "select_tool" in path

func _unhandled_input(event: InputEvent) -> void:
	# El manejo general del ratón global para deseleccionar o arrastrar si ya está activo
	var global_mouse := get_global_mouse_position()
	var local_mouse := to_local(global_mouse)
	var total_rect := Rect2(Vector2.ZERO, artboard_size)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Si está seleccionado y se usan herramientas de selección, permitimos arrastre/redimensionado
			if is_selected and _is_selection_tool():
				if is_on_handle(local_mouse):
					var edge := get_resize_edge(local_mouse)
					if edge != Vector2.ZERO:
						_mode = "resize"
						_resize_edge = edge
						get_viewport().set_input_as_handled()
						return
				
				if total_rect.has_point(local_mouse):
					_mode = "drag"
					_drag_start_mouse = global_mouse
					_drag_start_pos = global_position
					get_viewport().set_input_as_handled()
					return
			
			# REGLA: Si hace click fuera del cuerpo del Artboard y sus márgenes, se DESACTIVAS automáticamente
			if not total_rect.grow(BORDER_MARGIN).has_point(local_mouse):
				if is_selected:
					is_selected = false
					_mode = ""
		else:
			if _mode != "":
				_handle_release()
				get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _mode != "":
		_handle_motion(global_mouse)
		get_viewport().set_input_as_handled()

# ─────────────────────────────────────────────────────────────────────────────
# Activación por Doble Clic en el Título
# ─────────────────────────────────────────────────────────────────────────────
func _on_title_gui_input(event: InputEvent) -> void:
	# Captura el doble click específico en el Label del título
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		var manager = ArtboardManager.find(get_tree()) if get_tree() else null
		if manager and manager.has_method("set_active_artboard"):
			manager.set_active_artboard(self)
		else:
			is_selected = true
		get_viewport().set_input_as_handled()

func _handle_release() -> void:
	_mode = ""
	_resize_edge = Vector2.ZERO

func _handle_motion(global_mouse: Vector2) -> void:
	match _mode:
		"drag":
			global_position = _drag_start_pos + (global_mouse - _drag_start_mouse)
		"resize":
			_apply_resize(_resize_edge, global_mouse)

func _apply_resize(edge: Vector2, new_global_mouse: Vector2) -> void:
	var new_w := artboard_size.x
	var new_h := artboard_size.y

	if edge.x > 0:
		new_w = max(100.0, to_local(new_global_mouse).x)
	elif edge.x < 0:
		var delta_x := new_global_mouse.x - global_position.x
		var pot_w   := artboard_size.x - delta_x
		if pot_w >= 100.0:
			new_w = pot_w
			global_position.x = new_global_mouse.x

	if edge.y > 0:
		new_h = max(100.0, to_local(new_global_mouse).y)
	elif edge.y < 0:
		var delta_y := new_global_mouse.y - global_position.y
		var pot_h   := artboard_size.y - delta_y
		if pot_h >= 100.0:
			new_h = pot_h
			global_position.y = new_global_mouse.y

	artboard_size = Vector2(new_w, new_h)

# ─────────────────────────────────────────────────────────────────────────────
# Métodos Auxiliares y Renderizado
# ─────────────────────────────────────────────────────────────────────────────
func get_handle_positions() -> Array[Vector2]:
	var w := artboard_size.x
	var h := artboard_size.y
	return [
		Vector2(0,   0), Vector2(w/2, 0), Vector2(w,   0),
		Vector2(0, h/2),                  Vector2(w, h/2),
		Vector2(0,   h), Vector2(w/2, h), Vector2(w,   h)
	]

func get_resize_edge(local_pos: Vector2) -> Vector2:
	var edge := Vector2.ZERO
	if   abs(local_pos.x - artboard_size.x) < BORDER_MARGIN: edge.x =  1.0
	elif abs(local_pos.x)                   < BORDER_MARGIN: edge.x = -1.0
	if   abs(local_pos.y - artboard_size.y) < BORDER_MARGIN: edge.y =  1.0
	elif abs(local_pos.y)                   < BORDER_MARGIN: edge.y = -1.0
	return edge

func is_on_handle(local_pos: Vector2) -> bool:
	for hp in get_handle_positions():
		if local_pos.distance_to(hp) < HANDLE_SIZE * 1.6:
			return true
	return false

func _draw() -> void:
	var w := artboard_size.x
	var h := artboard_size.y

	# Sombra
	for i in range(4, 0, -1):
		draw_rect(Rect2(Vector2(0, i * 0.5), artboard_size).grow(i * 0.3), Color(0, 0, 0, 0.01 * (5 - i)), true)

	# Papel Base
	draw_rect(Rect2(Vector2.ZERO, artboard_size), COLOR_BG_SHEET, true)

	if is_selected and _is_selection_tool():
		draw_rect(Rect2(Vector2.ZERO, artboard_size), COLOR_BORDER_ACTIVE, false, 1.0)
		_draw_corner_guides(w, h)
		for hp in get_handle_positions():
			var hr := Rect2(hp - Vector2(HANDLE_SIZE, HANDLE_SIZE) * 0.5, Vector2(HANDLE_SIZE, HANDLE_SIZE))
			draw_rect(hr, COLOR_HANDLE_FILL, true)
			draw_rect(hr, COLOR_BORDER_ACTIVE, false, 1.0)
	else:
		draw_rect(Rect2(Vector2.ZERO, artboard_size), COLOR_BORDER_NORMAL, false, 1.0)

	_draw_dimension_pill(w, h)

func _draw_corner_guides(w: float, h: float) -> void:
	var gl := 14.0
	var go := 6.0
	draw_line(Vector2(-go - gl, 0),  Vector2(-go, 0),         COLOR_GUIDE_LINES, 1.0)
	draw_line(Vector2(0, -go - gl),  Vector2(0, -go),         COLOR_GUIDE_LINES, 1.0)
	draw_line(Vector2(w + go, 0),    Vector2(w + go + gl, 0),  COLOR_GUIDE_LINES, 1.0)
	draw_line(Vector2(w, -go - gl),  Vector2(w, -go),         COLOR_GUIDE_LINES, 1.0)
	draw_line(Vector2(-go - gl, h),  Vector2(-go, h),         COLOR_GUIDE_LINES, 1.0)
	draw_line(Vector2(0, h + go),    Vector2(0, h + go + gl),  COLOR_GUIDE_LINES, 1.0)
	draw_line(Vector2(w + go, h),    Vector2(w + go + gl, h),  COLOR_GUIDE_LINES, 1.0)
	draw_line(Vector2(w, h + go),    Vector2(w, h + go + gl),  COLOR_GUIDE_LINES, 1.0)

func _draw_dimension_pill(w: float, h: float) -> void:
	var font      := ThemeDB.fallback_font
	var font_size := 11
	var label     := "%d × %d" % [w, h]
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var padding   := Vector2(10, 4)
	var pill_size := text_size + padding * 2
	var pill_pos  := Vector2((w - pill_size.x) / 2.0, h + 14)
	draw_rect(Rect2(pill_pos, pill_size), COLOR_PILL_BG, true)
	draw_string(font, pill_pos + padding + Vector2(0, font.get_ascent(font_size) - 1),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.88, 0.89, 0.91))

# ─────────────────────────────────────────────────────────────────────────────
# Exportación (llamado por ImportExportManager — antes NO EXISTÍA, causaba
# "Nonexistent function 'export_to_svg'/'export_to_png'" al exportar SVG/PNG)
# ─────────────────────────────────────────────────────────────────────────────

## Recorre recursivamente los hijos del artboard y arma un documento SVG.
## Las herramientas reales (CircleTool, RectangleTool, brushtool) crean
## Polygon2D/Line2D/Path2D directamente, NO las clases VectorRectangle/
## VectorCircle/VectorPath — por eso hay un fallback genérico por tipo de
## nodo además del has_method("to_svg") (que sí cubre esas clases, por si
## se llegan a usar más adelante).
func export_to_svg(path: String) -> String:
	var body := ""
	for child in get_children():
		body += _node_to_svg(child)

	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%f" height="%f" viewBox="0 0 %f %f">\n%s</svg>\n' % [
		artboard_size.x, artboard_size.y, artboard_size.x, artboard_size.y, body
	]

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(svg)
		file.close()
	else:
		push_error("Artboard.export_to_svg: no se pudo abrir %s para escritura" % path)

	return svg

func _node_to_svg(node: Node) -> String:
	if node.has_method("to_svg"):
		return "  " + node.to_svg() + "\n"

	if node is Polygon2D:
		var pts: PackedVector2Array = node.polygon
		if pts.size() >= 3:
			var points_str := ""
			for p in pts:
				points_str += "%f,%f " % [node.position.x + p.x, node.position.y + p.y]
			return '  <polygon points="%s" fill="%s" />\n' % [points_str.strip_edges(), node.color.to_html()]
		return ""

	if node is Line2D:
		var pts: PackedVector2Array = node.points
		if pts.size() >= 2:
			var points_str := ""
			for p in pts:
				points_str += "%f,%f " % [node.position.x + p.x, node.position.y + p.y]
			return '  <polyline points="%s" fill="none" stroke="%s" stroke-width="%f" stroke-linecap="round" stroke-linejoin="round" />\n' % [
				points_str.strip_edges(), node.default_color.to_html(), node.width
			]
		return ""

	if node is Path2D and node.curve and node.curve.point_count >= 2:
		var baked: PackedVector2Array = node.curve.get_baked_points()
		if baked.size() >= 2:
			var d := "M %f,%f " % [node.position.x + baked[0].x, node.position.y + baked[0].y]
			for i in range(1, baked.size()):
				d += "L %f,%f " % [node.position.x + baked[i].x, node.position.y + baked[i].y]
			return '  <path d="%s" fill="none" stroke="black" stroke-width="2" />\n' % d
		return ""

	return ""

## Renderiza el artboard a un PNG usando un SubViewport temporal — necesita
## esperar al menos un frame para que el viewport realmente dibuje antes de
## capturar la textura, por eso es una función async (await).
func export_to_png(path: String, png_scale: float = 1.0) -> void:
	var sub_viewport := SubViewport.new()
	sub_viewport.size = Vector2i(artboard_size * png_scale)
	sub_viewport.transparent_bg = false
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# El artboard "de verdad" se queda intacto en el canvas — duplicamos
	# para renderizar en el viewport offscreen sin tocar lo que el usuario
	# está editando.
	var artboard_copy := duplicate() as Node2D
	artboard_copy.position = Vector2.ZERO
	if artboard_copy is ArtboardEditor:
		(artboard_copy as ArtboardEditor).is_selected = false  # no queremos handles/guías en el export
	artboard_copy.scale = Vector2(png_scale, png_scale)

	sub_viewport.add_child(artboard_copy)
	add_child(sub_viewport)

	# Dos frames de margen: uno para que el SubViewport entre al árbol y
	# procese _ready()/_draw() de sus hijos, otro para que el frame ya
	# renderizado quede reflejado en la textura antes de leerla.
	await get_tree().process_frame
	await get_tree().process_frame

	var image: Image = sub_viewport.get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		push_error("Artboard.export_to_png: save_png falló (%d) para %s" % [err, path])

	sub_viewport.queue_free()

## Crea y agrega una nueva Layer vacía a este artboard. Usado por
## Layer.copy_to() (scripts/ui/layer.gd) — antes no existía, esa llamada
## está protegida con has_method() así que no crasheaba, pero copiar una
## capa a otro artboard no hacía nada silenciosamente.
func create_layer(layer_display_name: String) -> Layer:
	var layer := Layer.new()
	layer.layer_id = "layer_%d_%d" % [Time.get_ticks_msec(), get_child_count()]
	layer.layer_name = layer_display_name
	add_child(layer)
	GlobalEvents.layer_created.emit()
	return layer

## Estado serializable del artboard y su contenido, para export JSON.
func get_state() -> Dictionary:
	var shapes: Array = []
	for child in get_children():
		if child.has_method("get_state"):
			shapes.append(child.get_state())
	return {
		"type": "artboard",
		"size": {"x": artboard_size.x, "y": artboard_size.y},
		"position": {"x": position.x, "y": position.y},
		"shapes": shapes,
	}

# ─────────────────────────────────────────────────────────────────────────────
# Importación (llamado por ImportExportManager — antes NO EXISTÍA, mismo bug
# que export_to_svg/export_to_png: "Nonexistent function" al importar)
# ─────────────────────────────────────────────────────────────────────────────

## Parser SVG con XMLParser (nativo de Godot, sin dependencias externas).
## Cubre rect/ellipse/circle/polygon/polyline/path — soporta round-trip
## completo de lo que produce nuestro propio export_to_svg. Un SVG externo
## complejo (gradientes, transforms anidados, curvas bezier reales en <path>)
## no se importa fielmente — ver _parse_svg_path_d.
func import_svg(file_path: String) -> void:
	var parser := XMLParser.new()
	var err := parser.open(file_path)
	if err != OK:
		push_error("Artboard.import_svg: no se pudo abrir %s (error %d)" % [file_path, err])
		return

	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var attrs := _read_svg_attributes(parser)
		match parser.get_node_name():
			"rect":
				_import_svg_rect(attrs)
			"ellipse":
				_import_svg_ellipse(attrs)
			"circle":
				_import_svg_circle(attrs)
			"path":
				_import_svg_path(attrs)
			"polygon":
				_import_svg_polygon(attrs, true)
			"polyline":
				_import_svg_polygon(attrs, false)
	queue_redraw()

func _read_svg_attributes(parser: XMLParser) -> Dictionary:
	var attrs := {}
	for i in range(parser.get_attribute_count()):
		attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
	return attrs

func _svg_color(attrs: Dictionary, key: String, default_color: Color) -> Color:
	if not attrs.has(key):
		return default_color
	var value: String = attrs[key]
	if value.is_empty() or value == "none":
		return Color(0, 0, 0, 0)
	return Color(value)

func _import_svg_rect(attrs: Dictionary) -> void:
	var x := float(attrs.get("x", "0"))
	var y := float(attrs.get("y", "0"))
	var w := float(attrs.get("width", "0"))
	var h := float(attrs.get("height", "0"))
	if w <= 0.0 or h <= 0.0:
		return
	var poly := Polygon2D.new()
	poly.name = "Rect_Importado_%d" % get_child_count()
	poly.polygon = PackedVector2Array([
		Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)
	])
	poly.color = _svg_color(attrs, "fill", Color.WHITE)
	add_child(poly)

func _import_svg_ellipse(attrs: Dictionary) -> void:
	_add_ellipse_polygon(
		float(attrs.get("cx", "0")), float(attrs.get("cy", "0")),
		float(attrs.get("rx", "0")), float(attrs.get("ry", "0")),
		_svg_color(attrs, "fill", Color.WHITE)
	)

func _import_svg_circle(attrs: Dictionary) -> void:
	var r := float(attrs.get("r", "0"))
	_add_ellipse_polygon(
		float(attrs.get("cx", "0")), float(attrs.get("cy", "0")), r, r,
		_svg_color(attrs, "fill", Color.WHITE)
	)

func _add_ellipse_polygon(cx: float, cy: float, rx: float, ry: float, fill: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	const SEGMENTS := 64
	var pts := PackedVector2Array()
	for i in range(SEGMENTS):
		var angle: float = TAU * float(i) / float(SEGMENTS)
		pts.append(Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry))
	var poly := Polygon2D.new()
	poly.name = "Ellipse_Importada_%d" % get_child_count()
	poly.polygon = pts
	poly.color = fill
	add_child(poly)

func _import_svg_polygon(attrs: Dictionary, closed: bool) -> void:
	if not attrs.has("points"):
		return
	var pts := _parse_svg_points(attrs["points"])
	if pts.size() < 2:
		return
	if closed:
		var poly := Polygon2D.new()
		poly.name = "Polygon_Importado_%d" % get_child_count()
		poly.polygon = pts
		poly.color = _svg_color(attrs, "fill", Color.WHITE)
		add_child(poly)
	else:
		var line := Line2D.new()
		line.name = "Polyline_Importada_%d" % get_child_count()
		line.points = pts
		line.default_color = _svg_color(attrs, "stroke", Color.BLACK)
		line.width = float(attrs.get("stroke-width", "2"))
		add_child(line)

func _parse_svg_points(points_str: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cleaned := points_str.strip_edges().replace(",", " ")
	var parts := cleaned.split(" ", false)
	var i := 0
	while i + 1 < parts.size():
		pts.append(Vector2(float(parts[i]), float(parts[i + 1])))
		i += 2
	return pts

func _import_svg_path(attrs: Dictionary) -> void:
	if not attrs.has("d"):
		return
	var pts := _parse_svg_path_d(attrs["d"])
	if pts.size() < 2:
		return
	var line := Line2D.new()
	line.name = "Path_Importado_%d" % get_child_count()
	line.points = pts
	line.default_color = _svg_color(attrs, "stroke", Color.BLACK)
	var stroke_width_str: String = attrs.get("stroke-width", "2")
	line.width = float(stroke_width_str) if not stroke_width_str.is_empty() else 2.0
	add_child(line)

## Soporta M/L/Z — exactamente lo que produce nuestro propio export_to_svg
## (ver _node_to_svg). NO soporta curvas C/Q/A: un <path> con curvas bezier
## reales de un SVG externo (Illustrator, Inkscape, etc.) se importaría
## como los segmentos rectos entre los puntos de control listados, no como
## una traza fiel de la curva — suficiente para round-trip propio, no para
## import general de SVGs arbitrarios.
func _parse_svg_path_d(d: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var tokens := d.strip_edges().split(" ", false)
	var i := 0
	while i < tokens.size():
		var token: String = tokens[i]
		if token == "M" or token == "L":
			i += 1
			if i < tokens.size():
				var coords := tokens[i].split(",")
				if coords.size() == 2:
					pts.append(Vector2(float(coords[0]), float(coords[1])))
		i += 1
	return pts

## NO es un trazado vectorial real (sin detección de contornos/edge-tracing)
## — carga la imagen como Sprite2D para que el import no falle, y avisa
## claramente que no se vectorizó de verdad. Implementar tracing real
## (Illustrator "Image Trace") es un algoritmo aparte, fuera de alcance aquí.
func vectorize_image(file_path: String) -> void:
	var image := Image.new()
	var err := image.load(file_path)
	if err != OK:
		push_error("Artboard.vectorize_image: no se pudo cargar %s (error %d)" % [file_path, err])
		return

	var texture := ImageTexture.create_from_image(image)
	var sprite := Sprite2D.new()
	sprite.name = "Imagen_Importada_SinVectorizar_%d" % get_child_count()
	sprite.texture = texture
	sprite.centered = false
	add_child(sprite)

	push_warning("Artboard.vectorize_image: la imagen se importó como raster — el trazado a vector real (edge detection) no está implementado todavía.")
	GlobalEvents.emit_safe("import_error", "Imagen importada sin vectorizar (trazado no implementado)")

func _verificar_y_crear_titulo() -> void:
	var label := get_node_or_null("ArtboardTitle") as WorldTextLabel
	if not label:
		label = WorldTextLabel.new()
		label.name = "ArtboardTitle"
		add_child(label)
	
	label.text = "Artboard"
	label.base_font_size = 12
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_font_size_override("font_size", 12)
	label.position = Vector2(0, -20)
	
	# Habilitamos la interactividad en el Label para capturar el doble click
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	if not label.gui_input.is_connected(_on_title_gui_input):
		label.gui_input.connect(_on_title_gui_input)
