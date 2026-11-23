## E2E Recursos ▸ «COMPONENTES» (Modern y Smart): la sección lista los
## componentes del documento con miniatura y nº de copias; «+» crea uno con
## la selección; doble clic coloca una copia vinculada; seleccionar todas las
## copias; editar una cambia las demás; desvincular todas.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://components_section")
	var S = load("res://script_gdscript/shapes/symbols.gd")
	for mode in ["modern", "smart"]:
		if not await K.boot(mode):
			quit(1)
			return
		api = K.api
		var ab: Node2D = await K.artboard(Vector2(800, 500), "Componentes " + mode, Color.WHITE)
		await K.look_at(ab)
		var tab: Button = root.find_child("TabRecursos", true, false)
		if tab and tab.is_visible_in_tree():
			tab.pressed.emit()
			await K.frames(6)
		var sec: Node = root.find_child("ComponentsSection", true, false)
		K.check("%s: Recursos tiene la sección COMPONENTES" % mode, sec != null and (sec as Control).is_visible_in_tree())
		if sec == null:
			continue
		var empty: Label = sec.find_child("Empty", true, false)
		K.check("%s: sin componentes → mensaje de ayuda" % mode, empty.is_visible_in_tree())
		# «+»: componente con la selección
		var a = api.add_rect(Vector2(150, 150), Vector2(100, 80), 0.0, "Botón")
		api.set_props(a, {"fill_color": Color(0.2, 0.6, 0.3)})
		var t = api.add_ellipse(Vector2(150, 150), Vector2(30, 30), "Punto")
		api.select([a, t])
		await K.frames(3)
		(sec.find_child("MakeComponent", true, false) as Button).pressed.emit()
		await K.frames(6)
		var list: ItemList = sec.find_child("Components", true, false)
		K.check("%s: «+» crea el componente y aparece en la lista" % mode, list.item_count == 1 and S.all().size() == 1, "%d %d" % [list.item_count, S.all().size()])
		var id: String = String(list.get_item_metadata(0)) if list.item_count > 0 else ""
		# doble clic = colocar una copia
		list.item_activated.emit(0)
		await K.frames(6)
		K.check("%s: doble clic coloca una copia vinculada (2 copias)" % mode, S.instances(id).size() == 2, str(S.instances(id).size()))
		sec.refresh(true)
		K.check("%s: el tooltip dice «2 copias»" % mode, list.get_item_tooltip(0).contains("2 copias"), list.get_item_tooltip(0))
		# miniatura
		var got_icon := false
		for i in 40:
			await K.frames(2)
			if list.item_count > 0 and list.get_item_icon(0) != null:
				got_icon = true
				break
		K.check("%s: el componente tiene miniatura" % mode, got_icon)
		# seleccionar todas las copias
		sec._menu_id = id
		sec._on_menu(1)
		await K.frames(3)
		K.check("%s: «Seleccionar todas las copias»" % mode, (root.get_node("InspectorCore").selection() as Array).size() == 2)
		# editar una copia cambia las demás
		var insts: Array = S.instances(id)
		var r0: Node = insts[0].find_child("Botón", true, false)
		api.select([r0])
		api.set_props(r0, {"fill_color": Color(0.9, 0.2, 0.2)})
		await K.frames(8)
		var r1: Node = S.instances(id)[1].find_child("Botón", true, false)
		K.check("%s: editar una copia cambia la otra" % mode, r1 != null and (r1.fill_color as Color).r > 0.8, str(r1.fill_color if r1 else "-"))
		# la miniatura se rehace con el color nuevo
		var red_thumb := false
		for i in 40:
			await K.frames(3)
			var ic_t: Texture2D = list.get_item_icon(0) if list.item_count > 0 else null
			if ic_t:
				var im := ic_t.get_image()
				var cpx := im.get_pixel(im.get_width() / 5, im.get_height() / 2)
				if cpx.r > 0.7 and cpx.g < 0.4:
					red_thumb = true
					break
		K.check("%s: la miniatura se actualiza al editar el componente" % mode, red_thumb)
		var head: Label = root.find_child("DocColorsRow", true, false).find_child("Head", true, false)
		var hc: Color = head.get_theme_color("font_color")
		K.check("%s: «Colores del documento» legible (no blanco)" % mode, hc.v < 0.85, str(hc))
		# renombrar (directo) y desvincular todas
		S.rename(id, "Botón principal")
		await K.frames(2)
		sec.refresh(true)
		K.check("%s: renombrar se ve en la lista" % mode, list.get_item_text(0) == "Botón principal", list.get_item_text(0))
		await K.shot("componentes_" + mode)
		sec._menu_id = id
		sec._on_menu(3)
		await K.frames(4)
		sec.refresh(true)
		K.check("%s: desvincular todas → ya no hay copias vinculadas" % mode, S.instances(id).is_empty())
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
