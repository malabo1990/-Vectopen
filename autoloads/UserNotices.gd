# =============================================================================
# RUTA: res://autoloads/UserNotices.gd
# Avisos para el usuario al estilo «Dynamic Island»: una cápsula negra arriba
# en el centro que nace pequeña, se expande con un muelle suave enseñando un
# icono de color y el mensaje, y se recoge al terminar. Un aviso cada vez; los
# demás esperan en cola. Clic en la cápsula = cerrar.
#
# Muestra GlobalEvents.user_notice(level, message) y los errores de exportar /
# importar, que antes se emitían sin que nadie los enseñara.
# =============================================================================
extends CanvasLayer

const SHOW_SECONDS := {"info": 3.5, "success": 3.0, "warning": 6.0, "error": 9.0}
const ACCENT := {
	"info": Color("#3e8bff"), "success": Color("#30d158"),
	"warning": Color("#ffb020"), "error": Color("#ff453a"),
}
const GLYPH := {"info": "i", "success": "✓", "warning": "!", "error": "!"}
const PILL_H := 40.0          # alto de la cápsula recogida
const PILL_W := 126.0         # ancho de la cápsula recogida
const MAX_W := 560.0          # ancho máximo expandida
const TOP := 8.0              # distancia al borde superior
const MAX_QUEUE := 6

## Contenedor raíz (las pruebas lo buscan por nombre).
var _box: Control
## Últimos avisos mostrados [level, message] — para pruebas y depuración.
var history: Array = []
var _queue: Array = []
var _busy := false
var _current: Control = null
var _hide_timer: SceneTreeTimer = null

func _ready() -> void:
	layer = 120
	_box = Control.new()
	_box.name = "Notices"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_box)
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge:
		if ge.has_signal("user_notice"):
			ge.user_notice.connect(show_notice)
		if ge.has_signal("export_error"):
			ge.export_error.connect(_on_export_error)
		if ge.has_signal("import_error"):
			ge.import_error.connect(_on_import_error)

func _on_export_error(fmt = "", msg = "") -> void:
	show_notice("error", ("No se pudo exportar %s: %s" % [str(fmt), str(msg)]) if str(msg) != "" else "No se pudo exportar %s." % str(fmt))

func _on_import_error(fmt = "", msg = "") -> void:
	show_notice("error", ("No se pudo importar %s: %s" % [str(fmt), str(msg)]) if str(msg) != "" else "No se pudo importar %s." % str(fmt))

## Muestra un aviso. level: "info" | "success" | "warning" | "error".
func show_notice(level: String, message: String) -> void:
	history.append([level, message])
	if history.size() > 50:
		history.pop_front()
	if _queue.size() >= MAX_QUEUE:
		_queue.pop_front()
	_queue.append([level, message])
	if not _busy:
		_next()

func _next() -> void:
	if _queue.is_empty() or not is_instance_valid(_box):
		_busy = false
		return
	_busy = true
	var item: Array = _queue.pop_front()
	_present(String(item[0]), String(item[1]))

# ── cápsula ──────────────────────────────────────────────────────────────────
func _present(level: String, message: String) -> void:
	var accent: Color = ACCENT.get(level, ACCENT["info"])
	var pill := Panel.new()   # Panel (no contenedor): no impone tamaño mínimo y deja animar
	pill.name = "Island"
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.clip_contents = true
	pill.tooltip_text = "Clic para cerrar"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.94)
	sb.set_corner_radius_all(int(PILL_H / 2.0))
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.anti_aliasing = true
	pill.add_theme_stylebox_override("panel", sb)

	# Medidas finales: una línea si cabe; si no, envuelto en MAX_W.
	const PAD_L := 8.0
	const DOT := 28.0
	const GAP := 10.0
	const PAD_R := 18.0
	var probe := Label.new()
	var font: Font = probe.get_theme_font("font")
	probe.free()
	var fs := 13
	var one_line := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2.0
	var max_text := MAX_W - (PAD_L + DOT + GAP + PAD_R)
	var text_w := minf(one_line, max_text)
	var text_h := font.get_multiline_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, text_w, fs).y
	var target_w := clampf(PAD_L + DOT + GAP + text_w + PAD_R, PILL_W, MAX_W)
	var target_h := maxf(PILL_H, text_h + 16.0)
	if target_h > PILL_H:
		sb.set_corner_radius_all(22)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(PAD_L, (target_h - maxf(DOT, text_h)) / 2.0)
	row.size = Vector2(DOT + GAP + text_w, maxf(DOT, text_h))
	pill.add_child(row)

	# Icono: círculo de color con un símbolo.
	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(DOT, DOT)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = accent
	dsb.set_corner_radius_all(int(DOT / 2.0))
	dsb.anti_aliasing = true
	dot.add_theme_stylebox_override("panel", dsb)
	var glyph := Label.new()
	glyph.text = GLYPH.get(level, "i")
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_color_override("font_color", Color.BLACK if level in ["warning", "success"] else Color.WHITE)
	glyph.add_theme_font_size_override("font_size", 15)
	dot.add_child(glyph)
	row.add_child(dot)

	var lbl := Label.new()
	lbl.name = "Message"
	lbl.text = message
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if one_line > max_text else TextServer.AUTOWRAP_OFF
	lbl.custom_minimum_size = Vector2(text_w, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	lbl.add_theme_font_size_override("font_size", fs)
	lbl.modulate.a = 0.0
	row.add_child(lbl)

	_box.add_child(pill)
	_current = pill
	pill.gui_input.connect(_on_pill_input)

	var vw := _box.get_viewport_rect().size.x
	pill.size = Vector2(PILL_W * 0.55, PILL_H * 0.8)
	pill.position = Vector2((vw - pill.size.x) / 2.0, TOP)
	pill.modulate.a = 0.0

	# Entrada: nace como punto, crece a cápsula y se expande con muelle.
	var tw := pill.create_tween().set_parallel(true)
	tw.tween_property(pill, "modulate:a", 1.0, 0.12)
	tw.tween_property(pill, "size", Vector2(target_w, target_h), 0.5).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tw.tween_property(pill, "position:x", (vw - target_w) / 2.0, 0.5).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.25).set_delay(0.18)

	var cid := pill.get_instance_id()
	_hide_timer = get_tree().create_timer(SHOW_SECONDS.get(level, 5.0))
	_hide_timer.timeout.connect(_dismiss_by_id.bind(cid))

func _on_pill_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and is_instance_valid(_current):
		_dismiss_by_id(_current.get_instance_id())

func _dismiss_by_id(cid: int) -> void:
	var pill := instance_from_id(cid) as Control
	if pill == null or pill.is_queued_for_deletion() or pill.has_meta(&"closing"):
		return
	pill.set_meta(&"closing", true)
	var vw := _box.get_viewport_rect().size.x
	var lbl := pill.find_child("Message", true, false) as Control
	# Salida: el texto se apaga, la cápsula se recoge hacia el centro y se va.
	var tw := pill.create_tween()
	if lbl:
		tw.tween_property(lbl, "modulate:a", 0.0, 0.12)
	tw.set_parallel(true)
	tw.tween_property(pill, "size", Vector2(PILL_W * 0.55, PILL_H * 0.8), 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(pill, "position:x", (vw - PILL_W * 0.55) / 2.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(pill, "modulate:a", 0.0, 0.22).set_delay(0.12)
	tw.chain().tween_callback(_finish_by_id.bind(cid))

func _finish_by_id(cid: int) -> void:
	var pill := instance_from_id(cid) as Node
	if pill:
		pill.queue_free()
	if _current != null and (not is_instance_valid(_current) or _current.get_instance_id() == cid):
		_current = null
	_next()
