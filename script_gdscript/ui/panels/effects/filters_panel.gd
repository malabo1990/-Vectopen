# =============================================================================
# RUTA: res://script_gdscript/ui/panels/effects/filters_panel.gd
# Pestaña "Filters" del panel Efectos: filtros de imagen sobre el render del
# objeto (cristal esmerilado, grano, duotono, neón, aberración cromática,
# glitch, semitono, pixelado). Motor: script_gdscript/shapes/filter_fx.gd.
#
# Se construye por código (no se tocan los .tscn): `install(effects_panel)`
# añade el botón de la pestaña a la cabecera y este panel al contenedor de
# pestañas. Edición como en Efectos: los arrastres escriben en vivo y UN
# paso de deshacer se registra al terminar el gesto.
# =============================================================================
extends PanelContainer

const FilterFx = preload("res://script_gdscript/shapes/filter_fx.gd")
const NumField = preload("res://script_gdscript/ui/pro/pro_num_field.gd")
const ColorPopover = preload("res://script_gdscript/ui/pro/text_color_popover.gd")
const FxUI = preload("res://script_gdscript/ui/panels/effects/fx_ui.gd")

const PANEL_NAME := "Filters"
const BUTTON_NAME := "ButtonFilters"

## [clave, etiqueta, mín, máx, paso, sufijo] · [clave, etiqueta, "color"] · [clave, etiqueta, "bool"]
const SPECS := {
	"glass": [["blur", "Blur", 0, 100, 1, "px"], ["tint", "Tint", "color"], ["tint_amount", "Tint amount", 0, 100, 1, "%"],
		["frost", "Frost", 0, 100, 1, "%"], ["saturation", "Saturation", 0, 300, 1, "%"]],
	"grain": [["amount", "Amount", 0, 100, 1, "%"], ["size", "Size", 0.25, 20, 0.25, "px"], ["mono", "Monochrome", "bool"]],
	"duotone": [["dark", "Shadows", "color"], ["light", "Highlights", "color"], ["mix", "Mix", 0, 100, 1, "%"]],
	"neon": [["color", "Color", "color"], ["radius", "Glow radius", 0, 100, 1, "px"], ["intensity", "Intensity", 0, 400, 1, "%"],
		["tint", "Tint", 0, 100, 1, "%"]],
	"chromatic": [["amount", "Offset", 0, 50, 0.5, "px"], ["angle", "Angle", -180, 180, 1, "°"]],
	"glitch": [["amount", "Amount", 0, 100, 1, "%"], ["shift", "Shift", 0, 200, 1, "px"], ["band", "Band height", 1, 100, 1, "px"],
		["seed", "Seed", 0, 999, 1, ""]],
	"halftone": [["cell", "Cell", 2, 100, 1, "px"], ["angle", "Angle", -90, 90, 1, "°"], ["scale", "Dot size", 10, 200, 1, "%"]],
	"pixelate": [["size", "Block", 1, 200, 1, "px"]],
}

## Textos en español si la app está en español (las claves no están en el
## CSV de traducciones; así no hace falta reimportarlo).
const ES := {
	"Filters": "Filtros", "+ Add filter": "+ Añadir filtro",
	"No selection\nSelect an object to apply filters": "Sin selección\nSelecciona un objeto para aplicar filtros",
	"Image filters: glass, grain, duotone, neon, glitch…": "Filtros de imagen: cristal, grano, duotono, neón, glitch…",
	"Remove filter": "Quitar filtro",
	"Frosted Glass": "Cristal esmerilado", "Grain": "Grano", "Duotone": "Duotono", "Neon": "Neón",
	"Chromatic Aberration": "Aberración cromática", "Glitch": "Glitch", "Halftone": "Semitono", "Pixelate": "Pixelado",
	"Blur": "Desenfoque", "Tint": "Tinte", "Tint amount": "Intensidad del tinte", "Frost": "Escarcha",
	"Saturation": "Saturación", "Amount": "Cantidad", "Size": "Tamaño", "Monochrome": "Monocromo",
	"Shadows": "Sombras", "Highlights": "Luces", "Mix": "Mezcla", "Color": "Color", "Glow radius": "Radio del halo",
	"Intensity": "Intensidad", "Offset": "Desplazamiento", "Angle": "Ángulo", "Shift": "Desplazamiento",
	"Band height": "Altura de franja", "Seed": "Semilla", "Cell": "Celda", "Dot size": "Tamaño del punto", "Block": "Bloque",
}

static func t(s: String) -> String:
	return String(ES.get(s, s)) if TranslationServer.get_locale().begins_with("es") else s

var _list: VBoxContainer = null
var _add_btn: Button = null
var _add_popup: PopupMenu = null
var _empty: Label = null
var _title: Label = null
var _scroll: ScrollContainer = null
var _filters: Array = []          # copia de trabajo de lo que muestra el panel
var _sig := ""
var _syncing := false
var _dirty := true
var _live_before: Dictionary = {}
var _commit_timer: Timer = null

# ── instalación ─────────────────────────────────────────────────────────────
## Añade la pestaña al panel de efectos (`effects_panel` es el hijo
## "effects" del contenedor de pestañas). Idempotente.
static func install(effects_panel: Control) -> Control:
	if effects_panel == null:
		return null
	var content := effects_panel.get_parent() as Container
	if content == null:
		return null
	var existing := content.get_node_or_null(PANEL_NAME)
	if existing:
		return existing
	var header := content.get_parent().get_node_or_null("MarginContainer/HBoxContainer") as HBoxContainer
	var panel: Control = load("res://script_gdscript/ui/panels/effects/filters_panel.gd").new()
	panel.name = PANEL_NAME
	panel.visible = false
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(panel)
	if header:
		var model := header.get_node_or_null("ButtonScript") as Button
		var btn: Button = model.duplicate() if model else Button.new()
		btn.name = BUTTON_NAME
		btn.text = t("Filters")
		btn.tooltip_text = t("Image filters: glass, grain, duotone, neon, glitch…")
		var spacer := header.get_node_or_null("Spacer")
		header.add_child(btn)
		if spacer:
			header.move_child(btn, spacer.get_index())
			# La cabecera enlaza cada hijo con la pestaña de su mismo índice:
			# el separador quedaría enlazado con esta pestaña nueva.
			(spacer as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.pressed.connect(func() -> void:
			for c in content.get_children():
				if c is CanvasItem:
					c.visible = c == panel)
		FxUI.style_window(content.owner as Control)
		FxUI.wire_tabs(header, header.get_node_or_null("ButtonEffects") as Button)
		_fit_window.call_deferred(content.owner as Control, header)
	return panel

## Con la pestaña nueva la fila de pestañas es más ancha que la ventana del
## panel: la ventana crece hacia la izquierda (su borde derecho no se mueve).
static func _fit_window(win: Control, header: Control) -> void:
	if not is_instance_valid(win) or not is_instance_valid(header):
		return
	var need := 0.0
	var root := win.get_child(0) as Control if win.get_child_count() > 0 else null
	if root:
		need = root.get_combined_minimum_size().x
	var extra := need - win.size.x
	if extra > 0.5:
		win.offset_left -= ceilf(extra)
	# Más alta: con 420 px solo cabían dos tarjetas de efecto.
	var vp_h := win.get_viewport_rect().size.y
	var want := clampf(vp_h - win.offset_top - 260.0, win.size.y, 600.0)
	if want > win.size.y + 0.5:
		win.offset_bottom = win.offset_top + want

# ── construcción ────────────────────────────────────────────────────────────
func _init() -> void:
	# Textos propios (ES/EN); sin auto-traducción parcial de claves sueltas.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	_title = Label.new()
	_title.text = t("Filters")
	bar.add_child(_title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_add_btn = Button.new()
	_add_btn.name = "AddFilter"
	_add_btn.text = t("+ Add filter")
	_add_btn.pressed.connect(_on_add_pressed)
	bar.add_child(_add_btn)
	_add_popup = PopupMenu.new()
	_add_popup.name = "AddFilterPopup"
	for i in FilterFx.ORDER.size():
		_add_popup.add_item(t(FilterFx.LABELS[FilterFx.ORDER[i]]), i)
	_add_popup.id_pressed.connect(_on_add_id)
	add_child(_add_popup)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 4)
	_scroll.add_child(inner)
	_list = VBoxContainer.new()
	_list.name = "FilterList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	inner.add_child(_list)
	_empty = Label.new()
	_empty.text = t("No selection\nSelect an object to apply filters")
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(_empty)

## Colores del tema (claro / oscuro…): al crear y al cambiar de tema.
func restyle() -> void:
	FxUI.style_panel_bg(self)
	FxUI.style_title(_title)
	FxUI.style_add_button(_add_btn)
	FxUI.style_empty(_empty)
	FxUI.style_scroll(_scroll)
	ProUIStyle.style_popup(_add_popup)
	for card in _list.get_children():
		var head := card.find_child("Head", true, false) as Container
		if head:
			FxUI.dress_card(card as PanelContainer, head, "filter_" + String(card.get_meta("filter_type", "")))

func _ready() -> void:
	_commit_timer = Timer.new()
	_commit_timer.one_shot = true
	_commit_timer.timeout.connect(_commit_live)
	add_child(_commit_timer)
	var ic := _ic()
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_on_inspector_changed):
		ic.changed.connect(_on_inspector_changed)
	restyle()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m: String) -> void: restyle())
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree() and _dirty:
			sync_from_selection())
	sync_from_selection()

func _ic() -> Node:
	return get_node_or_null("/root/InspectorCore")

# ── sincronización ──────────────────────────────────────────────────────────
func _on_inspector_changed(_props: Dictionary = {}) -> void:
	if _syncing or not _live_before.is_empty():
		return   # durante un gesto el panel ya muestra lo que se edita
	if not is_visible_in_tree():
		_dirty = true   # oculto: se sincroniza al mostrarse
		return
	sync_from_selection()

func sync_from_selection() -> void:
	_dirty = false
	var ic := _ic()
	var sel: Array = ic.selection() if ic else []
	_add_btn.disabled = sel.is_empty()
	_add_btn.visible = not sel.is_empty()
	_empty.visible = sel.is_empty()
	if sel.is_empty():
		_filters = []
		_sig = ""
		_rebuild()
		return
	var cur: Array = FilterFx.get_filters(sel[0]).duplicate(true)
	var sig := var_to_str(cur)
	if sig == _sig and _list.get_child_count() == cur.size():
		return
	_filters = cur
	_sig = sig
	_rebuild()

func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for i in _filters.size():
		var f = _filters[i]
		if f is Dictionary:
			_list.add_child(_make_card(i, f))

func _make_card(i: int, f: Dictionary) -> Control:
	var ft := FilterFx.canonical(String(f.get("type", "")))
	var card := PanelContainer.new()
	card.name = "Filter_" + ft
	card.set_meta("filter_type", ft)
	var v := VBoxContainer.new()
	card.add_child(v)
	var head := HBoxContainer.new()
	head.name = "Head"
	v.add_child(head)
	var en := CheckBox.new()
	en.name = "Enabled"
	en.text = t(String(FilterFx.LABELS.get(ft, ft)))
	en.button_pressed = bool(f.get("enabled", true))
	en.toggled.connect(func(on: bool) -> void: _set_structural(i, "enabled", on))
	head.add_child(en)
	var rm := Button.new()
	rm.name = "Remove"
	rm.text = "✕"
	rm.tooltip_text = t("Remove filter")
	rm.pressed.connect(func() -> void: _remove(i))
	head.add_child(rm)
	for spec in SPECS.get(ft, []):
		v.add_child(_make_row(i, ft, f, spec))
	FxUI.dress_card(card, head, "filter_" + ft)
	return card

func _make_row(i: int, ft: String, f: Dictionary, spec: Array) -> Control:
	var key: String = spec[0]
	var row := HBoxContainer.new()
	row.name = "Row_" + key
	var lb := Label.new()
	lb.text = t(String(spec[1]))
	row.add_child(lb)
	var def = FilterFx.DEFAULTS[ft].get(key)
	if spec.size() == 3 and spec[2] == "color":
		var cp := ColorPickerButton.new()
		cp.name = "Value"
		cp.color = FilterFx._col(f.get(key, def), def if def is Color else Color.WHITE)
		cp.color_changed.connect(func(c: Color) -> void: _set_live(i, key, c))
		ColorPopover.attach(cp, t(String(spec[1])))
		row.add_child(cp)
	elif spec.size() == 3 and spec[2] == "bool":
		var cb := CheckBox.new()
		cb.name = "Value"
		cb.button_pressed = bool(f.get(key, def))
		cb.toggled.connect(func(on: bool) -> void: _set_structural(i, key, on))
		row.add_child(cb)
	else:
		var nf: Control = NumField.new("", "", t(String(spec[1])))
		nf.name = "Value"
		nf.min_value = float(spec[2])
		nf.max_value = float(spec[3])
		nf.step = float(spec[4])
		nf.suffix = String(spec[5])
		nf.custom_minimum_size = Vector2(FxUI.FIELD_W, 0)
		nf.size_flags_horizontal = Control.SIZE_SHRINK_END
		nf.set_value_no_signal(float(f.get(key, def)))
		nf.scrub_changed.connect(func(val: float) -> void: _set_live(i, key, val))
		nf.value_changed.connect(func(val: float) -> void: _set_live(i, key, val))
		row.add_child(nf)
	return row

# ── edición ─────────────────────────────────────────────────────────────────
func _on_add_pressed() -> void:
	_add_popup.position = Vector2i(_add_btn.get_screen_position() + Vector2(0, _add_btn.size.y))
	_add_popup.popup()

func _on_add_id(id: int) -> void:
	if id >= 0 and id < FilterFx.ORDER.size():
		add_filter(FilterFx.ORDER[id])

## Añade un filtro (si ya existe ese tipo, solo lo activa: uno por tipo).
func add_filter(kind: String) -> void:
	var c := FilterFx.canonical(kind)
	var list := _filters.duplicate(true)
	for f in list:
		if f is Dictionary and FilterFx.canonical(String(f.get("type", ""))) == c:
			f["enabled"] = true
			_apply(list)
			return
	list.append(FilterFx.make(c))
	_apply(list)

func _remove(i: int) -> void:
	if i < 0 or i >= _filters.size():
		return
	var list := _filters.duplicate(true)
	list.remove_at(i)
	_apply(list)

func _set_structural(i: int, key: String, val: Variant) -> void:
	if _syncing or i >= _filters.size():
		return
	var list := _filters.duplicate(true)
	list[i][key] = val
	_apply(list)

## Cambio de valor (arrastre / escribir / color): en vivo, deshacer al final.
func _set_live(i: int, key: String, val: Variant) -> void:
	if _syncing or i >= _filters.size():
		return
	_filters[i][key] = val
	_sig = var_to_str(_filters)
	var ic := _ic()
	if ic == null or not ic.has_method("_write"):
		_apply(_filters.duplicate(true))
		return
	if _live_before.is_empty():
		for s in ic.selection():
			_live_before[s] = ic._read(s, "filters")
	for s in _live_before:
		if is_instance_valid(s):
			ic._write(s, "filters", _filters.duplicate(true))
	if ic.has_method("post_write_live"):
		ic.post_write_live()
	_commit_timer.start(0.45)

func _commit_live() -> void:
	if _live_before.is_empty():
		return
	var before := _live_before
	_live_before = {}
	var ic := _ic()
	if ic and ic.has_method("commit_live"):
		ic.commit_live("filters", before)

func flush_live() -> void:
	if not _live_before.is_empty():
		_commit_timer.stop()
		_commit_live()

## Añadir / quitar / activar: un paso de deshacer y reconstruir las tarjetas.
func _apply(list: Array) -> void:
	flush_live()
	var ic := _ic()
	if ic == null:
		return
	_syncing = true
	ic.apply("filters", list)
	_syncing = false
	_filters = list.duplicate(true)
	_sig = var_to_str(_filters)
	_rebuild.call_deferred()
