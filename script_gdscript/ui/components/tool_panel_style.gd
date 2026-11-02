# =============================================================================
# VECTOPEN — ESTILO COMÚN DE LOS PANELES DE HERRAMIENTA (Pincel, Bézier…)
# RUTA: res://script_gdscript/ui/components/tool_panel_style.gd
#
# UX-06 / UX-07: los paneles de Pincel y Bézier tenían colores escritos a mano
# (gris fijo en las tarjetas, fondo oscuro aunque el tema fuera claro, textos
# atenuados con «modulate»). Todo sale ahora de los colores del TEMA ACTUAL
# (ThemeManager vía ProUIStyle.col) con la misma estructura que el panel de
# Capas: cabeceras de sección en versalitas atenuadas, superficies con borde
# fino, botones-interruptor con el estilo del resto de la app.
# =============================================================================
extends RefCounted

const SECTION_FONT := 10
const TITLE_FONT := 12

## Marco del panel FLOTANTE (Smart). Acoplado en el Inspector (Modern/Pro)
## lo quita ToolPanelDock: aquí no se toca.
static func apply_frame(panel: Control) -> void:
	if not is_instance_valid(panel):
		return
	var p := panel.get_parent()
	if p and String(p.name) == "ToolPanelSlot":
		return
	var sb := ProUIStyle.flat(ProUIStyle.col("PANEL_BG"), 12, ProUIStyle.col("BORDER"))
	sb.set_border_width_all(1)
	var shadow := Color.BLACK
	shadow.a = 0.22
	sb.shadow_color = shadow
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", sb)

## Título del panel.
static func style_title(l: Label) -> void:
	if not is_instance_valid(l):
		return
	l.add_theme_font_size_override("font_size", TITLE_FONT)
	l.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))

## Cabecera de sección como en Capas («CAPAS», «PÁGINAS»): versalitas,
## pequeña y atenuada.
static func style_section_label(l: Label) -> void:
	if not is_instance_valid(l):
		return
	l.uppercase = true
	l.add_theme_font_size_override("font_size", SECTION_FONT)
	l.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))

## Texto secundario (estado, ayuda): color atenuado del tema, no «modulate».
static func style_muted(l: Label) -> void:
	if not is_instance_valid(l):
		return
	l.modulate = Color.WHITE
	l.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))

## Etiqueta normal de una fila.
static func style_text(l: Label) -> void:
	if is_instance_valid(l):
		l.add_theme_color_override("font_color", ProUIStyle.col("PANEL_TEXT"))

## Superficie de una tarjeta / grupo (antes: negro al 8 % fijo).
static func style_card(pc: PanelContainer) -> void:
	if not is_instance_valid(pc):
		return
	var sb := ProUIStyle.flat(ProUIStyle.col("PANEL_SURFACE"), 8, ProUIStyle.col("BORDER"), 10, 8)
	sb.set_border_width_all(1)
	pc.add_theme_stylebox_override("panel", sb)

## Botón de acción con icono del tema (o solo texto).
static func style_action(b: Button, icon_path: String = "") -> void:
	if not is_instance_valid(b):
		return
	if icon_path != "":
		b.set_meta("tps_icon", icon_path)
	var path := String(b.get_meta("tps_icon", ""))
	if path != "":
		b.icon = ProUIStyle.icon(path, ProUIStyle.col("ICON_PRIMARY"), 14)
		b.expand_icon = false
	for st in ["normal", "hover", "pressed", "disabled"]:
		var bg: String = {"normal": "BUTTON_BG", "hover": "BUTTON_HOVER", "pressed": "BUTTON_PRESSED", "disabled": "BUTTON_BG"}[st]
		var border: String = "ACCENT" if st == "pressed" else ("BORDER_STRONG" if st == "hover" else "BORDER")
		var sb := ProUIStyle.flat(ProUIStyle.col(bg), 6, ProUIStyle.col(border), 8, 4)
		sb.set_border_width_all(1)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, ProUIStyle.col("BUTTON_TEXT"))
	b.add_theme_color_override("font_disabled_color", ProUIStyle.col("TEXT_DISABLED"))

## Interruptor (uno de un grupo): activo = acento, como en Pro y Capas.
static func style_toggle(b: Button, active: bool) -> void:
	if is_instance_valid(b):
		ProUIStyle.style_toggle(b, active)

## Separador fino con el color de borde del tema.
static func style_separator(s: HSeparator) -> void:
	if not is_instance_valid(s):
		return
	var line := StyleBoxLine.new()
	line.color = ProUIStyle.col("BORDER")
	line.thickness = 1
	s.add_theme_stylebox_override("separator", line)
