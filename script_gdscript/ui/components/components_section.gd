# =============================================================================
# RUTA: res://script_gdscript/ui/components/components_section.gd
# Recursos ▸ «COMPONENTES»: los componentes (símbolos vinculados) del
# documento, con miniatura, nombre y nº de copias. Pedido del usuario: «el
# componente necesita su parte dentro de Recursos».
#   · Doble clic = colocar una copia en el centro de la vista.
#   · Clic derecho = colocar copia · seleccionar todas las copias ·
#     renombrar · desvincular todas.
#   · «+ Componente con la selección».
# Se rehace solo cuando cambian los componentes (firma barata cada 0,5 s y al
# mostrarse).
# =============================================================================
extends VBoxContainer

const Symbols = preload("res://script_gdscript/shapes/symbols.gd")
const THUMB := 48

var _title: Label
var _list: ItemList
var _empty: Label
var _make_btn: Button
var _menu: PopupMenu
var _menu_id := ""
var _sig := 0
var _tick := 0.0
var _thumbs := {}   # id → [firma, Texture2D]

func _init() -> void:
	name = "ComponentsSection"
	add_theme_constant_override("separation", 4)

func _ready() -> void:
	var head := HBoxContainer.new()
	add_child(head)
	_title = Label.new()
	_title.name = "Title"
	_title.text = tr("COMPONENTES")
	_title.add_theme_font_size_override("font_size", 10)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_make_btn = Button.new()
	_make_btn.name = "MakeComponent"
	_make_btn.text = "+"
	_make_btn.tooltip_text = tr("Crear un componente con la selección")
	_make_btn.focus_mode = Control.FOCUS_NONE
	_make_btn.custom_minimum_size = Vector2(24, 20)
	_make_btn.set_meta("small", true)   # estilo de los botones pequeños de Recursos
	_make_btn.pressed.connect(make_from_selection)
	head.add_child(_make_btn)
	_empty = Label.new()
	_empty.name = "Empty"
	_empty.text = tr("Sin componentes. Selecciona objetos y pulsa «+»: todas las copias quedarán vinculadas.")
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_theme_font_size_override("font_size", 10)
	add_child(_empty)
	_list = ItemList.new()
	_list.name = "Components"
	_list.max_columns = 0
	_list.icon_mode = ItemList.ICON_MODE_TOP
	_list.fixed_icon_size = Vector2i(THUMB, THUMB)
	_list.fixed_column_width = 76
	_list.same_column_width = true
	_list.auto_height = true
	_list.focus_mode = Control.FOCUS_NONE
	_list.add_theme_font_size_override("font_size", 10)
	_list.item_activated.connect(func(i: int) -> void: place_copy(String(_list.get_item_metadata(i))))
	_list.item_clicked.connect(func(i: int, at: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_RIGHT:
			_menu_id = String(_list.get_item_metadata(i))
			_menu.position = Vector2i(_list.get_screen_position() + at)
			_menu.popup())
	add_child(_list)
	_menu = PopupMenu.new()
	_menu.add_item(tr("Colocar una copia"), 0)
	_menu.add_item(tr("Seleccionar todas las copias"), 1)
	_menu.add_item(tr("Renombrar…"), 2)
	_menu.add_separator()
	_menu.add_item(tr("Desvincular todas las copias"), 3)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh(true))
	refresh(true)

func _api():
	var pm := get_node_or_null("/root/PluginManager")
	return pm.api if pm else null

func _process(d: float) -> void:
	if not is_visible_in_tree():
		return
	_tick += d
	if _tick < 0.5:
		return
	_tick = 0.0
	refresh()

## Rehace la lista si cambiaron los componentes (o siempre con `force`).
func refresh(force: bool = false) -> void:
	var all: Array = Symbols.all()
	# también el contenido: editar una copia rehace la miniatura
	var s := hash([var_to_str(all), var_to_str(Symbols._table()).hash()])
	if s == _sig and not force:
		return
	_sig = s
	_list.clear()
	_empty.visible = all.is_empty()
	_list.visible = not all.is_empty()
	_title.text = tr("COMPONENTES") + ("  ·  %d" % all.size() if not all.is_empty() else "")
	for c in all:
		var i := _list.add_item(String(c["name"]))
		_list.set_item_metadata(i, String(c["id"]))
		_list.set_item_tooltip(i, tr("%s · %d copias\nDoble clic: colocar una copia · clic derecho: más") % [String(c["name"]), int(c["count"])])
		var th = _thumbs.get(String(c["id"]))
		if th:
			_list.set_item_icon(i, th[1])
		_thumb_for.call_deferred(String(c["id"]), i)

## Miniatura de la primera copia del componente (en segundo plano).
func _thumb_for(id: String, index: int) -> void:
	var insts: Array = Symbols.instances(id)
	if insts.is_empty():
		return
	var inst: Node2D = insts[0]
	var page: Node = inst.get_parent()
	while page and not ("artboard_size" in page):
		page = page.get_parent()
	if page == null or not page.has_method("render_to_image"):
		return
	# firma = contenido del componente: al editar una copia la miniatura se rehace
	var sig := hash([id, var_to_str(Symbols._table().get(id, {}).get("content", []))])
	var cached = _thumbs.get(id)
	if cached and int(cached[0]) == sig:
		return
	var r := _page_rect(inst, page)
	if not r.has_area():
		return
	var k := minf(THUMB * 2.0 / maxf(r.size.x, r.size.y), 4.0)
	var img: Image = await page.render_to_image(k, true, [inst], r.grow(2.0))
	if img == null or img.is_empty() or not is_inside_tree():
		return
	var tex := ImageTexture.create_from_image(img)
	_thumbs[id] = [sig, tex]
	if index < _list.item_count and String(_list.get_item_metadata(index)) == id:
		_list.set_item_icon(index, tex)

static func _page_rect(n: Node2D, page: Node) -> Rect2:
	var u := Rect2()
	var first := true
	for c in [n] + n.find_children("*", "Node2D", true, false):
		if not c.has_method("get_effect_points"):
			continue
		var pts: PackedVector2Array = c.get_effect_points()
		var xf: Transform2D = (page as Node2D).global_transform.affine_inverse() * (c as Node2D).global_transform
		for p in pts:
			var q := xf * p
			if first:
				u = Rect2(q, Vector2.ZERO)
				first = false
			else:
				u = u.expand(q)
	return u

func make_from_selection() -> void:
	var api = _api()
	var ic := get_node_or_null("/root/InspectorCore")
	if api == null or ic == null or (ic.selection() as Array).is_empty():
		return
	var g = api.make_symbol(ic.selection())
	if g:
		api.select([g])
	refresh(true)

## Copia nueva en el centro de la vista (en la página activa).
func place_copy(id: String) -> Node2D:
	var api = _api()
	if api == null or id == "":
		return null
	var cv = get_tree().get_first_node_in_group("_vectopen_canvas")
	var mgr = cv.get_node_or_null("manager_script") if cv else null
	var ab: Node2D = mgr.get_active_artboard() if mgr and mgr.has_method("get_active_artboard") else null
	var center := Vector2(200, 200)
	if ab and cv:
		var vp_center: Vector2 = (cv as Node2D).get_viewport().get_canvas_transform().affine_inverse() * ((cv as Node2D).get_viewport().get_visible_rect().size * 0.5)
		center = ab.to_local(vp_center)
	var n = api.place_symbol(id, center)
	if n:
		api.select([n])
	refresh(true)
	return n

func _on_menu(cmd: int) -> void:
	var api = _api()
	if api == null:
		return
	match cmd:
		0:
			place_copy(_menu_id)
		1:
			api.select(Symbols.instances(_menu_id))
		2:
			var dlg := AcceptDialog.new()
			dlg.title = tr("Renombrar componente")
			var le := LineEdit.new()
			var cur: Dictionary = Symbols._table().get(_menu_id, {})
			le.text = String(cur.get("name", ""))
			le.custom_minimum_size = Vector2(240, 0)
			dlg.add_child(le)
			var id := _menu_id
			dlg.confirmed.connect(func() -> void:
				Symbols.rename(id, le.text)
				refresh(true)
				dlg.queue_free())
			dlg.canceled.connect(dlg.queue_free)
			add_child(dlg)
			dlg.popup_centered()
			le.grab_focus()
		3:
			for n in Symbols.instances(_menu_id):
				api.detach_symbol(n)
			refresh(true)

func restyle(title_col: Color, text_col: Color) -> void:
	_title.add_theme_color_override("font_color", title_col)
	_empty.add_theme_color_override("font_color", text_col)
	_list.add_theme_color_override("font_color", text_col)
