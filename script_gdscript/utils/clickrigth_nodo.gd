extends Control
## Menú contextual del botón derecho (tool_in_Mouse.tscn): Copiar / Pegar /
## Duplicar / Eliminar / Renombrar sobre la selección del canvas.
##
## Antes: al click derecho SOLO se mostraba/ocultaba el panel y lo movía al
## ratón — y NINGUNO de sus botones estaba conectado a nada (Copy/Paste/…
## no hacían nada). Ahora se cablean a las acciones reales de MoveTool.

@export var target_node: Node   # el panel que se muestra/oculta (normalmente self)
@export var tab_normal_style: StyleBox
@export var tab_active_style: StyleBox
@export var tab_hover_style: StyleBox

# Ruta a los botones dentro de tool_in_mouse.tscn (relativa a este nodo raíz).
const _MENU_BASE := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/PanelContainer/VBoxContainer"
const _ACCIONES := {
	"Paste": "paste_clipboard",
	"Copy": "copy_selected",
	"Duplicate": "duplicate_selected",
	"Remove": "delete_selected",
}

func _ready() -> void:
	if target_node:
		target_node.visible = false
	var tcp = get_node_or_null("ThemeConfigPanel")
	if tcp:
		tcp.visible = false
	_conectar_botones()
	_setup_align_panel_icons()
	_setup_align_panel_extras()
	_conectar_trazos()
	_conectar_transform_panel()
	_conectar_tab_bar()
	_conectar_tema_e_idioma()
	_aplicar_tema()
	_actualizar_idioma()
	var gui := get_node_or_null("/root/GlobalUI")
	if gui and gui.has_signal("ui_mode_changed") and not gui.ui_mode_changed.is_connected(_close_context_menus):
		gui.ui_mode_changed.connect(_close_context_menus)
	# Re-sincronizar los campos del panel cuando cambie la selección / estilo.
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_sincronizar_trazos):
		ic.changed.connect(_sincronizar_trazos)

const _ALIGN_TOOLS := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/TOOLS ALINEACION/VBoxContainer"
# Filas de iconos: horizontal (HBoxContainer4) y vertical (HBoxContainer5).
const _ALIGN_ROW := {
	"HBoxContainer4/Button":  ["align", "left"],
	"HBoxContainer4/Button2": ["align", "center_h"],
	"HBoxContainer4/Button3": ["align", "right"],
	"HBoxContainer4/Button4": ["distribute", "h"],
	"HBoxContainer4/Button7": ["align", "right"],
	"HBoxContainer5/Button":  ["align", "top"],
	"HBoxContainer5/Button2": ["align", "middle"],
	"HBoxContainer5/Button3": ["align", "bottom"],
	"HBoxContainer5/Button4": ["distribute", "v"],
}
# Grid 4×4 de alineación: 9 puntos combinados + barras de un solo eje.
const _ALIGN_GRID := {
	"BoxContainer/GridContainer/Button":    ["align", ["left", "top"]],
	"BoxContainer/GridContainer/Button2":   ["align", ["center_h", "top"]],
	"BoxContainer/GridContainer/Button3":   ["align", ["right", "top"]],
	"BoxContainer/GridContainer/Button4":   ["align", ["top"]],
	"BoxContainer/GridContainer/Button5":   ["align", ["left", "middle"]],
	"BoxContainer/GridContainer/Button6":   ["align", ["center_h", "middle"]],
	"BoxContainer/GridContainer/Button7":   ["align", ["right", "middle"]],
	"BoxContainer/GridContainer/Button8":   ["align", ["middle"]],
	"BoxContainer/GridContainer/Button9":   ["align", ["left", "bottom"]],
	"BoxContainer/GridContainer/Button10":  ["align", ["center_h", "bottom"]],
	"BoxContainer/GridContainer/Button11":  ["align", ["right", "bottom"]],
	"BoxContainer/GridContainer/Button12":  ["align", ["bottom"]],
	"BoxContainer/GridContainer/Button13":  ["align", ["left"]],
	"BoxContainer/GridContainer/Button14":  ["align", ["center_h"]],
	"BoxContainer/GridContainer/Button15":  ["align", ["right"]],
	"BoxContainer/GridContainer/Button17":  ["align", ["full_rect"]],
}

func _conectar_botones() -> void:
	for nombre in _ACCIONES:
		var b := get_node_or_null(_MENU_BASE + "/" + nombre) as Button
		if b and not b.pressed.is_connected(_on_accion.bind(_ACCIONES[nombre])):
			b.pressed.connect(_on_accion.bind(_ACCIONES[nombre]))
	var cut := get_node_or_null(_MENU_BASE + "/Cut") as Button
	if cut and not cut.pressed.is_connected(_on_accion.bind("cut_selected")):
		cut.pressed.connect(_on_accion.bind("cut_selected"))
	# Renombrar (botones "name" y "Button6") → editor inline de nombre.
	for rn in ["name", "Button6"]:
		var rb := get_node_or_null(_MENU_BASE + "/" + rn) as Button
		if rb and not rb.pressed.is_connected(_on_rename):
			rb.pressed.connect(_on_rename)
	# Alineación / distribución → InspectorCore (opera sobre la selección, con undo).
	for mapa in [_ALIGN_ROW, _ALIGN_GRID]:
		for rel in mapa:
			var ab := get_node_or_null(_ALIGN_TOOLS + "/" + rel) as Button
			var op: Array = mapa[rel]
			if ab and not ab.pressed.is_connected(_on_align.bind(op[0], op[1])):
				ab.pressed.connect(_on_align.bind(op[0], op[1]))

## Alignment grid: anchor-preset icons (frame + solid block showing the target
## position) instead of loose ColorRects.
func _setup_align_panel_icons() -> void:
	for rel in _ALIGN_GRID:
		var b := get_node_or_null(_ALIGN_TOOLS + "/" + rel) as Button
		if b == null:
			continue
		var modes: Array = _ALIGN_GRID[rel][1]
		var icon_name: String = modes[0] if modes.size() == 1 else "%s_%s" % [modes[0], modes[1]]
		var path := "res://icon/UI/anchor/%s.svg" % icon_name
		if not ResourceLoader.exists(path):
			continue
		b.icon = load(path)
		b.expand_icon = false
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		for cr in b.find_children("", "ColorRect", false, false):
			(cr as ColorRect).visible = false

## Rotate 90° / flip / arrange rows under the alignment rows.
const _ALIGN_EXTRAS := [
	[["rotate_ccw", "Rotar 90° a la izquierda"], ["rotate_cw", "Rotar 90° a la derecha"],
		["flip_h", "Voltear horizontal"], ["flip_v", "Voltear vertical"]],
	[["bring_to_front", "Traer al frente"], ["bring_forward", "Traer adelante"],
		["send_backward", "Enviar atrás"], ["send_to_back", "Enviar al fondo"]],
]

func _setup_align_panel_extras() -> void:
	var base := get_node_or_null(_ALIGN_TOOLS) as Container
	if base == null or base.has_node("ExtrasSeparator"):
		return
	var ref := base.get_node_or_null("HBoxContainer4/Button") as Button
	var btn_size := ref.custom_minimum_size if ref else Vector2(28, 28)
	var sep := HSeparator.new()
	sep.name = "ExtrasSeparator"
	base.add_child(sep)
	for row_spec in _ALIGN_EXTRAS:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		if ref and ref.get_parent() is HBoxContainer:
			row.add_theme_constant_override("separation", ref.get_parent().get_theme_constant("separation"))
		base.add_child(row)
		for spec in row_spec:
			var action_id: String = spec[0]
			var b := Button.new()
			b.name = "Btn_" + action_id
			b.custom_minimum_size = btn_size
			b.focus_mode = Control.FOCUS_NONE
			b.tooltip_text = tr(spec[1])
			b.icon = load("res://icon/UI/menu/%s.svg" % action_id)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.pressed.connect(func(): ContextMenuActions.execute(action_id, self))
			row.add_child(b)

	# Fila de operaciones booleanas y Shape Builder en el panel de alineación
	var bool_sep := HSeparator.new()
	bool_sep.name = "BooleanSeparator"
	base.add_child(bool_sep)

	var bool_rows := [
		[
			["union", "res://icon/UI/boolean_union.svg", "Unión Booleana (No destructiva)"],
			["subtract", "res://icon/UI/boolean_subtract.svg", "Sustracción Booleana (No destructiva)"],
			["intersect", "res://icon/UI/boolean_intersect.svg", "Intersección Booleana (No destructiva)"],
			["exclude", "res://icon/UI/boolean_exclude.svg", "Exclusión Booleana / XOR (No destructiva)"]
		],
		[
			["shape_builder", "res://icon/UI/shape_builder.svg", "Shape Builder (Smart Fusion Shift+M)"],
			["flatten", "res://icon/UI/boolean_flatten.svg", "Aplanar a Curvas Bézier"],
			["release", "res://icon/UI/boolean_release.svg", "Liberar Componentes Booleano"]
		]
	]

	for r_idx in range(bool_rows.size()):
		var b_row := HBoxContainer.new()
		b_row.name = "BooleanRow" + str(r_idx + 1)
		b_row.alignment = BoxContainer.ALIGNMENT_CENTER
		if ref and ref.get_parent() is HBoxContainer:
			b_row.add_theme_constant_override("separation", ref.get_parent().get_theme_constant("separation"))
		base.add_child(b_row)

		for b_spec in bool_rows[r_idx]:
			var op_key: String = b_spec[0]
			var b_btn := Button.new()
			b_btn.name = "Btn_Bool_" + op_key
			b_btn.custom_minimum_size = btn_size
			b_btn.focus_mode = Control.FOCUS_NONE
			b_btn.tooltip_text = tr(b_spec[2])
			if ResourceLoader.exists(b_spec[1]):
				var raw_tex: Texture2D = load(b_spec[1])
				var tm = get_node_or_null("/root/ThemeManager")
				if tm and tm.has_method("make_white_icon"):
					b_btn.icon = tm.make_white_icon(raw_tex, 16)
				else:
					b_btn.icon = raw_tex
				b_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				b_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
				b_btn.expand_icon = false
			b_btn.pressed.connect(func():
				var bc = get_node_or_null("/root/BooleanCore")
				if bc and bc.has_method("apply_operation"):
					bc.apply_operation(op_key)
			)
			b_row.add_child(b_btn)

# ── Barra de pestañas superiores (button_tab_tools2) ─────────────────────────
const _TAB_BAR := "PanelContainer/MarginContainer/VBoxContainer/button_tab_tools2"
const _TAB_LIST := "PanelContainer/MarginContainer/VBoxContainer"

func _conectar_tab_bar() -> void:
	var tab_list = get_node_or_null(_TAB_LIST)
	if tab_list and tab_list.has_signal("button_clicked"):
		if not tab_list.button_clicked.is_connected(_on_tab_changed):
			tab_list.button_clicked.connect(_on_tab_changed)
	_actualizar_estilo_tabs(0)

var _current_tab_idx: int = 0
## Last tab the user picked; reopening the menu returns to it
var _last_chosen_tab: int = 0
var _tab_original_icons: Dictionary = {}
var _action_original_icons: Dictionary = {}

func _on_tab_changed(idx: int) -> void:
	_current_tab_idx = idx
	_last_chosen_tab = idx
	_actualizar_estilo_tabs(idx)

func _actualizar_estilo_tabs(active_idx: int) -> void:
	var bar := get_node_or_null(_TAB_BAR)
	if bar == null:
		return
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var accent: Color = tm.get_color(S.ACCENT) if (tm and S) else Color(0.2, 0.6, 1.0)
	var icon_primary: Color = tm.get_color(S.ICON_PRIMARY) if (tm and S) else Color.WHITE
	for i in range(bar.get_child_count()):
		var btn = bar.get_child(i) as Button
		if btn:
			if tab_hover_style:
				btn.add_theme_stylebox_override("hover", tab_hover_style)
			if i == active_idx:
				if tab_active_style:
					btn.add_theme_stylebox_override("normal", tab_active_style)
				btn.add_theme_color_override("icon_normal_color", accent)
			else:
				if tab_normal_style:
					btn.add_theme_stylebox_override("normal", tab_normal_style)
				btn.add_theme_color_override("icon_normal_color", icon_primary)

func _conectar_tema_e_idioma() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm:
		if tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)
		if tm.has_signal("color_slot_changed") and not tm.color_slot_changed.is_connected(_on_color_slot_changed):
			tm.color_slot_changed.connect(_on_color_slot_changed)
	var lm = get_node_or_null("/root/LanguageManager")
	if lm and lm.has_signal("language_changed") and not lm.language_changed.is_connected(_actualizar_idioma):
		lm.language_changed.connect(_actualizar_idioma)

func _on_theme_changed(_mode: String) -> void:
	_aplicar_tema()

func _on_color_slot_changed(_slot_name: String, _color: Color) -> void:
	_aplicar_tema()

func _aplicar_tema() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if not tm:
		return
	var S = tm.Slot
	var surface_col: Color = tm.get_color(S.PANEL_SURFACE)
	var border_col: Color = tm.get_color(S.BORDER)
	var panel_text: Color = tm.get_color(S.PANEL_TEXT)
	var text_secondary: Color = tm.get_color(S.TEXT_SECONDARY)
	var btn_bg: Color = tm.get_color(S.BUTTON_BG)
	var btn_hov: Color = tm.get_color(S.BUTTON_HOVER)
	var btn_prs: Color = tm.get_color(S.BUTTON_PRESSED)
	var accent: Color = tm.get_color(S.ACCENT)
	var negative: Color = tm.get_color(S.NEGATIVE)
	var surface_raised: Color = tm.get_color(S.SURFACE_RAISED)
	var icon_primary: Color = tm.get_color(S.ICON_PRIMARY)
	var _icon_muted: Color = tm.get_color(S.ICON_MUTED)
	var is_dark: bool = tm.is_dark()

	# 1. Panel contenedor principal
	var root_pc := get_node_or_null("PanelContainer") as PanelContainer
	if root_pc:
		var rsb := StyleBoxFlat.new()
		rsb.bg_color = surface_col
		rsb.border_color = border_col
		rsb.set_border_width_all(1)
		rsb.set_corner_radius_all(12)
		rsb.shadow_color = Color(0, 0, 0, 0.35 if is_dark else 0.08)
		rsb.shadow_size = 12
		rsb.shadow_offset = Vector2(0, 4)
		root_pc.add_theme_stylebox_override("panel", rsb)

	# 2. Estilos para pestañas superiores
	var t_norm := StyleBoxFlat.new()
	t_norm.bg_color = btn_bg
	t_norm.border_color = border_col
	t_norm.set_border_width_all(1)
	t_norm.set_corner_radius_all(6)
	t_norm.content_margin_left = 6
	t_norm.content_margin_right = 6
	t_norm.content_margin_top = 4
	t_norm.content_margin_bottom = 4

	var t_hov := StyleBoxFlat.new()
	t_hov.bg_color = btn_hov
	t_hov.border_color = border_col
	t_hov.set_border_width_all(1)
	t_hov.set_corner_radius_all(6)
	t_hov.content_margin_left = 6
	t_hov.content_margin_right = 6
	t_hov.content_margin_top = 4
	t_hov.content_margin_bottom = 4

	var t_act := StyleBoxFlat.new()
	t_act.bg_color = surface_raised
	t_act.border_color = accent
	t_act.set_border_width_all(1)
	t_act.set_corner_radius_all(6)
	t_act.content_margin_left = 6
	t_act.content_margin_right = 6
	t_act.content_margin_top = 4
	t_act.content_margin_bottom = 4

	tab_normal_style = t_norm
	tab_hover_style = t_hov
	tab_active_style = t_act

	var bar := get_node_or_null(_TAB_BAR)
	if bar:
		for b in bar.get_children():
			if b is Button:
				if not _tab_original_icons.has(b):
					_tab_original_icons[b] = b.icon
				var raw_tab_icon: Texture2D = _tab_original_icons[b]
				if raw_tab_icon and tm and tm.has_method("make_white_icon"):
					b.icon = tm.make_white_icon(raw_tab_icon, 18)
				b.modulate = Color.WHITE
				b.add_theme_color_override("icon_normal_color", icon_primary)
				b.add_theme_color_override("icon_hover_color", panel_text)
				b.add_theme_color_override("icon_pressed_color", accent)
				b.add_theme_color_override("icon_focus_color", icon_primary)
	_actualizar_estilo_tabs(_current_tab_idx)

	# 3. Estilos para botones de acción (Tab 0: Edición)
	var chip_norm := StyleBoxFlat.new()
	chip_norm.bg_color = btn_bg
	chip_norm.border_color = border_col
	chip_norm.set_border_width_all(1)
	chip_norm.set_corner_radius_all(6)
	chip_norm.content_margin_left = 10
	chip_norm.content_margin_right = 10
	chip_norm.content_margin_top = 5
	chip_norm.content_margin_bottom = 5

	var chip_hov := StyleBoxFlat.new()
	chip_hov.bg_color = btn_hov
	chip_hov.border_color = border_col
	chip_hov.set_border_width_all(1)
	chip_hov.set_corner_radius_all(6)
	chip_hov.content_margin_left = 10
	chip_hov.content_margin_right = 10
	chip_hov.content_margin_top = 5
	chip_hov.content_margin_bottom = 5

	var chip_prs := StyleBoxFlat.new()
	chip_prs.bg_color = btn_prs
	chip_prs.border_color = accent
	chip_prs.set_border_width_all(1)
	chip_prs.set_corner_radius_all(6)
	chip_prs.content_margin_left = 10
	chip_prs.content_margin_right = 10
	chip_prs.content_margin_top = 5
	chip_prs.content_margin_bottom = 5

	var del_hov := StyleBoxFlat.new()
	del_hov.bg_color = Color(negative.r, negative.g, negative.b, 0.20 if is_dark else 0.10)
	del_hov.border_color = negative
	del_hov.set_border_width_all(1)
	del_hov.set_corner_radius_all(6)
	del_hov.content_margin_left = 10
	del_hov.content_margin_right = 10
	del_hov.content_margin_top = 5
	del_hov.content_margin_bottom = 5

	var action_names: Array[String] = ["Paste", "Copy", "Duplicate", "Remove", "name", "Button6"]
	for an: String in action_names:
		var btn := get_node_or_null(_MENU_BASE + "/" + an) as Button
		if not btn:
			continue
		var is_del: bool = (an == "Remove")
		btn.add_theme_stylebox_override("normal", chip_norm)
		btn.add_theme_stylebox_override("hover", del_hov if is_del else chip_hov)
		btn.add_theme_stylebox_override("pressed", chip_prs)
		btn.add_theme_color_override("font_color", panel_text)
		btn.add_theme_color_override("font_hover_color", negative if is_del else panel_text)
		btn.add_theme_color_override("font_pressed_color", accent)
		if not _action_original_icons.has(btn):
			_action_original_icons[btn] = btn.icon
		var raw_act_icon: Texture2D = _action_original_icons[btn]
		if raw_act_icon and tm and tm.has_method("make_white_icon"):
			btn.icon = tm.make_white_icon(raw_act_icon, 16)
		btn.modulate = Color.WHITE
		btn.add_theme_color_override("icon_normal_color", negative if is_del else icon_primary)
		btn.add_theme_color_override("icon_hover_color", negative if is_del else panel_text)
		btn.add_theme_color_override("icon_pressed_color", accent)
		for sc in btn.find_children("", "Label", false, false):
			(sc as Label).add_theme_color_override("font_color", text_secondary)
	_build_theme_switcher()

	# 4. Tab 1: Herramientas de alineación
	var align_base = get_node_or_null(_ALIGN_TOOLS)
	if align_base:
		for b in align_base.find_children("", "Button", true, false):
			var btn := b as Button
			btn.add_theme_stylebox_override("normal", chip_norm)
			btn.add_theme_stylebox_override("hover", chip_hov)
			btn.add_theme_stylebox_override("pressed", chip_prs)
			if btn.icon and tm.has_method("make_white_icon"):
				btn.icon = tm.make_white_icon(btn.icon, 16)
			btn.modulate = Color.WHITE
			btn.add_theme_color_override("icon_normal_color", icon_primary)
			btn.add_theme_color_override("icon_hover_color", panel_text)
			btn.add_theme_color_override("icon_pressed_color", accent)
		for cr in align_base.find_children("", "ColorRect", true, false):
			(cr as ColorRect).color = icon_primary

	# 5. Tab 3: Panel_color
	var panel_color = get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_color")
	if panel_color:
		# The color picker (GestorColor) styles its own compact icon buttons;
		# the 10px chip margins here squashed their icons to a couple of pixels
		# until the first click restyled them.
		var gestor := panel_color.find_children("", "GestorColor", true, false)
		var picker: Node = gestor[0] if not gestor.is_empty() else null
		if picker and picker.has_method("_aplicar_tema"):
			picker._aplicar_tema()
		for btn in panel_color.find_children("", "Button", true, false):
			var b := btn as Button
			if picker and picker.is_ancestor_of(b):
				continue
			b.add_theme_stylebox_override("normal", chip_norm)
			b.add_theme_stylebox_override("hover", chip_hov)
			b.add_theme_stylebox_override("pressed", chip_prs)
			b.add_theme_color_override("font_color", panel_text)
			b.add_theme_color_override("font_hover_color", panel_text)
			b.add_theme_color_override("font_pressed_color", accent)

	# 6. Tab 5: Panel_trazos
	var pt := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_trazos") as PanelContainer
	if pt:
		var pt_sb := StyleBoxFlat.new()
		pt_sb.bg_color = surface_col
		pt_sb.border_color = border_col
		pt_sb.set_border_width_all(1)
		pt_sb.set_corner_radius_all(10)
		pt.add_theme_stylebox_override("panel", pt_sb)

	# 7. Tab 4: Panel_tooltext (Tipografía)
	var pt_tool := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_tooltext")
	if pt_tool:
		var bc = pt_tool.get_node_or_null("BoxContainer")
		if bc and bc.has_method("_aplicar_tema"):
			bc._aplicar_tema()

	# 8. Tab 2: Tool_LAYOUT (Disposición)
	var t_layout := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Tool_LAYOUT")
	if t_layout:
		for le in t_layout.find_children("", "LineEdit", true, false):
			(le as LineEdit).add_theme_color_override("font_color", panel_text)
		for p in t_layout.find_children("", "Panel", true, false):
			var pan := p as Panel
			if pan.name == "Panel" or pan.name == "Panel2" or pan.name == "Panel_radous":
				var psb := StyleBoxFlat.new()
				psb.bg_color = btn_bg
				psb.border_color = border_col
				psb.set_border_width_all(1)
				psb.set_corner_radius_all(15)
				pan.add_theme_stylebox_override("panel", psb)

	# 9. Botón de configuración de temas
	var btn_cfg := get_node_or_null("Button_configuration") as Button
	if btn_cfg:
		btn_cfg.visible = false

func _actualizar_idioma(_locale: String = "") -> void:
	var btn_paste := get_node_or_null(_MENU_BASE + "/Paste") as Button
	if btn_paste:
		btn_paste.text = tr("Paste")
		btn_paste.tooltip_text = tr("Paste (Ctrl+V)")
	var btn_copy := get_node_or_null(_MENU_BASE + "/Copy") as Button
	if btn_copy:
		btn_copy.text = tr("Copy")
		btn_copy.tooltip_text = tr("Copy (Ctrl+C)")
	var btn_dup := get_node_or_null(_MENU_BASE + "/Duplicate") as Button
	if btn_dup:
		btn_dup.text = tr("Duplicate")
		btn_dup.tooltip_text = tr("Duplicate (Ctrl+D)")
	var btn_del := get_node_or_null(_MENU_BASE + "/Remove") as Button
	if btn_del:
		btn_del.text = tr("Remove")
		btn_del.tooltip_text = tr("Delete selection")
	var btn_name := get_node_or_null(_MENU_BASE + "/name") as Button
	if btn_name:
		btn_name.text = tr("Name")
		btn_name.tooltip_text = tr("Name")
	var btn_rn := get_node_or_null(_MENU_BASE + "/Button6") as Button
	if btn_rn:
		btn_rn.text = tr("Rename")
		btn_rn.tooltip_text = tr("Rename")

	var bar := get_node_or_null(_TAB_BAR)
	if bar:
		var tooltips := [
			"Inicio / Edición",
			"Alineación y Distribución",
			"Disposición / Transformación",
			"Color y Relleno",
			"Tipografía",
			"Trazos y Borde"
		]
		for i in range(mini(bar.get_child_count(), tooltips.size())):
			var b = bar.get_child(i) as Button
			if b:
				b.tooltip_text = tr(tooltips[i])

# ── Panel de trazos (Panel_trazos) → InspectorCore ───────────────────────────
const _TRAZOS_BASE := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_trazos"
const _TRAZOS_COLOR := _TRAZOS_BASE + "/MarginContainer/BoxContainer/BoxContainer/ColorPickerButton"
const _TRAZOS_SIZE := _TRAZOS_BASE + "/MarginContainer/BoxContainer/BoxContainer2/SpinBox"

var _sync_trazos_guard := false

func _conectar_trazos() -> void:
	var cp := get_node_or_null(_TRAZOS_COLOR) as ColorPickerButton
	if cp == null:
		var pt := get_node_or_null(_TRAZOS_BASE)
		if pt:
			cp = pt.find_child("ColorPickerButton", true, false) as ColorPickerButton
	if cp and not cp.color_changed.is_connected(_on_trazo_color):
		cp.color_changed.connect(_on_trazo_color)
	var sb := get_node_or_null(_TRAZOS_SIZE)
	if sb == null:
		var pt := get_node_or_null(_TRAZOS_BASE)
		if pt:
			sb = pt.find_child("SpinBox", true, false)
	if sb and sb.has_signal("value_changed") and not sb.value_changed.is_connected(_on_trazo_size):
		sb.value_changed.connect(_on_trazo_size)

func _on_trazo_color(c: Color) -> void:
	if _sync_trazos_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply("stroke_color", c)

func _on_trazo_size(v: float) -> void:
	if _sync_trazos_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic:
		ic.apply("stroke_width", v)

const _LAYOUT_BASE := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Tool_LAYOUT"

func _conectar_transform_panel() -> void:
	var tl := get_node_or_null(_LAYOUT_BASE)
	if tl:
		tl.visible = true
		for c in tl.get_children():
			if c is Control and not (c is TransformPanel):
				c.visible = false
		if tl.get_node_or_null("TransformPanel") == null:
			var tp := TransformPanel.new()
			tp.name = "TransformPanel"
			tl.add_child(tp)

## Refleja en el panel los valores de la selección (sin re-disparar apply()).
func _sincronizar_trazos(props: Dictionary) -> void:
	_sync_trazos_guard = true
	var cp := get_node_or_null(_TRAZOS_COLOR) as ColorPickerButton
	if cp == null:
		var pt := get_node_or_null(_TRAZOS_BASE)
		if pt:
			cp = pt.find_child("ColorPickerButton", true, false) as ColorPickerButton
	if cp and props.has("stroke_color") and not props["stroke_color"]["mixed"]:
		cp.color = props["stroke_color"]["value"]
	var sb := get_node_or_null(_TRAZOS_SIZE)
	if sb == null:
		var pt := get_node_or_null(_TRAZOS_BASE)
		if pt:
			sb = pt.find_child("SpinBox", true, false)
	if sb and props.has("stroke_width") and not props["stroke_width"]["mixed"]:
		if sb.has_method("set_value"):
			sb.set_value(float(props["stroke_width"]["value"]))
		else:
			sb.value = float(props["stroke_width"]["value"])
	_sync_trazos_guard = false

## Editor inline del nombre de la figura seleccionada (selección única).
func _on_rename() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	var props: Dictionary = ic.current_props()
	if not props.has("name"):
		return   # multiselección o nada seleccionado
	var le := LineEdit.new()
	le.text = String(props["name"]["value"])
	le.custom_minimum_size = Vector2(180, 26)
	le.size = le.custom_minimum_size
	add_child(le)
	le.global_position = get_global_mouse_position()
	le.select_all()
	le.grab_focus()
	le.text_submitted.connect(func(t: String):
		ic.apply("name", t)
		le.queue_free()
		if target_node: target_node.visible = false)
	le.focus_exited.connect(func(): if is_instance_valid(le): le.queue_free())

func _on_align(kind: String, arg) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	if kind == "align":
		ic.align(arg)
	else:
		ic.distribute(arg)
	if target_node:
		target_node.visible = false

func _move_tool():
	var canvas := get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if canvas and canvas.has_method("get_current_tool"):
		var t = canvas.get_current_tool()
		if t and t.has_method("get_class_name") and t.get_class_name() == "MoveTool":
			return t
	return null

func _on_accion(metodo: String) -> void:
	var mt = _move_tool()
	if mt and mt.has_method(metodo):
		mt.call(metodo)
	if target_node:
		target_node.visible = false   # cerrar el menú tras la acción

const _ModernContextMenuScript := preload("res://script_gdscript/ui/modern/modern_context_menu.gd")
var _modern_context_menu: Control = null

func _ensure_modern_context_menu() -> Control:
	if is_instance_valid(_modern_context_menu):
		return _modern_context_menu
	var scene := load("res://scenes/ui/modern/modern_context_menu.tscn")
	if scene:
		_modern_context_menu = scene.instantiate() as Control
		var p = get_parent()
		if p:
			p.add_child(_modern_context_menu)
		else:
			add_child(_modern_context_menu)
	return _modern_context_menu

var _pro_context_menu: ProContextMenu = null

## Each UI mode has its own context menu: close whatever is open on a mode switch
## so the next right-click opens the menu that belongs to the new mode.
func _close_context_menus(_mode: String = "") -> void:
	if target_node:
		target_node.visible = false
	if is_instance_valid(_modern_context_menu):
		_modern_context_menu.visible = false
	if is_instance_valid(_pro_context_menu):
		_pro_context_menu.hide()

func _ensure_pro_context_menu() -> ProContextMenu:
	if is_instance_valid(_pro_context_menu):
		return _pro_context_menu
	_pro_context_menu = ProContextMenu.new()
	var p = get_parent()
	if p:
		p.add_child(_pro_context_menu)
	else:
		add_child(_pro_context_menu)
	return _pro_context_menu

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
		return
	
	# No abrir el menú si el click derecho cae sobre OTRA UI (paneles, etc.).
	var gui := get_node_or_null("/root/GlobalUI")
	if gui != null and gui.is_mouse_over_ui:
		return

	# Modern UI: Menú contextual vertical estilo Figma / Penpot
	if gui != null and gui.has_method("is_modern_mode") and gui.is_modern_mode():
		if target_node and target_node.visible:
			target_node.visible = false
		var mcm := _ensure_modern_context_menu()
		if mcm:
			mcm.popup_at(get_global_mouse_position())
		return

	# Professional UI: compact desktop-style menu with submenus
	if gui != null and gui.has_method("is_professional_mode") and gui.is_professional_mode():
		if target_node and target_node.visible:
			target_node.visible = false
		if is_instance_valid(_modern_context_menu) and _modern_context_menu.visible:
			_modern_context_menu.visible = false
		var pcm := _ensure_pro_context_menu()
		pcm.popup_at(get_global_mouse_position())
		return

	# Smart UI: asegurar que el menú moderno esté cerrado
	if is_instance_valid(_modern_context_menu) and _modern_context_menu.visible:
		_modern_context_menu.visible = false

	if not target_node:
		return
	if target_node.visible:
		target_node.visible = false
		return
	# Colocar el menú junto al cursor, sin salirse de la ventana.
	var mp: Vector2 = get_global_mouse_position()
	var vp: Vector2 = get_viewport_rect().size
	var ctrl := target_node as Control
	var w: float = 222.0
	var h: float = 360.0
	if ctrl:
		w = maxf(ctrl.size.x, 222.0)
		var pc := ctrl.get_node_or_null("PanelContainer") as Control
		if pc:
			w = maxf(w, pc.size.x)
			h = maxf(h, pc.size.y)
		else:
			h = maxf(ctrl.size.y, 360.0)
	var menu_size := Vector2(w, h)
	mp.x = clampf(mp.x, 0.0, maxf(0.0, vp.x - menu_size.x))
	mp.y = clampf(mp.y, 0.0, maxf(0.0, vp.y - menu_size.y))
	if target_node is Control:
		target_node.global_position = mp
	var tcp = get_node_or_null("ThemeConfigPanel")
	if tcp:
		tcp.visible = false
		
	# Adaptive UI / Smart Context:
	# Clic derecho normal -> last tab the user picked (Tab 0 the first time)
	# Ctrl + Clic derecho -> Full Inspector (Tab 2: Tool_LAYOUT / TransformPanel)
	var is_ctrl: bool = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	var target_tab: int = 2 if is_ctrl else _last_chosen_tab
	_current_tab_idx = target_tab
	var tab_list = get_node_or_null(_TAB_LIST)
	if tab_list and tab_list.has_method("_update_control_b_visibility"):
		tab_list._update_control_b_visibility(target_tab)
		_actualizar_estilo_tabs(target_tab)

	_aplicar_tema()
	_actualizar_idioma()
	target_node.visible = true

func _build_theme_switcher() -> void:
	var menu_base := get_node_or_null(_MENU_BASE) as Control
	if not menu_base:
		return
	var existing := menu_base.get_node_or_null("ThemeSwitcherContainer")
	if existing:
		existing.free()

	var tm = get_node_or_null("/root/ThemeManager")
	if not tm:
		return
	var S = tm.Slot
	var border_col: Color = tm.get_color(S.BORDER)
	var bg_input: Color = tm.get_color(S.INPUT_BG)
	var text_muted: Color = tm.get_color(S.TEXT_SECONDARY)

	var panel := PanelContainer.new()
	panel.name = "ThemeSwitcherContainer"
	var psb := StyleBoxFlat.new()
	psb.bg_color = bg_input
	psb.border_color = border_col
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(6)
	psb.content_margin_left = 6
	psb.content_margin_right = 6
	psb.content_margin_top = 3
	psb.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", psb)
	menu_base.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 3)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)

	var lbl := Label.new()
	lbl.text = tr("Tema:")
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", text_muted)
	hbox.add_child(lbl)

	var themes: Array = [
		{"id": "light", "label": "Claro", "icon": "☀️"},
		{"id": "dark", "label": "Oscuro", "icon": "🌙"},
		{"id": "dark_contrast", "label": "Contraste", "icon": "⬛"},
		{"id": "godot_blue", "label": "Godot", "icon": "🔷"},
		{"id": "blender_gray", "label": "Blender", "icon": "🔶"},
	]

	for t in themes:
		var b := Button.new()
		b.text = t["icon"]
		b.tooltip_text = tr(t["label"])
		b.custom_minimum_size = Vector2(22, 20)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 10)
		if tm.current_mode == t["id"]:
			var act_sb := StyleBoxFlat.new()
			act_sb.bg_color = tm.get_color(S.BUTTON_SELECTED)
			act_sb.border_color = tm.get_color(S.ACCENT)
			act_sb.set_border_width_all(1)
			act_sb.set_corner_radius_all(4)
			b.add_theme_stylebox_override("normal", act_sb)
		else:
			b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		var hov_sb := StyleBoxFlat.new()
		hov_sb.bg_color = tm.get_color(S.BUTTON_HOVER)
		hov_sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override("hover", hov_sb)
		var tid: String = t["id"]
		b.pressed.connect(func():
			tm.apply_preset(tid)
		)
		hbox.add_child(b)

	var btn_gear := Button.new()
	btn_gear.text = "⚙️"
	btn_gear.tooltip_text = tr("Preferencias...")
	btn_gear.custom_minimum_size = Vector2(20, 20)
	btn_gear.focus_mode = Control.FOCUS_NONE
	btn_gear.add_theme_font_size_override("font_size", 10)
	btn_gear.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	var gear_hov := StyleBoxFlat.new()
	gear_hov.bg_color = tm.get_color(S.BUTTON_HOVER)
	gear_hov.set_corner_radius_all(4)
	btn_gear.add_theme_stylebox_override("hover", gear_hov)
	btn_gear.pressed.connect(func():
		var tcp = get_node_or_null("ThemeConfigPanel") as Control
		if tcp:
			tcp.visible = !tcp.visible
	)
	hbox.add_child(btn_gear)
