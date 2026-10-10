# =============================================================================
# RUTA: res://script_gdscript/ui/panels/effects/fx_ui.gd
# DISEÑO COMÚN de la ventana Efectos (pestañas Efectos y Filtros).
# Todo por código y con los colores del ThemeManager (claro / oscuro / …):
#   · ventana y pestañas (la activa resaltada como chip);
#   · tarjetas plegables (chevron) con cabecera: activar, nombre, ▲ ▼ ✕;
#   · filas compactas: etiqueta secundaria + campo numérico arrastrable
#     (ProNumField, el mismo que los paneles de texto) / muestra de color /
#     desplegable / casilla;
#   · botón "Añadir…" y estado vacío.
# Las tarjetas de efectos vienen de .tscn con el SpinBoxValue antiguo: aquí
# se sustituye en pantalla por un ProNumField que lo maneja (el SpinBoxValue
# sigue existiendo, oculto, y su script de efecto no cambia).
# =============================================================================
extends RefCounted

const NumField = preload("res://script_gdscript/ui/pro/pro_num_field.gd")

const FS_TITLE := 12
const FS_ROW := 11
const ROW_H := 20
const FIELD_W := 92

## Plegado por tipo de tarjeta (sobrevive a reconstrucciones del panel).
static var collapsed: Dictionary = {}

const ES := {
	"Offset X": "Desplazamiento X", "Offset Y": "Desplazamiento Y", "Blur": "Desenfoque",
	"Spread": "Extensión", "Color": "Color", "Width": "Grosor", "Radius": "Radio",
	"Opacity": "Opacidad", "Angle": "Ángulo", "Depth": "Profundidad", "Bevel": "Bisel",
	"Highlight": "Luz", "Shadow": "Sombra", "Contour": "Contorno", "Preserve Alpha": "Conservar alfa",
	"Effects": "Efectos", "+ Add effect": "+ Añadir efecto",
	"No selection\nSelect an object to edit effects": "Sin selección\nSelecciona un objeto para editar sus efectos",
	"No effects yet": "Sin efectos", "Collapse / expand": "Plegar / desplegar",
	"Move up": "Subir", "Move down": "Bajar", "Remove": "Quitar",
	"Gradient Overlay": "Degradado", "Color Overlay": "Color superpuesto",
	"3D": "3D (iluminación)", "Bevel Emboss": "Bisel y relieve", "Extrusion": "Extrusión",
	"Link radius and depth": "Vincular radio y profundidad", "Soften": "Suavizar",
	"Profile": "Perfil", "Smooth": "Suave", "Chisel": "Cincel", "Rounded": "Redondeado",
	"Sunken": "Hundido", "Diffuse": "Difuminado", "Specular": "Especular", "Shininess": "Brillo",
	"Specular color": "Color especular", "Ambient": "Ambiente", "Ambient color": "Color de ambiente",
	"Azimuth": "Acimut", "Elevation": "Elevación", "Light color": "Color de luz", "Direction": "Dirección",
	"Style": "Estilo", "Inner bevel": "Bisel interior", "Outer bevel": "Bisel exterior",
	"Emboss": "Relieve", "Pillow emboss": "Relieve almohadilla", "Technique": "Técnica",
	"Chisel hard": "Cincel duro", "Chisel soft": "Cincel suave", "Up": "Arriba", "Down": "Abajo",
	"Size": "Tamaño", "Altitude": "Altitud", "Highlight opacity": "Opacidad de la luz",
	"Shadow opacity": "Opacidad de la sombra",
}

## Unidad correcta según la etiqueta (algunas tarjetas traían "px" en todo).
const SUFFIX_BY_LABEL := {"Angle": "°", "Opacity": ""}

static func t(s: String) -> String:
	return String(ES.get(s, s)) if TranslationServer.get_locale().begins_with("es") else s

static func c(slot: String) -> Color:
	return ProUIStyle.col(slot)

static func flat(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), mh: int = 0, mv: int = 0) -> StyleBoxFlat:
	return ProUIStyle.flat(bg, radius, border, mh, mv)

# ── ventana y pestañas ──────────────────────────────────────────────────────
static func style_window(win: Control) -> void:
	if win == null or win.get_child_count() == 0:
		return
	var root := win.get_child(0) as PanelContainer
	if root:
		var sb := flat(c("PANEL_BG"), 12, c("BORDER"))
		sb.shadow_color = Color(0, 0, 0, 0.35 if ProUIStyle.is_dark() else 0.14)
		sb.shadow_size = 18
		sb.shadow_offset = Vector2(0, 4)
		root.add_theme_stylebox_override("panel", sb)

static func style_tabs(header: Container, active: Button) -> void:
	if header == null:
		return
	for b in header.get_children():
		if not (b is Button):
			continue
		var btn := b as Button
		if btn.name == "cancel":
			style_icon_button(btn, false)
			btn.add_theme_font_size_override("font_size", 13)
			continue
		btn.focus_mode = Control.FOCUS_NONE
		ProUIStyle.style_toggle(btn, btn == active)
		btn.add_theme_font_size_override("font_size", FS_ROW)
		for k in ["normal", "hover", "pressed", "hover_pressed"]:
			var sb := btn.get_theme_stylebox(k) as StyleBoxFlat
			if sb:
				sb.content_margin_left = 7
				sb.content_margin_right = 7
				sb.content_margin_top = 3
				sb.content_margin_bottom = 3
				sb.set_corner_radius_all(6)
	header.add_theme_constant_override("separation", 2)

## Pestaña activa: se resalta al pulsar cualquiera (y se reaplica con el tema).
static func wire_tabs(header: Container, initial: Button) -> void:
	if header == null or header.has_meta("fx_ui_tabs"):
		return
	header.set_meta("fx_ui_tabs", true)
	header.set_meta("fx_ui_active", initial)
	for b in header.get_children():
		if b is Button and b.name != "cancel":
			(b as Button).pressed.connect(func() -> void:
				header.set_meta("fx_ui_active", b)
				style_tabs(header, b))
	style_tabs(header, initial)

static func restyle_tabs(header: Container) -> void:
	if header and header.has_meta("fx_ui_active"):
		style_tabs(header, header.get_meta("fx_ui_active") as Button)

# ── piezas ──────────────────────────────────────────────────────────────────
static func style_panel_bg(p: PanelContainer) -> void:
	p.add_theme_stylebox_override("panel", flat(c("PANEL_BG"), 0))

static func style_title(l: Label) -> void:
	l.add_theme_font_size_override("font_size", FS_TITLE + 1)
	l.add_theme_color_override("font_color", c("PANEL_TEXT"))

static func style_add_button(b: Button) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", FS_ROW)
	b.add_theme_stylebox_override("normal", flat(c("BUTTON_BG"), 6, c("BORDER"), 9, 4))
	b.add_theme_stylebox_override("hover", flat(c("BUTTON_HOVER"), 6, c("ACCENT"), 9, 4))
	b.add_theme_stylebox_override("pressed", flat(c("BUTTON_PRESSED"), 6, c("ACCENT"), 9, 4))
	b.add_theme_stylebox_override("disabled", flat(Color(0, 0, 0, 0), 6, c("BORDER"), 9, 4))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, c("PANEL_TEXT"))
	b.add_theme_color_override("font_disabled_color", c("TEXT_DISABLED"))

static func style_icon_button(b: Button, danger: bool) -> void:
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(18, 18)
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", c("TEXT_SECONDARY"))
	b.add_theme_color_override("font_hover_color", c("NEGATIVE") if danger else c("PANEL_TEXT"))
	b.add_theme_color_override("font_pressed_color", c("PANEL_TEXT"))
	b.add_theme_stylebox_override("hover", flat(c("BUTTON_HOVER"), 4))
	b.add_theme_stylebox_override("pressed", flat(c("BUTTON_PRESSED"), 4))
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

static func style_card(card: PanelContainer) -> void:
	card.add_theme_stylebox_override("panel", flat(c("PANEL_SURFACE"), 7, c("BORDER"), 8, 4))

static func style_title_check(cb: CheckBox) -> void:
	ProUIStyle.style_check(cb)
	cb.add_theme_font_size_override("font_size", FS_TITLE)
	cb.add_theme_constant_override("h_separation", 6)

static func style_row_label(l: Label) -> void:
	l.add_theme_font_size_override("font_size", FS_ROW)
	l.add_theme_color_override("font_color", c("TEXT_SECONDARY"))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true

static func style_swatch(cp: ColorPickerButton) -> void:
	cp.custom_minimum_size = Vector2(FIELD_W, 18)
	cp.size_flags_horizontal = Control.SIZE_SHRINK_END
	cp.focus_mode = Control.FOCUS_NONE
	cp.add_theme_stylebox_override("normal", flat(c("INPUT_BG"), 4, c("INPUT_BORDER"), 3, 3))
	cp.add_theme_stylebox_override("hover", flat(c("INPUT_BG"), 4, c("BORDER_STRONG"), 3, 3))
	cp.add_theme_stylebox_override("pressed", flat(c("INPUT_BG"), 4, c("ACCENT"), 3, 3))
	cp.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

static func style_option(o: OptionButton) -> void:
	ProUIStyle.style_option(o)
	o.custom_minimum_size = Vector2(FIELD_W + 20, 20)
	o.size_flags_horizontal = Control.SIZE_SHRINK_END
	o.add_theme_font_size_override("font_size", FS_ROW)

static func style_empty(l: Label) -> void:
	l.add_theme_font_size_override("font_size", FS_ROW + 1)
	l.add_theme_color_override("font_color", c("TEXT_SECONDARY"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

static func style_scroll(sc: ScrollContainer) -> void:
	var bar := sc.get_v_scroll_bar()
	if bar:
		bar.add_theme_stylebox_override("scroll", flat(Color(0, 0, 0, 0), 3, Color(0, 0, 0, 0), 2, 0))
		bar.add_theme_stylebox_override("grabber", flat(c("SCROLLBAR_GRAB"), 3))
		bar.add_theme_stylebox_override("grabber_highlight", flat(c("BORDER_STRONG"), 3))
		bar.add_theme_stylebox_override("grabber_pressed", flat(c("ACCENT"), 3))

## Campo numérico pro (si no existe ya) en lugar de un SpinBoxValue antiguo.
static func upgrade_spin(sb: Control) -> Control:
	var row := sb.get_parent()
	if row == null:
		return null
	var existing := row.get_node_or_null(String(sb.name) + "_Pro")
	if existing:
		return existing
	var nf: Control = NumField.new("", "", "")
	nf.name = String(sb.name) + "_Pro"
	nf.min_value = float(sb.get("min_value"))
	nf.max_value = float(sb.get("max_value"))
	nf.step = float(sb.get("step"))
	nf.suffix = String(sb.get("suffix"))
	compact_field(nf)
	nf.set_value_no_signal(float(sb.get("value")))
	# campo → SpinBoxValue (su value_changed llega al script del efecto)
	var push := func(v: float) -> void:
		if not is_equal_approx(float(sb.get("value")), v):
			sb.set("value", v)
	nf.scrub_changed.connect(push)
	nf.value_changed.connect(push)
	# SpinBoxValue → campo (set_params, deshacer, otra selección)
	sb.value_changed.connect(func(v: float) -> void:
		if not nf.is_scrubbing():
			nf.set_value_no_signal(v))
	row.add_child(nf)
	row.move_child(nf, sb.get_index())
	sb.visible = false
	return nf

## Campo numérico más bajo (20 px) para las tarjetas.
static func compact_field(nf: Control) -> void:
	nf.custom_minimum_size = Vector2(FIELD_W, 20)
	nf.size_flags_horizontal = Control.SIZE_SHRINK_END
	nf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var le := nf.call("line_edit") as LineEdit if nf.has_method("line_edit") else null
	if le:
		le.custom_minimum_size.y = 18

## Chevron de plegar al principio de la cabecera. `body` = filas a ocultar.
static func add_collapse(header: Container, body: Array, key: String) -> Button:
	var chev := header.get_node_or_null("Collapse") as Button
	if chev == null:
		chev = Button.new()
		chev.name = "Collapse"
		chev.tooltip_text = t("Collapse / expand")
		header.add_child(chev)
		header.move_child(chev, 0)
		chev.pressed.connect(func() -> void:
			collapsed[key] = not bool(collapsed.get(key, false))
			_apply_collapse(chev, body, key))
	style_icon_button(chev, false)
	chev.custom_minimum_size = Vector2(14, 18)
	_apply_collapse(chev, body, key)
	return chev

static func _apply_collapse(chev: Button, body: Array, key: String) -> void:
	var folded := bool(collapsed.get(key, false))
	chev.text = "▸" if folded else "▾"
	if folded == bool(chev.get_meta("folded", false)):
		return
	chev.set_meta("folded", folded)
	for n in body:
		if not (is_instance_valid(n) and n is CanvasItem):
			continue
		var ci := n as CanvasItem
		if folded:
			# Se recuerda si la fila estaba visible (algunas las oculta el
			# propio efecto, p.ej. el ángulo del desenfoque gaussiano).
			ci.set_meta("fx_ui_prev", ci.visible)
			ci.visible = false
		else:
			ci.visible = bool(ci.get_meta("fx_ui_prev", true))

## Viste una tarjeta (de efecto o de filtro): estilo, filas y plegado.
## `header` = fila de la cabecera; el resto de hijos de su VBox es el cuerpo.
static func dress_card(card: PanelContainer, header: Container, key: String) -> void:
	style_card(card)
	var body: Array = []
	var box := header.get_parent()
	if box is BoxContainer:
		(box as BoxContainer).add_theme_constant_override("separation", 2)
	for n in box.get_children():
		if n != header and n is Control:
			body.append(n)
			if n is CheckBox:
				_dress_check(n as CheckBox)
			else:
				_dress_row(n as Control)
	for n in header.get_children():
		if n is CheckBox:
			if not n.has_meta("fx_ui_src"):
				n.set_meta("fx_ui_src", (n as CheckBox).text)
			var src := String(n.get_meta("fx_ui_src"))
			var es := TranslationServer.get_locale().begins_with("es") and ES.has(src)
			(n as CheckBox).text = t(src) if es else tr_text(n as CheckBox, src)
			(n as CheckBox).tooltip_text = (n as CheckBox).text
			style_title_check(n as CheckBox)
			(n as CheckBox).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			(n as CheckBox).clip_text = true
		elif n is Button and n.name != "Collapse":
			var danger := n.name == "Remove" or (n as Button).text in ["✕", "x", "×"]
			if danger:
				(n as Button).text = "✕"
				(n as Button).tooltip_text = t("Remove")
			style_icon_button(n as Button, danger)
		elif n.name == "Spacer" and n is Control:
			(n as Control).visible = false
	add_collapse(header, body, key)

## Texto ya traducido por el motor (tr) si tiene clave; si no, el original.
static func tr_text(n: Node, src: String) -> String:
	var tt := n.tr(src)
	return tt

static func _dress_check(cb: CheckBox) -> void:
	ProUIStyle.style_check(cb)
	cb.add_theme_font_size_override("font_size", FS_ROW)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		cb.add_theme_color_override(k, c("TEXT_SECONDARY"))
	if not cb.has_meta("fx_ui_src"):
		cb.set_meta("fx_ui_src", cb.text)
	cb.text = t(String(cb.get_meta("fx_ui_src")))

static func _dress_row(row: Control) -> void:
	if row is BoxContainer:
		(row as BoxContainer).add_theme_constant_override("separation", 6)
		row.custom_minimum_size.y = maxf(row.custom_minimum_size.y, ROW_H)
	var suffix_override = null
	for n in row.get_children():
		if n is Label:
			var l := n as Label
			if not l.has_meta("fx_ui_src"):
				l.set_meta("fx_ui_src", l.text)
			var src := String(l.get_meta("fx_ui_src"))
			if SUFFIX_BY_LABEL.has(src):
				suffix_override = SUFFIX_BY_LABEL[src]
			l.text = t(src)
			style_row_label(l)
		elif n is ColorPickerButton:
			style_swatch(n as ColorPickerButton)
		elif n is OptionButton:
			style_option(n as OptionButton)
		elif n is CheckBox:
			_dress_check(n as CheckBox)
		elif n is Slider:
			ProUIStyle.style_slider(n as Slider)
		elif n is Control and n.get_script() and String(n.get_script().resource_path).ends_with("spin_box_value.gd"):
			var nf := upgrade_spin(n as Control)
			if nf and suffix_override != null:
				nf.set("suffix", String(suffix_override))
		elif n is NumField:
			(n as Control).call("apply_theme")
			compact_field(n as Control)
		elif n is BoxContainer:
			_dress_row(n as Control)
