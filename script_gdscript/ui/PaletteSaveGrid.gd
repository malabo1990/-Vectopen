# =============================================================================
# VECTOPEN — MUESTRAS GUARDADAS DEL SELECTOR DE COLOR («+»)
# RUTA: res://script_gdscript/ui/PaletteSaveGrid.gd
#
# UX-03: además de colores planos guarda DEGRADADOS (con sus puntos, tipo,
# ángulo y centro) y se pueden borrar con clic derecho (Eliminar / Duplicar),
# con deshacer. Pide confirmación solo si algún objeto usa esa muestra.
# Persistente entre sesiones y compartida por los selectores de los tres
# modos (Smart, Modern y Pro): al cambiar en uno se ven los cambios en todos.
#
# Cada muestra es un Color (plano) o un Dictionary «paint» de ColorCore
# ({"type": "linear"/"radial"/…, "stops": [[pos, Color], …], …}).
# =============================================================================
extends GridContainer
class_name PaletteSaveGrid

const SAVE_PATH := "user://vectopen_palette.cfg"
const SWATCH := Vector2(30, 30)
const GROUP := "palette_save_grid"

## Muestras: Color o Dictionary (degradado).
var saved: Array = []
var add_button: Button
var _menu: PopupMenu = null
var _menu_index := -1
var _confirm: ConfirmationDialog = null

## Compatibilidad: solo los colores planos.
var saved_colors: Array[Color]:
	get:
		var out: Array[Color] = []
		for e in saved:
			if e is Color:
				out.append(e)
		return out

## Compatibilidad con la API anterior.
func _load_colors() -> void:
	saved = load_entries()

func _on_swatch_clicked(event: InputEvent, swatch: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if swatch is ColorRect:
			apply_entry((swatch as ColorRect).color)

func _ready() -> void:
	add_to_group(GROUP)
	_find_add_button()
	saved = load_entries()
	_refresh()

func _find_add_button() -> void:
	for child in get_children():
		if child is Button and child.text == "+":
			add_button = child
			add_button.tooltip_text = tr("Guardar el color o el degradado actual")
			if not add_button.pressed.is_connected(_on_add_pressed):
				add_button.pressed.connect(_on_add_pressed)
			break

# ── guardar / leer ───────────────────────────────────────────────────────────
static func load_entries() -> Array:
	var out: Array = []
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		for e in cfg.get_value("palette", "colors", []):
			if e is Color or (e is Dictionary and (e as Dictionary).has("stops")):
				out.append(e)
	return out

static func save_entries(entries: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("palette", "colors", entries)
	cfg.save(SAVE_PATH)

## Guarda la lista y la refresca en TODOS los selectores (los tres modos).
static func _commit_static(tree: SceneTree, entries: Array) -> void:
	save_entries(entries)
	if tree:
		for g in tree.get_nodes_in_group(GROUP):
			if is_instance_valid(g):
				g.saved = entries.duplicate(true)
				g._refresh()

## Cambio con deshacer (Ctrl+Z recupera una muestra borrada).
func _commit_undoable(action: String, entries: Array) -> void:
	var before := saved.duplicate(true)
	var after := entries.duplicate(true)
	var tree := get_tree()
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_method("register_action"):
		hm.register_action(action)
		hm.add_do(func() -> void: _commit_static(tree, after))
		hm.add_undo(func() -> void: _commit_static(tree, before))
		hm.commit()
	_commit_static(tree, after)

# ── «+»: guarda lo que está activo (color o degradado) ──────────────────────
func _on_add_pressed() -> void:
	var entry: Variant = _current_entry()
	if entry == null:
		return
	var next := saved.duplicate(true)
	next.append(entry)
	_commit_undoable("Guardar muestra", next)

func _current_entry() -> Variant:
	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_method("active_paint"):
		var paint: Dictionary = cc.active_paint()
		if String(paint.get("type", "solid")) != "solid" and paint.has("stops"):
			return paint.duplicate(true)
	var color_rect := _find_color_rect()
	if color_rect:
		return color_rect.color
	return cc.active_color() if cc else null

func _find_color_rect() -> ColorRect:
	return get_node_or_null("../../BoxContainer/ColorRect_fill") as ColorRect

static func _same(a: Variant, b: Variant) -> bool:
	if a is Color and b is Color:
		return (a as Color).is_equal_approx(b)
	if a is Dictionary and b is Dictionary:
		return str(a) == str(b)
	return false

# ── muestras ─────────────────────────────────────────────────────────────────
func _refresh() -> void:
	for child in get_children():
		if child != add_button:
			remove_child(child)
			child.queue_free()
	for i in saved.size():
		add_child(_make_swatch(saved[i], i))

func _make_swatch(entry: Variant, index: int) -> Control:
	var sw: Control
	if entry is Dictionary:
		var tex_rect := TextureRect.new()
		var gt := GradientTexture2D.new()
		gt.width = 32
		gt.height = 32
		var cc := get_node_or_null("/root/ColorCore")
		gt.gradient = cc.gradient_from_paint(entry) if cc else Gradient.new()
		match String(entry.get("type", "linear")):
			"radial", "diamond", "box", "spiral":
				gt.fill = GradientTexture2D.FILL_RADIAL
				gt.fill_from = Vector2(0.5, 0.5)
				gt.fill_to = Vector2(1.0, 0.5)
			"conic":
				gt.fill = GradientTexture2D.FILL_SQUARE
		tex_rect.texture = gt
		tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.tooltip_text = tr("Degradado guardado · clic derecho: eliminar o duplicar")
		sw = tex_rect
	else:
		var rect := ColorRect.new()
		rect.color = entry
		rect.tooltip_text = "#%s · %s" % [(entry as Color).to_html(false).to_upper(), tr("clic derecho: eliminar o duplicar")]
		sw = rect
	sw.name = "Swatch%d" % index
	sw.custom_minimum_size = SWATCH
	sw.mouse_filter = Control.MOUSE_FILTER_STOP
	sw.set_meta("swatch_index", index)
	sw.gui_input.connect(_on_swatch_input.bind(sw))
	return sw

func _on_swatch_input(event: InputEvent, swatch: Control) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var i := int(swatch.get_meta("swatch_index", -1))
	if i < 0 or i >= saved.size():
		return
	match (event as InputEventMouseButton).button_index:
		MOUSE_BUTTON_LEFT:
			apply_entry(saved[i])
		MOUSE_BUTTON_RIGHT:
			_open_menu(i, (event as InputEventMouseButton).global_position)
			accept_event()

## Aplica la muestra: un color al selector (como antes); un degradado, a la
## selección con su tipo, puntos, ángulo y centro tal cual se guardó.
func apply_entry(entry: Variant) -> void:
	if entry is Dictionary:
		var cc := get_node_or_null("/root/ColorCore")
		if cc and cc.has_method("set_paint"):
			cc.set_paint((entry as Dictionary).duplicate(true))
		return
	var color_rect := _find_color_rect()
	if color_rect:
		color_rect.color = entry
	var gestor := _gestor()
	if gestor and gestor.has_method("establecer_color"):
		gestor.establecer_color(entry, true)

func _gestor() -> Node:
	var n: Node = self
	while n:
		if n.get_script() and n.get_script().get_global_name() == "GestorColor":
			return n
		n = n.get_parent()
	return null

# ── clic derecho: Eliminar / Duplicar ───────────────────────────────────────
func _open_menu(index: int, at: Vector2) -> void:
	if _menu == null:
		_menu = PopupMenu.new()
		_menu.name = "SwatchMenu"
		_menu.add_item(tr("Eliminar"), 0)
		_menu.add_item(tr("Duplicar"), 1)
		_menu.id_pressed.connect(_on_menu_id)
		add_child(_menu, false, Node.INTERNAL_MODE_BACK)
	_menu_index = index
	_menu.position = Vector2i(at)
	_menu.reset_size()
	_menu.popup()

func _on_menu_id(id: int) -> void:
	var i := _menu_index
	if i < 0 or i >= saved.size():
		return
	match id:
		0:
			if _in_use(saved[i]):
				_ask_delete(i)
			else:
				delete_at(i)
		1:
			var copy: Variant = saved[i] if saved[i] is Color else (saved[i] as Dictionary).duplicate(true)
			var next := saved.duplicate(true)
			next.insert(i + 1, copy)
			_commit_undoable("Duplicar muestra", next)

func delete_at(i: int) -> void:
	if i < 0 or i >= saved.size():
		return
	var next := saved.duplicate(true)
	next.remove_at(i)
	_commit_undoable("Eliminar muestra", next)

func _ask_delete(i: int) -> void:
	if _confirm == null:
		_confirm = ConfirmationDialog.new()
		_confirm.name = "ConfirmDeleteSwatch"
		_confirm.title = tr("Eliminar muestra")
		_confirm.ok_button_text = tr("Eliminar")
		add_child(_confirm, false, Node.INTERNAL_MODE_BACK)
	_confirm.dialog_text = tr("Esta muestra la usa algún objeto del documento. ¿Eliminarla de la paleta? (Los objetos no cambian.)")
	for c in _confirm.confirmed.get_connections():
		_confirm.confirmed.disconnect(c["callable"])
	_confirm.confirmed.connect(func() -> void: delete_at(i), CONNECT_ONE_SHOT)
	_confirm.popup_centered()

## ¿Algún objeto del documento usa esta muestra (relleno o trazo)?
func _in_use(entry: Variant) -> bool:
	var ic := get_node_or_null("/root/InspectorCore")
	var canvas := get_tree().get_first_node_in_group("_vectopen_canvas")
	if ic == null or canvas == null:
		return false
	for n in canvas.find_children("*", "Node2D", true, false):
		if not ("fill_color" in n or "stroke_color" in n):
			continue
		if entry is Color:
			# Con degradado, el color plano guardado no es lo que se ve.
			var grad := {"fill_color": n.has_method("has_gradient_fill") and n.has_gradient_fill(),
				"stroke_color": n.has_method("has_gradient_stroke") and n.has_gradient_stroke()}
			for p in ["fill_color", "stroke_color"]:
				if p in n and not grad[p]:
					if p == "stroke_color" and "stroke_width" in n and float(n.stroke_width) <= 0.0:
						continue
					var c: Color = n.get(p)
					if c.a > 0.0 and c.is_equal_approx(entry):
						return true
		else:
			for p in ["fill_paint", "stroke_paint"]:
				var v = ic._read(n, p)
				if v is Dictionary and String(v.get("type", "solid")) == String(entry.get("type", "")) \
						and str(v.get("stops", [])) == str(entry.get("stops", [])):
					return true
	return false
