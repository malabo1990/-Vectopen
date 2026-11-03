# =============================================================================
# UX-06 — Panel de Pincel y estilos: acabado y colores del tema (claro y
# oscuro) en Smart, Modern y Pro. Ver tool_panel_theme_common.gd.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/brush_panel_theme_e2e.gd
# =============================================================================
extends "res://test/e2e/tool_panel_theme_common.gd"

func _init() -> void:
	PANEL_NAME = "brush"
	TOOL_ID = "brush"
	SCRIPT_PATH = "res://script_gdscript/ui/panel_brush.gd"
	SCENE_PATH = "res://scenes/ui/panels/panel_brush.tscn"
	OUT = "user://brush_panel_theme"
	super._init()
	no_emoji(SCRIPT_PATH)

## Iconografía y campos comunes (UX-06, intento 2): cada estilo con su
## muestra dibujada, Grosor y Opacidad con el campo numérico de la app, y
## pulsar un estilo lo activa de verdad.
func extra_checks(panel: Control, theme: String, mode: String) -> void:
	var styles := panel.find_child("BrushStyles", true, false) as Control
	var n_ok := 0
	var n := 0
	if styles:
		for b in styles.get_children():
			if b is Button:
				n += 1
				var g := (b as Button).get_node_or_null("Sample") as Control
				if g and g.is_visible_in_tree() and g.size.x > 20.0:
					n_ok += 1
	check("%s/%s: los 6 estilos con su muestra dibujada" % [theme, mode], n == 6 and n_ok == 6, "%d/%d" % [n_ok, n])
	# UX-16: cada muestra (menos el borrador) es un trazo REAL pintado por el
	# render del lienzo, con la textura de su estilo.
	var real := 0
	for id in ["pencil", "pen", "marker", "calligraphy", "airbrush"]:
		var b := styles.get_node_or_null("Style_" + id) if styles else null
		var ln := b.find_child("SampleStroke", true, false) as Line2D if b else null
		if ln and ln.get_node_or_null("StrokeRender") and ln.points.size() > 10:
			real += 1
	check("%s/%s: muestras = trazos reales del pincel" % [theme, mode], real == 5, "%d/5" % real)
	var BSR = load("res://script_gdscript/shapes/brush_stroke_render.gd")
	var tex_ok := true
	for id in ["pencil", "marker", "airbrush"]:
		var l := Line2D.new()
		l.set_meta("brush_style", id)
		tex_ok = tex_ok and BSR.style_id(l) > 0
		l.free()
	check("%s/%s: el render pinta el estilo de cada pincel (sombreador)" % [theme, mode], tex_ok)
	for f in ["FieldSize", "FieldOpacity"]:
		var c := panel.find_child(f, true, false)
		check("%s/%s: %s es el campo numérico común" % [theme, mode, f], c is NumericField)
	if theme == "light" and mode == "modern" and styles:
		var btn := styles.get_node_or_null("Style_marker") as Button
		if btn:
			for s in panel.find_children("*", "ScrollContainer", true, false):
				if (s as Node).is_ancestor_of(btn):
					(s as ScrollContainer).ensure_control_visible(btn)
			var sc_up := btn.get_parent()
			while sc_up:
				if sc_up is ScrollContainer:
					(sc_up as ScrollContainer).ensure_control_visible(btn)
				sc_up = sc_up.get_parent()
			await frames(4)
			var at := btn.get_global_rect().get_center()
			var mm := InputEventMouseMotion.new()
			mm.position = at
			mm.global_position = at
			root.push_input(mm)
			await frames(1)
			var hit := root.gui_get_hovered_control()
			check("se puede pulsar «Marcador»", hit == btn or (hit != null and btn.is_ancestor_of(hit)), str(hit))
			for pressed in [true, false]:
				var mb := InputEventMouseButton.new()
				mb.position = at
				mb.global_position = at
				mb.button_index = MOUSE_BUTTON_LEFT
				mb.pressed = pressed
				mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
				root.push_input(mb)
				await frames(2)
			await frames(4)
			var tool = panel._get_brush_tool()
			check("clic en «Marcador» activa ese estilo", tool != null and String(tool.brush_style) == "marker" and btn.button_pressed,
				str(tool.brush_style) if tool else "sin herramienta")
