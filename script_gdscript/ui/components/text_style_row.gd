# =============================================================================
# RUTA: res://script_gdscript/ui/components/text_style_row.gd
# Fila «Estilo» de los paneles de texto (Smart, Modern y Pro) — VAL-24.
#
#   [ Título *         ▾ ] [⋯]
#
# · La lista muestra los estilos del documento; elegir uno lo aplica a los
#   textos seleccionados (y los vincula). «Sin estilo» los desvincula.
#   Un «*» indica que la selección tiene retoques locales.
# · «⋯»: nuevo estilo con la selección, redefinir el estilo (actualiza todos
#   sus textos), renombrar y borrar.
# Todo pasa por TextStyles (un paso de deshacer por acción).
# =============================================================================
extends HBoxContainer

const TS = preload("res://script_gdscript/text/text_styles.gd")

enum { M_NEW, M_REDEFINE, M_RENAME, M_DELETE, M_DETACH }

var option: OptionButton
var menu_btn: MenuButton
var _ids: Array = []          # índice de la lista → id ("" = sin estilo)
var _guard := false
var _dialog: ConfirmationDialog = null
var _dialog_edit: LineEdit = null
var _dialog_mode := M_NEW
var _font_size := 11

func _init(font_size: int = 11) -> void:
	_font_size = font_size
	name = "TextStyleRow"
	add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = tr("Estilo")
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.modulate.a = 0.75
	lbl.custom_minimum_size = Vector2(40, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(lbl)
	option = OptionButton.new()
	option.name = "TextStyleOption"
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.focus_mode = Control.FOCUS_NONE
	option.clip_text = true
	option.custom_minimum_size = Vector2(60, 22)
	option.add_theme_font_size_override("font_size", font_size)
	option.tooltip_text = tr("Estilo de texto con nombre: elegir uno lo aplica a la selección")
	option.item_selected.connect(_on_selected)
	add_child(option)
	menu_btn = MenuButton.new()
	menu_btn.name = "TextStyleMenu"
	menu_btn.text = "⋯"
	menu_btn.flat = false
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.custom_minimum_size = Vector2(26, 22)
	menu_btn.add_theme_font_size_override("font_size", font_size + 2)
	menu_btn.tooltip_text = tr("Estilos de texto: crear, redefinir, renombrar, borrar")
	add_child(menu_btn)
	var pm := menu_btn.get_popup()
	pm.add_theme_font_size_override("font_size", font_size + 1)
	pm.id_pressed.connect(_on_menu)
	menu_btn.about_to_popup.connect(_fill_menu)

func _ready() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_on_ic_changed):
		ic.changed.connect(_on_ic_changed)
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("selection_changed"):
		ge.selection_changed.connect(func(_s = null) -> void: refresh())
	refresh()

func _on_ic_changed(_p = null) -> void:
	if is_visible_in_tree():
		refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		refresh()

## Textos seleccionados.
func selected_texts() -> Array:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return []
	var sel: Array = ic.selection() if ic.has_method("selection") else []
	return sel.filter(func(n) -> bool: return TS.is_text(n))

## Estilo común de la selección ("" ninguno, "<mixed>" varios).
func _current() -> String:
	var texts := selected_texts()
	if texts.is_empty():
		return ""
	var first := TS.style_of(texts[0])
	for t in texts:
		if TS.style_of(t) != first:
			return "<mixed>"
	return first

func refresh() -> void:
	if option == null:
		return
	_guard = true
	option.clear()
	_ids = [""]
	option.add_item(tr("Sin estilo"))
	var cur := _current()
	var texts := selected_texts()
	var modified := false
	for t in texts:
		if TS.is_modified(t):
			modified = true
	for s in TS.all():
		var label := String(s["name"])
		if String(s["id"]) == cur and modified:
			label += " *"
		option.add_item(label)
		_ids.append(String(s["id"]))
	if cur == "<mixed>":
		option.add_item(tr("(varios)"))
		_ids.append("<mixed>")
	var idx := _ids.find(cur)
	option.select(maxi(0, idx))
	option.disabled = texts.is_empty()
	menu_btn.disabled = texts.is_empty() and TS.all().is_empty()
	_guard = false

func _on_selected(i: int) -> void:
	if _guard or i < 0 or i >= _ids.size():
		return
	var id: String = _ids[i]
	var texts := selected_texts()
	if id == "<mixed>" or texts.is_empty():
		refresh()
		return
	if id == "":
		TS.detach(texts)
	else:
		TS.apply(id, texts)
	refresh()

func _fill_menu() -> void:
	var pm := menu_btn.get_popup()
	pm.clear()
	var texts := selected_texts()
	var cur := _current()
	var has_cur := cur != "" and cur != "<mixed>"
	var cur_name := String(TS.get_style(cur).get("name", "")) if has_cur else ""
	pm.add_item(tr("Nuevo estilo con la selección…"), M_NEW)
	pm.set_item_disabled(pm.get_item_index(M_NEW), texts.is_empty())
	pm.add_item(tr("Redefinir «%s» con la selección") % cur_name if has_cur else tr("Redefinir estilo con la selección"), M_REDEFINE)
	pm.set_item_disabled(pm.get_item_index(M_REDEFINE), not has_cur or texts.size() != 1)
	pm.add_item(tr("Desvincular del estilo"), M_DETACH)
	pm.set_item_disabled(pm.get_item_index(M_DETACH), cur == "")
	pm.add_separator()
	pm.add_item(tr("Renombrar estilo…"), M_RENAME)
	pm.set_item_disabled(pm.get_item_index(M_RENAME), not has_cur)
	pm.add_item(tr("Borrar estilo"), M_DELETE)
	pm.set_item_disabled(pm.get_item_index(M_DELETE), not has_cur)

func _on_menu(id: int) -> void:
	var texts := selected_texts()
	var cur := _current()
	match id:
		M_NEW:
			if not texts.is_empty():
				_ask_name(M_NEW, "%s %d" % [tr("Estilo"), TS.all().size() + 1])
		M_REDEFINE:
			if texts.size() == 1 and cur != "" and cur != "<mixed>":
				TS.redefine(cur, texts[0])
		M_DETACH:
			TS.detach(texts)
		M_RENAME:
			if cur != "" and cur != "<mixed>":
				_ask_name(M_RENAME, String(TS.get_style(cur).get("name", "")))
		M_DELETE:
			if cur != "" and cur != "<mixed>":
				TS.remove(cur)
	refresh()

## Pide un nombre (crear / renombrar).
func _ask_name(mode: int, initial: String) -> void:
	_dialog_mode = mode
	if _dialog == null:
		_dialog = ConfirmationDialog.new()
		_dialog.name = "TextStyleNameDialog"
		_dialog_edit = LineEdit.new()
		_dialog_edit.custom_minimum_size = Vector2(240, 0)
		_dialog.add_child(_dialog_edit)
		_dialog.register_text_enter(_dialog_edit)
		_dialog.confirmed.connect(_on_dialog_ok)
		add_child(_dialog)
	_dialog.title = tr("Nuevo estilo de texto") if mode == M_NEW else tr("Renombrar estilo de texto")
	_dialog.ok_button_text = tr("Crear") if mode == M_NEW else tr("Renombrar")
	_dialog_edit.text = initial
	_dialog.popup_centered()
	_dialog_edit.grab_focus()
	_dialog_edit.select_all()

func _on_dialog_ok() -> void:
	submit_name(_dialog_edit.text if _dialog_edit else "")

## Confirma el nombre pedido (público para las pruebas).
func submit_name(text: String) -> void:
	var nm := text.strip_edges()
	if nm == "":
		return
	var texts := selected_texts()
	if _dialog_mode == M_NEW:
		if not texts.is_empty():
			TS.create(nm, texts[0], texts)
	else:
		var cur := _current()
		if cur != "" and cur != "<mixed>":
			TS.rename(cur, nm)
	refresh()
