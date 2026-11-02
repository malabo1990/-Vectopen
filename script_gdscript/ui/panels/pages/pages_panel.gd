# =============================================================================
# VECTOPEN — PANEL DE PÁGINAS (para documentos grandes: 500+ páginas)
# RUTA: res://script_gdscript/ui/panels/pages/pages_panel.gd
# Estilo InDesign / Affinity Publisher:
#   · rejilla de MINIATURAS virtualizada: un solo Control que dibuja solo las
#     celdas visibles (no un nodo por página) → fluido con cientos de páginas;
#   · miniaturas en segundo plano, una a la vez, solo de lo visible, en caché;
#     la de la página editada se rehace al cambiar el documento;
#   · número + nombre, la activa resaltada; clic = ir a la página, doble clic =
#     encuadrarla; Mayús / Ctrl = selección múltiple;
#   · «Ir a» por número, tamaño de miniatura, añadir / duplicar / borrar
#     (con deshacer) y reordenar arrastrando (la fila del lienzo se recoloca);
#   · tres MODOS DE VISTA (se recuerdan entre sesiones):
#       SIMPLE – miniaturas de tamaño fijo, tantas por fila como quepan;
#       SPREAD – pliegos enfrentados como InDesign: la portada sola (a la
#                derecha) y luego 2‑3, 4‑5…; con un nº par de páginas la
#                última queda sola a la izquierda;
#       GRID   – retícula: N columnas que llenan el ancho del panel (redes
#                sociales, carteles); el deslizador elige las columnas.
# =============================================================================
class_name PagesPanel
extends VBoxContainer

const FxUI = preload("res://script_gdscript/ui/panels/effects/fx_ui.gd")
const GAP := 80.0                 # separación entre páginas en el lienzo
const LABEL_H := 18.0             # alto del número / nombre bajo la miniatura
const CELL_PAD := 8.0

var thumb_w := 96.0               # ancho de miniatura (slider)
var selected := {}                # artboard → true
var _anchor: Node2D = null        # para Mayús+clic (rango)
var _cache := {}                  # instance_id → {"tex": Texture2D, "dirty": bool}
var _rendering := false
var _count: Label = null
var _goto: LineEdit = null
var _scroll: ScrollContainer = null
var grid: Control = null
var _drag_from := -1
var _drop_at := -1

enum ViewMode { SIMPLE, SPREAD, GRID }
const PREFS := "user://vectopen_pages.cfg"
const MODE_NAMES := ["simple", "spread", "grid"]
const SPREAD_GAP := 14.0          # separación entre pliegos
var view_mode: int = ViewMode.SIMPLE
var grid_cols := 3                # columnas en modo rejilla
var _mode_btns: Array[Button] = []
var _zoom: HSlider = null
## Celdas calculadas para el modo actual: índice de página → Rect2.
var _rects: Array[Rect2] = []
var _content_h := 0.0
var _laid_w := -1.0

func _init() -> void:
	name = "PagesPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	add_child(head)
	var title := Label.new()
	title.text = "PÁGINAS"
	title.add_theme_font_size_override("font_size", 11)
	title.set_meta("muted", true)
	head.add_child(title)
	_count = Label.new()
	_count.name = "Count"
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.add_theme_font_size_override("font_size", 10)
	_count.set_meta("muted", true)
	head.add_child(_count)
	_goto = LineEdit.new()
	_goto.name = "GoTo"
	_goto.placeholder_text = "Ir a…"
	_goto.tooltip_text = "Escribe el número de página e Intro"
	_goto.custom_minimum_size = Vector2(58, 22)
	_goto.add_theme_font_size_override("font_size", 11)
	_goto.text_submitted.connect(func(t: String) -> void:
		if t.strip_edges().is_valid_int():
			go_to_page(int(t) - 1)
		_goto.text = ""
		_goto.release_focus())
	head.add_child(_goto)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	for spec in [["Add", "", "Añadir página (después de la activa)", add_page, "res://icon/UI/frame-plus-in.svg"],
			["Duplicate", "", "Duplicar las páginas seleccionadas", duplicate_selected, "res://icon/UI/copy.svg"],
			["Delete", "", "Borrar las páginas seleccionadas (Supr)", delete_selected, "res://icon/UI/trash.svg"]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[1]
		b.set_meta("icon_path", spec[4])
		b.tooltip_text = spec[2]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(28, 24)
		b.pressed.connect(spec[3])
		bar.add_child(b)
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(6, 0)
	bar.add_child(sep)
	var group := ButtonGroup.new()
	for spec in [["ModeSimple", "▯", "Página simple: miniaturas en fila", ViewMode.SIMPLE],
			["ModeSpread", "▯▯", "Pliegos enfrentados (libro): portada sola y luego 2‑3, 4‑5…", ViewMode.SPREAD],
			["ModeGrid", "▦", "Rejilla: columnas que llenan el panel (redes sociales, carteles)", ViewMode.GRID]]:
		var mb := Button.new()
		mb.name = spec[0]
		mb.text = spec[1]
		mb.tooltip_text = spec[2]
		mb.toggle_mode = true
		mb.button_group = group
		mb.focus_mode = Control.FOCUS_NONE
		mb.custom_minimum_size = Vector2(28, 24)
		mb.add_theme_font_size_override("font_size", 12)
		var m: int = spec[3]
		mb.pressed.connect(func() -> void: set_view_mode(m))
		bar.add_child(mb)
		_mode_btns.append(mb)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var zoom := HSlider.new()
	zoom.name = "ThumbSize"
	zoom.min_value = 56
	zoom.max_value = 220
	zoom.step = 4
	zoom.value = thumb_w
	zoom.tooltip_text = "Tamaño de las miniaturas"
	zoom.custom_minimum_size = Vector2(80, 0)
	zoom.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zoom.value_changed.connect(_on_zoom)
	bar.add_child(zoom)
	_zoom = zoom

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Barra siempre presente: si apareciera y desapareciera, el ancho útil
	# cambiaría con la altura y la rejilla (que depende del ancho) se
	# recalcularía sin fin.
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_scroll.custom_minimum_size = Vector2(0, 160)
	add_child(_scroll)
	grid = Control.new()
	grid.name = "Grid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.focus_mode = Control.FOCUS_CLICK
	grid.draw.connect(_draw_grid)
	grid.gui_input.connect(_on_grid_input)
	grid.resized.connect(func() -> void:
		if absf(grid.size.x - _laid_w) > 0.5:
			_relayout())
	_scroll.add_child(grid)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: grid.queue_redraw())

func _ready() -> void:
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge:
		for sig in ["artboard_created", "artboard_deleted", "object_created", "object_deleted"]:
			if ge.has_signal(sig):
				ge.connect(sig, func(_a = null, _b = null) -> void: _on_doc_changed())
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_signal("history_changed"):
		hm.history_changed.connect(func(_a = null, _b = null, _c = null, _d = null) -> void: _on_doc_changed())
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m) -> void: restyle())
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())
	_load_prefs()
	restyle()
	refresh()

func _process(_dt: float) -> void:
	# sin pantalla (pruebas) no hay nada que ver: no generar miniaturas
	if is_visible_in_tree() and not _rendering and DisplayServer.get_name() != "headless":
		_render_next()

# ── datos ────────────────────────────────────────────────────────────────────
func _mgr() -> Node:
	return ArtboardManager.find(get_tree()) if is_inside_tree() else null

## Páginas en orden (el de los hijos del contenedor).
func pages() -> Array:
	var m := _mgr()
	if m == null:
		return []
	var out: Array = []
	for ab in m.all_artboards():
		if ab.is_inside_tree():
			out.append(ab)
	# orden REAL (hijos del contenedor): all_artboards() va por orden de creación
	out.sort_custom(func(a: Node, b: Node) -> bool: return a.get_index() < b.get_index())
	return out

func active() -> Node2D:
	var m := _mgr()
	return m.get_active_artboard() if m else null

func _api():
	var pm := get_node_or_null("/root/PluginManager")
	return pm.api if pm else null

func refresh() -> void:
	var ps := pages()
	for ab in selected.keys():
		if not is_instance_valid(ab) or not ps.has(ab):
			selected.erase(ab)
	var a := active()
	var idx := ps.find(a)
	if _count:
		_count.text = ("%d páginas" % ps.size()) if idx < 0 else ("%d de %d" % [idx + 1, ps.size()])
	_relayout()

## Algo cambió en el documento: rehacer la miniatura de la página activa.
func _on_doc_changed() -> void:
	var a := active()
	if a and _cache.has(a.get_instance_id()):
		_cache[a.get_instance_id()]["dirty"] = true
	if is_visible_in_tree():
		refresh()

# ── modo de vista ────────────────────────────────────────────────────────────
## Cambia el modo. Conserva la selección y deja a la vista la página que se
## veía arriba (no salta al principio).
func set_view_mode(m: int) -> void:
	m = clampi(m, ViewMode.SIMPLE, ViewMode.GRID)
	# Qué página dejar a la vista: la activa si se veía; si no, la de arriba.
	var keep := _first_visible_index()
	var ai := pages().find(active())
	if ai >= 0 and grid:
		var vr := _visible_range()
		if vr.x <= ai and ai <= vr.y:
			keep = ai
	view_mode = m
	_sync_mode_ui()
	_cache.clear()          # otra resolución de miniatura
	_relayout()
	_save_prefs()
	if keep >= 0 and _scroll:
		_restore_scroll(keep)

## El contenedor aplica la nueva altura al fotograma siguiente: antes de eso
## el desplazamiento se recortaría a la altura vieja.
func _restore_scroll(i: int) -> void:
	await get_tree().process_frame
	if not is_instance_valid(_scroll) or i >= pages().size():
		return
	var r := _cell_rect(i)
	_scroll.scroll_vertical = int(maxf(0.0, r.get_center().y - _scroll.size.y * 0.5))
	grid.queue_redraw()

func _on_zoom(v: float) -> void:
	if view_mode == ViewMode.GRID:
		grid_cols = int(v)
	else:
		thumb_w = v
	_cache.clear()          # nueva resolución
	_relayout()
	_save_prefs()

## El deslizador es «tamaño» en Simple / Pliegos y «columnas» en Rejilla.
func _sync_mode_ui() -> void:
	for k in _mode_btns.size():
		_mode_btns[k].set_pressed_no_signal(k == view_mode)
	if _zoom == null:
		return
	_zoom.set_block_signals(true)
	if view_mode == ViewMode.GRID:
		_zoom.min_value = 1
		_zoom.max_value = 8
		_zoom.step = 1
		_zoom.value = grid_cols
		_zoom.tooltip_text = "Columnas de la rejilla"
	else:
		_zoom.min_value = 56
		_zoom.max_value = 220
		_zoom.step = 4
		_zoom.value = thumb_w
		_zoom.tooltip_text = "Tamaño de las miniaturas"
	_zoom.set_block_signals(false)

func _load_prefs() -> void:
	var cf := ConfigFile.new()
	if cf.load(PREFS) == OK:
		view_mode = MODE_NAMES.find(String(cf.get_value("pages", "view_mode", "simple")))
		if view_mode < 0:
			view_mode = ViewMode.SIMPLE
		thumb_w = clampf(float(cf.get_value("pages", "thumb_w", thumb_w)), 56.0, 220.0)
		grid_cols = clampi(int(cf.get_value("pages", "grid_cols", grid_cols)), 1, 8)
	_sync_mode_ui()

func _save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.set_value("pages", "view_mode", MODE_NAMES[view_mode])
	cf.set_value("pages", "thumb_w", thumb_w)
	cf.set_value("pages", "grid_cols", grid_cols)
	cf.save(PREFS)

# ── geometría (una celda por página, según el modo) ──────────────────────────
## Ancho de la miniatura en el modo actual.
func _box_w() -> float:
	var w := maxf(grid.size.x if grid else 0.0, 1.0)
	match view_mode:
		ViewMode.GRID:
			return maxf(24.0, (w - 4.0) / grid_cols - CELL_PAD * 2.0)
		ViewMode.SPREAD:
			# dos páginas por pliego: que quepa al menos uno
			return minf(thumb_w, maxf(24.0, (w - 8.0) * 0.5 - CELL_PAD))
	return thumb_w

func _cell_size() -> Vector2:
	var bw := _box_w()
	return Vector2(bw + CELL_PAD * 2.0, bw * 1.414 + LABEL_H + CELL_PAD * 2.0)

func _cols() -> int:
	if view_mode == ViewMode.GRID:
		return grid_cols
	return maxi(1, int(floor(maxf(grid.size.x, 1.0) / _cell_size().x)))

## Pliegos: [[0], [1, 2], [3, 4], …] (la portada sola).
static func spreads(n: int) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	out.append([0])
	var i := 1
	while i < n:
		out.append([i, i + 1] if i + 1 < n else [i])
		i += 2
	return out

func _build_rects() -> void:
	_rects.clear()
	var n := pages().size()
	var cs := _cell_size()
	var w := maxf(grid.size.x, 1.0)
	if view_mode == ViewMode.SPREAD:
		var y := 0.0
		var pair_w := cs.x * 2.0
		@warning_ignore("confusable_local_declaration")
		var x0 := (w - pair_w) * 0.5
		_rects.resize(n)
		for sp in spreads(n):
			if sp.size() == 2:
				_rects[sp[0]] = Rect2(Vector2(x0, y), cs)                 # par, izquierda
				_rects[sp[1]] = Rect2(Vector2(x0 + cs.x, y), cs)          # impar, derecha
			elif sp[0] == 0:
				_rects[0] = Rect2(Vector2(x0 + cs.x, y), cs)              # portada: derecha
			else:
				_rects[sp[0]] = Rect2(Vector2(x0, y), cs)                 # última par: izquierda
			y += cs.y + SPREAD_GAP
		_content_h = y
		return
	var cols := _cols()
	var x0 := maxf(0.0, (w - cols * cs.x) * 0.5)
	_rects.resize(n)
	for i in n:
		@warning_ignore("integer_division")
		_rects[i] = Rect2(Vector2(x0 + (i % cols) * cs.x, (i / cols) * cs.y), cs)
	_content_h = ceilf(float(n) / cols) * cs.y

func _cell_rect(i: int) -> Rect2:
	if _rects.size() != pages().size():
		_build_rects()
	if i < 0 or i >= _rects.size():
		return Rect2()
	return _rects[i]

func _relayout() -> void:
	if grid == null:
		return
	_build_rects()
	_laid_w = grid.size.x
	grid.custom_minimum_size = Vector2(0, _content_h + 4.0)
	grid.queue_redraw()

func _index_at(p: Vector2) -> int:
	if _rects.size() != pages().size():
		_build_rects()
	for i in _rects.size():
		if _rects[i].has_point(p):
			return i
	return -1

## Índice de inserción (entre celdas) para soltar al reordenar: la celda más
## cercana de esa fila, antes o después según el lado.
func _insert_at(p: Vector2) -> int:
	if _rects.size() != pages().size():
		_build_rects()
	var n := _rects.size()
	if n == 0:
		return 0
	var best := -1
	var best_d := INF
	for i in n:
		var r := _rects[i]
		var dy := 0.0 if (p.y >= r.position.y and p.y <= r.end.y) else minf(absf(p.y - r.position.y), absf(p.y - r.end.y)) * 4.0
		var d := absf(p.x - r.get_center().x) + dy
		if d < best_d:
			best_d = d
			best = i
	return best + (1 if p.x > _rects[best].get_center().x else 0)

func _visible_range() -> Vector2i:
	if _rects.size() != pages().size():
		_build_rects()
	var top := float(_scroll.scroll_vertical) if _scroll else 0.0
	var h := _scroll.size.y if _scroll else grid.size.y
	var first := -1
	var last := -1
	for i in _rects.size():
		var r := _rects[i]
		if r.end.y >= top and r.position.y <= top + h:
			if first < 0:
				first = i
			last = i
		elif first >= 0 and r.position.y > top + h:
			break
	if first < 0:
		return Vector2i(0, -1)
	return Vector2i(first, last)

func _first_visible_index() -> int:
	if grid == null or pages().is_empty():
		return -1
	var vr := _visible_range()
	return vr.x if vr.y >= vr.x else -1

# ── miniaturas (en segundo plano, solo lo visible) ───────────────────────────
func _render_next() -> void:
	var ps := pages()
	if ps.is_empty() or grid == null:
		return
	var vr := _visible_range()
	for i in range(vr.x, vr.y + 1):
		var ab: Node2D = ps[i]
		# páginas DORMIDAS (carga perezosa): no despertarlas por una miniatura
		if not ab.is_inside_tree() or bool(ab.get("is_dormant")):
			continue
		var e: Dictionary = _cache.get(ab.get_instance_id(), {})
		if e.is_empty() or bool(e.get("dirty", false)):
			_render_thumb(ab)
			return

func _render_thumb(ab: Node2D) -> void:
	if not ab.has_method("render_to_image"):
		return
	_rendering = true
	var sz: Vector2 = ab.artboard_size if "artboard_size" in ab else Vector2(794, 1123)
	var k := clampf(_box_w() * 2.0 / maxf(sz.x, 1.0), 0.02, 1.0)   # ×2 para pantallas nítidas
	var img: Image = await ab.render_to_image(k, false)
	_rendering = false
	if not is_inside_tree() or not is_instance_valid(ab) or img == null or img.is_empty():
		return
	_cache[ab.get_instance_id()] = {"tex": ImageTexture.create_from_image(img), "dirty": false}
	grid.queue_redraw()

# ── dibujo ───────────────────────────────────────────────────────────────────
func _draw_grid() -> void:
	var ps := pages()
	if ps.is_empty():
		return
	var font := get_theme_default_font()
	var fs := 10
	var acc := FxUI.c("ACCENT")
	var text := FxUI.c("PANEL_TEXT")
	var muted := FxUI.c("TEXT_SECONDARY")
	var a := active()
	var vr := _visible_range()
	for i in range(vr.x, vr.y + 1):
		var ab: Node2D = ps[i]
		var cell := _cell_rect(i)
		var sz: Vector2 = ab.artboard_size if "artboard_size" in ab else Vector2(794, 1123)
		var box_h := cell.size.y - LABEL_H - CELL_PAD * 2.0
		var box_w := _box_w()
		var k := minf(box_w / sz.x, box_h / sz.y)
		var tsz := sz * k
		@warning_ignore("shadowed_variable_base_class")
		var tr := Rect2(cell.position + Vector2(CELL_PAD + (box_w - tsz.x) * 0.5, CELL_PAD + (box_h - tsz.y) * 0.5), tsz)
		if selected.has(ab):
			grid.draw_rect(cell.grow(-2), Color(acc.r, acc.g, acc.b, 0.16), true)
		var e: Dictionary = _cache.get(ab.get_instance_id(), {})
		if e.has("tex"):
			grid.draw_texture_rect(e["tex"], tr, false)
		else:
			# aún generándose: gris claro (no parece una página en blanco)
			grid.draw_rect(tr, Color(0.86, 0.87, 0.9), true)
		grid.draw_rect(tr, acc if ab == a else FxUI.c("BORDER"), false, 2.0 if ab == a else 1.0)
		var label := "%d  %s" % [i + 1, ab.name]
		var ly := cell.position.y + cell.size.y - CELL_PAD - 4.0
		grid.draw_string(font, Vector2(cell.position.x + CELL_PAD, ly), label, HORIZONTAL_ALIGNMENT_CENTER,
			cell.size.x - CELL_PAD * 2.0, fs, text if ab == a else muted)
	if _drop_at >= 0:
		var r := _cell_rect(mini(_drop_at, ps.size() - 1))
		var x := r.position.x if _drop_at < ps.size() else r.end.x
		grid.draw_line(Vector2(x, r.position.y + 4), Vector2(x, r.end.y - 4), acc, 3.0)

# ── entrada ──────────────────────────────────────────────────────────────────
func _on_grid_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var i := _index_at(ev.position)
		if ev.pressed:
			if i < 0:
				return
			var ab: Node2D = pages()[i]
			if ev.double_click:
				go_to_page(i, true)
			elif ev.shift_pressed and is_instance_valid(_anchor):
				_select_range(_anchor, ab)
			elif ev.ctrl_pressed or ev.meta_pressed:
				if selected.has(ab):
					selected.erase(ab)
				else:
					selected[ab] = true
				_anchor = ab
			else:
				if not selected.has(ab):
					selected = {ab: true}
				_anchor = ab
				go_to_page(i)
			_drag_from = i
			grid.queue_redraw()
		else:
			if _drag_from >= 0 and _drop_at >= 0:
				move_selected_to(_drop_at)
			elif _drag_from >= 0 and not (ev.shift_pressed or ev.ctrl_pressed or ev.meta_pressed):
				var j := _index_at(ev.position)
				if j >= 0:
					selected = {pages()[j]: true}
			_drag_from = -1
			_drop_at = -1
			grid.queue_redraw()
		grid.accept_event()
	elif ev is InputEventMouseMotion and _drag_from >= 0 and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var start := _cell_rect(_drag_from).get_center()
		if _drop_at >= 0 or ev.position.distance_to(start) > 14.0:
			_drop_at = _insert_at(ev.position)
			grid.queue_redraw()
	elif VectopenInput.is_delete_event(ev) and not selected.is_empty():
		delete_selected()
		grid.accept_event()

func _select_range(a: Node2D, b: Node2D) -> void:
	var ps := pages()
	var i0 := ps.find(a)
	var i1 := ps.find(b)
	if i0 < 0 or i1 < 0:
		return
	selected = {}
	for i in range(mini(i0, i1), maxi(i0, i1) + 1):
		selected[ps[i]] = true

# ── acciones ─────────────────────────────────────────────────────────────────
## Ir a la página `i` (0 = primera): activarla y centrar el lienzo en ella;
## `fit` la encuadra entera.
func go_to_page(i: int, fit: bool = false) -> void:
	var ps := pages()
	if ps.is_empty():
		return
	i = clampi(i, 0, ps.size() - 1)
	var ab: Node2D = ps[i]
	var m := _mgr()
	if m:
		m.set_active_artboard(ab)
	var canvas := get_tree().get_first_node_in_group("_vectopen_canvas")
	var cam: Camera2D = canvas.get("camera") if canvas else null
	if cam:
		var sz: Vector2 = ab.artboard_size if "artboard_size" in ab else Vector2.ZERO
		cam.global_position = ab.global_position + sz * 0.5
		if fit and sz.x > 0.0:
			var vs := cam.get_viewport_rect().size
			var z := clampf(minf(vs.x * 0.85 / sz.x, vs.y * 0.85 / sz.y), 0.05, 8.0)
			cam.zoom = Vector2(z, z)
			if "zoom_percentage" in canvas:
				canvas.set("zoom_percentage", z * 100.0)
	if not selected.has(ab):
		selected = {ab: true}
	_anchor = ab
	_scroll_to(i)
	refresh()

func _scroll_to(i: int) -> void:
	if _scroll == null:
		return
	var r := _cell_rect(i)
	if r.position.y < _scroll.scroll_vertical:
		_scroll.scroll_vertical = int(r.position.y)
	elif r.end.y > _scroll.scroll_vertical + _scroll.size.y:
		_scroll.scroll_vertical = int(r.end.y - _scroll.size.y)

## Página nueva del tamaño de la activa, justo después de ella.
func add_page() -> void:
	var api = _api()
	var a := active()
	if api == null:
		return
	var sz: Vector2 = a.artboard_size if a and "artboard_size" in a else Vector2(794, 1123)
	var ab: Node2D = api.add_artboard(sz, "Página")
	if ab and a:
		var cont := ab.get_parent()
		cont.move_child(ab, a.get_index() + 1)
		_relayout_canvas()
	refresh()

func duplicate_selected() -> void:
	var api = _api()
	if api == null:
		return
	var list := _selected_in_order()
	if list.is_empty() and active():
		list = [active()]
	api.begin("Duplicar páginas")
	var last: Node2D = null
	for ab in list:
		var c: Node2D = api.duplicate(ab, Vector2.ZERO)
		if c:
			c.get_parent().move_child(c, (last if last else ab).get_index() + 1)
			last = c
	api.end()
	_relayout_canvas()
	refresh()

func delete_selected() -> void:
	var api = _api()
	var ps := pages()
	var list := _selected_in_order()
	if api == null or list.is_empty() or list.size() >= ps.size():
		return   # siempre queda al menos una página
	var keep: Node2D = null
	for ab in ps:
		if not list.has(ab):
			keep = ab
			break
	api.delete(list)
	var m := _mgr()
	if m and keep:
		m.set_active_artboard(keep)
	selected = {}
	_relayout_canvas()
	refresh()

## Mueve las páginas seleccionadas a la posición `to` (índice de inserción).
func move_selected_to(to: int) -> void:
	var list := _selected_in_order()
	if list.is_empty():
		return
	var ps := pages()
	var cont: Node = ps[0].get_parent()
	var before: Array = ps.duplicate()
	var rest: Array = ps.filter(func(ab) -> bool: return not list.has(ab))
	var before_count := 0
	for i in range(0, mini(to, ps.size())):
		if not list.has(ps[i]):
			before_count += 1
	var order: Array = rest.slice(0, before_count) + list + rest.slice(before_count)
	if order == before:
		return
	_apply_order(cont, order, true, before)

func _apply_order(cont: Node, order: Array, record: bool, previous: Array) -> void:
	# primer hueco que ocupaban las páginas (puede haber otros hijos antes)
	var base := cont.get_child_count()
	for ab in order:
		base = mini(base, (ab as Node).get_index())
	for i in order.size():
		cont.move_child(order[i], base + i)
	_relayout_canvas()
	refresh()
	if record:
		var api = _api()
		if api and api.has_method("_record"):
			api._record("Reordenar páginas",
				func() -> void: _apply_order(cont, order, false, previous),
				func() -> void: _apply_order(cont, previous, false, order),
				true)

## Coloca las páginas en fila en el lienzo, en el orden del panel.
func _relayout_canvas() -> void:
	var ps := pages()
	if ps.is_empty():
		return
	# la fila empieza donde empezaba (la página más a la izquierda)
	var x: float = INF
	var y: float = 0.0
	for ab in ps:
		if ab.global_position.x < x:
			x = ab.global_position.x
			y = ab.global_position.y
	for ab in ps:
		ab.global_position = Vector2(x, y)
		var sz: Vector2 = ab.artboard_size if "artboard_size" in ab else Vector2(794, 1123)
		x += sz.x + GAP

func _selected_in_order() -> Array:
	return pages().filter(func(ab) -> bool: return selected.has(ab))

# ── aspecto ──────────────────────────────────────────────────────────────────
func restyle() -> void:
	for l in find_children("*", "Label", true, false):
		l.add_theme_color_override("font_color", FxUI.c("TEXT_SECONDARY") if l.has_meta("muted") else FxUI.c("PANEL_TEXT"))
	for b in find_children("*", "Button", true, false):
		b.add_theme_stylebox_override("normal", FxUI.flat(FxUI.c("INPUT_BG"), 4, FxUI.c("INPUT_BORDER"), 6, 0))
		b.add_theme_stylebox_override("hover", FxUI.flat(FxUI.c("BUTTON_HOVER"), 4, FxUI.c("BORDER_STRONG"), 6, 0))
		b.add_theme_stylebox_override("pressed", FxUI.flat(FxUI.c("BUTTON_PRESSED"), 4, FxUI.c("ACCENT"), 6, 0))
		b.add_theme_color_override("font_color", FxUI.c("PANEL_TEXT"))
		if b.has_meta("icon_path"):
			b.icon = ProUIStyle.icon(String(b.get_meta("icon_path")), FxUI.c("ICON_PRIMARY"), 14)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _goto:
		ProUIStyle.style_line_edit(_goto)
	var zs := find_child("ThumbSize", true, false) as HSlider
	if zs:
		ProUIStyle.style_slider(zs)
	if grid:
		grid.queue_redraw()
