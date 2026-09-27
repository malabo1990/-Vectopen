# =============================================================================
# RUTA: res://scenes/canvas/bounding_box.gd
# Sincronización Espacial de Precisión con Vinculación por Inspector (@export)
# =============================================================================
extends Control
class_name BoundingBox

@export_group("Referencias de Interfaz")
## Arrastra aquí el panel central o el contenedor que recibirá el arrastre (Drag)
@export var drag_panel: Control
## Arrastra aquí el nodo raíz de la escena (CanvasRoot) para una comunicación directa de alto rendimiento
@export var canvas_root: Node2D

var move_tool_reference: MoveTool = null
var target_node: Node2D = null # SOLUCIÓN AL CRASH: Satisface la verificación del controlador externo
var _is_dragging_canvas_area: bool = false
var _pool_initialized: bool = false

signal bounding_box_ready

# Mapeo Panel de handle → código usado por MoveTool.
#   move_x / move_y → arrastrar mueve la selección SOLO en horizontal / vertical
#   (los Panels `x` y `Y` del .tscn, antes solo indicadores del modo por teclado).
const _HANDLE_CODES := {
	"handle_IA": "tl", "handle_DA": "tr", "handle_IB": "bl", "handle_DB": "br",
	"handle_MA": "tc", "MB": "bc", "handle_IM": "lc", "handle_DM": "rc",
	"Rotation": "rot_handle",
	"x": "move_x", "Y": "move_y",
}
# Handles de redimensionado: posición como fracción del rect (0..1).
const _HANDLE_FRAC := {
	"handle_IA": Vector2(0, 0), "handle_DA": Vector2(1, 0),
	"handle_IB": Vector2(0, 1), "handle_DB": Vector2(1, 1),
	"handle_MA": Vector2(0.5, 0), "MB": Vector2(0.5, 1),
	"handle_IM": Vector2(0, 0.5), "handle_DM": Vector2(1, 0.5),
}
# Axis gizmo: red arrow to the right (move X only), green arrow below (move
# Y only). Long stems keep the arrow heads well clear of the right and bottom
# resize handles.
const _AXIS_START_PX: float = 12.0   # stem starts this far from the box edge
const _AXIS_LEN_PX: float = 46.0     # box edge → arrow tip
const _AXIS_HEAD_PX: float = 10.0    # arrow head length
const _AXIS_X_COLOR := Color("#e5484d")
const _AXIS_Y_COLOR := Color("#30a46c")
# Dimension pill under the selection ("W × H")
const _PILL_FONT_PX: int = 11
const _PILL_GAP_PX: float = 8.0
# Interactive corner-radius handles (rectangles only)
const _RADIUS_MIN_INSET_PX: float = 14.0   # handle inset when the radius is ~0
const _RADIUS_HANDLE_PX: float = 7.0
const _RADIUS_MIN_BOX_PX: float = 56.0     # hide on boxes smaller than this on screen
const _CURSOR_ROTATE := preload("res://icon/UI/cursor/rotate.svg")
const _CURSOR_MOVE_X := preload("res://icon/UI/cursor/move_x.svg")
const _CURSOR_MOVE_Y := preload("res://icon/UI/cursor/move_y.svg")

# ── Tamaño CONSTANTE en pantalla, a cualquier zoom (como en un editor profesional) ────
# Los handles ya NO se ven vía sus StyleBox (el borde es entero y se escala con
# el canvas → en zoom fuerte/lejano quedaban enormes o invisibles). Ahora:
#   · el Panel de cada handle queda TRANSPARENTE y solo sirve de zona de clic
#   · el dibujo real (cuadros + contorno + tallo de rotación) lo hace _draw()
#     con medidas en PÍXELES DE PANTALLA divididas por el zoom.
const _OUTLINE_SCREEN_PX: float = 1.25   # grosor del contorno
const _OUTLINE_COLOR := Color(0.05, 0.55, 0.91, 1.0)   # azul de acento
const _HANDLE_FILL := Color(1, 1, 1, 1)                # relleno del handle
const _HANDLE_SCREEN_PX: float = 8.0     # lado visible del handle
const _HANDLE_HIT_PX: float = 16.0       # lado de la zona de clic (Panel)
const _ROT_STEM_SCREEN_PX: float = 20.0  # largo del tallo del handle de rotación
# Puntero del ratón por handle → identidad visual (como en un editor profesional).
# Godot no trae cursor de rotación → CROSS para el de rotación.
const _HANDLE_CURSORS := {
	"handle_IA": Control.CURSOR_FDIAGSIZE, "handle_DB": Control.CURSOR_FDIAGSIZE,  # ╲ tl/br
	"handle_DA": Control.CURSOR_BDIAGSIZE, "handle_IB": Control.CURSOR_BDIAGSIZE,  # ╱ tr/bl
	"handle_MA": Control.CURSOR_VSIZE, "MB": Control.CURSOR_VSIZE,                  # ↕ tc/bc
	"handle_IM": Control.CURSOR_HSIZE, "handle_DM": Control.CURSOR_HSIZE,           # ↔ lc/rc
	"Rotation": Control.CURSOR_CROSS,
	"x": Control.CURSOR_HSIZE, "Y": Control.CURSOR_VSIZE,                           # gizmo de eje
}
var _handle_base_rects: Dictionary = {}    # nombre de nodo → Rect2 de offsets originales (a zoom 1.0)
var _last_zoom_scale: float = -1.0
var _last_layout_size: Vector2 = Vector2(-1, -1)
var _active_custom_cursor: int = -1        # Input.CursorShape currently overridden, -1 = none
# Corner-radius drag state
var _radius_drag_corner: int = -1          # 0 tl, 1 tr, 2 br, 3 bl
var _radius_drag_all: bool = true
var _radius_before: Vector4 = Vector4.ZERO
var _radius_hover: int = -1
var _outline_style: StyleBoxFlat = null    # copia única por instancia (no la compartida del .tscn)

## Factor de compensación de zoom, exacto (sin recorte visible). El clamp solo
## evita valores patológicos si el zoom se acerca a 0 o es absurdamente grande.
static func _zoom_comp(zoom: float) -> float:
	return 1.0 / clampf(zoom, 0.0002, 100000.0)

## Número corto para la píldora "W × H" y el radio: 2 decimales máximo,
## sin ceros sobrantes (320.0→"320", 12.5→"12.5", 0.004→"0", 99.126→"99.13").
static func _fmt_num(v: float) -> String:
	var r := snappedf(v, 0.01)
	if is_zero_approx(r):
		return "0"
	var s := "%.2f" % r
	while s.contains(".") and s.ends_with("0"):
		s = s.trim_suffix("0")
	return s.trim_suffix(".")

# ── Campos numéricos X/Y (posición doc-space de la figura seleccionada) ──────
var _fields_wrapper: Control = null
var _field_x: Control = null
var _field_y: Control = null
var _bound_shape: VectorShape = null

# ── Gradient Annotator (Affinity / Illustrator / Figma style) ────────────────
var _selected_gradient_stop_idx: int = 0
var _annotator_drag_mode: String = "" # "end", "start", "rot", "stop", "line"
var _annotator_drag_stop_idx: int = -1
var _annotator_undo_state: Dictionary = {}
var _line_drag_start_pos: Vector2 = Vector2.ZERO
var _line_drag_start_p0: Vector2 = Vector2.ZERO
var _line_drag_start_p1: Vector2 = Vector2.ZERO
var _line_drag_has_moved: bool = false
var _line_click_ratio: float = 0.5
const GRAD_HIT_PX: float = 18.0

func _ready() -> void:
	# Permitir que los eventos de ratón fluyan libremente a través de las capas de control
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Conexión limpia usando la referencia del Inspector elegida por ti
	if is_instance_valid(drag_panel):
		drag_panel.gui_input.connect(_on_drag_panel_gui_input)

	# Conectar señales para actualización eficiente
	_connect_signals()
	_connect_handle_signals()
	_connect_field_signals()
	_capture_base_handle_geometry()
	_apply_zoom_compensation()
	_sync_fields_wrapper_transform()
	_update_axis_lock_indicators()

	# Notificar que el objeto está listo para ser usado
	bounding_box_ready.emit()
	_pool_initialized = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if _annotator_drag_mode == "":
			if is_instance_valid(move_tool_reference) and move_tool_reference.is_gradient_mode:
				Input.set_default_cursor_shape(Input.CURSOR_CROSS)
			else:
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)

## Guarda la geometría base de cada handle y deja sus Panels transparentes
## (pasan a ser solo zona de clic; el dibujo lo hace _draw()).
func _capture_base_handle_geometry() -> void:
	if not _handle_base_rects.is_empty():
		return  # ya capturado (instancia reciclada del pool)
	var panel_interactivo := get_node_or_null("PANEL_BOUNDINGBOX")
	if not is_instance_valid(panel_interactivo):
		return
	var vacio := StyleBoxEmpty.new()
	for handle_name in _HANDLE_CODES:
		# `Y` cuelga de `MB` en el .tscn, no directamente del panel → find_child.
		var p := panel_interactivo.find_child(handle_name, true, false) as Control
		if is_instance_valid(p):
			_handle_base_rects[handle_name] = Rect2(
				p.offset_left, p.offset_top,
				p.offset_right - p.offset_left, p.offset_bottom - p.offset_top
			)
			p.add_theme_stylebox_override("panel", vacio)   # solo zona de clic; el dibujo lo hace _draw()
			if _HANDLE_CURSORS.has(handle_name):
				p.mouse_default_cursor_shape = _HANDLE_CURSORS[handle_name]
			if handle_name in ["x", "Y", "Rotation"]:
				p.mouse_entered.connect(_on_special_handle_hover.bind(handle_name, true))
				p.mouse_exited.connect(_on_special_handle_hover.bind(handle_name, false))
	# Arrastrar el cuerpo de la caja = mover libre → cursor de movimiento.
	if is_instance_valid(drag_panel):
		drag_panel.mouse_default_cursor_shape = Control.CURSOR_MOVE
	var candle := panel_interactivo.get_node_or_null("candle")
	if is_instance_valid(candle):
		candle.add_theme_stylebox_override("panel", vacio)  # el tallo lo dibuja _draw()

	# El StyleBox del contorno del panel: le quitamos el borde (el contorno lo
	# dibuja _draw() con grosor CONSTANTE en pantalla — el borde de StyleBoxFlat
	# es entero y se escala con el zoom, así que en zoom fuerte/lejano quedaba
	# demasiado grueso o invisible).
	var current_style: StyleBox = panel_interactivo.get_theme_stylebox("panel")
	if current_style is StyleBoxFlat:
		_outline_style = current_style.duplicate()
		_outline_style.set_border_width_all(0)
		panel_interactivo.add_theme_stylebox_override("panel", _outline_style)

## Escala TOTAL con la que se ve en pantalla el contenido de esta caja:
##   zoom de cámara (viewport canvas transform)  ×  escala propia de la caja
##   (que copia la escala de la figura seleccionada, ver _sincronizar…).
## El código antiguo leía canvas.global_transform.get_scale(), que SIEMPRE es 1
## (la cámara no escala el nodo Canvas, escala el viewport) → la compensación no
## hacía nada y los handles/línea crecían/encogían con el zoom. Ese era el bug.
func _get_zoom_scale() -> float:
	var vp := get_viewport()
	var cam_s: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	var self_s: float = get_global_transform().get_scale().x   # escala propia + ancestros
	return maxf(cam_s * self_s, 0.0001)

## Coloca la ZONA DE CLIC de cada handle (un Panel transparente) centrada en su
## punto y con un tamaño constante en pantalla. El dibujo real lo hace _draw().
func _apply_zoom_compensation() -> void:
	if _handle_base_rects.is_empty():
		return
	var zoom: float = _get_zoom_scale()
	# The axis handles hang off the box edges, so a resize moves them too
	if is_equal_approx(zoom, _last_zoom_scale) and size.is_equal_approx(_last_layout_size):
		return
	_last_zoom_scale = zoom
	_last_layout_size = size
	var f: float = _zoom_comp(zoom)
	queue_redraw()

	var panel_interactivo := get_node_or_null("PANEL_BOUNDINGBOX")
	if not is_instance_valid(panel_interactivo):
		return

	var hit_half: float = _HANDLE_HIT_PX * 0.5 * f
	# Hit zone centred on the arrow head
	var gap: float = (_AXIS_LEN_PX - _AXIS_HEAD_PX * 0.5) * f
	var cy0: float = size.y * 0.5
	for handle_name in _handle_base_rects:
		var p := panel_interactivo.find_child(handle_name, true, false) as Control
		if not is_instance_valid(p):
			continue
		if handle_name == "x":
			# `x` cuelga del panel (layout_mode 0): a la DERECHA del borde, centrado.
			var xc := Vector2(size.x + gap, cy0)
			p.offset_left = xc.x - hit_half
			p.offset_right = xc.x + hit_half
			p.offset_top = xc.y - hit_half
			p.offset_bottom = xc.y + hit_half
			continue
		if handle_name == "Y":
			# `Y` cuelga de `MB` (bottom-center, rect ±hit_half): centrado, DEBAJO.
			var yc_local := Vector2(hit_half, hit_half + gap)   # relativo al top-left de MB
			p.offset_left = yc_local.x - hit_half
			p.offset_right = yc_local.x + hit_half
			p.offset_top = yc_local.y - hit_half
			p.offset_bottom = yc_local.y + hit_half
			continue
		# Handles de resize/rotación: cuadrado centrado en su anchor.
		var cy: float = -_ROT_STEM_SCREEN_PX * f if handle_name == "Rotation" else 0.0
		p.offset_left = -hit_half
		p.offset_right = hit_half
		p.offset_top = cy - hit_half
		p.offset_bottom = cy + hit_half


## Dibuja el contorno, los handles y el tallo de rotación con medidas SIEMPRE
## constantes en pantalla, a cualquier zoom (como en un editor profesional / editor profesional).
## `_draw()` corre en el espacio local de la caja, que el canvas escala por el
## zoom → cada medida en px de pantalla se divide por ese zoom (`inv`).
func _draw() -> void:
	if not visible or size == Vector2.ZERO:
		return
	var inv: float = _zoom_comp(_get_zoom_scale())
	var lw: float = _OUTLINE_SCREEN_PX * inv
	var hs: float = _HANDLE_SCREEN_PX * inv
	var hb: float = maxf(_OUTLINE_SCREEN_PX * inv, 0.01)   # borde del handle = grosor de línea

	# Contorno
	draw_rect(Rect2(Vector2.ZERO, size), _OUTLINE_COLOR, false, lw)

	# Tallo + handle de rotación (por encima del centro superior)
	var top_c := Vector2(size.x * 0.5, 0.0)
	var rot_p := top_c + Vector2(0.0, -_ROT_STEM_SCREEN_PX * inv)
	draw_line(top_c, rot_p, _OUTLINE_COLOR, lw)
	draw_circle(rot_p, hs * 0.5, _HANDLE_FILL)
	draw_arc(rot_p, hs * 0.5, 0.0, TAU, 20, _OUTLINE_COLOR, hb)

	# 8 handles de redimensionado (esquinas + centros de lado)
	for handle_name in _HANDLE_FRAC:
		var frac: Vector2 = _HANDLE_FRAC[handle_name]
		var c := Vector2(frac.x * size.x, frac.y * size.y)
		var r := Rect2(c - Vector2(hs, hs) * 0.5, Vector2(hs, hs))
		draw_rect(r, _HANDLE_FILL, true)
		draw_rect(r, _OUTLINE_COLOR, false, hb)

	# Axis gizmo arrows (drag = move on that axis only)
	_draw_axis_arrow(Vector2(size.x, size.y * 0.5), Vector2.RIGHT, _AXIS_X_COLOR, inv)
	_draw_axis_arrow(Vector2(size.x * 0.5, size.y), Vector2.DOWN, _AXIS_Y_COLOR, inv)

	# Corner-radius handles
	var radius_c := _radius_handle_centers(inv)
	for i in radius_c.size():
		var rc: Vector2 = radius_c[i]
		var grow: float = 1.25 if (i == _radius_hover or i == _radius_drag_corner) else 1.0
		var rr: float = _RADIUS_HANDLE_PX * 0.5 * inv * grow
		draw_circle(rc, rr, _HANDLE_FILL)
		draw_arc(rc, rr, 0.0, TAU, 20, _OUTLINE_COLOR, hb, true)

	# Gradient Annotator (Affinity / Illustrator / Figma style)
	if has_gradient_annotator():
		var grad_data := _get_gradient_annotator_data()
		if not grad_data.is_empty():
			_draw_gradient_annotator(grad_data, inv)

	# Puerto de enlace interactivo para párrafos (Text Threading)
	_draw_paragraph_threading_port(inv)

	_draw_dimension_pill(inv)

## Arrow = thin stem + solid head, all sized in screen pixels.
func _draw_axis_arrow(edge: Vector2, dir: Vector2, col: Color, inv: float) -> void:
	var start := edge + dir * _AXIS_START_PX * inv
	var tip := edge + dir * _AXIS_LEN_PX * inv
	var head_base := tip - dir * _AXIS_HEAD_PX * inv
	var normal := Vector2(-dir.y, dir.x)
	draw_line(start, head_base, col, 1.5 * inv, true)
	var half_w := _AXIS_HEAD_PX * 0.55 * inv
	draw_colored_polygon(PackedVector2Array([tip, head_base + normal * half_w, head_base - normal * half_w]), col)

## "W × H" pill under the selection, always horizontal and screen-sized.
## While a corner radius is dragged it shows the radius instead.
func _draw_dimension_pill(inv: float) -> void:
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	if font == null:
		return
	var txt := ""
	var rshape := _radius_target()
	if _radius_drag_corner >= 0 and is_instance_valid(rshape):
		var radii: Vector4 = rshape.get_corner_radii()
		txt = "%s %s" % [tr("Radio"), _fmt_num(radii[_radius_drag_corner])]
	else:
		var dims := Vector2(absf(size.x * scale.x), absf(size.y * scale.y))
		if dims == Vector2.ZERO:
			return
		txt = "%s × %s" % [_fmt_num(dims.x), _fmt_num(dims.y)]
	var text_size := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, _PILL_FONT_PX)
	var pad := Vector2(7, 3)
	var pill_size := text_size + pad * 2.0
	# Counter the box rotation/scale so the pill reads upright at a fixed size
	var sx := inv * (-1.0 if scale.x < 0.0 else 1.0)
	var sy := inv * (-1.0 if scale.y < 0.0 else 1.0)
	var below: float = _AXIS_LEN_PX + _PILL_GAP_PX   # clear of the green Y arrow
	draw_set_transform(Vector2(size.x * 0.5, size.y), -rotation, Vector2(sx, sy))
	var r := Rect2(Vector2(-pill_size.x * 0.5, below), pill_size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = _OUTLINE_COLOR
	sb.set_corner_radius_all(4)
	sb.anti_aliasing = true
	draw_style_box(sb, r)
	var baseline := r.position + Vector2(pad.x, pad.y + font.get_ascent(_PILL_FONT_PX))
	draw_string(font, baseline, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, _PILL_FONT_PX, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _is_paragraph_shape_selected() -> bool:
	if not is_instance_valid(move_tool_reference) or move_tool_reference.selected_shapes.size() != 1:
		return false
	var shape: Node2D = move_tool_reference.selected_shapes[0]
	return is_instance_valid(shape) and shape.has_meta("shape_type") and str(shape.get_meta("shape_type")) == "text_paragraph"

func _get_paragraph_threading_port_rect(inv: float) -> Rect2:
	var port_sz: float = 14.0 * inv
	var port_margin: float = 4.0 * inv
	return Rect2(Vector2(size.x - port_sz - port_margin, size.y - port_sz - port_margin), Vector2(port_sz, port_sz))

func _is_point_in_threading_port(local_p: Vector2) -> bool:
	if not _is_paragraph_shape_selected():
		return false
	var inv: float = _zoom_comp(_get_zoom_scale())
	var r := _get_paragraph_threading_port_rect(inv)
	return r.grow(4.0 * inv).has_point(local_p)

func _draw_paragraph_threading_port(inv: float) -> void:
	if not _is_paragraph_shape_selected():
		return
	var shape: Node2D = move_tool_reference.selected_shapes[0]
	var is_overflow: bool = shape.get_meta("is_overflowing", false)
	var has_next: bool = shape.has_meta("next_paragraph") and not str(shape.get_meta("next_paragraph")).is_empty()

	var port_rect := _get_paragraph_threading_port_rect(inv)
	var bg_col := Color(0.2, 0.25, 0.35, 0.9)
	var border_col := Color(1.0, 1.0, 1.0, 0.95)
	var glyph := ""

	if is_overflow:
		bg_col = Color(0.95, 0.2, 0.2, 0.95) # Rojo: desbordamiento de texto [+]
		glyph = "+"
	elif has_next:
		bg_col = Color(0.15, 0.65, 0.95, 0.95) # Cian: marco enlazado con texto que continúa [→]
		glyph = "→"

	draw_rect(port_rect, bg_col, true)
	draw_rect(port_rect, border_col, false, maxf(1.0 * inv, 0.01))

	var font := get_theme_default_font()
	if font == null: font = ThemeDB.fallback_font
	if font and glyph != "":
		var fs: int = maxi(8, int(round(10.0 * inv)))
		draw_string(font, port_rect.position + Vector2(2.5 * inv, 10.5 * inv), glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color.WHITE)

# ── Corner radius handles ───────────────────────────────────────────────────
## Single selected rectangle with room for the handles, or null.
func _radius_target() -> Node2D:
	if not is_instance_valid(move_tool_reference) or move_tool_reference.selected_shapes.size() != 1:
		return null
	var s: Node2D = move_tool_reference.selected_shapes[0]
	if not is_instance_valid(s) or not s.has_method("get_corner_radii") or not s.has_method("set_corner_radii"):
		return null
	return s

const _CORNER_INWARD: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]

func _corner_points() -> Array[Vector2]:
	return [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]

## Handle centres in box-local coordinates (tl, tr, br, bl); empty when hidden.
func _radius_handle_centers(inv: float) -> Array:
	var shape := _radius_target()
	if shape == null or is_gradient_active() or has_gradient_annotator():
		return []
	var screen_w := absf(size.x) / maxf(inv, 1e-6)
	var screen_h := absf(size.y) / maxf(inv, 1e-6)
	if minf(screen_w, screen_h) < _RADIUS_MIN_BOX_PX:
		return []
	var radii: Vector4 = shape.get_corner_radii()
	var max_r: float = minf(size.x, size.y) * 0.5
	var corners := _corner_points()
	var out: Array = []
	for i in 4:
		var d: float = maxf(minf(radii[i], max_r), _RADIUS_MIN_INSET_PX * inv)
		d = minf(d, max_r)
		out.append(corners[i] + _CORNER_INWARD[i] * d)
	return out

func _radius_handle_at(local_pos: Vector2) -> int:
	var inv: float = _zoom_comp(_get_zoom_scale())
	var centers := _radius_handle_centers(inv)
	var hit: float = (_RADIUS_HANDLE_PX * 0.5 + 4.0) * inv
	for i in centers.size():
		if local_pos.distance_to(centers[i]) <= hit:
			return i
	return -1

func _local_from_event(event: InputEvent) -> Vector2:
	return get_screen_transform().affine_inverse() * event.global_position

func _begin_radius_drag(corner: int, all_corners: bool) -> void:
	var shape := _radius_target()
	if shape == null:
		return
	_radius_drag_corner = corner
	_radius_drag_all = all_corners
	_radius_before = shape.get_corner_radii()

## Radius = pointer projected onto the corner's inward diagonal.
func _update_radius_drag(local_pos: Vector2) -> void:
	var shape := _radius_target()
	if shape == null or _radius_drag_corner < 0:
		return
	var corner: Vector2 = _corner_points()[_radius_drag_corner]
	var r: float = (local_pos - corner).dot(_CORNER_INWARD[_radius_drag_corner]) * 0.5
	r = clampf(r, 0.0, minf(size.x, size.y) * 0.5)
	if Input.is_key_pressed(KEY_SHIFT):
		r = roundf(r)
	var radii: Vector4 = _radius_before
	if _radius_drag_all:
		radii = Vector4(r, r, r, r)
	else:
		radii[_radius_drag_corner] = r
	shape.set_corner_radii(radii)
	queue_redraw()

func _end_radius_drag() -> void:
	var shape := _radius_target()
	var corner := _radius_drag_corner
	_radius_drag_corner = -1
	if shape == null or corner < 0:
		return
	var after: Vector4 = shape.get_corner_radii()
	if after.is_equal_approx(_radius_before):
		return
	var before := _radius_before
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action("Radio de esquina")
		hm.add_do(func(): if is_instance_valid(shape): shape.set_corner_radii(after))
		hm.add_undo(func(): if is_instance_valid(shape): shape.set_corner_radii(before))
		hm.commit()
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("object_style_changed"):
		ge.emit_safe("object_style_changed")

# ── Custom cursors for the axis and rotation handles ────────────────────────
func _on_special_handle_hover(handle_name: String, entered: bool) -> void:
	if not entered:
		# Keep the cursor while that handle is being dragged
		if is_instance_valid(move_tool_reference) and (move_tool_reference.is_rotating or move_tool_reference.is_dragging_shape):
			return
		_restore_custom_cursor()
		return
	var tex: Texture2D = null
	var shape: int = Input.CURSOR_ARROW
	match handle_name:
		"x":
			tex = _CURSOR_MOVE_X
			shape = Input.CURSOR_HSIZE
		"Y":
			tex = _CURSOR_MOVE_Y
			shape = Input.CURSOR_VSIZE
		"Rotation":
			tex = _CURSOR_ROTATE
			shape = Input.CURSOR_CROSS
	_restore_custom_cursor()
	if tex:
		Input.set_custom_mouse_cursor(tex, shape, Vector2(12, 12))
		_active_custom_cursor = shape

func _restore_custom_cursor() -> void:
	if _active_custom_cursor >= 0:
		Input.set_custom_mouse_cursor(null, _active_custom_cursor)
		_active_custom_cursor = -1

## Los campos X/Y son texto: si heredaran la rotation/scale de esta caja (como
## los handles, a propósito) quedarían ilegibles cuando la figura está rotada
## o escalada. Se contra-rotan/escalan para mantenerse siempre horizontales y
## de tamaño constante en pantalla. A diferencia de _apply_zoom_compensation(),
## esto NO puede saltarse cuando el zoom no cambió: "rotation" (de esta caja)
## sí cambia en cada frame durante un arrastre de rotación, aunque el zoom de
## cámara se mantenga fijo — por eso se llama sin condición desde _process().
func _sync_fields_wrapper_transform() -> void:
	if not is_instance_valid(_fields_wrapper):
		return
	var f: float = _zoom_comp(_get_zoom_scale())
	_fields_wrapper.rotation = -rotation
	_fields_wrapper.scale = Vector2(f, f)

func _process(_delta: float) -> void:
	_heal_stuck_drag()
	if not visible:
		return
	_apply_zoom_compensation()
	_sync_fields_wrapper_transform()
	queue_redraw()   # el contorno sigue a la figura (tamaño/rotación) y al zoom
	_update_axis_lock_indicators()

## Autocuración: al pulsar sobre el interior del gizmo (`_on_drag_panel_gui_input`)
## ponemos `_is_dragging_canvas_area` y `move_tool.is_dragging_shape` a `true`.
## Si el gizmo se aleja bajo el cursor mientras arrastras, la SUELTA nunca llega
## a ese `gui_input` y ambos se quedan atascados → la figura se queda pegada al
## ratón y NADA más responde (ni el panel de capas ni el arrastre del artboard).
## Cada frame comprobamos: si decimos estar arrastrando pero el botón izquierdo
## NO está pulsado de verdad, cerramos el gesto.
func _heal_stuck_drag() -> void:
	if is_instance_valid(move_tool_reference) and "is_middle_dragging_3d" in move_tool_reference and move_tool_reference.is_middle_dragging_3d:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			if move_tool_reference.has_method("end_middle_drag_3d"):
				move_tool_reference.end_middle_drag_3d()
			else:
				move_tool_reference.is_middle_dragging_3d = false
	if _radius_drag_corner >= 0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_radius_drag()
	if not _is_dragging_canvas_area and _annotator_drag_mode == "":
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_is_dragging_canvas_area = false
	if _annotator_drag_mode != "":
		_commit_annotator_undo()
		_annotator_drag_mode = ""
		_annotator_drag_stop_idx = -1
	if is_instance_valid(move_tool_reference) and "is_dragging_shape" in move_tool_reference:
		move_tool_reference.is_dragging_shape = false

## Los Panels `x` / `Y` son ahora las ZONAS DE CLIC del gizmo de eje (mover solo
## en horizontal / vertical). Siempre visibles mientras haya selección; el
## dibujo del gizmo lo hace _draw().
func _update_axis_lock_indicators() -> void:
	var panel_interactivo := get_node_or_null("PANEL_BOUNDINGBOX")
	if not is_instance_valid(panel_interactivo):
		return
	for n in ["x", "Y"]:
		var p := panel_interactivo.find_child(n, true, false) as Control
		if is_instance_valid(p) and not p.visible:
			p.visible = true

## Conecta cada Panel de handle (resize + rotación) para que dispare la
## transformación real en MoveTool, en vez de depender de su hit-testing manual.
func _connect_handle_signals() -> void:
	var panel_interactivo := get_node_or_null("PANEL_BOUNDINGBOX")
	if not is_instance_valid(panel_interactivo):
		return
	for handle_name in _HANDLE_CODES:
		var handle_panel := panel_interactivo.find_child(handle_name, true, false) as Control
		if is_instance_valid(handle_panel):
			var handle_code: String = _HANDLE_CODES[handle_name]
			var bound_callable := _on_handle_gui_input.bind(handle_code)
			if not handle_panel.gui_input.is_connected(bound_callable):
				handle_panel.gui_input.connect(bound_callable)

func _on_handle_gui_input(event: InputEvent, handle_code: String) -> void:
	if not is_instance_valid(move_tool_reference):
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			move_tool_reference.start_handle_transform(handle_code)
			# Start from the exact press point, not the cached viewport mouse
			move_tool_reference.transform_initial_mouse = _world_from_event(event)
		elif move_tool_reference.resize_handle == handle_code:
			move_tool_reference._on_release(_world_from_event(event))
			_restore_custom_cursor()
	elif event is InputEventMouseMotion:
		var m = move_tool_reference
		if m.resize_handle == handle_code and (m.is_resizing or m.is_rotating or m.is_dragging_shape):
			m._on_motion(_world_from_event(event), _mods_from_event(event))

## Canvas-world position of a GUI event. The cached viewport mouse position
## (get_global_mouse_position) can lag a frame behind the event, which made
## drags stutter; the event carries the exact position.
func _world_from_event(event: InputEvent) -> Vector2:
	var c: Node2D = move_tool_reference.canvas if is_instance_valid(move_tool_reference) else null
	if not is_instance_valid(c) or not (event is InputEventMouse):
		return c.get_global_mouse_position() if is_instance_valid(c) else Vector2.ZERO
	return c.get_global_transform() * (c.get_screen_transform().affine_inverse() * (event as InputEventMouse).global_position)

func _mods_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventWithModifiers:
		return {
			"shift": event.shift_pressed or Input.is_key_pressed(KEY_SHIFT),
			"alt": event.alt_pressed or Input.is_key_pressed(KEY_ALT),
			"ctrl": event.ctrl_pressed or event.meta_pressed or Input.is_key_pressed(KEY_CTRL),
		}
	return {}

## Localiza los campos X/Y (FieldsWrapper/FieldX/FieldY, ver boundingbox.tscn)
## y conecta su señal value_committed a los handlers que mueven la figura.
func _connect_field_signals() -> void:
	# El wrapper vive bajo PANEL_BOUNDINGBOX/MB (se movió al rediseñar el panel);
	# se prueba también la ruta antigua por compatibilidad.
	_fields_wrapper = get_node_or_null("PANEL_BOUNDINGBOX/MB/FieldsWrapper")
	if not is_instance_valid(_fields_wrapper):
		_fields_wrapper = get_node_or_null("PANEL_BOUNDINGBOX/FieldsWrapper")
	if not is_instance_valid(_fields_wrapper):
		return
	_field_x = _fields_wrapper.get_node_or_null("FieldX")
	_field_y = _fields_wrapper.get_node_or_null("FieldY")
	if is_instance_valid(_field_x) and _field_x.has_signal("value_committed"):
		if not _field_x.value_committed.is_connected(_on_field_x_committed):
			_field_x.value_committed.connect(_on_field_x_committed)
	if is_instance_valid(_field_y) and _field_y.has_signal("value_committed"):
		if not _field_y.value_committed.is_connected(_on_field_y_committed):
			_field_y.value_committed.connect(_on_field_y_committed)

func _on_field_x_committed(v: float) -> void:
	if is_instance_valid(_bound_shape):
		_bound_shape.set_doc_position(DVec2.new(v, _bound_shape.doc_position.y))
		_sincronizar_dimensiones_en_canvas()

func _on_field_y_committed(v: float) -> void:
	if is_instance_valid(_bound_shape):
		_bound_shape.set_doc_position(DVec2.new(_bound_shape.doc_position.x, v))
		_sincronizar_dimensiones_en_canvas()

func _hide_position_fields() -> void:
	_bound_shape = null
	if is_instance_valid(_fields_wrapper):
		_fields_wrapper.hide()

func _show_position_fields_for(shape: VectorShape) -> void:
	_bound_shape = shape
	# The editable X/Y boxes are replaced on canvas by the "W × H" pill (position
	# is edited in the inspector); keep their values synced for tooling/tests.
	if is_instance_valid(_fields_wrapper):
		_fields_wrapper.hide()
	if is_instance_valid(_field_x):
		_field_x.set_display_value(shape.doc_position.x)
	if is_instance_valid(_field_y):
		_field_y.set_display_value(shape.doc_position.y)

## Método requerido por el controlador para inyectar objetivos individuales
func set_target(new_target: Node2D) -> void:
	target_node = new_target

func _sincronizar_dimensiones_en_canvas() -> void:
	# El bounding box solo tiene sentido dibujado dentro de un CanvasItem (canvas).
	# Instancias filtradas / zombis (pool, restos de test) tienen un padre Node
	# pelado → global_rotation/to_local revientan. Salimos antes.
	if not (get_parent() is CanvasItem):
		return

	# Agrupamos los elementos a calcular según el flujo de origen. `MoveTool`
	# mantiene su `selected_shapes` sincronizado con `SelectionManager` (única
	# fuente de verdad), así que leerlo aquí sigue reflejando el panel de capas.
	var shapes_to_calculate: Array[Node2D] = []
	if is_instance_valid(move_tool_reference) and not move_tool_reference.selected_shapes.is_empty():
		shapes_to_calculate = move_tool_reference.selected_shapes
	elif is_instance_valid(target_node):
		shapes_to_calculate = [target_node]

	if shapes_to_calculate.is_empty():
		if visible: hide()
		_hide_position_fields()
		return

	var parent_node = get_parent()
	if not is_instance_valid(parent_node):
		return

	if shapes_to_calculate.size() == 1 and is_instance_valid(shapes_to_calculate[0]):
		# Selección única: la caja debe rotar/escalar EXACTAMENTE igual que la figura,
		# no solo envolverla con un rectángulo alineado al mundo.
		var shape: Node2D = shapes_to_calculate[0]
		var local_rect: Rect2 = _local_rect_cloned(shape)
		if local_rect.size == Vector2.ZERO:
			if visible: hide()
			_hide_position_fields()
			return

		# Control no tiene global_position/global_rotation (eso es de Node2D):
		# convertimos manualmente al espacio local del padre (canvas).
		var p_rot: float = parent_node.global_rotation if parent_node is Node2D else parent_node.get_global_transform().get_rotation()
		pivot_offset = Vector2.ZERO
		scale = shape.global_transform.get_scale()
		rotation = shape.global_rotation - p_rot
		size = local_rect.size
		var g_pos: Vector2 = shape.to_global(local_rect.position)
		position = parent_node.to_local(g_pos) if parent_node is Node2D else parent_node.get_global_transform().affine_inverse() * g_pos

		if not visible: show()

		# Campos X/Y: solo tienen sentido para una figura con doc-space (el
		# valor mostrado/editable es shape.doc_position, precisión doble).
		# Figuras sueltas (Polygon2D/Path2D/Line2D) no lo tienen — se ocultan.
		if shape is VectorShape:
			_show_position_fields_for(shape)
		else:
			_hide_position_fields()
	else:
		# Multi-selección.
		var mt = move_tool_reference
		var mid_rot: bool = is_instance_valid(mt) and mt.is_rotating
		var mid_scale: bool = is_instance_valid(mt) and mt.is_resizing
		if (mid_rot or mid_scale) and mt.transform_macro_rect.size != Vector2.ZERO:
			# DURANTE el gesto: la caja = el AABB de INICIO transformado por el
			# gesto en vivo (rota / escala con la selección). Así no "respira"
			# recalculando el AABB de las figuras ya rotadas cada frame.
			var r0: Rect2 = mt.transform_macro_rect
			var piv: Vector2 = mt.live_pivot
			var box_center: Vector2 = r0.get_center()
			var box_size: Vector2 = r0.size
			if mid_scale:
				box_size = Vector2(absf(box_size.x) * absf(mt.live_scale.x), absf(box_size.y) * absf(mt.live_scale.y))
				box_center = piv + (r0.get_center() - piv) * mt.live_scale
			var box_rot := 0.0
			if mid_rot:
				box_center = piv + (r0.get_center() - piv).rotated(mt.live_rot_angle)
				box_rot = mt.live_rot_angle
			var p_rot: float = parent_node.global_rotation if parent_node is Node2D else parent_node.get_global_transform().get_rotation()
			pivot_offset = box_size * 0.5
			rotation = box_rot - p_rot
			scale = Vector2.ONE
			size = box_size
			var b_pos: Vector2 = parent_node.to_local(box_center) if parent_node is Node2D else parent_node.get_global_transform().affine_inverse() * box_center
			position = b_pos - box_size * 0.5
			if not visible: show()
			_hide_position_fields()
			return

		# En reposo: AABB alineado al mundo que envuelve toda la selección.
		var global_rect: Rect2 = _get_macro_rect_cloned(shapes_to_calculate)
		if global_rect.size == Vector2.ZERO:
			if visible: hide()
			_hide_position_fields()
			return

		var g_p0: Vector2 = global_rect.position
		var g_p1: Vector2 = global_rect.end
		var local_pos: Vector2 = parent_node.to_local(g_p0) if parent_node is Node2D else parent_node.get_global_transform().affine_inverse() * g_p0
		var local_end: Vector2 = parent_node.to_local(g_p1) if parent_node is Node2D else parent_node.get_global_transform().affine_inverse() * g_p1

		pivot_offset = Vector2.ZERO
		scale = Vector2.ONE
		rotation = 0.0
		position = local_pos
		size = local_end - local_pos

		if not visible: show()
		_hide_position_fields()

func _gui_input(event: InputEvent) -> void:
	if has_gradient_annotator() and _handle_annotator_input(event):
		accept_event()
		return
	_on_drag_panel_gui_input(event)

# ── INTERACCIÓN: GESTIÓN DE RATÓN PARA DRAG DIRECTO DESDE PANEL ASIGNADO ─────
func _on_drag_panel_gui_input(event: InputEvent) -> void:
	if has_gradient_annotator() and _handle_annotator_input(event):
		return
	if not is_instance_valid(move_tool_reference):
		return

	var gm: Vector2
	if is_instance_valid(move_tool_reference.canvas) and event is InputEventMouse:
		gm = _world_from_event(event)
	elif event is InputEventMouse:
		gm = event.global_position
	else:
		gm = Vector2.ZERO

	# Puerto de enlace de párrafos (Text Threading)
	if _is_paragraph_shape_selected():
		var local_mouse := _local_from_event(event)
		if _is_point_in_threading_port(local_mouse):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed and not event.double_click:
					if is_instance_valid(move_tool_reference):
						var sel_p: Node2D = move_tool_reference.selected_shapes[0]
						move_tool_reference.start_threading_drag(sel_p, gm)
					accept_event()
					return
			elif event is InputEventMouseMotion and not _is_dragging_canvas_area:
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				if is_instance_valid(drag_panel):
					drag_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
				return

	# Corner-radius handles take priority over moving the box
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not event.double_click:
			var corner := _radius_handle_at(_local_from_event(event))
			if corner >= 0:
				# Drag = all corners together; Alt = only this corner
				_begin_radius_drag(corner, not (event.alt_pressed or Input.is_key_pressed(KEY_ALT)))
				accept_event()
				return
		elif not event.pressed and _radius_drag_corner >= 0:
			_end_radius_drag()
			accept_event()
			return
	elif event is InputEventMouseMotion:
		if _radius_drag_corner >= 0:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_update_radius_drag(_local_from_event(event))
			else:
				_end_radius_drag()
			accept_event()
			return
		var hover := _radius_handle_at(_local_from_event(event))
		if hover != _radius_hover:
			_radius_hover = hover
			queue_redraw()
		if hover >= 0 and not _is_dragging_canvas_area:
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			if is_instance_valid(drag_panel):
				drag_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
			return
		elif is_instance_valid(drag_panel) and drag_panel.mouse_default_cursor_shape != Control.CURSOR_MOVE:
			drag_panel.mouse_default_cursor_shape = Control.CURSOR_MOVE

	# Si hay un modelo 3D en modo de edición activo, delegar la interacción de ratón directamente a MoveTool
	if is_instance_valid(move_tool_reference) and "active_3d_model" in move_tool_reference and is_instance_valid(move_tool_reference.active_3d_model):
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			if move_tool_reference.handle_input(event):
				accept_event()
				return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if move_tool_reference.has_method("handle_middle_click_3d"):
				if move_tool_reference.handle_middle_click_3d(event, gm):
					accept_event()
					return
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if move_tool_reference.has_method("handle_wheel_3d"):
				if move_tool_reference.handle_wheel_3d(event, gm):
					accept_event()
					return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.double_click:
				if move_tool_reference.has_method("_on_double_click"):
					move_tool_reference._on_double_click(gm)
				accept_event()
				return
			if Input.is_key_pressed(KEY_SHIFT):
				var hit: Node2D = null
				if move_tool_reference.selected_shapes.size() == 1:
					hit = move_tool_reference.selected_shapes[0]
				elif move_tool_reference.has_method("_shape_at"):
					hit = move_tool_reference._shape_at(gm)
				if is_instance_valid(hit) and move_tool_reference.selected_shapes.has(hit):
					move_tool_reference._deselect(hit)
				accept_event()
				return
			_is_dragging_canvas_area = true
			if "is_dragging_shape" in move_tool_reference:
				move_tool_reference.is_dragging_shape = true
				move_tool_reference.transform_initial_mouse = gm
				if "transform_initial_states" in move_tool_reference:
					move_tool_reference.transform_initial_states.clear()
					for s in move_tool_reference.selected_shapes:
						if is_instance_valid(s):
							move_tool_reference.transform_initial_states[s] = move_tool_reference._snapshot(s)
			accept_event()
		else:
			_is_dragging_canvas_area = false
			if "is_dragging_shape" in move_tool_reference:
				if move_tool_reference.has_method("_on_release"):
					move_tool_reference._on_release(gm)
				else:
					move_tool_reference.is_dragging_shape = false
			accept_event()

	elif event is InputEventMouseMotion:
		if is_instance_valid(move_tool_reference) and move_tool_reference.has_method("handle_middle_motion_3d") and "is_middle_dragging_3d" in move_tool_reference and move_tool_reference.is_middle_dragging_3d:
			if move_tool_reference.handle_middle_motion_3d(gm):
				accept_event()
				return
		if _is_dragging_canvas_area:
			# La SUELTA se pudo perder si el panel se alejó bajo el cursor. Si el botón
			# izquierdo ya no está en la máscara del evento, cerramos el gesto aquí.
			if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
				_is_dragging_canvas_area = false
				if "is_dragging_shape" in move_tool_reference:
					if move_tool_reference.has_method("_on_release"):
						move_tool_reference._on_release(gm)
					else:
						move_tool_reference.is_dragging_shape = false
				accept_event()
				return
			move_tool_reference._on_motion(gm, _mods_from_event(event))
			accept_event()
		else:
			if not is_gradient_active():
				if mouse_default_cursor_shape != Control.CURSOR_MOVE:
					mouse_default_cursor_shape = Control.CURSOR_MOVE
				Input.set_default_cursor_shape(Input.CURSOR_MOVE)

# ── MÉTODOS DE GEOMETRÍA CLONADOS (Conserva tus funciones matemáticas aquí abajo) ──
func _get_macro_rect_cloned(selected_shapes_array: Array[Node2D]) -> Rect2:
	if selected_shapes_array.size() == 0: return Rect2()
	var valid_first_rect = false
	var r: Rect2 = Rect2()
	for shape in selected_shapes_array:
		if is_instance_valid(shape):
			if not valid_first_rect:
				r = _global_rect_cloned(shape)
				valid_first_rect = true
			else:
				r = r.merge(_global_rect_cloned(shape))
	return r

func _global_rect_cloned(node: Node2D) -> Rect2:
	if not is_instance_valid(node): return Rect2()
	if node.has_meta("shape_type") and (node.get_meta("shape_type") in ["text_paragraph", "text_title"]):
		var w: float = node.get_meta("width") if node.has_meta("width") else 350.0
		var h: float = node.get_meta("height") if node.has_meta("height") else 65.0
		return Rect2(node.global_position, Vector2(w, h))
	if node is Path2D:
		var curve: Curve2D = (node as Path2D).curve
		var baked = curve.get_baked_points()
		if baked.size() == 0: return Rect2(node.global_position - Vector2(10, 10), Vector2(20, 20))
		var first_gpt: Vector2 = node.to_global(baked[0])
		var g_mn: Vector2 = first_gpt
		var g_mx: Vector2 = first_gpt
		for p in baked:
			var g_pt: Vector2 = node.to_global(p)
			g_mn.x = min(g_mn.x, g_pt.x)
			g_mn.y = min(g_mn.y, g_pt.y)
			g_mx.x = max(g_mx.x, g_pt.x)
			g_mx.y = max(g_mx.y, g_pt.y)
		var pad: float = 6.0
		var renderer = node.get_node_or_null("Render_Visual")
		if renderer is Line2D: pad = max(pad, renderer.width * 0.5)
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
		if line.points.size() == 0: return Rect2(line.global_position - Vector2(10, 10), Vector2(20, 20))
		var first_gpt: Vector2 = line.to_global(line.points[0])
		var g_mn: Vector2 = first_gpt
		var g_mx: Vector2 = first_gpt
		for p in line.points:
			var g_pt: Vector2 = line.to_global(p)
			g_mn.x = min(g_mn.x, g_pt.x)
			g_mn.y = min(g_mn.y, g_pt.y)
			g_mx.x = max(g_mx.x, g_pt.x)
			g_mx.y = max(g_mx.y, g_pt.y)
		var pad: float = max(6.0, line.width * 0.5)
		return Rect2(g_mn, g_mx - g_mn).grow(pad)

	if node is Sprite2D and (node as Sprite2D).texture:
		var sp: Sprite2D = node as Sprite2D
		var lr: Rect2 = sp.get_rect()
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

	return Rect2(node.global_position - Vector2(20, 20), Vector2(40, 40))


## Igual que _global_rect_cloned(), pero en el espacio LOCAL/propio de la figura
## (sin aplicar su transform). Se usa para la caja orientada de selección única:
## al aplicar luego global_position/global_rotation/scale de la figura sobre este
## rect, el resultado queda pegado exactamente a su geometría real, ya rotada o no.
func _local_rect_cloned(node: Node2D) -> Rect2:
	if not is_instance_valid(node): return Rect2()
	if node.has_meta("shape_type") and (node.get_meta("shape_type") in ["text_paragraph", "text_title"]):
		var w: float = float(node.get_meta("width", 350.0))
		var h: float = float(node.get_meta("height", 65.0))
		var dl: Control = node.get_node_or_null("DisplayLabel")
		if dl and str(node.get_meta("shape_type")) == "text_title":
			var ms: Vector2 = dl.get_world_minimum_size() if dl is WorldTextLabel else dl.get_combined_minimum_size()
			w = maxf(w, ms.x)
			h = maxf(h, ms.y)
		return Rect2(Vector2.ZERO, Vector2(w, h))
	if node is Path2D:
		var curve: Curve2D = (node as Path2D).curve
		var baked = curve.get_baked_points()
		if baked.size() == 0: return Rect2(Vector2(-10, -10), Vector2(20, 20))
		var mn: Vector2 = baked[0]
		var mx: Vector2 = baked[0]
		for p in baked:
			mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
			mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
		var pad: float = 6.0
		var renderer = node.get_node_or_null("Render_Visual")
		if renderer is Line2D: pad = max(pad, renderer.width * 0.5)
		return Rect2(mn, mx - mn).grow(pad)
	if node is Polygon2D:
		var poly = node as Polygon2D
		if poly.polygon.size() > 0:
			var mn: Vector2 = poly.polygon[0]
			var mx: Vector2 = poly.polygon[0]
			for p in poly.polygon:
				mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
				mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
			return Rect2(mn, mx - mn)
	if "size" in node and (node is VectorRectangle or node is VectorCircle or node.has_method("rotate_orbit")):
		var s: Vector2 = node.get("size")
		return Rect2(-s * 0.5, s)

	if "vertices" in node:
		var verts: PackedVector2Array = node.get("vertices")
		if verts.size() == 0:
			return Rect2(Vector2(-10, -10), Vector2(20, 20))
		var mn: Vector2 = verts[0]
		var mx: Vector2 = verts[0]
		for p in verts:
			mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
			mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
		return Rect2(mn, mx - mn)

	if "width" in node and "height" in node:
		var w: float = node.get("width")
		var h: float = node.get("height")
		var size_vec: Vector2 = Vector2(w, h)
		return Rect2(-size_vec * 0.5, size_vec)
	if node is Line2D:
		var line: Line2D = node as Line2D
		if line.points.size() == 0: return Rect2(Vector2(-10, -10), Vector2(20, 20))
		var mn: Vector2 = line.points[0]
		var mx: Vector2 = line.points[0]
		for p in line.points:
			mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
			mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
		var pad: float = max(6.0, line.width * 0.5)
		return Rect2(mn, mx - mn).grow(pad)

	if node is Sprite2D and (node as Sprite2D).texture:
		return (node as Sprite2D).get_rect()

	if node.has_method("get_evaluated_geometry"):
		var polys: Array[PackedVector2Array] = node.call("get_evaluated_geometry")
		if not polys.is_empty():
			var mn: Vector2 = polys[0][0]
			var mx: Vector2 = mn
			for poly in polys:
				for p in poly:
					mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
					mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
			return Rect2(mn, mx - mn)

	return Rect2(Vector2(-20, -20), Vector2(40, 40))


func _connect_signals() -> void:
	# Conectar señales para actualización eficiente
	if GlobalEvents:
		if GlobalEvents.has_signal("object_selected"):
			GlobalEvents.object_selected.connect(_on_object_selected)
		if GlobalEvents.has_signal("object_transformed"):
			GlobalEvents.object_transformed.connect(_on_object_transformed)
		if GlobalEvents.has_signal("object_style_changed"):
			GlobalEvents.object_style_changed.connect(_on_object_transformed)
		if GlobalEvents.has_signal("selection_changed"):
			GlobalEvents.selection_changed.connect(_on_selection_changed)
		if GlobalEvents.has_signal("gradient_changed"):
			GlobalEvents.gradient_changed.connect(_on_external_gradient_changed)
		if GlobalEvents.has_signal("gradient_stop_selected"):
			GlobalEvents.gradient_stop_selected.connect(_on_external_stop_selected)

func _on_object_selected() -> void:
	_sincronizar_dimensiones_en_canvas()

func _on_object_transformed() -> void:
	_sincronizar_dimensiones_en_canvas()

func _on_selection_changed(_shapes: Array = []) -> void:
	_sincronizar_dimensiones_en_canvas()

func _on_external_gradient_changed(_g: Gradient) -> void:
	queue_redraw()

func _on_external_stop_selected(_c: Color, idx: int) -> void:
	if _selected_gradient_stop_idx != idx:
		_selected_gradient_stop_idx = idx
		queue_redraw()

# ── GRADIENT ANNOTATOR (AFFINITY / FIGMA / ILLUSTRATOR STYLE) ─────────────────

var is_gradient_tool_active: bool = false

func is_gradient_active() -> bool:
	if is_instance_valid(move_tool_reference) and "is_gradient_mode" in move_tool_reference:
		return move_tool_reference.is_gradient_mode
	return is_gradient_tool_active or _annotator_drag_mode != "" or (is_instance_valid(_bound_shape) and _bound_shape.has_gradient_fill())

func deactivate_gradient_mode() -> void:
	is_gradient_tool_active = false
	_annotator_drag_mode = ""
	_annotator_drag_stop_idx = -1
	_line_drag_has_moved = false
	queue_redraw()

func has_gradient_annotator() -> bool:
	if not is_instance_valid(_bound_shape) or not visible:
		return false
	if not _bound_shape.has_gradient_fill():
		return false
	return is_gradient_active()

func ensure_shape_gradient_fill() -> void:
	if is_instance_valid(_bound_shape) and _bound_shape is VectorShape and not _bound_shape.has_gradient_fill():
		var g := Gradient.new()
		var base_col: Color = _bound_shape.fill_color if _bound_shape.fill_color.a > 0.0 else Color(0.2, 0.5, 0.9, 1.0)
		g.set_color(0, base_col)
		g.set_color(1, Color.WHITE if base_col.get_luminance() < 0.6 else Color(0.1, 0.1, 0.1, 1.0))
		_bound_shape.fill_gradient = g
		_bound_shape.set_gradient_points(Vector2(0.1, 0.5), Vector2(0.9, 0.5))
		_bound_shape.queue_redraw()
		queue_redraw()
		_notify_gradient_changed()

func handle_annotator_input(event: InputEvent, custom_local_pos: Variant = null) -> bool:
	return _handle_annotator_input(event, custom_local_pos)

func _get_gradient_annotator_data() -> Dictionary:
	if not is_instance_valid(_bound_shape) or not _bound_shape.has_gradient_fill():
		return {}
	var g: Gradient = _bound_shape.fill_gradient
	if not is_instance_valid(g) or g.get_point_count() < 2:
		return {}

	var g_type: int = int(_bound_shape.fill_gradient_type)
	var angle: float = float(_bound_shape.fill_gradient_angle)
	var center := size * 0.5

	var norm_p0 := _bound_shape.get_gradient_p0_norm()
	var norm_p1 := _bound_shape.get_gradient_p1_norm()
	var p0 := Vector2(norm_p0.x * size.x, norm_p0.y * size.y)
	var p1 := Vector2(norm_p1.x * size.x, norm_p1.y * size.y)
	var line_vec := p1 - p0
	var span := p0.distance_to(p1)
	var dir := line_vec.normalized() if span > 0.001 else Vector2(cos(angle), sin(angle))

	var inv: float = _zoom_comp(_get_zoom_scale())
	var p_rot: Vector2 = p1 + dir * (16.0 * inv)

	var stops_pts: Array[Dictionary] = []
	for i in range(g.get_point_count()):
		var off: float = g.get_offset(i)
		var pt: Vector2 = p0.lerp(p1, off)
		var col: Color = g.get_color(i)
		stops_pts.append({
			"index": i,
			"offset": off,
			"position": pt,
			"color": col
		})

	return {
		"type": g_type,
		"angle": angle,
		"p0": p0,
		"p1": p1,
		"p_rot": p_rot,
		"dir": dir,
		"span": span,
		"center": center,
		"gradient": g,
		"stops": stops_pts
	}

func _get_annotator_mouse_local(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		if is_inside_tree():
			return get_screen_transform().affine_inverse() * event.global_position
		return get_global_transform().affine_inverse() * event.global_position
	if is_inside_tree():
		var vp := get_viewport()
		if is_instance_valid(vp):
			return get_screen_transform().affine_inverse() * vp.get_mouse_position()
	return Vector2.ZERO

func _draw_gradient_annotator(data: Dictionary, inv: float) -> void:
	var p0: Vector2 = data.p0
	var p1: Vector2 = data.p1
	var is_radial: bool = (data.type == 1)
	var is_conic: bool = (data.type == 2)
	var is_diamond: bool = (data.type == 3)
	var is_box: bool = (data.type == 4)
	var is_spiral: bool = (data.type == 5)
	var is_reflected: bool = (data.type == 6)
	var stops: Array = data.stops
	var num_stops: int = stops.size()
	var last_idx: int = num_stops - 1

	# 1. Línea directriz del degradado con alto contraste (sombra oscura + línea blanca interior)
	var p_end: Vector2 = data.get("p_rot", p1) if (data.type == 0) else p1
	draw_line(p0, p_end, Color(0, 0, 0, 0.5), 3.2 * inv, true)
	draw_line(p0, p_end, Color(1, 1, 1, 0.95), 1.6 * inv, true)

	# 2. Guía según tipo de degradado
	if is_radial:
		draw_arc(p0, data.span, 0.0, TAU, 48, Color(0, 0, 0, 0.4), 2.8 * inv, true)
		draw_arc(p0, data.span, 0.0, TAU, 48, Color(1, 1, 1, 0.9), 1.4 * inv, true)
	elif is_conic:
		var r_arc := maxf(data.span * 0.85, 12.0 * inv)
		var start_ang: float = data.dir.angle()
		draw_arc(p0, r_arc, start_ang, start_ang + TAU * 0.85, 48, Color(0, 0, 0, 0.4), 2.8 * inv, true)
		draw_arc(p0, r_arc, start_ang, start_ang + TAU * 0.85, 48, Color(0.1, 0.65, 1.0, 0.95), 1.5 * inv, true)
		var tip_ang := start_ang + TAU * 0.85
		var tip_p := p0 + Vector2(cos(tip_ang), sin(tip_ang)) * r_arc
		var tangent := Vector2(-sin(tip_ang), cos(tip_ang))
		var norm := Vector2(cos(tip_ang), sin(tip_ang))
		var arr_p1 := tip_p - tangent * (7.5 * inv) + norm * (4.0 * inv)
		var arr_p2 := tip_p - tangent * (7.5 * inv) - norm * (4.0 * inv)
		draw_colored_polygon(PackedVector2Array([tip_p, arr_p1, arr_p2]), Color(0.1, 0.65, 1.0, 1.0))
	elif is_diamond:
		var d_vec: Vector2 = data.dir * data.span
		var d_norm: Vector2 = Vector2(-data.dir.y, data.dir.x) * data.span
		var pts := PackedVector2Array([p0 + d_vec, p0 + d_norm, p0 - d_vec, p0 - d_norm, p0 + d_vec])
		draw_polyline(pts, Color(0, 0, 0, 0.45), 2.8 * inv, true)
		draw_polyline(pts, Color(0.9, 0.45, 1.0, 0.95), 1.4 * inv, true)
	elif is_box:
		var d_vec: Vector2 = data.dir * data.span
		var d_norm: Vector2 = Vector2(-data.dir.y, data.dir.x) * data.span
		var pts := PackedVector2Array([
			p0 + d_vec + d_norm,
			p0 - d_vec + d_norm,
			p0 - d_vec - d_norm,
			p0 + d_vec - d_norm,
			p0 + d_vec + d_norm
		])
		draw_polyline(pts, Color(0, 0, 0, 0.45), 2.8 * inv, true)
		draw_polyline(pts, Color(0.15, 0.85, 0.65, 0.95), 1.4 * inv, true)
	elif is_spiral:
		var spiral_pts := PackedVector2Array()
		var start_ang: float = data.dir.angle()
		var turns := 1.75
		var steps := 36
		for i in range(steps + 1):
			var frac := float(i) / float(steps)
			var cur_ang := start_ang + frac * TAU * turns
			var cur_r: float = float(data.span) * frac
			spiral_pts.append(p0 + Vector2(cos(cur_ang), sin(cur_ang)) * cur_r)
		draw_polyline(spiral_pts, Color(0, 0, 0, 0.45), 2.8 * inv, true)
		draw_polyline(spiral_pts, Color(1.0, 0.65, 0.15, 0.95), 1.4 * inv, true)
	elif is_reflected:
		var p_mirror: Vector2 = p0 - data.dir * data.span
		draw_line(p0, p_mirror, Color(0, 0, 0, 0.4), 2.4 * inv, true)
		draw_line(p0, p_mirror, Color(1, 1, 1, 0.85), 1.2 * inv, true)
		var perp: Vector2 = Vector2(-data.dir.y, data.dir.x) * (data.span * 0.75)
		draw_line(p0 - perp, p0 + perp, Color(0, 0, 0, 0.5), 2.8 * inv, true)
		draw_line(p0 - perp, p0 + perp, Color(0.25, 0.75, 1.0, 0.95), 1.4 * inv, true)

	# 3. Handle inicial (p0) — Stop 0
	var c0: Color = stops[0].color if not stops.is_empty() else Color.WHITE
	var is_p0_sel: bool = (_selected_gradient_stop_idx == 0)
	if is_radial or is_conic or is_diamond or is_box or is_spiral or is_reflected:
		# Centro focal circular
		var r0_circ: float = (7.2 if is_p0_sel else 5.4) * inv
		draw_circle(p0, r0_circ + 2.0 * inv, Color(0, 0, 0, 0.45))
		if is_p0_sel:
			draw_circle(p0, r0_circ + 1.6 * inv, Color(0.05, 0.55, 0.91, 1.0))
		draw_circle(p0, r0_circ, Color.WHITE)
		draw_circle(p0, r0_circ - 1.8 * inv, c0)
	else:
		# Origen lineal (p0 cuadrado con selección activa)
		var side := (12.0 if is_p0_sel else 9.5) * inv
		var r0 := Rect2(p0 - Vector2(side, side) * 0.5, Vector2(side, side))
		draw_rect(r0.grow(2.0 * inv), Color(0, 0, 0, 0.45), true)
		if is_p0_sel:
			draw_rect(r0.grow(1.5 * inv), Color(0.05, 0.55, 0.91, 1.0), true)
		draw_rect(r0, Color.WHITE, true)
		draw_rect(r0.grow(-1.6 * inv), c0, true)

	# 4. Handle final (p1) — Último stop
	var c1: Color = stops[last_idx].color if not stops.is_empty() else Color.BLACK
	var is_p1_sel: bool = (_selected_gradient_stop_idx == last_idx)
	var r_p1 := (7.2 if is_p1_sel else 5.6) * inv
	draw_circle(p1, r_p1 + 2.0 * inv, Color(0, 0, 0, 0.45))
	if is_p1_sel:
		draw_circle(p1, r_p1 + 1.6 * inv, Color(0.05, 0.55, 0.91, 1.0))
	draw_circle(p1, r_p1, Color.WHITE)
	draw_circle(p1, r_p1 - 1.6 * inv, c1)

	# 5. Marcadores de paradas INTERMEDIAS (exclusivamente index > 0 and index < last_idx)
	for s in stops:
		var idx: int = int(s.index)
		if idx <= 0 or idx >= last_idx:
			continue
		var is_sel: bool = (idx == _selected_gradient_stop_idx)
		var sr: float = (6.8 if is_sel else 5.0) * inv
		draw_circle(s.position, sr + 2.0 * inv, Color(0, 0, 0, 0.45))
		if is_sel:
			draw_circle(s.position, sr + 1.6 * inv, Color(0.05, 0.55, 0.91, 1.0))
		draw_circle(s.position, sr, Color.WHITE)
		draw_circle(s.position, sr - 1.6 * inv, s.color)

	# 6. Handle de rotación/dirección en la punta extendida (solo en lineal, tipo 0)
	if data.type == 0 and data.has("p_rot"):
		var p_rot: Vector2 = data.p_rot
		var r_end := 4.8 * inv
		draw_circle(p_rot, r_end + 1.8 * inv, Color(0, 0, 0, 0.45))
		draw_circle(p_rot, r_end + 1.0 * inv, Color.WHITE)
		draw_circle(p_rot, r_end, Color(0.1, 0.55, 0.92, 1.0))

func _hit_gradient_annotator(local_pos: Vector2, inv: float) -> Dictionary:
	if not has_gradient_annotator():
		return {"hit": "none"}
	var data := _get_gradient_annotator_data()
	if data.is_empty():
		return {"hit": "none"}
	var thresh: float = GRAD_HIT_PX * inv
	var thresh_sq := thresh * thresh

	# 1. Handle inicial (p0) -> índice 0
	if local_pos.distance_squared_to(data.p0) <= thresh_sq:
		return {"hit": "start", "index": 0, "data": data}

	# 2. Handle final (p1) -> último índice
	var last_idx: int = data.stops.size() - 1 if not data.stops.is_empty() else 1
	if local_pos.distance_squared_to(data.p1) <= thresh_sq:
		return {"hit": "end", "index": last_idx, "data": data}

	# 3. Stops intermedios (excluyendo extremos 0 y último para no solapar p0/p1)
	var stops: Array = data.stops
	var stop_thresh_sq := (thresh * 1.15) * (thresh * 1.15)
	for s in stops:
		var idx: int = int(s.index)
		if idx > 0 and idx < stops.size() - 1:
			if local_pos.distance_squared_to(s.position) <= stop_thresh_sq:
				return {"hit": "stop", "index": idx, "data": data}

	# 4. Handle de rotación en punta extendida (solo en modo lineal, tipo 0)
	if data.type == 0:
		var p_rot: Vector2 = data.get("p_rot", data.p1)
		if local_pos.distance_squared_to(p_rot) <= thresh_sq:
			return {"hit": "rot", "data": data}

	# 5. Línea (arrastrar la línea completa o clic para añadir nuevo stop)
	var line_vec: Vector2 = data.p1 - data.p0
	var len_sq: float = line_vec.length_squared()
	if len_sq > 0.0001:
		var t: float = clampf((local_pos - data.p0).dot(line_vec) / len_sq, 0.0, 1.0)
		var proj: Vector2 = data.p0 + line_vec * t
		if local_pos.distance_squared_to(proj) <= (thresh * 0.85) * (thresh * 0.85):
			return {"hit": "line", "ratio": t, "data": data}

	return {"hit": "none", "data": data}

func _handle_annotator_input(event: InputEvent, custom_local_pos: Variant = null) -> bool:
	if not is_instance_valid(_bound_shape):
		return false
	if not has_gradient_annotator():
		return false
	
	# Soporte para borrar stop seleccionado con Delete / Backspace (solo stops intermedios)
	if event is InputEventKey and event.pressed:
		if (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE) and _selected_gradient_stop_idx >= 0:
			var g: Gradient = _bound_shape.fill_gradient
			if is_instance_valid(g) and g.get_point_count() > 2:
				if _selected_gradient_stop_idx > 0 and _selected_gradient_stop_idx < g.get_point_count() - 1:
					g.remove_point(_selected_gradient_stop_idx)
					_selected_gradient_stop_idx = clampi(_selected_gradient_stop_idx - 1, 0, g.get_point_count() - 1)
					_bound_shape.queue_redraw()
					queue_redraw()
					_notify_stop_selected(g.get_color(_selected_gradient_stop_idx))
					_notify_gradient_changed()
					return true

	if not (event is InputEventMouse):
		return false

	var inv: float = _zoom_comp(_get_zoom_scale())
	var local_pos: Vector2 = custom_local_pos if custom_local_pos != null else _get_annotator_mouse_local(event)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit_info := _hit_gradient_annotator(local_pos, inv)
			var mode: String = hit_info.get("hit", "none")
			if mode != "none":
				_annotator_drag_mode = mode
				var g: Gradient = _bound_shape.fill_gradient
				_annotator_undo_state = {
					"angle": _bound_shape.fill_gradient_angle,
					"p0": _bound_shape.get_gradient_p0_norm(),
					"p1": _bound_shape.get_gradient_p1_norm(),
					"offsets": [],
					"colors": []
				}
				if is_instance_valid(g):
					for i in range(g.get_point_count()):
						_annotator_undo_state["offsets"].append(g.get_offset(i))
						_annotator_undo_state["colors"].append(g.get_color(i))

				if mode == "start":
					_selected_gradient_stop_idx = 0
					if is_instance_valid(g) and g.get_point_count() > 0:
						_notify_stop_selected(g.get_color(0))
				elif mode == "end":
					if is_instance_valid(g) and g.get_point_count() > 0:
						_selected_gradient_stop_idx = g.get_point_count() - 1
						_notify_stop_selected(g.get_color(_selected_gradient_stop_idx))
				elif mode == "stop":
					_annotator_drag_stop_idx = hit_info.get("index", 0)
					_selected_gradient_stop_idx = _annotator_drag_stop_idx
					if is_instance_valid(g) and _selected_gradient_stop_idx < g.get_point_count():
						if event.alt_pressed:
							# Alt + Drag: Duplicar stop en esa posición
							var orig_off := g.get_offset(_selected_gradient_stop_idx)
							var orig_col := g.get_color(_selected_gradient_stop_idx)
							g.add_point(orig_off, orig_col)
							for i in range(g.get_point_count()):
								if is_equal_approx(g.get_offset(i), orig_off) and g.get_color(i) == orig_col:
									_annotator_drag_stop_idx = i
									_selected_gradient_stop_idx = i
									break
						var c: Color = g.get_color(_selected_gradient_stop_idx)
						_notify_stop_selected(c)
				elif mode == "rot":
					_annotator_drag_mode = "rot"
					_annotator_drag_stop_idx = -1
				elif mode == "line":
					_line_drag_start_pos = local_pos
					_line_drag_start_p0 = _bound_shape.get_gradient_p0_norm()
					_line_drag_start_p1 = _bound_shape.get_gradient_p1_norm()
					_line_drag_has_moved = false
					_line_click_ratio = float(hit_info.get("ratio", 0.5))
				queue_redraw()
				return true
			elif is_gradient_active():
				# Clic en el canvas o sobre la figura con modo degradado activo:
				# Preparar posible nuevo arrastre de degradado SIN sobreescribir el color aún
				_annotator_drag_mode = "drag_new"
				_line_drag_start_pos = local_pos
				var sz := size if size.x > 0 and size.y > 0 else Vector2(100, 100)
				_line_drag_start_p0 = Vector2(local_pos.x / sz.x, local_pos.y / sz.y)
				_line_drag_has_moved = false
				_annotator_undo_state = {
					"angle": _bound_shape.fill_gradient_angle,
					"p0": _bound_shape.get_gradient_p0_norm(),
					"p1": _bound_shape.get_gradient_p1_norm(),
					"offsets": [],
					"colors": []
				}
				var g: Gradient = _bound_shape.fill_gradient
				if is_instance_valid(g):
					for i in range(g.get_point_count()):
						_annotator_undo_state["offsets"].append(g.get_offset(i))
						_annotator_undo_state["colors"].append(g.get_color(i))
				queue_redraw()
				return true
		else:
			if _annotator_drag_mode != "":
				if _annotator_drag_mode == "line" and not _line_drag_has_moved:
					# Clic sin arrastrar sobre la línea: añadir parada de color
					var g: Gradient = _bound_shape.fill_gradient
					if is_instance_valid(g):
						var col: Color = g.sample(_line_click_ratio)
						g.add_point(_line_click_ratio, col)
						_annotator_drag_stop_idx = -1
						for i in range(g.get_point_count()):
							if is_equal_approx(g.get_offset(i), _line_click_ratio):
								_annotator_drag_stop_idx = i
								_selected_gradient_stop_idx = i
								break
						_bound_shape.queue_redraw()
						queue_redraw()
						_notify_stop_selected(col)
						_notify_gradient_changed()
				elif _annotator_drag_mode == "drag_new":
					if _line_drag_has_moved:
						_commit_annotator_undo()
				else:
					_commit_annotator_undo()
				_annotator_drag_mode = ""
				_annotator_drag_stop_idx = -1
				_line_drag_has_moved = false
				queue_redraw()
				return true

	elif event is InputEventMouseMotion:
		if _annotator_drag_mode != "":
			var data := _get_gradient_annotator_data()
			if data.is_empty():
				return true
			var sz := size if size.x > 0 and size.y > 0 else Vector2(100, 100)
			if _annotator_drag_mode == "line":
				if not _line_drag_has_moved and local_pos.distance_squared_to(_line_drag_start_pos) > (3.0 * inv) * (3.0 * inv):
					_line_drag_has_moved = true
				if _line_drag_has_moved:
					var delta_local := local_pos - _line_drag_start_pos
					var delta_norm := Vector2(delta_local.x / sz.x, delta_local.y / sz.y)
					_bound_shape.set_gradient_points(_line_drag_start_p0 + delta_norm, _line_drag_start_p1 + delta_norm)
					_bound_shape.queue_redraw()
					queue_redraw()
					_notify_gradient_changed()
				return true
			elif _annotator_drag_mode == "end":
				var target_pos := local_pos
				if event.shift_pressed:
					var data_p0: Vector2 = data.p0
					var ang: float = (target_pos - data_p0).angle()
					var snap_ang := roundf(ang / (PI / 4.0)) * (PI / 4.0)
					var dist: float = (target_pos - data_p0).length()
					target_pos = data_p0 + Vector2(cos(snap_ang), sin(snap_ang)) * dist
				var norm_p1 := Vector2(target_pos.x / sz.x, target_pos.y / sz.y)
				_bound_shape.set_gradient_endpoint_1(norm_p1)
				_bound_shape.queue_redraw()
				queue_redraw()
				_notify_gradient_changed()
				return true
			elif _annotator_drag_mode == "start":
				var target_pos := local_pos
				if event.shift_pressed:
					var data_p1: Vector2 = data.p1
					var ang: float = (data_p1 - target_pos).angle()
					var snap_ang := roundf(ang / (PI / 4.0)) * (PI / 4.0)
					var dist: float = (data_p1 - target_pos).length()
					target_pos = data_p1 - Vector2(cos(snap_ang), sin(snap_ang)) * dist
				var norm_p0 := Vector2(target_pos.x / sz.x, target_pos.y / sz.y)
				_bound_shape.set_gradient_endpoint_0(norm_p0)
				_bound_shape.queue_redraw()
				queue_redraw()
				_notify_gradient_changed()
				return true
			elif _annotator_drag_mode == "rot":
				var norm_p0 := _bound_shape.get_gradient_p0_norm()
				var p0_loc: Vector2 = data.p0
				var cur_span: float = data.span
				var new_ang: float = (local_pos - p0_loc).angle()
				if event.shift_pressed:
					new_ang = roundf(new_ang / (PI / 4.0)) * (PI / 4.0)
				var new_p1_loc: Vector2 = p0_loc + Vector2(cos(new_ang), sin(new_ang)) * cur_span
				var norm_p1 := Vector2(new_p1_loc.x / sz.x, new_p1_loc.y / sz.y)
				_bound_shape.set_gradient_points(norm_p0, norm_p1)
				_bound_shape.queue_redraw()
				queue_redraw()
				_notify_gradient_changed()
				return true
			elif _annotator_drag_mode == "stop" and _annotator_drag_stop_idx >= 0:
				var g: Gradient = _bound_shape.fill_gradient
				if is_instance_valid(g) and _annotator_drag_stop_idx < g.get_point_count():
					var line_vec: Vector2 = data.p1 - data.p0
					var len_sq := maxf(line_vec.length_squared(), 0.0001)
					var t: float = clampf((local_pos - data.p0).dot(line_vec) / len_sq, 0.01, 0.99)
					if event.shift_pressed:
						t = clampf(roundf(t * 4.0) / 4.0, 0.01, 0.99)
					var target_col: Color = g.get_color(_annotator_drag_stop_idx)
					g.set_offset(_annotator_drag_stop_idx, t)
					for i in range(g.get_point_count()):
						if is_equal_approx(g.get_offset(i), t) and g.get_color(i) == target_col:
							_annotator_drag_stop_idx = i
							_selected_gradient_stop_idx = i
							break
					_bound_shape.queue_redraw()
					queue_redraw()
					_notify_gradient_changed()
				return true
			elif _annotator_drag_mode == "drag_new":
				if not _line_drag_has_moved and local_pos.distance_squared_to(_line_drag_start_pos) > (4.0 * inv) * (4.0 * inv):
					_line_drag_has_moved = true
					if not _bound_shape.has_gradient_fill():
						ensure_shape_gradient_fill()
				if _line_drag_has_moved:
					var cur_norm := Vector2(local_pos.x / sz.x, local_pos.y / sz.y)
					_bound_shape.set_gradient_points(_line_drag_start_p0, cur_norm)
					_bound_shape.queue_redraw()
					queue_redraw()
					_notify_gradient_changed()
				return true
		else:
			var hit_info := _hit_gradient_annotator(local_pos, inv)
			var hmode: String = hit_info.get("hit", "none")
			if hmode == "line":
				mouse_default_cursor_shape = Control.CURSOR_MOVE
				Input.set_default_cursor_shape(Input.CURSOR_MOVE)
				return true
			elif hmode in ["start", "end", "rot", "stop"]:
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
				return true
			elif is_gradient_active():
				mouse_default_cursor_shape = Control.CURSOR_CROSS
				Input.set_default_cursor_shape(Input.CURSOR_CROSS)
				return false
			else:
				mouse_default_cursor_shape = Control.CURSOR_ARROW
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				return false

	return false

func _notify_gradient_changed() -> void:
	if not is_instance_valid(_bound_shape):
		return
	if GlobalEvents.has_signal("object_style_changed"):
		GlobalEvents.object_style_changed.emit()
	if GlobalEvents.has_signal("gradient_changed") and _bound_shape.fill_gradient:
		GlobalEvents.gradient_changed.emit(_bound_shape.fill_gradient)

func _notify_stop_selected(c: Color) -> void:
	if GlobalEvents and GlobalEvents.has_signal("gradient_stop_selected"):
		GlobalEvents.gradient_stop_selected.emit(c, _selected_gradient_stop_idx)

func _commit_annotator_undo() -> void:
	if not is_instance_valid(_bound_shape) or not _bound_shape.has_gradient_fill():
		return
	var shape := _bound_shape
	var g: Gradient = shape.fill_gradient
	if g == null:
		return

	var old_angle: float = float(_annotator_undo_state.get("angle", 0.0))
	var new_angle: float = shape.fill_gradient_angle
	var old_p0: Vector2 = _annotator_undo_state.get("p0", Vector2(-1, -1))
	var new_p0: Vector2 = shape.fill_gradient_p0
	var old_p1: Vector2 = _annotator_undo_state.get("p1", Vector2(-1, -1))
	var new_p1: Vector2 = shape.fill_gradient_p1
	var old_offsets: Array = _annotator_undo_state.get("offsets", []).duplicate()
	var old_colors: Array = _annotator_undo_state.get("colors", []).duplicate()

	var new_offsets: Array = []
	var new_colors: Array = []
	for i in range(g.get_point_count()):
		new_offsets.append(g.get_offset(i))
		new_colors.append(g.get_color(i))

	if old_p0 == new_p0 and old_p1 == new_p1 and is_equal_approx(old_angle, new_angle) and old_offsets == new_offsets and old_colors == new_colors:
		return

	var hm := get_node_or_null("/root/HistoryManager")
	if hm == null:
		return

	hm.register_action("Ajustar Degradado en Canvas")
	hm.add_do(func():
		if not is_instance_valid(shape): return
		shape.fill_gradient_p0 = new_p0
		shape.fill_gradient_p1 = new_p1
		shape._internal_point_update = true
		shape.fill_gradient_angle = new_angle
		shape._internal_point_update = false
		if shape.fill_gradient:
			var fg: Gradient = shape.fill_gradient
			for i in range(new_offsets.size()):
				if i < fg.get_point_count():
					fg.set_offset(i, new_offsets[i])
					fg.set_color(i, new_colors[i])
				else:
					fg.add_point(new_offsets[i], new_colors[i])
			while fg.get_point_count() > new_offsets.size() and fg.get_point_count() > 1:
				fg.remove_point(fg.get_point_count() - 1)
		shape.queue_redraw()
		if GlobalEvents.has_signal("object_style_changed"):
			GlobalEvents.object_style_changed.emit()
	)
	hm.add_undo(func():
		if not is_instance_valid(shape): return
		shape.fill_gradient_p0 = old_p0
		shape.fill_gradient_p1 = old_p1
		shape._internal_point_update = true
		shape.fill_gradient_angle = old_angle
		shape._internal_point_update = false
		if shape.fill_gradient:
			var fg: Gradient = shape.fill_gradient
			for i in range(old_offsets.size()):
				if i < fg.get_point_count():
					fg.set_offset(i, old_offsets[i])
					fg.set_color(i, old_colors[i])
				else:
					fg.add_point(old_offsets[i], old_colors[i])
			while fg.get_point_count() > old_offsets.size() and fg.get_point_count() > 1:
				fg.remove_point(fg.get_point_count() - 1)
		shape.queue_redraw()
		if GlobalEvents.has_signal("object_style_changed"):
			GlobalEvents.object_style_changed.emit()
	)
	hm.commit()
