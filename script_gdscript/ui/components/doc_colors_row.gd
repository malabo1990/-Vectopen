# =============================================================================
# RUTA: res://script_gdscript/ui/components/doc_colors_row.gd
# «Colores del documento» (encargo 25): las muestras GLOBALES del .vtp.
#   [■][■][■][+]
# · Clic en una muestra → la aplica al RELLENO de la selección (vinculado).
#   Mayús + clic → al TRAZO.
# · «+» → crea una muestra con el relleno del objeto seleccionado (o negro).
# · Clic derecho en una muestra → cambiar el color (cambia todos los objetos
#   que la usan) o renombrar.
# =============================================================================
extends VBoxContainer

const GC = preload("res://script_gdscript/shapes/global_colors.gd")

var _row: HFlowContainer
var _menu: PopupMenu
var _menu_id := ""
var _picker_popup: PopupPanel
var _picker: ColorPicker

var _head: Label

func _on_theme_changed(_m = null) -> void:
	_paint_head()

func _paint_head() -> void:
	if is_instance_valid(_head):
		_head.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))

func _init() -> void:
	name = "DocColorsRow"
	add_theme_constant_override("separation", 3)
	var head := Label.new()
	head.text = tr("Colores del documento")
	head.add_theme_font_size_override("font_size", 11)
	head.name = "Head"
	# colores del tema (antes blanco fijo: ilegible en el tema claro); método
	# propio → Godot lo desconecta solo al borrar la fila
	_head = head
	_paint_head()
	var tm: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("ThemeManager") if Engine.get_main_loop() is SceneTree else null
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(_on_theme_changed)
	head.tooltip_text = tr("Colores globales: al cambiar uno cambian todos los objetos que lo usan. Clic = relleno, Mayús + clic = trazo, clic derecho = editar")
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(head)
	_row = HFlowContainer.new()
	_row.add_theme_constant_override("h_separation", 4)
	_row.add_theme_constant_override("v_separation", 4)
	add_child(_row)
	_menu = PopupMenu.new()
	_menu.add_item(tr("Cambiar color…"), 0)
	_menu.add_item(tr("Renombrar…"), 1)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)

func _ready() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed"):
		ic.changed.connect(func(_p = null) -> void:
			if is_visible_in_tree(): refresh())
	refresh()

func _api():
	var pm := get_node_or_null("/root/PluginManager")
	return pm.api if pm else null

func refresh() -> void:
	for c in _row.get_children():
		c.queue_free()
	for e in GC.all():
		var b := Button.new()
		b.custom_minimum_size = Vector2(22, 22)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s  #%s" % [e["name"], (e["color"] as Color).to_html(false)]
		b.name = "Swatch_" + String(e["id"])
		var sb := StyleBoxFlat.new()
		sb.bg_color = e["color"]
		sb.set_corner_radius_all(4)
		sb.border_color = Color(0, 0, 0, 0.25)
		sb.set_border_width_all(1)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		var id := String(e["id"])
		b.gui_input.connect(func(ev: InputEvent) -> void: _on_swatch_input(ev, id))
		_row.add_child(b)
	var add := Button.new()
	add.name = "AddDocColor"
	add.text = "+"
	add.focus_mode = Control.FOCUS_NONE
	add.custom_minimum_size = Vector2(22, 22)
	add.tooltip_text = tr("Nuevo color global con el relleno del objeto seleccionado")
	add.pressed.connect(add_from_selection)
	_row.add_child(add)

func _on_swatch_input(ev: InputEvent, id: String) -> void:
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	if ev.button_index == MOUSE_BUTTON_LEFT:
		apply(id, "stroke" if ev.shift_pressed else "fill")
	elif ev.button_index == MOUSE_BUTTON_RIGHT:
		_menu_id = id
		_menu.position = Vector2i(get_global_mouse_position()) + get_window().position
		_menu.popup()

## Aplica la muestra a la selección (público para las pruebas).
func apply(id: String, channel: String = "fill") -> void:
	var api = _api()
	if api == null or api.selection().is_empty():
		return
	api.apply_global_color(id, api.selection(), channel)

func add_from_selection() -> String:
	var api = _api()
	if api == null:
		return ""
	var col := Color.BLACK
	if not api.selection().is_empty():
		var f = api.get_prop(api.selection()[0], "fill_color")
		if f is Color:
			col = f
	var id: String = api.add_global_color("%s %d" % [tr("Color"), GC.all().size() + 1], col)
	if id != "" and not api.selection().is_empty():
		api.apply_global_color(id, api.selection(), "fill")
	refresh()
	return id

func _on_menu(mid: int) -> void:
	match mid:
		0:
			if _picker_popup == null:
				_picker_popup = PopupPanel.new()
				_picker = ColorPicker.new()
				_picker.edit_alpha = true
				_picker_popup.add_child(_picker)
				add_child(_picker_popup)
				_picker_popup.popup_hide.connect(func() -> void:
					var api = _api()
					if api and _menu_id != "":
						api.set_global_color(_menu_id, _picker.color)
					refresh())
			var c = GC.get_color(_menu_id)
			_picker.color = c if c is Color else Color.BLACK
			_picker_popup.popup_centered()
		1:
			var dlg := ConfirmationDialog.new()
			var le := LineEdit.new()
			le.custom_minimum_size = Vector2(220, 0)
			for e in GC.all():
				if e["id"] == _menu_id:
					le.text = String(e["name"])
			dlg.add_child(le)
			dlg.register_text_enter(le)
			dlg.title = tr("Renombrar color global")
			add_child(dlg)
			dlg.confirmed.connect(func() -> void:
				var api = _api()
				if api: api.rename_global_color(_menu_id, le.text)
				refresh()
				dlg.queue_free())
			dlg.canceled.connect(dlg.queue_free)
			dlg.popup_centered()
			le.grab_focus()
