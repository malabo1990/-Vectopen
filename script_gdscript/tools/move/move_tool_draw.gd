# =============================================================================
# RUTA: res://script_gdscript/tools/move/move_tool_draw.gd
# Dibujo: bounding box pro, tiradores, hover, marquee, guías e hilos de marcos.
# Parte de la herramienta Mover (MoveTool), dividida por capas de herencia:
#   move_tool_core → transform → ops → threading → keyboard → 3d → draw → MoveTool
# El código se movió TAL CUAL desde MoveTool.gd (sin cambios de comportamiento).
# =============================================================================
extends "res://script_gdscript/tools/move/move_tool_3d.gd"


func _draw_hover_shape(c: Node2D) -> void:
	if not is_instance_valid(_hover_shape) or selected_shapes.has(_hover_shape):
		return
	if is_resizing or is_rotating or is_dragging_shape or is_marquee:
		return
	var vp := c.get_viewport()
	var zsc: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	var w: float = 1.5 / maxf(zsc, 0.0002)
	var r: Rect2 = _global_rect(_hover_shape)
	var lr := Rect2(c.to_local(r.position), c.to_local(r.end) - c.to_local(r.position))
	c.draw_rect(lr, COLOR_HOVER, false, w)
	var st := String(_hover_shape.get_meta("shape_type", ""))
	if st.begins_with("text"):
		# Baseline cue under the text box
		c.draw_line(Vector2(lr.position.x, lr.end.y), lr.end, COLOR_HOVER, w * 2.0)

## Dibuja las guías del imán: líneas de alineación (bordes/centros) que cruzan
## toda la vista + marcas en los bordes exactos, y las barras de separación
## (distribución / hueco igualado) con la distancia en px.
func _dibujar_guias_iman(c: Node2D) -> void:
	var vpg := c.get_viewport()
	var zg: float = vpg.get_canvas_transform().get_scale().x if vpg else 1.0
	zg = maxf(zg, 0.0002)
	var k: float = 1.0 / zg                 # unidades de mundo por píxel de pantalla
	var lw: float = 1.3 * k
	var tick: float = 4.0 * k
	var ext: float = 4000.0                 # prolongación de la línea (mundo)
	var font := ThemeDB.fallback_font
	var fs: int = maxi(1, int(round(11.0 * k)))

	for g in _snap_guides:
		var coord: float = g["coord"]
		var lo: float = minf(g["a"], g["b"])
		var hi: float = maxf(g["a"], g["b"])
		var col: Color = COLOR_SNAP_RULE if g.get("guide", false) else COLOR_SNAP_GUIDE
		var gw2: float = lw * (1.4 if g.get("guide", false) else 1.0)
		if String(g["axis"]) == "x":
			c.draw_line(c.to_local(Vector2(coord, lo - ext)), c.to_local(Vector2(coord, hi + ext)), col, gw2)
			c.draw_line(c.to_local(Vector2(coord - tick, g["a"])), c.to_local(Vector2(coord + tick, g["a"])), col, lw)
			c.draw_line(c.to_local(Vector2(coord - tick, g["b"])), c.to_local(Vector2(coord + tick, g["b"])), col, lw)
		else:
			c.draw_line(c.to_local(Vector2(lo - ext, coord)), c.to_local(Vector2(hi + ext, coord)), col, gw2)
			c.draw_line(c.to_local(Vector2(g["a"], coord - tick)), c.to_local(Vector2(g["a"], coord + tick)), col, lw)
			c.draw_line(c.to_local(Vector2(g["b"], coord - tick)), c.to_local(Vector2(g["b"], coord + tick)), col, lw)

	var col_sp := Color(1.0, 0.36, 0.46, 0.98)
	for s in _snap_spacing:
		var perp: float = s["perp"]
		var gap_txt := str(roundi(s["gap"]))
		for seg in s["segs"]:
			var a0: float = seg[0]
			var a1: float = seg[1]
			var mid: float = (a0 + a1) * 0.5
			if String(s["axis"]) == "x":
				c.draw_line(c.to_local(Vector2(a0, perp)), c.to_local(Vector2(a1, perp)), col_sp, lw)
				c.draw_line(c.to_local(Vector2(a0, perp - tick)), c.to_local(Vector2(a0, perp + tick)), col_sp, lw)
				c.draw_line(c.to_local(Vector2(a1, perp - tick)), c.to_local(Vector2(a1, perp + tick)), col_sp, lw)
				if font:
					c.draw_string(font, c.to_local(Vector2(mid, perp - tick * 2.0)), gap_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col_sp)
			else:
				c.draw_line(c.to_local(Vector2(perp, a0)), c.to_local(Vector2(perp, a1)), col_sp, lw)
				c.draw_line(c.to_local(Vector2(perp - tick, a0)), c.to_local(Vector2(perp + tick, a0)), col_sp, lw)
				c.draw_line(c.to_local(Vector2(perp - tick, a1)), c.to_local(Vector2(perp + tick, a1)), col_sp, lw)
				if font:
					c.draw_string(font, c.to_local(Vector2(perp + tick * 2.0, mid)), gap_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_sp)

## 13.1 Medidas y distancias inteligentes: muestra distancias al presionar Alt
func _draw_alt_smart_measurements(c: Node2D) -> void:
	var sel_rect := _get_macro_rect()
	if sel_rect.size == Vector2.ZERO or not target_artboard:
		return
	var mgr := ArtboardManager.find(get_tree()) if is_inside_tree() else null
	var ab_rect: Rect2 = mgr.world_rect(target_artboard) if mgr else Rect2(target_artboard.global_position, target_artboard.artboard_size if "artboard_size" in target_artboard else Vector2.ZERO)
	if ab_rect.size == Vector2.ZERO:
		return

	var vpg := c.get_viewport()
	var zg: float = vpg.get_canvas_transform().get_scale().x if vpg else 1.0
	zg = maxf(zg, 0.0002)
	var k: float = 1.0 / zg
	var col := Color(1.0, 0.20, 0.50, 0.95) # magenta sutil
	var font := ThemeDB.fallback_font
	var fs: int = maxi(1, int(round(10.0 * k)))
	var lw: float = 1.2 * k
	var tick: float = 3.0 * k

	var center := sel_rect.get_center()

	# 1. Distancia al borde izquierdo del artboard
	if sel_rect.position.x > ab_rect.position.x:
		var p1 := c.to_local(Vector2(ab_rect.position.x, center.y))
		var p2 := c.to_local(Vector2(sel_rect.position.x, center.y))
		c.draw_line(p1, p2, col, lw)
		c.draw_line(p1 - Vector2(0, tick), p1 + Vector2(0, tick), col, lw)
		c.draw_line(p2 - Vector2(0, tick), p2 + Vector2(0, tick), col, lw)
		var dist_l := roundi(sel_rect.position.x - ab_rect.position.x)
		if font:
			c.draw_string(font, (p1 + p2) * 0.5 - Vector2(0, 4 * k), str(dist_l) + " px", HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)

	# 2. Distancia al borde derecho del artboard
	if ab_rect.end.x > sel_rect.end.x:
		var p1 := c.to_local(Vector2(sel_rect.end.x, center.y))
		var p2 := c.to_local(Vector2(ab_rect.end.x, center.y))
		c.draw_line(p1, p2, col, lw)
		c.draw_line(p1 - Vector2(0, tick), p1 + Vector2(0, tick), col, lw)
		c.draw_line(p2 - Vector2(0, tick), p2 + Vector2(0, tick), col, lw)
		var dist_r := roundi(ab_rect.end.x - sel_rect.end.x)
		if font:
			c.draw_string(font, (p1 + p2) * 0.5 - Vector2(0, 4 * k), str(dist_r) + " px", HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)

	# 3. Distancia al borde superior del artboard
	if sel_rect.position.y > ab_rect.position.y:
		var p1 := c.to_local(Vector2(center.x, ab_rect.position.y))
		var p2 := c.to_local(Vector2(center.x, sel_rect.position.y))
		c.draw_line(p1, p2, col, lw)
		c.draw_line(p1 - Vector2(tick, 0), p1 + Vector2(tick, 0), col, lw)
		c.draw_line(p2 - Vector2(tick, 0), p2 + Vector2(tick, 0), col, lw)
		var dist_t := roundi(sel_rect.position.y - ab_rect.position.y)
		if font:
			c.draw_string(font, (p1 + p2) * 0.5 + Vector2(6 * k, 3 * k), str(dist_t) + " px", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# 4. Distancia al borde inferior del artboard
	if ab_rect.end.y > sel_rect.end.y:
		var p1 := c.to_local(Vector2(center.x, sel_rect.end.y))
		var p2 := c.to_local(Vector2(center.x, ab_rect.end.y))
		c.draw_line(p1, p2, col, lw)
		c.draw_line(p1 - Vector2(tick, 0), p1 + Vector2(tick, 0), col, lw)
		c.draw_line(p2 - Vector2(tick, 0), p2 + Vector2(tick, 0), col, lw)
		var dist_b := roundi(ab_rect.end.y - sel_rect.end.y)
		if font:
			c.draw_string(font, (p1 + p2) * 0.5 + Vector2(6 * k, 3 * k), str(dist_b) + " px", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

## Solo visible mientras HAY un modificador realmente pulsado (igual que el
## badge de IHTML, que se esconde del todo con mods.length===0) — no un hint
## permanente. draw_preview es un callback de pintado sin InputEvent propio
## (lo dispara queue_redraw, no un evento de teclado/ratón), así que aquí SÍ
## corresponde leer Input.is_key_pressed() directo — no hay "evento actual"
## del que sacar shift_pressed/alt_pressed/ctrl_pressed, mismo criterio que
## _draw_alt_smart_measurements arriba.
func _draw_modifier_hint(c: Node2D) -> void:
	if not (is_resizing or is_rotating or is_dragging_shape):
		return
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var alt := Input.is_key_pressed(KEY_ALT)
	var ctrl := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	if not (shift or alt or ctrl):
		return

	var parts: Array[String] = []
	if is_resizing:
		if _is_image_only_selection():
			if ctrl:
				parts.append("Ctrl: estirar imagen")
			else:
				parts.append("Normal: proporción fija")
		else:
			if shift:
				parts.append("Shift: grosor de trazo" if resize_handle in ["rc", "lc", "bc", "tc"] else "Shift: escala uniforme")
		if alt:
			parts.append("Alt: desde el centro")
	elif is_rotating:
		if shift:
			parts.append("Shift: 15°")
		elif ctrl:
			parts.append("Ctrl: 1°")
	elif is_dragging_shape:
		if shift:
			parts.append("Shift: eje")
		if alt:
			parts.append("Alt: duplicar")
		if ctrl:
			parts.append("Ctrl: ajustar a grilla")

	if parts.is_empty():
		return

	var vp := c.get_viewport()
	var zoom: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	zoom = maxf(zoom, 0.0002)
	var k: float = 1.0 / zoom
	var font := ThemeDB.fallback_font
	var fs: int = maxi(1, int(round(11.0 * k)))
	var pos: Vector2 = c.to_local(canvas.get_global_mouse_position()) + Vector2(16, -16) * k
	var text: String = " · ".join(parts)

	# Contorno oscuro (4 copias desplazadas) + texto claro encima, en vez de
	# una caja de fondo real — evita tener que medir el ancho del texto para
	# dibujar un Rect2 a mano, y se lee igual de bien sobre cualquier fondo.
	var shadow := Color(0, 0, 0, 0.85)
	for off in [Vector2(-1, -1) * k, Vector2(1, -1) * k, Vector2(-1, 1) * k, Vector2(1, 1) * k]:
		c.draw_string(font, pos + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, shadow)
	c.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.4, 0.8, 1.0, 1.0))

# ── Renderizado del Bounding Box Pro (estilo profesional) ─────────────────────────

func draw_preview(c: Node2D) -> void:
	if not is_instance_valid(c):
		return

	if is_marquee:
		var sl: Vector2 = c.to_local(marquee_start)
		var el: Vector2 = c.to_local(marquee_end)
		var r: Rect2 = Rect2(sl, el - sl).abs()
		var zsc: float = c.get_viewport().get_canvas_transform().get_scale().x if c.get_viewport() else 1.0
		var lw: float = maxf(1.0 / maxf(zsc, 0.0002), 0.8)
		c.draw_rect(r, COLOR_MARQUEE_F, true)
		c.draw_rect(r, COLOR_MARQUEE_S, false, lw)
		return

	_draw_hover_shape(c)

	# Guías del imán inteligente (solo mientras se arrastra una figura)
	if is_dragging_shape and (not _snap_guides.is_empty() or not _snap_spacing.is_empty()):
		_dibujar_guias_iman(c)

	# 13.1 Medidas y distancias inteligentes al presionar Alt
	if selected_shapes.size() > 0 and Input.is_key_pressed(KEY_ALT) and not is_dragging_shape and not is_resizing and not is_rotating:
		_draw_alt_smart_measurements(c)

	# Insignia de modificadores activos — mismo propósito que IHTML
	# (js/workspace/bounding-box.js, .bb-modifier-badge): feedback visual de
	# qué hace cada tecla mientras se arrastra, sin tener que memorizarlas.
	_draw_modifier_hint(c)

	# NOTA: El recuadro principal + handles de resize/rotate ya no se dibujan aquí.
	# Los renderiza boundingbox.tscn (instancia real del pool), ver bounding_box.gd.
	if selected_shapes.size() > 1:
		# Grosor CONSTANTE en pantalla (≈1.25 px) a cualquier zoom — como un editor profesional /
		# editor profesional. El zoom REAL es el del viewport (la cámara no escala el nodo
		# Canvas, escala el viewport).
		var vp := c.get_viewport()
		var zsc: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
		var outline_width: float = 1.25 / maxf(zsc, 0.0002)
		for shape in selected_shapes:
			if is_instance_valid(shape):
				var s_rect: Rect2 = _global_rect(shape)
				var s_lrect: Rect2 = Rect2(c.to_local(s_rect.position), c.to_local(s_rect.end) - c.to_local(s_rect.position))
				c.draw_rect(s_lrect, Color(COLOR_BBOX.r, COLOR_BBOX.g, COLOR_BBOX.b, 0.3), false, outline_width)

	# Previsualización de hilos y encadenamiento de párrafos (Text Threading)
	_draw_paragraph_threads(c)
	if is_dragging_thread:
		_draw_threading_drag_preview(c)

func _draw_paragraph_threads(c: Node2D) -> void:
	if selected_shapes.is_empty():
		return
	var vp := c.get_viewport()
	var zsc: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	var lw: float = maxf(1.5 / maxf(zsc, 0.0002), 1.0)
	var arrow_sz: float = maxf(6.0 / maxf(zsc, 0.0002), 4.0)
	var col_line := Color(0.18, 0.65, 0.98, 0.85)

	var drawn_pairs := {}
	for s in selected_shapes:
		if not is_instance_valid(s) or not s.has_meta("shape_type") or str(s.get_meta("shape_type")) != "text_paragraph":
			continue
		var chain := ParagraphThreading.get_chain(s)
		for i in range(chain.size() - 1):
			var cur := chain[i]
			var nxt := chain[i + 1]
			if not is_instance_valid(cur) or not is_instance_valid(nxt):
				continue
			var pair_key := str(cur.get_instance_id()) + "->" + str(nxt.get_instance_id())
			if drawn_pairs.has(pair_key):
				continue
			drawn_pairs[pair_key] = true

			var p1: Vector2 = c.to_local(ParagraphThreading.get_out_port_rect(cur, zsc).get_center())
			var nxt_gpos: Vector2 = nxt.global_position
			var p2: Vector2 = c.to_local(nxt_gpos + Vector2(10.0 / maxf(zsc, 0.0002), 10.0 / maxf(zsc, 0.0002)))

			var ctrl_dx := absf(p2.x - p1.x) * 0.5 + 20.0 / maxf(zsc, 0.0002)
			var c1 := p1 + Vector2(ctrl_dx, 0.0)
			var c2 := p2 - Vector2(ctrl_dx, 0.0)

			var pts := PackedVector2Array()
			const STEPS := 16
			for step in range(STEPS + 1):
				var t := float(step) / float(STEPS)
				var it := 1.0 - t
				var pt := it*it*it*p1 + 3.0*it*it*t*c1 + 3.0*it*t*t*c2 + t*t*t*p2
				pts.append(pt)

			c.draw_polyline(pts, col_line, lw, true)
			if pts.size() >= 2:
				var dir := (p2 - pts[pts.size() - 2]).normalized()
				var norm := Vector2(-dir.y, dir.x)
				var a1 := p2 - dir * arrow_sz + norm * (arrow_sz * 0.5)
				var a2 := p2 - dir * arrow_sz - norm * (arrow_sz * 0.5)
				c.draw_colored_polygon(PackedVector2Array([p2, a1, a2]), col_line)

func _draw_threading_drag_preview(c: Node2D) -> void:
	if not is_dragging_thread or not is_instance_valid(thread_source_frame):
		return
	var vp := c.get_viewport()
	var zsc: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	var lw: float = maxf(1.8 / maxf(zsc, 0.0002), 1.2)
	var col_drag := Color(0.2, 0.8, 1.0, 0.9)
	var col_dash := Color(0.2, 0.8, 1.0, 0.5)

	var p1: Vector2 = c.to_local(ParagraphThreading.get_out_port_rect(thread_source_frame, zsc).get_center())
	var p2: Vector2 = c.to_local(thread_target_pos)

	var ctrl_dx := absf(p2.x - p1.x) * 0.5 + 20.0 / maxf(zsc, 0.0002)
	var c1 := p1 + Vector2(ctrl_dx, 0.0)
	var c2 := p2 - Vector2(ctrl_dx, 0.0)
	var pts := PackedVector2Array()
	const STEPS := 20
	for step in range(STEPS + 1):
		var t := float(step) / float(STEPS)
		var it := 1.0 - t
		var pt := it*it*it*p1 + 3.0*it*it*t*c1 + 3.0*it*t*t*c2 + t*t*t*p2
		pts.append(pt)

	c.draw_polyline(pts, col_drag, lw, true)

	var target_shape: Node2D = _shape_at(thread_target_pos)
	if is_instance_valid(target_shape) and target_shape != thread_source_frame and target_shape.has_meta("shape_type") and str(target_shape.get_meta("shape_type")) == "text_paragraph":
		var target_rect: Rect2 = _global_rect(target_shape)
		var ltr: Rect2 = Rect2(c.to_local(target_rect.position), c.to_local(target_rect.end) - c.to_local(target_rect.position))
		c.draw_rect(ltr, Color(0.2, 0.9, 0.4, 0.25), true)
		c.draw_rect(ltr, Color(0.2, 0.9, 0.4, 0.9), false, lw * 1.5)
		c.draw_circle(p2, 6.0 / maxf(zsc, 0.0002), Color(0.2, 0.9, 0.4, 1.0))
	else:
		var w: float = float(thread_source_frame.get_meta("width", 350.0))
		var h: float = float(thread_source_frame.get_meta("height", 100.0))
		var preview_r := Rect2(p2, Vector2(w, h))
		c.draw_rect(preview_r, Color(0.2, 0.8, 1.0, 0.1), true)
		c.draw_rect(preview_r, col_dash, false, lw)
		c.draw_circle(p2, 5.0 / maxf(zsc, 0.0002), col_drag)
