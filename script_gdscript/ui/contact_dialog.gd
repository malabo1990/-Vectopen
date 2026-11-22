# =============================================================================
# RUTA: res://script_gdscript/ui/contact_dialog.gd
# «CONTACTAR CON EL TÉCNICO» (USR-36): motivo (error / sugerencia / otro),
# email opcional, texto libre de varias líneas y, si se quiere, el informe
# técnico (versión, sistema, errores recientes con su traza, registro).
#   · «Abrir en GitHub»: issue PRE-RELLENADO en el navegador; el usuario lo
#     revisa y lo envía él. Nada se envía solo.
#   · «Guardar informe»: lo deja en user://bug_reports/ (también al abrir
#     GitHub, por si el texto se recorta).
# Se abre desde Acerca de ▸ «Contactar / informar de un error» y desde el aviso
# de error (ErrorHandler.open_contact).
# =============================================================================
extends Window

const BugReport = preload("res://script_gdscript/system/bug_report.gd")

var _kind: OptionButton
var _email: LineEdit
var _title: LineEdit
var _text: TextEdit
var _tech: CheckBox
var _preview: TextEdit
var _status: Label
var last_saved := ""
var last_url := ""
## En pruebas: no abrir el navegador (solo preparar la URL).
var dry_run := false

static func open(tree: SceneTree, kind: String = "bug") -> Window:
	var w: Window = load("res://script_gdscript/ui/contact_dialog.gd").new()
	tree.root.add_child(w)
	var tm := tree.root.get_node_or_null("ThemeManager")
	if tm and tm.has_method("adopt"):
		tm.adopt(w.get_node("UiRoot"))
	w.set_kind(kind)
	w.popup_centered(Vector2i(620, 600))
	w._match_inputs.call_deferred()
	return w

## Los cuadros de varias líneas con el mismo aspecto que los de una línea
## (el tema no estiliza TextEdit: salía gris oscuro con letra gris).
func _match_inputs() -> void:
	var sb: StyleBox = _email.get_theme_stylebox("normal")
	var fc: Color = _email.get_theme_color("font_color")
	var ph: Color = _email.get_theme_color("font_placeholder_color")
	for te in [_text, _preview]:
		if sb:
			te.add_theme_stylebox_override("normal", sb)
			te.add_theme_stylebox_override("read_only", sb)
			te.add_theme_stylebox_override("focus", _email.get_theme_stylebox("focus"))
		te.add_theme_color_override("font_color", fc)
		te.add_theme_color_override("font_readonly_color", fc)
		te.add_theme_color_override("font_placeholder_color", ph)

func _init() -> void:
	name = "ContactDialog"
	title = tr("Contactar con el técnico")
	close_requested.connect(queue_free)
	var bg := PanelContainer.new()
	bg.name = "UiRoot"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 14)
	bg.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = tr("Cuéntanos qué ha pasado o qué echas en falta. Nada se envía solo: se abre un aviso (issue) en GitHub para que lo revises y lo envíes tú.")
	v.add_child(intro)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	g.add_child(_lbl(tr("Motivo")))
	_kind = OptionButton.new()
	_kind.name = "Kind"
	for k in BugReport.KINDS:
		_kind.add_item(tr(String(BugReport.KINDS[k])))
		_kind.set_item_metadata(_kind.item_count - 1, k)
	_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kind.item_selected.connect(func(_i: int) -> void: _refresh())
	g.add_child(_kind)
	g.add_child(_lbl(tr("Título")))
	_title = LineEdit.new()
	_title.name = "Title"
	_title.placeholder_text = tr("Resumen en una línea (opcional)")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(_title)
	g.add_child(_lbl(tr("Email (opcional)")))
	_email = LineEdit.new()
	_email.name = "Email"
	_email.placeholder_text = tr("Solo si quieres que te contestemos")
	_email.tooltip_text = tr("Ojo: los avisos de GitHub son públicos; tu email se verá.")
	_email.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_email.text_changed.connect(func(_t: String) -> void: _refresh())
	g.add_child(_email)
	_text = TextEdit.new()
	_text.name = "Message"
	_text.placeholder_text = tr("¿Qué hacías cuando pasó? ¿Qué esperabas que ocurriera?")
	_text.custom_minimum_size = Vector2(0, 140)
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.text_changed.connect(_refresh)
	v.add_child(_text)
	_tech = CheckBox.new()
	_tech.name = "WithTech"
	_tech.text = tr("Adjuntar informe técnico (versión, sistema, errores recientes y registro)")
	_tech.button_pressed = true
	_tech.toggled.connect(func(_on: bool) -> void: _refresh())
	v.add_child(_tech)
	v.add_child(_lbl(tr("Esto es lo que se enviará:")))
	_preview = TextEdit.new()
	_preview.name = "Preview"
	_preview.editable = false
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(0, 120)
	v.add_child(_preview)
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_btn(row, "Save", tr("Guardar informe"), save_report)
	_btn(row, "Send", tr("Abrir en GitHub"), send)
	_btn(row, "Cancel", tr("Cancelar"), queue_free)
	_refresh()

func _lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l

func _btn(row: Control, nm: String, t: String, cb: Callable) -> void:
	var b := Button.new()
	b.name = nm
	b.text = t
	b.pressed.connect(cb)
	row.add_child(b)

func set_kind(kind: String) -> void:
	for i in _kind.item_count:
		if String(_kind.get_item_metadata(i)) == kind:
			_kind.select(i)
	_refresh()

func kind() -> String:
	return String(_kind.get_item_metadata(_kind.selected)) if _kind.selected >= 0 else "bug"

func report() -> String:
	return BugReport.build(kind(), _text.text, _email.text, _tech.button_pressed)

func _refresh() -> void:
	if _preview:
		_preview.text = report()

func save_report() -> void:
	last_saved = BugReport.save_local(report())
	_status.text = tr("Informe guardado en %s") % ProjectSettings.globalize_path(last_saved)

func send() -> void:
	var r := report()
	last_saved = BugReport.save_local(r)
	last_url = BugReport.issue_url(kind(), _title.text, r)
	if not dry_run:
		OS.shell_open(last_url)
	_status.text = tr("Se ha abierto GitHub en el navegador: revisa el aviso y pulsa «Submit new issue». Copia local: %s") % ProjectSettings.globalize_path(last_saved)
